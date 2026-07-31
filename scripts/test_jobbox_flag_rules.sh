#!/bin/bash
#
# Runs the REAL JobBoxFlagRules.swift — the same file the app compiles — and
# checks its rules. Not a paraphrase in another language: a test that
# reimplements the logic proves nothing about the logic that ships.
#
# The rows here are a local type conforming to `JobBoxFlagRow`, which is the
# protocol the shipped function is written against; `JobBox` itself imports
# Supabase and cannot be compiled in a harness.
#
# NOTE ON SCOPE: the CURRENT-TRIP CUT IS THE CALLER'S, not this function's (see
# the file header) — `flagReading` is handed rows already cut to one trip. So
# "a flag on a previous trip does not count" is not tested here; it cannot be,
# because this function never sees the previous trip.
#
#   ./scripts/test_jobbox_flag_rules.sh
#   ./scripts/test_jobbox_flag_rules.sh --prove-can-fail
#
set -euo pipefail

cd "$(dirname "$0")/.."
RULES="Iconik Employee/JobBox/JobBoxFlagRules.swift"
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

func check(_ name: String, _ actual: Bool, _ expected: Bool) {
    check(name, "\(actual)", "\(expected)")
}

/// A `job_boxes` row, reduced to the three columns the rule reads.
struct Row: JobBoxFlagRow {
    var flagged: Bool
    var flag_note: String?
    var flagged_at: Date?
}

let t0 = Date(timeIntervalSince1970: 1_750_000_000)
func at(_ h: Double) -> Date { t0.addingTimeInterval(h * 3600) }

func plain() -> Row { Row(flagged: false, flag_note: nil, flagged_at: nil) }
func flag(_ note: String?, _ h: Double?) -> Row {
    Row(flagged: true, flag_note: note, flagged_at: h.map(at))
}

func stamp(_ d: Date?) -> String {
    guard let d else { return "nil" }
    return String(format: "%.0f", d.timeIntervalSince(t0) / 3600)
}

// ── A box with nothing to say must say nothing.
print("no flag")
let noRows = JobBoxFlagRules.flagReading(currentTripRows: [Row]())
check("no rows: not flagged", noRows.flagged, false)
check("no rows: no note",     noRows.note ?? "nil", "nil")
check("no rows: no date",     stamp(noRows.flaggedAt), "nil")

let unflagged = JobBoxFlagRules.flagReading(currentTripRows: [plain(), plain(), plain()])
check("no flags: not flagged", unflagged.flagged, false)
check("no flags: no note",     unflagged.note ?? "nil", "nil")
check("no flags: no date",     stamp(unflagged.flaggedAt), "nil")

// ── THE RULE THAT MATTERS. Flagging UPDATEs the box's LATEST row; the next
//    ordinary scan INSERTs a new, unflagged row. Reading the flag off the last
//    row alone would clear a manager's flag the moment the box is scanned again.
print("one flagged row")
let midTrip = JobBoxFlagRules.flagReading(currentTripRows: [
    plain(),
    flag("Lid is cracked", 4),
    plain(),
    plain()
])
check("mid-trip flag survives later scans", midTrip.flagged, true)
check("mid-trip note",  midTrip.note ?? "nil", "Lid is cracked")
check("mid-trip date",  stamp(midTrip.flaggedAt), "4")

let firstRowFlagged = JobBoxFlagRules.flagReading(currentTripRows: [flag("Packed wrong", 0), plain()])
check("first row flagged", firstRowFlagged.flagged, true)
check("first row note",    firstRowFlagged.note ?? "nil", "Packed wrong")

let lastRowFlagged = JobBoxFlagRules.flagReading(currentTripRows: [plain(), flag("Still out", 9)])
check("last row flagged", lastRowFlagged.flagged, true)
check("last row note",    lastRowFlagged.note ?? "nil", "Still out")

// ── Two flags: the NEWEST one is what the box says now.
print("two flagged rows")
let twoFlags = JobBoxFlagRules.flagReading(currentTripRows: [
    flag("Old concern", 2),
    plain(),
    flag("New concern", 30)
])
check("two flags: flagged",   twoFlags.flagged, true)
check("two flags: newest note", twoFlags.note ?? "nil", "New concern")
check("two flags: newest date", stamp(twoFlags.flaggedAt), "30")

// Row ORDER must not decide it — the rows arrive in whatever order the fetch
// returned, and `flagged_at` is the only thing that ranks a flag.
let twoFlagsReversed = JobBoxFlagRules.flagReading(currentTripRows: [
    flag("New concern", 30),
    flag("Old concern", 2)
])
check("order does not decide", twoFlagsReversed.note ?? "nil", "New concern")

// A flagged row with no date at all still flags the box, and loses to a dated
// flag. `flagged_at` is nullable, so this is a real shape.
let undated = JobBoxFlagRules.flagReading(currentTripRows: [flag("No date", nil)])
check("undated flag still flags", undated.flagged, true)
check("undated flag note",        undated.note ?? "nil", "No date")
check("undated flag has no date", stamp(undated.flaggedAt), "nil")

let undatedLoses = JobBoxFlagRules.flagReading(currentTripRows: [
    flag("No date", nil), flag("Dated", 6)
])
check("dated flag wins", undatedLoses.note ?? "nil", "Dated")
check("dated flag date", stamp(undatedLoses.flaggedAt), "6")

// A flag with no note is legitimate — the sheet's note field is optional.
let noteless = JobBoxFlagRules.flagReading(currentTripRows: [plain(), flag(nil, 3)])
check("noteless flag flags",   noteless.flagged, true)
check("noteless flag no note", noteless.note ?? "nil", "nil")
check("noteless flag date",    stamp(noteless.flaggedAt), "3")

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
    "any row of the trip can flag the box|s/let flaggedRows = rows.filter\(\\\\.flagged\)/let flaggedRows = rows.suffix(1).filter(\\\\.flagged)/"
    "an unflagged box reports nothing|s/return \(false, nil, nil\)/return (true, nil, nil)/"
    "the newest flag is the one reported|s/flaggedRows.max/flaggedRows.min/"
    "an undated flag loses to a dated one|s/a.flagged_at \?\? .distantPast/a.flagged_at ?? .distantFuture/"
    "the note comes from the newest flagged row|s/newest\?.flag_note/nil/"
    "the date comes from the newest flagged row|s/newest\?.flagged_at/nil/"
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
