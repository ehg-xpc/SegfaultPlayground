# Config

This directory holds per-CLI preference files that configure coding-agent
behavior across your repositories.

## Structure

```
Config/
├── claude/
│   └── preferences.md    # Claude Code style & behavioral preferences
├── copilot/
│   └── preferences.md    # GitHub Copilot CLI preferences
└── opencode/
    └── preferences.md    # OpenCode preferences
```

## Setup

Create a subfolder for each CLI you use and add a `preferences.md` file
containing your coding style, conventions, and behavioral guidelines.
These are injected into agent context by the shared-context pipeline
(`Scripts/Devenv/SetupSharedAgentContext.ps1`) so every session picks
them up automatically.
