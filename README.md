# samuelswandi/skills

My personal collection of agent skills. Skills are reusable instruction sets that
extend a coding agent — each one is a directory with a `SKILL.md` file that the
agent loads when the task matches its description.

Everything here follows the [Agent Skills specification](https://agentskills.io),
so the same skill works in Claude Code, Codex, Cursor, OpenCode, Kiro, and the
other agents the `skills` CLI supports.

## Install

Install every skill in this repo:

```bash
npx skills add samuelswandi/skills
```

See what's available before committing to anything:

```bash
npx skills add samuelswandi/skills --list
```

Install one skill:

```bash
npx skills add samuelswandi/skills --skill pr
```

Install globally (available in every project) to a specific agent, without prompts:

```bash
npx skills add samuelswandi/skills --skill pr -g -a claude-code -y
```

Try a skill without installing it:

```bash
npx skills use samuelswandi/skills@pr | claude
```

By default `npx skills add` installs into the current project (`.claude/skills/`
for Claude Code) and symlinks each agent to a single canonical copy. Add `-g` for
your home directory instead, or `--copy` if symlinks don't work on your setup.

Later, pull in my updates:

```bash
npx skills update
```

## Skills

<!-- skills:start -->
| Skill | Description |
| ----- | ----------- |
| [`comms`](skills/comms/) | Communication and collaboration preferences covering how to write for the user, explain technical detail precisely, surface assumptions, handle unknowns, and make verification claims. Use when drafting or editing any user-facing prose — replies, progress updates, explanations, PR and ticket descriptions, commit messages, documents — and when deciding how much depth an answer needs, whether to ask or assume, or what a passing check actually proves. |
| [`logbook`](skills/logbook/) | Create and maintain a persistent logbook for work that spans multiple iterations or sessions. Use for investigations, prompt tuning, architecture changes, performance work, or handoffs where exact results and decisions must survive context compaction. Resume an existing logbook when given its path. |
| [`onboard`](skills/onboard/) | Build a source-backed understanding of one task before implementing it — read the live ticket, PR, or doc first, trace the code path, then explain the product behavior, scope, and open questions. Use when the user says onboard, asks to be onboarded or brought up to speed on a ticket, Jira issue, Linear issue, GitHub PR, Notion doc, or bug report, or wants a task explained before any code is written. On first use in a new organization, generates a customized onboard-<org> skill wired to that org's own systems. |
| [`pr`](skills/pr/) | Use when opening, updating, submitting, or preparing a GitHub pull request from Claude or Codex in this repository, especially when the user asks for /pr, $pr, or the PR workflow. |
<!-- skills:end -->

`comms` is the one worth borrowing if you take nothing else. It's how I want an
agent to write and reason with me: answer the question first, match depth to what
was asked, say what you actually verified rather than what you hope is true, and
raise a weak assumption instead of agreeing with it. It pairs with
[`humanizer`](https://github.com/blader/humanizer), which handles the editing
pass:

```bash
npx skills add samuelswandi/skills --skill comms -g
npx skills add blader/humanizer -g
```

Install it globally (`-g`) so it applies everywhere. If you'd rather have these
preferences always loaded instead of triggered on demand, put the contents in
your agent's instruction file (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`) — same
rules, different mechanism. As a skill it loads when the task looks like writing;
in an instruction file it's always in context.

`onboard` starts generic and specializes itself. The first time you use it, it
onboards you onto whatever you pointed it at, then offers to generate an
`onboard-<org>` skill wired to the systems it just used — your tracker, your
repositories, your docs. Accept and you get a second skill in
`~/.claude/skills/onboard-acme/` that already knows where to look, so later
sessions skip the discovery:

```bash
npx skills add samuelswandi/skills --skill onboard -g
```

The generic skill stays installed and keeps working for one-off tasks outside that
org. The variant lives only on your machine, since it encodes your project keys and
checkout paths — nothing about your setup comes back here.

## Layout

```
skills/
  <skill-name>/
    SKILL.md          # required: YAML frontmatter + instructions
    agents/           # optional: per-agent interface metadata
    scripts/          # optional: helper scripts the skill invokes
    templates/        # optional: files the skill generates from
```

`SKILL.md` needs `name` and `description` in its frontmatter:

```markdown
---
name: my-skill
description: What this does and when the agent should reach for it.
---

# My Skill

Instructions for the agent.
```

The `description` is the only thing an agent sees before deciding whether to load
the skill, so it should name both the capability and its triggers.

## Adding a skill

Scaffold one:

```bash
npx skills init skills/my-skill
```

Then validate and refresh the table above:

```bash
./scripts/validate.sh
./scripts/sync-readme.sh
```

Before pushing anything here, check it for hardcoded absolute paths, credentials,
internal hostnames, and anything else that shouldn't be public. `validate.sh`
catches the obvious cases; it isn't a substitute for reading the diff.

## License

[MIT](LICENSE)
