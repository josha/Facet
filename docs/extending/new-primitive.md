# Adding a blueprint primitive

A **primitive** is a class the render target materialises — `UI.Text`,
`UI.ScrollView`, `UI.Path`. A **control** is composed out of primitives and
needs none of this; if you can build it from what already exists, read
[`new-control.md`](new-control.md) and stop here. Adding a primitive means the
framework grows a new kind of *box*, and every target has to know how to make
one.

Until 2026-08-17 this path had no playbook — `new-control.md` deferred it to
[`new-engine-feature.md`](new-engine-feature.md), which only covers adding a
*property* or a *modifier* to a class that already exists — and no checker.
`tools/lune/check_primitives.luau` is that checker now; every step below is a
thing it can see.

**Before you start:** a primitive is a permanent widening of the public surface
and of every render target's obligations. Three questions, in order:

1. Can a **composite** do it? A control that arranges existing primitives costs
   nothing outside its own file.
2. Can an existing class do it with **one more property**? That is
   `new-engine-feature.md`, and it is a much smaller change.
3. Is the box genuinely new — a different engine instance, or a different
   *layout* contract? Only then is it a primitive.

---

## 1. Declare the class in the schema

`src/blueprint_schema.luau` is the authority for what a class is: its
properties, their types, their enum sets, and which update classes a reactive
change to each one schedules.

```lua
Gauge = {
    props = {
        value = { types = { "number" }, required = true, dirty = { "paint" }, doc = "…" },
        -- shared props (id, width, height, …) come from the shared table
    },
    container = false,   -- can it hold children?
    structural = false,  -- true ONLY for mount-layer control flow (When/ForEach)
},
```

Two rules the schema enforces for you, and one it cannot:

- every property declares `dirty` — what a reactive change must invalidate. Get
  this wrong and a bound value repaints nothing (`paint`) or re-solves the whole
  tree (`measure`) forever;
- an enum property declares its closed set, and the value is checked wherever it
  lands — not only where it is authored;
- **the schema cannot tell you whether your class needs a `required` prop.** If
  it does, add its minimal legal form to `MINIMAL_PROPS` in
  `tools/lune/check_primitives.luau`, or the create-branch check below cannot
  build one and will say so by name.

## 2. Map it to an engine instance

`CLASS_TO_INSTANCE` in `src/client/screen_target.luau` names the Roblox class
the live adapter creates. **Omitting it is a decision, not an oversight**: a
class with no entry is created as a `Frame`, which is right for every container
and every box that paints only its own chrome.

```lua
local CLASS_TO_INSTANCE: { [string]: string } = {
    Text = "TextLabel",
    …
    Gauge = "ImageLabel",
}
```

`check_primitives` refuses a mapping for a class the schema does not declare — a
mapping that outlives its class is a `create()` branch for something that cannot
exist.

## 3. Write the `create()` branch — on BOTH targets

The live adapter (`src/client/screen_target.luau`) and the headless twin
(`tests/lib/fake_target.luau`) implement the same contract
(`src/render/target_contract.luau`), and a primitive only one of them can make
is a primitive the suite proves nothing about. The headless target is not a
mock: it is the second implementation that keeps the contract honest, and
`tests/render_target_contract.spec.luau` compares the two.

`check_primitives` proves this by DRIVING rather than reading: it mounts one
node of every non-structural class and asks the target for its handle. A class
that mounts and produces no handle fails, whatever the source looks like.

If your primitive owns engine children (a `Path`'s `Path2D` containers, a
`Stage`'s `WorldModel` and `Camera`), it also owns their destruction —
`remove()` and `destroyRoot()` both, and the connection census in
`screen_pointer.connectionCensus` should be able to see anything you connect.

## 4. Decide the layout contract

`src/render/layout_node.luau` translates a mounted node into a `solver.Node`.
Answer three questions there:

- **How does it measure?** Intrinsic size from its content (like `Text`), from a
  declared dim only, or from its children?
- **Does it arrange children?** A container declares its axis and how it
  distributes; a leaf declares neither.
- **Does it clip, scroll, or reserve?** `ScrollView` is the worked example: it
  is a clip host, it publishes a canvas extent, and it reserves a scrollbar
  gutter that siblings outside it can read back.

A primitive with no layout contract silently takes the leaf default. That is a
legitimate choice — say so in a comment, so the next reader knows it was chosen.

## 5. Register the control contract

`src/controls/contract.luau` carries the rest of the declared contract: focus
role, semantic actions, effective hit floor, accessibility summary.

```lua
Gauge = {
    focusRole = "none",
    actions = {},
    accessibility = "read-only value display; the value is announced, never focusable",
},
```

**This is not optional and it is not paperwork.** An unregistered class is
invisible to the four-input rule, the paradigm-axis rule and the hit-floor
enforcement — `Grip` was a focusable, pointer-handling control that no
four-input rule could see for exactly this reason. `check_primitives` fails a
schema class with no row here, and fails a row here with no schema class.

## 6. Tests

- a spec for the class itself: construction, refusals, every reactive prop's
  dirty class, and the layout contract from step 4;
- the render-target conformance pair (`tests/render_target_contract.spec.luau`)
  if you added a prop write;
- a **large-text fixture** in `tests/lib/large_text_fixtures.luau`, or an
  `UNSWEEPABLE` entry with a real reason. `LT8-COVER` fails a registry row that
  is neither;
- if the class is interactive, the four `inputProofs` and four
  `affordanceProofs` cases named in `tests/conformance/controls_registry.luau`.

## 7. Prove it

```
./run-tests.sh                                   # suite green, count grew
lune run tools/lune/check_registration_cli       # exports and specs registered
lune run tools/lune/check_prop_parity_cli        # schema / renderer / adapter / docs agree
python3 tools/check_source_size.py               # no module crossed the cap
```

`tests/primitive_registration.spec.luau` runs `check_primitives` as part of the
suite, so steps 1, 2, 3 and 5 are checked on every run — including the mutation
cases that prove the checker can still see each kind of drift.

## 8. Document it

`docs/reference/api.md` needs a `###` entry for the constructor with its
properties, its refusals and a short example; `check_registration` fails an
undocumented public export. If the primitive introduces a concept (a new kind of
box, a new layout behaviour), add a paragraph to the relevant `docs/guide/`
page — the reference says what it does, the guide says when to reach for it.
