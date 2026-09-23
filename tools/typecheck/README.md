# Native Luau type checks

`python3 tools/check_types.py` checks every Facet-owned module under `src/`, the public control witness, and generated negative probes. A passing result requires strict directives, no owned-source or witness type errors, and rejection of every invalid public call. The checker records upstream dependency diagnostics separately; it does not claim to type-check Compose's implementation on Facet's behalf.

The public witness uses `Facet.controls(runtime)`, native Roblox properties and return types, Compose cells, and typed callbacks. Negative probes reject invalid behavior fields, native property values, callbacks, constructor inputs and returned-value assumptions in both supported constructor forms. They also reject the nullable text binding that caused the HUD's live `TextButton.Text` failure.

With the pinned Luau solver, reusable content factories and anchors sometimes need explicit `Instance` or `GuiObject` annotations, and literal option values may need their singleton type preserved. The witnesses make those annotations explicit without widening contracts to `any`.

Run `python3 tools/check_types.py --files src/ui/inputs.luau` while editing a module. This focused mode reports errors in the requested files and records dependency errors separately. It is not a substitute for the complete check. `--source-only` checks all owned source without the public fixtures; `--selftest` proves the analyzer accepts a native `UDim2` and rejects an incompatible scalar assignment.

The analyzer version is pinned in `rokit.toml`. Roblox definitions come unchanged from a pinned commit of the analyzer's upstream repository, using its game security surface. The definitions include the native InputAction and InputBinding properties used by Facet; their commit is independent of the analyzer binary version. `roblox.lock.json` pins the source URL and SHA-256. The first run downloads the matching definitions into `artifacts/verify/types/`; later runs reuse the verified cache. These declarations are build tooling, not a runtime dependency or a parallel engine implementation.

`generate_engine_types.py --check` verifies native property and event declarations against the pinned definitions and the checked-in writable-member metadata from creator-docs. The complete type check requires this generation check to pass.

Each run writes a JSON report and the complete analyzer output under `artifacts/verify/types/`. Source diagnostics are deduplicated when several entry points report the same imported module. The raw log preserves every emitted diagnostic.
