'use strict';

const $ = (id) => document.getElementById(id);

let phase = 'idle';
let lineEnding = 'lf';
const connections = new Map(); // id -> {peer, bytes, startedAt, file}

const MAX_LINES = 6000;

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

let settings = {
  sshUser: 'debug',
  sshHost: '176.53.160.131',
  password: '',
  savePassword: false,
  lineEnding: 'lf',
  lastPort: ''
};

async function initSettings() {
  const loaded = await window.ecto.loadSettings();
  settings = Object.assign(settings, loaded || {});
  lineEnding = settings.lineEnding || 'lf';
  $('port').value = settings.lastPort || '';
  $('sshUser').value = settings.sshUser || '';
  $('sshHost').value = settings.sshHost || '';
  $('sshPassword').value = settings.password || '';
  $('savePassword').checked = !!settings.savePassword;
  setSegActive(lineEnding);
  updateNoPwHint();
  const lp = await window.ecto.logsPath();
  $('logsPathText').textContent = lp;
}

function collectSettings() {
  settings.sshUser = $('sshUser').value.trim();
  settings.sshHost = $('sshHost').value.trim();
  settings.lineEnding = lineEnding;
  settings.lastPort = $('port').value.trim();
  const pw = $('sshPassword').value;
  settings.savePassword = $('savePassword').checked;
  settings.password = settings.savePassword ? pw : '';
  return settings;
}

async function persist() {
  collectSettings();
  await window.ecto.saveSettings(settings);
  updateNoPwHint();
}

function currentPassword() {
  // Use whatever is typed in settings field (even if "remember" is off).
  return $('sshPassword').value;
}

function updateNoPwHint() {
  const has = !!$('sshPassword').value;
  $('noPwHint').style.display = has ? 'none' : 'block';
}

// ---------------------------------------------------------------------------
// Console
// ---------------------------------------------------------------------------

const TAGS = { info: 'SYS', command: 'CMD', control: 'NET', data: 'RX ', sent: 'TX ', error: 'ERR' };

