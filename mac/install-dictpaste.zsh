#!/bin/zsh
#
# install-dictpaste.zsh — One-shot installer for local dictation on macOS
#
# Sets up whisper.cpp + Hammerspoon for local speech-to-text.
# Hotkey records speech, transcribes via Metal GPU, pastes at cursor.
# No cloud, no always-on mic.
#
# Prerequisites:
#   - macOS with Homebrew installed
#   - Apple Silicon (Intel Macs are not supported)
#
# What this script does:
#   1. Installs whisper-cpp and sox via Homebrew
#   2. Installs Hammerspoon (if not already present)
#   3. Downloads the whisper large-v3-turbo model (~1.5GB)
#   4. Writes ~/.hammerspoon/dictpaste.lua (won't clobber existing Hammerspoon config)
#   5. Adds require("dictpaste") to ~/.hammerspoon/init.lua if not already present
#   6. Launches Hammerspoon (you'll need to grant Accessibility + Microphone permissions)
#
# Safe to run multiple times — idempotent. Only dictpaste.lua is overwritten on re-run.
#
# Usage:
#   zsh install-dictpaste.zsh
#
# Transcript log: ~/Library/Logs/dictpaste/dictpaste.log (rolling 1MB, 5 files)
# Hotkey: Cmd+Ctrl+Opt+Space (default, configurable during install)
#

set -euo pipefail

# Reattach stdin to terminal so interactive prompts work when piped from curl
exec < /dev/tty

brew_prefix="/opt/homebrew"

# --- Model config (update these when switching models) ---
model_name="ggml-large-v3-turbo.bin"
model_sha256="1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
model_dir="$HOME/.whisper"
model_path="$model_dir/$model_name"
model_url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$model_name"

hs_config_dir="$HOME/.hammerspoon"
hs_init="$hs_config_dir/init.lua"
hs_module="$hs_config_dir/dictpaste.lua"
require_line='require("dictpaste")'

info()  { printf "\033[1;34m==>\033[0m %s\n" "$1" }
warn()  { printf "\033[1;33mWARN:\033[0m %s\n" "$1" }
error() { printf "\033[1;31mERROR:\033[0m %s\n" "$1"; exit 1 }

# --- Hotkey selection ---

pick_hotkey() {
  echo ""
  info "Choose a hotkey for dictpaste:"
  echo ""
  echo "  1) Cmd+Ctrl+Opt+Space   (default — left-hand modifiers + thumb)"
  echo "  2) Cmd+Shift+Space      (simpler combo, but may conflict with Spotlight/Alfred)"
  echo "  3) Ctrl+Opt+Space       (two modifiers — less likely to conflict)"
  echo "  4) Cmd+Ctrl+Shift+Space (avoids Opt key for non-US keyboard layouts)"
  echo "  5) Custom               (enter your own)"
  echo ""
  echo "  NOTE: Custom combos may conflict with system or app shortcuts."
  echo "  Modifiers: cmd, ctrl, alt/opt, shift. Key: any single key (space, r, d, etc.)"
  echo ""
  printf "Selection [1]: "
  read -r choice
  choice=${choice:-1}

  case $choice in
    1)
      hs_mods='{"cmd", "ctrl", "alt"}'
      hs_key="space"
      hotkey_display="Cmd+Ctrl+Opt+Space"
      ;;
    2)
      hs_mods='{"cmd", "shift"}'
      hs_key="space"
      hotkey_display="Cmd+Shift+Space"
      ;;
    3)
      hs_mods='{"ctrl", "alt"}'
      hs_key="space"
      hotkey_display="Ctrl+Opt+Space"
      ;;
    4)
      hs_mods='{"cmd", "ctrl", "shift"}'
      hs_key="space"
      hotkey_display="Cmd+Ctrl+Shift+Space"
      ;;
    5)
      echo ""
      echo "  Enter modifiers as comma-separated list (cmd, ctrl, alt, shift)."
      printf "  Modifiers: "
      read -r custom_mods
      printf "  Key: "
      read -r custom_key

      if [[ -z "$custom_mods" || -z "$custom_key" ]]; then
        error "Modifiers and key are both required."
      fi

      # Format into lua table: "cmd, ctrl, alt" -> {"cmd", "ctrl", "alt"}
      hs_mods="{$(echo "$custom_mods" | sed 's/[[:space:]]*,[[:space:]]*/", "/g' | sed 's/^/"/;s/$/"/')}"
      hs_key="$custom_key"
      hotkey_display="$(echo "$custom_mods" | sed 's/alt/Opt/g;s/cmd/Cmd/g;s/ctrl/Ctrl/g;s/shift/Shift/g' | sed 's/,[[:space:]]*/+/g')+$(echo "$custom_key" | sed 's/.*/\u&/')"

      warn "Custom hotkey: $hotkey_display — this may conflict with system or app shortcuts."
      ;;
    *)
      warn "Invalid selection, using default."
      hs_mods='{"cmd", "ctrl", "alt"}'
      hs_key="space"
      hotkey_display="Cmd+Ctrl+Opt+Space"
      ;;
  esac

  info "Hotkey set to: $hotkey_display"
}

