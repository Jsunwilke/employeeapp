import SwiftUI

struct ExampleTypeBadge: View {
    let type: String
    
    var isGoodExample: Bool {
        type == "example"
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isGoodExample ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12))
            
            Text(isGoodExample ? "Good Example" : "Needs Improvement")
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isGoodExample ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
        .foregroundColor(isGoodExample ? .green : .orange)
        .cornerRadius(20)
    }
}

#Preview {
    VStack(spacing: 20) {
        ExampleTypeBadge(type: "example")
        ExampleTypeBadge(type: "improvement")
    }
    .padding()
}