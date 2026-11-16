#!/usr/bin/env bash
# Baut app.js (Gleam -> JavaScript -> ein gebündeltes Modul für den Browser).
set -euo pipefail
cd "$(dirname "$0")"
gleam build --target javascript
npx --yes esbuild@0.28.2 app_entry.mjs --bundle --minify --format=esm --outfile=app.js
echo "fertig: app.js ($(wc -c < app.js) Bytes)"
