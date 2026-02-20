import SwiftUI
import AppKit

struct HistoryView: View {
    @EnvironmentObject var historyStore: HistoryStore
    @State private var showClearConfirm = false
    @State private var copiedID: UUID?

    private var totalWords: Int {
        historyStore.entries.reduce(0) { $0 + $1.wordCount }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Stats + action bar
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
                    HistoryRowView(entry: entry, isCopied: copiedID == entry.id) {
                        copyToClipboard(entry)
                    }
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
        NSPasteboard.general.setString(entry.text, forType: .string)
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
    let onCopy: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Main content
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .lineLimit(2)
                    .font(.body)

                Text(Self.dateFormatter.string(from: entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Token usage — shown only when AI cleanup was used
                if let input = entry.inputTokens, let output = entry.outputTokens {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .imageScale(.small)
                        Text("\(input) in")
                        Text("·")
                        Text("\(output) out")
                    }
                    .font(.caption2)
                    .foregroundStyle(.purple.opacity(0.8))
                }
            }

            Spacer()

            // Right column
            VStack(alignment: .trailing, spacing: 6) {
                Button(isCopied ? "Copied" : "Copy") { onCopy() }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .foregroundStyle(isCopied ? .green : Color.accentColor)
            }
        }
        .padding(.vertical, 4)
    }

}
