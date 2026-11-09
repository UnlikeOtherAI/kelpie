import AppKit
import SwiftUI

/// Observe the initial click before AppKit transfers focus to its field editor.
/// Later clicks retain native caret placement, drag selection and IME behavior.
final class AddressTextField: NSTextField {
    private var clickMonitor: Any?

    var isEditingAddress: Bool {
        guard let editor = currentEditor() else { return false }
        return window?.firstResponder === editor
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        guard window != nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, event.window === self.window,
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
                  !self.isEditingAddress else { return event }
            // NSWindow moves focus before calling mouseDown. Consume only the
            // initial click here so native tracking cannot collapse selection.
            self.selectText(nil)
            return nil
        }
    }

    deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }
}

struct AddressField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var focusRequested: Bool
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
        // Native edit notifications already update the binding. Equal values
        // leave caret/IME state alone; a different value is a model replacement,
        // such as selecting another tab, and must reach the focused editor too.
        if field.stringValue != text { field.stringValue = text }
        field.textColor = color
        if focusRequested && !context.coordinator.focusPending {
            context.coordinator.focusPending = true
            DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
                guard let coordinator else { return }
                coordinator.focusPending = false
                guard let field, field.window != nil else { return }
                field.selectText(nil)
                coordinator.parent.isFocused = true
                coordinator.parent.focusRequested = false
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressField
        var focusPending = false

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
