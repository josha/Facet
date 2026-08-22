# SDD ledger — plan: docs/plans/release-candidate-review.md

Mission: LuauUI → Facet rename + release-candidate review (roadmap Step 13).
Controller: Fable 5 (fresh session, satisfies plan's fresh-lead rule).
Repos: LuauUI = GameStudio/ui/LuauUI (git, main, origin github.com/josha/LuauUI);
RascalRally = games/RascalRally/code (git, main, clean at 02df98c).
Binding docs read: release-candidate-review.md, api-architecture-consistency.md,
performance-stress-places.md, agent-execution-contract.md, distribution-readiness.md,
STUDIO.md, root CLAUDE.md.

## Pre-flight conflict scan

| Check | What I compared | Found |
|---|---|---|
| Worktree rule vs repo convention | SDD "never on main" vs repo gate system + docs/lessons worktree-cannot-run-gates + rename moves the repo dir itself | Conflict — ruled R1 |
| Dirty tree vs freeze | 6 modified docs/plans files (user's mission edits) vs "freeze source identity before editing" | Conflict — ruled R2 |
| skills/use-luauui rename input | Plan lists it; find shows it does not exist anywhere | N/A — ruled R3 |
| Studio-baseline freeze vs Studio availability | Plan: freeze Studio scenarios before editing; user reports showcase open but Rojo not serving/connected | Sequencing — ruled R4 |
| Fresh-lead rule | Plan wants a Fable 5 lead that did not implement prior stages; this session is fresh post-/clear | Satisfied |
| Sponsor selector rename vs cutover memory | Plan: rename selector, preserve exact default + legacy rollback; memory: UseLuauUISponsor=false is authorized legacy rollback | Compatible — inventory must classify the flag (persistent vs code-only) before rename |
| Haptics plan vs Roblox API | Plan requires HapticEffectType.Custom + SetWaveformKeys; must verify against current official docs at execution (platform can change) | To verify in T11 |
| Step 14 boundary | Release plan forbids remote mutation/publish; distribution-readiness defines the packet | Consistent — packet only |

## Rulings

- R1: Work in-place on main in both repos. Why: the repo's gate system cannot run in
  worktrees (docs/lessons), every prior stage committed to main, and the rename moves
  the repo directory itself. Cost if wrong: noisy main history; mitigated by frequent
  green-suite commits.
- R2: Commit the user's six modified docs/plans files as the plan-freeze commit before
  any baseline. Why: they are the binding mission text; freezing a dirty tree is
  worse. Cost if wrong: none material (docs only, revertable).
- R3: `skills/use-luauui` does not exist; nothing to rename. Step 14 will create
  skills/use-facet. Recorded as N/A, not a defect (missing is a defect only if
  promised as shipped).
- R4: Reorder within the freeze: headless baselines, collision check, inventory, and
  gate registration proceed now; Studio baseline captured as soon as the user connects
  Rojo; no mass source edits before the Studio baseline exists. Cost if wrong: delay only.

## Task list (dependency order)

- T1 Freeze & register: plan-freeze commit; record HEADs; full suites (LuauUI + RR);
  public API dump; lifecycle/perf headless baselines; register release-candidate-review
  gate + acceptance ledger; Studio baseline scenarios (blocked on Rojo connect).
- T2 Facet collision/rights check (GitHub target, Roblox surfaces, code hosts,
  trademark) — evidence only, no brand decision by agent.
- T3 Machine-readable rename inventory, all name forms, classified + counted.
- T4 Rename execution in LuauUI repo (git mv, contents, ModuleScript/binding, outer
  dir move, rebuilt generated outputs, profile labels).
- T5 RascalRally sync (both Rojo projects, sources, types, fixtures, tests, Studio
  labels, Sponsor selector rename preserving exact default + legacy rollback).
- T6 Old-name drift guard + negative controls; rewrite plans to Facet; rename ADR.
- T7 Clean clone/build/test/Studio from GameStudio/ui/Facet + both RR projects.
- T8 Step 14 remote-change packet (no remote mutation).
- T9 Whole-framework review sweep → finding ledger (arch, reuse, maintainability,
  ownership, errors, teardown, dead code, tests, comments, hot paths).
- T10 Input Action System authority: inventory, migration, allowlisted adapters,
  drift checks, no double firing.
- T11 Sensory haptics: audit vs current SwiftUI/Roblox docs; original Custom
  press/release/select defaults; timing/cancellation; pooling/teardown; tests;
  demo/docs/lab/RR; PENDING_DEVICE packet.
- T12 Docs: rebuild guide catalog + API reference drift; product-language scan +
  negative control; clear-writing pass; comment audit.
- T13 ELI5 new-control guide + scaffold; ColorWell fresh-agent + human-verifier
  exercises; seeded-defect exercise; rerun until clean without hints.
- T14 Naming ADR: Facet.Controls.Table vs one flat alternative; compatible migration.
- T15 Performance requalification: lab refresh, Studio MCP/MicroProfiler baselines,
  measured optimizations, artifacts current.
- T16 Remediation closeout: fix blockers/highs, disposition rest, full gate matrix,
  fresh independent reviews, final evidence report.

## Progress
- T1 complete: baselines frozen (suites 6188/3345 green, surface v0.9.0, perf PASS,
  inventory 1031 files, Studio showcase sweep 36/36 + theme swap) at commits fe920dc,
  230f864. Gate + RC acceptance ledger registered; rows baselines-frozen,
  facet-collision-evidence, studio-baseline-frozen PASS; rest honestly PENDING.
- T2 complete: collision check recorded — NO blocking conflicts; github.com/josha/Facet
  free; dormant wally package emdomanus/facet flagged for owner.
- Ruling R5: RR Studio canary is captured in the same session that verifies the
  RR-side rename (not pre-frozen) — RR source is untouched until then; anchor is the
  same-session before/after. Cost if wrong: weaker RR pre/post anchor; mitigated by
  RR suite 3345 + fixture dumps.
- T3 complete: rename-inventory-before.json (1031 files; 10788 current-source
  matches; 94 storage-flavoured lines; five UseLuauUI* workspace attributes → dual-read
  migration; LuauUI_Source* stamps rename outright).
- T4+T5 implemented (Opus): framework 2a1823a..a97336f (44b9e62 rename, a97336f gate
  sweep), RR 02df98c..b92b606. Suites 6188 / 3374 (3345+29 migration) green; surface
  byte-identical; generated outputs rebuilt (old-name generated matches 0). Report:
  task-4-report.md. DONE_WITH_CONCERNS ×7. Task review dispatched (fresh Opus).
- Controller Studio canary of renamed tree: gallery injected into open session
  (320 nodes, 0 refused), [Facet Gallery] running 0.9.0, FacetScenarioAPI live,
  adaptive_controls report clean, capture matches baseline board. Evidence:
  artifacts/release-candidate-review/rename/studio-canary.md (uncommitted until
  review lands).
- Ruling J-1: vendor `[LuauUI vendor patch]` markers (60) → rename to `[Facet vendor
  patch]` + VENDOR.md quote; they are OUR annotations. Cost if wrong: vendor churn.
- Ruling J-2: `git rm --cached` the two tracked __pycache__ .pyc files (embed old
  path; bytecode should not be tracked). Cost if wrong: none (regenerated).
- Ruling R6: distribution-readiness.md references the Step 14 packet for the
  pre-rename URL instead of carrying the literal; the packet (artifacts/**) is the
  one holder. Cost if wrong: doc indirection.
- Ruling R7: T6 (drift guard install + rename ADR + packet install + negative
  controls + gate rows) executed by controller — the design IS the controller's
  rulings, drafts already written; final whole-branch review audits it. Deviation
  from dispatch-per-task recorded deliberately. Cost if wrong: unreviewed until
  final review.
- RC-21 acceptance row + gate note reference ADR-0033 for the naming ADR but 0033
  is taken (time-based easing); naming ADR will be ADR-0037. Fix the two references
  when T14 lands.
- T4 review round 1: SPEC FAIL / QUALITY APPROVED, 0C/3I/10M (task-4-review.md).
  Fix round 1 dispatched to original implementer: I-1..I-3, M-3, M-5, M-7, rulings
  J-1/J-2/R6. FAIL_RECOVERABLE dispositions independently re-measured REAL by
  reviewer.
- T4 minors (deferred): M-1 ALLOWED_PROP_DRIFT path-blanket vs text-only reasons
  (make prop entries key-scoped — T9 remediation candidate); M-2 report factual
  slips (8 not 9 call sites; row names; 20/10 not 19/11); M-4 one RR rename needs
  -M40% for --follow (stylua re-wrap same commit); M-6 mechanically re-branded
  historical anecdotes (prior_gates.sh:57, gate_manifest:3900); M-10 three
  different-counts read as contradictory (report 11 / inventory 13 / file 16).
- M-8 (controller-owned): Studio still holds pre-rename showcase file via .lock —
  the rebuilt Facet-Showcase.rbxl has never been opened; fold into RC-6/RC-2-after
  and the one batched user ask.
- Forward note (T6/T12): docs/plans/release-candidate-review.md is itself a
  maintained doc that names both brands and the vendor terms (its instructions).
  Per the plan's own rule, once consumed those sections are rewritten to reference
  the rename ADR / the guard's private list, so the final maintained-tree scans
  pass. Handle at T6 (brand) and T12 (vendor).
- Fix round 1 returned: all 10 ADDRESSED, framework 664d974, suites 6188/3374 cold
  green, surface byte-identical, src+vendor+model zero old-brand. Controller
  committed packet+canary at 871cd30. Scoped re-review dispatched (sonnet).
- Guard calibration from after-inventory: scan vendor now (clean); RR docs walk
  recursively excluding missions/+playtests/ with DECISIONS.md allowlisted
  (append-only); add check_flat_baseline.luau (quotes frozen 0.6.0 titles) and
  theme_sync_cli.luau (frozen dump stamps); drop token_sync + edge_case_hardening +
  distribution-readiness entries (clean now).
- Task 4+5: complete (framework 2a1823a..664d974 + controller 871cd30, RR
  02df98c..b92b606, review clean after fix round 1/5; re-review independently
  reproduced every measurement).
- T6 complete (controller per R7): check_brand_drift.py installed — full scan PASS
  incl. built-XML serialized names; selftest negative controls all bite;
  ADR-0036-facet-rename.md landed; step14 packet completed with read-only remote
  facts (repo id 1320732857, private, no Pages, 0 workflows, target 404); gate rows
  rename-canonical-identity, rename-drift-guard-bites, step14-remote-packet PASS.
  RC-4/RC-5/RC-8 PASS_AUTOMATED.
- T7 complete: clean-clone proof (0 symlinks, 6188 cold green, showcase builds
  2,957,478 bytes) — RC-6 PASS_AUTOMATED, gate row PASS (c7090bb).
- T14 decision made + ADR-0037 landed: Facet.Controls.<Name>(core, spec) for the
  19 composite controls; newX stays for the 11 infrastructure constructors; flat
  alternative rejected on arity-sniffing grounds; 317+32 call sites measured;
  deprecations since=0.10.0. Implementation goes in the post-review wave.
- Verifier stubs (facet-*) cannot write files — corrected all three mid-flight to
  return reports as text; general-purpose reviewers unaffected. Lesson for stubs.
- ARCH-1/2 REPRODUCED (controller probe, probe_arch1.luau): keys {a,b}->{a,c}
  with c's factory throwing, no boundary: set() returns OK (error swallowed to
  core:lastError), mounted 4->3 (b disposed), children still lists disposed
  /S/Rows/[b]/Row-b, c absent, 0 dirty entries. Severity CONFIRMED High
  (tree corruption + silent swallow). Follow-up at fix time: is the rebuild
  effect quarantined afterward (does the NEXT set() rebuild at all)?
- Reviews stored: architecture (26: 2H/11M/13L), reactive (15: 2H/4M/9L),
  platform (26: 3H/9M/14L). RR-6 == PLAT-1 (independent convergence, OSK
  occlusion never connected on device).
- IAS inventory landed (input/ias-inventory.md, INPUT-1..116): class-1 must-migrate
  = 5 (RR InputAction:Fire x4 -> Scriptable InputBinding:Fire; INPUT-105 manual
  GuiButton staging -> InputBinding.UIButton, its engine-bug rationale fixed
  2026-04-07); DF-1..4 root cause = RR contexts carry no Priority/Sink (DF-6);
  DF-7 Facet row_actions Shift+Return vs plain Return — PrimaryModifier x Sink
  engine interaction UNDOCUMENTED, no gate row measures it (needs E2/E3 or a
  binding redesign); DF-9 disableLegacyControls repair possibly obsolete under
  the flag but the BUILT places lack the flag; flag missing from 5 project
  surfaces incl. built Facet-Showcase + both RR projects; stale
  gamepad_contention comment ("not rojo-reflectable") is half-false and likely
  why. ARCH-1 recovery probed: next good update rebuilds (not a permanent
  wedge); severity stays High.
- Interim from the maintainability/dead-code seat (its own fork consolidation):
  4 dead public motion aliases (resolveClass/isRegisteredClass/resetClasses/
  resolveCurve — zero call sites); vendor/Fusion + fusion_adapter + imperative
  vestigial bake-off artifacts kept alive only by a historical gate (product
  decision: retire or document); native_style DEFAULT_ENABLED=false promotion
  tracker stale since 2026-07-24 (4 unchecked stillRequired, no owner); stale
  gate pointer to nonexistent tools/lune/oracle_easing.luau; NO genuine dead
  duplicates among 9 investigated pairs (all documented 200k-cap splits or
  deliberate); screen_target opts.isReducedMotion deprecated closure flagged.
  Tasks 3+4 (deferred-features + stale probes) still pending from its fork.
- Maintainability audit landed: 41 findings (1 Blocker: renderer 350 chars from
  200k cap, no warning band; 12 High incl. gate-manifest empty failure detail,
  scaffold emits theme-drift-rejected output, 6 hand-maintained theme lists).
- findings.md (RC-9 ledger) committed at a8b0a26 with wave assignment + initial
  dispositions (gate restructure → Step 14 owner; renderer extraction → seam
  analysis first; luau-* tags → R5; native-style default → owner checkpoint;
  vendor bake-off → R5 recommendation keep+signpost).
- Wave R1+R2 DISPATCHED (Opus, 35 decided contracts, BASE a8b0a26).
- R3 brief written (task-r3-brief.md): RR Scriptable-binding migration, UIButton
  staging replacement, Priority/Sink scheme (modal 3000 sink, HUD 2000, gameplay
  1000), DF-7 measured-not-guessed (bare-PENDING gate row + studio checklist),
  flag into 5 project surfaces + rebuilds, DF-9 inert-under-flag, new
  check_input_authority.py with inventory-derived allowlist + selftest.
- Reuse audit still running; R4 haptics queued behind R1 (single tree-writer).
- Reuse audit final landed + committed (cc4a9cd, 125 findings). R1 addendum sent
  (items 36 VirtualList/Grid clamped-anchor port of the table fix; 37 RR
  presenter.tick drive + guide correction). Controller rule: never amend while
  an implementer is active (checked reflog; tip was mine alone this time).
- Review wave COMPLETE: 6/6 seats. Totals: ARCH 26, RR 15, PLAT 26, MAINT 41,
  REUSE 125, INPUT 116 rows + 9 DF risks.
- DIRECTOR ROUND (physical device screenshots, 2026-08-17): DIR-1 left edge 1px
  cutoff on the demo chip row (callout demo, ~393px portrait, "compact desktop");
  DIR-2 themed HUD plates: text overflows plate boxes (ornate themes); DIR-3
  themed HUD plates overcrowd/overlap each other + topbar (theme chrome extents
  not in HUD layout math); DIR-4 playlist table: resize columns in landscape ->
  rotate portrait -> Rating column gone (header says "Rating locked", Artist
  clipped at right edge); DIR-5 HUD portrait->landscape loses left content,
  URL-bar toggle resets it (arrangement latch not recomputed on orientation
  change — recurrence-shaped: the band-collapse family from the nested-tree
  round). Reproduce before fixing; build under test on device uncertain
  (published place may predate rename) — reproduce against current tree.
- Director confirmed the phone build = publish just before the rename (includes
  the 2026-08-15 O-23/O-25 fixes) → DIR-2/3 are REAL ON CURRENT CODE and the
  themed overflow sweep is blind to them. Gallery reproduction attempt: only
  theme_authoring consumes flags.themePackage; the hud scenario cannot be themed
  in the gallery runner — the showcase shell (global theme picker) is required.
  Live session DID confirm: no settled text misfits in hud at 749x380 unthemed;
  mid-motion TextFits=false readings are animation transients (instrument note).
  → The batched Studio ask fires NOW: open the rebuilt Facet-Showcase.rbxl.
- Controller opened Facet-Showcase.rbxl itself (`open` cmd; user away). Post-rename
  36/36 sweep on the REBUILT artifact green. DIR-2/3 REPRODUCED (rail-over-chip
  28px overlap, zero-height "Tasks 1/3" box, ammo in 3-4px boxes; sweep blind:
  no appChromeRects axis, no painted-fits oracle). DIR-5 REPRODUCED live
  (emulator rotation: Feed 0x0 at inset corner, "skipped: Feed"; theme swap does
  NOT repair → decision latch over transient facts; model spec green only under
  single-batch facts). DIR-1 NOT reproduced in emulation (min gutter 4px under
  classic-desktop; PLAT-17 suspect; gutter-floor fix regardless). Six fix
  contracts recorded in rename/dir-reproductions.md → DIR wave after R1.
- DIR-2 text-overflow mechanism PINNED via A/B (pre-rename artifact from git vs
  rebuilt Facet place, same machine): both paint Fondamento via SHEETS
  (GetStyled shows it; plain FontFace reads LegacyArial — fell into the
  documented plain-read trap mid-diagnosis, corrected). NO font-application or
  rename regression. Real mechanism: width math ignores styled typography +
  give-way squeezes below floors (4px ammo, 48x0 Tasks). Contract 7 added
  (styled-measure everywhere + GetStyled-based sweep oracle). Both extra Studio
  instances stopped (pre-rename scratch instance left open, harmless).
- R1+R2 complete: 36/39 fixed, RR-11 + PLAT-8 contested with measured
  refutations (rounds<=CAP checked post-increment = exactly 100; bridge cleared
  by controller.dispose since NS-A12), DIR-1 model-innocent (per-package x =
  space.s 4..10) -> device-side + gutter-floor fix stays in DIR wave. Suites
  6270 (+82 accounted) / 3375. Renderer got prop_channels.luau extracted (was
  350 from cap); table.luau now 1,418 chars headroom — next-extraction trigger
  = next mission touching it. Commits 436e945..7456794 + RR 64949c8.
  Adjudication: accept both refutations pending scoped re-review verification;
  RR-11 pin + PLAT-8 disposal-path check named as re-review items.
- Perf gate PASS post-R1 (byte-identical artifact, no commit needed). R1 scoped
  review dispatched (Opus, read-only). R4 haptics dispatched (writer). DIR wave
  brief written (7 contracts incl. worktree negative-control for the extended
  sweep). Ruling R8: no ScreenInsets/SafeAreaCompatibility property flips
  mid-stage — E2 probe + decision packet for the device round instead; gutter
  floor ≥8px lands as a metrics change. Cost if wrong: DIR-1's device clip
  persists one round longer; mitigated by the 8px floor.
- Writer queue: R4 haptics (running) -> DIR wave -> R3 input -> R5 naming/
  consolidation -> docs wave (T12) -> T13 exercises -> T15 perf requalification
  -> T16 close.
- R1 scoped review: SPEC FAIL / QUALITY GOOD. 32 ADDRESSED, 4 PARTIAL (6,7,27,38),
  1 NOT ADDRESSED (item 10 — describesViewport judges an inset with the viewport
  that derived it: belt cannot refuse; 48-case sweep 0 refusals, worst accepted
  inset reserves 96% of an axis; spec certifies a shape roblox_env.bind never
  produces), 2 CONTESTED-ACCEPTED upheld (+RR-11 upheld). New breakage: 11
  (2 HIGH) + 4 mutation-confirmed coverage gaps — details in task-r1-review.md.
  Suite counts independently confirmed on a clean git-archive export (6270/3375).
  Fix round 1 for the wave queued BEHIND the running haptics writer (single-writer
  discipline); item 10 redo is the round's head item (DIR-5 foundation).
- Instrument trap recorded (R1 reviewer, measured): two concurrent
  `lune run tests/run` processes sharing ONE working tree fabricate failures
  (phantom syntax error in async_image.luau; phantom doc-drift failures) that
  vanish on a solitary rerun. All final numbers were re-measured in a private
  git-archive export. Standing rule for this stage: concurrent suite runs get
  their own export or wait; memory candidate at close.
- R4 haptics DONE: framework 0d3169e (6338, +68), RR 4e58424 (3383, +8).
  Adjudications: lazy pooling ACCEPTED (observable contracts intact; protects
  pinned blocked/boot behaviors); select-verb-first routing ACCEPTED (one-line
  flip if director disagrees); MAP.select/adjust dead-data note -> docs wave;
  RR haptics live-by-default on the game's existing UiSound switch — product
  note for the director (player-facing toggle = one-line follow-up).
  PENDING_DEVICE stands for feel. R4 review dispatched (isolated-export rule);
  R1 fix round 1 resumed concurrently (disjoint files).
- R4 review: SPEC PASS / QUALITY STRONG; 1H/5M/10L. F1 HIGH: FacetHitExpander
  (sibling GuiButton, screen_target:2213) never gets setActivationFeedback nor
  host Active state -> none-declared controls buzz in the tap band; disabled
  skip defeated for sub-44px controls; zero expander coverage in haptics specs.
  F2: pressSpecFor("select") returns UIClick preset -> select controls feel
  UIClick down + tick up, contradicting the round's own PHASE_VERBS doctrine.
  F4: device packet confounded (no isolation instruction; no keyboard/gamepad
  rows where down/complete coincide). F3: RR binds 1 of 4 presenters.
  CONTRACTS DECIDED for fix round: expander mirrors host verb+disabled state
  (identical sensation incl. silence); pressSpecFor("select") -> nil (select
  feels ONLY tick); same-frame press+release collapse plays only settle
  (non-pointer activation); packet gains isolation gesture + input-class rows;
  RR binds all four presenters. Queued behind R1 fix round (writer discipline).
  10 LOW -> deferred minors ledger.
- R1 fix round 1: ALL ADDRESSED per implementer (6351/3383 in private export;
  belt discriminator = byte-identical area beside changed viewport; quarantine
  keys on settle passes; gate trace failure-only bash-3.2 path). Commits
  6ccd7b2..05eafa8. Scoped re-review dispatched (sonnet). CARRY: table.luau at
  1,236 from cap — ledger trigger updated: builder extraction PRECEDES the next
  change that touches it (binding constraint for R5/naming + any later wave).
  theme_drift lint --[[ ]] blindspot fixed en route.
- R4 haptics fix round dispatched (writer): F1 expander mirror, F2 select-down
  silent, same-instant collapse rule, F4 packet rebuild, F3 all four RR
  presenters, remaining MEDIUMs. Told to STOP if table.luau needed.
- Wave R1+R2: COMPLETE (framework a8b0a26..05eafa8, RR 64949c8; review clean
  after fix round 1/5; re-reviewer re-ran mutations red; 0 new breakage).
  All Blocker/High from the review wave now fixed except those owned by later
  waves per findings.md dispositions.
- Haptics fix round 1 landed (3b8bfce / RR 1759409): F1-F6 fixed/measured,
  engine-side same-instant suppression honestly CONTESTED-ACCEPTED (undocumented
  engine behavior -> device rows D8/D9 with decided fallback: withhold press
  effects per input class if two pulses). Suite endpoint independently verified
  6372 in my own export. Re-review dispatched (sonnet). DIR wave dispatched
  (writer, Opus; table.luau off-limits; belt-aware contract 4).
- Haptics fix1 re-review: F1-F6 ADDRESSED, 0 new breakage, suites confirmed —
  EXCEPT F1 residual: enabled-seam mirror sits inside `elseif
  instance:IsA("TextButton")`, so TextField hosts with expanders skip disabled
  mirroring on that seam (narrower recurrence, untested). Haptics ROUND 2 queued
  (one item: mirror on every expander-capable host class + covering spec) —
  runs after DIR (screen_target single-writer). R4 stays open until then.
- DIR wave COMPLETE (d47f6d9..e60d30a, 6394/3384): contracts 2,3,4,5,6 DONE
  (band give-way via onGeometry monotone-in-epoch; disclosure guaranteed; settle
  null-result mutation-proved; extended sweep neg-control 6-failed/95-collisions
  pre-fix -> 82 passed; gutter via derived space.gutter=max(8,space.s) after
  measuring space.s bump broke 4 surfaces). Contract 1 CONTESTED-with-measurement
  (no region below floor; ornate chromeOutsets.panel=20 is DECLARED art overhang)
  — TextFits half open as a 269-truncation census. Contract 7: my stated
  mechanism refuted; real defect = clamped labels never report past the offer so
  ViewThatFits always picked rung 1; fixed narrowly, LT6-LADDERNEG rebuilt.
- Ruling R9 (standing-rule application, no user needed): VALUE-bearing text
  (timer/ammo/scores) may never truncate — the localization-safe rule "wrap/
  auto-fit, never clip" governs; lanes elide-with-disclosure instead. LABEL text
  may degrade via the ladder. The 269-census gets classified value-vs-label and
  value cases fixed; goes into the DIR fix round (or its own item if re-review
  is clean). Cost if wrong: HUD lanes elide more often under ornate.
- Device-pass additions: adaptive_controls at 640x320/Largest (contract-7 solver
  change); rotation Feed-returns check; chromeOutsets rect-only collision blind
  spot noted.
- Haptics round 2 landed (d2a9c47, 6396/3384): F1 residual fixed via DERIVED
  condition (hitExpander-presence guard, no class list — Grip was also outside
  the gate); screen_target crossed the 190k warning band and correctly owed a
  SOURCE_CAP_LEDGER row (the R2 mechanism biting as designed). Scoped re-review
  dispatched; R4 closes on its verdict. DIR review still running.
- DIR review: ACCEPT WITH FOLLOW-UPS; refutations upheld; negative control
  reproduced from scratch; whole-corpus ViewThatFits differential = exactly one
  node changed rung. Fix round 1 dispatched: H1 per-term epoch staleness specs
  (delete-each-term mutation matrix), M1 nested-ladder/authored-width cut rules,
  M2 honest paint assertion, R9 value-vs-label census classification with zero
  value-text truncations. LOWs ledgered: epoch omits platformChrome (0 decision
  divergence measured), fixture-owned give-way dies silently without onGeometry,
  extra feedback solve per epoch change, solver +7,954 chars w/ stale ledger row
  (fold into fix round? left to implementer's ledger duty), `local next` shadow.
- Wave R4 (haptics): COMPLETE (0d3169e, 3b8bfce, d2a9c47 / RR 4e58424, 1759409;
  review clean after 2 rounds; PENDING_DEVICE + engine-half CONTESTED-ACCEPTED
  remain as designed device rows). Evidence nit ledgered: round-2 commit claimed
  the parallel-list mutation reddens both pins; re-reviewer reproduced it
  reddening only the new pin (non-functional — coverage held by the new pin).
- Batched Studio pass shopping list (runs after R3 + rebuilds): rebuild places,
  reopen showcase; haptics calibration drive + sub-44px none-control expander
  check; DIR checklist (ornate hud numbers, rotation Feed-returns, zero
  value-text truncations); adaptive_controls 640x320/Largest; DF-7 modifier-sink
  measurement; DF-1..4 RR arbitration + RR canary + flag-gated surfaces ON.
- DIR fix round 1 landed (6424c5c, 6407/3384): H1 per-term epoch guards (4/6
  caught, riding/urlBar measured-uncatchable across 1,764 cells each + COVERAGE
  pin), M1 both halves, M2 restated dropped-only with self-mutating control,
  R9 timer->"2m" via ViewThatFits (946->832, all remaining label-class),
  solver warning-band row forced by the guard. Re-review dispatched (sonnet).
- R3 input-authority wave DISPATCHED (writer, Opus) in parallel — disjoint
  files (input/RR vs hud/solver). If a DIR round 2 triggers, it queues behind
  R3 (no two writers on overlapping files).
- Wave DIR: COMPLETE (3b8bfce..6424c5c, review clean after fix round 1;
  re-reviewer reproduced all 8 mutations exactly; 0 new breakage; 6407/3384).
  All DIR-1..5 fixes merged with guards; device confirmations pend in the
  batched Studio/phone pass.
- R3 landed (38500c8 / RR 2f3185a, 6412/3410): all 8 items, class-1
  must-migrate 5->0, arbitration bands + 26-case spec + 6 mutations, drift
  guard live on the gate row, flag 8/8 + 15 places rebuilt, DF-7 honest
  PENDING row. R3 review dispatched (Opus, hardest on the staging deletion).
- Ruling R10: menu.luau pinned as DK-16's third file (2 sites, platform menu
  keys, shipped+gated in navigation round) — director veto open in the final
  report. step8-debt gate regen running in background.
- Rulings R11 (luau-* tags -> facet-* outright, pre-public window), R12
  (world.luau: substrate + drift-hazard files only). R5 brief written; queues
  behind R3 review verdict + any R3 fix round.
- R3 concern noted for the Studio pass: both RR migrations swapped a proven
  ServerAdapter call for a documented one — checklist §7 reads the server side;
  if red on device, touch driving/assists are dead (E3 check mandatory).
- R10 integration fixes: menu pin corrected to OCCURRENCES (3, two on one line —
  the check's own line-vs-occurrence lesson re-learned by the controller);
  stale /tmp/facet_prior_gates.lock from my timed-out background run cleared
  (the documented orphan trap); new-primitive.md gained its constitution link
  (surface-ledger check). Both gates re-running in background (holds the tree;
  R3 fix round queued behind it).
- R3 review: ACCEPT WITH ONE BLOCKING FIX — RR modal band 3000 == Facet
  ENGAGED_BASE_PRIORITY on the same client: ButtonB double-fires
  sponsorCancel + Facet.Cancel; the no-op guard sinks ButtonA away from Facet
  base (1500) incl. results CTAs. Controller fix direction (not a renumber):
  game actions on Facet-presented surfaces route THROUGH Facet's action system
  (the mission's own no-parallel-paths rule); RR contexts keep world/gameplay
  actions only; cross-system spec builds Facet + RR contexts together.
- Prior-gate sweep (16 gates): TWO real reds, both pre-existing + dispositioned:
  (1) input-adaptation-audit::examples-no-input-boilerplate — red since mission
  baseline; the failing clause is the advanced-API grep over tutorial examples;
  route: T12/T13 wave (fix the example or extend the row's allowlist with a
  reason). (2) theme-packages-and-skinning::style-editor-sync — sheet dump
  predates the progress-ring tokens (sheet nil vs committed 30/3/9); route:
  fresh Studio sheet capture in the batched pass (the tool's suggested reverse
  reconcile would delete three GOOD tokens — do not run it). All other rows
  green or honest FAIL_ENVIRONMENT physical pendings. Load-noise rows cleared
  on the quiet rerun; Studio relaunch killed again.
- R3 fix round 1 landed (c12d2cf / RR 53b4544, 6412/3416): items 1-2 CONTESTED
  with strong evidence (legacy-rollback-only contexts, mutually exclusive with
  the Facet presenter; Facet already owns both verbs on default path) —
  controller ACCEPTS pending re-review confirmation; structural ceiling
  delivered instead (FACET_BASE_SCREEN_PRIORITY=1500 asserted; overlay 1400+
  Sink / hud 1200 / gameplay 1000; guard deleted; 4 scheme mutations bite).
  NEW pre-existing finding: FacetSponsor pose context SkipCelebration Space at
  1000-no-sink beside drift Space (DF-2 shape, DELIBERATE for racers per
  PRESENT_OPTS_RACER) — routed to the DESIGN review at close (game-design call,
  not a framework defect). R10 batch committed (ceb6db2). Re-review dispatched.
- Wave R3: COMPLETE (38500c8, c12d2cf / RR 2f3185a, 53b4544; review clean after
  fix round 1; contested items upheld with byte-checked evidence; 6412/3416).
  RC-12 PASS_AUTOMATED. Riders for R5: modal->overlay comment leftover
  (InputActions.luau:91-93) + R3 round-1's three trivials.
- DIRECTOR-APPROVED product addition (UI-SPEC verdict: Option A, 2026-08-18):
  reveal-richest-form on stepped-down composition regions. Constraints from the
  director: gamepad first-class; ONE GESTURE ONE MEANING (actionable compact
  forms get a separate chevron affordance, never overloaded controls); minimum
  form always carries the zone's essential value. Brief: task-reveal-brief.md;
  queued after R5 (presenter.luau overlap).
- DIRECTOR-ORDERED audit added (2026-08-18): ADAPT-AUDIT — the default-paradigm
  matrix (size-class x input combos vs expected paradigms; reference-platform
  tie-breakers allowed INSIDE the audit artifact + parity doc only; ten-foot/
  gamepad resolved via tvOS conventions per director). Brief:
  task-adapt-audit-brief.md. Queue position: audit seat runs read-only in
  parallel once R5 lands; its WRONG/MISSING findings get a fix wave before
  close; not-headless rows join the batched Studio/device pass. Updated queue:
  R5 (running) -> REVEAL (approved) -> ADAPT-AUDIT (parallel read-only) ->
  adapt fixes -> T12 docs -> T13 exercises -> T15 perf -> batched pass -> T16.
- R5 original seat died 4x on 529 Overloaded (giant replayed transcript likely
  aggravating). §1 (8691380 Controls namespace) + §2 (36d1883 tag rename)
  committed; §3a partial UNCOMMITTED in tree; no report file. FRESH seat
  dispatched: verify §1/§2 (incl. RR half of §1), adopt-or-redo §3a, finish
  §3b-§5 + riders. Lesson: after 2 consecutive 529 deaths, hand off to a fresh
  small-context seat with the report file as the bridge instead of resuming.
- Controller triage during the 529 outage: §1 VERIFIED (surface dump: VERSION
  0.10.0 + Controls table(frozen)); §2 VERIFIED (drift selftest catches a
  planted luau-* tag; luau-analyze/luau-lsp exempt). In-flight uncommitted work
  is FURTHER than reported: all four leaf modules exist (num/paths/rect +
  text_distance = §3d started), leaf_helpers.spec.luau new, 38 consumers
  migrated (net -100 lines), fast tier GREEN 5810 exit 0. Verdict: ADOPTABLE —
  resuming seat adopts, adds missing red-first evidence, commits §3a+§3d,
  continues. Scratch tests/_r5_one.luau to be removed before commit.
- Wave R5 COMPLETE (fresh seat; framework 8691380..d6c5b3c4, RR b9a7466,
  6a12637e, 927b8047; suites 6467/3417; surface diff = exactly the four
  permitted classes + specGuard). Contested items ACCEPTED: isRegisteredClass
  has a SHIPPED RR consumer (single-repo audit blind spot — lesson), authority
  read-only-to-refuse is not an inversion, class_contract at src/ root (solver
  also consumes), ARCH-18 recorded w/ trigger, REUSE-3 latent site honest.
  Process notes banked: zsh no-word-split broke commit_isolated (fixed 3ca4b51),
  git checkout -- destroyed two WT files mid-mutation-battery (reconstructed).
- THREE seats dispatched: R5 review (Opus, exports), REVEAL build (writer,
  canonical shapes), ADAPT-AUDIT (anchored d6c5b3c4, live-tree artifact only).
- R5 review: ACCEPT WITH FIXES — BLOCKER: reuse-ledger.md omits 109/125
  findings (incl. 9 of 12 brief-named keep-separates) while claiming
  completeness; REUSE-29 (in §3a scope) still unfixed at presenter.luau:949;
  RC-10 flipped on the faulty artifact (controller un-flipped it immediately);
  gate row blind (five fixed greps). 13 MAJOR: stylua red at
  gate_manifest:4032 executed clause; call-shape drift check line-based;
  host.new leaks adapter/input/presenter on failure AND dispose; ARCH-10/11
  justification false (solver never required class_contract); +4 world.luau
  unreproducible counts; +others in task-r5-review.md. R5 fix round queued
  BEHIND the REVEAL writer (presenter.luau collision).
- Wave REVEAL COMPLETE (66153fa..12476bf / RR 849d766; 6516/3418; expand knob
  renamed in time; RR results screen declined via expand="none" with positive
  control — a real consumer catch; modal-plate + recover="none" contested rows
  accepted pending review). REVEAL review dispatched (Opus). R5 fix round
  resumed (writer): honest 125-finding ledger + REUSE-29 + 13 majors incl.
  stylua gate clause, lexical call-shape check, host.new undo coverage,
  ARCH-10/11 justification correction. Device rows for the batched pass: sheet
  fallback e2e, Tasks-zone reshape, chevron arm's-length legibility.
- AWAITING DIRECTOR: ADAPT-17 (build snapping?), ADAPT-18 (table collapse after
  extraction?), ADAPT-8 (ten-foot metric ladder now or triggered follow-up?).
  In-stage ADAPT-FIX brief to be written once R5-fix lands (shares files).
- REVEAL review: CHANGES REQUESTED. HIGH-1 (reproduced): keyboard-only player
  cannot close the expand plate (Escape engine-reserved per ADR-0013 D1; empty
  ring; only pad B / mouse tap exit) — the wave moved modal PRESENTING into the
  framework without moving ADR-0013's focusable-close obligation; fix lives in
  ExpandPanel. Also: docs claim "Escape dismisses" while guide:256 says Escape
  cannot be bound (api.md:857, 01-concepts.md:419); M2 + M9 mutations vacuous
  across 6516 cases; CONTESTED-2 to become a refusal; census "nothing is
  hidden" edge over a stepped-down region. Esc-row verdict itself: NOT
  ADDRESSED-as-impossible (correct per platform). REVEAL fix round queued
  behind R5-fix (presenter overlap). Teardown 30-cycle zero-delta and the RR
  single-consumer proof both independently verified.
- R5 fix round 1 landed (7199318, 6534/3418): honest 125-row ledger +
  structural completeness checker (delete-a-row flips the gate — measured),
  REUSE-29 was FOUR copies, host teardown gained real dispose paths, RC-10
  legitimately PASS_AUTOMATED. CARRY: solver.luau 3,834 past its own extraction
  trigger (REVEAL growth) — extraction-first now binds solver like table.
  Re-review dispatched (sonnet). REVEAL fix round resumed (writer): keyboard-
  closable ExpandPanel (ADR-0013 obligation), docs truth on dismissal, refusal
  not default, two vacuous mutations, census edge.
- Wave R5: COMPLETE (framework 8691380..7199318, RR b9a7466/6a12637e/927b8047/
  849d766-adjacent; review clean after fix round 1; re-reviewer confirmed all
  items by measurement incl. delete-a-row gate flip; 0 new breakage; 6534/3418).
  Facet.Controls canonical at 0.10.0; facet-* tags; leaf modules; client host
  blessed; honest 125-row reuse ledger; RC-10 + RC-21 legitimately closed.
- REVEAL fix round complete at six items (4c79e1a, 5552272, a182648, d783648 /
  RR ddc4de4; 6546/3418): keyboard Close as last child riding ADR-0013's rule;
  docs dismissal truth; refusal semantics (caught pure-vs-host default split +
  RR blanket opt-out build error); M2/M9 bite without touching closed files;
  UNSEEN_CONTENT set named for its rule with Stage exclusion reasoned. Scoped
  re-review dispatched (sonnet). ADAPT-FIX wave dispatched (writer, Opus).
- Wave REVEAL: COMPLETE (66153fa..d783648 / RR 849d766, ddc4de4; review clean
  after fix round 1; re-reviewer confirmed all items with exact mutation
  isolation; 0 new breakage; 6546/3418). Director's expand feature shipped:
  keyboard-closable, one-gesture-one-meaning, key-info-in-collapse, census
  truthful. Device rows (sheet e2e, chevron legibility, Tasks reshape) join
  the batched pass.
- DIRECTOR RULINGS on the three paradigm calls (2026-08-18): ADAPT-17 BUILD
  (snap on the scroll substrate + compact card default); ADAPT-18 BUILD (table
  extraction first, then priority-collapse with the no-dead-ends disclosure);
  ADAPT-8 FULL APPLE-TV-STYLE SCALING (director overrode the keep-type-only
  recommendation — factor 1.5 matching the type floor, proportion-equality as
  the falsifiable acceptance, runs LAST to re-pin console geometry once).
  Briefs written: task-table-brief.md, task-carousel-brief.md,
  task-tenfoot-brief.md. Writer order: ADAPT-FIX (running) -> TABLE ->
  CAROUSEL -> TEN-FOOT -> T12 docs -> T13 exercises -> T15 perf -> batched
  pass -> T16 close.
- ADAPT-FIX COMPLETE (a4b17ff..30cec7f / RR 5ce9d09; 6579/3419): 15 cells
  fixed (touch->sheet fires in Cartwheel; short-side tablet classing; ten-foot
  unauthored text; pad/keyboard reorder), 21 contested (11 = table.luau),
  6 deferred. Concern flagged for review: surface_env weak registry =
  ARCH-24-class side effect on environment.new. Review dispatched (Opus,
  hardest on the registry). TABLE wave dispatched (writer) with the addendum
  absorbing the 11 table-blocked cells incl. ADAPT-10/13/14/15.
- ADAPT-FIX review: all items ADDRESSED/CONTESTED-ACCEPTED; 0 HIGH, 3 MEDIUM,
  5 LOW. Registry sound (0 retained after GC) but two internal rules to fix:
  values strong/keys weak, and ambiguity needs unpublish. Head MEDIUM:
  newTextInput hard-refuses unconditionally while api.md:6528 still promises
  optional env + graceful degradation (26 constructions). ADAPT-FIX fix round
  (3 MEDIUM + registry rules + counting errors; LOWs ledgered) queued BEHIND
  the running TABLE wave, before CAROUSEL. Writer order now: TABLE ->
  ADAPT-FIX-r1 -> CAROUSEL -> TEN-FOOT -> T12 -> T13 -> T15 -> batched pass
  -> T16.
- TABLE wave COMPLETE (9f8459d..0f20133 / RR 4026b9f, 468552f; 6633/3425):
  extraction unlocked the "no seam" file (two reassigned upvalues -> one
  record), FOUND+FIXED a live swipe-release bug in its own moved code (19-red),
  headroom 1,236 -> 18,412 with two more seams (disclosure, header) fired by
  their own triggers; collapse = hidden-not-When (no dead band, state survives
  rotation), disclosure reuses region_expand whole; 12 ADAPT cells fixed.
  CAP LOCKS NOW: renderer (1,018 from cap, rect_pass extraction owed FIRST),
  presenter (discloseScope seam owed), solver (owed). Review dispatched;
  ADAPT-FIX round 1 dispatched (small writer).
- DIRECTOR QUEUE (for the final report unless reviews escalate): TABLE's two
  carried narrowings (ADAPT-15 primary-action tables; ADAPT-27 handle
  placement) + the collapse-default product note (two shipped surfaces moved).
- ADAPT-FIX round 1 landed (2e347d6, 6640/3425): api.md refusal guard became
  structural (caught a fifth control); touchPrimary explicit fallback; registry
  moved ONTO the core after MEASURING the reviewer's weak-key/strong-value
  suggestion as a trap (env references core -> would pin everything); ambiguity
  a count + unpublish + host releases-last. Re-review dispatched (sonnet).
  CAROUSEL wave dispatched (writer) with all three cap-locks stated.
- TABLE review: CHANGES REQUIRED. Stage 1 extraction clean (byte-identity
  mechanical, 17/18 mutations bite). HIGH-1: collapse vs disclosure on
  DIFFERENT predicates -> silent column deletion (122/371 widths after one
  resize on a no-floors table; no chip/plate/dump). HIGH-2: exact float compare
  collapses fitting columns (53/1,011). MEDIUMs: ADAPT-11 env split decides
  which column dies; edit-mode mark doc/gate mismatch; ledger mis-attribution.
  Two candidates REFUTED with measurements (recorded, not repeated). Fix round
  1 resumed (table files only; carousel writer active on disjoint scroll files).
- 2026-08-20: weekly-limit outage over (user re-logged). All three seats
  resumed: TABLE fix round (table files), CAROUSEL (scroll/rail files, from
  scratch — died pre-work), adapt-fix re-review (2e347d6). User reports
  Facet-Showcase open in Studio, Rojo not connected — fine: the MCP bridge
  injects directly; the batched Studio pass runs in that session once TABLE-fix
  + CAROUSEL + TEN-FOOT land and places rebuild.
- Adapt-fix re-review: all items ADDRESSED except MEDIUM-1 residual (guard is
  a hardcoded 4-name list; newTabView refuses undocumented). Trap-reproduction
  independently CONFIRMED (weak-key tables are not ephemerons in this VM —
  durable platform fact). One-item round 2 dispatched (guard becomes
  structural + newTabView doc). RR suite pins to 468552f now (3425).
- DIRECTOR DIRECTIVE (2026-08-20): reduce memory via lazy loading where
  possible. Folded into T15 as workstream 7 (measure-first: require-graph
  memory table decides; lazy namespace boundaries only; surface-dump/checker/
  no-hitch contracts named; Facet.preload() escape hatch; honest-win rule).
- DIRECTOR DIRECTIVE (2026-08-20): themes out of the library, pickable per
  game. Verified already structurally true (model = src only; packages in
  examples/themes; src mentions are comments). THEME-UNBUNDLE brief written:
  per-theme build artifacts + self-containment proof + library-purity guard +
  docs catalog (T15 fills cost lines) + RR compat check. Queue position: after
  TEN-FOOT, beside T12. Updated writer order: TABLE-fix (running) -> CAROUSEL
  (running) -> adapt-guard round (running) -> TEN-FOOT -> THEME-UNBUNDLE ->
  T12 -> T13 -> T15 -> batched pass -> T16.
- TABLE fix round 1 landed (4979023 / RR 5f955ef; 6650/3425 in exports):
  HIGH-1 = predicate DELETED, one state, sweep 122-silent -> 52 collapse /
  0 silent / 0 unreported, rider reaches via the shipped divider gesture;
  HIGH-2 epsilon (not composition's EPS — different meaning, recorded);
  ADAPT-11 seven reads unified (231-vs-199 bite); mark fixed by GATING THE
  GUTTER (mode-with-content reasoning); ledger honest per commit. NEW DEBT:
  table.luau 189,197 — 188k trigger fired; disclosure-state seam (~4KB) owed
  before next change. ISSUE-6 (LOW) noted as HIGH-1's shape one level down
  (clamp vs collapse floor functions) — now VISIBLE not silent; fold with the
  next table touch after its extraction. Re-review dispatched (sonnet).
- DIRECTOR CHECK (2026-08-20): were layout primitives audited as paradigms?
  Honest answer NO — the 12 families were interaction-centric; stacks/grids/
  ZStack/ViewThatFits/spacing/scroll-as-layout only incidentally covered.
  Supplemental audit seat dispatched (Part 2: matrix-layout.md, 7 row
  families, same method/anchoring). Its WRONG/MISSING cells join the adapt-fix
  disposition flow before close.
- Adapt-guard round 2 DONE (e25ad06 + the guard half swept into 4979023 by the
  concurrent stager — attribution noted, content correct): guard derives from
  the two refusal shapes across 33 modules (5 found, 0 false positives, bite-
  checks in memory); newTabView documented. In-tree 1-red = the guard catching
  newVirtualList pre-registered ahead of its source — routed to the carousel
  writer to close either way. Adapt-fix wave now fully closed pending that.
- Open seats: TABLE-fix re-review, CAROUSEL build, layout-primitive audit
  supplement. Then TEN-FOOT -> THEME-UNBUNDLE -> T12 -> T13 -> T15 -> batched
  pass -> T16.
- Part-2 layout audit landed (matrix-layout.md, 61 cells: 42R/11W/5A/3M):
  ADAPT-L1 critical (ADAPT-23 fix inert on default path — folded into TEN-FOOT
  as its first proof cell); ADAPT-L2 critical (Grid = 1 lane everywhere);
  L3 viewport-not-container axis; L4 silent permanent VStack; L5 overflow
  default = paint outside. LAYOUT-FIX brief written (runs after TEN-FOOT;
  L10 snapping stays with carousel). Updated queue: TABLE-fix re-review +
  CAROUSEL (running) -> TEN-FOOT -> LAYOUT-FIX + THEME-UNBUNDLE -> T12 ->
  T13 -> T15 -> batched pass -> T16.
- Wave TABLE: COMPLETE (9f8459d..4979023 / RR 4026b9f, 468552f, 5f955ef;
  review clean after fix round 1; re-reviewer confirmed all five items with
  exact mutation reproductions — the 53/1,011 phantom-collapse revert, the
  231-vs-199 env case, the forced-false sweep bite). The re-review's "2 new
  breakage" = the known cross-wave staging tangle: newTabView doc closed by
  e25ad06; newVirtualList expectation closes with the carousel wave (routed).
  Director's column-collapse paradigm shipped with zero dead ends.
  Remaining table debts: the fired 188k trigger (disclosure-state seam ~4KB,
  extraction-first) + ISSUE-6 shared floor function — both fold into the next
  table touch.
- INTERIM STUDIO PASS (director-ordered, live session, tree at ce56ac6):
  injection clean (336 nodes, 0 refused — the extractions paid off). FOUND:
  INT-1 card-rail + sorted-entries FAIL TO MOUNT live (showcase demo host
  publishes no env; refusals fire as designed; headless green because no spec
  exercised the HOST path) — routed to carousel writer with red-first host-path
  spec demanded. INT-2 the §5 scenario surface REGRESSED silently (attribute-
  driven FacetScenarioAPI no longer boots; worked 08-17) — investigation +
  fix + silent-failure guard dispatched. VERIFIED LIVE: 34/36 demos mount;
  ten-foot type floor 1.5x exact at console row (16->24, 22->33). BLOCKED
  live: input injection lacks capability in this VM (known XP-B3) + scenario
  surface down -> table-collapse/expand/carousel interaction rows move to the
  batched pass AFTER INT-2's fix restores the driver's scenario route.
  Carousel review seat running in parallel.
- CAROUSEL review: ACCEPT (both layers measured; one-clock confirmed; anchor
  composition refuted-then-verified; contest upheld with a rigor caveat). Its
  fixes folded into the writer's live round: virtual_list ledger STALE by
  1,847 (real 192,195; 805 from trigger — extraction-first if host fix grows
  it), velocity-detector coverage case, 1 MEDIUM, matrix-row OVERTAKEN
  annotations. New standing note: check_input_authority standalone exit-0-
  while-selftest-FAILED (pre-existing, ledgered for T16 triage).
- CAROUSEL wave: COMPLETE (f3d2fe8, c247f1b, 0411973 / RR a90a6f6; review
  ACCEPT + fixes folded; 6719/3431). INT-1 root cause: demo PROXY core +
  rawget-blind registry lookup (sorted-entries broken since ADAPT-1; card-rail
  second casualty) — fix: find() reads through the index, delegation answers;
  host-path spec sweeps all 36 with negative control. virtual_list trigger
  ARRIVED (805 away) — extraction-first binds it (4th locked file). Discipline
  recorded: measure ledger sizes LAST. Bycatch (unowned, real): with-animation
  + tab-view DOUBLE-DISPOSE at teardown → findings ledger for the next
  gallery-area round. c247f1b swept a concurrent tests/run.luau hunk (benign,
  disclosed; that commit alone couldn't run the suite — noted for history).
- INTERIM PASS CLOSED (interim-studio-pass.md committed): 36/36 live, §5
  surface alive + negative control, precedence live, ten-foot floor 1.5x
  exact, three emulator rows driven. Owed to batched pass: ex02 resize step
  (prep), expand keyboard walk, carousel §12a-c, device half. INT-2's live
  canary DONE (was the diagnosis seat's owed item). Next writer: TEN-FOOT.
- TEN-FOOT COMPLETE (35f7348, 2e2d6d7, fd59cae / RR 655cbd7; 6750/3437):
  ladder at the themeMetrics memo seam — ZERO locked files touched; ADAPT-L1
  proof cell (5 vs 9 lanes); metricScale IS tenFootFloor (identity asserted);
  densityClassOf structural classifier; hit floor 66 one-owner; 20 re-pins;
  ADR-0039. CONTESTED (accepted, director queue): table minWidth author-
  literals don't follow the ladder — needs table.luau extraction-first, its
  own wave post-stage or in T16 triage. ADAPT-8 human half = batched §13 rows
  (1.5 at 3m is the director's eye; one-line change + named sweep if re-ruled).
  Two instrument catches recorded (art geometry must not scale; throwing memo
  = silently deaf surface).
- THEME-UNBUNDLE COMPLETE (da50128..a04be05 / RR e4f02a2; 6766/3440): 8
  artifacts (4.2K..14.7K — real cost numbers for the catalog), purity guard
  caught 2 live library defects (slug example + a refusal pointing consumers
  at examples/themes — both rewritten not allowlisted), enumerator-derived
  everything, RR names-none guard. CONTESTED accepted: no package declares
  metrics.tenFoot yet (derived ladder proved; declaration path via negative
  control). NEW OPEN: check_flat_baseline red at fd59cae (9 popup-surface
  problems, inherited — owner TBD after LAYOUT-FIX lands, likely their
  neighborhood). Self-containment check homeless → Step 14 gate note. Review
  dispatched (sonnet).
- TEN-FOOT review: ACCEPT WITH FINDINGS (mechanism real; seam blob-verified;
  L1 red-at-anchor reproduced; minWidth contest UPHELD). Fix round dispatched:
  vacuous deaf-surface guard (reviewer verified the one-liner), radii/strokes
  RECLASSIFIED must-not-scale (ruling R13: metric agrees with the paint
  authority; TV-radii question = batched §13 director-eye row), identity spec
  honest, env.get normalization pin must bite + derivative double-apply blunted.
  2 LOWs + informational ledgered.
- Wave THEME-UNBUNDLE: FULLY CLOSED (…a04be05, ddebd97; review ACCEPT + round-2
  transcripts recorded both-ways in artifacts.md — accepted without a third
  seat). Silent-refusal was worse than reviewed (pre-check stale artifacts);
  now loud + named cleanup. Suites 6781/3443 at ddebd97 with concurrent
  LAYOUT-FIX commits (ed825da, 8fd4779, 021a896, 8e69648 / RR 1888cd6)
  accounted; awaiting the LAYOUT-FIX report notification.
- LAYOUT-FIX COMPLETE (91a474d..a6a4c0a / RR d708d26, 1888cd6; 6781/3443):
  ADAPT-L2 Grid lanes FIXED via minColumnWidth="intrinsic" default (TV 5 vs
  desktop 9 from one line of existing machinery); L4 axis required, fixture
  comments now true; L3/L5 CONTESTED with killing evidence (contentWidth
  deprecated-for-cause; focus_map live axis read; hwrap no shrink pair) +
  guards for every reproduction; corpus re-verdict: pages bleed, not rows.
  Live score 49/61 RIGHT. Ruling R14: B-6e ten-foot measure cap = 900
  (tablet 600 x 1.5 proportion doctrine), director veto in batched §13 —
  one-liner dispatched to the wave writer. Review dispatched (Opus). The
  8 extraction-locked contests = the post-stage extraction wave's charter
  (disposition owner recorded at T16). commit_isolated lesson #2: read the
  DROP list (markers match hunks; a bare load-bearing line vanishes).
- TEN-FOOT fix round landed (c4a751e / RR b3bcbae; 6785/3443): deaf-guard
  marker-per-case (bites alone); radii/strokes must-not-scale under the new
  doctrine "a metric may only scale where the framework owns the paint"
  (DENSITY_PAINT_SECTIONS); adapted-write REFUSED (no lossy third answer),
  red-first on 44->66->99; identity = value-agreement over the whole closed
  domain. Director taste number banked for the batched pass: table row 84px at
  console vs 36 desktop / 44 touch. Re-review dispatched (sonnet). Remaining
  seats: layout-fix review, B-6e, tenfoot re-review -> then T12 docs.
- Wave TEN-FOOT: FULLY CLOSED (35f7348..fd59cae + c4a751e / RR 655cbd7,
  b3bcbae; review + fix round + re-review all clean; 6785/3443; five locked
  files blob-verified untouched across the whole wave). The director's
  Apple-TV ruling is shipped: full metric ladder, 66px targets, 5-lane cap,
  900px measure (R14), paint-ownership doctrine, device-eye rows staged.
- LAYOUT-FIX review: ACCEPT + policy catch (2 breaking changes unrecorded;
  instruments structurally blind to required-flips). Ruling R15: pre-release
  breaking changes ride the unreleased 0.10.0 with an ADR record (ADR-0040) +
  the instrument closes (required-flip/default-change detection) + constitution
  §14 pre-release clause; NO compat shim (refuse-don't-guess stands). Fix
  round folded into the writer's B-6e work. Director veto on R15 in the final
  report.
- LAYOUT-FIX fix round + B-6e landed (fa5f21a..5d97826 / RR 57bbdc8;
  6794/3446): maxWidth as minWidth's twin (the audit's maxMeasure seam was
  WRONG — 452px trap caught); Cartwheel fixed-px-at-distance latent defect
  fixed; ADR-0040 (13 breaking surfaces, R15) + required-flip/default-change
  instruments (6 mutations); constitution §14 pre-release clause. Re-review
  dispatched (sonnet). T12 DOCS WAVE dispatched (writer, Opus) with the full
  post-wave state distilled. ADR-0040 carries the 0.10.0-boundary question to
  the director's final report.
- Wave LAYOUT-FIX: FULLY CLOSED (91a474d..5d97826 / RR d708d26, 1888cd6,
  57bbdc8; review + fix round + re-review clean; 6794/3446; locked files
  byte-identical across the whole range). LOWs ledgered for T16: ADR-0040's
  B-1 record-check string non-unique (prose duplicate); two stale count lines
  in the report file. ALL PARADIGM WAVES NOW CLOSED (adapt-fix, table,
  carousel, ten-foot, layout-fix, theme-unbundle, reveal). Remaining: T12
  (running) -> T13 exercises -> T15 perf/memory -> batched pass -> T16.
- T12 COMPLETE (25b838b..2b05191 / RR fccf29d; 6799/3449; vendor 724->0 in
  scope with selftest; catalog 107 derived; comments 88->29; writing checker
  36->0). Review dispatched. T13 EXERCISES LIVE: clone A (ColorWell fresh
  author, zero mission context), clone B (seeded defect: FIT_EPSILON reverted
  to 0 + its one covering case removed — suite green 6798 in clone, tree
  clean, defect uncovered and player-observable; agent must repro, own, fix,
  regress, gate). Verifier seat follows A's report. Exercises do NOT merge;
  journals drive real improvements.
- RC-20 PASS: seeded-defect exercise DONE by a zero-context agent — repro
  53/551 widths, correct owner, one-line fix matching the docstring's own
  argument, stripe regression + null hypothesis, proportionate checks, clean
  commit via commit_isolated. Friction harvest (for the improvements round):
  no root README; doctor.sh false-alarms on clean checkouts (build/ never
  created); no single-spec runner; stale "~42s" suite timing; no proportionate
  verification bar for small fixes; framework-standalone verification impossible
  (RR shell-outs) — the last is Step 14's standalone-consumer concern, recorded.
- T12 review: CHANGES REQUESTED (instruments bite; scope drawn by directory
  not reachability; comment numbers irreproducible; RC-18 un-flipped by
  controller at 9401845; 19 reader-facing mechanical-strip defects). Ruling
  R16: vendor scope = link-reachable from the shipped doc surface (one owner:
  check_docs' link graph); linked ADRs teach in Facet/Roblox terms, history
  notwithstanding. Fix round dispatched to the T12 writer. LazyVGrid/
  contextMenu occurrences to be classified prose-vs-identifier (identifier
  renames CONTESTED to the deprecation policy, not this round).
- T12 fix round 1 landed (1482571, 69ae4ee; 6803/3449): reachability scope
  (56/17 exact match to review; ADR-0014 defines first responder in Facet
  terms; depth-1 recorded with the transitive alternative measured); zero
  vendor identifiers among exports (verified against the surface dump);
  comments 531->122 ratcheted; pin verifier committed (237); prop_parity
  comment-blindness FIXED not dodged; 19 defects closed. Ruling R17 (RC-18
  closure rule): the bar is UNEXPLAINED shorthand — round 2 dispatched:
  resolvable-vs-orphan classifier, orphans -> 0, resolvable stay as citations,
  ratchet on orphans; + disarm the ten remaining fixed-char comment slices.
- RC-19 first half PASS: ColorWell DONE by a zero-context agent (6837 green in
  clone, all gates clean, hardening gate byte-identical; two named exceptions
  both REAL repo defects: the 19-pin contradiction + no live Studio for its
  checkout). Friction harvest x5 (19-pin, six unlisted registrations, 44px doc
  trap, two undocumented truths, fast-loop discoverability). IMPROVEMENTS
  ROUND dispatched (both journals; 8 decided contracts incl. derive-the-pin,
  scaffold-stamps-all, root README, doctor fix). After it lands: the
  human-verifier seat re-walks the improved guide (plan's rerun-until-clean),
  then T15 perf/memory.
- T12 round 2 landed (d2d53bd, c1a243d, 931393c; 6803/3449): orphans 87->0
  (ceiling 0, not a ratchet — "what the rule prohibits"), resolvable 25 with
  per-site routes, locked-185 separated; slice trap disarmed everywhere via
  the one owner (adapter_source.bodyOf); RC-18 PASS_AUTOMATED on the R17 rule;
  its own gate row caught as unrunnable shell (backtick substitution) by
  execute-not-inspect. Comment trajectory: 531 -> 25 across the campaign.
  T12 re-review dispatched (sonnet). Improvements round still running.
- Improvements round COMPLETE (8ed3cb8, ce40a79, d8aa27e; 6808/3449 + all
  checkers green): 19-pin derives; scaffold stamps all six registrations
  (end-to-end run: zero undocumented failures — its own two output defects
  found+fixed); root README (with check_doc_style extended to scan it); doctor
  fixed (swept into d2d53bd, disclosed); fast loop taught; four contested
  calls recorded. FINAL EXERCISE SEAT dispatched: human-facing verifier walks
  the improved guide in fresh clone exC (protocol per step). T15 PERF/MEMORY
  dispatched (writer, Opus — the last build wave). T12 re-review fork still
  out.
- T12: FULLY CLOSED (all rounds + re-review + micro-round; 4d1f285; orphaned
  punctuation probe widened with base-control). Controller follow-through on
  the micro-round's residual: the two declarative-3d spike evidence JSONs were
  IGNORED by the blanket artifacts/**/*.json rule while four gate pins target
  them — force-added (commit above); pin count now clone-stable. Process
  failure recorded from the round: checkout-revert erased hand edits mid-batch
  (nine of ten accidentally survived via later passes) — verify-per-edit, not
  per-batch, after any revert.
- Human-verifier walk DONE (exC protocol: 7 steps, 5 MATCH / 3 MISMATCH /
  2 UNCLEAR): eleven-vs-ten count; the specGuard example HANGS in-repo
  (circular require — dangerous); "double-fires" is false (real behavior:
  node handler silently shadows the bundle handler — intent TBD); gate-
  cascade guidance gap. Final guide round dispatched (incl. loud-failure
  guard for the hang if cheap; activate-precedence intent verdict or
  CONTESTED). RC-19 closes when this lands.
- T13 EXERCISES: FULLY CLOSED (4167ff4). RC-17/19/20 PASS_AUTOMATED; exercise
  artifacts installed (journals + verifier protocol + READMEs); gate rows
  earned run strings (their PASS lands on the batched pass's full gate rerun —
  quick rerun timed out cold). REMAINING GAP: RC-11 maintainer map — fold into
  the batched-pass prep round alongside T15's close (small: derive the
  area->owner/seam/tests/gate/extension table from the now-clean structure).
  Board: T15 (running) -> RC-11 round -> batched Studio pass -> T16 close-out.
- T15 COMPLETE (1bde05e..1f9510a; 6821/3449; perf PASS; surface byte-identical):
  memory table (require = 2,797 KB; lazy Controls = -831 KB / -29.7%; RR
  subset -550 KB); lazy NOT shipped — no type analyzer instrument, disposition
  owner+trigger (analyzer gate row; DIRECTOR CALL at close: add luau analyzer
  to toolchain?). RR-5 re-derived 38 sites: 4 fixed / 2 locked / 18 noise /
  14 unmeasured (no VirtualGrid/RowActions scene — recorded). Instrument
  catches: aggregator read all owned dumps as EMPTY (Facet/-filter, fixed +
  selftest); place 3 days stale; haptics counters absent from capture rows;
  three workloads lost from the guide. PLAT-20 stays OPEN (headless-blind).
  T15 review + RC-11 maintainer-map round dispatched in parallel.
- DIRECTOR RULING (2026-08-21): "Luau already has a type solver" — the T15
  contested blocker is a toolchain pin, not a gap. Round dispatched: pin
  luau-lsp/luau-analyze via rokit, witness type-check over the 19 Controls
  signatures (red-first both directions), SHIP lazy Controls (-831 KB) with
  surface-dump byte-identity + no-hitch spec + Facet.preload() + realized
  memory table + RR lockstep evidence.
- DIRECTOR DEVICE ROUND 2 (2026-08-21, expand feature live): DIR2-1 stepped-
  down pills paint EMPTY (violates the approval's key-info constraint; the
  value-text oracle is structurally blind to an empty box — instrument fix
  demanded with the fixture's own NOT PAINTED counter wired in); DIR2-2 the
  plate HIDES the whole base screen (contract: over the live screen, rest
  visible); DIR2-3 Close -> X icon (a11y label stays verbal); + plate under-
  offers width (task labels truncate in the RICH form). Priority round
  dispatched to the reveal implementer; batched pass re-verifies live.
- T15 review: CHANGES REQUESTED — 3 red release-gate checks the wave introduced
  and its report omitted (hand-picked verification tail; the citation rule
  caught its own successor wave); memory headline overstated (bimodal; mode-
  matched 600-795 KB); capture-plan parser silently drops cleanCapture; 6/13
  rows name a nonexistent counter. ALL folded into the running lazy-ship round
  (same agent). Standing rule from this: a wave's verification tail = the gate
  rows, never a hand-picked list.
- RC-11 CLOSED (b5bad08..425e5dd; 6841/3449): docs/MAINTAINERS.md 19 areas /
  28 src entries, all columns derived-from-source, 12-obligation drift check
  (7 scratch + 20 in-memory plants), gate row maintainer-map-current exit 0;
  found+fixed the eleven-vs-twelve blessed-modules doc defect. Its three
  contested reds correctly attributed to T15 (already in the lazy round's
  fold-in). Two instrument traps recorded (SIGPIPE-141 under pipefail;
  grep -qF line-wrap pins). REMAINING SEATS: expand-defect round, lazy-ship
  round -> batched Studio pass -> T16.
- DIRECTOR ORDER (2026-08-21): final visual + synthetic-input sweep confirmed
  and EXTENDED as batched-plan §14 (36 demos x 5 views scripted oracles;
  rotation round-trips; theme axis; semantic drives via scenario steps with
  honest evidence-class labels; capture packet for the director's eye).
- DIRECTOR (2026-08-21): eyeball confirmation made explicit — §14f two-layer:
  controller reviews EVERY capture visually during the pass (green oracles
  notwithstanding), director's organized eye pass is the binding gate;
  eye-vs-oracle disagreement = an oracle finding too.
- DIRECTOR ROUND 2 fixes landed (9a32399; 6851/3449): DIR2-1 root cause = the
  framework's own transparent cover ABOVE author content (z measured 116/115
  vs text 113) — cover role RETIRED structurally (nothing-above-author rule;
  chevron-beside only); NOT-PAINTED readout was a stale probe row; DIR2-3 X
  icon chip (a11y label verbal); plate under-offer fixed (184->328, second
  consumer lockstep). DIR2-2 base-disappear NOT reproduced headlessly — tail
  seam band (the only opaque candidate) removed + EXPAND 16 fence; STAYS OPEN
  until the batched pass verifies live. BLOCKED to the extraction charter:
  mark-yields-to-value (2 lines in locked solver). New sweep oracle:
  emptyCollapseViolations (blank chip reddens 5 cells; honestly states its
  engine-side blindness).
- DIRECTOR ROUND 3 (2026-08-21, live showcase): DIR3-1 transient surfaces from
  buttons must appear OVER the live screen — FRAMEWORK RULE per director
  ("seen a couple times"); opaque full-screen backdrops behind transients
  banned, scrims translucent by token contract; guard across the anchored
  family with opaque-mutation red. DIR3-2 showcase chrome gamepad access:
  L1 = demo picker, R1 = settings, focus in, B out. Dispatched to the
  anchored-surface implementer. Controller fixed own two gate-row defects
  (migration-doc path; unanchored suite grep -> cache-status check).
- LEDGER CATCH-UP (final review M1 — the missing entries): lazy-Controls ship
  landed (45fc2c6..8202a9d: luau-lsp@1.69.0 pinned, check_types witness over
  19 signatures red/green both ways, 4-entry defer shipped for 228 KB
  [131..313] with the 860 KB ceiling on the extraction charter, three red
  gates repaired, capture-plan parser refuses unparsable pairs); acceptance
  catch-up commits (af2c806, fe4da14); five-red-gates repair (12ae6d5,
  ea4e342, c54a1c7); places rebuilt (7e34ce1); batched pass executed
  (close-out.md, 0c14f07); style-editor-sync closed live (b832793); director
  round 3 dispatched (DIR3-1 transient-over-screen framework rule, DIR3-2
  L1/R1 chrome access).
- FINAL REVIEW verdict NOT-READY (final-review.md): H1 fixed-in-crossing
  (path + grep, committed); H2 = the Studio profiling captures silently
  dropped from close-out while the gate row passed on file existence —
  closure in progress (lab telemetry captures + honest gprx disposition);
  M-items being closed in this batch; the M2 missing review seat dispatched.

## 2026-08-21 (cont.) — final-review closure batch + DIR4

- M3 t16-triage.md written (5656ade); M4 DIR2/DIR3/DIR4 rows in findings.md; M5
  promotion tracker refreshed with owner+trigger (130dcae); L2 reviews/README
  seat note. M2 seat dispatched and RETURNED: Round A (lazy ship) APPROVE WITH
  FINDINGS (2H/5M/6L), Round B (DIR2 fixes) APPROVE WITH FINDINGS (1H/1M/2L),
  suites reproduced at both endpoints, all claimed mutations bite. The two
  load-bearing HIGHs: A-H1 both laziness pins pass with the mechanism deleted;
  B-H1 the hit expander's 44px floor reaches 12x20px over author content and
  EXPAND 15 reads rect, never hitRect. Fix round dispatched (task-m2fix:
  A-H1, A-H2 stale-831KB/idiom purge, B-H1, A-M1). Ruling R18: the hit-expander
  floor is EXEMPT over passive content (F1 accessibility floor, platform
  convention), BANNED over interactive content; the fence reads hitRects with
  exactly that split, plus a paint-inertness pin (no slot tags, no paint
  claims) — "transparent so harmless" stays refused. Cost if wrong: a passive
  overlap that turns out to paint; the pin is what catches it.
- H2 disposition: FAIL_ENVIRONMENT, recorded in requalification.md §5 and the
  perf-requalification gate note corrected (it claimed captures never taken);
  run string now checks the honest markers. The MCP session cannot open a
  different .rbxl — the 13-row plan is runnable the moment a human opens the
  lab place. Asked the director (they are live at the machine today).
- M6 executed live on the console-ten-foot row (stamp 8d1aa6f6-6889795,
  injected at HEAD after starting studio_sync): §13a ladder (spaceM 24,
  controlHeight 66, ×1.5), §13c overscan once (eff 90/60, authored 0), §13d
  4 lanes @404 vs desktop 4 @289 + table 84px rung, §13e GetStyled stroke 1 /
  scrim 0.45 / capsule unscaled. Item 5 haptics calibration: adapter refuses
  honestly on macOS (decorated 12), per-phase counters move, fallback
  reachable, Custom effects built. FOUND+FIXED en route (3ad40b0): the
  scenario runner's fn(session,payload) call shape vs the sensory scenario's
  one-parameter steps — the whole scripted calibration route was dead while
  its spec (payload-first calls) stayed green; serializer cycle guard added
  (a poisoned signal stack-overflowed api.step). Suite 6865.
- DIR3 live check: L1 opens the panel over the live screen with the scrim
  between ✓; R1 dead live (presenter Adjust binds L1/R1 for adjustTargets;
  the chrome's "no other context binds either key" comment is false); B is
  CoreGui-bound, injection refuses it. DIR4 (director live report: chips
  vanish on console + shoulder discoverability): root cause measured — chrome
  edge-to-edge at (12,12) vs body overscan-inset x=106; TV bezel eats the
  chips. DIR4 implementer dispatched (overscan-aware chrome, gamepad shoulder
  glyphs, R1 contention fix); told mid-flight to use commit_isolated (two
  writers now share the tree).
- DIR3 review seat dispatched (task-reveal-review.md) — running.

## 2026-08-21 (cont. 2) — H2 captured; DIR4 landed + verified live

- H2 EXECUTED: the director opened the lab place. All 13 capture-plan rows
  driven at desktop-standard 1280x720 (the lab REFUSED the host's native 1920
  width — Large classing made 77px rows in 60px slots; that refusal is the
  lab working), profiler armed and staleness-asserted, rows landed byte-for-
  byte via the studio_sync bridge + check_perf_captures PASS (9de8bfd, force-
  added past the blanket ignore). Headlines: edit-locality arrangePerEdit=1 /
  partialSolvesPerEdit=1 (RR-5 live on engine); variable-extents
  arrangePerGrow=1 all arms; host-move hosted 9.82 vs unhosted 12.86 us/leaf
  (ADR-0032 answered in the win column); soak core counters byte-identical
  x12; require(Facet) 4.7MB Studio heap vs 2.8 headless; haptics counter flat
  across a scroll. NOT captured: .gprx binary dumps (no scripted route; LibMP
  live aggregation recorded instead) and the Android device row. LESSON: the
  lab keeps only the LAST export row — save each row through the bridge AT
  drive time, or you re-drive everything (I re-drove; deterministic seeds).
- Gate-row case bug found+fixed (158ba46): my perf-requalification grep used
  lowercase "verified" vs the file's "Verified" — check_gate_pins caught it,
  and it was ALSO the comments-plain red (that row runs check_gate_pins).
- DIR4 LANDED (68f813e, 67256d2, 3f6ea5e; suite 6881 = 6865+16, all its own):
  overscan chrome (root cause: solver answers edgeToEdge with the raw viewport
  and reads no insets — renderer computed and DISCARDED the ten-foot margin
  for that surface), LB/RB hints via displayName->Facet.inputHint (no new
  API), double-fire fixed via sink=true per R19. ITS NULL RESULT: the brief's
  "R1 loses the contention" premise was WRONG — headless, chrome wins both
  keys at 3500; the reproducible defect was the double-fire. MAJOR-2
  mitigation shipped (skip re-present when already above), full fix CONTESTED
  into the presenter extraction; MAJOR-3 guard now RED at the parent commit
  (the definition of a guard that works). CONTESTED-2: first modal ties 3500,
  a modal demo with focused adjust target still double-fires — framework
  re-banding call, queued for the director report.
- DIR4 VERIFIED LIVE (fresh showcase session, injected clean-HEAD export
  e35325e0-6907328): chips (102,72) inside the safe band, glyphs painted and
  ladder-consistent, all six section-state transitions proven at the ACTION
  layer (InputAction:Fire press/release pairs — Fire(true) without Fire(false)
  is a held edge and later fires are ignored; instrument note). Raw injected
  input did not deliver AT ALL this session (Backquote included; census shows
  every context/binding correct) — so the old session's "R1 dead" was almost
  certainly flaky injection delivery, not code; raw-delivery rows moved to
  the device packet where E4 already places them.

## 2026-08-21 (cont. 3) — m2fix landed

- M2FIX LANDED (1f0b99d..1f9e32c + report 5e8c1d9; suite 6883 = DIR4's 6881
  + 2): A-H1 closed by watching the CALL, not the cache (src/init.luau
  re-loaded under an interposed require; deferred set DERIVED from
  source-minus-load-log; P1 3 red / P2 1 red / P3 seam pin red); A-H2 purged
  at all six sites plus two the review missed, retracted numbers NAMED as
  retracted; B-H1 fence reads both rects screen-wide under R18 with the
  passive-overlap assertion non-vacuous and a three-half paint-inert guard;
  A-M1 made true (SUPERSEDED table + banner). EXTRA: surface-ledger-complete
  had been RED since 8202a9d (preload shipped with no ledger row) — repaired.
  Its measurement lesson: in a shared tree a baseline pins by CONTENT
  (revert the other agent's paths inside the same snapshot), never by timing.
- Booked to triage: solver-side hit-floor reserve (fixture-only ban today),
  presenter.raise/displayLayer seam, modal-ties-3500 (DIRECTOR CALL), the
  831-literal gate idea, locked-module comment debt.
- Requalification §5 updated: the environment unblocked and the 13 rows ran;
  still open = .gprx dumps + Android. Review seats running: DIR4 (task-dir4-
  review) and m2fix (task-m2fix-review).

## 2026-08-21 (cont. 4) — DIR4 review seat back; fix round 1 dispatched

- DIR4 REVIEW (task-dir4-review.md): spec PASS, quality CHANGES REQUESTED,
  2 MAJOR / 7 MINOR. Everything measured reproduced (suite arithmetic exact,
  all 8 mutations + the reviewer's own, guard red at the parent, near rows
  proven byte-identical at all three viewports, R1 null result confirmed,
  sink per-key against eight unbound keys). The two MAJORs are the two
  things the round REASONED instead of measured: (1) the layer-climb
  mitigation's type(demoHandle)=="table" guard bites on NO real path
  (demo_picker passes nil on failed mount; the certifying case hand-builds a
  table no call site produces); (2) §5 re-asserts "nothing else binds either
  key" for ButtonY while src/controls/menu.luau binds it sinking in the
  shipped menu demo — one Y press at head opens the CHROME and eats the
  framework's own menu verb.
- RULING R20: ButtonY leaves the chrome toggle entirely. The bumpers are the
  pad's chrome doors (R19) and make Y redundant there; the platform gives Y
  to menus and the framework's menu verb claims it. Keyboard keeps Backquote.
  TOGGLE_GAMEPAD removal rides R15 (unreleased inside 0.10.0). Cost if
  wrong: a pad user who learned Y loses one habit; the bumpers are painted
  on screen, the habit re-forms in one session.
- Fix round 1 resumed on the same implementer: both MAJORs + five MINORs
  (right-edge overscan inset — a real TV crops both sides; dead BAR_ID;
  unpinned warn; loose isPanelPath; the R19 comment's false claim about
  what Adjust keeps on a pad). Gate PASS frozen at 045de93 will be re-run
  and re-frozen after the round lands.

## 2026-08-21 (cont. 5) — m2fix re-review back; NEW-H1 fixed inline

- M2FIX RE-REVIEW (task-m2fix-review.md): ALL FOUR findings CLOSED + the
  ledger extra, every reproduction message-for-message, suite arithmetic
  confirmed 6881->6883 by direct parent measurement. NEW-H1 (HIGH): the
  paint-inert guard's %a class could not see digit-suffixed properties —
  BackgroundColor3 painted the expander RED inside a green suite. Fixed
  INLINE by the controller (e79312c, one character class + the reviewer's
  exact mutation proven red naming the property) — inline because the fix
  was smaller than a dispatch and the re-review supplied the oracle.
  NEW-M1 (three fresh sites re-asserting A-M2's not-run procedure) reworded;
  NEW-M2 (dead hitRectOf arm) named as forward protection. Report-prose
  count slips: 9a5ea84's "69->70" is 68->69 and "grep -c supersed 0->5"
  measures 2/8 — corrected here, the report left as written. LOWs booked.
- Review records force-added (b00053a): the four review seats' files are now
  fresh-clone-readable alongside the reports.

## 2026-08-21 (cont. 6) — DIR4 fix round 1 landed + live check

- FIX ROUND 1 LANDED (f19b6cb + 1e76d5d; suite 6892 = 6883 + 9): MAJOR-1
  guard fires on the real failed-mount path (fabricated-handle harness and
  the raise export that fed it DELETED); R20 implemented — ButtonY gone from
  the chrome (TOGGLE_GAMEPAD deleted under R15, ADR-0040 B-14), case 16
  proves one Y = one menu against the REAL menu scenario; overscan moved to
  the Dock anchor's padding so all four edges inset at once — the fill
  offer was ~90px too wide before; warn pinned; N3 bottom-edge recorded as
  an explicit null (top-anchored bar, unobservable). Scoped re-review
  dispatched (task-dir4-fix1-rereview).
- LIVE CHECK (stamp 8bbb1c49-6912872, console row): chips (102,72), right
  edge 1818 = 1920-102 — symmetric, both edges inside the band (was 1908);
  boot print now says "Backquote on a keyboard, ButtonL1/ButtonR1 on a pad".

## 2026-08-21 (cont. 7) — fix-round re-review: ALL ADDRESSED; loop closed

- RE-REVIEW (task-dir4-fix1-rereview.md): ALL FINDINGS ADDRESSED. Both
  MAJORs verified at the measurement level (guard 10400->10400 on the real
  failed mount with both contract directions pinned; §5's history
  reconstructed on the head tree — double-fire, then deletion; overflow
  delta exactly 90; near rows byte-identical in a 68-node x 4-viewport
  dump; suite 6883->6892 = exactly 9 added lines). Its three MINORs fixed
  INLINE by the controller: the blank line that severed ADR-0040's B-14
  from its own table (the artifact R20's legality rests on — one
  character), the two stale key-count comments in showcase_chrome, and the
  hazard note's 20400-that-measures-20300. MINOR-3 correction FOR THE
  RECORD: the fix round's mutation ledger mis-attributes two rows — N2
  reddens case (4) (there is no (7)) and N5 as written reddens (15)'s
  success control + three (10)-family cases; the report stays as written,
  this entry is the correction. Nits (case-17 tablet row, "five MINORs"
  heading) noted, not chased.
- The DIR3/DIR4 arc is CLOSED: 48b6e7b -> review (3 MAJOR) -> 68f813e
  -> review (2 MAJOR) -> f19b6cb -> re-review ALL ADDRESSED.

## 2026-08-21 — CAMPAIGN CLOSED

- Final gate: PASS re-confirmed at the closing tree, byte-identical to the
  frozen gate.json (23 PASS, 2 FAIL_ENVIRONMENT device rows, non-blocking
  by design). Suites 6892 / 3449.
- Final report to the director committed:
  artifacts/release-candidate-review/final-report.md — twenty rulings +
  J-2 for veto, six open design calls, the device-half packet, the
  extraction charter, the Step 14 pointer. Publishing stays the director's
  manual click. Nothing pushed, published, or packaged.

## 2026-08-21 (post-close) — director's answers to the six open calls

- Q1 modal-tie: SHIP AS-IS, re-spacing rides the extraction charter (decided).
- Q2 native-style default: STYLE SHEETS BECOME THE DEFAULT — implementation
  round dispatched (Facet flip + RR lockstep per the constitution; ADR-0040
  row under R15; Facet_ForceStyleFallback keeps the explicit-write path
  testable).
- Q3 TV radii + Q4 metric 1.5x: fresh ladder-era console capture delivered
  (tools/studio/capture_viewport.sh — the durable-capture instrument; the
  first attempt was a full-screen grab that caught the director's own inbox
  and a doc draft, DISCARDED unsent — single-window capture is the only safe
  form). Q4 provisionally: 1.5 stays. Q3 awaits the director's eye.
- Q5 celebration-Space: CONFIRMED intended for racers. Future condition
  recorded in RR docs: in a real multiplayer match the skip should likely
  require EVERYONE to hit Space (or not exist) — a design note for the MP
  mission, not a change now.
- Q6 version: stays 0.10.0; publish boundary = Step 14's publish click
  (recorded in ADR-0040 under "Answered by the director").

## 2026-08-21 (post-close 2) — Q3 decided: radii scale in LOCKSTEP

- DIRECTOR DECISION (Q3, seen on the live A/B capture): TV corner rounding
  scales with the SAME factor as everything else, and stays derived from
  metricScale so a future scale tweak moves both together. This supersedes
  the RADII half of ruling R13; the doctrine survives intact — "a metric may
  only scale where the framework owns the paint" — because the implementation
  is exactly the sheet-GENERATION path the R13 pointer named
  (DENSITY_PAINT_SECTIONS in src/themes/snapshot.luau): the painted literal
  moves WITH the metric, so measure and paint keep agreeing. STROKES stay
  held at 1 (the director spoke to rounding only; the hairline half of §13f
  stays an open eye/device question).
- The A/B itself was produced by editing the LIVE theme sheet's Radii_*
  attributes in Play (12/8 -> 18/12, instant repaint, restored after) — proof
  the seam already exists and the lockstep change is sheet-derivation work,
  not new machinery. Captures committed (2be1490).
- SEQUENCING: the native-default flip round is mid-flight in adjacent files
  (theme docs, ADR-0040 appends). The radii-lockstep round DISPATCHES ON ITS
  LANDING, not before — two writers appending to one ADR table is the
  conflict class the B-14 blank-line find just demonstrated.

## 2026-08-21 (post-close 3) — hairlines join the lockstep

- DIRECTOR: strokes scale too. R13 is now FULLY superseded — the whole paint
  family (radii AND strokes) derives from metricScale through sheet
  generation, so hairline 1 -> 1.5 at ten-foot and both move automatically
  with any future scale tweak. The doctrine still holds: the painted literal
  moves WITH the metric, measure and paint agree. §13f is fully decided; the
  queued round's scope is radii + strokes together.

## 2026-08-21 (post-close 4) — DIR5: the expand feature, four ways, MEASURED first

- Director round 5 (live, hud demo): (1) the expand arrow should not exist
  for passive content — whole-pill tappable, arrow only when the host is
  itself actionable; (2) the opaque-popup bug is BACK (third report);
  (3) the "9" overflows the plate; (4) the in-panel X is rejected — wants
  the floating circular corner close (reference image); (5, mid-turn) LB/RB
  hints only when gamepad is the PRIMARY input, not merely connected.
- CONTROLLER FORENSICS BEFORE DISPATCH (the DIR4 lesson: verify the premise):
  phone row, hud demo, expand opened via coordinate click (instance-path
  click fails on flat-tree names with '/'). MEASURED: (2)'s root is the
  scrim CATCHER — /__scrim__/catcher full-viewport with GetStyled
  BackgroundTransparency = 0, OPAQUE, while roots/orders are CORRECT
  (12000/42050/42100) and PreferredTransparency=1; the 0.45 scrim token
  never reaches this catcher, and popup_catcher_paint.spec is green over it
  (check-that-proves-nothing, again, on the twin path its own comment
  names). (3) is two measured defects: ExpandPanel 135w with content
  spanning 159..294 vs right edge 286 (one missing inset), and the
  COLLAPSED "12"/"9" texts solving width 0 while visible (text bleeds;
  "2:14" solves 29 beside them). (5)'s mechanism: PreferredInput reads
  Gamepad with an idle pad plugged in (3 pads connected, primary class
  "pointer") — the DIR4 hint gate keys on the wrong fact. Also flagged:
  Facet_PaintProbe root at 20100 mounted during the hud demo — fixture or
  teardown leak, the round verifies.
- DIR5 implementer dispatched with the numbers; ADR-0040 row text comes back
  in its report (the controller appends — two writers on one table is the
  B-14 class). Native-flip round still in flight; radii+strokes lockstep
  round queued behind it; DIR5 told to keep clear of the flip's files.

## 2026-08-21 (post-close 5) — the flip landed; canary PASS; two seats + one round out

- NATIVE-DEFAULT FLIP LANDED (Facet c1120fc + 50887a8, RR 5dff3de; suites
  6905/3460, +13/+11 all its own): DEFAULT_ENABLED=true through a new pure
  resolveOpt seam (its headline: NOTHING pinned the old default — the flag
  had two source lines and no spec; now 8+ pins). Real defect exposed and
  fixed red-first: the edit-preview exemption existed only in a comment —
  the flip would have seeded a persistent FacetStyle sheet into the EDIT
  DataModel on place save. RR: tri-state nativeStyleOpt() preserves
  UseFacetNativeStyle=false as the rollback (the ==true collapse would have
  silently deleted it) — controller RATIFIES as R21 (mirrors the Sponsor
  cutover precedent; reverting is one function + four sites). Cost of the
  flip in the near-cap file: screen_target +108 chars, 686 from trigger,
  ledger row re-recorded. Follow-up BOOKED: the perf lab measures the
  NON-default path now — re-baseline owed (t16).
- LIVE CANARY PASS (stamp 4c64d676-6918299, desktop row, zero attributes):
  3 StyleLinks, FacetStyle+FacetTheme sheets installed, sample plate
  GetStyled (0.16,0.18,0.23) differs from plain (0.64,...) — the sheet owns
  the paint by DEFAULT. Suspected regression ("Ed"/"Ed..." buttons) A/B'd
  against ForceStyleFallback: IDENTICAL on both paths — it is the
  compact-label demo exhibiting truncation, not a defect. RR Studio canary
  under the new default still owed (needs the RR place open — director's
  packet).
- Dispatched: the radii+strokes lockstep round (queued behind the flip, now
  live) and the flip's review seat. DIR5 still running.

## 2026-08-21 (post-close 6) — flip review back; fix round dispatched; overflow-guard mission queued

- FLIP REVIEW (task-native-default-review.md): APPROVE, 0 blocker / 1 MAJOR /
  2 MEDIUM / 6 LOW / 2 INFO; everything reproduced exactly (11 mutations, two
  positive controls; RR green against moving HEAD). MAJOR-1: the seam pin is
  a SOURCE GREP — the reviewer's bypass calls resolveOpt, discards the
  answer, re-derives the pre-flip rule, and the full suite stays 6905 green
  while the default reverts (only 2 cases redden on flip-back, both on the
  pure function). MEDIUM-1: the RR sweep gate accepts nativeStyleOn( and a
  fifth adapter site can silently delete the rollback with RR green.
  ALSO: the edit-preview defect is WORSE than reported — ensure seeds to
  ReplicatedStorage in Edit by design and dispose never looks there. Fix
  round resumed on the flip implementer (paintPlan extraction per the
  reviewer — also buys chars back in near-cap screen_target; RR gate
  nativeStyleOpt%( + nativeStyleOn removal).
- DIRECTOR (systemic ask): the test system must GUARANTEE no-overflow — the
  "9" class. Assessment delivered: it escaped because (a) sweeps never open
  stateful surfaces, (b) the oracle asks off-viewport not out-of-parent,
  (c) nothing forbids zero-size visible text. Mission queued behind DIR5
  (file overlap): LAYER 1 harness-level containment invariant on-by-default
  in every fixture world (visible node within nearest clipping ancestor;
  non-empty visible text never zero-box; explicit waiver registry via
  triage_overflow_waivers), LAYER 2 solver diagnostics treated red in dev
  builds, LAYER 3 sweep state-walk (demos declare openable states; the L3
  expand step). Proof bar: the new rule must redden on TODAY's hud "9"
  state before DIR5's fix.

## 2026-08-21 (post-close 7) — DIR5 landed + verified live; design round; solver charter upgraded

- DIR5 LANDED (27af00f; 6915/3463) and LIVE-VERIFIED by the controller
  (stamp b0f35391): zero carets on passive zones (the pill IS the target),
  catcher GetStyled 0.45 (was 0 — three-times-reported bug dead at the
  paint level), plate contains content (300 <= 336), 36x36 corner disc
  straddling, base screen alive behind the scrim. B-16 appended
  contiguously (41aca37); the RR fence committed in the RR repo by the
  controller (e6e1c56 — the round resolved the game repo root wrong;
  games/RascalRally/code is the repo, docs/ is outside it). DIR5 review
  seat dispatched. Its forensics correction absorbed: my "visible
  zero-width text" probe read OWN Visible on a hidden variant subtree —
  ancestor-chain visibility is the only honest read (baked into the
  overflow-guard brief).
- DIRECTOR (solver question): why didn't the solver ensure containment?
  Answer given: the solver did what it was told — the control composed its
  own hug arithmetic and forgot an inset; the solver has no
  parents-contain-children invariant because authored fixed-size parents
  legitimately under-size (the declared overflow routes exist for that).
  CHARTER UPGRADED: the solver extraction stops being a someday-rider —
  its first deliverable is containment-by-construction (hug = content +
  insets composed in ONE seam, the exact line DIR5 contested at ~1113) +
  settle-time containment enforcement with declared routes. The
  overflow-guard mission (harness invariant + sweep state-walk) dispatched
  NOW as the immediate net; calibration bar = red on 27af00f's parent.
- DIRECTOR (two design notes on the verified plate): upper-left vs
  upper-right close, and "not a fan of how much negative space it added —
  control feels unbalanced. come up with a better visual design." UI
  DESIGNER dispatched (per the studio constitution — spec before build):
  2-3 options with PIL-rendered mockups, token-derived metrics, the
  left-vs-right question answered inside the options with platform
  reasoning. Build waits for the director's pick.

## 2026-08-21 (post-close 8) — solver split ACTIVE; close position settled

- DIRECTOR: "do the split as part of this work" + "upper right is ok then."
- SOLVER MISSION DISPATCHED (task-solver-split): Phase A = the ledger's own
  prescription (layout/measure_facts.luau, ~6 KB one-way — SHRINK_DEPS
  already threads the argument list), house seam method (READ==DECLARED==
  PASSED mechanised spec, zero re-verdicts, measure LAST), honest ledger
  re-record. Phase B in the freed room: hug-includes-insets composed in ONE
  seam (closes DIR5's contested band at ~1113 beside expandGutter) + the
  settle-time containment diagnostic through the existing channel
  (the-solver-already-told-you made literal); the R18 hit-floor reserve if
  headroom allows. Hard rule: the file ends with MORE headroom than it
  started.
- Design round told upper-right is settled; options now differ on BALANCE
  only.
- LEDGER COLLISION TO RESOLVE AT LANDING: the cap ledger's screen_target row
  (re-recorded by the paint-lockstep round mid-flight) calls that round's
  ADR row "B-16" — but B-16 is DIR5's appended row. The lockstep round's
  row must land as B-17; renumber at append time.

## 2026-08-21 (post-close 9) — plate design decided: OPTION B

- Director picked B (corner disc on symmetric padding, upper-right settled).
  Build round dispatched on the designer's spec (task-plate-design-spec.md,
  every metric a token derivation): uniform space.m padding, disc centered
  on the corner via space.xs + disc/2, incursion proven padding-only with
  the m*sqrt(2) > disc/2 argument kept as a spec assertion, all DIR5
  behavior preserved. Told to treat solver as locked (the split round owns
  it) and keep clear of the hud scenario file (overflow-guard may declare
  states there). Live verify mine at landing.

## 2026-08-21 (post-close 10) — DIR5 review: CHANGES REQUESTED, split two ways

- DIR5 REVIEW (task-dir5-review.md): 0 critical / 2 HIGH / 4 MEDIUM / 6 LOW;
  every number reproduced; the load-bearing tree-vs-paint-order reasoning
  CONFIRMED. H1: the cover's full-width 44px floor + hit_lift steals a 12px
  band from NEIGHBOR buttons (26% of each, measured; 0 at the parent) and
  EXPAND 15 asserts the lift as desired so the suite cannot redden. H2: the
  hugging plate exceeds the viewport (panel 8..398 on 390; the close disc
  outside the safe area under 20px insets) — the clamp repositions, it
  cannot shrink. M: the scrim fix WORKS (live 0.45) but its mechanism story
  is contradicted by its own oracle and other scrim="none" catchers were
  left unswept; formCarriesMeaning misses UI.Box{active=true}; the
  GetLastInputType primacy fix flaps without the INPUT-100/101 deadzone.
- ROUTING (avoid a three-way collision in region_expand): H1 + H2 +
  formCarriesMeaning FOLDED INTO the plate-B build round (already in those
  files — the plate gains a bounded width, the floor clamps to its region,
  EXPAND 15 learns to redden on outside-region overlap); the input deadzone
  + scrim-class sweep resumed on the DIR5 implementer (roblox_env +
  catchers, files nobody else holds). B-16 amended by the controller
  ("UNDER every form WITHIN ITS OWN REGION" + correction note). The
  cover-on-device evidence row joins the director packet.

## 2026-08-21 (post-close 11) — paint-lockstep landed; ITS OWN CLASS found alive in the gallery

- PAINT-LOCKSTEP LANDED (c4d0591 + c6c6260, RR 4e271c3; 6926/3465, +11/+2;
  tree-behind clean export 6939): one derivation
  (snapshot.paintForDisplay) spent by both authorities; radii whole-pixel,
  strokes keep the fraction; the capsule SCALES (999→1499, clamp-identical
  to 1998px, swept) — no underivable threshold; metrics.tenFoot now wins on
  BOTH sides (closing a real measure-without-paint gap); near density
  byte-identical (sha256 over nine configurations); artifacts unchanged
  by construction. RR defect found+fixed: FacetSponsor built its own target
  — measured at three metres, painted at arm's length. Row appended as
  B-17 (its report said B-16 — the collision the ledger predicted).
- LIVE VERIFY CAUGHT THE SAME CLASS IN THE GALLERY: console row, Large —
  painted capsule GetStyled "0, 999" (not 1499) because
  examples/gallery/client/init.client.luau:38 constructs screen_target.new
  with NO displaySize while host.luau:153 passes it. The showcase paints
  unscaled at ten-foot; the round swept RR's consumers and not the
  framework's own bootstraps. Fix round resumed: gallery + a full
  constructor census with a closed-set spec (a new bare constructor goes
  red) + the B-16→B-17 reference correction in the cap ledger row.
- screen_target is EIGHT BYTES under its 194,000 trigger — the vocabulary
  extraction is owed by the NEXT round that opens the file (the lockstep
  round cut its own comments twice to land under). Live density-change
  repaint gap (Studio-only) recorded as a deliberate not-taken.

## 2026-08-21 (post-close 12) — flip fix round landed

- FLIP FIX LANDED (b52d220, RR 1509383; isolated 6949 +10; RR 3461 with the
  honest −4): MAJOR-1 answered by EXTRACTION — native_style.paintPlan is the
  whole decision, pure, engine facts as parameters, motion fact as a
  function (call-count pinned); the consumer pin is five SHAPE checks and
  the opt-read-count lock (plan.opt is resolved; the raw opt is
  unrecoverable). Reviewer's exact bypass now reds naming three pins;
  flip-back reds 4 (was 2); the fifth-site RR bypass reds. nativeStyleOn
  DELETED; sweep gate is a floor. BONUS: screen_target −278 chars (was 8
  from the trigger, now 286 below). Its LOW-5 note is a live cross-round
  lesson: its host.luau hunk got swept into the lockstep round's c4d0591 —
  content correct, but the exact accident commit_isolated exists to prevent,
  running the other way. Re-review seat dispatched. Two INFO policy notes
  booked to triage (showcase's hardcoded true; host.Opts boolean? typing).

## 2026-08-21 (post-close 13) — DIR5 fix round: the TRUE opaque mechanism

- DIR5 FIX LANDED (4110ba1 + bb3b801, RR 4fdb0e6; 6957/3464): the input
  primacy flap fixed BY THE HOUSE RECORD (INPUT-100/101 applied clause for
  clause — raw stream, presses deliberate, 0.25 stick deadzone, mouse
  movement is noise; check_input_authority correctly failed on the new
  subscriptions and the allowlist entry mirrors the consumer's).
  THE SCRIM MECHANISM RETRACTED, not restated: plain resolves to 1; the
  false story's "corroborating" property read was native-mode-permanent;
  the TRUE finding is the STYLING-APPLICATION WINDOW (~3 frames) where any
  full-viewport catcher paints its class default — measured live, artifact
  at artifacts/expand-plate/catcher-paint-window.md; the discriminator for
  any fourth director report is DURATION. The other two catcher paths stay
  plain deliberately (tap swallowers), oracle pins exactly-1. The
  create-window flash is real, unclosable from a role, booked to the
  extraction charter (adapter create path / presenter mount order).
  Cross-round lesson repeated: an early RR pairing showed 3 phantom reds
  from a MIS-PINNED pair (RR HEAD vs stale Facet archive) — rebuilt both
  sides; content-pinning exists to expose exactly this.
- Stale false-mechanism comment in region_expand forwarded to plate-B (its
  file). RR L2 correction: RR DOES have a repo (games/RascalRally/code) —
  the DIR5 main round's "no .git" claim was wrong and its fence commit was
  already landed by the controller (e6e1c56).

## 2026-08-21 (post-close 14) — census landed; the SECOND door found live

- LOCKSTEP FIX 1 LANDED (5a43992 + e74e5fe; 6950 +1): constructor census —
  six sites, five FIXED (gallery, perf lab, billboard, edit preview, RR
  last round) + host blessed; EXEMPT table exists and is EMPTY (the edit
  preview is NOT near-only: device_profiles ships a console profile);
  class-closing guard with the new-bare-file mutation (M14). Its honest
  correction: NO framework surface was exercised live at Large by the
  original round — only host, headlessly. B-16→B-17 references corrected.
- LIVE VERIFY 2 (stamp b62ac109, console, Large): the SHEET path is now
  derived ON GLASS — `.facet-surface-raised::UICorner` rule carries 0, 18.
  But the BESPOKE path still paints base: the segmented Indicator Bar
  capsules GetStyled "0, 999" (not 1499); default_style.luau:69 holds the
  base tokens. A second door: some style source reaches the bespoke painter
  without paintForDisplay (candidate: the studio-neutral boot hands
  default_style raw — theme_controller.styleFor may only engage when a
  package installs). Fix round 2 resumed on the implementer: find the
  actual reader, ENUMERATE THE DOORS the way the census enumerated
  constructors, red-first. Third live verify owed on its landing.

## 2026-08-21 (post-close 15) — the overflow guard SHIPS, calibrated on history

- OVERFLOW GUARD LANDED (19dc1cb + repair 3183740; committed tree 6982/0):
  Layer 1 = containment invariant ON BY DEFAULT in every fixture world
  (ancestor-chain visibility — the campaign's instrument lesson made
  structural; off is a REASON STRING; no-waiver-rot case runs LAST);
  Layer 3 = scenarios declare states(), the missing generic expand step
  exists, the sweep walks fresh-mounts per state, the Studio driver gains
  containment/zeroBoxes + mode="states". CALIBRATION (the director's own
  bar): at 27af00f^ the walk reds with the VERBATIM 8px "9" message at 4/9
  viewports AND found a SECOND unseen instance (Expand:Actions past the
  LEFT edge at narrow-landscape); HEAD clean; fresh mutation 4/9 red. The
  waiver registry ships EMPTY and that is a measurement (the corner disc
  was expected to need one and measured not to). Triage across 630 cells /
  49k nodes: one instrument fix (transparent Hit counted as paint), zero
  waivers. commit_isolated's -U1 hole hit FOR REAL (a neighbor require
  swept in, HEAD briefly unloadable — caught by running the COMMITTED
  tree; dry-run cannot see this class) and repaired without touching the
  other round's work.
- NEW PROBLEM IT SURFACED: RR 3462/2 red at Facet HEAD on an unmodified
  pair (facet_large_text_sweep NameTag, facet_large_text_results Ctas) —
  pre-existing, entered by some recent round unnoticed. Bisect-by-pair
  round dispatched (root-fix or honest re-verdict; in-flight files
  report-only).
- Owed mine: the Studio driver's containment mode live pass (next console
  session); world-vs-sweep scrollBarThickness divergence booked; RR
  harness does not share tests/lib/world — one-line follow-up is an RR
  decision, booked.

## 2026-08-21 (post-close 16) — the director answers: STEADY. Reconciliation.

- The opaque background was STEADY (director confirmed), which settles the
  two rounds' mechanism dispute: the pre-fix state was REAL and persistent
  (controller measured GetStyled = 0 seconds after open, PreferredTransparency
  = 1), the DIR5 role change removed it (controller measured 0.45 after),
  and the ~3-frame styling-application window is a SEPARATE minor item —
  NOT the explanation for what the director saw. The fix round's retraction
  over-corrected: its "plain resolves to 1" measurement is about a node a
  CLASS RULE reaches; the pre-fix catcher earned NO tag, no rule matched,
  and an unmatched Frame paints its instance default — BackgroundTransparency
  0, opaque, steadily. Both rounds held half the truth: DIR5's product fix
  was right, the fix round's window discovery is real but answers a
  different (minor) question. The create-window flash stays on the charter
  at LOW priority. If a fourth report ever comes, the written discriminator
  (duration + the artifact's probes) applies.

## 2026-08-21 (post-close 17) — THE SOLVER SPLIT LANDED

- SOLVER SPLIT + CONTAINMENT LANDED (f0fc77e + 435dade + report c874840;
  6937 +22 ZERO removals; RR identical verdicts): solver.luau 197,810 →
  188,050 — 11,950 headroom, OUT of the warning band; measure_facts.luau
  took the ledger's exact prescription (first seam in the document costing
  neither a record nor an accessor; two honest analysis corrections
  recorded). Phase B.1: DIR5's contested band closed by DECLARATION —
  src/layout/expand_plate.luau owns insets + straddle, three consumers one
  source (red at the predicted 380-vs-358, green at HEAD). Phase B.2: the
  containment diagnostic's scope was MEASURED, not chosen — the broad rule
  fired 21,916 times on a green library; shipped = stack cross-axis (41,
  all fuzz). The 800-tree differential oracle byte-identical, diagnostics
  strictly additive. Two proves-nothing checks found and fixed en route,
  one exposing a dead export (PLAN_KEYED). 20 mutations bite.
- ROUTED: plate-B told to build against expand_plate.luau and rebase (the
  band under it changed); the 312-hit composition-region-below-box class
  (concern 2, counted not shipped) resumed on the overflow-guard
  implementer for triage; the R18 hit-floor reserve stays booked (its own
  fixture round). Review seat dispatched (the most load-bearing diff of
  the day: behavior-identity is the whole question).

## 2026-08-21 (post-close 18) — DOOR 2 CLOSED; third verify EXACT

- LOCKSTEP FIX 2 LANDED (41e6829 + reports; RR cae4c7a; 6986 +4, RR
  3465/0): the second door was AUTHOR-time freezing — styling.normalize*
  resolved tokens where they were WRITTEN (control factories, no style, no
  class), so radii.pill=999 froze into blueprints before any target
  existed. Fix: token NAMES travel to paint (the gap="m" idiom); pure
  paintCorners/paintStroke resolvers re-derive against the target's style;
  an absent stroke thickness is a token too. Door census: TWO doors, both
  derive, four default_style readers each with a written reason, a fifth
  goes red. RR was in the same trap (Ticker/StartCountdown corner tokens)
  and is carried; Marks' computed literal pinned as must-not-move. New
  at-Large-by-a-test evidence: the real Picker mounted at 1920 Large
  asserts authored 999 both distances, painted 1499/999.
- THIRD LIVE VERIFY: EXACT oracle match (stamp 2116ce45) — capsules
  0,1499; sheet rule 0,18; Large. Both doors derive ON GLASS. The
  director's TV-paint decision is fully live; capture committed
  (afa2882) and sent. NOTE: this round reports RR 3465/0 — the
  large-text bisect round may find its two reds already healed by this
  commit; let its report settle the truth.

## 2026-08-21 (post-close 19) — PLATE B ON GLASS; the last lock opens

- PLATE-B LANDED (099e28f; committed tree 7000/0, RR 3464/0 pinned): Option
  B built INTO expand_plate.luau (correctly rebased onto the solver round's
  module); discHalf resolves the one number the metric vocabulary cannot
  spell (a half); R18 is an INEQUALITY with a CIRCLE fence (a box sweep
  would stay green on a disc that covered a word); H2 fixed (plate carries
  its own cap — panel 8..366 at every content width); H1 REFUTED as
  mechanism (hit_lift never fires for a cover — rank already wins) and
  RELOCATED: the real fix is a class-keyed clamp in renderer pushHitRects,
  LOCKED, so EXPAND 15 stops ratifying and asserts a bound. M3 fixed
  (formCarriesMeaning reads active).
- LIVE VERIFY: disc center (328,114) == panel corner EXACTLY; padding
  16/16 symmetric; disc in viewport; scrim 0.45. Capture committed
  (aa46cda) and sent. The director's balance complaint is answered in
  numbers.
- GATE REPAIR by controller: check_comment_codes was red on 4 new codes
  from two rounds — made resolvable, then the RATCHET fired (32 > 25);
  seven codes displaced into plain prose (the definitions stood alone);
  PASS at exactly 25/25, 0 orphans (4553a22, follow-ups).
- RENDERER SPLIT DISPATCHED — the last locked file (1,018 chars from the
  cap, the closest in the repo), the ledger's rect_pass prescription, with
  the H1 tap-theft clamp as its Phase B (960+828 px² red probe). Plate-B
  review seat next.

## 2026-08-21 (post-close 20) — the RR reds RETRACTED; mkpair lands; flip round 2

- RR BISECT VERDICT: the two "large-text reds" were FABRICATED by a
  mis-pinned pair — the overflow-guard round's Facet sha was HEAD at its
  START (4f86ac5), one commit BEFORE the input-primacy fix its RR side
  requires; the tripwire fired exactly as designed. The accused specs NEVER
  failed (green at 20 Facet pins; both current pairs 7000/0 and 3465/0).
  Erratum inserted in the overflow-guard report (d0e554e). The instrument
  lessons, kept: a difference measurement cannot see a common-mode defect
  (both arms carried the same stale framework — pin the ABSOLUTE, not the
  delta); a matching failure COUNT is not identification — read the ✗
  lines.
- MKPAIR LANDED (tools/mkpair.sh, selftested): both repos archived at refs
  resolved AT CALL TIME, resolved pins written INTO the pair as artifacts
  (PIN_FACET/PIN_RR). Third bite of the day was the last.
- FLIP RE-REVIEW: APPROVE with findings — the substitution class survives
  one level down (a value substituted into the seam's own argument stays
  green at the identical count; the RR floor binds the reader's NAME not
  the tri-state). Fix round 2 resumed with the reviewer's own endgame:
  paintPlan takes the opts TABLE + .nativeStyle read-count ZERO in the
  target — nothing left to substitute; the RR sweep refuses tri-state
  collapse and derives its site list. Report overclaims to be corrected.

## 2026-08-21 (post-close 21) — solver-split review: the behavior held

- SOLVER-SPLIT REVIEW (task-solver-split-review.md): PASS WITH FINDINGS —
  the behavior claim proved INDEPENDENTLY (their own 800-tree oracle
  byte-identical across Phase A, 0-removed/125-added all-containment across
  Phase B; the move textually identical; all 19 mutations bite; the 312
  census reproduced on the nose; hot-path cost measured inside the noise).
  2H/2M/2L, all record integrity: HIGH-1 the round CERTIFIED
  check_comment_codes PASS while it was red at its own commits (asserted,
  not run — the split stripped the EXTRACTION_LOCKED exemption from the
  moved codes; the controller's sweep later made the tree green without
  knowing it was paying that debt); HIGH-2 the re-recorded ledger row
  carries an ALREADY-FIRED trigger (188,000 beside a measured 188,050 —
  the presenter row's capital-letters failure, repeated, and 099e28f
  already slipped 420 chars through it). Fix round resumed: report
  corrections, honest trigger, ADR B-18 text, expand_plate header's two
  nonexistent symbols, AND the maturing debt measured — dropping
  solver.luau from the checker's exemption tuple now that its extraction
  happened (the "owed to that extraction" codes come due).

## 2026-08-21 (post-close 22) — the 312 verdict: one event, 312 hats

- 312 TRIAGE (e7e2268; 7002/0, RR 3465/0): DELIBERATE. All 312 carry
  fallback=true — "a region left the box" and "the composition fell back"
  are the SAME EVENT, which the framework already files once per solve as
  its single designed=true finding. Structurally proven both ways: a legal
  composition cannot produce one (the 20px legality boundary measured:
  lead 400 legal/everything inside; 420 rejected/fallback outside); no
  horizontal instance possible (the slot is clamped); where it fires,
  nothing escapes PAINT (worst cell: 0 collisions, 0 off-screen, guard 0).
  Shipped as a RULE with its measurement, not a waiver ("a waiver hides a
  class where a rule explains it") + two pinning cases either side of the
  boundary + 3 mutations. Root pressure is the hud fixture's own
  documented under-8px headroom cell; no fixture change taken — it would
  change what the demo demonstrates. Its earlier §6 RR-reds note corrected
  in-file (the bisect's mis-pin verdict stands as the mechanism; the reds
  do not exist at proper pins).

## 2026-08-21 (post-close 23) — solver record fix; the class reborn next door

- SOLVER FIX ROUND LANDED (b5732d0 + 3fee51c; 7005/0, RR identical; pins
  via mkpair, both refs at measurement time): HIGH-1 corrected unhedged
  (asserted-not-run owned); THE TUPLE DEBT PAID — solver.luau dropped from
  the checker's exemption, 12 sites swept to prose (10 orphans + 2 that
  would breach the ratchet), 0 orphans / 25 of 25 / four locked modules
  holding 171; the ledger head gained the rule the next split needs.
  HIGH-2 rewritten as a STATE (ARRIVED, flowPartition+flowPlan named,
  this round's +385 recorded as the last free pass). B-18 appended by the
  controller. MEDIUM-B was already fixed by plate-B — coordinated, and the
  header now names the three REAL fields so the drift class is closed.
- THE CLASS REBORN WITHIN THE HOUR: the renderer round's own extraction
  (4cc5cb0, mid-flight) moved ADAPT-7/RS-A16/NS-A2 into unlocked
  commit_walks.luau — check_comment_codes FAIL at HEAD, exactly the
  pattern the ledger-head rule now names. Messaged the round directly so
  it sweeps before closing, runs every guard it certifies, and labels its
  ADR row B-19.

## 2026-08-21 (post-close 24) — the flip guard reaches its dead end

- FLIP FIX 2 LANDED (c3eec58 + 9a88feb, RR c3c8d49; 7022/3466 at
  measurement-time pins): MAJOR-A closed by the PRESCRIBED endgame —
  paintPlan takes the whole opts table, the consumer pin is a count of
  ZERO over the word (two structural exclusions, which is what catches
  bracket spellings), the argument itself pinned. Both surviving
  mutations now redden with messages QUOTING the attempted substitution;
  the original bypass still red. MEDIUM-A closed as a class: the sweep's
  contract is the VALUE EXPRESSION (unmapped pass-through; a variable
  deliberately refused), the hardcoded SITES list replaced by the sweep
  feeding both cases; the collapsing fifth site reds, the correct fifth
  site is admitted. LOW-E fixed rather than named (short-circuit
  restored). Both report overclaims retracted INLINE in the sentences
  that made them. Sonnet re-review seat dispatched with one instruction
  beyond reproduction: design a FRESH bypass of its own.
- Housekeeping: two review seats' staged records committed (55fdfb0);
  check_theme_artifacts red on the WORKING tree only (the renderer
  round's mid-edit state) — green on clean exports all day; full battery
  re-runs on the committed tree at the renderer landing.

## 2026-08-21 (post-close 25) — R22: the loop ends by ruling, not by round 4

- FLIP FIX-2 RE-REVIEW (05aeeea): M7/M3/original all redden as claimed;
  MEDIUM-A closed (collapsing site reds, honest site admitted); overclaims
  genuinely retracted inline. BUT the reviewer's OWN fresh bypass survived
  — opts reassigned to a fabricated table via a runtime-CONCATENATED field
  name, six pins satisfied, 7022 green. Third occurrence of the class.
- RULING R22: the class is PROVEN un-closable at the source level in a
  dynamic language — the loop terminates by threat-model statement, not a
  fourth round. The pins' job is accidental reversion + careless refactor
  (they now catch every natural spelling); deliberate obfuscation is
  outside the file's job in an unpublished single-team repo; the
  BEHAVIORAL terminator is the boot canary (already run live: bare boot →
  3 StyleLinks + sheet-resolved paint), booked to t16 as a standing
  scripted canary row. Threat model written INTO the spec header. Cost if
  wrong: an in-repo saboteur — who owns commit rights anyway.
- Re-review's LOW absorbed: the "+81 belongs to another round" attribution
  was wrong — true ancestry +7 another round's, +74 this round's own
  comment (the −30 was the code line alone). Recorded here; the ledger
  cell's chronology stands corrected by this entry.

## 2026-08-21 (post-close 26) — THE LAST LOCK OPENS; two closing seats out

- RENDERER SPLIT LANDED (4cc5cb0/935f9a2/5c407cc/2e6c7d9/753e088; 7036/0,
  RR 3466/0): renderer.luau 198,974 → 182,522 — 17,478 headroom, out of
  the band; commit_walks.luau took the six write loops; the ledger's own
  prescription was one day stale (rect_pass had already left) and the
  round said so. THE BRIEF REFUSED ON MEASUREMENT: my prescribed hard
  clamp would have cost three shipped HUD covers their F1 floor
  (overflow_sweep's dead-end guard caught it on five viewports); shipped
  = B-19, the floor GROWS one side at a time and stops at the first
  pressable rect — ringScreen theft retracted (960/828 → 0), HUD covers
  keep 44, the boxed-in region keeps 42-of-44 instead of 0. Four of eight
  Phase-B mutations were green FIRST, one exposing a real arithmetic
  defect (a blocker above zeroing downward growth) — fixed, kept as B-M7.
  It also paid BOTH exemption debts the day created (comment codes 41 →
  prose with renderer out of the tuple; check_brand_drift red THREE DAYS
  on the solver split's move — the same lock's second list, which the
  ledger names once; a checker that enumerates its own lock lists is the
  follow-up). One commit left HEAD red (missed hunk, own instrument
  caught it, repaired next commit — the -U1 class again). B-19 appended
  (as a table row; the report offered blockquote form). The R18 hit-floor
  reserve on the solver row is now SUFFICIENT, not just nice.
- Dispatched: the renderer review seat (behavior identity + the
  brief-refusal reproduction) and the plate-B review seat (the last
  unreviewed round). When both return: the consolidated day wrap for the
  director.

## 2026-08-21 (post-close 27) — plate-B review: the shared helper's other consumer

- PLATE-B REVIEW (195c5f9): REQUEST CHANGES — 1H/4M/6L; every headline
  claim reproduced (geometry to the pixel both rungs, H2's exact red,
  all 8 mutations, arithmetic from archives). THE HIGH: closeAffordance()
  serves panelOf AND sheetOf — the plate-correct margin moved the SHEET's
  disc 4/6px into its reservation, COVERED=true on a filling form where
  the parent was exactly TANGENT — the precise violation the new circle
  fence exists to catch, on the one presentation the fence doesn't sweep.
  Their concern-2 upgraded: the 9×9 ten-foot hit-floor incursion lands on
  CONTENT (81 px² of an interactive corner control) and the renderer's
  new clamp is cover-scoped so it doesn't reach the close. Concern-5
  sharpened: inset 3 vs a 4px ten-foot ring on two packages, and the
  snapshot returns nil for the ring authority. Fix round resumed: the
  one-line sheet fix + the fence learns the sheet, the close joins the
  grow-until-pressable class (commit_walks is unlocked now), the ring
  inequality against the real authority.

## 2026-08-21 (post-close 28) — R23: the floor stops for the author, not for itself

- RENDERER REVIEW (cff4bb8): ACCEPT WITH FIXES — behavior identity and the
  brief-refusal reproduced independently (the hard clamp costs all three
  shipped covers their floor, reddening overflow_sweep on exactly the five
  named viewports). MAJOR-1: at matrix scale the grow rule over-applies —
  42/382 route boxes under the floor (min 25px), 32 covers retracted, and
  55 of 110 cuts are framework-vs-framework — a question R18 never ruled
  and hit_lift's own doctrine answers the other way.
- RULING R23: the floor stops ONLY at author-interactive rects (the theft
  class); framework affordances overlap each other and arbitrate by the
  existing z/hit_lift order, per that doctrine's own words. Fix round
  resumed with the review's matrix instrument as the oracle and the blast
  radius PINNED at matrix scale (never again asserted on one fixture).
  Also: ADR-0041's 8 dangling citations get a real file or a re-point;
  "three days" corrected to the measured 3h10m; B-19's blast-radius
  sentence to be re-edited from the corrected text. Coordination noted:
  two rounds now share commit_walks.luau (plate-B extending the rule to
  the close class) — marker-tight hunks, re-read before edit, never
  revert the unfamiliar.

## 2026-08-21 (post-close 29) — the director's purity question becomes an audit

- DIRECTOR (architecture): worried a fix implied showcase code was
  calculating its own width — "showcase code should not be doing layout
  solving... conceptually akin to SwiftUI... anything we need to cleanup
  to use the framework right (or that needs to move to the framework)?"
  CLARIFIED: the overspill bug was FRAMEWORK code (region_expand's own
  hug), not showcase — now by-construction in the solver. But the
  question stands on the record's own evidence: fixture pixel literals
  fixed piecemeal all campaign (336 window, vlistGap 8, ROW_HEIGHT),
  hand-computed lanes (ADAPT-L2 residue), the hud fixture's zone
  bookkeeping and reach epoch, estimatedItemExtent-as-number.
- DECLARATIVE-PURITY AUDIT DISPATCHED (read-only, classification only):
  every consumer-side layout-ish site in examples/** + RR's Facet
  consumers → DELETE (framework answers; cite the seam) / MOVE (real
  capability gap; name the home) / DECLARATIVE-OK / PROBE-EXEMPT, with
  the §"what the framework teaches wrong" section for APIs that make the
  imperative path easier than the declarative one (design findings). The
  director sees the matrix before anything changes.

## 2026-08-21 (post-close 30) — the sheet is tangent again; a hold done right

- PLATE-B FIX ROUND LANDED (fcc0f7f + f54281b; 7037/0, RR 3466/0 identical
  at measurement-time pins): the sheet disc back to EXACT tangency
  (14→18 / 21→27 measured with the reviewer's instrument); the real
  defect — the fence's blind spot — closed with one r18Sweep over BOTH
  presentations, the sheet arm asserting TANGENCY not clearance (a >=
  would have stayed green on the 4px incursion). `active` handles every
  reactive spelling; the circle-vs-box argument kept only its true half;
  the ring-room ratchet asserted BOTH directions against style.extra (the
  binding package headroom 0.63px/0.31px — geometry unchanged because
  raising the inset would move the director-settled corner).
- THE HOLD: the 9×9 fix (widen growWithin to the whole synthesized-chrome
  class, close included) is BUILT, GREEN, MUTATION-TESTED, and NOT LANDED
  — applying it entangled the renderer round's uncommitted R23 rename in
  the same hunks (proven with git diff, reverted byte-for-byte, md5
  matched). Replay script at scratchpad/fix1_B.py anchored on parts
  neither round moves. **EXPLICIT HANDOFF: when the renderer R23 round
  lands, resume the plate agent to replay and land the held fix — the
  9×9 is live until then, deliberately.**

## 2026-08-21 (post-close 31) — the hold rehearses against its blocker

- The plate agent used a stale-poll wake to REHEARSE the held 9×9 fix
  against a private export carrying the R23 round's in-flight files:
  every anchor survives their rewrite (the rename lives BETWEEN its two
  touch points), red-first holds under R23 (1 failed/77 → 78), and the
  two rules compose the right way round — R23 narrows which RECTS stop a
  floor (author-declared only), the held fix widens which HOSTS are
  stopped (the whole synthesized-chrome class); the author Button keeps
  blocking the close's floor, the close stops blocking other framework
  floors. Replay is two scripted steps; a bounded watch will fire on the
  file's release. c6f313f (report only).

## 2026-08-21 (post-close 32) — the purity verdict: not imperative, UN-NAMED

- PURITY AUDIT RETURNED (2c5451e; 165 files/~70k lines + 43 RR clients):
  the director's strict fear is UNFOUNDED — 5 imperative geometry writes
  in the whole corpus. The real disease: spending un-named numbers (539
  raw literals on theme-owned props — 40% of the TEACHING corpus vs 22%
  in the shipping game, the inverse of reference material) and
  re-deriving a missing layer of nouns (97 sites → 34 capability gaps;
  the metric-ladder app-namespace gap rediscovered FOUR times
  independently; RR holds four hand-rolled text-fit copies, THREE WRONG;
  gap=6 wanted 61 times across 25 files while the framework routes
  around its own missing step privately). ROOT CAUSE IS ONE LINE:
  check_theme_drift deliberately exempts examples/ — right for a game,
  wrong for teaching. 7 live defects found by a style audit (incl.
  reduced-motion ignored by the wardrobe turntable; RR Ticker/FollowScreen
  overlap at large text).
- PHASE 1 DISPATCHED (mechanical only): flip the lint (examples covered,
  probe-list + games exempt), sweep the 539 + floors + minColumnWidth +
  deprecated sites, fix the 7 defects red-first, mark the 13 mistakable
  probes. The 34 MOVE gaps + gap-6 are the DIRECTOR'S pick list —
  presented with the matrix; phase 2 waits on his word.

## 2026-08-21 (post-close 33) — the held fix lands on the commit it waited for

- PLATE-B FULLY CLOSED (cec8453 + 8b51929 on top of the renderer round's
  16f5434; 7040/0, RR 3466/0 identical): the replay applied with ZERO
  edits, exactly as the rehearsal predicted. The close declares
  role="close"; commit_walks' predicate is the whole synthesized-chrome
  class (cover|close — the chevron stays out: it owns its column). The
  TV-corner overlap: 81 px² → 9 px², and the residue is the DISC'S OWN
  BOUNDING BOX (a hit rect is a rectangle, the disc is a circle) — the
  case asserts that honest rule; paint stays with the circle fence. Both
  new mutations land on this case and no other. THE PROCESS LESSON,
  evidenced end to end: the hold was proven necessary (md5), the wait was
  made cheap by rehearsing against the blocker's in-flight state, and
  landing was two scripts + zero reconstruction.
- Renderer R23 landed as 16f5434 (its report notification pending);
  purity sweep phase 1 running. Remaining after those: final live
  verification pass + the consolidated day wrap.

## 2026-08-21 (post-close 34) — R23 report in; the last guard red repaired

- RENDERER FIX ROUND REPORT (16f5434; 7039/0 its own, 7040/0 at HEAD with
  the plate landing composed cleanly on top): R23 implemented at the
  CENSUS (inputSinks records who declared each sinker; hit_lift keeps
  every key, the floor walk reads the value — one census, no second
  table). Matrix after: 381 routes, 38 sub-floor ALL author-cut, 0
  framework-attributable, smallest 35px (was 25), DIR5 stays 0 px².
  The blast-radius pin derives attribution INDEPENDENTLY of the rule it
  audits and reddens in both directions. ADR-0041 written (8 citations
  resolve); B-19 corrected in place by the round itself; "three days" →
  the measured 3h10m. Its routed note strengthens the booked solver
  reserve: with it, R23 stops firing on shipped screens entirely.
- check_theme_artifacts repaired by the controller (its COPIED_FILES
  tuple gains the two files every fixture world now requires since the
  containment invariant became default-on). All guards green at HEAD.
- Remaining: the purity sweep (running), then the final live pass + gate
  re-run + the consolidated wrap.

## 2026-08-22 (early) — the sweep lands; the last seat goes out

- PURITY SWEEP LANDED (five Facet commits → b3f9c89 + RR ca50fdb; 7057/0,
  3469/0 at measurement-time pins): the lint flip is a STANDING GUARD
  (red-first 365/0-framework against the pre-sweep tree; example scope
  fires only on exact token equality so every fix is pixel-identical;
  gap=6 stays a PENDING finding that reddens 60 sites the day the scale
  grows the rung). 353 literals swept / 11 measured opt-outs / 147
  unreachable (no name resolves — phase-2 fodder). TWO AUDIT CLAIMS
  REFUTED BY MEASUREMENT and recorded (7 minColumnWidth are a packing
  floor — "intrinsic" collapsed a fill column, 70 findings; two
  "non-reactive" reads are per-frame by design, null result pinned).
  6 defects fixed red-first (wardrobe reduced-motion, RR ticker 22px
  inside, 31→0 imperative transforms, autoscroll band). Two sweeps
  WOULD HAVE SHIPPED BUGS caught only by reading the diff (role name
  across the FOREIGN seam = runtime type error; a METRICS table that is
  arithmetic). Hit floors NAMED not deleted (the framework enforces the
  hit floor, not the visual one). Corpus raw share 39.4% → 12.6%, now
  BETTER than the game's 22% — the teaching inversion is fixed.
- Controller: the d3a-help + picker gate rows re-pointed to
  check_theme_drift_cli (the exitless form was a proves-nothing call);
  pins pass; the navigation-and-menus gate re-running as proof. The
  sweep review seat dispatched — the final seat. Then: full RC gate
  re-run, the wrap, memory.
