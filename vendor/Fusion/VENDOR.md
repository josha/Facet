# Vendored: Fusion 0.3

- **Upstream:** https://github.com/dphfox/Fusion, tag `v0.3-beta` (the 0.3 release; `src/` copied verbatim, then patched as below). License: `LICENSE` (MIT).
- **Why:** Phase 0 foundation bake-off candidate (design §3 Foundation, §17 Phase 0). Pinned at 0.3 per the build directive.

## This does not ship, and it is not dead code either (RC review disposition, 2026-08-18)

Facet's reactive core is **candidate A**, `src/core/custom.luau` — the one the
library builds on and the only one `Facet.newCore` ever returns. This vendored
Fusion is **candidate B** and `src/core/imperative.luau` is **candidate C**: the
other two arms of the ADR-0002 bake-off, kept in the tree for one reason and
stated here so nobody has to guess it.

**The reason is that the benchmark stays runnable.** ADR-0002 chose A over B and
C on measured numbers. A decision whose losing arms have been deleted cannot be
re-checked, re-run against a newer Fusion, or defended when someone asks "how
much did that actually buy?" — it becomes an assertion. `bench/` still drives all
three through `src/core/contract.luau`, and that is the whole of the job these
files do.

**They are not entry points.** `Facet.newCore` returns candidate A;
`tools/lune/check_boundary.luau`'s consumer scan refuses a require of anything
under `src/core/` or `vendor/` from a game or an example, and would fail if one
appeared. Nothing in `src/` outside `src/core/fusion_adapter.luau` mentions
Fusion at all. If you are reading this because you want to *use* Fusion in a
Facet consumer, the answer is that you cannot, and `docs/adr/ADR-0002` is why.

## Local patches (keep when updating)

1. **Require transform** — every Roblox instance-path require (`require(script.Parent.X)`, `local Package = script.Parent` aliases) is rewritten to Luau require-by-string form (`./`, `../`, and `@self/` inside `init.luau`) so the source loads under both Lune and the engine. Mechanical transform: `scratchpad/transform_fusion.py` at vendor time; alias lines are commented `[Facet vendor patch]`.
2. **`init.luau` scheduler guard** — `RobloxExternal` auto-bind is wrapped in `if game ~= nil` so requiring under Lune does not touch `RunService`. Headless hosts must bind `tests/lib/fusion_lune_external.luau` first.

## Headless limits

- The root `init.luau` still cannot load under plain Lune: `Instances/defaultProps.luau` reads `Enum.*` at require time (engine-only by design). Headless code uses the state-subset facade `tests/lib/fusion_headless.luau` (Value/Computed/ForX/Observer/scopes/peek/Contextual/Safe).
- `fusion_lune_external.doTaskImmediate` runs callbacks synchronously (matches RobloxExternal's `task.spawn` run-now semantics). The upstream SpecExternal queue-and-yield variant kills Lune's main thread: the suite truncates silently with exit 0.
