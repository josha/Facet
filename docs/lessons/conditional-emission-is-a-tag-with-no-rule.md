# A tag applied by the NODE needs a rule emitted for every node, not per declared feature

**Found:** 2026-07-25, director round 5 of rich-skinning-v2 (a rung-2 per-view
slider thumb sat on a square opaque plate under `glossy-touch`).

Step 3.5's fix round produced the APPLICATION half of this lesson: *a tag whose
application depends on whether some other package feature is in use is not
applied at all* (a slot tag that only landed because some unrelated recipe caused
a decoration to be created). This is the same defect one level up, on the
EMISSION side.

`luau-skinned-<slot>` is earned by the **node**, from three independent routes:

1. the installed package declares a nine-slice recipe for the slot;
2. the installed package declares a layer stack for the slot;
3. a **view** supplies its own image for that slot (the rung-2 per-view override).

The suppression rules that tag selects were emitted by walking the package's
DECLARED recipes — routes 1 and 2 only. So route 3 produced a node carrying a tag
that no rule in the sheet matched, and the paint it was supposed to lift kept
painting. It was invisible to the suite because every spec asserted the rule for a
package that declares the slot.

**Rule: when a tag's presence is decided at runtime by the node, the rule that
consumes it must be emitted unconditionally.** Emitting per declared feature is
only safe when the feature is the *only* thing that can produce the tag. Ask
explicitly: what are ALL the routes to this tag, and does every one of them go
through the code that emits its rule?

The cost of unconditional emission is a fixed, countable number of inert rules
(here 4 slots x 3 = 12, censused rather than excused). The cost of conditional
emission is a live defect that no headless test sees.

**Detection that would have caught it:** a spec that walks every REFERENCE
package — including the flat ones and the ones that declare the slot's siblings
but not the slot — rather than only the fixture that declares everything.

## Third instance, 2026-07-26 (RS-A16-D4): "every package" is not "every SHEET"

The detection above was implemented and still missed the next one, because it
enumerated **packages** and the framework has a paint authority that is not a
package: with nothing installed, the live sheet is `sheet_model.build`'s BASE
SEED, and only `sheet_model.buildPackage` emitted the `Slot — <slot>` family. So
the four value-control surfaces of the **built-in default** — every unskinned
screen — were selected by no rule at all, `Frame default` (`BackgroundTransparency
= 1`) won, and the default progress bar was pixel-identical at 0 % and 100 %.

Two aggravating details worth remembering:

- the emitting loop's own comment said *"emitted for every package including the
  flat ones — a value control has to be visible under Studio Neutral too"*. The
  one path where it was not emitted was Studio Neutral. A comment stating the
  requirement is not the requirement being met;
- **no rule reads as invisible, not as unstyled.** Because "transparent until a
  surface says otherwise" is itself sheet-owned, a missing rule in this
  architecture is a *maximally* visible defect, not a cosmetic one.

**Rule: enumerate the SHEETS the framework can run, not the packages it ships.**
Two builders serving one requirement is the shape of this bug; the fix is one
shared emitter both call, never a second copy — a copy diverges silently and only
one of the two paths is ever exercised by the fixture in front of you.

**Detection that now exists** (`tests/theme_matrix_audit.spec.luau`, audit (e)):
drive `classifyTags` — the single function by which any Facet state reaches a
native selector — over its whole input domain and require every resulting tag to
be selected by at least one rule in *every* sheet the framework can run (the base
seed included), with the only exemptions computed from the same `chrome_slots`
functions the adapter uses. Enumerating from the classifier means a newly added
tag is required by construction rather than by someone remembering to extend a
list.
