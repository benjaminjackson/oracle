# Oracle eval harness

Permanent regression harness for the `/oracle` skill: measures answer quality
per output token across `--effort` × system-prompt configurations of the
headless `claude -p --model fable` call, using anchored pairwise judging
against the shipping configuration.

## Layout

- `questions.jsonl` — 51-question corpus: 41 open-ended judgment questions
  (legal, finance, operations, strategy, architecture, positioning, marketing,
  editorial, complex systems), each with `key_points` the judge is steered by,
  plus 10 `anchor` questions with verified `truth` fields graded absolutely.
  The plan's 5 recency-dependent `needs_search` questions were deliberately
  omitted (owner's call) — every question here is stable over time.
- `configs.jsonl` — the run matrix: efforts {low, medium, default} × prompts
  {P0 current concise, P1 Chain-of-Draft sketch} + P2 one-liner control.
  `p0-default` is the incumbent (what SKILL.md ships).
- `run.sh` / `run_one.sh` — generation. Resume-safe on (config, question,
  repeat): rerun after any interruption and it fills only the gaps.
  Parallelized with `xargs -P`.
- `judge.sh` / `judge_one.sh` — Sonnet judge. `pairwise` mode judges each
  challenger head-to-head vs the base config, twice per pair position-swapped
  (orientation disagreement = tie). `anchor` mode grades anchor questions
  against `truth`. Resume-safe the same way.
- `summary.sh` — jq-only report: per-config token stats, anchor accuracy,
  pairwise W/T/L with net losses, per-domain net losses, and the
  length-bias tripwire (how often the longer answer won).
- `phase0.sh` — one-off anatomy: input-overhead ablations, cache probe,
  default-effort identification, judge schema shape check.
- `results/` — committed raw outputs and judgments.

## How to run

```bash
evals/phase0.sh                                   # anatomy (~28 cheap calls)
evals/run.sh --ids evals/stage_a_ids.txt          # Stage A generation (7 × 25)
evals/judge.sh anchor
evals/judge.sh pairwise --base p0-default --challenger <cfg> --ids evals/stage_a_ids.txt
evals/summary.sh
# Stage B: full corpus, 2 repeats, champion only
evals/run.sh --configs p0-default,<champion> --repeats 2
evals/judge.sh pairwise --base p0-default --challenger <champion> --repeats 2
evals/summary.sh
```

All calls run on subscription quota (`--safe-mode`) unless `ANTHROPIC_API_KEY`
is set (then `--bare`). Everything is resume-safe; interrupt freely at quota
windows.

## Decision rule

A challenger is as-good-as-incumbent iff on Stage B (50 questions × 2 repeats):
net pairwise losses (losses − wins, ties excluded) ≤ 5 per 50; anchor accuracy
within 1 question of the incumbent; no single domain with ≥ 3 net losses; and
among decisive comparisons it doesn't lose worse than ~60/40 (a chosen
tolerance, not a significance test). Among as-good configs pick the lowest
mean output tokens, and adopt only if the saving is ≥ ~25%.

## Results

### Phase 0 — call anatomy (2026-07-05)

Ablations on the shipping config (mean of 3, tiny probe question):

| Variant | Input tokens (incl. cache) |
|---|---|
| Full shipping config | **896** |
| `--tools ""` (no tools at all) | 296 |
| No `--system-prompt` (CLI default) | 3,607 |
| `--tools` omitted (CLI default toolset) | 18,007 |
| Bare (no flags) | 20,767 |

- The WebSearch tool schema costs ~600 input tokens per call. That's noise,
  and far below the plan's 1k threshold — **conditional `--tools` (A3) is
  dead**; keep it unconditional. Omitting the flag is the expensive mistake
  (the default toolset is ~17k tokens).
- Oracle's short system prompt *saves* ~2.7k tokens vs the CLI default one.
- **Caching (A4): already maximal.** Identical calls at t=0/+10s/+6min all
  show `cache_read=894, cache_creation=0` — the scaffolding is cached from
  the first call. Fresh input per call ≈ 2 tokens + the question.
- Default effort produces more output tokens than `medium` and slightly fewer
  than `high` on reasoning probes (default 159/354, low 74/270, medium
  95/320, high 155/433) — so the Stage A effort columns stay
  {low, medium, default}.
- Judge `--json-schema` returns the structured verdict as a JSON *string* in
  `.result`; `judge_one.sh` parses either shape.

### Stage A / Stage B

_(pending)_
