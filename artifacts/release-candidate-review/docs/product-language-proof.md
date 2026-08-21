# Product-language independence — the guard, the sweep, the negative control

**What this file records:** the vendor profile added to
`tools/check_brand_drift.py`, its scope and exceptions, the negative control, and
the before/after scan counts.

## The guard

`tools/check_brand_drift.py` now enforces two rules. Rule 1 is the retired
framework name, unchanged. Rule 2 is product-language independence: another
user-interface framework, its vendor, that vendor's operating systems, its
sample applications, and its documentation domains may not be the NAME or the
REASON for a Facet feature. The match list is `VENDOR`, and per the plan it
lives only inside the guard.

Two pattern choices are deliberately narrow and are written beside the pattern:
`mac catalyst` rather than a bare `catalyst`, and sample-application names only
where the name is distinctive. One sample application shares its name with an
ordinary English noun this repository uses for visual anchors in a scrolling
rail, so it is NOT matched — a guard that reports a homonym gets routed around.

### Scope

Rule 2 scans the framework repository only. The rule is about how FACET explains
itself; Rascal Rally is a separate product with its own editorial policy, and it
is rule 1 that legitimately reaches into it. Frozen and dated records are not
scanned, each with its reason and removal rule in `VENDOR_HISTORY`:
`artifacts/`, `docs/superpowers/`, `.superpowers/`, `vendor/`, `build/`,
`docs/adr/`, `docs/plans/` and `docs/research/`. An accepted ADR and a consumed
wave plan are the EVIDENCE of a decision; rewriting one to remove a name
falsifies the record rather than cleaning the product.

Four documents inside those directories ARE current-facing product surface and
are carved back in and swept: `docs/plans/release-candidate-review.md`,
`docs/plans/agent-execution-contract.md`,
`docs/plans/facet-consolidated-roadmap.md`, and
`docs/research/2026-08-12-haptics-engine-facts.md`.

### The two content exceptions, and nothing else

1. `docs/reference/swiftui-parity.md`, path and body — the one dedicated
   comparison document.
2. A short comparison block inside `docs/guide/**`, delimited by
   `<!-- comparison:begin -->` and `<!-- comparison:end -->` and capped at 15
   lines. One such block ships, in `docs/guide/10-rich-skinning.md`: four lines
   that map the three customization rungs for a reader who already knows another
   framework, marked optional and stated not to be part of the contract.

The cap is enforced: an over-long block, an unclosed block and a block opened
twice each FAIL. A marker outside `docs/guide/` is not a marker at all — the
exception does not reach there, so the words it tries to excuse are scanned
normally.

### What is allowlisted, and why

Every entry carries a reason and a removal rule beside it:

| Entry | Reason | Removed when |
|---|---|---|
| the parity document | content exception 1 | never |
| the guard itself | its own match data | never |
| any line quoting a path under `artifacts/…` | frozen gate evidence keeps the name it was earned under | Step 14 evidence archive |
| four earned gate ids, in six named registries | the id is also the name of its frozen `artifacts/` directory | Step 14 gate archive |
| `gate_manifest` lines quoting the parity document's path | a shell command has to open the file the path really names | when the comparison document retires |
| `check_docs.luau` + `theme_docs.spec.luau`, quoted literals only | they are the machinery of content exception 1 | same |
| the host screen-capture helper | the host compiler fixes its language and file extension | when the helper stops needing a compiled binary |
| the haptics research file, device names only | verbatim quotations of Roblox's own haptics device-support matrix | when Roblox restates it |
| device-name PROHIBITION lists in three specs and the gate manifest | they are checks of this same rule | never |
| the recorded Studio device-emulator catalog | the engine's data, and the policy under test hard-codes none of it | when re-read from Studio |
| five extraction-locked modules | held by concurrent extraction work; named debt, not a hidden one | when that extraction lands |

## The negative control

`python3 tools/check_brand_drift.py --selftest` plants, for rule 2: one vendor
word in `src/`, one in `docs/guide/` outside a marked block, the same word INSIDE
a marked block, an over-long block, and an unclosed block. It requires the first
two and the last two to be reported, the third NOT to be, then restores the tree
and requires a clean scan.

```
check_brand_drift: SELFTEST PASS — rule 1: planted content, planted path, planted
`luau-*` theme tag and an out-of-scope allowlist pattern each caught,
`luau-analyze`/`luau-lsp` deliberately not; rule 2: a planted vendor word in src/
and one in docs/guide outside a marked block each caught, the same word inside a
marked block deliberately not, an over-long and an unclosed block each caught;
restored tree clean
```

## The sweep: before and after

| Scan | Lines with a match |
|---|---|
| Framework repo at the wave's start, excluding frozen trees | 1,817 |
| …of which the one comparison document | 372 |
| Guard's first full run (scope + exceptions applied) | 724 |
| After the sweep | **0 outside the recorded allowlist** |

Where the 724 went: 74 in `docs/reference/api.md`, 230 in `src/`, ~230 in
`tests/`, 82 in `examples/`, 165 in `tools/`, and the rest across
`docs/guide`, `docs/lessons`, `docs/handoff`, `docs/reference`, `phases.json`,
`requirements.json`, `ui_todo.md` and the four carved-in plan/research documents.

Eight documents were renamed so that citations of them stopped carrying a vendor
word, and every citation in the maintained tree was repointed (74 files):

```
docs/plans/swiftui-parity-next.md            -> docs/plans/parity-next.md
docs/plans/swiftui-parity-round2{,-brief}.md -> docs/plans/parity-round2{,-brief}.md
docs/plans/swiftui-parity-round3{,-brief}.md -> docs/plans/parity-round3{,-brief}.md
docs/plans/swiftui-reference-app-validation.md -> docs/plans/reference-app-validation.md
docs/research/2026-07-21-swiftui-affordance-research.md
                                             -> docs/research/2026-07-21-affordance-research.md
docs/adr/ADR-0010-swiftui-shaped-table-api.md
                                             -> docs/adr/ADR-0010-column-owned-table-api.md
```

Frozen `artifacts/` directories keep their earned names; that is what the
citation allowlist rule exists for.

### The named debts from the brief

- `docs/research/2026-08-12-haptics-engine-facts.md`: the prose now speaks in
  Facet and Roblox terms. Its device names survive only inside verbatim
  quotations of ROBLOX's own haptics support matrix, which is the platform fact
  the document exists to hold; that is the allowlist entry above.
- `src/client/roblox_input.luau`: the two stale claims are corrected. The header
  said both `Fire()` and `GetState()` were deprecated; only `Fire()` is, and the
  comment now says so and dates the re-read. The bounded-wait note lost its
  finding code.
- `src/client/native_style.luau`: the seed-once header lost its ledger code.
- `src/themes/package.luau`: the ghost class `UI.Custom` — which never shipped —
  is now `UI.Foreign`, the class that did.
- `docs/plans/release-candidate-review.md`: the haptics section and the
  product-language section no longer spell the prohibited names. They point at
  the guard, which is the only place the match list may live, and at the naming
  ADRs.

## Residual, stated rather than hidden

Five modules are held by concurrent extraction work and were not swept:
`src/controls/table.luau`, `src/layout/solver.luau`, `src/render/renderer.luau`,
`src/present/presenter.luau`, `src/controls/virtual_list.luau`. Together they
hold roughly 70 vendor-language comment lines. They are allowlisted by path with
that reason and a removal trigger, so the debt is visible in the guard rather
than invisible in the tree.
