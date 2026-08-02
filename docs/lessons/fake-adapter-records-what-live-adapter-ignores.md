# A generic fake adapter records the props the live adapter ignores

**Found:** 2026-07-27, the Sponsor capability re-audit (acceptance row SF-M9). The
keyboard keep-visible shift — a shipped feature with green specs — had never moved
a pixel on a device.

The channel looked complete from every angle a test could see it from:

- `render/authority.luau` declared `transform` and `transparency` as
  **presentation** properties;
- the presenter observed each text field's `keepVisibleOffset` and called
  `controller.setPresentationOffset(dy)`;
- the renderer asserted the authority and wrote
  `adapter.setProp(root, "transform", { x = 0, y = -dy }, "presentation")`;
- `FakeTarget.setProp` did `handle.props[prop] = value`, so
  `tests/text_input.spec.luau` could read `props.transform.y < 0` back and pass;
- `screen_target.setProp` — a string-keyed `if/elseif` chain over prop names — had
  **no branch for either name**. The write fell off the end of the chain and
  returned.

Two specs asserted the shift, both green, for as long as the feature existed.

**The mechanism is the generality of the fake.** A headless adapter that records
*any* prop cannot fail on a prop nobody implemented — it faithfully proves that the
framework EMITTED something, which is the half that was never in doubt. Method-level
conformance could not catch it either: `target_contract.check` asks "does this
adapter have a `setProp`", and both adapters had one. The divergence lived one level
below the method, in a switch on strings, where nothing was enumerable.

**Rule: when a seam dispatches on a NAME, the set of names is part of the contract
and must be declared on both sides.** A prop, an event kind, a tag, a step name —
anything a `==` chain branches on. Recording an unknown one is worse than refusing
it, because a recorded write reads as a pass.

**What now exists** (`tests/render_target_contract.spec.luau`, "adapter prop
parity"):

- `renderer.EMITTED_PROPS` — every name the renderer can hand to `setProp`, built
  from `BINDING_PROPS` ∪ `STYLE_PROPS` ∪ `DIRECT_PROPS`, where the last table names
  the dedicated seam each write rides so an exemption is a decision on the record;
- `fake_target.HANDLED_PROPS` — the fake's declared list, and `setProp` **errors**
  on anything outside it, naming both files to fix;
- the live adapter's view read out of its own source (`prop == "…"`), because
  `screen_target` is client-only and cannot be required under Lune — the same
  technique `check_prop_parity` already used for exactly this seam;
- all three pinned against each other in both directions.

**The related trap, same defect class, worth stating separately:** a mirror that
proves *emission* proves nothing about *application*. The fix for this row was not
only a new branch — it was making the fake mirror the live adapter's composition
RULE (`rect + own transform + every ancestor's` → `node.presentedPosition`), the way
it already mirrored the per-view gradient's single reused child. That is what turned
"the prop was written" into "the node ends up in the right place", and it is what
caught the second half of the same defect: on the real client the instance tree is
**flat** (`docs/lessons/screen-target-tree-is-flat.md`), so even a `transform`
branch that moved the root node's own instance would have moved one transparent
frame and nothing the player can see.

**Ask, of every new adapter seam:** what does the fake do with input the live target
has not implemented? If the answer is "records it", the suite is measuring the
framework's intentions.
