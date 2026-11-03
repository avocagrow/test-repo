#!/usr/bin/env bash
# Lists each run's lab window (first upgrade start to last rollback end) and
# reports any two runs whose windows overlap. Works for GitHub-hosted runners,
# where lab.yml's marker files can't see other runs.
#
# Usage: scripts/check-overlap.sh [number of recent runs, default 30]
set -euo pipefail

limit="${1:-30}"
windows="$(mktemp)"
trap 'rm -f "$windows"' EXIT

for id in $(gh run list --limit "$limit" --json databaseId --jq '.[].databaseId'); do
  gh run view "$id" --json databaseId,workflowName,event,headBranch,jobs --jq '
    [.jobs[] | select(.startedAt != null and (.name | test("upgrade-|rollback-")))] as $lab
    | select($lab | length > 0)
    | [
        .databaseId,
        .workflowName,
        .event,
        ([$lab[].startedAt] | min),
        ([$lab[] | .completedAt | select(. != null)] | max // "running"),
        .headBranch
      ]
    | @tsv' >> "$windows"
done

echo "run_id	workflow	event	lab_start	lab_end	branch"
sort -t$'\t' -k4 "$windows"
echo

# Windows are sorted by start; a run overlaps the previous one if it starts
# before the latest end seen so far. ISO-8601 UTC strings compare as text.
sort -t$'\t' -k4 "$windows" | awk -F'\t' '
  {
    if (NR > 1 && $4 < max_end) {
      printf "OVERLAP: run %s started %s before run %s ended %s\n", $1, $4, max_id, max_end
      found = 1
    }
    end = ($5 == "running") ? "9999" : $5
    if (end > max_end) { max_end = end; max_id = $1 }
  }
  END { if (!found) print "No overlapping lab windows." }'
