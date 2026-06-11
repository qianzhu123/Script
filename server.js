const express = require('express');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn, execFile, exec } = require('child_process');
const WebSocket = require('ws');
let iconv = null;
try { iconv = require('iconv-lite'); } catch {}

const ROOT = __dirname;
const PORT = Number(process.env.PORT || 3100);
const CONFIG_DIR = path.join(ROOT, 'config');
const SCRIPT_CONFIG = path.join(CONFIG_DIR, 'scripts.json');
const EXAMPLE_CONFIG = path.join(CONFIG_DIR, 'scripts.example.json');

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

// 路径标准化：
// - 项目内绝对路径 → 转为相对路径
// - 项目外绝对路径 → 原样保留（用户配置了外部脚本，合法）
// - 相对路径 → 标准化斜杠
function normalizePath(input) {
  const text = String(input || '').trim().replace(/^"|"$/g, '').replace(/^'|'$/g, '').replace(/\\/g, '/');
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
  const clean = String(p || '').trim().replace(/^"|"$/g, '').replace(/^'|'$/g, '');
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
  if (!hasUsableConfig(current)) writeJson(SCRIPT_CONFIG, normalizeConfig(readJson(EXAMPLE_CONFIG, defaultConfig())));
}

function loadConfig() {
  ensureConfig();
  const normalized = normalizeConfig(readJson(SCRIPT_CONFIG, defaultConfig()));
  return hasUsableConfig(normalized) ? normalized : normalizeConfig(defaultConfig());
}

function saveConfig(config) { writeJson(SCRIPT_CONFIG, normalizeConfig(config)); }

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

app.use(express.json({ limit: '2mb' }));
app.use(express.static(path.join(ROOT, 'public')));

app.get('/api/config', (_req, res) => {
  try {
    res.json(loadConfig());
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
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

function decodeOutput(chunk) {
  if (!Buffer.isBuffer(chunk)) return String(chunk || '');
  if (looksLikeUtf16le(chunk)) return chunk.toString('utf16le');
  const utf8 = chunk.toString('utf8');
  if (!utf8.includes('\uFFFD')) return utf8;
  if (iconv) {
    try { return iconv.decode(chunk, 'cp936'); } catch {}
  }
  return utf8;
}

function runScript(script, ws) {
  const absolute = path.normalize(resolveScriptPath(script.path));
  if (!fs.existsSync(absolute)) {
    ws.send(JSON.stringify({ type: 'error', message: `Script not found: ${script.path}` })); return null;
  }
  const ext = path.extname(absolute).toLowerCase();
  const isPs = ext === '.ps1' || script.shell === 'powershell';
  let child;
  if (isPs) {
    child = spawn(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', absolute],
      { cwd: path.dirname(absolute), windowsHide: false, shell: false, env: { ...process.env, SCRIPT_STUDIO_ROOT: ROOT } }
    );
  } else {
    child = spawn(
      'cmd.exe',
      ['/d', '/s', '/c', absolute],
      { cwd: path.dirname(absolute), windowsHide: false, shell: false, env: { ...process.env, SCRIPT_STUDIO_ROOT: ROOT } }
    );
  }
  child.stdout.on('data', (c) => ws.send(JSON.stringify({ type: 'data', data: decodeOutput(c) })));
  child.stderr.on('data', (c) => ws.send(JSON.stringify({ type: 'data', data: decodeOutput(c) })));
  child.on('close', (code) => ws.send(JSON.stringify({ type: 'exit', code })));
  child.on('error', (error) => ws.send(JSON.stringify({ type: 'error', message: error.message })));
  return child;
}

wss.on('connection', (ws, req) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
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

server.listen(PORT, '127.0.0.1', () => console.log(`Script Studio is running at http://127.0.0.1:${PORT}`));
