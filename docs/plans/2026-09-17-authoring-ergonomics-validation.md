# Component and motion ergonomics: implementation evidence

This extends the Signals migration recorded in
[the earlier validation](2026-09-16-signals-validation.md). The public examples
and mental model are in [component authoring](../guide/15-components.md).

## Delivered behavior

- `animation = { layout = "container" }` coordinates surviving descendants at
  the next visual commit. State writes need no animation wrapper. Nested groups
  can select different presets; `false` suppresses a property or layout group.
- `scale`, `opacity`, `rotation`, and `offset` have independent local policies.
  Retargeting preserves continuity, initial layout appears immediately, and
  paint animation adds no layout solves. Structural enter/exit remains the
  transition system's responsibility.
- `ui.animate` owns a readable animated number; `ui.withAnimation` exposes the
  existing explicit action operation. Reduced motion, viewport changes,
  native scrolling and motion/world-tracking updates have explicit handling.
- Custom components accept ordered numeric children and ordinary named slots.
  `When` accepts a direct child, collection keys accept `key = "id"`, and row
  components receive the current item getter. A mounted owner reuses a shared
  property getter's memo while validating each destination independently.
- The **Motion → Automatic** showcase combines these APIs. Its gallery wrapper
  now mounts deferred component descriptions intact. Copying a component's empty
  placeholder had discarded its content; nested navigation and purchase tests
  cover this integration in addition to the standalone example.

## Roblox animation primitives

Native styled paint now enables `StyleRule:SetPropertyTransitions` by default.
An explicit `transitions = false` remains available. Reduced motion removes and
restores the declarations live, including a surface born with reduced motion.
The showcase's absent transition attribute follows the library default instead
of silently converting absence into an opt-out.

Timed motion already used `TweenService:GetValue` through `motion_driver`;
`client.host` now installs that evaluator too. Existing native instance tweens
for control feedback remain in place. Facet retains its spring integrator and
single presentation composition for interruptible layout, velocity handoff and
spring presets. StyleRule's duration-based transitions do not replace those
semantics. The new syntax does not create a second renderer or frame driver.

## Verification

Focused checks passed: 21 component cases, 11 declarative animation cases,
35 existing explicit-animation cases, 24 native-style default cases, 17 client
host cases, nine nested-showcase cases, and the 115-case viewport/theme overflow
sweep. Public type witnesses report zero target-file diagnostics across all
29 typed control entries; existing dependency-graph diagnostics are not claimed
to be eliminated. Property parity and source-size checks pass.

All **135 performance runs / 27 scenes** and **17 benchmark scenes** pass with
unchanged budgets. The new paired benchmark uses the same retained 100-row tree
and continuously interrupts layout motion: declarative p95 **2.6075 ms**, explicit
p95 **2.5908 ms** (0.64% apart). The existing scenes' normalized p95 ratios against
the pre-change run range from 0.72 to 1.044; yardstick drift was 9.0%. These are
single-session trend measurements, not a universal speedup claim.

The separate FacetBench headless run uses 750 samples after 50 warmup, size L,
all five workloads. All rows are `ok`. Its existing drift retry repeated the
nameplates row once; the accepted rows all have drift below 10%.

Live Studio used the complete synced runtime (249 modules in the benchmark
place, package source hash `3cdb47bf6712901cebf121cbbf614926b009911cfc4d90fa469683b78ecca295`).
The showcase sync reported zero stale/refused modules. Actual mouse input drove
selection, expansion, reorder, purchases, and the disabled purchase state,
including a purchase and expansion inside the real nested Automatic tab.
Readbacks reported no diagnostics. Screenshots confirmed the mounted interface.
The expanded nested view also retained selection through reorder and refused a
third purchase after the balance reached 20. A simulated 390 × 844 viewport
wrapped the details text and adapted navigation to a bottom bar with the actions
visible. This was a layout simulation, not physical phone evidence. The normal
viewport and live environment binding were restored afterward.

The native-style probe read four active transition rules, zero under reduced
motion, and the same four after restoring motion. Sampling an actual hover
captured both endpoints and an intermediate engine-painted color. A normal
client host probe recorded one installation of Roblox's easing evaluator.

The Studio FacetBench runner used a temporary normal-client relay, 300 samples,
30 warmup, size L, frames mode. The live marker was `3cdb47bf6712`; all five rows
were `ok`, `FACETBENCH_DONE 5` was recorded, and the error log was empty.

| Workload | Update p95 ms | Whole-frame p95 ms |
|---|---:|---:|
| Battle HUD | 6.568 | 18.260 |
| Damage fountain | 3.975 | 18.104 |
| Killfeed/nameplates | 12.258 | 18.073 |
| Nameplates | 5.834 | 18.170 |
| War room inventory | 15.281 | 22.817 |

These live numbers are one current-source run, not a paired before/after claim.
In particular, update-tail variability should not be inferred from the older
ABBA table as a controlled regression comparison. The inventory stress case
exceeds a 60 Hz frame budget, as it did in the earlier validation. Physical
phone/console measurements remain outside this desktop Studio run.

Raw local results are under `artifacts/authoring-ergonomics/`: before/after bench
JSON and logs, the scene comparison, performance JSON, FacetBench headless rows,
Studio functional readbacks and hover samples, and the live benchmark rows.
Temporary probes and the benchmark relay were removed. The package and 14
example places were rebuilt locally; nothing was published.

The final deterministic suite passed **10,083 tests**. The coordinator also caught
an outdated coverage-index reference to the former opt-in transition test name;
the reference was updated to the new default-on behavior. **Full verification
passes** (`tools/verify.sh full --explain`, identity `fe5bf7197f87`). That final
run reused the verified unchanged suite and reran the affected checks. The full
JSON report and log are copied beside the other raw results as
`verify-full.json` and `verify-full.log`. Earlier failing integration runs are
retained and are not passing evidence. Existing declared historical receipts
remain distinct from the fresh Studio measurements above.
