import SwiftUI
import UIKit

enum KeyboardDismissal {
    static func dismiss() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .endEditing(true)
    }
}

extension View {
    func hideKeyboard() {
        KeyboardDismissal.dismiss()
    }

    func keyboardDismissible() -> some View {
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        KeyboardDismissal.dismiss()
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .foregroundStyle(Color.wolfBlue)
                    .accessibilityLabel("Dismiss keyboard")
                }
            }
    }
}
