//  ClassGroupsRules.swift
//  Iconik Employee — the Class Groups value rules, as compiled types
//
//  PRODUCTION CODE, COMPILED AND RUN BY `scripts/test_classgroups_rules.sh`
//  alongside the REAL `Models/ClassGroupModels.swift` — the same two files Xcode
//  builds. Not a paraphrase in another language: that mistake was made once on
//  this arc and the operator's verdict was "your logic was fake and doesn't
//  actually do anything".
//
//  NO SwiftUI IMPORT. Deliberate and load-bearing: `swiftc` compiles this
//  standalone with `ClassGroupModels.swift`, which is Foundation-only for the same
//  reason. Anything that needs a Color or a View belongs in ClassGroupsKit.swift.
//
//  WHY THESE PARTICULAR RULES
//      Every one of them was a sentence assembled inline inside a SwiftUI body,
//      and three of them were wrong there:
//
//        · "\(grade) - \(teacher)" was rendered UNCONDITIONALLY
//          (`ClassGroupJobDetailView.swift:204`), so a row with no teacher read
//          "Kindergarten - " with a dangling dash. Teacher is optional — only the
//          grade is required by the form.
//        · "\(totalImageCount) images" was NEVER singularized
//          (`ClassGroupJobsListView.swift:208`), so a job with one frame recorded
//          read "1 images".
//        · The zero case and the counted case were two separate branches with two
//          separate vocabularies, so the amber warning and the blue count could
//          drift apart.
//
//  WHAT IS DELIBERATELY *NOT* FIXED HERE, and it is a decision rather than an
//  oversight: `imageCount` is a NAIVE comma split, so "12," counts as one number
//  and "1,,2" counts as two. That is exactly what `ClassGroup.imageCount`
//  (`ClassGroupModels.swift:269`) does and therefore what every stored row already
//  means. Counting better here than production stores would make this file
//  disagree with the model it describes — and the model's count is what the web
//  app reads too.

import Foundation

// MARK: - Pills

/// What a pill MEANS, without knowing what colour that is. The kit maps a tone to
/// a `Color`; this file stays SwiftUI-free so the rules can be run by a script.
enum ClassGroupPillTone: String, Equatable {
    /// How many rows the job has.
    case count
    /// The job has none. Amber, and ALWAYS drawn — an empty job is the one you
    /// have to go back to.
    case missing
    /// How many image numbers are recorded across the job.
    case images
}

/// One pill on a job card.
struct ClassGroupPill: Equatable {
    let id: String
    let text: String
    let systemImage: String
    let tone: ClassGroupPillTone
}

// MARK: - The rules

enum ClassGroupsRules {

    /// The separator between a grade and its teacher. An EM DASH, not the hyphen
    /// the old row used — it is a break between two names, not a subtraction.
    static let separator = "—"

    // MARK: Row title

    /// THE DANGLING-DASH FIX. Grade alone when the teacher is blank (or is nothing
    /// but whitespace, which a keyboard produces easily); "grade — teacher" when
    /// both exist.
    ///
    /// Clubs share this shape: `grade` carries the club name and `teacher` the
    /// advisor, so a club with no advisor recorded read "Debate Team - ", which is
    /// where the defect looks worst.
    static func rowTitle(grade: String, teacher: String) -> String {
        let trimmedGrade = grade.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTeacher = teacher.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTeacher.isEmpty else { return trimmedGrade }
        return "\(trimmedGrade) \(separator) \(trimmedTeacher)"
    }

    // MARK: Counting

    /// The stored image-number count. NAIVE, on purpose — see the file header.
    /// Mirrors `ClassGroup.imageCount` so the two can never disagree.
    static func imageCount(_ raw: String) -> Int {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return trimmed.split(separator: ",").count
    }

    /// "1 group" / "3 groups" / "1 club" / "4 clubs" — the noun comes from the job
    /// type, so Clubs never says "groups".
    static func countLabel(jobType: String?, count: Int) -> String {
        let noun = count == 1
            ? ClassGroupJobType.countNoun(jobType)
            : ClassGroupJobType.countNounPlural(jobType)
        return "\(count) \(noun)"
    }

    /// The amber pill at zero. Plural noun, because it names the absent kind.
    static func missingLabel(jobType: String?) -> String {
        "No \(ClassGroupJobType.countNounPlural(jobType)) yet"
    }

    /// "1 image" / "12 images". SINGULARIZED, which the old row never was.
    static func imagesLabel(count: Int) -> String {
        "\(count) \(count == 1 ? "image" : "images")"
    }

    /// The count pill's icon, PER TYPE — the same vocabulary the empty states
    /// already use. The old row hardcoded `person.3` for Clubs and Candids
    /// (parity §3, a recorded copy bug); a candids pill showing a posed-group
    /// glyph is the icon contradicting the noun beside it.
    static func countIcon(jobType: String?) -> String {
        ClassGroupJobType.listEmptyIcon(jobType)
    }

    // MARK: The job card's pills

    /// The count pill, and the image pill when there is anything to count.
    ///
    /// IMAGES ARE OMITTED ENTIRELY AT ZERO rather than drawn as "0 images" — the
    /// old row's behaviour, and correct: an image count of zero on a job you have
    /// not shot yet is not information, it is a number that looks like a problem.
    static func pills(jobType: String?, groupCount: Int, imageCount: Int) -> [ClassGroupPill] {
        var pills: [ClassGroupPill] = []

        if groupCount > 0 {
            pills.append(ClassGroupPill(id: "count",
                                        text: countLabel(jobType: jobType, count: groupCount),
                                        systemImage: countIcon(jobType: jobType),
                                        tone: .count))
        } else {
            pills.append(ClassGroupPill(id: "count",
                                        text: missingLabel(jobType: jobType),
                                        systemImage: "exclamationmark.circle",
                                        tone: .missing))
        }

        if imageCount > 0 {
            pills.append(ClassGroupPill(id: "images",
                                        text: imagesLabel(count: imageCount),
                                        systemImage: "photo",
                                        tone: .images))
        }

        return pills
    }

    // MARK: The detail hero

    /// "14 groups · 300 images". BOTH figures unconditionally, including at zero —
    /// this is the line that tells a photographer standing in a school how much of
    /// the job is done, and a hidden zero is the answer they most need.
    static func totalsLine(jobType: String?, groupCount: Int, imageCount: Int) -> String {
        "\(countLabel(jobType: jobType, count: groupCount)) · \(imagesLabel(count: imageCount))"
    }

    // MARK: The form

    /// The Images section's status summary — "none yet" / "1 number" / "3 numbers".
    /// It counts NUMBERS rather than images because that is what the field holds:
    /// nothing in this feature stores a photograph.
    static func imagesFieldStatus(count: Int) -> String {
        guard count > 0 else { return "none yet" }
        return "\(count) \(count == 1 ? "number" : "numbers")"
    }

    /// Grade is the only required field on the form — Save and the whiteboard are
    /// both gated on it, in one place rather than in two `canShow…` computed
    /// properties per form (there used to be four, across two duplicate views).
    static func isFormValid(grade: String) -> Bool {
        !grade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
