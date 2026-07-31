//  NFCContainerView.swift
//  Iconik Employee — the job box / NFC sub-shell
//
//  ONE FEATURE, ONE CHROME (AMB.11, claim 1 of the approved `JobBoxMockup`).
//
//  What this file used to be: an `HStack` of content plus a fixed 60pt vertical
//  rail, inside which THREE of the five tabs wrapped themselves in a SECOND
//  `NavigationView` — so "Write NFC" drew its title in an inner bar below the
//  Home button while "Scan" drew its in the shell's. The shell
//  (`MainEmployeeView.featureContainer`) already supplies a `NavigationView` for
//  this feature, so every one of those was a nested container.
//
//  DELETED IN THE SAME CHANGE (delete-first migration):
//    - all three nested `NavigationView`s;
//    - the 60pt rail, which was 60pt on a 4.7" SE and 60pt on a 12.9" iPad, and
//      whose 50pt label frame wrapped exactly two of the five labels;
//    - `ToolbarButton` and `PressedButtonStyle`, the rail's own controls;
//    - the five hardcoded tab colours (.orange/.blue/.green/.purple/.teal),
//      which bypassed `FeatureTheme` entirely — one feature is one colour, and
//      that colour is the REGISTERED `scan` #2AA7D8;
//    - `ComingSoonView` (finding N3): zero call sites, and it shipped the
//      internal note "This feature is being integrated from the NFC SD Tracker
//      app" to whatever photographer ever reached it;
//    - the `initialFeature` init parameter (finding N2): no caller ever supplied
//      it. The sole construction site is `MainEmployeeView.swift:963`,
//      `NFCContainerView()`, which needs no change.
//
//  The five tabs are now `JobBoxTabPill`s (`NFC/JobBoxKit.swift`) laid out in an
//  `AmbientFlowLayout` INSIDE the content, under the shell's one bar, and the bar
//  finally gets a title on every tab — Scan and Search rendered an EMPTY shell
//  title before this.

import SwiftUI

struct NFCContainerView: View {
    @State private var selectedFeature: NFCFeature = .scan

    /// Cross-tab deep link, kept exactly: Statistics' distribution rows route
    /// into Search pre-filtered. These are `SearchView`'s existing init
    /// parameters, so they land when the tab is re-created.
    ///
    /// The Scan screen's Job Box Alert banner used this too until the operator's
    /// 2026-07-31 ruling; it now presents its own sheet that MARKS the stalled
    /// boxes turned in, so `ScanView` takes no `onNavigateToSearch` at all
    /// (delete-first). Statistics is the only caller left.
    @State private var initialSearchStatus: String? = nil
    @State private var initialIsJobBoxMode: Bool = false

    enum NFCFeature: String, CaseIterable, Identifiable {
        case scan = "Scan"
        case search = "Search"
        case stats = "Stats"
        case writeNFC = "Write NFC"
        case manualEntry = "Manual Entry"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .scan: return "wave.3.right.circle.fill"
            case .search: return "magnifyingglass"
            case .stats: return "chart.bar.fill"
            case .writeNFC: return "pencil.circle.fill"
            case .manualEntry: return "square.and.pencil"
            }
        }

        /// What the ONE nav bar says. The tab pill stays short ("Stats"); the bar
        /// spells it out, and Scan and Search get a title at all for the first
        /// time.
        var navigationTitle: String {
            switch self {
            case .scan: return "Scan"
            case .search: return "Search"
            case .stats: return "Statistics"
            case .writeNFC: return "Write NFC"
            case .manualEntry: return "Manual Entry"
            }
        }
    }

    private var tint: Color { FeatureTheme.color(for: "scan") }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            VStack(spacing: 12) {
                tabRow
                content
            }
        }
        .navigationTitle(selectedFeature.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tabRow: some View {
        // ONE line, never a wrap (operator, 2026-07-31): the selected pill
        // carries the name, the rest are icon-only, so five tabs fit any phone.
        HStack(spacing: 6) {
            ForEach(NFCFeature.allCases) { feature in
                JobBoxTabPill(title: feature.rawValue,
                              systemImage: feature.icon,
                              on: selectedFeature == feature,
                              tint: tint) {
                    // A MANUAL tap on Search is a fresh Search (audit round).
                    // `showSearch` sets these and nothing ever cleared them, so
                    // after one banner or statistics tap every later tap on the
                    // Search pill silently re-applied that stale filter — the
                    // screen opened pre-filtered with no way to see why.
                    if feature == .search {
                        initialSearchStatus = nil
                        initialIsJobBoxMode = false
                    }
                    selectedFeature = feature
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedFeature {
        case .scan:
            ScanView()
        case .search:
            SearchView(initialStatus: initialSearchStatus,
                       initialIsJobBoxMode: initialIsJobBoxMode)
        case .stats:
            StatisticsView(onNavigateToSearch: { status, isJobBox in
                showSearch(status: status, isJobBox: isJobBox)
            })
        case .writeNFC:
            WriteNFCView()
        case .manualEntry:
            ManualEntryView(onCancel: {
                withAnimation(AmbientMotion.snappy) { selectedFeature = .scan }
            })
        }
    }

    private func showSearch(status: String, isJobBox: Bool) {
        initialSearchStatus = status
        initialIsJobBoxMode = isJobBox
        withAnimation(AmbientMotion.snappy) { selectedFeature = .search }
    }
}

struct NFCContainerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NFCContainerView()
        }
    }
}
