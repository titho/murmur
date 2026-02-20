import Foundation
import Combine

class HistoryStore: ObservableObject {
    @Published var entries: [TranscriptionEntry] = []

    private let maxEntries = 200
    private let storagePathKey = "historyStoragePath"

    private static let defaultDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Murmur")
    }()

    var storageFolder: URL {
        let saved = UserDefaults.standard.string(forKey: storagePathKey) ?? ""
        if !saved.isEmpty {
            return URL(fileURLWithPath: saved)
        }
        return HistoryStore.defaultDirectory
    }

    var isDefaultLocation: Bool {
        let saved = UserDefaults.standard.string(forKey: storagePathKey) ?? ""
        return saved.isEmpty
    }

    private var storageURL: URL {
        storageFolder.appendingPathComponent("history.json")
    }

    init() {
        ensureDirectoryExists(storageFolder)
        load()
    }

    // MARK: - CRUD

    func append(_ entry: TranscriptionEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func exportMarkdown(to url: URL) throws {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var lines = ["# Dictation History", ""]
        for entry in entries {
            lines.append("## \(formatter.string(from: entry.date))")
            lines.append("")
            lines.append(entry.text)
            lines.append("")
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Location management

    /// Change the storage folder. Optionally moves the existing history.json.
    func changeStorageLocation(to folder: URL, moveExisting: Bool) throws {
        let oldURL = storageURL
        let newURL = folder.appendingPathComponent("history.json")

        ensureDirectoryExists(folder)

        if moveExisting && FileManager.default.fileExists(atPath: oldURL.path) {
            if FileManager.default.fileExists(atPath: newURL.path) {
                try FileManager.default.removeItem(at: newURL)
            }
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        }

        UserDefaults.standard.set(folder.path, forKey: storagePathKey)
        objectWillChange.send()

        if moveExisting {
            load()
        } else {
            entries = []
        }
    }

    /// Revert to the default ~/Library/Application Support location.
    func resetStorageLocation(moveExisting: Bool) throws {
        let folder = HistoryStore.defaultDirectory
        ensureDirectoryExists(folder)

        if moveExisting {
            let oldURL = storageURL
            let newURL = folder.appendingPathComponent("history.json")
            if FileManager.default.fileExists(atPath: oldURL.path) {
                if FileManager.default.fileExists(atPath: newURL.path) {
                    try FileManager.default.removeItem(at: newURL)
                }
                try FileManager.default.moveItem(at: oldURL, to: newURL)
            }
        }

        UserDefaults.standard.removeObject(forKey: storagePathKey)
        objectWillChange.send()

        if moveExisting {
            load()
        } else {
            entries = []
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([TranscriptionEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func ensureDirectoryExists(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
