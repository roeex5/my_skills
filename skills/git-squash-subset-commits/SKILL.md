---
name: git-squash-subset-commits
description: Use when reviewing local git history to squash small fix, noise, or follow-up commits into their parent feature commits before pushing or sharing a branch.
---

# Git Squash Subset Commits

## Overview

Safely squash noise commits into their logical parents using the **file-subset rule** as the safety constraint — never on topic or message similarity alone.

**Core principle:** Commit A can only be squashed into earlier commit B if every file touched by A is also touched by B. Thematic grouping is not enough.

## The File-Subset Rule

```
files(A) ⊆ files(B)   →   safe to squash A into B
files(A) ⊄ files(B)   →   STOP, do not squash
```

**Why this matters:** Squashing on topic alone (e.g. "both are about GCP credentials") is unsafe. A test file and an implementation file are different files. Absorbing the test commit into the impl commit silently changes the scope of that commit.

## Helper Scripts

Scripts in this skill directory implement the deterministic checks from Steps 1–3. Use them when available — they save tokens and eliminate manual reasoning errors. The numbered steps below remain the authoritative description of what needs to happen; the scripts are accelerators, not replacements.

**Verify scripts are executable (one-time check):**
```bash
ls -la ~/.claude/skills/git-squash-subset-commits/*.sh
# All scripts should show -rwxr-xr-x. If not:
# chmod +x ~/.claude/skills/git-squash-subset-commits/<script>.sh
```

**Scripts must be run from within the target repository** (any subdirectory works). Every `git` command inherits `$PWD` and walks up to find `.git` — the script's location in `~/.claude/skills/` is irrelevant.

### `find-pairs.sh` — Full scan (covers Steps 1–3)

```bash
~/.claude/skills/git-squash-subset-commits/find-pairs.sh                          # uses @{u}, max-distance=10
~/.claude/skills/git-squash-subset-commits/find-pairs.sh origin/main              # explicit base
~/.claude/skills/git-squash-subset-commits/find-pairs.sh origin/main -m 20        # look back up to 20 commits
~/.claude/skills/git-squash-subset-commits/find-pairs.sh --max-distance 5         # short lookback
```

O(m·N) scan over local-only commits, where N is the commit count and m is the max lookback distance (default 10). For each commit A, only the m nearest earlier commits are considered as candidate parents B — noise commits are almost always adjacent to their logical parent, so the default covers all practical cases. Delegates all safety checks to `check-pair.sh`. Run this first — pairs it reports are already verified.

### `check-pair.sh` — Single-pair check (covers Steps 2–3)

```bash
~/.claude/skills/git-squash-subset-commits/check-pair.sh <sha-A-noise> <sha-B-parent>
```

Runs all three checks for a specific pair and prints a clear SAFE / UNSAFE verdict:
1. Merge commit check — rejects immediately if any merge commit exists between B and A
2. File-subset rule — lists any files in A that are absent from B
3. Intermediate conflict check — lists any commits between B and A that touch A's files

Exit 0 = SAFE, proceed to Steps 4–6. Exit non-zero = reject the pair.

## Process

### Step 1 — Survey local-only commits

Only squash commits that haven't been pushed to a remote. Use `find-pairs.sh` or list manually:

```bash
git log @{u}..HEAD --oneline
# Or if not tracking: git log origin/<branch>..HEAD --oneline
```

Identify candidate pairs: noise messages ("DONE", "path edits", "fix typo"), bare `.gitignore` commits, single-file amendments.

**All squash candidates must be in the local-only range.** Do not squash commits already on the remote.

### Step 2 — Check the file-subset rule

Use `check-pair.sh` or run manually for every candidate pair (squash A into B):

```bash
git diff-tree --no-commit-id -r --name-only <A>
git diff-tree --no-commit-id -r --name-only <B>
```

Every file in A's output must appear in B's output. If not — reject the pair.

### Step 3 — Check for merge commits and intermediate conflicts

Use `check-pair.sh` or run manually.

**First: check for merge commits between B and A.**

```bash
git log --oneline --merges <B>..<A>
```

If any merge commit appears — **reject the pair unconditionally.** Rebasing across a merge commit drops the merge topology by default (unless `--rebase-merges`, which is a different, more complex operation). Do not squash across a merge boundary.

**Second: check for intermediate commits that touch A's files.**

```bash
git log --oneline <B>..<A> -- <shared-file>
```

If any intermediate commit appears — reordering would cause a conflict. **Reject the pair or choose the other reorder direction.**

### Step 4 — Choose reorder direction

Two ways to bring A and B adjacent:

| Direction | When safe |
|---|---|
| Move A earlier (toward B) | No intermediate commit touches any of A's files |
| Move B later (toward A) | No intermediate commit touches any of B's files, AND no intermediate commit depends on B's output |

Check both; pick the safe direction. If neither is safe — reject the pair.

