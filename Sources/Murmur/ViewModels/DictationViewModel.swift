import Foundation
import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

enum RecordingState: Equatable {
    case idle
    case loading
    case recording
    case transcribing
    case cancelled
    case done(String)
    case error(String)
}

@MainActor
class DictationViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var waveformSamples: [Float] = Array(repeating: 0, count: 60)
    @Published var lastTranscription: String = ""
    @Published var isModelReady: Bool = false

    let historyStore = HistoryStore()
    let whisperService = WhisperService()
    let resourceMonitor = ResourceMonitor()

    private let audioRecorder = AudioRecorder()
    private let outputManager = OutputManager()
    private let hotkeyManager = HotkeyManager()
    private var cancellables = Set<AnyCancellable>()
    private var recordingTimer: Task<Void, Never>?
    private var frontmostAppBeforeRecording: NSRunningApplication?

    private var maxRecordingDuration: Int? {
        guard UserDefaults.standard.bool(forKey: "maxRecordingEnabled") else { return nil }
        let val = UserDefaults.standard.integer(forKey: "maxRecordingSeconds")
        return val > 0 ? val : 120
    }

    private var whisperInitialPrompt: String? {
        guard UserDefaults.standard.bool(forKey: "whisperPromptEnabled") else { return nil }
        let p = UserDefaults.standard.string(forKey: "whisperPrompt") ?? ""
        return p.isEmpty ? nil : p
    }

    init() {
        audioRecorder.onWaveformSample = { [weak self] rms in
            Task { @MainActor in
                self?.pushWaveformSample(rms)
            }
        }
    }

    func setup() {
        hotkeyManager.onHotkeyFired = { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        hotkeyManager.onCancelFired = { [weak self] in
            Task { @MainActor in
                self?.cancelRecording()
            }
        }

        resourceMonitor.start()

        Task {
            await loadModelIfNeeded()
        }
    }

    func cleanup() {
        hotkeyManager.unregister()
        resourceMonitor.stop()
        recordingTimer?.cancel()
        recordingTimer = nil
        if case .recording = state {
            Task { try? await audioRecorder.stop() }
        }
    }

    func updateHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        hotkeyManager.updateHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    func updateCancelHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        hotkeyManager.updateCancelHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    func toggleRecording() {
        switch state {
        case .recording:
            stopAndTranscribe()
        case .idle, .done, .error, .cancelled:
            if isModelReady { startRecording() }
        default:
            break
        }
    }

    func cancelRecording() {
        guard case .recording = state else { return }
        recordingTimer?.cancel()
        recordingTimer = nil
        state = .cancelled
        Task { try? await audioRecorder.stop() }

        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if case .cancelled = self.state { self.state = .idle }
        }
    }

    func startRecording() {
        frontmostAppBeforeRecording = NSWorkspace.shared.frontmostApplication

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if granted {
                    do {
                        try await self.audioRecorder.start()
                        self.state = .recording
                        self.waveformSamples = Array(repeating: 0, count: 60)

                        if let duration = self.maxRecordingDuration {
                            self.recordingTimer = Task { @MainActor [weak self] in
                                try? await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000_000)
                                guard let self, !Task.isCancelled else { return }
                                if case .recording = self.state { self.stopAndTranscribe() }
                            }
                        }
                    } catch {
                        self.state = .error("Mic error: \(error.localizedDescription)")
                    }
                } else {
                    self.state = .error("Microphone access denied. Enable in System Settings > Privacy.")
                }
            }
        }
    }

    func transcribeFile() {
        guard isModelReady else { return }
        let targetApp = NSWorkspace.shared.frontmostApplication

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.prompt = "Transcribe"
        panel.message = "Select an audio file to transcribe"

        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self.transcribeAudioFile(url: url, targetApp: targetApp)
            }
        }
    }

    private func transcribeAudioFile(url: URL, targetApp: NSRunningApplication?) async {
        state = .transcribing
        do {
            let duration = audioDuration(url: url)
            let prompt = whisperInitialPrompt
            let transcribeStart = Date()
            let text = try await whisperService.transcribe(audioURL: url, initialPrompt: prompt)
            let transcribeTime = Date().timeIntervalSince(transcribeStart)
            let cpu = resourceMonitor.cpuPercent
            let mem = resourceMonitor.memoryMB

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let (finalText, entry) = await applyCleanupIfEnabled(
                trimmed,
                audioDurationSeconds: duration,
                transcriptionTimeSeconds: transcribeTime,
                cpuPercent: cpu,
                memoryMB: mem
            )

            lastTranscription = finalText
            state = .done(finalText)

            if !finalText.isEmpty {
                if let app = targetApp {
                    app.activate(options: .activateIgnoringOtherApps)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
                outputManager.output(finalText)
                historyStore.append(entry)
            }

            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if case .done = state { state = .idle }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func stopAndTranscribe() {
        recordingTimer?.cancel()
        recordingTimer = nil
        state = .transcribing

        Task {
            do {
                let wavURL = try await audioRecorder.stop()
                waveformSamples = Array(repeating: 0, count: 60)

                let duration = audioDuration(url: wavURL)
                let prompt = whisperInitialPrompt
                let transcribeStart = Date()
                let text = try await whisperService.transcribe(audioURL: wavURL, initialPrompt: prompt)
                let transcribeTime = Date().timeIntervalSince(transcribeStart)
                let cpu = resourceMonitor.cpuPercent
                let mem = resourceMonitor.memoryMB

                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let (finalText, entry) = await applyCleanupIfEnabled(
                    trimmed,
                    audioDurationSeconds: duration,
                    transcriptionTimeSeconds: transcribeTime,
                    cpuPercent: cpu,
                    memoryMB: mem
                )

                lastTranscription = finalText
                state = .done(finalText)

                if !finalText.isEmpty {
                    if let app = frontmostAppBeforeRecording {
                        app.activate(options: .activateIgnoringOtherApps)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                    outputManager.output(finalText)
                    historyStore.append(entry)
                }

                try? FileManager.default.removeItem(at: wavURL)

                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if case .done = state { state = .idle }

            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Model management

    func loadModelIfNeeded() async {
        let variant = UserDefaults.standard.string(forKey: "selectedModel") ?? WhisperModel.default.id

        guard whisperService.isModelDownloaded(variant) else {
            isModelReady = false
            state = .idle
            return
        }

        state = .loading
        do {
            try await whisperService.loadModel(variant: variant)
            isModelReady = true
            state = .idle
            Task { await whisperService.warmup() }
        } catch {
            state = .error("Failed to load model: \(error.localizedDescription)")
        }
    }

    func downloadModel(variant: String) async throws {
        try await whisperService.downloadModel(variant: variant)
    }

    func reloadModel() async {
        isModelReady = false
        await loadModelIfNeeded()
    }

    func deleteModel(variant: String) {
        whisperService.deleteModel(variant: variant)
        let selected = UserDefaults.standard.string(forKey: "selectedModel") ?? WhisperModel.default.id
        if variant == selected {
            isModelReady = false
            state = .idle
        }
    }

    func rerunCleanup(entryID: UUID) async {
        guard let entry = historyStore.entries.first(where: { $0.id == entryID }),
              let apiKey = CleanupService.resolvedApiKey() else { return }

        let modelRaw = UserDefaults.standard.string(forKey: "cleanupModel") ?? CleanupModel.haiku.rawValue
        let model = CleanupModel(rawValue: modelRaw) ?? .haiku

        do {
            let result = try await CleanupService.clean(entry.text, model: model, apiKey: apiKey)
            var updated = entry
            updated.cleanedText = result.text
            updated.inputTokens = result.inputTokens
            updated.outputTokens = result.outputTokens
            updated.cleanupModel = modelRaw
            historyStore.update(updated)
        } catch {
            // UI handles error state via @State on the calling view
        }
    }

    // MARK: - Private

    private func audioDuration(url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    private func applyCleanupIfEnabled(
        _ rawText: String,
        audioDurationSeconds: Double?,
        transcriptionTimeSeconds: Double?,
        cpuPercent: Double?,
        memoryMB: Double?
    ) async -> (String, TranscriptionEntry) {
        let whisperModelUsed = UserDefaults.standard.string(forKey: "selectedModel")

        func makeEntry(cleanedText: String? = nil, inputTok: Int? = nil, outputTok: Int? = nil, model: String? = nil) -> TranscriptionEntry {
            TranscriptionEntry(
                text: rawText,
                cleanedText: cleanedText,
                inputTokens: inputTok,
                outputTokens: outputTok,
                cleanupModel: model,
                audioDurationSeconds: audioDurationSeconds,
                transcriptionTimeSeconds: transcriptionTimeSeconds,
                whisperModel: whisperModelUsed,
                cpuPercentAtTranscription: cpuPercent,
                memoryMBAtTranscription: memoryMB
            )
        }

        guard
            !rawText.isEmpty,
            UserDefaults.standard.bool(forKey: "cleanupEnabled"),
            let apiKey = CleanupService.resolvedApiKey()
        else {
            return (rawText, makeEntry())
        }

        let modelRaw = UserDefaults.standard.string(forKey: "cleanupModel") ?? CleanupModel.haiku.rawValue
        let model = CleanupModel(rawValue: modelRaw) ?? .haiku

        do {
            let result = try await CleanupService.clean(rawText, model: model, apiKey: apiKey)
            return (result.text, makeEntry(cleanedText: result.text, inputTok: result.inputTokens, outputTok: result.outputTokens, model: modelRaw))
        } catch {
            return (rawText, makeEntry())
        }
    }

    private func pushWaveformSample(_ rms: Float) {
        waveformSamples.removeFirst()
        waveformSamples.append(min(rms * 4.0, 1.0))
    }
}
