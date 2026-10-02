const { app, BrowserWindow, dialog, ipcMain, Menu, Notification, screen, shell } = require('electron');
const { autoUpdater } = require('electron-updater');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

if (process.platform === 'linux') {
  // The pet only draws small 2D sprite frames. Avoid GPU driver crashes on
  // Linux desktops and use Electron's software rendering path.
  app.disableHardwareAcceleration();
}

const WIDTH = 96;
const HEIGHT = 104;
const rand = (min, max) => min + Math.random() * (max - min);
const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
let window;
let timer;
let lastTick = performance.now() / 1000;
let readyToDraw = false;
let updateReady = false;
let checkingForUpdate = false;
let lastUpdateError = null;
let manualUpdateCheck = false;
let positioningAvailable = true;

const state = {
  x: 0, y: 0, activity: 'idle', age: 0, duration: 1.8,
  facingRight: true, paused: false, firstJourney: true,
  walkTarget: 0, walkSpeed: 0, walkMaxSpeed: 50, walkPhase: 0,
  headingForEdge: false, forcedDirection: null, consecutiveActions: 0,
  nextFlip: 0, nextWave: 0, nextLaugh: 0, nextRest: 0,
  dragStart: null, dragOffset: null, dragging: false,
  carryX: 0, carryY: 0, vx: 0, vy: 0, bounces: 0,
  height: 0, impactX: 0
};

