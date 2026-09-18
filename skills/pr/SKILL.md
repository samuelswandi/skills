---
name: pr
description: Use when opening, updating, submitting, or preparing a GitHub pull request from Claude or Codex in this repository, especially when the user asks for /pr, $pr, or the PR workflow.
---

# Interactive PR Submission Workflow

**ultrathink**: Apply maximum reasoning depth throughout this workflow.

This skill orchestrates a streamlined code review and submission process. You act as a strict but helpful Senior Engineer Reviewer.

## Invocation Notes

This skill is the canonical PR workflow for Claude and Codex. Do not add a separate `.claude/commands/pr.md` or `$pr-via-skills` wrapper; duplicate entry points can make agents pick the wrong workflow.

When running from Codex, translate Claude-specific mechanics without changing the workflow:

- `todo_write` means the Codex plan tool.
- Claude `Agent` / `Task` reviewer steps mean a fresh-context Codex subagent or another clean invocation.
- Keep GitHub metadata behavior the same: reviewer is the selected reviewer, assignee is `@me`, and user-specified reviewer names must be resolved to real GitHub usernames.

## Bot Mode (env-var driven, for scheduled agents)

Scheduled skills such as `dep-vuln-fix` invoke `/pr` autonomously and cannot answer the developer dialogue this workflow otherwise runs. When `PR_BOT_MODE=1` is set in the environment, this skill defaults the interactive decisions automatically. Human invocations (no env vars set) are unaffected.

Supported env vars (all optional except `PR_BOT_MODE`):

- `PR_BOT_MODE=1` — enables bot mode.
- `PR_BOT_REVIEWER=<gh-username>` — assign as the sole reviewer. Bypasses the top-contributor picker in `pr-3-get-metadata.sh`. Both `/pr` Phase 4 AND `pr-3-get-metadata.sh` honor this env var.
- `PR_BOT_TITLE="<title-body>"` — the PR title minus the `[Domain]` prefix.
- `PR_BOT_TITLE_PREFIX="<domain>"` — wraps as `[<Domain>]`.
- `PR_BOT_BODY_CONTENT_FILE=/abs/path.md` — contents spliced into the `## What changed` block instead of the human-driven bucket dialogue.
- `PR_BOT_RISK_LEVEL=low|medium|high` — used verbatim in the `## Risk Level` block.
- `PR_BOT_AUTO_FIX_SEVERITY=""` (default) — comma-separated severities the Phase 2 cold review auto-fixes. Default is empty (info-only), so all findings are logged into the PR body and left for the human reviewer. Set to e.g. `HIGH` to opt into auto-application. **Warning**: auto-fixes are committed and force-pushed without re-running the caller's typecheck / build / smoke gate (Phase 1 and Phase 3 are skipped in bot mode). Opt in only if you accept that the fixup can ship on stale verification evidence.
- `PR_BOT_PRIMARY_LABEL=<label>` — primary domain label to apply (e.g. `eng`, `april-db`, `catalina-re`). If unset, no primary label is applied and the caller is expected to apply labels post-hoc. `ci:*` labels are never inferred inside bot mode — the caller applies them itself.

Per-phase effect summary:

| Phase | Behavior in bot mode |
|---|---|
| 0 | Skip branch-state actions (checkout, rebase, stash). Caller has arranged the branch and pushed. |
| 1 | Skip `pr-2-run-checks.sh`. Caller has typechecked and built. |
| 2 | Replace the "one concern at a time, fix or ignore?" loop with the auto-ignore policy above. Cold reviewer still runs; findings land in the PR body's Test Plan block. No auto-fix by default — opt in via `PR_BOT_AUTO_FIX_SEVERITY` if you accept the stale-verification tradeoff. |
| 3 | Skip entirely. Do NOT run the affected-tests detector or `autoRun` test areas — caller has already verified, and `ci:*` labels are the caller's responsibility. |
| 4 | Use `PR_BOT_REVIEWER`/`PR_BOT_TITLE`/`PR_BOT_TITLE_PREFIX`/`PR_BOT_BODY_CONTENT_FILE`/`PR_BOT_RISK_LEVEL`/`PR_BOT_PRIMARY_LABEL` to populate the summary. Skip "Ready to submit?" — proceed straight to Phase 5. |
| 5 | Use `gh api` (not `gh pr edit`) for reviewer/assignee/labels — `gh pr edit` silently drops metadata under the GraphQL Projects-Classic deprecation. |

Each phase below carries a `**Bot mode:** ...` note at the interactive-decision points.

## Phase 0: Understand Intent & Git State

**Bot mode:** skip this phase entirely. The caller (a scheduled skill like `dep-vuln-fix`) has already set up its own worktree, made its commits, and pushed. Do NOT run branch-state investigation, `git rebase`, stash pops, or branch creation. Assume the current branch is the correct one and its remote counterpart already exists (Phase 5 will update-in-place). Skip straight to Phase 2.

**Your job:** Gather ALL relevant context before taking action. Be thorough and investigative. Think deeply about what the user is trying to accomplish.

### Gather Initial Context

As a starting point, run the investigation script and the metadata script **in parallel**:

```bash
~/.claude/skills/pr/scripts/pr-1-investigate.sh [pr-url]
```

```bash
~/.claude/skills/pr/scripts/pr-3-get-metadata.sh    # in background
```

The investigation script provides the initial report (branch, status, commits, PR context). The metadata script (codeowners, labels, recent contributors) runs in the background so results are ready by Phase 4.

**If the investigation script fails (exits non-zero), STOP THE WORKFLOW.**

1. Show the user the specific failure message from the script
2. Help them fix the issue (e.g., "Install gh from https://cli.github.com/, then run `gh auth login`")
3. Tell them to run `/pr` again after fixing
4. **DO NOT attempt to proceed without these tools**. The workflow cannot function correctly without them.

Once prerequisites pass, the script provides an initial report including current branch, git status, recent commits, PR context, etc.

**However:** This is just a starting point. Think about what additional information you might need:

- Do you need to see the actual diff to understand scope?
- Should you read specific files that changed?
- Do you need to check other branches or PRs?
- Is there context in commit messages or PR descriptions you should examine more closely?

Use additional tools as needed to fully understand the situation.

### Analyze & Reason

With the information gathered (from the script and any additional investigation), think deeply about:

1. **User Intent**

   - PR URL provided? What does that signal?
   - Text explanation provided? Parse for intent signals ("update", "new", "separate", etc.)
   - Nothing provided? Infer from git state and PR context

