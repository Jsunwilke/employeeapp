//
//  CreateEquipmentView.swift
//  Iconik Employee
//
//  Equipment Management Feature - Create Equipment (Placeholder)
//
//  Lifted out of AllEquipmentView.swift when that file was deleted in AMB.3. It is
//  carried over UNCHANGED and still a placeholder: the "+" button in the inventory
//  has always opened this stub, and building the real creation form is a feature,
//  not a restyle. Kept rather than dropped so the gated "+" keeps leading somewhere
//  and the gap stays visible.
//

import SwiftUI

struct CreateEquipmentView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Create Equipment")
                .font(.title)

            Text("Equipment creation form will be implemented here")
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .navigationTitle("New Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
