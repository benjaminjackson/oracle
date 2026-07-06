# oracle

A Claude Code plugin marketplace with one plugin: **oracle**, a fast, cheap way to get a one-shot answer without derailing your main session's context or train of thought.

## Before you install

- Requires the `claude` CLI binary on `PATH` — the skill shells out to a fresh headless `claude -p` session. If you're running Claude Code at all, you already have this.
- Uses the `fable` model. Your account needs access to it.
- Billing: if `ANTHROPIC_API_KEY` is set in your environment, the skill runs headless with `--bare` (API rates, off your Claude Code quota). Otherwise it runs `--safe-mode` (OAuth, counts against your normal plan quota) — no extra cost beyond a small, cheap request.
- The skill has no file access in its headless session — only `WebSearch`. If a question needs a file's contents, the calling session reads the file first and pastes the relevant lines in.

## Installation

Inside a Claude Code session:

### Add the marketplace

```
/plugin marketplace add benjaminjackson/oracle
```

### Install oracle

```
/plugin install oracle@oracle
```

(The repo lives at `benjaminjackson/oracle`; `oracle` is the marketplace's internal name, used only in the `plugin@marketplace` install id above.)

Confirm it's installed: run `/plugin` (Installed tab) or `/plugin list`.

## oracle

One skill, one agent, same job — answer a question as concisely as possible — at two different price points.

### oracle (skill)

The default path. Writes your question to a scratch file, then shells out to a bare headless Fable session (`claude -p --safe-mode` or `--bare`, whichever fits your setup) with a stripped system prompt. No agent scaffolding, no tool loadout beyond `WebSearch` — measured at ~900 input tokens of overhead per question, nearly all of it cache reads (the `WebSearch` schema is ~600 of those; omitting `--tools` entirely would load the CLI's ~17k default toolset instead). Every answer comes back with the exact token count and dollar cost for that call, so you're not guessing.

#### Usage

- **Explicitly:** `/oracle <question>`
- **Automatically:** on phrases like "ask the oracle" or "oracle, ..."

#### Why the scratch-file step

macOS ships bash 3.2 by default, and a heredoc nested inside `$(...)` breaks the instant the body has a contraction (`don't`, `it's`) — a real parser bug, not a wording issue. The skill sidesteps it entirely: write the question to a plain text file with the Write tool (no shell parsing, so quotes and backticks are inert), then read it back with a bare `$(cat file)`.

### oracle (agent)

Fallback only, for when the headless call can't run — no `claude` CLI on `PATH`, auth broken, sandboxed environment with no shell access. Same brief (shortest correct answer, lead with the word that matters), run as a proper subagent instead of a headless process: `Read`, `Grep`, `Glob`, `WebSearch`, `WebFetch`, ~6k tokens per question.

The skill falls back to this agent automatically if the headless command fails, and says so when it does.

## Repo structure

```
.claude-plugin/marketplace.json   # marketplace manifest (this repo)
oracle/.claude-plugin/plugin.json # oracle plugin manifest
oracle/agents/oracle.md           # fallback agent
oracle/skills/oracle/SKILL.md     # headless-Fable skill
evals/                            # permanent eval harness; evals/experiments/ holds each experiment's data + results
```

The `evals/` directory holds a bash+jq eval harness (generation, Sonnet judge, reporting) shared across experiments, each of which lives in its own folder under `evals/experiments/` with its own question corpus, run matrix, and results. See `evals/README.md`, and each experiment's own `README.md` (e.g. `evals/experiments/prompt-tuning-2026-07/README.md`) for its results/decision log.

## Author

Benjamin Jackson ([@benjaminjackson](https://github.com/benjaminjackson))
