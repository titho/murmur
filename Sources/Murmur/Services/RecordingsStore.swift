import Foundation

class RecordingsStore: ObservableObject {
    let recordingsFolder: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Murmur/recordings")
        recordingsFolder = appSupport
        try? FileManager.default.createDirectory(
            at: appSupport, withIntermediateDirectories: true
        )
    }

    func recordingURL(for id: UUID) -> URL {
        recordingsFolder.appendingPathComponent("\(id.uuidString).wav")
    }

    func hasRecording(for id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: recordingURL(for: id).path)
    }

    /// Move (not copy) the temp WAV into the recordings folder.
    func save(tempURL: URL, for id: UUID) {
        let dest = recordingURL(for: id)
        try? FileManager.default.moveItem(at: tempURL, to: dest)
    }

    func delete(for id: UUID) {
        try? FileManager.default.removeItem(at: recordingURL(for: id))
    }

    /// Total bytes used by the recordings folder.
    func totalSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: recordingsFolder,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return 0 }
        return enumerator.compactMap { url -> Int64? in
            guard let u = url as? URL,
                  let v = try? u.resourceValues(forKeys: [.fileSizeKey]),
                  let size = v.fileSize else { return nil }
            return Int64(size)
        }.reduce(0, +)
    }
}
