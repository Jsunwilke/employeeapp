//  AppTheme.swift
//  Iconik Employee — light / dark / system, in one place
//
//  CONSOLIDATED IN AMB.12. Before this file the app carried TWO copies of
//  `applyAppTheme()` with DIFFERENT BODIES — one in `MainEmployeeView`, one in
//  `Iconik_EmployeeApp` — and the `"appTheme"` storage key was declared twice.
//  Only the window override ever did anything.
//
//  DELETED WITH THE MERGE, because batch 4's inventory proved both statements
//  dead: the copy in `MainEmployeeView` also wrote the string "Light"/"Dark" into
//  `UserDefaults` under `"AppleInterfaceStyle"` and posted an
//  `AppleInterfaceThemeChangedNotification`. Nothing in this repo reads that key
//  and nothing subscribes to that notification — they are a system-looking API
//  that this app invented for itself, and carrying them forward would keep
//  implying the theme reaches something outside the app. It does not.
//
//  THE ONE BEHAVIOURAL FIX: the override is applied to the scene that is actually
//  in FRONT. Both old copies took `connectedScenes.first`, which is an unordered
//  set — on an iPad with two windows open that could apply the theme to a scene
//  the user is not looking at.

import SwiftUI
import UIKit

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// The single `@AppStorage` key. Anything that reads or writes the theme
    /// reads or writes this.
    static let storageKey = "appTheme"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "gear"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Tolerant of anything already in storage — an unrecognised string means
    /// "follow the system", which is the default the app shipped with.
    static func from(storedValue: String) -> AppTheme {
        AppTheme(rawValue: storedValue) ?? .system
    }

    /// Push the stored choice onto the windows of the FOREGROUND scene.
    static func apply(_ theme: AppTheme) {
        DispatchQueue.main.async {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            guard let active else { return }
            for window in active.windows {
                window.overrideUserInterfaceStyle = theme.interfaceStyle
            }
        }
    }

    static func apply(storedValue: String) {
        apply(from(storedValue: storedValue))
    }
}
