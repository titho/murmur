# The Great Dictator — Implementation Plan

## Overview

10 phases, ordered by dependency. Each phase produces working, testable output. Do not skip phases — each builds on the last.

**Stack**: Swift/SwiftUI + whisper.cpp (C submodule) + AVFoundation + AppKit
**Target**: macOS 13.0+, Apple Silicon primary

---

## Phase 1: Foundation

**What**: Xcode project skeleton, whisper.cpp submodule, build system wired up.

**Steps**:
1. Create Xcode project: macOS App, SwiftUI, Swift, bundle ID `com.yourname.TheGreatDictator`
2. Add whisper.cpp as git submodule: `git submodule add https://github.com/ggerganov/whisper.cpp`
3. Create C bridging header `WhisperBridgingHeader.h` and point to it in Build Settings
4. Add whisper.cpp source files to Xcode target compile sources (or use a static library via CMake)
5. Set `NSApp.setActivationPolicy(.accessory)` to hide from Dock
6. Verify: app builds and launches as a menu bar-only app (no Dock icon, no window)
7. Add `.gitignore` (Xcode artifacts, model files, `*.ggml`, `*.mlmodelc`)

**Dependencies**: None (start here)

**Acceptance criteria**:
- `cmd+B` in Xcode succeeds with no errors
- App launches with no Dock icon
- whisper.cpp headers are importable in Swift

**Complexity**: XL (most friction is here — build system setup with C library)

---

## Phase 2: Status Bar + Popover Shell

**What**: NSStatusItem in menu bar, popover that opens/closes, placeholder SwiftUI content.

**Steps**:
1. `StatusBarController.swift`: create `NSStatusItem`, set icon (SF Symbol: `waveform.circle`)
2. Wire up `NSPopover` with `RecordingPanelView` as content
3. Click on status item → toggle popover open/close
4. `RecordingPanelView.swift`: placeholder text ("Ready to dictate"), fixed size popover (300×200pt)
5. Right-click menu on status item: "Settings...", "Quit"
6. `SettingsView.swift`: empty window placeholder (just a label for now)

**Dependencies**: Phase 1

**Acceptance criteria**:
- Click menu bar icon → popover appears
- Right-click → shows context menu
- "Quit" quits the app

**Complexity**: M

---

## Phase 3: Audio Recording

**What**: Microphone capture via AVAudioEngine, WAV file output, mic permission request.

**Steps**:
1. `AudioRecorder.swift`:
   - Request microphone permission (`AVCaptureDevice.requestAccess`)
   - Set up `AVAudioEngine` with input node
   - Install tap: `inputNode.installTap(onBus:bufferSize:format:block:)`
   - Resample to 16kHz mono using `AVAudioConverter`
   - Write resampled PCM data to temp `.wav` file (`AVAudioFile`)
2. `start()` and `stop() -> URL` methods
3. Wire `DictationViewModel` to own an `AudioRecorder`
4. Add placeholder record/stop button to `RecordingPanelView`
5. Test: record 10 seconds, verify `.wav` file is valid (playable in QuickTime)

**Dependencies**: Phase 2

**Acceptance criteria**:
- Tapping record → mic permission prompt (first time)
- WAV file written to temp dir, playable in QuickTime
- Stop returns the file URL

**Complexity**: L

---

## Phase 4: Waveform Visualization

**What**: Real-time audio amplitude bars rendered in SwiftUI Canvas.

**Steps**:
1. During recording tap, compute RMS of each buffer: `sqrt(sum(x²) / n)`
2. Push RMS values to `@Published var waveformSamples: [Float]` in `DictationViewModel` (capped at 60 values)
3. `WaveformView.swift`:
   ```swift
   TimelineView(.animation) { _ in
       Canvas { ctx, size in
           // Draw N vertical bars, height = sample * size.height
           // Bars animate left as new samples arrive
       }
   }
   ```
4. Embed `WaveformView` in `RecordingPanelView`
5. Show flat/zero waveform when idle, animate when recording

