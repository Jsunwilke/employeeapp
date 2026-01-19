//
//  ConflictResolutionView.swift
//  Iconik Employee
//
//  DEPRECATED: This view was used for the legacy SyncEngine conflict resolution.
//  PowerSync handles conflicts differently (last-write-wins).
//  This is a stub that always shows "No Conflicts" since PowerSync handles conflicts automatically.
//

import SwiftUI

struct ConflictResolutionView: View {
    let onComplete: (Bool) -> Void

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                Text("No Conflicts")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("PowerSync handles conflicts automatically.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text("Data is synchronized using last-write-wins.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Done") {
                    onComplete(true)
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Sync Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct ConflictResolutionView_Previews: PreviewProvider {
    static var previews: some View {
        ConflictResolutionView(onComplete: { _ in })
    }
}
