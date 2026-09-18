---
name: onboard-stx
description: Onboard the user to a StraitsX/Fazz engineering ticket, Jira issue, GitHub PR, or dashboard task by tracing the live source into the relevant xfers repository before implementation. Use when the user says onboard-stx, asks to onboard on an STX/Fazz/Jira/GitHub task, or wants the product behavior, code path, scope, and open questions explained first.
---

# Onboard STX

Build a source-backed, plain-language understanding of one STX/Fazz task. This is read-only: do not edit Jira, code, PRs, data, or deployments unless the user explicitly asks afterward.

## 1. Start From The Live Surface

Require the concrete surface from the user: Jira ticket, GitHub PR/issue, Slack/Lark context, or exact task identifier. If none is present, ask for it and stop.

Use the named live system before inspecting code:

- **Jira/Atlassian:** fetch the live ticket through the configured Jira/Atlassian MCP or CLI. If auth is stale, report the exact failure and ask the user to reauthenticate. Do not replace the ticket body with repo guesses.
- **GitHub:** use `gh` against the relevant repository, usually `payfazz/xfers`. Fetch the live PR/issue body, changed files, commits, checks, review state, and unresolved review threads when relevant.
- **Lark/Slack:** use the matching configured tool if the task points there. If access is blocked, stop at the auth boundary and state what is needed.
- **Other systems:** use the configured source tool. If no source tool is available, say which source is blocked; do not substitute memory or broad search.

Keep the live task as source of truth. Distinguish source facts from inference.

## 2. Establish The Task Contract

Extract the exact title and identify:

- the user-visible or operational problem
- current behavior versus desired behavior
- why the change matters
- acceptance criteria, examples, screenshots, or linked evidence
- explicit non-goals, dependencies, owners, and unresolved decisions
- linked tickets, PRs, dashboards, or docs needed to understand the task

Follow linked STX/Fazz sources through the matching tool before tracing implementation.

## 3. Trace The Implementation Surface

Inspect the repository only after reading the live source. Prefer an existing local checkout of the relevant repository, usually `payfazz/xfers`, or a current worktree of it. If no checkout is present, ask the user where it lives instead of guessing.

Search from product terms, identifiers, routes, feature flags, dashboard names, API names, ticket examples, and PR filenames. Trace the smallest end-to-end path:

1. where the behavior enters the system
2. where the relevant permission, routing, rendering, validation, or transformation happens
3. where the result is persisted, displayed, emitted, or sent downstream
4. which tests, checks, or review comments currently protect that path

Preserve dirty local work unless edits are explicitly requested. For PR review follow-up, re-fetch the live head and review threads before drawing conclusions.

## 4. Explain At The User's Altitude

Lead with product behavior, then connect to code:

1. **What this changes** - one short paragraph
2. **The current problem** - concrete missing or failing flow
3. **How it works today** - compact end-to-end walkthrough
4. **Where the change likely lives** - concrete files/modules and why
5. **Boundaries or open questions** - only decisions that could change scope

Prefer flow and intent over file inventory. If the user says one by one, explain one selected ticket or PR fully before moving to the next.

## 5. Stop Before Implementation

End with what is already verified and what still needs to happen. Do not turn onboarding into a fix plan unless the user asks for implementation next.
