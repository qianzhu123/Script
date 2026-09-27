const childProcess = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const AUTOSTART_CONFIG_VERSION = 1;
const TASK_NAME_PREFIX = 'ScriptStudio-';
const TASK_HASH_LENGTH = 16;
const DEFAULT_AUTOSTART_SETTINGS = Object.freeze({
  trigger: 'logon',
  delaySeconds: 30,
  runElevated: false,
  restartOnFailure: true,
  enabled: true
});

class AutostartError extends Error {
  constructor(code, message, details) {
    super(message);
    this.name = 'AutostartError';
    this.code = code;
    if (details !== undefined) this.details = details;
  }
}

function normalizeScriptId(value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new AutostartError('INVALID_SCRIPT_ID', 'scriptId must be a non-empty string.');
  }
  if (value.includes('\0')) {
    throw new AutostartError('INVALID_SCRIPT_ID', 'scriptId cannot contain a null character.');
  }
  return value;
}

function scriptIdHash(scriptId) {
  const id = normalizeScriptId(scriptId);
  return crypto.createHash('sha256').update(id, 'utf8').digest('hex').slice(0, TASK_HASH_LENGTH);
}

function taskNameForScriptId(scriptId) {
  return `${TASK_NAME_PREFIX}${scriptIdHash(scriptId)}`;
}

function logFileNameForScriptId(scriptId) {
  return `${scriptIdHash(scriptId)}.log`;
}

function normalizeBoolean(value, fieldName) {
  if (typeof value !== 'boolean') {
    throw new AutostartError('INVALID_SETTINGS', `${fieldName} must be a boolean.`);
  }
  return value;
}

function normalizeAutostartSettings(input = {}, base = DEFAULT_AUTOSTART_SETTINGS) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new AutostartError('INVALID_SETTINGS', 'Autostart settings must be an object.');
  }

  const values = { ...DEFAULT_AUTOSTART_SETTINGS, ...base, ...input };
  if (values.trigger !== 'logon' && values.trigger !== 'startup') {
    throw new AutostartError('INVALID_SETTINGS', 'trigger must be "logon" or "startup".');
  }
  if (!Number.isInteger(values.delaySeconds) || values.delaySeconds < 0 || values.delaySeconds > 3600) {
    throw new AutostartError('INVALID_SETTINGS', 'delaySeconds must be an integer from 0 through 3600.');
  }

  const runElevated = normalizeBoolean(values.runElevated, 'runElevated');
  return {
    trigger: values.trigger,
    delaySeconds: values.delaySeconds,
    runElevated: values.trigger === 'startup' ? true : runElevated,
    restartOnFailure: normalizeBoolean(values.restartOnFailure, 'restartOnFailure'),
    enabled: normalizeBoolean(values.enabled, 'enabled')
  };
}

function parseAutostartConfig(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new AutostartError('INVALID_SETTINGS_FILE', 'autostart.json must contain a JSON object.');
  }
  if (value.version !== AUTOSTART_CONFIG_VERSION || !Array.isArray(value.scripts)) {
    throw new AutostartError('INVALID_SETTINGS_FILE', 'autostart.json has an unsupported schema.');
  }

  const seen = new Set();
  return value.scripts.map((record) => {
    if (!record || typeof record !== 'object' || Array.isArray(record)) {
      throw new AutostartError('INVALID_SETTINGS_FILE', 'Each autostart record must be an object.');
    }
    const scriptId = normalizeScriptId(record.scriptId);
    if (seen.has(scriptId)) {
      throw new AutostartError('INVALID_SETTINGS_FILE', `Duplicate autostart record for scriptId: ${scriptId}`);
    }
    seen.add(scriptId);
    return {
      scriptId,
      settings: normalizeAutostartSettings(record)
    };
  });
}

function compareScriptIds(left, right) {
  if (left.scriptId < right.scriptId) return -1;
  if (left.scriptId > right.scriptId) return 1;
  return 0;
}

