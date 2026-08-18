# Vendored: Fusion 0.3

- **Upstream:** https://github.com/dphfox/Fusion, tag `v0.3-beta` (the 0.3 release; `src/` copied verbatim, then patched as below). License: `LICENSE` (MIT).
- **Why:** Phase 0 foundation bake-off candidate (design §3 Foundation, §17 Phase 0). Pinned at 0.3 per the build directive.

## Local patches (keep when updating)

1. **Require transform** — every Roblox instance-path require (`require(script.Parent.X)`, `local Package = script.Parent` aliases) is rewritten to Luau require-by-string form (`./`, `../`, and `@self/` inside `init.luau`) so the source loads under both Lune and the engine. Mechanical transform: `scratchpad/transform_fusion.py` at vendor time; alias lines are commented `[Facet vendor patch]`.
2. **`init.luau` scheduler guard** — `RobloxExternal` auto-bind is wrapped in `if game ~= nil` so requiring under Lune does not touch `RunService`. Headless hosts must bind `tests/lib/fusion_lune_external.luau` first.

## Headless limits

- The root `init.luau` still cannot load under plain Lune: `Instances/defaultProps.luau` reads `Enum.*` at require time (engine-only by design). Headless code uses the state-subset facade `tests/lib/fusion_headless.luau` (Value/Computed/ForX/Observer/scopes/peek/Contextual/Safe).
- `fusion_lune_external.doTaskImmediate` runs callbacks synchronously (matches RobloxExternal's `task.spawn` run-now semantics). The upstream SpecExternal queue-and-yield variant kills Lune's main thread: the suite truncates silently with exit 0.
