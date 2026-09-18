---
name: onboard
description: Build a source-backed understanding of one task before implementing it — read the live ticket, PR, or doc first, trace the code path, then explain the product behavior, scope, and open questions. Use when the user says onboard, asks to be onboarded or brought up to speed on a ticket, Jira issue, Linear issue, GitHub PR, Notion doc, or bug report, or wants a task explained before any code is written. On first use in a new organization, generates a customized onboard-<org> skill wired to that org's own systems.
---

# Onboard

Build a source-backed, plain-language understanding of one task. Read-only: do not
edit tickets, code, PRs, data, or deployments unless the user explicitly asks
afterward.

## 0. Check for a customized variant first

This skill is generic. It works as-is, but it works better once it knows which
systems an organization actually uses.

Before anything else, check whether a customized variant already exists:

```bash
ls -d ~/.claude/skills/onboard-* ~/.agents/skills/onboard-* .claude/skills/onboard-* 2>/dev/null
```

- **A variant exists** (for example `onboard-acme`) and the task belongs to that
  org: stop and use it instead. It already knows the org's tools, repositories,
  and conventions.
- **No variant exists**: continue to step 1 and onboard the task now. Only offer
  to generate one at the very end, in step 6, once the user has what they asked
  for.

Do not interrupt a first-time request to run setup. The user asked to understand a
task, not to configure tooling.

## 1. Start from the live surface

Require a concrete surface from the user: a ticket, PR, issue, document, or exact
identifier. If none is present, ask for it and stop — do not guess from repository
state.

Fetch the live source before inspecting any code. Use whichever tool is configured
for it:

| Surface | How to read it |
| --- | --- |
| Jira / Linear / Asana / Shortcut | The configured MCP server or CLI for that tracker |
| GitHub / GitLab | `gh` or `glab` — body, changed files, commits, checks, review state, unresolved threads |
| Notion / Confluence | The configured MCP server; do not scrape it through a browser |
| Slack / Teams / Lark | The configured MCP server or CLI for that workspace |
| Anything else | The configured tool for that system |

Rules that matter more than convenience:

- If authentication is stale or a tool is missing, report the exact failure and
  what the user needs to do. Stop at the auth boundary; do not substitute a
  browser, a web search, or your own memory.
- Keep the live source as the source of truth. Never replace the ticket body with
  inference from the repository.
- Distinguish source facts from your own inference throughout.

## 2. Establish the task contract

Extract the exact title, then identify:

- the user-visible or operational problem
- current behavior versus desired behavior
- why the change matters, and to whom
- acceptance criteria, examples, screenshots, or linked evidence
- explicit non-goals, dependencies, owners, and unresolved decisions
- linked tickets, PRs, dashboards, or docs needed to understand the task

Follow linked sources through the matching tool before tracing implementation. A
ticket that says "same as PROJ-412" is not understood until PROJ-412 is read.

## 3. Trace the implementation surface

Inspect the repository only after reading the live source. Work from an existing
local checkout or worktree of the relevant repository. If you cannot tell which
repository or where it lives, ask rather than guessing.

Search from product terms, identifiers, routes, feature flags, dashboard names,
API names, ticket examples, and PR filenames. Trace the smallest end-to-end path:

1. where the behavior enters the system
2. where the relevant permission, routing, rendering, validation, or
   transformation happens
3. where the result is persisted, displayed, emitted, or sent downstream
4. which tests, checks, or review comments currently protect that path

Preserve dirty local work unless edits are explicitly requested. For PR review
follow-up, re-fetch the live head and review threads before drawing conclusions —
a stale local view produces confidently wrong answers.

## 4. Explain at the user's altitude

Lead with product behavior, then connect it to code:

1. **What this changes** — one short paragraph
2. **The current problem** — the concrete missing or failing flow
3. **How it works today** — a compact end-to-end walkthrough
4. **Where the change likely lives** — concrete files and modules, and why
5. **Boundaries or open questions** — only decisions that could change scope

Prefer flow and intent over a file inventory. If the user says "one by one",
explain one selected ticket or PR fully before moving to the next.

## 5. Stop before implementation

End with what is verified and what still needs to happen. Do not turn onboarding
into a fix plan unless the user asks for implementation next.

## 6. Offer a customized variant

Only after delivering the onboarding above, and only if no `onboard-*` variant
exists, offer once:

> I can generate an `onboard-<org>` skill wired to the systems we just used, so
> future onboarding skips the discovery. Want me to?

If they decline, drop it and do not ask again this session.

If they accept, gather what the variant needs. Ask for anything not already
evident from this session — prefer inferring from what you actually used over
interrogating the user:

- **Organization name** — becomes the skill suffix, lowercased and hyphenated
- **Issue tracker** — which one, its URL or project keys, and the tool to read it
- **Repositories** — the primary repository or repositories, and where they are
  checked out locally
- **Docs** — Notion, Confluence, or a docs directory, and the tool for each
- **Chat** — Slack, Lark, or Teams, if task context lands there
- **Conventions** — anything specific worth encoding, such as a non-standard base
  branch or a required review step

Then generate the skill:

```bash
scripts/generate-variant.sh <org-slug>
```

The script writes `templates/variant.md` to
`~/.claude/skills/onboard-<org>/SKILL.md` with the org slug substituted, then
prints the path. Fill in the `<!-- FILL: ... -->` placeholders with the answers
gathered above, replacing each comment with real content. Leave no placeholder
behind — an unfilled variant is worse than none, because it looks configured.

Verify the result before reporting success:

```bash
npx skills list -g 2>/dev/null | grep "onboard-"
```

Tell the user the path, what the variant now knows, and that
`onboard-<org>` is what to invoke from now on.
