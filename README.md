# Developer Environment Template

A starter scaffold for a personal Windows developer environment. Provides
Windows Terminal profile generation, repository management scripts, agent
setup (Claude Code, GitHub Copilot CLI, OpenCode), and device-bootstrap
automation.

One command bootstraps a new device: installs tools via Scoop and winget, generates Windows Terminal profiles per repository, wires AI coding agents to your preferences, and registers automated daily maintenance — so every machine starts consistent.

## Prerequisites

- Windows 10 or 11
- PowerShell 7+ — `devsetup.cmd` will attempt to install it automatically via winget if it is not already present
- Git
- Claude CLI, Github Copilot CLI, or OpenCode (optional, for AI agent setup)

## Getting Started

1. **Clone** this repo (or fork it) into your repos directory.
2. **Edit `Scripts/Devenv/config.json`** — set your name and email.
3. **Edit `Scripts/Devenv/RepositoryConfig.json`** — add entries for each
   repository you work in. The two included entries (`Developer` and
   `Workbench`) are examples; add, remove, or rename as needed.
4. **Run `devsetup.cmd`** — bootstraps the device: installs tooling, generates
   Windows Terminal profiles, registers Git aliases, and sets up the agent
   context pipeline.

## Install OpenCode CLI

For the latest check the official [OpenCode CLI page](https://opencode.ai/).

On Windows:

```bash
curl -fsSL https://opencode.ai/install | bash
```

On MacOS:

```bash
brew install anomalyco/tap/opencode
```

## Install GitHub Copilot CLI

For the latest check the official [GitHub Copilot CLI page](https://github.com/features/copilot/cli).

On Windows, install via winget:

```bash
winget install GitHub.Copilot
```

On MacOS

```bash
brew install copilot-cli
```

---

## Features

- **One-command bootstrap** — `devsetup.cmd` elevates, installs Scoop and winget packages, and runs all configuration scripts **idempotently**.

- **AI agent wiring** — `setup-agents.cmd` symlinks your preference files in `Config/` to the expected locations for Claude Code, GitHub Copilot CLI, and OpenCode so every session inherits your coding style.

> Note: A "symlink" (symbolic link) is a filesystem shortcut that points
   to another file or directory. Accessing the symlink acts like accessing
   the target; if the target is removed or moved the symlink becomes
   dangling (it points to a non-existent target).

- **Windows Terminal profiles** — `SetupWindowsTerminal.ps1` reads `RepositoryConfig.json` and generates one profile per repository, complete with custom icons, tab titles, and starting directories.

- **Per-session repository context** — `UserEnv.ps1` clones missing repos on demand, sets the working directory, loads posh-git and oh-my-posh, and adds repo-specific scripts to `PATH`.

- **Local Claude plugin marketplace** — `AI/plugins/` hosts installable Claude Code plugins; listed plugins are installed user-wide automatically during device setup.

- **Git worktree utilities** — `start-worktree` and `end-worktree` create and tear down feature branches in a standard off-repo worktree layout with automatic branch naming.

- **Automated maintenance** — `Invoke-RepoMaintenance.ps1` runs as a scheduled task, syncing every configured repo and calling per-repo maintenance scripts.

- **Remote node support** — optional KeepAlive task prevents RDP idle disconnection and Azure Dev Box auto-hibernate on headless dev nodes.

- **Hyper-V toolkit** — PowerShell module for spinning up, snapshotting, and running MSI test passes in guest VMs.

---

## Pulling Template Updates (for Forks)

If you forked this repo rather than using it directly, you can pull updates
from the template:

```
git remote add template <template-repo-url>
git fetch template
git merge template/main
```

Files that intentionally diverge in your fork (config, repo list, metadata,
README) are marked `merge=ours` in `.gitattributes` so they survive merges
automatically. Register the merge driver once per clone:

```
git config merge.ours.driver true
```

`Scripts/Devenv/SetupDevice.ps1` registers both the remote and the merge
driver as part of device setup, so a normal bootstrap needs neither step
run by hand.

---

## Configuration

### Repository config (`RepositoryConfig.json`)

Each entry under `repositories` produces one Windows Terminal profile and one environment target for `UserEnv.ps1`:

| Field | Description |
| --- | --- |
| `url` | Git remote URL — omit or set to `null` for local-only directories |
| `folderName` | Folder name under `%Repos%` |
| `tabTitle` | Label shown in the Windows Terminal tab |
| `icon` | Path to a `.ico` file (supports `%DEV_REPO%` expansion) |
| `startingDirectory` | Optional override for the shell's initial directory |
| `commandline` | Optional full command line; defaults to launching `UserEnv.ps1 -RepositoryName <name>` |
| `generateProfile` | Set to `false` to suppress Terminal profile generation for an entry |
| `skipCommonSync` | Set to `true` on a repo to skip the daily stash/checkout/pull |

Repositories are cloned automatically the first time a profile is opened if they do not yet exist locally.

### User identity (`config.json`)

Stores the name and email written to `.gitconfig` during device setup.

## AI Agent Setup

Preference files live under `Config/<cli>/preferences.md`. Run `setup-agents.cmd` (or `Scripts/Agents/Run-Setup.ps1`) to symlink each file to the location the CLI reads at startup:

| CLI | Link target |
| --- | --- |
| Claude Code | `~/.claude/CLAUDE.md` |
| GitHub Copilot CLI | `~/.copilot/copilot-instructions.md` and the VS Code user-level `personal.instructions.md` |
| OpenCode | OpenCode's global instructions file |

```cmd
setup-agents.cmd
```

Pass `-Cli claude` (or `copilot`, `opencode`) to wire a single tool. CLIs whose `preferences.md` does not exist are silently skipped.

### Local Claude plugins (`AI/plugins/`)

Each subdirectory is a self-contained Claude Code plugin. Plugins listed in `Scripts/Agents/auto-install-plugins.txt` are installed user-wide by `SetupDevice.ps1`. Others can be installed per-project:

```
claude plugin install <name>@<marketplace> --scope project
```

## Worktree Utilities

`start-worktree` and `end-worktree` (Python, no dependencies) manage feature branches in a consistent off-repo layout:

```cmd
start-worktree.cmd "add dark mode support"
# Creates: <drive>:\.worktrees\<project>\add-dark-mode-support
# Branch:  user/<alias>/add-dark-mode-support (based on origin/main)
```

```cmd
end-worktree.cmd [worktree-path]
# Removes the worktree and optionally deletes the local branch
```

## Automated Maintenance

`Invoke-RepoMaintenance.ps1` is registered as a Windows scheduled task by `SetupRepoMaintenance.ps1`. Each run:

1. Stashes local changes, switches to the default branch, and `git pull --ff-only` for every configured repo (skippable per repo with `"skipCommonSync": true`).
2. Calls `Scripts/Repos/<RepoName>/Invoke-Maintenance.ps1 -RepoPath <path>` if it exists, for repo-specific build or cache steps.

Logs are written to `%LOCALAPPDATA%\RepoMaintenance\RepoMaintenance.log`.

## Repository-Specific Scripts

Drop scripts into `Scripts/Repos/<RepoName>/` — the folder is added to `PATH` automatically when that repository's profile is opened. No configuration required beyond matching the folder name to the key in `RepositoryConfig.json`.

