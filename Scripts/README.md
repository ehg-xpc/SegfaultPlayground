# Scripts: Call Trees and Usage

This file documents the call graph for every script in the `Scripts/` folder. It includes a concise description for each script and an ASCII visual call graph so you can quickly see what runs what.

## Overview

- `devsetup.cmd` -> `Scripts/Devenv/SetupDevice.ps1` (main orchestrator)
- `start-worktree.cmd` -> `Scripts/Worktree/start-worktree.py`
- `end-worktree.cmd` -> `Scripts/Worktree/end-worktree.py`
- `setup-agents.cmd` -> `Scripts/Agents/Run-Setup.ps1`

Note: `*.cmd` wrappers are Windows-only. See portability notes in Scripts/portability.md.

## Tools glossary

- Clink: Bash-style command line editing for cmd.exe
- Scoop: Windows command-line installer (alternative to winget)
- Winget: Windows package manager
- Beyond Compare: Diff/merge tool used for git and other comparisons
- Windows Terminal: Terminal app for Windows with profile support

---

## Top-level ASCII call graph

Scripts/
├─ devsetup.cmd -> Scripts/Devenv/SetupDevice.ps1 (Windows Only)
│   └─ (internal functions + Invoke-DevenvSubScript)
│       ├─ Devenv/SetupDefenderExclusions.ps1        : Configure Defender exclusions
│       ├─ Devenv/SetupPowerManagement.ps1           : Power / hibernate / timeouts (optional)
│       ├─ Devenv/SetupKeepAlive.ps1                 : Register KeepAlive scheduled task (uses KeepAlive.vbs)
│       ├─ Devenv/ResetScoopBuckets.ps1              : Fix Scoop bucket merge conflicts
│       ├─ Devenv/scoop-packages.txt                 : Scoop package list (input)
│       ├─ Devenv/winget-packages.txt                : Winget package list (input)
│       ├─ Devenv/SetupWindowsTerminal.ps1            : Deploy / pull Windows Terminal settings
│       │   └─ Devenv/UserEnv.ps1                      : Terminal profile helper (calls SetupPrompt, ShowBanner, ManageRepository)
│       ├─ Devenv/SetupBeyondCompare.ps1              : Beyond Compare integration
│       ├─ Devenv/SetupClink.ps1                      : Clink/prompt integration
│       ├─ Agents/Run-Setup.ps1                       : Wire CLI preferences (see below)
│       │   ├─ Agents/Setup-ClaudeCli.ps1              : Install/link Claude preferences
│       │   ├─ Agents/Setup-CopilotCli.ps1             : Install/link Copilot preferences and VS Code prompt link
│       │   └─ Agents/Setup-OpenCodeCli.ps1            : Install/link OpenCode preferences
│       ├─ Agents/Register-Marketplace.ps1            : Register AI marketplace and auto-install plugins
│       │   └─ auto-install-plugins.txt               : plugin list input
│       ├─ Maintenance/SetupRepoMaintenance.ps1       : Register daily RepoMaintenance scheduled task
│       │   └─ Maintenance/Invoke-RepoMaintenance.ps1 : Called by the scheduled task
│       ├─ Devenv/SetupBuildThrottling.ps1           : Set build throttling env vars
│       └─ (many helper functions and probes inside SetupDevice.ps1)
├─ start-worktree.cmd-> Scripts/Worktree/start-worktree.py
│   └─ Worktree/start-worktree.py                    : create git worktree, branch user/<alias>/<slug>
├─ setup-agents.cmd -> Scripts/Agents/Run-Setup.ps1
│   └─ Agents/Run-Setup.ps1                           : wire CLI preferences (calls per-CLI helpers)
└─ end-worktree.cmd  -> Scripts/Worktree/end-worktree.py
    └─ Worktree/end-worktree.py                      : remove git worktree and optional branch delete

---

## Per-script quick reference

- `Scripts/Devenv/SetupDevice.ps1`— Main device setup. Validates admin/PowerShell, installs Scoop/winget, installs packages, configures PATH, sets environment variables, and runs a set of idempotent sub-scripts. Uses `Invoke-SubScript` to funnel sub-script output into a log file.

- `Scripts/Devenv/SetupDefenderExclusions.ps1`— Adds Defender path/process exclusions for repos, scoop, node, git, msbuild, etc.

- `Scripts/Devenv/SetupPowerManagement.ps1`—Disables hibernate/Modern Standby and sets AC power timeouts. Intended for remote/dev nodes (run via `-RemoteNode`).

- `Scripts/Devenv/SetupKeepAlive.ps1`& `KeepAlive.vbs` —Registers a scheduled task to simulate activity and prevent idle disconnects; uses a VBS shim to hide the window.

- `Scripts/Devenv/ResetScoopBuckets.ps1`— Repairs Scoop bucket state when merge conflicts occur during `scoop install` operations.

- `Scripts/Devenv/scoop-packages.txt`— List of packages to install via Scoop.

- `Scripts/Devenv/winget-packages.txt`— List of packages to install via winget.

- `Scripts/Devenv/SetupWindowsTerminal.ps1` —Deploys generated Windows Terminal profiles and settings based on `RepositoryConfig.json`. Invokes `UserEnv.ps1` for profile commandlines.

- `Scripts/Devenv/UserEnv.ps1` — Session helper invoked by terminal profiles; sets PATH, aliases (e.g. `devsetup`), and loads prompt/banner scripts.

- `Scripts/Agents/Run-Setup.ps1` — Entrypoint used by `setup-agents.cmd`. For each CLI it finds under `%DEV_REPO%/Config/<cli>/preferences.md`, it calls the corresponding per-CLI setup script.

- `Scripts/Agents/Register-Marketplace.ps1` — Registers the local `AI/` marketplace with supported CLIs and optionally auto-installs plugins from `auto-install-plugins.txt`.

- `Scripts/Maintenance/SetupRepoMaintenance.ps1` — Registers a scheduled task that runs repo maintenance daily via `Invoke-RepoMaintenance.ps1`.

- `Scripts/Worktree/start-worktree.py` — Convenience tool to create feature worktrees in a centralized `.worktrees` location; generates slug, creates branch from `origin/main`, and runs `git worktree add -b`.

- `Scripts/Worktree/end-worktree.py` — Convenience tool to remove a worktree and optionally delete the branch. Validates the path is a worktree before removing.