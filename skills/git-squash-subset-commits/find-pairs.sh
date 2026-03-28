#!/bin/zsh
# Usage: ./find-pairs.sh [upstream-ref]
# Scans all local-only commits and suggests safe squash pairs.
# For each commit A, checks every earlier local commit B as a potential target.
# Delegates all safety checks to check-pair.sh (merge boundary, file-subset, intermediate conflicts).

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
CHECK_PAIR="${SCRIPT_DIR}/check-pair.sh"

if [[ ! -x "$CHECK_PAIR" ]]; then
    echo "ERROR: check-pair.sh not found or not executable at ${CHECK_PAIR}"
    exit 1
fi

if [[ -n "${1:-}" ]]; then
    UPSTREAM="$1"
else
    UPSTREAM='@{u}'
fi

# Verify we are inside a git repository.
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: Not inside a git repository."
    echo "Run this script from within the target repo."
    exit 1
fi

# Oldest-first so index j < index i means B is an ancestor of A.
if ! commits=($(git log "${UPSTREAM}..HEAD" --format="%H" --reverse 2>/dev/null)); then
    echo "ERROR: Cannot compute local commits against upstream '${UPSTREAM}'."
    echo "If the branch has no remote tracking, pass the base ref explicitly:"
    echo "  ./find-pairs.sh origin/main"
    exit 1
fi

if [[ ${#commits[@]} -eq 0 ]]; then
    echo "No local-only commits found."
    exit 0
fi

n=${#commits[@]}
total=$(( n * (n - 1) / 2 ))

echo "Scanning ${n} local commit(s) — ${total} pair(s) to check..." >&2

# Progress bar: width 40, printed to stderr so stdout stays clean.
_progress() {
    local checked=$1 total=$2
    local percent=$(( total > 0 ? checked * 100 / total : 100 ))
    local filled=$(( percent * 40 / 100 ))
    local bar=""
    for (( k=0; k<filled; k++ ));  do bar+="#"; done
    for (( k=filled; k<40; k++ )); do bar+="-"; done
    printf "\r  [%s] %3d%%  (%d/%d)" "$bar" "$percent" "$checked" "$total" >&2
}

found=0
checked=0

# Outer loop: A is the noise/fix commit (later in history, higher index).
for (( i=2; i<=n; i++ )); do
    A="${commits[$i]}"

    # Inner loop: B is the candidate parent (earlier in history, lower index).
    for (( j=1; j<i; j++ )); do
        B="${commits[$j]}"
        (( ++checked )) || true
        _progress "$checked" "$total"

        # Delegate all three checks to check-pair.sh; suppress its output.
        if "$CHECK_PAIR" "$A" "$B" > /dev/null 2>&1; then
            short_A=$(git log -1 --format="%h" "$A")
            msg_A=$(git log -1 --format="%s" "$A")
            files_A=($(git diff-tree --no-commit-id -r --name-only "$A"))
            short_B=$(git log -1 --format="%h" "$B")
            msg_B=$(git log -1 --format="%s" "$B")

            printf "\n" >&2   # drop below the progress bar before printing a pair
            echo "SAFE PAIR:"
            echo "  squash: ${short_A}  \"${msg_A}\"  [${files_A[*]}]"
            echo "   into:  ${short_B}  \"${msg_B}\""
            echo ""
            (( ++found ))
        fi
    done
done

printf "\n" >&2   # newline after final progress bar

if [[ $found -eq 0 ]]; then
    echo "No safe squash pairs found among local commits."
else
    echo "---"
    echo "${found} safe pair(s) found."
fi
