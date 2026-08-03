# Fresh-author exercise — adding a composite control with only the public docs

**Stage:** `api-architecture-consistency`
**Date:** 2026-08-02
**Author role:** an agent with NO repository history, allowed to read only
`docs/guide/**`, `docs/reference/api.md`, `docs/reference/constitution.md`,
`docs/extending/**`, and the files those documents explicitly cite as patterns
(`tests/chip.spec.luau`, `tests/conformance/controls_registry.luau`,
`tests/lib/fake_target.luau`). `src/**` was treated as a black box behind the
public API — the only source file read or written was the one the scaffold
stamped for me.

**The control:** `newTagCount` / `TagCount` — a read-only "tag and how many"
pair: a chip-styled label beside a badge-styled count.
`build(LuauUI, core, spec)` with `spec = { id?, label (required string),
count (Readable<number>, owner-held) }`. Non-interactive by construction: two
`UI.Text` leaves in a `UI.HStack`, no focusable primitive, no input contribution.

**Constraint honoured:** `src/controls/tag_count.luau` imports NOTHING. Its
entire dependency surface is the injected `LuauUI` table, `core`, and `spec`
(`docs/extending/new-control.md` §3, `constitution.md` §13.1).

---

## Outcome

| Thing | Result |
|---|---|
| `./run-tests.sh` | **PASS, 2914 passed** (baseline before the exercise: 2906 — grew by 8) |
| `lune run tools/lune/check_registration_cli` | **PASS** (16 controls, 82 exports documented, 120 specs registered) |
| `lune run tools/lune/check_docs_cli` | **PASS** |
| `lune run tools/lune/check_prop_parity_cli` | **PASS** (not required — no new primitive property) |
| `lune run tools/lune/check_boundary` | **PASS** |
| `lune run tools/lune/check_surface_ledger` | **FAIL, as expected** — caught the unclassified new export (see phase 3) |
| Verdict | **A fresh author CAN succeed with only these docs** — with 12 recorded friction points, three of which are enforcement gaps rather than doc gaps |

---

## Phase 1 — scaffold, and the stamped red state

```
cd "/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/LuauUI"
lune run tools/lune/scaffold_cli control tag_count
```

```
scaffold: wrote src/controls/tag_count.luau
scaffold: wrote tests/tag_count.spec.luau
scaffold: registered in tests/run.luau
scaffold: registered in tests/conformance/controls_registry.luau
scaffold: registered in src/init.luau
scaffold: registered in docs/reference/api.md
scaffold: done. Loop: implement until ./run-tests.sh is green (the stamped spec fails on purpose),
then: lune run tools/lune/check_registration_cli && lune run tools/lune/gate phase-4-hardening
```

`./run-tests.sh` → `14 failed, 2902 passed`. Ten of the fourteen are the
stamped TODO/input/affordance/hot-switch cases — the intended red step. **Four
are not**, and are the subject of friction item F-1:

```
no reusable framework control hardcodes a theme-owned metric
  ✗ the framework surface is clean
      theme drift lint FAILED:
src/controls/tag_count.luau:25: hardcoded textSize in a reusable framework surface — "UI.Text({ id = "Todo", text = "TagCount: unimplemented", textSize = 14 }),". Use a theme metric name (a spacing step, a typography role, or a dotted snapshot path such as "targetSizes.minimum"), or add an entry to the ALLOWLIST in tools/lune/check_theme_drift.luau with the reason it is deliberately theme-independent.
  ✗ catches a hardcoded dimension in a control
      tests/theme_drift.spec:34: expected 2 to be 1
  ✗ zero is not a metric: 'this container adds no spacing' stays legal
      tests/theme_drift.spec:68: expected false to be true
  ✗ a comment describing a literal is not a violation
      tests/theme_drift.spec:74: expected false to be true
```

---

## Phase 2 — the DELIBERATE-OMISSION probe

Control code and a basic spec were completed, then three obligations were
deliberately left undone:

- **(a)** `docs/reference/api.md` left as the scaffolded TODO stub.
- **(b)** the registry row's `inputProofs` / `affordanceProofs` left exactly as
  stamped — full interactive proof sets citing nine case names, none of which
  exist in the spec any more (no real decision was made about them).
- **(c)** the dump-determinism case (playbook step 2.5) not written.

### `./run-tests.sh` — verbatim

