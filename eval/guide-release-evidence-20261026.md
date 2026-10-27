# Guide candidate evidence, 2026-10-26

This is a candidate record, not a claim of superiority over Plain. The
[registered comparison plan](guide-release-plan-20261026.md) remains unchanged.
Frozen historical submissions and failed attempts were not repaired or replaced.

## Source and scope

- Candidate: `1491e2fa1df6cb6fd70066486184c775b8bb5a42`, based on main
  `8be51096f4f704c9380608f8e478866c781d2fae`.
- Draft review: <https://github.com/josha/Facet/pull/271>.
- This follow-up adds a documented theme choice for stationary covered pages.
  It changes no framework source, evaluator, deadline or frozen submission.
- Local evidence root: `artifacts/guide-release-20261026/` in the candidate
  checkout. Native attempts are under `validation/`. These local artifacts are
  not distributed as consumer documentation.
- Validation games are copied diagnostic fixtures. Their source originals and
  SHA256 manifests are retained in `validation/original-fixtures*`; permitted
  path/type migrations are described in `validation/CUSTODY.txt`. These are
  not fresh independent author submissions.

## Repository checks

At candidate 1491, docs links, node budgets, style, strict samples, focused docs
specs, example types and skill validation passed. There were 89 strict samples;
eight example/type targets had no blocking diagnostics. Dependency diagnostics
are retained separately in `example-types.log`.

`lute run tools/facet gate full` completed with 38 selected producers. The
recorded result is **NARROWED**, with 3335 passed cases and two unsupported
cases. Reference-host bench and complete Studio-live evidence were unavailable;
this is not a full release attestation. The first attempt failed because the
sandbox could not write typedefs; its log is retained. See
`gate-full-permitted.log` for the successful selected scope.

Standalone bench passed. Package build and status ran at 1491; source hash was
`b7c43892148af972d4c361c11e5ddbfe81615bd97471d5ed599db3658a7e53f0`.
No package was published. Status explicitly does not attest the current tree
from an older gate receipt. GitHub workflow 40415850843 passed its four suite
shards, four paired performance shards and Verify aggregation at 1491. These
checks do not replace controlled native game timing or retained-memory tests.

For this motion documentation follow-up:

```text
lute run tools/facet check docs-nodes links doc-style
lute run tools/facet check docs-samples
lute run tools/facet gate spec docs_examples tools/docs_nodes
```

All passed. Node limits remain unchanged. Reports are `docs-motion-check-final.log`,
`docs-motion-samples.log` and `docs-motion-specs-v2.log`. Earlier over-budget
drafts and an incorrect spec-path invocation remain in separate logs.
The full command was also repeated on the motion follow-up, run
`gate-1793056851-604388-1`. Its 38 producers passed with the same two deferrals
and selected-scope limitation; see `gate-motion-followup.log`. It records base
1491 with an uncommitted docs diff, not a clean-commit attestation.

## Native evidence

| Path | Observation and limit | Local attempt |
| --- | --- | --- |
| Search, empty result, reset | Real typing and activation restored 12 records. Empty-state capture was rejected by the capture validator; state assertions alone do not validate that image. | `collection-flow-v4` |
| Filter, detail, Back | Plants filter retained four records. First Back capture was mid-transition and is not settled visual evidence. | `collection-flow-v4` |
| Settled landscape return | Draft and scroll context retained; native ancestor geometry stayed stable across 180 frames. Settled image retained. | `landscape-back-flow` |
| Open phone rotation | Query, selected Willow key and collection/list instances retained. The first-visible record changed after a transient resize clamped scrolling. This remains a scroll-context failure; the later observation case passing does not turn it into acceptance. | `rotation-observed-v1`, `rotation-observed-v2`, `rotation-frames-v1` |
| Controller entry and return | User input and then emulator keyboard mappings produced actual `Gamepad1` X/B events. X opened Equipment with Search selected; B restored the HUD and Equipment focus. Settled captures retained. This is entry/return evidence, not every controller operation. | `controller-held`, responses 5–9 |
| Largest text | Native portrait and landscape record/detail/Back paths passed; six settled images retained. Landscape shows two complete records at this access setting. | `largest-settled-v2` |
| Server rejection and retry | Rejection preserved 100 credits; retry produced 65 credits and one accepted loan. Ledger and Close passed. The accepted-state raw image was manually inspected but its automated 98.8%-one-color rejection remains unresolved. | `trail-settled-v1` |
| Gameplay return | After Close, native W arrived as unprocessed Keyboard input, MoveDirection reached 1, and the character moved 62.73 studs in the plane. This proves that return path, not all required gameplay. | `rotation-observed-v2` |

The initial controller VirtualInput path delivered `ButtonX` as `Keyboard`;
it did not exercise a controller. The later scoped emulator mapping did.
The held evaluation Studio closed through the owning Verify session, which
reported restoration to Edit, PID termination and no survivors. Personal
Studio windows were not manipulated.

