# textinput-typing-storm p95 — open adjudication (2026-08-31)

**State: OPEN. The 8 bench rows and their 16 prior-gate cascades stay red until
this is decided on a quiet machine.**

Measured today (Roblox Studio OPEN throughout — the bench header itself records
a 1.54x lift from an open Studio on a gated scene):

| Run | File under test | p50 (ms) | p95_norm | vs base | heap swing |
|---|---|---:|---:|---:|---:|
| A1 | current | 0.1155 | 1.729 | 1.65x | 188 MB |
| B1 | pre-settle (9841d5c^) | 0.1141 | 1.049 | 1.00x | 100 MB |
| A2 | current | 0.1141 | 1.665 | 1.59x | 199 MB |
| B2 | pre-settle | 0.1142 | 1.713 | 1.63x | 190 MB |
| A/A ×6 | current, fixed source | 0.114–0.122 | 1.626–1.763 | 1.55–1.68x | 186–199 MB |

Findings:
- **`9841d5c` (the text-settle flip) is exonerated**: the pre-change file
  reproduces the red tail (B2), and p50 — the per-flush work — is identical to
  the frozen baseline era (0.109 then, 0.114–0.122 now) in every run.
- The tail is **bimodal across processes** (B1's green 1.05 with half the heap
  swing sits between reds of both files) and **tight within today's session**
  (six consecutive 1.63–1.76). That is collector-phase behavior under ambient
  memory pressure, not a code path: the scene churns ~190 MB per run and the
  CPU yardstick cannot normalize collector pauses.
- The baseline's own precedent for THIS scene: at 300 samples it was declared
  un-adjudicable (A/A 2.07x over a 1.5x factor) and carried as an instrument
  failure; 1500 samples brought A/A to 1.22x on a quiet machine.

Decision procedure (the baseline header's own rule): re-run **9 runs on a quiet
machine (Studio closed, no agents)**. If quiet A/A sits at the baseline's 1.22x
and the median is red, bisect 63e878f..HEAD before any re-freeze; if the quiet
median is green, today's reds were environment and nothing changes; if quiet
A/A exceeds the 1.5x factor again, the scene is un-adjudicable at p95 and the
honest gate for it is the stable p50_norm channel — a tooling change plus
re-freeze, recorded, never a silent adjustment.
