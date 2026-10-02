const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('pet', {
  assetUrl(name) {
    return ipcRenderer.invoke('pet-asset-url', name);
  },
  action(type) {
    if (['down', 'move', 'up', 'double', 'menu', 'assets-ready', 'assets-error'].includes(type)) {
      ipcRenderer.send('pet-action', type);
    }
  },
  onFrame(callback) {
    ipcRenderer.on('pet-frame', (_event, frame) => callback(frame));
  }
});
