# An enum-valued prop that accepts any string turns a typo into invisible UI, and the tag/rule architecture hides it perfectly

Observed 2026-07-24 (Milestone 0, roadmap Step 3). A Studio capture of a brand-new
fixture showed a three-cell `UI.Grid` that was simply not there. The geometry dump said
the cells existed at the correct column origins with the correct height. The style dump
said each one carried the tag `luau-surface-panel` and resolved
`BackgroundTransparency == 1`.

`"panel"` is not a surface role. The roles are
`base | raised | control | chip | badge | accent | scrim | plain`.

Nothing failed. The blueprint accepted the string, the adapter turned it into a
CollectionService tag by concatenating a prefix, no StyleRule matched that selector, and
the node kept the sheet's "invisible until a surface says otherwise" default. The
fallback (explicit-write) path had the same hole from the other direction: a chain of
`elseif surface == "..."` branches with no `else`, so an unknown role fell through
silently.

Two SHIPPED controls carried the same typo and had been rendering with no background:

- `src/controls/popup_button.luau` — the floating popup list had no panel behind it;
- `examples/gallery/examples/05_word_game.luau` — the results modal had no surface.

The same class of hole existed on `Text.role` (only `"secondary"` is meaningful;
`role = "title"` did nothing), `anchor`, `align`, `alignH`/`alignV`, `overflow`, and
`ScrollView.axis`.

**Why the tag architecture makes this worse, not better.** A prefix-plus-value tag scheme
is open by construction: any value produces a syntactically valid selector. The engine
cannot help — an unmatched selector is a normal, expected condition, not an error. So the
usual safety net (the renderer or the engine rejecting a bad value) does not exist for
styled state at all.

**Rule:** every string-valued public prop with a closed value set must declare that set in
`src/blueprint_schema.luau` (`enum = { ... }`) and be validated at construction. A closed
set is exactly the information that makes the error message useful:
`UI.VStack.surface expects string, got string — one of base | raised | control | chip |
badge | accent | scrim | plain`.

Corollaries:

- When adding a role/kind/mode value to an adapter, add it to the schema enum in the same
  change. `tools/lune/check_prop_parity_cli` catches the documentation half of the drift
  but cannot infer a value set from an `elseif` chain.
- A tag-based state hand-off needs its value set validated at the AUTHORING boundary,
  because there is no later boundary that will reject it.
- Do not "fix" this by giving the adapter an `else` that paints a default. That converts
  an invisible bug into a wrong-looking one and still hides the typo.
