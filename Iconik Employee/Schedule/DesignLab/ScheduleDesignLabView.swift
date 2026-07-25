//  ScheduleDesignLabView.swift
//  Schedule Design Lab — gallery
//
//  The entry point: pick one of the five schedule designs and use it for real.
//  Each design opens full-screen with its own navigation stack (one nav bar per
//  screen, per NAV.1), so what you're evaluating is the design itself and not a
//  frame around it.
//
//  Data source is switchable at the top: Live reads the org's real sessions
//  (one-shot fetch, read-only, no realtime subscription — it cannot interfere
//  with the production schedule screens), Sample runs a fixed three-week set
//  built to contain the hard cases: overlaps, a three-day job, a draft, all-day
//  and partial time off, a six-person crew, and an empty day.

import SwiftUI

struct ScheduleDesignLabView: View {
    @ObservedObject private var store = ScheduleLabStore.shared
    @State private var presented: LabDesign?
    /// Reopens on whichever design you were last looking at.
    @AppStorage("scheduleLabLastDesign") private var lastDesign: String = LabDesign.rail.rawValue

    var body: some View {
        List {
            Section {
                dataSourceRow
                statusRow
            } header: {
                Text("Data")
            } footer: {
                Text("The lab never writes. Live is a read-only fetch of your organization's sessions and time off for the surrounding twelve weeks.")
            }

            Section("Designs") {
                ForEach(LabDesign.allCases) { design in
                    Button {
                        presented = design
                    } label: {
                        designRow(design)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button {
                    presented = LabDesign(rawValue: lastDesign) ?? .rail
                } label: {
                    Label("Resume \(( LabDesign(rawValue: lastDesign) ?? .rail).title)",
                          systemImage: "play.circle.fill")
                        .font(.headline)
                }
            } footer: {
                Text("Once you're in, the switcher at the bottom-right swaps designs instantly — you don't have to come back here.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to judge these")
                        .font(.subheadline.weight(.semibold))
                    Text("""
                    Open each one on the day you actually work. The questions that separate them: how fast can you tell what is next, can you see a double-booking, does a three-day job read as one job, and does a draft look different from a published shift.
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Schedule Design Lab")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.loadIfNeeded() }
        .fullScreenCover(item: $presented) { design in
            LabDesignRunner(initial: design, lastDesign: $lastDesign) { presented = nil }
        }
    }

    private var dataSourceRow: some View {
        Picker("Source", selection: Binding(
            get: { store.dataSource },
            set: { store.setDataSource($0) }
        )) {
            ForEach(ScheduleLabStore.DataSource.allCases) { source in
                Text(source.rawValue).tag(source)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var statusRow: some View {
        if store.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading…").foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("\(store.sessions.count) sessions", systemImage: "calendar")
                    Spacer()
                    Label("\(store.timeOff.count) time off", systemImage: "sun.max")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                if let error = store.loadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func designRow(_ design: LabDesign) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(design.tint.gradient)
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: design.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(design.title).font(.headline)
                Text(design.premise)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Designs

enum LabDesign: String, CaseIterable, Identifiable {
    case rail, deck, board, agenda, ambient

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rail: return "1 · Rail"
        case .deck: return "2 · Deck"
        case .board: return "3 · Board"
        case .agenda: return "4 · Agenda"
        case .ambient: return "5 · Ambient"
        }
    }

    var premise: String {
        switch self {
        case .rail:
            return "A real time axis for the day. Overlaps sit side by side, a live now-line runs through it. Detail is a run of show."
        case .deck:
            return "One shift at a time as a full card you flick through. Tapping grows the card into the detail."
        case .board:
            return "All seven days as tracks against one hour axis — the whole week's shape without tapping. Detail is a sheet you can peek at."
        case .agenda:
            return "A continuous, searchable document with swipe actions. Densest of the five and the closest to stock iOS."
        case .ambient:
            return "Leads with a live countdown to the next call time; glass layers tinted by the session's own colour."
        }
    }

    var symbol: String {
        switch self {
        case .rail: return "calendar.day.timeline.left"
        case .deck: return "rectangle.stack.fill"
        case .board: return "chart.bar.xaxis"
        case .agenda: return "list.bullet.rectangle.portrait"
        case .ambient: return "timer"
        }
    }

    var tint: Color {
        switch self {
        case .rail: return .indigo
        case .deck: return .pink
        case .board: return .teal
        case .agenda: return .blue
        case .ambient: return .purple
        }
    }
}

/// Runs a design full-screen with the one piece of lab chrome that matters:
/// an always-present switcher. Comparing designs means flipping between them on
/// the same day, so switching is one tap from inside any of them — the gallery
/// is only for the first entry.
private struct LabDesignRunner: View {
    @State private var design: LabDesign
    @State private var expanded = false
    @Binding var lastDesign: String
    let onClose: () -> Void

    init(initial: LabDesign, lastDesign: Binding<String>, onClose: @escaping () -> Void) {
        self._design = State(initialValue: initial)
        self._lastDesign = lastDesign
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // .id forces a clean rebuild per design: you always land on each
            // design's own root, never inside the previous one's detail stack.
            content
                .id(design)
                .transition(.opacity)

            switcher
                .padding(.trailing, 14)
                .padding(.bottom, 30)
        }
        .onAppear { lastDesign = design.rawValue }
        // Swipe anywhere along the bottom edge to page through the designs.
        .simultaneousGesture(
            DragGesture(minimumDistance: 60)
                .onEnded { value in
                    guard value.startLocation.y > UIScreen.main.bounds.height - 120,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    step(value.translation.width < 0 ? 1 : -1)
                }
        )
    }

    // MARK: switcher

    private var switcher: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if expanded {
                ForEach(LabDesign.allCases.reversed()) { option in
                    Button {
                        select(option)
                    } label: {
                        HStack(spacing: 8) {
                            Text(option.title)
                                .font(.caption.weight(.semibold))
                            Image(systemName: option.symbol)
                                .font(.caption)
                                .frame(width: 18)
                        }
                        .foregroundStyle(option == design ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background {
                            if option == design {
                                Capsule().fill(option.tint)
                            } else {
                                Capsule().fill(.regularMaterial)
                            }
                        }
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Button {
                    onClose()
                } label: {
                    HStack(spacing: 8) {
                        Text("Gallery").font(.caption.weight(.semibold))
                        Image(systemName: "square.grid.2x2.fill").font(.caption).frame(width: 18)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(.regularMaterial))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                    .foregroundStyle(.secondary)
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                // Previous / next without opening the list at all.
                Button { step(-1) } label: {
                    Image(systemName: "chevron.left").font(.caption.weight(.bold)).frame(width: 26, height: 34)
                }
                Text(design.title)
                    .font(.caption.weight(.bold))
                    .contentTransition(.opacity)
                Button { step(1) } label: {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).frame(width: 26, height: 34)
                }
                Divider().frame(height: 18)
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.caption2.weight(.bold))
                    .frame(width: 22, height: 34)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(LabAnim.pop) { expanded.toggle() }
                        LabHaptics.impact(.light)
                    }
            }
            .padding(.horizontal, 10)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(design.tint.opacity(0.45), lineWidth: 1.5))
            .foregroundStyle(.primary)
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        }
    }

    private func select(_ option: LabDesign) {
        withAnimation(LabAnim.gentle) {
            design = option
            expanded = false
        }
        lastDesign = option.rawValue
        LabHaptics.impact(.medium)
    }

    private func step(_ delta: Int) {
        let all = LabDesign.allCases
        guard let index = all.firstIndex(of: design) else { return }
        let next = all[(index + delta + all.count) % all.count]
        select(next)
    }

    @ViewBuilder
    private var content: some View {
        switch design {
        case .rail: RailScheduleView()
        case .deck: DeckScheduleView()
        case .board: BoardScheduleView()
        case .agenda: AgendaScheduleView()
        case .ambient: AmbientScheduleView()
        }
    }
}

// MARK: - Preview

struct ScheduleDesignLabView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ScheduleDesignLabView()
        }
    }
}
