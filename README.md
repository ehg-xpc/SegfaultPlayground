# Developer Environment Template

## What this is

A starter scaffold for a personal Windows developer environment. It bundles the
scripts, shared agent configuration, and Windows Terminal profile generation
that bootstraps a new devbox to a known-good state.

The template is intentionally generic. Personal data (your name and email,
your repository list, your Stanley project map) lives in a small set of files
that downstream forks override and never push back upstream.

## Getting started

1. Clone this repository.
2. Edit `Scripts/Devenv/config.json` and set `user.name` and `user.email`.
3. Edit `Scripts/Devenv/RepositoryConfig.json` and add the repos you work in.
4. From an elevated PowerShell, run `Scripts\devsetup.cmd`.

## Forking

This template is designed to be forked. A downstream fork keeps a `template`
remote pointing at this repository and pulls in updates over time:

```
git remote add template <this-repo-url>
git fetch template
git merge template/main
```

The fork-side files that intentionally diverge from the template (your
`config.json`, your `RepositoryConfig.json`, your Stanley `server.settings.json`,
your personal `CLAUDE.md` and `copilot-instructions.md`, and the fork-side
`README.md`) are kept in place across merges via `merge=ours` rules in
`.gitattributes`. See the fork's own README for fork-specific guidance.
