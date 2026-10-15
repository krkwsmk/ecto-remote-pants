'use strict';

const $ = (id) => document.getElementById(id);
const MAX_LINES = 4000;

const TAGS = { info: 'SYS', command: 'CMD', control: 'NET', data: 'RX ', sent: 'TX ', error: 'ERR' };
const PHASE_LABEL = { idle: 'ОФФЛАЙН', connecting: 'ПОДКЛЮЧЕНИЕ…', reconnecting: 'ПЕРЕПОДКЛ…', listening: 'СЛУШАЮ', failed: 'ОШИБКА' };

// Global relay settings (shared across tabs)
let settings = {
  sshUser: 'debug',
  sshHost: '176.53.160.131',
  password: '',
  savePassword: false,
  lineEnding: 'lf',
  lastPort: ''
};

// Per-tab session state (renderer side)
const sessions = new Map(); // sid -> session
let activeSid = null;
let sidCounter = 0;

function makeSession() {
  sidCounter += 1;
  const sid = 's' + sidCounter;
  const s = {
    id: sid,
    title: 'Порт —',
    phase: 'idle',
    port: settings.lastPort || '',
    totalBytes: 0,
    lines: [],
    conns: new Map(), // connId -> {peer, startedAt, status, bytes, file}
    targetConnId: null,
    manualTarget: false,
    cmdDraft: ''
  };
  sessions.set(sid, s);
  return s;
}

function activeSession() { return sessions.get(activeSid); }

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

async function initSettings() {
  const loaded = await window.ecto.loadSettings();
  settings = Object.assign(settings, loaded || {});
  $('sshUser').value = settings.sshUser || '';
  $('sshHost').value = settings.sshHost || '';
  $('sshPassword').value = settings.password || '';
  $('savePassword').checked = !!settings.savePassword;
  setSegActive(settings.lineEnding || 'lf');
  updateNoPwHint();
  $('logsPathText').textContent = await window.ecto.logsPath();
}

function collectSettings() {
  settings.sshUser = $('sshUser').value.trim();
  settings.sshHost = $('sshHost').value.trim();
  settings.lineEnding = currentLineEnding();
  settings.savePassword = $('savePassword').checked;
  settings.password = settings.savePassword ? $('sshPassword').value : '';
  return settings;
}

async function persist() {
  collectSettings();
  await window.ecto.saveSettings(settings);
  updateNoPwHint();
}

function updateNoPwHint() {
  $('noPwHint').style.display = $('sshPassword').value ? 'none' : 'block';
}

let lineEnding = 'lf';
function currentLineEnding() { return lineEnding; }
function setSegActive(mode) {
  lineEnding = mode;
  document.querySelectorAll('.seg-btn').forEach((b) => b.classList.toggle('active', b.dataset.le === mode));
}

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------

function renderTabs() {
  const el = $('tabs');
  el.innerHTML = '';
  for (const s of sessions.values()) {
    const tab = document.createElement('div');
    tab.className = 'tab' + (s.id === activeSid ? ' active' : '');
    const dot = document.createElement('span');
    dot.className = 'tab-dot ' + s.phase;
    const label = document.createElement('span');
    label.className = 'tab-label';
    label.textContent = s.title;
    tab.append(dot, label);
    if (sessions.size > 1) {
      const x = document.createElement('span');
      x.className = 'tab-close';
      x.textContent = '✕';
      x.onclick = (e) => { e.stopPropagation(); closeTab(s.id); };
      tab.append(x);
    }
    tab.onclick = () => switchTab(s.id);
    el.appendChild(tab);
  }
}

function newTab() {
  const s = makeSession();
  activeSid = s.id;
  renderTabs();
  renderMain();
}

function closeTab(sid) {
  const s = sessions.get(sid);
  if (!s) return;
  window.ecto.closeSession(sid);
  sessions.delete(sid);
  if (activeSid === sid) {
    const next = sessions.keys().next();
    if (!next.done) activeSid = next.value;
    else { newTab(); return; }
  }
  renderTabs();
  renderMain();
}

function switchTab(sid) {
  if (!sessions.has(sid)) return;
  // save current port draft
  const cur = activeSession();
  if (cur) { cur.port = $('port').value; cur.cmdDraft = $('cmdInput').value; }
  activeSid = sid;
  renderTabs();
  renderMain();
}

function tabTitle(s) {
  const p = (s.port || '').trim();
  return p ? ('Порт ' + p) : 'Новая вкладка';
}

// ---------------------------------------------------------------------------
// Main area render (reflects the active session)
// ---------------------------------------------------------------------------

function renderMain() {
  const s = activeSession();
  if (!s) return;
  $('port').value = s.port || '';
  $('cmdInput').value = s.cmdDraft || '';
  applyPhase(s);
  rebuildConsole(s);
  renderConnections(s);
  $('bytes').textContent = `${s.totalBytes} байт`;
}

