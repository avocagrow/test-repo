#!/usr/bin/env bash
# Opens N pull requests that each add one file, and asks to add each one to
# the merge queue once its checks pass (gh pr merge --auto).
#
# Usage: scripts/make-prs.sh [count, default 3] [prefix, default mq-test]
set -euo pipefail

count="${1:-3}"
prefix="${2:-mq-test}"
stamp="$(date -u +%Y%m%d-%H%M%S)"

git fetch origin main
for i in $(seq 1 "$count"); do
  branch="$prefix-$stamp-$i"
  git switch -c "$branch" origin/main
  mkdir -p changes
  echo "$branch" > "changes/$branch.txt"
  git add "changes/$branch.txt"
  git commit -m "test: $branch"
  git push -u origin "$branch"
  gh pr create --base main --head "$branch" --title "test: $branch" --body "Merge queue lab-lock test."
  gh pr merge "$branch" --auto --squash
done
git switch main
