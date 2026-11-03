# Reflection Brief — Harness Engineering Capstone Submission

**Name:** Not provided  
**Date:** 2026-11-03

**Environment**

- **Model(s):** `claude-haiku-4-5-20251001` for Systems 1 and 2; System 4 used its recorded response.
- **OS / Python:** Windows; Python 3.14.4.
- **Approx. API spend:** About $0.34 estimated from the run token counts and the repository's Haiku rates: Claims reported $0.1328; Context is about $0.206. These are estimates, not the provider's bill.

---

## Part 1 — Per-system

### System 1 — Agentic loop

1. **Loop control.** In [claim_03_water_damage.jsonl](./system1/run-artifacts/20261103_191028/traces/claim_03_water_damage.jsonl), the `stop_reason` sequence is `tool_use, tool_use, tool_use, tool_use, end_turn`. `claims_intake.loop.run` owns the decision: it dispatches tool results and continues on `tool_use`, returns on `end_turn`, and raises for any other reason. The trace is from run `20261103_191028`; the run summary is in [summary.md](./system1/run-artifacts/20261103_191028/summary.md).

2. **Anti-pattern.** `test_antipatterns.py` rejects content-based string-membership checks as loop control. If this loop stopped by looking for a word in the claimant or assistant text, it could stop prematurely or miss the actual API turn boundary, leaving tool work incomplete. The [Claims test log](./system1/tests.log) records 30 passing tests, and the water-damage [trace](./system1/run-artifacts/20261103_191028/traces/claim_03_water_damage.jsonl) shows explicit API stop reasons instead.

3. **Tool design.** `route_to_adjuster` and `escalate_to_human` both act on the same claim, but their descriptions distinguish the terminal action and its conditions: route after classification confidence is at least 0.6 and severity is assessed, or escalate when the claim cannot be routed safely. Tool errors are structured as `is_error`, `error_category`, `is_retryable`, and `message`, so the model can distinguish a correctable/retryable problem from a permanent one rather than guessing from a generic string. The [claim_02 trace](./system1/run-artifacts/20261103_191028/traces/claim_02_stolen_bike.jsonl) shows the run's tool-use turns.

4. **Your numbers.** `claim_02_stolen_bike` took 5 turns and its estimated cost was $0.0206; the entire eight-claim run estimated $0.1328 in [summary.md](./system1/run-artifacts/20261103_191028/summary.md). That total is above the README's roughly $0.05 sample. The live run used more tokens and turns than that estimate assumed, and the measured total includes all eight model-driven claim paths.

### System 2 — Context strategy

5. **The reduction.** In [budget.json](./system2/run-artifacts/20261103-192605/budget.json), the baseline is 38,708 tokens and the assembled context is 16,773, a 56.67% reduction. The active section dominates at 15,789 tokens because it preserves the ongoing payment-method issue verbatim. Keeping it exact protects details that are still being negotiated and may change turn by turn.

6. **Summarize vs preserve.** The rule is to compress resolved threads but preserve the active thread byte-for-byte, with the durable case-facts block separately placed at the top. In [budget.json](./system2/run-artifacts/20261103-192605/budget.json), resolved refund went from 12,344 input tokens to a 411-token assembled section, and subscription from 11,485 input tokens to 387; case facts are 204 tokens. The active section is 15,789 tokens and remains the exact source text.

7. **Facts block.** The main [eval.jsonl](./system2/run-artifacts/20261103-192605/eval.jsonl) passed 6/6 questions, including Q6's exact `in_progress` status. In [eval_control.jsonl](./system2/run-artifacts/20261103-192605/eval_control.jsonl), Q1 still passed but Q6 failed after removing case facts. That regression shows the compact structured facts block carries information that neither resolved summaries nor the active transcript reliably supplies.

### System 3 — Claude Code config

8. **Path-scoped rules.** The frontmatter in [api.md](./system3/.claude/rules/api.md) includes `paths: - "src/api/**/*"`. A glob-scoped rule can enforce an API convention across every matching file, including files in different subdirectories, while a directory-level `CLAUDE.md` is tied to one location in the hierarchy. The captured [configuration tree](./system3/claude-structure.txt) and validator's [OK output](./system3/validator.log) are the run evidence.

9. **Forked skill.** The [deploy-check skill](./system3/.claude/skills/deploy-check/SKILL.md) specifies `context: fork` and an `allowed-tools` list limited to `Read`, `Grep`, `Glob`, and read-only Git/GitHub commands. Forking keeps verbose discovery out of the parent context, and the allowlist prevents the check from modifying files or deploying. Without the fork, intermediate output contaminates the caller; without the read-only restriction, the check could have a wider operational blast radius.

10. **Scope.** The validator returned `OK` in [validator.log](./system3/validator.log). A project-level example is `.claude/commands/review.md`, shared by this repository; a user-level example named in that command is `~/.claude/commands/review-strict.md`, which would remain personal and is not included in the captured project tree. The [tree listing](./system3/claude-structure.txt) confirms the bundled configuration is project-level.

