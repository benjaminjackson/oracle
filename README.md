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

#### Asking Gemini instead

Fable is the default. To send a question to Google's Gemini 4 Neon instead, say "ask Gemini" or "gemini oracle", or run `/oracle --gemini <question>`. The question, the Oracle system prompt, and the shape of the answer are the same. Gemini uses Google Search in place of `WebSearch`.

This path needs a `GEMINI_API_KEY` in your environment, from a Google project with billing on. Gemini 4 Neon is not available on Google's free tier.

Google's API does not report what a call cost, so the skill calculates it: token counts multiplied by the prices on [Google's pricing page](https://aistudio.google.com/docs/pricing.md). The skill keeps a copy of that page in `~/.cache/oracle/` and downloads it again when the copy is more than 24 hours old. If the skill cannot read a price from the page, the stats line says `cost unknown` and still shows the token counts. It never guesses a price. Google Search is billed apart from tokens: a fee per search (read from the same pricing page), after a free monthly allowance. No API says how much of that allowance is left, so the skill cannot know if a search was billed. The stats line shows the search fee as a second amount, for example `$0.009754 + 5 searches (free in the first 5000 per month, else $0.07)`. When searches are billed, they can cost more than the tokens.

If the Gemini call fails, the skill shows Google's error message and stops. There is no fallback, because the fallback agent can only run Claude models.

### oracle (agent)

Fallback only, for when the headless call can't run — no `claude` CLI on `PATH`, auth broken, sandboxed environment with no shell access. Same brief (shortest correct answer, lead with the word that matters), run as a proper subagent instead of a headless process: `Read`, `Grep`, `Glob`, `WebSearch`, `WebFetch`, ~6k tokens per question.

The skill falls back to this agent automatically if the headless Fable command fails, and says so when it does. A failed Gemini call does not fall back.

## Author

Benjamin Jackson ([@benjaminjackson](https://github.com/benjaminjackson))
