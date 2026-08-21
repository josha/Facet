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

### Scope — by REACHABILITY, not by directory (fix round 1)

Rule 2 scans the framework repository only. The rule is about how FACET explains
itself; Rascal Rally is a separate product with its own editorial policy, and it
is rule 1 that legitimately reaches into it.

**The first version carved by DIRECTORY, and the re-review was right that this
was wrong.** It skipped `docs/adr/`, `docs/plans/` and `docs/research/` wholesale
on the reasoning that a dated record is evidence. The reasoning holds for a
record nobody reads; it does not hold for one a shipped page sends a reader to.
Measured by the re-review and reproduced here: **15 documents that a guide
chapter, an extension playbook or `api.md` links carried 56 vendor lines** —
including `docs/adr/ADR-0014-first-responder.md:13`, which named the vendor as
the NAME AND THE REASON for a Facet concept, in a document `docs/guide/07-input.md`
links.

So the scope is now the SHIPPED SURFACE plus everything it links:

```
SHIPPED_SURFACE = docs/guide/**, docs/extending/**,
                  docs/reference/api.md, docs/reference/constitution.md
REACHABLE_DEPTH = 1
```

A link is a markdown link, a written path, or an `ADR-nnnn` reference — three
spellings, because a reader follows all three. The comparison document is a LEAF:
it is content exception 1, and walking its outbound links would drag its own
sources into the shipped surface.

**Depth is 1, and that is a decision.** One click from a shipped page is that
page recommending a document. Transitively, `docs/plans/facet-consolidated-roadmap.md`
is a hub that links about twenty-five plans, so a depth-N walk reaches every plan
the project has ever written — which is the archive the exclusion exists for. The
wider set is measured rather than assumed: at full transitive depth the reachable
dated documents carry **305 vendor lines across 40 files**. Reproduce either
number by changing `REACHABLE_DEPTH` and running the guard.

`VENDOR_HISTORY` still lists `artifacts/`, `docs/superpowers/`, `.superpowers/`,
`vendor/`, `build/`, `docs/adr/`, `docs/plans/` and `docs/research/` — but a path
inside one is only skipped when NOTHING in the shipped surface links it.
`VENDOR_HISTORY_MAINTAINED` remains as the floor for four documents that must be
scanned whether or not a link happens to exist today:
`docs/plans/release-candidate-review.md`,
`docs/plans/agent-execution-contract.md`,
`docs/plans/facet-consolidated-roadmap.md`, and
`docs/research/2026-08-12-haptics-engine-facts.md`.

**What the re-scope cost and left.** 56 lines across 17 files were swept, and
they are the ones a reader could reach. `docs/adr/ADR-0010-column-owned-table-api.md`
(11 vendor lines, zero inbound links from a shipped page) stays out, which the
re-review agreed is correct: it is a real dated record.

### The other framework's TYPE names (fix round 1)

`VENDOR` matched the vendor, its operating systems, its sample applications and
its domains. It matched no framework TYPE names, so `api.md` — the exhaustive
reference — explained a Facet property by naming `LazyVGrid` and `LazyHGrid`, and
`src/controls/virtual_grid.luau` raised a live construction error that named one.

`VENDOR_TYPES` matches them now, CASE-SENSITIVELY, and the case sensitivity is
load-bearing. **Every name on the list was checked against
`lune run tools/lune/_probe_public_surface`: none of them is a Facet export.**
Three names were deliberately left off after that check, so no deprecation-policy
question arises and nothing was renamed:

| Name | Why it is not matched |
|---|---|
| `ViewThatFits` | a Facet export; the plan says not to rename a stable API for a name collision |
| `ProgressView` | a Facet export, same rule |
| `SensoryFeedback` | Facet spells its own `UI.sensoryFeedback` this way in mounted-node ids, so the type name and a Facet identifier collide outright |

About 40 sites were rewritten across `api.md`, `src/`, `tests/` and `examples/`,
including the construction error, which now teaches in Facet's terms: an axis is
`"y"` (the vertical grid) or `"x"` (the sideways grid).

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
| the haptics research file, device names INSIDE a quotation | verbatim quotations of Roblox's own haptics device-support matrix | when Roblox restates it |
| device-name PROHIBITION lists in three specs and the gate manifest | they are checks of this same rule | never |
| the recorded Studio device-emulator catalog | the engine's data, and the policy under test hard-codes none of it | when re-read from Studio |
| five extraction-locked modules | held by concurrent extraction work; named debt, not a hidden one | when that extraction lands |

## The negative control

`python3 tools/check_brand_drift.py --selftest` plants, for rule 2: one vendor
word in `src/`, one in `docs/guide/` outside a marked block, the same word INSIDE
a marked block, an over-long block, and an unclosed block. It requires the first
two and the last two to be reported, the third NOT to be, then restores the tree
and requires a clean scan.

Fix round 1 added the arm that proves the SCOPE rule itself: an unlinked dated
record is planted (out of scope, skipped), a shipped page is then given a link to
it, and the same unchanged file must come INTO scope. A scope rule nobody has
watched switch is a scope rule nobody knows the shape of.

```
check_brand_drift: SELFTEST PASS — rule 1: planted content, planted path, planted
`luau-*` theme tag and an out-of-scope allowlist pattern each caught,
`luau-analyze`/`luau-lsp` deliberately not; rule 2: a planted vendor word in src/
and one in docs/guide outside a marked block each caught, the same word inside a
marked block deliberately not, an over-long and an unclosed block each caught;
restored tree clean
```

## The sweep: before and after

The first version of this file printed a bare "724" for the before-count. The
re-review could not reproduce it, and it was right not to: the number depends on
which scope and which exceptions are applied, and the file did not say which.
Corrected to the method and the band.

**Method.** Count lines matching the vendor profile across tracked files, with a
stated scope. Four scopes, all measured on the base tree `5d97826`:

| Scope | Lines with a match |
|---|---|
| everything tracked, minus `artifacts/`, `docs/superpowers/`, `.superpowers/`, `vendor/`, `build/` — no allowlist at all | **1,826** |
| …of which the one comparison document | 372 |
| the shipped guard's scope and exceptions | **687** |
| the same, minus the five extraction-lock entries | 765 |
| the same, with only the plan's two content exceptions | 969 |

The wave's own working figure of 724 sits inside that band and was never
reproducible from the record. **687** is the number this guard, as shipped,
reports on the base tree.

| After the sweep | **0 outside the recorded allowlist** |
|---|---|

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

### The one allowlist entry that was wider than its reason (fix round 1)

The haptics-research entry said "verbatim quotations" and was scoped to the
FILE, so it also excused four lines of the author's own prose about the machine
the probe ran on. That is the scoped-to-the-file-not-the-sentence shape this
guard's own comments warn about. The four prose lines are rewritten, and the
pattern now requires the device name to sit inside quotation marks or on a
markdown blockquote line, which is how a quotation that wraps is written.

## Residual, stated rather than hidden

The extraction lock is the ONE content carve-out left, and the re-review measured
its exact size: **71 vendor lines** — `table.luau` 43, `solver.luau` 11,
`renderer.luau` 7, `virtual_list.luau` 6, `presenter.luau` 4.

Five modules are held by concurrent extraction work and were not swept:
`src/controls/table.luau`, `src/layout/solver.luau`, `src/render/renderer.luau`,
`src/present/presenter.luau`, `src/controls/virtual_list.luau`. Together they
hold roughly 70 vendor-language comment lines. They are allowlisted by path with
that reason and a removal trigger, so the debt is visible in the guard rather
than invisible in the tree.
