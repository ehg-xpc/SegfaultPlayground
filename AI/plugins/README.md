# Local Marketplace Plugins

This directory holds plugin folders for the local Claude Code marketplace.

Each plugin is a directory containing:

- `.claude-plugin/plugin.json` — plugin manifest
- `commands/*.md` — command definitions

Plugins listed in `Scripts/Agents/auto-install-plugins.txt` are installed
user-wide automatically by `SetupDevice`. Others can be installed per-project:

```
claude plugin install <name>@<marketplace> --scope project
```