function serializeAutostartConfig(records) {
  const scripts = records
    .map(({ scriptId, settings }) => ({
      scriptId: normalizeScriptId(scriptId),
      ...normalizeAutostartSettings(settings)
    }))
    .sort(compareScriptIds);
  return { version: AUTOSTART_CONFIG_VERSION, scripts };
}

function quoteWindowsCommandLineArgument(value) {
  const text = String(value);
  if (text.includes('\0')) {
    throw new AutostartError('INVALID_ARGUMENT', 'Windows command-line arguments cannot contain null characters.');
  }

  let result = '"';
  let backslashes = 0;
  for (const character of text) {
    if (character === '\\') {
      backslashes += 1;
      continue;
    }
    if (character === '"') {
      result += '\\'.repeat(backslashes * 2 + 1) + '"';
      backslashes = 0;
      continue;
    }
    result += '\\'.repeat(backslashes) + character;
    backslashes = 0;
  }
  return result + '\\'.repeat(backslashes * 2) + '"';
}

function buildNodeActionArguments(runnerPath, scriptId) {
  return [runnerPath, normalizeScriptId(scriptId)]
    .map(quoteWindowsCommandLineArgument)
    .join(' ');
}

function requiresAdministrativeAccess(settings) {
  const normalized = normalizeAutostartSettings(settings);
  return normalized.trigger === 'startup' || normalized.runElevated;
}

function emptyTaskStatus(taskName) {
  return {
    taskName,
    exists: false,
    enabled: false,
    state: null,
    lastRunTime: null,
    lastTaskResult: null,
    nextRunTime: null,
    requiresElevation: false,
    principalUserId: null,
    principalLogonType: null,
    principalRunLevel: null
  };
}

function normalizeTaskStatus(task, taskName) {
  if (!task || !task.exists) return emptyTaskStatus(taskName);
  return {
    taskName,
    exists: true,
    enabled: Boolean(task.enabled),
    state: task.state == null ? null : String(task.state),
    lastRunTime: task.lastRunTime || null,
    lastTaskResult: task.lastTaskResult == null ? null : Number(task.lastTaskResult),
    nextRunTime: task.nextRunTime || null,
    requiresElevation: Boolean(task.requiresElevation),
    principalUserId: task.principalUserId || null,
    principalLogonType: task.principalLogonType || null,
    principalRunLevel: task.principalRunLevel || null
  };
}

function mergeAutostartEntry(scriptId, settings, task) {
  const id = normalizeScriptId(scriptId);
  const taskName = taskNameForScriptId(id);
  const persisted = settings ? normalizeAutostartSettings(settings) : null;
  const actual = normalizeTaskStatus(task, taskName);
  return {
    scriptId: id,
    taskName,
    configured: Boolean(persisted),
    settings: persisted,
    trigger: persisted ? persisted.trigger : null,
    delaySeconds: persisted ? persisted.delaySeconds : null,
    runElevated: persisted ? persisted.runElevated : null,
    restartOnFailure: persisted ? persisted.restartOnFailure : null,
    configuredEnabled: persisted ? persisted.enabled : null,
    ...actual
  };
}

async function writeJsonAtomic(filePath, value, options = {}) {
  const fsApi = options.fs || fs.promises;
  const directory = path.dirname(filePath);
  const suffix = crypto.randomBytes(8).toString('hex');
  const temporaryPath = path.join(directory, `.${path.basename(filePath)}.${process.pid}.${suffix}.tmp`);
  const content = `${JSON.stringify(value, null, 2)}\n`;
  let handle = null;

  await fsApi.mkdir(directory, { recursive: true });
  try {
    handle = await fsApi.open(temporaryPath, 'wx', 0o600);
    await handle.writeFile(content, 'utf8');
    await handle.sync();
    await handle.close();
    handle = null;
    await fsApi.rename(temporaryPath, filePath);
  } catch (error) {
    if (handle) {
      try { await handle.close(); } catch {}
    }
    try { await fsApi.unlink(temporaryPath); } catch {}
    throw error;
  }
}

