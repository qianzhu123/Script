const express = require('express');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn, execFile, exec } = require('child_process');
const WebSocket = require('ws');
const { writeJsonWithBackup, pruneExpiredBackups } = require('./config-backup.js');
const { buildRunnerLaunch } = require('./runner-launch.js');
let iconv = null;
try { iconv = require('iconv-lite'); } catch {}

const ROOT = __dirname;
const PORT = Number(process.env.PORT || 3100);
const CONFIG_DIR = path.join(ROOT, 'config');
const SCRIPT_CONFIG = path.join(CONFIG_DIR, 'scripts.json');
const EXAMPLE_CONFIG = path.join(CONFIG_DIR, 'scripts.example.json');
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
const wss = new WebSocket.Server({ server, path: '/ws' });
const processes = new Map();
// 轮询任务由服务器持有，因此浏览器刷新或临时断开不会停止后续运行。
const pollJobs = new Map();

app.use(express.json({ limit: '2mb' }));
app.use(express.static(path.join(ROOT, 'public')));

app.get('/api/config', (_req, res) => {
  try {
    res.json(loadConfig());
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
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

app.delete('/api/scripts/:id', (req, res) => {
  const config = loadConfig();
  const before = config.scripts.length;
  config.scripts = config.scripts.filter((x) => x.id !== req.params.id);
  if (before === config.scripts.length) return res.status(404).json({ error: 'Script not found.' });
  saveConfig(config);
  res.json({ ok: true });
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
  if (child) { child.kill(); processes.delete(req.params.token); }
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
  const child = spawn(launch.command, launch.args, launch.options);
  child.stdout.on('data', (c) => ws.send(JSON.stringify({ type: 'data', data: decodeOutput(c) })));
  child.stderr.on('data', (c) => ws.send(JSON.stringify({ type: 'data', data: decodeOutput(c) })));
  child.on('close', (code) => ws.send(JSON.stringify({ type: 'exit', code })));
  child.on('error', (error) => ws.send(JSON.stringify({ type: 'error', message: error.message })));
  return child;
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
      if (msg.type === 'input' && child && child.stdin.writable) child.stdin.write(String(msg.data || ''));
      if (msg.type === 'stop' && child) child.kill();
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
