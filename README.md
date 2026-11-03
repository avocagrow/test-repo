# device-agent merge queue testing

A copy of device-agent's CI shape where every step just sleeps. It tests one
change before it goes into device-agent: putting the whole device-lab section
behind a single global lock, so only one run uses the lab at a time.

Background: on 2026-11-02, PR 1648's merge-queue E2E failed because PR 1673's
CI uninstalled the agent from a lab machine between 1648's upgrade and backup
jobs, then was cancelled before reinstalling it.

## What maps to what

| Here | device-agent |
|---|---|
| `ci.yml` | `ci.yml`: same triggers and the same `${{ github.workflow }}-${{ github.ref }}` cancel-in-progress group |
| `ci.yml` job `lab` with `concurrency: { group: device-lab, queue: max }` | **the change being tested**: the job that calls `e2e-tests.yml` |
| `lab.yml` `upgrade` / `backup` / `rollback` | `e2e-tests.yml` `agent-upgrade-test` / `launch-and-validate-backup` / `rollback` |
| `lab-placeholder` | PR checks record placeholders and don't use the lab |
| `weekly.yml` | `weekly-e2e.yml`: own group, and the same `device-lab` lock |
| `ci-result` | the required check |

Two differences from device-agent:
- `rollback` runs `if: always()`, including on cancel. device-agent has `!cancelled()`.
- There's no build-artifact upload, so the shared S3 folder problem isn't tested here.

## Setup

1. Push this directory to `git@github.com:Copia-Labs/device-agent-merge-queue-testing.git`. Merge queues need an organization-owned repository.
2. Optional repository variables (Settings → Secrets and variables → Actions → Variables):

   | Variable | Default | Purpose |
   |---|---|---|
   | `BUILD_SECONDS` | `60` | Build stand-in |
   | `LAB_UPGRADE_SECONDS` | `120` | Each upgrade job |
   | `LAB_BACKUP_SECONDS` | `180` | Backup job |
   | `LAB_ROLLBACK_SECONDS` | `60` | Each rollback job |
   | `LAB_RUNNERS` | `["lab-a","lab-b"]` | Matrix of lab runners (labels when self-hosted) |
   | `LAB_RUNNER_GROUP` | unset | Set to an org runner group to run upgrade and rollback on self-hosted runners |

3. Ruleset on `main` (Settings → Rules → Rulesets):
   - Require status check `ci-result`.
   - Require merge queue. Set **build concurrency** to at least 3, so entries build in parallel like device-agent's. Set the **status check timeout** to about 15 minutes, so you can provoke `checks_timed_out` on purpose. One full lab section takes about 6 minutes with the defaults.
4. Optional self-hosted runners: register 1–2 runners in an org runner group, with labels matching `LAB_RUNNERS`, and set `LAB_RUNNER_GROUP`. On those runners, `lab.yml` keeps a marker file per runner and fails with `OVERLAP` if another run's install shows up. Windows runners need Git Bash on `PATH`.

## Scenarios

After each scenario, run `scripts/check-overlap.sh` (needs `gh` and `jq`). It prints each run's lab window and any overlaps.

1. **One at a time:** dispatch `CI` three times back to back (`gh workflow run ci.yml` ×3).
   - Pass: the lab windows don't overlap, and none of the runs is cancelled.
   - Note: all three dispatches are on `refs/heads/main`, so the workflow-level per-ref group will cancel the older ones. To test the lab lock on its own, dispatch from three different branches, or use scenario 2.
2. **Merge queue:** `scripts/make-prs.sh 3`.
   - Pass: the three merge-group runs' lab windows don't overlap.
   - Also record whether a run waiting for the lab counts against the queue timeout, and what happens when it exceeds it.
3. **Cancel during backup:** while a run is in `backup`, cancel it (`gh run cancel <id>`) or re-queue its PR.
   - Pass: its `rollback` jobs still run, and the next run's `upgrade` starts only after they finish.
4. **Weekly waits:** start a merge-queue run, then dispatch `Weekly` (`gh workflow run weekly.yml`).
   - Pass: Weekly's lab section waits for the merge-queue run's lab section to finish.
5. **Newer commit cancels an older run:** with a merge-queue or tag run waiting for `device-lab`, push again to the same ref or re-queue the PR.
   - Pass: the older run is cancelled while still waiting, and the newer one waits in its place.

## Things to confirm

- `concurrency` with `queue: max` is accepted on a job that calls a reusable workflow.
- The lock is held from the first `upgrade` through the last `rollback`. No other run's lab job should start in between, including between matrix jobs.
- How the merge queue's check timeout counts time spent waiting for the lock.
