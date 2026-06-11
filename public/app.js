const state = {
  config: { groups: [], scripts: [] },
  currentGroup: 'all',
  selectedScript: null,
  drag: { type: null, id: null },
  // 运行实例 tab 管理
  // sessions: Map<tabId, { scriptId, scriptName, ws, wsToken, output }>
  sessions: new Map(),
  activeTabId: null,
  tabCounter: 0
};

const $ = (id) => document.getElementById(id);
const sorted = (items) => [...items].sort((a, b) => (a.order || 0) - (b.order || 0));

async function api(url, options = {}) {
  const response = await fetch(url, {
    headers: { 'Content-Type': 'application/json' },
    ...options
  });
  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(data.error || response.statusText);
  return data;
}

function escapeHtml(value) {
  return String(value || '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#039;'
  }[char]));
}

function basename(filePath) {
  return String(filePath || '').split(/[\\\/]/).filter(Boolean).pop() || 'script';
}

function displayScriptNameFromPath(filePath) {
  const fileName = basename(filePath).replace(/\.lnk$/i, '');
  return fileName.replace(/\.(bat|cmd|ps1|js|vbs|wsf|py)$/i, '');
}

// ── 通用对话框 ────────────────────────────────────────────
function openAppDialog({ title = '提示', message = '', inputLabel = '', defaultValue = '', confirmText = '确定', cancelText = '取消', danger = false } = {}) {
  return new Promise((resolve) => {
    const dialog = $('appDialog');
    const form = $('appDialogForm');
    const inputWrap = $('appDialogInputWrap');
    const input = $('appDialogInput');
    const confirmBtn = $('appDialogConfirmBtn');
    const cancelBtn = $('appDialogCancelBtn');

    $('appDialogTitle').textContent = title;
    $('appDialogMessage').textContent = message;
    confirmBtn.textContent = confirmText;
    cancelBtn.textContent = cancelText;
    confirmBtn.classList.toggle('danger-btn', danger);

    if (inputLabel) {
      inputWrap.classList.remove('hidden');
      inputWrap.firstChild.textContent = inputLabel;
      input.value = defaultValue;
      input.required = true;
    } else {
      inputWrap.classList.add('hidden');
      input.value = '';
      input.required = false;
    }

    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      dialog.close();
      form.onsubmit = null;
      cancelBtn.onclick = null;
      dialog.oncancel = null;
      dialog.onclick = null;
      resolve(value);
    };

    form.onsubmit = (event) => {
      event.preventDefault();
      finish(inputLabel ? input.value.trim() : true);
    };
    cancelBtn.onclick = () => finish(null);
    dialog.oncancel = (event) => { event.preventDefault(); finish(null); };
    dialog.onclick = (event) => { if (event.target === dialog) finish(null); };

    dialog.showModal();
    if (inputLabel) input.focus();
  });
}

function bindDialogBackdrop(dialog) {
  dialog.addEventListener('click', (event) => {
    if (event.target === dialog) dialog.close();
  });
}

const appPrompt = (title, defaultValue = '') => openAppDialog({ title, inputLabel: title, defaultValue });
const appConfirm = (title, message) => openAppDialog({ title, message, confirmText: '删除', danger: true });

window.alert = (message) => openAppDialog({ title: '提示', message: String(message || '') });
window.confirm = () => false;
window.prompt = () => null;

// ── 运行实例 Tab 管理 ─────────────────────────────────────

function createTabId() {
  return `tab-${++state.tabCounter}`;
}

