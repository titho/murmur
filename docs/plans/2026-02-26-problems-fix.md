# Problems Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all 5 items from PROBLEMS.md and add lightweight resource monitoring with persistent metrics logging.

**Architecture:** Fixes are surgical — each touches only the file(s) responsible for that bug. Two new service files (`ResourceMonitor.swift`, `MetricsLogger.swift`) are added under `Sources/Murmur/Services/`. xcodegen auto-discovers all Swift files in that directory, so no `project.yml` changes are needed.

**Tech Stack:** Swift 5.9, macOS 14+, `SMAppService` (login items), `mach_task_basic_info` + `getrusage` (resource sampling), Darwin, AppKit, SwiftUI.

---

## Task 1: Fix run.sh — skip xcodegen when unchanged, install to ~/Applications

**Files:**
- Modify: `run.sh`

**Step 1: Read current run.sh, then replace with this**

```bash
#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Skip xcodegen if project.yml hasn't changed since .xcodeproj was last generated
PROJ_YML="$PROJECT_DIR/project.yml"
XCODEPROJ="$PROJECT_DIR/Murmur.xcodeproj"
if [ ! -d "$XCODEPROJ" ] || [ "$PROJ_YML" -nt "$XCODEPROJ" ]; then
  echo "▶ Generating project (project.yml changed)..."
  cd "$PROJECT_DIR"
  xcodegen generate --quiet
else
  echo "▶ Skipping xcodegen (project.yml unchanged)"
fi

echo "▶ Building..."
xcodebuild \
  -scheme Murmur \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  -quiet 2>&1 | grep -v "^ld: warning"

echo "▶ Installing to ~/Applications..."
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Murmur-* -name "Murmur.app" -type d 2>/dev/null | grep "/Debug/" | head -1)
mkdir -p ~/Applications
rm -rf ~/Applications/Murmur.app
cp -r "$APP_PATH" ~/Applications/Murmur.app

echo "▶ Relaunching..."
pkill -x "Murmur" 2>/dev/null || true
sleep 0.3
open ~/Applications/Murmur.app
echo "✓ Done — app installed at ~/Applications/Murmur.app"
```

**Step 2: Make executable and test**

```bash
chmod +x /path/to/murmur/run.sh
./run.sh
```

Expected: First run prints "Generating project...". Second run prints "Skipping xcodegen". App opens from ~/Applications/Murmur.app (verify with `ps aux | grep Murmur`).

**Step 3: Verify app is findable**

Open Spotlight (⌘Space), type "Murmur" — it should appear as an app in ~/Applications.

**Step 4: Commit**

```bash
git add run.sh
git commit -m "fix: skip xcodegen when project.yml unchanged; install to ~/Applications"
```

---

## Task 2: Request microphone permission at launch

The mic permission dialog was appearing on every recording start because the app ran from a different DerivedData path each time (unstable identity). Installing to ~/Applications (Task 1) fixes the root cause. Additionally, request permission eagerly at launch so it's cached before first use.

**Files:**
- Modify: `Sources/Murmur/App/AppDelegate.swift`

**Step 1: Add eager mic permission request**

In `applicationDidFinishLaunching`, add this block right before `viewModel.setup()`:

```swift
// Request mic permission at launch so it's cached before first recording.
// The app's stable identity (~/Applications/Murmur.app) ensures macOS
// remembers the grant across relaunches.
AVCaptureDevice.requestAccess(for: .audio) { _ in }
```

Also add `import AVFoundation` at the top if not already present.

Full updated file:

```swift
import AppKit
import AVFoundation
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = DictationViewModel()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "maxRecordingSeconds": 120,
            "maxRecordingEnabled": true,
            "cleanupEnabled": false,
            "cleanupModel": "claude-haiku-4-5-20251001",
            "selectedModel": "large-v3_turbo",
            "historyStoragePath": "",
            "pillEnabled": true,
        ])

        NSApp.setActivationPolicy(.accessory)

        // Request mic permission eagerly so it's cached before first recording
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        statusBarController = StatusBarController(viewModel: viewModel)
        viewModel.setup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.cleanup()
    }
}
```

**Step 2: Build and verify**

```bash
./run.sh
```

Expected: On first launch from ~/Applications/Murmur.app, a mic permission dialog appears immediately. On subsequent launches, no dialog.

