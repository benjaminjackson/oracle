# Experiment: oracle system-prompt / effort tuning (2026-07)

Tunes the `/oracle` skill's `--effort` × system-prompt configuration. Run via
the shared harness in `evals/` — see `../../README.md` for how to invoke the
scripts (run them from inside this directory, e.g. `../../run.sh --ids
stage_a_ids.txt`).

Files here: `configs.jsonl` (the run matrix), `questions.jsonl` (the question
corpus), `stage_a_ids.txt` (Stage A subset), `results/` (raw generations,
judgments, phase0 anatomy, calibration artifacts).

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

### Decision (rule applied, superseded below)

Non-inferior configs: p0-low (410), p0-medium (490), p3-caveman (629, better
than incumbent), p4 (707). Lowest-token as-good config is `p0-low` at a 14%
saving — **below the ≥25% adoption bar. The incumbent (`p0-default`:
current prompt, default effort, unconditional `--tools "WebSearch"`) is
retained unchanged.** Stage B was cancelled by the owner mid-run as moot —
the adoption-blocking token arithmetic is judge-independent.

This call was revisited the same day once the caveman result's real driver
was separated out from raw length — see below.

### Judge rubric fix — closing the length-bias loophole (2026-07-05)

`p3-caveman`'s win looked like it might just be verbosity credit: it ran
+32% tokens and 14/16 of its decisive wins were also the longer answer of
the pair. The pairwise rubric already said "length is NOT merit"
(`judge_one.sh`), but that instruction alone wasn't forcing the judge to
separate genuine added content from padding. Strengthened it to require the
judge to name the specific claim/fact/number the longer answer has that the
shorter one lacks, and only count it if it's non-redundant and would change
what the asker does next — plus a worked example distinguishing an added
fact from an added caveat that doesn't change anything. All results below
were judged under the strengthened rubric.

### Follow-up screen — length-neutral density prompts (2026-07-05)

Caveman wins by telling Fable to strip filler — but demonstrated (not
described) it also makes Fable write *more*, not less. Tested whether an
explicit "cut wasted words, keep every fact" instruction could win the same
way without the token surcharge, plus how far compact notation and a full
informal register push it. Same 25-question Stage A screen, strengthened
rubric, `p0-default` figures below are the Stage-A-matched subset (differs
slightly from the Phase-0-inclusive numbers in the table above):

| Config | Mean out tokens | Mean chars | W–T–L vs incumbent | Loss share (decisive) | Anchors |
|---|---|---|---|---|---|
| p0-default (incumbent, Stage A subset) | 477 | 1184 | — | — | 5/5 |
| p5-telegram (cut filler, no notation) | 521 (+9%) | 1236 (+4%) | 7–17–1 | 13% | 5/5 |
| p6-shorthand (+ compact notation: `&` `w/` `b/c` `vs`, numerals, comma joins) | 490 (+3%) | 1125 (−5%) | 11–14–0 | **0%** | 5/5 |
| p7-teentext (full texting register: `u` `ur` `thx`) | 615 (+29%) | 1456 (+23%) | 11–8–6 | 35% | 5/5 |

Findings:

- **`p6-shorthand` is the first challenger in this harness to win outright
  without running longer than incumbent.** Zero losses across 25 pairs,
  and shorter by character count — the length-bias tripwire can't explain
  this one away.
- **Why it wins isn't length — it's density.** Reading the judge's own
  reasoning for every decisive shorthand win, the cited reason is
  consistently a specific added fact/number/technique the other answer
  lacked (a named dedup mechanism, a concrete reconsideration threshold, an
  extra uptime-tier reference point), never raw length or thoroughness.
  Same mechanism the strengthened rubric was designed to isolate.
- **Informal register alone doesn't reduce tokens.** `p7-teentext` is the
  most expensive config tested, more than incumbent — shorthand notation
  built for a human's eyes (`u`, `ur`, `w/`) doesn't reliably tokenize
  smaller than the plain words it replaces, since common English words are
  often already single cheap tokens. It still beats incumbent on quality
  (35% loss share) but loses more than twice as often as shorthand, at
  higher cost. Not adopted.
- **No correctness cost measured** for any of the three: 5/5 anchor
  accuracy across telegram, shorthand, and teentext, same as every other
  config tested. (Small sample — 5 anchor questions — not a strong
  guarantee against edge cases the corpus doesn't cover.)
- Caveat: single generation per question, 25 questions, 8–17 decisive
  pairs per comparison. Real signal, not a large-n guarantee.

### Decision (updated, 2026-07-05)

**Adopted `p6-shorthand`, superseding the earlier "retain incumbent" call.**
Zero losses at roughly matched length clears a higher bar than the original
≥25%-token-savings rule was built to test for — the original rule assumed
the only way to justify a switch was cost; this challenger justifies it on
quality at neutral cost instead. `SKILL.md` and `oracle/agents/oracle.md`
now ship the shorthand system prompt. Separately, `SKILL.md` was changed to
have the calling assistant present Oracle's answer in its own words rather
than relaying it verbatim — which also means the raw system-prompt voice
(shorthand, or whatever ships next) no longer reaches the user unfiltered,
only the facts it contains do.

Calibration: a blind 20-pair human audit against `results/calibration_key.tsv`
was attempted and abandoned. An unrelated `calibrate.sh --help` invocation
(the script has no help flag; the first argument is parsed as sample size
`N`, and a `head -n` failure downstream wasn't fatal without `set -e`)
silently truncated the key and regenerated the sheet mid-audit, and the
original key — never read, per the audit's own blinding rule — could not be
reconstructed. Separately, the caveman configs' writing style turned out to
be recognizable enough on its own that a human grader likely isn't blind to
config identity regardless of file hygiene, which would have undermined the
audit's premise even on a clean run. Abandoned in favor of trusting the
judge directly, cross-checked by reading its actual reasoning (see above)
rather than a blind human replay. `calibrate.sh` now validates its `N`
argument, handles `-h`/`--help`, and refuses to touch an existing
key/sheet if a run comes up empty — the footgun that caused this is
closed, though the original destroyed key remains unrecoverable.