/** 渲染顶部 tab 栏 */
function renderRunTabs() {
  const bar = $('runTabs');
  bar.innerHTML = '';

  if (state.sessions.size === 0) {
    bar.style.display = 'none';
    return;
  }
  bar.style.display = 'flex';

  state.sessions.forEach((session, tabId) => {
    const btn = document.createElement('button');
    btn.className = `run-tab-btn ${tabId === state.activeTabId ? 'active' : ''}`;
    // 运行中显示小圆点
    const dot = session.ws ? '<span class="run-dot"></span>' : '';
    btn.innerHTML = `${dot}<span class="run-tab-label">${escapeHtml(session.scriptName)}</span><span class="tab-close" data-tab="${tabId}">×</span>`;
    btn.onclick = (e) => {
      if (e.target.classList.contains('tab-close')) return;
      switchRunTab(tabId);
    };
    btn.querySelector('.tab-close').onclick = (e) => {
      e.stopPropagation();
      closeRunTab(tabId);
    };
    bar.appendChild(btn);
  });
}

/** 切换到指定 tab，恢复其输出内容 */
function switchRunTab(tabId) {
  state.activeTabId = tabId;
  const session = state.sessions.get(tabId);
  if (!session) return;

  // 恢复该 tab 的输出
  $('terminal').textContent = session.output;
  $('terminal').scrollTop = $('terminal').scrollHeight;

  // 更新选中脚本为该 tab 对应的脚本
  state.selectedScript = state.config.scripts.find((s) => s.id === session.scriptId) || state.selectedScript;
  $('selectedTitle').textContent = session.scriptName;

  // stdin 输入框：运行中才可用
  $('stdinInput').disabled = !session.ws;

  renderRunTabs();
  renderSelected();
}

/** 关闭 tab：先停止 ws，再移除 */
function closeRunTab(tabId) {
  const session = state.sessions.get(tabId);
  if (session && session.ws) {
    try { session.ws.send(JSON.stringify({ type: 'stop' })); } catch {}
    session.ws.close();
    session.ws = null;
    session.wsToken = null;
  }
  state.sessions.delete(tabId);
  // 切到最后一个 tab，或清空
  if (state.activeTabId === tabId) {
    const remaining = [...state.sessions.keys()];
    if (remaining.length) {
      switchRunTab(remaining[remaining.length - 1]);
    } else {
      state.activeTabId = null;
      $('terminal').textContent = '选择左侧脚本后，点击「运行」执行，或点击「文件夹」在资源管理器中打开。';
      $('stdinInput').disabled = true;
      $('selectedTitle').textContent = state.selectedScript ? state.selectedScript.name : '未选择脚本';
    }
  }
  renderRunTabs();
  renderSelected();
}

/** 向当前活跃 tab 的终端追加文字，并同步保存到 session.output */
function appendToActiveTab(text) {
  const session = state.sessions.get(state.activeTabId);
  if (session) session.output += text;
  const el = $('terminal');
  el.textContent += text;
  el.scrollTop = el.scrollHeight;
}

function setActiveTabText(text) {
  const session = state.sessions.get(state.activeTabId);
  if (session) session.output = text;
  const el = $('terminal');
  el.textContent = text;
  el.scrollTop = el.scrollHeight;
}

// ── 加载配置 ──────────────────────────────────────────────
async function loadConfig() {
  state.config = await api('/api/config');
  if (state.selectedScript) {
    state.selectedScript = state.config.scripts.find((s) => s.id === state.selectedScript.id) || null;
  }
  renderGroups();
  renderScripts();
  renderSelected();
}

function currentScripts() {
  const scripts = sorted(state.config.scripts || []);
  return state.currentGroup === 'all'
    ? scripts
    : scripts.filter((s) => s.groupId === state.currentGroup);
}

function currentGroupName() {
  if (state.currentGroup === 'all') return '全部脚本';
  return state.config.groups.find((g) => g.id === state.currentGroup)?.name || '全部脚本';
}

// ── 拖拽排序 ──────────────────────────────────────────────
function startListDrag(event, type, id) {
  state.drag = { type, id };
  event.currentTarget.classList.add('dragging');
  event.dataTransfer.effectAllowed = 'move';
  event.dataTransfer.setData('text/plain', id);
}

function moveListDrag(event, container, selector) {
  event.preventDefault();
  const dragging = container.querySelector('.dragging');
  if (!dragging) return;
  const after = getDragAfterElement(container, event.clientY, selector);
  if (after) container.insertBefore(dragging, after);
  else container.appendChild(dragging);
}

