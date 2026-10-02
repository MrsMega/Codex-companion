const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadWalk(randomValue = 0) {
  const source = fs.readFileSync(path.join(__dirname, '..', 'main.js'), 'utf8');
  const context = {
    performance,
    process,
    Math: Object.assign(Object.create(Math), { random: () => randomValue }),
    require(name) {
      if (name === 'electron') return {
        app: { commandLine: { appendSwitch() {} }, disableHardwareAcceleration() {}, whenReady: () => ({ then() {} }), on() {} },
        screen: { getDisplayNearestPoint: () => ({ workArea: { x: 0, y: 0, width: 1200, height: 800 } }) }
      };
      if (name === 'electron-updater') return { autoUpdater: {} };
      return require(name);
    }
  };
  vm.runInNewContext(`${source}\nconst pet = createPet(null, true); globalThis.hooks = { state: pet.state, startWalk: pet.startWalk, moveWalk: pet.moveWalk };`, context);
  return context.hooks;
}

test('le premier trajet avance tout droit avec le cycle de marche', () => {
  const { state, startWalk, moveWalk } = loadWalk();
  state.x = 552;
  state.y = 672;
  startWalk();
  assert.equal(state.walkTargetY, state.y);
  const initialX = state.x;
  const initialY = state.y;
  moveWalk(0.05);
  assert.ok(state.x > initialX);
  assert.equal(state.y, initialY);
  assert.ok(state.walkPhase > 0);
});

test('les trajets suivants peuvent aussi rester horizontaux', () => {
  const { state, startWalk, moveWalk } = loadWalk(0.9);
  state.x = 552;
  state.y = 400;
  state.firstJourney = false;
  startWalk();
  assert.equal(state.walkTargetY, 400);
  moveWalk(0.05);
  assert.equal(state.y, 400);
});

test('un trajet peut monter depuis le sol', () => {
  const { state, startWalk, moveWalk } = loadWalk();
  state.x = 552;
  state.y = 672;
  state.firstJourney = false;
  startWalk();
  assert.ok(state.walkTargetY < state.y);
  moveWalk(0.05);
  assert.ok(state.y < 672);
});

test('un trajet depuis le haut redescend et reste dans la zone visible', () => {
  const { state, startWalk, moveWalk } = loadWalk();
  state.x = 552;
  state.y = -12;
  state.firstJourney = false;
  startWalk();
  assert.ok(state.walkTargetY > state.y);
  for (let i = 0; i < 1000 && state.activity === 'walk'; i++) {
    moveWalk(0.05);
    assert.ok(state.y >= -12 && state.y <= 672);
  }
  assert.ok(state.y > -12);
});
