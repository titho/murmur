# Metrics + Cleanup Retry Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Capture per-transcription performance metrics (audio duration, transcription time, Whisper model, CPU/mem) stored on each history entry, displayed inline on demand; plus a "Run Cleanup" button per history row and a dedicated Cleanups tab showing raw vs cleaned text.

**Architecture:** `TranscriptionEntry` gains new optional fields (backward-compatible); `DictationViewModel` captures metrics during transcription and fixes the raw/cleaned text split; `HistoryView` gets disclosure rows and a Run Cleanup button; `SettingsView` gets a new Cleanups tab.

**Tech Stack:** Swift 5.9, SwiftUI, AVFoundation (audio duration), `ResourceMonitor` (CPU/mem snapshot), `CleanupService` (existing)

---

## Key Semantic Change

Currently when cleanup runs, `TranscriptionEntry.text` is set to the **cleaned** text. After this change:
- `entry.text` = always the **raw Whisper output**
- `entry.cleanedText` = AI cleanup result (nil if no cleanup ran)
- `entry.effectiveText` = `cleanedText ?? text` — what gets output/copied

Old entries in `history.json` that had cleanup will have `text = cleaned text` and `cleanedText = nil`. That is acceptable — they just won't show a cleanup diff.

---

## Task 1: Extend TranscriptionEntry with metrics + cleaned text fields

**Files:**
- Modify: `Sources/Murmur/Models/TranscriptionEntry.swift`

### Step 1: Add new stored properties

Replace the entire file with:

```swift
import Foundation

struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let text: String               // always raw Whisper output
    let date: Date
    var cleanedText: String?       // AI cleanup result; nil = no cleanup ran
    var inputTokens: Int?
    var outputTokens: Int?
    var cleanupModel: String?

    // Metrics
    var audioDurationSeconds: Double?
    var transcriptionTimeSeconds: Double?
    var whisperModel: String?
    var cpuPercentAtTranscription: Double?
    var memoryMBAtTranscription: Double?

    var wordCount: Int { text.split(separator: " ").count }

    /// What gets pasted / copied — cleaned if available, otherwise raw.
    var effectiveText: String { cleanedText ?? text }

    /// Estimated cost in USD based on stored token counts and model pricing.
    var estimatedCost: Double? {
        guard let input = inputTokens, let output = outputTokens, let model = cleanupModel else { return nil }
        let pricing: [String: (Double, Double)] = [
            "claude-haiku-4-5-20251001": (0.80,  4.00),
            "claude-sonnet-4-6":         (3.00,  15.00),
            "claude-opus-4-6":           (15.00, 75.00),
        ]
        guard let (inPrice, outPrice) = pricing[model] else { return nil }
        return Double(input) * inPrice / 1_000_000 + Double(output) * outPrice / 1_000_000
    }

    init(
        text: String,
        cleanedText: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cleanupModel: String? = nil,
        audioDurationSeconds: Double? = nil,
        transcriptionTimeSeconds: Double? = nil,
        whisperModel: String? = nil,
        cpuPercentAtTranscription: Double? = nil,
        memoryMBAtTranscription: Double? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.cleanedText = cleanedText
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cleanupModel = cleanupModel
        self.audioDurationSeconds = audioDurationSeconds
        self.transcriptionTimeSeconds = transcriptionTimeSeconds
        self.whisperModel = whisperModel
        self.cpuPercentAtTranscription = cpuPercentAtTranscription
        self.memoryMBAtTranscription = memoryMBAtTranscription
    }
}
```

### Step 2: Build to confirm no compile errors

```bash
cd /Users/stoil.yankov/Repositories/VibeProjects/murmur
xcodebuild -scheme Murmur -configuration Debug CODE_SIGNING_ALLOWED=NO ARCHS=arm64 -quiet 2>&1 | grep -E "error:|warning:" | grep -v "^ld:"
```

