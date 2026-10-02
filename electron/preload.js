'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('ecto', {
  connect: (cfg) => ipcRenderer.invoke('connect', cfg),
  disconnect: () => ipcRenderer.invoke('disconnect'),
  send: (text) => ipcRenderer.invoke('send', text),
  enter: () => ipcRenderer.invoke('enter'),
  openLogs: () => ipcRenderer.invoke('openLogs'),
  revealConn: (p) => ipcRenderer.invoke('revealConn', p),
  logsPath: () => ipcRenderer.invoke('logsPath'),
  loadSettings: () => ipcRenderer.invoke('loadSettings'),
  saveSettings: (s) => ipcRenderer.invoke('saveSettings', s),
  on: (channel, cb) => ipcRenderer.on(channel, (_e, data) => cb(data))
});
