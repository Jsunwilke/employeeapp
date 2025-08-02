import SwiftUI

struct ToastView: View {
    let message: String
    let isSuccess: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(.white)
                .font(.title2)
            
            Text(message)
                .foregroundColor(.white)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding()
        .background(
            Capsule()
                .fill(isSuccess ? Color.green : Color.red)
        )
        .shadow(radius: 10)
    }
}

// View modifier for toast
extension View {
    func toast(isPresented: Binding<Bool>, message: String, isSuccess: Bool = true) -> some View {
        self.overlay(
            Group {
                if isPresented.wrappedValue {
                    VStack {
                        Spacer()
                        ToastView(message: message, isSuccess: isSuccess)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    withAnimation {
                                        isPresented.wrappedValue = false
                                    }
                                }
                            }
                    }
                    .padding(.bottom, 50)
                }
            }
        )
    }
}