function getDragAfterElement(container, y, selector) {
  const elements = [...container.querySelectorAll(`${selector}:not(.dragging)`)];
  return elements.reduce((closest, child) => {
    const box = child.getBoundingClientRect();
    const offset = y - box.top - box.height / 2;
    return offset < 0 && offset > closest.offset ? { offset, element: child } : closest;
  }, { offset: Number.NEGATIVE_INFINITY, element: null }).element;
}

function clearListDrag() {
  document.querySelectorAll('.dragging').forEach((item) => item.classList.remove('dragging'));
  state.drag = { type: null, id: null };
}

async function finishGroupDrag(event, container) {
  event.preventDefault();
  const ids = [...container.querySelectorAll('.group-row')].map((item) => item.dataset.id);
  await api('/api/groups/order', { method: 'POST', body: JSON.stringify({ ids }) });
  await loadConfig();
}

async function finishScriptDrag(event, container) {
  event.preventDefault();
  const ids = [...container.querySelectorAll('.script-card')].map((item) => item.dataset.id);
  await api('/api/scripts/order', { method: 'POST', body: JSON.stringify({ ids }) });
  await loadConfig();
}

// ── 左侧分组渲染 ──────────────────────────────────────────
function renderGroups() {
  const list = $('groupList');
  list.innerHTML = '';

  const all = document.createElement('button');
  all.className = `group-item ${state.currentGroup === 'all' ? 'active' : ''}`;
  all.textContent = '全部脚本';
  all.onclick = () => {
    state.currentGroup = 'all';
    renderGroups();
    renderScripts();
  };
  list.appendChild(all);

  sorted(state.config.groups || []).forEach((group) => {
    const row = document.createElement('div');
    row.className = `group-row ${state.currentGroup === group.id ? 'active' : ''}`;
    row.dataset.id = group.id;
    row.draggable = true;
    row.addEventListener('dragstart', (event) => startListDrag(event, 'group', group.id));
    row.addEventListener('dragover', (event) => moveListDrag(event, list, '.group-row'));
    row.addEventListener('drop', (event) => finishGroupDrag(event, list));
    row.addEventListener('dragend', clearListDrag);

    const button = document.createElement('button');
    button.className = 'group-name';
    button.textContent = group.name;
    button.onclick = () => {
      state.currentGroup = group.id;
      renderGroups();
      renderScripts();
    };

    const edit = document.createElement('button');
    edit.className = 'mini-btn';
    edit.textContent = '编辑';
    edit.onclick = async (event) => {
      event.stopPropagation();
      const name = await appPrompt('请输入分组名称', group.name);
      if (!name) return;
      await api(`/api/groups/${group.id}`, { method: 'PUT', body: JSON.stringify({ name }) });
      await loadConfig();
    };

    const remove = document.createElement('button');
    remove.className = 'mini-btn danger-text';
    remove.textContent = '删除';
    remove.onclick = async (event) => {
      event.stopPropagation();
      const confirmed = await appConfirm('删除分组', `删除分组"${group.name}"？组内脚本也会一起删除。`);
      if (!confirmed) return;
      await api(`/api/groups/${group.id}`, { method: 'DELETE' });
      state.currentGroup = 'all';
      await loadConfig();
    };

    row.append(button, edit, remove);
    list.appendChild(row);
  });
}

