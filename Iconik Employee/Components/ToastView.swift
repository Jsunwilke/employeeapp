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
//
// NOTE, AMB.5 (2026-07-26): this 50pt is UNVERIFIED against the floating tab bar
// AMB.4 introduced, and an attempted fix was reverted rather than shipped.
//
// The bar's own published clearance is TabBarMetrics.clearance (84pt), and 50 is
// less than that — which looks like a collision. But the two numbers are not
// measured from the same datum: the clearance is a safe-area INSET while this is
// plain padding on an overlay, the toast grows upward from it, and the clearance
// carries a 10pt breathing margin. Worse, two of the three call sites (ScanView
// and DailyJobReportView) are shell-wrapped features that ALREADY receive the
// shell's 84pt inset in MainEmployeeView.featureContainer, so adding padding here
// would double-count for them and only the MainEmployeeView site is bare.
//
// Whether a toast is actually clipped by the bar needs one look on a device.
// Recorded in AMB_SHELL_INVENTORY.md; the toast belongs to no phase yet.
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