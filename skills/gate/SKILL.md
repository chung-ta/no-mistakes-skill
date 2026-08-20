---
name: gate
description: Validate Java/Spring Boot changes through an adversarial pipeline — intent, rebase, fresh-context code review, tests with recorded evidence, docs, format/lint — then push and open a PR and watch CI. Use when the user says gate this, validate my changes, ship it, run the pipeline, /gate, or asks you to do a task and then gate it. Replaces the no-mistakes binary with a native skill.
user-invocable: true
argument-hint: [task to do first, or empty to gate what is already committed]
---

# gate

A local validation pipeline that takes first-pass code all the way to a clean PR. Ported from [`no-mistakes`](https://github.com/kunchenguid/no-mistakes) and specialized for Java / Spring Boot.

The premise: **you are not the reviewer of your own work.** Every gate run puts the diff in front of a reviewer with a fresh context window that did not write it, fixes what is mechanically fixable, escalates what needs human judgement, and records evidence that the change actually works.

## Request

$ARGUMENTS

Empty means **validate-only** — the user's work is already committed; gate it.
Non-empty means **task-first** — do the task, commit it, then gate it with the task text as the intent.

## Two modes

**Validate-only** (`/gate`) — the change is committed on a feature branch. Go straight to [Run the pipeline](#run-the-pipeline).

**Task-first** (`/gate add a --json flag to the export endpoint`):

1. **Check scope.** Run `git status` before touching anything. Preserve unrelated pre-existing uncommitted changes; commit only what belongs to this task.
2. **Do the work.** Load the `java-house-style` skill first if you are writing Java. Commit on a **feature branch** — if the user is on the default branch, create one first.
3. **Then gate**, passing the user's task text as the intent.

## Intent is required

Before running, write down **what the user set out to accomplish** — the goal behind the work, in their terms. Not a description of the diff.

Err toward completeness. The reviewer uses intent to tell a deliberate decision apart from a mistake, so a thin one-liner makes it flag things the user already chose. Capture: the user's goal, decisions and tradeoffs made along the way, constraints or approaches ruled in or out, and anything explicitly requested that would look surprising in the diff. A few sentences to a short paragraph is normal.

Write it to `.gate/intent.md` in the repo (gitignored) so every stage reads the same text.

## Preconditions

- Work is **committed**. The gate validates committed history, not a dirty tree.
- You are on a **feature branch**, not the default branch.
- `gh` is authenticated (`gh auth status`).

## Detect the build

```sh
ls mvnw gradlew pom.xml build.gradle build.gradle.kts settings.gradle 2>/dev/null
```

Prefer the wrapper (`./mvnw`, `./gradlew`) over a system `mvn`/`gradle` — it pins the version the repo expects. Record which one you found; every later stage uses it.

| | Maven | Gradle |
|---|---|---|
| Compile | `./mvnw -q -DskipTests compile` | `./gradlew compileJava` |
| Test | `./mvnw -q verify` | `./gradlew test` |
| Format | `./mvnw spotless:apply` | `./gradlew spotlessApply` |
| Lint | `./mvnw -q checkstyle:check` | `./gradlew checkstyleMain` |

Only run a plugin the repo actually configures. Never add one as a side effect.

## Resolve the delivery mode

Before running anything, resolve **fast** vs **full** from the base branch and read `references/delivery-modes.md`.

Short version: a base branch matching `^(team|play)`, or a current branch name containing `TEAM`, means **fast** — skip review, test, and documentation, including for diffs that touch migrations. Everything else is **full**.

State the resolved mode before starting: *"team1 base → fast mode: skipping review and test."* A silently-skipped review looks identical to a review that found nothing.

## Run the pipeline

Do the whole pipeline in an **isolated worktree** so nothing you run disturbs the user's working tree:

```sh
BRANCH=$(git rev-parse --abbrev-ref HEAD)
WT=$(mktemp -d)/gate-$BRANCH
git worktree add "$WT" "$BRANCH"
```

Clean it up with `git worktree remove --force "$WT"` when the run ends, including on failure.

Stages run in order. A stage that finds nothing passes silently; report progress as you go.

### 1. Rebase

Rebase onto the latest default branch **up front**, so conflicts surface now rather than at PR time:

```sh
git fetch origin
git rebase origin/$(git symbolic-ref refs/remotes/origin/HEAD | sed 's|.*/||')
```

Resolve conflicts yourself when the resolution is unambiguous. When a conflict has real semantic ambiguity — two changes to the same logic with different intents — stop and ask the user. Never resolve a conflict by discarding one side because it is easier.

### 2. Adversarial review

**Fast mode skips this stage entirely**, including for diffs that touch migrations. See `references/delivery-modes.md`.

This is where most problems get caught. **Delegate it to a subagent with a fresh context window.** Do not review your own diff inline — you wrote it, and you will rationalize it.

Read `references/house-review-rules.md` first. It names the authoritative reviewers, carries the rules this codebase has been burned by (Cartesian product, boundary conditions, eager-fetch consumer tracing, migrations), and defines the severity normalization table.

**Run `/pre-pr-review` as the reviewer.** It already fans out five specialists against this codebase's own conventions, and it is what `pre-pr-create.sh` requires — so review happens once rather than twice. Pass it the base branch. Use `references/review-contract.md` for the finding schema and the restraint rules, and only fall back to a bespoke reviewer subagent when `/pre-pr-review` is unavailable.

Normalize whatever comes back into `gate`'s finding schema using the table in `house-review-rules.md`, keyed on **(source, tier)** — never on the tier label alone, since `Major` means opposite things across paths. Preserve each finding's original label in its text, and fail closed on any tier the table does not list.

Then act on the findings by their `action`:

- **`auto-fix`** — apply the fix yourself. Non-functional, non user-visible: correctness, error handling, security, performance, mechanical quality.
- **`ask-user`** — stop and ask. Anything touching functional requirements, product behavior, or the author's deliberate intent. When in doubt, this is the default.
- **`no-op`** — informational; record it in the PR body, change nothing.

**Re-review after fixes, with another fresh subagent.** Never resume the reviewing subagent that prescribed the fixes, and never let the subagent that *wrote* the fixes certify them. That seats the prescriber as its own certifier: the re-review then checks that its prescription was implemented rather than judging whether the new code is correct. This is a real shipped-defect mechanism, not a theoretical one — one fix round wrote both wrong code and the test blessing it, and the resumed reviewer passed both. The fixer may keep a durable session because it certifies nothing; the reviewer never does.

Carry cross-round context explicitly in the prompt (previous findings, what was changed in response), not by resuming a session.

Repeat review → fix → re-review until a round returns no `error`-severity findings. Cap at 3 rounds, then escalate to the user with what is still open.

### 3. Test with evidence

**Fast mode skips this stage.**

Run the suite:

```sh
./mvnw -q verify        # or ./gradlew test
```

Then **prove the change does what the intent says** — a green suite only proves nothing regressed, not that the feature works. Exercise the actual behavior end to end and record evidence to `.gate/evidence/`:

- An HTTP endpoint → `curl` against a locally booted app, request and response saved
- A scheduled job or listener → a log excerpt showing it firing with the right payload
- A repository/query change → the executed SQL (turn on `spring.jpa.show-sql`) plus row counts before and after
- A UI change → a screenshot
- A migration → the schema diff before and after `flyway:migrate`

If the change genuinely cannot be exercised (pure refactor, config-only), say so explicitly and name why, rather than skipping the stage silently.

**Test-quality rule.** Never add a test whose only evidence is that it opens, reads, greps, parses, or snapshots implementation source and finds or omits particular strings, tokens, lines, method names, or AST shapes. That does not prove behavior — matching text can be dead or commented out, and a behavior-preserving refactor changes it. Execute a public or executable interface and assert observable behavior, state, output, side effects, and failure modes.

For machine-consumed declarative artifacts (workflow YAML, JSON, policy, generated config), invoke the real consumer when feasible, or parse into a typed semantic model and assert meaning. A raw substring match over the file is still the anti-pattern.

For a regression, reproduce the reported failure first: the test should fail before the fix and pass after it.

Prefer the narrowest Spring test that proves the point — `@WebMvcTest` over `@SpringBootTest` for a controller, `@DataJpaTest` for a repository — and reach for Testcontainers rather than mocking a database whose behavior is the thing under test.

### 4. Documentation

**Fast mode skips this stage.**

Update what the change actually invalidated: Javadoc on changed public API, `README`/`docs/` for behavior or configuration users depend on, OpenAPI annotations, and any architecture note describing a contract you altered. Do not manufacture documentation for unchanged code.

### 5. Format and lint

```sh
./mvnw spotless:apply && ./mvnw -q checkstyle:check
```

If the repo has no formatter plugin, conform to the `java-house-style` skill by hand. Fix every lint finding — this stage never escalates to the user, it only fixes.

### 6. Push and open the PR

```sh
git push -u origin "$BRANCH"
gh pr create --base "<the base branch>" --title "<conventional commit style title>" --body-file .gate/pr-body.md
```

**Always pass `--base` explicitly.** The hook parses the base branch out of this exact command and falls back to `master` when the flag is absent. Omitting it while the pipeline resolved fast mode from somewhere else makes the hook and the skill read different values — the one divergence `references/delivery-modes.md` exists to prevent. The base you pass here must be the same one the mode was resolved from.

**The review sentinel.** `~/.claude/hooks/pre-pr-create.sh` blocks `gh pr create` unless `/tmp/claude-pr-review-done-<branch>` exists. Write it only when the gate has genuinely earned it:

- **full mode** — a review round returned **no `error`-severity findings**. Not merely that the loop terminated: `/pre-pr-review` exits legitimately at its 4-iteration cap and on a same-finding stall, and both of those hand back control with blocking findings still open. A capped or stalled loop has **not** earned the sentinel — escalate to the user with what is still open instead.
- **fast mode** — the mode resolved to fast under the documented rule (no review runs, so there is nothing to leave unresolved)

```sh
touch "/tmp/claude-pr-review-done-$BRANCH"
```

Never write it to get past the hook. If review left blocking findings open, the hook is correctly stopping the PR — fix them and re-run. Writing the sentinel around an unfinished review disables the only enforced quality gate in this workflow.

The PR body must carry, in this order:

- **Intent** — what the user set out to accomplish, verbatim from `.gate/intent.md`
- **What changed** — the substance, not a file list
- **How it was tested** — with links to the recorded evidence
- **Pipeline findings** — what review caught and how each was resolved
- **Risk assessment** — `low` / `medium` / `high` plus a one-sentence rationale

The risk level is what tells the user how much of their own attention this PR deserves, so assess it honestly:

- **low** — well-bounded, mostly mechanical, little ambiguity
- **medium** — room to improve, safe to merge with concerns as follow-ups
- **high** — should not merge without explicit human approval: fundamental, risky, ambiguous, or carrying strong negative signals

### 7. Watch CI

Poll until CI settles:

```sh
gh pr checks --watch
```

On failure, read the actual log (`gh run view <id> --log-failed`), fix the cause, and push again. Distinguish a **real** failure from a **transient** one (flaky test, runner timeout, network blip) — retry a transient once before treating it as real, and say which you concluded.

**`gh pr checks` only sees checks reported back to GitHub.** Most Real Java services build on **TeamCity → Brahman → ArgoCD**, not GitHub Actions, so this stage has three outcomes, not two:

| Outcome | Meaning | Do |
|---|---|---|
| Checks appear, green | CI passed | Report green |
| Checks appear, red | CI failed | Read the log, fix, push |
| **No checks ever register** | CI is not reporting to GitHub | **Do not conclude green.** Verify through TeamCity directly |

An empty check list is **not** success and **not** failure — it is the absence of a signal, and reporting it as green is how an unverified branch gets merged. When nothing registers within a couple of minutes, stop polling and switch: load the `teamcity-cli` skill (or `real-eng:teamcity-reference`) and confirm the build through the TeamCity CLI. Some feature-branch builds need a **manual trigger** rather than firing on push — if so, say that plainly rather than treating "no build" as "clean build".

**Always name which path you verified through**, because "CI passed" means different things: *"green via `gh pr checks`"* or *"green via TeamCity build #NNNN"*. Never report CI status you did not actually observe.

Also re-check mergeability: a conflict can land while CI runs. Rebase and push if so.

Stop when checks are green and report. **Do not merge** — merging is the user's call.

## Reporting

Report the outcome at the end: what the pipeline caught, what it fixed, what needs the user's judgement, the risk level, and the PR link. If the run stopped early, say exactly which stage and why.
