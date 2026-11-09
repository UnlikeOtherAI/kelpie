import AppKit
import SwiftUI

/// The cell owns the transition into editing; later clicks belong to the
/// existing field editor and retain native caret, drag selection and IME behavior.
final class AddressTextFieldCell: NSTextFieldCell {
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                       delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: rect, in: controlView, editor: textObj, delegate: delegate, event: nil)
        textObj.selectAll(nil)
    }
}

final class AddressTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { AddressTextFieldCell.self }
        set { super.cellClass = newValue }
    }

    var isEditingAddress: Bool {
        guard let editor = currentEditor() else { return false }
        return window?.firstResponder === editor
    }
}

struct AddressField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let focusRequest: Int
    let color: NSColor
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> AddressTextField {
        let field = AddressTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.placeholderString = "Search or enter website name"
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setAccessibilityIdentifier("browser.address")
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: AddressTextField, context: Context) {
        context.coordinator.parent = self
        let focusChanged = context.coordinator.focusRequest != focusRequest
        // AppKit owns the live editor and its selection. A SwiftUI focus update
        // must not rewrite that editor while the person is entering text.
        if (!field.isEditingAddress || focusChanged) && field.stringValue != text { field.stringValue = text }
        field.textColor = color
        if focusChanged {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { [weak field] in
                guard let field, field.window != nil else { return }
                field.selectText(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressField
        var focusRequest = 0

        init(_ parent: AddressField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) { parent.isFocused = true }

        func controlTextDidEndEditing(_ notification: Notification) { parent.isFocused = false }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}