```
extension checker (UI-AGENT-001)
  ✗ the live repository passes every registration rule
      tests/extension_checker.spec:48: checker problems:
  control TagCount: pointer input proof 'TagCount pointer: a tap activates through the presenter (device-true)' is not found verbatim in any spec that tests/run.luau registers (rule b)
  control TagCount: touch input proof 'TagCount touch: a touch tap/pan drives the control (device-true)' is not found verbatim in any spec that tests/run.luau registers (rule b)
  control TagCount: keyboard input proof 'TagCount keyboard: focus + Return drives the control' is not found verbatim in any spec that tests/run.luau registers (rule b)
  control TagCount: gamepad input proof 'TagCount gamepad: focus + ButtonA drives the control' is not found verbatim in any spec that tests/run.luau registers (rule b)
  control TagCount: pointer affordance proof 'TagCount pointer affordance: the pointer structural idiom (hover/direct-drag/wheel)' is not found verbatim in any spec that tests/run.luau registers (rule b, paradigm)
  control TagCount: touch affordance proof 'TagCount touch affordance: the touch structural idiom (44px/naked-pan-scroll/edit-grip)' is not found verbatim in any spec that tests/run.luau registers (rule b, paradigm)
  control TagCount: keyboard affordance proof 'TagCount keyboard affordance: the keyboard structural idiom (focus ring/Navigate/Activate/Adjust)' is not found verbatim in any spec that tests/run.luau registers (rule b, paradigm)
  control TagCount: gamepad affordance proof 'TagCount gamepad affordance: the gamepad structural idiom (focus/grab/A-B/ten-foot)' is not found verbatim in any spec that tests/run.luau registers (rule b, paradigm)
  control TagCount: hotSwitch affordance proof 'TagCount hot-switch: in-flight state resolves CARRY or CANCEL on a class flip' is not found verbatim in any spec that tests/run.luau registers (rule b, paradigm)

  ✗ the live repository proves the four-input story for every interactive control
      tests/extension_checker.spec:233: expected 9 to be 0

  ✗ the live repository proves the PARADIGM axis for every interactive control
      tests/extension_checker.spec:328: expected 9 to be 0

  ✗ build/mount/render/dispose returns every registry to baseline
      tests/tag_count.spec:129: expected 11 to be 0

4 failed, 2909 passed
```

(The fourth failure was my own bug, not an omission — see friction item F-8.)

### `lune run tools/lune/check_registration_cli` — verbatim

```
check_registration: FAIL [UI-AGENT-001] — 9 problem(s):
  - control TagCount: pointer input proof 'TagCount pointer: a tap activates through the presenter (device-true)' is not found verbatim in any spec that tests/run.luau registers (rule b)
  - control TagCount: touch input proof 'TagCount touch: a touch tap/pan drives the control (device-true)' is not found verbatim in any spec that tests/run.luau registers (rule b)
  - control TagCount: keyboard input proof 'TagCount keyboard: focus + Return drives the control' is not found verbatim in any spec that tests/run.luau registers (rule b)
  - control TagCount: gamepad input proof 'TagCount gamepad: focus + ButtonA drives the control' is not found verbatim in any spec that tests/run.luau registers (rule b)
  - control TagCount: pointer affordance proof 'TagCount pointer affordance: the pointer structural idiom (hover/direct-drag/wheel)' is not found verbatim in any spec that tests/run.luau registers (rule b, paradigm)
  - control TagCount: touch affordance proof 'TagCount touch affordance: the touch structural idiom (44px/naked-pan-scroll/edit-grip)' is not found verbatim in any spec that tests/run.luau registers (rule b, paradigm)
  - control TagCount: keyboard affordance proof 'TagCount keyboard affordance: the keyboard structural idiom (focus ring/Navigate/Activate/Adjust)' is not found verbatim in any spec that tests/run.luau registers (rule b, paradigm)
  - control TagCount: gamepad affordance proof 'TagCount gamepad affordance: the gamepad structural idiom (focus/grab/A-B/ten-foot)' is not found verbatim in any spec that tests/run.luau registers (rule b, paradigm)
  - control TagCount: hotSwitch affordance proof 'TagCount hot-switch: in-flight state resolves CARRY or CANCEL on a class flip' is not found verbatim in any spec that tests/run.luau registers (rule b, paradigm)
hint: docs/extending/ has the playbook for each extension class; tools/lune/scaffold stamps complete skeletons
```

