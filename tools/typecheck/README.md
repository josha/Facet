# Native Luau type checks

`python3 tools/check_types.py` checks every tracked and untracked Luau file that Git does not ignore. This includes source, the pinned Compose snapshot, tests, examples, benchmarks and tools. A passing complete check requires strict directives, zero type errors in every analysis context, and rejection of every invalid public probe. There is no diagnostic budget or dependency exemption in the complete check.

The checker first compiles every target with the pinned Lune compiler. It then builds a Rojo sourcemap for each checked-in project. It checks mapped files in each project that includes them. It also checks all files outside those projects. Designer plugin code and Studio injection use the pinned plugin security declarations. Game code uses the pinned game security declarations. The JSON report lists each context and its targets.

The default check uses the pinned old Luau solver. Use `--solver new` or `--solver both` to select another solver. Every selected solver requires zero diagnostics. New solver reports and logs have a `-v2` suffix.

The public witness uses `Facet.controls(runtime)`, native Roblox properties and return types, Compose cells, and typed callbacks. Negative probes reject invalid behavior fields, native property values, callbacks, constructor inputs and returned-value assumptions in both constructor forms. They also reject nullable text bindings where the engine requires text.

The pinned solver can require explicit `Instance` or `GuiObject` return annotations for content factories. Preserve singleton types for literal options. Give cells the full type of the values they can store. Give arrays their shared entry type when entries have different optional fields.

Run `python3 tools/check_types.py --files src/ui/inputs.luau` while editing a module. This focused mode reports errors in the requested files and records dependency errors separately. It is not complete verification. `--source-only` checks Facet-owned source. `--selftest` checks repository inventory, analysis contexts, strict directives and diagnostic policy. It also proves that the analyzer accepts a native `UDim2` and rejects an incompatible scalar assignment.

The analyzer and Lune versions are pinned in `rokit.toml`. `roblox.lock.json` and `roblox-plugin.lock.json` pin the upstream Roblox declaration URLs and SHA-256 hashes. `lune.lock.json` pins the generated Lune declarations. The checker verifies those hashes and caches declarations under `artifacts/verify/types/`. It adds the native datatype exports that Lune provides at runtime to Lune's Roblox module declarations. These declarations are build tools.

`generate_engine_types.py --check` verifies native property and event declarations against the pinned definitions and the checked-in writable-member metadata from creator-docs. The complete check requires this generation check to pass.

Each run writes a JSON report and complete analyzer logs under `artifacts/verify/types/`. Repeated diagnostics are deduplicated in the report. The logs preserve every diagnostic.

The analyzer uses `LuauTarjanChildLimit=100000` to check the full control and engine type graphs. This increases analysis capacity. It does not suppress diagnostics.
