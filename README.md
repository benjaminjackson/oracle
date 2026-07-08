# oracle

A Claude Code plugin marketplace with one plugin: **oracle**, a fast, cheap way to get a one-shot answer without derailing your main session's context or train of thought.

## Installation

```
claude plugin marketplace add benjaminjackson/oracle
claude plugin install oracle@oracle
```

(The repo lives at `benjaminjackson/oracle`; `oracle` is the marketplace's internal name, used only in the `plugin@marketplace` install id above.)

Confirm it's installed with `claude plugin list`.

A couple of notes: if `ANTHROPIC_API_KEY` is set in your environment, the skill runs headless with `--bare` (API rates, off your Claude Code quota); otherwise it runs `--safe-mode` (OAuth, counts against your normal plan quota). Either way it's a small, cheap request. And the headless session has no file access, only `WebSearch`, so if a question needs a file's contents, the calling session reads the file first and pastes the relevant lines in.

## oracle

One skill, one agent, same job — answer a question as concisely as possible — at two different price points.

### oracle (skill)

The default path. Writes your question to a scratch file, then shells out to a bare headless Fable session (`claude -p --safe-mode` or `--bare`, whichever fits your setup) with a stripped system prompt. No agent scaffolding, no tool loadout beyond `WebSearch` — measured at ~900 input tokens of overhead per question, nearly all of it cache reads (the `WebSearch` schema is ~600 of those; omitting `--tools` entirely would load the CLI's ~17k default toolset instead). Every answer comes back with the exact token count and dollar cost for that call, so you're not guessing.

#### Usage

- **Explicitly:** `/oracle <question>`
- **Automatically:** on phrases like "ask the oracle" or "oracle, ..."

### oracle (agent)

Fallback only, for when the headless call can't run — no `claude` CLI on `PATH`, auth broken, sandboxed environment with no shell access. Same brief (shortest correct answer, lead with the word that matters), run as a proper subagent instead of a headless process: `Read`, `Grep`, `Glob`, `WebSearch`, `WebFetch`, ~6k tokens per question.

The skill falls back to this agent automatically if the headless command fails, and says so when it does.

## Author

Benjamin Jackson ([@benjaminjackson](https://github.com/benjaminjackson))
