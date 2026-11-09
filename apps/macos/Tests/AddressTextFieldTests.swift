import AppKit
import XCTest
@testable import KelpieBrowser

@MainActor
final class AddressTextFieldTests: XCTestCase {
    func testInitialClickSelectsAddressAndTypingReplacesIt() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let field = AddressTextField(frame: NSRect(x: 10, y: 10, width: 400, height: 24))
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(field)
        field.stringValue = "https://example.org/a-long-address"
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 80, y: 20),
                                                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        field.mouseDown(with: event)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: field.stringValue.utf16.count))
        editor.insertText("replacement", replacementRange: editor.selectedRange())
        XCTAssertEqual(editor.string, "replacement")
        window.makeFirstResponder(nil)
        window.close()
    }

    func testEmptyAddressAcceptsInputAndExplicitFocusReselectsText() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let field = AddressTextField(frame: NSRect(x: 10, y: 10, width: 400, height: 24))
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(field)
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 0))
        editor.insertText("example.org", replacementRange: editor.selectedRange())
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        field.selectText(nil)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: "example.org".utf16.count))
        window.makeFirstResponder(nil)
        window.close()
    }
}