function display() {
  return screen.getDisplayNearestPoint({ x: Math.round(state.x + WIDTH / 2), y: Math.round(state.y + HEIGHT / 2) });
}
function area() { return display().workArea; }
function ground() { const a = area(); return a.y + a.height - HEIGHT - 24; }
function bounds() { const a = area(); return { min: a.x - 12, max: a.x + a.width - WIDTH + 12 }; }
function begin(activity, duration) {
  state.activity = activity;
  state.age = 0;
  state.duration = duration;
  if (activity !== 'walk') state.walkSpeed = 0;
}
function startWalk() {
  const b = bounds();
  state.facingRight = state.forcedDirection ?? Math.random() < 0.5;
  state.forcedDirection = null;
  state.headingForEdge = state.firstJourney || Math.random() < 0.34;
  state.firstJourney = false;
  state.walkMaxSpeed = rand(30, 54);
  if (state.headingForEdge) {
    state.walkTarget = state.facingRight ? b.max : b.min;
  } else {
    const distance = Math.round(rand(90, Math.min(330, Math.max(100, b.max - b.min))) / 20) * 20;
    state.walkTarget = clamp(state.x + (state.facingRight ? distance : -distance), b.min + 20, b.max - 20);
  }
  if (Math.abs(state.walkTarget - state.x) < 25) {
    state.facingRight = !state.facingRight;
    state.walkTarget = clamp(state.x + (state.facingRight ? 100 : -100), b.min, b.max);
  }
  state.consecutiveActions = 0;
  state.walkPhase = 0;
  begin('walk', 120);
}
function chooseAction() {
  state.consecutiveActions++;
  const now = performance.now() / 1000;
  if (now >= state.nextFlip) { state.nextFlip = now + rand(35, 60); return begin('backflip', 1.15); }
  if (now >= state.nextLaugh) { state.nextLaugh = now + rand(25, 45); return begin('laugh', 1.55); }
  if (now >= state.nextWave) { state.nextWave = now + rand(22, 40); return begin('wave', 1.45); }
  if (now >= state.nextRest) {
    state.nextRest = now + rand(65, 110);
    return Math.random() < 0.3 ? begin('sleep', rand(10, 16)) : begin('rest', rand(4, 7));
  }
  const roll = Math.floor(Math.random() * 100);
  if (roll < 15) begin('idle', rand(1, 2.8));
  else if (roll < 32) begin('think', rand(1.7, 3.5));
  else if (roll < 40) begin('wait', rand(0.9, 1.6));
  else if (roll < 52) begin('look', rand(1.4, 2.2));
  else if (roll < 66) begin('wave', rand(1.1, 1.7));
  else if (roll < 76) { state.nextLaugh = now + rand(25, 45); begin('laugh', 1.55); }
  else if (roll < 83) begin('surprise', 1.35);
  else if (roll < 90) begin('pout', 1.75);
  else if (roll < 96) begin('jump', 0.75);
  else begin('review', rand(1.3, 2.2));
}
function finishActivity() {
  if (state.firstJourney) return startWalk();
  switch (state.activity) {
    case 'walk': return chooseAction();
    case 'bump':
      state.facingRight = !state.facingRight;
      state.consecutiveActions = 1;
      return begin('surprise', 1.35);
    case 'backflip':
      state.nextWave = performance.now() / 1000 + rand(22, 40);
      return begin('wave', 1.35);
    case 'fall': case 'land': return startWalk();
    case 'carry': return;
    default:
      return state.consecutiveActions >= 2 || Math.random() < 0.68 ? startWalk() : chooseAction();
  }
}
function moveWalk(dt) {
  const b = bounds();
  const sign = state.facingRight ? 1 : -1;
  const remaining = Math.max(0, (state.walkTarget - state.x) * sign);
  const brakingSpeed = state.headingForEdge ? state.walkMaxSpeed : Math.sqrt(210 * remaining);
  const desiredSpeed = Math.min(state.walkMaxSpeed, brakingSpeed);
  state.walkSpeed += (desiredSpeed - state.walkSpeed) * (1 - Math.exp(-dt * 6.5));
  const step = state.headingForEdge ? state.walkSpeed * dt : Math.min(state.walkSpeed * dt, remaining);
  state.x += sign * step;
  state.walkPhase += Math.abs(step) * 0.2;
  if (state.x <= b.min || state.x >= b.max) {
    state.x = clamp(state.x, b.min, b.max);
    state.impactX = state.x;
    state.forcedDirection = !state.facingRight;
    begin('bump', 0.9);
  } else if (Math.abs(state.walkTarget - state.x) < 3 && state.walkSpeed < 10) {
    state.x = state.walkTarget;
    chooseAction();
  }
}
function moveCarry(dt) {
  const pointer = screen.getCursorScreenPoint();
  state.carryX = pointer.x - state.dragOffset.x;
  state.carryY = pointer.y - state.dragOffset.y;
  const response = 1 - Math.exp(-dt * 14);
  const oldX = state.x;
  const oldY = state.y;
  state.x += (state.carryX - state.x) * response;
  state.y += (state.carryY - state.y) * response;
  state.vx = (state.x - oldX) / Math.max(dt, 0.001);
  state.vy = (state.y - oldY) / Math.max(dt, 0.001);
}
function moveFall(dt) {
  state.vy += 900 * dt;
  state.x += state.vx * dt;
  state.y += state.vy * dt;
  const b = bounds();
  if (state.x < b.min || state.x > b.max) {
    state.x = clamp(state.x, b.min, b.max);
    state.vx *= -0.45;
  }
  const floor = ground();
  if (state.y >= floor) {
    state.y = floor;
    state.bounces++;
    if (state.bounces <= 2 && Math.abs(state.vy) > 110) state.vy *= -0.31;
    else { state.vy = 0; begin('land', 1.42); }
    state.vx *= 0.72;
  }
  state.height = Math.max(0, floor - state.y);
}
function draw() {
  if (!window || window.isDestroyed() || !readyToDraw) return;
  let bob = 0;
  if (state.activity === 'backflip') {
    const t = clamp(state.age / state.duration, 0, 1);
    bob = -184 * t * (1 - t);
  } else if (state.activity === 'sleep') bob = -0.6 * Math.max(0, Math.sin(state.age * 2.4));
  // Electron rejects NaN and out-of-range coordinates. A temporary display
  // change can make the roaming position invalid; recover on the main screen.
  if (!Number.isFinite(state.x) || !Number.isFinite(state.y + bob)
      || Math.abs(state.x) > 1_000_000 || Math.abs(state.y + bob) > 1_000_000) {
    console.error('Position de la mascotte invalide', {
      x: state.x, y: state.y, bob, activity: state.activity,
      age: state.age, duration: state.duration, walkTarget: state.walkTarget
    });
    const safeArea = screen.getPrimaryDisplay().workArea;
    state.x = safeArea.x + (safeArea.width - WIDTH) / 2;
    state.y = safeArea.y + safeArea.height - HEIGHT - 24;
    state.vx = 0;
    state.vy = 0;
    begin('idle', 1.8);
    bob = 0;
  }
  const x = Math.round(state.x);
  const y = Math.round(state.y + bob);
  const previous = window.getPosition();
  if (positioningAvailable && (previous[0] !== x || previous[1] !== y)) {
    try { window.setPosition(x, y); }
    catch (error) {
      positioningAvailable = false;
      console.error('Déplacement de la mascotte désactivé pour cette session', { x, y, error });
    }
  }
  window.webContents.send('pet-frame', {
    activity: state.activity, age: state.age, duration: state.duration,
    facingRight: state.facingRight, walkPhase: state.walkPhase,
    height: state.height, vy: state.vy
  });
}
function tick() {
  const now = performance.now() / 1000;
  const dt = clamp(now - lastTick, 0, 0.05);
  lastTick = now;
  if (state.paused && !['carry', 'fall', 'land'].includes(state.activity)) return;
  state.age += dt;
  if (state.activity === 'walk') moveWalk(dt);
  if (state.activity === 'carry') moveCarry(dt);
  if (state.activity === 'fall') moveFall(dt);
  if (state.activity === 'land') { state.vx *= Math.exp(-9 * dt); state.x = clamp(state.x + state.vx * dt, bounds().min, bounds().max); }
  if (state.activity === 'bump') state.x = state.impactX - (state.facingRight ? 1 : -1) * 14 * (1 - Math.pow(1 - clamp(state.age / 0.35, 0, 1), 3));
  if (state.age >= state.duration) finishActivity();
  draw();
}
function handlePointer(type) {
  const point = screen.getCursorScreenPoint();
  if (type === 'down') {
    state.dragStart = point;
    state.dragOffset = { x: point.x - state.x, y: point.y - state.y };
    state.dragging = false;
  } else if (type === 'move' && state.dragStart && !state.dragging) {
    if (Math.hypot(point.x - state.dragStart.x, point.y - state.dragStart.y) > 3) {
      state.dragging = true;
      state.bounces = 0;
      begin('carry', 120);
    }
  } else if (type === 'up') {
    state.dragStart = null;
    if (state.dragging) {
      state.dragging = false;
      state.vx = clamp(state.vx, -450, 450);
      state.vy = clamp(state.vy, -550, 550);
      begin('fall', 120);
    }
  }
}
function action(activity, duration) {
  state.paused = false;
  state.firstJourney = false;
  begin(activity, duration);
}
function showMenu() {
  action('context', 1.2);
  const items = [
    { label: `Codex Promenade ${app.getVersion()}`, enabled: false },
    { type: 'separator' },
    { label: 'Faire un salto arrière', click: () => action('backflip', 1.15) },
    { label: 'Saluer', click: () => action('wave', 1.45) },
    { label: 'Rire', click: () => action('laugh', 1.55) },
    { label: 'Être surpris', click: () => action('surprise', 1.35) },
    { label: 'Bouder', click: () => action('pout', 1.75) },
    { label: 'Se reposer', click: () => action('rest', 6) },
    { label: 'Dormir', click: () => action('sleep', 14) },
    { type: 'separator' },
    { label: state.paused ? 'Reprendre' : 'Pause', click: () => { state.paused = !state.paused; } },
    { label: 'Ouvrir ChatGPT', click: () => shell.openExternal('https://chatgpt.com/') },
    { type: 'separator' },
    updateReady
      ? { label: 'Installer la mise à jour et relancer', click: () => autoUpdater.quitAndInstall() }
      : { label: checkingForUpdate ? 'Recherche en cours…' : 'Rechercher les mises à jour', enabled: !checkingForUpdate,
          click: () => checkForUpdates(true) },
    { label: 'Quitter', click: () => app.quit() }
  ];
  Menu.buildFromTemplate(items).popup({ window });
}
function checkForUpdates(manual = false) {
  if (!app.isPackaged || checkingForUpdate || updateReady) return;
  manualUpdateCheck = manual;
  checkingForUpdate = true;
  lastUpdateError = null;
  autoUpdater.checkForUpdates().catch((error) => {
    checkingForUpdate = false;
    lastUpdateError = error;
  });
}
function setupUpdater() {
  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = true;
  autoUpdater.on('checking-for-update', () => { checkingForUpdate = true; });
  autoUpdater.on('update-available', () => { checkingForUpdate = false; });
  autoUpdater.on('update-not-available', () => {
    checkingForUpdate = false;
    if (manualUpdateCheck) dialog.showMessageBox(window, { message: 'Codex Promenade est à jour.' });
    manualUpdateCheck = false;
  });
  autoUpdater.on('update-downloaded', () => {
    checkingForUpdate = false;
    manualUpdateCheck = false;
    updateReady = true;
    if (Notification.isSupported()) new Notification({ title: 'Codex Promenade', body: 'Mise à jour prête. Elle sera installée à la fermeture de l’application.' }).show();
  });
  autoUpdater.on('error', (error) => {
    checkingForUpdate = false;
    lastUpdateError = error;
    if (manualUpdateCheck) dialog.showErrorBox('Mise à jour indisponible', error.message);
    manualUpdateCheck = false;
  });
  setTimeout(() => checkForUpdates(), 20_000);
  setInterval(() => checkForUpdates(), 6 * 60 * 60 * 1000);
}

