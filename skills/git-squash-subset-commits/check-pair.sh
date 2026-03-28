#!/bin/zsh
# Usage: ./check-pair.sh <sha-A-noise> <sha-B-parent>
# Checks whether commit A can be safely squashed into commit B.
# Runs: merge-commit check, file-subset rule, intermediate-conflict check.

set -euo pipefail

A=${1:-}
B=${2:-}

if [[ -z "$A" || -z "$B" ]]; then
    echo "Usage: $0 <sha-A-noise> <sha-B-parent>"
    echo "  sha-A: the noise/fix commit you want to squash"
    echo "  sha-B: the earlier parent commit to absorb A into"
    exit 1
fi

# Resolve to full SHAs
A=$(git rev-parse --verify "$A" 2>/dev/null) || { echo "ERROR: Cannot resolve commit A: $1"; exit 1; }
B=$(git rev-parse --verify "$B" 2>/dev/null) || { echo "ERROR: Cannot resolve commit B: $2"; exit 1; }

files_A=($(git diff-tree --no-commit-id -r --name-only "$A"))
files_B=($(git diff-tree --no-commit-id -r --name-only "$B"))

echo "=== Commits ==="
echo "A (noise):  $(git log -1 --format='%h %s' "$A")"
echo "B (parent): $(git log -1 --format='%h %s' "$B")"
echo ""
echo "=== Files in A ==="
printf '  %s\n' "${files_A[@]}"
echo ""
echo "=== Files in B ==="
printf '  %s\n' "${files_B[@]}"
echo ""

# --- Merge commit check ---
echo "=== Merge Commit Check ==="
merges=$(git log --oneline --merges "${B}..${A}^" 2>/dev/null || true)
if [[ -n "$merges" ]]; then
    echo "REJECT — merge commit(s) exist between B and A:"
    echo "$merges" | sed 's/^/  /'
    echo ""
    echo "Rebasing across a merge boundary silently drops merge topology."
    echo "Result: UNSAFE — do not squash this pair."
    exit 1
fi
echo "PASS — no merge commits between B and A."
echo ""

# --- File-subset rule ---
echo "=== File-Subset Rule ==="
not_in_B=()
for f in "${files_A[@]}"; do
    if ! (( ${files_B[(Ie)$f]} )); then
        not_in_B+=("$f")
    fi
done

if [[ ${#not_in_B[@]} -gt 0 ]]; then
    echo "REJECT — file-subset rule violated."
    echo "These files are in A but NOT in B:"
    printf '  %s\n' "${not_in_B[@]}"
    echo ""
    echo "Result: UNSAFE — do not squash this pair."
    exit 1
fi
echo "PASS — all files in A are also in B."
echo ""

# --- Intermediate conflict check: moving A toward B ---
echo "=== Intermediate Conflict Check (moving A toward B) ==="
# Commits strictly between B and A (exclusive of both)
between=$(git log --oneline "${B}..${A}^" 2>/dev/null || true)
conflict=0
for f in "${files_A[@]}"; do
    hits=$(git log --oneline "${B}..${A}^" -- "$f" 2>/dev/null || true)
    if [[ -n "$hits" ]]; then
        echo "CONFLICT on '$f':"
        echo "$hits" | sed 's/^/  /'
        conflict=1
    fi
done

if [[ $conflict -eq 0 ]]; then
    echo "PASS — no intermediate commit touches A's files."
    echo ""
    echo "Result: SAFE to squash A into B."
else
    echo ""
    echo "Result: UNSAFE to move A directly next to B."
    echo "Consider the reverse direction: check if B can be moved forward toward A,"
    echo "or reject this pair."
fi