pick_hotkey

# --- Recording mode selection ---

pick_mode() {
  echo ""
  info "Choose recording mode:"
  echo ""
  echo "  1) Toggle (default) — press hotkey to start, press again to stop"
  echo "  2) Hold             — hold hotkey while speaking, release to transcribe"
  echo ""
  printf "Selection [1]: "
  read -r mode_choice
  mode_choice=${mode_choice:-1}

  case $mode_choice in
    1)
      rec_mode="toggle"
      info "Mode: toggle (press to start/stop)"
      ;;
    2)
      rec_mode="hold"
      info "Mode: hold-to-talk (release to transcribe)"
      ;;
    *)
      warn "Invalid selection, using toggle."
      rec_mode="toggle"
      ;;
  esac
}

pick_mode

# --- Preflight ---

if [[ "$(uname -m)" != "arm64" ]]; then
  error "dictpaste requires Apple Silicon. Intel Macs are not supported."
fi

if ! command -v brew &>/dev/null; then
  error "Homebrew not found. Install it first: https://brew.sh"
fi

# --- Brew dependencies ---

info "Installing whisper-cpp and sox..."
brew install whisper-cpp sox

if ! brew list --cask hammerspoon &>/dev/null; then
  info "Installing Hammerspoon..."
  brew install --cask hammerspoon
else
  info "Hammerspoon already installed, skipping."
fi

# --- Model download ---

mkdir -p "$model_dir"

if [[ -f "$model_path" ]]; then
  info "Verifying existing model checksum..."
  actual=$(shasum -a 256 "$model_path" | awk '{print $1}')
  if [[ "$actual" != "$model_sha256" ]]; then
    warn "Existing model failed checksum. Re-downloading..."
    rm "$model_path"
  else
    info "Model already exists and verified, skipping download."
  fi
fi

if [[ ! -f "$model_path" ]]; then
  info "Downloading whisper large-v3-turbo model (~1.5GB)..."
  curl -L --progress-bar -o "$model_path.tmp" "$model_url"
  info "Verifying download checksum..."
  actual=$(shasum -a 256 "$model_path.tmp" | awk '{print $1}')
  if [[ "$actual" != "$model_sha256" ]]; then
    rm -f "$model_path.tmp"
    error "Downloaded model failed checksum — corrupted or incomplete download. Try again."
  fi
  mv "$model_path.tmp" "$model_path"
fi

# --- Hammerspoon config ---

mkdir -p "$hs_config_dir"

# Write dictpaste.lua (always overwrite — this file is ours)
info "Writing $hs_module..."

cat > "$hs_module" << LUA_HEAD
local recording = false
local recTask = nil
local tmpfile = "/tmp/dictpaste.wav"
local model = os.getenv("HOME") .. "/.whisper/$model_name"
local whisperBin = "$brew_prefix/bin/whisper-cli"
local recBin = "$brew_prefix/bin/rec"
LUA_HEAD

cat >> "$hs_module" << 'LUA'

local logDir = os.getenv("HOME") .. "/Library/Logs/dictpaste"
local logFile = logDir .. "/dictpaste.log"
local logMaxBytes = 1 * 1024 * 1024  -- 1MB
local logMaxFiles = 5

