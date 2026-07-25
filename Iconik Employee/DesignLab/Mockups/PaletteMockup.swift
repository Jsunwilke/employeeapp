//  PaletteMockup.swift
//  Iconik Employee — the D11 palette proposal, on screen
//
//  ARC SCAFFOLDING. Deleted with the rest of the lab at AMB.12.
//
//  D11 says the ambient wash takes each screen's FEATURE colour. That only works
//  if the colours are distinct, and today they are not. This sheet shows the
//  problem and the proposal side by side, at the two sizes that matter: as a
//  SOLID TILE (what the home screen and bottom bar draw today) and as a WASH
//  (what every converted screen will draw behind it).
//
//  APPROVED AND APPLIED 2026-07-25. FeatureTheme now carries these 27 colours,
//  so this sheet has changed job: it was the proposal, and it is now the record
//  of what changed and why. The "was" swatches come from LabPalette.legacyColor,
//  a verbatim copy of the old map, so the before and after survive the port.

import SwiftUI

struct PaletteMockup: View {
    @State private var showingWash = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                intro
                collisions
                Divider()
                ForEach(LabPalette.families.indices, id: \.self) { index in
                    family(LabPalette.families[index])
                }
                batchOne
                footer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Every feature needs its own colour")
                .font(.title3.weight(.semibold))
            Text("The wash behind a screen is its feature's colour, so two features sharing a colour would be two screens you cannot tell apart. The old map had 27 features sharing 11 colours. All 27 are now distinct.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Preview as", selection: $showingWash) {
                Text("As a wash").tag(true)
                Text("As a tile").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.top, 4)

            Text(showingWash
                 ? "A wash is what you will see behind a converted screen — soft, and it has to stay distinguishable at low opacity."
                 : "A tile is what the home screen and the bottom bar draw today — solid, and it has to stay legible against white text.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - What is wrong today

    private var collisions: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("What was sharing a colour",
                                trailing: "\(LabPalette.currentCollisions.count) clashes")
            ForEach(Array(LabPalette.currentCollisions.enumerated()), id: \.offset) { _, clash in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color(hex: "#9AA0A6"))
                        .frame(width: 10, height: 10)
                        .padding(.top, 4)
                        .hidden()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clash.titles.joined(separator: " · "))
                            .font(.footnote.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(clash.titles.count) features, one colour")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ambientCard(density: .roomy, fillWidth: true)
    }

    // MARK: - A family

    private func family(_ family: LabPalette.Family) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle(family.name)
            Text(family.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(family.features) { feature in
                    row(feature)
                }
            }
        }
    }

    private func row(_ feature: LabPalette.Feature) -> some View {
        HStack(spacing: 12) {
            swatch(feature.legacyColor, label: "was")
            Image(systemName: "arrow.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
            swatch(feature.proposedColor, label: "now")

            VStack(alignment: .leading, spacing: 1) {
                Text(feature.title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                Text(feature.proposed.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func swatch(_ color: Color, label: String) -> some View {
        VStack(spacing: 3) {
            if showingWash {
                // The wash as it will actually be drawn: the tint bloom over the
                // page background, not the raw colour.
                ZStack {
                    Color(.systemBackground)
                    color.opacity(0.55).blur(radius: 6)
                }
                .frame(width: 52, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08)))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color)
                    .frame(width: 52, height: 34)
                    .overlay {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - The four that matter first

    private var batchOne: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Batch 1, side by side")
            Text("These four convert next, so they are the first four washes you will ever see together. Chat and Tasks are the closest pair in the whole palette — they are both People — so judge those two hardest.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                washTile("Equipment", LabPalette.proposedColor(for: "equipment"))
                washTile("Tasks", LabPalette.proposedColor(for: "tasks"))
                washTile("Chat", LabPalette.proposedColor(for: "chat"))
                washTile("Home", nil)
            }
        }
    }

    private func washTile(_ title: String, _ color: Color?) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Color(.systemBackground)
                if let color {
                    Circle().fill(color.opacity(0.55))
                        .frame(width: 90, height: 90)
                        .blur(radius: 26).offset(x: -18, y: -26)
                    Circle().fill(color.opacity(0.28))
                        .frame(width: 80, height: 80)
                        .blur(radius: 30).offset(x: 22, y: 22)
                }
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))

            Text(title)
                .font(.caption2.weight(.semibold))
            if color == nil {
                Text("no wash")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Why Home has no wash")
                .font(.footnote.weight(.semibold))
            Text("The dashboard is the container, not a feature, and it already carries nine coloured tiles. A wash behind them would fight every one. Proposed as a deliberate absence rather than a colour — say if you would rather it had one.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("These colours are LIVE as of 2026-07-25 — the home tiles, the All Features grid and the bottom bar all use them now. The \"was\" swatches are a copy of the old map, kept so this stays a before-and-after.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ambientCard(density: .roomy, fillWidth: true)
    }
}
