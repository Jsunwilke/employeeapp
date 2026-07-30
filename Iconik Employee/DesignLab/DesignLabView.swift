//  DesignLabView.swift
//  Iconik Employee — the design lab
//
//  ARC SCAFFOLDING. Built once in AMB.2, carried for the whole AMB arc, and
//  DELETED WHOLE AT AMB.12 along with its entry in the profile menu.
//
//  WHAT IT IS FOR
//      No screen in this app gets restyled before the operator has seen the
//      design running on a device and said yes (AMB plan, D10 — a hard gate).
//      This is where those mockups live. Each phase adds its surface's mockup
//      views here shortly before its own conversion, so an approval cannot rot
//      against primitives that moved underneath it, and deletes them once the
//      converted screens are confirmed.
//
//  THE ONE THING THIS FILE MUST NOT DO
//      Supply its own navigation container.
//
//      AMB.1's design lab gave every prototype its own NavigationStack. Ambient
//      was chosen inside that frame, ported into the real shell — which hands
//      features a NavigationView, per NAV.1 — and tapping a shift did nothing,
//      because `navigationDestination` is NavigationStack-only and is silently
//      ignored inside a NavigationView. The lab could not have caught it: it was
//      testing a frame that does not exist in the app.
//
//      So: this view is PUSHED from the profile menu into the Home screen's real
//      NavigationView, exactly the way SettingsView is, and every mockup is
//      PUSHED from here rather than presented in a fullScreenCover. A mockup is
//      therefore running inside the same container its real screen will get, and
//      pushes from inside a mockup have to go through `.ambientPush(item:)` —
//      the same wrapper production uses — or they will fail here first.

import SwiftUI

// MARK: - The registry

/// Every mockup the lab currently carries. Phases add cases as they mock their
/// batch, and delete them once their screens are converted and confirmed.
enum DesignLabMockup: String, CaseIterable, Identifiable {
    case specimens
    case palette
    /// AMB.7's two Reports mockups were DELETED at that phase's close, once the
    /// operator confirmed both device smokes on the converted screens — a
    /// validation reference outlives the port it validates, not the phase.
    case timeOff
    /// AMB.11's job box meter mockup was DELETED at its close (2026-07-29), the
    /// same rule AMB.7's two Reports mockups went by: the operator confirmed the
    /// converted screens on a device, so the validation reference had outlived the
    /// port it validated. Its awkward states — Packed-then-Turned-In, a box on its
    /// second trip — are covered executably by
    /// `scripts/test_jobbox_progress_rules.sh` instead of by a screen.
    /// AMB.9's three mockups (Mileage, Route Planner, Statistics) were DELETED
    /// at its close (2026-07-30) — the operator confirmed the converted screens
    /// on both devices and the /code-review passed, so the validation references
    /// had outlived the ports. Their arithmetic lives on executably in
    /// `scripts/test_mileage_rules.sh` and `scripts/test_stats_rules.sh`, and
    /// the shared drawing in MileageKit/RoutePlannerKit/StatsKit, which the
    /// converted screens use directly.
    /// Batch 3's remaining two are AMB.10's, mocked with the batch so it was
    /// judged in one sitting; they die at AMB.10's close.
    case classGroups
    case yearbook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .specimens: return "Specimen Sheet"
        case .palette: return "Feature Colours"
        case .timeOff: return "Time Off"
        case .classGroups: return "Class Groups"
        case .yearbook: return "Yearbook"
        }
    }

    /// Which phase owns it — shown in the gallery so the lab reads as the arc's
    /// progress rather than a pile of screens.
    var phase: String {
        switch self {
        case .specimens: return "AMB.2"
        case .palette: return "AMB.2 · D11"
        case .timeOff: return "AMB.8"
        case .classGroups: return "AMB.10"
        case .yearbook: return "AMB.10"
        }
    }

    var premise: String {
        switch self {
        case .specimens:
            return "Every Ambient primitive at every density, drawn against Equipment's real row content. This is where the density decision gets made."
        case .palette:
            return "The wash behind each screen is its feature's colour — but 27 features share 11 colours today. Current against proposed, as a wash and as a tile."
        case .timeOff:
            return "Five surfaces. The balance moves out of Settings to the top of the screen it is about, status gets ONE rendering instead of three, and the manager queue admits it is a queue."
        case .classGroups:
            return "Job cards say when — with the year — and how much is done. The detail finally shows the date and the note bodies, and the whole row takes the tap. The slate stays a plain whiteboard on purpose."
        case .yearbook:
            return "0% stops reading as an error, filters compose with search instead of wiping it, OPTIONAL marks the few items that really are, and a network failure stops claiming the checklist doesn't exist."
        }
    }

    var symbol: String {
        switch self {
        case .specimens: return "square.grid.3x3.square"
        case .palette: return "paintpalette.fill"
        case .timeOff: return "calendar.badge.clock"
        case .classGroups: return "person.3.fill"
        case .yearbook: return "list.clipboard.fill"
        }
    }


    /// Batch-1 surfaces carry their own FEATURE colour (D11), so the gallery is
    /// itself a check on whether four converted screens will read as four
    /// different places.
    var tint: Color {
        switch self {
        case .specimens: return .purple
        case .palette: return .pink
        case .timeOff: return TimeOffMockup.featureTint
        case .classGroups: return ClassGroupsMockup.featureTint
        case .yearbook: return YearbookMockup.featureTint
        }
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .specimens: SpecimenSheetMockup()
        case .palette: PaletteMockup()
        case .timeOff: TimeOffMockup()
        case .classGroups: ClassGroupsMockup()
        case .yearbook: YearbookMockup()
        }
    }
}