local function rotateLog()
  local attr = hs.fs.attributes(logFile)
  if not attr or attr.size < logMaxBytes then return end
  for i = logMaxFiles - 1, 1, -1 do
    local src = logDir .. "/dictpaste." .. i .. ".log"
    local dst = logDir .. "/dictpaste." .. (i + 1) .. ".log"
    os.rename(src, dst)
  end
  os.rename(logFile, logDir .. "/dictpaste.1.log")
end

local function appendLog(text)
  hs.fs.mkdir(logDir)
  rotateLog()
  local f = io.open(logFile, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S") .. "\t" .. text .. "\n")
    f:close()
  end
end

local function cleanTranscript(text)
  if not text then return "" end
  text = text:gsub("%[%d%d:%d%d:%d%d%.%d+%s*%-%->%s*%d%d:%d%d:%d%d%.%d+%]", "")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  text = text:gsub("%s+", " ")
  text = text:gsub("^%[.*%]$", "")
  text = text:gsub("%(.*%)$", "")
  return text
end

local function showRecordingAlert()
  local msg = hs.styledtext.new("● Recording", {
    font = { name = ".AppleSystemUIFont", size = 27 },
    color = { white = 1 },
  })
  msg = msg:setStyle({ color = { red = 1, green = 0, blue = 0 } }, 1, 1)
  hs.alert.show(msg, 9999)
end

local function stopRecording()
  recording = false
  if recTask then recTask:terminate() end
  hs.alert.closeAll()
  hs.alert.show("⏳ Transcribing…", 9999)

  hs.task.new(whisperBin,
    function(_, stdout, _)
      local text = cleanTranscript(stdout)
      if #text > 0 then
        appendLog(text)
        hs.pasteboard.setContents(text)
        hs.eventtap.keyStroke({"cmd"}, "v")
      end
      hs.alert.closeAll()
    end,
    {"-m", model, "--no-timestamps", "-f", tmpfile}
  ):start()
end

local function startRecording()
  recording = true
  recTask = hs.task.new(recBin, nil,
    {"-q", "-r", "16000", "-c", "1", "-b", "16", tmpfile})
  recTask:start()
  showRecordingAlert()
end

LUA

# Append the hotkey binding (needs shell variable expansion)
if [[ "$rec_mode" == "hold" ]]; then
  cat >> "$hs_module" << LUA
hs.hotkey.bind($hs_mods, "$hs_key", startRecording, stopRecording)
LUA
else
  cat >> "$hs_module" << LUA
hs.hotkey.bind($hs_mods, "$hs_key", function()
  if recording then
    stopRecording()
  else
    startRecording()
  end
end)
LUA
fi

# Add require("dictpaste") to init.lua if not already present
if [[ ! -f "$hs_init" ]]; then
  info "Creating $hs_init with dictpaste require..."
  echo "$require_line" > "$hs_init"
elif ! grep -qF "$require_line" "$hs_init"; then
  info "Adding dictpaste require to existing $hs_init..."
  echo "" >> "$hs_init"
  echo "$require_line" >> "$hs_init"
else
  info "init.lua already requires dictpaste, skipping."
fi

# --- Launch Hammerspoon ---

info "Launching Hammerspoon..."
open -a Hammerspoon

echo ""
info "Installation complete!"
echo ""
if [[ "$rec_mode" == "hold" ]]; then
  echo "  Hotkey: $hotkey_display (hold to talk, release to transcribe)"
else
  echo "  Hotkey: $hotkey_display (press to start/stop)"
fi
echo "  Log:    ~/Library/Logs/dictpaste/dictpaste.log"
echo ""
echo "  IMPORTANT: Grant Hammerspoon these permissions in System Settings:"
echo ""
echo "  - Hammerspoon will likely prompt for accessibility permissions on first run; grant:"
echo ""
echo "      → Privacy & Security → Accessibility → Hammerspoon ✓"
echo "      → You may need to restart Hammerspoon after granting this..."
echo "          → (menu bar item → quit; cmd+space, search hammerspoon, open it)"
echo ""
echo "  - However, it will not immediate prompt for Microphone, but it will" 
echo "    likely prompt during first use of the hotkey -> transcription process:"
echo ""
echo "        → Privacy & Security → Microphone → Hammerspoon ✓"
echo "        → Then, you will need to restart Hammerspoon as above"
echo ""
echo "  - Then, click the Hammerspoon menu bar icon → Reload Config."
echo ""