**Step 3: Commit**

```bash
git add Sources/Murmur/App/AppDelegate.swift
git commit -m "fix: request mic permission at launch, not at first recording"
```

---

## Task 3: Fix paste — always use simulatePaste (Cmd+V)

The `AXUIElementSetAttributeValue` call was **replacing** the entire text field content instead of inserting at cursor. Drop that path entirely and always use the CGEvent Cmd+V approach, which works the same way as a user pressing ⌘V.

**Files:**
- Modify: `Sources/Murmur/Services/OutputManager.swift`

**Step 1: Replace OutputManager.swift**

```swift
import AppKit
import ApplicationServices

class OutputManager {
    /// Copy text to clipboard and (if outputMode allows) paste into frontmost app.
    func output(_ text: String) {
        let mode = UserDefaults.standard.string(forKey: "outputMode") ?? "clipboardAndPaste"
        copyToClipboard(text)
        if mode == "clipboardAndPaste" {
            simulatePaste()
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func simulatePaste() {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        let loc = CGEventTapLocation.cghidEventTap
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
    }
}
```

**Step 2: Build**

```bash
./run.sh
```

**Step 3: Manual test**

Open a text editor (e.g. Notes). Place cursor in a document with existing text. Trigger dictation. Verify text is **inserted at cursor** (not replacing entire content).

**Step 4: Commit**

```bash
git add Sources/Murmur/Services/OutputManager.swift
git commit -m "fix: always use Cmd+V for paste; remove AX set-value which replaced entire field"
```

---

## Task 4: Increase focus-restore delay before paste (150ms → 400ms)

After transcription, the app re-activates the previous frontmost app before pasting. 150ms isn't enough for some apps (especially Electron apps like VS Code, Notion) to regain focus and route Cmd+V to the text field.

**Files:**
- Modify: `Sources/Murmur/ViewModels/DictationViewModel.swift`

**Step 1: Find and update the two sleep durations**

In `stopAndTranscribe()` at line ~213:
```swift
// Change from:
try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s for focus to settle
// To:
try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s for focus to settle
```

In `transcribeAudioFile(url:targetApp:)` at line ~177, same change:
```swift
try? await Task.sleep(nanoseconds: 400_000_000)
```

**Step 2: Build and test**

```bash
./run.sh
```

Trigger dictation while cursor is inside a VS Code editor or Notes. Text should appear at cursor reliably.

**Step 3: Commit**

```bash
git add Sources/Murmur/ViewModels/DictationViewModel.swift
git commit -m "fix: increase focus-restore delay from 150ms to 400ms before paste"
```

---

## Task 5: WhisperKit warmup after model load

The first transcription after model load is 3-5× slower because the Apple Neural Engine / GPU needs to JIT-compile the CoreML graph. Run a silent warmup transcription immediately after load so real dictations are consistently fast.

**Files:**
- Modify: `Sources/Murmur/Services/WhisperService.swift`
- Modify: `Sources/Murmur/ViewModels/DictationViewModel.swift`

**Step 1: Add warmup method to WhisperService**

Add these two methods inside `WhisperService`, after `transcribe()`:

```swift
/// Prime the ANE/GPU pipeline with a silent audio clip.
/// Call once after loadModel() to make the first real transcription fast.
func warmup() async {
    guard pipe != nil else { return }
    let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("murmur_warmup.wav")
    createSilentWAV(at: tmpURL, durationSeconds: 1)
    _ = try? await transcribe(audioURL: tmpURL)
    try? FileManager.default.removeItem(at: tmpURL)
}

private func createSilentWAV(at url: URL, durationSeconds: Int) {
    let sampleRate: UInt32 = 16000
    let numChannels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let numSamples = UInt32(sampleRate) * UInt32(durationSeconds)
    let dataSize = numSamples * UInt32(numChannels) * UInt32(bitsPerSample / 8)
    let chunkSize = 36 + dataSize

    var wav = Data()
    func u32le(_ v: UInt32) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: 4)) }
    func u16le(_ v: UInt16) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: 2)) }

    wav.append("RIFF".data(using: .ascii)!); u32le(chunkSize)
    wav.append("WAVE".data(using: .ascii)!)
    wav.append("fmt ".data(using: .ascii)!); u32le(16); u16le(1)
    u16le(numChannels); u32le(sampleRate)
    u32le(sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8))
    u16le(numChannels * bitsPerSample / 8); u16le(bitsPerSample)
    wav.append("data".data(using: .ascii)!); u32le(dataSize)
    wav.append(Data(count: Int(dataSize))) // silence

    try? wav.write(to: url)
}
```

