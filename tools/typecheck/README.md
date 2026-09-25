# Native Luau type checks

`python3 tools/check_types.py` checks every Facet-owned module under `src/`, the public control witness, the gallery example modules in `examples/gallery/examples/`, the standalone consumer in `examples/consumer/src`, and generated negative probes. The consumer check uses a Rojo sourcemap, so its `require` calls resolve to the typed Facet module. A passing result requires strict directives, no type errors in owned source, witnesses or gallery examples, and rejection of every invalid public call. The checker records upstream dependency diagnostics separately; it does not claim to type-check Compose's implementation on Facet's behalf.

The public witness uses `Facet.controls(runtime)`, native Roblox properties and return types, Compose cells, and typed callbacks. Negative probes reject invalid behavior fields, native property values, callbacks, constructor inputs and returned-value assumptions in both supported constructor forms. They also reject the nullable text binding that caused the HUD's live `TextButton.Text` failure.

With the pinned Luau solver, reusable content factories and anchors sometimes need explicit `Instance` or `GuiObject` annotations, and literal option values may need their singleton type preserved. The witnesses make those annotations explicit without widening contracts to `any`.

The check runs twice: first with the old Luau type solver, then with the new type solver (`LuauSolverV2=true`). The old solver pass requires zero owned diagnostics and rejection of every negative probe. The new solver pass requires that owned diagnostics do not exceed the budget in `solver_v2_budget.json`, and that no negative probe outside its `missedProbes` list is accepted. The budget only decreases. Use `--solver old` or `--solver new` to run one pass. Each report prints the analyzer CPU time. New solver reports and logs have a `-v2` suffix.

The generator writes each native property table as one flat table that includes the inherited members. The new solver cannot check a table literal against an intersection of ancestor tables, so the generator does not use intersections for these tables. It also groups `Observe` overloads by class and value type.

Run `python3 tools/check_types.py --files src/ui/inputs.luau` while editing a module. This focused mode reports errors in the requested files and records dependency errors separately. It is not a substitute for the complete check. `--source-only` checks all owned source without the public fixtures; `--selftest` proves the analyzer accepts a native `UDim2` and rejects an incompatible scalar assignment.

The analyzer version is pinned in `rokit.toml`. Roblox definitions come unchanged from a pinned commit of the analyzer's upstream repository, using its game security surface. The definitions include the native InputAction and InputBinding properties used by Facet; their commit is independent of the analyzer binary version. `roblox.lock.json` pins the source URL and SHA-256. The first run downloads the matching definitions into `artifacts/verify/types/`; later runs reuse the verified cache. These declarations are build tooling, not a runtime dependency or a parallel engine implementation.

`generate_engine_types.py --check` verifies native property and event declarations against the pinned definitions and the checked-in writable-member metadata from creator-docs. The complete type check requires this generation check to pass.

Each run writes a JSON report and the complete analyzer output under `artifacts/verify/types/`. Source diagnostics are deduplicated when several entry points report the same imported module. The raw log preserves every emitted diagnostic.
