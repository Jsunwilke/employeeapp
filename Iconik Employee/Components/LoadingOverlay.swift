//  LoadingOverlay.swift
//  Iconik Employee — the blocking "wait" scrim
//
//  CONVERTED IN AMB.12. One of the shell orphans: it carried a drift-allowlist
//  row and no phase, and its single consumer is `NFC/ScanView.swift`.
//
//  WHAT IT WAS: a black scrim under a black rounded slab with a white spinner —
//  the same in light mode and dark mode, because both colours were hardcoded
//  black. On the ambient light theme it read as a modal from a different app.
//
//  WHAT CHANGED, and nothing else did:
//    - the panel is the app's card, so it takes the current appearance;
//    - the scrim is `.ultraThinMaterial` over a dimming layer rather than flat
//      black, which is what every other blocking surface in the app uses;
//    - it announces itself. It had no accessibility label at all, so VoiceOver
//      reached a screen that had silently stopped responding to touches;
//    - `.allowsHitTesting(true)` is now explicit rather than incidental. The
//      whole point of this view is that it swallows taps while a write is in
//      flight, and that was resting on the scrim's opacity being non-zero.
//
//  DELIBERATELY NOT ADDED, because both would be features and neither exists
//  anywhere in the app's blocking paths: a cancel affordance and a timeout. A
//  cancel button that cannot actually cancel the network call underneath it is
//  worse than no button.

import SwiftUI

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.96)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)

                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: 300)
            .ambientCard(density: .roomy, contentAlignment: .center)
        }
        .allowsHitTesting(true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    func loadingOverlay(isPresented: Binding<Bool>, message: String = "Loading...") -> some View {
        overlay {
            if isPresented.wrappedValue {
                LoadingOverlay(message: message)
                    .transition(.opacity)
            }
        }
        .animation(AmbientMotion.snappy, value: isPresented.wrappedValue)
    }
}
