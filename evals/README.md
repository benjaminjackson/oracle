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

### Stage A — screen (2026-07-05)

7 configs × 25-question stratified subset (5 anchors + 20 open-ended) × 1
repeat; pairwise vs incumbent `p0-default`, double-judged position-swapped.

| Config | Mean out tokens | W–T–L vs incumbent | Net losses | Anchors |
|---|---|---|---|---|
| p0-default (incumbent) | 477 | — | — | 5/5 |
| p0-low | **410 (−14%)** | 3–19–3 | 0 | 5/5 |
| p0-medium | 490 (+3%) | 3–19–3 | 0 | 5/5 |
| p1-default (CoD) | 554 (+16%) | 4–10–11 | 7 | 5/5 |
| p1-low (CoD) | 458 (−4%) | 3–11–10 | 7 | 5/5 |
| p1-medium (CoD) | 560 (+17%) | 5–13–7 | 2 | 5/5 |
| p2-default (one-liner) | 121 (−75%) | 0–2–23 | 23 | 5/5 |

Findings:

- **Chain-of-Draft loses on both axes**: more output tokens than the
  incumbent at default/medium effort *and* clearly worse pairwise quality at
  every effort level. On a prompt that already suppresses visible reasoning,
  the sketch is a surcharge, not a substitute (HANDOFF Q3: answered, no).
- **Lower effort is quality-neutral but saves only ~14%** (`p0-low`), below
  the ≥25% adoption threshold. `p0-medium` saves nothing.
- **One-liner control demolished** (0W–23L) — the corpus and judge
  distinguish quality; brevity alone doesn't win.
- **Length-bias tripwire: clear.** In CoD comparisons the longer answer lost
  most decisive pairs; anchor accuracy was flat everywhere.

### Follow-up screen — "caveman" density prompts (2026-07-05)

Owner-suggested variants, same 25-question screen:

| Config | Mean out tokens | W–T–L vs incumbent | Anchors |
|---|---|---|---|
| p3-caveman (instructed: strip filler, keep every fact) | 629 (+32%) | **14–9–2** | 5/5 |
| p4-caveman-prompt (system prompt itself telegraphic) | 707 (+48%) | 7–9–9 | 5/5 |

- Neither compresses: told to cut filler, Fable adds *substance* instead.
- `p3` is a real quality win (judge citations name quantified impacts and
  extra correct insights, not bulk; the same judge made longer CoD answers
  lose, so this isn't verbosity bias) — but at +32% output tokens it moves
  the wrong direction for this eval's objective. Documented as the known
  "deluxe Oracle" option.
- Demonstrating the register (`p4`) is strictly worse than describing it.

### Decision (rule applied)

Non-inferior configs: p0-low (410), p0-medium (490), p3-caveman (629, better
than incumbent), p4 (707). Lowest-token as-good config is `p0-low` at a 14%
saving — **below the ≥25% adoption bar. The incumbent (`p0-default`:
current prompt, default effort, unconditional `--tools "WebSearch"`) is
retained unchanged.** Stage B was cancelled by the owner mid-run as moot —
the adoption-blocking token arithmetic is judge-independent.

Calibration: `results/calibration_sheet.md` holds 18 blind pairs for human
audit of the judge (`calibrate.sh score` after filling in
`results/calibration_human.tsv`).
