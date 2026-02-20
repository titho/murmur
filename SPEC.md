# The Great Dictator — Technical Specification

## Executive Summary

The Great Dictator is a lightweight, privacy-first dictation app for macOS. It lives entirely in the menu bar, activates via a global hotkey, records your voice, and pastes properly punctuated transcribed text into whatever app you're typing in. It uses a local whisper.cpp model accelerated by CoreML/Metal on Apple Silicon — no cloud, no subscriptions, no data leaving your machine. The entire stack is pure Swift/SwiftUI with whisper.cpp as a C library, producing a single native `.app` bundle with no runtime dependencies.

---

## Technology Stack

### UI Framework: SwiftUI + AppKit

**Decision**: Pure Swift, SwiftUI for views, AppKit for system integration (NSStatusItem, NSEvent, AXUIElement).

**Rationale**:
- Fully native macOS look and feel with no compromises
- First-class access to AVFoundation, CoreML, Accessibility frameworks
- Single binary `.app` — no Python runtime, no Node, no Electron bloat
- SwiftUI `Canvas` + `TimelineView` for 60fps waveform rendering
- Easy distribution: drag-and-drop install or notarized DMG

**Rejected alternatives**:
- Python + PyObjC: poor distribution story, slow startup, feels second-class
- Electron/Tauri: wrong for a tool that needs deep system integration and minimal footprint
- Python backend + Swift frontend (IPC): two codebases, unnecessary complexity
- React Native / Flutter: no real macOS-native status bar app support

### Transcription Engine: whisper.cpp

**Decision**: whisper.cpp as a git submodule, compiled as a static library, called from Swift via a C bridging header.

**Rationale**:
- Runs 100% locally — complete privacy
- CoreML acceleration on Apple Silicon: M1 transcribes 30s audio in ~1-2 seconds
- Native C library — zero runtime dependencies beyond what's in the `.app`
- Supports Whisper large-v3-turbo (best speed/quality tradeoff, ~800MB)
- Whisper natively outputs punctuated text (no post-processing needed)
- Active development, CoreML model support built-in

**Model choice**: `ggml-large-v3-turbo` (default), with `ggml-base.en` as a fast fallback option in Settings.

**Rejected alternatives**:
- Apple SFSpeechRecognizer: cloud by default, inferior punctuation, no control over model
- faster-whisper: Python runtime required, harder to ship as `.app`
- mlx-whisper: Python runtime still needed; whisper.cpp has better Swift integration
- OpenAI API: cloud dependency, not offline-first

### Audio: AVAudioEngine

AVAudioEngine with a tap on the input bus. PCM buffers are:
1. Accumulated in memory during recording
2. Streamed to a `WaveformViewModel` for real-time visualization
3. Written to a temp `.wav` file on recording stop
4. The `.wav` is passed to whisper.cpp for transcription

### Waveform: SwiftUI Canvas + TimelineView

`TimelineView(.animation)` drives a `Canvas` that renders a bar-graph waveform from a circular buffer of RMS amplitude samples. Smooth 60fps animation with no UIKit dependency.

### Global Hotkeys: CGEventTap / NSEvent

`NSEvent.addGlobalMonitorForEvents(matching:)` for a sandboxed approach. If Accessibility permission is granted (needed anyway for paste), `CGEventTap` provides more reliable interception.

Default hotkey: **⌘⇧D** (Cmd+Shift+D), configurable in Settings.

### Output: Clipboard + Accessibility Paste