**Step 2: Call warmup in DictationViewModel after model loads**

In `DictationViewModel.loadModelIfNeeded()`, after `isModelReady = true`:

```swift
try await whisperService.loadModel(variant: variant)
isModelReady = true
state = .idle
// Prime the pipeline so first real dictation isn't slow
Task { await whisperService.warmup() }
```

**Step 3: Build and time**

```bash
./run.sh
```

Start the app, wait for model to load (the status changes from "Loading model…" to idle). Then immediately trigger a short dictation. The transcription should finish in under 2 seconds (previously could take 5-10s for the first run).

**Step 4: Commit**

```bash
git add Sources/Murmur/Services/WhisperService.swift Sources/Murmur/ViewModels/DictationViewModel.swift
git commit -m "perf: warm up WhisperKit ANE/GPU pipeline after model load to avoid first-transcription slowness"
```

---

## Task 6: Create MetricsLogger — JSONL append with rotation

**Files:**
- Create: `Sources/Murmur/Services/MetricsLogger.swift`

**Step 1: Create the file**

```swift
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
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
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
            // Rotate if over cap
            if let existing = try? String(contentsOf: logURL, encoding: .utf8) {
                let lines = existing.split(separator: "\n", omittingEmptySubsequences: true)
                if lines.count >= maxLines {
                    let kept = lines.suffix(maxLines - 1000).joined(separator: "\n") + "\n"
                    try? kept.write(to: logURL, atomically: true, encoding: .utf8)
                }
            }
            // Append
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
```

**Step 2: Build to check compilation**

```bash
./run.sh
```

Expected: Builds without errors.

**Step 3: Commit**

```bash
git add Sources/Murmur/Services/MetricsLogger.swift
git commit -m "feat: add MetricsLogger — JSONL metrics with 10k-line rotation"
```

---

## Task 7: Create ResourceMonitor — CPU and memory sampling

**Files:**
- Create: `Sources/Murmur/Services/ResourceMonitor.swift`

**Step 1: Create the file**

```swift
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
        // Prime CPU baseline
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
```

**Step 2: Build**

```bash
./run.sh
```

Expected: Compiles without errors.

**Step 3: Commit**

```bash
git add Sources/Murmur/Services/ResourceMonitor.swift
git commit -m "feat: add ResourceMonitor — CPU%/memory sampling with 60s metrics logging"
```

---

## Task 8: Wire ResourceMonitor into the app

**Files:**
- Modify: `Sources/Murmur/ViewModels/DictationViewModel.swift`
- Modify: `Sources/Murmur/App/AppDelegate.swift`
- Modify: `Sources/Murmur/UI/StatusBarController.swift`

**Step 1: Add ResourceMonitor to DictationViewModel**

Add as a property and start/stop it with the VM lifecycle:

```swift
// In DictationViewModel — add property:
let resourceMonitor = ResourceMonitor()

// In setup():
resourceMonitor.start()

// In cleanup():
resourceMonitor.stop()
```

**Step 2: Pass resourceMonitor as environment object in StatusBarController**

Find where `StatusBarController` injects environment objects into the popover and settings window. Add `resourceMonitor`:

Read `Sources/Murmur/UI/StatusBarController.swift` first to find the exact injection points (search for `.environmentObject(viewModel)`). Add `.environmentObject(viewModel.resourceMonitor)` in the same chain, for both the popover content and the settings window hosting view.

**Step 3: Build**

```bash
./run.sh
```

**Step 4: Commit**

```bash
git add Sources/Murmur/ViewModels/DictationViewModel.swift Sources/Murmur/UI/StatusBarController.swift
git commit -m "feat: wire ResourceMonitor into app lifecycle and environment"
```

---

## Task 9: Add resource footer to RecordingPanelView

**Files:**
- Modify: `Sources/Murmur/UI/RecordingPanelView.swift`

**Step 1: Add @EnvironmentObject and resource footer**

Add at the top of `RecordingPanelView`:
```swift
@EnvironmentObject var resourceMonitor: ResourceMonitor
```

