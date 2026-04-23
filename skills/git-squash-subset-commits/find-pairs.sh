#!/bin/zsh
# Usage: ./find-pairs.sh [upstream-ref] [-m|--max-distance N]
# Scans local-only commits and suggests safe squash pairs.
# For each commit A, checks at most M earlier commits B (default M=10).
# Delegates all safety checks to check-pair.sh (merge boundary, file-subset, intermediate conflicts).

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
CHECK_PAIR="${SCRIPT_DIR}/check-pair.sh"

if [[ ! -x "$CHECK_PAIR" ]]; then
    echo "ERROR: check-pair.sh not found or not executable at ${CHECK_PAIR}"
    exit 1
fi

UPSTREAM='@{u}'
MAX_DISTANCE=10

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--max-distance)
            shift
            if [[ -z "${1:-}" || ! "$1" =~ ^[0-9]+$ ]]; then
                echo "ERROR: --max-distance requires a positive integer."
                exit 1
            fi
            MAX_DISTANCE="$1"
            shift
            ;;
        --max-distance=*)
            val="${1#*=}"
            if [[ -z "$val" || ! "$val" =~ ^[0-9]+$ ]]; then
                echo "ERROR: --max-distance requires a positive integer."
                exit 1
            fi
            MAX_DISTANCE="$val"
            shift
            ;;
        -*)
            echo "ERROR: Unknown option '$1'."
            echo "Usage: ./find-pairs.sh [upstream-ref] [-m|--max-distance N]"
            exit 1
            ;;
        *)
            UPSTREAM="$1"
            shift
            ;;
    esac
done

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
m=$MAX_DISTANCE

# Count pairs actually checked: for each A at index i, B ranges over max(1,i-m)..i-1.
total=0
for (( i=2; i<=n; i++ )); do
    (( total += (i-1 < m ? i-1 : m) )) || true
done

echo "Scanning ${n} local commit(s) — ${total} pair(s) to check (max-distance=${m})..." >&2

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
    # Only look back at most m commits to keep complexity O(m*N).
    for (( j = (i-m > 1 ? i-m : 1); j < i; j++ )); do
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
