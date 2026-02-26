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
                                expandedID = entry.id
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

                    if hasMetrics || entry.cleanedText != nil || CleanupService.resolvedApiKey() != nil {
                        Button { onToggleExpand() } label: {
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
                    if hasMetrics {
                        MetricsGridView(entry: entry)
                    }

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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
        }
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
