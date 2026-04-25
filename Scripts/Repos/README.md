# Repository-Specific Scripts

This folder contains scripts that are specific to individual repositories.

## Convention

When initializing a repository with `UserEnv.ps1 -RepositoryName <name>` or `UserEnv.cmd <name>`, 
the environment will automatically check for a folder matching the repository name in this directory.

If found, that folder is added to the PATH for that session only.

## Structure

```
Scripts/Repos/
├── MyRepo/       # Scripts for MyRepo only
├── MyRepo2/      # Scripts for MyRepo2 only
└── ...
```

## Usage

1. Create a folder with the exact repository name (as defined in `RepositoryConfig.json`)
2. Add your repo-specific scripts to that folder
3. When you initialize that repository, the scripts become available in PATH

## Example

```powershell
# When you run:
.\UserEnv.ps1 -RepositoryName MyRepo

# The following folder is automatically added to PATH (if it exists):
# %DEV_REPO%\Scripts\Repos\MyRepo
```

No configuration needed - just name the folder to match the repository name!

## Automated Maintenance: Invoke-Maintenance.ps1

The orchestrator `Scripts/Maintenance/Invoke-RepoMaintenance.ps1` runs daily and, for each
cloned repo in `Scripts/Devenv/RepositoryConfig.json`, performs two phases:

1. **Common sync** -- runs `Scripts/Maintenance/Invoke-RepoSync.ps1`, which stashes any
   local changes, switches to the repo's default branch, and `git pull --ff-only`s.
   Set `"skipCommonSync": true` on a repo entry in `RepositoryConfig.json` to opt out
   (e.g. for repos that need bespoke sync behavior).
2. **Per-repo maintenance** -- if `Scripts/Repos/<RepoName>/Invoke-Maintenance.ps1`
   exists, the orchestrator invokes it with `-RepoPath <absolute repo root>`. If the
   common sync failed for that repo, the per-repo script is skipped.

Per-repo `Invoke-Maintenance.ps1` scripts are therefore for any maintenance work
beyond a plain stash/checkout/pull -- builds, dependency installs, cache warming, etc.

**Signature:**

```powershell
param([string]$RepoPath)
# RepoPath is the absolute path to the repository root
```

**Behavior:**
- The repo is already on its default branch and up to date when the script runs (unless
  the repo has `skipCommonSync: true`).
- Exit 0 = success (logged as OK); non-zero = failure (logged as ERROR; other repos still run).
- stdout + stderr are captured into the orchestrator log at
  `%LOCALAPPDATA%\RepoMaintenance\RepoMaintenance.log`.
- The script's working directory is the orchestrator's, NOT the repo. Scripts that need
  the repo as cwd should `Push-Location $RepoPath` themselves.

**Example:**

```powershell
param([string]$RepoPath)
Push-Location $RepoPath
try {
    npm install
    npm run build
} finally {
    Pop-Location
}
```
