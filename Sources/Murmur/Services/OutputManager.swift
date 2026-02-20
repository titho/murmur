import AppKit
import ApplicationServices

class OutputManager {
    /// Copy text to clipboard and attempt to paste into frontmost app.
    func output(_ text: String) {
        copyToClipboard(text)
        pasteToFrontApp(text)
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func pasteToFrontApp(_ text: String) {
        guard AXIsProcessTrusted() else {
            // Accessibility not granted — clipboard copy already done above
            return
        }

        // Get focused element
        let systemElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard err == .success, let element = focusedElement else {
            simulatePaste()
            return
        }

        let axElement = element as! AXUIElement

        // Try setting value directly (works in many text fields)
        let setErr = AXUIElementSetAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )

        if setErr != .success {
            // Fallback: simulate Cmd+V (clipboard was already set)
            simulatePaste()
        }
    }

    private func simulatePaste() {
        // Post Cmd+V as a CGEvent
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        let loc = CGEventTapLocation.cghidEventTap
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
    }
}
