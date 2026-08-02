# Inside an init.luau, "./" means siblings of the directory-module; children need "@self/"

Observed 2026-07-19 under Lune 0.10.4 (per the amended Luau require-by-string RFC): a leaf module's `./X` resolves against its own directory, but an `init.luau`'s `./X` resolves against the PARENT directory (siblings of the module the directory represents). `require("./Types")` from `vendor/Fusion/init.luau` failed with "could not resolve child component"; `require("@self/Types")` is correct for the directory's own children.

**Rule:** the vendor require-transform (`transform_fusion.py`) maps, for `init.luau`: 0 ups → `@self/`, 1 up → `./`, N ups → `../`×(N−1); for leaf files: 0 ups → `./`, N ups → `../`×N. Engine-side semantics of the same paths are pending the Phase 0 Studio spike.
