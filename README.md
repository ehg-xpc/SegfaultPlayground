# Developer Environment Template

A starter scaffold for a personal Windows developer environment. Provides
Windows Terminal profile generation, repository management scripts, agent
setup (Claude Code, GitHub Copilot CLI, OpenCode), and device-bootstrap
automation.

## Getting Started

1. **Clone** this repo (or fork it) into your repos directory.
2. **Edit `Scripts/Devenv/config.json`** — set your name and email.
3. **Edit `Scripts/Devenv/RepositoryConfig.json`** — add entries for each
   repository you work in. The two included entries (`Developer` and
   `Workbench`) are examples; add, remove, or rename as needed.
4. **Run `devsetup.cmd`** — bootstraps the device: installs tooling, generates
   Windows Terminal profiles, registers Git aliases, and sets up the agent
   context pipeline.

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
