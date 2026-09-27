const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  AutostartError,
  buildNodeActionArguments,
  createAutostartManager,
  logFileNameForScriptId,
  normalizeAutostartSettings,
  parseAutostartConfig,
  quoteWindowsCommandLineArgument,
  serializeAutostartConfig,
  taskNameForScriptId
} = require('../autostart-manager.js');

function makeTempDir(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'script-studio-autostart-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

function taskStatus(taskName, overrides = {}) {
  return {
    taskName,
    exists: true,
    enabled: true,
    state: 'Ready',
    lastRunTime: null,
    lastTaskResult: 0,
    nextRunTime: null,
    ...overrides
  };
}

test('creates deterministic task and log names without exposing script ids', () => {
  const taskName = taskNameForScriptId('script with spaces/and symbols');

  assert.match(taskName, /^ScriptStudio-[a-f0-9]{16}$/);
  assert.equal(taskName, taskNameForScriptId('script with spaces/and symbols'));
  assert.notEqual(taskName, taskNameForScriptId('another-script'));
  assert.equal(logFileNameForScriptId('script with spaces/and symbols'), `${taskName.slice('ScriptStudio-'.length)}.log`);
});

test('normalizes safe defaults and forces startup tasks to run as SYSTEM', () => {
  assert.deepEqual(normalizeAutostartSettings({}), {
    trigger: 'logon',
    delaySeconds: 30,
    runElevated: false,
    restartOnFailure: true,
    enabled: true
  });
  assert.deepEqual(normalizeAutostartSettings({
    trigger: 'startup',
    delaySeconds: 5,
    runElevated: false,
    restartOnFailure: false,
    enabled: false
  }), {
    trigger: 'startup',
    delaySeconds: 5,
    runElevated: true,
    restartOnFailure: false,
    enabled: false
  });
  assert.throws(
    () => normalizeAutostartSettings({ delaySeconds: 3601 }),
    (error) => error instanceof AutostartError && error.code === 'INVALID_SETTINGS'
  );
});

test('quotes Windows task action arguments using CommandLineToArgvW rules', () => {
  assert.equal(quoteWindowsCommandLineArgument('plain'), '"plain"');
  assert.equal(quoteWindowsCommandLineArgument('C:\\Program Files\\node\\'), '"C:\\Program Files\\node\\\\"');
  assert.equal(quoteWindowsCommandLineArgument('say "hello"'), '"say \\"hello\\""');
  assert.equal(
    buildNodeActionArguments('D:\\code\\startup runner.js', 'script id'),
    '"D:\\code\\startup runner.js" "script id"'
  );
});

test('serializes records deterministically and validates duplicate ids', () => {
  const value = serializeAutostartConfig([
    { scriptId: 'z', settings: { enabled: false } },
    { scriptId: 'a', settings: { trigger: 'startup' } }
  ]);

  assert.deepEqual(value.scripts.map((record) => record.scriptId), ['a', 'z']);
  assert.deepEqual(parseAutostartConfig(value), [
    { scriptId: 'a', settings: normalizeAutostartSettings({ trigger: 'startup' }) },
    { scriptId: 'z', settings: normalizeAutostartSettings({ enabled: false }) }
  ]);
  assert.throws(
    () => parseAutostartConfig({ version: 1, scripts: [{ scriptId: 'a' }, { scriptId: 'a' }] }),
    /Duplicate autostart record/
  );
});

test('manager persists settings only after helper success and reports actual task state', async (t) => {
  const root = makeTempDir(t);
  const calls = [];
  const tasks = new Map();
  const helper = async (request, options) => {
    calls.push({ request, options });
    if (request.operation === 'upsert') {
      const task = taskStatus(request.taskName, { enabled: request.settings.enabled });
      tasks.set(request.taskName, task);
      return { ok: true, task };
    }
    if (request.operation === 'list') {
      return { ok: true, tasks: request.taskNames.map((name) => tasks.get(name)).filter(Boolean) };
    }
    if (request.operation === 'disable') {
      const task = taskStatus(request.taskName, { enabled: false, state: 'Disabled' });
      tasks.set(request.taskName, task);
      return { ok: true, task };
    }
    if (request.operation === 'remove') {
      tasks.delete(request.taskName);
      return { ok: true, removed: true, task: { taskName: request.taskName, exists: false } };
    }
    throw new Error(`Unexpected operation: ${request.operation}`);
  };
  const manager = createAutostartManager({
    root,
    nodePath: path.join(root, 'node.exe'),
    runnerPath: path.join(root, 'startup-runner.js'),
    settingsPath: path.join(root, 'config', 'autostart.json'),
    currentUser: 'TEST\\User',
    findScript: async (id) => id === 'service-a' ? { id } : null,
    helper
  });

  assert.deepEqual(await manager.list(), []);
  assert.equal(calls.length, 0);

  const created = await manager.upsert('service-a', { delaySeconds: 45 });
  assert.equal(created.configured, true);
  assert.equal(created.exists, true);
  assert.equal(created.delaySeconds, 45);
  assert.equal(created.logPath, path.join(root, 'logs', 'autostart', logFileNameForScriptId('service-a')));
  assert.equal(calls[0].options.elevated, false);
  assert.equal(calls[0].request.userId, 'TEST\\User');

  const persisted = JSON.parse(fs.readFileSync(path.join(root, 'config', 'autostart.json'), 'utf8'));
  assert.equal(persisted.scripts[0].scriptId, 'service-a');
  assert.equal(persisted.scripts[0].delaySeconds, 45);

  const listed = await manager.list();
  assert.equal(listed[0].state, 'Ready');
  assert.equal(listed[0].enabled, true);

  const disabled = await manager.disable('service-a');
  assert.equal(disabled.enabled, false);
  assert.equal(disabled.configuredEnabled, false);

  const removed = await manager.remove('service-a');
  assert.equal(removed.removed, true);
  assert.equal(removed.configured, false);
  assert.equal(await manager.isConfigured('service-a'), false);
});

test('manager elevates startup registration and does not persist failed changes', async (t) => {
  const root = makeTempDir(t);
  let invoked;
  const manager = createAutostartManager({
    root,
    nodePath: path.join(root, 'node.exe'),
    runnerPath: path.join(root, 'startup-runner.js'),
    currentUser: 'TEST\\User',
    findScript: async () => ({ id: 'service-a' }),
    helper: async (request, options) => {
      invoked = { request, options };
      throw new AutostartError('UAC_CANCELLED', 'Canceled.');
    }
  });

  await assert.rejects(
    manager.upsert('service-a', { trigger: 'startup' }),
    (error) => error.code === 'UAC_CANCELLED'
  );
  assert.equal(invoked.options.elevated, true);
  assert.equal(invoked.request.settings.runElevated, true);
  assert.equal(invoked.request.userId, null);
  assert.equal(fs.existsSync(path.join(root, 'config', 'autostart.json')), false);
});
