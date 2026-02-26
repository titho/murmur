import AppKit
import ApplicationServices

class OutputManager {
    /// Copy text to clipboard and (if outputMode allows) paste into frontmost app.
    func output(_ text: String) {
        let mode = UserDefaults.standard.string(forKey: "outputMode") ?? "clipboardAndPaste"
        copyToClipboard(text)
        if mode == "clipboardAndPaste" {
            simulatePaste()
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func simulatePaste() {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        let loc = CGEventTapLocation.cghidEventTap
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
    }
}
