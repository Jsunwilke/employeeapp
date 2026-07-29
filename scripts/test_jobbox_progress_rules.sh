#!/bin/bash
#
# Runs the REAL JobBoxProgressRules.swift — the same file the app compiles — and
# checks its rules. Not a paraphrase in another language: a test that reimplements
# the logic proves nothing about the logic that ships.
#
# Every check here was proved able to FAIL before being kept (see
# --prove-can-fail, which reverts each rule in a scratch copy and expects a
# failure). A test that cannot fail is fake evidence in a costume.
#
#   ./scripts/test_jobbox_progress_rules.sh
#   ./scripts/test_jobbox_progress_rules.sh --prove-can-fail
#
set -euo pipefail

cd "$(dirname "$0")/.."
RULES="Iconik Employee/JobBox/JobBoxProgressRules.swift"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ ! -f "$RULES" ]]; then
  echo "FATAL: cannot find $RULES"
  exit 1
fi

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var passed = 0
var failed = 0

func check(_ name: String, _ actual: String, _ expected: String) {
    if actual == expected {
        passed += 1
    } else {
        failed += 1
        print("  FAIL  \(name)")
        print("        expected: \(expected)")
        print("        actual:   \(actual)")
    }
}

func check(_ name: String, _ actual: Int, _ expected: Int) {
    check(name, "\(actual)", "\(expected)")
}

func check(_ name: String, _ actual: Double, _ expected: Double) {
    check(name, String(format: "%.4f", actual), String(format: "%.4f", expected))
}

func check(_ name: String, _ actual: Bool, _ expected: Bool) {
    check(name, "\(actual)", "\(expected)")
}

let t0 = Date(timeIntervalSince1970: 1_750_000_000)
func at(_ h: Double) -> Date { t0.addingTimeInterval(h * 3600) }

func scan(_ s: JobBoxTripStage, _ who: String?, _ h: Double) -> JobBoxScanPoint {
    JobBoxScanPoint(stage: s, who: who, at: at(h))
}

func stateWord(_ s: JobBoxStageState) -> String {
    switch s {
    case .scanned: return "scanned"
    case .skipped: return "skipped"
    case .pending: return "pending"
    }
}

func shape(_ r: JobBoxProgressReading) -> String {
    JobBoxTripStage.allCases.map { stateWord(r.state($0)).prefix(2) }.joined(separator: "/")
}

// ── The stored-value mapping. Both clients write this column as plain text, so
//    the mapping is a real surface, not a formality.
print("stored value mapping")
check("packed",      JobBoxTripStage(stored: "Packed")?.label ?? "nil",    "Packed")
check("picked up",   JobBoxTripStage(stored: "Picked Up")?.label ?? "nil", "Picked up")
check("left job",    JobBoxTripStage(stored: "Left Job")?.label ?? "nil",  "Left job")
check("turned in",   JobBoxTripStage(stored: "Turned In")?.label ?? "nil", "Turned in")
check("lowercase",   JobBoxTripStage(stored: "turned in")?.label ?? "nil", "Turned in")
check("no space",    JobBoxTripStage(stored: "TurnedIn")?.label ?? "nil",  "Turned in")
check("padded",      JobBoxTripStage(stored: "  Left Job \n")?.label ?? "nil", "Left job")
check("garbage",     JobBoxTripStage(stored: "Exploded").map(\.label) ?? "nil", "nil")
check("empty",       JobBoxTripStage(stored: "").map(\.label) ?? "nil",    "nil")
check("round trip",  JobBoxTripStage(stored: JobBoxTripStage.pickedUp.stored)?.label ?? "nil", "Picked up")

// ── The live shapes, in the proportion they occur.
print("real box shapes")

// 199 boxes: packed and never moved.
let packedOnly = JobBoxProgressReading(log: [scan(.packed, nil, 0)])
check("packedOnly shape",     shape(packedOnly), "sc/pe/pe/pe")
check("packedOnly count",     packedOnly.scannedCount, 1)
check("packedOnly position",  packedOnly.positionFraction, 0.25)
check("packedOnly headline",  packedOnly.headline, "Packed")
check("packedOnly no skips",  packedOnly.skipNote ?? "nil", "nil")
check("packedOnly no holder", packedOnly.holder ?? "nil", "nil")
check("packedOnly unfinished", packedOnly.isFinished, false)

// 47 boxes: out with a photographer.
let out = JobBoxProgressReading(log: [scan(.packed, nil, 0), scan(.pickedUp, "Isaac", 5)])
check("out shape",    shape(out), "sc/sc/pe/pe")
check("out position", out.positionFraction, 0.5)
check("out holder",   out.holder ?? "nil", "Isaac")