function timeStr(ts) {
  const d = new Date(ts);
  const p = (n, l = 2) => String(n).padStart(l, '0');
  return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}.${p(d.getMilliseconds(), 3)}`;
}

function addLine(entry) {
  const con = $('console');
  const row = document.createElement('div');
  row.className = 'line k-' + entry.kind;
  const t = document.createElement('span'); t.className = 'time'; t.textContent = timeStr(entry.ts);
  const tag = document.createElement('span'); tag.className = 'tag'; tag.textContent = TAGS[entry.kind] || '   ';
  const msg = document.createElement('span'); msg.className = 'msg'; msg.textContent = entry.text;
  row.append(t, tag, msg);
  con.appendChild(row);
  while (con.childElementCount > MAX_LINES) con.removeChild(con.firstChild);
  if ($('autoScroll').checked) con.scrollTop = con.scrollHeight;
}

// ---------------------------------------------------------------------------
// Connections UI
// ---------------------------------------------------------------------------

function renderConnections() {
  const list = $('connList');
  const empty = $('connEmpty');
  $('connCount').textContent = String(connections.size);
  list.innerHTML = '';
  if (connections.size === 0) { empty.style.display = 'block'; return; }
  empty.style.display = 'none';
  const items = [...connections.values()].sort((a, b) => b.id - a.id);
  for (const c of items) {
    const row = document.createElement('div');
    row.className = 'conn-row';
    const idx = document.createElement('span');
    idx.className = 'conn-idx';
    idx.textContent = '#' + String(c.id).padStart(3, '0');
    const info = document.createElement('div');
    info.className = 'conn-info';
    const peer = document.createElement('div'); peer.className = 'conn-peer'; peer.textContent = c.peer;
    const meta = document.createElement('div'); meta.className = 'conn-meta'; meta.textContent = `${c.bytes} B · ${c.startedAt}`;
    info.append(peer, meta);
    const btn = document.createElement('button');
    btn.className = 'conn-open';
    btn.textContent = 'ОТКРЫТЬ';
    btn.onclick = () => window.ecto.revealConn(c.file);
    row.append(idx, info, btn);
    list.appendChild(row);
  }
}

// ---------------------------------------------------------------------------
// Phase
// ---------------------------------------------------------------------------

const PHASE_LABEL = { idle: 'ОФФЛАЙН', connecting: 'ПОДКЛЮЧЕНИЕ…', listening: 'СЛУШАЮ', failed: 'ОШИБКА' };

function applyPhase(p) {
  phase = p;
  const pill = $('statusPill');
  pill.className = 'pill ' + p;
  $('statusLabel').textContent = PHASE_LABEL[p] || p.toUpperCase();

  const active = (p === 'connecting' || p === 'listening');
  $('connectBtn').style.display = active ? 'none' : 'block';
  $('disconnectBtn').style.display = active ? 'block' : 'none';

  const canSend = (p === 'listening');
  $('cmdInput').disabled = !canSend;
  $('enterBtn').disabled = !canSend;
  $('sendBtn').disabled = !canSend;
  $('cmdInput').placeholder = canSend ? 'Команда устройству, Enter — отправить' : 'Нет активного соединения';
  $('cmdChevron').className = canSend ? 'chevron on' : 'chevron';
}

// ---------------------------------------------------------------------------
// Segmented control for line ending
// ---------------------------------------------------------------------------

function setSegActive(mode) {
  lineEnding = mode;
  document.querySelectorAll('.seg-btn').forEach((b) => {
    b.classList.toggle('active', b.dataset.le === mode);
  });
}

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------

function connect() {
  const cfg = {
    port: $('port').value.trim(),
    host: ($('sshHost').value || settings.sshHost).trim(),
    user: ($('sshUser').value || settings.sshUser).trim(),
    password: currentPassword(),
    lineEnding
  };
  persist();
  window.ecto.connect(cfg);
}

function sendCmd() {
  const text = $('cmdInput').value;
  window.ecto.send(text);
  $('cmdInput').value = '';
}

window.addEventListener('DOMContentLoaded', () => {
  initSettings();
  applyPhase('idle');
  renderConnections();

  $('connectBtn').onclick = connect;
  $('disconnectBtn').onclick = () => window.ecto.disconnect();
  $('openLogsBtn').onclick = () => window.ecto.openLogs();
  $('openLogsBtn2').onclick = () => window.ecto.openLogs();
  $('clearBtn').onclick = () => { $('console').innerHTML = ''; };
  $('sendBtn').onclick = sendCmd;
  $('enterBtn').onclick = () => window.ecto.enter();
  $('cmdInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') sendCmd(); });

  $('settingsBtn').onclick = () => { $('settingsOverlay').style.display = 'flex'; };
  $('settingsClose').onclick = () => { $('settingsOverlay').style.display = 'none'; };
  $('settingsSave').onclick = async () => {
    await persist();
    const f = $('savedFlash');
    f.style.display = 'block';
    setTimeout(() => { f.style.display = 'none'; }, 1800);
  };
  $('sshPassword').addEventListener('input', updateNoPwHint);
  document.querySelectorAll('.seg-btn').forEach((b) => {
    b.onclick = () => setSegActive(b.dataset.le);
  });
  $('settingsOverlay').addEventListener('click', (e) => {
    if (e.target === $('settingsOverlay')) $('settingsOverlay').style.display = 'none';
  });

  // IPC events from main
  window.ecto.on('phase', applyPhase);
  window.ecto.on('log', addLine);
  window.ecto.on('bytes', (n) => { $('bytes').textContent = `${n} байт`; });
  window.ecto.on('reset-connections', () => { connections.clear(); renderConnections(); });
  window.ecto.on('conn-new', (c) => { connections.set(c.id, c); renderConnections(); });
  window.ecto.on('conn-update', (u) => {
    const c = connections.get(u.id);
    if (c) { c.bytes = u.bytes; renderConnections(); }
  });
});
