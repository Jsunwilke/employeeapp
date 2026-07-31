//  DeleteConfirmationAlert.swift
//  Iconik Employee — the hand-rolled confirmation modal, converted (AMB.11)
//
//  Consumed only by `SearchView`. Every user-facing string still comes from the
//  caller — this file contains none of its own, and that is deliberate.
//
//  TWO THINGS CHANGED:
//    - the 300pt `systemBackground` + radius 12 + `shadow(radius: 10)` panel is
//      now the one card container, and the two buttons are capsule controls
//      rather than hand-rolled rounded fills;
//    - the scrim's `.onTapGesture` had a FULLY COMMENTED-OUT body (finding N18):
//      a dimming layer that visibly accepted a tap and did nothing. It now
//      dismisses. Dismissing runs NEITHER action — tapping outside is a cancel,
//      and running the caller's secondary action from a gesture it never asked
//      to be wired to is not ours to invent.

import SwiftUI

struct AlertConfiguration {
    var title: String
    var message: String
    var primaryButtonTitle: String
    var secondaryButtonTitle: String?
    var isDestructive: Bool
    var primaryAction: () -> Void
    var secondaryAction: (() -> Void)?
}

// Reusable confirmation dialog that works on any action
struct ConfirmationDialogView: View {
    @Binding var isPresented: Bool
    var config: AlertConfiguration

    var body: some View {
        ZStack {
            if isPresented {
                // Semi-transparent background
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        isPresented = false
                    }
                    .accessibilityLabel("Dismiss")

                // Alert content
                VStack(spacing: 16) {
                    Text(config.title)
                        .font(.headline)

                    Text(config.message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        if let secondaryTitle = config.secondaryButtonTitle,
                           let secondaryAction = config.secondaryAction {
                            Button {
                                isPresented = false
                                secondaryAction()
                            } label: {
                                Text(secondaryTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .frame(minWidth: 100)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    // ambient-allow: a dialog button, not a container.
                                    .background(Capsule().fill(.ultraThinMaterial))
                                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            isPresented = false
                            config.primaryAction()
                        } label: {
                            Text(config.primaryButtonTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 100)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                // ambient-allow: a dialog button, not a container.
                                .background(Capsule().fill(config.isDestructive ? Color.red : AmbientStyle.brand))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 300)
                .ambientCard(density: .roomy, fill: .surface,
                             border: .hairline(Color.primary.opacity(0.10)),
                             contentAlignment: .center)
                .transition(.scale)
            }
        }
        .animation(.easeInOut, value: isPresented)
    }
}
