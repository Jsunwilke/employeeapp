import SwiftUI

// MARK: - iPad Floating Keypad
// Drag-anywhere alternative to iPadVerticalStripKeyboard, toggled from a key
// on either keyboard (preference lives in KeyboardManager.iPadKeyboardStyle).
// Phone-style 3-column grid with Prev/Next/Done. Position persists per device.
// Keys: 1-9, -, +, 0, ⌫, ▲, Next ▼, Done

struct FloatingNumberKeypad: View {
    @Binding var text: String
    let containerSize: CGSize
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onDismiss: () -> Void
    var onSwitchStyle: () -> Void

    @StateObject private var keyboardManager = KeyboardManager.shared
    @State private var displayText: String = ""  // Local state to force updates
    @State private var position: CGPoint = .zero
    @State private var dragOrigin: CGPoint? = nil
    @State private var hasLoadedPosition = false

    private static let positionXKey = "iPadFloatingKeypadX"
    private static let positionYKey = "iPadFloatingKeypadY"

    private let panelWidth: CGFloat = 232
    private let panelHeight: CGFloat = 354
    private let spacing: CGFloat = 6
    private let buttonHeight: CGFloat = 44
    private let edgeMargin: CGFloat = 16

    var body: some View {
        VStack(spacing: spacing) {
            dragZone
            digitRow(["1", "2", "3"])
            digitRow(["4", "5", "6"])
            digitRow(["7", "8", "9"])
            specialRow
            navigationRow
        }
        .padding(12)
        .frame(width: panelWidth, height: panelHeight)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(UIColor.systemGray6))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        )
        .offset(x: clamped(position).x, y: clamped(position).y)
        .onAppear {
            displayText = text
            if !hasLoadedPosition {
                hasLoadedPosition = true
                loadPosition()
            }
        }
        .onChange(of: text) { newValue in
            displayText = newValue
        }
    }

    // MARK: Drag zone (header + display box)

    private var dragZone: some View {
        VStack(spacing: spacing) {
            // Header: layout-switch button + grab bar
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 40, height: 5)

                HStack {
                    Button(action: onSwitchStyle) {
                        Image(systemName: "rectangle.righthalf.inset.filled")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .frame(height: 28)

            // Display box showing editing context and current text
            VStack(alignment: .leading, spacing: 2) {
                if !keyboardManager.editingContext.isEmpty {
                    Text(keyboardManager.editingContext)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text(displayText.isEmpty ? "Enter image numbers" : displayText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(displayText.isEmpty ? Color.gray : Color.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.none, value: displayText)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)
        }
        .contentShape(Rectangle())
        .gesture(
            // Global coordinate space: translation must be measured against a
            // frame that does not move with the panel, or the drag feeds back
            // into itself and jitters.
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if dragOrigin == nil {
                        dragOrigin = position
                    }
                    if let origin = dragOrigin {
                        position = clamped(CGPoint(x: origin.x + value.translation.width,
                                                   y: origin.y + value.translation.height))
                    }
                }
                .onEnded { _ in
                    dragOrigin = nil
                    savePosition()
                }
        )
    }

    // MARK: Key rows

    private func digitRow(_ digits: [String]) -> some View {
        HStack(spacing: spacing) {
            ForEach(digits, id: \.self) { digit in
                keypadButton(label: digit) {
                    text.append(digit)
                    displayText = text
                }
            }
        }
        .frame(height: buttonHeight)
    }

    private var specialRow: some View {
        HStack(spacing: spacing) {
            // First column: hyphen and plus (each half width)
            HStack(spacing: spacing) {
                keypadButton(label: "-", fontSize: 24) {
                    text.append("-")
                    displayText = text
                }
                keypadButton(label: "+", fontSize: 24) {
                    text.append("+")
                    displayText = text
                }
            }

            // Second column: zero
            keypadButton(label: "0") {
                text.append("0")
                displayText = text
            }

            // Third column: backspace
            Button(action: {
                if !text.isEmpty {
                    text.removeLast()
                    displayText = text
                }
            }) {
                Image(systemName: "delete.left.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(UIColor.label))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .frame(height: buttonHeight)
    }

    private var navigationRow: some View {
        HStack(spacing: spacing) {
            // Prev button
            Button(action: { onUp?() }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(maxHeight: .infinity)
                    .frame(width: 44)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(8)
                    .shadow(radius: 1)
            }
            .buttonStyle(.plain)

            // Next button (prominent — primary workflow action)
            Button(action: { onDown?() }) {
                HStack(spacing: 4) {
                    Text("Next")
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "arrow.down")
                        .font(.system(size: 13))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.green)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Done button
            Button(action: onDismiss) {
                Text("Done")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxHeight: .infinity)
                    .frame(width: 64)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .frame(height: buttonHeight)
    }

    private func keypadButton(label: String, fontSize: CGFloat = 24, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: fontSize, weight: .regular))
                .foregroundColor(Color(UIColor.label))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(8)
                .shadow(radius: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: Position persistence

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), max(0, containerSize.width - panelWidth)),
            y: min(max(point.y, 0), max(0, containerSize.height - panelHeight))
        )
    }

    private func loadPosition() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.positionXKey) != nil,
           defaults.object(forKey: Self.positionYKey) != nil {
            position = clamped(CGPoint(x: defaults.double(forKey: Self.positionXKey),
                                       y: defaults.double(forKey: Self.positionYKey)))
        } else {
            // Default: bottom-trailing corner
            position = clamped(CGPoint(x: containerSize.width - panelWidth - edgeMargin,
                                       y: containerSize.height - panelHeight - edgeMargin))
        }
    }

    private func savePosition() {
        let defaults = UserDefaults.standard
        defaults.set(Double(position.x), forKey: Self.positionXKey)
        defaults.set(Double(position.y), forKey: Self.positionYKey)
    }
}

// Preview
struct FloatingNumberKeypad_Previews: PreviewProvider {
    static var previews: some View {
        FloatingNumberKeypad(
            text: .constant("123-125"),
            containerSize: CGSize(width: 1024, height: 768),
            onUp: {},
            onDown: {},
            onDismiss: {},
            onSwitchStyle: {}
        )
        .previewLayout(.fixed(width: 1024, height: 768))
    }
}