app.whenReady().then(() => {
  if (process.platform === 'darwin') app.dock.hide();
  const a = screen.getPrimaryDisplay().workArea;
  state.x = Math.round(a.x + (a.width - WIDTH) / 2);
  state.y = Math.round(a.y + a.height - HEIGHT - 24);
  const now = performance.now() / 1000;
  state.nextFlip = now + rand(18, 32);
  state.nextWave = now + rand(9, 18);
  state.nextLaugh = now + rand(12, 24);
  state.nextRest = now + rand(35, 60);
  window = new BrowserWindow({
    x: state.x, y: state.y, width: WIDTH, height: HEIGHT,
    frame: false, transparent: true, hasShadow: false,
    resizable: false, maximizable: false, fullscreenable: false,
    alwaysOnTop: true, skipTaskbar: true, show: false,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: true, nodeIntegration: false }
  });
  window.setMenu(null);
  if (process.platform === 'darwin') window.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', (event) => event.preventDefault());
  window.loadFile(path.join(__dirname, 'index.html'));
  ipcMain.handle('pet-asset-url', (event, name) => {
    if (event.sender !== window.webContents || !/^codex-[a-z0-9-]+\.(png|webp)$/.test(name)) return null;
    const folder = app.isPackaged ? path.join(process.resourcesPath, 'sprites') : path.join(__dirname, '..', 'Resources');
    return pathToFileURL(path.join(folder, name)).href;
  });
  ipcMain.on('pet-action', (event, type) => {
    if (event.sender !== window.webContents) return;
    if (['down', 'move', 'up'].includes(type)) handlePointer(type);
    else if (type === 'menu') showMenu();
    else if (type === 'double' && !state.dragging) shell.openExternal('https://chatgpt.com/');
    else if (type === 'assets-ready') {
      readyToDraw = true;
      window.showInactive();
      draw();
      if (process.env.CODEX_SMOKE_TEST === '1') {
        console.log('SPRITES_READY');
        console.log(`OZONE_PLATFORM=${app.commandLine.getSwitchValue('ozone-platform')}`);
        console.log(`WINDOW_VISIBLE=${window.isVisible()}`);
      }
    }
    else if (type === 'assets-error') dialog.showErrorBox('Sprites introuvables', 'Les images de Codex Promenade manquent dans cette installation.');
  });
  timer = setInterval(tick, 1000 / 60);
  if (app.isPackaged) setupUpdater();
  screen.on('display-metrics-changed', () => {
    const b = bounds();
    state.x = clamp(state.x, b.min, b.max);
    if (!['carry', 'fall'].includes(state.activity)) state.y = ground();
    draw();
  });
});

app.on('window-all-closed', () => { clearInterval(timer); app.quit(); });
