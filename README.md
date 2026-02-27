# Murmur

Quiet, local, instant — dictation for macOS.

<!-- demo gif -->

![macOS](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)
![WhisperKit](https://img.shields.io/badge/WhisperKit-on--device-5B5EE8)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

---

Press a hotkey. Speak. Text appears — already pasted into whatever you were typing in. No app switching, no clicking, no window to manage. Your audio never leaves your Mac.

Murmur runs [WhisperKit](https://github.com/argmaxinc/WhisperKit) on the Apple Neural Engine — on-device accuracy with no cloud dependency, no subscription, and no Dock icon in your way.

## Features

- **On-device transcription** — WhisperKit + Apple Neural Engine. Works offline.
- **Global hotkey** — `⌘⇧D` from any app, no Accessibility permission required for the hotkey itself.
- **Auto-paste** — transcribed text lands at your cursor automatically.
- **Floating HUD** — unobtrusive pill indicator while recording and transcribing.
- **AI cleanup** (optional) — Claude post-processes filler words, punctuation, and grammar.
- **History** — every transcription saved locally with timestamps, token counts, and cost estimates.
- **Configurable** — hotkeys, Whisper model, output behavior, custom prompts.

## Install

Requires macOS 14+, Xcode 16+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
git clone https://github.com/titho/murmur
cd murmur
./run.sh
```

Swift Package Manager fetches WhisperKit automatically. On first launch, Murmur will prompt you to download a Whisper model.

Grant **Accessibility** permission when prompted (System Settings → Privacy & Security → Accessibility) — required for auto-paste.

## Usage

| Action | How |
|--------|-----|
| Start / stop recording | `⌘⇧D` |
| Cancel recording | configurable cancel hotkey |
| Transcribe an audio file | Right-click menu bar icon → Transcribe file… |
| Open settings | Right-click → Settings… |

**Settings tabs**

| Tab | What's there |
|-----|-------------|
| General | Output mode, Whisper model, recording timeout, AI cleanup |
| Keybinding | Remap toggle and cancel hotkeys |
| History | Past transcriptions, cleanup results, token counts, cost |

**AI Cleanup** — enable in Settings → General. Requires an [Anthropic API key](https://console.anthropic.com/). Only the transcribed text is ever sent to Anthropic — never audio. Token counts and cost are tracked per entry in History.

## Choosing a model

**Start with Base.** For everyday English dictation it feels near-instant (short clips transcribe in under a second) and produces the same output as the larger models on clear speech.

| Model | Size | When to use |
|-------|------|-------------|
| **Base** *(recommended)* | 142 MB | Everyday English dictation. Fast, accurate, the right default. |
| Tiny | 75 MB | Fastest possible. Use only when even Base feels slow. |
| Small | 466 MB | Marginally better than Base on difficult audio. English only. |
| Medium | 1.5 GB | Heavily accented or noisy English where Base misses words. |
| **Large v3 Turbo** | 1.6 GB | Non-English languages, mixed-language speech, or technical vocabulary that smaller models mangle. Noticeably slower on short clips due to Whisper's architecture (the encoder always processes a 30-second window regardless of clip length). |
| Large v3 | 3.1 GB | Maximum accuracy. Only practical on M2 Pro/Max or newer. |

The short version: if you dictate in English and your audio is clear, Base will be faster *and* produce the same result. Move up only when you notice specific words being missed.

## License

MIT
