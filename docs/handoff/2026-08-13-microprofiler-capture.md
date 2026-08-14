# MicroProfiler capture — what to do when you're back (2026-08-13)

The perf lab place has been rebuilt with the solve-count fix in it
(`examples/places/LuauUI-PerformanceLab.rbxl`). **Reopen it** — the copy you had
open in Studio is running the old source, which was confirmed by reading the
loaded module text, not guessed.

## Why the last two captures were unusable, in one line each

- **`perfPlace2gb.html`** — the dump holds ~30 frames (~1.08 s) and a `Run all`
  sweep is tens of seconds long, so it sampled a random second and drew
  `dense-scroll-native`: the one workload with no LuauUI code in it. Nine of the
  twelve scopes had zero occurrences.
- **`resize-relayout` + Profile** — the pass ran a whole lap inside one frame, so
  nothing repainted and the profiler had a single several-hundred-millisecond
  frame to sample. Both halves are fixed: the workloads yield internally, and
  there is a stop flag no pass can clear.

## The capture, step by step

1. Open the rebuilt `LuauUI-PerformanceLab.rbxl` and press Play.
2. Pick a workload — `resize-relayout` is the one this round's fix targets.
3. Press **Profile**, not `Run all`. Profile loops ONE pass until you stop it, so
   the ~1.3 s dump window is guaranteed to land inside the workload you chose.
   `Run all` is for a correctness sweep, not for a capture.
4. Let it settle a few laps (the status line counts them).
5. **Ctrl+F6** (**Cmd+F6** on macOS) opens the MicroProfiler, **Ctrl+P** pauses it,
   then **Dump → Dump in binary format**.
6. Send the file. The workload identity is written into `workspace` attributes and
   warned to the console, so the capture no longer has to be identified by
   forensics.

Full detail: `docs/guide/12-performance-lab.md` §12.4.

## What to look for, and what would be new information

The fix should show as a **count**, not a duration. Before: one viewport change
cost 5 solves. After: 1. So in a `resize-relayout` capture, `LuauUI/arrange` and
`LuauUI/measure` occurrences per step should drop sharply; the per-occurrence
milliseconds should be roughly unchanged, because the solve itself was never the
problem.

Reference numbers from the previous device capture (`rr.html`), for comparison:

| scope | per occurrence | note |
|---|---|---|
| `arrange` | 8.270 ms | 9.67 occurrences per step |
| `measure` | 3.057 ms | |
| `arrange` + `measure` | — | 58.5 % of wall |

Two costs are known to remain and are *expected* in the capture, so they are not
a surprise to chase:

- the lab overlay's reservation dance — two extra unbatched `coreSafeInsets`
  writes per resize (optimization-log L-29 residual 1);
- a presented modal costs 2 solves per geometry change rather than 1 (residual 2).

Neither is per-key fan-out; that is gone. If a capture shows ~5 solves per
resize again, the coalescing has regressed and
`tests/geometry_solve_coalescing.spec.luau` should be red.