// 31 boxes: Packed straight to Turned In. THE case the old bar got wrong — it
// drew four ticks. Position is the end; two stages must read skipped.
let jumped = JobBoxProgressReading(log: [scan(.packed, nil, 0), scan(.turnedIn, "Rylee", 40)])
check("jumped shape",    shape(jumped), "sc/sk/sk/sc")
check("jumped count",    jumped.scannedCount, 2)
check("jumped position", jumped.positionFraction, 1.0)
check("jumped finished", jumped.isFinished, true)
check("jumped note",     jumped.skipNote ?? "nil", "Picked up and Left job never scanned")
check("jumped holder",   jumped.holder ?? "nil", "nil")

// 22 boxes: one stage skipped, single-name note (no Oxford list).
let oneSkip = JobBoxProgressReading(log: [
    scan(.packed, nil, 0), scan(.pickedUp, "Isaac", 4), scan(.turnedIn, "Isaac", 30)
])
check("oneSkip shape", shape(oneSkip), "sc/sc/sk/sc")
check("oneSkip note",  oneSkip.skipNote ?? "nil", "Left job never scanned")

// 35 boxes: the full walk.
let full = JobBoxProgressReading(log: [
    scan(.packed, nil, 0), scan(.pickedUp, "Isaac", 4),
    scan(.leftJob, "Isaac", 26), scan(.turnedIn, "Isaac", 28)
])
check("full shape",    shape(full), "sc/sc/sc/sc")
check("full count",    full.scannedCount, 4)
check("full position", full.positionFraction, 1.0)
check("full no note",  full.skipNote ?? "nil", "nil")

// 4 live boxes have NO Packed row at all.
let neverPacked = JobBoxProgressReading(log: [scan(.leftJob, "Zada", 3), scan(.turnedIn, "Zada", 9)])
check("neverPacked shape", shape(neverPacked), "sk/sk/sc/sc")
check("neverPacked count", neverPacked.scannedCount, 2)
check("neverPacked note",  neverPacked.skipNote ?? "nil", "Packed and Picked up never scanned")

// A box with no rows at all must not claim anything.
let none = JobBoxProgressReading(log: [])
check("empty isEmpty",   none.isEmpty, true)
check("empty shape",     shape(none), "pe/pe/pe/pe")
check("empty position",  none.positionFraction, 0.0)
check("empty headline",  none.headline, "Not scanned")
check("empty count",     none.scannedCount, 0)

// ── Rule 2: a box is reused, so progress means the CURRENT trip.
print("current trip")

// Box 3028's whole season: out and back in June, then packed again in October.
// A naive reading of the group would report the October trip as fully walked.
let reused = JobBoxProgressReading(log: [
    scan(.packed, nil, 0),
    scan(.pickedUp, "Isaac", 5),
    scan(.leftJob, "Isaac", 20),
    scan(.turnedIn, "Isaac", 22),
    scan(.packed, nil, 3000),          // repacked for a new job
    scan(.pickedUp, "Rylee", 3005)
])
check("reused trip length", reused.scans.count, 2)
check("reused shape",       shape(reused), "sc/sc/pe/pe")
check("reused position",    reused.positionFraction, 0.5)
check("reused holder",      reused.holder ?? "nil", "Rylee")
check("reused unfinished",  reused.isFinished, false)

// The cut is the LAST Packed, not the first.
let twicePacked = JobBoxProgressReading(log: [
    scan(.packed, nil, 0), scan(.packed, nil, 100), scan(.turnedIn, "Zada", 140)
])
check("twicePacked length", twicePacked.scans.count, 2)
check("twicePacked shape",  shape(twicePacked), "sc/sk/sk/sc")

// No Packed row means no seam to cut on: the whole log is one trip.
let noSeam = JobBoxProgressReading(log: [scan(.pickedUp, "Isaac", 1), scan(.turnedIn, "Isaac", 8)])
check("noSeam length", noSeam.scans.count, 2)
// Packed and Left job are both skipped here — the box reached Turned In
// without either being scanned.
check("noSeam shape",  shape(noSeam), "sk/sc/sk/sc")
check("noSeam note",   noSeam.skipNote ?? "nil", "Packed and Left job never scanned")

// ── Out-of-order rows. `furthest` is not `latest`, and the live table has both.
print("ordering")

