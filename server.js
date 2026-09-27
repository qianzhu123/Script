const express = require('express');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn, execFile, exec } = require('child_process');
const WebSocket = require('ws');
const { writeJsonWithBackup, pruneExpiredBackups } = require('./config-backup.js');
const { buildRunnerLaunch } = require('./runner-launch.js');
const { createAutostartManager, DEFAULT_AUTOSTART_SETTINGS } = require('./autostart-manager.js');
let iconv = null;
try { iconv = require('iconv-lite'); } catch {}
// PTY 支持（oh-my-posh 等需要真 TTY）。加载失败时回退旧的管道模式。
let pty = null;
try { pty = require('node-pty'); } catch (error) {
  console.warn(`[pty] node-pty unavailable (${error.message}); falling back to pipe mode.`);
}

const ROOT = __dirname;
const PORT = Number(process.env.PORT || 3100);
const CONFIG_DIR = path.join(ROOT, 'config');
const SCRIPT_CONFIG = path.join(CONFIG_DIR, 'scripts.json');
const EXAMPLE_CONFIG = path.join(CONFIG_DIR, 'scripts.example.json');
const SETTINGS_CONFIG = path.join(CONFIG_DIR, 'settings.json');
const THEMES_DIR = path.join(ROOT, 'themes');
const BACKUP_DIR = path.join(ROOT, 'backup');

function ensureDir(dir) { fs.mkdirSync(dir, { recursive: true }); }
function readJson(file, fallback) { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; } }
function writeJson(file, data) { ensureDir(path.dirname(file)); fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n', 'utf8'); }

function defaultConfig() {
  return {
    groups: [{ id: 'examples', name: 'Examples', order: 1 }],
    scripts: [
      { id: 'demo-ps1', name: 'Demo PowerShell Script', groupId: 'examples', path: 'ps1/demo.ps1', description: 'Prints a short message from a PowerShell script.', priority: 'low', shell: 'powershell', ports: [], order: 1 }
    ]
  };
}

function hasUsableConfig(data) { return data && Array.isArray(data.groups) && Array.isArray(data.scripts) && (data.groups.length > 0 || data.scripts.length > 0); }
function normalizeId(value, prefix) {
  const raw = String(value || '').trim();
  if (!raw) return `${prefix}-${Date.now().toString(36)}`;
  // 保留原始 id（含中文），只去掉首尾空白
  return raw;
}
function makeNewId(name, prefix) {
  // 生成新 id 时才做 ASCII 化处理
  const raw = String(name || '').trim().toLowerCase();
  const safe = raw.replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '');
  return safe || `${prefix}-${Date.now().toString(36)}`;
}

