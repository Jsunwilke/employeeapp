#!/bin/bash
#
# Runs the REAL Class Groups rules — Iconik Employee/Class Groups/ClassGroupsRules.swift
# compiled alongside the REAL Class Groups/Models/ClassGroupModels.swift, the same
# two files Xcode builds. Not a paraphrase in another language: a test that
# reimplements the logic proves nothing about the logic that ships.
#
# Every check here was proved able to FAIL before being kept (see
# --prove-can-fail, which reverts each rule in a scratch copy and expects a
# failure). A test that cannot fail is fake evidence in a costume.
#
#   ./scripts/test_classgroups_rules.sh
#   ./scripts/test_classgroups_rules.sh --prove-can-fail
#
set -euo pipefail

cd "$(dirname "$0")/.."
RULES="Iconik Employee/Class Groups/ClassGroupsRules.swift"
MODELS="Iconik Employee/Class Groups/Models/ClassGroupModels.swift"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for f in "$RULES" "$MODELS"; do
  if [[ ! -f "$f" ]]; then
    echo "FATAL: cannot find $f"
    exit 1
  fi
done

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

let groups = ClassGroupJobType.classGroups
let candids = ClassGroupJobType.classCandids
let clubs = ClassGroupJobType.clubs

// ---------------------------------------------------------------------------
// THE ROW TITLE. Teacher is OPTIONAL — only the grade is required by the form —
// and the old row concatenated "\(grade) - \(teacher)" unconditionally, so an
// unrecorded teacher rendered a dangling dash.
print("the row title")

check("both names, em dash",
      ClassGroupsRules.rowTitle(grade: "3rd Grade", teacher: "Mrs. Alvarez"),
      "3rd Grade — Mrs. Alvarez")
check("no teacher is the grade ALONE",
      ClassGroupsRules.rowTitle(grade: "Kindergarten", teacher: ""),
      "Kindergarten")
check("whitespace-only teacher is still no teacher",
      ClassGroupsRules.rowTitle(grade: "Kindergarten", teacher: "   "),
      "Kindergarten")
check("a newline-only teacher is no teacher",
      ClassGroupsRules.rowTitle(grade: "Kindergarten", teacher: "\n \t"),
      "Kindergarten")
// CLUB VOCABULARY: the club name lives in `grade` and the advisor in `teacher`,
// so this is the same rule reading a different pair of nouns — and it is where
// the defect looked worst ("Debate Team - ").
check("a club with an advisor",
      ClassGroupsRules.rowTitle(grade: "Robotics Club", teacher: "Mr. Duarte"),
      "Robotics Club — Mr. Duarte")
check("a club with NO advisor is the club name alone",
      ClassGroupsRules.rowTitle(grade: "Debate Team", teacher: ""),
      "Debate Team")
check("the grade is trimmed too",
      ClassGroupsRules.rowTitle(grade: "  3rd Grade  ", teacher: "  Mr. Whitfield  "),
      "3rd Grade — Mr. Whitfield")
check("a separator that is not a hyphen",
      ClassGroupsRules.separator, "—")
check("an empty row is an empty string, not a bare dash",
      ClassGroupsRules.rowTitle(grade: "", teacher: ""), "")

// ---------------------------------------------------------------------------
// THE IMAGE COUNT. Deliberately NAIVE — it mirrors ClassGroup.imageCount, which
// is what every stored row already means and what the web app reads.
print("the naive image count")

check("empty",                ClassGroupsRules.imageCount(""), 0)
check("whitespace only",      ClassGroupsRules.imageCount("   \n"), 0)
check("one number",           ClassGroupsRules.imageCount("1042"), 1)
check("three numbers",        ClassGroupsRules.imageCount("1042, 1043, 1051"), 3)
// THE KEPT QUIRK, asserted so it cannot be "fixed" by accident: a trailing comma
// does not add a number, and neither does a doubled one.
check("a trailing comma counts nothing extra", ClassGroupsRules.imageCount("12,"), 1)
check("a doubled comma counts nothing extra",  ClassGroupsRules.imageCount("1,,2"), 2)
check("commas alone count nothing",            ClassGroupsRules.imageCount(",,"), 0)
check("a leading comma counts nothing extra",  ClassGroupsRules.imageCount(",12"), 1)
check("it agrees with the model it describes",
      ClassGroupsRules.imageCount("1042, 1043, 1051"),
      ClassGroup(imageNumbers: "1042, 1043, 1051").imageCount)