### Covered-page motion

The Trail fixture puts the gameplay HUD at the root of NavigationStack.
`src/ui/nav_stack.luau` reads `motion.distances.parallax`; the neutral value
is 0.3. Its covered-page position is `-parallax * (1 - moved)`. Thus the HUD
slide is expected default behavior, not evidence that navigation oscillates.
For a task covering gameplay, the guide now demonstrates a theme value of zero.
It retains stack ownership and the incoming page slide. This affects all default
stacks using the theme; it is not a per-destination option or a new API.
The separate `parallax-zero-v1` fixture changed only this theme value. Real
pointer input opened and closed Equipment. Across 151 opening frames and 150
closing frames, HUD X/Y ranges were exactly zero. Equipment X-scale travel
ranges were 1.0000 and 0.9987. Settled captures and the closed-session receipt
are retained. The baseline fixture remains unchanged.

### Rotation limitation

Before rotation, list height was 562, canvas height 768 and scroll Y 206. During
rotation the list briefly became 643 high with a 748-high canvas, clamping Y
to 105. The final window became 189 high; canvas height returned to 768 and Y
settled at 125. The first-visible record shifted from Golden sedge to Fine
collection net. Willow's selected tag survived once that virtual row was
revealed through input. This is not merely a different pixel offset from a
benign row reflow.

The native-only comparator reproduced the same final 81-pixel loss with no
Facet or Compose. Its fixed 768-high canvas clamped Y from 206 to 125 while
the window briefly grew from 562 to 643; the final 189-high window retained
125. Facet adds a brief measurement change, but ends at the same native offset.
This confirms a native simulator/ScrollingFrame resize path, not a Facet-only
defect. A passing observation case does not establish retention acceptance.
Any mitigation needs separate scroll-policy work and physical-device rotation
evidence; do not hide it in the guide or alter this failure into a pass.
The comparator is `validation/native-scroll-v1/`. Final attempt descriptions,
52 evidence hashes and cleanup checks are in `validation/STEP2-FOLLOWUP-RESULTS.txt`,
`validation/STEP2-FOLLOWUP-FILES.json` and `validation/STEP2-FOLLOWUP-CLEANUP.txt`.
All seven follow-up Studio PIDs were checked absent after owned-session cleanup.

### Lighting setup

The user identified the Studio migration prompt's missing lighting setting.
New diagnostic copies at `validation/fixtures-voxel-v1/` explicitly set
`Lighting.Technology` to `Voxel`; their Trail and Largest collection builds
passed. `lighting-change.json` records the changed project hashes. Existing
attempts, source originals and historical submissions remain unchanged. The
next comparison must record one explicit shared lighting setting for both arms
before freezing; these setup copies are not a measured comparison. The new
native-only comparator opened with Voxel without migration-dialog intervention.
Live readback reported `LightingStyle = Soft`; Technology readback was unavailable.

## Comparison admission

No calibration or pilot benchmark author was launched. Public usage preflight
failed the registered exact-accounting prerequisite. Four tiny Sol 6.1 Medium
probes tested measurement only, with no game brief, Studio or author tools.
The completed probe reported 6788 total tokens, including 6783 input, zero
cached input and five output. Hard deadline stop, SIGINT and public app-server
interruption each omitted usage for the interrupted response. A public
thread-scoped recovery lookup returned null usage. Details and raw public
receipts are in `usage-preflight/FINDINGS.txt`.

Missing usage is unknown, not zero. Partial totals cannot pass the 1.30 ratio.
No private Codex session/account logs were used. Complete measured usage for
the interrupted response is required before this admission can pass. Graceful
shutdown alone did not solve it. Setup, native validation and these probes are
not author time or benchmark consumption.

The unlaunched preparation at
`artifacts/facetbench/guide-calibration-20261026-v2/` targets candidate 1491.
Its input receipt SHA256 is
`ea7206d68657ae0b683972a150302f605cffeac282efe8dd918bdd0183b55403`;
manifest SHA256 is
`0ebc94309b51e29c10fff4965381b6d10fcc92d4ce0c12990852ced4fe0cb21a`.
Offline builds and process deadline/child cleanup checks passed. No author
freeze was issued. Regenerate inputs for this follow-up before any launch;
retain the v2 preparation as a separate attempt.

## Four-step status

1. Clean candidate PR: open as draft, with reviewed scope and local checks.
2. Native gaps: substantial targeted coverage above; rotation scroll context,
   complete gameplay/input coverage and capture validation still limit acceptance.
3. Full P/F1 calibration: prepared but blocked before launch by public usage.
4. Three P/F0/F1 blocks, then six fresh pairs if advancement passes: not launched.

No anonymous reversed-order visual judgment or complete native performance
comparison exists for this candidate. It cannot yet be called better than Plain.