// ── 中间脚本列表渲染 ──────────────────────────────────────
function renderScripts() {
  $('listTitle').textContent = currentGroupName();
  const list = $('scriptList');
  list.innerHTML = '';
  const scripts = currentScripts();

  if (!scripts.length) {
    list.innerHTML = '<div class="empty">没有脚本。点击「新增脚本」添加一个本地 BAT、CMD 或 PowerShell 脚本。</div>';
    return;
  }

  scripts.forEach((script) => {
    const card = document.createElement('article');
    card.className = `script-card ${state.selectedScript?.id === script.id ? 'selected' : ''}`;
    card.dataset.id = script.id;
    card.draggable = true;
    card.addEventListener('dragstart', (event) => startListDrag(event, 'script', script.id));
    card.addEventListener('dragover', (event) => moveListDrag(event, list, '.script-card'));
    card.addEventListener('drop', (event) => finishScriptDrag(event, list));
    card.addEventListener('dragend', clearListDrag);

    const description = script.description
      ? `<p class="description">${escapeHtml(script.description)}</p>`
      : '<p class="description muted">暂无说明</p>';

    card.innerHTML = `
      <div class="script-info">
        <h2>${escapeHtml(script.name)}</h2>
        <p class="path">${escapeHtml(script.path)}</p>
        ${description}
      </div>
      <div class="card-actions">
        <button data-action="edit">编辑</button>
        <button data-action="delete" class="danger-outline">删除</button>
      </div>`;

    card.onclick = (event) => {
      const action = event.target.dataset.action;
      if (action === 'edit') return openScriptDialog(script);
      if (action === 'delete') return deleteScript(script);
      state.selectedScript = script;
      $('selectedTitle').textContent = script.name;
      renderScripts();
      renderSelected();
    };

    list.appendChild(card);
  });
}

// ── 右侧详情面板渲染 ──────────────────────────────────────
function renderSelected() {
  const script = state.selectedScript;
  $('runBtn').disabled = !script;
  $('exploreBtn').disabled = !script;

  // 停止按钮：当前活跃 tab 是否有运行中的 ws
  const activeSession = state.sessions.get(state.activeTabId);
  $('stopBtn').disabled = !activeSession?.ws;
}

// ── 运行脚本（WebSocket，每次新建一个 tab）────────────────
function runSelected() {
  const script = state.selectedScript;
  if (!script) return;

  const tabId = createTabId();
  const session = {
    scriptId: script.id,
    scriptName: script.name,
    ws: null,
    wsToken: null,
    output: `正在启动 ${script.name}...\n`
  };
  state.sessions.set(tabId, session);
  state.activeTabId = tabId;

  renderRunTabs();
  $('terminal').textContent = session.output;
  $('terminal').scrollTop = 0;
  $('stdinInput').disabled = true;
  $('selectedTitle').textContent = script.name;

  const ws = new WebSocket(`ws://${location.host}/ws?script=${encodeURIComponent(script.id)}`);
  session.ws = ws;

  ws.onopen = () => appendToActiveTab('已连接\n');

  ws.onmessage = (event) => {
    // 只有活跃 tab 才直接渲染，非活跃只存 output
    try {
      const msg = JSON.parse(event.data);
      if (msg.type === 'ready') {
        session.wsToken = msg.token;
        session.output += '脚本已启动\n';
        if (state.activeTabId === tabId) {
          $('terminal').textContent = session.output;
          $('terminal').scrollTop = $('terminal').scrollHeight;
          $('stdinInput').disabled = false;
        }
        renderRunTabs();
        renderSelected();
      } else if (msg.type === 'data') {
        session.output += msg.data;
        if (state.activeTabId === tabId) {
          const el = $('terminal');
          el.textContent += msg.data;
          el.scrollTop = el.scrollHeight;
        }
      } else if (msg.type === 'exit') {
        const exitMsg = `\n脚本已退出，退出码: ${msg.code}`;
        session.output += exitMsg;
        session.ws = null;
        session.wsToken = null;
        if (state.activeTabId === tabId) {
          const el = $('terminal');
          el.textContent += exitMsg;
          el.scrollTop = el.scrollHeight;
          $('stdinInput').disabled = true;
        }
        renderRunTabs();
        renderSelected();
      } else if (msg.type === 'error') {
        const errMsg = `\n错误: ${msg.message}`;
        session.output += errMsg;
        session.ws = null;
        session.wsToken = null;
        if (state.activeTabId === tabId) {
          const el = $('terminal');
          el.textContent += errMsg;
          el.scrollTop = el.scrollHeight;
          $('stdinInput').disabled = true;
        }
        renderRunTabs();
        renderSelected();
      }
    } catch {}
  };

  ws.onerror = () => {
    const errMsg = '\nWebSocket 连接失败';
    session.output += errMsg;
    session.ws = null;
    session.wsToken = null;
    if (state.activeTabId === tabId) {
      $('terminal').textContent = session.output;
      $('stdinInput').disabled = true;
    }
    renderRunTabs();
    renderSelected();
  };

  ws.onclose = () => {
    if (session.ws) {
      session.ws = null;
      session.wsToken = null;
      if (state.activeTabId === tabId) $('stdinInput').disabled = true;
      renderRunTabs();
      renderSelected();
    }
  };
}

