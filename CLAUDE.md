# Claude Instructions — my_skills
*Created: 2026-03-28*

This repo mirrors `~/.claude/` and holds personal Claude Code configuration.

## Structure

- `skills/` — each subdirectory is one skill with a `SKILL.md` and optional supporting scripts
- `hooks/` — event-driven shell scripts triggered by Claude Code events
- `plugins/` — bundled plugins (skills + hooks packaged together)

## When Creating or Editing Skills

Always follow the `superpowers:writing-skills` skill. Key rules:
- Skill name: letters, numbers, hyphens only
- Every skill needs `SKILL.md` with valid YAML frontmatter (`name`, `description`)
- Description starts with "Use when..." — triggering conditions only, no workflow summary
- Shell scripts in a skill directory must use `#!/bin/zsh` and be committed executable (`chmod +x`)

## Shell Scripts

- Use `#!/bin/zsh` (not bash)
- Avoid `${var:-default}` when `default` contains `{}` — use an explicit `if/else` instead
- Use `(( ++var ))` not `(( var++ ))` under `set -e` to avoid false exit on zero
