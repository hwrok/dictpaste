#!/bin/zsh
#
# uninstall-dictpaste.zsh — Remove dictpaste and its artifacts
#
# Removes the Hammerspoon module, model, and logs.
# Optionally uninstalls whisper-cpp, sox, and Hammerspoon (only if you don't use them for other things).
#
# Usage:
#   zsh uninstall-dictpaste.zsh
#

set -euo pipefail

hs_config_dir="$HOME/.hammerspoon"
hs_init="$hs_config_dir/init.lua"
hs_module="$hs_config_dir/dictpaste.lua"
model_path="$HOME/.whisper/ggml-large-v3-turbo.bin"
log_dir="$HOME/Library/Logs/dictpaste"

info()  { printf "\033[1;34m==>\033[0m %s\n" "$1" }
warn()  { printf "\033[1;33mWARN:\033[0m %s\n" "$1" }

# --- Hammerspoon module ---

if [[ -f "$hs_module" ]]; then
  info "Removing $hs_module..."
  rm "$hs_module"
else
  info "No dictpaste.lua found, skipping."
fi

# Remove require("dictpaste") from init.lua
if [[ -f "$hs_init" ]] && grep -qF 'require("dictpaste")' "$hs_init"; then
  info "Removing require(\"dictpaste\") from $hs_init..."
  sed -i '' '/require("dictpaste")/d' "$hs_init"

  # Clean up empty init.lua if we were the only thing in it
  if [[ ! -s "$hs_init" ]] || ! grep -q '[^[:space:]]' "$hs_init"; then
    info "init.lua is now empty, removing..."
    rm "$hs_init"
  fi
fi

# --- Model ---

if [[ -f "$model_path" ]]; then
  echo ""
  warn "Whisper model found at $model_path (~1.5GB)."
  printf "Delete it? [y/N] "
  read -r reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    rm "$model_path"
    info "Model deleted."
    # Remove ~/.whisper if empty
    rmdir "$HOME/.whisper" 2>/dev/null && info "Removed empty ~/.whisper directory." || true
  else
    info "Keeping model."
  fi
fi

# --- Logs ---

if [[ -d "$log_dir" ]]; then
  echo ""
  warn "Transcript logs found at $log_dir."
  printf "Delete them? [y/N] "
  read -r reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    rm -rf "$log_dir"
    info "Logs deleted."
  else
    info "Keeping logs."
  fi
fi

# --- Temp file ---

[[ -f /tmp/dictpaste.wav ]] && rm /tmp/dictpaste.wav

# --- Brew packages ---

echo ""
info "The following Homebrew packages were installed by dictpaste:"
echo "  - whisper-cpp"
echo "  - sox"
echo "  - hammerspoon (cask)"
echo ""
echo "  These are NOT automatically uninstalled in case you use them for other things."
echo "  To remove them manually:"
echo "    brew uninstall whisper-cpp sox"
echo "    brew uninstall --cask hammerspoon"
echo ""

info "Dictpaste uninstalled."
