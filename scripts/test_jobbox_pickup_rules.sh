#!/bin/bash
#
# Runs the REAL JobBoxPickupRules.swift — the same file the app compiles — and
# checks its rules. Same harness idea as test_jobbox_progress_rules.sh: the
# logic that ships is the logic under test, and --prove-can-fail reverts each
# rule in a scratch copy and expects the suite to fail.
#
#   ./scripts/test_jobbox_pickup_rules.sh
#   ./scripts/test_jobbox_pickup_rules.sh --prove-can-fail
#
set -euo pipefail

cd "$(dirname "$0")/.."
RULES="Iconik Employee/JobBox/JobBoxPickupRules.swift"
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

func inherit(last: (status: String, school: String, shift: String)?,
             newStatus: String, school: String) -> String {
    JobBoxPickupRules.inheritableShiftUid(
        lastStatus: last?.status, lastSchool: last?.school, lastShiftUid: last?.shift,
        newStatus: newStatus, selectedSchool: school
    ) ?? "nil"
}

func warn(box: String, target: String?, school: String,
          packed: String?, lookupFailed: Bool = false,
          lastStatus: String? = nil, lastSchool: String? = nil) -> String {
    let w = JobBoxPickupRules.pickupWarning(
        scannedBox: box, targetShiftUid: target, selectedSchool: school,
        packedBoxNumber: packed, packedLookupFailed: lookupFailed,
        lastStatus: lastStatus, lastSchool: lastSchool
    )
    switch w {
    case nil: return "none"
    case .wrongBox(let s, let p, _): return "wrongBox \(s)/\(p)"
    case .nothingPacked: return "nothingPacked"
    case .noJobLink: return "noJobLink"
    }
}

// ── Inheritance: only within the current trip.
print("inheritance")

// Normal trip: pickup after a same-school pack inherits the pack's job.
check("pickup after same-school pack inherits",
      inherit(last: ("Packed", "Pinckneyville Jr High 5-8", "shiftA"),
              newStatus: "Picked Up", school: "Pinckneyville Jr High 5-8"), "shiftA")

// THE live defect: pickup after a TURNED IN record (previous trip is over)
// must inherit nothing, even at the same school.
check("pickup after turned-in inherits nothing",
      inherit(last: ("Turned In", "Mt Vernon High", "shiftMV"),
              newStatus: "Picked Up", school: "Mt Vernon High"), "nil")

// Pickup for a DIFFERENT school than the last record: no quiet attach to the
// other school's job.
check("pickup for different school inherits nothing",
      inherit(last: ("Packed", "Mt Vernon High", "shiftMV"),
              newStatus: "Picked Up", school: "Pinckneyville Jr High 5-8"), "nil")

// Left Job / Turned In continue the trip regardless of the school text
// (Turned In flows rewrite school to the studio on purpose).
check("left job inherits within trip",
      inherit(last: ("Picked Up", "Pinckneyville Jr High 5-8", "shiftA"),
              newStatus: "Left Job", school: "Pinckneyville Jr High 5-8"), "shiftA")
check("turn-in inherits despite studio school",
      inherit(last: ("Left Job", "Pinckneyville Jr High 5-8", "shiftA"),
              newStatus: "Turned In", school: "Iconik"), "shiftA")
check("turn-in after turn-in inherits nothing",
      inherit(last: ("Turned In", "Iconik", "shiftA"),
              newStatus: "Turned In", school: "Iconik"), "nil")

// A Packed scan never inherits — packing STARTS a trip.
check("packing never inherits",
      inherit(last: ("Turned In", "Iconik", "shiftOld"),
              newStatus: "Packed", school: "Anywhere"), "nil")

// Empty or missing history yields nothing.
check("empty shift uid inherits nothing",
      inherit(last: ("Packed", "X", ""), newStatus: "Picked Up", school: "X"), "nil")
check("no history inherits nothing",
      inherit(last: nil, newStatus: "Picked Up", school: "X"), "nil")

// ── Pickup warning: compare against what was packed for the target job.
print("warning")

