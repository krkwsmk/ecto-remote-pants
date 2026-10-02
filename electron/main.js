'use strict';

const { app, BrowserWindow, ipcMain, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const { Client } = require('ssh2');

let win = null;

// Live state
let conn = null;
let phase = 'idle';            // idle | connecting | listening | failed
let activeStream = null;       // most recent device stream (for sending)
let totalBytes = 0;
let connectionIndex = 0;

// Logging
let sessionDir = null;
let sessionLog = null;         // fs write stream for session.log

// ---------------------------------------------------------------------------
// Settings (stored in userData/settings.json)
// ---------------------------------------------------------------------------

function settingsFile() {
  return path.join(app.getPath('userData'), 'settings.json');
}

function loadSettings() {
  try {
    return JSON.parse(fs.readFileSync(settingsFile(), 'utf8'));
  } catch {
    return {};
  }
}

function saveSettings(s) {
  try {
    fs.mkdirSync(app.getPath('userData'), { recursive: true });
    fs.writeFileSync(settingsFile(), JSON.stringify(s || {}, null, 2));
    return true;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Logs
// ---------------------------------------------------------------------------

function logsRoot() {
  const d = path.join(app.getPath('userData'), 'logs');
  fs.mkdirSync(d, { recursive: true });
  return d;
}

function stamp() {
  const d = new Date();
  const p = (n, l = 2) => String(n).padStart(l, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

function nowString() {
  return new Date().toISOString().replace('T', ' ').replace('Z', '');
}

function sanitizePeer(s) {
  return (s || 'peer').replace(/[^A-Za-z0-9.\-_]/g, '_');
}

function startSession(port) {
  const dir = path.join(logsRoot(), `session_${port}_${stamp()}`);
  fs.mkdirSync(dir, { recursive: true });
  sessionDir = dir;
  connectionIndex = 0;
  try {
    sessionLog = fs.createWriteStream(path.join(dir, 'session.log'), { flags: 'a' });
  } catch {
    sessionLog = null;
  }
  return dir;
}

function appendSession(line) {
  try { if (sessionLog) sessionLog.write(`[${nowString()}] ${line}\n`); } catch {}
}

function closeSession() {
  try { if (sessionLog) sessionLog.end(); } catch {}
  sessionLog = null;
}

// ---------------------------------------------------------------------------
// Renderer messaging
// ---------------------------------------------------------------------------

function send(channel, payload) {
  if (win && !win.isDestroyed()) win.webContents.send(channel, payload);
}

function setPhase(p) {
  phase = p;
  send('phase', p);
}

function pushLine(kind, text) {
  send('log', { kind, text, ts: Date.now() });
}

function sanitizeForDisplay(s) {
  let out = '';
  for (const ch of s) {
    const code = ch.codePointAt(0);
    if (ch === '\t' || code >= 0x20) out += ch;
    else out += '·';
  }
  return out;
}

// ---------------------------------------------------------------------------
// SSH tunnel
// ---------------------------------------------------------------------------

function terminatorFor(mode) {
  if (mode === 'cr') return '\r';
  if (mode === 'crlf') return '\r\n';
  return '\n';
}

let lineEndingMode = 'lf';

function doConnect(cfg) {
  if (phase === 'connecting' || phase === 'listening') return;

  const port = parseInt(String(cfg.port || '').trim(), 10);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    pushLine('error', 'Неверный порт. Введите число от 1 до 65535.');
    return;
  }
  const host = (cfg.host || '').trim();
  const user = (cfg.user || '').trim();
  const password = cfg.password || '';
  lineEndingMode = cfg.lineEnding || 'lf';

  if (!host || !user) {
    pushLine('error', 'Укажите пользователя и хост релея в Настройках.');
    return;
  }

  totalBytes = 0;
  activeStream = null;
  send('bytes', 0);
  send('reset-connections');

  const dir = startSession(String(port));
  pushLine('info', `Лог сессии: ${dir}`);
  appendSession('SYS session start');

  setPhase('connecting');
  pushLine('info', `Подключаюсь к ${user}@${host}…`);

  conn = new Client();

  conn.on('ready', () => {
    pushLine('info', 'Аутентификация успешна. Запрашиваю обратный туннель…');
    appendSession('SYS ssh authenticated');
    conn.forwardIn('', port, (err) => {
      if (err) {
        pushLine('error', `Релей отклонил проброс порта ${port}: ${err.message}`);
        appendSession('ERR forwardIn failed: ' + err.message);
        failConnection();
        return;
      }
      setPhase('listening');
      pushLine('info', `Туннель активен на порту ${port}. Жду подключения устройства…`);
      appendSession(`SYS tunnel up on port ${port}`);
    });
  });

  conn.on('tcp connection', (info, accept) => {
    handleDeviceConnection(info, accept);
  });

  conn.on('error', (err) => {
    let msg = err && err.message ? err.message : String(err);
    if (err && /All configured authentication methods failed/i.test(msg)) {
      msg = 'Аутентификация не удалась. Проверьте пароль/логин в Настройках.';
    }
    pushLine('error', `SSH ошибка: ${msg}`);
    appendSession('ERR ' + msg);
    failConnection();
  });

  conn.on('close', () => {
    if (phase !== 'idle' && phase !== 'failed') {
      pushLine('info', 'Соединение закрыто.');
      appendSession('SYS connection closed');
      setPhase('idle');
    }
    conn = null;
  });

  try {
    conn.connect({
      host,
      port: 22,
      username: user,
      password,
      readyTimeout: 20000,
      keepaliveInterval: 15000,
      keepaliveCountMax: 4
    });
  } catch (e) {
    pushLine('error', 'Не удалось начать подключение: ' + (e && e.message));
    failConnection();
  }
}

function handleDeviceConnection(info, accept) {
  const stream = accept();
  activeStream = stream;
  const peer = `${info.srcIP}:${info.srcPort}`;
  pushLine('control', `Подключение от ${peer}`);
  appendSession(`NET connection from ${peer}`);

  let rec = null; // lazily created on first byte so empty probes don't clutter

  stream.on('data', (data) => {
    if (!rec) rec = openConnectionRecord(peer);
    rec.bytes += data.length;
    try { rec.file.write(data); } catch {}
    totalBytes += data.length;
    send('bytes', totalBytes);
    send('conn-update', { id: rec.id, bytes: rec.bytes });

    const text = data.toString('utf8').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const pieces = text.split('\n');
    pieces.forEach((piece, i) => {
      if (piece === '' && i === pieces.length - 1) return;
      pushLine('data', sanitizeForDisplay(piece));
    });
  });

  const done = () => {
    try { if (rec && rec.file) rec.file.end(); } catch {}
    if (activeStream === stream) activeStream = null;
  };
  stream.on('close', done);
  stream.on('end', done);
  stream.on('error', () => {});
}

function openConnectionRecord(peer) {
  connectionIndex += 1;
  const id = connectionIndex;
  const name = `connection_${String(id).padStart(3, '0')}_${sanitizePeer(peer)}_${stamp()}.log`;
  const filePath = sessionDir ? path.join(sessionDir, name) : path.join(logsRoot(), name);
  let file = null;
  try { file = fs.createWriteStream(filePath, { flags: 'a' }); } catch {}
  const startedAt = nowString();
  send('conn-new', { id, peer, bytes: 0, startedAt, file: filePath });
  pushLine('info', `Соединение #${id}: ${peer} → ${name}`);
  return { id, peer, bytes: 0, file, filePath };
}

function writeToDevice(text, display) {
  if (phase !== 'listening' || !activeStream) {
    pushLine('error', 'Нет активного подключения устройства — отправлять некуда.');
    return;
  }
  try {
    activeStream.write(text + terminatorFor(lineEndingMode));
  } catch (e) {
    pushLine('error', 'Не удалось отправить: ' + (e && e.message));
    return;
  }
  pushLine('sent', display);
  appendSession('TX ' + display);
}

function failConnection() {
  try { if (conn) conn.end(); } catch {}
  conn = null;
  activeStream = null;
  setPhase('failed');
  closeSession();
}

function doDisconnect() {
  pushLine('info', 'Отключение…');
  appendSession('SYS session closed');
  try { if (conn) conn.end(); } catch {}
  conn = null;
  activeStream = null;
  closeSession();
  setPhase('idle');
}

// ---------------------------------------------------------------------------
// IPC
// ---------------------------------------------------------------------------

ipcMain.handle('connect', (_e, cfg) => { doConnect(cfg || {}); });
ipcMain.handle('disconnect', () => { doDisconnect(); });
ipcMain.handle('send', (_e, text) => {
  const t = String(text || '');
  writeToDevice(t, t === '' ? '⏎' : t);
});
ipcMain.handle('enter', () => { writeToDevice('', '⏎'); });
ipcMain.handle('loadSettings', () => loadSettings());
ipcMain.handle('saveSettings', (_e, s) => saveSettings(s));
ipcMain.handle('logsPath', () => logsRoot());
ipcMain.handle('openLogs', () => { shell.openPath(logsRoot()); });
ipcMain.handle('revealConn', (_e, p) => {
  if (p && fs.existsSync(p)) shell.showItemInFolder(p);
  else shell.openPath(logsRoot());
});

// ---------------------------------------------------------------------------
// Window
// ---------------------------------------------------------------------------

function createWindow() {
  win = new BrowserWindow({
    width: 1040,
    height: 680,
    minWidth: 900,
    minHeight: 600,
    backgroundColor: '#05060B',
    title: 'Ecto Remote',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });
  win.setMenuBarVisibility(false);
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  try { if (conn) conn.end(); } catch {}
  app.quit();
});

app.on('before-quit', () => { try { if (conn) conn.end(); } catch {} });
