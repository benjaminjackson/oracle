# Oracle eval harness

Permanent regression harness for the `/oracle` skill: measures answer quality
per output token across `--effort` × system-prompt configurations of the
headless `claude -p --model fable` call, using anchored pairwise judging
against the shipping configuration.

## Layout

Shared harness (this directory) — reused across every experiment:

- `run.sh` / `run_one.sh` — generation. Resume-safe on (config, question,
  repeat): rerun after any interruption and it fills only the gaps.
  Parallelized with `xargs -P`.
- `judge.sh` / `judge_one.sh` — Sonnet judge. `pairwise` mode judges each
  challenger head-to-head vs a base config, twice per pair position-swapped
  (orientation disagreement = tie). `anchor` mode grades anchor questions
  against `truth`. Resume-safe the same way.
- `summary.sh` — jq-only report: per-config token stats, anchor accuracy,
  pairwise W/T/L with net losses, per-domain net losses, and the
  length-bias tripwire (how often the longer answer won).
- `phase0.sh` — one-off anatomy: input-overhead ablations, cache probe,
  default-effort identification, judge schema shape check.
- `calibrate.sh` — blind human-calibration audit: samples judged pairs and
  writes an answer key + blinded sheet for manual grading.

Each experiment lives in its own folder under `experiments/`, holding that
experiment's `configs.jsonl` (run matrix), `questions.jsonl` (question
corpus), any question-subset files (e.g. `stage_a_ids.txt`), `results/`
(raw generations + judgments), and a `README.md` with that experiment's
results/decision log. See `experiments/prompt-tuning-2026-07/README.md` for
the current example.

The scripts operate on the **current working directory** — `cd` into an
experiment folder before running them.

## How to run

```bash
cd evals/experiments/prompt-tuning-2026-07
../../phase0.sh                                   # anatomy (~28 cheap calls)
../../run.sh --ids stage_a_ids.txt                # Stage A generation (7 × 25)
../../judge.sh anchor
../../judge.sh pairwise --base p0-default --challenger <cfg> --ids stage_a_ids.txt
../../summary.sh
# Stage B: full corpus, 2 repeats, champion only
../../run.sh --configs p0-default,<champion> --repeats 2
../../judge.sh pairwise --base p0-default --challenger <champion> --repeats 2
../../summary.sh
```

Starting a new experiment: make a new folder under `experiments/` with its
own `configs.jsonl` + `questions.jsonl`, `cd` into it, and run the same
scripts.

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

See each experiment's own `README.md` for its results/decision log, e.g.
`experiments/prompt-tuning-2026-07/README.md`.
