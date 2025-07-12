import SwiftUI

struct NotesInputView: View {
    @Environment(\.presentationMode) var presentationMode
    
    let isClockOut: Bool
    let onComplete: (String?) -> Void
    
    @State private var notes = ""
    @State private var characterCount = 0
    
    private let maxCharacters = 500
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: isClockOut ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(isClockOut ? .red : .blue)
                    
                    Text(isClockOut ? "Clocking Out" : "Clocking In")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Add optional notes for this time entry")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)
                
                Spacer()
                
                // Notes input section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes (optional)")
                        .font(.headline)
                    
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                        .onChange(of: notes) { value in
                            // Limit character count
                            if value.count > maxCharacters {
                                notes = String(value.prefix(maxCharacters))
                            }
                            characterCount = notes.count
                        }
                    
                    // Character count
                    HStack {
                        Spacer()
                        Text("\(characterCount)/\(maxCharacters)")
                            .font(.caption)
                            .foregroundColor(characterCount > maxCharacters * 9/10 ? .red : .secondary)
                    }
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        onComplete(notes.isEmpty ? nil : notes)
                    }) {
                        HStack {
                            Image(systemName: isClockOut ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title2)
                            Text(isClockOut ? "Clock Out" : "Clock In")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(isClockOut ? Color.red : Color.blue)
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundColor(.gray)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .onAppear {
            characterCount = notes.count
        }
    }
}

#Preview {
    NotesInputView(isClockOut: true) { notes in
        print("Notes: \(notes ?? "None")")
    }
}