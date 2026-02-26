# Installing Scoop (Windows Package Manager)

User-level package manager for Windows. No admin required. Installs to `~/scoop/`.

---

## Prerequisites

- Windows 10/11
- PowerShell 5.1+ (ships with Windows)

## Install

Open PowerShell (not as admin):

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
```

Verify:

```powershell
scoop --version
```

## Add Extras Bucket

The `extras` bucket has GUI apps and additional tools not in the default `main` bucket:

```powershell
scoop bucket add extras
```

## Useful Commands

```powershell
scoop search <name>       # Find packages
scoop install <name>      # Install
scoop update <name>       # Update one package
scoop update *            # Update all
scoop list                # Show installed
scoop uninstall <name>    # Remove
```

## How It Works

- Everything lives under `~/scoop/` — no system-wide changes
- Executables are shimmed into `~/scoop/shims/` which is added to your PATH
- Portable by design — uninstall scoop by deleting the folder
