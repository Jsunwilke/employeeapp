import SwiftUI

struct NFCSessionSelectionView: View {
    let sessions: [Session]
    @Binding var selectedSession: Session?
    @Binding var isPresented: Bool
    @State private var searchText = ""
    
    // Filtered sessions based on search
    private var filteredSessions: [Session] {
        if searchText.isEmpty {
            return sessions
        } else {
            return sessions.filter { session in
                session.schoolName.localizedCaseInsensitiveContains(searchText) ||
                session.date?.contains(searchText) ?? false ||
                session.getPhotographerNames().joined(separator: ", ").localizedCaseInsensitiveContains(searchText) ||
                (session.sessionType?.joined(separator: ", ").localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if sessions.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No available sessions in the next 2 weeks")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredSessions.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No sessions match your search")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        Text("Try adjusting your search terms")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredSessions) { session in
                        SessionRowView(session: session) {
                            selectedSession = session
                            isPresented = false
                        }
                    }
                    .listStyle(PlainListStyle())
                    .searchable(text: $searchText, prompt: "Search sessions")
                }
            }
            .navigationTitle("Select Session")
            .navigationBarItems(
                leading: Button("Cancel") {
                    isPresented = false
                }
            )
        }
    }
}

struct SessionRowView: View {
    let session: Session
    let onTap: () -> Void
    
    private var formattedDate: String {
        guard let dateString = session.date else { return "" }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        if let date = dateFormatter.date(from: dateString) {
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            return dateFormatter.string(from: date)
        }
        
        return dateString
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // School name and date
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.schoolName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if let sessionTypes = session.sessionType, !sessionTypes.isEmpty {
                            Text(sessionTypes.joined(separator: ", ").capitalized)
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formattedDate)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        if let startTime = session.startTime, let endTime = session.endTime {
                            Text("\(startTime) - \(endTime)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Photographers
                let photographers = session.getPhotographerNames()
                if !photographers.isEmpty {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(photographers.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                // Notes if available
                if let notes = session.description, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Preview Provider
struct NFCSessionSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        NFCSessionSelectionView(
            sessions: [],
            selectedSession: .constant(nil),
            isPresented: .constant(true)
        )
    }
}