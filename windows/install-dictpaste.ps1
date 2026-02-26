#
# install-dictpaste.ps1 — One-shot installer for local dictation on Windows
#
# Sets up whisper.cpp + AutoHotkey for local speech-to-text.
# Hotkey records speech, transcribes via GPU (CUDA) or CPU, pastes at cursor.
# No cloud, no always-on mic. No admin required.
#
# Prerequisites:
#   - Windows 10/11
#   - Scoop package manager (https://scoop.sh)
#
# What this script does:
#   1. Installs whisper-cpp, sox, and AutoHotkey via Scoop
#   2. Downloads the whisper large-v3-turbo model (~1.5GB)
#   3. Writes ~/.dictpaste/dictpaste.ahk with your chosen hotkey and mode
#   4. Optionally creates a startup shortcut
#   5. Launches the AHK script
#
# Safe to run multiple times — idempotent. Only dictpaste.ahk is overwritten on re-run.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install-dictpaste.ps1
#
# Transcript log: ~/AppData/Local/dictpaste/logs/dictpaste.log (rolling 1MB, 5 files)
# Hotkey: Ctrl+Alt+Win+Space (default, configurable during install)
#

$ErrorActionPreference = "Stop"

$modelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
$modelDir = "$env:USERPROFILE\.whisper"
$modelPath = "$modelDir\ggml-large-v3-turbo.bin"
$ahkDir = "$env:USERPROFILE\.dictpaste"
$ahkScript = "$ahkDir\dictpaste.ahk"
$startupDir = [Environment]::GetFolderPath("Startup")

function Info($msg) {
    Write-Host "==> " -ForegroundColor Blue -NoNewline
    Write-Host $msg
}

function Warn($msg) {
    Write-Host "WARN: " -ForegroundColor Yellow -NoNewline
    Write-Host $msg
}

function Fatal($msg) {
    Write-Host "ERROR: " -ForegroundColor Red -NoNewline
    Write-Host $msg
    exit 1
}

# --- Hotkey selection ---

Write-Host ""
Info "Choose a hotkey for dictpaste:"
Write-Host ""
Write-Host "  1) Ctrl+Alt+Win+Space   (default)"
Write-Host "  2) Ctrl+Shift+Space     (simpler combo, may conflict with IME)"
Write-Host "  3) Ctrl+Alt+Space       (two modifiers)"
Write-Host "  4) Ctrl+Win+Shift+Space (avoids Alt key)"
Write-Host "  5) Custom               (enter your own AHK hotkey string)"
Write-Host ""
Write-Host "  NOTE: Custom combos may conflict with system or app shortcuts."
Write-Host "  AHK modifiers: ^ = Ctrl, ! = Alt, # = Win, + = Shift"
Write-Host ""

$choice = Read-Host "Selection [1]"
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

switch ($choice) {
    "1" {
        $ahkHotkey = "^!#Space"
        $hotkeyDisplay = "Ctrl+Alt+Win+Space"
    }
    "2" {
        $ahkHotkey = "^+Space"
        $hotkeyDisplay = "Ctrl+Shift+Space"
    }
    "3" {
        $ahkHotkey = "^!Space"
        $hotkeyDisplay = "Ctrl+Alt+Space"
    }
    "4" {
        $ahkHotkey = "^#+Space"
        $hotkeyDisplay = "Ctrl+Win+Shift+Space"
    }
    "5" {
        Write-Host ""
        $ahkHotkey = Read-Host "  AHK hotkey string (e.g. ^!#d)"
        if ([string]::IsNullOrWhiteSpace($ahkHotkey)) {
            Fatal "Hotkey string is required."
        }
        $hotkeyDisplay = $ahkHotkey
        Warn "Custom hotkey: $hotkeyDisplay — this may conflict with system or app shortcuts."
    }
    default {
        Warn "Invalid selection, using default."
        $ahkHotkey = "^!#Space"
        $hotkeyDisplay = "Ctrl+Alt+Win+Space"
    }
}

Info "Hotkey set to: $hotkeyDisplay"

# --- Recording mode selection ---

Write-Host ""
Info "Choose recording mode:"
Write-Host ""
Write-Host "  1) Toggle (default) — press hotkey to start, press again to stop"
Write-Host "  2) Hold             — hold hotkey while speaking, release to transcribe"
Write-Host ""

$modeChoice = Read-Host "Selection [1]"
if ([string]::IsNullOrWhiteSpace($modeChoice)) { $modeChoice = "1" }

switch ($modeChoice) {
    "1" {
        $recMode = "toggle"
        Info "Mode: toggle (press to start/stop)"
    }
    "2" {
        $recMode = "hold"
        Info "Mode: hold-to-talk (release to transcribe)"
    }
    default {
        Warn "Invalid selection, using toggle."
        $recMode = "toggle"
    }
}

# --- Preflight ---

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Fatal "Scoop not found. Install it first: https://scoop.sh"
}

# --- Scoop dependencies ---