### Step 5 — Create backup and execute the rebase

Create a backup branch **before touching history**:

```bash
git branch backup/<branch-name>-$(date +%Y%m%d)
```

Then build and execute the rebase todo:

```bash
cat > /tmp/rebase-todo.sh << 'SCRIPT'
#!/bin/zsh
cat > "$1" << 'EOF'
pick <sha-B> parent commit
fixup <sha-A> noise commit
...
EOF
SCRIPT
chmod +x /tmp/rebase-todo.sh
GIT_SEQUENCE_EDITOR="/tmp/rebase-todo.sh" git rebase -i <earliest-affected-parent>^
```

- Use `fixup` to keep B's message (silent discard of A's message)
- Use `fixup -C <sha-A>` to keep A's message instead (requires Git 2.32+)
- Do **not** use `--root`; always rebase from a specific ancestor to avoid touching the root commit

### Step 6 — Verify, clean up, and push

**Do not delete the backup until you have confirmed the rebase produced the correct result.**

```bash
# 1. Confirm commit list looks right
git log --oneline @{u}..HEAD

# 2. Confirm content is identical to the backup
git diff backup/<branch-name>-<date>
```

`git diff` must produce **no output**. If it does, the rebase changed content — investigate before proceeding.

```bash
# 3. Only after a clean diff — force-delete the backup
#    (-D required: the backup's rewritten commits are not in the current branch's ancestry)
git branch -D backup/<branch-name>-<date>
```

**After deleting the backup, propose the push to the user — do not push without confirmation:**

> "History is clean. Ready to push `<branch-name>` to origin. Shall I go ahead?"

```bash
# 4. Push only after explicit user confirmation
git push origin <branch-name>
```

If the rebase went wrong, recover before deleting:

```bash
git reset --hard backup/<branch-name>-<date>
git branch -D backup/<branch-name>-<date>
```

## Common Mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| Squash commits already on remote | Rewriting shared history breaks other clones | Only squash commits in `@{u}..HEAD` range; check Step 1 |
| Skip backup branch before rebase | No recovery path if rebase goes wrong | Always create backup in Step 5 before executing |
| Squash based on topic, not files | Introduces new files into B's scope | Always run `diff-tree` for both commits |
| Merge commit exists between B and A | Rebase silently drops merge topology | Run `git log --merges <B>..<A>`; reject the pair if any result appears |
| Skip intermediate conflict check | Rebase conflict mid-run | Run `git log <B>..<A> -- <file>` before reordering |
| Squash test-only commit into impl-only commit | Test file appears in an implementation commit | Reject; test commits need a target that also touches tests |
| Move A earlier past a commit that shares A's files | Conflict during rebase | Check the other direction, or skip |
| Using `--root` | Risk of rewriting the root commit unintentionally | Always anchor to a specific commit with `<sha>^` |
| Squash `.gitignore` commit into a commit that doesn't touch `.gitignore` | File-subset violation | `.gitignore` commits can only absorb into other `.gitignore`-touching commits |
| Delete backup branch before verifying with `git diff` | No recovery path if content silently changed | Run `git diff backup/<name>` first; delete only on empty output |
| Delete backup after a non-empty `git diff` | Destroys safety net while rebase result is suspect | Investigate the diff; recover with `git reset --hard backup/<name>` instead |
| Using `git branch -d` to delete backup | Fails — rebased commits are not in the backup branch's ancestry | Always use `git branch -D` for backup branches |

## Example

```
# Noise commits to squash — generic scenario:
# a1b2c3 DONE               → touches docs/plan.md
# d4e5f6 fix typo in config  → touches config/settings.yml
# 7890ab update .gitignore   → touches .gitignore

# Candidate: a1b2c3 → e3f4a5 (feat: add planning doc, touches docs/plan.md)
git diff-tree --no-commit-id -r --name-only a1b2c3   # → docs/plan.md
git diff-tree --no-commit-id -r --name-only e3f4a5   # → docs/plan.md
# ✓ subset — safe to squash

# Candidate: d4e5f6 → b7c8d9 (feat: add config loader, touches config/settings.yml)
git diff-tree --no-commit-id -r --name-only d4e5f6   # → config/settings.yml
git diff-tree --no-commit-id -r --name-only b7c8d9   # → config/settings.yml, src/loader.py
# ✓ subset — safe (d4e5f6's files ⊆ b7c8d9's files)

# Reject: 7890ab → b7c8d9 (feat: add config loader — does NOT touch .gitignore)
git diff-tree --no-commit-id -r --name-only 7890ab   # → .gitignore
git diff-tree --no-commit-id -r --name-only b7c8d9   # → config/settings.yml, src/loader.py
# ✗ not subset — .gitignore not in target — reject

# Reject: fix-tests-commit (tests/test_api.py) → feat-commit (src/api.py only)
# ✗ different files entirely — reject even though both relate to "the API feature"
```
