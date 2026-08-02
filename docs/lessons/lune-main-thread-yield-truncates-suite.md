# A yield on Lune's main thread silently truncates the test suite with exit 0

Observed 2026-07-19: Fusion's SpecExternal-style `doTaskImmediate` (queue self + `coroutine.yield()`, expecting an outer scheduler loop) suspended the main thread mid-suite; Lune exited 0 having printed only the tests that ran, with no summary line. A green-looking, truncated run is a false PASS.

**Rule:** never yield on the runner's main thread; headless schedulers run immediate tasks synchronously (`tests/lib/fusion_lune_external.luau`). Tooling must treat a missing `N passed` summary line as failure — the `test`/`gate` commands check for it rather than trusting the exit code alone.