function encodePowerShellCommand(command) {
  return Buffer.from(String(command), 'utf16le').toString('base64');
}

function quotePowerShellLiteral(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function buildElevatedLauncherCommand({ helperPath, requestPath, resultPath }) {
  const innerCommand = [
    "$ErrorActionPreference = 'Stop'",
    `& ${quotePowerShellLiteral(helperPath)} -RequestPath ${quotePowerShellLiteral(requestPath)} -ResultPath ${quotePowerShellLiteral(resultPath)}`
  ].join('; ');
  const innerEncoded = encodePowerShellCommand(innerCommand);

  return [
    "$ErrorActionPreference = 'Stop'",
    `$resultPath = ${quotePowerShellLiteral(resultPath)}`,
    'function Write-LauncherFailure {',
    '  param([string]$Code, [string]$Message)',
    '  $payload = @{ ok = $false; error = @{ code = $Code; message = $Message } } | ConvertTo-Json -Compress',
    '  $utf8 = New-Object System.Text.UTF8Encoding($false)',
    '  [System.IO.File]::WriteAllText($resultPath, $payload, $utf8)',
    '}',
    'try {',
    `  $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', '${innerEncoded}') -Wait -PassThru`,
    '  if (($process.ExitCode -ne 0) -and -not (Test-Path -LiteralPath $resultPath)) {',
    "    Write-LauncherFailure 'ELEVATED_PROCESS_FAILED' 'The elevated task operation did not complete.'",
    '  }',
    '} catch {',
    '  $nativeCode = 0',
    '  if ($_.Exception -is [System.ComponentModel.Win32Exception]) { $nativeCode = $_.Exception.NativeErrorCode }',
    '  $lowWord = ([int64]$_.Exception.HResult) -band 0xffff',
    '  if (($nativeCode -eq 1223) -or ($lowWord -eq 1223)) {',
    "    Write-LauncherFailure 'UAC_CANCELLED' 'Administrator approval was canceled.'",
    '  } else {',
    "    Write-LauncherFailure 'ELEVATION_FAILED' 'Unable to start the administrator task operation.'",
    '  }',
    '}'
  ].join('\r\n');
}

function runExecFile(execFileImpl, executable, args, options) {
  return new Promise((resolve) => {
    try {
      execFileImpl(executable, args, options, (error, stdout, stderr) => {
        resolve({ error, stdout, stderr });
      });
    } catch (error) {
      resolve({ error, stdout: '', stderr: '' });
    }
  });
}

function errorFromHelperResult(result) {
  const detail = result && result.error ? result.error : {};
  return new AutostartError(
    detail.code || 'TASK_OPERATION_FAILED',
    detail.message || 'The scheduled task operation failed.',
    detail.details
  );
}

function createPowerShellTaskHelper(options = {}) {
  const fsApi = options.fs || fs.promises;
  const execFileImpl = options.execFile || childProcess.execFile;
  const platform = options.platform || process.platform;
  const powershellPath = options.powershellPath || 'powershell.exe';
  const helperPath = path.resolve(options.helperPath || path.join(__dirname, 'scripts', 'windows-task-manager.ps1'));
  const temporaryRoot = options.temporaryRoot || os.tmpdir();
  const timeout = options.timeout || 300000;

  return {
    async invoke(request, invokeOptions = {}) {
      if (platform !== 'win32') {
        throw new AutostartError('UNSUPPORTED_PLATFORM', 'Windows Task Scheduler is only available on Windows.');
      }

      const temporaryDirectory = await fsApi.mkdtemp(path.join(temporaryRoot, 'script-studio-task-'));
      const requestPath = path.join(temporaryDirectory, 'request.json');
      const resultPath = path.join(temporaryDirectory, 'result.json');
      let launchResult;

      try {
        await fsApi.writeFile(requestPath, `${JSON.stringify(request)}\n`, { encoding: 'utf8', mode: 0o600 });
        if (invokeOptions.elevated) {
          const launcher = buildElevatedLauncherCommand({ helperPath, requestPath, resultPath });
          launchResult = await runExecFile(execFileImpl, powershellPath, [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-EncodedCommand',
            encodePowerShellCommand(launcher)
          ], { windowsHide: true, timeout, maxBuffer: 1024 * 1024 });
        } else {
          launchResult = await runExecFile(execFileImpl, powershellPath, [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            helperPath,
            '-RequestPath',
            requestPath,
            '-ResultPath',
            resultPath
          ], { windowsHide: true, timeout, maxBuffer: 1024 * 1024 });
        }

        let text;
        try {
          text = await fsApi.readFile(resultPath, 'utf8');
        } catch (readError) {
          const timedOut = launchResult.error && launchResult.error.code === 'ETIMEDOUT';
          throw new AutostartError(
            timedOut ? 'HELPER_TIMEOUT' : 'HELPER_FAILED',
            timedOut
              ? 'The scheduled task operation timed out.'
              : 'The scheduled task helper did not return a result.',
            { cause: launchResult.error ? launchResult.error.message : readError.message }
          );
        }

        let result;
        try {
          result = JSON.parse(text);
        } catch (error) {
          throw new AutostartError('INVALID_HELPER_RESULT', 'The scheduled task helper returned invalid JSON.', {
            cause: error.message
          });
        }
        if (!result || result.ok !== true) throw errorFromHelperResult(result);
        return result;
      } finally {
        try { await fsApi.rm(temporaryDirectory, { recursive: true, force: true }); } catch {}
      }
    }
  };
}

function getCurrentWindowsUser(environment = process.env) {
  const username = environment.USERNAME || environment.USER || '';
  const domain = environment.USERDOMAIN || '';
  if (!username) return '';
  return domain ? `${domain}\\${username}` : username;
}

async function callHelper(helper, request, options) {
  let result;
  if (typeof helper === 'function') result = await helper(request, options);
  else if (helper && typeof helper.invoke === 'function') result = await helper.invoke(request, options);
  else throw new AutostartError('INVALID_HELPER', 'The task helper must be a function or expose invoke().');
  if (result && result.ok === false) throw errorFromHelperResult(result);
  return result || {};
}

function findRecord(records, scriptId) {
  return records.find((record) => record.scriptId === scriptId) || null;
}

function replaceRecord(records, scriptId, settings) {
  return [
    ...records.filter((record) => record.scriptId !== scriptId),
    { scriptId, settings }
  ];
}

function buildUpsertRequest({ scriptId, settings, root, nodePath, runnerPath, currentUser }) {
  const normalized = normalizeAutostartSettings(settings);
  if (!path.isAbsolute(nodePath) || !path.isAbsolute(runnerPath) || !path.isAbsolute(root)) {
    throw new AutostartError('INVALID_PATH', 'Node, runner, and working directory paths must be absolute.');
  }
  if (normalized.trigger === 'logon' && !currentUser) {
    throw new AutostartError('CURRENT_USER_UNAVAILABLE', 'The current Windows user could not be determined.');
  }
  return {
    operation: 'upsert',
    taskName: taskNameForScriptId(scriptId),
    nodePath,
    actionArguments: buildNodeActionArguments(runnerPath, scriptId),
    workingDirectory: root,
    userId: normalized.trigger === 'logon' ? currentUser : null,
    settings: normalized
  };
}

function createAutostartManager(options = {}) {
  const root = path.resolve(options.root || __dirname);
  const fsApi = options.fs || fs.promises;
  const settingsPath = path.resolve(options.settingsPath || path.join(root, 'config', 'autostart.json'));
  const scriptsPath = path.resolve(options.scriptsPath || path.join(root, 'config', 'scripts.json'));
  const runnerPath = path.resolve(options.runnerPath || path.join(root, 'startup-runner.js'));
  const logsDirectory = path.resolve(options.logsDirectory || path.join(root, 'logs', 'autostart'));
  const nodePath = path.resolve(options.nodePath || process.execPath);
  const currentUser = options.currentUser === undefined
    ? getCurrentWindowsUser(options.env || process.env)
    : options.currentUser;
  const helper = options.helper || createPowerShellTaskHelper({
    helperPath: options.helperPath || path.join(root, 'scripts', 'windows-task-manager.ps1'),
    fs: fsApi,
    execFile: options.execFile,
    platform: options.platform,
    powershellPath: options.powershellPath,
    temporaryRoot: options.temporaryRoot,
    timeout: options.timeout
  });
  let mutationTail = Promise.resolve();

  async function loadRecords() {
    let text;
    try {
      text = await fsApi.readFile(settingsPath, 'utf8');
    } catch (error) {
      if (error && error.code === 'ENOENT') return [];
      throw error;
    }
    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch (error) {
      throw new AutostartError('INVALID_SETTINGS_FILE', 'autostart.json contains invalid JSON.', {
        cause: error.message
      });
    }
    return parseAutostartConfig(parsed);
  }

  async function saveRecords(records) {
    await writeJsonAtomic(settingsPath, serializeAutostartConfig(records), { fs: fsApi });
  }

  async function ensureScriptExists(scriptId) {
    if (typeof options.findScript === 'function') {
      const script = await options.findScript(scriptId);
      if (!script) throw new AutostartError('SCRIPT_NOT_FOUND', `Script not found: ${scriptId}`);
      return script;
    }

    let config;
    try {
      config = JSON.parse(await fsApi.readFile(scriptsPath, 'utf8'));
    } catch (error) {
      throw new AutostartError('SCRIPTS_CONFIG_ERROR', 'Unable to read config/scripts.json.', {
        cause: error.message
      });
    }
    if (!config || !Array.isArray(config.scripts)) {
      throw new AutostartError('SCRIPTS_CONFIG_ERROR', 'config/scripts.json has an invalid schema.');
    }
    const script = config.scripts.find((candidate) => candidate && candidate.id === scriptId);
    if (!script) throw new AutostartError('SCRIPT_NOT_FOUND', `Script not found: ${scriptId}`);
    return script;
  }

  async function invoke(request, elevated, allowElevationRetry = true) {
    try {
      return await callHelper(helper, request, { elevated: Boolean(elevated) });
    } catch (error) {
      if (!elevated && allowElevationRetry && error && error.code === 'ADMIN_REQUIRED') {
        return callHelper(helper, request, { elevated: true });
      }
      throw error;
    }
  }

  function enqueueMutation(operation) {
    const pending = mutationTail.then(operation, operation);
    mutationTail = pending.catch(() => undefined);
    return pending;
  }

  function taskFromResult(result, taskName) {
    return result && result.task ? result.task : emptyTaskStatus(taskName);
  }

  function withLogPath(entry) {
    return {
      ...entry,
      logPath: path.join(logsDirectory, logFileNameForScriptId(entry.scriptId))
    };
  }

  async function isConfigured(scriptId) {
    const id = normalizeScriptId(scriptId);
    return Boolean(findRecord(await loadRecords(), id));
  }

  async function list() {
    const records = await loadRecords();
    if (records.length === 0) return [];
    const taskNames = records.map((record) => taskNameForScriptId(record.scriptId));
    const result = await invoke({ operation: 'list', taskNames }, false, false);
    const tasksByName = new Map(
      (Array.isArray(result.tasks) ? result.tasks : []).map((task) => [task.taskName, task])
    );
    return records
      .slice()
      .sort(compareScriptIds)
      .map((record) => {
        const taskName = taskNameForScriptId(record.scriptId);
        return withLogPath(mergeAutostartEntry(record.scriptId, record.settings, tasksByName.get(taskName)));
      });
  }

  async function get(scriptId) {
    const id = normalizeScriptId(scriptId);
    const records = await loadRecords();
    const record = findRecord(records, id);
    const taskName = taskNameForScriptId(id);
    const result = await invoke({ operation: 'get', taskName }, false, false);
    return withLogPath(mergeAutostartEntry(id, record && record.settings, taskFromResult(result, taskName)));
  }

  function upsert(scriptId, inputSettings = {}) {
    const id = normalizeScriptId(scriptId);
    return enqueueMutation(async () => {
      await ensureScriptExists(id);
      const records = await loadRecords();
      const existing = findRecord(records, id);
      const settings = normalizeAutostartSettings(inputSettings, existing && existing.settings);
      const request = buildUpsertRequest({
        scriptId: id,
        settings,
        root,
        nodePath,
        runnerPath,
        currentUser
      });
      const result = await invoke(request, requiresAdministrativeAccess(settings));
      await saveRecords(replaceRecord(records, id, settings));
      return withLogPath(mergeAutostartEntry(id, settings, taskFromResult(result, request.taskName)));
    });
  }

  function remove(scriptId) {
    const id = normalizeScriptId(scriptId);
    return enqueueMutation(async () => {
      const records = await loadRecords();
      const existing = findRecord(records, id);
      const taskName = taskNameForScriptId(id);
      const elevated = existing ? requiresAdministrativeAccess(existing.settings) : false;
      const result = await invoke({ operation: 'remove', taskName }, elevated);
      if (existing) await saveRecords(records.filter((record) => record.scriptId !== id));
      return {
        ...withLogPath(mergeAutostartEntry(id, null, taskFromResult(result, taskName))),
        removed: result.removed !== false
      };
    });
  }

  function setEnabled(scriptId, enabled) {
    const id = normalizeScriptId(scriptId);
    return enqueueMutation(async () => {
      const records = await loadRecords();
      const existing = findRecord(records, id);
      const taskName = taskNameForScriptId(id);
      const elevated = existing ? requiresAdministrativeAccess(existing.settings) : false;
      const operation = enabled ? 'enable' : 'disable';
      const result = await invoke({ operation, taskName }, elevated);
      let settings = existing && existing.settings;
      if (existing && existing.settings.enabled !== enabled) {
        settings = normalizeAutostartSettings({ enabled }, existing.settings);
        await saveRecords(replaceRecord(records, id, settings));
      }
      return withLogPath(mergeAutostartEntry(id, settings, taskFromResult(result, taskName)));
    });
  }

  async function runControlOperation(operation, scriptId) {
    const id = normalizeScriptId(scriptId);
    const records = await loadRecords();
    const existing = findRecord(records, id);
    const taskName = taskNameForScriptId(id);
    const elevated = existing ? requiresAdministrativeAccess(existing.settings) : false;
    const result = await invoke({ operation, taskName }, elevated);
    return withLogPath(mergeAutostartEntry(id, existing && existing.settings, taskFromResult(result, taskName)));
  }

  return {
    list,
    get,
    isConfigured,
    upsert,
    remove,
    enable: (scriptId) => setEnabled(scriptId, true),
    disable: (scriptId) => setEnabled(scriptId, false),
    run: (scriptId) => runControlOperation('run', scriptId),
    stop: (scriptId) => runControlOperation('stop', scriptId),
    taskNameForScriptId,
    paths: Object.freeze({ root, settingsPath, scriptsPath, runnerPath, logsDirectory, nodePath })
  };
}

module.exports = {
  AUTOSTART_CONFIG_VERSION,
  TASK_NAME_PREFIX,
  TASK_HASH_LENGTH,
  DEFAULT_AUTOSTART_SETTINGS,
  AutostartError,
  normalizeScriptId,
  scriptIdHash,
  taskNameForScriptId,
  logFileNameForScriptId,
  normalizeAutostartSettings,
  parseAutostartConfig,
  serializeAutostartConfig,
  quoteWindowsCommandLineArgument,
  buildNodeActionArguments,
  requiresAdministrativeAccess,
  normalizeTaskStatus,
  mergeAutostartEntry,
  writeJsonAtomic,
  encodePowerShellCommand,
  buildElevatedLauncherCommand,
  createPowerShellTaskHelper,
  getCurrentWindowsUser,
  buildUpsertRequest,
  createAutostartManager
};
