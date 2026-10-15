'use strict';

const { app, BrowserWindow, ipcMain, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const { Client } = require('ssh2');

let win = null;
const sessions = new Map(); // sid -> Session

const RECONNECT_DELAY_MS = 3000;
const MAX_RETRIES = 5;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function send(channel, payload) {
  if (win && !win.isDestroyed()) win.webContents.send(channel, payload);
}

function settingsFile() { return path.join(app.getPath('userData'), 'settings.json'); }
function loadSettings() { try { return JSON.parse(fs.readFileSync(settingsFile(), 'utf8')); } catch { return {}; } }
function saveSettings(s) {
  try {
    fs.mkdirSync(app.getPath('userData'), { recursive: true });
    fs.writeFileSync(settingsFile(), JSON.stringify(s || {}, null, 2));
    return true;
  } catch { return false; }
}

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

function nowString() { return new Date().toISOString().replace('T', ' ').replace('Z', ''); }

function sanitizePeer(s) { return (s || 'peer').replace(/[^A-Za-z0-9.\-_]/g, '_'); }

function terminatorFor(mode) {
  if (mode === 'cr') return '\r';
  if (mode === 'crlf') return '\r\n';
  return '\n';
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
// Session: one tab = one reverse tunnel
// ---------------------------------------------------------------------------

class Session {
  constructor(sid) {
    this.id = sid;
    this.conn = null;
    this.phase = 'idle';           // idle | connecting | reconnecting | listening | failed
    this.streams = new Map();      // connId -> stream
    this.connCounter = 0;
    this.totalBytes = 0;
    this.sessionDir = null;
    this.sessionLog = null;
    this.lineEnding = 'lf';
    this.activeConnId = null;
    this.userClosed = false;
    this.cfg = null;
    this.retries = 0;
    this.reconnectTimer = null;
  }

  log(kind, text) { send('log', { sid: this.id, kind, text, ts: Date.now() }); }
  setPhase(p) { this.phase = p; send('phase', { sid: this.id, phase: p }); }
  appendSession(line) { try { if (this.sessionLog) this.sessionLog.write(`[${nowString()}] ${line}\n`); } catch {} }

  startLog(port) {
    const dir = path.join(logsRoot(), `session_${port}_${stamp()}`);
    fs.mkdirSync(dir, { recursive: true });
    this.sessionDir = dir;
    try { this.sessionLog = fs.createWriteStream(path.join(dir, 'session.log'), { flags: 'a' }); } catch { this.sessionLog = null; }
    return dir;
  }
  closeLog() { try { if (this.sessionLog) this.sessionLog.end(); } catch {} this.sessionLog = null; }

  // --- connect / disconnect ---

  connect(cfg, isRetry = false) {
    if (this.phase === 'connecting' || this.phase === 'listening') return;

    const port = parseInt(String(cfg.port || '').trim(), 10);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      this.log('error', 'Неверный порт. Введите число от 1 до 65535.');
      return;
    }
    const host = (cfg.host || '').trim();
    const user = (cfg.user || '').trim();
    if (!host || !user) {
      this.log('error', 'Укажите пользователя и хост релея в Настройках.');
      return;
    }

    this.cfg = cfg;
    this.lineEnding = cfg.lineEnding || 'lf';
    this.userClosed = false;
    this.portNum = port;

    if (!isRetry) {
      this.retries = 0;
      this.totalBytes = 0;
      send('bytes', { sid: this.id, bytes: 0 });
      send('reset-connections', { sid: this.id });
      const dir = this.startLog(String(port));
      this.log('info', `Лог сессии: ${dir}`);
      this.appendSession('SYS session start');
    }

    this.setPhase(isRetry ? 'reconnecting' : 'connecting');
    this.log('info', isRetry
      ? `Переподключение к ${user}@${host} (попытка ${this.retries})…`
      : `Подключаюсь к ${user}@${host}…`);

    const conn = new Client();
    this.conn = conn;

    conn.on('ready', () => {
      this.retries = 0;
      this.log('info', 'Аутентификация успешна. Запрашиваю обратный туннель…');
      this.appendSession('SYS ssh authenticated');
      conn.forwardIn('', port, (err) => {
        if (err) {
          this.log('error', `Релей отклонил проброс порта ${port}: ${err.message}`);
          this.appendSession('ERR forwardIn failed: ' + err.message);
          this.fail(true);
          return;
        }
        this.setPhase('listening');
        this.log('info', `Туннель активен на порту ${port}. Жду подключения устройства…`);
        this.appendSession(`SYS tunnel up on port ${port}`);
      });
    });

    conn.on('tcp connection', (info, accept) => { this.handleDeviceConnection(info, accept); });

    conn.on('error', (err) => {
      let msg = err && err.message ? err.message : String(err);
      if (/All configured authentication methods failed/i.test(msg)) {
        msg = 'Аутентификация не удалась. Проверьте пароль/логин в Настройках.';
        this.log('error', `SSH ошибка: ${msg}`);
        this.appendSession('ERR ' + msg);
        this.fail(false); // do not retry bad auth
        return;
      }
      this.log('error', `SSH ошибка: ${msg}`);
      this.appendSession('ERR ' + msg);
      this.fail(true);
    });

    conn.on('close', () => {
      this.conn = null;
      // Mark any still-open connections as closed in the UI.
      this.closeAllStreams('tunnel');
      if (this.userClosed) {
        this.setPhase('idle');
        return;
      }
      if (this.phase === 'listening' || this.phase === 'connecting' || this.phase === 'reconnecting') {
        this.scheduleReconnect();
      }
    });

    try {
      conn.connect({
        host, port: 22, username: user, password: cfg.password || '',
        readyTimeout: 20000, keepaliveInterval: 15000, keepaliveCountMax: 4
      });
    } catch (e) {
      this.log('error', 'Не удалось начать подключение: ' + (e && e.message));
      this.fail(true);
    }
  }

  scheduleReconnect() {
    if (this.userClosed) { this.setPhase('idle'); return; }
    if (this.retries >= MAX_RETRIES) {
      this.log('error', `Туннель потерян. Исчерпаны попытки переподключения (${MAX_RETRIES}).`);
      this.setPhase('failed');
      this.closeLog();
      return;
    }
    this.retries += 1;
    this.setPhase('reconnecting');
    this.log('info', `Связь потеряна. Переподключение через ${RECONNECT_DELAY_MS / 1000} c…`);
    clearTimeout(this.reconnectTimer);
    this.reconnectTimer = setTimeout(() => {
      if (this.userClosed || !this.cfg) return;
      this.connect(this.cfg, true);
    }, RECONNECT_DELAY_MS);
  }

  fail(allowRetry) {
    try { if (this.conn) this.conn.end(); } catch {}
    this.conn = null;
    if (allowRetry && !this.userClosed) {
      this.scheduleReconnect();
    } else {
      this.setPhase('failed');
      this.closeLog();
    }
  }

  disconnect() {
    this.userClosed = true;
    clearTimeout(this.reconnectTimer);
    this.log('info', 'Отключение…');
    this.appendSession('SYS session closed');
    this.closeAllStreams('user');
    try { if (this.conn) this.conn.end(); } catch {}
    this.conn = null;
    this.closeLog();
    this.setPhase('idle');
  }

  dispose() {
    this.userClosed = true;
    clearTimeout(this.reconnectTimer);
    this.closeAllStreams('user');
    try { if (this.conn) this.conn.end(); } catch {}
    this.conn = null;
    this.closeLog();
  }

  // --- device connections ---

  handleDeviceConnection(info, accept) {
    const stream = accept();
    this.connCounter += 1;
    const connId = this.connCounter;
    const peer = `${info.srcIP}:${info.srcPort}`;
    this.streams.set(connId, stream);
    this.activeConnId = connId;

    const startedAt = nowString();
    let file = null;
    let filePath = null;
    let bytes = 0;

    const ensureFile = () => {
      if (file) return;
      const name = `connection_${String(connId).padStart(3, '0')}_${sanitizePeer(peer)}_${stamp()}.log`;
      filePath = this.sessionDir ? path.join(this.sessionDir, name) : path.join(logsRoot(), name);
      try { file = fs.createWriteStream(filePath, { flags: 'a' }); } catch {}
      send('conn-file', { sid: this.id, id: connId, file: filePath });
    };

    send('conn-new', { sid: this.id, id: connId, peer, startedAt, status: 'active', bytes: 0, file: null });
    this.log('control', `Подключение #${connId} от ${peer}`);
    this.appendSession(`NET connection #${connId} from ${peer}`);

    stream.on('data', (data) => {
      ensureFile();
      bytes += data.length;
      try { if (file) file.write(data); } catch {}
      this.totalBytes += data.length;
      send('bytes', { sid: this.id, bytes: this.totalBytes });
      send('conn-update', { sid: this.id, id: connId, bytes, status: 'active' });

      const text = data.toString('utf8').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
      const pieces = text.split('\n');
      pieces.forEach((piece, i) => {
        if (piece === '' && i === pieces.length - 1) return;
        this.log('data', `#${connId} ${sanitizeForDisplay(piece)}`);
      });
    });

    const done = (reason) => {
      try { if (file) file.end(); } catch {}
      this.streams.delete(connId);
      if (this.activeConnId === connId) {
        const remaining = [...this.streams.keys()];
        this.activeConnId = remaining.length ? remaining[remaining.length - 1] : null;
      }
      send('conn-update', { sid: this.id, id: connId, bytes, status: 'closed' });
      this.appendSession(`NET connection #${connId} closed (${bytes} B, ${reason || 'end'})`);
    };
    stream.on('close', () => done('end'));
    stream.on('end', () => done('end'));
    stream.on('error', () => done('error'));
  }

  closeConnection(connId) {
    const stream = this.streams.get(connId);
    if (!stream) return;
    this.log('info', `Обрываю соединение #${connId}…`);
    try { stream.end(); } catch {}
    try { stream.close(); } catch {}
    try { stream.destroy(); } catch {}
  }

  closeAllStreams(reason) {
    for (const [, stream] of this.streams) {
      try { stream.end(); } catch {}
      try { stream.close(); } catch {}
      try { stream.destroy(); } catch {}
    }
    if (reason === 'user') this.streams.clear();
  }

  setActiveConnection(connId) {
    if (this.streams.has(connId)) this.activeConnId = connId;
  }

  writeToDevice(text, display) {
    if (this.phase !== 'listening' || this.activeConnId == null) {
      this.log('error', 'Нет активного подключения устройства — отправлять некуда.');
      return;
    }
    const stream = this.streams.get(this.activeConnId);
    if (!stream) {
      this.log('error', 'Выбранное соединение уже закрыто.');
      return;
    }
    try {
      stream.write(text + terminatorFor(this.lineEnding));
    } catch (e) {
      this.log('error', 'Не удалось отправить: ' + (e && e.message));
      return;
    }
    this.log('sent', `#${this.activeConnId} ${display}`);
    this.appendSession(`TX #${this.activeConnId} ${display}`);
  }
}

function getSession(sid) {
  let s = sessions.get(sid);
  if (!s) { s = new Session(sid); sessions.set(sid, s); }
  return s;
}

// ---------------------------------------------------------------------------
// IPC
// ---------------------------------------------------------------------------

ipcMain.handle('connect', (_e, { sid, cfg }) => { getSession(sid).connect(cfg || {}); });
ipcMain.handle('disconnect', (_e, { sid }) => { getSession(sid).disconnect(); });
ipcMain.handle('send', (_e, { sid, text }) => {
  const t = String(text || '');
  getSession(sid).writeToDevice(t, t === '' ? '⏎' : t);
});
ipcMain.handle('enter', (_e, { sid }) => { getSession(sid).writeToDevice('', '⏎'); });
ipcMain.handle('closeConn', (_e, { sid, connId }) => { getSession(sid).closeConnection(connId); });
ipcMain.handle('setActiveConn', (_e, { sid, connId }) => { getSession(sid).setActiveConnection(connId); });
ipcMain.handle('closeSession', (_e, { sid }) => {
  const s = sessions.get(sid);
  if (s) { s.dispose(); sessions.delete(sid); }
});
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
    width: 1280,
    height: 760,
    minWidth: 820,
    minHeight: 560,
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
  for (const [, s] of sessions) s.dispose();
  app.quit();
});

app.on('before-quit', () => { for (const [, s] of sessions) s.dispose(); });
