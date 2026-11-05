#!/bin/bash
# Build, install to /Applications, (re)launch. Ad-hoc signed: re-allow any TCC permissions afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
pkill -x Move 2>/dev/null || true
for _ in $(seq 50); do pgrep -xq Move || break; sleep 0.1; done  # let it quit, or `open` fails with -600
rm -rf /Applications/Move.app
cp -R build/Move.app /Applications/Move.app
open /Applications/Move.app
echo "Installed /Applications/Move.app"
