//  TrainingKit.swift
//  Iconik Employee — the Training design, as production code
//
//  PRODUCTION CODE THAT THE LAB MOCKUP IMPORTS. That direction is the whole
//  mechanism (AMB.10's shape, and TimeOffKit's and MileageKit's before it):
//  `DesignLab/Mockups/TrainingMockup.swift` prototyped these four types privately
//  as `TrainingLab*`, and at the conversion they land HERE so the mockup and the
//  real screens draw with one set of views. Nothing can drift, because there is no
//  second copy to drift from.
//
//  WHAT DIED TO MAKE ROOM (delete-first, same change):
//    · `Components/StatsCard.swift`      — the app already had TWO stat tiles and
//      must not carry a third. The three tiles are `AmbientStatTile` now.
//    · `Components/ExampleTypeBadge.swift` — `AmbientBadge` through
//      `CritiqueTypeBadge`, on the same shipped binary test.
//    · `Components/CritiqueGridCard.swift` / `Components/CritiqueListCard.swift`
//      — hand-rolled cards (both carried a card-drift allowlist row), replaced by
//      the two cards below, which go through `.ambientCard(...)`.
//
//  WHAT IS DELIBERATELY NOT HERE: anything that knows about Supabase. These views
//  take a `Critique` and draw it; the service, the query and its filters are
//  untouched by this phase (D12).
//
//  THE FIVE CLAIMS THE OPERATOR APPROVED (mockup header, 2026-07-30), and where
//  each one lives:
//    1. ONE CONCEPT, ONE WORD          — `CritiqueTypeBadge`, and the stat tiles
//                                        in `PhotoCritiqueListView`
//    2. A FAILED FETCH SAYS SO         — `PhotoCritiqueListView` (AmbientFailureCard)
//    3. THE GRID FOLLOWS WIDTH         — `PhotoCritiqueListView`'s size class
//    4. A ROW WITH NO IMAGES IS REAL   — `Critique.resolvedImageUrls` here, and
//                                        the guarded gallery in the detail
//    5. A CONFIRMATION DESCRIBES THE SAVE — `PhotoCritiqueDetailView`

import SwiftUI

// MARK: - Identity

enum TrainingStyle {
    /// This feature's ACCENT (D11) — `#C43B6D`. Read from `FeatureTheme` rather
    /// than restated, so the dashboard tile you tap and the screen you land on
    /// cannot disagree. It does NOT reach the background: D14 gives every screen
    /// the one app wash.
    static var tint: Color { FeatureTheme.color(for: "training") }
}

// MARK: - What a row really has

/// THE FIELD THE DESIGN HAD TO CHOOSE BETWEEN (claim 4).
///
/// A critique carries THREE fields for the same asset: the plural `image_urls` /
/// `thumbnail_urls`, the singular `image_url` / `thumbnail_url` kept for rows
/// written before the app stored a list, and an `image_count` column. Before this
/// phase the cards read the singular field, the detail's pager read the plural one,
/// and the counter and the whole thumbnail strip were gated on `image_count` —
/// which decodes to 0 when it is NULL (`Models.swift:884`), so a genuinely
/// multi-image critique drew as a single photo with no strip and no counter.
///
/// Everything Training draws now counts the URLs it is actually going to load.
extension Critique {
    /// Every image this row really has, plural list first and the legacy singular
    /// field as the fallback. Empty means empty — the legacy row the detail used to
    /// index unguarded (and crash on).
    var resolvedImageUrls: [String] {
        let plural = imageUrls.filter { !$0.isEmpty }
        if !plural.isEmpty { return plural }
        return imageUrl.isEmpty ? [] : [imageUrl]
    }

    /// How many images there really are. This is what the pager, the counter, the
    /// strip and the count pill all count.
    var resolvedImageCount: Int { resolvedImageUrls.count }

    /// The thumbnail for image `index`, falling back to the full-resolution URL
    /// when the row has fewer thumbnails than images (or none at all). Indexed
    /// rather than zipped, because the two lists are written independently and a
    /// short thumbnail list must not shorten the strip.
    func resolvedThumbnailUrl(at index: Int) -> String? {
        let thumbnails = thumbnailUrls.filter { !$0.isEmpty }
        if index < thumbnails.count { return thumbnails[index] }
        if index == 0, !thumbnailUrl.isEmpty { return thumbnailUrl }
        let images = resolvedImageUrls
        return index < images.count ? images[index] : nil
    }

