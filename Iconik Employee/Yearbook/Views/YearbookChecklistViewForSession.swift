//  YearbookChecklistViewForSession.swift
//  Iconik Employee — the yearbook checklist reached FROM A SHIFT, Ambient (AMB.10)
//
//  Presented as a SHEET from `Schedule/ShiftDetailView.swift` (~:262), which
//  brings its own `NavigationView` and passes the school and a
//  `YearbookSessionContext`. That call site is a CONTRACT: the type name and the
//  three inputs are unchanged.
//
//  WHAT THIS SCREEN GAINED — all four are states it did not have:
//    · A LOAD FAILURE IS NOT "THIS SCHOOL HAS NO CHECKLIST" (claim 4). The old
//      catch block printed the error and rendered "No Yearbook List Found — no
//      yearbook checklist exists for X", which is a factual claim about the school
//      made on the strength of a dropped connection. A photographer who reads it
//      stops looking. So does a missing organization id, which rendered the same
//      screen.
//    · THE SPINNER ENDS. If the initial fetch came back nil the old screen span
//      forever — no timeout, no error, no retry.
//    · THE YEAR PICKER SCROLLS. It was a bare `VStack`, so a school with six years
//      of books pushed the oldest ones off the bottom with no way to reach them.
//    · EVERY WRITE IS ON THE MAIN ACTOR. The old `Task` wrote `@State` and
//      `@Published` from a background context, and assigned view-model state from
//      outside the view model (parity §3).

import SwiftUI

struct YearbookChecklistViewForSession: View {
    let schoolId: String
    let schoolName: String
    let sessionContext: YearbookSessionContext

    @StateObject private var viewModel = YearbookShootListViewModel()

    /// Which of the four things this screen can be. The old screen carried three
    /// booleans and could not distinguish a failure from an absence.
    private enum Phase: Equatable {
        case loading
        /// The school genuinely has no list.
        case noList
        /// The load itself failed — a different claim entirely.
        case failed(String)
        /// Several years exist; the photographer picks one.
        case picking
        /// A year is chosen and the checklist is being fetched or shown.
        case opening
    }

    @State private var phase: Phase = .loading
    @State private var years: [String] = []
    @State private var organizationId: String?
    @Environment(\.dismiss) private var dismiss

    private var tint: Color { YearbookStyle.tint }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                loadingScreen
            case .noList:
                noListScreen
            case .failed(let message):
                failureScreen(message)
            case .picking:
                yearPicker
            case .opening:
                openingScreen
            }
        }
        // The child sets its own title (school • year) once it renders, and the
        // inner modifier wins — as it did before this conversion.
        .navigationTitle("Yearbook Checklist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close") { dismiss() }
            }
        }
        .task { await load() }
    }

    // MARK: - The four states

    private var loadingScreen: some View {
        ZStack {
            AmbientBackdrop()
            YearbookLoadingRow(message: "Loading yearbook checklist…")
                .padding(.horizontal, 16)
        }
    }

    private var noListScreen: some View {
        ZStack {
            AmbientBackdrop()
            AmbientEmptyState(
                title: "No Yearbook List Found",
                message: "No yearbook checklist exists for \(schoolName).",
                systemImage: "list.clipboard")
                .padding(.horizontal, 16)
        }
    }

    /// Claim 4, drawn: what failed, what is still unknown, and a way to try again.
    private func failureScreen(_ message: String) -> some View {
        ZStack {
            AmbientBackdrop()
            ScrollView {
                YearbookFailureCard(
                    systemImage: "wifi.exclamationmark",
                    title: "Couldn't load the checklist",
                    message: message,
                    retryTitle: "Retry",
                    tint: tint,
                    retry: { Task { await load() } })
                    .padding(.horizontal, 16)
            }
            .ambientNoBounceWhenShort()
        }
    }

    /// SCROLLABLE. Six years of books are reachable now.
    private var yearPicker: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    AmbientSectionTitle("Select school year")
                    Text("Multiple yearbook lists found for \(schoolName).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                        ForEach(years, id: \.self) { year in
                            YearbookYearRow(
                                year: year,
                                isCurrent: year == YearbookShootList.getCurrentSchoolYear(
                                    date: sessionContext.sessionDate),
                                tint: tint) {
                                    open(year: year)
                                }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
    }

    /// A year is chosen. Either the list is here, or it is still coming, or the
    /// fetch answered with nothing — which is the case that used to spin forever.
    @ViewBuilder
    private var openingScreen: some View {
        if let shootList = viewModel.selectedShootList {
            YearbookChecklistView(shootList: shootList, sessionContext: sessionContext)
        } else if viewModel.isLoading {
            loadingScreen
        } else {
            failureScreen("\(schoolName) may well have one — this device just couldn't reach the server.")
        }
    }

    // MARK: - Loading

    /// MainActor-isolated, so every `@State` and `@Published` write below is on the
    /// main actor by construction rather than by remembering to hop.
    @MainActor
    private func load() async {
        phase = .loading

        let orgId = await withCheckedContinuation { continuation in
            UserManager.shared.getCurrentUserOrganizationID { continuation.resume(returning: $0) }
        }

        guard let orgId else {
            // NOT "this school has no list": nothing was ever asked.
            phase = .failed("This device couldn't work out which studio you belong to, so it couldn't ask for \(schoolName)'s checklist.")
            return
        }
        organizationId = orgId

        let fetched: [String]
        do {
            fetched = try await YearbookShootListService.shared.getAvailableYears(
                schoolId: schoolId, organizationId: orgId)
        } catch {
            // THE FIX FOR CLAIM 4: the catch block no longer maps a failure onto
            // "no checklist exists".
            phase = .failed("\(schoolName) may well have one — this device just couldn't reach the server. (\(error.localizedDescription))")
            return
        }

        years = fetched

        guard !fetched.isEmpty else {
            phase = .noList
            return
        }

        let sessionYear = YearbookShootList.getCurrentSchoolYear(date: sessionContext.sessionDate)
        if fetched.contains(sessionYear) {
            open(year: sessionYear)
        } else if fetched.count == 1, let only = fetched.first {
            open(year: only)
        } else {
            phase = .picking
        }
    }

    private func open(year: String) {
        guard let orgId = organizationId else {
            phase = .failed("This device couldn't work out which studio you belong to, so it couldn't ask for \(schoolName)'s checklist.")
            return
        }
        phase = .opening
        viewModel.loadShootList(schoolId: schoolId, schoolYear: year, organizationId: orgId)
    }
}

// MARK: - Preview
struct YearbookChecklistViewForSession_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            YearbookChecklistViewForSession(
                schoolId: "school123",
                schoolName: "Lincoln High School",
                sessionContext: YearbookSessionContext(
                    sessionId: "session123",
                    photographerId: "user123",
                    photographerName: "John Doe",
                    sessionDate: Date()
                )
            )
        }
    }
}
