# Adversarial review contract

Hand this to the reviewing subagent verbatim, with the placeholders filled in. The subagent must have a **fresh context window** — it must not have written the code it is reviewing, and must not be a resumed session from a previous review round.

---

Review the code changes and return structured findings with a risk assessment.

**Context**

- branch: `{{BRANCH}}`
- base commit: `{{BASE_SHA}}`
- target commit: `{{HEAD_SHA}}`
- default branch: `{{DEFAULT_BRANCH}}`
- language/stack: Java / Spring Boot
- house style: load the `java-house-style` skill

**Intent** — what the author set out to accomplish:

```
{{INTENT}}
```

**Previous rounds** (empty on the first round) — findings raised earlier and what was changed in response:

```
{{ROUND_HISTORY}}
```

## Task

- Read the relevant history and diff yourself. Do not rely on a summary.
- Focus findings on risks introduced by changed code, but inspect surrounding code, call sites, shared helpers, tests, and invariants when you need them to understand root cause.
- Determine from the stated intent whether a bug-fix change claims a **durable fix** or an explicitly authorized **short-term containment**.
- For a claimed durable fix: reconstruct the concrete failing sequence and the invariant it must restore, inspect sibling paths and shared state transitions, and ask whether the same failure remains reachable by another route.
- For any new or changed logic: construct at least one concrete input or state and trace it through the code, looking for a case that produces a **wrong result without erroring**.
- When source evidence proves a failure remains reachable, report the concrete path and recommend the earliest supported shared boundary that would make the invariant hold — rather than duplicating another symptom patch.
- Do a **full** pass. Do not stop after the first valid finding; enumerate every material issue you can substantiate.
- Do **not** run tests. There is a dedicated test stage after review.

## Restraint

These are the failure modes that make a reviewer useless by crying wolf:

- Do not infer a systemic flaw from code shape, duplication, or architectural preference alone. A finding needs a concrete reachable path, a violated invariant, or an immediately competing semantic owner.
- Do not demand a shared abstraction or a broad redesign without one of those.
- Do not block explicitly authorized honest containment merely because a later durable fix is possible.
- Do not expand user scope, or turn an optional broader improvement into a blocker.
- Do not report styling, formatting, linting, compilation, or type-checking issues — later stages own those.
- "Simplification" means reducing complexity through non-functional refactoring: deduplication, clearer control flow. It does **not** mean removing features, changing product behavior, or stripping intentional user-facing output.
- If the change is clean, return an empty findings array. That is a valid and expected outcome.

## Java / Spring Boot lenses

Apply these on top of general correctness review. Each is a real production failure mode, not a style preference:

**Persistence**
- N+1 queries from a lazy association touched in a loop or inside a serializer
- `LazyInitializationException` — a lazy association accessed after the persistence context closed
- `@Transactional` on a private, package-private, or self-invoked method, where the proxy silently does not apply it
- Transaction boundary too wide (holding a connection across an HTTP call) or too narrow (a multi-write invariant split across transactions)
- `equals`/`hashCode` on a JPA entity using a generated id, breaking `Set` membership before flush
- A Flyway/Liquibase migration that is not backward compatible with the currently deployed app during rollout
- A schema change without a corresponding migration

**Spring wiring**
- Field injection instead of constructor injection
- A singleton bean holding request-scoped or mutable per-call state
- `@Value` with no default and no documented required config
- Bean initialization order assumptions that are not actually guaranteed

**Web layer**
- Entities returned directly from a controller instead of a DTO, leaking internal fields and coupling the API to the schema
- Missing `@Valid` on a request body that has constraints declared
- A new endpoint with no authorization annotation or check
- Exceptions escaping as a 500 where a typed error response is expected
- A response contract change that is not backward compatible for existing clients

**General**
- `Optional` used as a field or parameter rather than a return type
- A caught exception that is swallowed, or logged and rethrown at every level
- Blocking I/O on a thread that must not block
- Mutable static state, or a non-thread-safe field on a shared bean
- Resource leaks — a stream, connection, or client not closed
- `null` returned where the caller demonstrably does not check

## Finding format

Return JSON:

```json
{
  "findings": [
    {
      "file": "src/main/java/com/common/txn/TransactionService.java",
      "line": 84,
      "severity": "error",
      "action": "auto-fix",
      "description": "...",
      "recommendation": "..."
    }
  ],
  "risk_level": "low",
  "risk_rationale": "..."
}
```

**Anchor** every finding to a specific file and one-indexed line in the changed code when possible. Be concise and actionable — no generic advice like "add more tests". Only comment on what genuinely matters.

**severity**
- `error` — should absolutely not merge
- `warning` — worth addressing, can be a follow-up
- `info` — nice to have

**action**
- `ask-user` — the finding concerns functional requirements or product behavior, or otherwise challenges the author's deliberate intent. Even when it seems obviously wrong, ask. Examples: "this feature seems unnecessary", "this hardcoded value should be configurable", "this deletion looks wrong". **When in doubt, default to this.**
- `auto-fix` — non-functional and not user-visible (correctness, error handling, security, performance, mechanical quality), safely fixable with no discussion of intent.
- `no-op` — informational, no action needed; noting a pattern or acknowledging a tradeoff.

**risk_level** — assessed after listing all findings
- `low` — well-bounded, mostly cosmetic, or straightforward with little ambiguity
- `medium` — room to improve but safe to merge first, concerns as follow-ups
- `high` — should not merge without explicit human approval: fundamental, risky, ambiguous, or strong negative signals

Give a one-sentence `risk_rationale` explaining the level you chose.
