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

    // EVERY SURFACE MOCKUP IS NOW GONE, and that is the rule working rather than
    // the lab emptying out. A mockup is a VALIDATION REFERENCE: it outlives the
    // port it validated, not the phase. AMB.7, 9, 10, 11 and now 12 each deleted
    // theirs at their close, once the operator had smoked the converted screens
    // on a device.
    //
    // AMB.12 (2026-08-01) removed the last three — Settings, Manager Tools and
    // Training — with its smoke passing on both devices. It also swept up three
    // that had outlived their own closes and had simply been left behind: Time
    // Off (AMB.8), Class Groups and Yearbook (AMB.10). Their designs live on
    // where they belong: in production, as `SettingsKit`, `AuthKit`,
    // `ManagerKit`, `TrainingKit`, `TimeOffKit`, `ClassGroupsKit` and
    // `YearbookKit`, which the converted screens use directly.
    //
    // WHAT SURVIVES, and why it is only these two: the specimen sheet and the
    // palette are FOUNDATIONS, not a phase's proposal. They show the primitives
    // themselves, so they stay useful for as long as there is a phase left to
    // design — which there is. THE HARNESS DOES NOT DIE HERE. D10 pinned its
    // deletion to "the close of AMB.12" back when AMB.12 was the arc's last
    // phase; the operator's 2026-08-01 ruling gave the time clock its own phase
    // (D15), so AMB.13 needs the lab to design against and the harness dies with
    // that phase instead.

    var id: String { rawValue }

    var title: String {
        switch self {
        case .specimens: return "Specimen Sheet"
        case .palette: return "Feature Colours"
        }
    }

    /// Which BATCH it belongs to, so the gallery groups the arc's remaining work
    /// rather than presenting nine peers.
    var batch: String {
        switch self {
        case .specimens, .palette: return "Foundations"
        }
    }

    /// Which phase owns it — shown in the gallery so the lab reads as the arc's
    /// progress rather than a pile of screens.
    var phase: String {
        switch self {
        case .specimens: return "AMB.2"
        case .palette: return "AMB.2 · D11"
        }
    }

    var premise: String {
        switch self {
        case .specimens:
            return "Every Ambient primitive at every density, drawn against Equipment's real row content. This is where the density decision gets made."
        case .palette:
            return "The wash behind each screen is its feature's colour — but 27 features share 11 colours today. Current against proposed, as a wash and as a tile."
        }
    }

    var symbol: String {
        switch self {
        case .specimens: return "square.grid.3x3.square"
        case .palette: return "paintpalette.fill"
        }
    }


    /// Batch-1 surfaces carry their own FEATURE colour (D11), so the gallery is
    /// itself a check on whether four converted screens will read as four
    /// different places.
    var tint: Color {
        switch self {
        case .specimens: return .purple
        case .palette: return .pink
        }
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .specimens: SpecimenSheetMockup()
        case .palette: PaletteMockup()
        }
    }
}

// MARK: - Gallery

struct DesignLabView: View {
    /// Batch order, first appearance wins — so a new batch shows up by adding a
    /// case to the enum and nothing else.
    private static var batches: [String] {
        var seen: [String] = []
        for mockup in DesignLabMockup.allCases where !seen.contains(mockup.batch) {
            seen.append(mockup.batch)
        }
        return seen
    }

    var body: some View {
        List {
            ForEach(Self.batches, id: \.self) { batch in
                Section {
                    ForEach(DesignLabMockup.allCases.filter { $0.batch == batch }) { mockup in
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
                    Text(batch)
                }
            }

            Section {
                EmptyView()
            } footer: {
                // D14 (2026-07-30) took the per-feature wash off every PRODUCTION
                // screen. The mockups keep theirs on purpose — they are the design
                // references the decisions were made against, and the palette sheet
                // exists to show colours side by side — so the lab now shows a
                // background the app no longer does. Said out loud rather than
                // silently rebuilt.
                Text("Nothing here reads or writes your data — every screen runs on fixed sample data chosen to contain the cases that break layouts. Once you are inside, the switcher at the bottom right swaps between mockups without coming back here.\n\nD14: these mockups still show a background in each feature's own colour. The real app no longer does — every production screen is washed in the one company blue the web app uses, and turns red when you are flagged. Feature colours live on in the tiles, icons and badges.")
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
