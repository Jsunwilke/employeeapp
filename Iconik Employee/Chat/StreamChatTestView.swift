import SwiftUI
import StreamChat

// Test view to verify Stream Chat integration
struct StreamChatTestView: View {
    @StateObject private var streamManager = StreamChatManager.shared
    @State private var connectionStatus = "Not Connected"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Stream Chat Integration Test")
                .font(.title)
                .padding()
            
            Text("Connection Status:")
                .font(.headline)
            
            Text(connectionStatus)
                .foregroundColor(streamManager.isConnected ? .green : .red)
                .font(.body)
            
            Button("Test Connection") {
                Task {
                    connectionStatus = "Connecting..."
                    do {
                        try await streamManager.connect()
                        connectionStatus = "Connected Successfully ✅"
                    } catch {
                        connectionStatus = "Connection Failed: \(error.localizedDescription)"
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            
            if streamManager.isConnected {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connected to Stream Chat")
                        .font(.headline)
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            }
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    StreamChatTestView()
}