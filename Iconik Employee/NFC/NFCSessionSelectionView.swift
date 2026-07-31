//  NFCSessionSelectionView.swift
//  Iconik Employee — choosing the job a box belongs to
//
//  AMB.11 conversion. THE ONE session-choosing UI: `JobBoxFormView` used to open
//  an inline `Picker` with a "None" tag over the same data, and now opens this.
//
//  FIXED HERE:
//    - N29: `.searchable` was attached to the `List`, so the search bar VANISHED
//      in both empty states — once a query found nothing you could not edit it,
//      only Cancel. It is now a persistent `JobBoxSearchField` above the content,
//      always editable.
//    - N28: the filter matched the raw `yyyy-MM-dd` string while the row DISPLAYS
//      a `.medium` date, so typing "Jul" matched nothing and you had to type "07".
//      Both forms match now.
//    - N30 (approved): honest LOADING and FAILURE states. The view took a plain
//      array, so during the caller's fetch it said "No available sessions in the
//      next 2 weeks" — a lie during load — and a network failure said the same
//      thing. Both call sites pass the real state.
//    - N42: the row's per-body `DateFormatter` is replaced by the shared
//      `Formatters`.
//
//  UNCHANGED: both empty states' copy, the row's facts (school, time range,
//  photographer names, type pill) and the source window — published, scheduled
//  sessions from today to today+14, owned by `TimeTrackingService`.

import SwiftUI

struct NFCSessionSelectionView: View {
    let sessions: [Session]
    @Binding var selectedSession: Session?
    @Binding var isPresented: Bool
    /// The caller's fetch state. Defaulted so neither call site is forced to
    /// track it, but both do.
    var isLoading: Bool = false
    var loadFailed: Bool = false
    /// The caller owns the fetch, so it owns the retry. Without one the failure
    /// card would offer a button that could only close the sheet.
    var onRetry: (() -> Void)? = nil

    @State private var searchText = ""

    private var tint: Color { FeatureTheme.color(for: "scan") }

    // Filtered sessions based on search
    private var filteredSessions: [Session] {
        if searchText.isEmpty {
            return sessions
        }
        return sessions.filter { session in
            session.schoolName.localizedCaseInsensitiveContains(searchText) ||
            session.date.contains(searchText) ||
            // N28: also match what the row actually SHOWS.
            SessionRowView.displayDate(for: session).localizedCaseInsensitiveContains(searchText) ||
            session.getPhotographerNames().joined(separator: ", ").localizedCaseInsensitiveContains(searchText) ||
            session.sessionType.joined(separator: ", ").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()

                VStack(spacing: 12) {
                    // Persistent — it does not disappear when a query finds
                    // nothing (N29).
                    JobBoxSearchField(placeholder: "Search sessions", text: $searchText)
                        .padding(.horizontal, 16)

                    content
                }
                .padding(.top, 12)
            }
            .navigationTitle("Select Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            JobBoxLoadingCard(message: "Loading sessions…")
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
        } else if loadFailed {
            JobBoxFailureCard(message: "Couldn't load sessions.") {
                if let onRetry { onRetry() } else { isPresented = false }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        } else if sessions.isEmpty {
            AmbientEmptyState(title: "No available sessions in the next 2 weeks",
                              message: "Only published, scheduled sessions from today onward appear here.",
                              systemImage: "calendar.badge.checkmark")
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
        } else if filteredSessions.isEmpty {
            AmbientEmptyState(title: "No sessions match your search",
                              message: "Try adjusting your search terms",
                              systemImage: "magnifyingglass")
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    noSessionRow
                    ForEach(filteredSessions) { session in
                        SessionRowView(session: session, tint: tint) {
                            selectedSession = session
                            isPresented = false
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .ambientNoBounceWhenShort()
        }
    }

    /// UNPICKING A SESSION, which unifying on this sheet would otherwise have
    /// taken away: `JobBoxFormView`'s inline `Picker` had a "None" tag, and one
    /// session in the list is auto-selected, so without this a box could be
    /// linked to a job with no way to unlink it (D12 — a design phase does not
    /// lose a capability).
    ///
    /// It only clears the LINK, and what stops an UNLINKED new box differs by
    /// call site (corrected in the audit round — this used to claim both had a
    /// session-required check on Submit):
    ///   · `ManualEntryView` does have that check — `submitData` refuses when the
    ///     box has no last record and no session is picked;
    ///   · `JobBoxFormView` has NO such check. A brand-new box there is stopped
    ///     instead by `ScanView.validationFailure`, which rejects the empty school
    ///     and empty status a new box arrives with and that only a session fills
    ///     in.
    private var noSessionRow: some View {
        Button {
            selectedSession = nil
            isPresented = false
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar.badge.minus")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text("No session")
                        .font(AmbientDensity.compact.titleFont)
                    Text("Save without linking this box to a job")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selectedSession == nil {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }
            }
            .ambientCard(density: .compact, fillWidth: true)
        }
        .buttonStyle(.plain)
    }
}

struct SessionRowView: View {
    let session: Session
    var tint: Color = .blue
    let onTap: () -> Void

    /// The `.medium` string the row shows. Static so the filter can match the
    /// same text the user is reading (N28).
    static func displayDate(for session: Session) -> String {
        if let date = Formatters.isoDate.date(from: session.date) {
            return Formatters.mediumDate.string(from: date)
        }
        return session.date
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // School name and date
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.schoolName)
                            .font(AmbientDensity.compact.titleFont)

                        if !session.sessionType.isEmpty {
                            AmbientBadge(text: session.sessionType.joined(separator: ", ").capitalized,
                                         tint: tint)
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Self.displayDate(for: session))
                            .font(.subheadline)

                        Text("\(session.startTime) - \(session.endTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Photographers
                let photographers = session.getPhotographerNames()
                if !photographers.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(photographers.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                // Notes if available
                if let notes = session.description, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .ambientCard(density: .compact, fillWidth: true)
        }
        .buttonStyle(.plain)
    }
}

struct NFCSessionSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        NFCSessionSelectionView(
            sessions: [],
            selectedSession: .constant(nil),
            isPresented: .constant(true)
        )
    }
}
