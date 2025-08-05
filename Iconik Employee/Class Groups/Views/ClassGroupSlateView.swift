import SwiftUI

struct ClassGroupSlateView: View {
    let grade: String
    let teacher: String
    let schoolName: String?
    
    @Environment(\.presentationMode) var presentationMode
    @State private var orientation = UIDeviceOrientation.unknown
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Full white background
                Color.white
                    .edgesIgnoringSafeArea(.all)
                
                // Content
                VStack(spacing: dynamicSpacing(for: geometry.size)) {
                    // Grade in large bold text
                    Text(grade)
                        .font(.system(size: dynamicFontSize(for: geometry.size, multiplier: 1.0), weight: .bold, design: .default))
                        .foregroundColor(.black)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    
                    // Teacher name in large bold text
                    Text(teacher)
                        .font(.system(size: dynamicFontSize(for: geometry.size, multiplier: 0.9), weight: .bold, design: .default))
                        .foregroundColor(.black)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    
                    // Optional school name
                    if let schoolName = schoolName, !schoolName.isEmpty {
                        Text(schoolName)
                            .font(.system(size: dynamicFontSize(for: geometry.size, multiplier: 0.5), weight: .medium, design: .default))
                            .foregroundColor(.gray)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .padding(.top, 10)
                    }
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Exit button overlay
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(Color.gray.opacity(0.6))
                                .background(Circle().fill(Color.white.opacity(0.9)))
                        }
                        .padding(20)
                    }
                    Spacer()
                }
                
                // Tap anywhere to dismiss
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        presentationMode.wrappedValue.dismiss()
                    }
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            // Maximize screen brightness
            UIScreen.main.brightness = 1.0
            
            // Keep screen awake
            UIApplication.shared.isIdleTimerDisabled = true
            
            // Detect orientation
            orientation = UIDevice.current.orientation
            
            // Listen for orientation changes
            NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                orientation = UIDevice.current.orientation
            }
        }
        .onDisappear {
            // Restore idle timer
            UIApplication.shared.isIdleTimerDisabled = false
            
            // Note: We don't restore brightness as the user may have set it manually
        }
    }
    
    // Dynamic font sizing based on screen size and orientation
    private func dynamicFontSize(for size: CGSize, multiplier: CGFloat) -> CGFloat {
        let baseSize: CGFloat = min(size.width, size.height) * 0.15
        return baseSize * multiplier
    }
    
    // Dynamic spacing based on screen size
    private func dynamicSpacing(for size: CGSize) -> CGFloat {
        return min(size.width, size.height) * 0.05
    }
}

// MARK: - Full Screen Modifier
extension View {
    func fullScreenSlate() -> some View {
        self
            .fullScreenCover(isPresented: .constant(true)) {
                self
            }
    }
}

// MARK: - Preview
struct ClassGroupSlateView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ClassGroupSlateView(
                grade: "3rd Grade",
                teacher: "Mrs. Smith",
                schoolName: "Lincoln Elementary"
            )
            .previewDisplayName("Portrait")
            
            ClassGroupSlateView(
                grade: "Kindergarten",
                teacher: "Ms. Johnson",
                schoolName: nil
            )
            .previewInterfaceOrientation(.landscapeLeft)
            .previewDisplayName("Landscape")
        }
    }
}