#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
snapshot_dir="$project_dir/.local-emulator-data/snapshot"
cd "$project_dir"

npm --prefix functions run build

if [ -f "$snapshot_dir/firebase-export-metadata.json" ]; then
  printf 'Restoring saved local Firestore data.\n'
  firebase emulators:start --project heatwatch-nv \
    --only functions,firestore \
    --import "$snapshot_dir" \
    --export-on-exit "$snapshot_dir"
else
  printf 'No saved local data yet. Start emulators, then seed centers in '
  printf 'another Terminal with: npm --prefix functions run centers:seed-local\n'
  firebase emulators:start --project heatwatch-nv \
    --only functions,firestore \
    --export-on-exit "$snapshot_dir"
fi
