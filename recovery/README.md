# Recovery Scripts

One-click restore scripts for OpenCode Desktop v1.17.20 (patched). Use if your OpenCode installation is broken or needs re-patching.

## Quick Start

1. **Download** the installer and patch bundle from [Release v1.17.20-patched-recovery](https://github.com/Mr-cjf/opencode-patches/releases/tag/v1.17.20-patched-recovery)
   - `opencode-desktop-win-x64-1.17.20.exe` (128 MB) — OpenCode installer
   - `app.asar.patched.zip` (38 MB) — pre-patched asar bundle
2. Run `restore.bat` (double-click) and follow the prompts.

> **Note**: Large binaries are hosted on GitHub Releases, not in this directory. The scripts here automate downloading them via `gh` CLI (preferred) or direct browser download.

## Files

| File | Description |
|------|-------------|
| `restore.bat` | One-click launcher (double-click to run) |
| `restore-opencode.ps1` | PowerShell automation script (auto-downloads assets via `gh` or browser) |
| `fix-db-time-fields.py` | SQL migration to fix `time` field after downgrade from v1.18.x |
| `checksums.txt` | SHA-256 checksums for integrity verification |