check("…including on the trailing-comma case",
      ClassGroupsRules.imageCount("12,"),
      ClassGroup(imageNumbers: "12,").imageCount)

// ---------------------------------------------------------------------------
// PLURALS. Every noun comes from ClassGroupJobType, so Clubs never says "groups"
// and one image never reads "1 images".
print("plurals, at 0 / 1 / 2")

check("zero groups",   ClassGroupsRules.countLabel(jobType: groups, count: 0), "0 groups")
check("one group",     ClassGroupsRules.countLabel(jobType: groups, count: 1), "1 group")
check("two groups",    ClassGroupsRules.countLabel(jobType: groups, count: 2), "2 groups")
// Candids share the group noun; clubs do not.
check("one candid row is a group", ClassGroupsRules.countLabel(jobType: candids, count: 1), "1 group")
check("one club",      ClassGroupsRules.countLabel(jobType: clubs, count: 1), "1 club")
check("four clubs",    ClassGroupsRules.countLabel(jobType: clubs, count: 4), "4 clubs")
check("an unknown job type buckets to class groups",
      ClassGroupsRules.countLabel(jobType: "somethingNew", count: 2), "2 groups")
check("a nil job type buckets to class groups",
      ClassGroupsRules.countLabel(jobType: nil, count: 2), "2 groups")

check("no groups yet",  ClassGroupsRules.missingLabel(jobType: groups), "No groups yet")
check("no clubs yet",   ClassGroupsRules.missingLabel(jobType: clubs), "No clubs yet")

check("zero images",    ClassGroupsRules.imagesLabel(count: 0), "0 images")
check("ONE image",      ClassGroupsRules.imagesLabel(count: 1), "1 image")
check("two images",     ClassGroupsRules.imagesLabel(count: 2), "2 images")
check("three hundred",  ClassGroupsRules.imagesLabel(count: 300), "300 images")

// ---------------------------------------------------------------------------
// THE JOB CARD'S PILLS.
print("the job card's pills")

let empty = ClassGroupsRules.pills(jobType: groups, groupCount: 0, imageCount: 0)
check("an empty job draws ONE pill", empty.count, 1)
check("…and it is the amber warning", empty[0].tone.rawValue, "missing")
check("…worded with the plural noun", empty[0].text, "No groups yet")
check("…with a warning glyph", empty[0].systemImage, "exclamationmark.circle")

// IMAGES AT ZERO ARE OMITTED, not drawn as "0 images".
let shotNothing = ClassGroupsRules.pills(jobType: groups, groupCount: 5, imageCount: 0)
check("a job with rows but no frames draws ONE pill", shotNothing.count, 1)
check("…the count", shotNothing[0].text, "5 groups")
check("…and no images pill", shotNothing.contains { $0.tone == .images }, false)

let working = ClassGroupsRules.pills(jobType: groups, groupCount: 1, imageCount: 1)
check("one row and one frame draws two pills", working.count, 2)
check("…singular row noun", working[0].text, "1 group")
check("…singular image noun", working[1].text, "1 image")
check("…tones", "\(working[0].tone.rawValue)/\(working[1].tone.rawValue)", "count/images")
check("…ids are stable for ForEach", "\(working[0].id)/\(working[1].id)", "count/images")

// THE ICON FOLLOWS THE TYPE (AMB.10 fix of parity §3's copy bug: the old row
// hardcoded person.3 for every type). Same vocabulary as the empty states.
check("groups count icon", ClassGroupsRules.countIcon(jobType: groups), "person.3")
check("candids count icon", ClassGroupsRules.countIcon(jobType: candids), "camera")
check("clubs count icon", ClassGroupsRules.countIcon(jobType: clubs), "person.2")
check("the count pill carries the type's icon",
      ClassGroupsRules.pills(jobType: clubs, groupCount: 3, imageCount: 0)[0].systemImage, "person.2")

let clubJob = ClassGroupsRules.pills(jobType: clubs, groupCount: 3, imageCount: 12)
check("club count pill", clubJob[0].text, "3 clubs")
check("club image pill", clubJob[1].text, "12 images")
// The zero-row club still warns in ITS OWN vocabulary.
check("an empty club job warns about clubs",
      ClassGroupsRules.pills(jobType: clubs, groupCount: 0, imageCount: 0)[0].text,
      "No clubs yet")
