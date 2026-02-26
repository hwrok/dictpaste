# dictpaste — Windows (Whisper.cpp + AutoHotkey)

Local speech-to-text. Hotkey toggles recording (or hold-to-talk). Transcribes via CUDA GPU (or CPU fallback), pastes at cursor. No cloud, no always-on mic. No admin required.

## dependencies

- [Scoop](https://scoop.sh) (only prereq — install it first if you haven't)
- `whisper-cpp` — local speech-to-text engine (CUDA GPU, falls back to CPU)
- `sox` — mic recording via WASAPI
- [AutoHotkey v2](https://www.autohotkey.com/) — hotkey binding + automation
- `ggml-large-v3-turbo` model (~1.5GB) — downloaded automatically

The installer handles all of these except Scoop.

## install

yolo method:

```powershell
irm https://raw.githubusercontent.com/hwrok/dictpaste/main/windows/install-dictpaste.ps1 | iex
```

if you'd rather read the script first:

```powershell
irm https://raw.githubusercontent.com/hwrok/dictpaste/main/windows/install-dictpaste.ps1 -OutFile install-dictpaste.ps1
Get-Content install-dictpaste.ps1   # satisfy your paranoia
powershell -ExecutionPolicy Bypass -File install-dictpaste.ps1
```

The installer prompts you to pick a hotkey and recording mode (toggle or hold-to-talk).

## usage

1. Focus any text input
2. Hit your hotkey → tooltip shows "● Recording"
3. Speak
4. Hit your hotkey again → "Transcribing..." → text pastes at cursor (also remains on clipboard)

## transcript log

All transcriptions are appended to `~/AppData/Local/dictpaste/logs/dictpaste.log` with timestamps. Rolling rotation at 1MB, max 5 files. Nothing is lost even if paste lands in the wrong place.

## troubleshooting

- **No audio:** Windows Settings → Privacy & Security → Microphone → toggle on for desktop apps
- **whisper-cli not found:** verify `scoop list` shows whisper-cpp installed and `~/scoop/shims/` is in PATH
- **CUDA errors:** ensure NVIDIA GPU drivers are installed (`nvidia-smi` should return GPU info). whisper-cpp falls back to CPU if CUDA isn't available
- **sox can't find audio device:** `sox -t waveaudio default` should pick the default mic. List devices with `sox --help-device waveaudio`
- **SmartScreen warning on first run:** click "More info" → "Run anyway". Not an admin prompt.
- **bad magic / model error:** re-download from the [huggingface repo](https://huggingface.co/ggerganov/whisper.cpp)
- **Junk output on short clips:** whisper hallucinates on <1s audio — cleanup strips common artifacts but very short recordings may still produce noise