**Dependencies**: Phase 3

**Acceptance criteria**:
- Waveform animates in real-time while recording
- Bars react visibly to loud vs quiet audio
- Smooth, no flickering

**Complexity**: M

---

## Phase 5: Whisper Integration

**What**: Call whisper.cpp from Swift to transcribe a WAV file.

**Steps**:
1. Download a test model for dev: `ggml-base.en.bin` (~150MB) via the whisper.cpp download script
2. `WhisperBridge.swift`:
   - `init(modelPath: String)` — calls `whisper_init_from_file()`
   - `transcribe(wavPath: String) -> String` — calls `whisper_full()`, collects segments
   - Handle `whisper_full_params` (language: "en", translate: false, no_timestamps: false)
3. Load model at app startup (or first use), show loading indicator
4. After `AudioRecorder.stop()` returns WAV URL → pass to `WhisperBridge.transcribe()`
5. Run transcription on a background `DispatchQueue` (not main thread — blocks for 1-3s)
6. Publish result to `DictationViewModel.lastTranscription`
7. Display transcription result in `RecordingPanelView`

**Dependencies**: Phase 3 (needs WAV files to transcribe)

**Acceptance criteria**:
- Record 10 words → see accurate, punctuated transcription in UI
- No UI freeze during transcription (runs off main thread)
- Model loads once, reused across recordings

**Complexity**: L

**Note**: CoreML acceleration is added in Phase 9. Use CPU-only for now.

---

## Phase 6: Global Hotkey

**What**: ⌘⇧D starts/stops recording from any app.

**Steps**:
1. `HotkeyManager.swift`:
   - Register `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`
   - Check for ⌘⇧D (keyCode 2 = 'd', modifiers: `.command | .shift`)
   - Call `DictationViewModel.toggleRecording()` on match
2. Wire up in `DictationViewModel.init()`
3. Status bar icon changes: idle → `waveform.circle`, recording → `waveform.circle.fill` (red tint), transcribing → spinner
4. Test: press ⌘⇧D in Safari → recording starts, press again → stops and transcribes

**Dependencies**: Phase 5

**Acceptance criteria**:
- Hotkey works in any foreground app
- Icon reflects state changes
- Second press stops recording and triggers transcription

**Complexity**: M

---

## Phase 7: Output — Clipboard + Paste

**What**: After transcription, copy to clipboard and paste into active text field.

**Steps**:
1. `OutputManager.swift`:
   - `copyToClipboard(_ text: String)`: `NSPasteboard.general.setString(text, forType: .string)`
   - `pasteToFrontApp(_ text: String)`:
     - Get `AXUIElementCreateSystemWide()` focused element
     - Try `AXUIElementSetAttributeValue` with `kAXValueAttribute`
     - On failure, fallback: simulate Cmd+V (after clipboard write)
2. Request Accessibility permission on first paste attempt (`AXIsProcessTrusted()`)
3. Show permission instructions if not granted
4. In `DictationViewModel`: after transcription → call `OutputManager`
5. Popover shows "Copied!" feedback for 1.5s then dismisses

**Dependencies**: Phase 5

**Acceptance criteria**:
- Transcription appears in the active text field in Safari, Notes, VSCode, Terminal
- Clipboard always contains the transcription as fallback
- Popover auto-dismisses after output

**Complexity**: S-M (AX permission UI is the tricky part)

---

## Phase 8: Settings

**What**: Persistent settings — hotkey, output mode, model selection.

**Steps**:
1. `AppSettings.swift`: `@AppStorage` backed struct with:
   - `hotkey: String` (default: "⌘⇧D")
   - `outputMode: OutputMode` (.clipboardAndPaste / .clipboardOnly)
   - `selectedModel: WhisperModel` (.largev3turbo / .baseEn)
2. `SettingsView.swift` (replace placeholder):
   - Hotkey recorder (click to capture new hotkey)
   - Output mode picker
   - Model selector with disk usage shown
   - "Open Models Folder" button