Expected: compile errors in `DictationViewModel.swift` (calls `TranscriptionEntry(text:)` without new params — that's fine because all new params have defaults). Should be zero actual errors.

### Step 3: Commit

```bash
git add Sources/Murmur/Models/TranscriptionEntry.swift
git commit -m "feat: extend TranscriptionEntry with metrics + cleanedText fields"
```

---

## Task 2: Add HistoryStore.update(_:)

**Files:**
- Modify: `Sources/Murmur/Services/HistoryStore.swift`

### Step 1: Add the update method after `delete(id:)`

```swift
func update(_ entry: TranscriptionEntry) {
    guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
    entries[idx] = entry
    save()
}
```

### Step 2: Build to confirm

```bash
xcodebuild -scheme Murmur -configuration Debug CODE_SIGNING_ALLOWED=NO ARCHS=arm64 -quiet 2>&1 | grep "error:"
```

Expected: no errors.

### Step 3: Commit

```bash
git add Sources/Murmur/Services/HistoryStore.swift
git commit -m "feat: add HistoryStore.update(_:) for in-place entry mutation"
```

---

## Task 3: Capture metrics in DictationViewModel

**Files:**
- Modify: `Sources/Murmur/ViewModels/DictationViewModel.swift`

### Step 1: Add AVFoundation import at the top (already present — verify)

`DictationViewModel.swift` already imports `AVFoundation`. Confirm line 3.

### Step 2: Add private audio-duration helper just before `applyCleanupIfEnabled`

```swift
private func audioDuration(url: URL) -> Double? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    return Double(file.length) / file.fileFormat.sampleRate
}
```

### Step 3: Update `applyCleanupIfEnabled` signature to accept and thread metrics

Replace the entire `applyCleanupIfEnabled` method:

```swift
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
```

### Step 4: Update `stopAndTranscribe` to capture metrics and pass them

Replace the `Task { do { ... } }` block inside `stopAndTranscribe`. The key additions (shown inline with comments):

```swift
func stopAndTranscribe() {
    recordingTimer?.cancel()
    recordingTimer = nil
    state = .transcribing

    Task {
        do {
            let wavURL = try await audioRecorder.stop()
            waveformSamples = Array(repeating: 0, count: 60)

            // Capture metrics
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
```

### Step 5: Update `transcribeAudioFile` similarly

Replace `transcribeAudioFile(url:targetApp:)`:

```swift
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
```

### Step 6: Add `rerunCleanup` method (for Task 5 UI to call)

Add after `deleteModel`:

```swift
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
        // Silently fail — UI handles error state separately via @State
    }
}
```

Note: `TranscriptionEntry` is a struct; `var updated = entry` copies it. The `cleanedText`, `inputTokens`, `outputTokens`, and `cleanupModel` properties are `var` — confirm they are `var` (not `let`) in Task 1.

### Step 7: Build

```bash
xcodebuild -scheme Murmur -configuration Debug CODE_SIGNING_ALLOWED=NO ARCHS=arm64 -quiet 2>&1 | grep "error:"
```

Expected: no errors.

### Step 8: Commit

```bash
git add Sources/Murmur/ViewModels/DictationViewModel.swift
git commit -m "feat: capture transcription metrics; fix raw/cleaned text split; add rerunCleanup"
```

---

## Task 4: Update HistoryRowView with metrics disclosure + Run Cleanup button

**Files:**
- Modify: `Sources/Murmur/UI/HistoryView.swift`

This is the most UI-heavy task. Replace `HistoryView.swift` entirely with the version below.

Key changes:
- `HistoryView` passes `viewModel` via `@EnvironmentObject` (already wired in `StatusBarController`)
- `HistoryRowView` gains `isExpanded: Bool`, `isRunningCleanup: Bool`, `onExpand`, `onRunCleanup` parameters
- Metrics shown when expanded; "Run Cleanup" button only when `CleanupService.resolvedApiKey() != nil` and `entry.cleanedText == nil`

```swift
import SwiftUI
import AppKit

struct HistoryView: View {
    @EnvironmentObject var historyStore: HistoryStore
    @EnvironmentObject var viewModel: DictationViewModel
    @State private var showClearConfirm = false
    @State private var copiedID: UUID?
    @State private var expandedID: UUID?
    @State private var cleaningID: UUID?

    private var totalWords: Int {
        historyStore.entries.reduce(0) { $0 + $1.wordCount }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(historyStore.entries.count) transcription\(historyStore.entries.count == 1 ? "" : "s") · \(totalWords) words total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Export...") { export() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(historyStore.entries.isEmpty)
                Button("Clear All") { showClearConfirm = true }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.red)
                    .disabled(historyStore.entries.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if historyStore.entries.isEmpty {
                Spacer()
                Text("No transcriptions yet")
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                List(historyStore.entries) { entry in
                    HistoryRowView(
                        entry: entry,
                        isCopied: copiedID == entry.id,
                        isExpanded: expandedID == entry.id,
                        isRunningCleanup: cleaningID == entry.id,
                        onCopy: { copyToClipboard(entry) },
                        onToggleExpand: {
                            expandedID = expandedID == entry.id ? nil : entry.id
                        },
                        onRunCleanup: {
                            cleaningID = entry.id
                            Task {
                                await viewModel.rerunCleanup(entryID: entry.id)
                                cleaningID = nil
                                expandedID = entry.id  // auto-expand to show result
                            }
                        }
                    )
                }
                .listStyle(.plain)
            }
        }
        .confirmationDialog("Clear all history?", isPresented: $showClearConfirm) {
            Button("Clear All", role: .destructive) { historyStore.clear() }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func copyToClipboard(_ entry: TranscriptionEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.effectiveText, forType: .string)
        copiedID = entry.id
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedID == entry.id { copiedID = nil }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "dictation-history.md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? self.historyStore.exportMarkdown(to: url)
        }
    }
}

// MARK: - Row

struct HistoryRowView: View {
    let entry: TranscriptionEntry
    let isCopied: Bool
    let isExpanded: Bool
    let isRunningCleanup: Bool
    let onCopy: () -> Void
    let onToggleExpand: () -> Void
    let onRunCleanup: () -> Void

    private var hasMetrics: Bool {
        entry.transcriptionTimeSeconds != nil || entry.audioDurationSeconds != nil
    }

    private var canRunCleanup: Bool {
        CleanupService.resolvedApiKey() != nil && entry.cleanedText == nil && !isRunningCleanup
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.text)
                        .lineLimit(isExpanded ? nil : 2)
                        .font(.body)

                    Text(Self.dateFormatter.string(from: entry.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let input = entry.inputTokens, let output = entry.outputTokens {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .imageScale(.small)
                            Text("\(input) in · \(output) out")
                            if let cost = entry.estimatedCost {
                                Text("· $\(String(format: "%.5f", cost))")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.purple.opacity(0.8))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Button(isCopied ? "Copied" : "Copy") { onCopy() }
                        .buttonStyle(.borderless)
                        .controlSize(.mini)
                        .foregroundStyle(isCopied ? .green : Color.accentColor)

                    if hasMetrics || entry.cleanedText != nil {
                        Button {
                            onToggleExpand()
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if isExpanded {
                Divider().padding(.vertical, 6)

                VStack(alignment: .leading, spacing: 8) {
                    // Metrics grid
                    if hasMetrics {
                        MetricsGridView(entry: entry)
                    }

                    // Cleaned text section
                    if let cleaned = entry.cleanedText {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Cleaned", systemImage: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(.purple.opacity(0.8))
                            Text(cleaned)
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }
                        .padding(8)
                        .background(Color.purple.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else if CleanupService.resolvedApiKey() != nil {
                        // Show Run Cleanup button only when key is available
                        HStack {
                            if isRunningCleanup {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                                Text("Cleaning…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button {
                                    onRunCleanup()
                                } label: {
                                    Label("Run Cleanup", systemImage: "sparkles")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Metrics grid

private struct MetricsGridView: View {
    let entry: TranscriptionEntry

    var body: some View {
        HStack(spacing: 12) {
            if let dur = entry.audioDurationSeconds {
                MetricChip(icon: "waveform", label: "Audio", value: String(format: "%.1fs", dur))
            }
            if let tt = entry.transcriptionTimeSeconds {
                MetricChip(icon: "clock", label: "Whisper", value: String(format: "%.1fs", tt))
            }
            if let model = entry.whisperModel {
                MetricChip(icon: "cpu", label: "Model", value: model)
            }
            if let cpu = entry.cpuPercentAtTranscription {
                MetricChip(icon: "bolt", label: "CPU", value: String(format: "%.0f%%", cpu))
            }
            if let mem = entry.memoryMBAtTranscription {
                MetricChip(icon: "memorychip", label: "RAM", value: String(format: "%.0f MB", mem))
            }
        }
        .padding(.vertical, 2)
    }
}

private struct MetricChip: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
```

### Step 2: Build

```bash
xcodebuild -scheme Murmur -configuration Debug CODE_SIGNING_ALLOWED=NO ARCHS=arm64 -quiet 2>&1 | grep "error:"
```

Expected: no errors. If `viewModel` not in environment for `HistoryView`, see Task 7 note.

### Step 3: Commit

```bash
git add Sources/Murmur/UI/HistoryView.swift
git commit -m "feat: add metrics disclosure + Run Cleanup button to history rows"
```

---

## Task 5: Add CleanupHistoryView (Cleanups tab)

**Files:**
- Create: `Sources/Murmur/UI/CleanupHistoryView.swift`

### Step 1: Create the file

```swift
import SwiftUI
import AppKit

struct CleanupHistoryView: View {
    @EnvironmentObject var historyStore: HistoryStore

    private var cleanedEntries: [TranscriptionEntry] {
        historyStore.entries.filter { $0.cleanedText != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(cleanedEntries.count) cleaned transcription\(cleanedEntries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if cleanedEntries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No cleaned transcriptions yet")
                        .foregroundStyle(.tertiary)
                    Text("Use "Run Cleanup" on any history entry, or enable AI Cleanup in settings.")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                }
                Spacer()
            } else {
                List(cleanedEntries) { entry in
                    CleanupEntryRow(entry: entry)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Row

private struct CleanupEntryRow: View {
    let entry: TranscriptionEntry

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    @State private var copiedRaw = false
    @State private var copiedCleaned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.dateFormatter.string(from: entry.date))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Raw text
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Label("Raw", systemImage: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(copiedRaw ? "Copied" : "Copy") {
                        copy(entry.text)
                        copiedRaw = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            copiedRaw = false
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .foregroundStyle(copiedRaw ? .green : Color.accentColor)
                }
                Text(entry.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            // Cleaned text
            if let cleaned = entry.cleanedText {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Label("Cleaned", systemImage: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.purple.opacity(0.8))
                        Spacer()
                        Button(copiedCleaned ? "Copied" : "Copy") {
                            copy(cleaned)
                            copiedCleaned = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                copiedCleaned = false
                            }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.mini)
                        .foregroundStyle(copiedCleaned ? .green : Color.accentColor)
                    }
                    Text(cleaned)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }
                .padding(8)
                .background(Color.purple.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Token info
            if let input = entry.inputTokens, let output = entry.outputTokens {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").imageScale(.small)
                    Text("\(input) in · \(output) out")
                    if let cost = entry.estimatedCost {
                        Text("· $\(String(format: "%.5f", cost))")
                    }
                    if let model = entry.cleanupModel {
                        Text("· \(model)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.purple.opacity(0.7))
            }
        }
        .padding(.vertical, 6)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
```

### Step 2: Register in project.yml

Open `project.yml` and add `CleanupHistoryView.swift` to the sources list under `UI/`. Find the section listing UI files and add:

```yaml
- Sources/Murmur/UI/CleanupHistoryView.swift
```

The file list in `project.yml` is under `targets: > Murmur: > sources:`. It uses glob patterns — check if it already uses `Sources/Murmur/**` (in which case no change needed) or explicit file listing.

**Check first:**
```bash
grep -n "CleanupHistory\|Sources/Murmur" /Users/stoil.yankov/Repositories/VibeProjects/murmur/project.yml | head -20
```

If it's a glob (`Sources/Murmur/**`), the file is already included — skip the yml edit.

### Step 3: Build

```bash
xcodebuild -scheme Murmur -configuration Debug CODE_SIGNING_ALLOWED=NO ARCHS=arm64 -quiet 2>&1 | grep "error:"
```

### Step 4: Commit

```bash
git add Sources/Murmur/UI/CleanupHistoryView.swift project.yml
git commit -m "feat: add CleanupHistoryView showing raw vs cleaned text side by side"
```

---

## Task 6: Add Cleanups tab to SettingsView

**Files:**
- Modify: `Sources/Murmur/UI/SettingsView.swift`

### Step 1: Add `.cleanups` to `SettingsSection` enum

After `.history`:

```swift
case cleanups = "Cleanups"
```

### Step 2: Add icon for `.cleanups`

In the `icon` computed property:

```swift
case .cleanups:   return "sparkles"
```

### Step 3: Wire up in `SettingsView.body` switch

Add after the `.history` case:

```swift
case .cleanups:   CleanupHistoryView()
```

### Step 4: Build

```bash
xcodebuild -scheme Murmur -configuration Debug CODE_SIGNING_ALLOWED=NO ARCHS=arm64 -quiet 2>&1 | grep "error:"
```

Expected: no errors.

### Step 5: Verify `HistoryView` has `viewModel` in environment

`HistoryView` now uses `@EnvironmentObject var viewModel: DictationViewModel`. Check that `StatusBarController` passes it. Search:

```bash
grep -n "HistoryView\|environmentObject" Sources/Murmur/UI/StatusBarController.swift
```

If `viewModel` is already passed as an environment object on the settings window's hosting view, it will be available. If not, add it alongside the existing `historyStore` injection in `StatusBarController`.

### Step 6: Run the app

```bash
./run.sh
```

Verify:
- Settings → History: rows show a "▾" chevron; expand shows metric chips and "Run Cleanup" button
- Settings → Cleanups: shows empty state or cleaned entries
- Hotkey → dictate something → check History row has metrics populated
- Run Cleanup on a row → spinner → result appears in expanded area and in Cleanups tab

### Step 7: Commit

```bash
git add Sources/Murmur/UI/SettingsView.swift
git commit -m "feat: add Cleanups tab to settings sidebar"
```

---

## Summary of Changes

| File | Change |
|------|--------|
| `Models/TranscriptionEntry.swift` | +6 optional fields, `effectiveText`, `cleanedText` |
| `Services/HistoryStore.swift` | +`update(_:)` method |
| `ViewModels/DictationViewModel.swift` | Metrics capture, raw/cleaned split, `rerunCleanup` |
| `UI/HistoryView.swift` | Metrics disclosure, Run Cleanup button, `MetricsGridView` |
| `UI/CleanupHistoryView.swift` | New file — Cleanups tab content |
| `UI/SettingsView.swift` | +`.cleanups` section |

## Verification Checklist

- [ ] New dictation → History row shows chevron → expand shows audio/whisper time chips
- [ ] When cleanup is enabled and key is set, initial cleanup populates cleanedText automatically
- [ ] "Run Cleanup" in history row → spinner → cleaned text appears in expanded area
- [ ] Cleanups tab shows only entries with `cleanedText != nil`
- [ ] Copy button in Cleanups tab copies each version independently
- [ ] `history.json` contains the new fields for new entries
- [ ] Old entries load correctly (new fields are nil)
- [ ] `./run.sh` → rebuild → AX trust persists (cert change from earlier)
