const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const afterPack = require('../scripts/after-pack.js').default;

test('le lancement Linux transmet X11 avant le démarrage d’Electron', async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-launcher-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const executable = path.join(dir, 'codex-promenade');
  fs.writeFileSync(executable, '#!/bin/sh\nprintf "<%s>\\n" "$@"\n', { mode: 0o755 });

  await afterPack({ electronPlatformName: 'linux', appOutDir: dir,
    packager: { executableName: 'codex-promenade' } });

  const result = spawnSync(executable, ['--disable-gpu', 'une valeur'], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, '<--ozone-platform=x11>\n<--disable-gpu>\n<une valeur>\n');
});
