# Murmur — Problems Fix Design
Date: 2026-02-26

## Problems Being Solved

1. No stable app to reopen
2. `./run.sh` is slow
3. Pasting directly after speech finishes doesn't work
4. Inconsistent transcription speed (sometimes 5–10s for 15s audio)
5. Asks for microphone permission on every open
6. (New) No way to track how heavy the app is on the laptop

---

## 1. Stable App — Install to /Applications + Launch at Login

**Approach:** After building, `run.sh` copies the built `.app` to `/Applications/Murmur.app`. This gives the app a stable, consistent identity on disk.

**Launch at Login:** Add a toggle in Settings > General backed by `SMAppService.mainApp.register()` / `.unregister()`. Persisted as `launchAtLogin` UserDefault.

**Why this fixes mic permissions (#5):** macOS ties sandbox permissions to the app's bundle path + team ID. Running from an unstable DerivedData path causes permission re-requests. `/Applications/Murmur.app` is stable.

---

## 2. Faster run.sh

**Approach:** Skip `xcodegen generate` if `project.yml` is older than the `.xcodeproj` directory (compare mtimes with `find`/`stat`). Most runs skip xcodegen and save ~1–2s.

---

## 3. Fix Paste After Speech

**Root causes:**
- 150ms focus-restore delay is too short → increase to 400ms
- `OutputManager.pasteToFrontApp()` uses `AXUIElementSetAttributeValue` to set the field's *entire value*, which replaces existing content instead of inserting at cursor

**Fix:**
- Remove the AX set-value path entirely; always use `simulatePaste()` (CGEvent Cmd+V)
- Increase the post-activate sleep in `DictationViewModel.stopAndTranscribe()` from 150ms to 400ms

---

## 4. Consistent Transcription Speed — WhisperKit Warmup

**Root cause:** WhisperKit's first transcription after model load triggers ANE/GPU JIT compilation, making it 3–5× slower than subsequent ones.

**Fix:** After `loadModel()` succeeds, run a warmup transcription on a synthetic 1-second silent WAV in the background. The model is primed; the first real transcription is then consistently fast.

**Bonus bug fix:** `WhisperService.transcribe()` accepts `initialPrompt` but never passes it to `DecodingOptions`. Fix by including it in the options.

---

## 5. Mic Permission — Fixed by #1

Stable `/Applications/Murmur.app` identity fixes the root cause. Additionally, call `AVCaptureDevice.requestAccess(for: .audio)` at app launch (in `AppDelegate.applicationDidFinishLaunching`) so the permission dialog appears once on first launch rather than at first recording.

---

## 6. Resource Usage Tracking

### Live display
Add a compact "Resource" footer in `RecordingPanelView` (the status bar popover) showing:
- Memory: resident set size in MB via `mach_task_basic_info`
- CPU: process CPU % sampled every 2s via `getrusage` delta
- Uptime since app launch

A `ResourceMonitor` class owns a repeating `Timer`, publishes `@Published` values, and is passed as an environment object.

### Persistent metrics log
**Format:** JSON Lines (`.jsonl`) — one JSON object per line, append-only. Easy to tail, grep, or load into Python/Excel.

**Location:** `~/Library/Application Support/Murmur/metrics.jsonl`

**Schema per line:**
```json
{"ts": 1740000000, "cpu_pct": 2.3, "mem_mb": 84, "uptime_s": 3600}
```

**Sampling:** Every 60 seconds (not every 2s display sample). File is capped at ~10,000 lines (~500KB); older lines are dropped when the cap is hit.

A `MetricsLogger` class handles append + rotation, called from `ResourceMonitor`.

---

## Files Changed

| File | Change |
|------|--------|
| `run.sh` | Skip xcodegen if project.yml unchanged; copy to /Applications |
| `App/AppDelegate.swift` | Request mic permission at launch |
| `ViewModels/DictationViewModel.swift` | Increase paste delay; warmup after model load |
| `Services/WhisperService.swift` | Pass initialPrompt to DecodingOptions; add warmup method |
| `Services/OutputManager.swift` | Remove AX set-value path; always simulatePaste |
| `Services/ResourceMonitor.swift` | New: CPU/mem sampling, publishes to ViewModel |
| `Services/MetricsLogger.swift` | New: JSONL append + rotation |
| `UI/RecordingPanelView.swift` | Add resource footer |
| `UI/SettingsView.swift` | Add Launch at Login toggle |
