# dictpaste — Local Dictation on macOS (Whisper.cpp + Hammerspoon)

Local speech-to-text. Hotkey toggles recording (or hold-to-talk). Transcribes via Metal GPU, pastes at cursor.

## macOS (Apple Silicon)

Requires Apple Silicon. Intel Macs are not supported.

## Windows

There's a [Windows version](windows/README.md) using AutoHotkey + CUDA (CPU fallback). Caveat: not tested to the same extent as the mac version.

### dependencies (the installer handles all of these except Homebrew)

- [Homebrew](https://brew.sh) (only prereq — install it first if you haven't)
- `whisper-cpp` — local speech-to-text engine (Metal GPU on Apple Silicon)
- `sox` — mic recording
- [Hammerspoon](https://www.hammerspoon.org/) — hotkey binding + automation
- `ggml-large-v3-turbo` model (~1.5GB) — downloaded automatically

### install

The installer prompts you to pick a hotkey and recording mode (toggle or hold-to-talk).

yolo method:

```shell
/bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/hwrok/dictpaste/main/mac/install-dictpaste.zsh)"
```

if you're scared of running random scripts from the internet and would rather see it first:

```shell
curl -fsSL https://raw.githubusercontent.com/hwrok/dictpaste/main/mac/install-dictpaste.zsh -o install-dictpaste.zsh
less install-dictpaste.zsh   # satisfy your paranoia
zsh install-dictpaste.zsh
```

### usage

1. Focus any text input
2. Hit your hotkey → "● Recording"
3. Speak
4. Hit your hotkey again → "Transcribing…" → text pastes at cursor (also remains on clipboard in case you need to repaste)

### transcript log

All transcriptions are appended to `~/Library/Logs/dictpaste/dictpaste.log` with timestamps. Rolling rotation at 1MB, max 5 files. Nothing is lost even if paste lands in the wrong place and clipboard is overwritten for whatever reason.

### troubleshooting

- **No audio:** System Settings → Privacy & Security → Microphone → Hammerspoon must be enabled
- **whisper-cli not found:** `ls /opt/homebrew/bin/whisper*` — binary name varies by brew version
- **bad magic / model error:** re-download from the [huggingface repo](https://huggingface.co/ggerganov/whisper.cpp) — older cached models may be incompatible with newer whisper-cpp
- **Junk output on short clips:** whisper hallucinates on <1s audio — cleanup strips common artifacts but very short recordings may still produce noise

### whisper tuning

dictpaste ships two whisper tweaks that make sense for short dictation but wouldn't be appropriate for long-form transcription (meetings, podcasts, movies):

- **`--no-context`** disables cross-segment context, where whisper uses the previous ~30s segment to inform the next one. For long recordings this improves coherence across segment boundaries. For dictation (a few seconds to maybe a minute), there's only one segment anyway, so the feature does nothing useful. Worse, it's the mechanism behind a known decoder bug where whisper's attention gets stuck on an earlier phrase and repeats it in a loop. Disabling it eliminates that bug with zero practical downside for dictpaste's use case.

- **Sox silence trimming** strips leading and trailing silence from the audio before handing it to whisper. Whisper was trained heavily on YouTube content that ends with "Thank you" or "Thanks for watching", so it confidently hallucinates sign-off phrases when it hits trailing dead air. Removing the silence before transcription prevents this. Overhead on a short 16kHz mono clip is negligible (single-digit ms).
