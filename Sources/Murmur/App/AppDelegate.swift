import AppKit
import AVFoundation
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = DictationViewModel()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "maxRecordingSeconds": 120,
            "maxRecordingEnabled": true,
            "cleanupEnabled": false,
            "cleanupModel": "claude-haiku-4-5-20251001",
            "selectedModel": "large-v3_turbo",
            "historyStoragePath": "",
            "pillEnabled": true,
        ])

        NSApp.setActivationPolicy(.accessory)

        // Request mic permission eagerly so it's cached before first recording.
        // The stable identity at ~/Applications/Murmur.app ensures macOS remembers the grant.
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        statusBarController = StatusBarController(viewModel: viewModel)
        viewModel.setup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.cleanup()
    }
}
