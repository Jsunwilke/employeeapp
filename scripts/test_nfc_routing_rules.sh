#!/bin/bash
#
# Runs the REAL NFCRoutingRules.swift — the same file the app compiles — and
# checks its rules. Not a paraphrase in another language: a test that
# reimplements the logic proves nothing about the logic that ships.
#
# Every check here was proved able to FAIL before being kept (see
# --prove-can-fail, which reverts each rule in a scratch copy and expects a
# failure). A test that cannot fail is fake evidence in a costume.
#
#   ./scripts/test_nfc_routing_rules.sh
#   ./scripts/test_nfc_routing_rules.sh --prove-can-fail
#
set -euo pipefail

cd "$(dirname "$0")/.."
RULES="Iconik Employee/NFC/NFCRoutingRules.swift"
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

func check(_ name: String, _ actual: Bool, _ expected: Bool) {
    check(name, "\(actual)", "\(expected)")
}

typealias R = NFCRoutingRules

// ── Routing. A scanned tag number decides which of two entirely different
//    screens, tables and vocabularies the scan belongs to, so the boundary is
//    the single highest-consequence rule on this surface.
print("tag routing")
check("3001 is the floor",        R.isJobBoxNumber("3001"), true)
check("3000 is an SD card",       R.isJobBoxNumber("3000"), false)
check("3002 is a job box",        R.isJobBoxNumber("3002"), true)
check("10000 is a job box",       R.isJobBoxNumber("10000"), true)
// Leading zeros still parse; the VALUE decides, not the spelling.
check("0301 is an SD card",       R.isJobBoxNumber("0301"), false)
check("1500 is an SD card",       R.isJobBoxNumber("1500"), false)
// Anything that is not a whole number is an SD card by construction.
check("abc is an SD card",        R.isJobBoxNumber("abc"), false)
check("empty is an SD card",      R.isJobBoxNumber(""), false)
check("3001.5 is an SD card",     R.isJobBoxNumber("3001.5"), false)
check("spaces are an SD card",    R.isJobBoxNumber(" 3001 "), false)
check("negative is an SD card",   R.isJobBoxNumber("-3001"), false)

check("floor constant",           R.jobBoxNumberFloor, 3001)
check("SD range lower",           R.sdCardNumberRange.lowerBound, 1001)
check("SD range upper",           R.sdCardNumberRange.upperBound, 2000)

// ── The left-at-a-job alert. The banner's words must be computed from the
//    threshold, never typed beside it: the shipped copy says "over 12 hours"
//    as a literal while the threshold drops to 5 minutes in debug builds.
print("left-job alert")
check("threshold seconds",  Int(R.leftJobAlertThreshold), 43200)
check("threshold in words", R.leftJobAlertThresholdDescription, "12 hours")
let derived = "\(Int((R.leftJobAlertThreshold / 3600).rounded())) hours"
check("words derive from the constant", R.leftJobAlertThresholdDescription, derived)

// ── The job box ring. A scan pre-selects the NEXT status, and Turned In wraps
//    to Packed because the box is repacked for its next trip.
print("job box status ring")
check("ring is the four stored strings", R.jobBoxStatusRing.joined(separator: "|"),
      "Packed|Picked Up|Left Job|Turned In")
check("packed -> picked up",   R.nextJobBoxStatus(after: "Packed"),    "Picked Up")
check("picked up -> left job", R.nextJobBoxStatus(after: "Picked Up"), "Left Job")
check("left job -> turned in", R.nextJobBoxStatus(after: "Left Job"),  "Turned In")
check("turned in wraps",       R.nextJobBoxStatus(after: "Turned In"), "Packed")
check("unknown -> packed",     R.nextJobBoxStatus(after: "Exploded"),  "Packed")
check("empty -> packed",       R.nextJobBoxStatus(after: ""),          "Packed")
check("case tolerant",         R.nextJobBoxStatus(after: "picked up"), "Left Job")
check("padded tolerant",       R.nextJobBoxStatus(after: "  Left Job "), "Turned In")

// ── The SD ring. TWO variants, because the two shipped paths genuinely differ
//    on what happens to a card coming out of the camera bag. Preserved, not
//    unified (D12).
print("SD status ring — shared steps")
check("ring is five",       R.sdStatusRing.joined(separator: "|"),
      "Job Box|Camera|Envelope|Uploaded|Cleared")
for variant in [R.SDAdvanceVariant.scan, R.SDAdvanceVariant.form] {
    let tag = variant == .scan ? "scan" : "form"
    check("\(tag): job box -> camera",   R.nextSDStatus(after: "Job Box", variant: variant), "Camera")
    check("\(tag): camera -> envelope",  R.nextSDStatus(after: "Camera", variant: variant), "Envelope")
    check("\(tag): envelope -> uploaded", R.nextSDStatus(after: "Envelope", variant: variant), "Uploaded")
    check("\(tag): uploaded -> cleared", R.nextSDStatus(after: "Uploaded", variant: variant), "Cleared")
    check("\(tag): cleared wraps",       R.nextSDStatus(after: "Cleared", variant: variant), "Job Box")
    check("\(tag): unknown -> job box",  R.nextSDStatus(after: "Exploded", variant: variant), "Job Box")
    check("\(tag): empty -> job box",    R.nextSDStatus(after: "", variant: variant), "Job Box")
    check("\(tag): case tolerant",       R.nextSDStatus(after: "camera", variant: variant), "Envelope")
}

print("SD status ring — where the variants differ")
// ScanView filters the side statuses out and then looks the last status up in
// the FILTERED list, so a card in the bag is simply not found and falls to the
// head of the ring.
check("scan: camera bag -> job box", R.nextSDStatus(after: "Camera Bag", variant: .scan), "Job Box")
check("scan: personal -> job box",   R.nextSDStatus(after: "Personal", variant: .scan), "Job Box")
// FormView and ManualEntryView (identical to each other) land them explicitly.
check("form: camera bag -> camera",  R.nextSDStatus(after: "Camera Bag", variant: .form), "Camera")
check("form: personal -> cleared",   R.nextSDStatus(after: "Personal", variant: .form), "Cleared")
check("form: side status case tolerant",
      R.nextSDStatus(after: "camera bag", variant: .form), "Camera")
check("side statuses named",  R.sdSideStatuses.joined(separator: "|"), "Camera Bag|Personal")
check("side statuses are not in the ring",
      R.sdStatusRing.contains { R.sdSideStatuses.map { $0.lowercased() }.contains($0.lowercased()) },
      false)

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
    "the job box floor is inclusive|s/>= jobBoxNumberFloor/> jobBoxNumberFloor/"
    "a non-number routes to SD|s/else \{ return false \}/else { return true }/"
    "the job box ring steps forward|s/\(index \+ 1\) % jobBoxStatusRing/index % jobBoxStatusRing/"
    "an unknown job box status defaults to Packed|s/return jobBoxStatusRing\[0\]/return status/"
    "the SD ring steps forward|s/\(index \+ 1\) % sdStatusRing/index % sdStatusRing/"
    "an unknown SD status defaults to Job Box|s/return sdStatusRing\[0\]/return status/"
    "the form variant's camera-bag landing|s/if key == \"camera bag\" \{ return \"Camera\" \}//"
    "the form variant's personal landing|s/if key == \"personal\" \{ return \"Cleared\" \}//"
    "the scan variant does NOT take the form landings|s/if variant == .form \{/if true {/"
    "the 12-hour threshold|s/TimeInterval = 43200/TimeInterval = 21600/"
    "the banner copy derives from the threshold|s/let hours = leftJobAlertThreshold \/ 3600/let hours = 6.0/"
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
