import AppKit
import SwiftUI
import Combine

@MainActor
class StatusBarController {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private let viewModel: DictationViewModel
    private var settingsWindow: NSWindow?
    private var pillHUD: PillHUDController!

    init(viewModel: DictationViewModel) {
        self.viewModel = viewModel
        setupStatusItem()
        setupPopover()
        observeState()
        pillHUD = PillHUDController(viewModel: viewModel)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Dictation")
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 200)
        popover.behavior = .transient
        popover.animates = true

        let contentView = RecordingPanelView()
            .environmentObject(viewModel)

        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    private func observeState() {
        viewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)
            }
            .store(in: &cancellables)

        viewModel.$isModelReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateIcon(for: self.viewModel.state)
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for state: RecordingState) {
        guard let button = statusItem.button else { return }

        switch state {
        case .idle, .done, .cancelled:
            if !viewModel.isModelReady {
                button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "No model")
                button.contentTintColor = .secondaryLabelColor
            } else {
                button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Dictation")
                button.contentTintColor = nil
            }
        case .recording:
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Recording")
            button.contentTintColor = .systemRed
        case .transcribing, .loading:
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Transcribing")
            button.contentTintColor = .systemOrange
        case .error:
            button.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Error")
            button.contentTintColor = .systemYellow
        }
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            removeEventMonitor()
        } else {
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
                installEventMonitor()
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let stateItem = NSMenuItem(title: stateMenuTitle(), action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        if case .recording = viewModel.state {
            let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        }

        let quitItem = NSMenuItem(title: "Quit Murmur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func stateMenuTitle() -> String {
        switch viewModel.state {
        case .idle:      return "Ready (⌘⇧D to dictate)"
        case .recording: return "🔴 Recording..."
        case .transcribing: return "⏳ Transcribing..."
        case .loading:   return "⬇️ Loading model..."
        case .cancelled: return "✗ Cancelled"
        case .done(let text): return "✅ \(text.prefix(40))..."
        case .error(let msg): return "⚠️ \(msg.prefix(40))"
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let content = SettingsView()
                .environmentObject(viewModel)
                .environmentObject(viewModel.historyStore)
                .environmentObject(viewModel.whisperService)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.contentView = NSHostingView(rootView: content)
            window.toolbar = nil  // Remove the sidebar toggle button added by NavigationSplitView
            window.center()
            window.setFrameAutosaveName("SettingsWindow")
            window.minSize = NSSize(width: 680, height: 460)

            // Switch to regular activation policy so Settings appears in Cmd+Tab
            NSApp.setActivationPolicy(.regular)

            // Restore accessory policy when window closes
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                NSApp.setActivationPolicy(.accessory)
            }

            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func stopRecording() {
        Task { @MainActor in
            viewModel.stopAndTranscribe()
        }
    }

    private func installEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
            self?.removeEventMonitor()
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