// Rows handed over newest-first must still read correctly.
let reversed = JobBoxProgressReading(log: [
    scan(.turnedIn, "Isaac", 28), scan(.leftJob, "Isaac", 26),
    scan(.pickedUp, "Isaac", 4), scan(.packed, nil, 0)
])
check("reversed shape",    shape(reversed), "sc/sc/sc/sc")
check("reversed position", reversed.positionFraction, 1.0)
check("reversed latest",   reversed.latest?.stage.label ?? "nil", "Turned in")

// A box scanned Left Job AFTER being turned in: latest is leftJob, furthest is
// turnedIn. Position must follow the furthest, or the meter walks backwards.
let backwards = JobBoxProgressReading(log: [
    scan(.packed, nil, 0), scan(.turnedIn, "Rylee", 10), scan(.leftJob, "Rylee", 12)
])
check("backwards latest",   backwards.latest?.stage.label ?? "nil", "Left job")
check("backwards position", backwards.positionFraction, 1.0)
check("backwards shape",    shape(backwards), "sc/sk/sc/sc")

// ── Holder. A Packed row's photographer is NULL on 199 live rows and must never
//    be presented as the person holding the box.
print("holder")
let packedWithGhostName = JobBoxProgressReading(log: [scan(.packed, "Warehouse", 0)])
check("packed never holds", packedWithGhostName.holder ?? "nil", "nil")

let emptyName = JobBoxProgressReading(log: [scan(.packed, nil, 0), scan(.pickedUp, "", 4)])
check("empty name falls back", emptyName.holder ?? "nil", "nil")

let inheritName = JobBoxProgressReading(log: [
    scan(.packed, nil, 0), scan(.pickedUp, "Isaac", 4), scan(.leftJob, nil, 20)
])
check("holder inherited", inheritName.holder ?? "nil", "Isaac")

let finishedHasNoHolder = JobBoxProgressReading(log: [
    scan(.packed, nil, 0), scan(.pickedUp, "Isaac", 4), scan(.turnedIn, "Isaac", 9)
])
check("finished has no holder", finishedHasNoHolder.holder ?? "nil", "nil")

print("")
if failed == 0 {
    print("\(passed) checks passed.")
} else {
    print("\(passed) passed, \(failed) FAILED.")
    exit(1)
}
SWIFT

run_suite() {
  local rules_file="$1"
  local out="$WORK/run"
  if ! swiftc -O -o "$out" "$rules_file" "$WORK/main.swift" 2>"$WORK/compile.log"; then
    echo "COMPILE FAILED"
    cat "$WORK/compile.log"
    return 2
  fi
  "$out"
}

if [[ "${1:-}" == "--prove-can-fail" ]]; then
  echo "Proving each rule's test can fail (reverting rules one at a time)…"
  echo ""
  # Each entry: label, then a perl expression that breaks exactly one rule.
  # A break that still passes means the corresponding checks are vacuous.
  declare -a BREAKS=(
    "position follows latest, not furthest|s/scans\.map\(\\\\\.stage\)\.max\(\)/scans\.last?\.stage/"
    "current trip not cut at last Packed|s/return Array\(ordered\[lastPacked\.\.\.\]\)/return ordered/"
    "trip cut at FIRST Packed|s/lastIndex\(where: \{ \\\$0\.stage == \.packed \}\)/firstIndex\(where: \{ \\\$0\.stage == \.packed \}\)/"
    "skipped treated as pending|s/return \.skipped/return \.pending/"
    "Packed row allowed to be the holder|s/furthest != \.packed, furthest != \.turnedIn/furthest != .turnedIn/"
    "stored mapping made case-sensitive|s/\.lowercased\(\)//"
  )
  fails=0
  for entry in "${BREAKS[@]}"; do
    label="${entry%%|*}"
    expr="${entry#*|}"
    cp "$RULES" "$WORK/broken.swift"
    perl -pi -e "$expr" "$WORK/broken.swift"
    if cmp -s "$RULES" "$WORK/broken.swift"; then
      echo "  UNMATCHED  $label  (the perl expression changed nothing — fix the test, not the rule)"
      fails=$((fails+1))
      continue
    fi
    if run_suite "$WORK/broken.swift" >/dev/null 2>&1; then
      echo "  NOT PROVEN $label  (suite still passed with the rule reverted)"
      fails=$((fails+1))
    else
      echo "  proven     $label"
    fi
  done
  echo ""
  if [[ $fails -gt 0 ]]; then
    echo "$fails rule(s) are not covered by a failing test."
    exit 1
  fi
  echo "Every rule above is covered by a test that fails without it."
  exit 0
fi

run_suite "$RULES"