2. **Relationships**

   - Do the uncommitted changes relate to an existing PR (current branch or provided URL)?
   - **Check branch commits**: If on a feature branch, do uncommitted changes relate to what's already committed on that branch? (See "Branch Commits vs master" in investigation report)
   - Is the user on master/production but referencing a specific PR? (might want to move changes there)
   - Is the user on a feature branch but changes seem unrelated to that PR?
   - Are there conflicting signals that need clarification?

3. **Best Action**
   - What's the most logical next step given all the context?
   - Do you need to switch branches, stash/unstash, create new branch, or stay put?

### Decision Making

**If intent is unambiguous** from investigation → State your reasoning briefly and proceed

Example: _"You're on `rpavlovs/fix/imports` with open PR #3424 about import fixes. Your uncommitted pr.md changes appear in the PR diff. Proceeding to add and review these changes for PR #3424..."_

**If ambiguous** → Present options with full context

Example: _"You're on `rpavlovs/fix/imports` which has merged PR #3424 (import fixes). You have new changes to pr.md (unrelated scope). Options:_

- _(a) Create new PR branching from master with pr.md changes_
- _(b) Re-use this branch for new PR (will need force push)_

_Which approach?"_

**Principle:** Don't ask questions you can answer yourself through investigation. Only present choices when genuinely ambiguous.

### Execute Branch Actions

**Before proceeding to Phase 1, handle any branch-related actions** identified in your analysis:

- If on master/production → create appropriate feature branch
- If changes unrelated to current branch → switch/create branch
- If on a non-master branch whose name is off-convention (common in worktrees) → offer to rename it (see "Off-convention existing branch" below)
- If need to stash/unstash → do it now

**Branch naming (when creating new branch):**

- Get first name from investigation report's "Git User" section (e.g., "Roman" from "Roman Pavlovskyi")
- Branch format: `<first-name>/<type>/<short-desc>`
- Types: `feature` | `fix` | `chore` | `cleanup`

**Off-convention existing branch (worktree case):**

Branch creation only runs when you're on master/production. If you started from a worktree or otherwise pre-created your branch, `/pr` would otherwise keep whatever name it has — including auto-generated names like `claude/elegant-almeida-3a08b7` or a Vibe Kanban name — because Phase 0 never renames an existing branch. Close that gap:

Only rename a branch that has NOT been pushed yet — a local-only rename is clean, while renaming a branch that already exists on the remote would strand the old remote branch (and any PR pointing at it). So this only fires at first-PR-creation time, before Phase 5 pushes.

When the current branch is NOT master/production, its name does NOT already match `<first-name>/<type>/<short-desc>` (types `feature` | `fix` | `chore` | `cleanup`), AND it does not yet exist on the remote. Gate on the remote ref itself, not on upstream config: the branch is eligible only when `git ls-remote --exit-code --heads origin <branch>` finds nothing. A missing upstream in "Remote Tracking Status" is just a hint — a branch pushed with `git push origin HEAD` (no `-u`) has no upstream yet still exists on `origin`, and renaming it would strand that remote branch and any PR pointing at it.

1. **Propose a conventional name** built from the Git User first name, the type inferred from the changeset (`fix` for bug fixes, else `feature`/`chore`/`cleanup`), and a short kebab-case description of the diff.
2. **Ask before renaming** (`Rename <old> → <new>? (y/n)`) unless in bot mode. On yes: `git branch -m <new-name>`. In bot mode, never rename — keep the caller's branch as-is.

If the branch is already pushed, or the name already matches the convention, keep it and move on.

### Handle Stale Branch

If the investigation report shows "BRANCH IS STALE" in the Branch Freshness section:

1. **Inform the user:** "Your branch is N commits behind origin/master. Rebasing now..."
2. **Rebase automatically:**
   ```bash
   git rebase origin/master
   ```
   - If conflicts occur, help resolve them
   - Note: Push will happen in Phase 5 (use `--force-with-lease` if branch was already pushed)

### Create Dynamic TODO List

After investigation completes, branch actions are handled, and you understand the changeset, create a TODO list using `todo_write`:

```
- [ ] Phase 1: Automated checks
- [ ] Phase 2: Cold sub-agent review (spawn reviewer, walk through concerns)
- [ ] Phase 3: Testing validation
- [ ] Phase 4: Reviewer & final approval
- [ ] Phase 5: Submit (auto: commit, push, create PR, assign, label)
```

**For infrastructure changes,** add: `Phase 2E: Infrastructure safety check`

After creating the todo list, proceed to Phase 1.

## Phase 1: Automated Checks

