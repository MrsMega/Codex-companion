const fs = require('node:fs/promises');
const path = require('node:path');

exports.default = async function afterPack(context) {
  if (context.electronPlatformName !== 'linux') return;

  const name = context.packager.executableName;
  if (!/^[a-z0-9._-]+$/i.test(name)) throw new Error(`Nom d'exécutable Linux invalide : ${name}`);

  const launcher = path.join(context.appOutDir, name);
  await fs.rename(launcher, `${launcher}.bin`);
  // Chromium chooses Wayland or X11 before main.js runs. Pass this flag from
  // the packaged entry point so a desktop pet can move under Xwayland.
  await fs.writeFile(launcher,
    `#!/bin/sh\nexec "$(dirname "$0")/${name}.bin" --ozone-platform=x11 "$@"\n`,
    { mode: 0o755 });
};
