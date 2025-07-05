import SwiftUI
import FirebaseFirestore

struct SchoolInfoListView: View {
    @State private var schools: [SchoolItem] = []
    @State private var errorMessage: String = ""
    
    var body: some View {
        NavigationView {
            List(schools) { school in
                NavigationLink(destination: SchoolDetailView(schoolId: school.id)) {
                    VStack(alignment: .leading) {
                        Text(school.name)
                            .font(.headline)
                        Text(school.address)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("School Info")
            .onAppear(perform: loadSchools)
            .alert(isPresented: .constant(!errorMessage.isEmpty)) {
                Alert(title: Text("Error"),
                      message: Text(errorMessage),
                      dismissButton: .default(Text("OK")) {
                          errorMessage = ""
                      })
            }
        }
    }
    
    func loadSchools() {
        let db = Firestore.firestore()
        db.collection("dropdownData")
            .whereField("type", isEqualTo: "school")
            .getDocuments { snapshot, error in
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }
                guard let docs = snapshot?.documents else { return }
                var temp: [SchoolItem] = []
                for doc in docs {
                    let data = doc.data()
                    if let value = data["value"] as? String,
                       let address = data["schoolAddress"] as? String {
                        temp.append(SchoolItem(id: doc.documentID, name: value, address: address))
                    }
                }
                temp.sort { $0.name.lowercased() < $1.name.lowercased() }
                schools = temp
            }
    }
}
