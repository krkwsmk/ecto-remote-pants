'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('ecto', {
  connect: (sid, cfg) => ipcRenderer.invoke('connect', { sid, cfg }),
  disconnect: (sid) => ipcRenderer.invoke('disconnect', { sid }),
  send: (sid, text) => ipcRenderer.invoke('send', { sid, text }),
  enter: (sid) => ipcRenderer.invoke('enter', { sid }),
  closeConn: (sid, connId) => ipcRenderer.invoke('closeConn', { sid, connId }),
  setActiveConn: (sid, connId) => ipcRenderer.invoke('setActiveConn', { sid, connId }),
  closeSession: (sid) => ipcRenderer.invoke('closeSession', { sid }),
  openLogs: () => ipcRenderer.invoke('openLogs'),
  revealConn: (p) => ipcRenderer.invoke('revealConn', p),
  logsPath: () => ipcRenderer.invoke('logsPath'),
  loadSettings: () => ipcRenderer.invoke('loadSettings'),
  saveSettings: (s) => ipcRenderer.invoke('saveSettings', s),
  on: (channel, cb) => ipcRenderer.on(channel, (_e, data) => cb(data))
});
