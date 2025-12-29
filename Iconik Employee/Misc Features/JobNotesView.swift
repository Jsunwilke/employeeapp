import SwiftUI
import Supabase

// Model for a school option
struct SchoolOption: Identifiable, Hashable {
    let id: String
    let value: String
    let schoolAddress: String
}

struct JobNotesView: View {
    // Store notes & school in AppStorage
    @AppStorage("jobNotes") var storedJobNotes: String = ""
    @AppStorage("jobNotesSchool") var storedJobNotesSchool: String = ""

    @State private var schoolOptions: [SchoolOption] = []
    @State private var selectedSchool: SchoolOption? = nil
    @State private var notes: String = ""

    @State private var errorMessage: String = ""

    var body: some View {
        VStack(spacing: 16) {
                if schoolOptions.isEmpty {
                    Text("Loading schools...")
                        .onAppear(perform: loadSchoolOptions)
                } else {
                    Picker("School Name", selection: $selectedSchool) {
                        ForEach(schoolOptions) { school in
                            Text(school.value).tag(school as SchoolOption?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: selectedSchool) { newValue in
                        // Auto-save the selected school name
                        if let s = newValue {
                            storedJobNotesSchool = s.value
                        }
                    }
                }

                TextEditor(text: $notes)
                    .border(Color.gray)
                    .frame(height: 200)
                    .onChange(of: notes) { newValue in
                        storedJobNotes = newValue
                    }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Job Notes")
        .onAppear {
            // Initialize local notes from AppStorage
            notes = storedJobNotes
        }
    }

    func loadSchoolOptions() {
        Task {
            do {
                let supabase = SupabaseManager.shared.client

                struct SchoolRecord: Decodable {
                    let id: String
                    let value: String?
                    let school_address: String?
                }

                let schools: [SchoolRecord] = try await supabase
                    .from("schools")
                    .select("id, value, school_address")
                    .eq("type", value: "school")
                    .execute()
                    .value

                await MainActor.run {
                    var temp: [SchoolOption] = []
                    for school in schools {
                        if let value = school.value,
                           let address = school.school_address {
                            let option = SchoolOption(id: school.id, value: value, schoolAddress: address)
                            temp.append(option)
                        }
                    }
                    // Sort by value
                    temp.sort { $0.value.lowercased() < $1.value.lowercased() }
                    self.schoolOptions = temp

                    // Match the stored school if any
                    if let match = temp.first(where: { $0.value == storedJobNotesSchool }) {
                        self.selectedSchool = match
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

