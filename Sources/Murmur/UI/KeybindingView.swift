import SwiftUI
import AppKit

// MARK: - NSView key capture

class KeyCaptureView: NSView {
    var onCapture: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        onCapture?(event.keyCode, flags)
    }

    override func flagsChanged(with event: NSEvent) {} // swallow modifier-only events
}

struct KeyCaptureRepresentable: NSViewRepresentable {
    let onCapture: (UInt16, NSEvent.ModifierFlags) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
}

// MARK: - Reusable hotkey row

private struct HotkeyRow: View {
    let label: String
    let keyCode: UInt16?
    let modifiers: NSEvent.ModifierFlags
    let isRecording: Bool
    let placeholder: String
    let onToggleRecord: () -> Void
    let onCapture: (UInt16, NSEvent.ModifierFlags) -> Void
    let onCancelCapture: () -> Void
    let onClear: (() -> Void)?

    private func modifiersString(_ flags: NSEvent.ModifierFlags) -> String {
        var r = ""
        if flags.contains(.control) { r += "⌃" }
        if flags.contains(.option)  { r += "⌥" }
        if flags.contains(.shift)   { r += "⇧" }
        if flags.contains(.command) { r += "⌘" }
        return r
    }

    private func keyCodeString(_ code: UInt16) -> String {
        let table: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
            103: "F11", 109: "F10", 111: "F12",
            115: "Home", 116: "PgUp", 117: "Del", 118: "F4",
            119: "End", 120: "F2", 121: "PgDn", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return table[code] ?? "Key(\(code))"
    }

    private var displayLabel: String {
        guard let code = keyCode else { return placeholder }
        return modifiersString(modifiers) + keyCodeString(code)
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if isRecording {
                Text("Press key combo…")
                    .foregroundStyle(.secondary)
                    .italic()
                KeyCaptureRepresentable(onCapture: onCapture, onCancel: onCancelCapture)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
            } else {
                Text(displayLabel)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(keyCode == nil ? .tertiary : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Button(isRecording ? "Cancel" : "Record", action: onToggleRecord)
                .buttonStyle(.bordered)
                .controlSize(.small)
            if !isRecording, let clear = onClear, keyCode != nil {
                Button("Clear", action: clear)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - KeybindingView

struct KeybindingView: View {
    @EnvironmentObject var viewModel: DictationViewModel

    // Main hotkey
    @State private var isRecordingMain = false
    @State private var mainKeyCode: UInt16 = {
        let v = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        return UInt16(v > 0 ? v : 2)
    }()
    @State private var mainModifiers: NSEvent.ModifierFlags = {
        let raw = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        return raw > 0 ? NSEvent.ModifierFlags(rawValue: UInt(raw)) : [.command, .shift]
    }()

    // Cancel hotkey
    @State private var isRecordingCancel = false
    @State private var cancelKeyCode: UInt16? = {
        let v = UserDefaults.standard.integer(forKey: "cancelHotkeyKeyCode")
        return v > 0 ? UInt16(v) : nil
    }()
    @State private var cancelModifiers: NSEvent.ModifierFlags = {
        let raw = UserDefaults.standard.integer(forKey: "cancelHotkeyModifiers")
        return raw > 0 ? NSEvent.ModifierFlags(rawValue: UInt(raw)) : []
    }()

    var body: some View {
        Form {
            Section("Start / Stop Recording") {
                HotkeyRow(
                    label: "Toggle recording",
                    keyCode: mainKeyCode,
                    modifiers: mainModifiers,
                    isRecording: isRecordingMain,
                    placeholder: "—",
                    onToggleRecord: { isRecordingMain.toggle() },
                    onCapture: { code, mods in
                        mainKeyCode = code
                        mainModifiers = mods
                        viewModel.updateHotkey(keyCode: code, modifiers: mods)
                        isRecordingMain = false
                    },
                    onCancelCapture: { isRecordingMain = false },
                    onClear: nil
                )
            }

            Section("Cancel Recording") {
                HotkeyRow(
                    label: "Discard without transcribing",
                    keyCode: cancelKeyCode,
                    modifiers: cancelModifiers,
                    isRecording: isRecordingCancel,
                    placeholder: "Not set",
                    onToggleRecord: { isRecordingCancel.toggle() },
                    onCapture: { code, mods in
                        cancelKeyCode = code
                        cancelModifiers = mods
                        viewModel.updateCancelHotkey(keyCode: code, modifiers: mods)
                        isRecordingCancel = false
                    },
                    onCancelCapture: { isRecordingCancel = false },
                    onClear: {
                        cancelKeyCode = nil
                        cancelModifiers = []
                        viewModel.updateCancelHotkey(keyCode: 0, modifiers: [])
                    }
                )
            }

            Section {
                Text("Click Record, then press your desired key combination. Press Escape to cancel recording a new combo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear { isRecordingMain = false; isRecordingCancel = false }
    }
}
