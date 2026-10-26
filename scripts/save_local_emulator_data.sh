#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
snapshot_dir="$project_dir/.local-emulator-data/snapshot"
cd "$project_dir"

firebase emulators:export --force --only firestore "$snapshot_dir"
printf 'Saved Firestore emulator data to %s\n' "$snapshot_dir"
