//  ClassGroupSlateView.swift
//  Iconik Employee — the shooting whiteboard, AMB.10
//
//  DELIBERATELY OUTSIDE THE DESIGN LANGUAGE, and that is the approved design
//  (mockup claim 4): hard white, huge black text, no wash, no card, no dark-mode
//  adaptation. It is held up in front of a class so the frame is labelled, and
//  every Ambient instinct — glass, tint, restraint — makes it worse. The board
//  itself lives in `ClassGroupsKit.swift` so the lab draws the same one; this file
//  owns the SCREEN behaviours, which a mockup must not have (it would change the
//  device's brightness from inside a gallery).
//
//  ONE APPROVED CHANGE: TAP-ANYWHERE-TO-DISMISS IS GONE. The old view laid a clear
//  `Color` with an `onTapGesture` over the whole board, so a photographer holding a
//  phone in one hand and a camera in the other lost the slate mid-shoot to a stray
//  thumb — and there is no undo: they found out when the frame came back
//  unlabelled. Only the X closes it now.
//
//  ALSO DELETED IN THE SAME CHANGE: the `fullScreenSlate()` View extension, which
//  was `fullScreenCover(isPresented: .constant(true)) { self }` — recursive,
//  un-dismissable, and with zero call sites in the app; and the `orientation`
//  `@State` with its `orientationDidChangeNotification` subscription, which was
//  written on every rotation and read by nothing (the layout is driven by the
//  GeometryReader's size, which already changes when the device turns).
//
//  UNCHANGED, and each is deliberate:
//    · Brightness goes to 1.0 on appear and is NEVER RESTORED — the user may have
//      set it manually, and lowering it under them mid-shoot is worse than leaving
//      it up.
//    · The idle timer is disabled on appear and restored on disappear, so the board
//      does not go dark between frames.
//    · The status bar is hidden.

import SwiftUI

struct ClassGroupSlateView: View {
    let grade: String
    let teacher: String
    let schoolName: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ClassGroupSlateBoard(grade: grade,
                             teacher: teacher,
                             schoolName: schoolName) { dismiss() }
            .statusBarHidden()
            .onAppear {
                // Maximize screen brightness — the board is read across a room.
                UIScreen.main.brightness = 1.0
                // Keep the screen awake between frames.
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false

                // Note: brightness is deliberately NOT restored — the user may have
                // set it manually.
            }
    }
}
