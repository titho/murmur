import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Sidebar navigation

enum SettingsSection: String, CaseIterable, Identifiable {
    case general   = "General"
    case models    = "Models"

    case aiCleanup = "AI Cleanup"
    case keybinding = "Keybinding"
    case storage   = "Storage"
    case history   = "History"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:    return "gearshape"
        case .models:     return "cpu"
        case .aiCleanup:  return "sparkles"
        case .keybinding: return "keyboard"
        case .storage:    return "externaldrive"
        case .history:    return "clock.arrow.circlepath"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var viewModel: DictationViewModel
    @EnvironmentObject var historyStore: HistoryStore
    @EnvironmentObject var whisperService: WhisperService

    @State private var selectedSection: SettingsSection? = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 210)
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selectedSection ?? .general {
                case .general:    GeneralSettingsView()
                case .models:     ModelsSettingsView()
                case .aiCleanup:  AICleanupSettingsView()
                case .keybinding: KeybindingView()
                case .storage:    StorageSettingsView()
                case .history:    HistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, minHeight: 500)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @AppStorage("outputMode")           private var outputMode: OutputMode = .clipboardAndPaste
    @AppStorage("maxRecordingSeconds")  private var maxRecordingSeconds: Int = 120
    @AppStorage("maxRecordingEnabled")  private var maxRecordingEnabled: Bool = true
    @AppStorage("pillEnabled")          private var pillEnabled: Bool = true
    @AppStorage("whisperPromptEnabled") private var whisperPromptEnabled: Bool = false
    @AppStorage("whisperPrompt")        private var whisperPrompt: String = ""
    @AppStorage("launchAtLogin")        private var launchAtLogin: Bool = false

    static let defaultWhisperPrompt = "Clean, properly punctuated text. No filler words or false starts."

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !enabled // revert if registration fails
                        }
                    }
            } footer: {
                Text("Requires Murmur to be installed at ~/Applications/Murmur.app (run ./run.sh once).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Output") {
                Picker("After dictation", selection: $outputMode) {
                    Text("Copy to clipboard + paste").tag(OutputMode.clipboardAndPaste)
                    Text("Clipboard only").tag(OutputMode.clipboardOnly)
                }
                .pickerStyle(.radioGroup)

                if outputMode == .clipboardAndPaste {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text("Requires Accessibility permission")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Open Accessibility Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        )
                    }
                    .buttonStyle(.link).controlSize(.small)
                }
            }

            Section("Recording") {
                Toggle("Show status pill during recording", isOn: $pillEnabled)
                Toggle("Limit recording length", isOn: $maxRecordingEnabled)
                if maxRecordingEnabled {
                    Stepper(value: $maxRecordingSeconds, in: 30...300, step: 30) {
                        HStack {
                            Text("Max duration")
                            Spacer()
                            Text("\(maxRecordingSeconds)s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section("Whisper Prompt") {
                Toggle("Use custom initial prompt", isOn: $whisperPromptEnabled)
                    .onChange(of: whisperPromptEnabled) { enabled in
                        if enabled && whisperPrompt.isEmpty {
                            whisperPrompt = Self.defaultWhisperPrompt
                        }
                    }
                if whisperPromptEnabled {
                    PromptEditor(
                        text: $whisperPrompt,
                        placeholder: Self.defaultWhisperPrompt,
                        emptyNote: "Guides Whisper's transcription style",
                        onReset: { whisperPrompt = Self.defaultWhisperPrompt },
                        resetLabel: "Reset to default"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

// MARK: - Models

private struct ModelsSettingsView: View {
    @EnvironmentObject var viewModel: DictationViewModel
    @EnvironmentObject var whisperService: WhisperService

    @AppStorage("selectedModel") private var selectedModel: String = WhisperModel.default.id
    @State private var downloadError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(WhisperModel.catalog) { model in
                        ModelRow(
                            model: model,
                            isSelected: selectedModel == model.id,
                            isLoading: viewModel.state == .loading && selectedModel == model.id,
                            isDownloading: whisperService.activeDownloads.contains(model.id),
                            downloadProgress: whisperService.downloadProgress[model.id],
                            isDownloaded: whisperService.isModelDownloaded(model.id),
                            onSelect: {
                                selectedModel = model.id
                                Task { await viewModel.reloadModel() }
                            },
                            onDownload: {
                                Task {
                                    do {
                                        try await viewModel.downloadModel(variant: model.id)
                                        selectedModel = model.id
                                        await viewModel.reloadModel()
                                    } catch {
                                        downloadError = error.localizedDescription
                                    }
                                }
                            },
                            onDelete: {
                                viewModel.deleteModel(variant: model.id)
                                if selectedModel == model.id {
                                    selectedModel = WhisperModel.default.id
                                }
                            }
                        )
                    }
                }
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            }
            .alert("Download Failed", isPresented: Binding(
                get: { downloadError != nil },
                set: { if !$0 { downloadError = nil } }
            )) {
                Button("OK") { downloadError = nil }
            } message: {
                Text(downloadError ?? "")
            }

            Divider()

            // Model storage footer
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let dir = whisperService.modelsDirectory {
                    Text(dir.path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Reveal") { NSWorkspace.shared.open(dir) }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("Models stored in WhisperKit cache after first download.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle("Models")
    }
}

private struct ModelRow: View {
    let model: WhisperModel
    let isSelected: Bool
    let isLoading: Bool
    let isDownloading: Bool
    let downloadProgress: (bytesDownloaded: Int64, totalBytes: Int64?)?
    let isDownloaded: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    private var borderColor: Color {
        if model.isRecommended { return .green }
        if isSelected { return Color.accentColor.opacity(0.3) }
        return .clear
    }

    private var sizeLabel: String {
        model.sizeMB < 1000
            ? "\(model.sizeMB) MB"
            : String(format: "%.1f GB", Double(model.sizeMB) / 1000)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb < 1000 {
            return String(format: "%.0f MB", mb)
        } else {
            return String(format: "%.1f GB", mb / 1000)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                // Name + badges
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    if model.isRecommended {
                        Badge("Recommended", color: .green)
                    }
                    if model.isEnglishOnly {
                        Badge("EN only", color: .blue)
                    }
                    if model.isHeavy {
                        Badge("Heavy", color: .orange)
                    }
                }

                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Stats row — compact, no wrapping labels
                HStack(spacing: 10) {
                    Text(sizeLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 48, alignment: .leading)

                    CompactRating(icon: "bolt.fill", rating: model.speedRating, color: .green)
                    CompactRating(icon: "scope", rating: model.accuracyRating, color: .blue)
                }
            }

            Spacer(minLength: 8)

            // Action area
            VStack(alignment: .trailing, spacing: 6) {
                if isDownloading, let progress = downloadProgress {
                    VStack(alignment: .trailing, spacing: 4) {
                        if let total = progress.totalBytes, total > 0 {
                            // Determinate progress (if totalBytes is known)
                            let fraction = Double(progress.bytesDownloaded) / Double(total)
                            ProgressView(value: fraction)
                                .frame(width: 80)
                                .progressViewStyle(.linear)
                            Text("\(Int(fraction * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } else {
                            // Indeterminate + byte count
                            ProgressView()
                                .scaleEffect(0.65)
                                .frame(width: 18, height: 18)
                            Text(formatBytes(progress.bytesDownloaded))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } else if isDownloading {
                    // No progress data yet
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.65)
                            .frame(width: 18, height: 18)
                        Text("Starting…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if isDownloaded {
                    if isSelected {
                        if isLoading {
                            ProgressView().scaleEffect(0.65).frame(width: 18, height: 18)
                        } else {
                            Text("Loaded")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.green.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    } else {
                        Button("Load") { onSelect() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Delete model from disk")
                } else {
                    Button("Download") { onDownload() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.07)
                      : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: model.isRecommended ? 1.5 : 1)
        )
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct CompactRating: View {
    let icon: String
    let rating: Int
    let color: Color
    private let total = 5

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(color.opacity(0.7))
            HStack(spacing: 2) {
                ForEach(0..<total, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i < rating ? color : color.opacity(0.15))
                        .frame(width: 10, height: 6)
                }
            }
        }
    }
}

// MARK: - AI Cleanup

private struct AICleanupSettingsView: View {
    @AppStorage("cleanupEnabled")             private var cleanupEnabled: Bool = false
    @AppStorage("cleanupModel")              private var cleanupModel: String = CleanupModel.haiku.rawValue
    @AppStorage("anthropicApiKey")           private var anthropicApiKey: String = ""
    @AppStorage("cleanupSystemPromptEnabled") private var cleanupSystemPromptEnabled: Bool = false
    @AppStorage("cleanupSystemPrompt")       private var cleanupSystemPrompt: String = ""

    @State private var isOverridingKey = false

    private var resolvedKey: String? { CleanupService.resolvedApiKey() }
    private var keyIsFromEnv: Bool {
        let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        return !env.isEmpty
    }

    private func maskedKey(_ key: String) -> String {
        let prefix = String(key.prefix(8))
        return prefix + String(repeating: "•", count: 20)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Clean up transcription with AI", isOn: $cleanupEnabled)
                    .font(.body)
            } footer: {
                Text("Uses Claude to fix grammar, punctuation, and remove filler words after each dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if cleanupEnabled {
                Section("Model") {
                    Picker("Cleanup model", selection: $cleanupModel) {
                        ForEach(CleanupModel.allCases, id: \.rawValue) { m in
                            Text(m.displayName).tag(m.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Section("API Key") {
                    if let key = resolvedKey, !isOverridingKey {
                        // Key is present — show masked + override button
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(maskedKey(key))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.primary)
                                if keyIsFromEnv {
                                    Text("From ANTHROPIC_API_KEY environment variable")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Label("Found", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Button("Override") { isOverridingKey = true }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    } else {
                        // No key or override mode
                        VStack(alignment: .leading, spacing: 6) {
                            SecureField("Anthropic API key", text: $anthropicApiKey)
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                Text("Enter key, or set ANTHROPIC_API_KEY env var")
                                    .font(.caption).foregroundStyle(.secondary)
                                if isOverridingKey {
                                    Spacer()
                                    Button("Cancel") {
                                        isOverridingKey = false
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("System Prompt") {
                    Toggle("Customize system prompt", isOn: $cleanupSystemPromptEnabled)
                    if cleanupSystemPromptEnabled {
                        PromptEditor(
                            text: $cleanupSystemPrompt,
                            placeholder: CleanupService.defaultSystemPrompt,
                            emptyNote: "Empty = no system prompt sent",
                            onReset: { cleanupSystemPrompt = CleanupService.defaultSystemPrompt },
                            resetLabel: "Reset to default"
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI Cleanup")
    }
}

// MARK: - Storage

private struct StorageSettingsView: View {
    @EnvironmentObject var historyStore: HistoryStore
    @State private var showMoveConfirm = false
    @State private var pendingFolder: URL?

    var body: some View {
        Form {
            Section("Transcription History Location") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text(historyStore.storageFolder.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    HStack(spacing: 10) {
                        Button("Change...") { chooseFolder() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                        if !historyStore.isDefaultLocation {
                            Button("Reset to Default") { showMoveConfirm = true; pendingFolder = nil }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }

                        Button("Reveal in Finder") {
                            NSWorkspace.shared.open(historyStore.storageFolder)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Text("Murmur stores your transcription history as a JSON file. You can point it to any folder — for example, your iCloud Drive or Obsidian vault.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Storage")
        .confirmationDialog(
            "Move existing history?",
            isPresented: $showMoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Move") { applyFolderChange(move: true) }
            Button("Start fresh") { applyFolderChange(move: false) }
            Button("Cancel", role: .cancel) { pendingFolder = nil }
        } message: {
            Text("Do you want to move your existing history file to the new location, or start fresh?")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            pendingFolder = url
            showMoveConfirm = true
        }
    }

    private func applyFolderChange(move: Bool) {
        if let folder = pendingFolder {
            try? historyStore.changeStorageLocation(to: folder, moveExisting: move)
        } else {
            try? historyStore.resetStorageLocation(moveExisting: move)
        }
        pendingFolder = nil
    }
}

// MARK: - Shared components

struct PromptEditor: View {
    @Binding var text: String
    let placeholder: String
    let emptyNote: String
    let onReset: () -> Void
    let resetLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $text)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 72, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(5)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Text(emptyNote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(resetLabel, action: onReset)
                    .buttonStyle(.link)
                    .controlSize(.mini)
            }
        }
    }
}

enum OutputMode: String, CaseIterable {
    case clipboardAndPaste
    case clipboardOnly
}
