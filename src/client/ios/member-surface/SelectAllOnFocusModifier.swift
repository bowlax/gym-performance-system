import SwiftUI
import UIKit

struct SelectAllOnFocusModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { notification in
                guard let textField = notification.object as? UITextField else { return }
                selectAllWhenReady(in: textField)
            }
            .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { notification in
                guard let textView = notification.object as? UITextView else { return }
                selectAllWhenReady(in: textView)
            }
    }

    private func selectAllWhenReady(in responder: UIResponder) {
        // Defer until after UIKit applies the tap location; otherwise finger taps
        // place the caret after selectAll runs (Tab navigation does not).
        DispatchQueue.main.async {
            responder.perform(#selector(UIResponder.selectAll(_:)), with: nil)
        }
    }
}

extension View {
    func selectAllOnFocus() -> some View {
        modifier(SelectAllOnFocusModifier())
    }
}
