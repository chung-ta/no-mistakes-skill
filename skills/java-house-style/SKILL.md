---
name: java-house-style
description: House Java formatting and structure conventions (Real Style V2). Load before writing, reviewing, or reformatting any Java, Spring Boot, or JVM source in a repository that uses this style — the formatting here is unusual (chop-down wrapping with parens on their own lines, 2-space indent, enforced member ordering) and default Java habits will produce diffs that fight the IDE's format-on-save.
---

# Java House Style (Real Style V2)

Canonical source: the `Real Style V2` IntelliJ scheme at `~/development/workspace/java-code-style/codestyles/Real Style V2.xml`, mirrored at `~/.claude/Real-Style-V2.xml` (byte-identical). The XML is authoritative — where this document and the scheme disagree, the scheme wins and this document should be corrected.

IntelliJ runs **Reformat Code, Optimize Imports, Rearrange Code, and Run Code Cleanup on every save**. Any code you write that deviates will be silently rewritten the first time a human opens the file, producing a noisy phantom diff that gets blamed on your change. Match the style on the way in.

## Layout

| Setting | Value |
|---|---|
| Indent | **2 spaces** (not 4) |
| Continuation indent | **4 spaces** |
| Tab size | 2, spaces only |
| Right margin | **120 columns** |
| Wildcard imports | **Never** — thresholds are set to 1000, so every import is explicit |

## Wrapping is chop-down, not fill

When a construct fits in 120 columns, keep it on one line. When it does **not** fit, every element goes on its own line — never pack two arguments onto one wrapped line. This applies to call arguments, method parameters, call chains, ternaries, `try`-with-resources lists, and array initializers.

Method parameters and call arguments also put the **opening paren at end of line, then a newline**, and the **closing paren on its own line**:

```java
public TransactionResponse createTransaction(
    CreateTransactionRequest request,
    Principal principal
) {
  return transactionService.create(
      request,
      principal
  );
}
```

Parameters are **not** aligned to the opening paren — they use the 4-space continuation indent, as above.

Call chains chop down:

```java
var activeNames = people.stream()
    .filter(Person::isActive)
    .map(Person::getName)
    .toList();
```

Ternaries put the `?` and `:` at the **start** of the next line, aligned:

```java
var label = subscription.isActive()
    ? "active"
    : "inactive";
```

Array initializers chop down with braces on their own lines, and get **spaces inside the braces** when they fit on one line:

```java
private static final String[] DEFAULT_SCOPES = { "read", "write" };

private static final String[] ALL_SCOPES = {
    "read",
    "write",
    "admin",
    "impersonate"
};
```

Annotation parameters wrap one-per-line, aligned, with the closing paren on its own line. A single annotation on a parameter does **not** force a wrap:

```java
@RequestMapping(
    value = "/transactions",
    method = RequestMethod.POST,
    produces = MediaType.APPLICATION_JSON_VALUE
)
public ResponseEntity<TransactionResponse> create(@Valid @RequestBody CreateTransactionRequest request) {
```

## Braces and one-liners

- `if`, `for`, and `do`/`while` **always** take braces, even for a single statement. No exceptions.
- Control statements never share a line with their body.
- Simple methods, lambdas, and classes **may** stay on one line — `int getId() { return id; }` and `x -> x.getName()` are fine.

## Member ordering (Rearrange Code enforces this)

Declare members in exactly this order. Getters/setters and `@Override` methods keep their existing relative order rather than being re-sorted, so group them deliberately.

1. `static final` fields — public, protected, package-private, private
2. `static` fields — public, protected, package-private, private
3. `static` initializer blocks
4. `final` fields — public, protected, package-private, private
5. Remaining fields — public, protected, package-private, private
6. Instance initializer blocks
7. Constructors
8. `public static` methods
9. `public` methods
10. `protected` methods
11. Package-private methods
12. `private` methods
13. Enums
14. Interfaces
15. `static` nested classes
16. Inner classes

```java
@Service
public class TransactionService {

  private static final Logger LOG = LoggerFactory.getLogger(TransactionService.class);
  private static final Duration LOCK_TIMEOUT = Duration.ofSeconds(5);

  private final TransactionRepository repository;
  private final AuditPublisher auditPublisher;

  public TransactionService(TransactionRepository repository, AuditPublisher auditPublisher) {
    this.repository = repository;
    this.auditPublisher = auditPublisher;
  }

  public Transaction create(CreateTransactionRequest request) {
    ...
  }

  private void publishAudit(Transaction transaction) {
    ...
  }
}
```

## Comments and Javadoc

- Javadoc does **not** get `<p>` tags on empty lines — leave blank lines bare.
- Block comments get a leading space after `/*`.
- Comments wrap at the right margin.
- A comment is not pinned to column 1; it indents with the code it describes.

## Other languages in a common repo

Markdown and XML both use 2-space indent with the same 4-space (Markdown) / 2-space (XML) continuation. Markdown is **not** hard-wrapped — leave long lines long and do not insert blank lines around headers or block elements. `.editorconfig` is explicitly disabled in this scheme, so do not add one expecting it to win.

## Verifying

If the repo has a formatter wired into the build, that is the authority — run it and let it settle the file:

```sh
./mvnw spotless:apply        # or
./gradlew spotlessApply
```

If the repo has **no** formatter plugin, this scheme is the only contract and you must match it by hand. Do not add a formatter plugin to a repo as a side effect of an unrelated change.
