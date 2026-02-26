# Murmur

Quiet, local, instant — dictation for macOS.

<!-- demo gif -->

![macOS](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)
![WhisperKit](https://img.shields.io/badge/WhisperKit-on--device-5B5EE8)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

---

## What It Does

Press a hotkey. Speak. Text appears — already pasted into whatever you were typing in. That's it. No app switching, no clicking, no window to manage.

## Why Local

Existing dictation tools either require an internet connection, lock you into a subscription, or feel heavy. Murmur wraps [WhisperKit](https://github.com/argmaxinc/WhisperKit) — which runs Whisper on the Apple Neural Engine with genuine on-device accuracy — in a menu bar interface with a global hotkey and nothing else in your way. No Dock icon. Your audio never leaves your Mac.

## Features

- **On-device transcription** — WhisperKit + Apple Neural Engine. No cloud, no subscription, works offline.
- **Global hotkey** — `⌘⇧D` works from any app. No Accessibility permission required.
- **Floating pill HUD** — unobtrusive recording/transcribing indicator above all windows.
- **Auto-paste** — transcribed text is copied and pasted into the frontmost field automatically.
- **Multiple Whisper models** — from `base.en` (fast, small) to `large-v3-turbo` (highest accuracy).
- **AI cleanup** (optional) — Claude post-processes filler words, punctuation, and grammar. Cost tracked per entry.
- **Transcription history** — saved locally with timestamps, token counts, and cost estimates.
- **Configurable** — hotkeys, model, output behavior, custom prompts, storage location.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Install

```bash
git clone https://github.com/titho/murmur
cd murmur
./run.sh
```

WhisperKit and all dependencies are fetched via Swift Package Manager on first build. The app will prompt you to download a Whisper model on first launch.

## Usage

1. Launch — Murmur appears in the menu bar only (no Dock icon)
2. Press **`⌘⇧D`** to start recording
3. Speak
4. Press **`⌘⇧D`** again (or wait for the timeout) — text is pasted automatically

## Configuration

Open Settings from the menu bar icon (or right-click → Settings...):

| Tab        | What's there                                              |
| ---------- | --------------------------------------------------------- |
| General    | Output mode, Whisper model, AI cleanup, recording timeout |
| Keybinding | Remap toggle and cancel hotkeys                           |
| History    | Past transcriptions, token counts, cost, storage location |

## AI Cleanup (Optional)

Enable in Settings → General. Requires an [Anthropic API key](https://console.anthropic.com/). Murmur sends only the transcribed text (never audio) to Anthropic's API. Token counts and estimated cost are tracked per entry in History.

The `ANTHROPIC_API_KEY` environment variable is also respected as a fallback.

## Privacy

Transcription runs entirely on your Mac using the Apple Neural Engine. Your audio is never uploaded anywhere.

If AI cleanup is enabled, the transcribed text (not the audio) is sent to Anthropic's API. You can inspect exactly what is sent — it is the plain text transcript, nothing else.

No telemetry. No analytics. No crash reporting. The app has no network access except the optional Anthropic API call and the one-time model download.

## Stack

WhisperKit · Swift / SwiftUI · Carbon API (global hotkey) · Anthropic Claude (optional)

## License

MIT
