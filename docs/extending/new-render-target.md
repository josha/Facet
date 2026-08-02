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

## 1. Scaffold

```
lune run tools/lune/scaffold_cli adapter <lower_snake_name>
```

stamps `src/client/<name>.luau` with the six required methods:
`createRoot`, `create`, `setRect`, `setProp`, `remove`, `destroyRoot`
(optional capabilities: `setZOrder`, `setActivateHandler`,
`setFocusVisual`, `setPointerHandlers`, plus your target-specific opts).

## 2. Contract conformance, failing first

`src/render/target_contract.luau` declares the required/optional surface and
`tests/render_target_contract.spec.luau` shows the conformance pattern (the
FakeTarget satisfies every method; a pixel-canvas fixture renders through
the full pipeline). Add a spec (register in `tests/run.luau`) that:

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
