//  ActivityShareSheet.swift
//  Iconik Employee — the system share sheet, once
//
//  CONSOLIDATED IN AMB.12. Three functionally IDENTICAL `UIActivityViewController`
//  wrappers existed under three names, differing only in what they called their
//  one parameter:
//
//      `ShareSheet`        declared in the YEARBOOK module (`YearbookChecklistView`)
//      `ImageShareSheet`   declared in CHAT (`FullScreenImageViewer`)
//      `MetricsShareSheet` file-private inside SETTINGS' metrics dashboard
//
//  The one that mattered was the first. `ShareSheet` was declared in Yearbook and
//  CONSUMED BY TRAINING — a cross-feature dependency on a type Training does not
//  own, in a module its own phase would never open. Batch 4's inventory recorded
//  it as a coupling rather than a location precisely because the declaration MOVED
//  between two reads while the inventory was being written: AMB.10's Yearbook
//  conversion shifted it from one line to another mid-audit. A rename or a
//  `private` over there breaks Training at compile time, and nothing about
//  Training says so.
//
//  Now nobody owns it, which is the point — it belongs to no feature.

import SwiftUI
import UIKit

/// Presents the system share sheet. Present it from `.sheet`, which is what all
/// four call sites did and still do; SwiftUI supplies the iPad presentation
/// anchor that a bare `UIActivityViewController` would need.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
