# Local Marketplace Plugins

## Introduction

This directory holds plugin folders for the local Claude Code marketplace.

Each plugin is a directory containing:

- `.claude-plugin/plugin.json` — plugin manifest
- `commands/*.md` — command definitions

Plugins listed in `Scripts/Agents/auto-install-plugins.txt` are installed
user-wide automatically by `SetupDevice`. Others can be installed per-project:

```
claude plugin install <name>@<marketplace> --scope project
```

## How to use the local marketplace

- Install a plugin for the current repository only:

```
claude plugin install <name>@<marketplace> --scope project
```

- To add a plugin locally, create a subdirectory here with the plugin layout:
	- `.claude-plugin/plugin.json` — plugin manifest
	- `commands/*.md` — command definitions

- To make plugins available user-wide, list them in `Scripts/Agents/auto-install-plugins.txt` or use the setup scripts in `Agents/` so `SetupDevice` installs them during machine provisioning.

- Tips: use semantic versioning in `plugin.json`, include concise examples in `commands/*.md`, and test by installing with `--scope project` and reloading your Claude/IDE integration.

---

## Concepts

### What is the local marketplace?

The local marketplace is a repository-scoped collection of Claude Code plugins kept alongside your project. It lets teams develop, share, and consume plugins without publishing them to a public marketplace. Plugins in this directory follow the same structure as published plugins (a `.claude-plugin/plugin.json` manifest plus `commands/*.md` files) but remain under your project's control.

### What is a plugin?

Create custom plugins to extend Claude Code with skills, agents, hooks, and MCP servers.

Plugins let you extend Claude Code with custom functionality that can be shared across projects and teams. This guide covers creating your own plugins with skills, agents, hooks, and MCP servers.

A plugin is a self-contained extension that adds commands, prompts, or integrations to a Claude Code-enabled environment. At minimum a plugin contains a `.claude-plugin/plugin.json` manifest (metadata, id, version, entry points, permissions) and one or more `commands/*.md` files that define the actual user-facing commands. Plugins are executed by the host CLI/integration and are intended to be discoverable, installable, and versioned.

Learn more from the official [Claude Code Docs](https://code.claude.com/docs/en/plugins).

### When to use a plugin?

Use plugins when:

- You want to share functionality with your team or community
- You need the same skills/agents across multiple projects
- You want version control and easy updates for your extensions
- You’re distributing through a marketplace.

### How a plugin compares to an MCP tool

- Scope: plugins are extension bundles for Claude/IDE integrations and are typically invoked by the assistant or the user's CLI; MCP tools (Model Context Protocol tools) are general-purpose programmatic tools or adapters the model can call as part of a workflow.
- Packaging: plugins use the `.claude-plugin` layout and `commands/*.md`; MCP tools follow whatever packaging the MCP/runtime requires (often code modules or registered endpoints).
- Invocation: plugins expose user-facing commands and are usually invoked interactively via the CLI or UI; MCP tools are invoked by a model or agent in-context as callable tools with programmatic inputs/outputs.
- Security/permissions: plugins declare permissions in their manifest and are installed explicitly; MCP tools are typically registered with a runtime and may require different authentication or sandboxing.
- Use cases: choose a plugin when you want sharable, discoverable commands integrated into the local developer workflow; choose an MCP tool when you need a programmatic API-like capability the model can call during automated workflows.

## Common official Claude plugins

The Anthropics `claude-code` repository includes many example and core plugins. Below is a concise table of several commonly referenced plugins, with a short paraphrased description and the main types of contents they expose. For full details see the upstream directory: https://github.com/anthropics/claude-code/tree/main/plugins

| Plugin | Description | Contents |
|---|---|---|
| code-review | Automated PR code review workflow using multiple specialized agents | Command: `/code-review`; Agents: review analyzers and scoring logic |
| commit-commands | Git workflow automations for committing, pushing, and creating PRs | Commands: `/commit`, `/commit-push-pr`, `/clean_gone` |
| feature-dev | Guided 7-phase feature development workflow | Command: `/feature-dev`; Agents: `code-explorer`, `code-architect`, `code-reviewer` |
| frontend-design | Frontend UI/UX design guidance and examples | Skill: `frontend-design`; design guidance and examples |
| hookify | Tools for authoring and managing conversation hooks and rules | Commands: `/hookify`, `/hookify:list`, `/hookify:configure`; Agent: `conversation-analyzer` |
| learning-output-style | Interactive learning mode that prompts for contributions at decision points | Hook: `SessionStart`; instructional prompts and checks |
| pr-review-toolkit | Bundle of PR-review agents focusing on comments, tests, and simplification | Command: `/pr-review-toolkit:review-pr`; Agents: `comment-analyzer`, `pr-test-analyzer`, `code-simplifier` |
| ralph-wiggum | Iterative self-referential loop agent for repeated refinement | Commands: `/ralph-loop`, `/cancel-ralph` |
| security-guidance | Hook that warns about common security issues while editing | Hook: `PreToolUse`; pattern checks for injection, unsafe deserialization, eval, etc. |
| explanatory-output-style | Adds explanatory, educational commentary to outputs | Hook: `SessionStart`; explanatory output helpers |
