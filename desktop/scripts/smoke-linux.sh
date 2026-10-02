#!/usr/bin/env bash
set -euo pipefail

# GitHub's temporary runner installs npm files as the unprivileged runner
# account. Chromium needs its sandbox helper owned by root and setuid.
node node_modules/electron/install.js
sudo chown root:root node_modules/electron/dist/chrome-sandbox
sudo chmod 4755 node_modules/electron/dist/chrome-sandbox

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT
set +e
CODEX_SMOKE_TEST=1 timeout 12s xvfb-run -a ./node_modules/.bin/electron . >"$log_file" 2>&1
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
if grep -Eq 'Uncaught Exception|Error processing argument|GPU process exited unexpectedly|Failed to send GpuControl.CreateCommandBuffer' "$log_file"; then
  echo 'Exception détectée pendant le test de démarrage.' >&2
  exit 1
fi
