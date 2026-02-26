import Darwin
import Foundation

/// Samples CPU % and memory (RSS) every 2 seconds for live display,
/// and logs to MetricsLogger every 60 seconds for historical analysis.
@MainActor
class ResourceMonitor: ObservableObject {
    @Published var cpuPercent: Double = 0
    @Published var memoryMB: Double = 0

    let uptimeStart = Date()
    var uptimeSeconds: TimeInterval { Date().timeIntervalSince(uptimeStart) }

    private var timer: Timer?
    private var lastCPUTime: Double = 0
    private var lastWallTime = Date()
    private var tickCount = 0
    private let logEveryTicks = 30 // 30 × 2s = 60s
    private let metricsLogger = MetricsLogger()

    func start() {
        lastCPUTime = totalCPUTime()
        lastWallTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func tick() {
        memoryMB = currentMemoryMB()
        cpuPercent = currentCPUPercent()
        tickCount += 1
        if tickCount >= logEveryTicks {
            tickCount = 0
            metricsLogger.append(cpu: cpuPercent, mem: memoryMB, uptime: uptimeSeconds)
        }
    }

    private func currentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576
    }

    private func totalCPUTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let sys  = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + sys
    }

    private func currentCPUPercent() -> Double {
        let now = Date()
        let wallElapsed = now.timeIntervalSince(lastWallTime)
        let currentCPU = totalCPUTime()
        let cpuElapsed = currentCPU - lastCPUTime
        lastCPUTime = currentCPU
        lastWallTime = now
        guard wallElapsed > 0 else { return 0 }
        return min((cpuElapsed / wallElapsed) * 100, 100)
    }
}
