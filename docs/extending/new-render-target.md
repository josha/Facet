# Playbook: adding a new render target

Audience: an agent with no prior context. A render target is WHERE the
rendered tree materializes (a `ScreenGui`, a billboard over a world part, a
surface on a part). The renderer is engine-free and talks only to the
RenderTargetAdapter contract — a new target is a new adapter implementation,
nothing more. Shipped examples: `tests/lib/fake_target.luau` (headless),
`src/client/screen_target.luau` (production ScreenGui),
`src/client/billboard_target.luau` (billboard; see also its decision record
`docs/adr/ADR-0009-billboard-target.md` and the contract module
`src/render/target_contract.luau`).

Read [`../reference/constitution.md`](../reference/constitution.md) first — the
rules your addition must follow.

## 1. Scaffold

```
lune run tools/lune/scaffold_cli adapter <lower_snake_name>
```

stamps `src/client/<name>.luau` with the six required methods
(`createRoot`, `create`, `setRect`, `setProp`, `remove`, `destroyRoot`) and
`tests/<name>.spec.luau` with its contract-conformance stub, plus the
`tests/run.luau` line that registers it.

Note `create`'s full signature —
`create(rootHandle, path, class, decorationHint?, createOpts?)`. Those last two
are CREATION-TIME facts (which decoration slot this node is skinned as; whether
its engine class must be a CanvasGroup so a subtree can fade as one). Neither
can arrive as a later prop write, so an adapter that drops them can never skin
or group, and nothing will tell you.

## 2. Contract conformance, failing first

`src/render/target_contract.luau` **is the authority** on the seam, and it
declares three lists — read its per-method consequence comments, they are the
specification:

- **REQUIRED** — the six the renderer calls unconditionally. Missing one means
  the target cannot be mounted.
- **OPTIONAL** — feature-detected with `~= nil`. Each absence is ONE named
  degrade, never a crash: `setActivateHandler`, `setFocusVisual`, `enableHover`,
  `enableDisclosure` (without it, no pointer-dwell/touch-long-press disclosure
  engagement — focus-driven disclosure still works), `setZOrder`,
  `setPointerHandlers`, `setTextInputHandlers`, `setScrollRegion`,
  `setScrollPosition`, `observeScroll`, `getScrollPosition`, `setScrollHandler`,
  `setEngineSelection`, `setVisible`, `setDragDetector`,
  `setTouchGestureHandlers`, `setHitRect`, `measureTextWidths`,
  `setRootVisible`, `setNativeTransitionsEnabled`, `setReducedMotion`,
  `setRootDisplayOrder`, `setScrollIndicatorPolicy`.
  The two motion names are the two halves of one fact the renderer pushes from
  the environment: `setNativeTransitionsEnabled` reaches a StyleSheet's declared
  transitions, `setReducedMotion` reaches the target's own bespoke tweens.
  Implement `setReducedMotion` if your target animates anything itself — without
  it a player's reduced-motion setting silently does nothing.
  Decide each deliberately — "not implemented yet" is a legal answer, a
  silently missing method is not. (Five of these were CALLED by the renderer
  and undeclared until 0.8.0, so a target could pass the checker with
  `#optionalAbsent == 0` and still ship with no hit-target floor, no wheel
  channel and no display order.)
- **THEME** — `nativeStyleInfo`, `themeRootGui`, `setThemePackage`,
  `relinkThemeSheet`. Without them `theme_controller.install` cannot theme this
  target: it degrades to fallback paint, and in native mode ERRORS unless the
  caller passes `opts.rootGui`. Theming is one capability with one consequence,
  which is why it is its own list.

`target_contract.check(adapter)` reports all three (`missing`,
`optionalAbsent`, `themeAbsent` / `themeable`).
`tests/render_target_contract.spec.luau` shows the conformance pattern (the
FakeTarget satisfies every method; a pixel-canvas fixture renders through
the full pipeline). Grow the stamped spec (already registered in
`tests/run.luau`) so that it:

1. asserts your adapter satisfies the contract (required methods, optional
   ones declared honestly);
2. renders a small screen through `mount → renderer.attach(yourAdapter) →
   initialRender` and asserts created nodes/rects (headlessly if the target
   has any headless-representable core; otherwise test the adapter's pure
   logic and leave engine writes behind the same capability-detection
   pattern as [new-engine-feature.md](new-engine-feature.md));
3. proves teardown: `destroyRoot` releases every instance/connection the
   adapter created (registry/leak counters at baseline).

### `measureTextWidths` — the one optional method with a correctness trap

Everything else on the optional list degrades to "the feature is absent".
This one degrades to "text boxes stay conservatively over-reserved", which is
also safe — but if you implement it, implement it correctly, because a width
you return is cached for the session and never asked for again.

The renderer hands you WORDS, not laid-out strings (`{ font, size, word }`),
and takes back the same rows with a `width`. Return `nil` for anything you
cannot measure; the estimator's safe bound stands. You may call `done` more
than once for the same batch — the renderer re-solves only when a width
actually changed.

**Measure the words twice.** On Roblox, `GetTextBoundsAsync` returns different
answers during the first moments of a session than once it has settled, gives
them without complaint, and gives them *stably* — so a "wait until it stops
changing" gate passes straight through the bad window. The shipped adapter
therefore re-reads every batch 1.5s later and corrects anything that moved
(`src/client/text_premeasure.luau`). Assume your engine has the same hazard
until you have disproved it on the running target, not in a REPL.

Two more things that are easy to get wrong: a lone space does not survive into
text bounds, so derive the space advance as `bounds("x x") - bounds("xx")`;
and this method must not yield the renderer — do the work in your own task and
answer through `done`.

## 3. Target-specific policy

Answer explicitly (in the module header + an ADR if the answers are
non-obvious): who owns the container instance; what `Adornee`/placement
semantics apply; pixels-per-stud or resolution policy; input routing (does
the target receive pointer events? focus visuals?); clipping; and the
performance ceiling (add a perf scene when the target changes cost
characteristics). World-space targets are NOT production-ready until the
design's world-target checklist (local ownership, replicated adornee,
legibility, input, clipping, perf, conformance) is answered — say which
items you are deferring.

## 4. Docs + gates

api.md entry if the target is public; guide paragraph on when to use it;
`./run-tests.sh` + `lune run tools/lune/check_registration_cli` +
`lune run tools/lune/gate phase-4-hardening` all exit 0. Evidence: spec
transcript (red → green), and a Studio drive artifact under
`artifacts/studio/` when the target has a visual component.

**Parity-checker caveat.** `lune run tools/lune/check_prop_parity_cli` pins the
`setProp` chain against **`src/client/screen_target.luau` only** — it reads that
one file's handler switch and knows nothing about yours. A green parity run is
therefore not evidence about your target. The prop set your adapter must handle
is `renderer.EMITTED_PROPS`; pin it yourself the way
`tests/render_target_contract.spec.luau` does ("every prop the renderer can emit
is handled"), because a target that silently ignores a written prop is the SF-M9
defect class — green headless, dead on the device.
