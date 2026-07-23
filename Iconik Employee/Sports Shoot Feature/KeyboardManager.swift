import SwiftUI
import UIKit

// Which custom keyboard layout to use on iPad. Per-device preference,
// toggled from a key on either keyboard and persisted across launches.
enum IPadKeyboardStyle: String {
    case strip      // vertical column fixed to the right edge
    case floating   // drag-anywhere 3-column keypad
}

class KeyboardManager: ObservableObject {
    static let shared = KeyboardManager()

    private static let styleDefaultsKey = "iPadCustomKeyboardStyle"

    @Published var isShowingCustomKeyboard = false
    @Published var activeFieldText: Binding<String>?
    @Published var onUp: (() -> Void)?
    @Published var onDown: (() -> Void)?
    @Published var onDismiss: (() -> Void)?
    @Published var editingContext: String = ""
    @Published var useMiniMode: Bool = false

    @Published var iPadKeyboardStyle: IPadKeyboardStyle {
        didSet {
            UserDefaults.standard.set(iPadKeyboardStyle.rawValue, forKey: Self.styleDefaultsKey)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.styleDefaultsKey) ?? ""
        self.iPadKeyboardStyle = IPadKeyboardStyle(rawValue: stored) ?? .strip
    }

    func showKeyboard(for text: Binding<String>, context: String = "", miniMode: Bool = false, onUp: (() -> Void)? = nil, onDown: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.activeFieldText = text
        self.editingContext = context
        self.useMiniMode = miniMode
        self.onUp = onUp
        self.onDown = onDown
        self.onDismiss = onDismiss
        self.isShowingCustomKeyboard = true
    }

    func hideKeyboard() {
        self.onDismiss?()
        self.isShowingCustomKeyboard = false
        self.activeFieldText = nil
        self.editingContext = ""
        self.useMiniMode = false
        self.onUp = nil
        self.onDown = nil
        self.onDismiss = nil
    }
}

// MARK: - iPad Vertical Strip Keyboard
// Fixed to the right edge of the screen. Single column of buttons.
// Dynamically resizes so all buttons fit regardless of orientation.
// Keys: layout switch, 1-9, 0, -, +, ⌫, Done

struct iPadVerticalStripKeyboard: View {
    @Binding var text: String
    var onDismiss: (() -> Void)?
    var onSwitchStyle: (() -> Void)?

    private enum KeyAction {
        case append(String)
        case backspace
        case done
        case switchStyle
    }

    private struct KeyDef: Identifiable {
        let id: String
        let label: String
        let icon: String?
        let action: KeyAction
        let isAccent: Bool

        init(_ label: String, icon: String? = nil, action: KeyAction, isAccent: Bool = false) {
            self.id = label
            self.label = label
            self.icon = icon
            self.action = action
            self.isAccent = isAccent
        }
    }

    private let keys: [KeyDef] = [
        KeyDef("Layout", icon: "square.grid.3x3", action: .switchStyle),
        KeyDef("1", action: .append("1")),
        KeyDef("2", action: .append("2")),
        KeyDef("3", action: .append("3")),
        KeyDef("4", action: .append("4")),
        KeyDef("5", action: .append("5")),
        KeyDef("6", action: .append("6")),
        KeyDef("7", action: .append("7")),
        KeyDef("8", action: .append("8")),
        KeyDef("9", action: .append("9")),
        KeyDef("0", action: .append("0")),
        KeyDef("-", action: .append("-")),
        KeyDef("+", action: .append("+")),
        KeyDef("⌫", icon: "delete.left.fill", action: .backspace),
        KeyDef("Done", action: .done, isAccent: true),
    ]

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 2
            let totalSpacing = spacing * CGFloat(keys.count - 1)
            let buttonHeight = (geometry.size.height - totalSpacing) / CGFloat(keys.count)
            let fontSize = min(buttonHeight * 0.38, 20)

            VStack(spacing: spacing) {
                ForEach(keys) { key in
                    Button(action: { handleTap(key) }) {
                        Group {
                            if let icon = key.icon {
                                Image(systemName: icon)
                                    .font(.system(size: fontSize))
                            } else {
                                Text(key.label)
                                    .font(.system(size: key.isAccent ? fontSize * 0.7 : fontSize, weight: .medium))
                            }
                        }
                        .foregroundColor(key.isAccent ? .white : Color(UIColor.label))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(key.isAccent ? Color.blue : Color(UIColor.systemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(height: buttonHeight)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .frame(width: 56)
        .background(Color.clear)
    }

    private func handleTap(_ key: KeyDef) {
        switch key.action {
        case .append(let c):
            text.append(c)
        case .backspace:
            if !text.isEmpty { text.removeLast() }
        case .done:
            onDismiss?()
        case .switchStyle:
            onSwitchStyle?()
        }
    }
}

// MARK: - View Modifier

struct CustomKeyboardModifier: ViewModifier {
    @StateObject private var keyboardManager = KeyboardManager.shared

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    // iPad mini-mode keyboard is active (either style)
    private var iPadKeyboardActive: Bool {
        isIPad && keyboardManager.useMiniMode && keyboardManager.isShowingCustomKeyboard
    }

    private var stripActive: Bool {
        iPadKeyboardActive && keyboardManager.iPadKeyboardStyle == .strip
    }

    private var floatingActive: Bool {
        iPadKeyboardActive && keyboardManager.iPadKeyboardStyle == .floating
    }

    func body(content: Content) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                content
                    .frame(width: stripActive ? geo.size.width - 56 : geo.size.width)

                if stripActive,
                   let textBinding = keyboardManager.activeFieldText {
                    iPadVerticalStripKeyboard(
                        text: textBinding,
                        onDismiss: { keyboardManager.hideKeyboard() },
                        onSwitchStyle: { keyboardManager.iPadKeyboardStyle = .floating }
                    )
                    .frame(width: 56, height: geo.size.height)
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: keyboardManager.isShowingCustomKeyboard)
            .overlay(alignment: .topLeading) {
                if floatingActive,
                   let textBinding = keyboardManager.activeFieldText {
                    FloatingNumberKeypad(
                        text: textBinding,
                        containerSize: geo.size,
                        onUp: {
                            keyboardManager.onUp?()
                            keyboardManager.hideKeyboard()
                        },
                        onDown: {
                            keyboardManager.onDown?()
                            keyboardManager.hideKeyboard()
                        },
                        onDismiss: { keyboardManager.hideKeyboard() },
                        onSwitchStyle: { keyboardManager.iPadKeyboardStyle = .strip }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
            .overlay(alignment: .bottom) {
                if (!isIPad || !keyboardManager.useMiniMode) && keyboardManager.isShowingCustomKeyboard,
                   let textBinding = keyboardManager.activeFieldText {
                    CustomNumberKeyboard(
                        text: textBinding,
                        compactMode: false,
                        onDismiss: { keyboardManager.hideKeyboard() },
                        onUp: {
                            keyboardManager.onUp?()
                            keyboardManager.hideKeyboard()
                        },
                        onDown: {
                            keyboardManager.onDown?()
                            keyboardManager.hideKeyboard()
                        }
                    )
                    .transition(.move(edge: .bottom))
                    .animation(.easeInOut(duration: 0.25), value: true)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: keyboardManager.isShowingCustomKeyboard)
    }
}

extension View {
    func customKeyboardOverlay() -> some View {
        modifier(CustomKeyboardModifier())
    }
}
