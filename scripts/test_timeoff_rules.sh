#!/bin/bash
#
# Compiles and RUNS the real Time Off rule types the app ships.
#
# The sources below are the SAME files Xcode builds — not copies, not a
# paraphrase in another language. That distinction is the whole point: this arc
# once "verified" a rule by reimplementing it in Python and testing that, and the
# operator's verdict was that the logic was fake and did not do anything.
#
# main.swift naming: Swift only executes top-level code from a file with that
# name, so the harness is copied in as main.swift rather than compiled by its own.
set -e
cd "$(dirname "$0")/.."
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
cp scripts/test_timeoff_rules.swift "$BUILD/main.swift"
swiftc -O -o "$BUILD/run" \
  "Iconik Employee/TimeOff/TimeOffRules.swift" \
  "$BUILD/main.swift"
"$BUILD/run"