// ── 停止脚本 ──────────────────────────────────────────────
function stopSelected() {
  const session = state.sessions.get(state.activeTabId);
  if (!session) return;
  if (session.ws) {
    try { session.ws.send(JSON.stringify({ type: 'stop' })); } catch {}
    session.ws.close();
    session.ws = null;
  }
  session.wsToken = null;
  const msg = '\n已发送停止信号';
  session.output += msg;
  $('terminal').textContent = session.output;
  $('stdinInput').disabled = true;
  renderRunTabs();
  renderSelected();
}

// ── 在文件资源管理器中打开（不新建 tab，直接调 API）────────
async function exploreSelected() {
  const script = state.selectedScript;
  if (!script) return;
  try {
    await api(`/api/explore/${script.id}`, { method: 'POST' });
  } catch (error) {
    // 打开失败才在当前终端提示
    const el = $('terminal');
    const msg = `\n✗ 打开文件夹失败: ${error.message}\n`;
    el.textContent += msg;
    el.scrollTop = el.scrollHeight;
    const session = state.sessions.get(state.activeTabId);
    if (session) session.output += msg;
  }
}

// ── stdin 输入框（底部，Enter 发送）──────────────────────
function setupStdinInput() {
  $('stdinInput').addEventListener('keydown', (event) => {
    if (event.key !== 'Enter') return;
    event.preventDefault();
    const session = state.sessions.get(state.activeTabId);
    if (!session || !session.ws) return;
    const text = $('stdinInput').value;
    $('stdinInput').value = '';
    try {
      session.ws.send(JSON.stringify({ type: 'input', data: text + '\n' }));
      // 回显输入
      const echo = `> ${text}\n`;
      session.output += echo;
      $('terminal').textContent = session.output;
      $('terminal').scrollTop = $('terminal').scrollHeight;
    } catch {}
  });
}

// ── 分组管理 ──────────────────────────────────────────────
async function addGroup() {
  const name = await appPrompt('请输入分组名称');
  if (!name) return;
  await api('/api/groups', { method: 'POST', body: JSON.stringify({ name }) });
  await loadConfig();
}

function fillGroupSelect(value = '') {
  const select = $('scriptGroup');
  select.innerHTML = '<option value="">未分组</option>' + sorted(state.config.groups || [])
    .map((g) => `<option value="${escapeHtml(g.id)}">${escapeHtml(g.name)}</option>`)
    .join('');
  select.value = value;
}

// ── 脚本对话框 ────────────────────────────────────────────
function openScriptDialog(script = null) {
  $('scriptDialogTitle').textContent = script ? '编辑脚本' : '新增脚本';
  $('scriptId').value = script?.id || '';
  $('scriptName').value = script?.name || '';
  $('scriptPath').value = script?.path || '';
  $('scriptDescription').value = script?.description || '';
  $('scriptPorts').value = (script?.ports || []).join(', ');
  fillGroupSelect(script?.groupId || (state.currentGroup !== 'all' ? state.currentGroup : ''));
  $('scriptDialog').showModal();
  if (!$('scriptName').value && $('scriptPath').value) {
    $('scriptName').value = displayScriptNameFromPath($('scriptPath').value);
  }
  $('scriptPath').focus();
}

