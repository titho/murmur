import AppKit
import ApplicationServices
import os.log

private let pasteLog = Logger(subsystem: "com.stoilyankov.Murmur", category: "paste")

class OutputManager {
    func output(_ text: String) {
        let mode = UserDefaults.standard.string(forKey: "outputMode") ?? "clipboardAndPaste"
        pasteLog.info("output() called, mode=\(mode), text length=\(text.count)")
        copyToClipboard(text)
        if mode == "clipboardAndPaste" {
            simulatePaste()
        } else {
            pasteLog.info("paste skipped — mode is not clipboardAndPaste")
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func simulatePaste() {
        let trusted = AXIsProcessTrusted()
        pasteLog.info("simulatePaste: AXIsProcessTrusted=\(trusted)")
        guard trusted else {
            pasteLog.warning("simulatePaste: aborting — accessibility not granted")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        pasteLog.info("simulatePaste: CGEventSource=\(source != nil)")

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        pasteLog.info("simulatePaste: keyDown=\(keyDown != nil), keyUp=\(keyUp != nil)")

        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        pasteLog.info("simulatePaste: events posted")
    }
}
