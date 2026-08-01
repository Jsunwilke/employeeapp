#!/bin/bash
#
# Compiles and RUNS the real time-clock rule types the app ships.
#
# The source below is the SAME file Xcode builds — not a copy, not a paraphrase
# in another language. That distinction is the whole point: this arc once
# "verified" a rule by reimplementing it in Python and testing that, and the
# operator's verdict was that the logic was fake and did not do anything.
#
# These rules decide what lands in payroll, which is why the clock got its own
# phase (AMB plan, D15).
#
# main.swift naming: Swift only executes top-level code from a file with that
# name, so the harness is copied in as main.swift rather than compiled by its own.
set -e
cd "$(dirname "$0")/.."
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
cp scripts/test_timeclock_rules.swift "$BUILD/main.swift"
swiftc -O -o "$BUILD/run" \
  "Iconik Employee/TimeClock/TimeClockRules.swift" \
  "Iconik Employee/Services/PayPeriodSequence.swift" \
  "$BUILD/main.swift"
"$BUILD/run"
