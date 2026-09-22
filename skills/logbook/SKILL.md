---
name: logbook
description: Create and maintain a persistent logbook for work that spans multiple iterations or sessions. Use for investigations, prompt tuning, architecture changes, performance work, or handoffs where exact results and decisions must survive context compaction. Resume an existing logbook when given its path.
---

# Logbook

Keep enough evidence that another agent can continue the work without repeating the investigation. Record exact results, decisions, failed approaches, and the next useful step.

## Create a logbook

1. Establish the problem and what done looks like from the current conversation. Ask only when missing information changes the scope or acceptance criteria.
2. Inspect the relevant files, current behavior, and available checks.
3. Choose a repeatable feedback loop: a focused test, evaluation, benchmark, reproduction command, or manual check with observable results. Add a helper only when existing checks cannot measure the outcome.
4. Use the project's logbook convention when one exists. Otherwise create `logbooks/YYMMDD_project_feature.md`, using the template below.
5. Run the feedback loop and record iteration 0 as the baseline. If blocked, record the missing prerequisite and leave the baseline pending.

Use commands verified in the current project. For model evaluations, record the model, settings, cases, and repeat count. Follow the project's evaluation and telemetry requirements.

## Resume a logbook

Read the entire logbook, including linked evidence needed for the next step. If it exceeds the tool's output limit, read it in chunks.

Tell the user the recorded status, latest results, and proposed next step. Verify facts that may have changed, such as the branch, deployment, or active failure, before relying on them.

## Maintain the iteration history

Before each iteration, reread the principles and recent entries. During the work, capture changes with enough detail to reproduce them: paths, commands, settings, inputs, and reasons.

After each iteration, append an entry and refresh the living sections: Status, Key files, Commands, Design, and Principles. Keep historical entries intact. Correct an earlier mistake with a dated correction that points to the original entry. Mark superseded principles with the reason and iteration that replaced them.

- Preserve exact counts, units, expected values, tolerances, and case identifiers when safe to record. Compare results under equivalent conditions and explain changes in test coverage.
- Separate observations from hypotheses. A failed reproduction, an unrun check, and a verified fix are different outcomes.
- If stuck, record the context, viable options, tradeoffs, and recommendation. Ask the user when the decision changes scope or product behavior.
- If entries accumulate without progress, revisit the hypothesis and feedback loop. Keep the audit trail available.
- Keep secrets and sensitive personal data out of the logbook. Use redacted examples and safe evidence references.

Keep the logbook within the authorized task. Its existence does not authorize committing, publishing, or running consequential operations.

### Iteration entry

Use the fields that apply. Record unavailable evidence explicitly instead of filling it with guesses.

```markdown
### Iteration N: [short title]

**Date:** YYYY-MM-DD

**Hypothesis or goal:** [what this iteration tests]

**Changes:**
- `path/to/file` [what changed and why]

**Verification:** [exact command or manual steps, environment, inputs, and settings]

| Case or metric | Result | Baseline | Notes |
| --- | --- | --- | --- |
| [case] | [observed value] | [previous value] | [conditions or limitations] |

**Root cause:** [confirmed mechanism and evidence, or unresolved hypothesis]

**Issues found:** [affected cases, fix, deferral, or blocker]

**Decision:** [continue, change approach, or done, with the reason and next step]
```

## New logbook template

Replace the placeholders with observed facts. Mark sections pending when evidence is unavailable.

````markdown
# [Workstream] logbook

## Status
Baseline pending.
Next step: [action and any prerequisite]

## Problem
[Current behavior, impact, scope, and observable acceptance criteria]

## Key files
- `path/to/file` [role]

## Commands
```text
[Verified command and working directory, or repeatable manual check]
```

## Design
[Chosen approach, alternatives, and reasons for rejecting them]

## Principles
[Constraints and lessons established by evidence; link to the relevant iteration]

## Iteration log

### Iteration 0: Baseline

**Date:** YYYY-MM-DD

**Current state:** [observed behavior and relevant revision or environment]

**Verification:** [command or steps, inputs, settings, and repeat count if applicable]

| Case or metric | Result | Notes |
| --- | --- | --- |
| [case] | [observed value or not run] | [evidence or blocker] |

**Plan:** [first change to try and why]
````
