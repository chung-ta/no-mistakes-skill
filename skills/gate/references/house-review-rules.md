# House review rules

These are the review rules this codebase has actually been burned by. They extend the generic lenses in `review-contract.md` and take precedence over them where they overlap.

**Do not restate these rules from memory.** The authoritative, maintained copies live in the reviewer agents; this file names them, adds the detection logic worth stating explicitly, and defines how their severities map into `gate`'s finding schema.

## Where the rules live

| Source | Owns |
|---|---|
| `~/.claude/agents/java-spring-code-reviewer.md` | The full 16-section Java/Spring review. The authority for everything below. |
| `~/.claude/agents/flyway-migration-reviewer.md` | Zero-downtime migration safety; verdict is SAFE / UNSAFE. |
| `~/.claude/skills/pre-pr-review/SKILL.md` | The 5-agent parallel pipeline `gate` drives in full mode. |
| `~/.claude/Real-Style-V2.xml` | Canonical formatting scheme. `java-house-style` describes it; the XML wins on conflict. |

In **full mode**, `gate`'s review stage runs `/pre-pr-review` rather than a reviewer of its own. That skill already fans out five specialists, and its findings feed the gate. It also satisfies `pre-pr-create.sh`, so review happens once rather than twice.

## Repo-local review assets — check before reviewing

Nearly every repo under `~/development/workspace/` ships its own `.claude/skills/` and often `.claude/agents/`. **Before the review stage runs, list the target repo's `.claude/` and fold whatever is relevant to the diff into the context passed to `/pre-pr-review`'s agents.** Repo conventions go *on top of* the five specialists, never instead of them.

```sh
ls .claude/skills .claude/agents 2>/dev/null
```

- **Repo `pr-review` cannot be the reviewer here.** It needs a PR URL and pulls the diff via GitHub MCP, so it only runs *post*-PR; `gate` reviews *pre*-PR. Read it for its repo-specific criteria and pass those through — do not try to invoke it as the review stage.
- **It is mostly, but not always, the shared file.** plutus / yenta / arrakis / hermes are byte-identical (445 lines); **keymaker (468) and real-commons (381) diverge.** Diff before assuming.
- **Match the asset to the diff.** A repo skill or agent scoped to what actually changed is worth more than a generic pass: plutus `mixpanel-handlers` + `mixpanel-reviewer` for Mixpanel handlers, real-commons `events` for event/domain changes, hermes `notifications`, keymaker `keymaker-security-review` + `add-permission`, hawkeye `new-migration`, arrakis `hexagon-*`. Name the ones you used in the review report.
- **Repo `.claude/agents/*.md` may not be spawnable** even with valid frontmatter — `Agent(subagent_type: "<name>")` can return "not found" when the session registry never loaded them. Verify before relying on one; the working fallback is to read the agent's `.md` and hand its checklist verbatim to a general-purpose agent with the same tool scope.

## The rules with a production incident behind them

### Cartesian product (🔴 Critical)

A PR replacing ~300 lazy queries with 3 JOIN FETCH queries caused a full outage: worst case 2,430 rows for a single entity, 47-second queries, HikariCP pool exhaustion, rollback.

**Detection is mechanical: count collection (`@OneToMany`/`@ManyToMany`) associations JOIN FETCHed in one query. Two or more → 🔴 Critical.**

Also 🔴: `SELECT DISTINCT` masking a multi-collection JOIN FETCH (Hibernate still materializes every Cartesian row in memory); nested JOIN FETCH through collection associations; `@EntityGraph` with 2+ collection `attributeNodes`; multi-query "session merge" strategies that lean on L1 cache.

Safe: `@BatchSize(size=50)`, `@Fetch(FetchMode.SUBSELECT)`. JOIN FETCH remains correct and recommended for `@ManyToOne`/`@OneToOne`.

When reporting this finding, **show the arithmetic** — collection sizes multiplied to the resulting row count. The number is the argument.

### Boundary conditions (🔴 / 🟠)

Boundary bugs are correct in the interior and wrong at the extreme. They read as idiomatic and survive a structural glance, so **evaluate the exact edge value rather than pattern-matching**. For every comparison, range, index, loop bound, or size check in the diff — including unchanged-but-adjacent logic in a modified method — name the boundary and ask what happens *at* it, one below, and one above.

The canonical case: `plusDays(1).atStartOfDay()` paired with `<=` → 🔴 Critical, because the upper bound is the next day's midnight and `<=` lets a row a full day past the range leak in. Correct forms are `<` with `plusDays(1)`, or `<=` with end-of-day. Never `<=` with `plusDays(1)`.

Section 13a of the reviewer agent owns the complete rule set — inclusive/exclusive mismatches, off-by-one in pagination and indexing, equality at thresholds, missing edge inputs, divergence across sibling paths, and the demand for a boundary test.

### Eager-fetch consumer tracing (🟠)

For `@EntityGraph`/`JOIN FETCH`, trace the **full consumer path** — mapper, DTO, serializer — and verify every lazy association the consumer touches is actually fetched. Read the generated MapStruct implementation, not just the interface. A Javadoc claiming "loads all associations needed for X" is a claim to verify, not evidence.

### Migrations

Owned by `flyway-migration-reviewer`. The blocking set: `NOT NULL` without a default; `DROP COLUMN`; `CREATE INDEX` without `CONCURRENTLY`; `ALTER COLUMN TYPE`; renames; `LOCK TABLE`. Plus audit-table (`_aud`) parity when the entity is `@Audited`.

Like every other review rule here, this applies in **full mode only**. Fast mode runs no review stage at all, migrations included — see `delivery-modes.md`.

## Severity normalization

Review paths in this workspace use different scales, and the same word means different things across them. `Major` in the yenta pipeline is second-tier and blocking; `🟡 Major` in the reviewer agent is third-tier and not. **Key the mapping on (source, tier) — never on the tier label alone.**

| Source | Their tier | `gate` severity | Blocking |
|---|---|---|---|
| java-spring-code-reviewer, flyway-migration-reviewer | 🔴 Critical | `error` | yes |
| " | 🟠 Warning | `error` | yes |
| " | 🟡 Major | `warning` | no |
| " | 🔵 Minor | `info` | no |
| " | 💡 Suggestion | `info` | no |
| pre-pr-review, yenta pr-review | `[Critical]` | `error` | yes |
| " | `[Major]` | `error` | yes |
| " | `[Minor]` | `warning` | no |
| " | `[Nit]` | `info` | no |
| arrakis review | `CRITICAL` | `error` | yes |
| " | `HIGH` | `error` | yes |

**Preserve the original label in the finding text.** A finding from arrakis should still read `CRITICAL` in the report — reviewers recognize their own vocabulary, and relabeling it hides where the finding came from.

**Fail closed on anything unlisted.** An unrecognized tier — a new severity, a renamed one, a repo not in this table — is classified `ask-user` and reported as such: *"unrecognized severity `BLOCKER` from arrakis/review — treating as needs-decision."* Never guess a mapping. An unmapped tier should be visible noise prompting an update to this table, not a silent miscategorization.

## Evidence requirement

Carried over from the reviewer agent, and it applies to every blocking finding `gate` reports:

**🔴 and 🟠 findings must carry concrete evidence** — a code trace, a specific failing input, or a logical proof. A vague observation without evidence gets dismissed by the author, wastes the round trip, and trains everyone to distrust the reviewer. If the evidence cannot be constructed, the finding is not blocking.
