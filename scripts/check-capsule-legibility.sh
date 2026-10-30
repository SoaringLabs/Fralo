#!/bin/bash
set -euo pipefail

# Renders the viewing capsule over every backdrop, appearance and accessibility setting,
# captures the matrix window and fails if any capsule edge or readout is too faint.
# Needs Screen Recording permission for the terminal that runs it.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$("$project_root/scripts/run-workbench-preview.sh" --build-only | tail -1)"
work="$(mktemp -d "${TMPDIR:-/tmp}/fralo-capsule.XXXXXX")"
report="$work/report.json"
capture="${1:-$work/capsule-matrix.png}"

env FRALO_SETTINGS_PATH="$work/settings.json" "$bundle/Contents/MacOS/FraloApp" \
  --workbench-preview --capsule-matrix="$report" >/dev/null 2>&1 &
app=$!
trap 'kill $app 2>/dev/null || true' EXIT
for _ in $(seq 1 100); do [[ -s "$report" ]] && break; sleep 0.2; done
[[ -s "$report" ]] || { echo "The matrix did not report its layout" >&2; exit 2; }
window="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["window"])' "$report")"
screencapture -x -o -l "$window" "$capture"
echo "Capture: $capture"
swift "$project_root/scripts/measure-capsule-legibility.swift" "$report" "$capture"
