import AppKit
import ApplicationServices
import os.log

private let pasteLog = Logger(subsystem: "com.stoilyankov.Murmur", category: "paste")

class OutputManager {
    func output(_ text: String, targetPID: pid_t? = nil) {
        let mode = UserDefaults.standard.string(forKey: "outputMode") ?? "clipboardAndPaste"
        pasteLog.info("output() called, mode=\(mode), text length=\(text.count), targetPID=\(targetPID ?? 0)")
        copyToClipboard(text)
        if mode == "clipboardAndPaste" {
            simulatePaste(targetPID: targetPID)
        } else {
            pasteLog.info("paste skipped — mode is not clipboardAndPaste")
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func simulatePaste(targetPID: pid_t? = nil) {
        let trusted = AXIsProcessTrusted()
        let frontmost = NSWorkspace.shared.frontmostApplication
        pasteLog.info("simulatePaste: AXIsProcessTrusted=\(trusted) frontmost=\(frontmost?.bundleIdentifier ?? "nil") PID=\(frontmost?.processIdentifier ?? 0) targetPID=\(targetPID ?? 0)")
        guard trusted else {
            pasteLog.warning("simulatePaste: aborting — accessibility not granted")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        pasteLog.info("simulatePaste: keyDown=\(keyDown != nil), keyUp=\(keyUp != nil)")

        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand

        if let pid = targetPID {
            // Post directly to the target process — bypasses HID routing, more reliable for Electron apps
            pasteLog.info("simulatePaste: posting via postToPid to PID=\(pid)")
            keyDown?.postToPid(pid)
            keyUp?.postToPid(pid)
        } else {
            pasteLog.info("simulatePaste: posting via .cghidEventTap (no target PID)")
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
        pasteLog.info("simulatePaste: events posted")
    }
}
