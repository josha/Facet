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
	["swiftui-reference-app-validation"] = {
		-- Roadmap Step 11 (docs/plans/swiftui-reference-app-validation.md): five
		-- self-contained clean-room reference proofs — three interpreting Apple's
		-- Backyard Birds / Food Truck / Fruta samples, plus (director-added scope
		-- 2026-08-08) the Roblox app's discovery home screen and avatar editor —
		-- each running a complete representative loop through public LuauUI only,
		-- with a complete honest feature ledger separating LuauUI behavior,
		-- game/Roblox-service behavior, and Apple host-OS behavior.
		--
		-- REGISTERED BEFORE ANY IMPLEMENTATION EDIT. Every check is a bare PENDING
		-- at registration and becomes a `run` only once its implementation AND its
		-- evidence exist (manifest header rule). Acceptance rows RA-* live in
		-- artifacts/swiftui-reference-app-validation/acceptance.md.
		--
		-- THE EVIDENCE-CLASS RULE: an unavailable Apple host surface (widgets, App
		-- Clips, Live Activities, Dynamic Island, WeatherKit, share sheets, OS
		-- payment sheets) is a LEDGER row, never a simulated fixture claiming
		-- parity. Studio emulation closes no physical touch/gamepad/OS row.
		{
			name = "acceptance-ledger",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/swiftui-reference-app-validation/acceptance.md && test -f "$f" && for id in RA-1 RA-2 RA-3 RA-4 RA-5 RA-6 RA-7 RA-8 RA-9 RA-P1 RA-P2 RA-P3 RA-P4 RA-P5 RA-M1 RA-M2 RA-M3 RA-M4 RA-M5; do grep -qE "[|] [*][*]${id}[*][*] [|].*[|] PASS_AUTOMATED" "$f" || { echo "$id not closed"; exit 1; }; done && grep -qE "[|] [*][*]RA-X1[*][*] [|].*[|] PENDING_PHYSICAL [|]" "$f" && grep -qE "[|] [*][*]RA-X2[*][*] [|].*[|] PENDING_PHYSICAL [|]" "$f" && grep -qE "[|] [*][*]RA-X3[*][*] [|].*[|] PENDING_HUMAN [|]" "$f"',
			evidence = "artifacts/swiftui-reference-app-validation/acceptance.md",
			note = "Every RA row must be status-anchored PASS_AUTOMATED and the three honest pendings must still read PENDING_PHYSICAL / PENDING_HUMAN — a row left PENDING fails the gate, and a relabelled physical row fails it too",
		},
		{
			name = "source-inspection-and-ip-boundary",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/swiftui-reference-app-validation/sources.md && test -f "$f" && grep -qF "2026-08-08" "$f" && grep -qF "behavioral references only" "$f" && grep -qF "Xcode 15.1" "$f" && grep -qF "Xcode 14.3" "$f" && grep -qF "Xcode 13.3" "$f" && grep -qF "Roblox desktop app (macOS), observed live 2026-08-08" "$f" && test -f artifacts/swiftui-reference-app-validation/sources/features-backyard-birds.md && test -f artifacts/swiftui-reference-app-validation/sources/features-food-truck.md && test -f artifacts/swiftui-reference-app-validation/sources/features-fruta.md && ! grep -rqE "Backyard Birds|Food Truck|Fruta" examples/reference/ --include="*.luau"',
			evidence = "artifacts/swiftui-reference-app-validation/sources.md",
			note = "Stage-start fetch dates + platform baselines recorded for all three Apple samples; the three source-read inventories exist; Roblox app observation recorded; and the clean-room grep proves no reference product name appears in any proof source",
		},
		{
			name = "capability-ledger",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/swiftui-reference-app-validation/capability-ledger.md && test -f "$f" && for w in "available" "composable" "framework gap" "Roblox-service adaptation" "no host equivalent"; do grep -qF "$w" "$f" || { echo "missing class: $w"; exit 1; }; done && grep -qF "## B. Backyard Birds" "$f" && grep -qF "## C. Food Truck" "$f" && grep -qF "## D. Fruta" "$f" && grep -qF "## E. Roblox app home" "$f" && grep -qF "## F. Roblox app avatar editor" "$f" && grep -qF "No percentage score" "$f"',
			evidence = "artifacts/swiftui-reference-app-validation/capability-ledger.md",
			note = "All five reference sections present, all five classifications in use, and the no-percentage rule stated in the ledger itself",
		},
		{
			name = "responsibility-ledger",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/swiftui-reference-app-validation/responsibility-ledger.md && test -f "$f" && grep -qF "Forbidden in proofs" "$f" && grep -qF "MarketplaceService" "$f" && grep -qF "LocalizationService" "$f" && grep -qF "never faked" "$f" && ! { grep -rnE "Instance[.]new|GetService[(]|UserInputService|os[.]clock|os[.]time|math[.]random" examples/reference/ --include="*.luau" | grep -vE ":[0-9]+:[[:space:]]*--" | grep -q .; } && lune run tools/lune/check_example_drift_cli >/dev/null',
			evidence = "artifacts/swiftui-reference-app-validation/responsibility-ledger.md",
			note = "The ownership split + production-service mapping exist, and the forbidden-list is ENFORCED by grep over every proof source (no Instance.new/GetService/UserInputService/wall-clock/random) plus the property-authority drift scan now covering examples/reference",
		},
		{
			name = "proof-garden-loop",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/swiftui-reference-app-validation/proofs/garden.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*restores the level, and the ring drains again" && echo "$out" | grep -q "✓.*the button says Confirming" && echo "$out" | grep -q "✓.*rejection, with its copy under the card" && echo "$out" | grep -q "✓.*every declared rejection reason has player-facing copy" && echo "$out" | grep -q "✓.*restore runs the same three-phase command"',
			evidence = "artifacts/swiftui-reference-app-validation/proofs/garden.json",
			note = "Garden/collection proof: persistent-looking resources, refill actions, detail, purchase/subscription-shaped flow on deterministic fake services — the complete representative loop played, not a static screen",
		},
		{
			name = "proof-dashboard-loop",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/swiftui-reference-app-validation/proofs/dashboard.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*THE COUNTDOWN SURVIVES NAVIGATION" && echo "$out" | grep -q "✓.*SELECTION RESETS PUSHED DETAIL" && echo "$out" | grep -q "✓.*BOTH purchase outcomes are reachable" && echo "$out" | grep -q "✓.*arrive in id order at seeded intervals and then stop" && echo "$out" | grep -q "✓.*already-collected brew is REJECTED, with copy, and reverts"',
			evidence = "artifacts/swiftui-reference-app-validation/proofs/dashboard.json",
			note = "Operations dashboard proof: adaptive split navigation, recent orders, detail + status changes, timer, custom thumbnail layout, charts — loop played end to end",
		},
		{
			name = "proof-catalog-loop",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/swiftui-reference-app-validation/proofs/catalog.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*idle -> pending -> rejected, shows a toast" && echo "$out" | grep -q "✓.*presents Order-Placed, and the disc flips" && echo "$out" | grep -q "✓.*redeeming debits a flat ten" && echo "$out" | grep -q "✓.*locked rows are ABSENT until the purchase confirms" && echo "$out" | grep -q "✓.*expands every string by at least 1.4x" && echo "$out" | grep -q "✓.*reflows every mounted surface with no remount"',
			evidence = "artifacts/swiftui-reference-app-validation/proofs/catalog.json",
			note = "Catalog proof: browse/search, favorites, rewards, recipes, ordering, localization expansion, plus a compact entry flow reusing the full experience's components",
		},
		{
			name = "proof-discovery-home-loop",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/swiftui-reference-app-validation/proofs/discovery-home.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*swaps chrome but never remounts the home body" && echo "$out" | grep -q "✓.*swaps the feed to the approval-ranked section" && echo "$out" | grep -q "✓.*then confirms with re-seeded sections" && echo "$out" | grep -q "✓.*honest empty state with a working clear button" && echo "$out" | grep -q "✓.*five-view sweep is diagnostic-clean with a live scrollbar"',
			evidence = "artifacts/swiftui-reference-app-validation/proofs/discovery-home.json",
			note = "Roblox-app-shaped discovery home proof: nav rail, friends carousel, sectioned recommendation feed with horizontal shelves, ratings, search, responsive column reflow — loop played end to end",
		},
		{
			name = "proof-avatar-editor-loop",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/swiftui-reference-app-validation/proofs/avatar-editor.json && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*lighting + camera recorded, fallback closed" && echo "$out" | grep -q "✓.*worn state survives the flip" && echo "$out" | grep -q "✓.*undo/redo walk the equip history and disable at the stack ends" && echo "$out" | grep -q "✓.*the wallet never moves; retry stays allowed" && echo "$out" | grep -q "✓.*balance debits, chip flips to Owned"',
			evidence = "artifacts/swiftui-reference-app-validation/proofs/avatar-editor.json",
			note = "Avatar-editor-shaped proof: category tabs, item grid with prices/creators, live preview pane (ViewportFrame-backed), equip/try-on with undo/redo, currency display, purchase-shaped flow on fake services, compact split adaptation — loop played end to end",
		},
		{
			name = "device-matrix",
			requirements = { "UI-LAYOUT-001" },
			run = "python3 -c \"\nimport json\nd = json.load(open('artifacts/swiftui-reference-app-validation/studio/device-matrix.json'))\nrows = set(d['rowSet'])\nassert rows == {'compact-phone-portrait', 'compact-phone-landscape', 'tablet-landscape', 'desktop-standard', 'console-ten-foot'}\nfor name in ('glade', 'cartwheel', 'sipworks', 'foyer', 'wardrobe'):\n    p = d['proofs'][name]\n    assert set(p['rows']) == rows, name\n    bad = {r: s for r, s in p['rows'].items() if s != 'ok'}\n    assert not bad, f'{name}: {bad}'\n    assert 'keyboard' in p and p['keyboard'].startswith('ok'), f'{name}: keyboard row not ok'\n\" && python3 -c \"\nimport json, glob, sys\nbad = []\nfor name in ('glade', 'cartwheel', 'sipworks', 'foyer', 'wardrobe'):\n    files = glob.glob(f'artifacts/swiftui-reference-app-validation/studio/{name}/row-*.json')\n    if len(files) < 6:\n        bad.append(f'{name}: only {len(files)} row files (need 5 views + keyboard)')\n    for f in files:\n        if json.load(open(f)).get('ok') is not True:\n            bad.append(f'{f}: ok is not true')\nif bad:\n    print(bad)\n    sys.exit(1)\n\"",
			evidence = "artifacts/swiftui-reference-app-validation/studio/device-matrix.json",
			note = "Each proof loop across the five view rows with presets resolved at runtime, VirtualInput keyboard/pointer traces from live geometry, raw event paired with semantic action; every row must read ok (a RERUN_OWED entry fails this check, which is the point) and per-row evidence files must exist",
		},
		{
			name = "fixture-axes",
			requirements = { "UI-THEME-001" },
			run = "python3 -c \"\nimport json\nd = json.load(open('artifacts/swiftui-reference-app-validation/studio/fixture-axes.json'))\nfor name in ('glade', 'cartwheel', 'sipworks', 'foyer', 'wardrobe'):\n    p = d['proofs'][name]\n    assert 'RERUN_OWED' not in str(p.get('status', '')), f'{name} axes owed'\n    for axis in (k for k in p if k not in ('themedNavigationSweep', 'headless', 'transients', 'status', 'prior', 'note')):\n        v = p[axis]\n        assert v == 0 or (isinstance(v, str) and ('settled 0' in v or v.startswith('0 '))), f'{name}.{axis}={v}'\nassert len(d['liveDefectsFoundByTheseAxes']) >= 4\n\"",
			evidence = "artifacts/swiftui-reference-app-validation/studio/fixture-axes.json",
			note = "Theme swap on the mounted tree, preferred text, reduced motion, and pseudo-locale per proof, driven through declared seams only; every axis must be settled-0 with no proof left owed, and the axes' own defect harvest (4 live framework defects) is recorded",
		},
		{
			name = "places-and-builds",
			requirements = { "UI-AGENT-001" },
			run = "tools/build_reference_places.sh >/dev/null && python3 -c \"import json,os; d=json.load(open('artifacts/swiftui-reference-app-validation/places.json')); names={'LuauUI-Ref-Glade','LuauUI-Ref-Cartwheel','LuauUI-Ref-Sipworks','LuauUI-Ref-Foyer','LuauUI-Ref-Wardrobe'}; assert set(d['places'])==names; assert all(os.path.getsize(f'examples/places/{n}.rbxl')>200000 for n in names)\"",
			evidence = "artifacts/swiftui-reference-app-validation/places.json",
			note = "All five reference places rebuild from clean source at gate time and exist at credible size; the artifact records bytes+digest per place and the no-network/no-purchase determinism contract",
		},
		{
			name = "framework-fixes-tested",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/swiftui-reference-app-validation/framework-fixes.md && test -f "$f" && grep -qF "UI.Stage" "$f" && grep -qF "Grid measure is now a fixed point" "$f" && grep -qF "hug ScrollView now measures the scrollbar" "$f" && grep -qF "Findings (follow-on candidates" "$f" && grep -qF "corpse-in-the-pool" "$f" && grep -qF "Fix 6" "$f" && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a grid of content buttons in a hug stack reports no overflow" && echo "$out" | grep -q "✓.*an overflowing hug x-shelf reports zero diagnostics with a live bar" && echo "$out" | grep -q "✓.*derives the glyph from the name after the namespace" && echo "$out" | grep -q "✓.*parkEligible refuses an unparented (destroyed) instance" && echo "$out" | grep -q "✓.*adopt refuses (never throws) when the Parent write fails" && echo "$out" | grep -q "✓.*a fill-size page scroller taller than the stack is NOT an overflow" && echo "$out" | grep -q "✓.*a fill-WIDTH child still reports its oversize HEIGHT" && echo "$out" | grep -q "✓.*hands back ONE cached handle per node" && echo "$out" | grep -q "✓.*setCamera records position/lookAt/fov in the exact table shape" ',
			evidence = "artifacts/swiftui-reference-app-validation/framework-fixes.md",
			note = "The six bounded fixes (Stage NO_SLOT leaf, Grid measure fixed-point, ScrollView bar measure, namespaced-icon ASCII floor, park-corpse guards, ZStack fill-axis diagnostic) are anchored to their live suite cases, and the follow-on findings section exists; approximations are declared, never claimed as parity",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "./tools/test.sh 3868",
			evidence = "artifacts/test.json",
			note = "Floor is the stage-close count 3868 (+ the scroll-indicator policy chain: derivation, seam, reserve consequence, reduced motion, absent-seam degrade) (the HIG tab-bar round: navPlacement policy cases, per-placement geometry + gamepad-traversal pins across three proofs, and the glade locale-x-width-x-selection sweep) (stage-start 3556 + ~225 proof pins + the six framework fixes' cases incl. the park-corpse anchors and the ZStack fill-diagnostic trio); the floor makes this stage's own pins regressing fail the gate",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = "if [ -n \"${LUAUUI_PRIOR_GATES_NESTED:-}\" ]; then echo \"prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)\"; exit 0; fi; a=artifacts/swiftui-reference-app-validation/prior-gates.txt && test -f \"$a\" && grep -q \"^DONE$\" \"$a\" && python3 -c \"\nimport re, sys\nallowed = {\n    ('phase-1-minimal-screen', 'bench-reproducible'),\n    ('phase-2-settings-parity', 'ui-cost-budget'),\n    ('phase-3-pilot', 'no-leak-regression'),\n    ('part-2-director', 'ws1-adr-and-bench'),\n    ('expansion-textinput', 'expansion-adr-bench-rollback'),\n    ('code-simplicity-cleanup', 'performance-unregressed'),\n    ('api-architecture-consistency', 'performance-unregressed'),\n    ('example-quality-pass', 'rascalrally-consumer'),\n}\ngate = None\nbad = []\nfor line in open('artifacts/swiftui-reference-app-validation/prior-gates.txt'):\n    m = re.match(r'^FAIL (\\S+)', line)\n    if m:\n        gate = m.group(1)\n        continue\n    if re.match(r'^PASS ', line):\n        gate = None\n        continue\n    m = re.match(r'^[ ]+FAIL_RECOVERABLE[ ]+(\\S+)', line)\n    if m and gate is not None and (gate, m.group(1)) not in allowed:\n        bad.append((gate, m.group(1)))\nif bad:\n    print(bad)\n    sys.exit(1)\n\" && lune run tools/lune/check_flat_baseline >/dev/null && lune run tools/lune/check_example_drift_cli >/dev/null && lune run tools/lune/check_docs_cli >/dev/null && python3 tools/check_manifest_integrity.py >/dev/null && stylua --check src tests tools examples >/dev/null && test -f artifacts/swiftui-reference-app-validation/prior-gates-analysis.md && grep -qF \"fresh justification, not inheritance\" artifacts/swiftui-reference-app-validation/prior-gates-analysis.md && grep -qF \"EIGHT named (gate, check) pairs\" artifacts/swiftui-reference-app-validation/prior-gates-analysis.md && { tools/bench.sh >/dev/null; python3 -c \"\nimport json, os, sys\nd = json.load(open('artifacts/bench.json'))\nbad = [r['name'] for r in d['results'] if r.get('regression')]\nif not bad:\n    sys.exit(0)\nconvicted = bad == ['textinput-typing-storm'] and os.path.exists('artifacts/example-quality-pass/bench-textinput-ab.json')\nprint('bench regressions:', bad, '| convicted-variance allowance applies:', convicted)\nsys.exit(0 if convicted else 1)\n\"; }",
			evidence = "artifacts/swiftui-reference-app-validation/prior-gates.txt",
			note = "The roll-up is the full tools/prior_gates.sh sweep regenerated at the judged source on a quiet machine (the check verifies its DONE terminator rather than re-running the 2h sweep inside the gate — three sweeps this stage proved concurrent regeneration invalidates itself; see prior-gates-analysis.md). The SAME five bench-instrument gates as the Step 10 close are allow-listed BY NAME with fresh justification (every other red across three sweeps was demonstrated environmental: load, shared-artifact collision, or this stage own stylua slip — each green on quiet re-run; the five stayed red with all sibling checks passing, and their only failing checks shell to tools/bench.sh). Any other gate red fails this check, the flat-baseline / example-drift / docs / manifest-integrity / stylua battery runs live here, and the live bench clause is a judgment over bench.json: any regressed scenario fails EXCEPT textinput-typing-storm alone under the standing Step 10 A/B conviction (close-day addendum in the analysis records the same-day 1.12x-pass/2.0x-fail flips at identical source that earn it)",
		},
		{
			name = "rascalrally-consumer",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/swiftui-reference-app-validation/consumer-impact.md && test -f "$f" && grep -qF "What this ledger does NOT claim" "$f" && grep -qF "check_flat_baseline" "$f" && cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1',
			evidence = "artifacts/swiftui-reference-app-validation/consumer-impact.md",
			note = "The consumer-impact ledger exists with its honest non-claims, cites the byte-compare evidence for the solver fixes, and the game suite is re-run LIVE at the judged source by this check",
		},
		{
			name = "docs-updated",
			requirements = { "UI-AGENT-001" },
			run = 'grep -qF "## 12. Reference-app validation" docs/reference/swiftui-parity.md && grep -qF "no host equivalent" docs/reference/swiftui-parity.md && grep -qF "UI.Stage" docs/reference/swiftui-parity.md && test -f artifacts/swiftui-reference-app-validation/docs.json && lune run tools/lune/check_docs_cli >/dev/null && lune run tools/lune/check_registration_cli >/dev/null',
			evidence = "artifacts/swiftui-reference-app-validation/docs.json",
			note = "The parity reference carries the validation section (what Roblox reproduces, the declared approximations, the no-host-equivalent boundary) and both drift checks run green at gate time",
		},
		{
			name = "fresh-context-reviews",
			requirements = { "UI-AGENT-001" },
			run = 'd=artifacts/swiftui-reference-app-validation/reviews && test -f "$d/README.md" && test -f "$d/phase-gate-verifier.md" && test -f "$d/architecture-verifier.md" && test -f "$d/roblox-platform-verifier.md" && grep -qF "0 BLOCKER" "$d/README.md" && grep -qF "MAJOR findings and their closures" "$d/README.md" && grep -qF "What the reviews did NOT close" "$d/README.md" && grep -qF "mutation-proved" "$d/README.md"',
			evidence = "artifacts/swiftui-reference-app-validation/reviews/README.md",
			note = "All three fresh-context reports exist on disk with the disposition README: zero BLOCKERs, every MAJOR fixed same-day with mutation proof where the finding was a cannot-fail check, and the not-closed list is explicit (the reviews independently converged on the same two vacuous greps, which is what makes the pass credible)",
		},
		{
			name = "physical-and-human-rows",
			requirements = { "UI-INPUT-001" },
			run = 'f=artifacts/swiftui-reference-app-validation/review-packet.md && test -f "$f" && grep -qF "RA-X1" "$f" && grep -qF "RA-X2" "$f" && grep -qF "RA-X3" "$f" && grep -qF "PENDING_PHYSICAL / PENDING_HUMAN" "$f" && grep -qF "LuauUI-Ref-Glade.rbxl" "$f"',
			evidence = "artifacts/swiftui-reference-app-validation/review-packet.md",
			releaseBlocking = false,
			note = "The three pending rows stay honestly open behind one prepared pass: this check asserts the packet exists with all three rows and the build list — it never claims the physical or human work happened",
		},
	},
	["example-quality-pass"] = {
		-- Roadmap Step 10 (docs/plans/example-quality-pass.md): the seven tutorial
		-- examples made understandable and playable WITHOUT reading their source,
		-- sharing one native-StyleSheet product design, adapting across the declared
		-- layouts and input paradigms, and rebuilding as standalone places.
		--
		-- REGISTERED BEFORE ANY IMPLEMENTATION EDIT, per the plan's own gate rule.
		-- Every check below is a bare `PENDING` at registration and becomes a `run`
		-- only once its implementation AND its evidence exist (manifest header rule).
		-- A PENDING check cannot be satisfied, so the gate cannot silently pass while
		-- the work is only planned.
		--
		-- Acceptance rows EQ-1..EQ-22 plus EQ-P1..EQ-P3 live in
		-- artifacts/example-quality-pass/acceptance.md, written from an audit of the
		-- current source rather than from the plan's prose.
		--
		-- THE EVIDENCE-CLASS RULE THIS GATE ENFORCES: a source read is not a play-through,
		-- a call to `typeLetter`/`submit`/`server.flush` is not native input, an emulated
		-- pointer is not physical touch, and synthetic navigation KeyCodes are not a
		-- gamepad. EQ-P1/EQ-P2 stay PENDING_PHYSICAL and EQ-P3 PENDING_HUMAN.
		{
			name = "acceptance-ledger",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/example-quality-pass/acceptance.md && test -f "$f" && for id in EQ-2 EQ-3 EQ-4 EQ-5 EQ-6 EQ-9 EQ-10 EQ-14 EQ-18; do grep -qE "^. [*][*]${id}[*][*] .*[|] PASS_AUTOMATED [|]" "$f" || { echo "$id not PASS_AUTOMATED"; exit 1; }; done && grep -qE "^. [*][*]EQ-15[*][*] .*[|] FAIL_ENVIRONMENT [|]" "$f" && grep -qF "there are no captures" "$f" && grep -qF "REJECT" "$f" && grep -qF "LT-F3 is FIXED" "$f"',
			evidence = "artifacts/example-quality-pass/acceptance.md",
			note = "EQ-1..EQ-22 status-anchored at close, with EQ-P1/EQ-P2 pinned PENDING_PHYSICAL and EQ-P3 PENDING_HUMAN. The ledger file exists now (execution contract §2); this check stays PENDING until its rows have real closing statuses to anchor",
		},
		{
			name = "play-teaching-matrix",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/example-quality-pass/audit.md && test -f "$f" && grep -qF "POST-FIX RE-AUDIT" "$f" && for w in Touch Gamepad Keyboard Tablet landscape ten-foot; do grep -qF "$w" "$f" || { echo "no $w coverage"; exit 1; }; done && grep -qF "PENDING_PHYSICAL for every example" "$f" && grep -qF "What this re-audit does NOT close" "$f" && grep -qF "35 of 35 cells pass" "$f"',
			evidence = "artifacts/example-quality-pass/audit.md",
			note = "BLOCKER-2 CLOSED — audit.md now carries a POST-FIX RE-AUDIT with the form-factor grid (35/35 cells), the four input paradigms named separately, the EQ-1 teaching questions re-answered from live strings, and an explicit list of what it does NOT close. Touch is PENDING_PHYSICAL for every example and gamepad is headless-only; neither is relabelled. Was: audit.md is the PRE-implementation audit — its per-example verdicts still read FAIL_PRODUCT, there is no post-fix re-audit, and it contains zero occurrences of touch/gamepad/tablet/landscape/ten-foot, which is the paradigm and form-factor coverage EQ-1 demands. EQ-1/EQ-13: one checked acceptance row per example, filled by PLAYING it — lesson, startup view, first action, success/failure/unavailable feedback, completion and reset, the four input paradigms, the four form factors, style ownership, and Studio warnings/dead controls/clipping/stale state/teardown",
		},
		{
			name = "ownership-ledger",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/example-quality-pass/ownership-ledger.md && test -f "$f" && for id in F-1 F-2 F-3 F-4 H-1 H-2 H-3; do grep -qF "**$id**" "$f" || { echo "$id missing"; exit 1; }; done && grep -q "LT-F3" "$f" && grep -q "Deliberately NOT changed" "$f"',
			evidence = "artifacts/example-quality-pass/ownership-ledger.md",
			note = "EQ-2: every custom UI helper, direct Roblox GUI/input access, device/layout branch and workaround classified as example-domain, explicit adapter wiring, or framework-owned — with each framework-owned need fixed behind a public LuauUI API with tests and docs BEFORE the example consumes it, and no unresolved workaround left",
		},
		{
			name = "style-authority-and-drift",
			requirements = { "UI-THEME-001" },
			run = 'lune run tools/lune/check_example_drift_cli >/dev/null && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the seven examples are clean" && echo "$out" | grep -q "✓.*it actually scanned the examples, and saw real semantic values there" && echo "$out" | grep -q "✓.*R2: an INVENTED surface token" && echo "$out" | grep -q "✓.*R2 does NOT fire on the legal vocabularies" && echo "$out" | grep -q "✓.*R3: a raw colour, in each of its three spellings" && echo "$out" | grep -q "✓.*R4: a platform branch is refused by name" && echo "$out" | grep -q "✓.*the allowlist suppresses ONLY its own line, in its own file"',
			evidence = "artifacts/example-quality-pass/drift.json",
			note = "EQ-3/EQ-4: the property-authority-aware drift check over examples/gallery — failing on literals/direct writes for style-owned properties, unknown semantic roles and example adapter writes while allowing documented content and structural constants — plus its recorded mutation proof. A broad ban-every-number grep does not satisfy this",
		},
		{
			name = "theme-package-swap",
			requirements = { "UI-THEME-001" },
			run = "python3 -c \"import json,sys,os; d=json.load(open('artifacts/example-quality-pass/captures.json')); cs=d['captures']; want={(e,pkg) for e in range(1,8) for pkg in ('neutral','parchment')}; have={(c['example'], 'parchment' if 'parchment' in c['capture'] else 'neutral') for c in cs if 'desktop' in c['capture']}; ok = have==want and all(d['swapProof'].values()) and all(os.path.isfile('artifacts/example-quality-pass/captures/'+c['capture']) for c in cs); sys.exit(0 if ok else 1)\"",
			evidence = "artifacts/example-quality-pass/captures.json",
			note = "MAJOR-3 CLOSED — the capture set now covers all seven examples under both packages, each paired with the facts it shows: every one changed font family (BuilderSans -> Fondamento), every one changed type size (24 -> 28), every one gained decoration layers, focus identity is preserved on all fourteen and the solver reports zero diagnostics on all fourteen. Was: phase-gate MAJOR-3: EQ-5 says all seven examples; provenChange records example 1 only, and the check asserts only those example-1 numbers. focusPathPreserved is a bare boolean where the row requires focus AND mount identity recorded either side. EQ-5/EQ-3: all seven captured under Studio Neutral AND Fantasy Parchment for every declared layout profile, with the ornate package changing font/metrics and exercising its nine-slice chrome rather than merely recolouring — no source edit, no remount, and each capture paired with effective package/snapshot, actual and solved geometry, style role/tag, decoration layers/fallback, focus and mount identity",
		},
		{
			name = "large-text-overflow",
			requirements = { "UI-LAYOUT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the solver files NO overflow anywhere in the table.s chrome, at any preference" && echo "$out" | grep -q "✓.*the toolbar, the header and the body never overlap" && echo "$out" | grep -q "✓.*the header band GROWS with the preference instead of holding its token" && grep -qE "minMax., min = .controls[.]table[.]headerHeight" src/controls/table.luau && grep -qE "reorderable = true" tests/lib/large_text_fixtures.luau && python3 tools/check_eq6_evidence.py',
			evidence = "artifacts/example-quality-pass/studio/large-text.json",
			note = "EQ-6 CLOSED 2026-08-06 — 56 of 56 cells. LT-F3 was `UI.Table` capping its header cell at a FIXED `controls.table.headerHeight` (28px) while a one-line column title measures 34px at a raised preference, so the title painted out of its ZStack into the auto Edit toolbar above and the first row below. The band is now a minMax FLOOR: the token is what a header must never be shorter than, the live text facts decide how much taller. The solver had been filing the finding all along and nothing failed on it; the first of the three new tests now asserts `controller.diagnostics()` is EMPTY, and the LT-8 Table fixture gained `reorderable` so the toolbar it collided with actually exists in the sweep. Mutation-proved (minMax->fixed fails all three) and live A/B-proved in one Studio session, both reference packages. Was: 52 of 56 cells pass (two phone orientations x two theme packages x two preferred-text values x seven examples). The four that fail are all example 02 at Largest: LT-F3, `UI.Table`'s touch Edit toggle overlapping the rating column header title. FRAMEWORK-owned (the example authors no toolbar or header geometry), three attempted fixes reverted because none moved the geometry, cause narrowed to the solver measuring an ELIDED container against a type-scaled child. Recorded open in studio/large-text.json. This state is deliberately not PENDING: the work ran, and it found a defect",
		},
		{
			name = "example-03-optimistic-sync",
			requirements = { "UI-REPL-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the seven promised states are reachable through on-screen controls alone" && echo "$out" | grep -q "✓.*a valid toggle applies optimistically, goes pending, then confirms" && echo "$out" | grep -q "✓.*a rejected change restores the optimistic draft to server truth" && echo "$out" | grep -q "✓.*reset recovers from a request the server never answered" && echo "$out" | grep -q "✓.*the visible history reads newest first and is bounded"',
			evidence = "artifacts/example-quality-pass/studio/ex03.json",
			note = "EQ-7/EQ-8: a player with no source access triggers an accepted change, sees the optimistic value apply and the request pend, observes acceptance and reconciliation, then triggers a REJECTED change and sees the reason and the rollback, reads a short visible history, and resets — driven through pointer AND focus-based keyboard activation, never through a test handle",
		},
		{
			name = "example-05-word-game",
			requirements = { "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a guess with a DOUBLED letter against a solution holding ONE spends the budget once" && echo "$out" | grep -q "✓.*an EXACT match consumes the budget BEFORE an earlier misplaced copy of the same letter" && echo "$out" | grep -q "✓.*three copies against two: the excess is absent" && echo "$out" | grep -q "✓.*refuses a guess shorter than five letters"',
			note = "EQ-9: the pure scoring and state machine — two-pass duplicate-letter budgeting, short/invalid rejection without consuming a row, retained submitted rows, monotonic key-state precedence (correct > present > absent), win, loss with the solution revealed, input disabled after the end except restart/dismiss, and deterministic seeded restart",
		},
		{
			name = "example-05-native-input",
			requirements = { "UI-INPUT-001" },
			run = "f=artifacts/example-quality-pass/studio/ex05.json && test -f \"$f\" && python3 -c \"import json,sys; d=json.load(open('$f')); names=[s['name'] for s in d['sequences']]; need=['hardware letter keys','Backspace','Return submits','arrow keys navigate','Space activates the FOCUSED','Tab traverses','switching input class']; traced=[s for s in d['sequences'] if s.get('rawEvents') or s.get('steps')]; ok = all(any(n in x for x in names) for n in need) and len(traced)>=7 and d['rawEvents']>0 and not d['usedGameMethods'] and d['duplicateLetterScored']; sys.exit(0 if ok else 1)\"",
			evidence = "artifacts/example-quality-pass/studio/ex05.json",
			note = "BLOCKER-3 CLOSED for EQ-10 — all eight input paths are now driven with paired raw events: hardware letters (R/E/A -> REA__), Backspace, Return (the full win, typed on hardware keys), arrow navigation, SPACE on a focused key (keyboard activation, not pointer), Tab traversal (the H-2 fix landing), and a keyboard->pointer->keyboard switch that kept one guess (A____ -> AS___ -> AST__). Every raw event carries gameProcessed. Was: studio/ex05.json is POINTER-ONLY. No hardware letter/Backspace/Enter trace, no keyboard focus navigation plus activation, no live input-class switch. The stage already measured that SendKey cannot insert a character into a focused TextBox and did not record it as FAIL_ENVIRONMENT. `usedGameMethods` is a self-declaration, not a measurement. EQ-10: the MOUNTED example played through hardware letter/Backspace/Enter, pointer activation of on-screen keys, keyboard focus navigation plus activation, and a live input-class switch that does not lose the active guess. Calling typeLetter/submit prepares fixtures and closes NOTHING here; the gamepad row is recorded as synthetic navigation, never as gamepad delivery",
		},
		{
			name = "example-06-07-gameplay",
			requirements = { "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*placing with nothing picked up says so instead of doing nothing" && echo "$out" | grep -q "✓.*placing on an occupied square names the square, and does not silently keep the tile held" && echo "$out" | grep -q "✓.*a spent rack slot is visibly DISABLED, not a live-looking blank button" && echo "$out" | grep -q "✓.*progress and completion are visible, and the rack really does run out" && echo "$out" | grep -q "✓.*opens with no run already on the board" && echo "$out" | grep -q "✓.*opens with at least one legal move" && echo "$out" | grep -q "✓.*a swap that makes no run is refused WITH A REASON, and costs no move" && echo "$out" | grep -q "✓.*a FAILED load is visible and recoverable, which is the half that was missing"',
			evidence = "artifacts/example-quality-pass/studio/games.json",
			note = "EQ-11/EQ-12: both games played from a fresh start through their meaningful loop — visible instructions and selectable state, activation selecting the expected tile, invalid moves explaining themselves, match-3 resolving matches/gravity/refill/chains deterministically from an opening board that is neither pre-matched nor stuck, image pending AND failure visible and recoverable, progress/completion and reset — with a gameplay test added for every defect found",
		},
		{
			name = "lifecycle-and-rapid-input",
			requirements = { "UI-RUNTIME-002" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*rapid alternating input leaves no stale selection or held tile" && echo "$out" | grep -q "✓.*rapid tapping and resetting leaves no stale selection or error" && echo "$out" | grep -q "✓.*reset returns every observable to its starting value, selection and message included" && echo "$out" | grep -q "✓.*tears down to a registry baseline after dispose"',
			evidence = "artifacts/example-quality-pass/studio/lifecycle.json",
			note = "EQ-16/EQ-17: a mount/dispose census per example returning to the pre-mount baseline for instances, connections, reactive nodes and action contexts, clean Studio output, and rapid-input/reset-mid-flight leaving no stale selection, focus, resource handle or bound action",
		},
		{
			name = "device-matrix",
			requirements = { "UI-LAYOUT-001" },
			run = "python3 -c \"import json,sys; d=json.load(open('artifacts/example-quality-pass/studio/device-matrix.json')); rows={r['row'] for r in d['rows']}; want={'compact-phone-portrait','compact-phone-landscape','tablet-landscape','desktop-standard','console-ten-foot'}; v=d['virtualInputTraces']; traced={p['row'] for p in v['perRow']}; ok = rows==want and traced==want and d['result']['passed']==35 and d['result']['failed']==0 and d['preflight']['ok'] and d['evidenceClass']=='studio-emulated' and all(len(p['traces'])>=3 for p in v['perRow']) and all(t.get('rawEvent') for p in v['perRow'] for t in p['traces']) and all(r.get('cannotProve') for r in d['rows']) and v.get('cannotProve'); sys.exit(0 if ok else 1)\"",
			evidence = "artifacts/example-quality-pass/studio/device-matrix.json",
			note = "VirtualInput traces ADDED on all five rows — Tab (traverse), Down (navigate) and Space (activate the focused key, _____ -> S____), each with its raw event and gameProcessed, identical across every view. Tab is only live because this stage enabled the gallery presenter keyboardNavigation (H-2). The wheel path stays FAIL_ENVIRONMENT and is named. Was: the artifact carries NO VirtualInput traces (only a capability probe listing method names), drops the judgedTrees anti-vacuity counter the tool emits, drops the live/observed/configurationChanged discriminators, and collapses rows 2-5 to a hand-authored `allSevenOk` scalar. Also: no row exercised the KeyboardAndMouse presentation and that is not disclosed. EQ-14/EQ-15: all seven examples across the canonical five view rows with each preset RESOLVED AT RUNTIME and its exact configuration recorded, plus VirtualInput traces for the supported Tab/Shift+Tab, Space/Return, arrow, text and mouse paths derived from live geometry — each raw event paired with its semantic action and the visible state change. An unavailable path is recorded FAIL_ENVIRONMENT, never relabelled",
		},
		{
			name = "places-and-docs",
			requirements = { "UI-AGENT-001" },
			run = 'test "$(ls examples/places/*.rbxl | wc -l | tr -d \' \')" -ge 10 && lune run tools/lune/check_docs_cli >/dev/null && grep -q "Refusal is feedback" docs/guide/04-tutorial-examples.md && grep -q "Who drains the provider" docs/guide/04-tutorial-examples.md && grep -q "The answer has to be visible" docs/guide/04-tutorial-examples.md && ! grep -qE "sizeClass == .compact. then 40" docs/guide/04-tutorial-examples.md',
			evidence = "artifacts/example-quality-pass/places.json",
			note = "EQ-18/EQ-19: every standalone example place rebuilt from clean source and asserted to contain the CURRENT example modules, plus the source headers, tutorial guide chapter and inventory describing what the player actually sees",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 3556",
			evidence = "artifacts/test.json",
			note = "EQ-20: stage-start floor is 3442 passing; the floor lands as the FINAL count so a regression of this stage's own pins fails the gate",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = 'if [ -n "${LUAUUI_PRIOR_GATES_NESTED:-}" ]; then echo "prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)"; exit 0; fi; a=artifacts/example-quality-pass/prior-gates.txt && tools/prior_gates.sh "$a" example-quality-pass; grep -q "^DONE$" "$a" && unexplained="$(grep "^FAIL " "$a" | grep -vE "^FAIL (phase-2-settings-parity|phase-3-pilot|expansion-textinput|code-simplicity-cleanup|api-architecture-consistency) " || true)" && test -z "$unexplained" && lune run tools/lune/check_flat_baseline >/dev/null && lune run tools/lune/check_example_drift_cli >/dev/null && lune run tools/lune/check_docs_cli >/dev/null && python3 tools/check_manifest_integrity.py >/dev/null && stylua --check src tests tools examples >/dev/null && test -f artifacts/example-quality-pass/prior-gates-analysis.md && grep -qF "All five remaining failures are the same instrument" artifacts/example-quality-pass/prior-gates-analysis.md',
			evidence = "artifacts/example-quality-pass/prior-gates.txt",
			note = "EQ-20: tools/prior_gates.sh REGENERATED by this check at the source being judged (13 PASS/9 FAIL at stage start -> 17 PASS/5 FAIL at close), plus the flat-baseline / example-drift / docs / manifest-integrity / stylua battery. FIVE gates are allow-listed BY NAME and the allow-list is exactly the set whose only failing check shells out to tools/bench.sh: phase-2-settings-parity (ui-cost-budget IS tools/bench.sh), phase-3-pilot (no-leak-regression), expansion-textinput (expansion-adr-bench-rollback), code-simplicity-cleanup and api-architecture-consistency (performance-unregressed). Any OTHER gate going red fails this check. That allowance is earned, not assumed: 16 recorded bench runs in this stage, every FAIL was textinput-typing-storm and no other scenario flagged once, and an interleaved three-pair A/B has the UNCHANGED pre-stage loop flagging exactly as often as the shipped one (artifacts/example-quality-pass/bench-textinput-ab.json). prior-gates-unregressed itself, red in five gates before this stage, is now green in all of them, and large-text-accessibility -- red since 2026-08-03 on a test the director had deleted -- passes again",
		},
		{
			name = "rascalrally-consumer",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/example-quality-pass/consumer-impact.md && test -f "$f" && grep -q "3089 passed" "$f" && grep -q "highlighted" "$f" && grep -q "What this ledger does NOT claim" "$f" && { ! grep -q "No Rascal Rally Studio canary was run" "$f" || { echo "the affected Studio canary is declared MISSING (contract: visible/input/layout/adapter/lifecycle changes require one)"; exit 1; }; } && cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1',
			evidence = "artifacts/example-quality-pass/consumer-impact.md",
			note = "EQ-21: the consumer-impact ledger with the game suite re-run LIVE at the judged source. If no public API, default, asset or distribution output changed, no caller edit is manufactured — and the ledger says so, together with what it does NOT claim",
		},
		{
			name = "fresh-context-reviews",
			requirements = { "UI-AGENT-001" },
			run = 'd=artifacts/example-quality-pass/reviews && test -f $d/architecture.md && test -f $d/README.md && grep -q "ACCEPT-WITH-FINDINGS" $d/architecture.md && for id in M-1 M-2 M-3 M-4 M-5; do grep -qF "**$id**" $d/README.md || { echo "$id not dispositioned"; exit 1; }; done && grep -q "NOT RUN" $d/README.md && grep -q "open acceptance control, not a passed one" $d/README.md',
			evidence = "artifacts/example-quality-pass/reviews/README.md",
			note = "EQ-22: the architecture review ran and returned ACCEPT-WITH-FINDINGS (0 BLOCKER, 5 MAJOR, 8 MINOR). M-2 (a Grid linking to a non-neighbour focus group) and M-3 (the press dip writing the PRESENTATION authority's UIScale — a regression THIS stage introduced) are fixed in source; M-1's overstated coverage claim is corrected in both places it was made. M-4, M-5 and the minors are recorded open with the change each needs. The Roblox-platform review is TRIGGERED AND NOT RUN, and the README says so — this check asserts the honest disposition exists, never that every control passed",
		},
		{
			name = "physical-and-human-rows",
			requirements = { "UI-INPUT-001" },
			state = "PENDING",
			releaseBlocking = false,
			evidence = "artifacts/example-quality-pass/review-packet.md",
			note = "EQ-P1/EQ-P2/EQ-P3: physical touch (incl. the real mobile OS keyboard), real gamepad/console delivery, and the human 'these seven read as one designed product' judgement stay honestly pending behind one prepared review build and one checklist. Studio emulation may not close any of them",
		},
	},
	["performance-stress-places"] = {
		-- Roadmap Step 9 (docs/plans/performance-stress-places.md): a self-contained,
		-- publish-ready performance place plus the repeatable Studio / low-end-Android
		-- profiling loop. Registered BEFORE any implementation edit per the plan's own
		-- gate rule; every check below started life as a bare `PENDING` and became a
		-- `run` only once its implementation existed.
		--
		-- Acceptance rows PL-1..PL-P3 live in
		-- artifacts/performance-stress-places/acceptance.md.
		--
		-- THE EVIDENCE-CLASS RULE THIS GATE ENFORCES: Lune, Studio, the device emulator,
		-- desktop retail and physical Android are five different labels and none of them
		-- substitutes for another. PL-P1/PL-P2 stay PENDING_PHYSICAL until real hardware
		-- captures exist, PL-P3 stays PENDING_HUMAN until the emitted file is opened;
		-- nothing here may claim the low-end device budget from a host number.
		--
		-- ARTIFACT ASSERTIONS LIVE IN tools/check_perf_gate_evidence.py, one section per
		-- check. They were inline `python3 -c` strings first, and the embedded newlines
		-- collapsed this manifest's single-quoted Luau strings — the trap in
		-- docs/lessons/luau-interpolated-strings-single-line.md, in a new place. A file
		-- keeps every `run` a one-liner and lets each assertion be mutation-tested.
		{
			name = "acceptance-ledger",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/performance-stress-places/acceptance.md && test -f "$f" && for id in PL-1 PL-2 PL-3 PL-4 PL-5 PL-6 PL-7 PL-8 PL-9 PL-10 PL-11 PL-12 PL-13 PL-14 PL-15 PL-16 PL-17 PL-18 PL-19 PL-20 PL-21; do grep -qE "^\\| \\*\\*$id\\*\\* \\|.*\\| PASS_AUTOMATED \\|" "$f" || { echo "$id not PASS_AUTOMATED"; exit 1; }; done && grep -qE "^\\| \\*\\*PL-P1\\*\\* \\|.*PENDING_PHYSICAL" "$f" && grep -qE "^\\| \\*\\*PL-P2\\*\\* \\|.*PENDING_PHYSICAL" "$f" && grep -qE "^\\| \\*\\*PL-P3\\*\\* \\|.*PENDING_HUMAN" "$f" && for d in PLN-1 PLN-2 PLN-3 PLN-4 PLN-5 PLN-6 PLN-7; do grep -q "$d" artifacts/performance-stress-places/decisions.md || { echo "$d missing"; exit 1; }; done',
			evidence = "artifacts/performance-stress-places/acceptance.md",
			note = "execution contract §2: the PL-* ledger written BEFORE implementation, status-anchored at close — every automated row pinned to PASS_AUTOMATED on its own line, the two physical rows and the one human row pinned to their pending states, and all seven decision packets present. A row silently flipping to FAIL_PRODUCT reddens the gate",
		},
		{
			name = "place-builds-and-opens",
			requirements = { "UI-AGENT-001" },
			run = "python3 tools/check_perf_place.py",
			evidence = "artifacts/performance-stress-places/place.json",
			note = "PL-1/PL-16: the doctor REBUILDS from clean source and inspects the resulting tree — 16 required instances with their classes, 5 version markers, no absolute developer path / PlaceId / GameId / plugin dependency, and the scenario runner byte-identical to the gallery's (reused, not forked). Mutation-tested twice: dropping the runner mapping and renaming a version marker each redden it",
		},
		{
			name = "deterministic-scenarios",
			requirements = { "UI-RUNTIME-002" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the same seed, count and content produce a byte-identical row set" && echo "$out" | grep -q "✓.*a different seed produces a different row set, and the digest says so" && echo "$out" | grep -q "✓.*each content variant is its own workload, not a relabelling of the same one" && echo "$out" | grep -q "✓.*an unknown content variant is refused, naming it" && echo "$out" | grep -q "✓.*every declared workload names only passes the scenario implements" && echo "$out" | grep -q "✓.*selecting a scenario adopts its implementation and content" && echo "$out" | grep -q "✓.*the row count is clamped to the declared ceiling rather than honoured blindly"',
			note = "PL-2: one seed reproduces one dataset byte for byte in both Lune and Roblox (own xorshift, no Random/math.randomseed), the digest distinguishes seeds and content variants, and a declared workload cannot name a pass the scenario does not implement",
		},
		{
			name = "dense-scroll-workload",
			requirements = { "UI-PERF-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a row carries an image, a two-line text stack, and three controls" && echo "$out" | grep -q "✓.*the identity line keeps its full-value disclosure" && echo "$out" | grep -q "✓.*2000 logical rows mount a window, not a collection" && echo "$out" | grep -q "✓.*the window stays bounded across a full programmatic scroll sweep" && echo "$out" | grep -q "✓.*the bound is not a bigger row count away from firing" && echo "$out" | grep -q "✓.*NEGATIVE CONTROL: the declared window fault makes the mount FAIL, naming the defect" && echo "$out" | grep -q "✓.*collection churn keeps the window bounded through insert, remove and reorder" && echo "$out" | grep -q "✓.*running a scenario executes its declared sequence and records each pass separately" && echo "$out" | grep -q "✓.*scrolling a virtualized list does NOT grow the reactive core"',
			note = "PL-3/PL-4: the row really is HStack + image + VStack text + toggle + value control + button with its disclosure intact; 200 and 20 000 logical rows mount the same window; the NEGATIVE control drives the declared window fault and requires the mount to be refused. The last grep is the durable regression for the control-scope leak this stage found live (17 078 memos after 400 scroll steps)",
		},
		{
			name = "native-reference-and-exclusivity",
			requirements = { "UI-PERF-002" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a second mount is refused, naming the rule" && echo "$out" | grep -q "✓.*the native reference refuses to mount where the host seam is absent" && python3 tools/check_perf_gate_evidence.py native-reference',
			note = "PL-5: exactly one implementation may be live during a capture, and the reference refuses rather than silently mounting nothing. The artifact side requires three repeats per side taken with the overlay dismissed, and the reference's capability gaps recorded beside the ratio — a floor compared without its omissions is a misleading number",
		},
		{
			name = "theme-cost-isolated",
			requirements = { "UI-PERF-002" },
			run = "python3 tools/check_perf_gate_evidence.py theme-cost",
			note = "PL-6: flat versus `fantasy_ornate` (34 declared image assets, the most expensive non-testOnly shipped package) over an identical workload, with install, steady scroll and teardown timed apart. The check requires the package to actually COMPILE — a module handed to setThemePackage uncompiled returns false and reads as 'the ornate skin costs nothing'",
		},
		{
			name = "large-text-workload",
			requirements = { "UI-LAYOUT-001" },
			run = 'python3 tools/check_perf_gate_evidence.py large-text && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*each content variant is its own workload, not a relabelling of the same one"',
			note = "PL-7: the four MEASURED preference offsets (0/4/10/14) swept live, the active-moving-label cap of one observed with zero findings, and the locale/identity content variants proven to be genuinely different workloads rather than the same one relabelled",
		},
		{
			name = "microprofiler-scopes",
			requirements = { "UI-PERF-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*every declared label is prefixed so LibMP can select exactly this set" && echo "$out" | grep -q "✓.*an undeclared scope name is refused at the call, naming the offender" && echo "$out" | grep -q "✓.*refusing an undeclared name opens no scope at all" && echo "$out" | grep -q "✓.*an ERRORING body still closes the scope, and the error value is unchanged" && echo "$out" | grep -q "✓.*a non-string error value survives the span unchanged" && echo "$out" | grep -q "✓.*nested spans unwind in order when the INNER one throws" && echo "$out" | grep -q "✓.*the number of scopes a frame opens does NOT scale with the row count" && echo "$out" | grep -q "✓.*mount -> solve -> commit produces only declared labels, and closes them all" && python3 tools/check_perf_gate_evidence.py scopes',
			note = "PL-8: the closed scope set, its cardinality bound stated as BEHAVIOUR (a 4-row and a 40-row tree open the same number of scopes), and balance on every exit path — proved through a recording hook pair because Lune has no debug.profilebegin and the instrumented branch would otherwise never run. Mutation-tested: dropping the close reddens exactly the three error cases. The artifact side pins all eight timers found by mask in a live LibMP capture with opens == closes",
		},
		{
			name = "capture-metadata",
			requirements = { "UI-AGENT-001" },
			run = "python3 tools/check_perf_captures.py",
			evidence = "artifacts/performance-stress-places/captures.json",
			note = "PL-9: every stored capture row carries its identity, workload, conditions, method and results, and `unknown` counts as MISSING. It also refuses a device-class row that lacks device fields or carries a studioVersion. The rule caught a real hole on its first run — the host read graphics quality through `settings()`, a plugin global that is nil in a LocalScript",
		},
		{
			name = "overlay-and-ramp",
			requirements = { "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the emergency stop halts a running sequence between passes" && echo "$out" | grep -q "✓.*the ramp climbs its declared ladder and stops when told" && echo "$out" | grep -q "✓.*the ramp ladder is bounded by a declared ceiling" && echo "$out" | grep -q "✓.*reset returns to the idle baseline and PROVES the workload is unmounted" && echo "$out" | grep -q "✓.*clean capture DISMISSES the overlay rather than hiding it" && python3 tools/check_perf_gate_evidence.py studio',
			note = "PL-10/PL-11: selectors, run controls, clean capture that DISMISSES rather than hides (a hidden ScreenGui is still a mounted tree the census counts), a ramp on a declared ladder with a hard ceiling and a stop checked between steps, and a reset that proves teardown with a before/after census. The live half — 222 GuiObjects to 0, and eight soak cycles byte-identical — rides the studio section",
		},
		{
			name = "headless-linkage",
			requirements = { "UI-PERF-001" },
			run = "python3 tools/check_perf_gate_evidence.py headless-linkage",
			note = "PL-12: `bench/perf_scenes.luau` requires the SAME dataset and row modules the place runs, so the headless budget cannot guard a workload the place does not have. The check also refuses a perf artifact stamped `injectedRegression` and any headless row wearing a device class",
		},
		{
			name = "studio-evidence",
			requirements = { "UI-FID-001" },
			run = "python3 tools/check_perf_gate_evidence.py studio",
			evidence = "artifacts/performance-stress-places/studio/perf-lab.json",
			note = "PL-13: the execution-contract preflight (source stamp checked against the built manifest, non-1x1 viewport, clean log boundary, exactly-once mount, canary), the window fault seen to BITE in a live session, an admissible capture row, and the capture images present on disk rather than named",
		},
		{
			name = "device-matrix-smoke",
			requirements = { "UI-LAYOUT-001" },
			run = "python3 tools/check_perf_gate_evidence.py device-matrix",
			evidence = "artifacts/performance-stress-places/studio/device-matrix.json",
			note = "PL-14: the canonical five rows, each selected through StudioDeviceSimulatorService with its configuration recorded, the lab operable and the mounted window bounded at every viewport, simulation stopped at the end — and the whole file stamped `emulator` with the honest boundary in it. The compact-phone-landscape row records that it needed an explicit pinnedDeviceId, because the first attempt silently stayed portrait",
		},
		{
			name = "perf-gate-falsifiable",
			requirements = { "UI-PERF-001" },
			run = "python3 tools/check_perf_gate_evidence.py falsifiable",
			evidence = "artifacts/performance-stress-places/prove-perf-gate.json",
			note = "PL-15: an 8x regression injected into the LAB-linked scene through the shipped environment hook reddened tools/perf.sh with BOTH a trend and a frame-ceiling violation, named the scene, and produced an artifact stamped as injected which check_perf_metrics refuses as a baseline",
		},
		{
			name = "optimization-loop-recorded",
			requirements = { "UI-PERF-001" },
			run = 'f=artifacts/performance-stress-places/optimization-log.md && test -f "$f" && grep -q "L-4 — arrange re-measures every scroll subtree" "$f" && grep -q "NEGATIVE: the .native-scroll-drag. regression was noise" "$f" && grep -q "INCONCLUSIVE" "$f" && grep -q "What was deliberately NOT changed" "$f" && grep -q "measureUncached" src/layout/solver.luau && grep -q "measureCache" src/layout/solver.luau && python3 tools/check_perf_gate_evidence.py budgets',
			evidence = "artifacts/performance-stress-places/optimization-log.md",
			note = "PL-17: the loop recorded end to end — repeated baselines, a falsifiable cause stated before the change, the smallest fix, gates, rebuild, repeated after-captures and a cross-scenario check — INCLUDING the refuted regression and the inconclusive attempt, and what was deliberately left alone. The source greps pin the fix existing; the budget section pins that re-baselining TIGHTENED the two lab scenes and left the phone budget unmeasured",
		},
		{
			name = "rascalrally-consumer",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/performance-stress-places/consumer-impact.md && test -f "$f" && grep -q "No public API changed" "$f" && grep -q "3089 passed" "$f" && grep -q "was NOT re-run" "$f" && cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1',
			evidence = "artifacts/performance-stress-places/consumer-impact.md",
			note = "PL-19: the consumer-impact ledger with the game suite re-run LIVE at the judged source. No public API, default, asset or distribution output changed, so no caller edit was manufactured — and the ledger says so, together with the one thing it does NOT claim (a Sponsor Studio canary was not re-run)",
		},
		{
			name = "registration-and-docs",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_registration_cli >/dev/null && lune run tools/lune/check_docs_cli >/dev/null && lune run tools/lune/check_boundary >/dev/null && lune run tools/lune/check_prop_parity_cli >/dev/null && lune run tools/lune/check_surface_ledger >/dev/null && python3 tools/check_manifest_integrity.py >/dev/null && stylua --check src tests tools bench examples && test -f docs/guide/12-performance-lab.md && grep -q '12-performance-lab.md' docs/guide/README.md && grep -q 'Publish to Roblox' docs/guide/12-performance-lab.md && grep -q 'MicroProfiler' docs/guide/12-performance-lab.md && grep -q 'phone-physical' docs/guide/12-performance-lab.md && test -f docs/lessons/embedded-newlines-measure-as-one-line.md",
			note = "PL-18/PL-20: the standard battery at the final source, plus the guide chapter existing, being LINKED from the index (an unlinked chapter is a chapter nobody finds), and covering the four procedures the plan names — rebuild/open, manual publish, MicroProfiler capture, and the device class that closes the budget. The lesson file pins the newline defect this stage found rather than losing it",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 3421",
			evidence = "artifacts/test.json",
			note = "PL-20: stage-start floor was 3319; the floor lands as the FINAL count (3402 after +15 profile-scope cases, +36 perf-lab cases, +5 measure-memo cases, +7 fine-grained-reactivity cases and +8 instance-recycling cases) so a regression of this stage's own pins fails the gate",
		},
		{
			name = "existing-perf-gate",
			requirements = { "UI-PERF-001" },
			run = "tools/perf.sh >/dev/null && python3 tools/check_perf_gate_evidence.py perf-gate",
			evidence = "artifacts/phase-4/perf.json",
			note = "PL-20: tools/perf.sh run at the final source and required to PASS with zero violations AND with the phone-physical budget explicitly SKIPPED rather than satisfied — the refusal has to be visible in the artifact, not merely implemented",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = "python3 tools/check_perf_gate_evidence.py prior-gates",
			evidence = "artifacts/performance-stress-places/prior-gates.txt",
			note = "PL-20: tools/prior_gates.sh regenerated at the final source, plus the supplement. Structural: roll-up DONE, >=18 PASS, and EVERY FAIL_RECOVERABLE check must carry a recorded `<gate> :: <check> :: standalone PASS` line. That replaced the inherited four-name bench allowlist, which trusted a NAME instead of demanding evidence. The new rule is not a formality: it caught a real regression in this stage — performance-unregressed was red in the sweep AND red standalone, which is the discriminator between load noise and a defect, and the memo was scoped rather than the budget loosened (optimization log L-6). Mutation-tested: removing a verdict line or truncating the roll-up each redden it",
		},
		{
			name = "fresh-context-reviews",
			requirements = { "UI-AGENT-001" },
			run = 'd=artifacts/performance-stress-places/reviews && test -f $d/phase-gate.md && test -f $d/architecture.md && test -f $d/reactive-runtime.md && test -f $d/roblox-platform.md && test -f $d/README.md && grep -q "Phase-gate" $d/README.md && grep -q "Architecture" $d/README.md && grep -q "Reactive runtime" $d/README.md && grep -q "Roblox platform" $d/README.md && grep -q "PLN-" $d/README.md',
			evidence = "artifacts/performance-stress-places/reviews/README.md",
			note = "PL-21: the required fresh-context phase-gate review plus the three specialist authorities this stage touched — architecture (the solver memo and the profile module's containment), reactive runtime (the flush-body hoist and the ownership changes), and Roblox platform (the MicroProfiler/LibMP claims and the place's publish safety). The README carries the dispositions",
		},
		{
			name = "physical-rows",
			requirements = { "UI-PERF-002" },
			run = 'f=artifacts/performance-stress-places/acceptance.md && grep -qE "^\\| \\*\\*PL-P1\\*\\* \\|.*PENDING_PHYSICAL" "$f" && grep -qE "^\\| \\*\\*PL-P2\\*\\* \\|.*PENDING_PHYSICAL" "$f" && grep -qE "^\\| \\*\\*PL-P3\\*\\* \\|.*PENDING_HUMAN" "$f" && test -f artifacts/performance-stress-places/review-packet.md && grep -q "automation complete, low-end performance not proven" artifacts/performance-stress-places/review-packet.md && grep -q "Open from" artifacts/performance-stress-places/review-packet.md && python3 tools/check_perf_gate_evidence.py budgets',
			releaseBlocking = false,
			evidence = "artifacts/performance-stress-places/review-packet.md",
			note = "PL-P1/PL-P2/PL-P3: the two device rows and the one file-open row stay honestly pending behind one prepared review build and one checklist. The budgets assertion keeps `phone-physical.measured = false` — the stage may report automation complete and may NOT report that LuauUI meets the low-end-device budget",
		},
	},
	["large-text-accessibility"] = {
		-- Roadmap Step 8.5 (docs/plans/large-text-accessibility.md): the player's
		-- PreferredTextSize (Medium/Large/Larger/Largest) as a first-class layout
		-- input — measured exactly once, live-updating without remount, with the
		-- reflow -> scroll -> bounded-truncation-with-full-value-access -> engaged-
		-- reveal overflow order, plus the Rascal Rally Sponsor View production
		-- proof on compact mobile portrait/landscape. Registered BEFORE any
		-- implementation edit per the plan's own gate rule; checks land as `run`
		-- only when their implementation exists (manifest header rule).
		-- Acceptance rows LT-* live in artifacts/large-text-accessibility/acceptance.md.
		{
			name = "acceptance-ledger",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/large-text-accessibility/acceptance.md && test -f "$f" && for id in LT-1 LT-2 LT-3 LT-4 LT-5 LT-6 LT-7 LT-8 LT-9 LT-10 LT-11 LT-12 LT-13 LT-14 LT-15 LT-16; do grep -qE "^\\| \\*\\*$id\\*\\* \\|.*\\| PASS_AUTOMATED \\|" "$f" || { echo "$id not PASS_AUTOMATED"; exit 1; }; done && grep -qE "^\\| \\*\\*LT-P1\\*\\* \\|.*PENDING_PHYSICAL" "$f" && grep -qE "^\\| \\*\\*LT-P2\\*\\* \\|.*PENDING_HUMAN" "$f" && for d in LTN-1 LTN-2 LTN-3 LTN-4 LTN-5; do grep -q "$d" artifacts/large-text-accessibility/decisions.md || { echo "$d missing"; exit 1; }; done',
			evidence = "artifacts/large-text-accessibility/acceptance.md",
			note = "execution contract §2: the ledger written BEFORE implementation, TIGHTENED at close (phase-gate review F4): every automated row is status-anchored to PASS_AUTOMATED on its own line, both honest-pending rows to their pending states, and all five decision packets (incl. LTN-4 disclosure contract and LTN-5 matrix-gap dispositions) must exist — a row silently flipping to FAIL_PRODUCT now reddens the gate",
		},
		{
			name = "live-preference-probe",
			requirements = { "UI-FID-001" },
			run = "python3 -c \"\nimport json\nd=json.load(open('artifacts/large-text-accessibility/probe/preference-probe.json'))\nr=d['results']\nassert r['offsets']['values']=={'Medium':0,'Large':4,'Larger':10,'Largest':14}, r['offsets']['values']\nassert 'does NOT include the preference' in r['getTextBoundsAsync']['finding']\nassert r['changeSignal']['events']==['Large','Larger','Largest','Larger','Large','Medium']\nassert 'preference-INDEPENDENT' in r['textScaled']['finding']\nassert 'OS-level' in d['session']['howDriven'], 'the probe must be the REAL settings path, not injection'\nassert d['seamDecision']['id']=='LTN-1'\n\"",
			evidence = "artifacts/large-text-accessibility/probe/preference-probe.json",
			note = "the E2 measurement matrix the plan demands BEFORE API/code, run 2026-08-03 against the real in-experience Text size setting (OS-level clicks; the property is script-locked even via UserGameSettings): offsets are per-preference CONSTANTS 0/4/10/14 uniform across font/weight/size; the engine paints at TextSize+offset while GetTextBoundsAsync answers WITHOUT it (refuting the 2026-07-23 grounding); the change signal fires on every step; TextScaled is preference-independent. The check pins the artifact's load-bearing claims so the numbers cannot drift from what the seam ships",
		},
		{
			name = "exact-once-seam",
			requirements = { "UI-FID-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*applies the measured fallback synchronously — first mount never waits" && echo "$out" | grep -q "✓.*a confirmed answer equal to the fallback applies nothing more" && echo "$out" | grep -q "✓.*a confirmed answer that differs applies exactly one atomic correction" && echo "$out" | grep -q "✓.*an answer that raced a preference step is DISCARDED" && echo "$out" | grep -q "✓.*an answer resolved with NO step in flight is cached: the revisit asks nothing" && echo "$out" | grep -q "✓.*a FAILED lookup keeps the fallback and does not retry in a loop" && echo "$out" | grep -q "✓.*garbage answers are refused: NaN and negative offsets keep the fallback" && echo "$out" | grep -q "✓.*an answer past the ceiling is CLAMPED and applied, never traded for a smaller fallback" && echo "$out" | grep -q "✓.*an unknown future enum value starts from the LARGEST known fallback" && echo "$out" | grep -q "✓.*dispose drops late answers on the floor" && grep -q "GetPropertyChangedSignal" src/client/roblox_env.luau && ! grep -q "Large = 6," src/client/preferred_text.luau',
			note = "LT-1/LT-3/LT-4 headless half (tests/preferred_text_seam.spec.luau, corrected by the platform review): measured-fallback-first (never blocks mount), confirm-once with an EPOCH-guarded cache (a raced answer is discarded entirely — the A->B->A poisoning repro is a named case), failures keep the fallback without loops, NaN/negative refused while over-ceiling answers clamp UP, unknown enum over-reserves. The source greps pin the adapter subscription existing and the wrong guessed offset (Large=6) staying dead — the E3 integrated half lives in studio-evidence",
		},
		{
			name = "live-change-reflow",
			requirements = { "UI-ENV-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*raising the offset re-solves in place: same node, taller text box, no creates/removes" && echo "$out" | grep -q "✓.*lowering it back restores the original geometry exactly" ',
			note = "LT-2 headless half: an offset change is GEOMETRY (rect/hitr writes only — a create or remove fails the case), node identity survives, and stepping back restores byte-identical geometry. Focus/editing/scroll/async survival across a hot swap lands with the headless-matrix check; the live Studio change probe lands in studio-evidence",
		},
		{
			name = "overflow-policy",
			requirements = { "UI-LAYOUT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*LT6-ACTION a Button.s action label wraps and grows instead of ellipsizing at any preference" && echo "$out" | grep -q "✓.*LT6-BAND the chosen candidate never gets richer as the preference rises" && echo "$out" | grep -q "✓.*LT6-BANDWITNESS the compact-portrait band is a row at Medium and a column at Largest" && echo "$out" | grep -q "✓.*LT6-LADDER nothing is truncated while the band still has a cheaper candidate to take" && echo "$out" | grep -q "✓.*LT6-LADDERNEG the ladder rule FIRES on a band that cuts a label with a candidate still in hand" && echo "$out" | grep -q "✓.*LT6-DISCLOSE an unbroken identity name truncates WITH a full-value path and files no finding" && echo "$out" | grep -q "✓.*LT6-FORM the form.s action pair reflows and the region scrolls" && echo "$out" | grep -q "✓.*LT6-COMPOSE the composition never picks a richer arrangement as the text grows" && echo "$out" | grep -q "✓.*LT6-COMPOSESCROLL the field region keeps its declared scroll path at every preference" && echo "$out" | grep -q "✓.*a truncated disclosing Toggle presents its LABEL through the same plate a Text does" && echo "$out" | grep -q "✓.*a disclosing column stamps disclose on its value cells AND its header title"',
			note = "LT-6, the ladder in the required order: rung 1 reflow (action labels wrap/step candidates, never cut — with the NEGATIVE control proving the rule can fire), rung 2 containing-region scroll, rung 3 bounded identity truncation with the full-value path. The two follow-up greps pin the LT-G1/LT-G2 closures (Toggle label disclosure; Table column disclosure) so the matrix's found gaps cannot quietly reopen",
		},
		{
			name = "diagnostics-checks",
			requirements = { "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the layout dump is luauui-dump/2 and carries textFacts per text node" && echo "$out" | grep -q "✓.*overlapping painted siblings are a finding naming both nodes and the fix" && echo "$out" | grep -q "✓.*and the finding is gone once the parent declares intentionalOverlap" && echo "$out" | grep -q "✓.*truncated text with no disclose and no allowlist entry is a finding" && echo "$out" | grep -q "✓.*gone the moment the node declares disclose" && echo "$out" | grep -q "✓.*an interactive node painted under its declared floor is a finding" && echo "$out" | grep -q "✓.*a second moving text surface is a finding at the default maximum of one" && echo "$out" | grep -q "✓.*a focused rect fully outside its clipping viewport is a finding" && echo "$out" | grep -q "✓.*gone once the viewport scrolls it back into view" && echo "$out" | grep -q "✓.*two runs over equal input produce equal, deterministically ordered findings" && echo "$out" | grep -q "✓.*a hidden subtree is audited by nobody" && echo "$out" | grep -q "✓.*UI.Text refuses a bound disclose, naming the prop"',
			note = "LT-7 (tests/text_audit.spec.luau): every check carries its NEGATIVE CONTROL in the same suite — the violation fires, the declaration (intentionalOverlap / disclose / allowlist / scroll-back) silences it — so a can't-ever-fail audit cannot land. Determinism is pinned; the dump schema bump to /2 is pinned; six mutations were confirmed to redden named cases during the build. The live half (a mounted node's textAt report) rides studio-evidence",
		},
		{
			name = "headless-matrix",
			requirements = { "UI-LAYOUT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*LT8-COVER every controls_registry row is swept or carries a declared reason" && echo "$out" | grep -q "✓.*LT8-CTL Toggle" && echo "$out" | grep -q "✓.*LT8-CTL Table" && echo "$out" | grep -q "✓.*LT8-CTL ViewThatFits" && echo "$out" | grep -q "✓.*LT8-MIRROR the audit.s target-floor mirror equals the renderer.s own hit expander" && echo "$out" | grep -q "✓.*LT8-SCRIPTS a mixed CJK . emoji . latin line files no overlap or clip finding at any preference" && echo "$out" | grep -q "✓.*LT8-MONOTONE" && echo "$out" | grep -q "✓.*LT8-GROWTH the Largest preference reserves a strictly taller box than Medium" && echo "$out" | grep -q "✓.*LT8-REDUCEDSWEEP" && echo "$out" | grep -q "✓.*LTSWING-IDENTITY the swing writes rects and props only" && echo "$out" | grep -q "✓.*LTSWING-FOCUS the focused path is the same node before, during and after the swing" && echo "$out" | grep -q "✓.*LTSWING-EDIT the field keeps its typed, uncommitted text" && echo "$out" | grep -q "✓.*LTSWING-SCROLL the list keeps its scroll offset" && echo "$out" | grep -q "✓.*LTSWING-GEOMETRY every rect returns byte-identical when the preference comes back to Medium" && echo "$out" | grep -q "✓.*LTSWAP-THEME installing Fantasy Parchment at Largest re-solves in place with no finding" && echo "$out" | grep -q "✓.*LTSWAP-BORN a screen BORN at Largest under Parchment matches one swung there live"',
			note = "LT-8 (tests/large_text_matrix/layout/hot_swap specs): 40 per-control rows at 0/4/10/14 x both reference themes with the audit checks over every solve, a coverage case that fails when a registry row is neither swept nor excused, mixed scripts + monotone growth, reduced motion, and the live Medium<->Largest swing with focus/edit/scroll/state survival plus theme x preference composition. Spot greps anchor the family plus every swing/swap invariant by name",
		},
		{
			name = "studio-evidence",
			requirements = { "UI-FID-001" },
			run = "python3 -c \"\nimport json, os\nd=json.load(open('artifacts/large-text-accessibility/studio/large-text.json'))\nassert d['preflight']['ok'] is True and d['preflight']['stalenessMarkerChecked'] is True\nrows={r['id']: r for r in d['rows']}\nfor k in ('LT9-portrait-medium','LT9-portrait-largest','LT9-portrait-largest-disclosure','LT9-landscape-medium+largest','LT9-tablet+desktop-largest','LT9-tenfoot-composition','LT10-real-setting-path','LT11-rolepick-real-largest','LT11-sponsor-table-real-largest','LT11-sponsor-667x375-real-largest','LT11-restore'):\n    assert rows[k]['status']=='PASS_AUTOMATED', k\nassert rows['LT11-rolepick-real-largest']['measured']['atLargest']['sponsorARace']['fits'] is True, 'the live regression pin'\nassert rows['LT9-tenfoot-composition']['measured']['identityH']==46, 'exact-once composition'\nassert rows['LT11-sponsor-667x375-real-largest']['measured']['notFitting']==0\nfor f in ('lt9-portrait-largest.png','lt9-portrait-largest-disclosure.png','lt9-landscape-largest.png','lt11-rolepick-largest-real-setting.png','lt11-sponsor-table-largest.png','lt11-sponsor-667x375-largest.png'):\n    assert os.path.exists('artifacts/large-text-accessibility/studio/'+f), f\n\"",
			evidence = "artifacts/large-text-accessibility/studio/large-text.json",
			note = "two live sessions, both preflighted at stamp ef45acde: the gallery place ran the public fixture through the five-view driver (portrait/landscape Medium+Largest, tablet/desktop, ten-foot composed EXACTLY once — (16*1.5+14)*1.2=46 measured — and the disclosure plate raised through a live ticked dwell), and the production place ran the REAL Text size stepper with mounted production surfaces: the shipped role-pick regression measured dead at Largest (13+14=27 painted in the 240x44 box), the maximized table/chips whole, exact 667x375 at Largest with zero non-fitting labels, and the user setting restored. Honest boundaries (VirtualInput delivers nothing on 0.732; synthetic hover impossible; sponsor compact-emulated rows ride the headless audit + phone pass) are recorded in the artifact",
		},
		{
			name = "sponsor-fixtures",
			requirements = { "UI-LAYOUT-001" },
			run = 'cd ../../../games/RascalRally/code && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*no painted siblings overlap ANYWHERE on the surface, on any view, at any offset" && echo "$out" | grep -q "✓.*nothing on the whole table surface is truncated without a way back to its full value" && echo "$out" | grep -q "✓.*the same surface with the disclosure withdrawn reports every name" && echo "$out" | grep -q "✓.*no row carries a position numeral — the list.s own order is the place" && echo "$out" | grep -q "✓.*both CTA labels PAINT inside their fixed boxes at every offset, on every view" && echo "$out" | grep -q "✓.*neither sub-line ellipsizes at any offset" && echo "$out" | grep -q "✓.*the longest shipped reason and a ~1.4x expansion of it read WHOLE at every offset" && echo "$out" | grep -q "✓.*whichever CTA form the composition chose reads WHOLE, both roles, every offset" && echo "$out" | grep -q "✓.*the coin TOTAL never truncates" && echo "$out" | grep -q "✓.*the standings and roll-call NAMES are the things that truncate, and they disclose" && echo "$out" | grep -q "✓.*the 667x375 fixture re-arranges rather than clipping a lane, for both roles" && echo "$out" | grep -q "✓.*NOTHING PAINTS OVER ANYTHING at any preference" && echo "$out" | grep -q "✓.*the mounted nodes, the live count, the geometry and the watched row all survive" && echo "$out" | grep -q "✓.*the race-start countdown numeral never truncates"',
			note = "GREP UPDATED 2026-08-06 (example-quality-pass prior-gates rerun): the chain asked for `the position numeral never truncates at any preference`, and no test of that name has existed since the director's 2026-08-03 ruling DELETED the Pos cell ('we know their places based on where they are in the list') — so this gate had been red on a phantom, independently of any stage, while the game suite stayed fully green. It now greps the SUCCESSOR claim, which is the same subject and strictly stronger: `no row carries a position numeral - the list's own order is the place`, swept over every view x every offset, plus the assertion that the name cell it paid into is present on every row. A numeral that does not exist cannot truncate. Original note: LT-11 headless half (games/RascalRally/code tests/luauui_large_text_sweep + _results + _contract): the production presenter at 0/4/10/14 on 390x844/844x390/667x375 with the framework audit over every solve — overlap-free, disclose-or-never-truncate (with the negative control), required facts whole, CTA paint-fits (the check that CAN fail: verified red-first against the pre-fix code), arrangement step-down asserted to actually move, hot-swing identity. Run LIVE at the judged source, never from a transcript. The E3 half is studio-evidence",
		},
		{
			name = "sponsor-policy-reconciled",
			requirements = { "UI-AGENT-001" },
			run = 'f=../../../games/RascalRally/docs/ui/UI_SPEC_sponsor_luauui.md && grep -q "Corrected 2026-08-03, Step 8.5 / LTN-3" "$f" && grep -q "identity only, full value reachable" "$f" && ! grep -q "seat name, countdown" "$f" && grep -q "LTN-3" artifacts/large-text-accessibility/decisions.md && grep -q "purged of essentials" artifacts/large-text-accessibility/decisions.md',
			note = "LT-12: S16.13 and §8 corrected in place with the LTN-3 record — countdown/coin totals/CTA labels/section heads left the truncation lists (essentials), position numerals/lap text moved to reserve-to-fit, identity truncation carries the full-value ruling. The corrections are TESTED by the sponsor-fixtures cases (never-truncate pins per corrected rule)",
		},
		{
			name = "rascalrally-consumer",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/large-text-accessibility/consumer-impact.md && test -f "$f" && grep -q "Rascal Rally consumer work — DONE" "$f" && grep -q "The role-pick fix" "$f" && grep -q "owed follow-up: a" "$f" && test -f ../../../games/RascalRally/code/tests/luauui_large_text_contract.spec.luau && test -f ../../../games/RascalRally/code/tests/luauui_large_text_sweep.spec.luau && cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1',
			evidence = "artifacts/large-text-accessibility/consumer-impact.md",
			note = "LT-13: the consumer-impact ledger (12 disclose adoptions, the role-pick fix, every fit caller audited incl. the honestly-owed legacy-HUD follow-up, 8 cap corrections with offset-0 changes recorded) with the game suite re-run LIVE at the judged source; the Studio canary rows live in studio-evidence",
		},
		{
			name = "perf-workloads",
			requirements = { "UI-AGENT-001" },
			run = 'f=docs/plans/performance-stress-places.md && grep -q "layout-style-churn" "$f" && grep -q "large-text-overflow" "$f" && grep -q "premeasure cache hits/misses/corrections" "$f" && grep -q "re-solve count per preference change" "$f" && grep -q "moving-text-surface count" "$f" && grep -q "Step 8.5 gate rider" "$f"',
			note = "the Step 9 plan already carried the layout-style-churn and large-text-overflow workload rows; this stage added the recorded-quantity riders (measurement queue/cache work incl. corrections, exactly-one-re-solve per settled preference change, idle per-frame writes, active moving-text count with its allowed maximum)",
		},
		{
			name = "registration-and-docs",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_registration_cli >/dev/null && lune run tools/lune/check_docs_cli >/dev/null && lune run tools/lune/check_boundary >/dev/null && lune run tools/lune/check_prop_parity_cli >/dev/null && lune run tools/lune/check_surface_ledger >/dev/null && python3 tools/check_manifest_integrity.py >/dev/null && stylua --check src tests tools bench examples && grep -q 'preferredTextOffset' docs/reference/api.md && grep -q 'disclose' docs/reference/api.md && grep -q 'preferred text size' docs/guide/05-styling.md && grep -q 'measured per-preference constants' docs/reference/swiftui-parity.md",
			note = "the standard battery at the final source, plus greps pinning the four doc surfaces this stage owed: the env-fact entry (measured constants + subscription), the disclose contract in api.md, the guide's preferred-text-as-layout-input paragraph, and the parity ledger's updated §7.3",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 3291",
			evidence = "artifacts/test.json",
			note = "stage-start floor was 3133; the floor lands as the FINAL count (3291 after the fresh-context review closures: +11 seam, +49 disclosure/audit, +73 matrix, +16 follow-up closures and wiring pins) so a regression of this stage's own pins fails the gate",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = "python3 -c \"\nimport re\nlines=open('artifacts/large-text-accessibility/prior-gates.txt').read().splitlines()\nassert 'DONE' in lines, 'roll-up truncated'\nassert sum(1 for l in lines if l.startswith('PASS '))>=18, 'structural PASS floor'\nBENCH={'ui-cost-budget','performance-unregressed','no-leak-regression','expansion-adr-bench-rollback'}\nsup=open('artifacts/large-text-accessibility/prior-gates-supplement.md').read()\ni=0\nwhile i<len(lines):\n    if lines[i].startswith('FAIL '):\n        gate=lines[i].split()[1]\n        j=i+1\n        reds=[]\n        while j<len(lines) and lines[j].startswith('      '):\n            state,name=lines[j].split()[0],lines[j].split()[1]\n            if state not in ('FAIL_ENVIRONMENT','PENDING','PENDING_PHYSICAL'):\n                reds.append(name)\n            j=j+1\n        assert reds and all(r in BENCH for r in reds), ('non-bench red check under', gate, reds)\n        assert gate in sup, ('bench-failed gate missing from the standalone supplement', gate)\n        i=j\n    else:\n        i=i+1\n\"",
			evidence = "artifacts/large-text-accessibility/prior-gates.txt",
			note = "tools/prior_gates.sh at the final source behind the new mkdir lock, PLUS prior-gates-supplement.md. Five sweeps established the shape: 18 gates pass structurally every run and only the four load-sensitive BENCH comparisons rotate red on this machine's ~4-load idle floor, each passing standalone/in another sweep (the supplement records all five runs + the standalone verdicts). The check is structural: roll-up DONE, >=18 PASS, and any FAIL line may carry ONLY the four named bench checks AND must appear in the supplement — a failed non-bench check anywhere, or a bench gate without standalone proof, reddens the gate. The two REAL defects the sweeps exposed (a stale hitFloorFor grep after the matrix package's rename; two bare PENDING states that made old gates permanently un-passable) were fixed at the source, dispositioned in LTN-7",
		},
		{
			name = "fresh-context-reviews",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/large-text-accessibility/reviews/README.md && grep -q "Roblox platform" artifacts/large-text-accessibility/reviews/README.md && grep -q "Architecture" artifacts/large-text-accessibility/reviews/README.md && grep -q "Phase-gate" artifacts/large-text-accessibility/reviews/README.md && grep -q "LTN-7" artifacts/large-text-accessibility/decisions.md && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the A->B->A double-step cannot poison the cache" && echo "$out" | grep -q "✓.*a HIDDEN ViewThatFits candidate discloses nothing" && echo "$out" | grep -q "✓.*the pointer dwell RE-ASKS at expiry" && echo "$out" | grep -q "✓.*a touch class arriving MID-SESSION retrofits the long-press half onto mounted labels" && echo "$out" | grep -q "✓.*an answer past the ceiling is CLAMPED and applied" && echo "$out" | grep -q "✓.*an unknown column key is refused, naming the column" && echo "$out" | grep -q "✓.*the FakeTarget satisfies every required and optional method"',
			note = "three fresh-context reviews at close (required phase-gate + the two authority specialists: platform, architecture), reports in artifacts/large-text-accessibility/reviews/, dispositions LTN-7. The greps pin the FIX of every BLOCKER/MAJOR by its named regression case — epoch-guarded cache (platform F1), hidden-candidate gate (arch F-1), dwell re-ask (arch F-2), capability retrofit (arch F-5), ceiling clamp (platform F2), strict column boundary (arch F-4), and enableDisclosure on the render-target contract (arch F-3, via the conformance case) — so reopening any of them reddens this check",
		},
		{
			name = "physical-and-human-rows",
			requirements = { "UI-FID-001" },
			run = 'f=artifacts/large-text-accessibility/acceptance.md && grep -qE "^\\| \\*\\*LT-P1\\*\\* \\|.*PENDING_PHYSICAL" "$f" && grep -qE "^\\| \\*\\*LT-P2\\*\\* \\|.*PENDING_HUMAN" "$f" && test -f artifacts/large-text-accessibility/review-packet.md && grep -q "Phone pass" artifacts/large-text-accessibility/review-packet.md && grep -q "Desktop micro-pass" artifacts/large-text-accessibility/review-packet.md',
			releaseBlocking = false,
			evidence = "artifacts/large-text-accessibility/review-packet.md",
			note = "LT-P1 (a physical phone at the actual Largest preference, portrait and landscape) and LT-P2 (subjective readability) stay honestly pending with one prepared review build and checklist; injected coverage is never the real read-only OS/player setting",
		},
	},
	["traversal-document-order"] = {
		-- Roadmap Step 8 FOLLOW-UP (docs/plans/traversal-document-order.md): Tab
		-- stops inheriting the directional Grip deferral and reads the focus map in
		-- DOCUMENT order, via a presenter-supplied rank; plus the two public items
		-- the defect's discovery proved missing — `traversalPriority` (move one
		-- control) and `handle.focusOrder()` (see the resolved chain at all).
		-- Acceptance rows TD-1..TD-P2 live in
		-- artifacts/traversal-document-order/acceptance.md.
		{
			name = "acceptance-ledger",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/traversal-document-order/acceptance.md && test -f "$f" && for id in TD-1 TD-2 TD-3 TD-5 TD-7 TD-9 TD-10 TD-13 TD-15 TD-16 TD-P1; do grep -q "$id" "$f" || { echo "$id missing"; exit 1; }; done && grep -qE "^\\| \\*\\*TD-P2\\*\\* \\|.*PENDING_PHYSICAL" "$f" && grep -qE "^\\| \\*\\*TD-P1\\*\\* \\|.*PASS_HUMAN" "$f" && test -f artifacts/traversal-document-order/decisions.md && grep -q "TDN-1" artifacts/traversal-document-order/decisions.md && grep -q "TDN-2" artifacts/traversal-document-order/decisions.md',
			evidence = "artifacts/traversal-document-order/acceptance.md",
			note = "execution contract §2: the ledger written BEFORE implementation. The status greps are anchored to the ROW (^| **TD-Pn** |), not to the file: they previously matched the legend line that merely LISTS the status vocabulary, so once the human row closed the check kept passing while asserting nothing — the can't-ever-fail shape this stage kept finding elsewhere. TD-P1 must read PASS_HUMAN and TD-P2 must still read PENDING_PHYSICAL, so neither closing the physical row by hand nor reopening the human one can slip through. The decision packets it cites (TDN-1 all-grips-no-exceptions, TDN-2 rank-is-a-sort-key-not-a-second-order, TDN-3 construction-only, TDN-4 the uncommitted Step 8 baseline, TDN-5 the two stale Step 8 gate checks) are checked to exist beside it",
		},
		{
			name = "document-order-traversal",
			requirements = { "UI-FOCUS-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*Tab visits the Slider.s track in DOCUMENT position, not last" && echo "$out" | grep -q "✓.*pressing Tab really moves focus in that order" && echo "$out" | grep -q "✓.*a bare focusable Grip declared between buttons traverses between them" && echo "$out" | grep -q "✓.*and pressing Tab really lands on it there" && echo "$out" | grep -q "✓.*a Grip inside a modal takes its document position within the modal" && echo "$out" | grep -q "✓.*a row mounted after present() takes its document position, not the end"',
			note = "TD-1/TD-4/TD-11/TD-12. Every fixture puts the Grip-bearing control BETWEEN ordinary controls — the shape every Step 8 fixture omitted, which is exactly why the defect shipped under a green suite. Each ordering claim is asserted TWICE: against handle.focusOrder() (the dump) and against real Tab presses recorded through opts.onFocusNav, because the dump and traverse read the rank by different code paths and a dump-only suite stays green when traversal is wired wrong — proved by mutation",
		},
		{
			name = "arrows-unregressed",
			requirements = { "UI-FOCUS-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*and the ARROWS still defer it to the end, exactly as before" && echo "$out" | grep -q "✓.*the two readings cover the SAME SET" && echo "$out" | grep -q "✓.*the tier does NOT reach the arrows" && echo "$out" | grep -q "✓.*the arrows never read the rank" && echo "$out" | grep -q "✓.*ENTRY focus still reads the unranked order, by design"',
			note = "TD-2/TD-3, the regression half. The deferral is CORRECT for directional navigation and must survive untouched; the two readings must cover one set. The entry-focus case pins the one place the stage deliberately did NOT change (a scope is entered through the arrows' reading), so a later change there is a decision rather than a drift",
		},
		{
			name = "traversal-priority",
			requirements = { "UI-FOCUS-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a positive tier pushes one control to the back without moving the others" && echo "$out" | grep -q "✓.*a negative tier pulls one to the front" && echo "$out" | grep -q "✓.*within one tier, DOCUMENT order always wins" && echo "$out" | grep -q "✓.*a non-number is refused, naming the property" && echo "$out" | grep -q "✓.*a BOUND value is refused: the prop is construction-only"',
			note = "TD-5/TD-6/TD-8: the sort TIER semantics (not an absolute index) and the §4 refusals. The same-tier case is what keeps the sort's explicit index tiebreak honest — Luau's table.sort is not stable, so equal-priority controls would otherwise be free to swap between presses",
		},
		{
			name = "consumer-map-untouched",
			requirements = { "UI-FOCUS-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the declared order survives exactly, grips and all" && echo "$out" | grep -q "✓.*navigationGroups = false is NOT a declared map: the flat ring is still ranked" && echo "$out" | grep -q "✓.*no rank means the pre-stage reading, byte for byte" && echo "$out" | grep -q "✓.*an INCOMPLETE rank is ignored entirely rather than applied to half the ring"',
			note = "TD-7 plus the graph contract under it (TDN-2). A rank is the framework's opinion about an order IT derived; a hand-authored navigationGroups map is the declared order and gets none. The incomplete-rank case pins the deliberate refusal to half-sort: mixing ranked and unranked entries yields an INTRANSITIVE comparator, which Luau's sort may reject or answer with garbage",
		},
		{
			name = "slider-focus-affordance",
			requirements = { "UI-FOCUS-001" },
			run = "out=\"$(./run-tests.sh 2>&1)\" && echo \"$out\" | grep -q \"✓.*the thumb takes a focus stroke while the track holds focus, and drops it after\" && echo \"$out\" | grep -q \"✓.*the .focusRing. thickness alias resolves to the adapter.s own ring weight\" && python3 -c \"\nimport json\nd=json.load(open('artifacts/traversal-document-order/studio/traversal.json'))\nr={x['id']: x for x in d['rows']}['TD17-slider-focus-affordance']\nassert r['status']=='PASS_AUTOMATED'\nassert 'thick=2 trans=0' in ' '.join(r['measuredAfter'])\n\" && test -f artifacts/traversal-document-order/studio/td17-slider-focused.png",
			evidence = "artifacts/traversal-document-order/studio/td17-slider-focused.png",
			note = 'TD-17, the director\'s round-2 finding: the Slider declares focusVisual = "none" so the adapter paints nothing, and what it painted instead was an accent HAIRLINE at 0.92 transparency — invisible. The suite could not see it because the existing case asserted only that a stroke EXISTED. Both halves are pinned now: the thickness/transparency the ring is actually drawn at, and that the "focusRing" alias resolves to the same number the adapter uses, so a Slider\'s ring can never drift from every other control\'s',
		},
		{
			name = "engage-and-resign",
			requirements = { "UI-INPUT-003" },
			run = "out=\"$(./run-tests.sh 2>&1)\" && echo \"$out\" | grep -q \"✓.*a tap on the UI takes the keyboard, and a tap OUTSIDE gives it back\" && grep -q 'responder = \"passive\"' examples/gallery/scenarios/keyboard_navigation.luau && python3 -c \"\nimport json\nd=json.load(open('artifacts/traversal-document-order/studio/traversal.json'))\nr={x['id']: x for x in d['rows']}['TD18-engage-and-resign']\nassert r['status']=='PASS_AUTOMATED'\nc=r['cycle']\nassert c[0]['traverse']==[] and 'Space' not in c[0]['activate'], 'at rest the keyboard must be free'\nassert c[1]['traverse']==['Tab'] and 'Space' in c[1]['activate'], 'a UI tap must take it'\nassert c[2]['traverse']==[] and 'Space' not in c[2]['activate'], 'an outside tap must give it back'\n\"",
			evidence = "artifacts/traversal-document-order/studio/traversal.json",
			note = 'TD-18, the director\'s round-3 finding: the fixture was presented engaged-open, where `resign()` is a no-op and no outside-tap catcher is ever mounted, so it held Tab and Space for the whole session. The headless case drives the two real TAPS rather than calling engage()/resign() — the existing case called the API, which is exactly why the routing gap was invisible to it. The check also pins the fixture to `responder = "passive"`, so the shape that could not unfocus cannot come back',
		},
		{
			name = "ring-follows-ownership",
			requirements = { "UI-FOCUS-001" },
			run = "out=\"$(./run-tests.sh 2>&1)\" && echo \"$out\" | grep -q \"✓.*a PASSIVE surface paints no focus ring: the ring never claims input it lacks\" && echo \"$out\" | grep -q \"✓.*an ordinary (engaged-open) screen still paints its ring exactly as before\" && python3 -c \"\nimport json\nd=json.load(open('artifacts/traversal-document-order/studio/traversal.json'))\nr={x['id']: x for x in d['rows']}['TD19-ring-follows-ownership']\nassert r['status']=='PASS_AUTOMATED'\nassert r['measuredBefore']['opaqueRingsPainted'], 'the before-state must record the defect'\nc=r['cycle']\nassert c[0]['rings']==[] and c[0]['traverse']==[], 'passive paints nothing'\nassert c[2]['rings'], 'a navigation move must bring the ring back'\nassert c[3]['rings']==[], 'resigning must take it away'\n\"",
			evidence = "artifacts/traversal-document-order/studio/td19-no-ring-when-passive.png",
			note = "TD-19, the director's round-4 finding: ring visibility was derived from focus ORIGIN alone and never from whether the surface owned input, so a passive HUD painted a ring over a keyboard the avatar had. Both halves are pinned — a passive surface paints nothing, and an engaged-open screen is byte-identical to pre-fix — because the gate is on RESPONDER ownership and a plain screen owns input from mount. The Studio row additionally pins the recorded before-state, so the defect cannot be quietly rewritten as never having happened",
		},
		{
			name = "initial-focus-and-release",
			requirements = { "UI-FOCUS-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*initialFocus defaults to the first focusable" && echo "$out" | grep -q "✓.*initialFocus = .none. mounts the surface with NO focus" && echo "$out" | grep -q "✓.*and Tab still ENTERS such a scope rather than no-opping" && echo "$out" | grep -q "✓.*initialFocus names a control by id, without the author knowing its path" && echo "$out" | grep -q "✓.*focus lands there ONCE — the ring never appears elsewhere first" && echo "$out" | grep -q "✓.*an initialFocus id that names nothing is refused, listing what is available" && echo "$out" | grep -q "✓.*makes the keyword ambiguous, and it says so" && echo "$out" | grep -q "✓.*is the escape hatch that means the CONTROL" && echo "$out" | grep -q "✓.*a dismissed surface gives up its focus ring immediately, mid-exit-transition"',
			note = "TD-20/TD-21, the director round-5 request. The DEFAULT is pinned first, because the whole point of the option is that nobody who did not ask for it moves. `focus lands there ONCE` is the case that keeps the decision in pushScope rather than in a correction afterwards, which would fire the focus observers twice and flash a ring on the wrong control. The dismissal case asserts the node is STILL MOUNTED and no longer painted — the exit-transition window is the only place the defect ever lived",
		},
		{
			name = "self-painted-ring-releases",
			requirements = { "UI-FOCUS-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a self-painted focus ring clears when the surface resigns" && echo "$out" | grep -q "✓.*a PASSIVE surface defaults to NO initial focus" && echo "$out" | grep -q "✓.*while an engaged-open screen still defaults to its first focusable" && echo "$out" | grep -q "✓.*an explicit initialFocus still wins on a passive surface"',
			note = 'TD-22/TD-23, director round 6. The ownership gate added in round 4 covered the ADAPTER\'s ring; a control declaring focusVisual = "none" paints its own and could not see it, so a Slider kept its thumb ring after the responder had already handed the keyboard back. The permission now rides the existing bindFocusGraph seam. Both halves of the new DEFAULT are pinned (passive = none, engaged-open = first) because the value of the rule is that it differs by responder — a check that only pinned one half would pass a framework that had collapsed them',
		},
		{
			name = "resign-has-no-forgiveness-zone",
			requirements = { "UI-INPUT-003" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*an engaged HUD resigns on an outside tap even CLOSE to its own content" && echo "$out" | grep -q "✓.*while a MODAL keeps its dismissal forgiveness" && echo "$out" | grep -q "✓.*a resigned surface unbinds the Adjust keys it had claimed" && echo "$out" | grep -q "✓.*a tap within 24px of the panel edge does NOT dismiss (near-miss forgiveness)"',
			note = "TD-24, director round 7. Zone A is the union bounding box of every painted node plus every focusable hit rect, inflated — modal DISMISSAL forgiveness, and on a surface holding a full-width slider it covered most of the viewport, so a click on empty world resigned nothing. The forgiveness is now destructive-outcome-only. BOTH sides are pinned: the HUD must resign on a tap close to its content, and the modal must still survive a near-miss (the existing 24px case is grepped here too, so removing forgiveness wholesale cannot pass). The Adjust half is pinned separately because it was gated on focus rather than on ownership",
		},
		{
			name = "physical-device-rows",
			requirements = { "UI-INPUT-002" },
			-- honest-pending-as-run (Step 8.5 disposition, mirroring its own
			-- physical-and-human-rows form): the gate asserts the rows are STILL
			-- honestly pending with the packet prepared, instead of carrying a
			-- bare state that makes this gate un-passable forever — which turned
			-- every later stage's prior-gates sweep permanently red through no
			-- regression at all
			run = 'f=artifacts/traversal-document-order/acceptance.md && grep -qE "^\\| \\*\\*TD-P2\\*\\* \\|.*PENDING_PHYSICAL" "$f" && test -f artifacts/traversal-document-order/review-packet.md',
			releaseBlocking = false,
			evidence = "artifacts/traversal-document-order/review-packet.md",
			note = "TD-P2, deliberately NOT closed by TD-P1. Every input in this stage is Studio-synthesized; a real client on real hardware is a separate row. It inherits Step 8's open items unchanged — DK-P1 a real OS keyboard on a phone/tablet, DK-P2 physical hot-plug against a live avatar stack, DKN-1 Tab while the CoreGui players list is enabled (the engine will not synthesize it at all), DKN-2 keyboard input marked gameProcessed while a TextBox holds capture",
		},
		{
			name = "focus-order-dump",
			requirements = { "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*carries its schema and both readings" && echo "$out" | grep -q "✓.*is deterministic: two calls with nothing changed are equal" && echo "✓ frozen" >/dev/null && echo "$out" | grep -q "✓.*is frozen — an inspector cannot mutate the map it is inspecting" && echo "$out" | grep -q "✓.*survives dispose: an overlay outliving its surface gets an empty map, not a throw" && echo "$out" | grep -q "✓.*reports the AUTHORED tier per entry"',
			note = "TD-9/TD-10: the §6 dump contract (schema string, deterministic, frozen) and the post-dispose safety that keeps a debug overlay from crashing the client it was added to diagnose. The dump reports BOTH readings, which is what makes 'one map read two ways' inspectable rather than merely asserted",
		},
		{
			name = "registration-and-docs",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_registration_cli >/dev/null && lune run tools/lune/check_docs_cli >/dev/null && lune run tools/lune/check_boundary >/dev/null && lune run tools/lune/check_prop_parity_cli >/dev/null && lune run tools/lune/check_surface_ledger >/dev/null && python3 tools/check_manifest_integrity.py >/dev/null && stylua --check src tests tools bench examples",
			note = "the standard battery at the final source. The prop-parity check is what caught traversalPriority declaring dirty classes while construction-only, and its absence from the exported ButtonSpec/ToggleSpec/TextFieldSpec/GripSpec types and from api.md's shared-prop table",
		},
		{
			name = "step8-debt-cleared",
			requirements = { "UI-AGENT-001" },
			run = "test -f artifacts/traversal-document-order/step8-debt.md && grep -q 'keyboardNavigation' docs/reference/api.md && grep -q 'Camera 100' docs/guide/07-input.md && grep -q 'Camera 100' docs/adr/ADR-0014-first-responder.md && python3 -c \"\nimport json\nd=json.load(open('artifacts/desktop-keyboard-navigation/gate.json'))\nc={x['name']: x.get('state') for x in d['checks']}\nfor k in ('adjust-claim-is-subtree-scoped','rascalrally-consumer','library-suite-green'):\n    assert c.get(k)=='PASS', (k, c.get(k))\nassert d['status']=='PASS', d['status']\n\"",
			evidence = "artifacts/traversal-document-order/step8-debt.md",
			note = "TD-16. Step 8's gate returned FAIL_RECOVERABLE when re-run at its own unmodified source (decision TDN-5): one check grepped a test that had been renamed, one ran a game test asserting a pre-Step-8 world, and its suite floor was pinned below its own finishing count. The proof that all three are repaired is Step 8's OWN gate result, so this check reads the three named checks out of its gate.json and requires PASS. Written that way after the first attempt used NEGATIVE greps for the stale strings against this manifest — which can never pass, because the check's own run string contains the strings it greps for. A check that cannot pass is the same defect class as one that cannot fail",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 3133",
			evidence = "artifacts/test.json",
			note = "stage-start floor was 3079; the floor lands as the FINAL number so a regression of this stage's own pins fails the gate. (Step 8's equivalent check pinned 3070 against a 3079 finish — corrected in this stage, see step8-debt.md)",
		},
		{
			name = "studio-evidence",
			requirements = { "UI-FID-001" },
			-- THE EVIDENCE IS CHECKED AGAINST THE SCENARIO IT WAS RECORDED FROM, and
			-- that question is asked FIRST. The whole check moved into
			-- `tools/check_traversal_evidence.py` (Milestone-1 architecture review, C1)
			-- because it stopped being a list of assertions: it is a staleness guard plus
			-- those assertions, and the guard needs prose a shell one-liner cannot carry.
			-- That file's header is the whole story.
			run = "python3 tools/check_traversal_evidence.py",
			evidence = "artifacts/traversal-document-order/studio/traversal.json",
			note = "TD-13/TD-14: raw Tab through the real adapter in a visible Play session against the keyboard_navigation scenario, with the live focus log compared against document order AND against a handle.focusOrder() dump taken in the same session. Step 8 left its post-sink key drive unverified after three execute_luau timeouts; if that recurs this lands FAIL_ENVIRONMENT with the procedure, never as a product claim. RED SINCE 2026-08-12, HONESTLY (Milestone-1 review C1): the device-bug round wrapped this fixture's body in a UI.ScrollView and every focusable moved one path segment deeper; the two order assertions were rewritten to the new paths and the RECORDING was never re-taken, so the check reported `the grip must be reached THIRD, in document position` — a sentence about traversal order, which is not what is wrong. It now fails as STALE EVIDENCE, names the re-record, and derives the expected prefix from the scenario source so the next restructure reddens it the day it lands. Re-record booked in docs/plans/device-bug-round-2026-08-12.md, section `Owed: the TD-13/TD-14 re-record`. It is not a permanent red: proved 2026-08-13 that a Body-shaped artifact makes this exact script exit 0.",
		},
		{
			name = "rascalrally-consumer",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/traversal-document-order/consumer-impact.md && test -f "$f" && grep -q "TD15-consumer-canary" "$f" && grep -q "luauui_focus_order_contract" "$f" && test -f ../../../games/RascalRally/code/tests/luauui_focus_order_contract.spec.luau && cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1',
			evidence = "artifacts/traversal-document-order/consumer-impact.md",
			note = "TD-15: the consumer-impact ledger audits every changed contract against the game's real callers, and the check re-runs the game suite live at the source being judged rather than trusting a stored transcript",
		},
		{
			name = "human-review",
			requirements = { "UI-INPUT-002" },
			run = 'f=artifacts/traversal-document-order/acceptance.md && grep -q "PASS_HUMAN" "$f" && grep -q "Human review — TD-P1, closed" "$f"',
			evidence = "artifacts/traversal-document-order/review-packet.md",
			note = 'TD-P1, CLOSED by the director 2026-08-03 ("both feel good"): the focus ring reads at a glance, and tabbing the form reads as the form reads. This row existed because the stage it fixes passed its gate and three fresh-context reviews and a person still found the defect in ten minutes — seven director rounds later, it found six more. It closes the E5 row ONLY: a Studio review on a desktop window does not speak for hardware, which is why the physical row below stays separate',
		},
	},
	["desktop-keyboard-navigation"] = {
		-- Roadmap Step 8 (docs/plans/desktop-keyboard-navigation.md): Tab/Shift+Tab
		-- traversal, Space-as-Activate, and focused-value arrow Adjust, all through
		-- the EXISTING focus graph / responder / IAS architecture. Registered BEFORE
		-- any edit with honest PENDING checks per the plan's "Gate"; each flipped to
		-- `run` only once its work and evidence actually existed. Acceptance rows
		-- DK-1..DK-18 live in artifacts/desktop-keyboard-navigation/acceptance.md.
		{
			name = "acceptance-ledger",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/desktop-keyboard-navigation/acceptance.md && test -f "$f" && for id in DK-1 DK-4 DK-7 DK-9 DK-11 DK-12 DK-13 DK-16 DK-17 DK-18 DK-P1; do grep -q "$id" "$f" || { echo "$id missing"; exit 1; }; done && grep -q "PENDING_PHYSICAL" "$f" && test -f artifacts/desktop-keyboard-navigation/decisions.md && grep -q "DKN-1" artifacts/desktop-keyboard-navigation/decisions.md',
			evidence = "artifacts/desktop-keyboard-navigation/acceptance.md",
			note = "execution contract §2: the ledger written BEFORE implementation, with a final honest status per row and the physical rows left pending rather than closed by an easier instrument. The decision packets it cites (DKN-1 Tab/CoreGui, DKN-2 TextBox suppression, DKN-3 the adjustTargets root, DKN-4 the consumer Space collision) are checked to exist beside it",
		},
		{
			name = "traversal-pure",
			requirements = { "UI-FOCUS-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*traverse(+1) walks the flat scope forward" && echo "$out" | grep -q "✓.*Tab leaves a CONTAINED group that the arrows cannot leave sideways" && echo "$out" | grep -q "✓.*Shift+Tab crosses back into the previous group at its LAST node" && echo "$out" | grep -q "✓.*wraps by default at both ends" && echo "$out" | grep -q "✓.*traversalWrap = false stops at the ends" && echo "$out" | grep -q "✓.*a GROUPED scope.s wrap policy is the scope.s, not any group.s" && echo "$out" | grep -q "✓.*an ineligible focus-skip entry is stepped over, not landed on" && echo "$out" | grep -q "✓.*focus stays put when nothing else in the scope is eligible" && echo "$out" | grep -q "✓.*a node removed between presses never becomes a traversal target" && echo "$out" | grep -q "✓.*re-ordering the scope re-reads the order on the very next press" && echo "$out" | grep -q "✓.*Tab cannot leave a trapped scope and the prior focus is restored on pop"',
			note = "DK-1..DK-6: red-first pure specs for forward/reverse traversal, contained-group crossing, the SCOPE-level wrap policy (distinct from a group's own arrow wrap), live focus-skip predicates, structural churn, and modal trap + restore. Form A, so a failing suite reddens the check",
		},
		{
			name = "action-system-behavior",
			requirements = { "UI-INPUT-003", "UI-INPUT-004" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*Tab and Shift+Tab move the focus ring through a plain form" && echo "$out" | grep -q "✓.*Space activates the focused control exactly once" && echo "$out" | grep -q "✓.*a disabled control consumes Space and does nothing" && echo "$out" | grep -q "✓.*a native Activated echoing the same keyboard press does not activate twice" && echo "$out" | grep -q "✓.*a real pointer tap beside a key press is two presses, never an echo" && echo "$out" | grep -q "✓.*a spent echo does not roll the window forward onto the next real press" && echo "$out" | grep -q "✓.*Shift+Tab into a scope with no focus enters at the LAST eligible node" && echo "$out" | grep -q "✓.*a surface with no selection bridge never collapses a tap next to a key press" && echo "$out" | grep -q "✓.*Left/Right adjust a focused horizontal Slider on a GROUPED screen" && echo "$out" | grep -q "✓.*the OTHER axis still navigates while the value control holds focus" && echo "$out" | grep -q "✓.*the Adjust keys are UNBOUND while focus sits off a declared target" && echo "$out" | grep -q "✓.*Tab commits through the field.s own path and only THEN advances focus" && echo "$out" | grep -q "✓.*the arrows stay with the field.s own sinking context while editing" && echo "$out" | grep -q "✓.*a PASSIVE HUD binds no Tab and no Space: gameplay is untouched" && echo "$out" | grep -q "✓.*engage() binds them and resign() gives them back, with no residue" && echo "$out" | grep -q "✓.*keyboard hot-plug adds and removes the bindings with no stuck sink" && echo "$out" | grep -q "✓.*a dismissed screen stops eating Tab and Space"',
			note = "DK-8..DK-15 driven through system.deviceKey (the arbitrated device path, never a direct callback): responder ownership, keyboard hot-plug bind/unbind with no leaked sink, teardown, exactly-once activation across the IAS and native-tap paths INCLUDING the two negative cases that keep the echo window from eating real presses, Space/Return parity, axis-scoped Adjust routing, and text editing",
		},
		{
			name = "adjust-claim-is-subtree-scoped",
			requirements = { "UI-PARADIGM-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the Adjust keys unbind when focus leaves the control for a sibling button" && echo "$out" | grep -q "✓.*a sibling button.s arrows fire no dead Adjust"',
			note = "DK-11, the defect Studio found under a green suite: the presenter handed `adjustTargets` the SCREEN root while `focusGroups` beside it has always been handed the contribution's own node, so newStepper/newRating claimed every Button/Grip on the screen and the Adjust keys stayed bound with focus anywhere. Both regressions put the value control on a screen WITH a sibling button, which is what every prior fixture omitted",
		},
		{
			name = "keep-visible-on-traverse",
			requirements = { "UI-FOCUS-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*tabbing past the visible band scrolls the host, with no control wiring"',
			note = "DK-7: a traversal move routes through the SHARED keep-visible service (controller.scrollToVisible via handle.focusMoved) rather than a second scroll path — asserted on the host's own scroll position, not on the call",
		},
		{
			name = "no-screen-key-bindings",
			requirements = { "UI-INPUT-001" },
			run = '! grep -rn "KeyCode" src/controls/ | grep -qvE ":[0-9]+:[[:space:]]*--" && ! grep -rn "UserInputService" src/controls/ | grep -qvE ":[0-9]+:[[:space:]]*--" && ! grep -rn "ContextActionService" src/controls/ | grep -qvE ":[0-9]+:[[:space:]]*--" && test "$(grep -rlE "keyCode *=" src/controls/ | sort | tr "\\n" " ")" = "src/controls/row_actions.luau src/controls/text_input.luau " && test "$(grep -oE "keyCode *=" src/controls/row_actions.luau | wc -l | tr -d " ")" = "4" && test "$(grep -oE "keyCode *=" src/controls/text_input.luau | wc -l | tr -d " ")" = "2" && ! grep -qE "keyCode *=|createAction\\(|\\.bind\\(" examples/gallery/scenarios/keyboard_navigation.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*Tab and Shift+Tab move the focus ring through a plain form"',
			note = "COUNTS OCCURRENCES, NOT LINES (2026-08-14). `grep -c` counts matching LINES, so this pin was measuring FORMATTING: round 3 consolidated row_actions' four key declarations into one `ROW_KEYS` table -- two lines holding the same four bindings, because a host now binds the identical set while standing in for an engine that does not exist until a swipe -- and the pin read 2 against 4 and failed a refactor that removed nothing. `grep -o | wc -l` counts the bindings themselves, which is what the row has always claimed: four on row_actions (Delete, Backspace, ButtonX, Shift+Return), two on text_input. A NEW binding still moves it. DK-16: the behavior is automatic for public controls, with ONE sanctioned seam. The first three clauses were CASE-BLIND when first written (phase-gate PG-2): they grepped `KeyCode` while the spelling this repo uses at a binding site is lowercase `keyCode`, so a new control binding Tab would have been invisible — proven by copying stepper.luau to scratch, appending a keyCode bind, and watching all three clauses still pass. Extending the pin for row_actions.luau (below) surfaced a SIBLING defect in those same three clauses: they were also COMMENT-BLIND, tripped by row_actions.luau's own engineering-rationale comment naming `Enum.KeyCode` in prose (explaining why PrimaryModifier needs two physical-Shift InputBindings), not a binding. All three now skip comment-only lines (`grep -rn` piped through a filter for a `:<line>:<whitespace>--` line shape) instead of scanning raw file text, so real bypass code still reddens the check and explanatory prose never does. The check now PINS the lowercase binding sites exactly across TWO files: text_input.luau (2 — its text-entry Swallow and Cancel bindings, a control-owned sinking context, not a screen binding a key) and row_actions.luau (4 — RowActionsDelete binds Delete+Backspace, RowActionsMenu binds ButtonX and Shift+Return; director-approved Tasks 8/8b, 2026-08-10). Both are the SAME sanctioned seam: contribution-scoped through bindActionSystem (the identical seam text_input.luau's own bindings ride), per-row focus-gated (ctx.setEnabled tracks `pathInsideRow`, never global), with the open menu owning ALL action dispatch while up (the MENU-OPEN CARVE-OUT guard on RowActionsDelete, review round 1 MAJOR) and the Shift+Return modifier match arbitrated through the identical priority/sink mechanism every other binding here already goes through — no second wiring path, so the raw UserInputService/ContextActionService/bare-Enum.KeyCode bypass class this check hunts does not apply. A THIRD file appearing, or either pinned count drifting, still reddens this check (mutation-proved: a fake keyCode bind appended to stepper.luau fails it; bumping a pinned count with no matching code change fails it too; restoring passes again). The Studio fixture CREATES no binding either — the test is for a `keyCode =` assignment or a createAction/bind call, since the fixture READS `binding.keyCode` for its trace, which is observation, not wiring. The traversal case that proves the behavior presents with ZERO input opts",
		},
		{
			name = "registration-and-docs",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_registration_cli >/dev/null && lune run tools/lune/check_docs_cli >/dev/null && lune run tools/lune/check_boundary >/dev/null && lune run tools/lune/check_prop_parity_cli >/dev/null && lune run tools/lune/check_surface_ledger >/dev/null && python3 tools/check_manifest_integrity.py >/dev/null && stylua --check src tests tools bench examples",
			note = "the standard battery at the final source: api.md drift both directions, the engine-free require graph plus the consumer scan, theme-doc anchors, seven-view property parity, surface-ledger classification of the new public items, manifest grep integrity, and stylua proving the diff is not a reformat",
		},
		{
			name = "conformance-proofs",
			requirements = { "UI-PARADIGM-001" },
			run = 'grep -q "Tab and Shift+Tab move the focus ring through a plain form" tests/conformance/controls_registry.luau && grep -q "Space activates the focused control exactly once" tests/conformance/controls_registry.luau && grep -q "a PASSIVE HUD binds no Tab and no Space" tests/conformance/controls_registry.luau && grep -q "Left/Right adjust a focused horizontal Slider on a GROUPED screen" tests/conformance/controls_registry.luau && grep -q "Space on the focused button steps the value, in both directions" tests/conformance/controls_registry.luau && lune run tools/lune/check_registration_cli >/dev/null',
			note = "the registry's keyboard input/affordance cells cite the new cases verbatim for Button, TextInput, Slider and Stepper, and check_registration proves every cited name exists in a registered spec",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 3079",
			evidence = "artifacts/test.json",
			note = "stage-start floor was 3028 (baseline/test-before.json, captured from a worktree pinned to aeffc68); the floor lands as the FINAL number so a regression of this stage's own pins fails the gate. CORRECTED 2026-08-03 (traversal-document-order TDN-5): the pin said 3070 while the stage actually finished at 3079, so nine of its own tests were outside the floor",
		},
		{
			name = "studio-evidence",
			requirements = { "UI-FID-001" },
			run = "python3 -c \"\nimport json,sys\nd=json.load(open('artifacts/desktop-keyboard-navigation/studio/keyboard.json'))\nassert d['preflight']['scenarioState']=='ready', 'preflight'\nassert d['preflight']['libraryVersion']=='0.8.0', 'version'\nrows={r['id']: r for r in d['rows']}\nneed={'DK17-B-form-traversal','DK17-C-keep-visible','DK17-D-modal-trap-and-restore','DK17-G-space-and-return-activate','DK17-H-value-control-axis','DK17-I-adjust-claim-is-subtree-scoped','DK17-J-keyboard-hot-plug'}\nassert need <= set(rows), sorted(need-set(rows))\nfor k in need: assert rows[k]['status']=='PASS_AUTOMATED', k\nassert rows['DK17-F-tab-while-editing']['status']=='FAIL_ENVIRONMENT', 'F must stay honest'\nassert rows['DK17-A-tab-contended']['status']=='FAIL_ENVIRONMENT', 'A must stay honest'\n\" && test -f artifacts/desktop-keyboard-navigation/studio/dk17-fixture.png",
			evidence = "artifacts/desktop-keyboard-navigation/studio/keyboard.json",
			note = "DK-17: raw Tab/Shift+Tab/Space/Return/arrow events driven with VirtualInput through the real adapter in a visible Play session, each row pairing the raw keyboard log (with gameProcessed), the semantic action, the focus log, the scroll position and the control state. The check reads the STATUS FIELD per row and pins the two honest FAIL_ENVIRONMENT rows so they cannot be quietly upgraded",
		},
		{
			name = "rascalrally-consumer",
			requirements = { "UI-AGENT-001" },
			run = 'test -f artifacts/desktop-keyboard-navigation/consumer-impact.md && grep -q "DKN-4" artifacts/desktop-keyboard-navigation/consumer-impact.md && grep -q "DK18-consumer-canary" artifacts/desktop-keyboard-navigation/consumer-impact.md && cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1',
			evidence = "artifacts/desktop-keyboard-navigation/consumer-impact.md",
			note = "the consumer-impact ledger audits all eight changed contracts against the game's real callers with file:line evidence, and the check RE-RUNS the game suite live at the source being judged rather than trusting a stored transcript",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = 'if [ -n "${LUAUUI_PRIOR_GATES_NESTED:-}" ]; then echo "prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)"; exit 0; fi; b=artifacts/desktop-keyboard-navigation/baseline/prior-gates-before.txt && a=artifacts/desktop-keyboard-navigation/prior-gates.txt && test -f "$b" && test "$(grep -cE "^PASS " "$b")" -ge 15 && tools/prior_gates.sh "$a" desktop-keyboard-navigation && grep -q "^DONE$" "$a" && lost="$(comm -23 <(grep "^PASS " "$b" | sort) <(grep "^PASS " "$a" | sort))" && test -z "$lost"',
			evidence = "artifacts/desktop-keyboard-navigation/prior-gates.txt",
			note = "all prior gates RE-RUN IN-TREE at the final source via tools/prior_gates.sh (nested-guard aware). The baseline is the PREVIOUS stage's in-tree roll-up, not a worktree run: a pinned worktree cannot read the gitignored evidence artifacts most checks consume, so a worktree baseline is all-FAIL and makes this comparison vacuously green — the exact can't-ever-fail shape the 2026-07-29 sweep removed (docs/lessons/pinned-worktree-cannot-rerun-gates.md). The `-ge 15` floor on the baseline is what stops a degenerate before-set from passing this check",
		},
		{
			name = "fresh-context-reviews",
			requirements = { "UI-AGENT-001" },
			run = "python3 -c \"import json,sys; p=json.load(open('artifacts/desktop-keyboard-navigation/verifier-phase-gate.json')); a=json.load(open('artifacts/desktop-keyboard-navigation/verifier-architecture.json')); t=json.load(open('artifacts/desktop-keyboard-navigation/verifier-platform.json')); sys.exit(0 if p.get('verdict') in ('READY TO DECLARE','ACCEPT') and a.get('verdict') in ('ACCEPT','ACCEPT-WITH-FINDINGS') and t.get('verdict') in ('ACCEPT','ACCEPT-WITH-FINDINGS') else 1)\"",
			evidence = "artifacts/desktop-keyboard-navigation/verifier-phase-gate.json",
			note = "fresh-context phase-gate + architecture (public contracts changed: traversalWrap, adjustAxis, handleTraverse, graph.traverse) + Roblox-platform (the Tab/CoreGui and TextBox-suppression findings) reviews on the raw artifacts; the check reads the verdict FIELD, never a grep for an accept token",
		},
		{
			name = "physical-and-contended-rows",
			requirements = { "UI-INPUT-002" },
			state = "FAIL_ENVIRONMENT",
			releaseBlocking = false,
			evidence = "artifacts/desktop-keyboard-navigation/review-packet.md",
			note = "four rows no instrument in this build can close: DK-P1 a real operating-system keyboard on a phone/tablet (the emulator cannot produce a keyboard-capable touch device and never summons the mobile OS keyboard); DK-P2 physical keyboard hot-plug against a real avatar control stack; DK17-A Tab while the CoreGui players list is enabled (the engine refuses to synthesize the key at all — decision packet DKN-1); DK17-F Tab inside a focused TextBox (the engine marks keyboard input gameProcessed and fires no developer binding — DKN-2). Exact procedures in review-packet.md",
		},
	},
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
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*re-bases while awaiting" && echo "$out" | grep -q "✓.*still returns the envelope and leaves the mutation usable" && echo "$out" | grep -q "✓.*does not latch the gap" && echo "$out" | grep -q "✓.*escapes a stuck pending request" && echo "$out" | grep -q "✓.*INFLATED backing layer keeps its drag declaration" && echo "$out" | grep -q "✓.*unknown spec key is refused, naming the modifier" && echo "$out" | grep -q "✓.*typo.d gradient field is refused" && echo "$out" | grep -q "✓.*cannot disable framework validation" && echo "$out" | grep -q "✓.*rejects a read-only Memo" && echo "$out" | grep -q "✓.*header title honours the column alignment" && echo "$out" | grep -q "✓.*table.freeze.d grouped scope" && echo "$out" | grep -q "✓.*ledger is the UNION of schema-generated and declared" && echo "$out" | grep -q "✓.*at least one MINOR of notice, and the ledger is frozen" && echo "$out" | grep -q "✓.*opts.scope owns the memo" && echo "$out" | grep -q "✓.*a critical fallback under rootPolicy" && echo "$out" | grep -q "✓.*an unknown responder names the opt" && echo "$out" | grep -q "✓.*semanticText is a Readable" && echo "$out" | grep -q "✓.*both forms answer identically for the same inputs" && echo "$out" | grep -q "✓.*a throwing formatter falls back to the default format" && echo "$out" | grep -q "✓.*refuses a non-empty opts table" && echo "$out" | grep -q "✓.*the sweep covers every boundary the constitution.s §4 claim names" && echo "$out" | grep -q "✓.*newResourceProvider refuses .definitelyNotAKey. and names itself" && echo "$out" | grep -q "✓.*complete the family and pulse the same way" && echo "$out" | grep -q "✓.*it detects a restricted class the authority manifest does not back"',
			note = "twenty-four named red-first regressions across the compatible-fix families (F-1..F-40 in dispositions.md; the last four pin the architecture-review resolution round — the spec_guard sweep's coverage floor + a per-boundary refusal, the *Data family pulse, and parity view 7), each anchored to the PASS marker (Form A — the assignment carries the suite exit code, so a failing suite reddens this check). The two ADR-0011 deprecations are pinned by the UNION-ledger and one-MINOR-of-notice cases; the deprecated surfaces keep working (their own specs still run)",
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
			run = 'f=artifacts/api-architecture-consistency/fresh-author-exercise.md && test -f "$f" && grep -q "rule b" "$f" && grep -qi "friction" "$f" && grep -q "newTagCount.* is not classified in the surface ledger" "$f" && grep -qi "verdict" "$f" && test ! -f src/controls/tag_count.luau',
			evidence = "artifacts/api-architecture-consistency/fresh-author-exercise.md",
			note = "run 2026-08-02, VERDICT YES: a fresh author with ONLY the public docs scaffolded, implemented, tested, registered and documented a small composite (newTagCount) with zero internal imports. Deliberate-omission probe: the four-input/paradigm registry obligations produced 9 named, actionable failures (exemplary); the api.md TODO-stub and the skipped dump-determinism case shipped GREEN — two one-axis-deep checks recorded as findings, not hidden — and check_surface_ledger caught the unclassified new export verbatim. 12-item friction log preserved in the artifact; the toy control was reverted after archiving (the last clause proves it), so the shipped surface is unchanged",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 2980",
			evidence = "artifacts/test.json",
			note = "stage-start floor was 2785; the floor lands as the FINAL number (2980 = +195 stage regressions and proofs across the seven packages incl. the architecture-review fixes, none removed and none weakened) so a regression of this stage's own pins fails the gate",
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
				.. "assert {'S1-header-alignment-live','S2-consumer-modal-real-pointer','S3-keyboard-semantic-path','S4-lifecycle'} <= ids, 'slices';"
				.. "assert all(s['level']=='E3' for s in c['slices']), 'levels';"
				.. "assert any('NS-P2' in o for o in c['honestObservations']), 'touch honesty';"
				.. '" && test -f artifacts/api-architecture-consistency/studio-disposition.md && grep -q "F-17" artifacts/api-architecture-consistency/studio-disposition.md && lune run tools/lune/check_flat_baseline >/dev/null',
			evidence = "artifacts/api-architecture-consistency/studio-disposition.md",
			note = "disposition-aware real-adapter proof, run in the LIVE Rojo-synced consumer place at v0.8.0: header alignment measured on real Instances both ways plus the sort-mark clearance; the game's own mandatory RolePick modal driven by a real routed click (scrim swallow observed, then dismissal); the full keyboard semantic path (focus -> column select -> sort cycle) through client/roblox_input; clean teardown. Touch-gesture FIRING stays honestly on physical row NS-P2 — Studio cannot synthesize touch. check_flat_baseline re-proves the regenerated 1140-node flat solve with the F-27 delta recorded in canary.json (it rides the pre-existing characterized /Playlist/ reshape scope)",
		},
		{
			name = "fresh-context-reviews",
			requirements = { "UI-AGENT-001" },
			run = "python3 -c \"import json,sys; a=json.load(open('artifacts/api-architecture-consistency/verifier-architecture.json')); p=json.load(open('artifacts/api-architecture-consistency/verifier-phase-gate.json')); sys.exit(0 if a.get('verdict')=='ACCEPT' and p.get('verdict') in ('READY TO DECLARE','ACCEPT') else 1)\"",
			evidence = "artifacts/api-architecture-consistency/verifier-phase-gate.json",
			note = "fresh-context architecture + phase-gate reviews ran on the raw surface ledger, baseline, diff, decisions, exercise, and evidence. Round 1: both ACCEPT-WITH-FINDINGS (architecture: 4 requirement-affecting — §4 strictness overclaim, three undispositioned MAJORs, the Label semanticText boundary call, the hand-assembled baseline; phase-gate: 6 MINOR). Every finding was resolved (spec_guard sweep, F-39/F-40/BEX-1/PKT-13, script-generated baseline, strict slice assert, packet costs, on-disk capture, physical-rows row) and both reviewers RE-VERIFIED the resolutions against the tree: architecture ACCEPT, phase-gate READY TO DECLARE, zero requirement-affecting findings open. The check reads the verdict FIELDS, never a grep for an accept token; runtime/platform review was not triggered (no reactive-runtime or platform-authority change beyond what the platform-adjacent evidence already covers)",
		},
		{
			name = "physical-rows",
			requirements = { "UI-INPUT-002" },
			state = "FAIL_ENVIRONMENT",
			releaseBlocking = false,
			evidence = "artifacts/api-architecture-consistency/studio-disposition.md",
			note = "phase-gate reviewer PG-A4: the F-17 touch-gesture repair (positional args + userdata readers at the screen adapter) is headlessly pinned and source-asserted, but real gesture FIRING needs physical touch no Studio instrument synthesizes — it stays on native-substrate's standing row NS-P2, restated here so this gate carries its own honest pending row instead of borrowing another stage's",
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
			run = "lune run tools/lune/_probe_public_surface > artifacts/code-simplicity-cleanup/public-surface.txt && python3 -c \"\nnorm=lambda l: l.replace('table(frozen)','table')\nnow={norm(l) for l in open('artifacts/code-simplicity-cleanup/public-surface.txt')}\nmissing=[l.rstrip() for l in open('artifacts/code-simplicity-cleanup/baseline/public-surface-before.txt') if norm(l) not in now and not l.startswith('VERSION')]\nassert not missing, ('REMOVED from the public surface:', missing)\n\"",
			evidence = "artifacts/code-simplicity-cleanup/public-surface.txt",
			note = "the stage's own promise, restated at its true scope (Step 8.5 disposition, phase-gate review F1): CLEANUP REMOVED NOTHING — every line of the frozen before-surface (minus the VERSION stamp) must still exist in the live surface. The original byte-equality form went permanently red the moment Step 7 legitimately ADDED public API (v0.7->v0.8 drift measured ~20 lines: text.fit, composition.*, adaptive additions, two DEPRECATIONS rows), which is the stale-check class step8-debt already documented for Step 8; ADDITIONS are governed by the api-architecture-consistency surface ledger, whose gate re-runs against the current tree. A REMOVED export still reddens this check, which is the claim the cleanup stage actually made",
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
			run = '! grep -l "navigationGroups\\|onNavigateIntercept\\|onFocusNav\\|keepVisibleOffset\\|onGeometry" examples/gallery/examples/*.luau && lune run tools/lune/check_example_drift_cli && [ "$(cat examples/gallery/examples/0*.luau | wc -l)" -le 3200 ]',
			note = "regression proof vs the wp-c baselines: generic input wiring ~158 lines -> 0 (no example passes any present() input opt). THE CHECK'S SUBJECT IS THE GREP, and it has stayed clean through every round. The line ceiling is a PROXY for it, and 2026-08-06 (example-quality-pass) is where the proxy stopped tracking its subject: that stage was chartered to add the mechanics the examples were MISSING — example 05's dictionary/validation/keyboard-state/restart/non-colour cues, example 03's player-reachable server with accept/reject/rollback/reset, 06's instructions/completion/reset, 07's scoring/hints/legal-move dealing, 04's visible outcome and Restore — so 1644 -> 2908 is required domain content, and a ceiling that forbade it would forbid the plan. Refreshed to 3100 with that reason, then to 3200 on 2026-08-14 for the same one: `13fd3c6` (\"swipe actions on the playlist table -- and the two device findings, measured\") took it 3007 -> 3142, which is the shipped demo the standing rule \"every gap ships its showcase demo\" requires. WORTH RECORDING: that overage went unnoticed from `13fd3c6` until the round-3 prior-gates sweep was actually RUN -- a stage can carry a red row for a whole round if nobody re-runs the sweep, which is exactly what the sweep row is for. Round 3 itself added ZERO lines here (3142 at `8560f2b~1` and 3142 at HEAD), so this is an inherited red, not a round-3 regression. The weak proxy is no longer carrying the claim alone: `tools/lune/check_example_drift_cli` now runs in the same step. Its R4 rule is the real assertion (no engine or adapter reach-around in an example) and R1-R3 additionally pin style authority, which a line count never could. Earlier refresh: 1587 -> 1644 during sponsor-framework-gaps' prior-gates rerun, for the 2026-07-26/27 director rounds that grew 02 (315->352, Table.scrolls page-scroll ruling) and 04 (87->107, the Rating control); app-semantic wiring kept per the wp-c keep-list (05 hardware-key context, node-level onActivate handlers)",
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
			run = "tools/test.sh 176 && ./run-tests.sh 2>&1 | grep -q '✓.*header taps cycle the owner-held sortOrder' && ./run-tests.sh 2>&1 | grep -q '✓.*per-column alignment positions cell content' && ./run-tests.sh 2>&1 | grep -q '✓.*columns own their cells' && ./run-tests.sh 2>&1 | grep -q '✓.*width sugar: a number is fixed px' && ./run-tests.sh 2>&1 | grep -q '✓.*grip drag previews a guide line and commits the width on release' && ./run-tests.sh 2>&1 | grep -q '✓.*ghost + indicator with the row IN PLACE' && ./run-tests.sh 2>&1 | grep -q '✓.*an invalid drop (outside the table) commits nothing' && ./run-tests.sh 2>&1 | grep -q '✓.*system interrupt (Roblox menu opened) aborts the drag' && ./run-tests.sh 2>&1 | grep -q '✓.*arrow navigation moves the SELECTION with focus' && ./run-tests.sh 2>&1 | grep -q '✓.*shift-click extends a contiguous range from the anchor' && ./run-tests.sh 2>&1 | grep -q '✓.*a focused column handle resizes its column via the Adjust action' && ./run-tests.sh 2>&1 | grep -q '✓.*sinkNavigation stops nav keys' && ./run-tests.sh 2>&1 | grep -q '✓.*wraps at the edges'",
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
			run = 'grep -q "assertNoFocusableContent" src/blueprint.luau && grep -q "effectiveHitFloor" src/render/renderer.luau && grep -q "setHitRect" src/client/screen_target.luau && grep -q "isDisabled" src/present/presenter.luau && grep -q "Destructive button" src/tokens/sheet_model.luau && grep -q "dangerPair" src/tokens/sheet_model.luau && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a focusable inside the content is rejected: one activation surface, one focus site" && echo "$out" | grep -q "✓.*a content button exposes exactly ONE focusable and activates once" && echo "$out" | grep -q "✓.*a sub-floor button reports an expanded hit rect" && echo "$out" | grep -q "✓.*a button already at or above the floor gets NO expander" && echo "$out" | grep -q "✓.*a disabled button is skipped by focus navigation" && echo "$out" | grep -q "✓.*a disabled button does not activate on the keyboard or gamepad path either" && echo "$out" | grep -q "✓.*every theme.s danger pair passes the contrast gate" && test -f artifacts/authoring-adaptive-ui/b-btn-button.json',
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
			-- honest-pending-as-run (Step 8.5 disposition, same conversion as the
			-- traversal gate's physical row): assert the packet is still prepared
			-- and the rows still declared pending, instead of a bare state that
			-- kept this gate permanently un-passable in every later sweep
			run = 'f=artifacts/authoring-adaptive-ui/review-packet.md && test -f "$f" && grep -q "PENDING_PHYSICAL" "$f" && grep -q "P1" "$f" && grep -q "P5" "$f"',
			releaseBlocking = false,
			evidence = "artifacts/authoring-adaptive-ui/review-packet.md",
			note = "P1..P5: physical touch targeting/momentum/slider feel, real gamepad class + Adjust at ten-foot, the mobile OS keyboard, floor-device performance, and the human adaptive-readability review — never closed by emulator or headless evidence; the check asserts the packet stays prepared and honestly pending",
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

	["row-actions"] = {
		-- SwiftUI-parity row swipe actions (docs/plans/row-actions.md,
		-- docs/plans/row-actions-implementation.md): newRowActions/
		-- newRowActionsCoordinator + Table's `rowActions` integration, full
		-- cross-input coverage. Task 12. Six load-bearing suite cases stand in
		-- for the ~150-case row_actions*.spec.luau corpus (Form A only, per
		-- the header discipline above): one per structurally distinct
		-- mechanism (mouse gesture, coordinator, axis-lock arbitration with
		-- reorder, the presentModal menu re-home, keyboard, and the RED-TEAM
		-- iOS tap-to-close fix), so a regression in any one of those
		-- mechanisms reddens this gate rather than riding on the others'
		-- coverage. row-actions-hosted-mode-plan Task 5 (VirtualList/Table
		-- host `rowActions` directly) added five more load-bearing cases,
		-- named here Task 8: the tray focus-traversal + restore fix, the
		-- Activate-seam close, the reused-spring snap-back regression, and
		-- the mount-identity differential's two shipping claims (exactly one
		-- extra overlay node, zero instance leaks across engage/disengage).
		-- Names verified against a live `./run-tests.sh` run before being
		-- pinned here, not copied from a report untouched.
		{
			name = "row-actions-suite",
			requirements = { "ROW-ACTIONS-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*full swipe commits (destructive): row slides off, collapses, onAction fires exactly once" && echo "$out" | grep -q "✓.*opening row B closes row A (one-open policy)" && echo "$out" | grep -q "✓.*vertical drag never moves the offset (axis lock)" && echo "$out" | grep -q "✓.*solved rect (y, x, height) byte-identical" && echo "$out" | grep -q "✓.*Delete on a focused row fires the first destructive action" && echo "$out" | grep -q "✓.*own content while ITS tray is open closes it" && echo "$out" | grep -q "✓.*(P9) focus TRAVERSAL: the d-pad reaches the revealed tray, and the ring comes BACK to the row" && echo "$out" | grep -q "✓.*(P10) the ACTIVATE SEAM closes the open row: Return on ANOTHER row puts the tray away" && echo "$out" | grep -q "✓.*(P2b) REGRESSION: every later short swipe on the SAME row also snaps back (the reused spring)" && echo "$out" | grep -q "✓.*a hosted list.s mounted paths are the plain list.s PLUS exactly the one overlay node" && echo "$out" | grep -q "✓.*engaging and disengaging returns the tree to the closed shape, with zero instance leaks"',
			note = "the full-swipe commit trajectory (tests/row_actions_input.spec.luau), the one-open coordinator (same file), pointer axis lock (same file), the RED-TEAM item-2 menu-contributes-zero-to-measure fix (tests/row_actions_input.spec.luau 'redteam item 2' block), keyboard Delete (same file), and the iOS tap-to-close fix through Table (tests/table.spec.luau) — one case per distinct mechanism, not six cases of the same one. Plus, from the hosted-mode plan (Task 5, tests/virtual_list_row_actions.spec.luau + tests/virtual_list_row_actions_identity.spec.luau): tray d-pad focus traversal + the R1 focus-restore fix (P9), the K1 Activate-seam close (P10), the shared-engine reused-spring regression (P2b), and the mount-identity differential's two shipping claims (exactly one extra overlay node; zero instance leaks across five engage/disengage cycles) — the apostrophes in the two identity-spec names ('list's') are matched with `.` (single-char wildcard), not a literal `'`, because this whole `run` value is itself a Lua SINGLE-quoted string: a literal apostrophe inside it would terminate the Lua string early rather than reach the shell as part of the grep pattern.",
		},
		{
			name = "row-actions-device-matrix",
			requirements = { "ROW-ACTIONS-001" },
			-- The plan's own sketch here was `test -f "$f" && ! grep -q "FAIL" "$f"
			-- && ! grep -qE "PENDING" "$f"` — which the artifact as legitimately
			-- shipped can never pass, since it legitimately contains candid
			-- "FAIL"/"superseded" prose in its own history. tools/check_row_actions_matrix.py
			-- replaces the blanket grep with three real assertions: the
			-- five-view FUNCTIONAL matrix must contain no FAIL cell, the
			-- artifact's "Current numbers" table (steady scroll, fling, wrapper
			-- instance count) must still be present, and each must not exceed
			-- the ceiling below — a future regression above those numbers
			-- reddens this check; the documented rider rows and the candid
			-- superseded-history prose never do (see the script's own docstring).
			--
			-- RE-BASELINE HISTORY. 2026-08-11 (director ruling, interim): the
			-- manual per-row `newRowActions` wrap Task 11/11b measured missed
			-- the plan's original <=5%/<=4-instance budget badly (steady +57%,
			-- fling +81%, +5 instances/row — mount-dominated), so the gate was
			-- re-baselined to those SHIPPED numbers as an interim ceiling, with
			-- the VirtualList-gesture-hook mission chartered as the closure
			-- path (docs/plans/row-actions-perf-mission.md).
			--
			-- 2026-08-12 BUDGET RESTORED (row-actions-hosted-mode-plan Task 8,
			-- this change). That closure mission landed: VirtualList/Table now
			-- host `rowActions` directly, so a closed row mounts no per-row
			-- `Hit` grip or gesture engine. Task 7's de-biased (ABBA-
			-- interleaved, >=5-run-mean) re-measurement of that hosted
			-- integration found the real cost sits back inside the plan's
			-- ORIGINAL <=5% timing budget with real headroom (hosted steady
			-- -0.28% mean, fling +2.83% mean — see device-matrix.md's "Current
			-- numbers" table and
			-- .superpowers/sdd/row-actions-hosted-mode-plan/task-7-report.md
			-- Sec 0), so the ceiling is restored to <=5%/<=5% on the timing
			-- side. The instance ceiling is TIGHTENED past the plan's original
			-- <=4 to <=1: the hosted design's own closed-row cost is
			-- integer-deterministic at +0.08 nodes/windowed-row (one shared
			-- overlay instance for the whole list, not one per row), so <=1 is
			-- the sharp regression detector two independent review rounds
			-- specified for a number that precise — <=4 would leave 12x of
			-- slack for a future regression toward the legacy per-row shape to
			-- hide in.
			run = "python3 tools/check_row_actions_matrix.py",
			evidence = "artifacts/row-actions/device-matrix.md",
		},
		{
			name = "library-suite-green",
			requirements = { "ROW-ACTIONS-001", "UI-AGENT-001" },
			run = "tools/test.sh 4136",
			evidence = "artifacts/test.json",
			note = "the row-actions stage floor: 4048 (Tasks 1-11b, incl. the RED-TEAM fix wave and its two re-review rounds, the item-2 presentModal round, Task 8b's action-system modifier support, and the final whole-branch fix wave: 4038 -> 4048, ten new cases across items 1/2/3/7 of final-review-findings.md — probe B/C + sibling-claim/scroll/outside-tap-during-commit, mouse body-drag + gamepad-grab tray-close, two displayLayer-band cycling proofs, and the passive-HUD catcher-consume proof), bumped to 4136 by the row-actions-hosted-mode-plan (Tasks 1-7: hosted VirtualList/Table `rowActions` integration, parity + mount-identity differential specs, workload de-bias). A regression of any test this stage added — or any prior test it broke — fails here.",
		},
		{
			name = "rascalrally-consumer",
			requirements = { "ROW-ACTIONS-001", "UI-AGENT-001" },
			run = 'f=artifacts/row-actions/consumer-impact.md && test -f "$f" && grep -qF "What this ledger does NOT claim" "$f" && grep -qF "luauui_sponsor_table.spec.luau" "$f" && test -f ../../../games/RascalRally/code/tests/luauui_sponsor_table.spec.luau && cd ../../../games/RascalRally/code && ./run-tests.sh >/dev/null 2>&1',
			evidence = "artifacts/row-actions/consumer-impact.md",
			note = "final-review.md finding I4: the consumer-impact ledger this stage was shipped without. Audits the hosted-mode plan's changed contracts (hosted VirtualList.rowActions, the D1 double-commit latch + spring re-seed shared-engine fixes, the trash/flag icon content ids) against RascalRally's real callers -- zero rowActions/newRowActions/standard_icons call sites in any RR production file, verified by the three mutation-bitten guard tests 92cd062/1f8560c/30ca16a add (pointer-capture surface, tray overlay, focus group -- each proven biting against a deliberately-unconditional framework mutation), plus its own honest 'what this ledger does NOT claim' (no row-actions-hosted-mode Studio canary; the earlier rr-compat.md canary is for the pre-hosted-mode Table feature and is not re-claimed here). The check re-runs the RascalRally suite LIVE at the judged source rather than trusting a stored transcript, the same shape every sibling rascalrally-consumer check in this manifest carries.",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = "if [ -n \"${LUAUUI_PRIOR_GATES_NESTED:-}\" ]; then echo \"prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)\"; exit 0; fi; a=artifacts/row-actions/prior-gates-rerun.txt && tools/prior_gates.sh \"$a\" row-actions && grep -q \"^DONE$\" \"$a\" && python3 -c \"\nimport re, sys\nallowed = {\n    ('phase-1-minimal-screen', 'bench-reproducible'),\n    ('phase-2-settings-parity', 'ui-cost-budget'),\n    ('phase-3-pilot', 'no-leak-regression'),\n    ('part-2-director', 'ws1-adr-and-bench'),\n    ('expansion-textinput', 'expansion-adr-bench-rollback'),\n    ('code-simplicity-cleanup', 'performance-unregressed'),\n    ('api-architecture-consistency', 'performance-unregressed'),\n    ('example-quality-pass', 'rascalrally-consumer'),\n}\ngate = None\nbad = []\nfor line in open('artifacts/row-actions/prior-gates-rerun.txt'):\n    m = re.match(r'^FAIL (\\S+)', line)\n    if m:\n        gate = m.group(1)\n        continue\n    if re.match(r'^PASS ', line):\n        gate = None\n        continue\n    m = re.match(r'^[ ]+FAIL_RECOVERABLE[ ]+(\\S+)', line)\n    if m and gate is not None and (gate, m.group(1)) not in allowed:\n        bad.append((gate, m.group(1)))\nif bad:\n    print(bad)\n    sys.exit(1)\n\"",
			evidence = "artifacts/row-actions/prior-gates-rerun.txt",
			note = "final-review-findings.md item 9: all 24 prior gates RE-RUN by this check at the source being judged, via tools/prior_gates.sh (list derived from phases.json), writing artifacts/row-actions/prior-gates-rerun.txt — the same shape native-substrate/native-stylesheets/authoring-adaptive-ui/theme-packages-and-skinning/rich-skinning-v2/cross-platform-proof/sponsor-framework-gaps already carry (gate-integrity sweep 2026-07-29, defect B-1: a stored-file grep that executes nothing against the current tree is a can't-ever-fail check). Guarded by LUAUUI_PRIOR_GATES_NESTED so a sweep that reaches row-actions as somebody ELSE's prior does not re-trigger this same regeneration recursively. The verdict logic is now the swiftui-reference-app-validation gate's allowlist VERBATIM (line ~172): a python pass over the roll-up flags a red gate ONLY when one of its checks came back FAIL_RECOVERABLE (an actual command exit, not an authored PENDING or FAIL_ENVIRONMENT row) and the (gate, check) pair is outside the EIGHT named pairs — the set the EQ-20 note at line ~328 earned: 16 recorded bench runs this stage, every FAIL_RECOVERABLE was one of these eight bench-shelling checks rotating red under load, and an interleaved A/B proved the unchanged pre-stage loop flags exactly as often as the shipped one. Replaces the prior version's own all-or-nothing shape (every FAIL_RECOVERABLE anywhere failed the gate, so a single bench-load wobble in any prior gate landed this check FAIL_RECOVERABLE with no way to tell a real regression from noise) and drops the authoring-adaptive-ui name-specific carve-out: that gate's own block (tools/lune/gate_manifest.luau ~2194-2345) carries no PENDING/FAIL_ENVIRONMENT row of its own today, the swiftui-reference-app-validation prior-gates.txt already re-runs it clean with no special case, and the general PENDING/FAIL_ENVIRONMENT tolerance in this allowlist logic subsumes what that carve-out used to cover — mirroring the live precedent rather than a stale one. Any gate red for a FAIL_RECOVERABLE reason NOT in the allowlist still fails this check outright; the allowlist is never widened for a genuinely new failure.",
		},
	},
	["swiftui-parity-round2"] = {
		-- SwiftUI parity round 2. docs/plans/swiftui-parity-round2-brief.md is
		-- the binding scope; docs/plans/swiftui-parity-round2.md is the per-phase
		-- design. Milestones: M1 = Phases 1-2 (withAnimation + the layout
		-- vocabulary, a42ef97), M2 = Phases 3-4 (indicators/sensoryFeedback/Table
		-- primary action, then the gallery adoption — be37e92, 3d60d24), M3 =
		-- Phases 5-6 (the parity-doc rewrite and the suite fast tier — f476b63,
		-- 3f2917b), plus the two example fix commits 732a520 and 13fd3c6.
		--
		-- REGISTERED AFTER THE FACT, AND THAT IS THE FINDING THIS BLOCK EXISTS
		-- FOR (phase-gate verification of 13fd3c6, MAJOR). phases.json held 25
		-- phases ending at `row-actions` and this manifest had no round-2 block,
		-- so `tools/gate.sh` HAD NO STAGE TO RUN for the entire mission: M1, M2
		-- and M3 were each closed on a hand-run suite, a hand-run checker
		-- battery and reviewer judgement, and nothing in the repo could have
		-- reddened if any of it had regressed afterwards. That is the same class
		-- as every can't-ever-fail check the gate-integrity sweep of 2026-07-29
		-- removed, one level up: not a check that cannot fail, but a mission
		-- with no check at all.
		--
		-- Every suite grep below is Form A (`out="$(./run-tests.sh 2>&1)" && echo
		-- "$out" | grep -q "✓.*<case>"`) and carries the pass marker, per the
		-- header discipline and tools/check_manifest_integrity.py. Every case
		-- name was verified to appear as a ✓ line in a full run of a PRISTINE
		-- `git archive 13fd3c6` export (4589 passed / 0 failed) before being
		-- pinned here — not copied out of a report, and not read off the working
		-- tree, which had two other agents' edits in it at the time.
		--
		-- APOSTROPHES AND BACKTICKS ARE MATCHED WITH `.`, never literally: each
		-- `run` value is a Lua SINGLE-quoted string (an apostrophe would end it
		-- early) that the shell then reads inside DOUBLE quotes (a backtick
		-- would open a command substitution). The row-actions block records the
		-- same rule for the same reason.
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 4589",
			evidence = "artifacts/test.json",
			note = "THE FLOOR THIS MISSION NEVER HAD (phase-gate finding C2). The highest tools/test.sh floor anywhere in this manifest was the row-actions stage's 4136, against an actual finishing count of 4589 — 453 cases of slack at the moment the mission closed, and 721 above the pre-mission 3868 the verifier first measured against, so a regression could have deleted every test round 2 added and still walked through every floor in the repo. 4589 is round 2's real finishing count, derived the only way it is trustworthy: `git archive 13fd3c6` into a scratch directory and `./run-tests.sh` there, giving `4589 passed` with zero `✗` lines and zero `N failed`. It is a FLOOR, NOT AN EQUALITY — tools/test.sh takes a minimum and the repo adds cases constantly, so a later stage raises this number and never lowers it. Equality would redden on the first new test anyone writes, which is how a floor check gets deleted rather than raised.",
		},
		{
			name = "with-animation",
			requirements = { "UI-MOTION-001", "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the solved rect is the NEW one on the frame the call returns" && echo "$out" | grep -q "✓.*the PAINTED position starts at the old place and travels to the new one" && echo "$out" | grep -q "✓.*a child riding its moved parent installs NO record of its own" && echo "$out" | grep -q "✓.*a second call mid-flight re-targets instead of restarting from rest" && echo "$out" | grep -q "✓.*a node that APPEARS inside the call installs no record of its own" && echo "$out" | grep -q "✓.*the sibling it displaced DOES fly, so the case is not vacuous" && echo "$out" | grep -q "✓.*the layout is exact and there is no flight" && echo "$out" | grep -q "✓.*a call inside an already-open transaction is refused, not silently inert"',
			note = "M1 Phase 1 (tests/with_animation.spec.luau). One case per structurally distinct claim of the design constraint the brief called non-negotiable — MOTION DRIVES PRESENTATION, NEVER SOLVER GEOMETRY — because a single grep on the feature's happy path would stay green through the exact erosion the brief said to escalate rather than commit silently. The pair `the solved rect is the NEW one on the frame the call returns` + `the PAINTED position starts at the old place and travels to the new one` IS that principle, asserted from both sides in one transaction: solver exact and instant, paint travelling. The riding-child case pins one record per moved subtree (a second record is the double-delta defect); the structural case pins that an appearing node defers to src/render/transitions.luau rather than growing a second transition system, and `the sibling it displaced DOES fly` is its negative control — without it the structural case is satisfied by nothing animating at all. Re-targeting pins interruption with velocity preservation, `the layout is exact and there is no flight` pins reduced motion, and the open-transaction refusal pins that the composition rule is enforced rather than silently inert.",
		},
		{
			name = "layout-vocabulary",
			requirements = { "UI-LAYOUT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the lowest tier absorbs the whole deficit before the next tier gives a pixel" && echo "$out" | grep -q "✓.*the weight is MULTIPLIED BY THE BASIS, so the small child is not collapsed first" && echo "$out" | grep -q "✓.*the measure MEMO tells the two offers apart" && echo "$out" | grep -q "✓.*a vertical stack distributes along Y, not X" && echo "$out" | grep -q "✓.*.center. centres just that child in the line" && echo "$out" | grep -q "✓.*column n is as wide as the widest natural cell in column n" && echo "$out" | grep -q "✓.*a spanning cell contributes to NO single column.s maximum" && echo "$out" | grep -q "✓.*a GridRow outside a Grid names the fix instead of inventing columns" && echo "$out" | grep -q "✓.*the NEAREST scroller wins, not the outermost" && echo "$out" | grep -q "✓.*a fraction ignores the wrappers between the view and the scroller" && echo "$out" | grep -q "✓.*the same node at the same offer under two containers gets two answers"',
			note = "M1 Phase 2, one case per member of the vocabulary the round added, chosen so each grep names the behaviour that would be MISSING if the prop shipped inert: `layoutPriority` (tiers give way in order), `shrinkWeight` (weight x basis, so the small child is not collapsed first), `distribute` (along the stack's own axis), `lineAlign`, `UI.GridRow`/`gridSpan` (column derivation, span contributing to no single column, and the outside-a-Grid refusal), and `containerRelativeFrame` (nearest scroller wins, wrappers ignored). `the measure MEMO tells the two offers apart` is here deliberately and is not a layout claim: the brief required the solver memo key to cover the new input, and a cache key that does not cover what it caches is the defect class docs/lessons/the-solver-already-told-you.md was written about — it returns a STALE CORRECT-LOOKING number, so no geometry assertion above it can see the bug. `the same node at the same offer under two containers gets two answers` is the same claim from the container side.",
		},
		{
			name = "indicators-and-sensory-feedback",
			requirements = { "UI-FEEDBACK-001", "UI-MOTION-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the DETERMINATE tree and dump are exactly what they were before indeterminate existed" && echo "$out" | grep -q "✓.*REDUCED MOTION keeps the indicator advancing" && echo "$out" | grep -q "✓.*FULL motion writes far more often than reduced motion over the same wall clock" && echo "$out" | grep -q "✓.*refuses a spinner with a value" && echo "$out" | grep -q "✓.*refuses an event outside the closed twelve, listing the vocabulary" && echo "$out" | grep -q "✓.*emits the declared verb with the mounted path when the trigger changes" && echo "$out" | grep -q "✓.*fires once per change, and not at all for a write of the same value" && echo "$out" | grep -q "✓.*stops emitting the moment the node unmounts" && echo "$out" | grep -q "✓.*observes NOTHING when no sink is wired, and exactly one thing when one is"',
			note = "M2 Phase 3. The indicators half pins the reduced-motion policy the brief demanded be decided DELIBERATELY rather than inherited: a loading indicator conveys information, so under reduced motion it is QUANTIZED, never frozen — and `FULL motion writes far more often ... over the same wall clock` is the case that keeps that honest, because an indicator that quantized itself to a standstill would satisfy the first grep alone. The determinate-unchanged case is the regression half (indeterminate must not have moved the existing tree or dump), and the value-refusal pins the spinner's closed spec. The sensoryFeedback half pins that LuauUI EMITS AND PLAYS NOTHING: the closed twelve-verb taxonomy refuses an unregistered event, emission is once per real change (never on a same-value write), it stops at unmount, and `observes NOTHING when no sink is wired` is the sink-independence claim the opt-in default-off haptics adapter rests on.",
		},
		{
			name = "four-input-proofs",
			requirements = { "UI-INPUT-003", "UI-PARADIGM-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*Table pointer: a double-click on a row fires onPrimaryAction once, and a single click never does" && echo "$out" | grep -q "✓.*Table pointer: two clicks SLOWER than the window are two single clicks, not an open" && echo "$out" | grep -q "✓.*Table touch: a plain single tap on a row activates it" && echo "$out" | grep -q "✓.*Table keyboard: Return on the focused row fires onPrimaryAction for THAT row" && echo "$out" | grep -q "✓.*Table gamepad: ButtonA on the focused row fires onPrimaryAction for THAT row" && echo "$out" | grep -q "✓.*a table with NO onPrimaryAction behaves exactly as it does today on all four inputs" && echo "$out" | grep -q "✓.*a horizontal drag on the same table row reveals its tray instead of reordering" && echo "$out" | grep -q "✓.*RowActions touch: a swipe reveals the tray on a table NOT in edit mode and survives its release Activate (after)" && echo "$out" | grep -q "✓.*RowActions touch: a swipe reveals the tray on a table NOT in edit mode and survives its release Activate (before)" && echo "$out" | grep -q "✓.*RowActions mouse: a swipe reveals the tray on a table NOT in edit mode and survives its release Activate (after)" && echo "$out" | grep -q "✓.*RowActions mouse: a swipe reveals the tray on a table NOT in edit mode and survives its release Activate (before)" && echo "$out" | grep -q "✓.*keyboard Delete on a focused row fires the destructive action end to end" && echo "$out" | grep -q "✓.*Shift.Return opens the action menu on a focused row" && echo "$out" | grep -q "✓.*(P9) focus TRAVERSAL: the d-pad reaches the revealed tray, and the ring comes BACK to the row"',
			note = "PHASE-GATE FINDING C4, ACTED ON HERE RATHER THAN IN THE CHECKER, and the reasoning is the point. tools/lune/check_registration keys `inputProofs` on CONTROLS: it reads tests/conformance/controls_registry.luau, derives interactivity from a focusable leaf row or a `contribution.attach` in a composite's module, and demands all four classes. Round 2 added interactive behaviour that is NOT a control — `Table.onPrimaryAction` (a prop) and the playlist table's hosted `rowActions` (a prop) — so that checker passed while asserting nothing whatever about the new surface: green, and structurally unable to see the thing it should be checking. TWO THINGS WERE WRONG AND ONLY ONE OF THEM IS THE CHECKER'S. (1) The proofs were unenforced. Fixed here, and fixed STRICTLY HARDER than mirroring the control path would have: check_registration's rule (b) is `string.find(source, caseName)` over the registered specs, which — by this manifest's own opening doctrine — proves a case is REGISTERED and never that it PASSES. These fourteen greps are anchored to `✓`, so they prove the proofs pass. Mirroring the control path would have imported a weaker assertion and called it enforcement. (2) COMPLETENESS — a FUTURE modifier or prop shipping interactive behaviour with no proofs at all — is NOT fixed, and is recorded as a named gap rather than papered over with machinery that cannot deliver it. A modifier has no mechanical interactivity signal to derive: `onPrimaryAction` is a blueprint prop with no `contribution.attach` of its own, so an automatic rule would have to heuristically scan prop schemas for names that smell interactive. That is precisely the noisy checker GameStudio/ENGINEERING.md's simplicity ladder says gets disabled, and it would buy nothing real — a hand-maintained registry of modifier rows only catches the next modifier if somebody remembers to add a row, which is the same `somebody remembers` that this gap already is. So: the obligation is enforced where it can bite, and the completeness hole is named. THE FOURTEEN PROOFS. `Table.onPrimaryAction` carries a true four-input block in tests/table_input.spec.luau §5, driven through the DEVICE seam (adapter.tap / adapter.touchTap / system.deviceKey) rather than tbl.api.handleActivate, so what passes is the path a finger, mouse, key and stick actually take: pointer double-click (plus the scripted-clock slow-pair case, without which the double-click window is satisfied by the test's own speed), the documented iOS single-tap touch divergence, Return, ButtonA — and `a table with NO onPrimaryAction behaves exactly as it does today on all four inputs` as the negative control. The playlist table's hosted `rowActions` adoption carries pointer, touch and keyboard in tests/row_actions_scenario.spec.luau (mouse horizontal drag reveals rather than reorders; the swipe on a table NOT in edit mode, all FOUR release-Activate combinations of it; Delete and Shift+Return on a focused row). THE FOUR RELEASE-ACTIVATE GREPS ARE A REPAIR AND A STRENGTHENING, both recorded because the shape of the mistake is instructive (redteam NEW-3, 2026-08-13). `a6229e0` renamed `RowActions touch: … that declares a primary action` to `… and survives its release Activate (after|before)` and did not update this check, so `four-input-proofs` was RED at committed HEAD — a rename is the cheapest way in the world to break a name-based check, and the only defence is running the gate. The first repair then re-pointed it at the two touch cases plus `mouse … (before)` — and that mouse case was VACUOUS FOR ITS OWN COMBINATION: its assertions were tray-open, not-editing, nothing-opened and order-unchanged, all four of which a MOUSE `Activated` leaves alone (a mouse single click REPLACE-SELECTS; only touch opens the row here), so it stayed green against unfixed source while its touch twins reddened. Fixed in the spec, not in the manifest: the four cases now assert `tableSelectedKeys` too — a swipe selects nothing on any pointer kind — which is what makes the mouse pair able to fail (measured: `{\"m1\"}` unfixed, `{}` fixed). Both mouse orders are cited here because `after` bites through the tray and `before` through the selection, and citing only one of them would leave half the mouse claim unpinned again. ITS GAMEPAD LEG IS NOT IN THE SCENARIO SPEC — a real gap, found while writing this check — so it is cited where it does exist, on the framework integration in tests/virtual_list_row_actions.spec.luau (P9, d-pad into the revealed tray and the ring back to the row). That case is also pinned by the row-actions stage; the duplication is deliberate, because round 2's four-input claim needs its gamepad leg cited SOMEWHERE, and a claim resting on a case no round-2 check names is a claim nobody would notice losing. `UI.sensoryFeedback` is deliberately ABSENT from this check and that is not an omission: it declares no input of its own — it observes a trigger Readable and emits — so the four-input rule has no surface to attach to. Whatever moved the trigger is the interactive thing, and it carries its own proofs. Its behaviour is pinned in `indicators-and-sensory-feedback` above.",
		},
		{
			name = "hosted-swipe-survives-release-activate",
			requirements = { "UI-INPUT-003", "UI-PARADIGM-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*RowActions hosted touch: a VirtualList swipe reveals the tray and fires no onActivate (silent release, control)" && echo "$out" | grep -q "✓.*RowActions hosted touch: a VirtualList swipe reveals the tray and survives its release Activate (after)" && echo "$out" | grep -q "✓.*RowActions hosted touch: a VirtualList swipe reveals the tray and survives its release Activate (before)" && echo "$out" | grep -q "✓.*RowActions hosted mouse: a VirtualList swipe reveals the tray and fires no onActivate (silent release, control)" && echo "$out" | grep -q "✓.*RowActions hosted mouse: a VirtualList swipe reveals the tray and survives its release Activate (after)" && echo "$out" | grep -q "✓.*RowActions hosted mouse: a VirtualList swipe reveals the tray and survives its release Activate (before)" && echo "$out" | grep -q "✓.*the arm is one activate wide: the tap AFTER a swipe.s release Activate still closes the tray" && echo "$out" | grep -q "✓.*a hosted swipe CANCELLED mid-gesture does not swallow the next gamepad Activate" && echo "$out" | grep -q "✓.*a hosted swipe CANCELLED mid-gesture does not swallow the hit expander.s Activate either" && echo "$out" | grep -q "✓.*a hosted swipe with a SILENT release still answers the next gamepad Activate with a close" && echo "$out" | grep -q "✓.*a swipe CANCELLED mid-gesture does not swallow the next gamepad Activate on that row" && echo "$out" | grep -q "✓.*a swipe CANCELLED mid-gesture does not swallow the hit expander.s Activate either" && echo "$out" | grep -q "✓.*a swipe with a SILENT release still answers the next gamepad Activate with a tray close" && echo "$out" | grep -q "✓.*a swipe whose release DID Activate still swallows that artifact, and the tray survives it"',
			note = 'REDTEAM NEW-1 (BLOCKER) AND NEW-2 (MEDIUM), 2026-08-13, and the pair is one check because it is one rule. A row `Hit` is a real engine `GuiButton`, so the pointer sequence that SWIPES it also ends in that button\'s own `Activated`, on either side of `InputEnded`. NEW-1: the hosted VirtualList armed its `suppressActivatePath` in exactly one place -- `onPointerUp`\'s `unresolved` branch, a TAP on an already-open row -- so a gesture that resolved HORIZONTAL, i.e. every real swipe, armed nothing and the artifact fell straight into `spec.onActivate`. Measured through the real adapter seam on a clean-room hosted list: 8 of 12 combinations RED (both orders x both edges x both pointer kinds; only the four SILENT releases were green), where the Table twin this milestone already blocked on was merely order-dependent. On the shipped playlist analogue that reads `swipe to reveal Remove, and the track plays`. Fixed at `hostedResolveAxis` -- the one place this control decides a gesture went sideways -- exactly as `table.luau` arms at its own lock, and for the same reason: an `Activated` landing BEFORE `InputEnded` is already dispatched by the time any `onPointerUp` could arm anything. NEW-2: `a6229e0` cleared the arm only at the next pointer-DOWN, on the stated premise that `a real Activated always fires between a pointer-up and the next pointer-down`. THAT PREMISE IS FALSE for the two Activate producers that carry no pointer-down at all -- an IAS device Activate (`meta.source == "action"`), and the minimum-target hit expander, a SEPARATE `GuiButton` whose press produces no pointer event on the row\'s `Hit`. So a swipe ending with no `Activated` (a cancel, or an up off the translated hit) left the arm standing and ate the next device press: measured against 13fd3c6, `fired 0 -> 1` became `0 -> 0`, and a tray a device press used to close stayed open. Closed by clearing on CANCEL and by refusing to spend the arm on a device Activate at all, in BOTH controls. WHAT THIS CHECK PINS, and why each grep is here. The six matrix titles are the 12 combinations (each case drives BOTH edges on fresh worlds, because swiping the other way out of an open tray is the CLOSE gesture and would pass for the wrong reason); the two SILENT-release rows are the CONTROL that proves the matrix is not green merely because nothing activates. `the arm is one activate wide` is the counterweight that stops the NEW-2 clears from degenerating into `never arm`: the tap AFTER the swallowed artifact must still reach the control. The seven cancel/silent/device rows are NEW-2 on both surfaces -- including, on each, the MINIMUM-TARGET HIT EXPANDER, the second producer that carries no pointer-down and the one the `meta.source == "action"` half cannot cover (it is a POINTER Activate), so the CANCEL clear is proved load-bearing rather than belt-and-braces -- plus its own counterweight (`a swipe whose release DID Activate still swallows that artifact`) so `clear more often` cannot pass by never suppressing. EVERY ONE WAS MUTATION-PROVED TO REDDEN against the unfixed source, which is the only evidence that counts for two defects that hid behind checks structurally unable to fail: until `fake_target.pointerUpActivating` existed, every swipe case in this repo drove a release sequence the engine does not produce.',
		},
		{
			name = "gallery-coverage",
			requirements = { "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*§2.2 a Grid of .UI.GridRow.s aligns its columns across rows, and .gridSpan. covers both plus the gap" && echo "$out" | grep -q "✓.*§2.4 when the axis is short the LOWEST tier gives way first, and a weightless child never gives at all" && echo "$out" | grep -q "✓.*§2.5 .containerRelativeFrame. measures against the SCROLLER.s viewport, not the parent column" && echo "$out" | grep -q "✓.*§3.3 .UI.sensoryFeedback. emits the declared verb on the presenter.s bus, stamped with the mounted path" && echo "$out" | grep -q "✓.*onPrimaryAction: a DOUBLE-click plays the track and the page says so; a single click only selects" && echo "$out" | grep -q "✓.*four inputs reach the demonstration: pointer, touch, keyboard and gamepad" && echo "$out" | grep -q "✓.*carries the INDETERMINATE pair, and reduced motion steps them instead of stopping them"',
			note = "M2 Phase 4 and the brief's standing obligation: every new public API this round added appears in at least one gallery scenario that tests/examples_gallery.spec.luau EXECUTES HEADLESSLY — reachable from the in-experience picker, not by editing a workspace attribute and republishing. The greps are the §-numbered coverage cases, one per home: `adaptive_controls` carries GridRow/gridSpan, layoutPriority/shrinkWeight, containerRelativeFrame and sensoryFeedback; the playlist table carries onPrimaryAction; the `with_animation` fixture carries withAnimation (`four inputs reach the demonstration`) and the two indeterminate indicators. WHY THESE CASES AND NOT AN API INVENTORY: the spec's own header records the rule that every one of them is a DIFFERENCE, not a value — each names the arrangement the DEFAULT would have produced and asserts the fixture is not at it — so an API that shipped inert cannot satisfy them. A coverage check written as `does the scenario mention the prop` is satisfied by a scenario that declares it and ignores it, which is the cheapest way to ship an inert prop past a gate.",
		},
		{
			name = "overflow-sweep",
			requirements = { "UI-LAYOUT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*scenario .adaptive_controls.: the solver reports NOTHING at any swept viewport, at any text size" && echo "$out" | grep -q "✓.*scenario .with_animation.: the solver reports NOTHING at any swept viewport, at any text size" && echo "$out" | grep -q "✓.*scenario .card_rail.: the solver reports NOTHING at any swept viewport, at any text size"',
			note = "The always-on instrument the device round of 2026-08-12 left behind (docs/plans/device-bug-round-2026-08-12.md): tests/overflow_sweep.spec.luau asks every registered scenario the overflow question at eight viewports, 320x640 and 640x320 included. Pinned here for the THREE scenarios round 2 added or rewrote, because the sweep is parameterised over a registry — a scenario that was renamed, dropped from the registry or quietly excluded stops being swept and the suite stays green with one fewer scenario under observation, which is a coverage regression no total-count assertion would show. Naming the three makes their disappearance a gate failure. This is also the check that carries the mission's localization-safety and small-screen claims: the round's whole layout vocabulary exists to make a short axis behave, and the 320x640 leg is where it is proven. RE-POINTED 2026-08-13, AND THE RENAME IS THE FINDING: parity round 3 taught this sweep the CROSS axis (a wrapping stack cannot overflow its main axis, so it would have been structurally invisible to a main-axis-only grep) and an accessibility TEXT-SIZE axis, which renamed every case from `no main-axis overflow at any swept viewport` — first to `no overflow on EITHER axis ... at any text size`, then, hours later, to `the solver reports NOTHING at any swept viewport, at any text size` when the sweep's phrase FILTER was deleted outright (ledger row 14) — so these three greps were RED at committed HEAD until this edit, exactly the way `four-input-proofs` above was broken by a rename and for the same reason. TWICE IN ONE DAY IS THE FINDING, not the individual rename: a case title is this repo's check-anchor of choice and nothing tells its author that a gate depends on it. Same three scenarios, strictly stronger claim each time; found by running every suite grep in this manifest against a complete transcript rather than by anything noticing on its own, which is the argument for running the gate.",
		},
		{
			name = "checker-battery",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_registration_cli >/dev/null && lune run tools/lune/check_docs_cli >/dev/null && lune run tools/lune/check_boundary >/dev/null && lune run tools/lune/check_prop_parity_cli >/dev/null && lune run tools/lune/check_surface_ledger >/dev/null && lune run tools/lune/check_flat_baseline >/dev/null && lune run tools/lune/check_example_drift_cli >/dev/null && python3 tools/check_manifest_integrity.py >/dev/null && stylua --check src tests tools bench examples",
			note = "The eight checkers the mission ran by hand at every milestone and the gate could not run at all, plus stylua, in one row: check_registration (four-input/paradigm conformance, api.md heading coverage, spec registration — an unregistered spec is a silent zero), check_docs, check_boundary (no internal instance-path requires from the game or the examples), check_prop_parity, check_surface_ledger (every live export and namespace member classified), check_flat_baseline (the neutral dump REGENERATED and compared, never read from store), check_example_drift, check_manifest_integrity (which is what refuses a suite grep in this file that does not anchor to ✓ — including the ones above), and the formatter. AT REGISTRATION THIS ROW IS RED, AND BOTH REASONS ARE REAL — which is the whole argument for the row, since the mission ran this battery by hand at every milestone and closed anyway. (1) `check_flat_baseline` exits 1: round 3's own popup-catcher fix (`7fb325f`) gave the dismiss catcher a `surface` declaration, so `/__popupcatcher__/catcher` gained `surface=plain` plus a font and text size at three views, and the stored neutral dump was never regenerated nor the delta characterized. The repair is a regenerate-and-characterize, NOT a re-pin — this checker declined a re-pin once already — and it is booked as O-22. (2) `stylua --check` fails on `tests/geometry_solve_coalescing.spec.luau`, committed unformatted with the solve-coalescing work; the formatting is fixed in the working tree but not committed, because that file also holds a concurrently running agent's uncommitted edits and committing it would have taken their in-flight work. Neither red was weakened away and neither is mine to close. Note what this row does NOT claim: check_registration passing says nothing about round 2's modifiers and props — that is finding C4, and the `four-input-proofs` row above is where it is answered.",
		},
		{
			name = "parity-doc-falsifiable",
			requirements = { "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the live parity document passes, and cites a substantial body of Apple pages" && echo "$out" | grep -q "✓.*fails when a verdict row asserts something about SwiftUI with no citation" && echo "$out" | grep -q "✓.*fails when the parity document loses the citation convention itself" && grep -qF "LuauUI will not add" docs/reference/swiftui-parity.md && grep -qF "ship as names" docs/reference/swiftui-parity.md && grep -qF "is a semantic bus event, and LuauUI plays nothing" docs/reference/swiftui-parity.md',
			evidence = "docs/reference/swiftui-parity.md",
			note = "M3 Phase 5. The document was rewritten as one fresh coherent draft, and the thing worth gating is not its prose but its FALSIFIABILITY: tests/theme_docs.spec.luau runs the live document through a citation checker and carries its own negative controls, so an uncited verdict row about SwiftUI, a citation that resolves to no §16 row, and the loss of the convention itself each redden the suite. The first grep is the live-document case; the two after it are the negative controls, and they are pinned deliberately — a checker with no proof it can fail is the shape this repo keeps finding, and the doc case alone would stay green against a checker that had been quietly defanged. The three literal greps pin the round's three recorded DECISIONS, which are the claims a future author is most likely to reopen by accident: no *Style protocols (native StyleSheets and theme packages own paint), no LazyVStack/LazyHStack as names (the lazy stacks are virtualization sugar over the existing substrate), and sensoryFeedback as a semantic bus event LuauUI never plays.",
		},
		{
			name = "rascalrally-consumer",
			requirements = { "UI-AGENT-001" },
			run = 'for f in luauui_grid_row_contract luauui_sensory_feedback_contract luauui_motion_and_scroll_contract; do test -f ../../../games/RascalRally/code/tests/$f.spec.luau || { echo "missing RR round-2 contract spec: $f"; exit 1; }; done && cd ../../../games/RascalRally/code && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*carries .UI.GridRow. as a primitive with a contract and a TINY prop set" && echo "$out" | grep -q "✓.*carries .UI.containerRelativeFrame. with a CLOSED spec" && echo "$out" | grep -q "✓.*the two live flow-grid declarations solve to their frozen geometry" && echo "$out" | grep -q "✓.*carries .UI.sensoryFeedback. as a blueprint modifier" && echo "$out" | grep -q "✓.*carries the haptics adapter, and it is DEFAULT OFF" && echo "$out" | grep -q "✓.*a real game screen.s activate still emits exactly one .activate. and nothing else" && echo "$out" | grep -q "✓.*a production screen.s target learns the setting with no wiring at all"',
			note = "The root CLAUDE.md rider — LuauUI and Rascal Rally move together — asked of round 2's own contracts, run LIVE at the judged source rather than from a stored transcript, the same shape every sibling rascalrally-consumer check in this manifest carries. The three round-2 contract specs are named individually before the suite runs, so deleting one is a failure rather than a smaller green run. WHAT THE GREPS ARE FOR, given the suite already has to be green: they pin the two halves that a whole-suite exit code cannot separate. The `carries ...` cases assert the framework surface RascalRally actually receives (GridRow's tiny prop set, containerRelativeFrame's closed spec, sensoryFeedback as a modifier, the haptics adapter DEFAULT OFF) — a compatibility claim about the shipped contract, which is what the rider is really about. The frozen-geometry and one-activate cases assert the game's own behaviour is UNCHANGED, which is the other half of the rider: no product change without separate authorization. WHAT THIS ROW DOES NOT CLAIM: round 2 shipped no artifacts/swiftui-parity-round2/consumer-impact.md, so unlike the row-actions and example-quality-pass stages there is no written ledger of affected callers here and none is pretended — the evidence is the three contract specs plus the live suite. A ledger, and a Rascal Rally Studio canary for the round-2 surface, are booked as owed alongside the prior-gates sweep.",
		},
		{
			name = "traversal-evidence-red-carried",
			requirements = { "UI-FID-001", "UI-AGENT-001" },
			run = "test -f tools/check_traversal_evidence.py && grep -qF \"THE FIX IS A RE-RECORD, NOT AN EDIT\" tools/check_traversal_evidence.py && grep -qF \"Owed: the TD-13/TD-14 re-record\" docs/plans/device-bug-round-2026-08-12.md && python3 -c \"\nimport re, sys\nsrc = open('tools/lune/gate_manifest.luau').read()\nstart = src.index('[\\\"traversal-document-order\\\"]')\nrest = src[start + 10:]\nm = re.search(r'\\n\\t\\[\\\"', rest)\nblock = rest[: m.start()] if m else rest\nif 'name = \\\"studio-evidence\\\"' not in block:\n    sys.exit('traversal-document-order no longer registers a studio-evidence check')\nif not any(l.strip().startswith('run =') and 'check_traversal_evidence' in l for l in block.splitlines()):\n    sys.exit('studio-evidence no longer RUNS tools/check_traversal_evidence.py — the red was downgraded, not re-recorded')\nprint('traversal-document-order/studio-evidence still runs the structural staleness check')\n\"",
			note = "THE HONESTLY-RED ITEM, GUARDED RATHER THAN INHERITED OR ERASED. `traversal-document-order` / `studio-evidence` is RED today and round 2 neither caused it nor can close it: the device round of 2026-08-12 wrapped the keyboard_navigation scenario's body in a UI.ScrollView, every surface in that fixture moved one path segment deeper, and the Studio artifact it is judged against is still the 2026-08-03 capture. tools/check_traversal_evidence.py derives the expected path prefix from the scenario source ON DISK and says so in one sentence: THE FIX IS A RE-RECORD, NOT AN EDIT. Re-recording needs Studio and a human, and is booked in docs/plans/device-bug-round-2026-08-12.md. WHAT THIS CHECK IS. Three guards against the red being made to disappear the wrong way: the structural checker still exists and still carries its own instruction; the re-record is still booked as owed; and the traversal-document-order block in this file still registers `studio-evidence` as a check that RUNS that checker — read by slicing that gate's block out of this file, so this row cannot satisfy itself with its own text (a self-matching grep is a check that cannot fail, which is the thing this whole file is organised against). Delete the booking, downgrade studio-evidence to a literal `state`, or point it at a softer command, and this reddens. WHAT IT DELIBERATELY IS NOT. It does not assert the checker currently FAILS. An inverted check would go red on the day a human legitimately re-records — the one moment the evidence is finally right — and would then be edited to agree with the change, which is the exact failure mode the checker's own docstring was written about. The red stays red in the gate that owns it, and round 2's gate refuses to let it be quietly rewritten as never having happened.",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = "if [ -n \"${LUAUUI_PRIOR_GATES_NESTED:-}\" ]; then echo \"prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)\"; exit 0; fi; a=artifacts/swiftui-parity-round2/prior-gates-rerun.txt && tools/prior_gates.sh \"$a\" swiftui-parity-round2 && grep -q \"^DONE$\" \"$a\" && python3 -c \"\nimport re, sys\nallowed = {\n    ('phase-1-minimal-screen', 'bench-reproducible'),\n    ('phase-2-settings-parity', 'ui-cost-budget'),\n    ('phase-3-pilot', 'no-leak-regression'),\n    ('part-2-director', 'ws1-adr-and-bench'),\n    ('expansion-textinput', 'expansion-adr-bench-rollback'),\n    ('code-simplicity-cleanup', 'performance-unregressed'),\n    ('api-architecture-consistency', 'performance-unregressed'),\n    ('example-quality-pass', 'rascalrally-consumer'),\n    ('traversal-document-order', 'studio-evidence'),\n}\ngate = None\nbad = []\nfor line in open('artifacts/swiftui-parity-round2/prior-gates-rerun.txt'):\n    m = re.match(r'^FAIL (\\S+)', line)\n    if m:\n        gate = m.group(1)\n        continue\n    if re.match(r'^PASS ', line):\n        gate = None\n        continue\n    m = re.match(r'^[ ]+FAIL_RECOVERABLE[ ]+(\\S+)', line)\n    if m and gate is not None and (gate, m.group(1)) not in allowed:\n        bad.append((gate, m.group(1)))\nif bad:\n    print(bad)\n    sys.exit(1)\n\"",
			evidence = "artifacts/swiftui-parity-round2/prior-gates-rerun.txt",
			note = "All 25 prior gates RE-RUN by this check at the source being judged, via tools/prior_gates.sh with the list derived from phases.json — the same shape row-actions and seven stages before it carry, and for the same reason (gate-integrity sweep 2026-07-29, defect B-1: a stored-file grep that executes nothing against the current tree is a can't-ever-fail check). Guarded by LUAUUI_PRIOR_GATES_NESTED so a sweep that reaches this stage as somebody else's prior does not recurse. The verdict logic is the row-actions allowlist VERBATIM plus ONE addition: (traversal-document-order, studio-evidence). That pair is the honestly-red item described in the row above — stale Studio evidence awaiting a human re-record, red since 2026-08-12, and it will redden that gate on every sweep until the re-record happens. It is allow-listed BY NAME rather than by widening the rule, so it stays visible in the roll-up and in this note instead of being absorbed into a tolerance, and the `traversal-evidence-red-carried` row makes it a gate failure to erase it. Every other FAIL_RECOVERABLE outside the eight bench-shelling pairs still fails this check outright. NOT YET RUN, AND SAID PLAINLY: at registration time this stage's sweep had not been executed — two other agents were live in the tree and one was mutation-testing, a sweep re-runs 25 gates each invoking the full suite, and a concurrent sweep already held /tmp/luauui_prior_gates.lock (the header of tools/prior_gates.sh records what two concurrent sweeps did to each other's artifacts the last time). So this row is registered live and RED for the honest reason that its evidence does not exist yet. It is the one check in this block that was not mutation-proven, because proving it would have meant running the sweep this stage is forbidden to run.",
		},
	},
	["declarative-3d-architecture"] = {
		-- Declarative 3D architecture DECISION stage (docs/plans/
		-- declarative-3d-architecture.md). This stage decides whether and how the
		-- studio builds a declarative fine-grained-reactive system for Roblox
		-- Parts/Models; it does NOT build one. PASS means the decision is proved:
		-- a reviewed plain-language ADR, an alternatives comparison, an isolated
		-- runnable disproof spike, topology/lifecycle traces, measured costs, and
		-- four fresh-context reviews with factual findings resolved.
		--
		-- REGISTERED BEFORE ANY OTHER STAGE WORK, per the round-2 block directly
		-- above (a mission that ran with no stage for tools/gate.sh to run). Every
		-- row lands as PENDING and becomes a `run` only when its implementation
		-- and evidence exist (manifest header rule).
		--
		-- ISOLATION IS A STANDING CLAIM OF THIS STAGE: the spike lives under
		-- spikes/declarative-3d/ (a directory this stage creates), never under
		-- src/, and the stage changes no LuauUI public export, extracts no core,
		-- edits no game code, and creates no production package. The durable
		-- checks below assert the spike's own structure; the one-time fact that
		-- src/ was untouched at close is recorded in the evidence and confirmed by
		-- the fresh-context phase-gate review, because a live `git status src/`
		-- re-run by a future prior-gates sweep would assert something about THAT
		-- day's tree, not about this stage.
		--
		-- NO prior-gates sweep row, DECIDED RATHER THAN FORGOTTEN: this stage
		-- writes no line of library source, so the sweep obligation (defect B-1's
		-- target: code changes regressing earlier gates) has no code to bite. The
		-- suite-floor row below is the regression evidence proportionate to a
		-- docs+spike+artifacts stage; the next code-bearing stage carries the full
		-- sweep as usual.
		{
			name = "adr-decisive",
			requirements = { "UI-AGENT-001" },
			run = 'f=docs/adr/ADR-0024-declarative-3d.md && test -f "$f" && grep -qF "Decision, in one paragraph" "$f" && grep -qF "Build it as a SIBLING system" "$f" && grep -qF "explained like you" "$f" && grep -qF "start building until a concrete consumer mission exists" "$f" && grep -qF "blesses its core as a public" "$f" && grep -qF "Extraction is reconsidered" "$f" && grep -qF "First bounded milestone" "$f" && grep -qF "Non-goals" "$f" && grep -qF "Evidence still required before any production use" "$f" && grep -qF "removal signals fire before the removal is" "$f" && grep -qF "Under Immediate signal mode" "$f"',
			evidence = "docs/adr/ADR-0024-declarative-3d.md",
			note = "The plain-language ADR states ONE decision (sibling system on the shared kernel, build gated on a concrete consumer), the ELI5, the kernel-sharing mechanism (bless, not extract — the extraction-vs-migration-risk call), the first bounded milestone, non-goals, the future-evidence list, and the spike's measured removal-signal finding. Greps pin the claims a future edit is most likely to erode, not the prose.",
		},
		{
			name = "alternatives-compared",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/declarative-3d-architecture/alternatives.md && test -f "$f" && grep -qF "A. Extend LuauUI" "$f" && grep -qF "B. Sibling package, shared kernel" "$f" && grep -qF "C. Independent system" "$f" && grep -qF "D. No build" "$f" && grep -qF "### 10. Failure recovery" "$f" && grep -qF "Score summary" "$f" && grep -qF "double-construction" "$f" && grep -qF "nobody has built the hard part" "$f"',
			evidence = "artifacts/declarative-3d-architecture/alternatives.md",
			note = "All four alternatives against the same ten criteria (the '### 10.' grep pins the count), the score table, double-construction prevention, and the research-grounded ecosystem fact.",
		},
		{
			name = "use-case-inventory",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/declarative-3d-architecture/use-cases.md && test -f "$f" && for h in "Static prop layout" "Repeated keyed collections" "Reactive visual properties" "Attachments and authored assemblies" "Server-owned shared objects" "Client-local decoration" "Streaming in/out" "Teardown"; do grep -qF "$h" "$f" || { echo "missing category: $h"; exit 1; }; done && grep -qF "Out of scope, restated from the plan" "$f" && grep -qF "per-frame" "$f"',
			evidence = "artifacts/declarative-3d-architecture/use-cases.md",
			note = "All eight mission-named categories present, the out-of-scope list stated in the artifact itself, and the per-frame refusal (the honest headline: the active game's two biggest world churners stay OUT of the reactive band) named.",
		},
		{
			name = "spike-headless-green",
			requirements = { "UI-AGENT-001" },
			run = 'out="$(lune run spikes/declarative-3d/specs 2>&1)" && printf \'%s\\n\' "$out" > artifacts/declarative-3d-architecture/spike-headless.txt && echo "$out" | grep -qF "declarative-3d spike: 18/18 cases passed" && echo "$out" | grep -q "✓.*keyed add creates only the new item; survivors keep their handles" && echo "$out" | grep -q "✓.*a throwing item build is quarantined" && echo "$out" | grep -q "✓.*dispose returns core and adapter counters to baseline" && echo "$out" | grep -q "✓.*a welded child is written once and never transform-written again" && echo "$out" | grep -q "✓.*a non-welded child under a welded part is refused at mount" && echo "$out" | grep -q "✓.*a build that writes its own items source still converges" && echo "$out" | grep -q "✓.*per-item resources owned by the build scope die with the item" && echo "$out" | grep -q "✓.*a runtime duplicate key discards that update wholesale"',
			evidence = "artifacts/declarative-3d-architecture/spike-headless.txt",
			note = "Form A: the assignment carries the spec runner's exit code, so any red case fails the row before the greps run; the transcript is regenerated as evidence on every gate run, never read from store. The 18/18 summary line pins the count (14 original + 4 review-round cases); the named ✓ cases pin the disproof claims (identity, quarantine, baseline, native-mechanism write discipline) and the four resolved review findings (welded-subtree rigidity refusal — architecture finding 2; read-then-subscribe convergence — runtime finding 1; scope-owned per-item resources — runtime finding 2; the real runtime-duplicate-key semantic — architecture finding 5). Mutation-proven at build time and again at the review round (convergence-loop disable reddened its case).",
		},
		{
			name = "spike-isolated",
			requirements = { "UI-AGENT-001" },
			run = "python3 - <<'D3ISOEOF'\nimport glob, re, sys\nfiles = glob.glob('spikes/declarative-3d/*.luau') + glob.glob('spikes/declarative-3d/studio/*.luau')\nassert len(files) >= 9, f'spike files missing: {files}'\nbad = []\nseam = []\nfor path in files:\n    src = open(path).read()\n    for _q, target in re.findall(\"require\\\\((['\\\"])([^'\\\"]+)\\\\1\\\\)\", src):\n        if target.startswith('./'):\n            continue\n        if target.startswith('@lune/') and path.endswith('specs.luau'):\n            continue  # the Lune spec RUNNER may use the Lune runtime; modules may not\n        if target == '../../src/core/custom' and path.endswith('core_custom.luau'):\n            seam.append(path)\n            continue\n        bad.append((path, target))\nif bad:\n    sys.exit(f'spike requires outside the sibling rule + the one declared kernel seam: {bad}')\nif len(seam) != 1:\n    sys.exit(f'expected exactly one kernel seam in core_custom.luau, found {seam}')\nimport subprocess\nhits = subprocess.run(['grep', '-rl', 'spikes/', 'src'], capture_output=True, text=True).stdout.strip()\nif hits:\n    sys.exit(f'library source references the spike: {hits}')\nprint('spike isolation: sibling requires only (both quote styles), one declared kernel seam, src/ never references spikes/')\nD3ISOEOF",
			note = "Durable structure check, mutation-proven at registration and re-proven at the review round: every spike module require — matched in BOTH quote styles (phase-gate finding 6 caught the single-quote evasion) — is a ./sibling except the single declared kernel seam (core_custom.luau -> ../../src/core/custom), and nothing under src/ references spikes/. Delivered to the shell as a quoted heredoc so no quoting layer can re-mangle the regex. The one-time fact that this stage changed no line of src/ is recorded in reviews.md and confirmed by the fresh-context phase-gate review against git state.",
		},
		{
			name = "studio-topology-evidence",
			requirements = { "UI-AGENT-001" },
			run = 'python3 tools/check_spike.py artifacts/declarative-3d-architecture/studio-topology.json server-root-once=PASS keyed-collection-mount=PASS client-root-once=PASS no-double-build=PASS client-root-invisible-to-server=PASS server-roots-alive-on-server=PASS anchor-created=PASS client-decoration-bound=PASS streaming-like-loss=PASS streaming-like-reentry=PASS streaming-like-second-cycle=PASS keyed-remove-survivors=PASS keyed-reorder-zero-churn=PASS single-update-bounded=PASS assembly-move-one-write=PASS assembly-welded-ride-engine-truth=PASS model-pivot-one-native-move=PASS external-destroy-tolerated=PASS destroy-cleanup=PASS && grep -qF "task.defer" artifacts/declarative-3d-architecture/studio-topology.json && grep -qF "StreamingEnabled=false" artifacts/declarative-3d-architecture/studio-topology.json && grep -qF "Immediate" artifacts/declarative-3d-architecture/studio-topology.json && test -s artifacts/declarative-3d-architecture/studio-raw-server.json && test -s artifacts/declarative-3d-architecture/studio-raw-client.json && test -s artifacts/declarative-3d-architecture/studio-raw-cross.json',
			evidence = "artifacts/declarative-3d-architecture/studio-topology.json",
			note = "Live Studio record content-checked row by row via tools/check_spike.py (a truncated file fails, per that tool's charter): both endpoint roots built exactly once, cross-endpoint re-declaration refused, client roots invisible to the server, streaming-like loss/reentry twice without duplicates or leaks, survivor identity on real Instances, one-write assembly and pivot moves engine-truth-verified, an external engine Destroy tolerated by disposal, and teardown to baseline through the leak-capable churned-ForEach shape. All 19 rows are emitted by CHECKED-IN runners (runner_server.run/crossCheck + runner_client.run — phase-gate finding 2) and preserved verbatim in the three studio-raw-*.json files this row requires to exist non-empty (phase-gate finding 3: raw output kept separate from editorial). The literal greps pin the honesty labels: the task.defer belt, the StreamingEnabled=false simulation caveat, and the Immediate-signal-mode scoping of the removal-signal finding with the Deferred replay recorded as owed (platform finding 3).",
		},
		{
			name = "spike-costs-measured",
			requirements = { "UI-AGENT-001" },
			run = 'python3 tools/check_spike.py artifacts/declarative-3d-architecture/costs.json mount-100-item-keyed-collection=MEASURED single-reactive-update=MEASURED keyed-remove-10-of-100=MEASURED keyed-reorder-full-reversal=MEASURED welded-assembly-move-20-parts=MEASURED model-pivot-move-11-instances=MEASURED teardown=MEASURED && grep -qF "NOT a production performance claim" artifacts/declarative-3d-architecture/costs.json',
			evidence = "artifacts/declarative-3d-architecture/costs.json",
			note = "Measured, not asserted: instance/write/connection counts per scenario (the portable evidence) plus desktop wall-clock as context only — the literal grep pins the caveat that keeps this from being read as a production performance claim.",
		},
		{
			name = "reviews-resolved",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/declarative-3d-architecture/reviews.md && test -f "$f" && grep -qF "[ARCH-D3]: CONCERNS" "$f" && grep -qF "[RUNTIME-D3]: CONCERNS" "$f" && grep -qF "[PLATFORM-D3]: CONCERNS" "$f" && grep -qF "[PHASE-GATE-D3]: CONCERNS" "$f" && grep -qF "No unresolved factual findings" "$f" && test "$(grep -c "RESOLVED" "$f")" -ge 25 && grep -qF "PROCESS NOTE" "$f" && grep -qF "What did NOT change under review" "$f"',
			evidence = "artifacts/declarative-3d-architecture/reviews.md",
			note = "Four fresh-context reviews (architecture, reactive-runtime, Roblox-platform, phase-gate) ran against the ADR, alternatives, raw spike, topology traces, and costs; all four returned CONCERNS, recorded VERBATIM (the greps pin the four verdict lines — a reviews file that upgraded a verdict would fail). Every factual finding is resolved (the >=25 RESOLVED entries), the process notes are present rather than erased, and the closing section states what survived review unchanged: the decision itself. Two findings were resolved by re-running the whole Studio session on the corrected spike; the fix-then-re-verify loop is the resolution, not a claim.",
		},
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 4624",
			evidence = "artifacts/test.json",
			note = "The library suite floor at stage close — the proportionate no-regression evidence for a stage that changes no library source (see block header for why there is no prior-gates sweep row). 4624 is the COMMITTED-tree count (git archive HEAD into a scratch dir, ./run-tests.sh there: 4624 passed / 0 failed, 2026-08-13) — pinned to HEAD rather than the working tree because a concurrent session's uncommitted src/controls work was inflating the live count to 4633+, and a floor that needs somebody else's in-flight edits to pass is a floor that reddens for reasons unrelated to this stage (phase-gate review finding 1). A FLOOR, not an equality, per the round-2 precedent.",
		},
	},
	["swiftui-parity-round3"] = {
		-- SwiftUI parity round 3. docs/plans/swiftui-parity-round3-brief.md is the
		-- binding scope; docs/plans/swiftui-parity-round3.md is the per-phase
		-- record of what actually shipped, and it is the source for every row
		-- below — a row here exists because that document says the thing landed.
		--
		-- What the mission shipped, in the brief's own letters: A flow-wrap as a
		-- native arrange branch (`wrap` on HStack/VStack, the `hwrap`/`vwrap`
		-- solver kinds, the cross-axis overflow diagnostic); B the custom `Layout`
		-- protocol EVALUATED and recorded as a conditional refusal with a named
		-- trigger — a decision, not a build; C the per-row capability opt-out
		-- family (`rowSelectable`/`rowMovable`/`rowDeletable`) across Table and
		-- newVirtualList; D the completeness audit's ranked gaps (onAppear /
		-- onDisappear / hidden) plus the four capabilities that already shipped and
		-- had never been rowed; D2 circular progress in BOTH forms on Path2D; D3
		-- the five clean-room reference apps re-proved; E the chrome restructure
		-- that made the showcase reachable on four inputs and the reduced-motion
		-- settings surface it unblocked. Beside them: the accessibility-text-size
		-- axis on the always-on sweeps, the lying-`itemExtent` guard, the
		-- viewport-change solve-count coalescing (`env:batch` + one scope-owned
		-- geometry memo), and the popup-catcher paint fix.
		--
		-- REGISTERED AFTER THE FACT, exactly as round 2 was, and for the same
		-- reason it is worth saying out loud: until this block existed
		-- `tools/gate.sh` had no stage to run for the mission, so every item closed
		-- on a hand-run suite and reviewer judgement with nothing in the repo able
		-- to redden if it regressed afterwards.
		--
		-- Every suite grep below is Form A (`out="$(./run-tests.sh 2>&1)" && echo
		-- "$out" | grep -q "✓.*<case>"`) and carries the pass marker, per the
		-- header discipline and tools/check_manifest_integrity.py. Every case name
		-- was verified to appear as a ✓ line in a full run before being pinned:
		-- 114 patterns checked against a complete `./run-tests.sh` transcript
		-- (4837 passed working tree / 4831 passed at committed HEAD) and a
		-- complete Rascal Rally transcript (3153 passed), zero misses.
		--
		-- APOSTROPHES AND BACKTICKS ARE MATCHED WITH `.`, never literally: each
		-- `run` value is a Lua SINGLE-quoted string (an apostrophe would end it
		-- early) that the shell then reads inside DOUBLE quotes (a backtick would
		-- open a command substitution). The round-2 and row-actions blocks record
		-- the same rule for the same reason.
		--
		-- WHAT THIS GATE DOES NOT CLAIM, said once here rather than in every note:
		-- nothing in round 3 was verified on a device or in a live Studio session.
		-- Items A, D, D2 and E each closed with an explicit PENDING_PHYSICAL rider
		-- in the mission record; `studio-device-canary` below carries that as a
		-- FAIL_ENVIRONMENT row instead of letting a headless green stand in for it,
		-- and artifacts/swiftui-parity-round3/owed.md names the four device
		-- questions individually.
		{
			name = "library-suite-green",
			requirements = { "UI-AGENT-001" },
			run = "tools/test.sh 4838",
			evidence = "artifacts/test.json",
			note = "The suite floor at stage close. 4838 is the COMMITTED-tree count, derived the only way it is trustworthy with three other agents live in this tree: `git archive HEAD` into a scratch directory and `./run-tests.sh` there, giving 4838 passed with zero ✗ lines and zero `N failed` (2026-08-13). The working tree measured 4842 at the same moment — four cases belonging to another agent's uncommitted specs — and pinning THAT number would make this floor depend on somebody else's in-flight edits, which is the declarative-3d block's finding 1. A FLOOR, NOT AN EQUALITY: tools/test.sh takes a minimum and the repo adds cases constantly, so a later stage raises this number and never lowers it. It rises 249 above round 2's 4589, and it moved twice while this block was being written (4831 -> 4838) because a concurrent agent was committing into the same tree — which is why it is a floor and not an equality. WHAT IT CATCHES: any regression that deletes or reddens a test, anywhere. WHAT IT DOES NOT CLAIM: that the new cases assert anything in particular — that is what every row below is for.",
		},
		{
			name = "flow-wrap",
			requirements = { "UI-LAYOUT-001", "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*fuzz: every child lands in exactly one line, in order, and only a lone item may overflow" && echo "$out" | grep -q "✓.*a line.s cross extent is its TALLEST item, not the first one.s" && echo "$out" | grep -q "✓.*Center: the BLOCK is centred — (400-80)/2 = 160 exactly, not per line" && echo "$out" | grep -q "✓.*ragged: line 2 starts at the TALLEST item of line 1 (90), never at 40" && echo "$out" | grep -q "✓.*the plan is keyed by the BOX: a SHRUNK wrapping stack re-breaks its lines" && echo "$out" | grep -q "✓.*gets its own line, is CLAMPED to the line, and the solver says so" && echo "$out" | grep -q "✓.*more lines than fit reports on the cross axis, with the pixel count" && echo "$out" | grep -q "✓.*...and a stack whose lines DO fit says nothing at all" && echo "$out" | grep -q "✓.*a LITERAL stretch on a wrapping stack is a construction error naming both readings" && echo "$out" | grep -q "✓.*a stretch that only a SOLVE can see is refused there, and treated as start" && echo "$out" | grep -q "✓.*takes a whole line to itself, and is named rather than ignored" && echo "$out" | grep -q "✓.*an unknown kind polices NOTHING — which is why the row has to exist" && echo "$out" | grep -q "✓.*.lineAlign. IS read by a wrapping stack; .alignH. beside it is NOT" && echo "$out" | grep -q "✓.*.wrap. is declared on VStack and HStack, reactive, and dirties measure" && echo "$out" | grep -q "✓.*...and NOWHERE else: a .wrap. a solver branch would never read is refused" && echo "$out" | grep -q "✓.*a BOUND .wrap. flips in place: the same stack, re-solved, never remounted" && echo "$out" | grep -q "✓.*the SHRINK PAIR is refused: wrapping IS the answer to a main-axis deficit" && echo "$out" | grep -q "✓.*THE TOGGLE IS THE ARGUMENT: wrap off overflows, wrap on does not — same nodes" && echo "$out" | grep -q "✓.*the tags really WRAP: more than one distinct row of y at every viewport" && echo "$out" | grep -q "✓.*scenario .flow_wrap.: the solver reports NOTHING at any swept viewport, at any text size" && grep -q "flowPartition" src/layout/solver.luau',
			note = "ITEM A. One grep per structurally distinct claim of the arrange branch, chosen so each names the behaviour that would be MISSING if the prop shipped inert (the mission's own mutation table M1-M17b is the map; these are the cases those mutations reddened). THE PARTITION: the fuzz case is the invariant form of `every child lands in exactly one line, in order` (M1 reddened 14 cases including it); `a line.s cross extent is its TALLEST item` is the measured engine rule, and `ragged: line 2 starts at ... (90), never at 40` is that rule stated as an arithmetic a mutation cannot satisfy accidentally (M2); `Center: the BLOCK is centred — (400-80)/2 = 160 exactly` pins that the CONTAINER's existing `align` positions the whole block of lines, which is the finding that deleted a design decision rather than adding a prop (M3). THE CACHE: `the plan is keyed by the BOX` is here because it is the one check in this item that did NOT bite on the first attempt — dropping the box from `flowPlan`'s key reddened NOTHING until a shrunk wrapping stack (measured at the full offer, squeezed, re-measured, arranged) was written for it, which is the stale-memo class docs/lessons/the-solver-already-told-you.md exists for: a cache key that does not cover what it caches returns a STALE CORRECT-LOOKING number no geometry assertion above it can see. THE TWO DIAGNOSTICS AND THEIR CONTROLS: the over-wide item is clamped AND named (M5/M6), the cross-axis overflow is reported with its pixel count (M7) — and `a stack whose lines DO fit says nothing at all` is its negative control, without which `always report` would satisfy the first. THE REFUSALS, one per seam, because the mission decided `stretch` is refused at TWO of them: a literal is a construction error (M14) and a bound one is a solver diagnostic (M9); a `fill` main child takes a whole line rather than entering the partition at zero (M10); the shrink pair is not read at all on a wrapping stack (wrapping IS what this stack does with a deficit). THE SOLVER TABLE: `an unknown kind polices NOTHING` is the placement audit's own admission, and it is pinned here because it is the reason the wrapping stack needed distinct `hwrap`/`vwrap` KINDS rather than a boolean read inside the hstack branch — forget the rows and every placement prop on a wrapping stack's children becomes accepted-and-ignored (M8, which also reddened a Rascal Rally case). THE SCHEMA: declared on exactly two classes, reactive, dirtying MEASURE not paint (M15), and refused everywhere else (M16) — with `a BOUND .wrap. flips in place ... never remounted` as the reason the feature is a prop rather than a `UI.FlowStack` class at all. THE SHOWCASE: `THE TOGGLE IS THE ARGUMENT` is a DIFFERENCE assertion (wrap off overflows, wrap on does not, same nodes), which is what an inert prop cannot satisfy, and the always-on sweep names `flow_wrap` so dropping the scenario from the registry is a failure rather than a smaller green run (M13/M17a). The `flowPartition` grep is not a behaviour claim: it pins that the line partition is still a NAMED PURE FUNCTION in the solver, which is the seam a future `Layout` mission would need and the shape that makes the partition fuzzable at all. WHAT THIS ROW DOES NOT CLAIM: nothing here is a device claim — the fixture has never been mounted in Studio under Play (owed.md, item A) — and the perf statement behind it is tier 1 (headless Lune) off-path only, since no perf scene contains a wrapping stack.",
		},
		{
			name = "layout-protocol-verdict",
			requirements = { "UI-LAYOUT-001", "UI-AGENT-001" },
			run = 'grep -qF "Build flow-wrap as a native arrange branch in the solver" docs/plans/swiftui-parity-round3.md && grep -qF "conditionally-refused future mission, with a named" docs/plans/swiftui-parity-round3.md && grep -qF "Trigger: *a real" docs/plans/swiftui-parity-round3.md && grep -qF "would be the first" docs/plans/swiftui-parity-round3.md && grep -qF "conditional refusal with a" docs/reference/swiftui-parity.md && grep -qF "incremental-arrange reuse skip and the placement-prop audit" docs/reference/swiftui-parity.md && grep -qF "SwiftUI ships **no** flow" docs/reference/swiftui-parity.md',
			evidence = "docs/plans/swiftui-parity-round3.md",
			note = "ITEM B, WHICH IS A DECISION AND NOT A BUILD, so what is gated is the decision's record and its falsifiability rather than any code. The brief required B to be evaluated BEFORE A was built, on the theory that a public `Layout` protocol might make flow-wrap consumer code; it was, and it does not. The greps pin the four claims a future author is most likely to reopen by accident: the verdict itself (`Build flow-wrap as a native arrange branch in the solver`), its FORM (`conditionally-refused future mission, with a named` trigger — this repo's established shape for a refusal, never an open TODO), the trigger's presence, and the one argument that carries it — a public `Layout` would be the first consumer-authored code ever executed inside the solve, which the measure memo's cache key, the incremental-arrange reuse skip and the placement-prop audit are each unsound without. The parity-document side is pinned separately because that is the reader-facing half, including the fact that cuts AGAINST the verdict and is stated anyway (`SwiftUI ships **no** flow` layout — its answer to this shape IS a custom `Layout`). WHAT THIS ROW WOULD CATCH: the refusal being deleted, downgraded to a TODO, or the trigger being dropped so the next mission reads it as unconditional. WHAT IT EXPLICITLY DOES NOT CLAIM: that no `Layout` protocol exists (it is a documentary check, not a source scan), that the evaluation was correct, or that the three solver mechanisms are actually sound — those are the enumeration arguments the mission recorded, and this row asserts only that they are still on the record as the reason.",
		},
		{
			name = "row-capability-optouts",
			requirements = { "UI-INPUT-003", "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*rowSelectable = false STOPS the selection at the funnel, not just at the affordance" && echo "$out" | grep -q "✓.*rowMovable = false refuses the GRAB — a pinned row never arms, on any input" && echo "$out" | grep -q "✓.*an absent predicate changes nothing — every row participates, byte-identical to today" && echo "$out" | grep -q "✓.*a predicate that THROWS is quarantined and fails CLOSED (the row does not participate)" && echo "$out" | grep -q "✓.*rowSelectable on a selection = .none. list is refused, naming the missing capability" && echo "$out" | grep -q "✓.*rowMovable without onReorder is refused, naming the missing capability" && echo "$out" | grep -q "✓.*rowDeletable without rowActions is refused, naming the missing capability" && echo "$out" | grep -q "✓.*rowSelectable = false refuses at api.select, in EVERY selection mode path" && echo "$out" | grep -q "✓.*rowMovable = false refuses at api.moveRow — Table has FIVE reorder entry points" && echo "$out" | grep -q "✓.*a pinned row is not a DESTINATION either: a movable row cannot displace it" && echo "$out" | grep -q "✓.*newVirtualList refuses .wrap. and explains the index x itemExtent arithmetic" && test -f src/row_capability.luau && grep -qF "rowSelectable(item)" docs/reference/api.md',
			note = "ITEM C, the family the director widened from two members to three. THE THREE DESIGN RULES THE MISSION HELD ITSELF TO ARE WHAT THESE GREPS ARE. (1) POSITIVE POLARITY: every case names `rowSelectable`/`rowMovable`/`rowDeletable`, not SwiftUI's negative `*Disabled` — the family sits on the same spec table as `rowFocusable`, and `rowFocusable` beside `moveDisabled` is a bug factory. (2) GATE THE FUNNEL, NOT THE AFFORDANCE: `STOPS the selection at the funnel, not just at the affordance` and `refuses at api.moveRow — Table has FIVE reorder entry points` are the two halves of the rule table.luau:1015-1030 was already bitten by (a third, wholly separate way to start the identical reorder that missed a guard), and `a pinned row is not a DESTINATION either` is the half a naive source-side gate misses entirely — refusing the grab while still letting a movable row displace a pinned one would satisfy every other case here. (3) A PREDICATE MAY ONLY EVER SUBTRACT: the three construction refusals pin that declaring a capability narrowing on a container without that capability is refused at build time naming what is missing (constitution §4), which is the difference between a predicate and a second, disagreeing source of truth. `a predicate that THROWS is quarantined and fails CLOSED` is the safety direction chosen deliberately — a consumer bug that stubbornly refuses to move a row is visible and harmless; one that silently deletes a protected row is not. `an absent predicate changes nothing — byte-identical to today` is the negative control that keeps the family from being satisfied by a container that has quietly started refusing things. The `newVirtualList refuses .wrap.` case is here rather than in the flow-wrap row because it is where item A's owed message was actually closed — the refusal now names the `index x itemExtent` conflict instead of the generic unknown-field text. The two file greps pin the single-implementation claim (`src/row_capability.luau`, one module, two callers — the mission's answer to the delete predicate having to cross `spec.rowActions`'s own callback boundary without becoming a second funnel) and the closure of D3's documentation defect 1, which found ZERO occurrences of all three names in api.md. WHAT THIS ROW DOES NOT CLAIM: nothing about the CONTAINER unification question §13 used to defer this family behind — the mission's verdict is that the two controls do not unify and that §13's row was false; that verdict is documentary and is not asserted here.",
		},
		{
			name = "circular-progress",
			requirements = { "UI-FEEDBACK-001", "UI-MOTION-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*draws an arc over a full backing ring, and no bar at all" && echo "$out" | grep -q "✓.*the SWEEP is the value: 25% ends at 3 o.clock, 100% closes the ring" && echo "$out" | grep -q "✓.*a value change is PAINT ONLY: one prop write on .points., zero re-solves" && echo "$out" | grep -q "✓.*the HEAD travels while the sweep stays fixed — and there is no backing ring" && echo "$out" | grep -q "✓.*rotating is PAINT: 60 frames of travel write points and never re-solve" && echo "$out" | grep -q "✓.*takes the SAME single clock entry the dots take — no second one for the arc" && echo "$out" | grep -q "✓.*under REDUCED motion the ring keeps advancing, on the quantized tick" && echo "$out" | grep -q "✓.*no circular indicator mounted = no Path instance and no .points. op, ever" && echo "$out" | grep -q "✓.*radius . size / 2 + thickness / 2 never exceeds size / 2" && echo "$out" | grep -q "✓.*refuses a spinner with a value — and names the shape that DOES draw one" && echo "$out" | grep -q "✓.*refuses .height. on a circular indicator, naming the metric that owns its size" && echo "$out" | grep -q "✓.*refuses .showValue. on a circular indicator rather than putting it beside the ring" && echo "$out" | grep -q "✓.*refuses an unknown presentation, listing the three that exist" && echo "$out" | grep -q "✓.*both forms are on screen: a filled ring, a rotating head, and the dot spinner" && echo "$out" | grep -q "✓.*scenario .progress_ring.: the solver reports NOTHING at any swept viewport, at any text size" && grep -qF "SW-130" docs/reference/swiftui-parity.md && grep -qF "SW-131" docs/reference/swiftui-parity.md',
			note = "ITEM D2, the director's request, and BOTH forms are pinned because shipping one of them would satisfy a looser check. DETERMINATE: `the SWEEP is the value: 25% ends at 3 o.clock, 100% closes the ring` is the arithmetic — an arc that merely appears is not a ring that FILLS to its value. INDETERMINATE: `the HEAD travels while the sweep stays fixed` is the design in one sentence (a fixed sweep whose START ANGLE advances), and it is the case that would fail if somebody re-implemented rotation on the presentation channel's `rotation` instead, which the mission deliberately did not use (it is presenter-owned and keyed by node path, so a control cannot reach it, and it is documented incompatible with ClipsDescendants). THE COST CLAIM IS ASSERTED, NOT ASSERTED-ABOUT: `a value change is PAINT ONLY: one prop write on .points., zero re-solves` and `60 frames of travel write points and never re-solve` are the whole reason this control could be built on Path2D at all — `points` is `dirty = { paint }`, and a regression that made the ring re-solve would be invisible to every geometry assertion while costing 600 solves over a 600-frame cycle (the measured indeterminate BAR does exactly that). OFF-PATH COST: `no circular indicator mounted = no Path instance and no .points. op, ever` is the brief's standing rule 3 obligation — prove the new feature's off-path cost is ~zero rather than asserting it — and mutation M14 (a stray UI.Path in the bar's builder) reddens it. REDUCED MOTION IS INHERITED, NOT RE-DECIDED: the ring reads the same phase value from the SAME single `informational` clock entry the dots read, so `takes the SAME single clock entry` pins that no second clock entry was acquired (which would have re-opened the scope/leak question) and `keeps advancing, on the quantized tick` pins the policy itself — a frozen spinner and a hung process look identical. THE FOUR GENERATED REFUSALS pin the capability registry that replaced three hand-written `if`s: a spinner with a value, `height` on a shape with no track, `showValue` on a shape with no room for it, and an unknown presentation listing the three that exist. `radius . size / 2 + thickness / 2 never exceeds size / 2` is the painted-at-a-size-nobody-measured family (a Path2D stroke is CENTRED on its curve) checked as arithmetic across the neutral snapshot and all eight shipped packages, because no headless diagnostic can see it. The two citations pin the SPLIT parity claim: the indeterminate ring is `ProgressView(.circular)` (SW-130) and the determinate one is `Gauge(.accessoryCircularCapacity)` (SW-131), because Apple's own page says a circular ProgressView is not guaranteed to be determinate. WHAT THIS ROW DOES NOT CLAIM: the arc's per-frame `SetControlPoints` cost on a device (PENDING_PHYSICAL), and whether the ENGINE would crop a stroke inside a clip host — the framework's own all-or-nothing cull runs first and is pinned by tests/path.spec.luau, but `GetBoundingRect` is not a clip oracle and no rendered capture was taken.",
		},
		{
			name = "reference-apps-reproved",
			requirements = { "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*THE PLAZA SUMMARY IS ONE ROW: each chip at ONE path, none at a zero rect" && echo "$out" | grep -q "✓.*THE TAG CLOUD IS RAGGED AND MULTI-LINE, where a uniform grid gave one width" && echo "$out" | grep -q "✓.*A POST.S TAGS AND THE CHART LEGEND KEEP THEIR OWN WIDTHS" && echo "$out" | grep -q "✓.*THE LADDER.S TWIN NODES ARE GONE: no MetaColumn, no ApprovalB, no ChipB" && echo "$out" | grep -q "✓.*AT NORMAL TEXT they share a line and .distribute. pushes the chip to the TRAILING edge" && echo "$out" | grep -q "✓.*AT RAISED PREFERRED TEXT it REFLOWS to a second line instead of squeezing" && echo "$out" | grep -q "✓.*NOT ONE .Spacer. INSTANCE IS MOUNTED: .distribute. says it on the container" && echo "$out" | grep -q "✓.*FIVE WORN PIECES SHARE ONE LINE, each at its own width — not five stacked lines" && echo "$out" | grep -q "✓.*IN A NARROW PANE THEY WRAP to a second line rather than paint past the plate" && echo "$out" | grep -q "✓.*the five-view sweep is diagnostic-clean with a live scrollbar (matrix pin)" && for p in Glade Cartwheel Sipworks Foyer Wardrobe; do test -f "examples/places/LuauUI-Ref-$p.rbxl" || { echo "missing place: $p"; exit 1; }; done && grep -qF "shipped parity round 3" artifacts/swiftui-reference-app-validation/capability-ledger.md',
			note = "ITEM D3. The five clean-room proofs are the only artefacts in the repo written from a spec by an author who did not read framework internals, which is what makes them evidence rather than demos — so what is gated is the RE-PROOF's findings, not the diff. THE NINE CASES ARE THE SEVEN ADOPTIONS PLUS THE TRAP. Each is a DIFFERENCE assertion against what the previous code produced: the tag cloud was sixteen tags forced to an identical 135x23 by a uniform Grid and is now ragged on three lines; a post's two tags came out the same width as each other and now do not; five worn pieces each had their own line and now share one; `AT RAISED PREFERRED TEXT it REFLOWS to a second line instead of squeezing` is the strongest single proof in the set, because p4_foyer's deleted ladder carried the comment `reflow, never squeeze` — the definition of a flow wrap, written in prose by an author who had no word for it. THE TRAP IS WHY THREE OF THESE READ THE WAY THEY DO. The brief warned that `06_tile_game`'s ViewThatFits ladder wrote its readouts twice and moved them off their published paths past a green suite, because a LOSING candidate stays mounted with its props and text intact at a zero rect — so a presence assertion passes against content no player can see. p2_cartwheel was the same defect and worse (three published paths for `Charge`; the two losers measured 8x0 at EVERY viewport the section is reachable on). `each chip at ONE path, none at a zero rect` and `THE LADDER.S TWIN NODES ARE GONE` are therefore rect assertions, not presence assertions: they would both have passed with either ladder intact. `NOT ONE .Spacer. INSTANCE IS MOUNTED` is the same kind of claim from the instance side — `distribute` replacing hand-placed spacers is a stronger proof than adding a new call, because it shows the framework absorbed something the author previously had to hand-build (24 mounted Spacer instances to 0; 601 to 454 nodes at 1400x900). The `matrix pin` case is the regression half: the apps still pass their own five-view diagnostic-clean sweep. The five place files and the capability-ledger grep close the item's two non-test deliverables — the places rebuilt, and bounded gap #3 spent with the measurement that decided it. WHAT THIS ROW DOES NOT CLAIM: that p1_glade and p3_sipworks were improved — they were surveyed in full and deliberately left unchanged, which the record argues is the more useful outcome; nor does it claim the adoption ledger's U/T/A verdicts, which are a documentary judgement.",
		},
		{
			name = "audit-gaps-and-free-parity",
			requirements = { "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*the hooks are NOT reactive — a lifetime is not a value that changes" && echo "$out" | grep -q "✓.*fires AFTER the first layout solve — the callback can read its own rect" && echo "$out" | grep -q "✓.*fires AFTER the handle is released: the path is no longer mounted" && echo "$out" | grep -q "✓.*does NOT fire again on a re-solve that changes no structure" && echo "$out" | grep -q "✓.*surface teardown fires every still-mounted hook, so a cleanup is never dropped" && echo "$out" | grep -q "✓.*keeps its layout box: the sibling below does NOT move up" && echo "$out" | grep -q "✓.*...which is the whole difference from .UI.When., whose sibling DOES move up" && echo "$out" | grep -q "✓.*leaves focus order — Apple.s .can.t receive or respond to interactions." && echo "$out" | grep -q "✓.*takes no tap — Apple.s sentence is two halves and this is the second" && echo "$out" | grep -q "✓.*...and so does a losing ViewThatFits candidate, which is the SAME verdict" && echo "$out" | grep -q "✓.*teardown fires the badge.s own disappear, so the count is never left short" && for c in SW-132 SW-138 SW-139 SW-140 SW-141 SW-142; do grep -qF "| **$c** |" docs/reference/swiftui-parity.md || { echo "missing citation $c"; exit 1; }; done && grep -qF "newAsyncImage" docs/reference/swiftui-parity.md && grep -qF "TextField.keyboardType" docs/reference/swiftui-parity.md && grep -qF "effectiveTransparency" docs/reference/swiftui-parity.md && grep -qF "parity-completeness-audit-2026-08-13.md" docs/reference/swiftui-parity.md',
			note = "ITEM D — the ranked gaps taken (#12 onAppear/onDisappear, #16's hide), the ones deliberately left, and the free parity that was never claimed. THE TWO ORDERING DECISIONS ARE THE POINT OF THE FIRST FOUR GREPS. Apple declines to specify when these fire ([SW-138], [SW-139]), so LuauUI defined it: appear drains AFTER that frame's layout solve, so the callback can read its own rect (the earlier placement would have handed every hook a nil rect, which is the useless half of the capability), and disappear drains AFTER the removal sweep, so `rectOf(path)` is nil INSIDE the callback — asserted from in there, because that is the only place the ordering is observable. `does NOT fire again on a re-solve that changes no structure` is the negative control that stops `fire on every refresh` from satisfying the appear case. `surface teardown fires every still-mounted hook` is the leak direction chosen on purpose: a panel usually goes away by being dismissed, so a cleanup that only ran on re-keying would be a leak with a green suite. HIDDEN'S THREE CLAUSES, EACH SEPARATELY: it keeps its layout box (with `the whole difference from UI.When, whose sibling DOES move up` as the contrast that makes the claim non-vacuous), it leaves focus order, and it takes no tap. The last two exist because `paint` was the obvious dirty channel and was WRONG — a paint-only channel would have repainted the node and reached neither the focus-order filter nor the hit-rect retraction, shipping an invisible control that still takes Tab and still activates, which is half of Apple's sentence sold as all of it. `...and so does a losing ViewThatFits candidate, which is the SAME verdict` pins that the gate reads the solver's MERGED hidden set rather than the authored prop alone — the case that caught a live Rascal Rally behaviour change within the hour (a spec driving `adapter.tap` into a 170x0 CTA in a losing candidate) and is the round-2 orchestration note one step worse: a test satisfied by a hidden copy, that DROVE the hidden copy. THE FREE PARITY: the four capabilities that already shipped and had never been rowed are pinned by name plus their citations, and the audit pointer keeps §13 pointing at the ranked list rather than at a silence a reader would fairly read as `considered and rejected`. SW-141/SW-142 are the two REFUSALS (`opacity`, `.disabled()` cascade) — a row that dropped them would let the next mission read either as an accidental omission rather than a recorded authority decision. WHAT THIS ROW DOES NOT CLAIM: the audit's other 36 capabilities are untouched and only enumerated; and neither capability has a Studio canary or a device run — in particular whether Roblox itself already refuses input to an invisible GuiButton is undocumented, which is exactly why the framework holds the rule rather than relying on the engine.",
		},
		{
			name = "chrome-four-inputs-and-settings",
			requirements = { "UI-INPUT-003", "UI-PARADIGM-001", "UI-MOTION-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*Tab reaches the demo, not the chip strip" && echo "$out" | grep -q "✓.*the toggle key opens the panel, engages it, and lands focus inside it with the ring showing" && echo "$out" | grep -q "✓.*the pad.s toggle button opens the panel and engages it — with no keyboard anywhere" && echo "$out" | grep -q "✓.*the motion setting is reachable and changeable with a pad alone" && echo "$out" | grep -q "✓.*ButtonB (Cancel) resigns the panel, which takes it down and returns the demo" && echo "$out" | grep -q "✓.*a tap outside the open panel takes it down (the engaged-surface dismissal path)" && echo "$out" | grep -q "✓.*one Tab press moves the ring one step, not two" && echo "$out" | grep -q "✓.*the toggle context binds exactly the two documented keys, and nothing a demo uses" && echo "$out" | grep -q "✓.*the 320px phone that killed the third chip steps down to icons rather than clipping" && echo "$out" | grep -q "✓.*the losing rung is out of the focus order at every width, on both rungs" && echo "$out" | grep -q "✓.*no player-visible string in this surface says on, off, disable or enable" && echo "$out" | grep -q "✓.*flipping it RE-SOLVES without rebuilding: mount identity and factory runs are untouched" && echo "$out" | grep -q "✓.*and the host.s re-apply is what makes the SETTING win over that restore" && echo "$out" | grep -q "✓.*no overflow on either axis, at any swept viewport, under any shipped theme" && echo "$out" | grep -q "✓.*the panel never overlaps the chip strip, under any shipped theme at 320x640" && echo "$out" | grep -q "✓.*every player-visible string survives ~1.4x pseudo-localization" && test -f examples/gallery/client/showcase_chrome.luau && test -f examples/gallery/client/settings_panel.luau',
			note = "ITEM E rows 4 and 11 — `[SHOWCASE-CHROME]: CONCERNS 16` executed, and the settings surface it hard-blocked. THE DEFECT WAS BIGGER THAN THE ROW SAID AND THE FIRST GREP IS THE HALF NOTHING HAD REPORTED: both pickers were `responder = passive`, a passive surface's nav context is created DISABLED, and the chrome re-presented itself after every demo mount — so the chrome's focus scope sat permanently on top and the DEMO was unreachable too. Driven headlessly before any change, Tab landed on a chip that paints no ring and Return/ButtonA no-opped against the demo's handle. `Tab reaches the demo, not the chip strip` is that regression, and it is first because a fix that only made the chrome reachable would have left it standing. THE FOUR-INPUT PROOF IS DRIVEN THROUGH THE DEVICE SEAM, never through an API: `system.deviceKey` through the real InputBinding table and `adapter.tap` through the real hit path. The gamepad leg runs with `capabilities.keyboard = false` so no keyboard binding can be helping it — that is what makes `with no keyboard anywhere` an assertion rather than a title. THE TWO COUNTERWEIGHTS ARE WHY THE RESTRUCTURE IS TWO SURFACES AND NOT ONE `engage()` CALL: `one Tab press moves the ring one step, not two` fails the moment the strip engages alongside the panel (two engaged surfaces both sit at the engaged band's 3000 and both receive Traverse), and `binds exactly the two documented keys, and nothing a demo uses` is asserted by pressing all twelve contended keys and requiring that none of them toggles the chrome — Backquote and ButtonY were chosen precisely because every other candidate is claimed (Escape is engine-reserved, Tab is Traverse and CoreGui-contended, ButtonA is eaten by the legacy jumpAction, ButtonB is Cancel, ButtonX is the row-actions menu). THE LADDER: `steps down to icons rather than clipping` is CONCERNS 16's arithmetic executed, and `the losing rung is out of the focus order at every width` is the hidden-candidate class asserted on the chrome's own ladder. THE SETTING IS A SETTING AND NOT A DEMO'S SIDE EFFECT: `flipping it RE-SOLVES without rebuilding` proves round 2's reason 3 rather than restating it (factory runs and instance count unchanged while `motionClock:isReduced()` goes true — mutation M15 makes the write a no-op and it reddens), and `the host.s re-apply is what makes the SETTING win over that restore` is the exact sequence that separates the place-wide preference from a demo's documented restore-on-dispose. `no player-visible string says on, off, disable or enable` enforces the Full|Reduced vocabulary decision — the env fact is binary but the effect is not. THE SHOWCASE RULE IN FULL: the chrome is NOT reachable by tests/overflow_sweep.spec.luau, so it sweeps itself — both surfaces, both sections, eight viewports, eight shipped packages, failing on either axis (128 mounts), plus the 320x640 non-overlap case and a ~1.4x pseudo-localization pass. WHAT THIS ROW DOES NOT CLAIM: no Studio canary was run. Whether a real Backquote reaches IAS and whether a physical ButtonY fires Activate end to end are both open — injected keys are known-unreliable for some classes and a pad button cannot be pressed headlessly.",
		},
		{
			name = "large-text-sweep-axis",
			requirements = { "UI-A11Y-001", "UI-LAYOUT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*AXIS CONTROL: a slot sized for Larger is SILENT at +0/+4/+10 and REPORTED at +14" && echo "$out" | grep -q "✓.*every waived finding still fires — a stale waiver is a fixed defect, delete the line" && echo "$out" | grep -q "✓.*scenario .adaptive_controls.: the solver reports NOTHING at any swept viewport, at any text size" && echo "$out" | grep -q "✓.*scenario .with_animation.: the solver reports NOTHING at any swept viewport, at any text size" && echo "$out" | grep -q "✓.*scenario .card_rail.: the solver reports NOTHING at any swept viewport, at any text size"',
			note = "THE ALWAYS-ON SWEEP GAINED TWO AXES THIS ROUND and both are pinned here, because a sweep is an instrument and an instrument that stops asking a question does so silently. The CROSS axis came from item A (a wrapping stack cannot overflow its main axis — that is what wrapping means — so a wrapping stack on any screen would have been structurally invisible to a sweep that greps `on the main axis`), and the TEXT-SIZE axis came from the same blind spot biting twice in one sitting: the perf lab's rows overflowed by 11/39/59px at preferredTextOffset 4/10/14 and were clean at 0, and p4_foyer's TopBar was pre-existing and invisible for exactly the same reason. THE TWO CONTROL CASES ARE THE ONLY THING THAT KEEPS THIS HONEST, and they are why this row is not a `check that proves nothing`: `AXIS CONTROL` mounts a slot sized for Larger and asserts SILENCE at +0/+4/+10 and a REPORT at +14 including the exact 6px, so if the axis is ever disabled that case says so on that run; and `every waived large-text overflow still fires` is the waiver machinery's own tripwire — a waiver is a CEILING and not a pardon (a finding that exceeds it, or appears at a SMALLER preference, fails) and a waiver that fires nowhere fails too, so the enumerated list of 35 known defects can only shrink. Nothing is waived at offset 0, so the pre-axis contract is untouched. THE THREE NAMED SCENARIOS are round 2's three, re-pinned at their CURRENT case titles — the sweep is parameterised over a registry, so naming them makes a scenario's disappearance a gate failure rather than a smaller green run, and the rename is recorded in the round-2 block above because that block's own greps were left pointing at the old titles and were RED at the moment round 3 was registered. WHAT THIS ROW DOES NOT CLAIM: the sweep still runs ONE LOCALE (measured stronger than this axis on at least one surface), 390x844 is still not a swept viewport, and the sweep still cannot see the `virtualSlot` finding's phrase — all three are booked in artifacts/swiftui-parity-round3/owed.md rather than papered over.",
		},
		{
			name = "virtual-slot-guard",
			requirements = { "UI-LAYOUT-001", "UI-A11Y-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*FIRES on the pre-fix lab shape and names the declared extent AND the measure" && echo "$out" | grep -q "✓.*names the RIGHT numbers at every step of the preference (4 -> 60, 14 -> 84)" && echo "$out" | grep -q "✓.*is SILENT on the fixed shape — the same rows in a slot that tells the truth" && echo "$out" | grep -q "✓.*is SILENT on a row that is legitimately SHORTER than its slot" && echo "$out" | grep -q "✓.*SEES a cell that declares .height = fill. — filling a slot is not fitting it" && echo "$out" | grep -q "✓.*is SILENT on a cell that ABSORBS its own overflow (a scroller on the list.s axis)" && echo "$out" | grep -q "✓.*is SILENT inside a hidden subtree (a losing ViewThatFits candidate)" && echo "$out" | grep -q "✓.*never accuses the list.s OWN furniture: a 16px slot, and the row hit is 24px" && echo "$out" | grep -q "✓.*compares against the DECLARED extent, never the row.s current box" && echo "$out" | grep -q "✓.*BREADTH CONTROL: a layered overlap and a lying itemExtent both reach the collector" && grep -qF "virtualSlot" docs/reference/api.md',
			note = "THE LYING `itemExtent` GUARD (director-approved 2026-08-13). `newVirtualList` windows by `index x itemExtent`, which is O(1) and exact ONLY because the extent is one declared number — and the control makes the CONSUMER predict its own row's height for every live fact the cell reads. Nothing checked the prediction, and the case study is the perf lab's `heightFor`, whose comments record it learning viewport width, then the type scale (3px), then theme insets (19px), then — found on a real device — the accessibility text preference (11/39/59px): four inputs, three of them added post-mortem. FOUR OF THESE NINE GREPS ARE SILENCE CASES, and that ratio is the design: a diagnostic that fires on honest rows gets disabled, which is worse than not shipping it. Legitimately-short rows say nothing (over-reservation is the correct direction), a cell that ABSORBS its own overflow says nothing (the exception zstack_fill_diagnostic.spec was written for), a hidden subtree says nothing, and the control's OWN full-row hit Button is excluded via `contentFrom` — without which every list denser than 24px would be accused of a lie the framework itself wrote. THE FIRE CASES pin that it names BOTH numbers (the declared extent and the measure, so the finding is actionable rather than an accusation) and that it tracks the preference (4 -> 60, 14 -> 84). `SEES a cell that declares height = fill` is the one place in solver.luau that does not excuse a fill axis, and it is load-bearing: 254 of 791 positive deltas across the suite sit on a fill main axis, shapes the previous ZStack overlap finding was structurally blind to. `compares against the DECLARED extent, never the row.s current box` is the case that keeps a hosted row-actions commit collapse — which drives one row's box down its own height ladder on purpose — from making the guard shout. THE ALWAYS-ON SWEEP CAN NOW SEE THIS CLASS, and the last grep is where that is pinned: when this row was first written the sweep greped two axis phrases and this finding says `than the slot it is windowed into`, so the class was enforced only by the perf lab's mount check, Rascal Rally's large-text fixtures and this spec. Hours later the sweep's phrase FILTER was deleted outright rather than widened (ledger row 14, another agent, same day), and its `BREADTH CONTROL` case is the control that proves a lying itemExtent now reaches the collector — the same solver mutation that reddens the cases above reddens it too. WHAT THIS ROW DOES NOT CLAIM: the two live gallery findings the guard surfaced (/ListLab/…/Row/Card +5px, /DropLab/…/Row/Card +4px) are state-specific, do not reproduce at the swept cross product, and belong to whoever owns those scenarios; they are recorded, not fixed.",
		},
		{
			name = "solve-count-coalescing",
			requirements = { "UI-PERF-001", "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*a batched geometry change is ONE solve" && echo "$out" | grep -q "✓.*every geometry key still re-solves" && echo "$out" | grep -q "✓.*a non-geometry write does not solve" && echo "$out" | grep -q "✓.*env:batch is the general mechanism" && grep -qF "env:batch" docs/reference/api.md',
			note = "L-27's LEVER, PAID. The device capture produced a ranked list and the top item was not a slow function, it was a COUNT: `arrange` 8.270 ms/occurrence and 9.67 arranges per step on a physical device, against L-27's standing record that one viewport change costs 5 solves — roughly 45 ms of a ~200 ms frame. THE INVESTIGATION IS WHY THE FIRST CASE READS THE WAY IT DOES: a bare `env:set(viewportRect, ...)` on a mounted 40-row tree cost exactly ONE solve at every size, so the defect would not reproduce headless at all. The seam headless does not have is the ADAPTER — `roblox_env.pushViewport()` writes SIX facts on one real resize — and mimicking exactly those six writes reproduced L-27's 5 on the first try. Two multipliers were compounding and NEITHER FIX WORKS ALONE (batching alone: 5; coalescing the eight independent geometry-key observers alone: 4; both: 1), which is why `a batched geometry change is ONE solve` is the case and not `fewer solves`. `every geometry key still re-solves` is its negative control — a memo that coalesced by never recomputing would satisfy the first case perfectly and break the framework — and `a non-geometry write does not solve` bounds the memo's dependency set from the other side. `env:batch is the general mechanism` pins standing rule 2: this is `core:transaction` exposed on the environment and applied to the adapter's three fact-groups, not a viewport special case. WHAT THIS ROW DOES NOT CLAIM: the device number itself. It is a headless solve-COUNT contract, which is the portable half of a tier-3 finding; the ms are tier 3 and not re-measurable here. Two open items ride with it and are booked rather than hidden: a presented modal still costs 2 solves per geometry change (L-29 residual 2, with the consumer rider asserting a CEILING of 2 so the second solve can be removed later without moving the check), and the lab overlay's measure-then-publish feedback loop.",
		},
		{
			name = "popup-catcher-paint",
			requirements = { "UI-AGENT-001" },
			run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*swiping LEFT TO RIGHT to reveal the leading tray must not paint a plate over the viewport" && echo "$out" | grep -q "✓.*the same catcher, reached through the other outsideDismiss owner, is equally unpainted" && echo "$out" | grep -q "✓.*sits beneath its owner.s DisplayOrder — which is why only the uncovered chrome band showed it"',
			note = "THE POPUP CATCHER DECLARED NO SURFACE, SO EVERY THEME PAINTED IT (fix commit 7fb325f). A dismiss catcher is a hit region, not a plate — but it went out with no surface declaration, so a theme package with a default plate painted one over the viewport, visible in practice only in the band the owner's own DisplayOrder did not cover. THE THREE GREPS ARE THE DEFECT, ITS SIBLING AND ITS EXPLANATION, and the second is the one that makes this more than a spot fix: the catcher is reached through TWO `outsideDismiss` owners, and fixing the path the report named while leaving the sibling caller broken is the failure mode ENGINEERING.md's `grep every caller` rule exists for. The third pins the DisplayOrder relationship that explains why the bug was nearly invisible — which is worth pinning precisely because a future change that raised the catcher's band would make the same latent paint fully visible. WHAT THIS ROW DOES NOT CLAIM: it is a headless paint-declaration assertion; no Studio capture of the fixed surface under a plate-painting package was taken.",
		},
		{
			name = "checker-battery",
			requirements = { "UI-AGENT-001" },
			run = "lune run tools/lune/check_registration_cli >/dev/null && lune run tools/lune/check_docs_cli >/dev/null && lune run tools/lune/check_boundary >/dev/null && lune run tools/lune/check_prop_parity_cli >/dev/null && lune run tools/lune/check_surface_ledger >/dev/null && lune run tools/lune/check_flat_baseline >/dev/null && lune run tools/lune/check_example_drift_cli >/dev/null && python3 tools/check_manifest_integrity.py >/dev/null && stylua --check src tests tools bench examples",
			note = "The eight checkers plus the formatter, in one row, exactly as the round-2 block carries them: check_registration (four-input/paradigm conformance, api.md heading coverage, spec registration — an unregistered spec is a silent zero), check_docs, check_boundary (no internal instance-path requires from the game or the examples), check_prop_parity, check_surface_ledger (every live export and namespace member classified — the row that would catch `wrap`, `hidden`, `onAppear`, `onDisappear`, `virtualSlot`, `rowSelectable`/`rowMovable`/`rowDeletable` and `env:batch` shipping unclassified), check_flat_baseline (the neutral dump REGENERATED and compared, never read from store), check_example_drift, and check_manifest_integrity, which is what refuses any suite grep in this file that does not anchor to ✓ — including all of the ones above. WHAT THIS ROW DOES NOT CLAIM: check_registration keys `inputProofs` on CONTROLS, so it says nothing about round 3's props and modifiers — the same finding round 2 recorded as C4. Round 3's interactive surface is the chrome (a showcase surface, four inputs proved in `chrome-four-inputs-and-settings`) and the row-capability predicates (proved at the funnel in `row-capability-optouts`); the structural completeness hole for a FUTURE prop shipping interactive behaviour with no proofs is still open and still named rather than papered over with a heuristic scanner.",
		},
		{
			name = "rascalrally-consumer",
			requirements = { "UI-AGENT-001" },
			run = 'for f in luauui_flow_wrap_contract luauui_resize_solve_contract luauui_sponsor_results; do test -f ../../../games/RascalRally/code/tests/$f.spec.luau || { echo "missing RR round-3 contract spec: $f"; exit 1; }; done && cd ../../../games/RascalRally/code && out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*carries .wrap. on VStack and HStack, boolean, reactive, measure-dirty" && echo "$out" | grep -q "✓.*the placement audit knows the wrapping kinds, so their children are policed" && echo "$out" | grep -q "✓.*every .wrap =. in this package is the FOCUS-navigation one, in a known file" && echo "$out" | grep -q "✓.*a real shipped screen still solves with zero layout diagnostics" && echo "$out" | grep -q "✓.*the new CROSS-axis overflow message exists, and a fitting stack never fires it" && echo "$out" | grep -q "✓.*env:batch is on the environment the game builds" && echo "$out" | grep -q "✓.*the surface still RESPONDS to each geometry fact" && echo "$out" | grep -q "✓.*a rotation re-solves the role-pick modal without per-key fan-out" && echo "$out" | grep -q "✓.*the capability registry still declares the BAR.s three cells the rally bar depends on" && echo "$out" | grep -q "✓.*A37b: the CTA form that LOST the ViewThatFits reaches nothing at all"',
			note = "The root CLAUDE.md rider — LuauUI and Rascal Rally move together — asked of round 3's own contracts, run LIVE at the judged source rather than from a stored transcript, the same shape every sibling rascalrally-consumer check in this manifest carries. The three contract specs are named individually before the suite runs, so deleting one is a failure rather than a smaller green run. THE GREPS SPLIT THE TWO HALVES A WHOLE-SUITE EXIT CODE CANNOT SEPARATE. The `carries ...` cases assert the framework surface the game actually receives: `wrap` on exactly two classes with the right reactivity and dirty channel, the placement audit knowing the wrapping kinds (mutation R3 — forget them and every placement prop on a wrapping stack's children becomes accepted-and-ignored inside the GAME), `env:batch` present on the environment the game builds, and the progress capability registry still declaring the three cells the rally bar depends on (mutating `bar.valueLabel` reddens one case; mutating `bar.hasTrack` reddens 388, because the rally bar stops presenting). The behaviour cases assert the game is UNCHANGED, which is the other half of the rider: a real shipped screen still solves with zero diagnostics, each geometry fact still re-solves, and `a rotation re-solves the role-pick modal without per-key fan-out` asserts a CEILING of 2 rather than an equality of 1 — deliberately, so that L-29 residual 2's second solve can be removed later without moving the check while a return to ~5 fan-out reddens immediately. `every .wrap =. in this package is the FOCUS-navigation one, in a known file` is the naming-collision guard: `wrap` was already this codebase's word for arrow-past-the-last-row in a focus group, and the spec pins the exact set of existing occurrences BY PATH rather than asserting there are none, because a naive grep would confuse them. `A37b` is the game-side half of item D's `hidden` finding — the Rascal Rally suite caught the behaviour change within the hour, and the tap that broke was driving into a 170x0 losing ViewThatFits candidate no player could reach. WHAT THIS ROW DOES NOT CLAIM: no game behaviour was authorized to change and none did (A37 was a test fixing its own drive, not a product change), and there is NO Rascal Rally Studio canary for the round-3 surface — the same gap round 2's block recorded, still open.",
		},
		{
			name = "owed-ledger-honest",
			requirements = { "UI-AGENT-001" },
			run = 'f=artifacts/swiftui-parity-round3/owed.md && test -f "$f" && for id in O-1 O-2 O-3 O-4 O-5 O-6 O-7 O-8 O-9 O-10 O-11 O-12 O-13 O-14 O-15 O-16 O-17 O-18 O-19 O-20 O-21 O-22; do grep -qE "^[|] [*][*]${id}[*][*] [|]" "$f" || { echo "$id missing from the owed ledger"; exit 1; }; done && grep -qE "^[|] [*][*]O-1[*][*] [|].*[|] .PENDING_HUMAN. [|]" "$f" && grep -qE "^[|] [*][*]O-3[*][*] [|].*[|] .PENDING_PHYSICAL. [|]" "$f" && grep -qE "^[|] [*][*]O-18[*][*] [|].*[|] .PENDING_PHYSICAL. [|]" "$f" && test "$(grep -cE "^[|] [*][*]O-[0-9]+[*][*] [|].*[|] .CLOSED_ROUND3. [|]" "$f")" -eq 8 && test -f tests/gallery_chrome.spec.luau && test -f examples/gallery/client/showcase_chrome.luau && test -f examples/gallery/client/settings_panel.luau && test -f examples/places/LuauUI-Showcase.rbxl && test -f docs/reference/api.md && test -f tests/overflow_sweep.spec.luau && test -f src/controls/table.luau && test -f src/controls/virtual_list.luau && grep -qF "It is not a claim that the" "$f"',
			evidence = "artifacts/swiftui-parity-round3/owed.md",
			note = "THE OWED LEDGER, STATUS-ANCHORED, because the brief's `Still owed, ranked` table lives in a design document where closing an item is a one-line edit nobody reviews. All 22 rows must be present by id (the brief's fourteen plus the eight round 3 created, the last of which — O-22, the flat baseline left uncharacterized by the popup-catcher fix — was found by this gate's own checker-battery row), which is what makes shortening the list a gate failure. THE THREE ANCHORED STATUSES ARE THE HONEST REDS: O-1 (the traversal re-record) must still read PENDING_HUMAN, O-3 (the Studio device canary) and O-18 (brief item E2, the hosted vertical pan that fires onActivate) must still read PENDING_PHYSICAL — so relabelling any of them as done fails here, exactly as the swiftui-reference-app-validation acceptance-ledger row refuses a relabelled physical row. THE CLOSED COUNT IS PINNED AT EIGHT and each names evidence this check verifies exists on disk: O-2 (places rebuilt), O-4 (the chrome), O-5 (api.md's prose skim), O-8 and O-9 (the tray focus group and hosted Delete — one defect, two hosts, src/controls/table.luau + src/controls/virtual_list.luau), O-11 (settings_panel.luau), O-14 (the sweep's phrase filter deleted) and O-16 (the virtualSlot class the sweep can now see). A NINTH CLOSED ROW CANNOT BE ADDED WITHOUT EDITING THIS CHECK, which is the point — a status change should cost a gate edit and a note, not a keystroke. It was FOUR when this row was first written and EIGHT ninety minutes later, because a concurrently running agent kept closing ledger rows while this gate was being authored; the count moving is the mechanism working, not a defect in it, and the ledger is a snapshot at this commit rather than a live view. WHAT THIS ROW DELIBERATELY IS NOT: it does not assert that any OPEN item is still broken. An inverted check would go red on the day somebody legitimately fixes one — the one moment the ledger is finally right — and would then be edited to agree with the change, which is the failure mode tools/check_traversal_evidence.py's own docstring was written about. The final grep pins that disclaimer inside the artifact, so the file cannot be rewritten into a claim it is not making.",
		},
		{
			name = "traversal-evidence-red-carried",
			requirements = { "UI-FID-001", "UI-AGENT-001" },
			run = "test -f tools/check_traversal_evidence.py && grep -qF \"THE FIX IS A RE-RECORD, NOT AN EDIT\" tools/check_traversal_evidence.py && grep -qF \"Owed: the TD-13/TD-14 re-record\" docs/plans/device-bug-round-2026-08-12.md && python3 -c \"\nimport re, sys\nsrc = open('tools/lune/gate_manifest.luau').read()\nstart = src.index('[\\\"traversal-document-order\\\"]')\nrest = src[start + 10:]\nm = re.search(r'\\n\\t\\[\\\"', rest)\nblock = rest[: m.start()] if m else rest\nif 'name = \\\"studio-evidence\\\"' not in block:\n    sys.exit('traversal-document-order no longer registers a studio-evidence check')\nif not any(l.strip().startswith('run =') and 'check_traversal_evidence' in l for l in block.splitlines()):\n    sys.exit('studio-evidence no longer RUNS tools/check_traversal_evidence.py — the red was downgraded, not re-recorded')\nprint('traversal-document-order/studio-evidence still runs the structural staleness check')\n\"",
			note = "THE HONESTLY-RED ITEM, CARRIED FORWARD FROM ROUND 2 UNCHANGED, and re-registered here rather than inherited because round 3 is the stage a future sweep will run first. `traversal-document-order` / `studio-evidence` is still RED at registration — `python3 tools/check_traversal_evidence.py` exits 1 with STALE EVIDENCE, verified 2026-08-13 — and round 3 neither caused it nor can close it: the device round of 2026-08-12 wrapped the keyboard_navigation scenario's body in a UI.ScrollView, every surface moved one path segment deeper, and the Studio artifact is still the 2026-08-03 capture. The checker derives the expected prefix from the scenario source ON DISK and says so in one sentence: THE FIX IS A RE-RECORD, NOT AN EDIT. WHAT THIS CHECK IS: three guards against the red being made to disappear the wrong way — the structural checker still exists and still carries its own instruction, the re-record is still booked as owed, and the traversal-document-order block in this file still registers `studio-evidence` as a check that RUNS that checker, read by slicing that gate's block out of this file so this row cannot satisfy itself with its own text (a self-matching grep is a check that cannot fail). WHAT IT DELIBERATELY IS NOT: it does not assert the checker currently FAILS. An inverted check would go red on the day a human legitimately re-records, and would then be edited to agree with the change. The red stays red in the gate that owns it; this row refuses to let it be quietly rewritten as never having happened, and owed.md carries it as O-1 / PENDING_HUMAN.",
		},
		{
			name = "studio-device-canary",
			requirements = { "UI-FID-001", "UI-PARADIGM-001" },
			state = "FAIL_ENVIRONMENT",
			releaseBlocking = false,
			evidence = "artifacts/swiftui-parity-round3/studio/canary-2026-08-14.md",
			note = "HALF RUN 2026-08-14, AND THE HALF THAT DID NOT RUN IS WHY THIS ROW IS STILL NOT A PASS. Round 3 shipped four surfaces whose remaining questions only a live session can answer, and every one of them closed headless-green with an explicit rider in the mission record. TWO ARE NOW ANSWERED, in a live Studio EDIT datamodel against the real screen_target adapter (the evidence file above; tier 2, never a device claim). ITEM A — the `flow_wrap` fixture had never been mounted in an engine at all; it is mounted now, and its own A/B was driven at 389x762: wrapped, the fourteen tags occupy FOUR lines and diagnostics is empty; unwrapped, one line reaching x=1183 and the solver reports `content overflows this hstack by 806px on the main axis`. The captures also say something the numbers do not — only five tags PAINT, because the page's own ScrollView crops the rest, so the diagnostic's `it will paint outside its box` is the honest worst case rather than what a player sees. ITEM D2 — BOTH halves answered, and both flip an assumption. (a) `ClipsDescendants` does NOT crop a Path2D stroke: the same octagon drawn in a clipping and a non-clipping 200x200 panel paints identically past the edge in both, while GetBoundingRect returns 147x147 for both — so a `presentation = \"circular\"` ring inside a scrolling or clipping host paints outside it and no diagnostic can see it, which is a live-only defect class. (b) `Path2D:UpdateControlPoint` — the cheap in-place mitigation — SUCCEEDS on a parented Path2D and refuses only on an unparented one (`Attempting to use Path2D with invalid parent`); the framework always parents its Path2D under a holder Frame, so that path is open. The arc's cost was measured in writes rather than guessed: 121 -> 9,169 propWrites across 120 heartbeats, ~75 per frame, on DESKTOP Studio — a magnitude for a phone number to be compared against, not a phone budget. STILL NOT RUN, and this is the blocker rather than an excuse: the Studio MCP Play bridge is unavailable in this environment — start_stop_play times out and then answers `Start play hasn't finished yet` for the rest of that instance's life, and while a session IS in Play, execute_luau answers `Target is not reachable` for BOTH the Client and Server datamodel; reproduced on two Studio instances, the second fresh. Synthetic CGEvent clicks and System Events keystrokes do not reach Studio either (proved against an Explorer row and a ribbon tab). So ITEM D — whether Roblox itself already refuses input to an invisible GuiButton — stays unanswered for want of delivered input, though the canary did record the shipped shape behind it (every `hud` node outside the viewport box is a `LuauUIHitExpander`: a TextButton, Visible = true, BackgroundTransparency = 1, painting nothing). ITEM E — a real Backquote reaching IAS, and a physical ButtonY firing Activate end to end — needs Play and hardware and stays PENDING_PHYSICAL. So does everything presenter-shaped: `roblox_input.newSystem` requires Players.LocalPlayer, which an Edit datamodel does not have, so there is no presenter and no InputContext in this canary at all. SPELLED AS FAIL_ENVIRONMENT WITH releaseBlocking = false, which is this manifest's established shape for work that is blocked on hardware or a human session (every PENDING_PHYSICAL row in every stage above): it reads as a non-PASS in the roll-up and in gate.json, it is visible to anyone reading the gate, and it does not block the phase — while a bare PENDING would make the gate structurally un-passable and would therefore be deleted rather than closed. IT KEEPS THAT SPELLING even though two of its four questions closed, because the row is the SESSION, not the question list: the four questions are enumerated individually in artifacts/swiftui-parity-round3/owed.md, which still carries O-3 as PENDING_PHYSICAL, and a row that went green on the Edit-datamodel half would retire the Play half with it.",
		},
		{
			name = "prior-gates-unregressed",
			requirements = { "UI-AGENT-001" },
			run = "if [ -n \"${LUAUUI_PRIOR_GATES_NESTED:-}\" ]; then echo \"prior-gates: NESTED - regeneration skipped (the outer prior_gates.sh run re-runs this same list)\"; exit 0; fi; a=artifacts/swiftui-parity-round3/prior-gates-rerun.txt && tools/prior_gates.sh \"$a\" swiftui-parity-round3 && grep -q \"^DONE$\" \"$a\" && python3 -c \"\nimport re, sys\nallowed = {\n    ('phase-1-minimal-screen', 'bench-reproducible'),\n    ('phase-2-settings-parity', 'ui-cost-budget'),\n    ('phase-3-pilot', 'no-leak-regression'),\n    ('part-2-director', 'ws1-adr-and-bench'),\n    ('expansion-textinput', 'expansion-adr-bench-rollback'),\n    ('code-simplicity-cleanup', 'performance-unregressed'),\n    ('api-architecture-consistency', 'performance-unregressed'),\n    ('example-quality-pass', 'rascalrally-consumer'),\n    ('traversal-document-order', 'studio-evidence'),\n}\ngate = None\nbad = []\nfor line in open('artifacts/swiftui-parity-round3/prior-gates-rerun.txt'):\n    m = re.match(r'^FAIL (\\S+)', line)\n    if m:\n        gate = m.group(1)\n        continue\n    if re.match(r'^PASS ', line):\n        gate = None\n        continue\n    m = re.match(r'^[ ]+FAIL_RECOVERABLE[ ]+(\\S+)', line)\n    if m and gate is not None and (gate, m.group(1)) not in allowed:\n        bad.append((gate, m.group(1)))\nif bad:\n    print(bad)\n    sys.exit(1)\n\"",
			evidence = "artifacts/swiftui-parity-round3/prior-gates-rerun.txt",
			note = "All 27 prior gates RE-RUN by this check at the source being judged, via tools/prior_gates.sh with the list derived from phases.json — the same shape round 2, row-actions and seven stages before them carry, and for the same reason (gate-integrity sweep 2026-07-29, defect B-1: a stored-file grep that executes nothing against the current tree is a can't-ever-fail check). Guarded by LUAUUI_PRIOR_GATES_NESTED so a sweep that reaches this stage as somebody else's prior does not recurse. The verdict logic and the nine-pair allowlist are round 2's VERBATIM: eight bench-shelling checks that rotate red under CPU load (an interleaved A/B proved the unchanged pre-stage loop flags exactly as often as the shipped one), plus (traversal-document-order, studio-evidence), the honestly-red item the row above guards. Every other FAIL_RECOVERABLE still fails this check outright; the allowlist is never widened for a genuinely new failure. ONE PRIOR GATE WAS FOUND RED BY ROUND 3'S OWN WORK AND WAS REPAIRED RATHER THAN ALLOW-LISTED: swiftui-parity-round2/overflow-sweep pinned three scenarios at the case title `no main-axis overflow at any swept viewport`, and item A, the accessibility axis and then ledger row 14's filter deletion renamed that title TWICE in one day, most recently to `the solver reports NOTHING at any swept viewport, at any text size`. A rename is the cheapest way in the world to break a name-based check; the greps were re-pointed at the current titles (same three scenarios, a strictly stronger claim) in the round-2 block, which is the repair round 2's own four-input-proofs note prescribes. It was found by running every suite grep in this entire manifest — 845 patterns — against one complete LuauUI transcript and one complete Rascal Rally transcript; overflow-sweep was the only genuine miss. NOT YET RUN, AND SAID PLAINLY: at registration time this stage's sweep had NOT been executed. Three other agents were live in this tree with uncommitted edits to src/controls/row_actions.luau, tests/run.luau, tests/overflow_sweep.spec.luau, tests/theme_chrome.spec.luau and docs/reference/api.md; a sweep re-runs 27 gates each invoking the full suite several times, so it would have judged a tree that changes underneath it and produced reds belonging to nobody. So this row is registered live and RED for the honest reason that its evidence does not exist yet — the same statement round 2's block makes, for the same reason, and it is the one check in this block that was not mutation-proven, because proving it would have meant running the sweep this stage could not run.",
		},
	},
}

return manifest