Exit 1.

### `lune run tools/lune/check_docs_cli` — verbatim

```
check_docs: PASS (8 documents, 77 surface anchors, 64 local links, 7 themes exports documented, 24 scenario steps, 10 example packages, 17 asset files, 11 stale phrases absent)
```

Exit 0.

### What the probe proved

| Omission | Caught? | By what | Actionable? |
|---|---|---|---|
| (b) registry proofs left stamped / undecided | **YES** | `run-tests.sh` (3 checks) and `check_registration_cli` | **Exemplary.** Nine separate problems, each naming the control, the class, the exact case string, and the rule id (`rule b` / `rule b, paradigm`). A fresh author knows precisely what to do. |
| (a) api.md left as the TODO stub | **NO** | nothing | Zero failures from all three commands. See F-2. |
| (c) dump determinism case skipped | **NO** | nothing | Zero failures from all three commands. See F-3. |

Two of the three deliberate omissions passed every gate. The enforcement is
excellent on the axis it was built for (four-input + paradigm) and silent on the
two obligations the same playbook states with equal force.

---

## Phase 3 — satisfying every obligation properly

**Non-interactive decision.** The docs DID tell me: `docs/extending/new-control.md`
§5, final sentence (line 225): *"A non-interactive control declares
`inputProofs = false` **and** `affordanceProofs = false`."* It is one sentence at
the end of ~35 lines devoted to the four-input bar, and the scaffold stamps the
opposite; see F-5. The registry rows for `AsyncImage` and `pathShapes` confirmed
the shape.

Changes made:
1. `tests/conformance/controls_registry.luau` — replaced the nine stamped proof
   citations with `inputProofs = false` / `affordanceProofs = false` plus a
   comment stating WHY the control is non-interactive.
2. `tests/tag_count.spec.luau` — added the dump-determinism case; fixed the
   neutrality case (`controller.dispose()`, F-8).
3. `docs/reference/api.md` — replaced the TODO stub with a real entry: signature,
   spec-field table, return surface, four invariants, worked example (plus the
   missing blank line before the heading, F-11).
4. `src/controls/tag_count.luau` — theme roles instead of the stamped literal
   (F-1), `table.freeze` on the return per constitution §6 (F-7).

### Final results

```
$ ./run-tests.sh
TagCount control
  ✓ builds, mounts, and renders headlessly with no error
  ✓ paints the label as a chip and the count as a badge
  ✓ changing the owner-held count repaints with no factory rerun
  ✓ rejects a missing `label` at BUILD, naming the control and the field
  ✓ rejects a `count` that is not a Readable at BUILD
  ✓ rejects an unknown spec key, listing the legal set
  ✓ dump() is deterministic and reflects the live count
  ✓ build/mount/render/dispose returns every registry to baseline

2914 passed
```

(2906 before the exercise → 2914; +8 cases, count GROWN.)

```
$ lune run tools/lune/check_registration_cli
check_registration: PASS (16 controls, 82 exports documented, 120 specs registered, 14 interactive controls prove four-input, 14 prove the paradigm axis)

$ lune run tools/lune/check_docs_cli
check_docs: PASS (8 documents, 77 surface anchors, 64 local links, 7 themes exports documented, 24 scenario steps, 10 example packages, 17 asset files, 11 stale phrases absent)

$ lune run tools/lune/check_prop_parity_cli
check_prop_parity: PASS (24 classes, 414 properties, 2 diagnosed, 448 typed fields)

$ lune run tools/lune/check_boundary
boundary: PASS (89 src files, 297 consumer files) -> artifacts/boundary.json
```

### `check_surface_ledger` — the expected FAIL, verbatim

```
$ lune run tools/lune/check_surface_ledger
check_surface_ledger: FAIL — 1 problem(s):
  - top-level export 'newTagCount' is not classified in the surface ledger
```

Exit 1. **The ledger was NOT edited.** This is the constitution's own coverage
check working exactly as designed: a brand-new public export reached green tests
and two green checkers without anyone classifying it against the kind ladder.
The message is specific and actionable *if you know the ledger exists* — which is
friction item F-6, because the control playbook never mentions it.

---

## FRICTION LOG