function applyPhase(s) {
  const pill = $('statusPill');
  pill.className = 'pill ' + s.phase;
  $('statusLabel').textContent = PHASE_LABEL[s.phase] || s.phase.toUpperCase();

  const active = (s.phase === 'connecting' || s.phase === 'listening' || s.phase === 'reconnecting');
  $('connectBtn').style.display = active ? 'none' : 'block';
  $('disconnectBtn').style.display = active ? 'block' : 'none';

  const canSend = (s.phase === 'listening') && (s.targetConnId != null) && connIsActive(s, s.targetConnId);
  $('cmdInput').disabled = !canSend;
  $('enterBtn').disabled = !canSend;
  $('sendBtn').disabled = !canSend;
  $('cmdInput').placeholder = canSend ? 'Команда устройству, Enter — отправить' : 'Нет активного соединения';
  $('cmdChevron').className = canSend ? 'chevron on' : 'chevron';
  $('activeConn').textContent = (s.targetConnId != null) ? `→ #${String(s.targetConnId).padStart(3, '0')}` : '';
}

function connIsActive(s, id) { const c = s.conns.get(id); return c && c.status === 'active'; }

// ---------------------------------------------------------------------------
// Console
// ---------------------------------------------------------------------------

function timeStr(ts) {
  const d = new Date(ts);
  const p = (n, l = 2) => String(n).padStart(l, '0');
  return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}.${p(d.getMilliseconds(), 3)}`;
}

function lineRow(entry) {
  const row = document.createElement('div');
  row.className = 'line k-' + entry.kind;
  const t = document.createElement('span'); t.className = 'time'; t.textContent = timeStr(entry.ts);
  const tag = document.createElement('span'); tag.className = 'tag'; tag.textContent = TAGS[entry.kind] || '   ';
  const msg = document.createElement('span'); msg.className = 'msg'; msg.textContent = entry.text;
  row.append(t, tag, msg);
  return row;
}

function rebuildConsole(s) {
  const con = $('console');
  con.innerHTML = '';
  const frag = document.createDocumentFragment();
  for (const e of s.lines) frag.appendChild(lineRow(e));
  con.appendChild(frag);
  if ($('autoScroll').checked) con.scrollTop = con.scrollHeight;
}

function addLine(s, entry) {
  s.lines.push(entry);
  if (s.lines.length > MAX_LINES) s.lines.splice(0, s.lines.length - MAX_LINES);
  if (s.id === activeSid) {
    const con = $('console');
    con.appendChild(lineRow(entry));
    while (con.childElementCount > MAX_LINES) con.removeChild(con.firstChild);
    if ($('autoScroll').checked) con.scrollTop = con.scrollHeight;
  }
}

// ---------------------------------------------------------------------------
// Connections
// ---------------------------------------------------------------------------

function renderConnections(s) {
  const list = $('connList');
  const empty = $('connEmpty');
  $('connCount').textContent = String(s.conns.size);
  list.innerHTML = '';
  if (s.conns.size === 0) { empty.style.display = 'block'; return; }
  empty.style.display = 'none';
  const items = [...s.conns.entries()].sort((a, b) => b[0] - a[0]);
  for (const [id, c] of items) {
    const row = document.createElement('div');
    row.className = 'conn-row' + (c.status === 'closed' ? ' closed' : '') + (id === s.targetConnId ? ' target' : '');

    const target = document.createElement('button');
    target.className = 'conn-target' + (id === s.targetConnId ? ' on' : '');
    target.textContent = (id === s.targetConnId) ? '●' : '○';
    target.title = 'Сделать активным для команд';
    target.disabled = c.status !== 'active';
    target.onclick = () => { setTarget(s, id, true); };

    const idx = document.createElement('span');
    idx.className = 'conn-idx';
    idx.textContent = '#' + String(id).padStart(3, '0');

    const info = document.createElement('div');
    info.className = 'conn-info';
    const peer = document.createElement('div');
    peer.className = 'conn-peer';
    peer.textContent = c.peer + (c.status === 'closed' ? '  (закрыто)' : '');
    const meta = document.createElement('div');
    meta.className = 'conn-meta';
    meta.textContent = `${c.bytes} B · ${c.startedAt.split(' ')[1] || c.startedAt}`;
    info.append(peer, meta);

    const actions = document.createElement('div');
    actions.className = 'conn-actions';
    if (c.status === 'active') {
      const kill = document.createElement('button');
      kill.className = 'conn-kill';
      kill.textContent = 'ОБОРВАТЬ';
      kill.onclick = () => window.ecto.closeConn(s.id, id);
      actions.append(kill);
    }
    const file = document.createElement('button');
    file.className = 'conn-open';
    file.textContent = 'ФАЙЛ';
    file.disabled = !c.file;
    file.onclick = () => window.ecto.revealConn(c.file);
    actions.append(file);

    row.append(target, idx, info, actions);
    list.appendChild(row);
  }
}

function setTarget(s, id, manual) {
  if (!connIsActive(s, id)) return;
  s.targetConnId = id;
  if (manual) s.manualTarget = true;
  window.ecto.setActiveConn(s.id, id);
  if (s.id === activeSid) { applyPhase(s); renderConnections(s); }
}

function autoFollowTarget(s, newId) {
  if (s.manualTarget && connIsActive(s, s.targetConnId)) return;
  setTarget(s, newId, false);
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

function connect() {
  const s = activeSession();
  if (!s) return;
  s.port = $('port').value.trim();
  s.title = tabTitle(s);
  settings.lastPort = s.port;
  persist();
  const cfg = {
    port: s.port,
    host: settings.sshHost,
    user: settings.sshUser,
    password: $('sshPassword').value,
    lineEnding: currentLineEnding()
  };
  window.ecto.connect(s.id, cfg);
  renderTabs();
}

function sendCmd() {
  const s = activeSession();
  if (!s) return;
  const text = $('cmdInput').value;
  window.ecto.send(s.id, text);
  $('cmdInput').value = '';
  s.cmdDraft = '';
}

// ---------------------------------------------------------------------------
// IPC routing
// ---------------------------------------------------------------------------

function onPhase(d) {
  const s = sessions.get(d.sid);
  if (!s) return;
  s.phase = d.phase;
  renderTabs();
  if (s.id === activeSid) applyPhase(s);
}

function onLog(d) {
  const s = sessions.get(d.sid);
  if (!s) return;
  addLine(s, { kind: d.kind, text: d.text, ts: d.ts });
}

function onBytes(d) {
  const s = sessions.get(d.sid);
  if (!s) return;
  s.totalBytes = d.bytes;
  if (s.id === activeSid) $('bytes').textContent = `${d.bytes} байт`;
}

function onConnNew(d) {
  const s = sessions.get(d.sid);
  if (!s) return;
  s.conns.set(d.id, { peer: d.peer, startedAt: d.startedAt, status: d.status, bytes: d.bytes || 0, file: d.file || null });
  autoFollowTarget(s, d.id);
  if (s.id === activeSid) renderConnections(s);
}

function onConnUpdate(d) {
  const s = sessions.get(d.sid);
  if (!s) return;
  const c = s.conns.get(d.id);
  if (!c) return;
  c.bytes = d.bytes;
  c.status = d.status;
  if (d.status === 'closed' && s.targetConnId === d.id) {
    // move target to another active connection if any
    const other = [...s.conns.entries()].reverse().find(([id, cc]) => cc.status === 'active');
    s.targetConnId = other ? other[0] : null;
    s.manualTarget = false;
    if (s.targetConnId != null) window.ecto.setActiveConn(s.id, s.targetConnId);
  }
  if (s.id === activeSid) { renderConnections(s); applyPhase(s); }
}

function onConnFile(d) {
  const s = sessions.get(d.sid);
  if (!s) return;
  const c = s.conns.get(d.id);
  if (c) { c.file = d.file; if (s.id === activeSid) renderConnections(s); }
}

function onResetConnections(d) {
  const s = sessions.get(d.sid);
  if (!s) return;
  s.conns.clear();
  s.targetConnId = null;
  s.manualTarget = false;
  s.totalBytes = 0;
  if (s.id === activeSid) { renderConnections(s); $('bytes').textContent = '0 байт'; }
}

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------

window.addEventListener('DOMContentLoaded', async () => {
  await initSettings();
  newTab();

  $('addTabBtn').onclick = () => newTab();
  $('connectBtn').onclick = connect;
  $('disconnectBtn').onclick = () => { const s = activeSession(); if (s) window.ecto.disconnect(s.id); };
  $('openLogsBtn').onclick = () => window.ecto.openLogs();
  $('openLogsBtn2').onclick = () => window.ecto.openLogs();
  $('clearBtn').onclick = () => { const s = activeSession(); if (s) { s.lines = []; rebuildConsole(s); } };
  $('sendBtn').onclick = sendCmd;
  $('enterBtn').onclick = () => { const s = activeSession(); if (s) window.ecto.enter(s.id); };
  $('cmdInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') sendCmd(); });
  $('cmdInput').addEventListener('input', () => { const s = activeSession(); if (s) s.cmdDraft = $('cmdInput').value; });
  $('port').addEventListener('input', () => {
    const s = activeSession();
    if (s) { s.port = $('port').value; s.title = tabTitle(s); renderTabs(); }
  });

  $('settingsBtn').onclick = () => { $('settingsOverlay').style.display = 'flex'; };
  $('settingsClose').onclick = () => { $('settingsOverlay').style.display = 'none'; };
  $('settingsSave').onclick = async () => {
    await persist();
    const f = $('savedFlash');
    f.style.display = 'block';
    setTimeout(() => { f.style.display = 'none'; }, 1800);
  };
  $('sshPassword').addEventListener('input', updateNoPwHint);
  document.querySelectorAll('.seg-btn').forEach((b) => { b.onclick = () => setSegActive(b.dataset.le); });
  $('settingsOverlay').addEventListener('click', (e) => {
    if (e.target === $('settingsOverlay')) $('settingsOverlay').style.display = 'none';
  });

  window.ecto.on('phase', onPhase);
  window.ecto.on('log', onLog);
  window.ecto.on('bytes', onBytes);
  window.ecto.on('conn-new', onConnNew);
  window.ecto.on('conn-update', onConnUpdate);
  window.ecto.on('conn-file', onConnFile);
  window.ecto.on('reset-connections', onResetConnections);
});
