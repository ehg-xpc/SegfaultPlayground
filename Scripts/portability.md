# Portability Notes — macOS / Linux

## Summary

This document lists which `Scripts/` files are reusable on macOS/Linux, what needs to be considered, and quick "how to run" examples.

## Portable (runs on macOS/Linux)

### Worktree helpers (pure Python)

- `Scripts/Worktree/start-worktree.py` — Portable. Run with `python3`.
- `Scripts/Worktree/end-worktree.py` — Portable. Run with `python3`.

### Agents / symlink helpers (PowerShell Core)

- `Scripts/Agents/Run-Setup.ps1`
- `Scripts/Agents/Setup-ClaudeCli.ps1`
- `Scripts/Agents/Setup-CopilotCli.ps1`
- `Scripts/Agents/Setup-OpenCodeCli.ps1`
- `Scripts/Agents/Register-Marketplace.ps1`

Notes:

- These are written for PowerShell and are expected to run under PowerShell 7+ (`pwsh`) on macOS/Linux.
- They mostly perform filesystem actions (create directories, create symlinks, read JSON). That is cross-platform.
- They contain Windows-specific fallbacks (e.g. `Start-Process ... -Verb RunAs`) which are ignored on POSIX; no harm but you can remove them for a cleaner POSIX experience.
- Path locations for VS Code are platform-detected in `Setup-CopilotCli.ps1` (APPDATA vs ~/Library vs XDG); confirm the detected path before running.
- Symlink privileges: on POSIX symlinks are normally allowed; on Windows creating file symlinks may require admin or developer mode — the PowerShell scripts include elevation fallbacks for Windows only.

## Likely portable with caveats

- `Scripts/Agents/*` installers that call external CLIs (e.g. `claude`, `copilot`) will only work if those CLIs exist on the target platform and accept the same arguments.
- `Scripts/Maintenance/*` scripts that only orchestrate PowerShell-level tasks (not Windows scheduler) may run under `pwsh`, but the repository's `SetupRepoMaintenance.ps1` registers Windows Scheduled Tasks (not portable). The maintenance worker `Invoke-RepoMaintenance.ps1` may be portable depending on what it does.

## Not portable (Windows-only)

- `Scripts/Devenv/SetupDevice.ps1` — heavy Windows-specific logic (registry edits, Appx/winget checks, Defender cmdlets, `powercfg`, Explorer restarts, Windows Scheduled Tasks). Not portable without substantial porting.
- `Scripts/Devenv/SetupDefenderExclusions.ps1` — Windows Defender cmdlets.
- `Scripts/Devenv/SetupPowerManagement.ps1` — registry and `powercfg`.
- `Scripts/Devenv/SetupKeepAlive.ps1` — Windows Task Scheduler COM API and VBS shim.
- Scripts that rely on Scoop/WinGet or Appx packages (Scoop buckets, winget packages, etc.).
- Windows batch wrappers: `*.cmd` files (`devsetup.cmd`, `start-worktree.cmd`, `end-worktree.cmd`, `setup-agents.cmd`) — not usable on macOS/Linux. Instead invoke the underlying `python3` or `pwsh` scripts directly.

## How to run these on macOS/Linux

### Python worktree

```bash
python3 Scripts/Worktree/start-worktree.py "my feature"
python3 Scripts/Worktree/end-worktree.py /path/to/worktree
```

### PowerShell agent scripts (PowerShell 7+ required)

```bash
# Ensure pwsh is installed
pwsh -v
# Run the agents setup (example)
pwsh Scripts/Agents/Run-Setup.ps1 -Cli copilot -Force
pwsh Scripts/Agents/Setup-CopilotCli.ps1 -PreferencesFile /path/to/preferences.md -Force
```

## Porting recommendations

- For cross-platform device setup, split Windows-specific actions from generic ones. Replace:
  - `winget` / `scoop` steps with conditional calls to `brew` (macOS) or `apt`/`dnf` (Linux).
  - Registry edits and Defender/scheduled-task changes with platform-appropriate equivalents or skip them on non-Windows.
- Remove Windows-only elevation fallbacks from Agent symlink scripts or guard them with `if ($IsWindows) { ... }` so POSIX runs are cleaner.
- Add CI or a small `check-platform.ps1` that prints the detected OS and whether required CLIs are present before running multi-step scripts.

## Next steps / offers

If you want, I can:

- Add these portability notes to `Scripts/README.md` instead of a separate file.
- Create a small `port-check.sh` and `port-check.ps1` that validate prerequisites on macOS/Linux and Windows respectively.
- Patch Agent scripts to remove Windows elevation fallbacks and make symlink creation explicitly cross-platform.