Twelve points where the public docs were ambiguous, wrong, silent, or
contradicted by the tooling. **E** = enforcement gap, **D** = documentation gap,
**S** = scaffold defect.

### F-1 (S+D) — the scaffold stamps code that fails the repo's own lint, and poisons three unrelated self-tests

`scaffold_cli` stamps `src/controls/<name>.luau:25`:

```lua
UI.Text({ id = "Todo", text = "TagCount: unimplemented", textSize = 14 }),
```

The very first `./run-tests.sh` after scaffolding is therefore red with FOUR
failures a fresh author did not cause and cannot map to their own work:
the theme-drift lint's real finding, **plus** `tests/theme_drift.spec:34`
(`expected 2 to be 1`), `:68` (`expected false to be true`) and `:74`
(`expected false to be true`) — the lint's OWN self-tests, which count
violations over the live tree and are thrown off by the stamped literal.

Compounding it: `docs/extending/new-control.md` never mentions the theme-drift
lint, `tools/lune/check_theme_drift.luau`, or the requirement to use theme
metric names, in any of its six sections. The only place a fresh author learns
that `textSize` takes a role name is `docs/reference/api.md:256` and the
"Theme metric names" paragraph at `api.md:261`, neither of which the playbook
cites. I found the rule from the failure message, not from the docs.

**Expected:** the scaffold stamps `textSize = "body"`; the playbook §3 gains a
bullet "theme-owned numbers are names, never literals (api.md §Theme metric
names) — the suite's theme-drift lint enforces it".

### F-2 (E) — nothing catches the TODO api.md stub

Omission (a) sailed through all three commands. `check_docs_cli` printed PASS
with this in `docs/reference/api.md`:

> `LuauUI.newTagCount(LuauUI, core, spec) -> { blueprint, dump, dispose }` —
> TODO: one-paragraph description, the spec shape, invariants, and a short
> usage example (scaffolded stub — the registration checker requires this
> anchor; **the docs-accuracy review requires it to be REAL**).

