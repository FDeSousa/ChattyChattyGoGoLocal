# ChattyChatty Local

A private chat client that runs its models **entirely on this device** with MLX.
No server account, no API key, no tracking. SwiftUI, iOS 26+, no third-party
SDKs beyond the MLX/Hugging Face integration.

```
Hugging Face  ->  local download  ->  ChattyChatty GoGo Local  ->  on-device chat history
```

## What it does

- **Local models** downloaded from Hugging Face and stored in the app sandbox.
- **Device-friendly presets** sized for 8 GiB-class Apple Silicon (0.6B–1.7B
  4-bit models), plus larger reference points for benchmarking.
- **Custom import**: paste any MLX-format Hugging Face repository ID.
- **Streaming chat** with markdown rendering, code highlighting, and collapsible reasoning.
- **Attachments**: images, documents (PDF/text/code), and on-device OCR via the image tool.
- **App tools** (model-invoked, user-confirmed): calculator, unit/date conversion,
  saved-chat search, single-URL reading, calendar lookup/event creation,
  reminders, contact lookup, and Apple Maps links.
- **Privacy**: Face ID lock, on-device history, no network calls except model downloads.
- **Storage management**: delete downloaded models to free space.

## Model presets

| Model | Size (download) | Approx. memory | Runs on 8 GiB? |
| --- | --- | --- | --- |
| Qwen3 0.6B 4-bit | ~0.4 GB | ~0.65 GB | Yes |
| Llama 3.2 1B Instruct 4-bit | ~0.7 GB | ~0.9 GB | Yes |
| Gemma 3 1B Instruct 4-bit | ~0.5 GB | ~0.8 GB | Yes |
| DeepSeek R1 Distill Qwen 1.5B 4-bit | ~0.95 GB | ~1.15 GB | Yes |
| LFM2 1.2B 4-bit | ~0.7 GB | ~0.9 GB | Yes |
| Qwen3 1.7B 4-bit | ~0.9 GB | ~1.35 GB | Yes |
| SmolLM3 3B 4-bit | ~1.7 GB | ~2.1 GB | Yes |
| Qwen2.5 3B Instruct 4-bit | ~1.8 GB | ~2.2 GB | Yes |
| Llama 3.2 3B Instruct 4-bit | ~1.8 GB | ~2.15 GB | Yes |
| Phi-4-mini Instruct 4-bit | ~2.1 GB | ~2.5 GB | Yes |
| Phi-4-mini Reasoning 4-bit | ~2.1 GB | ~2.5 GB | Yes |
| Qwen3 4B 4-bit | ~2.2 GB | ~2.9 GB | Yes |
| Llama 3.1 8B Instruct 4-bit | ~4.5 GB | ~5.2 GB | Reference |
| Hermes 3 Llama 3.1 8B 4-bit | ~4.7 GB | ~5.4 GB | Reference |

VLMs from the table (Qwen3-VL, Gemma-3n, LFM3-Omni, etc.) need the MLX
vision factory, and a few models (LFM3 text, Jev) have no usable MLX weights
in this runtime yet — add them via the custom import once verified.

Sizes are approximations — actual downloads can grow with the tokenizer and
duplicate weight shards.

## Requirements

- An iPhone with Apple Silicon and at least 8 GB of memory for the presets.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- Xcode 27.1 (iOS 27.1 SDK) — targets **iOS 26.0** and up.

## Getting started

```bash
brew install xcodegen
xcodegen generate
open ChattyChattyGoGoLocal.xcodeproj
```

In Xcode: select the `ChattyChattyGoGoLocal` scheme, pick your iPhone, and run.
Onboarding asks you to download a starting model; the smallest preset is
recommended first.

## Notes on the MLX integration

The app uses `mlx-swift-lm` with the `swift-huggingface` downloader and
`swift-transformers` tokenizers, wired up manually (no Swift macros) for
build reliability. One persistent session per conversation preserves the KV
cache across turns.

## License

MIT — see `LICENSE`.
