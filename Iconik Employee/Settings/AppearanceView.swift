//  AppearanceView.swift
//  Iconik Employee — light / dark / system, as a Settings screen (AMB.12)
//
//  THE PICKER MOVES. It was a sheet off the home profile hamburger, sitting in that
//  menu directly beside "Settings" itself — two entries in one menu where one of
//  them is a settings screen. It is a Settings screen now, and the hamburger keeps
//  one entry.
//
//  BEHAVIOUR IS UNCHANGED: the choice commits the instant a row is tapped and there
//  is no Cancel. What changes is that this is a pushed screen in the app's design
//  language rather than a bare untokenised `List` in a sheet, and the checkmark is
//  tinted rather than a bare system glyph.
//
//  The light/dark/system decision itself lives in `Utilities/AppTheme.swift` — the
//  storage key, the parse and the window override, in one place. This screen only
//  draws it.

import SwiftUI

struct AppearanceView: View {
    @AppStorage(AppTheme.storageKey) private var storedTheme: String = AppTheme.system.rawValue

    private var selected: AppTheme { AppTheme.from(storedValue: storedTheme) }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    AmbientSectionTitle("Appearance", trailing: selected.label)

                    VStack(spacing: AmbientDensity.compact.stackSpacing) {
                        ForEach(AppTheme.allCases) { theme in
                            row(theme)
                        }
                    }

                    Text("Applies to this device only. \"System\" follows the iPhone or iPad's own light/dark setting.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        // A PUSHED screen insets itself — an inset does not travel out of a
        // navigation container into what that container pushes.
        .tabBarClearance()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ theme: AppTheme) -> some View {
        let isSelected = selected == theme
        return Button {
            withAnimation(AmbientMotion.snappy) { storedTheme = theme.rawValue }
            AppTheme.apply(theme)
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: theme.symbol)
                    .foregroundStyle(isSelected ? SettingsStyle.tint : Color.secondary)
                    .frame(width: 22)
                Text(theme.label).font(.subheadline)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SettingsStyle.tint)
                }
            }
            .ambientCard(density: .compact, fillWidth: true)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