Add a `resourceFooter` computed property:
```swift
private var resourceFooter: some View {
    HStack(spacing: 12) {
        Label(
            String(format: "%.0f MB", resourceMonitor.memoryMB),
            systemImage: "memorychip"
        )
        Label(
            String(format: "%.1f%% CPU", resourceMonitor.cpuPercent),
            systemImage: "cpu"
        )
        Spacer()
        let h = Int(resourceMonitor.uptimeSeconds) / 3600
        let m = (Int(resourceMonitor.uptimeSeconds) % 3600) / 60
        Text(h > 0 ? "\(h)h \(m)m" : "\(m)m")
    }
    .font(.system(size: 10, design: .monospaced))
    .foregroundStyle(.tertiary)
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
}
```

Add the footer at the bottom of the main `body` VStack, after the existing footer block:

```swift
// Resource footer — always visible
Divider()
resourceFooter
```

Insert it just before the closing `}` of the outer VStack, after the recording stop-button footer block.

**Step 2: Build and verify visually**

```bash
./run.sh
```

Open the status bar popover. The bottom should show something like:
```
💾 84 MB  🖥 1.2% CPU            2m
```

**Step 3: Commit**

```bash
git add Sources/Murmur/UI/RecordingPanelView.swift
git commit -m "feat: show live CPU%, memory, and uptime in status bar popover"
```

---

## Task 10: Add Launch at Login toggle to Settings

**Files:**
- Modify: `Sources/Murmur/UI/SettingsView.swift`

**Step 1: Add import and toggle**

Add `import ServiceManagement` at the top of `SettingsView.swift`.

In `GeneralSettingsView`, add a `@AppStorage` property:
```swift
@AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
```

Add this toggle at the **top** of the `Form`, as its own `Section`:

```swift
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
                // Revert if registration fails (app not installed to /Applications or ~/Applications)
                launchAtLogin = !enabled
            }
        }
} footer: {
    Text("Murmur must be running from ~/Applications/Murmur.app (run ./run.sh once to install).")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

**Step 2: Build**

```bash
./run.sh
```

**Step 3: Manual test**

Open Settings → General. Toggle "Launch at login" on. Go to System Settings → General → Login Items — "Murmur" should appear. Toggle off — it should disappear.

**Step 4: Commit**

```bash
git add Sources/Murmur/UI/SettingsView.swift
git commit -m "feat: add Launch at Login toggle (SMAppService) in General settings"
```

---

## Task 11: Clear PROBLEMS.md

**Files:**
- Modify: `PROBLEMS.md`

**Step 1: Replace with empty file or resolved notes**

```markdown
# Problems

All resolved as of 2026-02-26. See docs/plans/2026-02-26-problems-fix.md.
```

**Step 2: Commit**

```bash
git add PROBLEMS.md
git commit -m "docs: mark all problems resolved"
```

---

## Verification checklist (after all tasks)

Run through each fix manually:

- [ ] `./run.sh` twice — second run skips xcodegen (prints "Skipping xcodegen")
- [ ] App appears in Spotlight as "Murmur" (from ~/Applications)
- [ ] First launch shows mic permission dialog; second launch does not
- [ ] Dictation inserts text **at cursor** in a text editor (not replacing entire content)
- [ ] Dictation in VS Code/Slack/Notion pastes reliably (no missed paste)
- [ ] First dictation after launch is fast (not 5-10s) — warmup did its job
- [ ] Status bar popover shows memory/CPU/uptime footer
- [ ] After 1 minute, `~/"Library/Application Support/Murmur/metrics.jsonl"` has at least 1 line
- [ ] Launch at Login toggle appears in Settings → General; works as expected

## Metrics log inspection

```bash
tail -5 ~/Library/Application\ Support/Murmur/metrics.jsonl
# Expected output (one JSON object per line):
# {"ts":1740000060,"cpu_pct":1.2,"mem_mb":84.3,"uptime_s":60}
# {"ts":1740000120,"cpu_pct":0.8,"mem_mb":85.1,"uptime_s":120}
```

To analyze in Python later:
```python
import json, pathlib
lines = pathlib.Path("~/Library/Application Support/Murmur/metrics.jsonl")
         .expanduser().read_text().splitlines()
records = [json.loads(l) for l in lines]
```
