const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function pair() {
  const source = fs.readFileSync(path.join(__dirname, '..', 'main.js'), 'utf8');
  const context = {
    performance,
    process: { platform: 'linux', env: process.env },
    Math: Object.assign(Object.create(Math), { random: () => 0 }),
    require(name) {
      if (name === 'electron') return {
        app: { disableHardwareAcceleration() {}, whenReady: () => ({ then() {} }), on() {} },
        screen: { getDisplayNearestPoint: () => ({ workArea: { x: 0, y: 0, width: 1200, height: 800 } }) }
      };
      if (name === 'electron-updater') return { autoUpdater: {} };
      return require(name);
    }
  };
  vm.runInNewContext(`${source}\nglobalThis.pair = [createPet(null, true), createPet(null, true)];`, context);
  return context.pair;
}

test('deux compagnons proches synchronisent leur salut et respectent le délai de reprise', () => {
  const [left, right] = pair();
  left.state.x = 100;
  right.state.x = 178;
  left.state.y = right.state.y = 300;
  left.tick();
  assert.equal(left.state.activity, 'handshake');
  assert.equal(right.state.activity, 'handshake');
  assert.equal(left.state.socialPartner, right);
  assert.equal(right.state.socialPartner, left);
  assert.equal(left.state.facingRight, true);
  assert.equal(right.state.facingRight, false);

  left.finishActivity();
  assert.equal(left.state.activity, 'dance');
  assert.equal(right.state.activity, 'dance');

  left.begin('carry', 120);
  assert.equal(right.state.activity, 'idle');
  assert.equal(left.state.socialPartner, null);
  assert.equal(right.state.socialPartner, null);
  assert.ok(right.state.nextSocial > performance.now() / 1000);
  right.tick();
  assert.equal(right.state.activity, 'idle');
});

test('une conversation et des saltos alternés se terminent par un rire commun', () => {
  for (const kind of ['conversation', 'duoFlip']) {
    const [left, right] = pair();
    left.state.x = 100;
    right.state.x = 178;
    left.state.y = right.state.y = 300;
    left.startSocial(right, kind, performance.now() / 1000);
    assert.equal(left.state.activity, kind);
    assert.equal(right.state.activity, kind);
    left.finishActivity();
    assert.equal(left.state.activity, 'sharedLaugh');
    assert.equal(right.state.activity, 'sharedLaugh');
    right.begin('carry', 120);
    assert.equal(left.state.activity, 'idle');
  }
});

test('le menu crée et retire un compagnon avec sa propre fenêtre', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'main.js'), 'utf8');
  let nextId = 1;
  let menuItems;
  class FakeWindow {
    constructor(options) {
      this.options = options;
      this.webContents = { id: nextId++, setWindowOpenHandler() {}, on() {}, send() {} };
      this.events = {};
    }
    setMenu() {}
    setVisibleOnAllWorkspaces() {}
    loadFile() {}
    on(name, callback) { this.events[name] = callback; }
    close() { this.events.closed?.(); }
    isDestroyed() { return false; }
  }
  const workArea = { x: 0, y: 0, width: 1200, height: 800 };
  const context = {
    performance, process: { platform: 'linux', env: process.env },
    __dirname: path.join(__dirname, '..'), setInterval: () => 1,
    require(name) {
      if (name === 'electron') return {
        app: {
          isPackaged: false, dock: { hide() {} }, getVersion: () => '2.9.0',
          disableHardwareAcceleration() {},
          whenReady: () => ({ then(callback) { context.boot = callback; } }), on() {}
        },
        BrowserWindow: FakeWindow,
        ipcMain: { handle() {}, on() {} },
        Menu: { buildFromTemplate(items) { menuItems = items; return { popup() {} }; } },
        screen: { getPrimaryDisplay: () => ({ workArea }), getDisplayNearestPoint: () => ({ workArea }), on() {} }
      };
      if (name === 'electron-updater') return { autoUpdater: {} };
      return require(name);
    }
  };
  vm.runInNewContext(`${source}\nglobalThis.allPets = pets;`, context);
  context.boot();
  const first = [...context.allPets][0];
  first.showMenu();
  menuItems.find((item) => item.label === 'Ajouter un compagnon').click();
  assert.equal(context.allPets.size, 2);
  const second = [...context.allPets][1];
  assert.notEqual(second.window.webContents.id, first.window.webContents.id);
  assert.equal(first.state.activity, 'handshake');
  assert.equal(second.state.activity, 'handshake');

  first.showMenu();
  menuItems.find((item) => item.label === 'Faire une activité à deux').click();
  assert.ok(['conversation', 'duoFlip', 'sharedLaugh'].includes(first.state.activity));
  assert.equal(second.state.activity, first.state.activity);

  first.showMenu();
  menuItems.find((item) => item.label === 'Ajouter un compagnon').click();
  const third = [...context.allPets][2];
  assert.equal(context.allPets.size, 3);
  assert.notEqual(third.state.x, second.state.x);
  assert.ok(Math.abs(third.state.x - first.state.x) >= 55);

  third.showMenu();
  menuItems.find((item) => item.label === 'Retirer ce compagnon').click();
  second.showMenu();
  menuItems.find((item) => item.label === 'Retirer ce compagnon').click();
  assert.equal(context.allPets.size, 1);
  assert.equal(first.state.socialPartner, null);
});
