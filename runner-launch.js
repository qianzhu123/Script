const path = require('node:path');

function buildRunnerLaunch({ absolutePath, shellName, root, baseEnv }) {
  const ext = path.extname(absolutePath).toLowerCase();
  const normalizedShell = String(shellName || '').toLowerCase();
  const env = {
    ...baseEnv,
    SCRIPT_STUDIO_ROOT: root,
    PYTHONIOENCODING: 'utf-8',
    PYTHONUTF8: '1',
    PYTHONUNBUFFERED: '1'
  };
  const options = {
    cwd: path.dirname(absolutePath),
    windowsHide: true,
    shell: false,
    env
  };

  if (ext === '.ps1' || normalizedShell === 'powershell') {
    return {
      command: 'powershell.exe',
      args: ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', absolutePath],
      options
    };
  }

  if (ext === '.py' || normalizedShell === 'python') {
    return {
      command: 'python',
      args: ['-u', absolutePath],
      options
    };
  }

  return {
    command: 'cmd.exe',
    args: ['/d', '/s', '/c', absolutePath],
    options
  };
}

module.exports = { buildRunnerLaunch };
