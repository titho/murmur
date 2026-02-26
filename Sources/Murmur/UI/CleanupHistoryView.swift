import SwiftUI
import AppKit

struct CleanupHistoryView: View {
    @EnvironmentObject var historyStore: HistoryStore

    private var cleanedEntries: [TranscriptionEntry] {
        historyStore.entries.filter { $0.cleanedText != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
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
                    Text("Use \u{201c}Run Cleanup\u{201d} on any history entry, or enable AI Cleanup in settings.")
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
