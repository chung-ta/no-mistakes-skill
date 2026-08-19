# no-mistakes-skill

**A Java/Spring Boot validation gate for Claude Code, as native skills — no binary required.**

Ported from [`no-mistakes`](https://github.com/kunchenguid/no-mistakes) by [Kun Chen](https://github.com/kunchenguid).

---

## What this is

The original `no-mistakes` is a Go binary that puts a local git proxy in front of your real remote: you `git push no-mistakes`, it spins up a disposable worktree, runs an AI validation pipeline, and opens a clean PR only after every check passes.

Almost all of that binary is *plumbing* — a git-proxy remote, a background daemon, a TUI, subprocess management. The part that actually catches bugs is **text**: the stage sequence, the adversarial review prompt, and the finding taxonomy that decides what gets auto-fixed versus escalated to a human.

This repo is that text, rewritten as Claude Code skills and specialized for **Java / Spring Boot**. You get the pipeline without installing anything compiled.

## Skills provided

| Skill | What it does |
|---|---|
| **`gate`** | The pipeline: intent → rebase → adversarial review → tests with recorded evidence → docs → format/lint → push → PR → CI watch. Invoked as `/gate`. |
| **`java-house-style`** | Java formatting and structure conventions. Loads automatically whenever Claude is about to write or review Java. |

### The core idea

**You are not the reviewer of your own work.** Every gate run puts the diff in front of a reviewer with a fresh context window that did not write it, fixes what is mechanically fixable, escalates what needs human judgement, and records evidence that the change actually works.

The most load-bearing rule, carried over from the original's source comments: **never resume the reviewer session that prescribed a fix in order to check that fix.** Doing so seats the prescriber as its own certifier — it verifies its prescription was followed rather than judging whether the new code is correct. That is the mechanism behind a real shipped defect in the original project, where one fix round wrote both wrong code and the test blessing it, and the resumed reviewer passed both.

### Java/Spring-specific review lenses

On top of general correctness review, the reviewer checks for the failure modes that actually bite Spring services:

- `@Transactional` on a private, package-private, or self-invoked method, where the proxy silently does not apply
- N+1 queries, and `LazyInitializationException` from an association touched after the persistence context closed
- Transaction boundaries too wide (holding a connection across an HTTP call) or too narrow (a multi-write invariant split across transactions)
- JPA `equals`/`hashCode` on a generated id, breaking `Set` membership before flush
- Migrations that are not backward compatible during a rolling deploy
- Entities returned straight from controllers instead of DTOs
- Missing `@Valid`, missing authorization on new endpoints
- Singleton beans holding mutable per-request state, field injection instead of constructor injection

Full list in [`skills/gate/references/review-contract.md`](skills/gate/references/review-contract.md).

## Requirements

- **Claude Code**
- **git** and **[`gh`](https://cli.github.com/)**, authenticated (`gh auth login`) — used for push, PR creation, and CI watching
- A Java project with a build wrapper (`./mvnw` or `./gradlew`). The skill detects which and adapts.

## Install

```sh
git clone https://github.com/chung-ta/no-mistakes-skill.git
cd no-mistakes-skill
./install.sh
```

Then **start a new Claude Code session** — skills are discovered at session start.

By default the installer **symlinks** each skill into `~/.claude/skills/`, so `git pull` in this checkout updates the installed skills with no reinstall. Move or delete the checkout and the skills go with it.

```sh
./install.sh --copy        # copy instead, so skills survive this checkout going away
./install.sh --force       # replace skills already installed under the same name
./install.sh --uninstall   # remove them
./install.sh --dir <path>  # install somewhere other than ~/.claude/skills
./install.sh --help
```

### Verify

Start a new session and run `/gate` with no arguments in a Java repo. It should report its preconditions rather than doing anything — that tells you it loaded.

## Use

**Validate work you already committed:**

```
/gate
```

**Do a task, then validate it:**

```
/gate add a --json flag to the export endpoint
```

In task-first mode Claude does the work, commits it on a feature branch, and then gates it using your task text as the intent.

**Preconditions.** Work must be committed, on a feature branch (not the default branch). The gate validates committed history, not a dirty working tree.

**Intent matters.** The reviewer uses your stated intent to tell a deliberate decision apart from a mistake. A thin one-liner makes it flag things you already chose on purpose. Give it the goal, the tradeoffs you made, and anything you asked for that would look surprising in the diff.

### What you get back

- Findings, each classified `auto-fix` (applied for you), `ask-user` (a judgement call, brought to you), or `no-op` (recorded, no action)
- A test stage that runs the suite **and** records evidence the change does what the intent said — a green suite only proves nothing regressed
- A PR whose body carries the intent, what changed, how it was tested, what the pipeline caught, and a **risk level** telling you how much of your own attention this deserves
- CI watched to green, with transient failures distinguished from real ones

It never merges. That stays your call.

## Differences from the original

**Kept:** the stage sequence, the adversarial review prompt and its restraint rules, the `auto-fix`/`ask-user`/`no-op` taxonomy, the risk assessment, the test-quality rule, evidence recording, isolated-worktree execution, fresh-context re-review.

**Dropped:** the `git push no-mistakes` git-proxy trigger, the background daemon, the TUI, support for agents other than Claude Code, and cross-session PR babysitting after the session ends.

**Added:** Java/Spring Boot review lenses, Maven/Gradle wrapper detection, Spring test-slice guidance, and the `java-house-style` skill.

If you want the git-proxy trigger, the TUI, or agent-agnostic support, **use the real thing** — it is excellent and it is not replaced by this:

```sh
curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh
```

The two can coexist. This repo's skill is named `gate`, not `no-mistakes`, specifically so it does not collide with the `/no-mistakes` skill that `no-mistakes init` installs.

## Attribution

Derived from [github.com/kunchenguid/no-mistakes](https://github.com/kunchenguid/no-mistakes) — MIT, © 2026 Kun Chen. The pipeline design, the review prompt structure, the finding taxonomy, the test-quality rule, and the self-certification insight are all his work; this repo ports them to a different runtime and a different language stack.

His other tools in the same workflow, all free and open source:

- [`firstmate`](https://github.com/kunchenguid/firstmate) — talk to one agent, ship with a crew
- [`lavish-axi`](https://github.com/kunchenguid/lavish-axi) — review HTML artifacts instead of walls of terminal text
- [`treehouse`](https://github.com/kunchenguid/treehouse) — manage worktrees without managing worktrees
- [`gnhf`](https://github.com/kunchenguid/gnhf) — "good night, have fun": long-running agent loops

Background: [L8 Principal's Agentic Engineering Workflow](https://www.youtube.com/watch?v=iQyg-KypKAA).

**Companion repo:** [`firstmate-skill`](https://github.com/chung-ta/firstmate-skill) — the `crew` orchestrator, which dispatches parallel tasks and has each one finish by running `/gate` from this repo.

## License

MIT. See [LICENSE](LICENSE).