// Right box for the job: silent.
check("matching box is silent",
      warn(box: "3033", target: "shiftE", school: "Elem", packed: "3033"), "none")

// THE typo case: box 3005 in hand, box 305 packed for the job.
check("mismatch warns with both numbers",
      warn(box: "3005", target: "shiftJH", school: "Jr High", packed: "305"),
      "wrongBox 3005/305")

// Job has no packed record at all.
check("no packed record warns",
      warn(box: "3005", target: "shiftJH", school: "Jr High", packed: nil), "nothingPacked")

// No job link, and the box's history points somewhere else: warn — the pickup
// would be invisible to every tracker (or worse, belongs to another job).
check("no link after turned-in warns",
      warn(box: "3005", target: nil, school: "Jr High", packed: nil,
           lastStatus: "Turned In", lastSchool: "Mt Vernon High"), "noJobLink")
check("no link, different school warns",
      warn(box: "3005", target: nil, school: "Jr High", packed: nil,
           lastStatus: "Packed", lastSchool: "Mt Vernon High"), "noJobLink")
check("no link, no history warns",
      warn(box: "3005", target: "", school: "Jr High", packed: nil), "noJobLink")

// But an unlinked SAME-SCHOOL pack is the office's routine (58 of the last 66
// live packs carry no session) — nothing is wrong with the pickup, stay silent.
check("unlinked same-school pack is silent",
      warn(box: "3005", target: nil, school: "Jr High", packed: nil,
           lastStatus: "Packed", lastSchool: "Jr High"), "none")

// A failed lookup must fail OPEN — never accuse on a network blink.
check("lookup failure is silent",
      warn(box: "3005", target: "shiftJH", school: "Jr High", packed: nil, lookupFailed: true), "none")

// The photographer reads the message — the words carry the box numbers.
let mismatch = JobBoxPickupRules.pickupWarning(
    scannedBox: "3005", targetShiftUid: "shiftJH", selectedSchool: "Pinckneyville Jr High 5-8",
    packedBoxNumber: "305", packedLookupFailed: false, lastStatus: nil, lastSchool: nil
)
check("mismatch message names both boxes",
      mismatch?.message ?? "nil",
      "This is box 3005, but box 305 was packed for Pinckneyville Jr High 5-8. Make sure you have the right box.")
let unlinked = JobBoxPickupRules.pickupWarning(
    scannedBox: "3005", targetShiftUid: nil, selectedSchool: "Jr High",
    packedBoxNumber: nil, packedLookupFailed: false, lastStatus: "Turned In", lastSchool: "Mt Vernon High"
)
check("no-link message names last location",
      unlinked?.message ?? "nil",
      "This pickup isn't linked to a session, so the job's tracker won't show it. The box was last at Mt Vernon High. Go back and select a session, or save without one.")

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
  declare -a BREAKS=(
    "turned-in no longer ends a trip|s/guard \(lastStatus \?\? \"\"\)\.lowercased\(\) != \"turned in\" else \{ return nil \}//"
    "school check dropped from pickups|s/guard \(lastSchool \?\? \"\"\) == selectedSchool else \{ return nil \}//"
    "mismatch compare inverted|s/if packedBoxNumber == scannedBox \{ return nil \}/if packedBoxNumber != scannedBox { return nil }/"
    "lookup failure accuses anyway|s/if packedLookupFailed \{ return nil \}//"
    "missing job link goes silent|s/return \.noJobLink\(lastSchool: lastSchool\)/return nil/"
    "same-school routine pack warns anyway|s/lastSchool == selectedSchool/lastSchool != selectedSchool/"
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
    # A compile failure is NOT proof — the mutation must produce a program the
    # tests catch, not a program that doesn't build.
    set +e
    run_suite "$WORK/broken.swift" >/dev/null 2>&1
    rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
      echo "  NOT PROVEN $label  (suite still passed with the rule reverted)"
      fails=$((fails+1))
    elif [[ $rc -eq 2 ]]; then
      echo "  NOT PROVEN $label  (mutation broke the build — rewrite it to compile)"
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
