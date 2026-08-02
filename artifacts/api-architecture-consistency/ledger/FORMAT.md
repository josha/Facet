# Surface-ledger fragment format (api-architecture-consistency)

One fragment file per audit area, `ledger/<area>.md`. Every assigned public item
gets one entry, even (especially) when the verdict is "follows the pattern, no
deviation" — coverage is the point, not finding count. Current code and tests
outrank historical prose: when docs and source disagree, the source+tests are the
shipped contract and the doc is the finding.

Entry shape:

```
### `<item>` — <kind>
- **Shipped shape:** the signature/spec/return surface AS THE CODE SHIPS IT (file:line).
- **Pattern:** the candidate pattern it follows (name it plainly, e.g.
  "control-build: build(LuauUI, core, spec) -> { blueprint, dump, dispose, … }",
  "owner-held Signal state", "modifier: (blueprint, spec, style?) -> new Blueprint",
  "construction-strict validation", "colon methods on stateful object",
  "dot functions on stateless module") — or "unique" with what makes it one.
- **Callers:** key call sites — LuauUI internal, examples/, and RascalRally
  (games/RascalRally/code) where they exist.
- **Lifecycle:** who owns/disposes it; scope story; leak posture.
- **Proof:** spec files + exact case names that pin the contract; the api.md
  section that documents it.
- **Findings:** none, or a list. Each finding:
  `[severity CRITICAL/MAJOR/MINOR/NOTE, confidence H/M/L] claim — evidence (file:line) — user cost (what an author suffers)`
```

Finding classes to look for (from the stage plan — do NOT invent inconsistencies
to justify churn; absence of findings is a valid result):
- inconsistent constructor/argument shapes vs the named pattern siblings use;
- unnecessary `any` at a public boundary (exported types, spec types);
- duplicate vocabulary (two public words for one concept) or one word with two meanings;
- callbacks with different meanings/signatures under the same name;
- undocumented lifecycle ownership (who disposes, what scope owns);
- accepted-but-ignored properties or options (the worst class);
- public-contract lies: api.md/guide claims the code does not honor;
- features usable only via internal imports (boundary violations);
- missing/weak proof: a public promise no spec pins;
- return-shape drift among siblings (e.g., dump schema, dispose semantics).

Rules:
- READ-ONLY audit: never edit src/, docs/, tests/. Write ONLY your fragment file.
- Every claim must carry file:line evidence you actually read this session.
- Report every issue including uncertain and low-severity ones, with severity and
  confidence. Do not filter.
- Dispositions (exception vs repair vs deprecation vs proposal) are the lead's
  call — flag, don't decide.
- End the fragment with a `## Coverage` list naming every assigned item and
  confirming it has an entry, plus anything you found that was public but
  unassigned (report it; do not audit it in depth).
