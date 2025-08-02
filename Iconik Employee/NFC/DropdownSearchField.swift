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
            HStack {
                Text(selectedText.isEmpty ? placeholder : selectedText)
                    .foregroundColor(selectedText.isEmpty ? .gray : .primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundColor(.gray)
            }
            .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.gray, lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }
}