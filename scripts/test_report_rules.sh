#!/bin/bash
# Compiles and runs the REAL rule files the app builds — Reports/*.swift — not a
# paraphrase of them. See the header of test_report_rules.swift for why.
#
# Swift only executes top-level code from a file named main.swift, so the test
# is copied under that name; the files under test compile from their real paths.
set -e
cd "$(dirname "$0")/.."
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
cp scripts/test_report_rules.swift "$BUILD/main.swift"
swiftc -O -o "$BUILD/run" \
  "Iconik Employee/Reports/ReportSchoolLink.swift" \
  "Iconik Employee/Reports/ReportRules.swift" \
  "$BUILD/main.swift"
"$BUILD/run"
