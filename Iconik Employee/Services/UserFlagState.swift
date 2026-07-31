//  UserFlagState.swift
//  Iconik Employee — is the signed-in photographer flagged?
//
//  ONE STORE (D14, operator 2026-07-30). "Red means flagged" is app-wide, so
//  the flag has to be readable from the backdrop of every screen, not just from
//  home. This is that store, and it is deliberately the ONLY one: it does not
//  query anything and it does not listen to anything.
//
//  MainEmployeeView already loads `is_flagged` for the flag banner and already
//  keeps it fresh through a realtime channel on the user's row. It now writes
//  the result HERE instead of into its own `@State`, and reads it back from
//  here. AmbientBackdrop observes the same object. A second listener would be a
//  second answer, which is exactly what D14's "count stores, not call sites"
//  rules out.
//
//  The note and the flagging manager's name stay where they were — they are the
//  banner's business, and nothing else reads them.

import Foundation
import Combine

/// Not `@MainActor`-isolated: `AmbientBackdrop` holds it as a stored
/// `@ObservedObject` default, which is initialised from a nonisolated `init`.
/// Its one writer (`MainEmployeeView.loadFlagStatusFromSupabase`) is already
/// `@MainActor`, so every mutation still happens on the main thread.
final class UserFlagState: ObservableObject {
    static let shared = UserFlagState()

    /// Whether the signed-in user's row has `is_flagged` set. Written only by
    /// MainEmployeeView's existing flag load; read by its banner and by every
    /// AmbientBackdrop in the app.
    @Published var isFlagged: Bool = false

    private init() {}
}