Two output modes (both enabled by default):
1. **Clipboard**: `NSPasteboard` — always works, no permissions beyond what we already have
2. **Accessibility paste**: `AXUIElement` — pastes directly into the frontmost text field using the macOS Accessibility API (requires Accessibility permission)

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                      macOS System                                │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │               The Great Dictator (.app)                     │ │
│  │                                                             │ │
│  │  ┌─────────────────────────────────────────────────────┐   │ │
│  │  │  UI Layer (SwiftUI + AppKit)                        │   │ │
│  │  │                                                     │   │ │
│  │  │  NSStatusItem ──► PopoverController                 │   │ │
│  │  │                        │                           │   │ │
│  │  │              RecordingPanelView                     │   │ │
│  │  │              ├── WaveformView (Canvas, 60fps)       │   │ │
│  │  │              ├── StateLabel ("Recording..." etc)    │   │ │
│  │  │              └── StopButton                        │   │ │
│  │  │                                                     │   │ │
│  │  │  SettingsWindow ──► SettingsView                   │   │ │
│  │  └──────────────────────┬──────────────────────────────┘   │ │
│  │                         │ @StateObject                      │ │
│  │  ┌──────────────────────▼──────────────────────────────┐   │ │
│  │  │  DictationViewModel (ObservableObject)              │   │ │
│  │  │  - state: RecordingState (.idle/.recording/.        │   │ │
│  │  │                           transcribing/.done)       │   │ │
│  │  │  - waveformSamples: [Float]  (circular buffer)      │   │ │
│  │  │  - lastTranscription: String                        │   │ │
│  │  │  - errorMessage: String?                            │   │ │
│  │  └──────┬──────────────────┬──────────────────┬────────┘   │ │
│  │         │                  │                  │             │ │
│  │  ┌──────▼──────┐  ┌────────▼────────┐  ┌─────▼──────────┐ │ │
│  │  │AudioRecorder│  │ WhisperBridge   │  │  HotkeyManager │ │ │
│  │  │(AVAudioEngine│  │ (C bridge to   │  │  (NSEvent /    │ │ │
│  │  │ input tap)  │  │  whisper.cpp)  │  │   CGEventTap)  │ │ │
│  │  └──────┬──────┘  └────────┬────────┘  └────────────────┘ │ │
│  │         │ PCM buffers      │ .wav file                     │ │
│  │  ┌──────▼──────┐  ┌────────▼────────┐                     │ │
│  │  │  Waveform   │  │  whisper.cpp    │                     │ │
│  │  │  ViewModel  │  │  (CoreML/Metal) │                     │ │
│  │  └─────────────┘  └────────┬────────┘                     │ │
│  │                            │ transcribed text              │ │
│  │                   ┌────────▼────────┐                     │ │
│  │                   │  OutputManager  │                     │ │
│  │                   │  - NSPasteboard │                     │ │
│  │                   │  - AXUIElement  │                     │ │
│  │                   └─────────────────┘                     │ │
│  │                                                             │ │
│  │  ┌───────────────────────────────────────────────────────┐ │ │
│  │  │  ModelManager                                         │ │ │
│  │  │  - Downloads ggml model files from Hugging Face       │ │ │
│  │  │  - Converts to CoreML format (whisper.cpp tooling)    │ │ │
│  │  │  - Caches in ~/Library/Application Support/...        │ │ │
│  │  └───────────────────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

---

## Features

### MVP (v1.0)

| Feature | Description | Acceptance Criteria |
|---|---|---|
| Global hotkey | ⌘⇧D starts/stops recording | Works in any app, even full-screen |
| Status bar icon | Shows idle/recording/transcribing state | Icon animates during recording |
| Recording panel | Popover with waveform + status | Opens on hotkey, closes after transcription |
| Waveform visualization | Real-time audio amplitude bars | 60fps, smooth, reacts to voice |
| Transcription | whisper.cpp local inference | Punctuated output in <3s for typical 30s clips |
| Clipboard output | Result copied to clipboard | Always happens after transcription |
| Accessibility paste | Pastes directly into active text field | Works in Safari, Notes, VSCode, etc. |
| First-launch setup | Model download with progress bar | User sees download progress, can cancel |
| Settings | Hotkey + output mode config | Persistent across launches via UserDefaults |
| Microphone permission | Asks for mic access on first use | Shows clear permission prompt |

### Nice-to-Have (v1.x+)

| Feature | Notes |
|---|---|
| Streaming partial results | Show text as it appears during recording |
| Pause detection → paragraphs | Insert `\n\n` after >2s silence gaps |
| Multiple model sizes | base.en (fast), small.en, large-v3-turbo (default) |
| Language selection | Any language Whisper supports |
| Transcription history | Local SQLite log of past dictations |
| Custom prompt priming | Whisper initial prompt for domain vocabulary |
| Noise gate | Discard recordings below amplitude threshold |
| Menubar shortcut display | Show current hotkey in status menu |

---

## File/Directory Structure

```
the-great-dictator/
├── TheGreatDictator.xcodeproj/          # Xcode project
├── TheGreatDictator/
│   ├── App/
│   │   ├── TheGreatDictatorApp.swift    # @main, SwiftUI App protocol, hides Dock icon
│   │   └── AppDelegate.swift            # NSApplicationDelegate for system-level setup
│   ├── UI/
│   │   ├── StatusBarController.swift    # Owns NSStatusItem, manages popover lifecycle
│   │   ├── RecordingPanelView.swift     # SwiftUI view shown in popover
│   │   ├── WaveformView.swift           # Canvas-based waveform renderer
│   │   └── SettingsView.swift           # Settings window (hotkey, model, output mode)
│   ├── ViewModels/
│   │   └── DictationViewModel.swift     # Central @ObservableObject, coordinates all services
│   ├── Services/
│   │   ├── AudioRecorder.swift          # AVAudioEngine: record, buffer tap, WAV export
│   │   ├── WhisperBridge.swift          # Swift class wrapping whisper.cpp C API
│   │   ├── HotkeyManager.swift          # Global hotkey registration + callback
│   │   ├── OutputManager.swift          # Clipboard write + AXUIElement paste
│   │   └── ModelManager.swift           # Download, cache, verify ggml model files
│   ├── Bridging/
│   │   └── WhisperBridgingHeader.h      # Imports whisper.h for Swift use
│   └── Resources/
│       ├── Assets.xcassets              # App icon, status bar icons
│       └── Info.plist                   # App metadata, entitlements refs
├── TheGreatDictatorTests/               # Unit tests
├── whisper.cpp/                         # Git submodule (github.com/ggerganov/whisper.cpp)
├── scripts/
│   └── download-model.sh               # Helper: download + convert ggml model
├── SPEC.md                              # This file
├── PLAN.md                              # Implementation plan
└── README.md                            # User-facing docs
```

