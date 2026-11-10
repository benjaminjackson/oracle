# Experiment: Oracle prompt on Gemini 4 Carbon (2026-11)

The Oracle system prompt was tuned against Fable in `../prompt-tuning-2026-07/`. This experiment asks one question: when the same prompt goes to Gemini 4 Carbon (the opt-in "ask Gemini" path of the skill), does the terse style hold, and how good are the answers?

Run with the shared harness in `evals/`. See `../../README.md` for how to start the scripts. Run them from inside this directory.

Files here: `configs.jsonl` (two configs with the same prompt, one per model), `questions.jsonl` and `stage_a_ids.txt` (copied without change from `../prompt-tuning-2026-07/`), `results/` (raw answers and judgments).

## Setup

- `fable-p6-shorthand`: the shipping Fable path. `claude -p --model fable`, WebSearch tool, default effort.
- `carbon-p6-shorthand`: `gemini-4-carbon` through `oracle/skills/oracle/gemini_oracle.sh`. Google Search tool, default thinking level.
- Both configs use the shipping system prompt, character for character.
- 25 questions (the Stage A subset: 5 anchor questions and 20 open questions), 1 answer per question per model.
- Fable answers were generated again on the same day. The July answers were not reused, so both models are compared as they are today.
- Judge: Sonnet, pairwise, each pair judged two times with the answer positions swapped. A disagreement between the two is a tie.

## Results (2026-11-10)

| | Fable | Gemini 4 Carbon |
|---|---|---|
| Mean answer length, characters | 1,559 | 1,540 |
| Median answer length, characters | 1,508 | 1,531 |
| Mean output tokens (answer only for Carbon) | 877 | 445 |
| Mean thinking tokens | not reported apart | 1,406 |
| Anchor questions correct | 5/5 | 5/5 |
| Answers that use `w/` | 18/25 | 21/25 |
| Answers that use `&` | 16/25 | 19/25 |
| Answers that use `b/c` | 3/25 | 8/25 |
| Mean cost per question | $0.051 | $0.019 |
| Total cost, 25 questions | $1.28 | $0.49 |

Pairwise, Carbon against Fable, 25 pairs: Carbon won 5, tied 9, lost 11. Net losses: 6. Carbon lost 69% of the 16 decisive pairs. The longer answer won 13 of the 16 decisive pairs.

Notes on the numbers:

- The Fable cost is the price the CLI reports. On a Claude subscription it is not billed as money. The Carbon cost is billed to the Google project.
- The Carbon cost is at the price that applied on the test day: $2 per 1M input tokens and $10 per 1M output tokens. Google's pricing page says both prices double on December 1, 2026. At those prices the mean Carbon cost is about $0.039 per question.
- The Carbon cost is the token cost only. The 25 Carbon calls made 8 searches. Google bills searches at $14 per 1,000 after 5,000 free searches per month, so these 8 cost $0.11 if the free allowance was used up, and nothing if it was not.
- Thinking tokens are about 76% of the tokens that Carbon bills at the output price.
- The Fable mean of 877 output tokens is higher than the 490 measured in July for the same prompt. The two numbers are from different days and possibly different model versions, so they are not comparable.

## Findings

- **The terse style holds.** Carbon's answers are the same length as Fable's, and Carbon uses the shorthand notation more often than Fable does.
- **Carbon is correct on the facts that have a known answer** (5/5 anchors), the same as Fable.
- **Fable's answers are better on the open questions.** Under the decision rule in `../../README.md`, a challenger is as good as the incumbent only with net losses of 5 or fewer per 50 pairs and a loss share near 60% or lower. Carbon has net losses of 6 in 25 pairs and a 69% loss share, so it does not pass. No single domain has 3 or more net losses; the losses are spread across domains. In the judge's reasons, Fable usually wins because it gives one more specific and useful fact or number. Two Carbon losses (`arch-05`, `mkt-03`) name a factual error in Carbon's answer, and others name claims that Carbon overstated.
- **The length-bias check did not come out clear.** The longer answer won 13 of 16 decisive pairs. The two models have the same mean length, so length does not explain why one model wins more often, but for a single pair the judge's choice and the length are linked.

Limits: one answer per question, 25 questions, 16 decisive pairs. This is a screen, not a large test.

## Decision

Fable stays the default. Gemini 4 Carbon is an opt-in second opinion, and the Oracle prompt is used on it without change. The prompt was not tuned for Carbon, and the thinking level was left at Google's default. A lower `thinking_level` could reduce the cost; it was not tested.
