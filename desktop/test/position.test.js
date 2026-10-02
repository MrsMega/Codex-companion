const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadDraw(setPosition) {
  const positions = [];
  const source = fs.readFileSync(path.join(__dirname, '..', 'main.js'), 'utf8');
  const context = {
    console: { error() {} },
    performance,
    process,
    setTimeout,
    setInterval,
    require(name) {
      if (name === 'electron') return {
        app: { commandLine: { appendSwitch() {} }, disableHardwareAcceleration() {}, whenReady: () => ({ then() {} }), on() {} },
        screen: { getPrimaryDisplay: () => ({ workArea: { x: 0, y: 0, width: 1200, height: 800 } }) }
      };
      if (name === 'electron-updater') return { autoUpdater: {} };
      return require(name);
    }
  };
  vm.runInNewContext(`${source}\n` +
    `globalThis.hooks = {
      state, draw,
      ready() {
        readyToDraw = true;
        window = {
          isDestroyed: () => false,
          getPosition: () => [0, 0],
          setPosition: globalThis.recordPosition,
          webContents: { send() {} }
        };
      }
    };`, context);
  context.recordPosition = (x, y) => {
    positions.push([x, y]);
    setPosition?.(x, y);
  };
  context.hooks.ready();
  return { hooks: context.hooks, positions };
}

test('une position invalide ne parvient pas à Electron', () => {
  const { hooks, positions } = loadDraw();
  hooks.state.x = NaN;
  hooks.state.y = 400;
  hooks.draw();
  assert.equal(positions.length, 1);
  assert.deepEqual(positions[0], [552, 672]);
});

test('les coordonnées arrondies à zéro ne transmettent pas -0 à Electron', () => {
  const { hooks, positions } = loadDraw();
  hooks.state.x = -0.4;
  hooks.state.y = 500;
  hooks.draw();
  hooks.state.x = 100;
  hooks.state.y = -0.4;
  hooks.draw();
  assert.deepEqual(positions, [[0, 500], [100, 0]]);
  assert.equal(Object.is(positions[0][0], -0), false);
  assert.equal(Object.is(positions[1][1], -0), false);
});

test('un refus du système arrête les tentatives de déplacement', () => {
  const { hooks, positions } = loadDraw(() => { throw new TypeError('conversion failure'); });
  hooks.state.x = 100;
  hooks.state.y = 500;
  hooks.draw();
  hooks.draw();
  assert.equal(positions.length, 1);
});
