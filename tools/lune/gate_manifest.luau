--!strict
-- Per-phase gate check manifest for tools/lune/gate.luau (design §16.4, §17).
-- Each check: name, requirements touched, and either
--   run  = shell command (relative to the library root; exit 0 => PASS), or
--   state = a literal current state for work that has not landed yet
--           ("PENDING") or that is externally blocked ("FAIL_ENVIRONMENT").
-- releaseBlocking marks FAIL_ENVIRONMENT checks that MUST clear before release
-- (a non-blocking one may remain pending at phase pass, per the design).
-- evidence: artifact path a passing run must produce (existence is verified).
-- KEEP HONEST: a check lands here as `run` only when its implementation exists;
-- everything else stays PENDING so the gate cannot silently pass.
--
-- ============================================================================
-- GREPPING THE SUITE: ANCHOR TO THE PASS MARKER, ALWAYS.
-- (gate-integrity sweep 2026-07-29, defect D-1 — enforced by
--  tools/check_manifest_integrity.py, which is a check in the terminal gate.)
--
-- tests/lib/testkit.luau prints the case name on BOTH outcomes:
--     ✓ modal traps navigation with wrap and restores previous focus on pop
--     ✗ modal traps navigation with wrap and restores previous focus on pop
-- so `grep -q "<case name>"` proves the case is REGISTERED, never that it PASSES.
--
-- Whether that is merely sloppy or actually blind depends on shell form:
--
--   FORM A   out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*X"
--            SAFE — the assignment carries run-tests.sh's exit code, so `&&`
--            short-circuits and the check reddens on any suite failure.
--
--   FORM B   ./run-tests.sh 2>&1 | grep -q '✓.*X'
--            A PIPELINE'S EXIT STATUS IS GREP'S. Without the marker the suite's
--            failure is MASKED: 26 checks shipped that way, and phase-0's
--            modal-focus-spike was proven green against a deliberately broken
--            focus graph.
--
-- Anchoring also catches a second mistake: grepping a describe-BLOCK header
-- instead of a case name. Headers print with no marker, so those checks could
-- never fail — one of them greped the bare word `examples`.
--
-- Prefer FORM A. Either way, every suite grep must carry `✓.*`.
-- ============================================================================

export type Check = {
	name: string,
	requirements: { string },
	run: string?,
	state: string?,
	evidence: string?,
	releaseBlocking: boolean?,
	note: string?,
}

