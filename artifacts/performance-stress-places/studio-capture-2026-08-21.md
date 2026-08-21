# Studio capture — 2026-08-21 (release-candidate requalification, H2)

**Session:** Facet-PerformanceLab.rbxl open in Studio (no Rojo), place bytes =
rebuild at `7e34ce1`; `git diff 7e34ce1..HEAD -- src/ examples/performance/` is
EMPTY, so the place is current framework source. Viewport locked to
**desktop-standard 1280×720** via the matrix driver (`DisplaySize = Medium`);
the first attempt at the host's native 1920×1078 was refused by the lab itself —
that width classes as `Large`, the ten-foot floor made rows 77px against the
declared 60, and the mount refusal named it. That refusal is the lab working.
Profiler armed via Ctrl+Alt+F6 and proven live (`GetFrameIdMax` +61/s) before
any number below was read.

**Rows:** all 13 capture-plan rows driven, exported admissible (0 problems each),
and landed byte-for-byte through the studio_sync bridge as
`studio/rc-requal-row01..13-*.json` + `rc-requal-moduleload.json`.
`check_perf_captures: PASS`.

## The headlines, against the plan's questions

| row | what the engine said |
|---|---|
| 01 idle-baseline | 0 GuiObjects; Facet idle ≈ 0.02–0.03 ms/frame across every scope |
| 02 dense-scroll flat | solves 103, **partialSolves 0**, creates 922 / recycled 567 / elided 505; `text.pending` false at snapshot; **haptics flat at 0 across the whole scroll** (event-driven, nothing built per frame) |
| 03 native reference | **zero Facet scopes during the scroll** — the framework does no work on the raw-Roblox arm, so the comparison is honest |
| 04 dense-scroll ornate | same order as flat (commit 96ms/67 vs 143/97 window totals) — the most expensive shipped skin does not blow up the scroll |
| 05 layout-style-churn | install/steady/teardown timed apart in the export row |
| 06 collection-churn | 6 solves for 20 edits, partial 0 — updates proportional to changed content |
| 07 arrange-shapes | **flat 7.49 µs/arranged-node, fill 8.37** (arrangePerRep=1, 240 leaves) — the control arm for the 2026-08-15 device captures |
| 08 edit-locality (re-capture owed) | **arrangePerEdit 1, measurePerEdit 1, partialSolvesPerEdit 1, mountPerEdit 0**, 3 arranged nodes/edit against 2024 logical rows, lastSkipped 96 — the RR-5 incremental path is live on the engine |
| 09 host-move (ADR-0032 risk) | hosted **9.82 µs/leaf** vs unhosted **12.86** at matched N (p50 solve 1.18 vs 1.54 ms) — the write collapse IS a frame-time win in Studio |
| 10 variable-extents (re-capture owed) | **arrangePerGrow 1 on all three arms** (uniform / uniformRepeat / measuredRagged); harness spread recorded; recycling armed and cycling |
| 11 large-text-overflow | revealAudit findings 0, moving-surface cap respected; text.pending false |
| 12 async-image-churn (imagesReuse) | provider bounded: cached 7 / active 7 / queued 0, dropped 389, staleRejected 271 over 60 cycles — reuse, not accumulation |
| 13 lifecycle-soak | **core counters byte-identical across all 12 cycles** (141 observers / 109 signals / 148 memos / 38 scopes), connections flat at 144 with an identical per-slot map, heap oscillates with the collector and does not climb |

## Module-load memory (capture-plan §2, requalification §7)

Read FIRST in the Play session, once: `beforeRequire 140 KB → afterRequire
4847 KB`, so **`require(Facet)` costs ~4.7 MB of Lua heap under Studio**
(headless: ~2.8 MB — the Studio number carries the engine-typed environment).
First workload mount added 8.1 MB (`afterFirstMount 12.9 MB`). This is the
number the lazy-loading question is judged against; the lazy split (228 KB
[131..313] deferred) shipped in T15.

## What this capture is NOT

- **No `.gprx` binary dumps were persisted.** The MicroProfiler's Dump-to-file
  is a UI action with no scripted route in this session; per-scope timings were
  instead read live via LibMP `CaptureToBufferSync` aggregation (the guide
  §12.4 procedure, staleness-asserted) and are recorded above and in the
  session ledger. `tools/microprofiler_aggregate.py` therefore has no new dump
  to decode; the engine-side `--layout` half (Relayouts/Updates/Resizes) rides
  the next human-driven dump.
- **Not a device claim.** `bench/perf_budgets.json` still carries
  `measured:false` on all three device budgets; the low-end Android procedure
  (guide §12.5) remains the only instrument that can close them.