### System 4 — Orchestration

11. **Push work down.** The SQL query returned 17 defects from a warm-tier total of 40, as recorded in [defect-counts.log](./system4/defect-counts.log). `defects_since` runs `SELECT * FROM defects WHERE ts > ? ORDER BY ts DESC LIMIT ?`, supported by the `idx_defects_ts` index. The pipeline sends only that filtered new-defect set plus the bounded hot state to the model, not the full warm history.

12. **Crash recovery.** `recovery.decide` returns fresh when there are no steps, the manifest is complete, or the latest step is more than 30 minutes old; otherwise it resumes. A fresh run can inject the manifest's captured findings as a summary without trusting a stale partial working context. The [System 4 test log](./system4/tests.log) includes passing truth-table cases at 29, 30, and 31 minutes and the 30-minute threshold test.

13. **Small state.** The captured [hot_state-size.txt](./system4/hot-state-size.txt) reports 980 bytes, well under the 5,120-byte budget enforced by the state model. A fixed budget prevents prompt state from growing without bound across indefinitely many shifts. It also makes the state that crosses sessions predictable and auditable; the actual state is in [hot_state.json](./system4/hot_state.json).

### Part 2 — Synthesis

*Graded on connecting two or more systems. Cite a named file/artifact from each.*

14. **Three layers.**
    - **Model:** The Claims run used `claude-haiku-4-5-20251001`; its observed choices appear in the [run summary](./system1/run-artifacts/20261103_191028/summary.md).
    - **Harness:** `claims_intake.loop.run` controls calls and tool dispatch; the [claim trace](./system1/run-artifacts/20261103_191028/traces/claim_03_water_damage.jsonl) records its per-turn `stop_reason`.
    - **Orchestration:** `shift_monitor.pipeline.run_shift` filters, invokes, and persists state; the [shift output](./system4/shift.log) and [hot state](./system4/hot_state.json) show the persisted result.

15. **Deterministic vs prompt.** The loop's continue/stop contract is deterministic code, and the [Claims test log](./system1/tests.log) records the passing suite for that harness. The choice of whether a claim is theft, property damage, or ambiguous is guided by the system prompt and model judgment, visible in the outcomes in [summary.md](./system1/run-artifacts/20261103_191028/summary.md). Deterministic enforcement is right for control flow and safety invariants; prompts are appropriate for judgment that depends on the claim facts.

16. **Context, two faces.** System 2 reduced one conversation from 38,708 to 16,773 tokens (56.67%) in [budget.json](./system2/run-artifacts/20261103-192605/budget.json). System 4 carried a 980-byte hot state between shifts in [hot_state-size.txt](./system4/hot-state-size.txt), while the warm tier retained 40 total defects and returned only 17 new ones in [defect-counts.log](./system4/defect-counts.log). Both systems keep the working context bounded, but System 2 compresses resolved material within a conversation while System 4 persists a small summary and queries historical storage across sessions.

17. **Reliability you can't see in one run.** System 4's tests exercise the recovery boundary: a 30-minute-old step resumes, while a 31-minute-old step starts fresh. A successful ordinary shift run would not prove this boundary behavior, which matters because stale partial state can otherwise be mistaken for current work. The boundary cases and threshold test are recorded in [tests.log](./system4/tests.log).

18. **Blast radius.** In System 4, a bad analysis could recommend a costly quarantine and persist misleading alerts or a summary into the next shift; the [shift output](./system4/shift.log) shows the quarantine recommendation and the persistent [hot state](./system4/hot_state.json) shows what carries forward. This project is invoked as a one-shift CLI, not an always-running worker, so the operational kill switch is to disable the caller's next invocation and hold the persisted state for review. The recorded-response mode is useful for offline replay, not a substitute for stopping production scheduling.

### Part 3 — Honest assessment

19. **What broke.** The initial long-path environment left an incomplete Anthropic SDK, and the first Context run hit a cp1252 encoding error while printing its final status; the initial terminal excerpt is preserved in [run-191623-initial-console.log](./system2/run-191623-initial-console.log). I moved the Claims and Context venvs to short paths, changed the status marker to ASCII, and configured the helper's subprocess output as UTF-8. The successful retry `20261103-192605` exited 0, passed all evals, and its post-run [test log](./system2/tests.log) records 30 passing tests.

20. **What you'd change.** I would add a run-level acceptance check that distinguishes a deliberate model escalation from the deterministic backstop escalation caused by ending without a terminal tool. In run `20261103_191028`, four claims were routed and four were escalated, and the [escalations.jsonl](./system1/run-artifacts/20261103_191028/escalations.jsonl) shows each escalation resulted from the missing terminal action. That signal should fail or prominently warn in evaluation before a run is treated as meeting the expected 7-routed/1-escalated behavior.
