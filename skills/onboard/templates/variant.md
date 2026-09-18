---
name: onboard-ORG_SLUG
description: Onboard onto one ORG_NAME task by reading the live source before implementation. Use when the user says onboard, asks to be brought up to speed on any ORG_NAME ticket, issue, PR, or doc, or wants a task explained before code is written.
---

# Onboard ORG_NAME

Build a source-backed, plain-language understanding of one ORG_NAME task. Read-only:
do not edit tickets, code, PRs, data, or deployments unless the user explicitly asks
afterward.

## 1. Start from the live surface

Require a concrete surface: ticket, PR, issue, doc, or exact identifier. If none is
present, ask for it and stop.

Read the live source before inspecting any code:

<!-- FILL: systems. One line per system this org actually uses, naming the exact
tool to read it. Delete the rows that do not apply. For example:

- **Jira** (`ACME`, `PLAT` project keys): fetch through the Atlassian MCP. If auth
  is stale, report the failure and ask the user to reauthenticate.
- **GitHub**: use `gh` against `acme/platform`. Fetch body, changed files, commits,
  checks, review state, and unresolved review threads.
- **Notion**: use the Notion MCP. Do not access Notion through a browser.
- **Slack**: use the Slack MCP when the task points there.
-->

If a tool is missing or authentication is stale, report the exact failure and what
the user needs to do. Stop at the auth boundary; do not substitute a browser, a web
search, or your own memory. Keep the live source as the source of truth and
distinguish source facts from inference.

## 2. Establish the task contract

Extract the exact title, then identify:

- the user-visible or operational problem
- current behavior versus desired behavior
- why the change matters, and to whom
- acceptance criteria, examples, screenshots, or linked evidence
- explicit non-goals, dependencies, owners, and unresolved decisions
- linked tickets, PRs, dashboards, or docs needed to understand the task

Follow linked sources through the matching tool before tracing implementation.

## 3. Trace the implementation surface

<!-- FILL: repositories. Name the primary repository or repositories and where they
are checked out locally, so the agent does not have to search for them. For example:

Work from the existing checkout of `acme/platform`. Ask the user for the path if no
checkout is present. The API lives in `services/api`, the web client in `apps/web`.
-->

Search from product terms, identifiers, routes, feature flags, dashboard names, API
names, ticket examples, and PR filenames. Trace the smallest end-to-end path:

1. where the behavior enters the system
2. where the relevant permission, routing, rendering, validation, or transformation
   happens
3. where the result is persisted, displayed, emitted, or sent downstream
4. which tests, checks, or review comments currently protect that path

Preserve dirty local work unless edits are explicitly requested. For PR review
follow-up, re-fetch the live head and review threads before drawing conclusions.

<!-- FILL: conventions. Optional. Anything specific worth encoding — a non-standard
base branch, a required review step, a codeowners quirk, a service that always needs
checking alongside another. Delete this block if there is nothing. -->

## 4. Explain at the user's altitude

Lead with product behavior, then connect it to code:

1. **What this changes** — one short paragraph
2. **The current problem** — the concrete missing or failing flow
3. **How it works today** — a compact end-to-end walkthrough
4. **Where the change likely lives** — concrete files and modules, and why
5. **Boundaries or open questions** — only decisions that could change scope

Prefer flow and intent over a file inventory. If the user says "one by one", explain
one selected ticket or PR fully before moving to the next.

## 5. Stop before implementation

End with what is verified and what still needs to happen. Do not turn onboarding into
a fix plan unless the user asks for implementation next.