3. Wire `HotkeyManager` to read from `AppSettings`
4. Wire `OutputManager` to respect `outputMode`
5. Open Settings window from status bar right-click menu

**Dependencies**: Phases 6, 7

**Acceptance criteria**:
- Change hotkey → new hotkey works immediately
- Change output mode → next transcription respects it
- Settings persist across app restarts

**Complexity**: M

---

## Phase 9: Model Management + CoreML

**What**: First-launch model download flow, CoreML acceleration.

**Steps**:
1. `ModelManager.swift`:
   - Check for model file in `~/Library/Application Support/TheGreatDictator/Models/`
   - If missing: show onboarding sheet explaining download size and privacy
   - Download via `URLSession` with progress (`URLSessionDownloadTask`)
   - Verify SHA256 of downloaded file
   - Publish `@Published var downloadProgress: Double`
2. First-launch onboarding `WelcomeView.swift`:
   - Explains the app, one-time model download, privacy (offline)
   - Shows download progress bar
   - "Use Small Model Instead" option (base.en, ~150MB)
3. CoreML acceleration:
   - Use whisper.cpp's `generate-coreml-model.sh` (or pre-generate and cache alongside)
   - Compile whisper.cpp with `-DWHISPER_COREML=1` in Xcode build settings
   - On model load, if `.mlmodelc` exists next to `.bin`, CoreML encoder is used automatically
4. Measure and verify: 30s audio should transcribe in <3s on M1

**Dependencies**: Phase 5 (replaces hardcoded model path)

**Acceptance criteria**:
- Fresh install shows welcome/download screen
- Download shows accurate progress
- Post-download: app works with the downloaded model
- Transcription time <3s on Apple Silicon (CoreML)

**Complexity**: L

---

## Phase 10: Polish + Distribution

**What**: App icon, error handling, edge cases, distribution prep.

**Steps**:
1. App icon: design or use SF Symbol–based icon at all required sizes (1024×1024 base)
2. Status bar icons: proper `@2x` assets for Retina
3. Error handling:
   - Microphone permission denied → friendly alert with "Open System Settings" button
   - Accessibility permission denied → same
   - Model file corrupted → offer re-download
   - No microphone found → graceful error in popover
   - Transcription failed → show error in popover, keep recording for retry
4. Edge cases:
   - Very short recording (<0.5s) → discard, show "Too short" message
   - Recording while already transcribing → queue or block with feedback
   - App update with new model format → migration
5. Notarization prep:
   - Enable App Sandbox (if distributing via MAS) or Hardened Runtime (direct distribution)
   - Required entitlements: `com.apple.security.device.audio-input`, `com.apple.security.automation.apple-events`
   - Codesign with Developer ID
6. README.md for users

**Dependencies**: All previous phases

**Acceptance criteria**:
- All error states show helpful messages (no crashes, no blank states)
- App passes notarization
- Works on a clean Mac with no prior setup

**Complexity**: M

---

## Dependency Graph

```
Phase 1: Foundation
    └── Phase 2: Status Bar Shell
            ├── Phase 3: Audio Recording
            │       ├── Phase 4: Waveform
            │       └── Phase 5: Whisper Integration
            │               ├── Phase 6: Global Hotkey
            │               ├── Phase 7: Output
            │               │       └── Phase 8: Settings
            │               └── Phase 9: Model Management
            └──────────────────── Phase 10: Polish (after all above)
```

## Summary Table

| Phase | What | Complexity | Dep |
|---|---|---|---|
| 1 | Foundation + build system | XL | — |
| 2 | Status bar + popover shell | M | 1 |
| 3 | Audio recording (AVAudioEngine) | L | 2 |
| 4 | Waveform visualization | M | 3 |
| 5 | Whisper integration (C bridge) | L | 3 |
| 6 | Global hotkey | M | 5 |
| 7 | Output (clipboard + paste) | S-M | 5 |
| 8 | Settings | M | 6,7 |
| 9 | Model management + CoreML | L | 5 |
| 10 | Polish + distribution | M | all |
