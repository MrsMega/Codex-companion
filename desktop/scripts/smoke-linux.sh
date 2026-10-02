#!/usr/bin/env bash
set -euo pipefail

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
if grep -Eq 'Uncaught Exception|Error processing argument' "$log_file"; then
  echo 'Exception détectée pendant le test de démarrage.' >&2
  exit 1
fi