local manifest: { [string]: { Check } } = {
	["api-architecture-consistency"] = {
		-- Roadmap Step 7 (docs/plans/api-architecture-consistency.md): the API
		-- constitution + whole-surface consistency audit. Registered BEFORE any
		-- edits with honest PENDING checks per the plan's "Evidence and gate";
		-- each flips to `run` only when its work and evidence actually exist.
		-- The stage rule is COMPATIBLE fixes only (ADR-0011 for migrations), so
		-- several checks are before/after comparisons against a frozen baseline.
		{
			name = "baseline-freeze",
			requirements = { "UI-AGENT-001" },
			run = 'b=artifacts/api-architecture-consistency/baseline && test -f "$b/public-surface-before.txt" && test -f "$b/test-before.json" && python3 -c "import json,sys; d=json.load(open(\'artifacts/api-architecture-consistency/baseline/test-before.json\')); sys.exit(0 if d[\'status\']==\'PASS\' and d[\'passed\']==2785 else 1)" && test -f "$b/prior-gates-before.txt" && grep -q "^DONE$" "$b/prior-gates-before.txt"',
			evidence = "artifacts/api-architecture-consistency/baseline/public-surface-before.txt",
			note = "stage-start freeze captured before any edit: the exported public surface + DEPRECATIONS dump (156 lines), the suite floor (2785 green), and the prior-gates roll-up — regenerated from a git worktree PINNED to the stage-start commit so concurrent implementation edits could not contaminate it (the first in-tree run was killed for exactly that reason)",
		},
		{
			name = "surface-ledger-complete",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_surface_ledger && test -f artifacts/api-architecture-consistency/ledger/core-state.md && test -f artifacts/api-architecture-consistency/ledger/blueprints.md && test -f artifacts/api-architecture-consistency/ledger/controls.md && test -f artifacts/api-architecture-consistency/ledger/services.md && test -f artifacts/api-architecture-consistency/ledger/seams.md && test -f artifacts/api-architecture-consistency/dispositions.md",
			evidence = "artifacts/api-architecture-consistency/surface-ledger.md",
			note = "check_surface_ledger proves MECHANICALLY that every top-level export and every nested namespace member of the LIVE surface (required fresh, never a stored dump) is classified in the master ledger, that the constitution exists and is linked from the guide index and all six playbooks, and that the ledger names the dispositions file — plus the five audit fragments and the disposition ruling exist. 0 CRITICAL / 46 MAJOR / ~120 MINOR findings, each with exactly one disposition",
		},
		{
			name = "constitution-published",
			requirements = { "UI-AGENT-001" },
			run = 'test -f docs/reference/constitution.md && grep -q "16. Exceptions" docs/reference/constitution.md && grep -q "constitution.md" docs/guide/README.md && grep -q "constitution.md" docs/guide/02-architecture.md && grep -q "constitution.md" docs/INVENTORY.md && grep -qi "kind ladder" docs/reference/constitution.md',
			evidence = "docs/reference/constitution.md",
			note = "one example-backed constitution: kind ladder, naming, constructors, specs/validation, reactive values, results, callbacks, ownership/lifecycle/errors, input/focus, adaptation, styling/property authority, engine adapters, extensions, versioning/docs, evidence, and the seventeen named exceptions (E-1..E-17) each with why uniformity would be worse. Per-playbook links are enforced by check_surface_ledger in the previous row; a plain-words distillation opens the guide README",
		},
		{
			name = "compatible-fixes-proven",
			requirements = { "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*re-bases while awaiting" && echo "$out" | grep -q "✓.*still returns the envelope and leaves the mutation usable" && echo "$out" | grep -q "✓.*does not latch the gap" && echo "$out" | grep -q "✓.*escapes a stuck pending request" && echo "$out" | grep -q "✓.*INFLATED backing layer keeps its drag declaration" && echo "$out" | grep -q "✓.*unknown spec key is refused, naming the modifier" && echo "$out" | grep -q "✓.*typo.d gradient field is refused" && echo "$out" | grep -q "✓.*cannot disable framework validation" && echo "$out" | grep -q "✓.*rejects a read-only Memo" && echo "$out" | grep -q "✓.*header title honours the column alignment" && echo "$out" | grep -q "✓.*table.freeze.d grouped scope" && echo "$out" | grep -q "✓.*ledger is the UNION of schema-generated and declared" && echo "$out" | grep -q "✓.*at least one MINOR of notice, and the ledger is frozen" && echo "$out" | grep -q "✓.*opts.scope owns the memo" && echo "$out" | grep -q "✓.*a critical fallback under rootPolicy" && echo "$out" | grep -q "✓.*an unknown responder names the opt" && echo "$out" | grep -q "✓.*semanticText is a Readable" && echo "$out" | grep -q "✓.*both forms answer identically for the same inputs" && echo "$out" | grep -q "✓.*a throwing formatter falls back to the default format" && echo "$out" | grep -q "✓.*refuses a non-empty opts table"',
			note = "twenty named red-first regressions, one per compatible-fix family (F-1..F-38 in dispositions.md), each anchored to the PASS marker (Form A — the assignment carries the suite exit code, so a failing suite reddens this check). The two ADR-0011 deprecations are pinned by the UNION-ledger and one-MINOR-of-notice cases; the deprecated surfaces keep working (their own specs still run)",
		},
		{
			name = "decision-packets",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/api-architecture-consistency/decision-packets.md && test -f "$f" && for id in PKT-1 PKT-2 PKT-3 PKT-4 PKT-5 PKT-6 PKT-7 PKT-8 PKT-9 PKT-10 PKT-11 PKT-12; do grep -q "$id" "$f" || { echo "$id missing"; exit 1; }; done && grep -qi "recommendation" "$f" && grep -qi "migration cost" "$f"',
			evidence = "artifacts/api-architecture-consistency/decision-packets.md",
			note = "twelve preserved proposals (return-shape unification, teardown verbs, session-lifetime dispose, Readable adapter, export policy, rule exports, self-driven class-loss, typed themes, sort-mark glyphs, error grammar, lastError semantics, env introspection) — each evidence-backed with a recommendation and migration cost, none executed here",
		},
		{
			name = "enforcement-checks",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_registration_cli >/dev/null && lune run tools/lune/check_docs_cli >/dev/null && lune run tools/lune/check_boundary >/dev/null && lune run tools/lune/check_prop_parity_cli >/dev/null && lune run tools/lune/check_surface_ledger >/dev/null",
			note = "the upgraded battery: check_registration now heading-anchors api.md coverage, descends into every namespace export (the defeat that let two whole namespaces ship undocumented), and refuses the proves-nothing dumpMarker; check_boundary now scans the game and examples for internal instance-path requires against the blessed client entry-point list; check_surface_ledger is the new classification-coverage check; api_surface.spec carries the ADR-0011 semver/window/marking rules; the scaffold's adapter template matches the target contract it stamps against",
		},
		{
			name = "fresh-author-exercise",
			requirements = { "UI-AGENT-001" },
			state = "PENDING",
			evidence = "artifacts/api-architecture-consistency/fresh-author-exercise.md",
			note = "an agent with ONLY public docs adds one small composite through the canonical extension path (docs/extending/new-control.md), with no internal imports, and receives actionable failures for omitted obligations; the artifact records the transcript summary, the failures received, and the final green state",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			state = "PENDING",
			evidence = "artifacts/test.json",
			note = "flips to `run = tools/test.sh <floor>` with the FINAL count once the stage's own regressions land; the floor may never fall below the stage-start count recorded in baseline-freeze",
		},
		{
			name = "rascalrally-consumer",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/api-architecture-consistency/consumer-impact.md && grep -q "F-27" artifacts/api-architecture-consistency/consumer-impact.md && cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1',
			evidence = "artifacts/api-architecture-consistency/consumer-impact.md",
			note = "the consumer-impact ledger audits every changed contract against the game's actual callers (each with the grep/file:line evidence; the lockstep rule's no-manufactured-churn clause applied — every change is compatible for the shipped call sites), and the check RE-RUNS the game suite live at the source being judged (3000 green at flip time) rather than trusting a stored transcript",
		},
		{
			name = "registration-and-drift",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_registration_cli >/dev/null && lune run tools/lune/check_boundary >/dev/null && lune run tools/lune/check_docs_cli >/dev/null && lune run tools/lune/check_prop_parity_cli >/dev/null && python3 tools/check_manifest_integrity.py >/dev/null && stylua --check src tests tools bench examples",
			note = "the standard battery at the final source: api.md drift both directions (now heading-anchored + namespace-descending), the engine-free require graph plus the new consumer scan, theme-doc anchors, the seven-view property parity, manifest grep integrity, and stylua proving the diff is not a reformat",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = 'if [ -n "${LUAUUI_PRIOR_GATES_NESTED:-}" ]; then echo "prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)"; exit 0; fi; b=artifacts/api-architecture-consistency/baseline/prior-gates-before.txt && a=artifacts/api-architecture-consistency/prior-gates.txt && test -f "$b" && grep -q "^DONE$" "$b" && tools/prior_gates.sh "$a" api-architecture-consistency && grep -q "^DONE$" "$a" && lost="$(comm -23 <(grep "^PASS " "$b" | sort) <(grep "^PASS " "$a" | sort))" && test -z "$lost"',
			evidence = "artifacts/api-architecture-consistency/prior-gates.txt",
			note = "all 17 prior gates RE-RUN at the final source via tools/prior_gates.sh (nested-guard aware); the DIRECTIONAL comparison is against a baseline regenerated from a worktree pinned to the stage-start commit — no gate that passed there may fail now",
		},
		{
			name = "performance-unregressed",
			requirements = { "UI-PERF-001" },
			run = "tools/bench.sh >/dev/null && python3 -c \"import json,sys; d=json.load(open('artifacts/bench.json')); sys.exit(0 if d['status']=='PASS' and not any(r['regression'] for r in d['results']) else 1)\"",
			note = "headless regression screening only, never a device claim: bench.json REGENERATED at the source being judged, every scene must report regression=false against the frozen baseline (this stage touched text_metrics, blueprint construction, and the renderer's binding dispatch — the scenes cover all three)",
		},
		{
			name = "studio-evidence",
			requirements = { "UI-FID-001" },
			run = 'python3 -c "'
				.. "import json,sys;"
				.. "c=json.load(open('artifacts/api-architecture-consistency/studio/canary.json'));"
				.. "assert c['preflight']['viewport'].startswith('1092'), 'viewport';"
				.. "assert 'VERSION=0.8.0' in c['preflight']['sourceMarker'], 'source marker';"
				.. "ids={s['id'].split(' ')[0] for s in c['slices']};"
				.. "assert {'S1-header-alignment-live','S2-consumer-modal-real-pointer','S3-keyboard-semantic-path','S4-lifecycle'} <= {i.split(' ')[0] for i in ids} or len(ids)>=4, 'slices';"
				.. "assert all(s['level']=='E3' for s in c['slices']), 'levels';"
				.. "assert any('NS-P2' in o for o in c['honestObservations']), 'touch honesty';"
				.. '" && test -f artifacts/api-architecture-consistency/studio-disposition.md && grep -q "F-17" artifacts/api-architecture-consistency/studio-disposition.md && lune run tools/lune/check_flat_baseline >/dev/null',
			evidence = "artifacts/api-architecture-consistency/studio-disposition.md",
			note = "disposition-aware real-adapter proof, run in the LIVE Rojo-synced consumer place at v0.8.0: header alignment measured on real Instances both ways plus the sort-mark clearance; the game's own mandatory RolePick modal driven by a real routed click (scrim swallow observed, then dismissal); the full keyboard semantic path (focus -> column select -> sort cycle) through client/roblox_input; clean teardown. Touch-gesture FIRING stays honestly on physical row NS-P2 — Studio cannot synthesize touch. check_flat_baseline re-proves the regenerated 1140-node flat solve with the F-27 delta recorded in canary.json (it rides the pre-existing characterized /Playlist/ reshape scope)",
		},
		{
			name = "fresh-context-reviews",
			requirements = { "UI-AGENT-001" },
			state = "PENDING",
			evidence = "artifacts/api-architecture-consistency/verifier-phase-gate.json",
			note = "fresh-context architecture + phase-gate reviews on the raw surface ledger, baseline, diff, decisions, exercise, and evidence — without the implementer's conclusions; runtime/platform review added only when the stage changed that authority. The check reads the verdict FIELD, never a grep for an accept token",
		},
	},
	["code-simplicity-cleanup"] = {
		-- Roadmap Step 5.5 (docs/plans/code-simplicity-cleanup.md): a
		-- behaviour-preserving cleanup. Registered BEFORE implementation with
		-- honest PENDING checks per the plan's "Verification and completion";
		-- each flips to `run` only when its work and evidence actually exist.
		-- The pass rule is unchanged code BEHAVIOUR, so most checks here are
		-- BEFORE/AFTER comparisons rather than new capability assertions.
		{
			name = "candidate-ledger",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/code-simplicity-cleanup/candidate-ledger.md && grep -q "^## IMPLEMENTED" artifacts/code-simplicity-cleanup/candidate-ledger.md && grep -q "^## RETAINED" artifacts/code-simplicity-cleanup/candidate-ledger.md && grep -q "^## ESCALATED" artifacts/code-simplicity-cleanup/candidate-ledger.md',
			evidence = "artifacts/code-simplicity-cleanup/candidate-ledger.md",
			note = "every candidate records location, evidence, preserved behaviour, proposal, risk, check, benefit, and a disposition of IMPLEMENTED / RETAINED / ESCALATED. 10 implemented, 19 retained, 6 escalated — RETAINED is the majority outcome, which is what the plan asks for",
		},
		{
			name = "step5-carryovers-dispositioned",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/code-simplicity-cleanup/carry-over-ledger.md && test -f "$f" && for id in RR-7-R1 RR-5-R1 RR-3-R1 RR-1-R2 RR-1-R1 ESC-1 ESC-2 ARCH-F3 ARCH-F4 ARCH-F6 ARCH-F7 ARCH-F8 PLAT-2 PLAT-7 PLAT-8 P2-4 P2-5 P2-6 PG-9; do grep -q "$id" "$f" || { echo "carry-over $id not dispositioned"; exit 1; }; done',
			evidence = "artifacts/code-simplicity-cleanup/carry-over-ledger.md",
			note = "every carry-over named in artifacts/sponsor-framework-gaps/{verifier-responses,responsibility-ledger}.md has a disposition; RR-7-R1/RR-5-R1/RR-3-R1/RR-1-R2 and the scope-less adaptive.conditions callers are fixed or retired WITH EVIDENCE (reproductions RUN, not read — tools/lune/_probe_carryovers); RR-1-R1/ESC-1/ESC-2 are decision packets only",
		},
		{
			name = "decision-packets",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/code-simplicity-cleanup/decision-packets.md && test -f "$f" && grep -q "RR-1-R1" "$f" && grep -q "ESC-1" "$f" && grep -q "ESC-2" "$f" && grep -qi "recommendation" "$f"',
			evidence = "artifacts/code-simplicity-cleanup/decision-packets.md",
			note = "RR-1-R1 (motion-clock quarantine granularity), ESC-1 (interactive-state theme vocabulary), ESC-2 (pointer-zone rects) are DESIGN decisions routed to Fable 5 / the user — evidence-backed recommendation, never implemented here; plus ARCH-F6's record correction, the imperative-scorecard nondeterminism, and the three consolidations found and deliberately not taken",
		},
		{
			name = "public-surface-unchanged",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/_probe_public_surface > artifacts/code-simplicity-cleanup/public-surface.txt && diff -q artifacts/code-simplicity-cleanup/baseline/public-surface-before.txt artifacts/code-simplicity-cleanup/public-surface.txt",
			evidence = "artifacts/code-simplicity-cleanup/public-surface.txt",
			note = "the exported LuauUI surface + DEPRECATIONS ledger dumped before and after; the check REGENERATES the after-dump and requires byte equality with the frozen before-dump (ADR-0011: exports and deprecation timing are frozen by this stage). 139 lines, identical",
		},
		{
			name = "carry-over-pins",
			requirements = { "UI-LIFE-001", "UI-RUNTIME-003" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the double-dispose report fires for an ALIASED child and stays silent otherwise (RR-5-R1)" && echo "$out" | grep -q "✓.*transactions counts frames that really committed, never the aborted ones" && echo "$out" | grep -q "✓.*disposing the registry with several flights in the air is clean (RR-3-R1)" && echo "$out" | grep -q "✓.*scope-cleanup-quarantined-and-early-child-is-not-a-double-dispose"',
			note = "the smallest durable regressions the carry-over work leaves behind, asserted by NAME so a silent removal fails here: RR-5-R1 (both directions — the aliased child reports, the non-aliased one stays silent), RR-1-R2 (transactions <= steps, equality iff healthy), RR-3-R1 (two flights airborne, registry disposed mid-air), RR-7-R1 (the cross-core scope check)",
		},
		{
			name = "conformance-all-cores",
			requirements = { "UI-LIFE-001" },
			run = "for core in custom fusion imperative; do lune run tests/conformance/cli $core >/dev/null 2>&1; python3 -c \"import json,sys; d=json.load(open('artifacts/conformance-$core.json')); r=[c for c in d['checks'] if c['name']=='scope-cleanup-quarantined-and-early-child-is-not-a-double-dispose']; sys.exit(0 if r and r[0]['status']=='PASS' else 1)\" || exit 1; done",
			evidence = "artifacts/conformance-custom.json",
			note = "RR-7-R1: the scope semantics Step 5 changed now live in tests/conformance/suite.luau, so they run against custom | fusion | imperative rather than the default core alone. The check asserts the NAMED check on each core and never a total — the imperative scorecard's total is nondeterministic for a pre-existing reason recorded in decision-packets.md (DP-5)",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 2571",
			evidence = "artifacts/test.json",
			note = "stage-start floor was 2567; the floor lands here as the FINAL number (2571 = +4 carry-over pins, none removed and none weakened) so a regression of this stage's own pins fails the gate",
		},
		{
			name = "game-untouched",
			requirements = { "UI-AGENT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1",
			note = "RascalRally suite green (2425 at the final source); this stage changes no game code",
		},
		{
			name = "registration-and-drift",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_registration_cli >/dev/null && lune run tools/lune/check_boundary >/dev/null && lune run tools/lune/check_docs_cli >/dev/null && lune run tools/lune/check_prop_parity_cli >/dev/null && python3 tools/check_manifest_integrity.py >/dev/null && stylua --check src tests tools bench examples",
			note = "a deleted surface that a registration or a doc still names fails here — check_registration drift-checks api.md in BOTH directions, check_boundary re-proves the engine-free require graph after the new controls->contract edges, check_manifest_integrity refuses any suite grep that is not anchored to the PASS marker (gate-integrity sweep 2026-07-29, defect D-1: a failing case still prints its name, and in the pipelined form the suite exit code is masked entirely), and stylua --check proves the diff is not a reformat",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = 'if [ -n "${LUAUUI_PRIOR_GATES_NESTED:-}" ]; then echo "prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)"; exit 0; fi; b=artifacts/code-simplicity-cleanup/baseline/prior-gates-before.txt && a=artifacts/code-simplicity-cleanup/prior-gates.txt && test -f "$b" && tools/prior_gates.sh "$a" code-simplicity-cleanup && grep -q "^DONE$" "$a" && lost="$(comm -23 <(grep "^PASS " "$b" | sort) <(grep "^PASS " "$a" | sort))" && test -z "$lost"',
			evidence = "artifacts/code-simplicity-cleanup/prior-gates.txt",
			note = "all 16 prior gates RE-RUN by this check at the source being judged (verifier PG-2), via tools/prior_gates.sh, which derives the list from phases.json so a newly registered gate is covered the day it lands. The check used to compare two STORED text files and execute nothing — the identical can't-ever-fail shape ledger C-08 had just removed from theme-packages-and-skinning, reintroduced here carrying this stage's own headline claim. The comparison is DIRECTIONAL on purpose: no gate that passed at the baseline may fail now. It does not demand an identical list, because theme-packages-and-skinning legitimately went FAIL -> PASS here (C-08/C-09). authoring-adaptive-ui fails identically before and after on its own standing PENDING physical row = unregressed. Analysis in prior-gates.md",
		},
		{
			name = "performance-unregressed",
			requirements = { "UI-PERF-001" },
			run = "test -f artifacts/code-simplicity-cleanup/perf-after.md && tools/bench.sh >/dev/null && python3 -c \"import json,sys; d=json.load(open('artifacts/bench.json')); sys.exit(0 if d['status']=='PASS' and not any(r['regression'] for r in d['results']) else 1)\"",
			evidence = "artifacts/code-simplicity-cleanup/perf-after.md",
			note = "headless regression screening only, never a device claim. All 17 scenes same-or-faster than the frozen baseline and every scene reports regression=false against the bench's own 1.5x p95 rule. REGENERATES bench.json at the source being judged (verifier PG-3): the check used to read whatever bench.json happened to be on disk — written, in fact, by a DIFFERENT gate's bench check during the prior-gate rerun — so it could not distinguish final-source evidence from a stale artifact and would have passed forever. Same shape as expansion-adr-bench-rollback. Scene-by-scene table in perf-after.md",
		},
		{
			name = "studio-evidence",
			requirements = { "UI-FID-001" },
			run = 'python3 -c "'
				.. "import json,sys;"
				.. "m=json.load(open('artifacts/code-simplicity-cleanup/studio/five-view-matrix.json'));"
				.. "want={'desktop-standard','compact-phone-portrait','compact-phone-landscape','tablet-landscape','console-ten-foot'};"
				.. "rows=m['rows'];"
				.. "got={r['row'] for r in rows};"
				.. "assert got==want, 'row set '+str(sorted(got));"
				.. "assert m['sourceStamp']=='efbe185e-2570354', 'stamp';"
				.. "assert m['preflight']['ok'] and m['preflight']['problems']==[], 'preflight';"
				.. "bad=[r['row'] for r in rows if not r['ok'] or r['diagnostics'] or r['solverDiagnostics'] or r['offscreenNodes'] or r['nodesCapped']];"
				.. "assert not bad, 'rows not clean: '+str(bad);"
				.. "assert all(r['viewport']['x']>1 and r['viewport']['y']>1 for r in rows), 'viewport 1x1';"
				.. "assert len({(r['viewport']['x'],r['viewport']['y']) for r in rows})==5, 'viewports not distinct';"
				.. "c=[r for r in rows if r['row']=='console-ten-foot'][0];"
				.. "assert c['isTenFoot'] and c['typographyScale']==1.5 and c['preferredInput']=='Gamepad', 'ten-foot profile';"
				.. "p=[r for r in rows if r['row']=='compact-phone-portrait'][0];"
				.. "assert p['sizeClass']=='compact' and p['pickerPresentation']=='inline', 'compact adaptation';"
				.. "s=json.load(open('artifacts/code-simplicity-cleanup/studio/scroll-host-keepvisible.json'));"
				.. "assert s['sourceStamp']==m['sourceStamp'], 'scroll stamp';"
				.. "st={x['step']:x for x in s['steps']};"
				.. "assert st['keepVisibleAlreadyVisible']['returned']['moved'] is False, 'already-visible must not scroll';"
				.. "assert st['keepVisibleFar']['returned']['moved'] and st['keepVisibleFar']['canvasPositionAfter']['/ScrollHost/FocusList']['y']==456, 'vertical keep-visible';"
				.. "assert st['keepVisibleHorizontal']['returned']['moved'] and st['keepVisibleHorizontal']['canvasPositionAfter']['/ScrollHost/Strip']['x']==570, 'horizontal keep-visible';"
				.. "assert st['keepVisibleFar']['canvasPositionAfter']['/ScrollHost/List']['y']==0, 'a sibling host must not move';"
				.. '"'
				.. " && test -f artifacts/code-simplicity-cleanup/studio/adaptive-controls-desktop-efbe185e.json",
			evidence = "artifacts/code-simplicity-cleanup/studio/five-view-matrix.json",
			note = "CLOSED 2026-07-28. The cleanup touched solver/renderer/mount/controls, so the real-adapter requirement fires and, because layout can change, so does the five-view matrix. All FIVE rows now run green at stamp efbe185e-2570354 (the place was re-injected at the review-response source; the earlier session's two rows were re-run, not carried). Zero diagnostics, zero solver diagnostics, no offscreen nodes and no node cap on every row, five DISTINCT viewports. The check validates row CONTENT, not file existence: the ten-foot profile must be live on console (isTenFoot + 1.5x typography + Gamepad) and the compact adaptation must be live on phone portrait (sizeClass compact + picker collapsed to inline). It also asserts the separate scroll_host row, which drives the CHANGED scrollToVisible host lookup against real ScrollingFrames: already-visible is a no-op, vertical moves FocusList to 456, horizontal moves Strip to 570, and a sibling host does NOT move. preferredInput reads KeyboardAndMouse on the emulated phone/tablet rows - an E3 instrument limitation recorded honestly in the matrix's honestObservations, NOT claimed as Touch. Physical touch/rotation/gamepad delivery remain E4 and unproven. The byte-exact geometry before/after stays with check_flat_baseline's 1140-node comparison",
		},
		{
			name = "fresh-context-reviews",
			requirements = { "UI-AGENT-001" },
			run = "test -f artifacts/code-simplicity-cleanup/verifier-architecture.json && python3 -c \"import json,sys; d=json.load(open('artifacts/code-simplicity-cleanup/verifier-phase-gate.json')); sys.exit(0 if d.get('verdict') in ('READY TO DECLARE', 'ACCEPT') else 1)\"",
			evidence = "artifacts/code-simplicity-cleanup/verifier-phase-gate.json",
			note = "fresh-context phase-gate + architecture reviews on the raw baseline/ledger/diff/evidence without the implementer's conclusions. Architecture is required by the plan; reactive-runtime is added because this stage changed scope_impl and the motion clock's documented contract. The check reads the verdict FIELD, never a grep for an accept token",
		},
	},
	["input-paradigms"] = {
		-- Interaction-paradigm expansion (prompt.md "Expansion: input
		-- paradigms", director 2026-07-21): the three adaptation axes — UI
		-- (layout), input (bindings/reachability), paradigm (structural
		-- affordances) — enforced as a contract; hybrid devices + hot-switch;
		-- console 10-foot. Checks flip from PENDING as work packages land.
		{
			name = "defect-example02-fix",
			requirements = { "UI-INPUT-002", "UI-ENV-001" },
			run = 'test -f docs/adr/ADR-0015-interaction-classes.md && test -f docs/research/2026-07-21-preferredinput-gamepad-research.md && test -f artifacts/input-paradigms/defect-example02.md && grep -q "interactionClasses" src/env/environment.luau && grep -q "interactionClasses" src/controls/table.luau && grep -q "GamepadConnected" src/client/roblox_env.luau && grep -q "sawGamepadInput" src/client/roblox_env.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*shown when a gamepad capability is live even though preferredInput stays KeyboardAndMouse" && echo "$out" | grep -q "✓.*a live touch capability shows it under a KeyboardAndMouse preferredInput"',
			evidence = "artifacts/input-paradigms/defect-example02.md",
			note = "root cause = engine fact unreachable (Studio/macOS pad forwarding, sourced) + affordances keyed off preferredInput ALONE; fixed via ADR-0015 interactionClasses + adapter capability subscriptions; red-first regression at the failing layer (491->493)",
		},
		{
			name = "affordance-matrix",
			requirements = { "UI-INPUT-002", "UI-PARADIGM-001" },
			run = "test -f docs/research/2026-07-21-swiftui-affordance-research.md && grep -q 'The interaction-class affordance contract' artifacts/input-paradigms/affordance-matrix.md && grep -q 'The master matrix' artifacts/input-paradigms/affordance-matrix.md && grep -q 'In-flight transition table' artifacts/input-paradigms/affordance-matrix.md && grep -q 'Console 10-foot presentation profile' artifacts/input-paradigms/affordance-matrix.md && grep -q 'UI-PARADIGM-001' artifacts/input-paradigms/affordance-matrix.md && grep -q 'UI-PARADIGM-001' requirements.json && grep -q 'UI-PARADIGM-003' requirements.json",
			evidence = "artifacts/input-paradigms/affordance-matrix.md",
			note = "UI-Designer-authored reviewed matrix (2026-07-21): 7 controls x 4 classes with SHIPPED/GAP per cell + hybrid/hot-switch CARRY-CANCEL table + 10-foot profile + UI-PARADIGM-001..003 (now in requirements.json); sourced from docs/research/2026-07-21-swiftui-affordance-research.md",
		},
		{
			name = "per-control-affordance-proofs",
			requirements = { "UI-PARADIGM-001" },
			run = 'lune run tools/lune/check_registration_cli | grep -q "prove the paradigm axis" && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*shown when a gamepad capability is live" && echo "$out" | grep -q "✓.*a pointer-live renderer enables hover" && echo "$out" | grep -q "✓.*DPadDown leaves the auto Edit/Done toggle and reaches a row" && echo "$out" | grep -q "✓.*gamepad grab-mode reorders end to end with selection none" && echo "$out" | grep -q "✓.*a tap on a rendered node OUTSIDE the open panel dismisses it" && echo "$out" | grep -q "✓.*gamepad ButtonB while open closes the popup" && echo "$out" | grep -q "✓.*Adjust keys bind the moment focus lands on the declared target" && echo "$out" | grep -q "✓.*a Thumbstick1 y push moves focus down like DPadDown"',
			evidence = "artifacts/input-paradigms/affordance-matrix.md",
			note = "registry affordanceProofs per class + hotSwitch enforced by check_registration (silent omission fails); every matrix per-class GAP closed (Amendments section) incl. the live-drive selection-none wedge; deferred new-feature gaps on the ui_todo ledger",
		},
		{
			name = "hybrid-hotswitch",
			requirements = { "UI-PARADIGM-002", "UI-ENV-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*pointer drag mid-flight + pointer capability lost" && echo "$out" | grep -q "✓.*focus survives any class flip" && echo "$out" | grep -q "✓.*an exclusive modal survives any class flip" && echo "$out" | grep -q "✓.*a gamepad arriving mid-edit CARRIES the edit" && echo "$out" | grep -q "✓.*leaving mid-edit ends the edit via commit" && grep -q "interactionClasses" src/env/environment.luau && grep -q "derived interactionClasses" tests/renderer.spec.luau',
			evidence = "artifacts/input-paradigms/affordance-matrix.md",
			note = "matrix SectionC CARRY/CANCEL table fully test-backed: Table (drag/grab/edit-mode cancel+carry, 2 wedges fixed), TextInput (dock commit path, 1 wedge fixed), framework focus+modal carry (paradigm_carry.spec); scripted mid-interaction flips throughout; live edit-mode flip driven in Studio",
		},
		{
			name = "console-10foot",
			requirements = { "UI-PARADIGM-003", "UI-ADAPT-001", "UI-ENV-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*displaySize fact defaults to Medium" && echo "$out" | grep -q "✓.*console profile whose facts flip distanceProfile and interactionClasses" && echo "$out" | grep -q "✓.*insets the solved tree by the overscan margins" && echo "$out" | grep -q "✓.*a ten-foot display scales rendered text sizes by 1.5x" && echo "$out" | grep -q "✓.*sizeClass caps at regular on a ten-foot Large display" && echo "$out" | grep -q "✓.*focus visuals differ between a Large display and a Medium display" && grep -q "ViewportDisplaySize" src/client/roblox_env.luau && grep -q "console" src/preview/device_profiles.luau && grep -q "console-tenfoot-profile" artifacts/input-paradigms/studio-drive.json',
			evidence = "artifacts/input-paradigms/studio-drive.json",
			note = "displaySize/overscanInsets facts + distanceProfile; renderer overscan composition; 1.5x type floor at measure+paint; density cap; ten-foot focus strengthening; console device profile Studio-driven (screenshot); Thumbstick1 tolerance via axis latch; TV-remote input explicitly deferred",
		},
		{
			name = "axes-future-proofing",
			requirements = { "UI-AGENT-001", "UI-PARADIGM-001" },
			run = 'test -f docs/adr/ADR-0016-three-axes-contract.md && lune run tools/lune/check_registration_cli | grep -q "prove the paradigm axis" && grep -q "affordanceProofs" tools/lune/scaffold.luau && grep -q "paradigm" docs/guide/07-input.md && grep -q "Three load-bearing facts" docs/extending/new-control.md && test -f artifacts/input-paradigms/dryrun-chip.md && test -f src/controls/chip.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*Chip gamepad affordance" && echo "$out" | grep -q "✓.*Chip keyboard affordance"',
			evidence = "artifacts/input-paradigms/dryrun-chip.md",
			note = "UI-PARADIGM-001..003 in requirements.json; registry affordanceProofs + hotSwitch enforced by check_registration; scaffold stamps the three axes born-red; guide/playbook/api updated; PROVEN by the fresh-context playbook-only Chip dry run (591 green, checker PASS, no regressed gate); three playbook gaps it found were folded back in",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 591",
			evidence = "artifacts/test.json",
		},
		{
			name = "game-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1",
		},
		{
			name = "studio-drive",
			requirements = { "UI-FID-001" },
			run = 'grep -q "luauui-studio-drive/1" artifacts/input-paradigms/studio-drive.json && grep -q "defect-fix-differential" artifacts/input-paradigms/studio-drive.json && grep -q "console-tenfoot-profile" artifacts/input-paradigms/studio-drive.json && grep -q "hotswitch-edit-mode-live" artifacts/input-paradigms/studio-drive.json',
			evidence = "artifacts/input-paradigms/studio-drive.json",
			note = "four live drives on real engine instances (defect chain trace both directions, fix differential, console ten-foot with screenshot, hot-switch edit-mode incl. the selection-none wedge discovery) plus the recorded synthetic-gamepad engine gates; physical-only items enumerated in the artifact",
		},
		{
			name = "opus-verification",
			requirements = { "UI-AGENT-001" },
			run = "test -f artifacts/input-paradigms/architecture-verification.json && test -f artifacts/input-paradigms/platform-verification.json && test -f artifacts/input-paradigms/runtime-verification.json && test -f artifacts/input-paradigms/phase-gate-verification.json && grep -q 'READY TO DECLARE' artifacts/input-paradigms/phase-gate-verification.json",
			evidence = "artifacts/input-paradigms/phase-gate-verification.json",
			note = "four Opus verifiers: architecture FINDINGS (5, all fixed red-first or ridered), roblox-platform FINDINGS (2, fixed), reactive-runtime PASS (+2 coverage gaps closed), phase-gate fresh-context READY TO DECLARE (9 substantive checks re-run PASS; cross-gate phase-4 + input-adaptation-audit unregressed; artifacts ruled honest)",
		},
		{
			name = "physical-device-confirmation",
			requirements = { "UI-INPUT-002" },
			state = "FAIL_ENVIRONMENT",
			releaseBlocking = false,
			note = "real PreferredInput=Gamepad flip + physical pad/touch confirmation: unreachable from Studio/macOS (HID forwarding bug class + RobloxScript-gated virtual gamepad, sourced in docs/research/2026-07-21-preferredinput-gamepad-research.md); confirm on retail client/console before shipping a console-facing UI",
		},
	},
	["input-adaptation-audit"] = {
		-- ui_todo §0 closure gate (director 2026-07-20): every control ships
		-- focus/navigation, Activate, and input-appropriate affordances for
		-- pointer, touch, keyboard, AND gamepad with no consumer wiring.
		-- Checks flip from PENDING to `run` as each work package lands.
		{
			name = "audit-matrix",
			requirements = { "UI-INPUT-001", "UI-INPUT-002" },
			run = "test -f artifacts/input-adaptation-audit/wp-a-framework.md && test -f artifacts/input-adaptation-audit/wp-b-composites.md && test -f artifacts/input-adaptation-audit/wp-c-examples.md && grep -q 'Master control matrix' artifacts/input-adaptation-audit/matrix.md && grep -q 'proof matrix' artifacts/input-adaptation-audit/matrix.md && grep -q 'Boilerplate baselines' artifacts/input-adaptation-audit/matrix.md && grep -q 'Engine truths' artifacts/input-adaptation-audit/matrix.md && grep -q 'Root causes' artifacts/input-adaptation-audit/matrix.md",
			evidence = "artifacts/input-adaptation-audit/matrix.md",
			note = "2026-07-21 audit: 64 control cells (16 rows x 4 input classes) = 12 framework-automatic / 39 consumer-wired / 13 missing, each cell with file:line evidence in the three WP appendices; 7 examples x 4 inputs = 13 PROVEN / 2 PARTIAL / 13 UNPROVEN; boilerplate baselines recorded for the regression proof (~158 generic lines)",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 479",
			evidence = "artifacts/test.json",
			note = "377 at audit start -> 479 at close: 15 auto_input seam + 14 auto_input_screens + 15 table_input + 14 virtual_list_input + 12 responder (incl. the P1 setSink seam-contract spy) + 5 gamepad_contention + 4 proof-gap closures + 17 example all-input cases + the F2 dispose/activate-race guard case + checker/scaffold cases",
		},
		{
			name = "game-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1",
			note = "2404 green through the audit closure (verified 2026-07-21)",
		},
		{
			name = "framework-auto-input",
			requirements = { "UI-INPUT-001", "UI-INPUT-002", "UI-FOCUS-001" },
			run = 'test -f src/input/contribution.luau && grep -q "contribution.attach" src/controls/table.luau && grep -q "contribution.attach" src/controls/text_input.luau && grep -q "contribution.attach" src/controls/popup_button.luau && grep -q "contribution.attach" src/controls/virtual_list.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*Button touch: a finger tap activates" && echo "$out" | grep -q "✓.*Toggle gamepad: ButtonA on the focused Toggle" && echo "$out" | grep -q "✓.*VirtualList gamepad: ButtonA activates the focused row" && echo "$out" | grep -q "✓.*VirtualList touch: a native pan scroll slides the window" && echo "$out" | grep -q "✓.*VirtualList keyboard: focus past the window edge" && echo "$out" | grep -q "✓.*gamepad ButtonA SELECTS the column" && echo "$out" | grep -q "✓.*DPadDown past the clip band scrolls" && echo "$out" | grep -q "✓.*a TOUCH drag on the grip previews and commits" && echo "$out" | grep -q "✓.*TOUCH-typed tap on the trigger opens the popup"',
			note = "ADR-0013 contribution seam: mounting a control yields its four-input story with zero present() opts (contributions auto-discovered; presenter composes groups/dispatch/intercepts/geometry; per-opt consumer override for back-compat); leaf Button/Toggle onActivate props; Toggle finally flips on Activate; layout-derived 2D groups for plain Grid/HStack screens; modal outside-tap Cancel",
		},
		{
			name = "per-control-per-input-conformance",
			requirements = { "UI-INPUT-001", "UI-INPUT-002" },
			run = 'lune run tools/lune/check_registration_cli | grep -q "interactive controls prove four-input"',
			note = "controls_registry inputProofs per input class (explicit false for non-interactive) + checker rules: undeclared row fails, unregistered case name fails, interactive row missing any class fails; PROOF_GAPS emptied 2026-07-21 (Button/Toggle/PopupButton touch + Toggle gamepad closed device-true); ScrollView wheel/pan recorded as named INTERACTIVE_ACTION_EXCEPT; scaffold stamps contribution stub + four failing per-class cases",
		},
		{
			name = "examples-all-input-headless",
			requirements = { "UI-INPUT-001", "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*ex03 touch" && echo "$out" | grep -q "✓.*ex03 keyboard" && echo "$out" | grep -q "✓.*ex03 gamepad" && echo "$out" | grep -q "✓.*ex04 pointer" && echo "$out" | grep -q "✓.*ex04 touch" && echo "$out" | grep -q "✓.*ex05 pointer" && echo "$out" | grep -q "✓.*ex05 touch" && echo "$out" | grep -q "✓.*ex05 keyboard" && echo "$out" | grep -q "✓.*ex05 gamepad" && echo "$out" | grep -q "✓.*ex06 touch" && echo "$out" | grep -q "✓.*ex06 keyboard" && echo "$out" | grep -q "✓.*ex06 gamepad" && echo "$out" | grep -q "✓.*ex07 pointer" && echo "$out" | grep -q "✓.*ex07 touch" && echo "$out" | grep -q "✓.*ex07 keyboard" && echo "$out" | grep -q "✓.*ex07 gamepad" && echo "$out" | grep -q "✓.*pointer tap and touch tap each enter edit mode" && echo "$out" | grep -q "✓.*gamepad A enters edit mode, B cancels reverting"',
			note = "all 7 examples proven per input class through real device paths: ex01/ex02 via the expansion-textinput per-input cases (still gate-grepped there) + ex03-ex07 via the 17 new cases (2026-07-21); the 15 not-fully-PROVEN matrix cells closed; ex04 keyboard/gamepad were already PROVEN pre-audit",
		},
		{
			name = "examples-no-input-boilerplate",
			requirements = { "UI-AGENT-001" },
			run = '! grep -l "navigationGroups\\|onNavigateIntercept\\|onFocusNav\\|keepVisibleOffset\\|onGeometry" examples/gallery/examples/*.luau && [ "$(cat examples/gallery/examples/0*.luau | wc -l)" -le 1644 ]',
			note = "regression proof vs the wp-c baselines: generic input wiring ~158 lines -> 0 (no example passes any present() input opt). Ceiling refreshed 1587 -> 1644 during sponsor-framework-gaps' prior-gates rerun: the 2026-07-26/27 director rounds legitimately grew 02 (315->352, Table.scrolls page-scroll ruling) and 04 (87->107, the Rating control) AFTER this ceiling was recorded — the grep half (the check's actual subject) stayed clean throughout; app-semantic wiring kept per the wp-c keep-list (05 hardware-key context, node-level onActivate handlers)",
		},
		{
			name = "studio-all-input-verification",
			requirements = { "UI-FID-001" },
			run = 'grep -q "luauui-studio-drive/1" artifacts/input-adaptation-audit/studio-drive.json && grep -q "responder-sink-seam" artifacts/input-adaptation-audit/studio-drive.json && grep -q "07_match3" artifacts/input-adaptation-audit/studio-drive.json && grep -q "ScreenCapture_ex06_focus" artifacts/input-adaptation-audit/studio-drive.json',
			evidence = "artifacts/input-adaptation-audit/studio-drive.json",
			note = "2026-07-21 live drive: place synced to the shipped library (48 updated + 4 new modules, then the P1 fix re-synced), 30 drive rows across 7 examples x 4 classes, every row programmatically asserted; responder exclusiveSurfaceActive proven live; P1 setSink fix confirmed on the REAL InputContext (Sink false->true->false across engage/resign); injection-channel wedge after ex06 recorded honestly (ex05/ex07 pointer+keyboard LIMITED via the identical dispatch layer); gamepad driven at the adapter/IAS layer (VirtualInput refuses CoreGUI-bound keys) — physical gamepad remains the standing device rider; drive findings F1 (outside-tap needs a rendered node — scrim-catcher design call owed to the director) and F2 (dispose/activate race — FIXED same session with a red-first guard test)",
		},
		{
			name = "engine-truths-encoded",
			requirements = { "UI-FID-001", "UI-AGENT-001" },
			run = 'test -f src/client/gamepad_contention.luau && grep -q "legacyStackActive" src/client/gamepad_contention.luau && grep -q "disableLegacyControls" examples/gallery/client/init.client.luau && test -f docs/guide/07-input.md && grep -q "PlayerScriptsUseInputActionSystem" docs/guide/07-input.md && test -f docs/lessons/gamepad-contention-truths.md && grep -q "CoreGuiNavigationEnabled" docs/lessons/gamepad-contention-truths.md && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*describeContention() returns a string carrying all three" && echo "$out" | grep -q "✓.*legacyStackActive() is a guarded probe: headless it returns false, never throws"',
			note = "ui_todo §3 truths encoded: gamepad_contention.luau (legacyStackActive behavioral probe for the panel-only flag; disableLegacyControls scoped UI-ONLY-PLACES; describeContention) + gallery bootstrap routes through it + guide 07-input + lesson file; CoreGui fights-back recorded as known non-fix",
		},
		{
			name = "first-responder-model",
			requirements = { "UI-INPUT-003", "UI-INPUT-004", "UI-FID-001" },
			run = 'test -f docs/adr/ADR-0014-first-responder.md && test -f src/client/responder_effects.luau && test -f docs/research/2026-07-21-first-responder-platform-research.md && grep -q "setSink" src/client/roblox_input.luau && grep -q "Workspace.PlayerScriptsUseInputActionSystem" docs/guide/07-input.md && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*all reach gameplay and the HUD focus never moves" && echo "$out" | grep -q "✓.*suppressed while the modal is up and restored on dismiss" && echo "$out" | grep -q "✓.*handle.engage() is the explicit public path" && echo "$out" | grep -q "✓.*nav works immediately AND gameplay ALSO receives" && echo "$out" | grep -q "✓.*50 engage/resign cycles leave a single working context" && echo "$out" | grep -q "✓.*engage() calls setSink(true) and resign() calls setSink(false)"',
			note = "director 2026-07-21: real games KEEP avatar input — responder modes (passive HUD binds nothing until engaged; engage via tap-in/engage(); resign via Cancel/outside-tap; modals exclusive), engaged band 3000+/3500+ strictly above the doc-sanctioned gameplay sink at 2000, Space/ButtonA gameplay guard while exclusive (gameplayGuard=false opt-out), responder_effects applies TouchControlsEnabled client-side; director scenario proven headless vs fake character(1000)+PlayContext(2000-sink); riders in ADR-0014 (WASD set, SelectedObject, live char+flag probe)",
		},
		{
			name = "playbooks-and-docs-updated",
			requirements = { "UI-AGENT-001" },
			run = 'grep -q "contribution.attach" docs/extending/new-control.md && grep -q "inputProofs" docs/extending/new-control.md && grep -q "contribution.attach" tools/lune/scaffold.luau && grep -q "PlayerScriptsUseInputActionSystem" docs/guide/07-input.md && grep -q "responder" docs/guide/07-input.md && grep -q "07-input" docs/guide/README.md && grep -q "onActivate" docs/reference/api.md && grep -q "engage" docs/reference/api.md && lune run tools/lune/check_registration_cli >/dev/null',
			note = "new-control.md teaches the §0 four-input contract + contribution attach + the checker consequence; scaffold stamps the multi-input skeleton; guide 07-input.md is the user-facing input story (director-revised 2026-07-21: IAS-required warning up top, concepts, responder chain, near-zero user obligations); api.md documents the new public surface",
		},
		{
			name = "adr-recorded",
			requirements = { "UI-AGENT-001" },
			run = 'test -f docs/adr/ADR-0013-input-auto-wiring.md && grep -q "Accepted" docs/adr/ADR-0013-input-auto-wiring.md && test -f docs/adr/ADR-0014-first-responder.md',
			note = "ADR-0013 (contribution seam, per-opt override, longest-prefix dispatch, justified exceptions incl. modal keyboard Cancel + grip Adjust) finalized Accepted; ADR-0014 (first-responder model) recorded with riders",
		},
		{
			name = "opus-verification",
			requirements = { "UI-AGENT-001" },
			run = "test -f artifacts/input-adaptation-audit/platform-verification.json && test -f artifacts/input-adaptation-audit/architecture-verification.json && test -f artifacts/input-adaptation-audit/phase-gate-verification.json && grep -q 'READY TO DECLARE' artifacts/input-adaptation-audit/phase-gate-verification.json",
			evidence = "artifacts/input-adaptation-audit/phase-gate-verification.json",
			note = "three fresh-context Opus verifiers 2026-07-21, all xhigh: roblox-platform FAIL->resolved (P1 setSink dead-write fixed with seam+spy test+live Studio Sink read-back; P2 Workspace-not-StarterPlayer flag rename); architecture PASS (F1 type-guard fixed; F2-F5 advisories recorded in ADR-0014); phase-gate fresh-context audit READY TO DECLARE (G1 drive-artifact amendment + G3 boilerplate bound tightened same session)",
		},
		{
			name = "physical-device-confirmation",
			requirements = { "UI-PERF-001", "UI-FID-001" },
			state = "FAIL_ENVIRONMENT",
			releaseBlocking = false,
			note = "physical phone/gamepad confirmation remains a pending release item (no device available to the autonomous build); never claimed",
		},
	},
	["expansion-textinput"] = {
		-- First Phase-5 expansion gate (design §17 Phase 5 rules: use case,
		-- inability with current primitives, benchmark, conformance extension,
		-- rollback/fallback — recorded in ADR-0012). Checks flip from PENDING to
		-- `run` as each work package lands; the gate passes only when all landed.
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 377",
			evidence = "artifacts/test.json",
			note = "328 at expansion start -> 377 at expansion close: 36 TextInput control cases (incl. touch story, invalid-UTF-8 rejection, engine-initiated-focus occlusion, settable-signal guard, dispose-mid-occlusion restore) + TextField conformance row + 11 upgraded example-01/02 cases",
		},
		{
			name = "game-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1",
			note = "consumer surfaces must stay green through the expansion",
		},
		{
			name = "engine-facts-probed",
			requirements = { "UI-FID-001" },
			run = 'python3 tools/check_spike.py artifacts/studio/expansion-textinput-probe.json reflection-TextInputType-security-locked reflection-Enum-TextInputType-values focus-lifecycle-round-trip handshake-gameProcessedEvent-while-focused handshake-negative-control && test -f docs/research/2026-07-20-textbox-engine-facts.md && test -f docs/lessons/textbox-reflection-and-injection-truths.md && grep -q "RobloxScript" docs/research/2026-07-20-textbox-engine-facts.md',
			evidence = "artifacts/studio/expansion-textinput-probe.json",
			note = "2026-07-20 live probe (20 probes, Place1): TextInputType RobloxScript-locked both directions; focused-TextBox keys arrive gameProcessed=true (handshake fact); cursor auto-clamps on shorter .Text rewrite; wrap-at-rest + AutomaticSize.Y + clipped-host focus OK; desktop OSK occlusion nil; mobile wrap-while-typing + real-key entry remain device-only (recorded UNVERIFIED)",
		},
		{
			name = "textinput-per-input-interaction",
			requirements = { "UI-INPUT-001", "UI-INPUT-002", "UI-FOCUS-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*tapping the field enters editing" && echo "$out" | grep -q "✓.*a touch tap enters editing and the occlusion keep-visible engages" && echo "$out" | grep -q "✓.*focused field + Activate (Return) enters editing" && echo "$out" | grep -q "✓.*ButtonA enters editing; D-pad does not navigate; ButtonB cancels" && echo "$out" | grep -q "✓.*typed text flows through the adapter seam into the owner value"',
			note = "ui_todo §0 review bar: pointer tap, touch tap (+occlusion story), keyboard Activate, gamepad A/D-pad/B each proven through real paths (onNodeTap / deviceKey / setTextInputHandlers seam) — never direct callbacks",
		},
		{
			name = "textinput-handshake-and-cancel",
			requirements = { "UI-INPUT-003", "UI-INPUT-004" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*navigation keys are sunk: a lower Navigate probe never fires" && echo "$out" | grep -q "✓.*Enter commits, editing ends, and navigation works again" && echo "$out" | grep -q "✓.*Activate does not re-fire while editing" && echo "$out" | grep -q "✓.*ButtonB cancels reverting to the snapshot" && echo "$out" | grep -q "✓.*ButtonA re-enters editing after a cancel" && echo "$out" | grep -q "✓.*registry to its baseline (incl. a mid-edit dispose)"',
			note = "text-entry mode raises a sinking nav context (priority 10000, above the modal band; Activate deliberately un-sunk — engine consumes Return natively, see WP2 decision 2); ButtonB cancel reverts to the edit-entry snapshot; desktop Escape arrives as adapter reason cancel (D1); mid-edit dispose tears the context down",
		},
		{
			name = "textinput-occlusion-keep-visible",
			requirements = { "UI-ENV-001", "UI-ADAPT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*mid-edit occlusion that overlaps the field produces an upward transform, restored on dismiss" && echo "$out" | grep -q "✓.*no occlusion offset when not editing"',
			note = "control consumes env keyboardOcclusionRect while editing; keep-visible dy rides the presentation authority (common.transform on the screen root) via presenter opts onGeometry/keepVisibleOffset; prop/transform writes only, zero factory reruns",
		},
		{
			name = "adapter-capability-detection",
			requirements = { "UI-STYLE-001", "UI-FID-001" },
			run = "test -f artifacts/studio/expansion-textinput-adapter.json && grep -q 'canSetTextInputType' src/client/screen_target.luau && grep -q 'ClearTextOnFocus' src/client/screen_target.luau && grep -q 'lastModelText' src/client/screen_target.luau && grep -q 'setTextInputHandlers' src/client/screen_target.luau && lune run tools/lune/check_boundary >/dev/null",
			evidence = "artifacts/studio/expansion-textinput-adapter.json",
			note = "TextField->TextBox in ScreenTarget only: capability-probed keyboardType (TextInputType RobloxScript-locked; degrades, declaration stays data), ClearTextOnFocus=false, single-line config (MultiLine/TextWrapped false per devforum 1014598), IME-safe value-based lastModelText echo guard (live drive caught the deferred-signal re-entrancy bug — see the artifact's RED run), Capture/ReleaseFocus via the editing binding with IsFocused guards; live-verified 2026-07-20 (raw-box probe of the exact adapter patterns)",
		},
		{
			name = "examples-upgraded",
			requirements = { "UI-AGENT-001", "UI-RUNTIME-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the numeric field is the primary affordance" && echo "$out" | grep -q "✓.*LIVE mode: typing a valid number updates the Celsius preview WITHOUT committing" && echo "$out" | grep -q "✓.*COMMIT mode: Enter commits the conversion into the Result" && echo "$out" | grep -q "✓.*focus loss (tapping away) also commits" && echo "$out" | grep -q "✓.*filter-as-you-type narrows the rows REACTIVELY" && echo "$out" | grep -q "✓.*in-field clear (✕) exists ONLY while the filter is non-empty" && echo "$out" | grep -q "✓.*typing in the filter field never navigates the table" && echo "$out" | grep -q "✓.*reordering is DISABLED while a filter is active" && echo "$out" | grep -q "✓.*pointer tap and touch tap each enter edit mode" && echo "$out" | grep -q "✓.*gamepad A enters edit mode, B cancels reverting"',
			note = "example 01: numeric TextInput is the sole primary affordance (steppers + Convert removed; live onChange preview vs committed onCommit Result; validate grammar ^-?%d*%.?%d*$); example 02: iTunes-style filter above the table (clear-only-when-non-empty, reactive filtering keeps mounted identity, reorder disabled under filter per iTunes/SwiftUI); per-input activation proven in both examples",
		},
		{
			name = "registration-and-docs",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_registration_cli && grep -q 'newTextInput' docs/reference/api.md && grep -q 'onFocusGained(path)' docs/reference/api.md && grep -q 'TextInput' docs/guide/04-tutorial-examples.md && grep -q 'BUILT (2026-07-20)' ui_todo.md",
			note = "registration checker green (api.md drift-checked both directions incl. UI.TextField + newTextInput); guide 04 walkthroughs teach live-vs-commit and the filter pattern; ui_todo §1 marked BUILT",
		},
		{
			name = "studio-drive-and-screenshots",
			requirements = { "UI-FID-001" },
			run = "test -f artifacts/studio/expansion-textinput-drive.json && grep -q 'ScreenCapture_ex01' artifacts/studio/expansion-textinput-drive.json && grep -q 'ScreenCapture_ex02_filtered' artifacts/studio/expansion-textinput-drive.json && grep -q '\"synced\"' artifacts/studio/expansion-textinput-drive.json",
			evidence = "artifacts/studio/expansion-textinput-drive.json",
			note = "2026-07-20 live drive: place re-synced to repo v0.4.0 (38 instances incl. 6 new modules), 11/11 drives pass (ex01 live-vs-commit + reject-reconcile; ex02 filter narrows/restores + clear ✕ visibility; edit_preview phone/tablet/desktop geometry), 6 screenshots (capture ids in the artifact; screen_capture has no disk sink); device-only riders recorded (real char-buffer typing, gamepad sink live, OSK occlusion); live-found clear-✕ trailing-alignment defect fixed post-drive with a red-first layout spec",
		},
		{
			name = "expansion-adr-bench-rollback",
			requirements = { "UI-AGENT-001", "UI-PERF-001" },
			run = "test -f docs/adr/ADR-0012-textinput-expansion.md && tools/bench.sh >/dev/null && grep -q 'textinput-typing-storm' artifacts/bench.json",
			evidence = "artifacts/bench.json",
			note = "ADR-0012 records the §17 Phase-5 expansion contract; textinput-typing-storm bench p50~0.05ms p95~0.10ms (2026-07-20), unpinned new scene per house pattern (table-resize-drag precedent)",
		},
		{
			name = "opus-verification",
			requirements = { "UI-AGENT-001" },
			run = "python3 tools/check_verdicts.py artifacts/expansion-textinput/platform-research.json=FINDINGS artifacts/expansion-textinput/runtime-verification.json=PASS artifacts/expansion-textinput/architecture-verification.json=PASS artifacts/expansion-textinput/phase-gate-verification.json=PASS",
			evidence = "artifacts/expansion-textinput/phase-gate-verification.json",
			note = "four fresh-context verifiers 2026-07-20: roblox-platform pre-implementation research (12 findings encoded before code — TextInputType CoreScript-only, ClearTextOnFocus trap, IME rewrite hazard); reactive-runtime PASS (F4 invalid-UTF-8 fixed, F1 escalated to real via WP3's native-focus truth and fixed cross-seam with onFocusGained(path), F3 documented); architecture PASS (ARCH-TI-1..4 resolved: settable-signal guard, dispose-mid-occlusion restore, comment/doc fixes; TI-5 info); phase-gate fresh-context audit",
		},
		{
			name = "physical-device-confirmation",
			requirements = { "UI-PERF-001", "UI-FID-001" },
			state = "FAIL_ENVIRONMENT",
			releaseBlocking = false,
			note = "physical phone/gamepad confirmation remains a pending release item (no device available to the autonomous build); never claimed",
		},
	},
	["phase-4-hardening"] = {
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 301",
			evidence = "artifacts/test.json",
			note = "301 at phase-4 close (176 at phase start); tools/test.sh asserts a minimum so a silently-unregistered spec cannot pass",
		},
		{
			name = "game-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1",
			note = "2404 at phase start; consumer surfaces must stay green through hardening",
		},
		{
			name = "old-settings-intact-and-default",
			requirements = { "UI-AGENT-001" },
			run = "test -f ../../../games/RascalRally/code/src/client/SettingsGui.luau && grep -q 'UseLuauUISettings' ../../../games/RascalRally/code/src/client/init.client.luau",
			note = "old Settings stays present and default (flag off) throughout Phase 4",
		},
		{
			name = "fuzz-scheduler",
			requirements = { "UI-RUNTIME-001", "UI-RUNTIME-003", "UI-LIFE-002" },
			run = "tools/fuzz.sh scheduler",
			evidence = "artifacts/phase-4/fuzz-scheduler.json",
			note = "400 seeded cases: glitch-free memo reads (incl. mid-transaction), observers fire on real change only (set-then-revert fires 0), registries at baseline after teardown; replay via LUAUUI_FUZZ_SEED",
		},
		{
			name = "fuzz-layout",
			requirements = { "UI-LAYOUT-001", "UI-LAYOUT-002" },
			run = "tools/fuzz.sh layout",
			evidence = "artifacts/phase-4/fuzz-layout.json",
			note = "400 random-tree cases + 60 adversarial: never throws, finite non-negative rects, deterministic re-solve, stack no-overlap, undefined dim combos diagnosed; found+fixed negative-size clamps (grid colW, stack crossAvail, inset>viewport contentRect)",
		},
		{
			name = "fuzz-replication",
			requirements = { "UI-REPL-001", "UI-REPL-002" },
			run = "tools/fuzz.sh replication",
			evidence = "artifacts/phase-4/fuzz-replication.json",
			note = "400 hostile-network cases: delay/dup/reorder/drop + gap->resnapshot recovery converge to authoritative state; mutation lifecycle legal, optimistic restore, send-while-pending refused",
		},
		{
			name = "fault-injection",
			requirements = { "UI-RUNTIME-003", "UI-LIFE-001", "UI-LIFE-002", "UI-INPUT-002", "UI-ENV-001" },
			run = "tools/faults.sh",
			evidence = "artifacts/phase-4/faults.json",
			note = "6 scenarios x 200 seeded iterations: async provider (cap/retry-generation/stale-rejection/cancel/cache-budget), teardown (dirty dispose, detected double-dispose, dispose-from-observer, quarantined runtime dup key), locale storms, garbage-a11y-fact clamps, input-switch storms; found+fixed presenter dismiss double-dispose and unguarded observer callbacks in flush",
		},
		{
			name = "virtualization-hardening",
			requirements = { "UI-RUNTIME-002", "UI-LIFE-002", "UI-FOCUS-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*mounts a bounded window" && echo "$out" | grep -q "✓.*same-window scroll delta is ZERO framework writes" && echo "$out" | grep -q "✓.*keep their mounted identity across a window slide" && echo "$out" | grep -q "✓.*off-window item BY KEY" && echo "$out" | grep -q "✓.*nearest surviving neighbor" && echo "$out" | grep -q "✓.*equals a fresh row.s dump" && echo "$out" | grep -q "✓.*late completion is stale" && echo "$out" | grep -q "✓.*registry at baseline after dispose"',
			note = "VirtualList (src/controls/virtual_list.luau): §10.5 first release — bounded window+overscan, keyed survivor identity, arrange-only same-window scroll, focus by item key w/ nearest-surviving-neighbor, no state bleed on re-entry, item-scope async cancellation w/ stale rejection, registry-neutral storms",
		},
		{
			name = "navigation-groups",
			requirements = { "UI-FOCUS-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*moves along the group axis" && echo "$out" | grep -q "✓.*wrap=false stops at the edge" && echo "$out" | grep -q "✓.*exit override crosses groups" && echo "$out" | grep -q "✓.*entry=.restore. returns" && echo "$out" | grep -q "✓.*containment blocks implicit exits" && echo "$out" | grep -q "✓.*falls through to the neighboring group" && echo "$out" | grep -q "✓.*modal trap keeps direction navigation" && echo "$out" | grep -q "✓.*nearest survivor" && echo "$out" | grep -q "✓.*legacy ring semantics"',
			note = "§9.3 NavigationGroups in the focus graph: axis-aware navigateDirection, per-group wrap, containment, entry policies (first/restore/nearest), per-direction exit overrides, array-order fallthrough, group-aware setGroupOrder/remove; flat scopes unchanged",
		},
		{
			name = "a11y-l10n-corpus",
			requirements = { "UI-ADAPT-001" },
			run = "lune run tests/conformance/corpus_cli",
			evidence = "artifacts/phase-4/a11y-l10n-corpus.json",
			note = "15 conformance checks over 6 l10n fixtures (pseudo-loc 1.385x, german-compound, thai-tall, CJK, emoji+combining, bidi-RTL w/ declared-fallback ledger) + a11y (text-size 1.0/1.3/2.0x, display-class effective targets 44/32, transparency, reduced motion, contrast incl. focus ring) + §15.3 contract checks; also folded into conformance-custom (41 checks) and the suite",
		},
		{
			name = "perf-runner-floor-suite",
			requirements = { "UI-PERF-001" },
			run = "tools/perf.sh",
			evidence = "artifacts/phase-4/perf.json",
			note = "controlled runner: 7 §14.3 scenes x 4 device profiles (floorAndroid 360x640 gates budgets from bench/perf_budgets.json, 4x-p95 headroom); full §14.3 record incl. per-phase p50/95/99, alloc/sec, heap slope, registry counters, dropped/stale async; deviceRun=false + empty on-device slot until the physical pass (trend-only per §14.3); re-baseline: tools/perf.sh baseline",
		},
		{
			name = "semver-and-deprecation",
			requirements = { "UI-AGENT-001" },
			run = 'test -f docs/adr/ADR-0011-semver-and-deprecation.md && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*VERSION is a plain semver" && echo "$out" | grep -q "✓.*semver/deprecation ADR exists" && echo "$out" | grep -q "✓.*machine-readable ledger"',
			note = "ADR-0011; VERSION 0.1.0-phase1 -> 0.4.0 (single source src/init.luau); LuauUI.DEPRECATIONS ledger with schema-enforced fields; spec cross-checks ADR names the current version",
		},
		{
			name = "error-boundaries",
			requirements = { "UI-RUNTIME-003" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*renders its view when healthy" && echo "$out" | grep -q "✓.*throwing view factory at mount swaps to the fallback" && echo "$out" | grep -q "✓.*structural rebuild that throws INSIDE the boundary" && echo "$out" | grep -q "✓.*boundary trips are registry-clean" && echo "$out" | grep -q "✓.*presents its declared fallback screen" && echo "$out" | grep -q "✓.*outside a boundary the mount-time hard-error contract"',
			note = "UI.ErrorBoundary (mount-level trip at mount AND runtime structural rebuilds; fallback errors stay hard; registry-clean) + presenter.presentCritical(fallbackScreen) for critical screens",
		},
		{
			name = "engine-styling-shadows-corners",
			requirements = { "UI-STYLE-001", "UI-FID-001" },
			run = 'test -f artifacts/studio/phase4-styling-fidelity.json && test -f docs/research/2026-07-20-uishadow-percorner-engine-facts.md && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*engine-true style data via the style authority" && echo "$out" | grep -q "✓.*token preset shadow resolves" && echo "$out" | grep -q "✓.*never enter layout" && echo "$out" | grep -q "✓.*alias form.*per-corner form" && echo "$out" | grep -q "✓.*resolve token names" && echo "$out" | grep -q "✓.*one spec is a build error" && echo "$out" | grep -q "✓.*negative only" && echo "$out" | grep -q "✓.*SwiftUI Group semantics" && echo "$out" | grep -q "✓.*container.s own surface" && echo "$out" | grep -q "✓.*style lint warns"',
			evidence = "artifacts/studio/phase4-styling-fidelity.json",
			note = "UI.shadow/UI.corners/UI.styleGroup modifiers (element/container/group) through tokens (default-style raised/overlay presets) + style authority (shadow/corners entries); engine-true shapes incl. BlurRadius-as-UDim + Spread-as-UDim2 corrections vs the spec text; one-form-per-node corner rule; style_lint jagged + >100-shadow budget; ScreenTarget materializes behind capability detection; live Studio probe 2026-07-20 confirmed all 13 facts",
		},
		{
			name = "maintainability-playbooks-and-checker",
			requirements = { "UI-AGENT-001" },
			run = 'lune run tools/lune/check_registration_cli && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*live repository passes every registration rule" && echo "$out" | grep -q "✓.*plans a complete control skeleton" && echo "$out" | grep -q "✓.*render-target adapter skeleton"',
			note = "4 playbooks (docs/extending/: control, engine feature, platform-capability/spatial extension contract with an explicit physical gate, render target); tools/lune/scaffold(+_cli) stamps source+failing-spec+runner/registry/export/api.md registrations; check_registration(+_cli) enforces control-registry completeness (incl. §10.2 dump surface), api.md drift BOTH directions, spec registration (silent-zero), playbook presence; uniform seams: Table + VirtualList gained dump()",
		},
		{
			name = "popup-button-dry-run",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/phase-4/popup-dryrun.json && test -f src/controls/popup_button.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*PopupButton" && lune run tools/lune/check_registration_cli',
			evidence = "artifacts/phase-4/popup-dryrun.json",
			note = "2026-07-20: fresh-context Opus agent, playbook only, shipped PopupButton end to end (suite 284->300, 14 spec cases, real api.md entry) with ZERO corrective interventions; it self-repaired 3 environment defects (scaffold anchor F1 — since fixed with sentinel + applyEdit regression test; a lead-dropped manifest brace; undocumented Grid) — full honesty ledger in the artifact",
		},
		{
			name = "documentation-and-examples",
			requirements = { "UI-AGENT-001" },
			run = 'test -f docs/guide/README.md && test -f docs/guide/01-concepts.md && test -f docs/guide/02-architecture.md && test -f docs/guide/03-getting-started.md && test -f docs/guide/04-tutorial-examples.md && test -f docs/guide/05-styling.md && test -f docs/guide/06-client-server.md && test -f docs/reference/api.md && ls examples/gallery/examples/01_temperature_converter.luau examples/gallery/examples/02_playlist_table.luau examples/gallery/examples/03_settings_sync.luau examples/gallery/examples/04_confirm_dialog.luau examples/gallery/examples/05_word_game.luau examples/gallery/examples/06_tile_game.luau examples/gallery/examples/07_match3.luau >/dev/null && ! grep -q "TODO" docs/guide/04-tutorial-examples.md && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*COMMIT mode: Enter commits the conversion into the Result" && echo "$out" | grep -q "✓.*the numeric field is the primary affordance" && echo "$out" | grep -q "✓.*filter-as-you-type narrows the rows REACTIVELY" && echo "$out" | grep -q "✓.*a valid toggle applies optimistically, goes pending, then confirms" && lune run tools/lune/check_registration_cli',
			note = "user guide (README + chapters 01-08, no internal shorthand, eight learning stages across seven runnable gallery files) (spec cases prove each runs headlessly; Studio: set workspace attr LuauUI_Example=1..7 in the gallery place) + api.md drift-checked both directions by check_registration; example-01 grep updated 2026-07-20 for the expansion-textinput rewrite (the old 'converts the entered Fahrenheit' case became the TextInput commit-mode case — phase-gate audit D1)",
		},
		{
			name = "specialist-docs-updated",
			requirements = { "UI-AGENT-001" },
			run = "grep -q 'Designing for LuauUI' ../../specialists/UI_DESIGNER.md && grep -q 'Building on LuauUI' ../../specialists/UI_ENGINEER.md && grep -q 'semantic' ../../specialists/UI_DESIGNER.md && grep -q 'docs/guide/README.md' ../../specialists/UI_ENGINEER.md",
			note = "§18 step 5 done 2026-07-20: UI_DESIGNER gained 'Designing for LuauUI' (primitives, semantic tokens, container policies, semantic actions, state boundaries, a11y/platform as declared intent) + woven pointers; UI_ENGINEER gained 'Building on LuauUI' (onboarding path, Rojo consumption never fork, adoption pace, six standing rules) + reconciliation of the one-framework rule",
		},
		{
			name = "opus-verification",
			requirements = { "UI-AGENT-001" },
			run = "python3 tools/check_verdicts.py artifacts/phase-4/opus-verification.json=ALL_REQUIREMENT_AFFECTING_FINDINGS_RESOLVED artifacts/phase-4/opus-runtime-verification.json=ALL_REQUIREMENT_AFFECTING_FINDINGS_RESOLVED artifacts/phase-4/opus-platform-research.json=ALL_REQUIREMENT_AFFECTING_FINDINGS_RESOLVED artifacts/phase-4/opus-architecture-verification.json=ALL_REQUIREMENT_AFFECTING_FINDINGS_RESOLVED artifacts/phase-4/opus-phase-gate-verification.json=ALL_REQUIREMENT_AFFECTING_FINDINGS_RESOLVED",
			evidence = "artifacts/phase-4/opus-verification.json",
			note = "four fresh-context Opus verifiers: reactive-runtime (7 findings incl. critical eq-wedge — all resolved), roblox-platform (2 spec-text corrections encoded pre-implementation + live Studio probe), architecture (5 findings — F1/F2/F3/F4 fixed, F5 deferred via deprecation ledger; separation/authority/containment PASS), phase-gate fresh-context audit incl. docs accuracy",
		},
		{
			name = "physical-device-confirmation",
			requirements = { "UI-PERF-001", "UI-FID-001" },
			state = "FAIL_ENVIRONMENT",
			releaseBlocking = false,
			note = "physical phone/gamepad confirmation remains a pending release item (no device available to the autonomous build); never claimed",
		},
	},
	["part-2-director"] = {
		{
			name = "ws1-table-phase-b-suite",
			requirements = { "UI-INPUT-001", "UI-RUNTIME-001" },
			run = "tools/test.sh 176 && ./run-tests.sh 2>&1 | grep -q '✓.*header taps cycle the owner-held sortOrder' && ./run-tests.sh 2>&1 | grep -q '✓.*per-column alignment positions cell content' && ./run-tests.sh 2>&1 | grep -q '✓.*columns own their cells' && ./run-tests.sh 2>&1 | grep -q '✓.*width sugar: a number is fixed px' && ./run-tests.sh 2>&1 | grep -q '✓.*grip drag previews a guide line and commits the width on release' && ./run-tests.sh 2>&1 | grep -q '✓.*ghost + indicator with the row IN PLACE' && ./run-tests.sh 2>&1 | grep -q '✓.*an invalid drop (outside the table) commits nothing' && ./run-tests.sh 2>&1 | grep -q '✓.*system interrupt (Roblox menu opened) aborts the drag' && ./run-tests.sh 2>&1 | grep -q '✓.*arrow navigation moves the SELECTION with focus' && ./run-tests.sh 2>&1 | grep -q '✓.*shift-click extends a contiguous range from the anchor' && ./run-tests.sh 2>&1 | grep -q '✓.*a focused grip resizes its column via the Adjust action' && ./run-tests.sh 2>&1 | grep -q '✓.*sinkNavigation stops nav keys' && ./run-tests.sh 2>&1 | grep -q '✓.*wraps at the edges'",
			evidence = "artifacts/test.json",
			note = "ADR-0008 seam + all four Phase B behaviors; revised per director hand-tests 2026-07-20 (rounds 1+2): row stays in place during drag (ghost+line affordance), post-removal slots, menu-open drag abort, Apple focus/selection model (click focuses, arrows select), focus wrap, sinkNavigation, cell insets",
		},
		{
			name = "ws1-pointer-seam-minimal-writes",
			requirements = { "UI-PERF-001", "UI-RUNTIME-001" },
			run = "./run-tests.sh 2>&1 | grep -q '✓.*Anchor overlay: a dynamic offset re-arranges with rect writes only'",
			note = "overlay guides move via arrange-only re-solve, rect writes only, no remount",
		},
		{
			name = "ws1-adr-and-bench",
			requirements = { "UI-AGENT-001", "UI-PERF-001" },
			run = "test -f docs/adr/ADR-0008-pointer-interaction-seam.md && tools/bench.sh && grep -q 'table-resize-drag' artifacts/bench.json",
			evidence = "artifacts/bench.json",
			note = "ADR-0008 recorded; table-resize-drag gesture benched vs baseline",
		},
		{
			name = "ws1-studio-drive",
			requirements = { "UI-FID-001" },
			run = 'python3 tools/check_spike.py artifacts/studio/part2-table-phaseb.json "plain mouse click replaces selection=PASS" "ctrl-click toggles into multi selection=PASS" "shift-click extends contiguous range=PASS" "grip drag=PASS" "row drag-and-drop=PASS" "keyboard focus navigation through real IAS bindings=PASS" && test -f docs/lessons/engine-input-truths-phaseb.md',
			evidence = "artifacts/studio/part2-table-phaseb.json",
			note = "2026-07-19 live: mouse resize preview+commit, drop indicator+reorder, ctrl/shift-click select, real-IAS keyboard nav (axis-sign fix), z-order + hover + inset defects found live and fixed; riders: keyboard-Adjust live re-drive (input channel wedged), shift-chord manual pass (virtual input never delivers them)",
		},
		{
			name = "ws2-edit-preview-harness",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 154 && ./run-tests.sh 2>&1 | grep -q '✓.*applying a profile re-renders an attached tree with rect writes only' && test -f src/client/edit_preview.luau && test -f src/preview/device_profiles.luau && test -f tools/studio/LuauUI_EditPreview.plugin.lua && test -f artifacts/studio/part2-edit-preview.json",
			evidence = "artifacts/studio/part2-edit-preview.json",
			note = "2026-07-19: real solver + ScreenTarget into StarterGui during Edit, 3 device presets live-re-solved via MCP (desktop/phone/tablet geometry verified programmatically), clean dispose; plugin installed to ~/Documents/Roblox/Plugins (loads on next Studio restart — rider); editor screenshot rider (capture channel wedged)",
		},
		{
			name = "ws3-billboard-target",
			requirements = { "UI-EXT-001" },
			run = "./run-tests.sh 2>&1 | grep -q '✓.*the FakeTarget satisfies every required and optional method' && ./run-tests.sh 2>&1 | grep -q '✓.*a billboard-sized pixel canvas renders a nameplate' && test -f src/client/billboard_target.luau && test -f src/render/target_contract.luau && test -f docs/adr/ADR-0009-billboard-target.md && grep -q 'billboard-nameplate-storm' artifacts/bench.json && test -f artifacts/studio/part2-billboard.json",
			evidence = "artifacts/studio/part2-billboard.json",
			note = "2026-07-19: root-swap over ScreenTarget (rootFactory seam); live Play drive verified offset canvas/Active/Clips/Adornee/PlayerGui + full runtime contract + solved rects + live binding update; bench p50 0.034ms; riders in the artifact",
		},
		{
			name = "ws4-game-table-surface",
			requirements = { "UI-AGENT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1 && ./run-tests.sh 2>&1 | grep -q '✓.*renders every racer headerless, in rank order, with custom cells' && ./run-tests.sh 2>&1 | grep -q '✓.*a position swap reorders rows without remounting them' && grep -q 'UseLuauUIRacerList' src/client/init.client.luau && test -f src/client/LuauUIRacerListScreen.luau && test -f ../../../GameStudio/ui/LuauUI/artifacts/studio/part2-racer-list.json",
			evidence = "artifacts/studio/part2-racer-list.json",
			note = "2026-07-19 commit 03e5541: racer list as the first Table consumer (headerless, reactive custom cells) behind UseLuauUIRacerList (default off, old SponsorRacerList untouched); game suite 2397; live drive in the REAL place against real RaceState (hidden-viewport rider)",
		},
		{
			name = "opus-verification",
			requirements = { "UI-AGENT-001" },
			run = 'python3 tools/check_verdicts.py artifacts/part-2/opus-verification.json=PASS "artifacts/part-2/opus-ws1-verification.json=ALL requirement-affecting findings resolved" "artifacts/part-2/opus-ws2-verification.json=ALL requirement-affecting findings resolved" "artifacts/part-2/opus-ws3-verification.json=ALL requirement-affecting findings resolved" "artifacts/part-2/opus-ws4-verification.json=ALL requirement-affecting findings resolved"',
			evidence = "artifacts/part-2/opus-verification.json",
			note = "four fresh-context Opus runs (one per workstream), 33 findings total, all requirement-affecting findings resolved with corrective tests/live drives before each workstream closed",
		},
	},
	["phase-3-pilot"] = {
		{
			name = "pilot-decision",
			requirements = { "UI-AGENT-001" },
			run = "python3 -c \"import json,sys; d=json.load(open('artifacts/decision-phase3-pilot.json')); t={x['id']:x['total'] for x in d['totals']}; sys.exit(0 if d['status']=='PASS' and d['winner']=='garage' and t['garage']==86 and t['card-management']==43 else 1)\" && test -f docs/adr/ADR-0005-phase3-pilot-selection.md",
			evidence = "artifacts/decision-phase3-pilot.json",
			note = "rubric-selected: garage 86 vs card-management 43 (pick-and-place is a deferred §9.4 pattern)",
		},
		{
			name = "game-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1",
			note = "2392 incl. the 8 'LuauUI garage pilot' specs",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 114",
			evidence = "artifacts/test.json",
		},
		{
			name = "all-interactions-reachable-across-bindings",
			requirements = { "UI-INPUT-001", "UI-FOCUS-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh 2>&1 | grep -q '✓.*every kart card is reachable by keyboard and by tap'",
			note = "keyboard ring walk covers all five cards; tap handlers on every card",
		},
		{
			name = "validated-mutation-flow",
			requirements = { "UI-REPL-002", "UI-SERVER-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh 2>&1 | grep -q '✓.*first pick grants and equips through the validated mutation' && cd ../../../games/RascalRally/code && ./run-tests.sh 2>&1 | grep -q '✓.*an invalid pick is rejected server-side and changes nothing'",
			note = "CarInventory validation both directions; reject changes nothing",
		},
		{
			name = "no-factory-rerun-in-pilot",
			requirements = { "UI-RUNTIME-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh 2>&1 | grep -q '✓.*labels repaint with zero factory reruns'",
		},
		{
			name = "multi-viewport-adaptation",
			requirements = { "UI-ADAPT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh 2>&1 | grep -q '✓.*adapts across viewports: cards fill width on phone and desktop'",
		},
		{
			name = "diagnosable-from-dumps",
			requirements = { "UI-DIAG-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh 2>&1 | grep -q '✓.*screen dumps are deterministic and diagnosable'",
		},
		{
			name = "no-leak-regression",
			requirements = { "UI-LIFE-002", "UI-PERF-001" },
			run = "(cd ../../../games/RascalRally/code && ./run-tests.sh 2>&1 | grep -q '✓.*open/close churn is registry-neutral') && tools/soak.sh && tools/bench.sh",
			evidence = "artifacts/bench.json",
			note = "pilot churn + library soak + bench vs baseline (no hitch/leak regression, headless trend)",
		},
		{
			name = "framework-defects-fixed-in-framework",
			requirements = { "UI-AGENT-001" },
			run = 'grep -q "fixed in the framework" docs/adr/ADR-0005-phase3-pilot-selection.md && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*cross-axis fill children stretch to the scroll viewport"',
			evidence = "docs/adr/ADR-0005-phase3-pilot-selection.md",
			note = "scroll cross-axis fill stretch fixed in solver during the pilot, not worked around",
		},
		{
			name = "opus-verification",
			requirements = { "UI-AGENT-001" },
			run = "python3 tools/check_verdicts.py artifacts/phase-3/opus-verification.json=PASS",
			evidence = "artifacts/phase-3/opus-verification.json",
			note = "fresh-context Opus run 2026-07-19: PASS; low findings F1/F2 + tightening all resolved (Grid wording, one-in-flight guard, library scroll-fill regression spec)",
		},
	},
	["phase-2-settings-parity"] = {
		{
			name = "game-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1",
			note = "full RascalRally suite (2384) incl. the 7 port parity specs",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 114",
			evidence = "artifacts/test.json",
		},
		{
			name = "behavior-parity-slice",
			requirements = { "UI-ADAPT-001", "UI-FOCUS-001", "UI-INPUT-004" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh 2>&1 | grep -q '✓.*renders title + both entries with whole-row touch targets and the capped panel' && ./run-tests.sh 2>&1 | grep -q '✓.*focus lands on the first entry; the scrim is never focusable'",
			note = "docs/LUAUUI_SETTINGS_PORT.md checklist; scrim/panel/rows/focus parity",
		},
		{
			name = "state-driven-repaint-no-rebuild",
			requirements = { "UI-RUNTIME-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh 2>&1 | grep -q '✓.*toggling reduced motion repaints from STATE without any rebuild or remount'",
			note = "the declaration-clearer win: zero factory reruns where the old gui rebuilt every row",
		},
		{
			name = "open-close-memory-neutral",
			requirements = { "UI-LIFE-002" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh 2>&1 | grep -q '✓.*open/close churn is registry-neutral'",
		},
		{
			name = "touch-and-action-paths",
			requirements = { "UI-INPUT-001", "UI-INPUT-003" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh 2>&1 | grep -q '✓.*tap-outside (scrim) activates close routing'",
			note = "tap path and keyboard Activate both route the same semantic command",
		},
		{
			name = "multi-viewport-adaptation",
			requirements = { "UI-ADAPT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh 2>&1 | grep -q '✓.*panel width tracks narrow phones below the cap'",
		},
		{
			name = "replication-convergence-carryover",
			requirements = { "UI-REPL-001", "UI-REPL-002" },
			run = "./run-tests.sh 2>&1 | grep -q '✓.*an optimistic view reconciled on snapshot ingest converges regardless of delivery order'",
			evidence = "artifacts/test.json",
			note = "the port's persistence seam is the device-proven attribute round-trip; library convergence suite covers the adapters",
		},
		{
			name = "old-settings-intact-and-default",
			requirements = { "UI-AGENT-001" },
			run = "test -f ../../../games/RascalRally/code/src/client/SettingsGui.luau && grep -q 'settingsGui = SettingsGui.new(player)' ../../../games/RascalRally/code/src/client/init.client.luau && grep -q 'UseLuauUISettings' ../../../games/RascalRally/code/src/client/init.client.luau",
			note = "old file untouched; flag default-off keeps the old path; port constructs only on opt-in",
		},
		{
			name = "ui-cost-budget",
			requirements = { "UI-PERF-001" },
			run = "tools/bench.sh",
			evidence = "artifacts/bench.json",
			note = "mounted-slice storm p95 ~0.1ms headless (trend); device budget check rides the device-confirmation pass",
		},
		{
			name = "port-doc-and-rollback",
			requirements = { "UI-AGENT-001" },
			run = 'f=../../../games/RascalRally/docs/LUAUUI_SETTINGS_PORT.md && test -f "$f" && grep -q "^## Behavior checklist" "$f" && grep -q "^## Code and complexity comparison" "$f" && grep -q "^## Defect log" "$f" && grep -q "^## Rollback and old-path deletion criteria" "$f"',
			evidence = "../../../games/RascalRally/docs/LUAUUI_SETTINGS_PORT.md",
			note = "checklist, comparison, defect log (D1 Escape-binding decision pending device), rollback + deletion criteria",
		},
		{
			name = "studio-port-run",
			requirements = { "UI-FID-001" },
			run = "python3 tools/check_spike.py artifacts/studio/phase2-port-drive.json flag-gating=PASS gear-topbar-dock=PASS modal-render=PASS real-mouse=PASS real-keyboard-activate=PASS server-persistence-roundtrip=PASS D1-escape=RESOLVED",
			evidence = "artifacts/studio/phase2-port-drive.json",
			note = "RESOLVED 2026-07-19 later session: full flagged-port drive in the real place (gear/modal/toggle/server-persistence/scrim-close) + D1 decided (Escape engine-core-reserved -> Cancel=ButtonB)",
		},
		{
			name = "opus-verification",
			requirements = { "UI-AGENT-001" },
			run = "python3 tools/check_verdicts.py artifacts/phase-2/opus-verification.json=PASS",
			evidence = "artifacts/phase-2/opus-verification.json",
			note = "fresh-context Opus run 2026-07-19: PASS; low findings F-1/F-2/F-3 all resolved (D4/D5 doc + re-entrant-dismiss spec)",
		},
	},
	["phase-1-minimal-screen"] = {
		{
			name = "doctor",
			requirements = { "UI-AGENT-001" },
			run = "tools/doctor.sh",
			evidence = "artifacts/doctor.json",
		},
		{
			name = "test-suite",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 114",
			evidence = "artifacts/test.json",
		},
		{
			name = "client-boundary-static",
			requirements = { "UI-BOUND-001" },
			run = "lune run tools/lune/check_boundary",
			evidence = "artifacts/boundary.json",
		},
		{
			name = "settings-subset-multi-input",
			requirements = { "UI-INPUT-001", "UI-INPUT-002" },
			run = "./run-tests.sh 2>&1 | grep -q '✓.*one action carries keyboard, touch, and gamepad bindings simultaneously'",
			evidence = "artifacts/test.json",
			note = "kb/touch/gamepad bindings on one semantic action; engine kb path proven live (artifacts/studio/phase1-gallery.json)",
		},
		{
			name = "two-clients-independent-layouts",
			requirements = { "UI-ADAPT-001", "UI-SERVER-001" },
			run = "./run-tests.sh 2>&1 | grep -q '✓.*independent environments and presentation state converge' && tools/render.sh",
			evidence = "artifacts/render/summary.json",
			note = "two-client convergence test + phone/desktop dump fixtures from one blueprint",
		},
		{
			name = "authoritative-mutation-slice",
			requirements = { "UI-REPL-002" },
			run = "./run-tests.sh 2>&1 | grep -q '✓.*toggle + save + delayed server confirm reconciles cleanly'",
			evidence = "artifacts/test.json",
			note = "UI-driven mutation validates/replicates/reconciles; live engine run in artifacts/studio/phase1-gallery.json",
		},
		{
			name = "no-permanent-pending-or-divergence",
			requirements = { "UI-REPL-001", "UI-REPL-002" },
			run = "./run-tests.sh 2>&1 | grep -q '✓.*rejection restores the draft; no permanent pending state'",
			evidence = "artifacts/test.json",
		},
		{
			name = "modal-context-priority-sink-disposal",
			requirements = { "UI-INPUT-004", "UI-FOCUS-001" },
			run = "./run-tests.sh 2>&1 | grep -q '✓.*a modal sinks navigation from the base screen and traps focus' && ./run-tests.sh 2>&1 | grep -q '✓.*Cancel dismisses the modal, restores focus, and disposes its context'",
			evidence = "artifacts/test.json",
		},
		{
			name = "preferred-input-affordance-no-remount",
			requirements = { "UI-INPUT-002" },
			run = "./run-tests.sh 2>&1 | grep -q '✓.*preferredInput flip updates the hint text prop only; zero factory reruns'",
			evidence = "artifacts/test.json",
			note = "the ADR-0004 phase-1 obligation",
		},
		{
			name = "churn-registry-neutral",
			requirements = { "UI-LIFE-002" },
			run = "tools/soak.sh",
			evidence = "artifacts/soak/summary.json",
			note = "200x modal churn + 100x ForEach structural churn to baseline",
		},
		{
			name = "no-factory-rerun-trace",
			requirements = { "UI-RUNTIME-001" },
			run = "./run-tests.sh 2>&1 | grep -q '✓.*a non-structural prop change dirties ONLY its node' && test -f artifacts/studio/phase1-gallery.json",
			evidence = "artifacts/studio/phase1-gallery.json",
			note = "headless dirty-trace + live factoryRuns=7 held through full engine interaction",
		},
		{
			name = "engine-fidelity",
			requirements = { "UI-FID-001" },
			run = 'python3 tools/check_spike.py artifacts/studio/phase1-gallery.json engine-string-requires=PASS client-bootstrap=PASS real-inputaction-slice=PASS live-env-adaptation=PASS screengui-policy=PASS && grep -q "size=true pos=true" artifacts/studio/engine-fidelity.json',
			evidence = "artifacts/studio/phase1-gallery.json",
			note = "phase-0 differential + live phase-1 slice through real InputActions and ScreenTarget, asserted by ROW: the five live checks must still be recorded PASS and the fidelity spike must still record its exact rect match. Both used to be `test -f` (gate-integrity sweep 2026-07-29, defect B-9) — truncating either artifact to {} left this green. The two FAIL_ENVIRONMENT rows in phase1-gallery (real-key drive, screenshot) are deliberately NOT asserted: they are honestly unmet, and the separate gallery-visible-viewport-checks row carries that story",
		},
		{
			name = "bench-reproducible",
			requirements = { "UI-PERF-001" },
			run = "tools/bench.sh",
			evidence = "artifacts/bench.json",
			note = "13 scenarios incl. mounted-slice-update-storm vs pinned baseline; headless trend only, device authoritative",
		},
		{
			name = "gallery-visible-viewport-checks",
			requirements = { "UI-FID-001" },
			run = "python3 tools/check_spike.py artifacts/studio/phase2-port-drive.json real-mouse=PASS real-keyboard-activate=PASS modal-render=PASS",
			evidence = "artifacts/studio/phase2-port-drive.json",
			note = "RESOLVED 2026-07-19 later session: real-key drive + screenshot performed in the REAL RascalRally place with a visible viewport (superset of the gallery check)",
		},
		{
			name = "opus-verification",
			requirements = { "UI-AGENT-001" },
			run = "python3 tools/check_verdicts.py artifacts/phase-1/opus-verification.json=PASS && test -f tests/focus_structural.spec.luau",
			evidence = "artifacts/phase-1/opus-verification.json",
			note = "fresh-context Opus phase-gate run 2026-07-19: PASS; advisory findings F1 (focus-ring structural sync) and F2 (confirm-before-ingest contract) RESOLVED with corrective tests",
		},
	},
	["phase-0-foundation"] = {
		{
			name = "doctor",
			requirements = { "UI-AGENT-001" },
			run = "tools/doctor.sh",
			evidence = "artifacts/doctor.json",
		},
		{
			name = "test-suite",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 54",
			evidence = "artifacts/test.json",
		},
		{
			name = "conformance-custom-core",
			requirements = { "UI-RUNTIME-001", "UI-RUNTIME-002", "UI-RUNTIME-003", "UI-LIFE-001", "UI-LIFE-002" },
			run = "lune run tests/conformance/cli custom --require-all-pass",
			evidence = "artifacts/conformance-custom.json",
			note = "suite + micro-screens; the selected core must pass everything",
		},
		{
			name = "conformance-fusion-adapter",
			requirements = { "UI-RUNTIME-001", "UI-RUNTIME-002", "UI-RUNTIME-003", "UI-LIFE-001", "UI-LIFE-002" },
			run = "lune run tests/conformance/cli fusion",
			evidence = "artifacts/conformance-fusion.json",
			note = "identical suite; scorecard feeds the rubric (need not fully pass)",
		},
		{
			name = "conformance-imperative-baseline",
			requirements = { "UI-RUNTIME-001", "UI-RUNTIME-002", "UI-RUNTIME-003", "UI-LIFE-001", "UI-LIFE-002" },
			run = "lune run tests/conformance/cli imperative",
			evidence = "artifacts/conformance-imperative.json",
			note = "identical suite; scorecard feeds the rubric (need not fully pass)",
		},
		{
			name = "layout-spike",
			requirements = { "UI-LAYOUT-001", "UI-DIAG-001" },
			-- COMMENTS ARE NOT CALLS (2026-07-26). The guard exists to keep a
			-- YIELDING call out of the solver; it was a bare grep, so the moment
			-- director round 9 explained the engine's GetTextBoundsAsync reporting
			-- grid in a text_metrics COMMENT the phase went red for prose. The
			-- second grep drops lines whose content is a comment and nothing else,
			-- which is the only false positive this pattern can have — a real call
			-- with a trailing comment still has code before the `--`.
			run = "test -z \"$(grep -rEn 'task\\.wait|task\\.delay|:Wait\\(|coroutine\\.yield|GetTextBoundsAsync' src/layout/ | grep -vE ':[0-9]+:[[:space:]]*--')\" && tools/render.sh",
			evidence = "artifacts/render/summary.json",
			note = "tests/layout.spec.luau + double-run-deterministic dump fixtures + static no-yield guard on src/layout",
		},
		{
			name = "replication-boundary-spike",
			requirements = { "UI-REPL-001", "UI-REPL-002", "UI-ADAPT-001", "UI-SERVER-001" },
			run = "./run-tests.sh 2>&1 | grep -q '✓.*independent environments and presentation state converge'",
			evidence = "artifacts/test.json",
			note = "tests/replication.spec.luau: stale/dup/gap/reject convergence + two-client independence",
		},
		{
			name = "client-boundary-static",
			requirements = { "UI-BOUND-001" },
			run = "lune run tools/lune/check_boundary",
			evidence = "artifacts/boundary.json",
			note = "require-graph scan: client renderer unreachable from non-client code",
		},
		{
			name = "property-authority-spike",
			requirements = { "UI-STYLE-001" },
			run = 'python3 tools/check_spike.py artifacts/studio/property-authority-spike.json explicit-write-defeats-style style-application-is-signal-silent && grep -q "silently and permanently defeats the stylesheet" artifacts/studio/property-authority-spike.json',
			evidence = "artifacts/studio/property-authority-spike.json",
			note = "Studio-verified 2026-07-19: explicit writes defeat StyleRules silently; authority manifest must be framework-enforced",
		},
		{
			name = "input-action-spike",
			requirements = { "UI-INPUT-001", "UI-INPUT-003", "UI-INPUT-004" },
			run = "python3 tools/check_spike.py artifacts/studio/ias-spike.json api-surface=PASS fire-requires-scriptable=PASS real-input-priority-sink=PASS scriptable-fire-bypasses-arbitration=PASS_WITH_DESIGN_IMPACT context-disposal-disconnects=PASS && test -f docs/adr/ADR-0004-input-verification-scope.md",
			evidence = "artifacts/studio/ias-spike.json",
			note = "Studio-verified 2026-07-19 incl. real-input sink test; PASS with named deviation: scriptable Fire bypasses arbitration -> split harness per ADR-0004; UI-INPUT-002 deferred to phase-1 (ADR-0004)",
		},
		{
			name = "modal-focus-spike",
			requirements = { "UI-FOCUS-001" },
			run = "./run-tests.sh 2>&1 | grep -q '✓.*modal traps navigation with wrap and restores previous focus'",
			evidence = "artifacts/test.json",
			note = "tests/focus.spec.luau: trap wrap, LIFO restoration, surviving-neighbor policy (engine selection half lives in the Studio spike)",
		},
		{
			name = "engine-fidelity-fixtures",
			requirements = { "UI-FID-001", "UI-DIAG-001" },
			run = 'grep -q "size=true pos=true" artifacts/studio/engine-fidelity.json && grep -q "fits=true" artifacts/studio/engine-fidelity.json && grep -q "declaredTolerance" artifacts/studio/engine-fidelity.json',
			evidence = "artifacts/studio/engine-fidelity.json",
			note = "Studio-verified 2026-07-19: dump rects applied exactly; text fits reserved rects; calibration table + declared tolerance recorded",
		},
		{
			name = "worldtarget-seam",
			requirements = { "UI-EXT-001" },
			run = "test -f docs/adr/ADR-0003-worldtarget-deferral.md",
			evidence = "docs/adr/ADR-0003-worldtarget-deferral.md",
			note = "explicitly deferred per design §13/§17 automatic fallback; ADR-0003",
		},
		{
			name = "foundation-decision",
			requirements = { "UI-AGENT-001" },
			run = "python3 -c \"import json,sys; d=json.load(open('artifacts/decision-foundation.json')); t={x['id']:x['total'] for x in d['totals']}; sys.exit(0 if d['status']=='PASS' and d['winner']=='custom' and t['custom']==144 and t['custom']>max(t['imperative'],t['fusion']) else 1)\" && test -f docs/adr/ADR-0002-foundation-core-selection.md",
			evidence = "artifacts/decision-foundation.json",
			note = "rubric evaluated via tools/decision.sh; ADR-0002 selected the custom core",
		},
		{
			name = "opus-verification",
			requirements = { "UI-AGENT-001" },
			run = "python3 tools/check_verdicts.py artifacts/phase-0/opus-verification.json=PASS && test -f docs/research/2026-07-19-runtime-verifier-findings-resolution.md && test -f docs/adr/ADR-0004-input-verification-scope.md",
			evidence = "artifacts/phase-0/opus-verification.json",
			note = "two fresh-context Opus runs (reactive-runtime pre-gate; phase-gate full audit) 2026-07-19; all requirement-affecting findings resolved (see artifact)",
		},
	},
	["native-substrate"] = {
		-- Roadmap Step 1 (docs/plans/luauui-consolidated-roadmap.md): adopt
		-- Roblox-native mechanisms per the corrected audit while every
		-- deterministic framework decision stays headlessly testable.
		-- Acceptance ledger: artifacts/native-substrate/acceptance-ledger.md.
		-- KEEP HONEST: checks flip from PENDING only when the implementation
		-- and its evidence artifact exist (contract: fable-execution-contract.md).
		{
			name = "docs-grounding",
			requirements = {
				"UI-NATIVE-001",
				"UI-NATIVE-002",
				"UI-NATIVE-003",
				"UI-NATIVE-004",
				"UI-NATIVE-005",
				"UI-NATIVE-006",
				"UI-NATIVE-007",
				"UI-NATIVE-008",
			},
			run = 'test -f docs/research/2026-07-23-native-adoption-docs-grounding.md && grep -q "fetched 2026-07-23" docs/research/2026-07-23-native-adoption-docs-grounding.md && grep -qi "UIDragDetector" docs/research/2026-07-23-native-adoption-docs-grounding.md && grep -qi "GetInsetArea" docs/research/2026-07-23-native-adoption-docs-grounding.md && grep -qi "PreloadAsync" docs/research/2026-07-23-native-adoption-docs-grounding.md',
			evidence = "docs/research/2026-07-23-native-adoption-docs-grounding.md",
			note = "NS-M0: every platform claim grounded in current official docs fetched this run; 7 disagreements flagged (2 confirmed live in spikes: no Path2D.Transparency, no ImageLabel.LoadingImageFailed)",
		},
		{
			name = "feasibility-matrix",
			requirements = {
				"UI-NATIVE-001",
				"UI-NATIVE-002",
				"UI-NATIVE-003",
				"UI-NATIVE-004",
				"UI-NATIVE-005",
				"UI-NATIVE-006",
				"UI-NATIVE-007",
				"UI-NATIVE-008",
			},
			run = 'for f in m1-scroll-host m2-canvas-window m3-dragdetector m4-touch-events m5-path2d m6-pagelayout m7-preferred-text m8-safe-area m9-selection-bridge m10-preload; do test -f "artifacts/native-substrate/feasibility/$f.json" || exit 1; grep -q "luauui-studio-spike/1" "artifacts/native-substrate/feasibility/$f.json" || exit 1; done && grep -q "only supports 100 control points" artifacts/native-substrate/feasibility/m5-path2d.json && grep -q "CustomOffset" artifacts/native-substrate/feasibility/m3-dragdetector.json && grep -q "AssetFetchStatus.Failure" artifacts/native-substrate/feasibility/m10-preload.json',
			evidence = "artifacts/native-substrate/feasibility/m1-scroll-host.json",
			note = "NS-M1..M10: ten Studio spikes with machine evidence (luauui-studio-spike/1), keyed to ledger rows; environment-limited sub-checks recorded honestly inside each artifact",
		},
		{
			name = "verification-surface",
			requirements = { "UI-AGENT-001" },
			run = 'test -f examples/gallery/scenarios/init.luau && test -f examples/gallery/scenarios/runner.luau && test -f examples/gallery/scenarios/probe.luau && test -f tools/lune/studio_sync.luau && test -f tools/studio/inject.luau && grep -q "LuauUI_Scenario" examples/gallery/client/init.client.luau && test -f artifacts/native-substrate/verification-surface-probe.json && grep -q "luauui-scenario/1" artifacts/native-substrate/verification-surface-probe.json && test -f docs/lessons/mcp-vm-isolation-bindablefunction-bridge.md',
			evidence = "artifacts/native-substrate/verification-surface-probe.json",
			note = "contract §5 scenario surface LIVE-PROVEN 2026-07-23: probe scenario mounted through the real presenter in Play, driven via workspace.LuauUIScenarioAPI BindableFunctions (list/steps/step/report/reset/freezeEnv), report carries stamp+env+geometry+focus; sync server tools/lune/studio_sync + injector tools/studio/inject.luau",
		},
		{
			name = "safe-area-adoption",
			requirements = { "UI-NATIVE-005", "UI-ENV-001" },
			run = 'test -f artifacts/native-substrate/a1-safe-area.json && grep -q "GetInsetArea" src/client/roblox_env.luau && grep -q "deviceSafeInsets" src/client/roblox_env.luau && grep -q "deviceSafeContent" src/render/renderer.luau && grep -q "phoneNotchLandscape" src/preview/device_profiles.luau && grep -q "deviceSafeContent insets the content rect" tests/renderer.spec.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*per-edge MAX of core and device insets" && echo "$out" | grep -q "✓.*phoneNotchLandscape pushes deviceSafeInsets"',
			evidence = "artifacts/native-substrate/a1-safe-area.json",
			note = "NS-A1 LIVE-PROVEN 2026-07-23: GetInsetArea four-edge facts (core+device), deviceSafeContent = per-edge max, single authority (IgnoreGuiInset=true + solver facts), live notch-injection re-solve + reversal in scenario safe_area; hardware notch values remain NS-P2",
		},
		{
			name = "scroll-host-adoption",
			requirements = { "UI-NATIVE-001" },
			run = 'test -f artifacts/native-substrate/a2-scroll-host.json && grep -q "ScrollView = \\"ScrollingFrame\\"" src/client/screen_target.luau && grep -q "setScrollRegion" src/client/screen_target.luau && grep -q "observeScroll" src/client/screen_target.luau && grep -q "forceScrollFallback" src/client/billboard_target.luau && grep -q "setScrollRegion" src/render/target_contract.luau && grep -q "scrollTo" src/render/renderer.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*sends its solved content extent as the scroll region" && echo "$out" | grep -q "✓.*FALLBACK: an adapter without the scroll seam"',
			evidence = "artifacts/native-substrate/a2-scroll-host.json",
			note = "NS-A2 LIVE-PROVEN 2026-07-23: real wheel moved the native canvas (0->300) on a running LuauUI ScrollView, programmatic clamp 476, captures paired with geometry; fallback (Frame clip-only) exercised separately live + headless; billboard stays fallback until proven",
		},
		{
			name = "table-virtuallist-migration",
			requirements = { "UI-NATIVE-001" },
			run = 'test -f artifacts/native-substrate/a4-virtuallist.json && test -f artifacts/native-substrate/a3-table.json && grep -q "bindNativeScroll" src/controls/virtual_list.luau && grep -q "bindNativeScroll" src/controls/table.luau && grep -q "bindNativeScroll" examples/gallery/client/init.client.luau && ! grep -q "onScrollWheel" src/controls/virtual_list.luau && ./tools/test.sh 655 >/dev/null',
			evidence = "artifacts/native-substrate/a4-virtuallist.json",
			note = "NS-A3/NS-A4 LIVE-PROVEN 2026-07-23: 72k canvas over 14 mounted rows, real-wheel window slide, keep-visible 53640 exact; Table body native in example 02 with behaviors intact; hand-rolled wheel/pan/offset-parking deleted; windowing pure",
		},
		{
			name = "drag-touch-adoption",
			requirements = { "UI-NATIVE-002", "UI-NATIVE-003" },
			run = 'test -f artifacts/native-substrate/a5-drag.json && test -f src/input/drag_session.luau && test -f src/input/touch_gestures.luau && grep -q "setDragDetector" src/client/screen_target.luau && grep -q "setTouchGestureHandlers" src/client/screen_target.luau && test -f docs/lessons/uidragdetector-event-truths.md && ./tools/test.sh 655 >/dev/null',
			evidence = "artifacts/native-substrate/a5-drag.json",
			note = "NS-A5/NS-A6 LIVE-PROVEN 2026-07-23: native detector drop/reject/cancel + separate pointer-fallback run over the same pure session (25 headless model tests); Vector2/space engine truth recorded; touch firing physical",
		},
		{
			name = "path2d-pagelayout",
			requirements = { "UI-NATIVE-004" },
			run = 'test -f artifacts/native-substrate/a7-path.json && test -f docs/adr/ADR-0017-native-substrate-adoption.md && grep -q "REJECTED" docs/adr/ADR-0017-native-substrate-adoption.md && test -f src/controls/path_shapes.luau && grep -q "class(\\"Path\\"" src/blueprint_schema.luau && grep -q "blueprint.Path" src/blueprint.luau && grep -q "applyPathPoints" src/client/screen_target.luau && grep -q "pathShapes" docs/reference/api.md && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a full ring closes" && echo "$out" | grep -q "✓.*a points change is one prop write and never a re-solve"',
			evidence = "artifacts/native-substrate/a7-path.json",
			note = "NS-A7 LIVE-PROVEN + NS-A8 decided 2026-07-23: three Path2D strokes in the running gauge, bound-progress sweep matches pure math (last CP 24,137 == prediction), paint-only reactive; UIPageLayout rejected with measured authority-conflict evidence (ADR-0017 §3)",
		},
		{
			name = "preferred-text-single-application",
			requirements = { "UI-NATIVE-006", "UI-FID-001" },
			run = 'test -f artifacts/native-substrate/a9-preferred-text.json && test -f artifacts/native-substrate/a10-text-cal.json && grep -q "typographyPaintScale" src/env/environment.luau && grep -q "typographyPaintScale" src/render/renderer.luau && grep -q "calibrate" src/layout/text_metrics.luau && test -f src/client/text_calibration.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*scales MEASUREMENT (reserved bounds) but never the painted TextSize" && echo "$out" | grep -q "✓.*a calibrated fraction tightens the estimate and never widens it"',
			evidence = "artifacts/native-substrate/a9-preferred-text.json",
			note = "NS-A9/NS-A10 LIVE-PROVEN 2026-07-23: measure/paint seams split (reserved 44->63 vs painted 18 under injected pref); real GetTextBoundsAsync calibration (0.367-0.451 vs 0.62) tighten-only clamped, corpus never clips; engine pref sweep = assisted review-packet row",
		},
		{
			name = "selection-policy",
			requirements = { "UI-NATIVE-007" },
			run = 'test -f artifacts/native-substrate/a12-bridge.json && grep -q "engineSelectionBridge" src/present/presenter.luau && grep -q "setEngineSelection" src/client/screen_target.luau && grep -q "setEngineSelection" src/render/target_contract.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*default surfaces never touch engine selection" && echo "$out" | grep -q "✓.*an opted-in modal mirrors logical focus and clears on dismiss" && echo "$out" | grep -q "✓.*IGNORES the opt (bridge is modal-only)"',
			evidence = "artifacts/native-substrate/a12-bridge.json",
			note = "NS-A11/NS-A12 Studio part LIVE-PROVEN 2026-07-23: base nil, opt-in modal mirror follows focus w/ Selectable handling per spike m9, native autoscroll observed (canvas 0->236), teardown clears; physical-pad contract row stays NS-P1 (FAIL_ENVIRONMENT check below)",
		},
		{
			name = "resource-transport",
			requirements = { "UI-NATIVE-008" },
			run = 'test -f artifacts/native-substrate/a13-resources.json && test -f artifacts/native-substrate/a14-image.json && test -f src/client/roblox_resources.luau && test -f src/controls/async_image.luau && grep -q "PreloadAsync" src/client/roblox_resources.luau && grep -q "newAsyncImage" docs/reference/api.md && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*release-then-stale-completion never resurrects"',
			evidence = "artifacts/native-substrate/a13-resources.json",
			note = "NS-A13/NS-A14 LIVE-PROVEN 2026-07-23: real PreloadAsync statuses (avatars ready, bad asset failed), stale completion rejected after release, no in-flight-stop claim; AsyncImage visuals from real signals",
		},
		{
			name = "keep-visible-consolidation",
			requirements = { "UI-LAYOUT-001" },
			run = 'grep -q "function solver.keepVisibleOffset" src/layout/solver.luau && grep -q "keepVisibleOffset" src/render/renderer.luau && grep -q "keepVisibleOffset" src/controls/virtual_list.luau && grep -q "keepVisibleOffset" src/controls/table.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*all three consumers call it — no second implementation survives" && echo "$out" | grep -q "✓.*the renderer.s substrate and the index path agree on the same geometry" && echo "$out" | grep -q "✓.*returns nil rather than a no-op scroll" && test -f artifacts/authoring-adaptive-ui/a-sv2-substrate-consolidation.json',
			evidence = "artifacts/authoring-adaptive-ui/a-sv2-substrate-consolidation.json",
			note = "A-SV2 delivered, though NOT as the row was worded: `scrollToVisible` reads a solved rect and a virtualized/culled row has none, so VirtualList and Table were never duplicating the substrate — they serve the case it cannot. What they DID duplicate three times was the minimum-distance clamp, now `solver.keepVisibleOffset` with all three consumers checked by source and an equivalence test proving the rect- and index-derived paths agree",
		},
		{
			name = "write-once-and-recipes",
			requirements = { "UI-LAYOUT-001" },
			run = 'test -f artifacts/authoring-adaptive-ui/a-al4-a-lv4-writeonce.json && grep -q "Toolbar" examples/gallery/scenarios/adaptive_controls.luau && grep -q "aspectRatio" examples/gallery/scenarios/adaptive_controls.luau && grep -q "badgedTile" examples/gallery/scenarios/adaptive_controls.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*derives the height from the RESOLVED fill width, not from zero" && echo "$out" | grep -q "✓.*the wrapper inherits the base.s dimensions" && echo "$out" | grep -q "✓.*a grid cell derives its aspect from the derived column width"',
			evidence = "artifacts/authoring-adaptive-ui/a-al4-a-lv4-writeonce.json",
			note = "A-AL4/A-LV4: ONE semantic tree now carries BOTH a settings surface and a genuinely dense HUD (toolbar, 16:9 media, a 12-tile derived-column readout grid, badged tiles), and every shape the recipe row lists is fixtured with no manual pixel positioning. The fixture found TWO real defects — aspectRatio produced ZERO height against a fill sibling, and overlay collapsed its base to the badge width — both fixed with regressions and confirmed live. Preferred-text sweep and captures for the two new surfaces remain owed",
		},
		{
			name = "headless-suite-preserved",
			requirements = { "UI-RUNTIME-001" },
			run = "./tools/test.sh 655",
			evidence = "artifacts/test.json",
			note = "NS-I1: post-adoption suite minimum 655 (baseline 595); windowing/geometry/focus/provider assertions intact; offset-arithmetic tests replaced by canvas-mirror conformance per plan",
		},
		{
			name = "game-suite-unchanged",
			requirements = { "UI-NATIVE-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1",
			evidence = "artifacts/native-substrate/game-suite.txt",
			note = "NS-I3: the RascalRally suite is RUN here, the same string eight sibling gates use. It used to grep a stored game-suite.txt for `2404 passed` and execute nothing (gate-integrity sweep 2026-07-29, defect B-2) — and the pinned 2404 had gone stale besides, the game suite being 2425 at the current source, so the check was reading a transcript of a suite that no longer exists. The `dirty count 0` half is NOT re-proved here: it is a historical git-porcelain observation from 2026-07-23 and stays in the evidence file as a record, because the game tree legitimately carries unrelated dirty files between sessions",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = 'if [ -n "${LUAUUI_PRIOR_GATES_NESTED:-}" ]; then echo "prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)"; exit 0; fi; a=artifacts/native-substrate/prior-gates-rerun.txt && tools/prior_gates.sh "$a" native-substrate && grep -q "^DONE$" "$a" && failed="$(grep "^FAIL " "$a" || true)" && test -z "$failed"',
			evidence = "artifacts/native-substrate/prior-gates.txt",
			note = "NS-I4: all 9 prior gates RE-RUN by this check at the source being judged, via tools/prior_gates.sh (list derived from phases.json), writing artifacts/native-substrate/prior-gates-rerun.txt. It used to grep the STORED prior-gates.txt for the phrase `FINAL: 9/9 prior gates PASS` and execute nothing — the identical can't-ever-fail shape verifier PG-2 removed from code-simplicity-cleanup, still carrying this stage's own integrity claim (gate-integrity sweep 2026-07-29, defect B-1). No allow-list: every gate preceding native-substrate is expected exit-zero, so ANY FAIL line fails this check. The hand-written 2026-07-23 record stays on disk as the evidence artifact and is no longer what the check reads",
		},
		{
			name = "fresh-context-verification",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/native-substrate/verifier-architecture.json && test -f artifacts/native-substrate/verifier-platform.json && grep -q "disposition" artifacts/native-substrate/verifier-architecture.json && grep -q "disposition" artifacts/native-substrate/verifier-platform.json && ./tools/test.sh 656 >/dev/null',
			evidence = "artifacts/native-substrate/verifier-architecture.json",
			note = "NS-I5 DONE 2026-07-23: two fresh-context reviews (architecture: 4 findings; platform: 7 findings incl. the additive-offset text-reservation reshape) — every finding fixed or explicitly dispositioned, regressions added (suite 656), selection-bridge slice re-driven live post-fix",
		},
		{
			name = "physical-device-confirmation",
			requirements = { "UI-NATIVE-007", "UI-NATIVE-003" },
			state = "FAIL_ENVIRONMENT",
			releaseBlocking = false,
			evidence = "artifacts/native-substrate/review-packet.md",
			note = "NS-P1..P3: physical gamepad (selection bridge), physical touch/OS keyboard, device-floor performance — irreducible E4 rows; closed via the batched review packet, never by emulator evidence",
		},
	},

	["native-stylesheets"] = {
		-- Roadmap Step 2: the DataModel StyleSheet + Style Editor become the
		-- runtime source of truth for every proven styleable paint property,
		-- semantic role, native interaction state, app-state tag, theme, and
		-- transition — behind an opt-in target capability with the explicit-
		-- write path preserved as a separate fallback mode.
		-- Acceptance ledger: artifacts/native-stylesheets/acceptance-ledger.md.
		-- KEEP HONEST: checks flip from PENDING only when the implementation
		-- and its evidence artifact exist (contract: fable-execution-contract.md).
		{
			name = "spike-matrix",
			requirements = { "UI-STYLE-001" },
			run = 'for f in m1-state-selectors m2-modifier-rules m3-capability-probe m4-queries-and-tags m5-authorability m6-specificity m7-derive-cost m8-transition-triggers m9-reduced-motion m10-authority-handoff; do test -f "artifacts/native-stylesheets/feasibility/$f.json" || exit 1; grep -q "luauui-studio-spike/1" "artifacts/native-stylesheets/feasibility/$f.json" || exit 1; done && grep -q "GetStyled" artifacts/native-stylesheets/feasibility/m10-authority-handoff.json && grep -q "phantom" artifacts/native-stylesheets/feasibility/m2-modifier-rules.json && grep -q "PreferredInputKeyboardAndMouse" artifacts/native-stylesheets/feasibility/m4-queries-and-tags.json && test -f docs/research/2026-07-24-native-stylesheet-spike.md',
			evidence = "artifacts/native-stylesheets/feasibility/m1-state-selectors.json",
			note = "NSS-M1..M10 LIVE 2026-07-24: Q1-Q12 answered with machine evidence — GetStyled instrument, phantom modifiers, Priority-then-insertion cascade, built-in @-queries + container queries (sheet-parented StyleQuery inert), transition triggers, strip path, defeat truth reconfirmed visually",
		},
		{
			name = "sheet-model-headless",
			requirements = { "UI-STYLE-001", "UI-RUNTIME-001" },
			run = 'test -f src/tokens/sheet_model.luau && test -f src/tokens/default_light_style.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*Dark theme tokens equal the default style values exactly" && echo "$out" | grep -q "✓.*every theme passes the contrast gate" && echo "$out" | grep -q "✓.*orders state rules per the measured cascade" && echo "$out" | grep -q "✓.*gates hover rules on the pointer-live tag" && echo "$out" | grep -q "✓.*classifyTags: the pure hint->tag mapping"',
			evidence = "tests/sheet_model.spec.luau",
			note = "NSS-A1 headless half: PURE model (tokens/rules/mirrors/motion) value-exact vs Luau styles, contrast-gated per theme, cascade-ordered, hover tag-gated, classification pure",
		},
		{
			name = "seed-once-materializer",
			requirements = { "UI-STYLE-001" },
			run = 'test -f src/client/native_style.luau && grep -q "SEED-ONCE" src/client/native_style.luau && grep -q "LuauUIStyle" src/client/native_style.luau && grep -q "IsA(\\"StyleSheet\\")" src/client/native_style.luau && grep -q "SetDerives" src/client/native_style.luau && grep -q "SetPropertyTransitions" src/client/native_style.luau && test -f artifacts/native-stylesheets/a9-layout-token-sync.json && grep -q "PRESERVED" artifacts/native-stylesheets/a9-layout-token-sync.json',
			evidence = "artifacts/native-stylesheets/a9-layout-token-sync.json",
			note = "NSS-A9 LIVE 2026-07-24 (§6.9 Fallback B): seed-once proven in the Edit DataModel — designer paint edit preserved across re-ensure, vandalized mirror refreshed, class-checked lookup never touches the library tree (live-found collision fixed)",
		},
		{
			name = "adapter-native-mode",
			requirements = { "UI-STYLE-001", "UI-PARADIGM-001" },
			run = 'grep -q "nativeStyle" src/client/screen_target.luau && grep -q "syncTags" src/client/screen_target.luau && grep -q "classifyTags" src/client/screen_target.luau && grep -q "wireNativePressDip" src/client/screen_target.luau && grep -q "nativeSheetOwned" src/render/authority.luau && grep -q "setNativeTransitionsEnabled" src/render/renderer.luau && test -f artifacts/native-stylesheets/a2-native-paint.json && grep -q "zero defeated properties" artifacts/native-stylesheets/a2-native-paint.json',
			evidence = "artifacts/native-stylesheets/a2-native-paint.json",
			note = "NSS-A2/NSS-I2 LIVE 2026-07-24: opt-in native paint hands off every targeted property (GetStyled == sheet-resolved on every classified node); adapter emits tags only; authority manifest declares the native-owned set; reduced-motion strip renderer-wired",
		},
		{
			name = "scenario-surface-extended",
			requirements = { "UI-AGENT-001" },
			run = 'test -f examples/gallery/scenarios/native_style.luau && grep -q "native_style" examples/gallery/scenarios/init.luau && grep -q "STYLED_PROPS" examples/gallery/scenarios/runner.luau && grep -q "mountIdentity" examples/gallery/scenarios/runner.luau && grep -q "editRuleProperty" examples/gallery/scenarios/runner.luau && grep -q "LuauUI_NativeStyle" examples/gallery/client/init.client.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*mounts through the real presenter and emits every classification input"',
			evidence = "examples/gallery/scenarios/native_style.luau",
			note = "contract §5: the shared verification surface gained the native_style scenario + tags/GetStyled/GuiState telemetry + mount-identity registry + runtime designer-edit seams (the same DataModel objects the Style Editor edits); headless conformance green",
		},
		{
			name = "live-acceptance-rows",
			requirements = { "UI-STYLE-001" },
			run = 'for f in a1-generated-sheet a2-native-paint a3-live-edit a4-native-states a5-app-state-tags a6-theme-swap a7-reduced-motion a8-preferred-text a9-layout-token-sync a10-fallback-parity; do test -f "artifacts/native-stylesheets/$f.json" || exit 1; grep -q "luauui-scenario-evidence/1" "artifacts/native-stylesheets/$f.json" || exit 1; done && grep -q "identity map" artifacts/native-stylesheets/a3-live-edit.json && grep -q "Idle->Hover->Press->Hover->Idle" artifacts/native-stylesheets/a4-native-states.json && grep -q "CanvasPosition retained" artifacts/native-stylesheets/a6-theme-swap.json && grep -q "TextSize stays 18" artifacts/native-stylesheets/a8-preferred-text.json && grep -q "byte-equal" artifacts/native-stylesheets/a10-fallback-parity.json || grep -q "EXACTLY" artifacts/native-stylesheets/a10-fallback-parity.json',
			evidence = "artifacts/native-stylesheets/a3-live-edit.json",
			note = "NSS-A1..A10 LIVE 2026-07-24 in Play Solo through the real adapter: runtime rule/token edits repaint with no Luau change and no remount/focus loss (captures paired), real-input state cycle, tag-only app state, theme swap with retention, strip path, preferred-text single application, exact fallback parity",
		},
		{
			name = "docs-and-adr",
			requirements = { "UI-STYLE-001" },
			run = 'test -f docs/adr/ADR-0018-native-stylesheets.md && grep -q "seed-once" docs/adr/ADR-0018-native-stylesheets.md && grep -q "Native stylesheets (opt-in)" docs/guide/05-styling.md && grep -q "reference only" docs/guide/05-styling.md && grep -q "sheet_model" src/tokens/tokens.luau && ! grep -q "generation is deferred" src/tokens/tokens.luau',
			evidence = "docs/adr/ADR-0018-native-stylesheets.md",
			note = "ADR-0018 records the decision + engine truths; the styling guide labels which Style Editor edits are immediate vs reference-only/source-owned; the tokens.luau deferral note lifted",
		},
		{
			name = "headless-suite-preserved",
			requirements = { "UI-RUNTIME-001" },
			run = "./tools/test.sh 671",
			evidence = "artifacts/test.json",
			note = "NSS-I1: post-stage suite minimum 671 (baseline 655); solver inputs remain plain-Luau (boundary discipline intact)",
		},
		{
			name = "game-suite-unchanged",
			requirements = { "UI-STYLE-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1",
			evidence = "artifacts/native-stylesheets/game-suite.txt",
			note = "NSS-I3: the RascalRally suite is RUN here. It used to grep a stored game-suite.txt for `2404 passed` and execute nothing (gate-integrity sweep 2026-07-29, defect B-2); the pinned count was also stale against the current 2425. The `dirty count 0` half stays a historical record in the evidence file and is not re-proved by this check",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = 'if [ -n "${LUAUUI_PRIOR_GATES_NESTED:-}" ]; then echo "prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)"; exit 0; fi; a=artifacts/native-stylesheets/prior-gates-rerun.txt && tools/prior_gates.sh "$a" native-stylesheets && grep -q "^DONE$" "$a" && failed="$(grep "^FAIL " "$a" || true)" && test -z "$failed"',
			evidence = "artifacts/native-stylesheets/prior-gates.txt",
			note = "NSS-I4: all 10 prior gates RE-RUN by this check at the source being judged, via tools/prior_gates.sh, writing artifacts/native-stylesheets/prior-gates-rerun.txt. It used to grep the STORED prior-gates.txt for `FINAL: 10/10 prior gates PASS` and execute nothing (gate-integrity sweep 2026-07-29, defect B-1 — the PG-2 shape). No allow-list: every gate preceding native-stylesheets is expected exit-zero. The hand-written 2026-07-24 record stays on disk as evidence",
		},
		{
			name = "fresh-context-verification",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/native-stylesheets/verifier-architecture.json && test -f artifacts/native-stylesheets/verifier-platform.json && grep -q "disposition" artifacts/native-stylesheets/verifier-architecture.json && grep -q "disposition" artifacts/native-stylesheets/verifier-platform.json',
			evidence = "artifacts/native-stylesheets/verifier-architecture.json",
			note = "NSS-I5: fresh-context architecture + Roblox-platform reviews with raw artifacts; findings fixed or dispositioned, affected slices re-run",
		},
		{
			name = "designer-and-device-confirmation",
			requirements = { "UI-STYLE-001" },
			state = "FAIL_ENVIRONMENT",
			releaseBlocking = false,
			evidence = "artifacts/native-stylesheets/review-packet.md",
			note = "NSS-P1..P3: Style Editor discoverability (E5 human), device theme-swap cost + real-touch hover + RM-on query direction (E4), transitions publish-status re-check at release — irreducible rows closed via the batched review packet",
		},
	},
	["authoring-adaptive-ui"] = {
		-- Roadmap Step 3: make LuauUI safe to author (Milestone 0), then deliver
		-- the adaptive-layout and common-control milestones (A and B).
		-- Acceptance ledger: artifacts/authoring-adaptive-ui/acceptance-ledger.md.
		-- KEEP HONEST: checks flip from PENDING only when the implementation AND
		-- its evidence artifact exist (contract: agent-execution-contract.md).
		{
			name = "strict-authoring",
			requirements = { "UI-AGENT-001" },
			run = 'test -f src/blueprint_schema.luau && grep -q "unknownPropError" src/blueprint.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*an unknown property names the control, the property, and the valid alternatives" && echo "$out" | grep -q "✓.*a misspelled property suggests the intended one" && echo "$out" | grep -q "✓.*a bare number where a dimension belongs explains the dimension table" && echo "$out" | grep -q "✓.*an unrecognised enum value is rejected with the closed value set" && echo "$out" | grep -q "✓.*children on a leaf are rejected and the containers are listed"',
			evidence = "artifacts/authoring-adaptive-ui/m0-a1-unknown-props.json",
			note = "M0-A1 LIVE 2026-07-24: 9/9 invalid screens rejected in the RUNNING client through public constructors (0 built); unknown prop + suggestion, wrong type, bare-number dimension, unknown enum, Signal-on-static-prop, missing required, children-on-leaf all fail at the boundary",
		},
		{
			name = "one-property-model",
			requirements = { "UI-AGENT-001", "UI-STYLE-001" },
			run = 'lune run tools/lune/check_prop_parity_cli >/dev/null && grep -q "schema.propDirty()" src/blueprint.luau && grep -q "STYLE_PROPS" src/render/renderer.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the live repository passes the property-parity check" && echo "$out" | grep -q "✓.*it detects a repainting property the refresh loop cannot re-apply" && echo "$out" | grep -q "✓.*a reactive style hint is re-applied instead of being dropped by the refresh loop" && echo "$out" | grep -q "✓.*a reactive .active. flag is re-applied instead of being dropped"',
			evidence = "artifacts/authoring-adaptive-ui/m0-a4-dead-props.json",
			note = "M0-A3/M0-A4: blueprint_schema is the single source (PROP_DIRTY generated); check_prop_parity reconciles schema x dirty x authority x renderer x adapter x exported types x api.md and is proved to FAIL on synthetic drift. Three silent-drop classes fixed: reactive style hints, reactive `active`, and unrecognised enum values (which had left the PopupButton panel and the word-game modal with no background at all)",
		},
		{
			name = "public-types-and-seams",
			requirements = { "UI-AGENT-001" },
			run = 'grep -q "export type ButtonSpec" src/blueprint.luau && grep -q "contribution = require" src/init.luau && grep -q "LuauUI.contribution.attach" docs/extending/new-control.md && grep -q "check_prop_parity_cli" docs/extending/new-control.md && grep -q "inputContribution" src/input/contribution.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*an attached bundle rides the internal meta channel, never the public prop bag" && echo "$out" | grep -q "✓.*no public constructor takes a bare untyped spec"',
			evidence = "artifacts/authoring-adaptive-ui/m0-a2-a7.json",
			note = "M0-A2/M0-A5: 19 exported <Class>Spec types, every constructor typed, 288 typed fields drift-checked both directions; LuauUI.contribution is public and the playbook + scaffold teach it; the bundle moved to the internal blueprint.meta channel so strict validation has no exemption",
		},
		{
			name = "complete-registration",
			requirements = { "UI-AGENT-001" },
			run = 'lune run tools/lune/check_registration_cli >/dev/null && grep -q "Grip = {" src/controls/contract.luau && grep -q "ErrorBoundary = {" src/controls/contract.luau && grep -q "Grip is registered" tests/authoring.spec.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*each UI..* constructor has a control contract and a registry row" && echo "$out" | grep -q "✓.*Grip is registered as an INTERACTIVE control with a hit floor"',
			evidence = "artifacts/authoring-adaptive-ui/m0-a2-a7.json",
			note = "M0-A6: all 19 public constructors have a contract + registry row (Anchor/Grid/Grip/Path/When/ForEach/ErrorBoundary were invisible); Grip — focusable and pointer-handling — now proves four-input AND the paradigm axis; the conformance kit mounts all 19 for dump determinism and dispose neutrality",
		},
		{
			name = "grid-fill-and-spacer",
			requirements = { "UI-LAYOUT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a fill-width cell occupies its whole column instead of collapsing to content" && echo "$out" | grep -q "✓.*a bare Spacer pushes its siblings apart in a VStack" && echo "$out" | grep -q "✓.*two bare Spacers share the leftover space equally" && echo "$out" | grep -q "✓.*a Spacer outside a stack axis stays inert" && test -f artifacts/authoring-adaptive-ui/a-lv1-grid-spacer.json && grep -q "geometryAfter" artifacts/authoring-adaptive-ui/a-lv1-grid-spacer.json',
			evidence = "artifacts/authoring-adaptive-ui/a-lv1-grid-spacer.json",
			note = "A-LV1 LIVE 2026-07-24: found in a Studio capture as a grid of correctly-positioned ZERO-width cells; fill cells now occupy their column/row, non-fill cells align inside the cell, and Spacer takes the stack's main axis by default. Live geometry 0 -> 96px per cell, re-verified in the running client",
		},
		{
			name = "scrollview-axes-and-keep-visible-headless",
			requirements = { "UI-LAYOUT-001", "UI-PARADIGM-001" },
			run = 'grep -q "scrollToVisible" src/render/renderer.luau && grep -q "getScrollPosition" src/client/screen_target.luau && grep -q "scrollToVisible" src/present/presenter.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*lays children out along x and advances by gap" && echo "$out" | grep -q "✓.*reports a horizontal canvas extent, not a vertical one" && echo "$out" | grep -q "✓.*scrolls the minimum distance to bring a node below the viewport into view" && echo "$out" | grep -q "✓.*finds the nearest scroll ancestor, not just a direct parent" && echo "$out" | grep -q "✓.*moving focus past the visible band scrolls the host without any control wiring"',
			evidence = "artifacts/authoring-adaptive-ui/a-sv1-scrollview.json",
			note = "A-SV1 HEADLESS HALF ONLY — the live geometry/capture half is FAIL_ENVIRONMENT, tracked by the separate `scrollview-live-geometry` check below (verifier finding V3: this check used to read PASS with no signal that the row was half blind): the horizontal axis now flows and accumulates along x (it painted a column and reported an unscrollable canvas before); the offset is readable from the engine; scrollToVisible is THE shared keep-visible substrate and the presenter calls it on every focus move, so any focusable in any ScrollView scrolls into view with no control wiring. LIVE geometry/capture half is FAIL_ENVIRONMENT (1x1 viewport) — see environment-log.md",
		},
		{
			name = "scrollview-live-geometry",
			requirements = { "UI-LAYOUT-001" },
			run = 'grep -q "liveClosed_2026-07-24" artifacts/authoring-adaptive-ui/a-sv1-scrollview.json && grep -q "nativeWheelProof" artifacts/authoring-adaptive-ui/a-sv1-scrollview.json && grep -q "mouseWheelEvents" artifacts/authoring-adaptive-ui/a-sv1-scrollview.json && grep -q "928" artifacts/authoring-adaptive-ui/a-sv1-scrollview.json && grep -q "keyboardHalf" artifacts/authoring-adaptive-ui/matrix/native-input.json && grep -q "user_keyboard_input" artifacts/authoring-adaptive-ui/matrix/native-input.json',
			evidence = "artifacts/authoring-adaptive-ui/a-sv1-scrollview.json",
			note = "A-SV1 LIVE HALF CLOSED 2026-07-24 (after `open -a RobloxStudio` gave a stable window): real absolute geometry — the horizontal region reports a 928px-WIDE canvas in a 280px band; keep-visible moved the far focusable INTO the band (Focus13 y=529 inside 433..573 while Focus1 scrolled to -23); and a real injected WHEEL (3 MouseWheel events) moved CanvasPosition 0->300 with Row1/Row20 clipped outside the host band — the engine-owned half the programmatic steps cannot prove. The same session also closed the KEYBOARD half of D-4 via user_keyboard_input (verifier finding V20)",
		},
		{
			name = "adaptive-layout",
			requirements = { "UI-LAYOUT-001" },
			run = 'test -f src/layout/adaptive.luau && grep -q "adaptive = require" src/init.luau && grep -q "AdaptiveStack" src/blueprint_schema.luau && grep -q "ViewThatFits" src/blueprint_schema.luau && grep -q "chosenCandidate" src/layout/solver.luau && grep -q "filterHidden" src/present/presenter.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a ten-foot display never resolves the densest class" && echo "$out" | grep -q "✓.*flipping the bound axis re-solves WITHOUT a factory rerun or a remount" && echo "$out" | grep -q "✓.*measures against the CONTAINER.s space, not the viewport.s" && echo "$out" | grep -q "✓.*an unchosen candidate.s focusables are removed from focus order" && test -f artifacts/authoring-adaptive-ui/a-al2-adaptive.json',
			evidence = "artifacts/authoring-adaptive-ui/a-al2-adaptive.json",
			note = "A-AL1/A-AL2/A-AL3: adaptive.luau (pure breakpoints + reactive conditions, ten-foot density floor, no device names); AdaptiveStack = ONE class with a reactive axis so a flip is a re-solve with zero remounts; ViewThatFits measures candidates through the real solver against the CONTAINER's space and filters losing candidates out of focus order (proven by driving real navigation)",
		},
		{
			name = "layout-modifiers-and-divider",
			requirements = { "UI-LAYOUT-001", "UI-STYLE-001" },
			run = 'grep -q "function blueprint.frame" src/blueprint.luau && grep -q "function blueprint.overlay" src/blueprint.luau && grep -q "function blueprint.aspectRatio" src/blueprint.luau && grep -q "luau-divider" src/tokens/sheet_model.luau && grep -q "nativeDivider" src/client/screen_target.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*an unknown alignment value fails at construction" && echo "$out" | grep -q "✓.*a modifier writing a property the class does not have is rejected" && echo "$out" | grep -q "✓.*the LAST writer of a property wins" && echo "$out" | grep -q "✓.*draws a vertical hairline in a horizontal stack" && echo "$out" | grep -q "✓.*follows an AdaptiveStack.s axis flip with no rebuild" && test -f artifacts/authoring-adaptive-ui/a-lv2-modifiers.json',
			evidence = "artifacts/authoring-adaptive-ui/a-lv2-modifiers.json",
			note = "A-LV2/A-LV3: frame/padding/offset/aspectRatio/alignment/overlay/background write only schema-declared props, and withProps now VALIDATES (a modifier could previously freeze in an unrecognised value — a hole straight through strict authoring). Divider is axis-aware and SHEET-painted. layoutPriority is a documented gap, not a silent prop",
		},
		{
			name = "button-complete",
			requirements = { "UI-PARADIGM-001", "UI-STYLE-001" },
			run = 'grep -q "assertNoFocusableContent" src/blueprint.luau && grep -q "hitFloorFor" src/render/renderer.luau && grep -q "setHitRect" src/client/screen_target.luau && grep -q "isDisabled" src/present/presenter.luau && grep -q "Destructive button" src/tokens/sheet_model.luau && grep -q "dangerPair" src/tokens/sheet_model.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a focusable inside the content is rejected: one activation surface, one focus site" && echo "$out" | grep -q "✓.*a content button exposes exactly ONE focusable and activates once" && echo "$out" | grep -q "✓.*a sub-floor button reports an expanded hit rect" && echo "$out" | grep -q "✓.*a button already at or above the floor gets NO expander" && echo "$out" | grep -q "✓.*a disabled button is skipped by focus navigation" && echo "$out" | grep -q "✓.*a disabled button does not activate on the keyboard or gamepad path either" && echo "$out" | grep -q "✓.*every theme.s danger pair passes the contrast gate" && test -f artifacts/authoring-adaptive-ui/b-btn-button.json',
			evidence = "artifacts/authoring-adaptive-ui/b-btn-button.json",
			note = "B-BTN1..B-BTN4: content inside ONE activation surface (a focusable in the content is a build error at any depth); default/cancel/destructive roles ride tags + sheet rules with a gated $Danger pair and a fallback for pre-existing styles; the effective-target floor is ENFORCED in hit geometry (visual rect untouched, by recorded decision); and enabled=false — which used to reach only paint, leaving a disabled control focusable and activatable — now removes it from focus AND refuses the verb on every input class",
		},
		{
			name = "value-controls",
			requirements = { "UI-PARADIGM-001" },
			run = 'test -f src/controls/value_model.luau && test -f src/controls/stepper.luau && grep -q "newStepper" src/init.luau && grep -q "isEnabled" src/controls/stepper.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*quantizes onto a grid measured FROM min, so the bounds are reachable" && echo "$out" | grep -q "✓.*stepping always makes progress and never leaves the range" && echo "$out" | grep -q "✓.*keyboard: Adjust on the focused control steps without touching a button" && echo "$out" | grep -q "✓.*no Adjust key is bound while focus sits outside the Stepper" && echo "$out" | grep -q "✓.*the affordance at a bound is DISABLED, not silently inert" && echo "$out" | grep -q "✓.*an explicitly disabled Stepper refuses every input class" && test -f artifacts/authoring-adaptive-ui/b-val-value-controls.json',
			evidence = "artifacts/authoring-adaptive-ui/b-val-value-controls.json",
			note = "B-VAL1 + the Stepper half of B-VAL3: ONE shared pure value model (grid from min so both bounds are reachable; stepped always progresses; NaN resolves to the low bound; impossible range/step is a build error) and a Stepper that reaches it from all four input classes, with focus-gated Adjust proven inert while focus is elsewhere. SLIDER IS NOT STARTED — it needs a controller drag-detector seam that does not exist yet (see the artifact)",
		},
		{
			name = "display-and-selection-controls",
			requirements = { "UI-PARADIGM-001", "UI-STYLE-001" },
			run = 'test -f src/controls/progress_view.luau && test -f src/controls/label.luau && test -f src/controls/picker.luau && test -f src/controls/disclosure_group.luau && grep -q "resolvePresentation" src/controls/picker.luau && grep -q "focusOn" src/controls/disclosure_group.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*paint is style-owned through the BAR FAMILY, never a borrowed surface" && echo "$out" | grep -q "✓.*iconOnly DEGRADES to the title when there is no icon" && echo "$out" | grep -q "✓.*a live size-class change flips the presentation WITHOUT remounting the options" && echo "$out" | grep -q "✓.*collapsing with focus INSIDE the content moves focus back to the header first" && echo "$out" | grep -q "✓.*the trigger and every open row report a hit rect at or above the floor" && echo "$out" | grep -q "✓.*the pure rule prefers a sheet on touch, inline when short, menu otherwise" && echo "$out" | grep -q "✓.*a sheet anchors to the bottom edge with visually larger rows" && echo "$out" | grep -q "✓.*every presentation keeps selection, Cancel, and the tap-away machinery" && echo "$out" | grep -q "✓.*a LIVE touch class flips it to a sheet with no rebuild of the trigger" && grep -q "resolvePresentation" src/controls/popup_button.luau && test -f artifacts/authoring-adaptive-ui/b-dsp-display-controls.json',
			evidence = "artifacts/authoring-adaptive-ui/b-dsp-display-controls.json",
			note = "B-DSP1/B-DSP2 + the floor half of B-DSP3: ProgressView (percent fill, style-owned roles, clamped), Label (title required BECAUSE it is the semantic text; iconOnly degrades), Picker (segmented/inline resolved from option count + space class through an exported pure rule, flipping with no remount), DisclosureGroup (focus returns to the header BEFORE collapse unmounts the content), and PopupButton rows inheriting the enforced target floor. B-DSP3 is now COMPLETE: the presentation adapts (menu / inline / sheet) from option count, space class and live touch, with the transient-surface machinery proven untouched in all three idioms",
		},
		{
			name = "headless-suite-preserved",
			requirements = { "UI-RUNTIME-001" },
			run = "./tools/test.sh 919",
			evidence = "artifacts/test.json",
			note = "I1: post-slice suite minimum 919 (baseline 672); every new assertion is pure Luau and no existing assertion was weakened or moved behind the engine",
		},
		{
			name = "game-suite-unchanged",
			requirements = { "UI-AGENT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1",
			evidence = "artifacts/authoring-adaptive-ui/game-suite.txt",
			note = "I3: the RascalRally suite is RUN here. It used to grep a stored game-suite.txt for `2404 passed` and execute nothing (gate-integrity sweep 2026-07-29, defect B-2); the pinned count was also stale against the current 2425. The dirty-file accounting (5 files pre-dating that session, from the earlier native-stylesheet promotion) stays a historical record in the evidence file and is not re-proved by this check",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = 'if [ -n "${LUAUUI_PRIOR_GATES_NESTED:-}" ]; then echo "prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)"; exit 0; fi; a=artifacts/authoring-adaptive-ui/prior-gates-rerun.txt && tools/prior_gates.sh "$a" authoring-adaptive-ui && grep -q "^DONE$" "$a" && failed="$(grep "^FAIL " "$a" || true)" && test -z "$failed"',
			evidence = "artifacts/authoring-adaptive-ui/prior-gates.txt",
			note = "I4: all 11 prior gates RE-RUN by this check at the source being judged, via tools/prior_gates.sh, writing artifacts/authoring-adaptive-ui/prior-gates-rerun.txt. It used to grep the STORED prior-gates.txt for `FINAL: 11/11 prior gates PASS` and execute nothing (gate-integrity sweep 2026-07-29, defect B-1 — the PG-2 shape). No allow-list: this stage's own standing PENDING physical row is NOT in its own prior list, so every gate before it is expected exit-zero. The hand-written 2026-07-24 record stays on disk as evidence",
		},
		{
			name = "live-studio-matrix",
			requirements = { "UI-AGENT-001", "UI-PARADIGM-001" },
			run = 'test -f artifacts/authoring-adaptive-ui/matrix/five-view-matrix.json && test -f artifacts/authoring-adaptive-ui/matrix/orientation-change.json && test -f artifacts/authoring-adaptive-ui/matrix/native-input.json && grep -q "samsung_galaxy_a06" artifacts/authoring-adaptive-ui/matrix/five-view-matrix.json && grep -q "TEN-FOOT DENSITY FLOOR" artifacts/authoring-adaptive-ui/matrix/five-view-matrix.json && grep -q "focusPreserved" artifacts/authoring-adaptive-ui/matrix/orientation-change.json && grep -q "MouseButton1" artifacts/authoring-adaptive-ui/matrix/native-input.json && test -f examples/gallery/scenarios/adaptive_controls.luau && grep -q "adaptive_controls" examples/gallery/scenarios/init.luau && grep -q "setEnv" examples/gallery/scenarios/runner.luau && test -f artifacts/authoring-adaptive-ui/matrix/intentional-failure.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the hit-floor assertion fails when a control is pinned below the floor" && echo "$out" | grep -q "✓.*the hidden-candidate assertion fails when a losing candidate still paints" && echo "$out" | grep -q "✓.*the adaptation assertion fails when a screen hard-codes one axis"',
			evidence = "artifacts/authoring-adaptive-ui/matrix/five-view-matrix.json",
			note = "D-1..D-5 LIVE 2026-07-24: presets RESOLVED at runtime via GetDeviceListAsync/GetDeviceInfoAsync (42 catalog entries, nothing hard-coded); ONE semantic tree driven across all five view rows through the verification surface's declared setEnv seam; the ten-foot density floor fired (1920px wide -> `regular`, not `wide`); a live portrait/landscape change preserved state AND focus; and a real injected MouseButton1 produced the full raw-event -> semantic-action -> focus -> value -> geometry -> capture chain. Device SELECTION and VirtualInput are absent at this security level and the boundary is recorded honestly in the artifact. D-6 is closed: all three load-bearing assertions (hit floor, hidden candidate, axis adaptation) proved to REJECT a deliberately broken fixture",
		},
		{
			name = "remaining-milestone-a-b-scope",
			requirements = { "UI-LAYOUT-001", "UI-PARADIGM-001" },
			run = 'test -f artifacts/authoring-adaptive-ui/a-al4-preferred-text-sweep.json && grep -q "theCompressionResult" artifacts/authoring-adaptive-ui/a-al4-preferred-text-sweep.json && grep -q "reducedMotion" artifacts/authoring-adaptive-ui/a-al4-preferred-text-sweep.json && grep -q "D-1b_adaptive_controls_compact-phone-portrait_toolbar-media-stats" artifacts/authoring-adaptive-ui/a-al4-preferred-text-sweep.json && grep -q "D-4b_adaptive_controls_desktop-standard_toolbar-media-stats" artifacts/authoring-adaptive-ui/a-al4-preferred-text-sweep.json && grep -q "diagnostics" examples/gallery/scenarios/runner.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a preference BELOW 1 never reserves less than the painted size" && echo "$out" | grep -q "✓.*the reservation floor composes with the ten-foot paint scale" && echo "$out" | grep -q "✓.*a stack that cannot hold its content reports it instead of painting off-screen" && echo "$out" | grep -q "✓.*a ViewThatFits candidate that lost does not report an overflow" && echo "$out" | grep -q "✓.*a stack that exactly fits reports no overflow"',
			evidence = "artifacts/authoring-adaptive-ui/a-al4-preferred-text-sweep.json",
			note = "CLOSED 2026-07-24 by the preferred-text sweep. (1) The COMPRESSION RESULT is now defined per recipe shape: text always wraps and never clips, but CONTAINERS DO NOT COMPRESS AT ALL — a content child keeps full size and the stack paints past its own box. (2) The toolbar / 16:9 media / stat-grid surfaces are captured at compact-phone-portrait and desktop-standard. The sweep found and fixed two MAJOR framework defects: a sub-1 text preference reserved a SMALLER box than the engine was told to paint (10 nodes TextFits==false live at 0.5, now zero across 0.2..5 and offsets 0..64), and stack overflow was completely silent (now reported, with hidden ViewThatFits candidates correctly exempt). reducedMotion swept as a regression: geometry byte-identical, which is the correct result. Looking at the captures is also what surfaced the OPEN fixture defect tracked as `adaptive-fixture-fits-one-screen`",
		},
		{
			name = "adaptive-fixture-fits-one-screen",
			requirements = { "UI-LAYOUT-001" },
			run = 'grep -q "BodyScroll" examples/gallery/scenarios/adaptive_controls.luau && grep -q "reDrive2026_07_24" artifacts/authoring-adaptive-ui/matrix/five-view-matrix.json && grep -q "canvasCoversContent" artifacts/authoring-adaptive-ui/matrix/five-view-matrix.json && grep -q "actionBarPinned" artifacts/authoring-adaptive-ui/matrix/five-view-matrix.json && python3 tools/check_matrix_rows.py && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a scroll canvas covers content laid out in fill columns that wrap" && echo "$out" | grep -q "✓.*an aspect box paired with fill is measured at the extent it will receive"',
			evidence = "artifacts/authoring-adaptive-ui/matrix/five-view-matrix.json",
			note = "CLOSED 2026-07-24. Director chose to fix the fixture and re-baseline: the body now sits in a UI.ScrollView taking `fill` with the action bar pinned outside it — the standard settings shape, which also exercises A-SV1 inside the adaptive fixture. All five device rows re-driven and re-captured at stamp 0cd49ad1-814757; this check re-reads them and fails if any row's canvas falls short of its content, any row reports a solver diagnostic, the action bar stops being pinned-and-on-screen, or the 44px hit floor breaks. Fixing it exposed TWO further MAJOR solver defects, both negative-proven: an hstack measured every child at its FULL inner width including `fill` children that only receive a share (151px of content unreachable by scrolling on phone landscape; a column reporting 39px while holding 77px of text), and an `aspect` box paired with `width = fill` measured 0x0 because `fill` reports CONTENT and a Box has none (costing exactly the 185px media box on phone portrait)",
		},
		{
			name = "fresh-context-verification",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/authoring-adaptive-ui/verifier-phase-gate.json && grep -q "ACCEPT_WITH_FINDINGS" artifacts/authoring-adaptive-ui/verifier-phase-gate.json && grep -q ""V12"" artifacts/authoring-adaptive-ui/verifier-phase-gate.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*opts.onActivate does not fire for a disabled node" && echo "$out" | grep -q "✓.*a path re-created while still hidden is written hidden again" && echo "$out" | grep -q "✓.*a sub-floor control re-created at the same path keeps its hit expander" && echo "$out" | grep -q "✓.*a sub-floor control inside a ScrollView gets an expander in HOST space, not window space" && echo "$out" | grep -q "✓.*navigation skips a disabled Slider" && echo "$out" | grep -q "✓.*verifier V14: a role carries its OWN hover and press rules"',
			evidence = "artifacts/authoring-adaptive-ui/verifier-phase-gate.json",
			note = "I5 DONE 2026-07-24: fresh-context phase-gate review, verdict ACCEPT_WITH_FINDINGS, 21 findings. Three MAJOR code defects — all inside rows already marked PASS and all invisible to the suite — fixed with regressions (V12 disabled bypassed by the consumer override; V11 hit expander in window space inside a clip host; V10 stale per-path caches across a remount), plus V13 and V14. Documentation findings V1-V9/V15-V19 corrected in the ledger and bundle",
		},
		{
			name = "physical-and-human-rows",
			requirements = { "UI-PARADIGM-001" },
			state = "PENDING",
			releaseBlocking = false,
			evidence = "artifacts/authoring-adaptive-ui/review-packet.md",
			note = "P1..P5: physical touch targeting/momentum/slider feel, real gamepad class + Adjust at ten-foot, the mobile OS keyboard, floor-device performance, and the human adaptive-readability review — never closed by emulator or headless evidence",
		},
	},
	["theme-packages-and-skinning"] = {
		-- Roadmap Step 3.5: public versioned theme packages, metric-aware
		-- swapping, and bounded rich skinning around native StyleSheets.
		-- Acceptance ledger: artifacts/theme-packages-and-skinning/acceptance-ledger.md.
		-- Row checks verify EVIDENCE + SOURCE ANCHORS (fast, deterministic); the
		-- library-suite-green check is the single full-suite run for this gate.
		{
			name = "feasibility-probes",
			requirements = { "UI-STYLE-001", "UI-FID-001" },
			run = 'for f in m1-per-target-sheets m2-nineslice-rules m3-font-tokens m4-metric-attributes m5-swap-atomicity-cost m6-sync-roundtrip m7-gradient-shadow-phantoms m8-render-order-combinators; do test -f "artifacts/theme-packages-and-skinning/feasibility/$f.json" || exit 1; grep -q "luauui-studio-spike/1" "artifacts/theme-packages-and-skinning/feasibility/$f.json" || exit 1; done && grep -q "ISOLATED" artifacts/theme-packages-and-skinning/feasibility/m1-per-target-sheets.json && grep -q "ATOMIC_NEXT_FRAME" artifacts/theme-packages-and-skinning/feasibility/m5-swap-atomicity-cost.json && grep -q "CHROME TEXT LIFT" artifacts/theme-packages-and-skinning/feasibility/m8-render-order-combinators.json',
			evidence = "artifacts/theme-packages-and-skinning/feasibility/m1-per-target-sheets.json",
			note = "TP-M1..M8 (Play Solo 0.731): per-target isolation; nine-slice rule-ownable; font/number tokens swap; AttributeChanged live-edit signal; ATOMIC_NEXT_FRAME swap 0.039ms@600; typed export exact; ::UIGradient renders / ::UIShadow inert; Sibling child covers parent text -> chrome text lift",
		},
		{
			name = "theme-package-contract",
			requirements = { "UI-STYLE-001", "UI-AGENT-001" },
			run = 'test -f src/themes/package.luau && grep -q "themes = {" src/init.luau && grep -q "checkCoverage" src/init.luau && grep -q "PASS_AUTOMATED" artifacts/theme-packages-and-skinning/b-a1-package-contract.json 2>/dev/null || grep -q "rejection class" artifacts/theme-packages-and-skinning/b-a1-package-contract.json && grep -q "onDanger on danger" src/themes/package.luau && grep -q "theme_package.spec" tests/run.luau',
			evidence = "artifacts/theme-packages-and-skinning/b-a1-package-contract.json",
			note = "TP-A1: public define/validate with useful errors per rejection class (incl. danger-pair contrast parity); live incompatible-package refusal; declarative data only",
		},
		{
			name = "metric-snapshot-single-source",
			requirements = { "UI-STYLE-001", "UI-LAYOUT-001" },
			run = 'test -f src/themes/snapshot.luau && grep -q "themeMetrics" src/env/environment.luau && grep -q "themeMetrics" src/render/renderer.luau && test -f artifacts/theme-packages-and-skinning/b-a2-metric-snapshot.json && lune run tools/lune/check_flat_baseline >/dev/null',
			evidence = "artifacts/theme-packages-and-skinning/b-a2-metric-snapshot.json",
			note = "TP-A2: one frozen plain-Luau snapshot on the themeMetrics fact; composition order + floors clamp UP; neutral render unchanged against the stored 3.5 baseline. THE LAST CLAUSE CHANGED IN STEP 5.5 (cleanup ledger C-08): it used to `cmp` baseline-neutral-dump.json against final-neutral-dump.json — two STORED files, so it proved nothing about the current tree, and it went red the moment `_theme_baseline` (which defaults to writing baseline-neutral-dump.json) was run without an argument on 2026-07-28. check_flat_baseline REGENERATES the neutral render from live source and compares it node-by-node against final-neutral-dump.json with a named allow-list, which is the check this one was always meant to be",
		},
		{
			name = "controls-semantic-roles",
			requirements = { "UI-STYLE-001", "UI-LAYOUT-001" },
			run = 'test -f tools/lune/check_theme_drift.luau && grep -q "theme_drift.spec" tests/run.luau && grep -q "theme_roles.spec" tests/run.luau && test -f artifacts/theme-packages-and-skinning/b-a3-controls-roles.json',
			evidence = "artifacts/theme-packages-and-skinning/b-a3-controls-roles.json",
			note = "TP-A3: every Step 3 control resolves theme-owned metrics through roles; drift lint fired on 21 real violations then negative-proven synthetically",
		},
		{
			name = "reactive-controller-atomic-swap",
			requirements = { "UI-STYLE-001", "UI-RUNTIME-001" },
			run = 'test -f src/client/theme_controller.luau && grep -q "themeRootGui" src/client/screen_target.luau && grep -q "theme_controller.spec" tests/run.luau && grep -q "byte-identical" artifacts/theme-packages-and-skinning/b-a4-atomic-swap.json && grep -q "180" artifacts/theme-packages-and-skinning/b-a4-atomic-swap.json',
			evidence = "artifacts/theme-packages-and-skinning/b-a4-atomic-swap.json",
			note = "TP-A4: target-scoped controller; live swap kept mount identity/focus/scroll; headless one-solve zero-rebuild; renamed-themes swapPackage regression (found live)",
		},
		{
			name = "font-aware-measurement",
			requirements = { "UI-FID-001", "UI-LAYOUT-001" },
			run = 'grep -q "fontKey" src/layout/solver.luau && grep -q "buildPackage" src/client/theme_controller.luau && grep -q "Fondamento" artifacts/theme-packages-and-skinning/b-a5-font-measurement.json && grep -q "TextFits true" artifacts/theme-packages-and-skinning/b-a5-font-measurement.json',
			evidence = "artifacts/theme-packages-and-skinning/b-a5-font-measurement.json",
			note = "TP-A5: descriptor-keyed measurement; the legacy-builder font split was found LIVE (exact-Fondamento boxes clipping BuilderSans glyphs) and fixed; all five rows unclipped incl. preferred-text and ten-foot",
		},
		{
			name = "style-editor-sync",
			requirements = { "UI-STYLE-001", "UI-AGENT-001" },
			run = 'test -f tools/lune/theme_sync_cli.luau && test -f src/themes/token_sync.luau && grep -q "ACTIVE theme sheet" artifacts/theme-packages-and-skinning/b-a6-editor-sync.json && test -f artifacts/theme-packages-and-skinning/theme-sync/gate-negative-proof.json && test -f artifacts/theme-packages-and-skinning/theme-sync/parchment-live-dump.json && lune run tools/lune/theme_sync_cli -- --dump artifacts/theme-packages-and-skinning/theme-sync/parchment-live-dump.json --package examples/themes/fantasy_parchment.luau --check',
			evidence = "artifacts/theme-packages-and-skinning/b-a6-editor-sync.json",
			note = "TP-A6: live sheet-attribute edits re-solve (Space_m) and repaint (Radii_control via metricRuleProps); ONE export action; the freshness gate RUNS here against the live Studio dump and is negative-proven in gate-negative-proof.json",
		},
		{
			name = "chrome-recipes-and-slots",
			requirements = { "UI-STYLE-001" },
			run = 'grep -q "buildPackage" src/tokens/sheet_model.luau && grep -q "LuauUIChromeText" src/client/screen_chrome.luau && grep -q "chromeArtJudgement" src/client/screen_chrome.luau && grep -q "judgeArt" src/tokens/chrome_slots.luau && grep -q "theme_chrome.spec" tests/run.luau && grep -q "33" artifacts/theme-packages-and-skinning/b-a7-chrome-slots.json',
			evidence = "artifacts/theme-packages-and-skinning/b-a7-chrome-slots.json",
			note = "TP-A7/TP-A8: bounded recipes + decoration slots; flat=0 ornate=33+11 counted live; asset-failure flip/recover; chrome text lift; the grace guard for art the engine was never asked to decode (re-anchored 2026-07-26: `chromeEffectivelyVisible` became the pure `chrome_slots.judgeArt` plus the adapter's `chromeArtJudgement` fact walk when RS-A16-D5 added the clipped-away clause)",
		},
		{
			name = "fantasy-parchment-public-build",
			requirements = { "UI-STYLE-001", "UI-AGENT-001" },
			run = 'test -f examples/themes/fantasy_parchment.luau && grep -q "neutralPackage" examples/themes/fantasy_parchment.luau && ! grep -q \'require("%.%./%.%./src\' examples/themes/fantasy_parchment.luau && test -f assets/themes/fantasy-parchment/provenance.md && test -f assets/themes/fantasy-parchment/upload-manifest.json && grep -q "paintController=controller\\|paintController.:.controller\\|controller" artifacts/theme-packages-and-skinning/b-a9-fantasy-parchment.json',
			evidence = "artifacts/theme-packages-and-skinning/b-a9-fantasy-parchment.json",
			note = "TP-A9 centerpiece: public-API-only package, original provenance-recorded art, installed via the real controller on all five rows with states/hit-floor/focus intact",
		},
		{
			name = "reference-theme-families",
			requirements = { "UI-STYLE-001" },
			run = 'for f in classic_desktop glossy_mobile scifi_hud fantasy_parchment fantasy_parchment_stub custom_control; do test -f "examples/themes/$f.luau" || exit 1; done && grep -q "checkCoverage" src/themes/package.luau && grep -q "theme_reference_packages.spec" tests/run.luau && test -f artifacts/theme-packages-and-skinning/b-a10-reference-families.json',
			evidence = "artifacts/theme-packages-and-skinning/b-a10-reference-families.json",
			note = "TP-A10/TP-A11: four families cover the four theme classes; namespaced contribution gate shipped (themes.checkCoverage) and proven both directions",
		},
		{
			name = "docs-and-check-docs-cli",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_docs_cli && test -f artifacts/theme-packages-and-skinning/b-a12-docs-gate.json",
			evidence = "artifacts/theme-packages-and-skinning/b-a12-docs-gate.json",
			note = "TP-A12: the canonical read-only doc command RUNS here (13 obligations) and is negative-proven in b-a12-docs-gate.json",
		},
		{
			name = "studio-matrix-themes",
			requirements = { "UI-FID-001" },
			run = 'python3 - <<\'PYEOF\'\nimport json, hashlib, os, sys\nd = json.load(open("artifacts/theme-packages-and-skinning/b-a13-matrix.json"))\nrows = d["rows"]\nassert len(rows) >= 11, "matrix rows missing"\nfor r in rows:\n    p = os.path.join("artifacts/theme-packages-and-skinning", r["capture"])\n    assert os.path.isfile(p), "missing capture " + p\n    sha = hashlib.sha256(open(p, "rb").read()).hexdigest()[:16]\n    assert sha == r["captureSha256_16"], "capture drifted: " + p\n    if "textUnfit" in r:\n        assert r["textUnfit"] == 0, "unfit text in " + r["id"]\nprint("matrix ok:", len(rows), "rows")\nPYEOF',
			evidence = "artifacts/theme-packages-and-skinning/b-a13-matrix.json",
			note = "TP-A13/TP-A14: every matrix row re-verified against its REAL PNG (sha) + zero-unfit digest on every run; locale axis honestly not driven (review packet)",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 1239",
			evidence = "artifacts/test.json",
			note = "TP-I1: stage-final floor 1239 (965 at stage start; +211 through the packages, +63 through the review-fix round)",
		},
		{
			name = "game-suite-untouched",
			requirements = { "UI-AGENT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1",
			note = "TP-I3: RascalRally suite green; no game edits, no Sponsor migration this stage",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = 'if [ -n "${LUAUUI_PRIOR_GATES_NESTED:-}" ]; then echo "prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)"; exit 0; fi; a=artifacts/theme-packages-and-skinning/prior-gates-rerun.txt && tools/prior_gates.sh "$a" theme-packages-and-skinning && grep -q "^DONE$" "$a" && failed="$(grep "^FAIL " "$a" | grep -v "^FAIL authoring-adaptive-ui " || true)" && test -z "$failed" && { ! grep -q "^FAIL authoring-adaptive-ui " "$a" || grep -q "^      PENDING  physical-and-human-rows$" "$a"; }',
			evidence = "artifacts/theme-packages-and-skinning/prior-gates.txt",
			note = "TP-I4: all 12 prior gates RE-RUN by this check at the source being judged, via tools/prior_gates.sh, writing artifacts/theme-packages-and-skinning/prior-gates-rerun.txt. It used to grep the STORED prior-gates.txt for the prose `12/12 PASS|11/12 PASS + authoring-adaptive-ui unregressed` and execute nothing (gate-integrity sweep 2026-07-29, defect B-1 — the PG-2 shape). ONE gate is allow-listed: authoring-adaptive-ui exits 1 on its own standing PENDING physical/human row, and the allowance is CONDITIONAL — if it fails, the run must still carry that exact PENDING row, so a failure for any NEW reason fails this check. Every other gate must be exit-zero",
		},
		{
			name = "fresh-context-reviews",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/theme-packages-and-skinning/verifier-phase-gate.json && grep -qE "READY TO DECLARE|ACCEPT" artifacts/theme-packages-and-skinning/verifier-phase-gate.json && test -f artifacts/theme-packages-and-skinning/verifier-architecture.json && test -f artifacts/theme-packages-and-skinning/verifier-runtime.json && test -f artifacts/theme-packages-and-skinning/verifier-platform.json',
			evidence = "artifacts/theme-packages-and-skinning/verifier-phase-gate.json",
			note = "TP-I5: phase-gate + architecture + reactive-runtime + Roblox-platform fresh-context reviews, findings fixed or dispositioned",
		},
		{
			name = "physical-and-human-rows",
			requirements = { "UI-STYLE-001" },
			-- FAIL_ENVIRONMENT non-blocking is the established encoding for rows
			-- no available instrument can reach (cf. input-paradigms/native-substrate
			-- physical rows): the review packet is the one-pass closing procedure
			state = "FAIL_ENVIRONMENT",
			releaseBlocking = false,
			evidence = "artifacts/theme-packages-and-skinning/review-packet.md",
			note = "TP-P1..P4: human Style Editor authoring pass, Parchment on a real phone, readability review of the stored captures, and the Step 7 low-end deferral — never closed by emulator or headless evidence; procedures in review-packet.md",
		},
	},

	["rich-skinning-v2"] = {
		-- Rich skinning v2: fully image-driven UI per docs/plans/rich-skinning-v2.md.
		-- Acceptance ledger: artifacts/rich-skinning-v2/acceptance-ledger.md.
		-- Registered BORN-RED 2026-07-25 before any implementation (the Step 3.5
		-- process): every check fails until its evidence exists. Source anchors
		-- tighten as architecture rulings land; evidence artifacts alone never
		-- pass a row — the ledger + fresh-context reviews audit their content.
		{
			name = "feasibility-probes",
			requirements = { "UI-STYLE-001", "UI-FID-001" },
			run = 'for f in rs-m1-tilesize rs-m2-layer-zorder rs-m3-ornament-anchoring rs-m4-fill-clip rs-m5-pixel-snapping rs-m6-state-swap-latency rs-m7-content; do test -f "artifacts/rich-skinning-v2/feasibility/$f.json" || exit 1; grep -q "luauui-studio-spike/1" "artifacts/rich-skinning-v2/feasibility/$f.json" || exit 1; grep -q "verdict" "artifacts/rich-skinning-v2/feasibility/$f.json" || exit 1; done && grep -q "GO" artifacts/rich-skinning-v2/feasibility/rs-m1-tilesize.json && grep -q "rule-owned from birth" artifacts/rich-skinning-v2/feasibility/rs-m2-layer-zorder.json && grep -q "WINDOW CLIP WINS" artifacts/rich-skinning-v2/feasibility/rs-m4-fill-clip.json && grep -q "accepted-but-silently-inert" artifacts/rich-skinning-v2/feasibility/rs-m7-content.json && test -f artifacts/rich-skinning-v2/captures/rs-m1-tilesize.png && test -f artifacts/rich-skinning-v2/captures/rs-m4-fillclip.png',
			evidence = "artifacts/rich-skinning-v2/feasibility/rs-m1-tilesize.json",
			note = "RS-M1..M7: TileSize FIRST (the tile layer kind is contingent on its verdict), layer z-order under the text lift, ornament anchoring, fill-clip approaches, pixel snapping, per-state swap latency, Content materialization",
		},
		{
			name = "layered-slots-and-posture",
			requirements = { "UI-STYLE-001" },
			-- R9's "cmp-enforced at gate" is now ACTUALLY enforced (phase-gate
			-- verifier F2): check_flat_baseline regenerates the neutral dump to a
			-- temp path and diffs it against the 0.6.0 baseline with an explicit,
			-- reasoned allow-list. `test -f` proved a file existed; this proves the
			-- flat render did not move.
			run = "test -f artifacts/rich-skinning-v2/rs-a1-image-is-element.json && test -f artifacts/rich-skinning-v2/rs-a2-layered-slots.json && grep -q 'theme_layers.spec' tests/run.luau && lune run tools/lune/check_flat_baseline",
			evidence = "artifacts/rich-skinning-v2/rs-a2-layered-slots.json",
			note = "RS-A1/RS-A2: image-is-the-element default posture (suppression censused, flat byte-identical — cmp-enforced by tools/lune/check_flat_baseline against the 0.6.0 dump with a characterized allow-list) + bounded fill/frame/corners/edges/plaque layer stacks with a fixed anchoring vocabulary, censused, flat zero",
		},
		{
			name = "state-variant-assets",
			requirements = { "UI-STYLE-001" },
			run = 'test -f artifacts/rich-skinning-v2/rs-a3-state-variants-rung1.json && test -f artifacts/rich-skinning-v2/rs-a4-state-variants-rung2.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*unstated states fall back to default, which is what lets an author ship less art" && echo "$out" | grep -q "✓.*rejects an unknown state key, naming the legal set" && echo "$out" | grep -q "✓.*rejects a state naming art the package never declared, naming the state" && echo "$out" | grep -q "✓.*accepts insets that are identical across every declared state" && echo "$out" | grep -q "✓.*rejects a per-axis difference, naming the slot, the state and the axis"',
			evidence = "artifacts/rich-skinning-v2/rs-a3-state-variants-rung1.json",
			note = "RS-A3/RS-A4: per-state asset maps (default/hover/pressed/selected/disabled/error + focus via selection) on every image-bearing slot AND on per-view override props; bare string = same art; unstated states fall back to default; disabled keeps its floor; no reflow on state change",
		},
		{
			name = "image-value-displays",
			requirements = { "UI-STYLE-001" },
			run = 'test -f artifacts/rich-skinning-v2/rs-a5-image-bars.json && test -f artifacts/rich-skinning-v2/rs-a6-toggle-slots.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the art inside the window is the WHOLE track on the driven axis" && echo "$out" | grep -q "✓.*direction decides the axis and the pinned edge, and nothing else" && echo "$out" | grep -q "✓.*the centrepiece is dead centre on both axes, direction-independently" && echo "$out" | grep -q "✓.*an ImageRect crop is REFUSED, citing the probe that rejected it" && echo "$out" | grep -q "✓.*chrome_slots.barReservation derives the overhang from the declared boxes"',
			evidence = "artifacts/rich-skinning-v2/rs-a5-image-bars.json",
			note = "RS-A5/RS-A6: bar track+fill (fill clipped by percent), end-caps, centerpiece, stepper glyph plates; toggleTrack/toggleKnob slots with per-state art on both; solver keeps geometry, adapter clips paint",
		},
		{
			name = "semantic-icons",
			requirements = { "UI-STYLE-001" },
			run = 'test -f artifacts/rich-skinning-v2/rs-a7-semantic-icons.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*rejects a name that is neither a framework icon nor namespaced" && echo "$out" | grep -q "✓.*rejects an unknown iconSizes role and a non-positive size" && echo "$out" | grep -q "✓.*a private-use codepoint FAILS the check" && echo "$out" | grep -q "✓.*every snapshot answers all three roles, authored or not" && echo "$out" | grep -q "✓.*a METRIC package resizes icons"',
			evidence = "artifacts/rich-skinning-v2/rs-a7-semantic-icons.json",
			note = "RS-A7: theme icon map + iconSizes + tint roles + fallback glyphs; controls request icons semantically; the sci-fi follow-ups tofu caret is the proof defect and must render an icon or real glyph live",
		},
		{
			name = "pixel-mode",
			requirements = { "UI-STYLE-001", "UI-FID-001" },
			run = 'test -f artifacts/rich-skinning-v2/rs-a8-pixel-mode.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*rejects an unknown rendering mode, naming the modes" && echo "$out" | grep -q "✓.*rejects a pixel package with no unit, and a fractional or zero one" && echo "$out" | grep -q "✓.*locks SliceScale to integers, naming the slot that uses the art" && echo "$out" | grep -q "✓.*every image-bearing rule carries it, and the census proves it" && echo "$out" | grep -q "✓.*a NON-pixel package never enters the path"',
			evidence = "artifacts/rich-skinning-v2/rs-a8-pixel-mode.json",
			note = "RS-A8: rendering=pixel — ResampleMode=Pixelated rides every image-bearing rule, snapshot metrics snap to integer unit multiples, SliceScale integer-locked; non-pixel packages byte-unaffected",
		},
		{
			name = "content-adoption",
			requirements = { "UI-STYLE-001" },
			run = 'test -f artifacts/rich-skinning-v2/rs-a9-content-adoption.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*both spellings compile to the same bytes" && echo "$out" | grep -q "✓.*both emit the same rules, carrying the same plain strings" && echo "$out" | grep -q "✓.*the compiled value is a plain STRING on one field, both ways round"',
			evidence = "artifacts/rich-skinning-v2/rs-a9-content-adoption.json",
			note = "RS-A9 (m9 stance): authored data stays plain string URIs; schema field content canonical with contentId alias, ONE resolution path; adapter materializes ImageContent; export round-trip value-exact",
		},
		{
			name = "selectby-profile-selection",
			requirements = { "UI-STYLE-001", "UI-INPUT-002" },
			run = 'test -f artifacts/rich-skinning-v2/rs-a10-selectby.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a pointer profile takes the pointer package" && echo "$out" | grep -q "✓.*an UNMAPPED profile falls back to the positional default package" && echo "$out" | grep -q "✓.*the vocabulary is CLOSED" && echo "$out" | grep -q "✓.*dock: touch -> pointer swaps the package and the metrics together" && echo "$out" | grep -q "✓.*a hybrid FLAP produces one swap per settlement, not one per flap"',
			evidence = "artifacts/rich-skinning-v2/rs-a10-selectby.json",
			note = "RS-A10: controller selectBy keyed on the existing input-paradigm facts (touch/pointer/gamepad); installs at mount, swaps live on dock/undock through the atomic swap; identity held; dispose clean; manual swapPackage precedence",
		},
		{
			name = "tile-decision-honest",
			requirements = { "UI-STYLE-001" },
			run = 'test -f artifacts/rich-skinning-v2/rs-a11-tile-decision.json && grep -q "rs-m1" artifacts/rich-skinning-v2/rs-a11-tile-decision.json && test -f artifacts/rich-skinning-v2/feasibility/rs-m1-tilesize.json && grep -q "GO" artifacts/rich-skinning-v2/feasibility/rs-m1-tilesize.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a fill, a frame and a tile are one full-bleed child each"',
			evidence = "artifacts/rich-skinning-v2/rs-a11-tile-decision.json",
			note = "RS-A11: tile layer kind (if RS-M1 proved TileSize rule-settable) OR pre-tiled strips stated honestly — the shipped decision cites the probe artifact either way",
		},
		{
			name = "reference-packages",
			requirements = { "UI-STYLE-001", "UI-AGENT-001" },
			run = 'test -f examples/themes/fantasy_ornate.luau && test -f artifacts/rich-skinning-v2/rs-a12-fantasy-ornate.json && test -f artifacts/rich-skinning-v2/rs-a13-pixel-package.json && test -f assets/themes/fantasy-ornate/provenance.md && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*palette-only, metric-changing, font-changing and asset-backed are all represented" && echo "$out" | grep -q "✓.*METRIC-CHANGING moves the numbers a control resolves on every solve" && echo "$out" | grep -q "✓.*ASSET-BACKED declares content IDs only inside package data" && echo "$out" | grep -q "✓.*an incompatible schema is REJECTED with the offending field and the fix"',
			evidence = "artifacts/rich-skinning-v2/rs-a12-fantasy-ornate.json",
			note = "RS-A12/RS-A13: Fantasy Ornate exercises EVERY v2 capability through public APIs (per-capability exercise map cross-referenced in the artifact); the pixel package proves rendering=pixel + selection-changes-style; original art with recorded provenance",
		},
		{
			name = "platform-pair",
			requirements = { "UI-STYLE-001", "UI-INPUT-002" },
			run = 'test -f artifacts/rich-skinning-v2/rs-a14-platform-pair.json && grep -q "identity" artifacts/rich-skinning-v2/rs-a14-platform-pair.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*dock: touch -> pointer swaps the package and the metrics together" && echo "$out" | grep -q "✓.*a hybrid FLAP produces one swap per settlement, not one per flap" && echo "$out" | grep -q "✓.*the manual flag clears on a settlement even when the package does not move"',
			evidence = "artifacts/rich-skinning-v2/rs-a14-platform-pair.json",
			note = "RS-A14 standing acceptance row: glossy touch-metric + compact pointer-metric packages over the SAME fixture; selectBy proves the live dock/undock swap with mount identity held and geometry re-solved; captures of both packages on both form factors",
		},
		{
			name = "customization-ladder-docs",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_docs_cli && test -f artifacts/rich-skinning-v2/rs-a15-ladder-docs.json",
			evidence = "artifacts/rich-skinning-v2/rs-a15-ladder-docs.json",
			note = "RS-A15: the three-rung SwiftUI customization ladder documented end to end; worked rung-3 custom-skinned control registers namespaced roles, ships its own art, passes themes.checkCoverage, re-themes with packages; doc gate negative-proven",
		},
		{
			name = "studio-matrix-final-stamp",
			requirements = { "UI-FID-001" },
			run = 'python3 - <<\'PYEOF\'\nimport json, hashlib, os, sys\nd = json.load(open("artifacts/rich-skinning-v2/rs-a16-matrix.json"))\nrows = d["rows"]\nassert len(rows) >= 17, "matrix rows missing (five views x flat/ornate/pixel + pair swap rows)"\nfor r in rows:\n    p = os.path.join("artifacts/rich-skinning-v2", r["capture"])\n    assert os.path.isfile(p), "missing capture " + p\n    sha = hashlib.sha256(open(p, "rb").read()).hexdigest()[:16]\n    assert sha == r["captureSha256_16"], "capture drifted: " + p\n    if "textUnfit" in r:\n        assert r["textUnfit"] == 0, "unfit text in " + r["id"]\nprint("matrix ok:", len(rows), "rows")\nPYEOF',
			evidence = "artifacts/rich-skinning-v2/rs-a16-matrix.json",
			note = "RS-A16: five views x {flat, Fantasy Ornate, pixel} + platform-pair swap rows, ALL at the stage-final stamp; every capture sha-pinned and paired with a trace; supersedes the stale pre-fix Step 3.5 b-a13 rows as current matrix evidence",
		},
		{
			name = "cost-honesty",
			requirements = { "UI-STYLE-001" },
			run = 'test -f artifacts/rich-skinning-v2/rs-a17-cost.json && grep -qi "derated" artifacts/rich-skinning-v2/rs-a17-cost.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*layers and INSTANCES are different numbers, and both are published" && echo "$out" | grep -q "✓.*a stack with no plaque, and every flat package, publishes NOTHING"',
			evidence = "artifacts/rich-skinning-v2/rs-a17-cost.json",
			note = "RS-A17: per-package layer census (flat zero), swap timing, preload counts, memory deltas — Studio-derated and labeled; no device claim (RS-P3/Step 7)",
		},
		{
			name = "circle-button",
			requirements = { "UI-STYLE-001", "UI-AGENT-001" },
			-- POST-GATE FEATURE ROUND (director-requested, 2026-07-26): the iOS
			-- floating round "…" action. Registered here rather than in a new
			-- stage because it extends this stage's radii/skinning machinery and
			-- has to stay PASS with it. Source anchors, not just `test -f`: the
			-- shape tag, the two phantom rules and the resolved diameter metric
			-- are the three seams a silent revert would take out.
			run = 'grep -q "shapePrefix" src/tokens/sheet_model.luau && grep -q "Circle button — corner" src/tokens/sheet_model.luau && grep -q "Circle button — hairline" src/tokens/sheet_model.luau && grep -q "circleDiameter" src/themes/snapshot.luau && grep -q "button_shape.spec" tests/run.luau && grep -q "presentCircleFixture" examples/gallery/scenarios/theme_authoring.luau && test -f artifacts/rich-skinning-v2/rs-circle.json && for f in studio-neutral fantasy-ornate glossy-touch; do test -f "artifacts/rich-skinning-v2/captures/RS-CIRCLE_desktop_$f.png" || exit 1; done && test -f artifacts/rich-skinning-v2/captures/RS-CIRCLE_statewalk_desktop_studio-neutral.png && lune run tools/lune/check_flat_baseline >/dev/null',
			evidence = "artifacts/rich-skinning-v2/rs-circle.json",
			note = 'RS-CIRCLE: shape = "circle" — 1:1 from controls.button.height (solver-enforced through the existing `aspect` dim), one semantic icon or <=3 chars rejected at the schema boundary otherwise, pill+rim as phantom ::UICorner/::UIStroke rules on luau-shape-circle (zero instances on a flat theme, realUICorner = 0 measured live), skinnable through the ordinary `control` slot. Four captures across studio-neutral/fantasy-ornate/glossy-touch plus a hover/pressed state walk; flat baseline unchanged. RS-CIRCLE-P1/P2 human+device rows in review-packet.md',
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 1868",
			evidence = "artifacts/test.json",
			note = "RS-I1: stage-start floor 1336 must GROW (P1 1428, P2 1471, P3 1512, P4 1565, P5 1609, close-out 1703, RS-A16-D1/D1b fix round 1710, D2/D3 round 1724, RS-A16-D4 round 1741, RS-A16-D5 round 1757, gate 1789, POST-GATE circle-button feature round 1839, POST-GATE picker-polish round 1848, POST-GATE director findings 12/13/14 round 1868; raise this floor as seams land so the final number is the honest stage total)",
		},
		{
			name = "game-suite-untouched",
			requirements = { "UI-AGENT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1",
			note = "RS-I3: RascalRally suite green; no game edits, no migration this stage",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = 'if [ -n "${LUAUUI_PRIOR_GATES_NESTED:-}" ]; then echo "prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)"; exit 0; fi; a=artifacts/rich-skinning-v2/prior-gates-rerun.txt && tools/prior_gates.sh "$a" rich-skinning-v2 && grep -q "^DONE$" "$a" && failed="$(grep "^FAIL " "$a" | grep -v "^FAIL authoring-adaptive-ui " || true)" && test -z "$failed" && { ! grep -q "^FAIL authoring-adaptive-ui " "$a" || grep -q "^      PENDING  physical-and-human-rows$" "$a"; }',
			evidence = "artifacts/rich-skinning-v2/prior-gates.txt",
			note = "RS-I4: all 13 prior gates RE-RUN by this check at the source being judged, via tools/prior_gates.sh, writing artifacts/rich-skinning-v2/prior-gates-rerun.txt. It used to grep the STORED prior-gates.txt for the prose `13/13 PASS|12/13 PASS + authoring-adaptive-ui unregressed` and execute nothing (gate-integrity sweep 2026-07-29, defect B-1 — the PG-2 shape). authoring-adaptive-ui is CONDITIONALLY allow-listed on its standing PENDING physical/human row and must still carry that exact row to be forgiven; every other gate must be exit-zero. check_docs/prop_parity/registration/boundary/bench are now re-proved by the gates that own them rather than riding a stored record",
		},
		{
			name = "fresh-context-reviews",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/rich-skinning-v2/verifier-phase-gate.json && grep -qE "READY TO DECLARE|ACCEPT" artifacts/rich-skinning-v2/verifier-phase-gate.json && test -f artifacts/rich-skinning-v2/verifier-architecture.json && test -f artifacts/rich-skinning-v2/verifier-platform.json',
			evidence = "artifacts/rich-skinning-v2/verifier-phase-gate.json",
			note = "RS-I5: phase-gate + architecture + Roblox-platform fresh-context reviews (reactive-runtime added if controller/observer semantics changed), findings fixed or dispositioned",
		},
		{
			name = "physical-and-human-rows",
			requirements = { "UI-STYLE-001" },
			-- FAIL_ENVIRONMENT non-blocking is the established encoding for rows
			-- no available instrument can reach (cf. theme-packages-and-skinning):
			-- the review packet is the one-pass closing procedure
			state = "FAIL_ENVIRONMENT",
			releaseBlocking = false,
			evidence = "artifacts/rich-skinning-v2/review-packet.md",
			note = "RS-P1..P4: director readability/feel review of the package captures, physical-device pass (DPI crispness, ornament targeting, real dock/undock), the Step 7 low-end deferral, and capture readability as a standing human row — never closed by emulator or headless evidence; procedures in review-packet.md",
		},
	},
	["cross-platform-proof"] = {
		-- Roadmap Step 4. Acceptance ledger:
		-- artifacts/cross-platform-proof/acceptance-ledger.md (§0 is the
		-- metric/evidence ledger the contract requires before code).
		-- Registered BORN-RED 2026-07-26: every check fails until its evidence
		-- exists. The stage's whole subject is honest labelling, so the checks
		-- anchor on the SEAMS that keep a headless number from becoming a device
		-- claim, not merely on files existing.
		{
			name = "console-tenfoot-profile",
			requirements = { "UI-PERF-002", "UI-PARADIGM-003" },
			run = "grep -q \"consoleTenFoot\" bench/perf_profiles.luau && test -f artifacts/cross-platform-proof/rows/xp-a1-console-profile.json && python3 -c \"import json;d=json.load(open('artifacts/phase-4/perf.json'));assert any(r['device']=='consoleTenFoot' for r in d['runs']), 'no console runs'\"",
			evidence = "artifacts/cross-platform-proof/rows/xp-a1-console-profile.json",
			note = "XP-A1: the ten-foot profile joins the headless matrix (type floor 1.5x, overscan margins, Gamepad class), so a console-only layout cost cannot regress unseen",
		},
		{
			name = "production-shaped-scenes",
			requirements = { "UI-PERF-001", "UI-PERF-002" },
			run = "test -f artifacts/cross-platform-proof/rows/xp-a2-production-scenes.json && python3 tools/check_perf_scenes.py",
			evidence = "artifacts/cross-platform-proof/rows/xp-a2-production-scenes.json",
			note = "XP-A2: virtual list, native scroll/drag, dense HUD, stylesheet churn, async image, lifecycle churn — each present in artifacts/phase-4/perf.json with a real dataset",
		},
		{
			name = "theme-swap-invalidation-scenes",
			requirements = { "UI-PERF-002", "UI-STYLE-001" },
			run = "test -f artifacts/cross-platform-proof/rows/xp-a3-theme-swap-scenes.json && test -f artifacts/cross-platform-proof/rows/xp-a3-theme-swap-studio.json && python3 tools/check_perf_scenes.py --themes",
			evidence = "artifacts/cross-platform-proof/rows/xp-a3-theme-swap-scenes.json",
			note = "XP-A3: flat / metric-changing / asset-backed swaps are three scenes with three different invalidation shapes, not one averaged number",
		},
		{
			name = "metric-set-complete",
			requirements = { "UI-PERF-002" },
			run = "python3 tools/check_perf_metrics.py",
			evidence = "artifacts/phase-4/perf.json",
			note = "XP-A4: M1..M7 present on every record, with an explicit `blind` marker where the instrument cannot observe the quantity — a missing field must never read as zero",
		},
		{
			name = "budgets-baseline-and-frame-target",
			requirements = { "UI-PERF-002" },
			run = "python3 tools/check_perf_budgets.py",
			evidence = "bench/perf_budgets.json",
			note = "XP-A5: trend budget (measured baseline) AND one-directional frame ceiling (supported frame target); device budgets declared measured=false and never enforced from emulator/headless data",
		},
		{
			name = "regression-gate-falsified",
			requirements = { "UI-PERF-002", "UI-AGENT-001" },
			run = "lune run tools/lune/prove_perf_gate && grep -q '\"gateFailedAsExpected\": true' artifacts/cross-platform-proof/rows/xp-a6-regression-proof.json",
			evidence = "artifacts/cross-platform-proof/rows/xp-a6-regression-proof.json",
			note = "XP-A6: an intentional regression is injected and the gate FAILS naming the scene and budget; an unfalsified performance gate is decoration",
		},
		{
			name = "evidence-classes-separated",
			requirements = { "UI-PERF-002" },
			run = 'test -f artifacts/cross-platform-proof/rows/xp-a7-evidence-classes.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*refuses to enforce a device budget from a non-device class" && echo "$out" | grep -q "✓.*every record carries exactly one evidence class"',
			evidence = "artifacts/cross-platform-proof/rows/xp-a7-evidence-classes.json",
			note = "XP-A7: the one failure mode this stage exists to prevent — physical rows are structurally unfillable by emulator or headless data",
		},
		{
			name = "matrix-driver-reusable",
			requirements = { "UI-FID-001", "UI-ADAPT-001" },
			run = 'test -f src/preview/matrix_rows.luau && test -f tools/studio/device_matrix.luau && grep -q "matrix_rows.spec" tests/run.luau && ! grep -qE "\\bsamsung_|\\biphone_|\\bipad_|\\bhd_1080\\b|\\bxbox\\b" src/preview/matrix_rows.luau && grep -q "probeMethod" tools/studio/device_matrix.luau && grep -q "StopSimulationAsync" tools/studio/device_matrix.luau && test -f artifacts/cross-platform-proof/rows/xp-b3-virtualinput.json',
			evidence = "artifacts/cross-platform-proof/matrix.json",
			note = "XP-B1/XP-B2: the five roles resolve from the LIVE catalog through one pure, tested selection policy; no catalog id is hard-coded anywhere in the policy",
		},
		{
			name = "matrix-five-views-driven",
			requirements = { "UI-FID-001" },
			run = "python3 tools/check_xp_matrix.py",
			evidence = "artifacts/cross-platform-proof/matrix.json",
			note = "XP-B2/XP-B3/XP-B4: all five canonical rows driven live with the resolved configuration recorded, VirtualInput used only where supported, and every capture paired with a trace",
		},
		{
			name = "matrix-intentional-failure",
			requirements = { "UI-FID-001", "UI-AGENT-001" },
			run = "test -f artifacts/cross-platform-proof/rows/xp-b5-intentional-failure.json && grep -q '\"layoutFaultDetected\": true' artifacts/cross-platform-proof/rows/xp-b5-intentional-failure.json && grep -q '\"inputFaultDetected\": true' artifacts/cross-platform-proof/rows/xp-b5-intentional-failure.json",
			evidence = "artifacts/cross-platform-proof/rows/xp-b5-intentional-failure.json",
			note = "XP-B5/XP-B6: a deliberately broken layout and a deliberately suppressed input effect each FAIL their row in the live driver",
		},
		{
			name = "device-capture-path",
			requirements = { "UI-PERF-002", "UI-FID-001" },
			run = "python3 tools/check_device_captures.py",
			evidence = "artifacts/cross-platform-proof/device/studio-emulated.json",
			note = "XP-C1/XP-C2: Studio captures carry M1..M7 plus preflight, fixture state, engine/place/source identity and evidence class, in a file separate from the headless trend artifact",
		},
		{
			name = "spatial-seam-contracts",
			requirements = { "UI-SPATIAL-001" },
			run = 'test -f src/input/spatial.luau && test -f docs/adr/ADR-0021-spatial-seam.md && grep -q "spatial.spec" tests/run.luau && grep -q "presentationSpace" src/env/environment.luau && grep -q "FUTURE" src/render/target_contract.luau && for f in xp-d1-presentation-facts xp-d2-spatial-events xp-d3-future-target; do test -f "artifacts/cross-platform-proof/rows/$f.json" || exit 1; done',
			evidence = "artifacts/cross-platform-proof/rows/xp-d2-spatial-events.json",
			note = "XP-D1/XP-D2/XP-D3: presentation-space facts, optional spatial event data that leaves 2D callbacks valid, and a DECLARED-but-unimplemented world target",
		},
		{
			name = "no-vr-claim",
			requirements = { "UI-SPATIAL-001", "UI-AGENT-001" },
			run = 'lune run tools/lune/check_docs_cli >/dev/null && test -f artifacts/cross-platform-proof/rows/xp-d5-no-vr-claim.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*no shipped document claims VR support"',
			evidence = "artifacts/cross-platform-proof/rows/xp-d5-no-vr-claim.json",
			note = "XP-D4/XP-D5: the VR gate list is named and explicitly unmet, and a suite rule greps the shipped guide/API/source for support phrasings so the build fails if one appears",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 2058",
			evidence = "artifacts/test.json",
			note = "XP-I1: stage-start floor was 1868; the stage total is 2008 (+81 across perf_evidence, spatial, matrix_rows and the showcase demo picker to 1949, then +37 in the 2026-07-26 director round 10 device-fix pass: the hug dimension, the anchor-offset fill fix, the plain chrome opt-out, themed table-row insets, the clear chip sizing, the new Rating control and the theme picker hug/scroll), and +11 more on 2026-07-27 for clearButtonMode, the clear chip ceiling the rating star rung, the hug-sibling ceiling, the scroll canvas bleed the theme picker in its real host column, and the word-vs-phrase label rule; then +30 on 2026-07-27 for `compactLabel` and the framework's own standard icon set (the fit ladder measured under all nine packages, the closed one-key grammar and its six rejections, the solver-verdict/paint-seam agreement, the table toggle's two $-anchored matchers still matching, the framework icon rung with its per-package opt-out, and the two tint-role vocabularies pinned to each other), and +3 for the showcase demo list, which was a plain VStack and therefore ran nine demos off the bottom of a phone with no way to scroll to them (director report 2026-07-27, Pixel Quest), and +2 net for the rating strip, which now GROUPS at the glyph's own pitch and centres in its column instead of spreading its stars across whatever slack the caller's cell had (director ruling 2026-07-27, superseding round 12's 'it FILLS the cell'), and +3 for the clipping-container glow gutter — a package's shadow paints outside its box and was cut at every scroll container's cross axis, where no scrolling can ever reach it (director report 2026-07-27, Glossy Mobile on a phone), and +4 for the chrome full-bleed fix — a decoration sized `fromScale(1,1)` resolves against its host's PADDED content box, so every skinned host with a UIPadding drew its plate inside the padding while the solver laid content out against the node's own rect (found live in Studio: a playlist row's text hung 2px off the left edge of its own plate), and +4 for the paradigm-aware star run — the gap between marks is now DERIVED from each package's own iconSizes and widens under touch, because a fingertip needs more room between marks than a cursor (director 2026-07-27: Compact Pointer's `xs` was 2px against a 12px star), and +4 for `Table.scrolls` — a table's body is a viewport by default, which is wrong when the table is one block on a page: in landscape the playlist's header ate 45-55% of the screen and only the rows could move (director report 2026-07-27). The floor is the FINAL number, so a regression of the tests this stage added fails here.",
		},
		{
			name = "showcase-place",
			requirements = { "UI-AGENT-001" },
			-- XP-S1..XP-S6. The place was shipped before it was ledgered, which a
			-- fresh-context review named: the guide asserted live behaviour that
			-- nothing on disk recorded. This check is the disk half.
			run = "test -f examples/gallery/client/demo_picker.luau && test -f examples/places/LuauUI-Showcase.rbxl && grep -q 'LuauUI-Showcase' tools/build_places.sh && grep -q 'LuauUIShowcaseAPI' examples/gallery/client/init.client.luau && grep -q 'other.bottom' examples/gallery/client/init.client.luau && grep -q 'The hands-on place' docs/guide/11-device-verification.md && grep -q 'XP-S6' artifacts/cross-platform-proof/acceptance-ledger.md && test -f artifacts/cross-platform-proof/rows/xp-s-showcase.json && grep -q 'scopedCore' examples/gallery/client/init.client.luau",
			evidence = "examples/places/LuauUI-Showcase.rbxl",
			note = "XP-S1..S7: the hands-on place exists, is built, publishes its pointer-free drive API, reserves only the TOP edge of coreSafeInsets, scopes each demo so a swap reclaims its reactive state, and is documented and ledgered with what it cannot prove",
		},
		{
			name = "game-untouched",
			requirements = { "UI-AGENT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1",
			note = "XP-I2: RascalRally suite green; this stage changes no game code and no Sponsor behavior",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = 'if [ -n "${LUAUUI_PRIOR_GATES_NESTED:-}" ]; then echo "prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)"; exit 0; fi; a=artifacts/cross-platform-proof/prior-gates-rerun.txt && tools/prior_gates.sh "$a" cross-platform-proof && grep -q "^DONE$" "$a" && failed="$(grep "^FAIL " "$a" | grep -v "^FAIL authoring-adaptive-ui " || true)" && test -z "$failed" && { ! grep -q "^FAIL authoring-adaptive-ui " "$a" || grep -q "^      PENDING  physical-and-human-rows$" "$a"; }',
			evidence = "artifacts/cross-platform-proof/prior-gates.txt",
			note = "XP-I3: all 14 prior gates RE-RUN by this check at the source being judged, via tools/prior_gates.sh, writing artifacts/cross-platform-proof/prior-gates-rerun.txt. It used to grep the STORED prior-gates.txt for `ALL PASS` plus the absence of a `^FAIL ` line and execute nothing (gate-integrity sweep 2026-07-29, defect B-1 — the PG-2 shape). Note the stored file already had to be hardened once against a self-contradicting body, which is what a hand-written operand invites. authoring-adaptive-ui is CONDITIONALLY allow-listed on its standing PENDING physical/human row; every other gate must be exit-zero",
		},
		{
			name = "docs-and-registration",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_docs_cli >/dev/null && lune run tools/lune/check_registration_cli >/dev/null && test -f docs/guide/11-device-verification.md && grep -q '11-device-verification' docs/guide/README.md && grep -q 'StudioTestService' docs/guide/11-device-verification.md && grep -q 'do not claim per-client' docs/guide/11-device-verification.md && grep -q 'StopSimulationAsync' docs/guide/11-device-verification.md && test -f docs/lessons/capability-probes-must-be-tri-state.md",
			note = "XP-I4/XP-B7: the device-verification chapter states what each instrument proves, what it cannot, and where StudioTestService is and is not appropriate",
		},
		{
			name = "fresh-context-reviews",
			requirements = { "UI-AGENT-001" },
			-- READS THE `verdict` FIELD, not the file. The earlier form grepped the
			-- whole document for an accept token, so a report that merely QUOTED
			-- one — a findings list, a disposition line, a sentence about a prior
			-- round — passed this check while its own verdict said NOT READY. The
			-- round-4 verifier found it and had to write its entire report around
			-- the words it was not allowed to use, which is the tell that the
			-- check was measuring the wrong thing.
			run = "test -f artifacts/cross-platform-proof/verifier-platform.json && python3 -c \"import json,sys; d=json.load(open('artifacts/cross-platform-proof/verifier-phase-gate.json')); sys.exit(0 if d.get('verdict') in ('READY TO DECLARE', 'ACCEPT') else 1)\"",
			evidence = "artifacts/cross-platform-proof/verifier-phase-gate.json",
			note = "XP-I5: fresh-context phase-gate + Roblox-platform reviews run against the METHODS and the CLAIMS, not just the code; findings fixed and affected evidence rerun. The check reads the verifier's own `verdict` field — a quoted accept token elsewhere in the document does not pass it",
		},
		{
			name = "physical-and-human-rows",
			requirements = { "UI-PERF-002" },
			state = "FAIL_ENVIRONMENT",
			releaseBlocking = false,
			evidence = "artifacts/cross-platform-proof/review-packet.md",
			note = "XP-P1..P4: weakest supported physical touch device, physical gamepad/ten-foot path, desktop-retail baseline, and the human honesty/legibility review — no instrument in this build can reach them; procedures in review-packet.md",
		},
	},

	["sponsor-framework-gaps"] = {
		-- Roadmap Step 5. Acceptance ledger:
		-- artifacts/sponsor-framework-gaps/acceptance-ledger.md (BORN-RED
		-- 2026-07-27) with artifacts/sponsor-framework-gaps/responsibility-ledger.md
		-- deciding ownership before code. Checks anchor on the Sponsor-shaped
		-- gallery rows and the headless contracts; a fixture-local workaround
		-- cannot satisfy a framework row because every row names public API
		-- evidence (specs in tests/run.luau + scenario registration), not
		-- screenshots alone.
		{
			name = "motion-authority",
			requirements = { "UI-MOTION-001", "UI-STYLE-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*setTarget touches neither value nor velocity (the interruptibility invariant)" && echo "$out" | grep -q "✓.*a seeded release velocity produces a continuous first frame (no seam)" && echo "$out" | grep -q "✓.*chases a target that moves mid-flight and lands on the MOVED one" && echo "$out" | grep -q "✓.*fires on the radius frame, well before the settle epsilon would" && echo "$out" | grep -q "✓.*commits every value in ONE transaction per stepped frame" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-m1.json SF-M1 SF-M2 SF-M3 SF-M7 && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-m2.json SF-M2 && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-m7.json SF-M7',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-m1.json",
			note = "SF-M1..M3/M7: interruptible velocity-seeded classes, live-target chase, perceptual arrival, presentation-channel authority — deterministic under an injected clock AND live in the gallery",
		},
		{
			name = "choreography-and-transitions",
			requirements = { "UI-MOTION-002" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*interrupt at EVERY beat boundary leaves the declared end state, in order" && echo "$out" | grep -q "✓.*an interrupt MID-beat lands every remaining terminal and nothing persists half-painted" && echo "$out" | grep -q "✓.*the branch scope disposes exactly once, at done" && echo "$out" | grep -q "✓.*a re-entry mid-exit reverses from the value it had, without a jump" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-m4.json SF-M4 && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-m6.json SF-M6',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-m4.json",
			note = "SF-M4/SF-M6: interrupted celebration resolves clean at every beat boundary; structural enter/exit transitions dispose exactly once and reverse on re-entry",
		},
		{
			name = "reduced-motion-parity",
			requirements = { "UI-MOTION-003" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*under reduced motion the flight is instant and the arrival still fires" && echo "$out" | grep -q "✓.*an informational value KEEPS RUNNING under RM, quantized to 250 ms writes" && echo "$out" | grep -q "✓.*under reduced motion the SAME events fire and the terminal states match (SF-M5)" && echo "$out" | grep -q "✓.*under reduced motion the same toasts appear for the same durations (SF-T3)" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-m5.json SF-M5 && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-t3.json SF-T3',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-m5.json",
			note = "SF-M5/SF-T3: RM substitutes, never deletes — same terminal states, same semantic events, timers still deplete",
		},
		{
			name = "unified-collection",
			requirements = { "UI-COLLECT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*selection is single and survives a live re-sort (SF-L1)" && echo "$out" | grep -q "✓.*churn never remounts a row: one cell factory run per key" && echo "$out" | grep -q "✓.*navigation SKIPS ineligible rows and never lands on one (SF-L3)" && echo "$out" | grep -q "✓.*the armed row keeps its focusability while the interaction lives" && echo "$out" | grep -q "✓.*a foreign payload lands on the row the game asked for" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-l1.json SF-L1 SF-L3 && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-l3.json SF-L3',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-l1.json",
			note = "SF-L1/SF-L3: one construct windows + selects + reorders + accepts drops with stable identity under live churn; focus-skip predicate with the in-progress-target exemption",
		},
		{
			name = "edge-autoscroll",
			requirements = { "UI-DRAG-003" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*dwelling at the bottom edge arms, scrolls, and re-resolves the verdict IN THE SAME frame" && echo "$out" | grep -q "✓.*short content is INERT: bands never arm when there is nothing to scroll" && echo "$out" | grep -q "✓.*clamps at the canvas end and STAYS armed (no re-paying the dwell)" && echo "$out" | grep -q "✓.*edge autoscroll dwells, ramps, clamps, and keeps the verdict fresh EVERY frame (SF-L2)" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-l2.json SF-L2',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-l2.json",
			note = "SF-L2: dwell/ramp/speed model with frame-accurate hover re-resolve, clamp-stays-armed, short-content inertness",
		},
		{
			name = "drag-public-contract",
			requirements = { "UI-DRAG-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*mounts the declarations: the card acquires a detector, the slots register" && echo "$out" | grep -q "✓.*arm -> navigate -> commit drives the SAME session and the SAME legality" && echo "$out" | grep -q "✓.*the non-pointer path drives ONE session to both terminals (SF-D4)" && echo "$out" | grep -q "✓.*an illegal drop rejects EXACTLY once" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-d1.json SF-D1 SF-D4 SF-D5 && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-d4.json SF-D4 && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-d5.json SF-D5',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-d1.json",
			note = "SF-D1/D4/D5: cross-container payload drag through public API; the non-pointer paradigm shares the session and legality model; illegal drops reject visibly with a reason",
		},
		{
			name = "velocity-and-promotion",
			requirements = { "UI-DRAG-002" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*answers zero until it has two samples" && echo "$out" | grep -q "✓.*estimates first-vs-last across the retained window" && echo "$out" | grep -q "✓.*drops samples older than the window: a flick after a pause reads as a FLICK" && echo "$out" | grep -q "✓.*promotion is a MAGNITUDE test, not two axis tests" && echo "$out" | grep -q "✓.*the same travel is a drag on a mouse and still a tap on a finger" && echo "$out" | grep -q "✓.*a release under the promotion gate starts NO session (SF-D3)" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-d3.json SF-D3',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-d3.json",
			note = "SF-D2/SF-D3: rolling-window release velocity with the zero-seed cancel path; shared promotion tokens per input class, tap preserved under threshold",
		},
		{
			name = "paint-extensions",
			requirements = { "UI-PAINT-001", "UI-STYLE-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the wash is a role BLEND on its own node, and the card keeps its state fill (SF-P1)" && echo "$out" | grep -q "✓.*the dim treatment rides the authored tint channel, both ends themable (SF-P2)" && echo "$out" | grep -q "✓.*the stroke pulse rides ONE bound prop and leaves nothing behind (SF-P3)" && echo "$out" | grep -q "✓.*marker #12 carries the DECLARED theming-exempt hue, and nothing else does" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-p1.json SF-P1 && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-p2.json SF-P2 && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-p3.json SF-P3 && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-p4.json SF-P4 && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-p5.json SF-P5',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-p1.json",
			note = "SF-P1..P5: continuous color, image tint/scale-mode, public stroke, zIndex override, fractional markers — each with a clean authority audit while live",
		},
		{
			name = "toast-presentation",
			requirements = { "UI-PRESENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a toast never joins the stack and never moves focus (SF-T1)" && echo "$out" | grep -q "✓.*the control beneath a live toast still activates" && echo "$out" | grep -q "✓.*no toast node is focusable, so no navigation can ever reach one" && echo "$out" | grep -q "✓.*a burst shows three, queues the rest, and drops at the cap WITH a reason (SF-T2)" && echo "$out" | grep -q "✓.*priority never truncates a showing toast" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-t1.json SF-T1 SF-T2 && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-t2.json SF-T2',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-t1.json",
			note = "SF-T1/SF-T2: input-transparent self-retiring stack; priority, queue cap, read-floor dwell, supersede proven headlessly",
		},
		{
			name = "async-avatars",
			requirements = { "UI-ASYNC-001", "UI-NATIVE-008" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a staggered load ends with every avatar ready" && echo "$out" | grep -q "✓.*failure keeps the placeholder and reports" && echo "$out" | grep -q "✓.*retry spends its budget a second apart and then gives up for the session (SF-A2)" && echo "$out" | grep -q "✓.*preload warms a declared set so a debuting composite skips the placeholder (SF-A3)" && echo "$out" | grep -q "✓.*the live-transport step degrades honestly with no engine seam (SF-A4 stays E3)" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-a1.json SF-A1 SF-A2 SF-A3 SF-A4 && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-a4.json SF-A4',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-a4.json",
			note = "SF-A1..A4: silent presentable failure, bounded retry, preload seam, stale-rejection under churn, live transport proof",
		},
		{
			name = "billboard-fixture",
			requirements = { "UI-WORLD-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the world-anchored steps degrade honestly when the engine seam is absent" && echo "$out" | grep -q "✓.*the depleting ring is an INFORMATIONAL timer that reaches empty on wall clock" && echo "$out" | grep -q "✓.*the omen unmounts and remounts with the scope, and the value keeps its terminus" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-w1.json SF-W1',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-w1.json",
			note = "SF-W1: omen-shaped display-only billboard: live bindings, RM, registry-neutral teardown; input rows stay out of contract",
		},
		{
			name = "semantic-feedback",
			requirements = { "UI-FEEDBACK-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*an invented verb is an authoring error that lists the vocabulary" && echo "$out" | grep -q "✓.*fires exactly once per press, on the causal frame, after the effect" && echo "$out" | grep -q "✓.*a disabled control emits nothing" && echo "$out" | grep -q "✓.*presenter.emitFeedback is the seam a drag session commits through" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-f1.json SF-F1',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-f1.json",
			note = "SF-F1: causal-frame semantic events through one seam; LuauUI plays nothing",
		},
		{
			name = "sponsor-gallery-registered",
			requirements = { "UI-AGENT-001", "UI-DIAG-001" },
			run = 'Q=$(printf "\\042"); for s in sponsor_motion sponsor_celebration sponsor_list sponsor_drop sponsor_toast sponsor_avatars sponsor_markers sponsor_billboard; do grep -q "$Q$s$Q," examples/gallery/scenarios/init.luau || { echo "scenario $s not registered in the shared registry"; exit 1; }; done; test "$(ls examples/gallery/scenarios/sponsor_*.luau | wc -l)" -eq 8 && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*every scenario is registered in the gallery registry, in order" && echo "$out" | grep -q "✓.*every scenario exports title, ledgerRows and build" && echo "$out" | grep -q "✓.*every scenario mounts its screen through the real presenter"',
			evidence = "examples/gallery/scenarios/init.luau",
			note = "SF: all EIGHT Sponsor scenarios are asserted BY NAME as registry entries, the scenario-module count is pinned at 8 so a ninth fixture cannot appear off-registry, and the suite proves registration order plus that each one mounts through the real presenter. It used to be `grep -q sponsor init.luau` — one lowercase token, comments included, which said nothing about the eight scenarios and nothing at all about the ABSENCE of a second surface, which is the actual claim (gate-integrity sweep 2026-07-29, defect B-5). Q=$(printf 042) supplies the double quote: a backslash-escaped quote inside a Lua single-quoted string collapses to a bare quote and silently changes the shell meaning",
		},
		{
			name = "lifecycle-churn",
			requirements = { "UI-LIFE-002" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*50 build/step/dispose cycles return the core counters to baseline" && echo "$out" | grep -q "✓.*churn with exits in flight returns the core to baseline" && echo "$out" | grep -q "✓.*churning toasts through mount and retire returns the core to baseline" && echo "$out" | grep -q "✓.*build/mount/reorder/drop/dispose returns the core to baseline" && echo "$out" | grep -q "✓.*preload churn returns the provider" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-c1.json SF-C1',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-c1.json",
			note = "SF-C1: every Sponsor scenario mount/reset/dispose cycle returns registries to baseline — motion clocks, transition scopes, and toast timers included",
		},
		{
			name = "preferred-text-axis",
			requirements = { "UI-NATIVE-006" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the row height is DERIVED from the theme snapshot, never typed" && echo "$out" | grep -q "✓.*the window RE-DERIVES on a live rotation, with no reset (R2-F7)" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-c2.json SF-C2',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-c2.json",
			note = "SF-C2: densest Sponsor fixture at the largest preference — reserved bounds match paint, nothing clips",
		},
		{
			name = "five-view-matrix",
			requirements = { "UI-FID-001", "UI-ADAPT-001" },
			-- verifier PG-2: evidence must be a FILE (gate.luau requires isFile), and
			-- the check now validates every row's own ok flag instead of `ls`
			run = "python3 -c \"import json,glob; rows=[json.load(open(p)) for p in glob.glob('artifacts/sponsor-framework-gaps/rows/matrix/*.json')]; assert len(rows)==5, f'expected 5 rows, got {len(rows)}'; bad=[r['row'] for r in rows if not r.get('ok')]; assert not bad, f'rows not ok: {bad}'\"",
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-c3.json",
			note = "SF-C3: the existing five-view driver runs the Sponsor gallery rows — all five row records ok:true; injected input honestly labeled; captures paired with traces",
		},
		{
			name = "perf-scene",
			requirements = { "UI-PERF-002" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the stress scene runs 20 concurrent springs and RESTS at zero cost (SF-M8)" && python3 tools/check_sf_rows.py artifacts/sponsor-framework-gaps/rows/sf-m8.json SF-M8 SF-C4',
			evidence = "artifacts/sponsor-framework-gaps/rows/sf-m8.json",
			note = "SF-M8/SF-C4: dense motion + list scene as evidence-classed regression data; physical low-end row stays in the review packet",
		},
		{
			name = "ui-designer-reviews",
			requirements = { "UI-AGENT-001" },
			run = "test -f artifacts/sponsor-framework-gaps/ui-designer-spec.md && test -f artifacts/sponsor-framework-gaps/ui-designer-review.md && grep -qi 'disposition' artifacts/sponsor-framework-gaps/ui-designer-review.md",
			evidence = "artifacts/sponsor-framework-gaps/ui-designer-review.md",
			note = "SF-R1/SF-R2: the named specialist ran before implementation and on the integrated result; every in-scope finding carries a disposition",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 2567",
			evidence = "artifacts/test.json",
			note = "SF-R4: stage-start floor was 2075; the stage total is 2567 (+492 over the 2075 start: the five implementation packages, the eight Sponsor scenarios, and the review rounds' pins — detector-tap, echo guard, detached flights, retiring-surface exclusion incl. the sibling boundary, disabled-source gate, runtime quarantines, long-lived-core churn, the live-found toast paint-width pin, the round-2 fireSettle subscriber quarantine, and the director fix round's pins — grabAnchor default/preserve, RR-instant commit with the landed wash, the centered scale pivot, the virtual-controller round's pins — device-driven armed flow, cancel/re-arm, horizontal hand navigation — and the director rounds three through six: float ring, one-plate rows, held-source guarantee, armOnTap). The floor is the FINAL number so a regression of this stage's own tests fails here (verifier PG-4)",
		},
		{
			name = "game-untouched",
			requirements = { "UI-AGENT-001" },
			run = "cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1",
			note = "SF-R4: RascalRally suite green; Step 5 changes no game code and no Sponsor behavior — the fixtures are Sponsor-SHAPED, not the game",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = 'if [ -n "${LUAUUI_PRIOR_GATES_NESTED:-}" ]; then echo "prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)"; exit 0; fi; a=artifacts/sponsor-framework-gaps/prior-gates-rerun.txt && tools/prior_gates.sh "$a" sponsor-framework-gaps && grep -q "^DONE$" "$a" && failed="$(grep "^FAIL " "$a" | grep -v "^FAIL authoring-adaptive-ui " || true)" && test -z "$failed" && { ! grep -q "^FAIL authoring-adaptive-ui " "$a" || grep -q "^      PENDING  physical-and-human-rows$" "$a"; }',
			evidence = "artifacts/sponsor-framework-gaps/prior-gates.txt",
			note = "SF-R4: all 15 prior gates RE-RUN by this check at the source being judged, via tools/prior_gates.sh, writing artifacts/sponsor-framework-gaps/prior-gates-rerun.txt. It used to grep the STORED prior-gates.txt for `ALL PASS` plus the absence of a `^FAIL ` line and execute nothing (gate-integrity sweep 2026-07-29, defect B-1 — the PG-2 shape), and that stored record openly conceded its per-gate rerun was recorded at a 2536-era close state, not the final source. authoring-adaptive-ui is CONDITIONALLY allow-listed on its standing PENDING physical/human row; every other gate must be exit-zero",
		},
		{
			name = "docs-and-adr",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_docs_cli >/dev/null && test -f docs/adr/ADR-0022-sponsor-framework-gaps.md && grep -q '2026-07-27 re-audit' docs/reference/sponsor-view-parity.md",
			evidence = "docs/adr/ADR-0022-sponsor-framework-gaps.md",
			note = "SF-R5: ADR for the decided motion/drag/collection architecture; the parity ledger re-marked from the fresh audit with evidence, stale roadmap claims corrected",
		},
		{
			name = "fresh-context-reviews",
			requirements = { "UI-AGENT-001" },
			run = "test -f artifacts/sponsor-framework-gaps/verifier-architecture.json && test -f artifacts/sponsor-framework-gaps/verifier-platform.json && python3 -c \"import json,sys; d=json.load(open('artifacts/sponsor-framework-gaps/verifier-phase-gate.json')); sys.exit(0 if d.get('verdict') in ('READY TO DECLARE', 'ACCEPT') else 1)\"",
			evidence = "artifacts/sponsor-framework-gaps/verifier-phase-gate.json",
			note = "SF-R3: fresh-context phase-gate + architecture + platform reviews on raw artifacts; the check reads the verdict FIELD (never a grep for an accept token)",
		},
		{
			name = "physical-and-human-rows",
			requirements = { "UI-MOTION-001", "UI-DRAG-001" },
			state = "FAIL_ENVIRONMENT",
			releaseBlocking = false,
			evidence = "artifacts/sponsor-framework-gaps/review-packet.md",
			note = "SF-R6: physical touch drag feel, real gamepad drag delivery, weakest-device performance, and the human motion-feel review cannot be closed by any instrument in this build; exact procedures in review-packet.md",
		},
	},
}

return manifest
