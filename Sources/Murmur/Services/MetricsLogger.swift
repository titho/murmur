import Foundation

/// Appends one JSON-Lines record per minute to:
///   ~/Library/Application Support/Murmur/metrics.jsonl
///
/// Schema: {"ts":1740000000,"cpu_pct":2.3,"mem_mb":84.0,"uptime_s":3600}
///
/// File is capped at 10,000 lines (~500 KB); oldest entries are dropped
/// when the cap is hit to keep the file lightweight forever.
class MetricsLogger {
    private let maxLines = 10_000
    private let logURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Murmur")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logURL = dir.appendingPathComponent("metrics.jsonl")
    }

    func append(cpu: Double, mem: Double, uptime: TimeInterval) {
        let ts = Int(Date().timeIntervalSince1970)
        let cpuRounded = (cpu * 10).rounded() / 10
        let memRounded = (mem * 10).rounded() / 10
        let uptimeInt = Int(uptime)
        let line = "{\"ts\":\(ts),\"cpu_pct\":\(cpuRounded),\"mem_mb\":\(memRounded),\"uptime_s\":\(uptimeInt)}\n"
        guard let data = line.data(using: .utf8) else { return }
        writeWithRotation(data: data)
    }

    private func writeWithRotation(data: Data) {
        let fm = FileManager.default
        if fm.fileExists(atPath: logURL.path) {
            if let existing = try? String(contentsOf: logURL, encoding: .utf8) {
                let lines = existing.split(separator: "\n", omittingEmptySubsequences: true)
                if lines.count >= maxLines {
                    let kept = lines.suffix(maxLines - 1000).joined(separator: "\n") + "\n"
                    try? kept.write(to: logURL, atomically: true, encoding: .utf8)
                }
            }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logURL)
        }
    }
}
