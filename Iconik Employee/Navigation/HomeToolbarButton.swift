import SwiftUI

/// A single, shared Home button for the top navigation bar of every feature
/// screen. There is no Home button in the bottom tab bar (Scan keeps the
/// center slot), so this is how the user returns to the dashboard from any
/// feature. Placed top-left (navigationBarLeading) at the root of each feature;
/// when the user drills into a detail, the system Back button takes that slot
/// instead, so root = Home, drilled-in = Back.
///
/// Used two ways: the shell adds it to the wrapper it puts around every
/// shell-dependent feature, and each self-nav feature (which owns its own
/// NavigationView) adds it to its own toolbar via `.homeToolbarItem()`.
struct HomeToolbarButton: View {
    // iPhone only. On iPad the bottom tab bar has no center Scan button, so Home
    // is the prominent center button there instead — the top-nav Home would be
    // redundant, so it is omitted on iPad.
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    var body: some View {
        if isPhone {
            Button {
                AmbientHaptics.selection()
                TabBarManager.shared.selectedTab = "home"
            } label: {
                // AMB.12: the glyph had no size, weight or tint at all, so it
                // took the bar's default and read lighter than the converted
                // chrome around it. Tinted to the app's own colour rather than a
                // feature's, because Home is not a feature.
                Image(systemName: "house.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AmbientStyle.brand)
            }
            .accessibilityLabel("Home")
        }
    }
}

extension View {
    /// Adds the shared Home button to this view's navigation bar (top-left).
    /// Attach inside (or on the content of) a NavigationView / NavigationStack.
    func homeToolbarItem() -> some View {
        self.toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HomeToolbarButton()
            }
        }
    }
}