Info "Installing whisper-cpp, sox, and autohotkey..."
scoop install whisper-cpp sox autohotkey

# --- Model download ---

if (-not (Test-Path $modelDir)) {
    New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
}

if (Test-Path $modelPath) {
    Info "Model already exists at $modelPath, skipping download."
} else {
    Info "Downloading whisper large-v3-turbo model (~1.5GB)..."
    Invoke-WebRequest -Uri $modelUrl -OutFile $modelPath
}

# --- Write AHK script ---

if (-not (Test-Path $ahkDir)) {
    New-Item -ItemType Directory -Path $ahkDir -Force | Out-Null
}

Info "Writing $ahkScript..."

# Static body — shared between toggle and hold modes
$ahkBody = @'
#Requires AutoHotkey v2.0

model := EnvGet("USERPROFILE") "\.whisper\ggml-large-v3-turbo.bin"
tmpFile := A_Temp "\dictpaste.wav"
logDir := EnvGet("USERPROFILE") "\AppData\Local\dictpaste\logs"
logFile := logDir "\dictpaste.log"
logMaxBytes := 1048576  ; 1MB
logMaxFiles := 5
recording := false
recPID := 0

StartRecording() {
    global recording, recPID, tmpFile
    recording := true

    ; sox recording via WASAPI
    Run('sox -q -r 16000 -c 1 -b 16 -t waveaudio default "' tmpFile '"',, "Hide", &recPID)
    ToolTip("● Recording")
}

StopRecording() {
    global recording, recPID, tmpFile, model
    recording := false

    ; Stop sox
    if recPID {
        ProcessClose(recPID)
        recPID := 0
    }

    ToolTip("Transcribing...")

    ; Run whisper-cli synchronously, capture output
    shell := ComObject("WScript.Shell")
    cmd := 'whisper-cli -m "' model '" --no-timestamps -f "' tmpFile '"'
    exec := shell.Exec(A_ComSpec ' /c ' cmd)
    stdout := exec.StdOut.ReadAll()

    text := CleanTranscript(stdout)

    if (StrLen(text) > 0) {
        AppendLog(text)
        A_Clipboard := text
        Send("^v")
    }

    ToolTip()  ; clear tooltip
}

CleanTranscript(text) {
    text := RegExReplace(text, "\[\d{2}:\d{2}:\d{2}\.\d+\s*-->\s*\d{2}:\d{2}:\d{2}\.\d+\]", "")
    text := Trim(text)
    text := RegExReplace(text, "\s+", " ")
    text := RegExReplace(text, "^\[.*\]$", "")
    text := RegExReplace(text, "\(.*\)$", "")
    return text
}

AppendLog(text) {
    global logDir, logFile, logMaxBytes, logMaxFiles
    DirCreate(logDir)
    RotateLog()

    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    FileAppend(timestamp "`t" text "`n", logFile)
}

RotateLog() {
    global logFile, logDir, logMaxBytes, logMaxFiles

    if !FileExist(logFile) {
        return
    }

    info := FileGetSize(logFile)
    if (info < logMaxBytes) {
        return
    }

    loop logMaxFiles - 1 {
        i := logMaxFiles - A_Index
        src := logDir "\dictpaste." i ".log"
        dst := logDir "\dictpaste." (i + 1) ".log"
        if FileExist(src) {
            FileMove(src, dst, true)
        }
    }
    FileMove(logFile, logDir "\dictpaste.1.log", true)
}
'@

# Hotkey binding — varies by mode
if ($recMode -eq "hold") {
    $ahkBinding = @"

Hotkey "$ahkHotkey", (*) => StartRecording()
Hotkey "$ahkHotkey up", (*) => StopRecording()
"@
} else {
    $ahkBinding = @"

$ahkHotkey:: {
    global recording
    if recording {
        StopRecording()
    } else {
        StartRecording()
    }
}
"@
}

Set-Content -Path $ahkScript -Value ($ahkBody + $ahkBinding) -Encoding UTF8

# --- Startup shortcut (optional) ---

Write-Host ""
$startupChoice = Read-Host "Create startup shortcut so dictpaste runs on login? [y/N]"
if ($startupChoice -match "^[Yy]$") {
    $shortcutPath = "$startupDir\dictpaste.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $ahkScript
    $shortcut.WorkingDirectory = $ahkDir
    $shortcut.Save()
    Info "Startup shortcut created at $shortcutPath"
} else {
    Info "Skipping startup shortcut. You can always add one later via Win+R → shell:startup"
}

# --- Launch ---

Info "Launching dictpaste..."
Start-Process $ahkScript

Write-Host ""
Info "Installation complete!"
Write-Host ""
if ($recMode -eq "hold") {
    Write-Host "  Hotkey: $hotkeyDisplay (hold to talk, release to transcribe)"
} else {
    Write-Host "  Hotkey: $hotkeyDisplay (press to start/stop)"
}
Write-Host "  Script: $ahkScript"
Write-Host "  Log:    ~/AppData/Local/dictpaste/logs/dictpaste.log"
Write-Host ""
