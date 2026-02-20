import AppKit
import SwiftUI
import Combine

@MainActor
class PillHUDController {
    private var window: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private weak var viewModel: DictationViewModel?

    private let pillWidth: CGFloat = 260
    private let pillHeight: CGFloat = 52

    init(viewModel: DictationViewModel) {
        self.viewModel = viewModel
        observeState()
    }

    // MARK: - State observation

    private func observeState() {
        viewModel?.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)
    }

    private func handleStateChange(_ state: RecordingState) {
        switch state {
        case .recording, .transcribing, .cancelled:
            if window == nil { createWindow() }
            if window?.isVisible == false { showWindow() }
        case .idle, .done, .error, .loading:
            if window?.isVisible == true { hideWindow() }
        }
    }

    // MARK: - Window lifecycle

    private func createWindow() {
        guard let screen = NSScreen.main, let vm = viewModel else { return }

        let frame = pillFrame(for: screen)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = false

        let content = PillHUDView().environmentObject(vm)
        panel.contentView = NSHostingView(rootView: content)

        self.window = panel
    }

    private func showWindow() {
        guard let window else { return }

        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    private func hideWindow() {
        guard let window else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.window = nil
        })
    }

    // MARK: - Positioning

    private func pillFrame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let menuBarHeight = NSStatusBar.system.thickness + 8
        let x = screenFrame.midX - pillWidth / 2
        let y = screenFrame.maxY - menuBarHeight - pillHeight
        return NSRect(x: x, y: y, width: pillWidth, height: pillHeight)
    }
}
