# My Claude Skills
*Created: 2026-03-28*

Personal Claude Code configuration — skills, hooks, and plugins. Structured to mirror `~/.claude/` for straightforward deployment.

## Structure

```
my_skills/
├── skills/       # Custom skills (~/.claude/skills/)
├── hooks/        # Event-driven automation (~/.claude/hooks/)
└── plugins/      # Bundled plugins (~/.claude/plugins/)
```

## Installing a Skill

Copy or symlink the skill directory into `~/.claude/skills/`:

```bash
# Copy
cp -r skills/git-squash-subset-commits ~/.claude/skills/

# Or symlink (changes here reflect immediately)
ln -s $(pwd)/skills/git-squash-subset-commits ~/.claude/skills/git-squash-subset-commits
```

## Skills

| Skill | Description |
|---|---|
| [git-squash-subset-commits](skills/git-squash-subset-commits/SKILL.md) | Safely squash noise commits into parent feature commits using the file-subset rule |

## Adding a New Skill

Follow the [superpowers:writing-skills](https://agentskills.io) authoring guide. Each skill lives in its own subdirectory under `skills/` with at minimum a `SKILL.md`.