**Bot mode:** skip `pr-2-run-checks.sh`. The caller has already run typecheck + build + affected tests as part of its own verification loop before invoking `/pr`. Skip the CLAUDE.md adherence dialogue too — for bot PRs, carry `CLAUDE.md: followed` into the PR body unconditionally (a scheduled skill's diff has already been vetted by its own author-time checks).

Run the quality checks script:

```bash
~/.claude/skills/pr/scripts/pr-2-run-checks.sh
```

This provides the diff, type checks, and code quality baseline.

**Your job: Think critically about what else needs checking.**

Don't just accept the script output. Ask yourself:

- What files need deeper inspection?
- What domain-specific risks apply? (DB migrations, API contracts, auth changes, data integrity)
- What should be tested or validated before this goes to production?
- Does the diff follow `CLAUDE.md` and the task-routed `agent-docs/` guidance, especially the simplicity rules, comments bar, TypeScript style, Prisma rules, Mastra dynamic-import rule, and testing policy?

Use whatever tools and checks are necessary to be confident in this change.

### Agent Guidance Adherence Review

Do a strict pass against `CLAUDE.md` and the relevant `agent-docs/` files before Phase 2:

- Re-read `CLAUDE.md`, then follow its Task Router to the relevant `agent-docs/` files for the files touched; do not rely on memory.
- Check for unnecessary abstractions, single-use helpers, exported types never imported, stale comments, over-broad tests, raw `psql`, direct `void` Prisma calls, and static Prisma imports in Mastra dependency chains.
- If the change violates `CLAUDE.md` or a task-routed `agent-docs/` file, fix it before continuing or explicitly surface the tradeoff in the Phase 4 summary.
- Carry a short result into the PR body: `CLAUDE.md: followed` or `CLAUDE.md: exception: <one-line reason>`.

## Phase 2: Deep Review & Critique (cold sub-agent)

**The code review here is performed by a freshly started agent that has NO memory of this coding session. This is what keeps it unbiased.** "Cold" means exactly that: a new agent, started from scratch, with no shared context. It is not a named reviewer or a persona. It runs as either a `codex exec` run or a cold sub-agent (chosen in Step 2). You (the `/pr` orchestrator) do NOT review the code yourself in this phase. You run the reviewer, then walk the developer through its findings in batches (see Step 3).

### Step 1: Previously-ignored concerns (in-session memory)

Memory is **in-session**. You (the orchestrator) hold it in your own context. On the FIRST review of this run there are none. If you re-spawn the reviewer later in this same run (after applying fixes), pass it the concerns the developer already chose to **ignore** so it doesn't re-raise them. Nothing is persisted between separate `/pr` runs.

### Step 2: Run the cold reviewer (Codex if configured, else native sub-agent)

Both paths run the SAME review spec (`.claude/agents/pr-reviewer.md`) and emit the SAME output format, so Step 3 is identical either way. Pick the engine first:

```bash
command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1 && echo CODEX_AVAILABLE || echo CODEX_UNAVAILABLE
```

- `CODEX_AVAILABLE` (the `codex` CLI is installed and authenticated) → use **Step 2A (`codex exec`)**.
- `CODEX_UNAVAILABLE` → use **Step 2B (native sub-agent)**.

If the orchestrator is Codex itself, the check always lands on Step 2A. The fresh `codex exec` child is the "clean, no-context invocation" the Invocation Notes call for, so it serves as the cold reviewer. Step 2B (the native `Agent`-tool sub-agent) only applies under a Claude Code orchestrator that has no `codex`.

#### Step 2A: Codex cold review (barebones `codex exec`)

Refresh `origin/master` FIRST, in the orchestrator. The `codex exec` review runs read-only and cannot write `.git/FETCH_HEAD`, so a fetch inside it would fail and leave the reviewer diffing against a stale base. Then write the prompt (pointing Codex at the same `pr-reviewer.md` spec) and run Codex non-interactively and read-only. Substitute the Step 1 ignored list (or `NONE`):

```bash
# Stop if the refresh fails; otherwise the review diffs a stale base and can hide conflicts.
git fetch origin +refs/heads/master:refs/remotes/origin/master || { echo "Failed to refresh origin/master" >&2; exit 1; }

# Per-run temp dir so concurrent /pr runs (other worktrees/terminals) can't clobber each other.
REVIEW_DIR=$(mktemp -d /tmp/pr-codex-review.XXXXXX)

cat > "$REVIEW_DIR/prompt.txt" <<'EOF'
You are a cold, independent code reviewer with NO context on this change.
Read `.claude/agents/pr-reviewer.md` and follow it EXACTLY: its rules, what to check, and its output format including the final `VERDICT:` line.

Review the change set on this branch against master:
- `origin/master` has ALREADY been refreshed for you. Do NOT run `git fetch` (this review is read-only and cannot write to .git).
- DIFF_BASE=$(git merge-base origin/master HEAD), then `git diff "$DIFF_BASE"` (includes uncommitted changes, but NOT brand-new untracked files).
- Also run `git ls-files --others --exclude-standard` and read every untracked file it lists; Phase 5 will commit those too, so they are part of this change set.
- Read each changed file IN FULL plus the code it calls into. Read `CLAUDE.md`, follow its Task Router to relevant `agent-docs/` files, and audit adherence.

Do NOT re-raise these previously-ignored concerns unless this change reintroduced them:
<the Step 1 ignored list, or NONE>

Output ONLY the concern blocks and the final VERDICT line. No preamble, no closing summary.
EOF

codex exec --sandbox read-only --skip-git-repo-check --model gpt-5.5 \
  -c model_reasoning_effort=high \
  --output-last-message "$REVIEW_DIR/out.txt" \
  - < "$REVIEW_DIR/prompt.txt" > "$REVIEW_DIR/review.log" 2>&1
STATUS=$?              # capture Codex's exit code before later commands overwrite $?
# Treat empty output as failure even when Codex exits 0, so the fallback below is driven by the exit code.
[ -s "$REVIEW_DIR/out.txt" ] || { echo "Codex produced no review output" >&2; exit 1; }
cat "$REVIEW_DIR/out.txt"
exit $STATUS
```

Run this as a single **blocking** Bash call (set a generous timeout, e.g. `900000` ms, because the review takes a few minutes), exactly like waiting on a sub-agent. The final `cat` prints the concern blocks + `VERDICT:` line in the shared `pr-reviewer.md` format; carry them into Step 3 unchanged. The call exits with Codex's own status, so a non-zero exit reliably signals failure. (If you need to debug, the full Codex log is at `$REVIEW_DIR/review.log`.)

If `codex exec` exits non-zero or the output file is empty, tell the user Codex failed, then fall back to **Step 2B**. Codex may report fewer findings than the Step 2B sub-agent (its agent loop tends to stop early even with an exhaustive prompt). That is a known tradeoff of this path.

**First round only.** This full-scope, `model_reasoning_effort=high` invocation is for the first review round. When Step 3 fixes trigger a re-review, use the incremental re-review block in Step 3 instead — it scopes the prompt to the fix delta and drops to `model_reasoning_effort=medium`. Never use `codex exec resume` for re-review rounds: a resumed session remembers its previous analysis, so it is no longer cold.

#### Step 2B: Cold sub-agent (Agent tool)

Use the Agent tool:

```
subagent_type: "pr-reviewer"
description: "Cold review of <branch>"
prompt: |
  Review the change set on this branch against master.
  - Base: origin/master (run `git fetch origin +refs/heads/master:refs/remotes/origin/master` first, because local `master` is often many commits stale). Compute `DIFF_BASE=$(git merge-base origin/master HEAD)`, then run `git diff "$DIFF_BASE"` (it includes uncommitted changes without base-only noise from a stale branch); read each changed file IN FULL plus the code it calls into.
  - Also run `git ls-files --others --exclude-standard` and read every untracked file it lists; `git diff` skips brand-new files, but Phase 5 will commit them, so they are part of this change set.
  - Re-read `CLAUDE.md`, follow its Task Router to the relevant `agent-docs/` files for the changed files, and explicitly audit adherence. Check simplicity/refactoring-pass expectations, TypeScript style, comments, tests, Prisma rules, Mastra dynamic imports, and critical restrictions. Treat violations in `CLAUDE.md` or the routed `agent-docs/` files as review findings unless the diff clearly documents a justified exception.
  - Previously-ignored concerns: do NOT re-raise these unless this push materially changed that code:
    <paste the Step 1 list, or "NONE">
  Apply `CLAUDE.md`, the relevant `agent-docs/` files, and `.claude/agents/pr-reviewer.md` rules. If the root contract or routed guidance is violated, raise it as a normal concern. Keep the `.claude/agents/pr-reviewer.md` output format exactly as-is, including its normal VERDICT line.
```

### Step 3: Walk the developer through the concerns IN BATCHES (fix / ignore)

Parse the reviewer's concern blocks into an ordered list (highest severity first).

**If there is at least one concern, snapshot the pre-fix working tree NOW — before anything edits it, in bot mode too.** Fixes land in the working tree before Phase 5 commits anything (and the developer may hand-edit files mid-walk), so `HEAD` cannot serve as the re-review's "before" point. The command below builds a git tree of the current state — tracked AND untracked files, `.gitignore` respected — without touching the real index. Note the printed SHA as `PRE_FIX_TREE`; every later review round that surfaces concerns re-runs this same command to refresh it.

```bash
# Temp index lives OUTSIDE the repo so `git add -A` can't sweep it into the snapshot.
# rm first: git gets a missing path ("no index yet"), not the 0-byte file mktemp made.
SNAP_INDEX=$(mktemp /tmp/pr-snap-index.XXXXXX) &&
rm -f "$SNAP_INDEX" &&
GIT_INDEX_FILE="$SNAP_INDEX" git read-tree HEAD &&
GIT_INDEX_FILE="$SNAP_INDEX" git add -A &&
GIT_INDEX_FILE="$SNAP_INDEX" git write-tree &&
rm -f "$SNAP_INDEX"
```

**Bot mode:** DO NOT prompt the developer. For each concern, decide automatically:
- If the concern's severity is in `PR_BOT_AUTO_FIX_SEVERITY` (default `""` → nothing auto-fixed) → apply the reviewer's suggested fix in this session and count as `fixed`.
- Otherwise → count as `ignored` and append a one-line entry `{severity, file:line, one-line-title}` to an in-memory `bot_ignored_concerns` list.
- After processing all concerns: if any fixes were applied, re-run the cold reviewer ONCE **in incremental mode** with the ignored list carried forward — identical mechanic to the human loop: snapshot `POST_FIX_TREE`, validate the delta (delta-validation step below; if it fails, use the full medium-effort fallback), and feed it via the "Incremental re-review" block below. **The re-run is verify-only: if it raises NEW concerns, do NOT auto-fix them — count them as ignored and log them for the PR body.** An auto-fix here would ship with no verification pass behind it, since no further re-run follows. Do not iterate more than one re-run.
- **Why default off**: auto-applied fixes are committed + force-pushed without re-running Phase 1 (typecheck) or Phase 3 (tests). The PR body's verification evidence would then reflect the PRE-fix commit, not what actually shipped. Keeping auto-fix off makes cold review information-only in bot mode — the human reviewer sees the ignored concerns in the Test Plan block and decides.
- Carry `X fixed, Y ignored` forward to Phase 4. The Y-ignored details must be rendered under Test Plan in the PR body so a human can audit which concerns the bot chose to skip. Format:
  ```
  - /pr cold review (codex, bot mode) on <sha>: X fixed, Y ignored.
    Ignored concerns (auto, severity below PR_BOT_AUTO_FIX_SEVERITY):
      • [MEDIUM] path/to/file.ts:42 — one-line title
      • [LOW]    path/to/other.ts:17 — one-line title
  ```
  If Y=0, omit the "Ignored concerns" sub-block.

Skip the rest of Step 3 (the interactive walk) below when in bot mode — the incremental re-review blocks still apply; proceed to Phase 3 after the re-run settles.

- If the verdict is `VERDICT: LGTM` (no concerns), tell the user "Cold review: no concerns" and proceed to Phase 3.
- Otherwise, present the concerns **in batches of up to 5 per message** (highest severity first), then **end your turn and wait** for the developer's decisions on that whole batch before showing the next. Follow it exactly:
  1. Show **up to 5** concerns in one message (fewer only if fewer remain), then **end your turn and wait.** Do NOT show the next batch until the developer has decided every concern in the current one. Do NOT dump all `N` at once when `N > 5`.
  2. Render EACH concern in the batch like a GitHub inline comment — point at the line, show the offending code, then the detail:

     ```
     Concern <i>/<N>  ·  [SEVERITY]  ·  <file>:<line>

         <the exact offending line(s) of code, indented>

     <title>: <what's wrong, what breaks, and the concrete fix>
     ```

     Close the batch with a single prompt: **"For each — fix or ignore?"**
  3. The developer replies with one decision per concern (e.g. `1 fix, 2 ignore, 3 fix, 4 fix, 5 ignore`). Record each; re-ask only the ones left ambiguous. Then present the NEXT batch (again ≤5) and wait. Repeat until every concern has a decision.

  Batch size is a ceiling, not a target: 3 concerns → one message of 3; 12 concerns → 5, then 5, then 2. Neither dump-everything nor drip-one-at-a-time.

When every concern has a decision:
- **Apply the "fix" concerns now, in this session** (use the reviewer's suggested fix), counting each as fixed. Do NOT stop and tell the dev to re-run. Keep going.
- **If you applied any fixes,** re-run the SAME engine you used in Step 2 once to verify — **in incremental mode, not another full review**. Run the snapshot command again and note the new SHA as `POST_FIX_TREE`, then produce and validate the fix delta BEFORE invoking either engine (substitute both SHAs):

  ```bash
  DELTA_FILE=$(mktemp /tmp/pr-fix-delta.XXXXXX)
  if ! git diff "<PRE_FIX_TREE>" "<POST_FIX_TREE>" > "$DELTA_FILE" || [ ! -s "$DELTA_FILE" ]; then
    echo "Fix delta missing or empty — do NOT run the incremental review; use the full-review fallback" >&2
  else
    echo "delta OK: $DELTA_FILE"
  fi
  ```

  Feed the reviewer that validated delta, the FULL original concern blocks just fixed (so it can verify them against the real failure, not a one-line title), and the **ignored** concerns from your memory (so it doesn't re-raise them) — use the engine-matching block below. Every re-review round is still a fresh, cold agent; it just reads the fixes instead of the whole change set. **Fallback:** if `PRE_FIX_TREE` was never captured, the diff command fails, or the delta file is empty, run a full Step 2A/2B review for that round instead — at `model_reasoning_effort=medium` on Codex. Never skip re-verification, and never start an incremental review without a validated non-empty delta.
- Walk any new concerns it surfaces the same way (batched, ≤5 per message). If they lead to more fixes, repeat the cycle — the snapshot taken when those concerns arrived is the new `PRE_FIX_TREE` — until nothing is left to fix.
- Carry the review engine and running counts (`X fixed, Y ignored`) forward to the PR body. This is the human-facing evidence that the cold review ran; keep it in the description instead of posting a separate PR comment.

#### Incremental re-review — Codex engine (re-runs of Step 2A)

Same mechanics as Step 2A — fresh `REVIEW_DIR`, one blocking Bash call with a generous timeout, empty output falls back to the sub-agent block — but no `git fetch` (the delta is purely local), the prompt scoped to the fix delta, and `model_reasoning_effort=medium`. Requires the validated `DELTA_FILE` from the step above. Substitute the delta path and the two placeholder lists:

```bash
REVIEW_DIR=$(mktemp -d /tmp/pr-codex-review.XXXXXX)

cat > "$REVIEW_DIR/prompt.txt" <<'EOF'
You are a cold, independent code reviewer with NO context on this change.
Read `.claude/agents/pr-reviewer.md` and follow it EXACTLY: its rules, what to check, and its output format including the final `VERDICT:` line.

INCREMENTAL RE-REVIEW: the full change set on this branch already passed a cold review; the author then applied targeted fixes. Review ONLY the fix delta at the end of this prompt — do NOT diff against master or re-review the rest of the change set.

- Read IN FULL the current version of every file the delta touches.
- Read each original concern's location and the execution or configuration path needed to verify its fix — these files may be OUTSIDE the fix delta.
- For any externally used contract or behavior the delta changes — functions, schemas, exported types, API payloads, config keys, constants, database fields, CLI flags — search its references repo-wide and read the relevant consumers, even when their files are outside the fix delta.
- Verify each complete original concern below is now correctly and completely fixed; re-raise any that is not. (The code shown in each block is the PRE-fix code.)
<paste the FULL original concern blocks decided "fix" this round — header, offending code, and explanation, exactly as the previous review emitted them>
- Do NOT re-raise these previously-ignored concerns unless the delta reintroduced them:
<the Step 1 ignored list, or NONE>
- Raise any NEW problem the fix delta introduces, including in consumers you read outside it. Parts of the branch unrelated to these fixes are out of scope — they already passed the full review.

Output ONLY the concern blocks and the final VERDICT line. No preamble, no closing summary.

Fix delta (pre-fix → current, unified diff):
EOF
cat "<DELTA_FILE>" >> "$REVIEW_DIR/prompt.txt"

codex exec --sandbox read-only --skip-git-repo-check --model gpt-5.5 \
  -c model_reasoning_effort=medium \
  --output-last-message "$REVIEW_DIR/out.txt" \
  - < "$REVIEW_DIR/prompt.txt" > "$REVIEW_DIR/review.log" 2>&1
STATUS=$?
[ -s "$REVIEW_DIR/out.txt" ] || { echo "Codex produced no review output" >&2; exit 1; }
cat "$REVIEW_DIR/out.txt"
exit $STATUS
```

#### Incremental re-review — sub-agent engine (re-runs of Step 2B)

No effort knob exists for the sub-agent engine; the savings come from delta scoping alone.

```
subagent_type: "pr-reviewer"
description: "Incremental re-review of <branch>"
prompt: |
  INCREMENTAL RE-REVIEW: the full change set on this branch already passed a cold review; the author then applied targeted fixes. Review ONLY the fix delta below — do NOT `git fetch`, diff against master, or re-review the rest of the change set.
  - Read IN FULL the current version of every file the delta touches.
  - Read each original concern's location and the execution or configuration path needed to verify its fix — these files may be OUTSIDE the fix delta.
  - For any externally used contract or behavior the delta changes — functions, schemas, exported types, API payloads, config keys, constants, database fields, CLI flags — search its references repo-wide and read the relevant consumers, even when their files are outside the fix delta.
  - Verify each complete original concern below is now correctly and completely fixed; re-raise any that is not. (The code shown in each block is the PRE-fix code.)
    <paste the FULL original concern blocks decided "fix" this round — header, offending code, and explanation, exactly as the previous review emitted them>
  - Previously-ignored concerns: do NOT re-raise these unless the delta reintroduced them:
    <paste the Step 1 list, or "NONE">
  - Raise any NEW problem the fix delta introduces, including in consumers you read outside it. Parts of the branch unrelated to these fixes are out of scope — they already passed the full review.
  Apply `CLAUDE.md`, the relevant `agent-docs/` files, and `.claude/agents/pr-reviewer.md` rules. Keep the `.claude/agents/pr-reviewer.md` output format exactly as-is, including its normal VERDICT line.
  Fix delta (pre-fix → current, unified diff):
  <paste the contents of the validated DELTA_FILE>
```

**Do not proceed to Phase 3 until every concern has a decision (fixed or ignored), and all "fix" concerns have been applied and re-verified.**

### Phase 2E: Infrastructure safety check (only if the change touches `infrastructure/`)

Skip this unless the change set modifies infrastructure (Terraform). When it does:

- **Blast radius & rollback:** state what resources change and how to undo them.
- **Shared Terraform (`infrastructure/azure/shared/`):** plan/apply is manual (not CI). Confirm `terraform plan` was run and reviewed. If the plan has **0 destroys**, `terraform apply` may be run directly; if it shows **any destroy**, stop and get explicit human approval before apply. **Do NOT submit until you have confirmation that plan/apply succeeded**. This is a CLAUDE.md Critical Restriction that the `/pr` workflow enforces.
- **App envs (`april/*`, `multitenant/*`):** CI/CD applies on merge. Do NOT apply locally, and never apply against `production`.

## Phase 3: Testing Validation

**Bot mode:** skip the entire phase. The caller has already run its own verification (typecheck, build, UI smoke, affected tests). Do NOT invoke the affected-tests detector, do NOT execute `autoRun` test areas from `test-area-config.ts`, do NOT run the per-test todo dialogue. `ci:*` labels are the caller's responsibility (applied post-hoc via REST — dep-vuln-fix does this in its Phase 5e). Re-running affected tests here duplicates the caller's work AND pollutes the PR body with unrelated LLM/DB flakiness that has nothing to do with the diff. No screenshots dialogue either; if the caller populated `/tmp/ui-test/<branch>/`, Phase 5 will still upload them.

**Use dynamic TODO items to verify testing one change at a time.**

### Step 1: Identify What Needs Testing

**Copy-only / non-logic changes skip test authoring.** If the diff is purely string literals, wording, labels, or comments with no behavioral change, record "No tests needed — copy-only change" and move on. Do not add or expand a test to assert exact UI copy, and do not treat an existing fixture that merely carries the reworded string as needing an update. (See `agent-docs/TESTING.md`.)

Analyze the changes and create specific test TODO items. Each **distinct change, feature, or behavior** gets its own test todo:

- Multiple file changes that are part of one logical change = one test todo
- Focus on testable behaviors, not individual files
- Include edge cases and failure scenarios as separate test items
- For docs: test examples, verify links work
- Be specific about what aspect is being tested

**Use `todo_write` with `merge: true` to add test todos to the existing list.**

Example test todos:

```
- [ ] Test: ts-dedent named imports work in Node ESM (covers 58 files)
- [ ] Test: Scripts don't open pager
- [ ] Test: Documentation examples can be run successfully
```

**Visual Documentation Check:**

Determine if screenshots would help reviewers understand the changes:

- ✅ Add screenshot todo for:
  - User-visible behavior changes (data display, formatting, aggregation)
  - UI components, layouts, or styling modifications
  - Error messages, notifications, or user feedback changes
  - Workflow changes users will experience
  - Before/after comparisons for behavior modifications
- ❌ Skip for:
  - Pure backend logic with no user-visible impact
  - Internal API changes
  - Refactoring without behavior changes
  - Infrastructure/config changes

If screenshots would help, add a specific screenshot todo with details on what to capture.

Example screenshot todo format:

```
- [ ] Screenshots: Capture before/after [describe what changed and what to show]
```

**Check for existing session screenshots first.** The `test-app-ui-locally` skill parks its screenshots at `/tmp/ui-test/<branch-name>/` (with `/` in the branch name replaced by `-`). Run:

```bash
UI_TEST_DIR="/tmp/ui-test/$(git branch --show-current | tr '/' '-')"
ls "$UI_TEST_DIR"/*.png 2>/dev/null | sort
```

If there are any, they're already proof of the change working and belong in the PR body. You don't need a new screenshot todo. Remember them for Phase 5 (Submit) where they get uploaded + embedded.

### Step 2: Go Through Each Test TODO One-by-One

For each test todo (mark as `in_progress`):

1. **Verify the test:**

   - **If you already ran and observed the test:** State what you observed and mark complete. Don't ask the user to confirm what you already saw.
   - **If you need information you don't have:** Ask specifically: "How did you test [specific change]?" Wait for response.

2. **Evaluate the response:**

   - **If response implicitly covers multiple tests:** Mark all covered todos as `completed` at once
   - **If adequate for one test only:** Mark that todo as `completed`, move to next
   - **If insufficient:**
     - Probe deeper: "What about edge case X?"
     - Suggest specific test: "Try: `./script.sh --flag`"
     - **Wait for response, iterate on this same todo**
   - **If untested:** Suggest safe testing approach and wait

3. **Mark complete and continue:**
   - After response, mark all verified todos as `completed` in one update
   - Move to next uncompleted test todo

Before proceeding to Phase 4, ensure all test todos are discussed and have appropriate actions taken.

### Step 3: Affected Test Summary

Ask the user whether they already ran `/run-affected-tests` locally for this branch. If they have not, recommend running it now:

```bash
pnpm --filter @agmi/unified test:affected
```

If they choose not to run it, record the reason in `## Test Plan`. Do not silently omit this; the PR should say whether affected tests were run, skipped, or only summarized.

Run affected-test detection and keep the markdown for Phase 4/5:

```bash
pnpm --filter @agmi/unified exec tsx scripts/ci/run-affected-tests.ts --dry-run --json > /tmp/pr-affected-tests.json
pnpm --filter @agmi/unified exec tsx scripts/ci/run-affected-tests.ts --dry-run --markdown > /tmp/pr-affected-tests.md
```

Use this output to:

- Add detected `ci:*` labels from `/tmp/pr-affected-tests.json` to the Phase 4 summary alongside the primary label.
- Apply only detected labels that exist in the GitHub label list from `pr-3-get-metadata.sh`; list missing labels in the PR body/test plan instead of passing nonexistent labels to `gh`.
- Add the affected-test summary to `## Test Plan` in the PR body.
- Preserve any full/smoke/skip recommendations or decisions in the PR description.

**Org-setup validation (replaces the old CircleCI guard).** If the affected areas include **`org-setup`** (the diff touches a tenant router, dashboard, the trpc registry, or an org migration), run the **`/verify-new-org`** skill now, as part of `/pr`:

- Its deterministic pass is a **hard gate** — do not submit until it exits 0 (it catches the credential-leak / cross-tenant / migration classes).
- Its LLM audit is advisory — surface findings for judgment.
- Record the result in `## Test Plan` (e.g. `verify-new-org: green` or the violations found).

This is the only PR-time trigger for org validation; it intentionally does not run on unrelated PRs and is not a CircleCI job.

Also review whether the maintained affected-test fields need updates:

- test docblocks: `@ci-area` and repo-relative `@covers` on runnable metadata files (`*.test.ts`, `*.test.tsx`, `runner.ts`, `cli.ts`)
- covered paths: update `@covers` when source files move or tests start protecting different product or package code
- `apps/unified/scripts/ci/test-area-config.ts` for new/renamed area slugs, measured timings, local area commands, and smoke commands
- `outOfScopePrefixes` in `apps/unified/scripts/ci/detect-test-areas.ts` for detector exclusions
- detector metadata file patterns if runnable tests start using a new metadata-bearing filename

GitHub labels are derived as `ci:<slug>`; do not maintain a separate area-label list in this command. If the detector reports missing `@ci-area`, missing `@covers`, unknown area, stale cover, or invalid cover metadata, use `/update-test-area-tags` or patch the relevant docblock before continuing.

## Phase 4: Reviewer & Final Approval

**Bot mode:** consume env vars instead of soliciting developer input. Bot mode does NOT expect a `pr-3-get-metadata.sh` background result — Phase 0 was skipped, so no background run exists. All metadata comes from env vars; `ci:*` labels come from the caller post-hoc.

- **Reviewer**: use `PR_BOT_REVIEWER` directly (the `pr-3-get-metadata.sh` reviewer picker is bypassed anyway — see the script's own bot-override at the top). Do NOT map through nicknames; the env var is already a GitHub username.
- **Title**: assemble as `[$PR_BOT_TITLE_PREFIX] $PR_BOT_TITLE`. If `PR_BOT_TITLE_PREFIX` is unset, use `$PR_BOT_TITLE` verbatim. If `PR_BOT_TITLE` is unset, fall back to the caller's default title from the branch's most-recent commit message.
- **Body**: use the standard `/pr` body template. Where the human path asks the developer for `## What changed` buckets, splice the raw contents of `PR_BOT_BODY_CONTENT_FILE` into that section. All other sections (`Why this PR exists`, `Reviewer guide`, `Test Plan`, `CLAUDE.md`, `Risk Level`, `Screenshots`) are auto-filled: use the caller's commit context for `Why`, "No special focus area" for `Reviewer guide` unless the caller supplied one, the cold-review summary for `Test Plan` (skip the affected-tests markdown — Phase 3 didn't run one in bot mode; the caller's own Verification section in the body file already covers what was tested), `CLAUDE.md: followed` for `CLAUDE.md`, `PR_BOT_RISK_LEVEL` for `Risk Level`, and the standard screenshot-upload logic for `Screenshots`.
- **Label**: apply `PR_BOT_PRIMARY_LABEL` if set; otherwise apply no primary label (the caller will). `ci:*` labels are never inferred here — the caller applies them post-hoc via REST after `/pr` returns. Skip label-existence dialogue.
- **Present the summary**: skip. The bot has no one to present to. Log the resolved metadata to stderr for debugging, then proceed directly to Phase 5.

### Step 1: Determine Reviewer

Use the metadata results from the background `pr-3-get-metadata.sh` run (started in Phase 0). If the background run hasn't completed, wait for it now.

**Reviewer Assignment Logic:**

The script uses a two-tier approach:

1. **Primary (Git History)**: Picks the top contributor to the changed files in the last 3 months (excluding the PR author and bot accounts in `EXCLUDED_REVIEWERS`). Domain expertise is the primary signal.

2. **Fallback (Repo Collaborators)**: If no git history contributors exist (new files, no recent changes), fetches repo collaborators from GitHub API, excludes the PR author and bot accounts, and picks the collaborator with the fewest open reviews (load balancing).

Bot accounts (e.g. `bex-novo`) are blacklisted via the `EXCLUDED_REVIEWERS` array at the top of `pr-3-get-metadata.sh`. Add new bots there.

The script outputs a **suggested reviewer**. Use this unless the user specifies otherwise. Inform the user: "Reviewer: @X (top contributor)" or "Reviewer: @X (load balanced)"

**When the user specifies a reviewer by name (e.g., "send to marcho"):**

- Do NOT assume the GitHub username matches the name. Names are often nicknames or partial names.
- Look up the actual GitHub username from the repo collaborators list (from `pr-3-get-metadata.sh` output or `gh api repos/{owner}/{repo}/collaborators`).
- Match the user's input to the closest collaborator username (e.g., "marcho" → `@acomarcho`, "zain" → `@zainsarfraz`).
- Confirm the resolved username in the summary.

### Step 2: Present Summary

Present a single summary so the user can see what is being submitted:

- **Commit message** (proposed)
- **PR title** (proposed)
- **Reviewer**: @X
- **Label**: Y (chosen from metadata output based on changed files)
- **Affected-test metadata**: reviewed / updated / not applicable
- **PR body plan**: why this exists, bucketed changes, walkthrough if applicable, reviewer guide, test plan, CLAUDE.md note
- **Cold review summary**: `<engine> on <short sha>: X fixed, Y ignored` (or `LGTM, 0 fixed, 0 ignored`), to be included in the PR body after the final commit SHA exists
- **Detected CI labels**: existing `ci:*` labels from `/tmp/pr-affected-tests.json`
- **Missing CI labels**: detected `ci:*` labels that do not exist yet
- **Affected-test run**: ran / not run, with result or skip reason
- **Risk level**: 🟢/🟡/🔴 (classified below)

After presenting the summary, proceed directly to Phase 5 — do not ask "ready to submit?" or wait for approval. If the user interjects with adjustments (commit message, title, reviewer, label), apply them and continue.

### Risk Classification (for the summary above)

- 🟢 **STP (Straight to Production)**: Typos, CSS, non-logic fixes, docs, Claude commands
- 🟡 **Review Needed**: Standard feature work
- 🔴 **Detailed Review Needed**: DB Migrations, Auth, Payments, Core Infrastructure

### PR Title & Description (for the summary above)

   - **Title**: `[Domain] <Concise Title>`
   - **Body quality bar**:
     - Treat the body as a readable digest, not a code dump and not a second code review.
     - Prefer readable completeness over brevity. Do not compress away context that would help a reviewer understand the gap, behavior change, or decision.
     - Keep the structure easy to scan, but do not omit useful sections just because the diff is small.
     - Write in plain English for a reviewer with no prior context. Avoid internal shorthand unless it is defined.
     - Explain why this PR exists: what gap it closes, why the gap matters, and why this approach was chosen.
     - Group the work into 2-4 buckets when the diff has multiple parts. Call out new things introduced separately from existing things modified.
     - Add a one-line glossary only when unavoidable jargon would block understanding.
     - If the PR improves a process, workflow, or domain behavior, include a short walkthrough. Prefer a concrete case walkthrough when it makes the behavior easier to understand. Make the before/after difference clear.
     - Include a short reviewer guide with known risks, important files, or "nothing special" if there is no focused review area. Do not paste the cold review findings.
     - Include the cold review summary as a compact line in `## Test Plan`, because it is validation evidence. Use the actual engine (`codex` or `subagent`), the final short commit SHA after Phase 5 commits, and counts from Phase 2, for example: ``- `/pr` cold review (codex) on `abc1234`: 2 fixed, 0 ignored.`` If the reviewer was clean, write: ``- `/pr` cold review (codex) on `abc1234`: LGTM, 0 fixed, 0 ignored.``
     - Do not post the cold review summary as a separate PR comment. Keep PR comments for actual review discussion so low-comment PRs stay low-comment.
     - Include a short CLAUDE.md adherence note from Phase 1.
   - **Body format depends on branch type**:

**For fix branches** (branch name contains `/fix/`):

   - `## Why this PR exists` - Plain-English problem, impact, and gap being closed
   - `## What changed` - 2-4 buckets; include "New" vs "Modified" inside the buckets when useful
   - `## Walkthrough` - Required for process, workflow, or domain-behavior changes. Keep it short; use a concrete case walkthrough when helpful, and make the before/after behavior difference clear.
   - `## Reviewer guide` - Focus areas, known risks, important files, or "No special focus area"
   - `## Test Plan` - _Actual_ tests performed (from Phase 3 dialogue) plus the affected-test summary from `/tmp/pr-affected-tests.md`
   - `## CLAUDE.md` - Short adherence note: `followed` or `exception: <reason>`
   - `## Risk Level` - Explicitly state the risk level determined above
   - `## Screenshots` (if applicable) - If `test-app-ui-locally` session screenshots exist at `/tmp/ui-test/<branch>/`, embed them inline via the upload step in Phase 5. Otherwise include a short descriptive placeholder ("Dashboard showing X", "Claim detail after Y edit") that the user can replace via GitHub UI.

**For feature/chore/cleanup branches**:

   - High-level summary paragraph (no header) - Start with a single sentence overview of what this PR does and why
   - `## Why this PR exists` - Plain-English gap, impact, and decision rationale
   - `## What changed` - 2-4 buckets; include "New" vs "Modified" inside the buckets when useful
   - `## Walkthrough` - Required for process, workflow, or domain-behavior changes. Keep it short; use a concrete case walkthrough when helpful, and make the before/after behavior difference clear.
   - `## Reviewer guide` - Focus areas, known risks, important files, or "No special focus area"
   - `## Test Plan` - _Actual_ tests performed (from Phase 3 dialogue) plus the affected-test summary from `/tmp/pr-affected-tests.md`
   - `## CLAUDE.md` - Short adherence note: `followed` or `exception: <reason>`
   - `## Risk Level` - Explicitly state the risk level determined above
   - `## Screenshots` (if applicable) - If `test-app-ui-locally` session screenshots exist at `/tmp/ui-test/<branch>/`, embed them inline via the upload step in Phase 5. Otherwise include a short descriptive placeholder ("Dashboard showing X", "Claim detail after Y edit") that the user can replace via GitHub UI.

## Phase 5: Submit (Automatic)

**This phase runs without user interaction.** All decisions were made in Phase 4.

**Bot mode:** the caller has typically already committed and pushed the branch before invoking `/pr`. In that case the initial `git add` / `git commit` / `git push` steps below become no-ops (nothing staged). Phase 5 detects the branch is already at the remote tip and enters update-mode. **Do NOT use `gh pr edit` for reviewer/assignee/labels** — the GraphQL Projects-Classic deprecation makes it silently drop metadata even when it exits 0. Use `gh api PATCH /repos/{owner}/{repo}/pulls/<num>` for the body, `gh api POST /repos/{owner}/{repo}/pulls/<num>/requested_reviewers` for the reviewer, `gh api POST /repos/{owner}/{repo}/issues/<num>/assignees` for the assignee, and `gh api POST /repos/{owner}/{repo}/issues/<num>/labels` for labels. Verify each with a follow-up `gh api GET`. If the caller passed no ready commits (e.g. the cold review's auto-fix loop produced new changes not yet committed), Phase 5 commits those with a follow-up "cold-review fixup" commit and force-pushes.

1. **Commit and Push**:

   - `git add <files>`
   - `git commit -m "<message>"`
   - Push with appropriate flags:
     - First push: `git push -u origin HEAD` (sets upstream tracking)
     - Subsequent pushes: `git push origin HEAD`
     - After rebase/amend: `git push --force-with-lease origin HEAD`

2. **Upload session screenshots (if any)**:

   If `test-app-ui-locally` left screenshots at `/tmp/ui-test/<branch>/`, run the helper script that ships with that skill. It uploads every PNG to `novoaishared/internal-workspace/ui-test-screenshots/<slug>/` and prints ready-to-paste markdown (each image wrapped in a long-lived Azure Blob SAS URL, expiry `9999-12-31`) on stdout.

   ```bash
   ./.claude/skills/test-app-ui-locally/upload-screenshots.sh > /tmp/pr-screenshots.md
   ```

   Splice the contents of `/tmp/pr-screenshots.md` into the `## Screenshots` section of the PR body before submitting. If the script exits non-zero (no `az` login, missing key access, upload failure), fall back to the placeholder behavior. Don't block the PR on image upload. Exit code 0 with empty stdout means "no screenshots found, nothing to attach, carry on".

   Note: the SAS URLs only work as long as `novoaishared`'s account key is valid. The storage lives at `internal-workspace/ui-test-screenshots/<slug>/` and is never auto-cleaned.

3. **Create or Update PR**:

   Before creating or updating the PR, make sure `<body>` / `<updated-body>` includes the cold review summary in `## Test Plan` using the post-commit value of `git rev-parse --short HEAD`. If an existing PR body already has a `/pr cold review` line from an earlier run, replace that line with the latest run instead of appending another one.

   **IF Create Mode:**

   ```bash
   gh pr create \
     --base master \
     --head $(git symbolic-ref --short HEAD) \
     --title "<title>" \
     --body "<body>" \
     --reviewer <reviewer-username> \
     --assignee @me \
     --label <primary-label> \
     --label <detected-ci-label>  # repeat for each detected ci:* label
   ```

   **IF Update Mode:**

   - The push already updated the PR

   - Check and ensure PR metadata is set:

     ```bash
     gh pr view <pr-url> --json reviewRequests,assignees,labels
     ```

     If missing reviewer/assignee/labels, set them:

     ```bash
     gh pr edit <pr-url> \
       --add-reviewer <reviewer-username> \
       --add-assignee @me \
       --add-label <primary-label> \
       --add-label <detected-ci-label>  # repeat for each detected ci:* label
     ```

   - To update PR description:
     - Run: `gh api -X PATCH "/repos/novoai/mono/pulls/<pr-number>" -f body="<updated-body>"`
       - **Important:** Use `gh api` instead of `gh pr edit` because `gh pr edit` fails with exit code 1 due to GraphQL deprecation errors (Projects Classic field)
       - Extract `<pr-number>` from PR URL (e.g., #3767 from https://github.com/novoai/mono/pull/3767)

4. **Enable auto-merge for STP PRs**:

   If the Phase 4 risk classification is 🟢 **STP**, set the PR to auto-merge after creating or updating it:

   ```bash
   gh pr merge <pr-number-or-url> --squash --auto --delete-branch
   ```

   If branch protection still requires checks or review, this queues the PR to merge once GitHub permits it. For 🟡 or 🔴 PRs, do not enable auto-merge unless the user explicitly asks.

5. **Verify the cold review summary is in the PR description**:

   Before reporting success, confirm the submitted PR body contains the Phase 2 cold review summary in `## Test Plan`:

   ```bash
   gh pr view <pr-number-or-url> --json body --jq '.body'
   ```

   The line must include the engine used (`codex` or `subagent`), `git rev-parse --short HEAD`, and the final counts (`X fixed, Y ignored`, or `LGTM, 0 fixed, 0 ignored`). If it is missing, patch the PR body with `gh api` as described above. Do not use `gh pr comment` for this summary.

6. **Open PR & Report**:

   - Open in browser: `open "<pr-url>"` (macOS) or `xdg-open "<pr-url>"` (Linux)
   - Show the PR URL and a summary of what was done (committed, pushed, PR created/updated, reviewer assigned, label applied)
   - If the body still has screenshot placeholders (step 2 skipped or gist upload failed), mention they can be filled in via GitHub UI

7. **Important**: Do NOT delete the local branch (review is ongoing)