function stripOuterQuotes(value) {
  let text = String(value || '')
    .trim()
    .replace(/[\u200B-\u200D\uFEFF]/g, '');

  // Windows “复制为路径”通常会得到 "D:\\...\\start.bat"。
  // 某些场景还会保存成 \"D:\\...\\start.bat\"，所以这里同时处理：
  // - 普通英文/中文引号包裹
  // - 被反斜杠转义的外层引号
  // - 多层误包裹，例如 '\"D:\\a.bat\"'、"'D:\\a.bat'"
  const wrappers = [
    ['\\"', '\\"'],
    ["\\'", "\\'"],
    ['"', '"'],
    ["'", "'"],
    ['“', '”'],
    ['‘', '’']
  ];

  let changed = true;
  while (changed && text.length >= 2) {
    changed = false;

    for (const [left, right] of wrappers) {
      if (text.startsWith(left) && text.endsWith(right)) {
        text = text.slice(left.length, text.length - right.length).trim();
        changed = true;
      }
    }

    // 兜底：如果只有一侧残留了外层引号/转义引号，也去掉。
    const before = text;
    text = text
      .replace(/^(?:\\["']|["'“‘])+/, '')
      .replace(/(?:\\["']|["'”’])+$/, '')
      .trim();
    if (text !== before) changed = true;
  }
  return text;
}

// 路径标准化：
// - 项目内绝对路径 → 转为相对路径
// - 项目外绝对路径 → 原样保留（用户配置了外部脚本，合法）
// - 相对路径 → 标准化斜杠
function normalizePath(input) {
  const text = stripOuterQuotes(input).replace(/\\/g, '/');
  if (!text) return '';

  // 绝对路径（Windows 盘符 或 UNC）
  if (/^[a-zA-Z]:/.test(text) || text.startsWith('//')) {
    const absolute = path.resolve(text.replace(/\//g, '\\'));
    const rel = path.relative(ROOT, absolute);
    // 项目内：转相对路径
    if (!rel.startsWith('..') && !path.isAbsolute(rel)) {
      return rel.replace(/\\/g, '/');
    }
    // 项目外：保留原始绝对路径（反斜杠统一）
    return absolute;
  }

  // 相对路径
  const normalized = path.posix.normalize(text).replace(/^\.\//, '');
  if (normalized === '.' || normalized.startsWith('../')) {
    throw new Error('Script paths must be relative paths inside this project.');
  }
  return normalized;
}

// 解析为绝对路径：相对路径拼项目目录，绝对路径直接返回
function resolveScriptPath(p) {
  const clean = stripOuterQuotes(p);
  if (path.isAbsolute(clean)) return clean;
  return path.resolve(ROOT, clean);
}

function normalizePorts(value) {
  if (Array.isArray(value)) return value.map(Number).filter((n) => Number.isInteger(n) && n > 0 && n < 65536);
  return String(value || '').split(/[\s,;]+/).map(Number).filter((n) => Number.isInteger(n) && n > 0 && n < 65536);
}

function normalizeConfig(data) {
  const groups = Array.isArray(data.groups) ? data.groups : [];
  const scripts = Array.isArray(data.scripts) ? data.scripts : [];
  return {
    groups: groups.map((g, i) => ({
      id: normalizeId(g.id || g.name, 'group'),
      name: String(g.name || 'New Group').trim() || 'New Group',
      order: Number.isFinite(Number(g.order)) ? Number(g.order) : i + 1
    })),
    scripts: scripts.map((s, i) => {
      let p = '';
      try { p = normalizePath(s.path || ''); } catch { p = s.path || ''; }
      return {
        id: normalizeId(s.id || s.name, 'script'),
        name: String(s.name || 'Untitled Script').trim() || 'Untitled Script',
        groupId: s.groupId || '',
        path: p,
        description: String(s.description || ''),
        priority: ['low', 'normal', 'high'].includes(s.priority) ? s.priority : 'normal',
        shell: s.shell || '',
        ports: normalizePorts(s.ports || s.port),
        order: Number.isFinite(Number(s.order)) ? Number(s.order) : i + 1
      };
    })
  };
}

function ensureConfig() {
  ensureDir(CONFIG_DIR);
  if (!fs.existsSync(EXAMPLE_CONFIG)) writeJson(EXAMPLE_CONFIG, defaultConfig());
  const current = readJson(SCRIPT_CONFIG, null);
  if (!hasUsableConfig(current)) {
    writeJsonWithBackup({
      sourcePath: SCRIPT_CONFIG,
      backupDir: BACKUP_DIR,
      data: normalizeConfig(readJson(EXAMPLE_CONFIG, defaultConfig()))
    });
  }
}

function loadConfig() {
  ensureConfig();
  const normalized = normalizeConfig(readJson(SCRIPT_CONFIG, defaultConfig()));
  return hasUsableConfig(normalized) ? normalized : normalizeConfig(defaultConfig());
}

function saveConfig(config) {
  writeJsonWithBackup({
    sourcePath: SCRIPT_CONFIG,
    backupDir: BACKUP_DIR,
    data: normalizeConfig(config)
  });
}

// ── 应用设置（交互式终端主题等） ─────────────────────────────
function defaultSettings() {
  return {
    // 交互式终端（"新建终端"）使用的 oh-my-posh 主题名，空串表示不用主题。
    terminalTheme: 'blue-owl'
  };
}

function normalizeSettings(raw) {
  const base = defaultSettings();
  if (!raw || typeof raw !== 'object') return base;
  const theme = typeof raw.terminalTheme === 'string' ? raw.terminalTheme.trim() : base.terminalTheme;
  return { ...base, terminalTheme: theme };
}

function loadSettings() {
  return normalizeSettings(readJson(SETTINGS_CONFIG, null));
}

function saveSettings(settings) {
  const normalized = normalizeSettings(settings);
  writeJsonWithBackup({
    sourcePath: SETTINGS_CONFIG,
    backupDir: BACKUP_DIR,
    data: normalized
  });
  return normalized;
}

/** 列出 themes/ 下的可用主题（文件名去掉 .omp.json / .omp.yaml）。 */
function listThemes() {
  let files = [];
  try {
    files = fs.readdirSync(THEMES_DIR);
  } catch {
    return [];
  }
  return files
    .filter((name) => /\.omp\.(json|yaml)$/i.test(name))
    .map((name) => ({ name: name.replace(/\.omp\.(json|yaml)$/i, ''), file: name }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

/** 把主题名解析成 themes/ 下的绝对路径；非法或缺失返回 null。 */
function resolveThemePath(themeName) {
  const name = String(themeName || '').trim();
  if (!name) return null;
  // 只允许主题名，禁止路径穿越。
  if (!/^[A-Za-z0-9._-]+$/.test(name) || name.includes('..')) return null;
  for (const ext of ['.omp.json', '.omp.yaml']) {
    const candidate = path.join(THEMES_DIR, `${name}${ext}`);
    if (path.dirname(candidate) === THEMES_DIR && fs.existsSync(candidate)) return candidate;
  }
  return null;
}

/** 找到可用的 oh-my-posh 可执行文件；找不到返回 null。 */
function resolveOhMyPosh() {
  const candidates = [
    process.env.OH_MY_POSH,
    'C:/Program Files/WindowsApps/ohmyposh.cli_29.14.0.0_x64__96v55e8n804z4/oh-my-posh.exe',
    'oh-my-posh.exe',
    'oh-my-posh'
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (candidate.includes('/') || candidate.includes('\\')) {
      if (fs.existsSync(candidate)) return candidate;
    } else {
      const found = whichSync(candidate);
      if (found) return found;
    }
  }
  return null;
}

/** 在 PATH 中查找可执行文件（避免为一次查找引入依赖）。 */
function whichSync(command) {
  const dirs = String(process.env.PATH || '').split(path.delimiter).filter(Boolean);
  const exts = String(process.env.PATHEXT || '.EXE;.CMD;.BAT').split(';').filter(Boolean);
  for (const dir of dirs) {
    for (const ext of exts) {
      const candidate = path.join(dir, command + ext.toLowerCase());
      try {
        if (fs.existsSync(candidate)) return candidate;
      } catch {}
    }
  }
  return null;
}

/** 找到可用的 PowerShell 7（pwsh）；找不到返回 null。 */
function resolvePwsh() {
  const candidates = [
    process.env.PWSH_PATH,
    'D:/tools/System/PowerShell/7/pwsh.exe',
    'C:/Program Files/PowerShell/7/pwsh.exe',
    'D:/Program Files/PowerShell/7/pwsh.exe'
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  return whichSync('pwsh');
}

function cleanupPort(port) {
  return new Promise((resolve) => {
    if (!Number.isInteger(port) || port <= 0 || port > 65535) return resolve([]);
    const ps = `Get-NetTCPConnection -LocalPort ${port} -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique`;
    execFile('powershell.exe', ['-NoProfile', '-Command', ps], { windowsHide: true }, (_e, stdout) => {
      const pids = String(stdout || '').split(/\r?\n/).map((x) => Number(x.trim())).filter((n) => Number.isInteger(n) && n > 0 && n !== process.pid);
      if (!pids.length) return resolve([]);
      let done = 0;
      const killed = [];
      pids.forEach((pid) => execFile('taskkill.exe', ['/PID', String(pid), '/F', '/T'], { windowsHide: true }, () => {
        killed.push(pid);
        done += 1;
        if (done === pids.length) resolve(killed);
      }));
    });
  });
}

// 打开文件资源管理器并选中文件
function openInExplorer(absolutePath, callback) {
  // explorer /select,"路径" — 必须整体作为一个参数传给 shell
  exec(`explorer.exe /select,"${absolutePath.replace(/"/g, '')}"`, { windowsHide: true }, () => callback(null));
}

const app = express();
const server = http.createServer(app);
function isTrustedBrowserOrigin(origin) {
  if (!origin) return true;
  try {
    const url = new URL(origin);
    const hostname = url.hostname.toLowerCase();
    const localHost = hostname === '127.0.0.1' || hostname === 'localhost' || hostname === '::1';
    const expectedPort = String(PORT);
    const originPort = url.port || (url.protocol === 'https:' ? '443' : '80');
    return localHost && originPort === expectedPort;
  } catch {
    return false;
  }
}

const wss = new WebSocket.Server({
  server,
  path: '/ws',
  verifyClient(info, callback) {
    if (isTrustedBrowserOrigin(info.origin || info.req.headers.origin)) callback(true);
    else callback(false, 403, 'Forbidden');
  }
});
const processes = new Map();
// 轮询任务由服务器持有，因此浏览器刷新或临时断开不会停止后续运行。
const pollJobs = new Map();

app.use(express.json({ limit: '2mb' }));
app.use((req, res, next) => {
  if (!isTrustedBrowserOrigin(req.headers.origin)) {
    return res.status(403).json({ error: '拒绝来自其他网站的本机操作请求。', code: 'UNTRUSTED_ORIGIN' });
  }
  next();
});
app.use(express.static(path.join(ROOT, 'public')));
// xterm.js 从 node_modules 提供（本地依赖，无 CDN）。
app.use('/vendor/xterm', express.static(path.join(ROOT, 'node_modules', '@xterm', 'xterm')));
app.use('/vendor/xterm-addon-fit', express.static(path.join(ROOT, 'node_modules', '@xterm', 'addon-fit')));

const autostartManager = createAutostartManager({ root: ROOT });

function autostartErrorMessage(error) {
  const messages = {
    UAC_CANCELLED: '已取消管理员授权。',
    ADMIN_REQUIRED: '此操作需要管理员权限。',
    TASK_NOT_FOUND: 'Windows 启动项不存在，请重新保存。',
    SCRIPT_NOT_FOUND: '脚本配置不存在。',
    UNSUPPORTED_PLATFORM: '自启动管理仅支持 Windows。',
    HELPER_TIMEOUT: 'Windows 任务操作超时。',
    CURRENT_USER_UNAVAILABLE: '无法识别当前 Windows 用户。'
  };
  return messages[error && error.code] || (error && error.message) || 'Windows 启动项操作失败。';
}

function sendAutostartError(res, error) {
  const badRequestCodes = new Set(['INVALID_SCRIPT_ID', 'INVALID_SETTINGS', 'INVALID_PATH']);
  const notFoundCodes = new Set(['SCRIPT_NOT_FOUND', 'TASK_NOT_FOUND']);
  const status = badRequestCodes.has(error && error.code) ? 400 : notFoundCodes.has(error && error.code) ? 404 : 500;
  return res.status(status).json({
    error: autostartErrorMessage(error),
    code: (error && error.code) || 'AUTOSTART_OPERATION_FAILED'
  });
}

function requireRunnableScript(scriptId) {
  const script = loadConfig().scripts.find((item) => item.id === scriptId);
  if (!script) {
    const error = new Error('Script not found.');
    error.code = 'SCRIPT_NOT_FOUND';
    throw error;
  }
  const absolute = resolveScriptPath(script.path);
  if (!fs.existsSync(absolute) || !fs.statSync(absolute).isFile()) {
    const error = new Error(`Script file not found: ${script.path}`);
    error.code = 'SCRIPT_NOT_FOUND';
    throw error;
  }
  return script;
}

app.get('/api/config', (_req, res) => {
  try {
    res.json(loadConfig());
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── 设置与主题 ──────────────────────────────────────────────
app.get('/api/settings', (_req, res) => {
  res.json(loadSettings());
});

app.put('/api/settings', (req, res) => {
  try {
    const incoming = req.body || {};
    if (typeof incoming.terminalTheme === 'string' && incoming.terminalTheme.trim()) {
      if (!resolveThemePath(incoming.terminalTheme)) {
        return res.status(400).json({ error: `主题不存在：${incoming.terminalTheme}` });
      }
    }
    res.json(saveSettings(incoming));
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/api/themes', (_req, res) => {
  res.json({
    themes: listThemes(),
    selected: loadSettings().terminalTheme,
    shell: resolvePwsh() ? 'pwsh' : null,
    ohMyPosh: Boolean(resolveOhMyPosh())
  });
});

// 轮询自动输入来源：单一输入框既可直接填写内容，也可填写本地文本文件路径。
// 路径不存在时返回 isFile=false，由前端将其视为普通输入，不把任意输入误报为文件错误。
app.post('/api/poll-input-source', (req, res) => {
  try {
    const supplied = stripOuterQuotes(req.body?.path || '');
    if (!supplied) return res.json({ isFile: false });
    const absolute = path.isAbsolute(supplied) ? supplied : path.resolve(ROOT, supplied);
    if (!fs.existsSync(absolute)) return res.json({ isFile: false });
    if (!fs.statSync(absolute).isFile()) return res.status(400).json({ error: '输入文件路径不是文件。' });
    if (fs.statSync(absolute).size > 1024 * 1024) return res.status(400).json({ error: '输入文件不能超过 1 MB。' });
    res.json({ isFile: true, path: absolute, content: fs.readFileSync(absolute, 'utf8') });
  } catch (error) { res.status(400).json({ error: error.message }); }
});

// 分组 CRUD
app.post('/api/groups', (req, res) => {
  const config = loadConfig();
  const name = String(req.body.name || '').trim();
  if (!name) return res.status(400).json({ error: 'Group name is required.' });
  const group = { id: makeNewId(req.body.id || name, 'group'), name, order: config.groups.length + 1 };
  while (config.groups.some((x) => x.id === group.id)) group.id = `${group.id}-${Date.now().toString(36)}`;
  config.groups.push(group);
  saveConfig(config);
  res.json(group);
});

app.put('/api/groups/:id', (req, res) => {
  const config = loadConfig();
  const group = config.groups.find((x) => x.id === req.params.id);
  if (!group) return res.status(404).json({ error: 'Group not found.' });
  const name = String(req.body.name || '').trim();
  if (!name) return res.status(400).json({ error: 'Group name is required.' });
  group.name = name;
  saveConfig(config);
  res.json(group);
});

app.delete('/api/groups/:id', (req, res) => {
  const config = loadConfig();
  const before = config.groups.length;
  config.groups = config.groups.filter((x) => x.id !== req.params.id);
  if (config.groups.length === before) return res.status(404).json({ error: 'Group not found.' });
  config.scripts = config.scripts.filter((s) => s.groupId !== req.params.id);
  saveConfig(config);
  res.json({ ok: true });
});

app.post('/api/groups/order', (req, res) => {
  const config = loadConfig();
  const ids = Array.isArray(req.body.ids) ? req.body.ids : [];
  config.groups.forEach((g) => { const i = ids.indexOf(g.id); if (i >= 0) g.order = i + 1; });
  saveConfig(config);
  res.json({ ok: true });
});

// 脚本 CRUD
app.post('/api/scripts', (req, res) => {
  try {
    const config = loadConfig();
    const body = req.body || {};
    const name = String(body.name || '').trim();
    const p = normalizePath(body.path || '');
    if (!name || !p) return res.status(400).json({ error: 'Name and path are required.' });
    const script = {
      id: makeNewId(body.id || name, 'script'), name, groupId: body.groupId || '', path: p,
      description: String(body.description || ''), priority: ['low', 'normal', 'high'].includes(body.priority) ? body.priority : 'normal',
      shell: body.shell || '', ports: normalizePorts(body.ports || body.port), order: config.scripts.length + 1
    };
    while (config.scripts.some((x) => x.id === script.id)) script.id = `${script.id}-${Date.now().toString(36)}`;
    config.scripts.push(script);
    saveConfig(config);
    res.json(script);
  } catch (error) { res.status(400).json({ error: error.message }); }
});

app.put('/api/scripts/:id', (req, res) => {
  try {
    const config = loadConfig();
    const script = config.scripts.find((x) => x.id === req.params.id);
    if (!script) return res.status(404).json({ error: 'Script not found.' });
    script.name = String(req.body.name || script.name).trim();
    script.groupId = req.body.groupId || '';
    script.path = normalizePath(req.body.path || script.path);
    script.description = String(req.body.description || '');
    script.priority = ['low', 'normal', 'high'].includes(req.body.priority) ? req.body.priority : 'normal';
    script.shell = req.body.shell || script.shell || '';
    script.ports = normalizePorts(req.body.ports || req.body.port);
    saveConfig(config);
    res.json(script);
  } catch (error) { res.status(400).json({ error: error.message }); }
});

app.delete('/api/scripts/:id', async (req, res) => {
  try {
    const config = loadConfig();
    const before = config.scripts.length;
    config.scripts = config.scripts.filter((x) => x.id !== req.params.id);
    if (before === config.scripts.length) return res.status(404).json({ error: 'Script not found.' });
    if (await autostartManager.isConfigured(req.params.id)) {
      await autostartManager.remove(req.params.id);
    }
    saveConfig(config);
    res.json({ ok: true });
  } catch (error) {
    return sendAutostartError(res, error);
  }
});

app.post('/api/scripts/order', (req, res) => {
  const config = loadConfig();
  const ids = Array.isArray(req.body.ids) ? req.body.ids : [];
  config.scripts.forEach((s) => { const i = ids.indexOf(s.id); if (i >= 0) s.order = i + 1; });
  saveConfig(config);
  res.json({ ok: true });
});

// 在文件资源管理器中打开（选中文件）
app.post('/api/explore/:id', (req, res) => {
  const config = loadConfig();
  const script = config.scripts.find((x) => x.id === req.params.id);
  if (!script) return res.status(404).json({ error: 'Script not found.' });
  const absolute = resolveScriptPath(script.path);
  if (!fs.existsSync(absolute)) return res.status(404).json({ error: `文件不存在: ${script.path}` });
  openInExplorer(absolute, () => res.json({ ok: true, path: absolute }));
});

// 运行脚本（WebSocket）
app.post('/api/run/:id', async (req, res) => {
  const config = loadConfig();
  const script = config.scripts.find((x) => x.id === req.params.id);
  if (!script) return res.status(404).json({ error: 'Script not found.' });
  for (const port of script.ports || []) await cleanupPort(port);
  res.json({ ok: true, ws: `/ws?script=${encodeURIComponent(script.id)}` });
});

app.post('/api/stop/:token', (req, res) => {
  const child = processes.get(req.params.token);
  if (child) {
    if (child.kill) child.kill();
    processes.delete(req.params.token);
  }
  res.json({ ok: true });
});

function pollJobSnapshot(job) {
  return {
    id: job.id, scriptId: job.scriptId, scriptName: job.scriptName,
    active: job.active, intervalMs: job.intervalMs, endAt: job.endAt,
    runCount: job.runCount, output: job.output
  };
}

function publishPollJob(job, message) {
  job.output += message;
  for (const ws of job.clients) {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'poll-update', job: pollJobSnapshot(job), data: message }));
  }
}

function stopPollJob(job, reason = '已停止轮询运行。') {
  if (!job || !job.active) return;
  job.active = false;
  clearTimeout(job.timer);
  if (job.child && !job.child.killed) job.child.kill();
  publishPollJob(job, `\n[轮询] ${reason}\n`);
}

function startPollIteration(job) {
  if (!job.active) return;
  if (Date.now() >= job.endAt) return stopPollJob(job, `总时长已到，共运行 ${job.runCount} 次。`);
  job.runCount += 1;
  job.pendingInputs = [...job.inputs];
  publishPollJob(job, `\n[轮询] 开始第 ${job.runCount} 次运行：${job.scriptName}。\n`);
  const script = loadConfig().scripts.find((item) => item.id === job.scriptId);
  if (!script) return stopPollJob(job, '脚本已不存在，轮询停止。');
  const relay = { send(raw) {
    const event = JSON.parse(raw);
    if (event.type === 'data') {
      publishPollJob(job, event.data);
      const text = String(event.data || '');
      const auto = /(?:按.*(?:回车|enter|任意键).*(?:继续|确认|退出)|press\s+(?:enter|any key))/i.test(text);
      const input = /(?:请输入|请输出|输入.*(?:：|:|\?)|选择.*(?:：|:|\?)|read-host|\binput\b)/i.test(text);
      if (job.child?.stdin?.writable && (auto || (input && job.pendingInputs.length))) {
        const value = auto ? '' : job.pendingInputs.shift();
        job.child.stdin.write(`${value}\n`);
        const status = auto ? '自动确认/继续/退出：已发送回车。' : `自动输入：${value || '（回车）'}`;
        publishPollJob(job, `\n[轮询] ${status}\n`);
      }
    } else if (event.type === 'error') {
      publishPollJob(job, `\n错误: ${event.message}`);
    } else if (event.type === 'exit') {
      publishPollJob(job, `\n脚本已退出，退出码: ${event.code}`);
      job.child = null;
      if (!job.active) return;
      const wait = Math.min(job.intervalMs, Math.max(0, job.endAt - Date.now()));
      if (!wait) return stopPollJob(job, `总时长已到，共运行 ${job.runCount} 次。`);
      publishPollJob(job, `\n[轮询] 第 ${job.runCount} 次结束，${Math.round(wait / 60000) || 1} 分钟后运行下一次。\n`);
      job.timer = setTimeout(() => startPollIteration(job), wait);
    }
  }};
  job.child = runScript(script, relay);
}

app.get('/api/polls', (_req, res) => res.json([...pollJobs.values()].filter((job) => job.active).map(pollJobSnapshot)));
app.post('/api/polls', (req, res) => {
  const body = req.body || {};
  const script = loadConfig().scripts.find((item) => item.id === body.scriptId);
  const intervalMs = Number(body.intervalMs);
  const durationMs = Number(body.durationMs);
  if (!script || intervalMs < 1000 || durationMs < intervalMs) return res.status(400).json({ error: '轮询参数无效。' });
  const job = { id: `${Date.now()}-${Math.random().toString(36).slice(2)}`, scriptId: script.id, scriptName: script.name, intervalMs, endAt: Date.now() + durationMs, runCount: 0, inputs: Array.isArray(body.inputs) ? body.inputs : [], pendingInputs: [], output: `[轮询] ${script.name}\n`, active: true, timer: null, child: null, clients: new Set() };
  pollJobs.set(job.id, job);
  startPollIteration(job);
  res.json(pollJobSnapshot(job));
});
app.post('/api/polls/:id/stop', (req, res) => {
  const job = pollJobs.get(req.params.id);
  if (!job) return res.status(404).json({ error: '轮询任务不存在。' });
  stopPollJob(job);
  res.json(pollJobSnapshot(job));
});

// Windows startup task management. No task is created until the user saves it explicitly.
app.get('/api/autostarts', async (_req, res) => {
  try {
    res.json({
      supported: process.platform === 'win32',
      defaults: DEFAULT_AUTOSTART_SETTINGS,
      entries: await autostartManager.list()
    });
  } catch (error) {
    return sendAutostartError(res, error);
  }
});

app.get('/api/autostarts/:id', async (req, res) => {
  try {
    requireRunnableScript(req.params.id);
    res.json(await autostartManager.get(req.params.id));
  } catch (error) {
    return sendAutostartError(res, error);
  }
});

app.put('/api/autostarts/:id', async (req, res) => {
  try {
    requireRunnableScript(req.params.id);
    res.json(await autostartManager.upsert(req.params.id, req.body || {}));
  } catch (error) {
    return sendAutostartError(res, error);
  }
});

app.delete('/api/autostarts/:id', async (req, res) => {
  try {
    res.json(await autostartManager.remove(req.params.id));
  } catch (error) {
    return sendAutostartError(res, error);
  }
});

for (const [action, operation] of [
  ['enable', 'enable'],
  ['disable', 'disable'],
  ['run', 'run'],
  ['stop', 'stop']
]) {
  app.post(`/api/autostarts/:id/${action}`, async (req, res) => {
    try {
      requireRunnableScript(req.params.id);
      res.json(await autostartManager[operation](req.params.id));
    } catch (error) {
      return sendAutostartError(res, error);
    }
  });
}

app.get('*', (_req, res) => res.sendFile(path.join(ROOT, 'public', 'index.html')));

// WebSocket：运行脚本并流式输出
function looksLikeUtf16le(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 2) return false;
  if ((buffer[0] === 0xFF && buffer[1] === 0xFE) || (buffer[0] === 0xFE && buffer[1] === 0xFF)) return true;
  const sample = Math.min(buffer.length - (buffer.length % 2), 32);
  let zeroHighBytes = 0;
  let pairs = 0;
  for (let i = 1; i < sample; i += 2) {
    pairs += 1;
    if (buffer[i] === 0x00) zeroHighBytes += 1;
  }
  return pairs > 0 && zeroHighBytes / pairs > 0.5;
}

function sanitizeTerminalOutput(text) {
  let s = String(text || '');
  // 常见 TTY 动画会用 ESC[999D ESC[J 回到行首并清空当前行。
  // 浏览器里不是完整终端，转换成专用控制符，由前端按“覆盖当前行”处理。
  // 普通 \r 仍然保留为普通回车，避免 BAT 的 set /p、pause 提示被误清空。
  s = s.replace(/\x1b\[[0-9;]*D\x1b\[[0-9;]*J/g, '\x0b');
  s = s.replace(/\x1b\[[0-9;]*G\x1b\[[0-9;]*J/g, '\x0b');
  // 光标显示/隐藏等私有模式控制。
  s = s.replace(/\x1b\[\?[0-9;]*[A-Za-z]/g, '');
  // SGR 颜色、粗体、清屏、移动光标等 CSI 序列。
  s = s.replace(/\x1b\[[0-9;:;?]*[ -/]*[@-~]/g, '');
  // OSC 标题等序列。
  s = s.replace(/\x1b\][^\x07]*(?:\x07|\x1b\\)/g, '');
  // 其它少见 ANSI/VT 控制序列。
  s = s.replace(/\x1b[@-_][0-?]*[ -/]*[@-~]/g, '');
  return s;
}

function decodeOutput(chunk) {
  if (!Buffer.isBuffer(chunk)) return sanitizeTerminalOutput(String(chunk || ''));
  let decoded;
  if (looksLikeUtf16le(chunk)) decoded = chunk.toString('utf16le');
  else {
    const utf8 = chunk.toString('utf8');
    if (!utf8.includes('\uFFFD')) decoded = utf8;
    else if (iconv) {
      try { decoded = iconv.decode(chunk, 'cp936'); } catch { decoded = utf8; }
    } else decoded = utf8;
  }
  return sanitizeTerminalOutput(decoded);
}

function runScript(script, ws) {
  const absolute = path.normalize(resolveScriptPath(script.path));
  if (!fs.existsSync(absolute)) {
    ws.send(JSON.stringify({ type: 'error', message: `Script not found: ${script.path}` })); return null;
  }
  const launch = buildRunnerLaunch({
    absolutePath: absolute,
    shellName: script.shell,
    root: ROOT,
    baseEnv: process.env
  });
  if (!pty) {
    const child = spawn(launch.command, launch.args, launch.options);
    child.stdout.on('data', (c) => ws.send(JSON.stringify({ type: 'data', data: decodeOutput(c) })));
    child.stderr.on('data', (c) => ws.send(JSON.stringify({ type: 'data', data: decodeOutput(c) })));
    child.on('close', (code) => ws.send(JSON.stringify({ type: 'exit', code })));
    child.on('error', (error) => ws.send(JSON.stringify({ type: 'error', message: error.message })));
    return child;
  }
  // PTY 模式：子进程获得真 TTY，oh-my-posh / cls / 进度条等都能正常渲染。
  // ANSI 原样透传，由前端 xterm.js 解析。cols/rows 由前端通过 resize 消息同步。
  try {
    const term = pty.spawn(launch.command, launch.args, {
      name: 'xterm-256color',
      cols: 120,
      rows: 30,
      cwd: launch.options.cwd,
      env: launch.options.env
    });
    term.onData((data) => ws.send(JSON.stringify({ type: 'data', data })));
    term.onExit(({ exitCode }) => ws.send(JSON.stringify({ type: 'exit', code: exitCode })));
    return term;
  } catch (error) {
    ws.send(JSON.stringify({ type: 'error', message: error.message }));
    return null;
  }
}

/**
 * 交互式终端：开一个带 oh-my-posh 提示符的 pwsh 会话。
 * 与脚本运行不同，这里不执行具体脚本，只是把 shell 本身挂在 PTY 上，
 * 由前端 xterm.js 直接交互（提示符、补全、历史都由 shell 负责）。
 */
function runInteractiveShell(ws) {
  if (!pty) {
    ws.send(JSON.stringify({ type: 'error', message: '交互式终端需要 node-pty，当前环境不可用。' }));
    return null;
  }
  const pwsh = resolvePwsh();
  if (!pwsh) {
    ws.send(JSON.stringify({ type: 'error', message: '未找到 PowerShell 7（pwsh）。请安装后重试。' }));
    return null;
  }

  const args = ['-NoLogo', '-NoProfile', '-NoExit'];
  const themeName = loadSettings().terminalTheme;
  const themePath = resolveThemePath(themeName);
  const omp = resolveOhMyPosh();
  if (omp && themePath) {
    // 显式 init，避免依赖用户的 profile（脚本运行用的是 -NoProfile）。
    const init = `oh-my-posh init pwsh --config '${themePath.replace(/'/g, "''")}' | Invoke-Expression`;
    args.push('-Command', init);
  }

  try {
    const term = pty.spawn(pwsh, args, {
      name: 'xterm-256color',
      cols: 120,
      rows: 30,
      cwd: ROOT,
      env: {
        ...process.env,
        // 供脚本判断"当前是网页终端"用（历史上有同名变量但从未被设置过）。
        SCRIPT_STUDIO_WEB_TERMINAL: '1',
        SCRIPT_STUDIO_WEB_NO_PAUSE: '1',
        TERM: 'xterm-256color'
      }
    });
    term.onData((data) => ws.send(JSON.stringify({ type: 'data', data })));
    term.onExit(({ exitCode }) => ws.send(JSON.stringify({ type: 'exit', code: exitCode })));
    return term;
  } catch (error) {
    ws.send(JSON.stringify({ type: 'error', message: error.message }));
    return null;
  }
}

wss.on('connection', (ws, req) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pollId = url.searchParams.get('poll');
  if (pollId) {
    const job = pollJobs.get(pollId);
    if (!job) { ws.send(JSON.stringify({ type: 'error', message: '轮询任务不存在。' })); ws.close(); return; }
    job.clients.add(ws);
    ws.send(JSON.stringify({ type: 'poll-snapshot', job: pollJobSnapshot(job) }));
    ws.on('close', () => job.clients.delete(ws));
    return;
  }
  // 交互式终端会话（新建终端）
  if (url.searchParams.get('shell')) {
    const token = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const settings = loadSettings();
    ws.send(JSON.stringify({
      type: 'ready',
      token,
      shell: { theme: settings.terminalTheme, cwd: ROOT }
    }));
    const child = runInteractiveShell(ws);
    if (child) processes.set(token, child);
    ws.on('message', (raw) => {
      try {
        const msg = JSON.parse(raw);
        if (msg.type === 'input' && child && child.write && !child.killed) child.write(String(msg.data || ''));
        if (msg.type === 'resize' && child && child.resize) {
          const cols = Math.max(2, Math.min(500, Number(msg.cols) || 120));
          const rows = Math.max(2, Math.min(300, Number(msg.rows) || 30));
          try { child.resize(cols, rows); } catch {}
        }
        if (msg.type === 'stop' && child && child.kill) child.kill();
      } catch {}
    });
    ws.on('close', () => { if (child && !child.killed) child.kill(); processes.delete(token); });
    return;
  }
  const scriptId = url.searchParams.get('script');
  const token = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const script = loadConfig().scripts.find((x) => x.id === scriptId);
  if (!script) { ws.send(JSON.stringify({ type: 'error', message: 'Script not found.' })); ws.close(); return; }
  ws.send(JSON.stringify({ type: 'ready', token, script }));
  const child = runScript(script, ws);
  if (child) processes.set(token, child);
  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw);
      if (msg.type === 'input' && child && child.write && !child.killed) child.write(String(msg.data || ''));
      else if (msg.type === 'input' && child && child.stdin && child.stdin.writable) child.stdin.write(String(msg.data || ''));
      if (msg.type === 'resize' && child && child.resize) {
        const cols = Math.max(2, Math.min(500, Number(msg.cols) || 120));
        const rows = Math.max(2, Math.min(300, Number(msg.rows) || 30));
        try { child.resize(cols, rows); } catch {}
      }
      if (msg.type === 'stop' && child) {
        if (child.kill) child.kill();
        else if (child.pid) child.kill();
      }
    } catch {}
  });
  ws.on('close', () => { if (child && !child.killed) child.kill(); processes.delete(token); });
});

pruneExpiredBackups({
  backupDir: BACKUP_DIR,
  retentionDays: 7,
  onDelete: (file) => console.log(`[backup] Deleted expired backup: ${path.relative(ROOT, file)}`),
  onError: (error, target) => console.error(`[backup] Cleanup failed for ${target}: ${error.message}`)
});

server.listen(PORT, '127.0.0.1', () => console.log(`Script Studio is running at http://127.0.0.1:${PORT}`));
