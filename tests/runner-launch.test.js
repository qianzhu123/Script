const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');

const { buildRunnerLaunch } = require('../runner-launch.js');

const root = path.resolve('D:\\code\\myweb\\daily');
const baseEnv = { EXISTING: 'value' };

function assertCommon(spec, absolutePath) {
  assert.equal(spec.options.windowsHide, true);
  assert.equal(spec.options.shell, false);
  assert.equal(spec.options.cwd, path.dirname(absolutePath));
  assert.equal(spec.options.env.EXISTING, 'value');
  assert.equal(spec.options.env.SCRIPT_STUDIO_ROOT, root);
  assert.equal(spec.options.env.PYTHONIOENCODING, 'utf-8');
}

test('builds a hidden PowerShell launch specification', () => {
  const absolutePath = path.join(root, 'ps1', 'example.ps1');
  const spec = buildRunnerLaunch({ absolutePath, shellName: '', root, baseEnv });

  assert.equal(spec.command, 'powershell.exe');
  assert.deepEqual(spec.args, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-InputFormat', 'None', '-Command', `. '${absolutePath.replace(/'/g, "''")}'`]);
  assert.deepEqual(spec.options.stdio, ['pipe', 'pipe', 'pipe']);
  assertCommon(spec, absolutePath);
});

test('builds a hidden Python launch specification', () => {
  const absolutePath = path.join(root, 'tools', 'example.py');
  const spec = buildRunnerLaunch({ absolutePath, shellName: '', root, baseEnv });

  assert.equal(spec.command, 'python');
  assert.deepEqual(spec.args, ['-u', absolutePath]);
  assertCommon(spec, absolutePath);
});

test('builds a hidden CMD launch specification', () => {
  const absolutePath = path.join(root, 'bat', 'example.bat');
  const spec = buildRunnerLaunch({ absolutePath, shellName: '', root, baseEnv });

  assert.equal(spec.command, 'cmd.exe');
  assert.deepEqual(spec.args, ['/d', '/s', '/c', absolutePath]);
  assertCommon(spec, absolutePath);
});

test('honors an explicit shell type when the extension is ambiguous', () => {
  const absolutePath = path.join(root, 'tools', 'script.txt');

  assert.equal(buildRunnerLaunch({ absolutePath, shellName: 'powershell', root, baseEnv }).command, 'powershell.exe');
  assert.equal(buildRunnerLaunch({ absolutePath, shellName: 'python', root, baseEnv }).command, 'python');
});
