# Experiment: Oracle prompt on Gemini 4 Neon (2026-11)

The skill's opt-in Gemini path changed from Gemini 4 Carbon to Gemini 4 Neon. This experiment repeats `../gemini-carbon-2026-11/` on Neon. It asks two questions: how do Neon's answers compare with Fable's, and are they better or worse than Carbon's?

Run with the shared harness in `evals/`. See `../../README.md` for how to start the scripts. Run them from inside this directory.

Files here: `configs.jsonl` (three configs with the same prompt), `questions.jsonl` and `stage_a_ids.txt` (copied without change from `../gemini-carbon-2026-11/`), `results/` (raw answers and judgments).

## Setup

- `fable-p6-shorthand`: the shipping Fable path. `claude -p --model fable`, WebSearch tool, default effort. Answers generated again on 2026-11-20.
- `neon-p6-shorthand`: `gemini-4-neon` through `oracle/skills/oracle/gemini_oracle.sh`. Google Search tool, default thinking level. Answers generated on 2026-11-20.
- `carbon-p6-shorthand`: the Carbon answers from 2026-11-10, copied from `../gemini-carbon-2026-11/results/raw/`. They were not generated again. The skill now calls Neon, so this config would call Neon if `run.sh` were to fill a missing Carbon answer. Do not run `run.sh` on this config.
- All configs use the shipping system prompt, character for character.
- 25 questions (the Stage A subset: 5 anchor questions and 20 open questions), 1 answer per question per model.
- Judge: Sonnet, pairwise, each pair judged two times with the answer positions swapped. A disagreement between the two is a tie. Two comparisons: Neon against Fable, and Neon against Carbon.

## Results (2026-11-20)

| | Fable | Gemini 4 Neon | Gemini 4 Carbon (11-10) |
|---|---|---|---|
| Mean answer length, characters | 1,517 | 1,481 | 1,540 |
| Mean output tokens (answer only for Gemini) | 857 | 431 | 445 |
| Mean thinking tokens | not reported apart | 1,552 | 1,406 |
| Anchor questions correct | 5/5 | 5/5 | 5/5 |
| Searches, 25 questions | not counted | 10 | 8 |
| Mean cost per question | $0.048 | $0.031 | $0.019 |
| Total cost, 25 questions | $1.20 | $0.78 | $0.49 |

Pairwise, 25 pairs each:

| | Neon won | Tied | Neon lost | Net losses | Neon's share of decisive pairs lost | Longer answer won |
|---|---|---|---|---|---|---|
| Neon against Fable | 3 | 14 | 8 | 5 | 73% (8 of 11) | 9 of 11 |
| Neon against Carbon | 7 | 13 | 5 | -2 | 42% (5 of 12) | 11 of 12 |

Notes on the numbers:

- The Fable cost is the price the CLI reports. On a Claude subscription it is not billed as money. The Gemini costs are billed to the Google project.
- Neon's prices are $3 per 1M input tokens and $15 per 1M output tokens, with no end date on the pricing page. The Carbon cost is at its price on 2026-11-10 ($2 and $10). Carbon's prices double on December 1, 2026, to about $0.039 per question. From that date Neon costs less than Carbon.
- The Gemini costs are the token cost only. Google bills searches at $14 per 1,000 after 5,000 free searches per month. Neon's 10 searches cost $0.14 if the free allowance was used up, and nothing if it was not.
- Thinking tokens are about 78% of the tokens that Neon bills at the output price.

## Findings

- **The terse style holds on Neon.** Neon's answers are about the same length as Fable's and Carbon's.
- **Neon is correct on the facts that have a known answer** (5/5 anchors), the same as Fable and Carbon.
- **Fable's answers are still better on the open questions.** Under the decision rule in `../../README.md`, a challenger is as good as the incumbent only with net losses of 5 or fewer per 50 pairs and a loss share near 60% or lower. Neon has net losses of 5 in 25 pairs (the same rate as 10 per 50) and a 73% loss share, so it does not pass. No single domain has 3 or more net losses. In the judge's reasons, Fable usually wins because it adds one more specific point that changes what the asker does: a precedent, a worked example, a quantified effect. No reason names a factual error in Neon's answer.
- **Neon is about the same as Carbon, possibly a little better.** Neon won 7 and lost 5 of the 12 decisive pairs. That difference is too small to mean much with 25 questions.
- **The length-bias check did not come out clear.** The longer answer won 9 of 11 decisive pairs against Fable and 11 of 12 against Carbon. The mean lengths are close, so length does not explain which model wins more often, but for a single pair the judge's choice and the length are linked.

Limits: one answer per question, 25 questions, 11 and 12 decisive pairs. This is a screen, not a large test.

## Decision

Fable stays the default. Gemini 4 Neon replaces Carbon as the opt-in second opinion, with the Oracle prompt unchanged. Its answers are about as good as Carbon's, and from December 1, 2026 it costs less. A lower `thinking_level` was not tested.
