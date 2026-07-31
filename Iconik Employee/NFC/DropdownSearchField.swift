//  DropdownSearchField.swift
//  Iconik Employee — the NFC surface's option picker
//
//  RESTYLED IN PLACE (AMB.11). Despite the name this contains no search field —
//  it is a `Menu` over `[String]`, and `SearchView` is its ONLY consumer, so it
//  is restyled here rather than replaced: the mockup's search surface keeps a
//  selection control for photographer / school / status and a text field only
//  for the number.
//
//  What changed: the 5pt grey stroke box became the one card container
//  (`.ambientCard`), matching `JobBoxSearchField` beside it, and the caller now
//  owns the horizontal padding — this view used to bake `.padding(.horizontal)`
//  in, so it could not sit in a padded stack without doubling.

import SwiftUI

struct DropdownSearchField: View {
    let placeholder: String
    let selectedText: String
    let options: [String]
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) {
                    onSelect(option)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedText.isEmpty ? placeholder : selectedText)
                    .font(.subheadline)
                    .foregroundStyle(selectedText.isEmpty
                                     ? AnyShapeStyle(.secondary)
                                     : AnyShapeStyle(.primary))
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .ambientCard(density: .compact, fill: .surface,
                         border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
        }
    }
}
