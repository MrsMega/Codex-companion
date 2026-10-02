const canvas = document.getElementById('pet');
const context = canvas.getContext('2d', { alpha: true });
context.imageSmoothingEnabled = false;

const sheets = {
  atlas: 'codex-spritesheet-v6.webp',
  backflip: 'codex-backflip-v3.png',
  carry: 'codex-carry-v5.png',
  context: 'codex-context-v1.png',
  land: 'codex-land-v1.png',
  laugh: 'codex-laugh-v3.png',
  pout: 'codex-pout-v3.png',
  selection: 'codex-selection-v1.png',
  surprise: 'codex-surprise-v3.png',
  rest: 'codex-rest-v1.png',
  doze: 'codex-doze-v1.png',
  sleep: 'codex-sleep-v1.png'
};
const images = {};

Promise.all(Object.entries(sheets).map(async ([key, file]) => new Promise(async (resolve, reject) => {
  const image = new Image();
  image.onload = () => { images[key] = image; resolve(); };
  image.onerror = reject;
  try { image.src = await window.pet.assetUrl(file); }
  catch (error) { reject(error); }
}))).then(() => window.pet.action('assets-ready'))
  .catch(() => window.pet.action('assets-error'));

let lastClickAt = 0;
let pointerDown = false;
canvas.addEventListener('pointerdown', (event) => {
  if (event.button !== 0) return;
  pointerDown = true;
  canvas.setPointerCapture(event.pointerId);
  window.pet.action('down');
});
canvas.addEventListener('pointermove', () => {
  if (pointerDown) window.pet.action('move');
});
function finishPointer(event) {
  if (!pointerDown) return;
  pointerDown = false;
  window.pet.action('up');
  if (event.type === 'pointerup') {
    const now = performance.now();
    if (now - lastClickAt < 360) window.pet.action('double');
    lastClickAt = now;
  }
}
canvas.addEventListener('pointerup', finishPointer);
canvas.addEventListener('pointercancel', finishPointer);
canvas.addEventListener('contextmenu', (event) => {
  event.preventDefault();
  window.pet.action('menu');
});

function cell(sheet, row, col) {
  return [images[sheet], col * 192, row * 208];
}
const walkOrder = [0, 1, 2, 3, 0, 1, 4, 5];
function frameFor(state) {
  const { activity, age, duration, facingRight, walkPhase } = state;
  const progress = Math.min(0.999, age / duration);
  const seq = (speed, count) => Math.floor(age * speed) % count;
  const once = (count) => Math.min(count - 1, Math.floor(progress * count));
  switch (activity) {
    case 'idle': return cell('atlas', 0, seq(4.5, 7));
    case 'walk': return cell('atlas', facingRight ? 1 : 2, walkOrder[Math.floor(walkPhase) % 8]);
    case 'think': return cell('atlas', 7, seq(5, 6));
    case 'wait': return cell('atlas', 6, seq(5, 6));
    case 'look': return cell('atlas', 9 + Math.floor(once(16) / 8), once(16) % 8);
    case 'wave': return cell('atlas', 3, seq(7, 4));
    case 'jump': return cell('atlas', 4, once(5));
    case 'backflip': {
      const index = once(10);
      return index === 0 || index === 9 ? cell('atlas', 0, 0) : cell('backflip', 0, index - 1);
    }
    case 'review': return cell('atlas', 8, seq(5, 6));
    case 'bump': return cell('atlas', 5, once(8));
    case 'laugh': case 'surprise': case 'pout': case 'context': case 'selection':
      return cell(activity, 0, once(6));
    case 'rest': return cell('rest', 0, 0);
    case 'sleep': return cell(age < 0.45 || age > duration - 0.6 ? 'rest' : age < 1.3 ? 'doze' : 'sleep', 0, 0);
    case 'carry': return cell('carry', 0, [0, 1, 0, 2, 0, 3, 4, 5][seq(8, 8)]);
    case 'fall': return cell('atlas', 4, state.height < 22 ? 0 : state.vy > 0 ? 2 : 1);
    case 'land': return cell('land', 0, age < 0.13 ? 0 : age < 0.31 ? 1 : age < 0.65 ? 2 : age < 0.84 ? 3 : age < 1.07 ? 4 : 5);
    default: return cell('atlas', 0, 0);
  }
}

window.pet.onFrame((state) => {
  if (!images.atlas) return;
  const [image, sx, sy] = frameFor(state);
  context.clearRect(0, 0, 192, 208);
  context.drawImage(image, sx, sy, 192, 208, 0, 0, 192, 208);
});
