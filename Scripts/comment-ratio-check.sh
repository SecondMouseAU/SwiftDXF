#!/usr/bin/env bash
# comment-ratio-check.sh: flag Swift files where comment lines outnumber code
# lines, as a signal for a human to look, not a fail.
#
# Part of the ecosystem's code-style policy rollout (SwiftDXF#13); see
# docs/code-style-policy-proposal-2026-08.md in the `ecosystem` repo for the
# full rationale, and OCCTSwiftScripts#114/#115 for the reference
# implementation this script is copied from. A high ratio is sometimes
# legitimate (a small function with several real caveats worth spelling out)
# and sometimes means a doc comment has drifted into restating design
# rationale that belongs in docs/ instead: this script surfaces the number,
# it doesn't judge which case it is. Report-only: always exits 0, since
# failing every file above a threshold on day one, in a codebase nobody has
# swept yet, punishes the report instead of the problem.
#
# Usage:
#   Scripts/comment-ratio-check.sh              # default threshold: 1.0
#   Scripts/comment-ratio-check.sh 1.5           # custom threshold
set -euo pipefail

threshold="${1:-1.0}"

[ -d Sources ] || { echo "FAIL: Sources/ not found; run from the repo root" >&2; exit 1; }

flagged=0

while IFS= read -r -d '' file; do
    comment=0
    code=0
    while IFS= read -r line; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        [ -z "$trimmed" ] && continue
        case "$trimmed" in
            //*) comment=$((comment + 1)) ;;
            *) code=$((code + 1)) ;;
        esac
    done < "$file"

    [ "$code" -eq 0 ] && continue

    # POSIX sh has no float math; compare as comment*100 >= threshold*code so
    # a fractional threshold (the common case: 1.0, 1.5) still works exactly.
    threshold_x100=$(awk -v t="$threshold" 'BEGIN { printf "%d", t * 100 }')
    if [ $((comment * 100)) -ge $((threshold_x100 * code)) ]; then
        ratio=$(awk -v c="$comment" -v d="$code" 'BEGIN { printf "%.2f", c / d }')
        printf '  %-55s comment=%-5d code=%-5d ratio=%s\n' "$file" "$comment" "$code" "$ratio"
        flagged=$((flagged + 1))
    fi
done < <(find Sources -name '*.swift' -print0 | sort -z)

if [ "$flagged" -eq 0 ]; then
    echo "comment-ratio-check: no files at or above ${threshold}x comment:code (Sources/)"
else
    echo "comment-ratio-check: $flagged file(s) at or above ${threshold}x comment:code (Sources/): not a failure, a signal to look"
fi

exit 0