---

## Key Technical Decisions

### 1. whisper.cpp C Bridge

whisper.cpp exposes a pure C API (`whisper.h`). From Swift:
1. Add `whisper.cpp/include/whisper.h` to the bridging header
2. Compile `whisper.cpp` source files as part of the Xcode build (via a custom build phase or CMake-generated static lib)
3. `WhisperBridge.swift` calls `whisper_init_from_file()`, `whisper_full()`, `whisper_full_get_segment_text()` etc.

CoreML acceleration: whisper.cpp supports CoreML via `--enable-coreml`. We pre-convert the ggml model to a CoreML `.mlmodelc` bundle and ship/cache both files side by side. At runtime, whisper.cpp automatically uses the CoreML encoder and falls back to CPU.

### 2. Audio Pipeline

```
Microphone
    │
    ▼
AVAudioInputNode (AVAudioEngine)
    │ installTap(onBus:bufferSize:format:block:)
    ▼
AVAudioPCMBuffer (Float32, 16kHz mono — whisper format)
    │
    ├──► WaveformBuffer (ring buffer of RMS values, 100 samples)
    │         └──► WaveformView renders at 60fps
    │
    └──► AudioFileWriter (appends to temp .wav)
              └──► on stop: flush → pass path to WhisperBridge
```

The input is resampled to 16kHz mono (whisper's native format) using `AVAudioConverter` before writing.

### 3. Waveform Rendering

```swift
TimelineView(.animation) { timeline in
    Canvas { ctx, size in
        // Draw bars from waveformSamples ring buffer
        // Each bar height = sample amplitude * size.height
        // Bars scroll left with each new sample
    }
}
```

No UIKit, no third-party charting libraries.

### 4. Global Hotkeys

Two-phase approach:
1. Try `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` — works in sandboxed apps, requires no extra permissions beyond normal app run
2. If we need to consume the event (prevent it reaching other apps), use `CGEventTap` with Accessibility permission (which we request anyway for paste)

### 5. Accessibility Paste

After transcription, paste into the frontmost app:
```swift
// Get frontmost app's focused element
let systemElement = AXUIElementCreateSystemWide()
var focusedElement: CFTypeRef?
AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

// Set value or simulate Cmd+V
AXUIElementSetAttributeValue(focusedElement as! AXUIElement, kAXValueAttribute as CFString, transcription as CFTypeRef)
```

Fallback: if AXValue set fails (e.g., in apps that don't support it), simulate Cmd+V after writing to clipboard.

### 6. Model Management

Models stored in `~/Library/Application Support/TheGreatDictator/Models/`.

On first launch:
1. Show a "Welcome" panel explaining model download
2. Download `ggml-large-v3-turbo.bin` (~800MB) from Hugging Face via `URLSession`
3. Optionally convert to CoreML format using bundled `coreml-generate` tool (or ship pre-converted)
4. Verify SHA256 checksum
5. Mark setup complete in UserDefaults

### 7. App Lifecycle

- `NSApp.setActivationPolicy(.accessory)` — no Dock icon, menu bar only
- App stays running in background, hotkey always active
- Popover dismisses automatically after transcription is output
- Cmd+Q in Settings or status menu quits

---

## Constraints and Non-Goals

**Constraints**:
- macOS 13.0+ (Ventura) minimum — required for modern SwiftUI APIs and `TimelineView`
- Apple Silicon recommended for real-time performance; Intel Macs supported but slower
- Accessibility permission required for paste (requested on first use)
- Microphone permission required (standard iOS/macOS permission flow)
- ~800MB disk for large-v3-turbo model; ~150MB for base.en fallback

**Non-Goals (v1.0)**:
- iOS/iPadOS support
- Windows/Linux support
- Cloud sync or accounts
- Real-time streaming transcription (post-MVP)
- Speaker diarization
- Custom wake word ("Hey Dictator")
- Background audio (music) while recording