// MARK: - Gallery

struct DesignLabView: View {
    var body: some View {
        List {
            Section {
                ForEach(DesignLabMockup.allCases) { mockup in
                    // A plain NavigationLink row, which is the one push form a
                    // List is reliable with inside a NavigationView. The mockups
                    // themselves push with .ambientPush(item:) — that is where
                    // the container actually matters, and where AMB.1's dead tap
                    // came from.
                    NavigationLink {
                        DesignLabRunner(initial: mockup)
                    } label: {
                        row(mockup)
                    }
                }
            } header: {
                Text("Mockups")
            } footer: {
                Text("Nothing here reads or writes your data — every screen runs on fixed sample data chosen to contain the cases that break layouts. Once you are inside, the switcher at the bottom right swaps between mockups without coming back here.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to judge these")
                        .font(.subheadline.weight(.semibold))
                    Text("Look at them on the device you actually use, in the light you actually work in. The questions that matter: can you scan a long list without it feeling slow, does the important thing on the screen look important, and does a finished thing look clearly different from one still to come. If something is wrong, say so here — changing a mockup costs minutes, changing a converted screen costs a session.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Label("This whole screen is temporary. It is deleted when the design rollout finishes (AMB.12), along with its entry in the profile menu.",
                      systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Design Lab")
        .navigationBarTitleDisplayMode(.inline)
        // The lab is a PUSHED screen, and a pushed screen does its own tab-bar
        // clearance (BottomTabBar.swift's rule — a container's root inset is not
        // inherited by what it pushes). Without this the gallery's last card is
        // trapped under the floating bar.
        .tabBarClearance()
    }

    private func row(_ mockup: DesignLabMockup) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(mockup.tint.gradient)
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: mockup.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(mockup.title).font(.headline)
                    Text(mockup.phase)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Text(mockup.premise)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Runner

/// Runs one mockup with the single piece of lab chrome that earns its place: a
/// switcher, so two designs can be compared on the same screen without walking
/// back out to the gallery between them.
///
/// The mockup is swapped IN PLACE inside this pushed screen rather than being
/// presented over it, which keeps everything inside the shell's real navigation
/// container. `.id(current)` forces a clean rebuild per mockup so you always
/// land on its root and never inside the previous one's drill-down.
private struct DesignLabRunner: View {
    @State private var current: DesignLabMockup
    @State private var expanded = false

    init(initial: DesignLabMockup) {
        self._current = State(initialValue: initial)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            current.view
                .id(current)

            if DesignLabMockup.allCases.count > 1 {
                switcher
                    .padding(.trailing, 14)
                    .padding(.bottom, 24)
            }
        }
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        // Same rule as the gallery above: the runner is itself a pushed screen.
        // The inset raises the switcher AND every mockup's bottom-anchored
        // chrome (Class Groups' floating "+") clear of the floating tab bar,
        // and lets each mockup's last row scroll out from under it. Found by
        // the operator on the Class Groups mockup — the bar sat on the "+".
        .tabBarClearance()
    }

    private var switcher: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if expanded {
                ForEach(DesignLabMockup.allCases.reversed()) { option in
                    Button {
                        select(option)
                    } label: {
                        HStack(spacing: 8) {
                            Text(option.title).font(.caption.weight(.semibold))
                            Image(systemName: option.symbol).font(.caption).frame(width: 18)
                        }
                        .foregroundStyle(option == current ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background {
                            if option == current {
                                Capsule().fill(option.tint)
                            } else {
                                Capsule().fill(.regularMaterial)
                            }
                        }
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            HStack(spacing: 8) {
                Button { step(-1) } label: {
                    Image(systemName: "chevron.left").font(.caption.weight(.bold)).frame(width: 26, height: 34)
                }
                Text(current.phase).font(.caption.weight(.bold)).contentTransition(.opacity)
                Button { step(1) } label: {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).frame(width: 26, height: 34)
                }
                Divider().frame(height: 18)
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.caption2.weight(.bold))
                    .frame(width: 22, height: 34)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(AmbientMotion.snappy) { expanded.toggle() }
                        AmbientHaptics.impact(.light)
                    }
            }
            .padding(.horizontal, 10)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(current.tint.opacity(0.45), lineWidth: 1.5))
            .foregroundStyle(.primary)
        }
    }

    private func select(_ option: DesignLabMockup) {
        withAnimation(AmbientMotion.gentle) {
            current = option
            expanded = false
        }
        AmbientHaptics.impact(.medium)
    }

    private func step(_ delta: Int) {
        let all = DesignLabMockup.allCases
        guard all.count > 1, let index = all.firstIndex(of: current) else { return }
        select(all[(index + delta + all.count) % all.count])
    }
}
