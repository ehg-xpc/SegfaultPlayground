# Sync Agent Context

Run the sync-context script to commit, pull, and push the AgentContext repo.

```
sync-context
```

Show the script output to the user. If the script exits with a non-zero code, report the error:

- **Exit 1**: `~/.stanley/shared/{project}` symlink not found — agent context is not set up for this repo.
- **Exit 2**: Rebase conflict — list the conflicted files, read each one, resolve conflicts by keeping both sides (agent context files are additive), then re-run the script.
- **Exit 3**: Push failed — report the error to the user.