async function saveScript(event) {
  event.preventDefault();
  const id = $('scriptId').value;
  const body = {
    name: $('scriptName').value,
    path: $('scriptPath').value,
    groupId: $('scriptGroup').value,
    description: $('scriptDescription').value,
    ports: $('scriptPorts').value
  };
  const saved = await api(id ? `/api/scripts/${id}` : '/api/scripts', {
    method: id ? 'PUT' : 'POST',
    body: JSON.stringify(body)
  });
  $('scriptDialog').close();
  state.selectedScript = saved;
  await loadConfig();
}

async function deleteScript(script) {
  const confirmed = await appConfirm('删除脚本', `删除脚本"${script.name}"？`);
  if (!confirmed) return;
  await api(`/api/scripts/${script.id}`, { method: 'DELETE' });
  if (state.selectedScript?.id === script.id) {
    state.selectedScript = null;
    $('selectedTitle').textContent = '未选择脚本';
  }
  await loadConfig();
}

// ── 面板宽度调整 ──────────────────────────────────────────
function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function applyPanelSizes() {
  const layout = $('layoutRoot');
  const sidebar = localStorage.getItem('script-studio-sidebar-width');
  const terminal = localStorage.getItem('script-studio-terminal-width');
  if (sidebar) layout.style.setProperty('--sidebar-width', `${clamp(Number(sidebar), 220, 520)}px`);
  if (terminal) layout.style.setProperty('--terminal-width', `${clamp(Number(terminal), 420, window.innerWidth - 520)}px`);
}

function setupPanelResizers() {
  const layout = $('layoutRoot');
  applyPanelSizes();

  document.querySelectorAll('.panel-resizer').forEach((resizer) => {
    resizer.addEventListener('pointerdown', (event) => {
      if (window.innerWidth <= 780) return;
      event.preventDefault();
      const type = resizer.dataset.resizer;
      const startX = event.clientX;
      const sidebarStart = document.querySelector('.sidebar').getBoundingClientRect().width;
      const terminalStart = document.querySelector('.terminal-panel').getBoundingClientRect().width;
      layout.classList.add('resizing');

      const move = (moveEvent) => {
        if (type === 'left') {
          const width = clamp(sidebarStart + moveEvent.clientX - startX, 220, 520);
          layout.style.setProperty('--sidebar-width', `${width}px`);
          localStorage.setItem('script-studio-sidebar-width', String(width));
        } else {
          const width = clamp(terminalStart - (moveEvent.clientX - startX), 420, window.innerWidth - 520);
          layout.style.setProperty('--terminal-width', `${width}px`);
          localStorage.setItem('script-studio-terminal-width', String(width));
        }
      };

      const stop = () => {
        layout.classList.remove('resizing');
        window.removeEventListener('pointermove', move);
        window.removeEventListener('pointerup', stop);
      };

      window.addEventListener('pointermove', move);
      window.addEventListener('pointerup', stop);
    });
  });
}

// ── 初始化 ────────────────────────────────────────────────
bindDialogBackdrop($('scriptDialog'));
$('addGroupBtn').onclick = addGroup;
$('addScriptBtn').onclick = () => openScriptDialog();
$('cancelScriptBtn').onclick = () => $('scriptDialog').close();
$('scriptForm').onsubmit = saveScript;
$('runBtn').onclick = runSelected;
$('exploreBtn').onclick = exploreSelected;
$('stopBtn').onclick = stopSelected;
$('scriptPath').addEventListener('input', () => {
  if ($('scriptPath').value) $('scriptName').value = displayScriptNameFromPath($('scriptPath').value);
});

setupStdinInput();
setupPanelResizers();

loadConfig().catch((error) => {
  $('scriptList').innerHTML = `<div class="empty">加载失败：${escapeHtml(error.message)}</div>`;
  $('terminal').textContent = `加载失败: ${error.message}`;
});
