#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-source}" == 'package' ]]; then
  version="$(node -p "require('./package.json').version")"
  pet_command=("dist/Codex Promenade-${version}.AppImage")
else
  # GitHub's temporary runner installs npm files as the unprivileged runner
  # account. Chromium needs its sandbox helper owned by root and setuid.
  node node_modules/electron/install.js
  sudo chown root:root node_modules/electron/dist/chrome-sandbox
  sudo chmod 4755 node_modules/electron/dist/chrome-sandbox
  pet_command=(./node_modules/.bin/electron --ozone-platform=x11 .)
fi

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT
set +e
CODEX_SMOKE_TEST=1 timeout 12s xvfb-run -a "${pet_command[@]}" >"$log_file" 2>&1
status=$?
set -e
cat "$log_file"
if [[ "$status" -ne 124 ]]; then
  echo "L'application a quitté avant la fin du test (code $status)." >&2
  exit 1
fi
if ! grep -q '^SPRITES_READY$' "$log_file"; then
  echo 'Les sprites ne se sont pas chargés.' >&2
  exit 1
fi
if ! grep -q '^OZONE_PLATFORM=x11$' "$log_file" || ! grep -q '^WINDOW_VISIBLE=true$' "$log_file"; then
  echo 'La fenêtre Linux n’a pas démarré sur X11 ou reste invisible.' >&2
  exit 1
fi
if grep -Eq 'Uncaught Exception|Error processing argument|GPU process exited unexpectedly|Failed to send GpuControl.CreateCommandBuffer|XGetWindowAttributes failed' "$log_file"; then
  echo 'Exception détectée pendant le test de démarrage.' >&2
  exit 1
fi
