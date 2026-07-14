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
    var body: some View {
        Button {
            TabBarManager.shared.selectedTab = "home"
        } label: {
            Image(systemName: "house.fill")
        }
        .accessibilityLabel("Home")
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