The stub is self-aware and still unenforced. `check_registration`'s coverage is
heading-anchored (constitution §14: *"`check_registration` enforces
heading-anchored coverage"*), so `### newTagCount` + one TODO sentence satisfies
it. Constitution §14 also says *"Documentation states what ships. A claim the
code does not honor is a defect of the same severity as the reverse"* — a TODO
is the null claim and it passes.

**Expected:** `check_docs` already greps for stale phrases ("11 stale phrases
absent"), so the mechanism exists — add `TODO:` inside a surface anchor to it.

### F-3 (E) — nothing catches a missing dump-determinism proof

Omission (c) produced zero failures. The registry row's `dumpFunction =
"function dump"` is a source-TEXT check ("cite the dump DEFINITION exactly"),
not a behavioural one. Yet `docs/extending/new-control.md` §2.5 makes it a
minimum of the control contract (*"**Dump determinism**: `dump()` twice →
identical"*) and `constitution.md` §6 makes it a rule (*"`dump()` is
deterministic (two calls, identical result)"*). The asymmetry is stark: the
input/affordance axes are enforced case-name by case-name, and the dump axis is
enforced by grepping for the string `function dump`.

**Expected:** a `dumpProof = { "<case name>" }` registry field validated exactly
like `inputProofs` (rule b), or `dump = false` + reason as today.

### F-4 (the positive control) — omission (b) was caught superbly

Recorded here as the standard the other two should meet: nine problems, each
naming the control, the class, the exact case string, the rule id, and a
closing `hint:` line pointing at `docs/extending/`. I needed no further
investigation to fix it. This is what an actionable failure looks like.

### F-5 (S+D) — the non-interactive escape hatch is a single trailing sentence, and the scaffold stamps the opposite

The rule is at `docs/extending/new-control.md:224-225`, the last sentence of §5,
after ~35 lines about the four-input bar. Meanwhile the scaffold stamps, into
BOTH `src/controls/tag_count.luau` (lines 29-52) and the registry row (lines
599-619), a full interactive proof set plus comment blocks that describe only
interactive escape hatches:

- source comment: *"Fill only your control's idioms."*
- registry comment: *"If your control owns no in-flight state, set
  hotSwitch = false and delete the stamped hot-switch spec case."*

Neither says "if your control is not interactive at all, set both to `false` and
delete all nine cases". An author who follows the stamped comments rather than
re-reading §5's last line will write nine meaningless interactive tests for a
label.

**Expected:** the scaffold's stamped registry comment carries the non-interactive
alternative verbatim, and §5 states it BEFORE the four-input paragraph, not after.

### F-6 (D) — the playbook's gate list omits the two checks that actually gate a new export

`docs/extending/new-control.md` §5 lists, "in order": `./run-tests.sh`,
`check_registration_cli`, `check_prop_parity_cli`, `gate phase-4-hardening`.

It does **not** list `check_docs_cli` — which `constitution.md:12-14` names as
one of the four enforcers — and it does **not** list `check_surface_ledger`,
which is the only check my work failed. A fresh author following §5 verbatim
never runs it, never learns the ledger exists, and hands back work the stage's
own coverage check rejects.

Worse, the ledger is undiscoverable from the author's path: `constitution.md:11`
names `artifacts/api-architecture-consistency/surface-ledger.md`, and
`constitution.md` §13 points a control author at `new-control.md`, which never
mentions it. There is no documented row format anywhere in `docs/`.

**Expected:** a step 4b in the playbook — "classify your export in the surface
ledger" with the row shape and the kind-ladder question — and both checkers
added to the §5 command list.

### F-7 (S) — the scaffold contradicts constitution §6 on freezing

`constitution.md` §6: *"Composite controls return a **frozen** table
`{ blueprint, …extras, dump, dispose }`."* The scaffold stamps a plain
unfrozen `return { … }`. Two authorities, and only one is right. I followed the
constitution (`table.freeze`). A fresh author who trusts the scaffold — the
document that claims to stamp "complete skeletons" — ships an unfrozen return
and nothing catches it.

**Expected:** the scaffold stamps `return table.freeze({ … })`.

### F-8 (D) — registry neutrality has no recipe for the bare mount+renderer path

Playbook §2.6 says to snapshot the baseline after the long-lived singletons and
points at `tests/table.spec.luau` for the house pattern — which uses a
**presenter** and tears down with `pres.dismiss(handle)`. A non-interactive
control has no reason to build a presenter, so I used the documented bare path
(`LuauUI.mount` + `LuauUI.renderer.attach`, api.md §Mounting and rendering) and
got:

```
tests/tag_count.spec:129: expected 11 to be 0
```

No indication of which registry leaked (the loop compares five counter keys) and
no hint about the fix, which was the undocumented obligation to call
`controller.dispose()`. `renderer.attach`'s entry lists `dispose()` as one of 27
controller members in a table cell ("Render cycle | `initialRender()`,
`refresh()`, `dispose()`") and nowhere says that skipping it leaks core
resources.

**Expected:** the playbook's §2.6 bullet names the bare-path teardown order
(`controller.dispose()` → `root.dispose()` → `control.dispose()` → your signals),
and/or the neutrality idiom reports WHICH counter key drifted.

### F-9 (D) — no documented idiom for unknown-key rejection on a control spec

`constitution.md` §4 is unambiguous that the strict-boundary rule *"applies to
modifier specs and control specs exactly as to `UI.*` props"*, and gives the
error grammar in one example (`LuauUI newStepper('Volume'): spec.value must
be…`). But:

- no public helper exists for it — `api.md:177` "Tooling surface: `UI.schema`,
  `UI.isReadable`, `UI.PROP_DIRTY`" offers a schema for **primitives** and a
  readable predicate, nothing that validates a control spec;
- `newChip` — the nearest sibling and the cited pattern — documents validation
  only for `selected` (api.md:3239) and says nothing about unknown keys;
- so the author hand-rolls the loop and guesses the message grammar (did-you-mean?
  the legal set inline? level-0 error?) from one example sentence.

I wrote the loop by hand and copied the `LuauUI newX('<id>'): …` prefix grammar
from that single §4 example.

**Expected:** either export a `UI.validateSpec(who, spec, legalKeys)` helper, or
state in new-control.md §3 that control specs must hand-roll it and give the
grammar (prefix, did-you-mean, legal-set listing).

### F-10 (D) — every cited spec exemplar is a large interactive control

Playbook §2 says *"see `tests/table.spec.luau` and
`tests/virtualization.spec.luau` for the house style"*; §3 cites
`tests/auto_input.spec.luau`, `tests/paradigm_table.spec.luau`,
`tests/paradigm_textinput.spec.luau`; §5 nothing. Every one of them is an
interactive control with a presenter harness. There is no cited exemplar for a
non-interactive composite. I found `AsyncImage` and `pathShapes` only by reading
the registry rows themselves — and `AsyncImage` is a poor model anyway, because
it is constitution exception **E-8** (caller-scope, no `dump`, no `dispose`).

**Expected:** name a non-interactive exemplar in §2 (or accept `newProgressView`
/ `newLabel` as one) so the smallest possible control has a smallest possible
pattern.

### F-11 (S) — the api.md stub is inserted with no blank line before its heading

After scaffolding, `docs/reference/api.md:3940-3941` reads:

```
both flags belong to the caller.
### `newTagCount`
```

Every other heading in the 3946-line file is preceded by a blank line. Cosmetic,
but it is the first thing in the author's diff, and it reads as "the tool put my
section inside someone else's paragraph". Fixed by hand.

### F-12 (D) — `schema = "luauui-<name>-dump/N"` does not say which name

`constitution.md` §6 requires the dump to carry `schema = "luauui-<name>-dump/N"`.
Every shipped example uses the lowercase control WORD (`luauui-chip-dump/1`,
api.md:3250). The scaffold stamped the MODULE FILE name:
`luauui-tag_count-dump/1`. For a single-word control these coincide; for a
two-word control they do not, and nothing says which is canonical (`tagcount`?
`tag_count`? `TagCount`?). I kept the scaffold's spelling on the grounds that the
tool is the de-facto authority, and documented it in the api.md entry.

**Expected:** constitution §6 states the derivation (snake_case module name, or
lowercased control name) in one clause.

---

## Verdict

**YES — a fresh author can succeed with only these docs.** I built, tested,
registered, and documented a new public composite control without reading a
single line of `src/**` other than the file the scaffold stamped for me, and
without importing anything internal into it. Every capability the playbook
demands was reachable from the public API: `LuauUI.UI.*`, `LuauUI.mount`,
`LuauUI.renderer.attach`, `LuauUI.newEnvironment`, `core:scope/:signal/:memo`,
`UI.isReadable`. The scaffold really does register all six touch points, and the
four-input/paradigm enforcement is the best failure-message writing I have seen
in a codebase — it names the control, the class, the exact string, and the rule.

**But the success is not evenly supported, and two of my three deliberate
omissions shipped green.** The three findings that matter:

1. **The enforcement is one-axis deep (F-2, F-3).** Input and paradigm proofs are
   verified case-name by case-name; the api.md entry is verified only as a
   heading anchor and the dump contract only as the source text
   `function dump`. A fresh author who follows the checkers rather than the prose
   ships a TODO doc and an unproven dump — and the tools congratulate them.
2. **The scaffold and the constitution disagree (F-1, F-5, F-7).** The tool
   stamps a lint violation, an interactive-only comment block, and an unfrozen
   return. The scaffold is the document a fresh author trusts most, because it is
   the one that runs. Every divergence between it and the constitution is a
   defect that will be copied.
3. **The last gate is invisible from the author's path (F-6).** `check_surface_ledger`
   is the only check my finished work failed, and the playbook a control author is
   told to follow step-by-step never names it, the ledger, or its row format.

Fix those three classes and the answer moves from "yes, with 12 friction points"
to "yes, cleanly".

---

## Files created / edited by this exercise

| File | Change |
|---|---|
| `src/controls/tag_count.luau` | **created** (scaffolded, then implemented) |
| `tests/tag_count.spec.luau` | **created** (scaffolded, then implemented — 8 cases) |
| `tests/run.luau` | scaffold registration (`require("./tag_count.spec")`) |
| `tests/conformance/controls_registry.luau` | scaffold row, then edited to `inputProofs = false` / `affordanceProofs = false` |
| `src/init.luau` | scaffold export (`newTagCount`) |
| `docs/reference/api.md` | scaffold stub, then replaced with the real `### newTagCount` entry |
| `artifacts/api-architecture-consistency/fresh-author-exercise.md` | this artifact |

**Not** edited: `artifacts/api-architecture-consistency/surface-ledger.md`
(deliberately — its FAIL is part of the deliverable),
`tools/lune/gate_manifest.luau`, `phases.json`.
