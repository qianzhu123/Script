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
    // 使用 -Command 而非 -File，因为 -File 模式下 Read-Host 的提示文字
    // 不会输出到 stdout（被写到 Windows 控制台 API），Node.js spawn 捕获不到。
    // -Command 模式下所有 Write-Host / Read-Host 提示都会走 stdout。
    // 用 iex 逐行读取文件内容，避免 -Command 内联脚本时转义问题。
    // 加 -InputFormat None 让 PowerShell 不尝试解析 stdin 作为 PS 代码。
    return {
      command: 'powershell.exe',
      args: ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-InputFormat', 'None', '-Command', `. '${absolutePath.replace(/'/g, "''")}'`],
      options: { ...options, stdio: ['pipe', 'pipe', 'pipe'] }
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
