#!/bin/bash
# Compiles and runs the REAL ReportSchoolLink.swift the app builds — not a
# paraphrase of it. See the header of test_report_school_link.swift for why.
#
# Swift only executes top-level code from a file named main.swift, so the test
# is copied under that name; the file under test is compiled from its real path.
set -e
cd "$(dirname "$0")/.."
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
cp scripts/test_report_school_link.swift "$BUILD/main.swift"
swiftc -O -o "$BUILD/run" \
  "Iconik Employee/DesignLab/ReportSchoolLink.swift" \
  "$BUILD/main.swift"
"$BUILD/run"
