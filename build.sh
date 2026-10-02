#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$project_dir/.build"
app_dir="$(cd "$project_dir/.." && pwd)/Codex Promenade.app"

mkdir -p "$build_dir/module-cache"
swift -module-cache-path "$build_dir/module-cache" \
  "$project_dir/validate-sprites.swift" "$project_dir/Resources"

swift -module-cache-path "$build_dir/module-cache" "$project_dir/make-icon.swift"

staging_dir="$(mktemp -d "$build_dir/staging.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
chmod 755 "$staging_dir"
mkdir -p "$staging_dir/Contents/MacOS" "$staging_dir/Contents/Resources"
cp "$project_dir/Info.plist" "$staging_dir/Contents/Info.plist"
cp "$project_dir"/Resources/* "$staging_dir/Contents/Resources/"
# Rebuilding must not silently discard an existing Gatekeeper quarantine.
if [[ -d "$app_dir" ]]; then
  quarantine_hex="$(xattr -px com.apple.quarantine "$app_dir" 2>/dev/null || true)"
  if [[ -n "$quarantine_hex" ]]; then
    xattr -wx com.apple.quarantine "$quarantine_hex" "$staging_dir"
  fi
fi

swiftc -module-cache-path "$build_dir/module-cache" -O \
  -framework AppKit -framework ApplicationServices \
  -framework CoreGraphics -framework ImageIO \
  "$project_dir/CodexPromenade.swift" \
  -o "$staging_dir/Contents/MacOS/CodexPromenade"

codesign --force --sign - "$staging_dir"
codesign --verify --deep --strict "$staging_dir"

backup_dir=""
if [[ -d "$app_dir" ]]; then
  backup_dir="$(mktemp -d "$build_dir/previous.XXXXXX")"
  rmdir "$backup_dir"
  mv "$app_dir" "$backup_dir"
fi
if ! mv "$staging_dir" "$app_dir"; then
  if [[ -n "$backup_dir" ]]; then mv "$backup_dir" "$app_dir"; fi
  exit 1
fi
if ! codesign --verify --deep --strict "$app_dir"; then
  rm -rf "$app_dir"
  if [[ -n "$backup_dir" ]]; then mv "$backup_dir" "$app_dir"; fi
  exit 1
fi
if [[ -n "$backup_dir" ]]; then rm -rf "$backup_dir"; fi

printf 'Application construite : %s\n' "$app_dir"
