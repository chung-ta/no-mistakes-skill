# Delivery modes

Not every branch deserves the same rigor. A shared integration branch is a place to iterate; `master` is not. `gate` resolves a mode from the **base branch** and runs only the stages that mode calls for.

The rule below deliberately mirrors `~/.claude/hooks/pre-pr-create.sh`. That hook already exempts team/play from review, so a `gate` that disagreed would either block work the hook allows or demand review the hook does not. Keep them in sync: if the hook's exemption changes, change this too.

## Resolving the mode

**fast** — when any of these holds:
- base branch matches `^(team|play)` case-insensitively (`team1`, `team2`, `play`, `play3`, …)
- the current branch name contains `TEAM` case-insensitively (e.g. `RV2-64171-TEAM1-organization`)

**full** — everything else, including `master`, `main`, and any release branch.

Resolve it from the actual `gh pr create --base` argument when present, otherwise the configured default (`master`). Never infer the mode from the ticket, the file paths, or how large the diff feels.

State the resolved mode out loud before running: *"team1 base → fast mode: skipping review and test."* A silently-skipped review is indistinguishable from a review that found nothing.

## What each mode runs

| Stage | fast | full |
|---|---|---|
| intent | yes | yes |
| rebase | yes | yes |
| **review** | **skipped** | yes |
| **test** | **skipped** | yes |
| migration check | **skipped** | yes (inside review) |
| document | skipped | yes |
| lint / house style | yes | yes |
| push | yes | yes |
| PR | yes | yes |
| CI watch | yes | yes |

Lint stays on in fast mode because it is seconds of cost and the IDE reformats on save anyway — unformatted code on a shared branch produces phantom diffs for whoever touches it next.

## Fast mode is a clean skip

Fast mode runs **no review stage at all**, including for schema changes. A diff touching `**/db/migration/*.sql` goes straight from rebase to lint like any other diff. Do not run the migration check, do not run a partial review, and do not warn about migrations as a substitute — that would reintroduce the gate the mode exists to skip.

This is a deliberate call. Team and play branches are for iteration, and gating them behind review defeats their purpose. The cost is real and worth naming: a non-backward-compatible migration merged to a team branch runs against that environment's shared database and can break every developer on it. Fast mode trades that risk for speed on branches where speed is the point.

`master` and every other base still get the full review, so migrations are reviewed before they reach anything permanent. Ask for full mode on a team branch when a particular schema change deserves the scrutiny (see Overrides below).

## Overrides

There is no flag to parse: `$ARGUMENTS` is the task text, so `/gate --full` would be read as "do the task `--full`, then gate it". Override in natural language instead — *"gate this but run full mode"* — and state the override and its reason before starting.

Forcing **full** on a team/play base is the useful direction: use it when a change is risky enough to want review despite the branch, which is the escape hatch for a schema change that fast mode would otherwise skip.

Forcing **fast** on a `master` base is not offered. If a change is too urgent for review, that is a conversation to have deliberately, not an override to slip past.

## The sentinel

`pre-pr-create.sh` blocks `gh pr create` unless `/tmp/claude-pr-review-done-<branch>` exists, and its message instructs the agent to `touch` that file after addressing findings. Nothing verifies a review actually happened — it is an honor-system gate.

`gate` makes it real. Write the sentinel **only** when:
- **full mode**: the review stage completed and no blocking finding is unresolved, or
- **fast mode**: the mode resolved to fast under the rule above (no review runs, so there is nothing to leave unresolved).

Never write it to get past the hook. If review found blocking findings that are still open, the hook is correctly stopping the PR — resolve them first. Writing the sentinel around an unfinished review defeats the only enforced quality gate in the workflow.
