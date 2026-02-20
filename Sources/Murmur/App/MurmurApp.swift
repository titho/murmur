import SwiftUI
import AppKit

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Window is opened manually via StatusBarController.openSettings().
        // SwiftUI requires at least one Scene, so keep an empty Settings stub.
        Settings { EmptyView() }
    }
}