    /// The one image a card shows.
    var cardThumbnailUrl: String? { resolvedThumbnailUrl(at: 0) }

    /// The notes, or nil when a manager sent none — the cards say "No notes" and
    /// the detail draws no note card at all rather than an empty box.
    var trimmedNotes: String? {
        let trimmed = managerNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The short date for a card, or nil when the row carries no timestamp.
    /// `Formatters` is the app's shared cache; the model's own `formattedDate`
    /// allocates a `DateFormatter` per call.
    var cardDateText: String? {
        guard let created = created_at else { return nil }
        return Formatters.shortDate.string(from: created)
    }
}

// MARK: - 1. The badge

/// The shipped binary test, unchanged: `example_type == "example"` is a good
/// example and EVERYTHING ELSE renders as a criticism — including values neither
/// client writes. Recorded, not changed: this phase touches no data layer.
///
/// The words are the SERVICE'S: "Needs Improvement", the same string the filter
/// uses (`PhotoCritiqueService.FilterType.improvement`) and the same one the stat
/// tile now uses. Before this phase the tile said "Needs Work" while the filter
/// beside it and the badge on every card said "Needs Improvement" — three words
/// for one concept on one screen (claim 1).
struct CritiqueTypeBadge: View {
    let isGood: Bool

    var body: some View {
        AmbientBadge(text: isGood ? "Good Example" : "Needs Improvement",
                     systemImage: isGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                     tint: isGood ? .green : .orange)
    }
}

// MARK: - 2. The thumbnail well

/// The image on a card, with the count pill that sits on top of it.
///
/// ONE failed-thumbnail treatment for both layouts: the icon AND the words "Image
/// unavailable". The grid card said it and the list row drew a bare icon, so the
/// same broken image meant two different things depending on which layout you were
/// in.
struct CritiqueThumbnail: View {
    let critique: Critique
    var height: CGFloat
    var width: CGFloat?

    private var count: Int { critique.resolvedImageCount }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // ambient-allow: a photo well — the image itself, not a container.
            shape
                .fill(Color(.tertiarySystemFill))
                .frame(width: width, height: height)
                .overlay { image }
                .clipShape(shape)

            if count > 1 {
                Label("\(count)", systemImage: "square.stack")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    // ambient-allow: a count pill over a photo, not a container.
                    .background(Capsule().fill(.ultraThinMaterial))
                    .padding(5)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var image: some View {
        if let url = critique.cardThumbnailUrl, let parsed = URL(string: url) {
            AsyncImage(url: parsed) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    unavailable
                case .empty:
                    ProgressView()
                @unknown default:
                    unavailable
                }
            }
        } else {
            // The legacy row: no image list, no singular URL. Drawn, not crashed.
            unavailable
        }
    }

    private var unavailable: some View {
        VStack(spacing: 4) {
            Image(systemName: "photo").font(.title3).foregroundStyle(.tertiary)
            Text("Image unavailable").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 3. The grid card

/// COMPACT. A photographer scans these; the notes are the thing being read, so the
/// badge and the attribution stay out of their way.
struct CritiqueGridCard: View {
    let critique: Critique

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CritiqueThumbnail(critique: critique, height: 120)

            CritiqueTypeBadge(isGood: critique.isGoodExample)

            Text(critique.trimmedNotes ?? "No notes")
                .font(.caption)
                .foregroundStyle(critique.trimmedNotes == nil ? .tertiary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(CritiqueGridCard.metaLine(critique))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    /// Submitter and date, with the separator dropped when the row carries no
    /// timestamp rather than trailing a bare "· ".
    static func metaLine(_ critique: Critique) -> String {
        guard let date = critique.cardDateText else { return critique.submitterName }
        return "\(critique.submitterName) · \(date)"
    }
}

// MARK: - 4. The list row

/// The same card, laid out for reading rather than scanning — the notes get the
/// width, and "for whom" earns a place the grid card has no room for.
struct CritiqueListRow: View {
    let critique: Critique

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CritiqueThumbnail(critique: critique, height: 74, width: 74)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    CritiqueTypeBadge(isGood: critique.isGoodExample)
                    Spacer(minLength: 0)
                    if let date = critique.cardDateText {
                        Text(date).font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                Text(critique.trimmedNotes ?? "No notes")
                    .font(.caption)
                    .foregroundStyle(critique.trimmedNotes == nil ? .tertiary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(critique.submitterName) · for \(critique.targetPhotographerName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}