// A job with zero rows cannot have images, but if the data ever says so the
// warning and the images pill coexist rather than one hiding the other.
check("zero rows with images still warns",
      ClassGroupsRules.pills(jobType: groups, groupCount: 0, imageCount: 4).count, 2)

// ---------------------------------------------------------------------------
// THE DETAIL HERO'S TOTALS LINE. BOTH figures, always, including at zero.
print("the totals line")

check("a full job",
      ClassGroupsRules.totalsLine(jobType: groups, groupCount: 14, imageCount: 300),
      "14 groups · 300 images")
check("a brand new job states both zeroes",
      ClassGroupsRules.totalsLine(jobType: groups, groupCount: 0, imageCount: 0),
      "0 groups · 0 images")
check("one of each, singular on both halves",
      ClassGroupsRules.totalsLine(jobType: groups, groupCount: 1, imageCount: 1),
      "1 group · 1 image")
check("clubs keep their noun in the totals",
      ClassGroupsRules.totalsLine(jobType: clubs, groupCount: 3, imageCount: 0),
      "3 clubs · 0 images")

// ---------------------------------------------------------------------------
// THE FORM.
print("the form")

check("no numbers yet",   ClassGroupsRules.imagesFieldStatus(count: 0), "none yet")
check("ONE number",       ClassGroupsRules.imagesFieldStatus(count: 1), "1 number")
check("three numbers",    ClassGroupsRules.imagesFieldStatus(count: 3), "3 numbers")
check("the status counts what the field holds",
      ClassGroupsRules.imagesFieldStatus(count: ClassGroupsRules.imageCount("1042, 1043, 1051")),
      "3 numbers")

check("a blank grade cannot be saved",       ClassGroupsRules.isFormValid(grade: ""), false)
check("a whitespace grade cannot be saved",  ClassGroupsRules.isFormValid(grade: "   "), false)
check("a newline grade cannot be saved",     ClassGroupsRules.isFormValid(grade: "\n"), false)
check("a real grade can",                    ClassGroupsRules.isFormValid(grade: "Pre-K"), true)
// Teacher, images and notes are all optional — the rule takes only the grade,
// which is what stops a second form growing a second opinion about it.
check("a club name is a grade as far as the form is concerned",
      ClassGroupsRules.isFormValid(grade: "Robotics Club"), true)

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
  if ! swiftc -O -o "$out" "$rules_file" "$MODELS" "$WORK/main.swift" 2>"$WORK/compile.log"; then
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
    "the count icon follows the type|s/ClassGroupJobType\\.listEmptyIcon\\(jobType\\)/\"person.3\"/"
    "a blank teacher drops the separator|s/guard !trimmedTeacher\.isEmpty else \{ return trimmedGrade \}//"
    "the separator is an em dash|s/static let separator = \"—\"/static let separator = \"-\"/"
    "the grade is trimmed|s/let trimmedGrade = grade\.trimmingCharacters\(in: \.whitespacesAndNewlines\)/let trimmedGrade = grade/"
    "an empty image field counts zero|s/if trimmed\.isEmpty \{ return 0 \}/if trimmed.isEmpty { return 1 }/"
    "the image count stays NAIVE|s/split\(separator: \",\"\)\.count/split(separator: \",\", omittingEmptySubsequences: false).count/"
    "the row noun is singular at one|s/let noun = count == 1/let noun = false/"
    "the zero warning uses the PLURAL noun|s/countNounPlural\(jobType\)\) yet/countNoun(jobType)) yet/"
    "images are singularized at one|s/count == 1 \? \"image\" : \"images\"/\"images\"/"
    "the images pill is omitted at zero|s/if imageCount > 0 \{/if imageCount >= 0 {/"
    "the count pill switches to the warning at zero only|s/if groupCount > 0 \{/if groupCount > 1 {/"
    "the totals line carries both figures|s/ · /: /"
    "the images status says 'none yet' only at zero|s/guard count > 0 else \{ return \"none yet\" \}/guard count > -1 else { return \"none yet\" }/"
    "the images status singularizes 'number'|s/count == 1 \? \"number\" : \"numbers\"/\"numbers\"/"
    "a whitespace grade is not a grade|s/!grade\.trimmingCharacters\(in: \.whitespacesAndNewlines\)\.isEmpty/!grade.isEmpty/"
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
