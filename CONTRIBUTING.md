# Contributing

This is my personal skills collection, so I'm not looking for new skills from
others here. Fixes are welcome: broken instructions, unclear steps, a script that
fails on your platform, or a skill that misfires on the wrong task.

## Working on a skill

Skills live in `skills/<name>/`. Each needs a `SKILL.md` whose `name` matches its
directory:

```markdown
---
name: my-skill
description: What this does and when the agent should reach for it.
---

# My Skill

Instructions for the agent.
```

The `description` is all an agent sees before deciding whether to load the skill,
so it must name both the capability and the triggers. "Formats code" tells an
agent nothing about when to use it; "Use when the user asks to format, lint, or
clean up code style" does.

Keep the instructions imperative and specific. A skill is read by an agent
mid-task, not by a person browsing docs, so front-load what to do and cut
background it doesn't need.

## Before opening a PR

```bash
./scripts/validate.sh
./scripts/sync-readme.sh
```

`validate.sh` checks frontmatter, that names match directories, that the plugin
manifest is in sync, and scans for secrets and hardcoded home paths.
`sync-readme.sh` regenerates the skills table in the README from disk. Both run
in CI, along with a check that the `skills` CLI can still discover every skill.

If you add or rename a skill, update the `skills` array in
`.claude-plugin/marketplace.json` too — `validate.sh` will fail until you do.

## Publishing checklist

Everything here is public the moment it's pushed. Before committing a skill,
read it for:

- absolute paths containing your home directory
- credentials, tokens, or API keys
- internal hostnames, dashboard URLs, or private repository details
- customer names, ticket contents, or anything else non-public

`validate.sh` catches the common shapes of these. It is a backstop, not a
substitute for reading the diff.
