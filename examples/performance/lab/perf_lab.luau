--!strict
-- Scenario 'perf_lab' — the performance lab (roadmap Step 9,
-- docs/plans/performance-stress-places.md; acceptance rows PL-2..PL-11, PL-17).
--
-- ONE registered scenario, NINE named workloads. The gallery runner mounts one
-- scenario per Play session (selected by a workspace attribute before Play), and
-- a lab whose every workload needed a Studio restart would be unusable on a
-- phone and unusable in an automated sweep. So the workload is a SELECTOR inside
-- this scenario: `select`, then `mount`, then `run`. That also makes the plan's
-- required "scenario, implementation, dataset size, seed, and run-mode selectors"
-- literal rather than aspirational.
--
-- EXACTLY ONE IMPLEMENTATION IS MOUNTED (PL-5). The Facet list and the matched
-- raw-Roblox reference answer the same question from opposite sides, and a
-- capture with both mounted is a sum of the two wearing one label. `mount`
-- refuses rather than trusting the caller.
--
-- ENGINE-FREE, like every scenario module. Engine seams arrive through the
-- runner ctx (`telemetry`, `themeChrome`, `geometry`, `bindResourceTransport`)
-- and through `ctx.host`, the lab client's own seam table (the raw-Roblox
-- reference, the environment facts, and the profiler wrapper). Nothing in this
-- file touches `game`, `Instance`, or `debug`.

-- Bump when a workload's STEPS change. Paired with dataset.VERSION and
-- rows.VERSION in every capture; the three together are the workload identity.
--
-- /2 (2026-08-04): SPLIT SCROLLING IN TWO. /1 had one "scrollProgrammatic" pass
-- that divided the whole canvas extent by the step count — with 2 000 rows and 12
-- steps that is a 166-row jump per step, which replaces the entire mounted window
-- every time. That is a SEEK (a scrollbar drag, a jump-to-index), not steady
-- scrolling, and the first MicroProfiler capture read exactly that: Facet/mount
-- at 12.5ms mean while measure/arrange/commit together were under 2ms. Answering
-- "is steady scrolling smooth" with a seek profile would have blamed the wrong
-- phase. `scrollSteady` advances a fixed pixel rate per frame the way a flick
-- does; `scrollSeek` keeps the old behaviour under its honest name. Both are
-- captured, because both are real.
--
-- /3 (2026-08-05): the row restacks on a compact width (perf-row/2) and the list's
-- rowHeight follows the same decision, so a phone no longer paints rows over each
-- other. The layout audit is now enforced at mount and after every pass.
--
-- 2026-08-14: TWO WORKLOADS ADDED FOR WHAT ROUND 3 SHIPPED, AND THE VERSION DOES
-- NOT MOVE. Every pass above this date windows by ONE number (`index x pitch`)
-- and no pass anywhere touched `newTable`, so the two things the collection round
-- actually built — the running-offset index behind variable item extents
-- (`src/virtual_extents.luau`) and `newTable{ virtualized = true }` — were
-- unmeasured by construction. `variable-extents` and `table-unified` are those
-- two, and both mount their own surfaces.
--
-- THE VERSION IS THE WORKLOAD'S IDENTITY, AND NO EXISTING WORKLOAD'S IDENTITY
-- CHANGED. The rule at the top of this block is "bump when a workload's STEPS
-- change", and adding a workload changes no other workload's steps: `dense-scroll`
-- runs the same passes over the same dataset and the same rows as it did this
-- morning. Bumping it was tried and is wrong — `tools/check_perf_captures.py`
-- immediately (and correctly) declared all six admissible PL-9 captures to
-- "describe a workload that no longer exists", which would have thrown away real
-- measurements of unchanged work to record an addition. A capture row already
-- carries the workload id, so a reader can always tell whether a given capture
-- predates these two.
local SCENARIO_VERSION = "perf-scenarios/4"

-- ---- the declared workloads ----------------------------------------------
-- Each isolates ONE cost so a profile has an interpretable cause. The plan is
-- explicit that a giant "everything churns" workload is worse than none.
local WORKLOADS = {
	{
		id = "idle-baseline",
		implementation = "none",
		question = "What does the place cost before any Facet work?",
		passes = {},
	},
	{
		id = "mount-ramp",
		implementation = "facet",
		question = "How do initial mount, layout, Instance creation and memory scale with row count?",
		passes = { "ramp" },
	},
	{
		id = "dense-scroll",
		implementation = "facet",
		question = "Is steady scrolling smooth and is windowing bounded?",
		passes = {
			"scrollSteady",
			"scrollSeek",
			"focusTraverse",
			"keepVisible",
			"selectRow",
			"updateOne",
			"updateBatch",
		},
	},
	{
		id = "dense-scroll-native",
		implementation = "native",
		question = "Which cost is unavoidable engine UI work versus Facet overhead?",
		passes = { "scrollSteady", "scrollSeek", "selectRow", "updateOne", "updateBatch" },
	},
	{
		id = "collection-churn",
		implementation = "facet",
		question = "Do updates stay proportional to changed and visible content?",
		passes = { "insert", "remove", "reorder", "selectRow", "scrollSteady" },
	},
	{
		id = "layout-style-churn",
		implementation = "facet",
		question = "Which invalidations cause unnecessary whole-tree work?",
		passes = { "preferenceSweep", "resize", "themeCost" },
	},
	{
		id = "resize-relayout",
		implementation = "facet",
		question = "What does a continuous resize cost, and how much of it is re-solving what did not change?",
		passes = { "resizeStorm", "scrollSteady", "updateOne" },
	},
	{
		id = "large-text-overflow",
		implementation = "facet",
		content = "identity",
		question = "Are measurement, disclosure and any motion bounded without hiding content?",
		passes = { "preferenceSweep", "localeSwap", "scrollSteady", "revealAudit" },
	},
	{
		id = "async-image-churn",
		implementation = "facet",
		question = "Are decoding, resource lifecycle and UI updates separated and bounded?",
		passes = { "imagesCold", "imagesWarm", "imagesFail", "imagesReuse" },
		--[[ THE PASS `Profile 1` LOOPS, WHICH IS NOT `passes[1]` HERE.

			`imagesCold`, `imagesWarm` and `imagesFail` are one-shot STATE CHANGES —
			set the resource state, refresh once — and the declared order cold → warm
			→ fail → reuse is what `steps.run()` should execute. Looped, each of them
			re-sets a flag that is already set: measured at 1 arrange and 0 mounts per
			lap, headless and on the device alike. `imagesReuse` is the only one that
			churns the window, so it is the only one a profiling capture can contain.
			Device capture `asyncImage.html`, 2026-08-15, is twenty-nine byte-identical
			frames of `imagesCold`; see device-capture-2026-08-15.md. ]]
		profilePass = "imagesReuse",
	},
	{
		-- `implementation = "none"` on purpose: the pass mounts its own surface, so
		-- a flight's cost is not blended with virtual-list windowing. See
		-- `passes.motionFlight` for the four-arm design and the tier rules.
		id = "motion-flight",
		implementation = "none",
		question = "What does an interpolating property cost per frame — position, size, and the AUTHORED paint triple — and what does a surface that authors none of them pay?",
		passes = { "motionFlight" },
	},
	{
		-- `implementation = "none"`: the pass mounts its own four arms, so the
		-- cascade's cost is not blended with virtual-list windowing (the same
		-- reason `motion-flight` stands alone).
		id = "sensory-cascade",
		implementation = "none",
		question = "What does the per-control sensory cascade cost a tree that declares nothing, and what does one declaration on a root cost when it reaches every node?",
		passes = { "sensoryCascade" },
	},
	{
		-- `implementation = "none"`: the pass mounts its own four arms, for the same
		-- reason `motion-flight` does — an A/B between two windowing ARITHMETICS has
		-- to hold everything else identical, and the shared `mounted` list is built
		-- from one spec.
		id = "variable-extents",
		implementation = "none",
		question = "What does a variable-extent window cost against the uniform arithmetic it replaces — to build the index on a data change, and to scroll?",
		passes = { "extentArms" },
	},
	{
		-- `implementation = "none"`: this workload's subject is `newTable`, not
		-- `newVirtualList`, so it mounts its own surface rather than teaching the
		-- shared mount seam a third implementation.
		id = "table-unified",
		implementation = "none",
		question = "What do virtualization, multi-selection and reordering cost in ONE container, and does each verb still reach a row no window has held?",
		passes = { "tableUnified" },
	},
	--[[ THE TWO NAMED LEVERS (2026-08-15), declared here and IMPLEMENTED in
		`examples/performance/lab/levers.luau`.

		`device-capture-2026-08-15.md` §7 ranks two levers and records that neither
		has a workload aimed at it: `arrange` itself (top cost in all four device
		captures, 9.1-10.6 ms/occurrence, worst 298.87 ms) and incremental layout on
		a COLLECTION EDIT (L-27 measured it inert on a resize, which is the case
		where every constraint changes; a collection edit is the opposite case and
		has never been measured). These are those two.

		AN ARM IS A PASS, which is the whole point of the shape. `extentArms` runs
		five arms inside one pass — 540 frames per lap — so a 60-frame MicroProfiler
		aggregate could never contain the comparison it was built for, and nothing in
		the dump named which arm the window landed in (L-35 D3). Here one lap is one
		arm, and `profileWindow` already stamps `Facet_ProfilingPass` into a
		`workspace` attribute, so the arm identity is in the session for free.

		WHY THE PASS NAMES ARE WRITTEN OUT HERE. This table is the one answer to
		"what workloads exist" — the picker, the sweep, the capture rows and
		`steps.workloads` all read it — and this module must stay `script`-free to
		run under Lune, so it cannot `require` the file that implements them. The
		duplication is closed at the bottom of `build`: every declared pass is
		asserted to have been installed, and the spec asserts these lists are exactly
		`levers.SHAPE_ARMS` / `levers.EDIT_ARMS`.

		ADDING THEM DOES NOT MOVE `SCENARIO_VERSION` — no existing workload's steps
		change, and a bump would declare all 18 admissible capture rows to describe a
		workload that no longer exists. Same ruling as the 2026-08-14 pair and L-33. ]]
	{
		id = "arrange-shapes",
		implementation = "none",
		question = "WHICH tree shape makes `arrange` expensive — and is the cost per NODE flat, "
			.. "or does one of arrange's per-kind phases dominate?",
		passes = { "flat", "flatRepeat", "deep", "deepScroll", "fill", "zstack", "wrap", "scroll", "text" },
		--[[ THE DEFAULT DUMP IS THE CONTROL, deliberately. An operator gets one dump
			before they have any calibration at all, and `flat` is the arm every other
			number is quoted against: the shortest path through arrange's stack branch,
			so its ms-per-arranged-node is the floor. A dump of `fill` alone says
			"expensive"; `flat` then `fill` says what the distribution phase costs. ]]
		profilePass = "flat",
	},
	{
		id = "edit-locality",
		implementation = "none",
		question = "Does a data edit that changes nothing visible still re-solve what did not move — "
			.. "and does incremental layout bite on a collection edit, where L-27 found it inert on a resize?",
		passes = {
			"editOffWindow",
			"editOffWindowRepeat",
			"editOffWindowIncremental",
			"editInWindow",
			"editInWindowIncremental",
		},
		--[[ THE DEFAULT DUMP IS THE ARM NOBODY HAS EVER CAPTURED. The incremental-OFF
			case is already tier-3 priced — `collectionChurn.html` is 26 solves per
			frame at 9.384 ms each, and (see levers.luau) the lab's own default meant
			the reuse path was DISABLED for it. The ON case has no capture at any tier,
			on the one edit shape where the reuse path has a reason to work. ]]
		profilePass = "editOffWindowIncremental",
	},
	--[[ THE THIRD NAMED LEVER (2026-08-17), same shape as the two above,
		implemented in `examples/performance/lab/levers.luau` (`levers.HOST_ARMS`).
		`artifacts/nested-instance-tree/live-probes.md` §4 measured this exact
		shape in Studio — a 20-row list inside a `ScrollView` with a header above
		it whose height goes 20 -> 60 — at 241 engine `Position` writes before
		ADR-0032's ordering fix and 1 after. Nothing pressed it at scale or asked
		whether the collapse is a FRAME-TIME win; `hosted`/`unhosted` are the same
		rows with and without the `ScrollView`, and `*Large` sweeps N 5x. SAME
		RULING AS 2026-08-14/2026-08-15: adding a workload changes no existing
		workload's steps, so `SCENARIO_VERSION` does not move. ]]
	{
		id = "host-move",
		implementation = "none",
		question = "Does a container's engine writes collapse when it moves inside a real instance "
			.. "host, and does that collapse show up as a frame-time difference on the device that "
			.. "matters? ADR-0032's own standing risk: the engine's C++ descendant walk is unmeasured, "
			.. "so this may show nothing.",
		passes = { "hosted", "hostedRepeat", "unhosted", "hostedLarge", "unhostedLarge" },
		profilePass = "hosted",
	},
	{
		id = "lifecycle-soak",
		implementation = "facet",
		question = "Do Instances, connections, memory or stale work trend upward?",
		passes = { "soak" },
	},
}

local WORKLOAD_BY_ID: { [string]: any } = {}
local WORKLOAD_ORDER: { string } = {}
for _, w in WORKLOADS do
	WORKLOAD_BY_ID[w.id] = w
	table.insert(WORKLOAD_ORDER, w.id)
end

-- the four native preference offsets, measured in Step 8.5 and pinned there
local PREFERENCE_OFFSETS = { 0, 4, 10, 14 }

-- THE MOST EXPENSIVE SHIPPED ASSET-BACKED PACKAGE (PL-6). Chosen by counting, not
-- by reputation: of the eleven non-testOnly reference packages in examples/themes,
-- `fantasy_ornate` declares 34 distinct image assets across 656 lines — more than
-- twice the next (`pixel_quest`, 20) and six times `fantasy_parchment`. The plan
-- asks for flat versus the MOST expensive skin, so the name is pinned here rather
-- than left to whoever drives the capture.
local FLAT_PACKAGE = "flat"
local ORNATE_PACKAGE = "fantasy_ornate"

return {
	title = "Facet performance lab",
	ledgerRows = {
		"PL-2",
		"PL-3",
		"PL-4",
		"PL-5",
		"PL-6",
		"PL-7",
		"PL-9",
		"PL-10",
		"PL-11",
		"PL-13",
		"PL-17",
	},
	WORKLOADS = WORKLOADS,
	SCENARIO_VERSION = SCENARIO_VERSION,

	build = function(ctx: any)
		local Facet = ctx.Facet
		local core = ctx.core
		local env = ctx.env
		local host = ctx.host or {}
		-- SIBLING MODULES ARRIVE THROUGH ctx, never through `script.Parent`. A
		-- scenario module that reached for `script` would be Roblox-only, and the
		-- whole point of the shared dataset/row definitions is that the SAME files
		-- run under Lune in the headless scene and the headless test. `ctx.lab` is
		-- supplied by the lab client in Studio and by the test harness in Lune.
		local lab = ctx.lab
		assert(
			type(lab) == "table" and lab.dataset ~= nil and lab.rows ~= nil and lab.capture ~= nil and lab.levers ~= nil,
			"[perf lab] ctx.lab must carry { dataset, rows, capture, overlay, levers } — see examples/performance/client/init.client.luau"
		)
		local dataset = lab.dataset
		local rows = lab.rows
		local capture = lab.capture
		local overlayLib = lab.overlay
		-- the two named levers (arrange by tree shape, incremental layout on a
		-- collection edit). Its passes are installed into `passes` below, once the
		-- helpers they share with this file exist.
		local leversLib = lab.levers
		-- profiler wrapper: the framework's own, handed in by the lab client so
		-- driver scopes and framework scopes come from ONE implementation and can
		-- never disagree about naming or balance. Absent headlessly -> a no-op span
		-- with the same signature, so this file behaves identically in a test.
		local profile = host.profile
			or {
				span = function(_key: string, fn: any)
					return fn()
				end,
				counters = function()
					return { opens = 0, closes = 0, balanced = true, engine = false, enabled = false, byScope = {} }
				end,
				resetCounters = function() end,
				SCOPES = {},
			}
		local telemetry = ctx.telemetry
			or {
				clock = function()
					return 0
				end,
				step = function()
					return 0
				end,
				instances = function()
					return { measured = false }
				end,
				connections = function()
					return { measured = false }
				end,
				memory = function()
					return { measured = false }
				end,
			}

		local labScope = core:scope("perf-lab")
		-- ONE ADAPTIVE DECISION, read by BOTH the row's arrangement and the list's
		-- fixed row height. A VirtualList windows on a fixed pitch, so two decisions
		-- here would be the split brain that paints a 152px row into a 56px slot —
		-- which is exactly the defect a phone screenshot exposed.
		-- THE DECLARED FAULT for the layout audit (the negative control PL-3 owes). It
		-- forces the one-line arrangement onto a width that cannot hold it — the exact
		-- shape that shipped — so the audit can be seen to bite rather than assumed to.
		local labOptions = ctx.labOptions or {}
		local isCompact = labScope:own(core:memo(function(use)
			if labOptions.forceOneLineRow == true then
				return false
			end
			local vp = use(env:get("viewportRect"))
			local w = if type(vp) == "table" and type(vp.w) == "number" then vp.w else 1280
			return rows.compactFor(w)
		end))
		-- THE THEME IS A ROW-GEOMETRY FACT (L-26). `themeMetrics` rides the
		-- environment, so reading it through `use` is what makes a theme swap re-derive
		-- the arrangement, the row height and the window bound in the same commit that
		-- repaints — the alternative is a themed surface laid out for a flat one, which
		-- is exactly what shipped.
		local splitControls = labScope:own(core:memo(function(use)
			if use(isCompact) ~= true then
				return false
			end
			local vp = use(env:get("viewportRect"))
			local w = if type(vp) == "table" and type(vp.w) == "number" then vp.w else 1280
			return rows.splitControlsFor(w, use(env:get("themeMetrics")))
		end))
		local rowHeight = labScope:own(core:memo(function(use)
			return rows.heightFor(
				use(isCompact) == true,
				use(env:get("typographyScale")),
				use(env:get("themeMetrics")),
				use(splitControls),
				-- the fourth input, added 2026-08-13 after a device refused to mount:
				-- `use`d, so raising the preference re-solves the pitch live rather
				-- than leaving every row overflowing a slot measured at Medium
				use(env:get("preferredTextOffset"))
			)
		end))
		-- forward: `listHeight` needs `viewportH`, which is declared with the window
		-- bound below; a later `local` would be nil at build time
		local listHeight: any

		-- ---- settings (the plan's selectors) ------------------------------
		-- The workload-owned defaults, named once: `select` restores them for any
		-- setting the chosen scenario does not declare, so a sweep is order-independent.
		local DEFAULT_CONTENT = "normal"
		local DEFAULT_THEME = "flat"
		local settings = {
			scenario = "idle-baseline",
			implementation = "none",
			rows = 2000,
			seed = 1,
			content = DEFAULT_CONTENT,
			theme = DEFAULT_THEME,
			-- INSTANCE RECYCLING (framework opt-in, default off). A selector rather
			-- than a constant so the same place can A/B it: the only honest way to
			-- report what it buys is to measure both builds in one session.
			recycle = true,
			-- incremental layout (Stage 2), selectable so the same place can A/B it
			incremental = false,
			cleanCapture = false,
			resourceState = "cold",
			-- THE DECLARED FAULT (PL-4's negative control). A bounded-window
			-- assertion nobody has seen fire is decoration, so the lab can break its
			-- OWN virtualization on demand: with the fault on, the list is built with
			-- an overscan large enough to materialize the whole logical collection,
			-- which is precisely the regression the assertion exists to catch. It is
			-- a first-class step so the instrument can be proven to bite in Studio,
			-- not only in a test.
			faultWindow = false,
			warmupFrames = 30,
			captureFrames = 120,
		}

		-- ---- live state ---------------------------------------------------
		local mounted: any = nil -- the ONE mounted implementation
		local items = dataset.build({ count = settings.rows, seed = settings.seed, content = settings.content })
		local rowsSignal = labScope:own(core:signal(items))
		local provider = Facet.newResourceProvider(core, { maxConcurrent = 8 })
		local unbindTransport: (() -> ())? = nil
		-- OWNED, so a reset RELEASES them (found live 2026-08-04). The per-row value
		-- and toggle signals are deliberately retained across scrolling — a control
		-- that resets when its row leaves the window is a different, cheaper workload
		-- — but they are keyed by item id, so a new dataset is a new population and
		-- the old ones must go. Dropping the TABLE is not disposing the SIGNALS: the
		-- first reset left 488 live signals on the core with nothing referencing
		-- them, which is exactly the trend a soak row is supposed to catch.
		local dataScope = labScope:child("perf-lab-data")
		local values: { [string]: any } = {}
		local toggles: { [string]: any } = {}
		local passLog: { any } = {}
		local emergencyStopped = false
		--[[ THE STOP A PASS CANNOT UNDO.

			`emergencyStopped` is reset to false by three step handlers AND by
			`passes.ramp` itself (it clears the flag so its own ladder starts
			un-stopped). That is fine for a single run and fatal for a loop: the
			profiling window's `while not emergencyStopped` was cleared by the very
			pass it was looping, so pressing Stop could never end it.

			This flag is set only by `steps.stop`, cleared only by `steps.resume`
			and by `profileWindow` at entry, and read only by the profiling loop.
			Two flags because they answer two questions — "abandon this run" and
			"stop looping" — and one variable answering both is what let a pass
			overrule the operator. ]]
		local profileStopRequested = false
		--[[ WHICH ARM `Profile 1` WILL LOOP, per workload.

			The two lever workloads declare their ARMS as passes (see levers.luau), and an
			arm comparison needs one dump per arm — so the operator has to be able to pick
			one. On a phone that means a BUTTON, and it means the button cannot be the one
			that starts the loop: `Profile 1` runs until Stop, so a control that both
			advanced the arm and started a run would either race the running loop or need
			two presses to do one thing. So `Arm >` only MOVES the pointer and says where
			it landed; `Profile 1` reads it. Two buttons, one job each, no concurrency.

			Per workload rather than global: cycling away to check something and back
			should not silently re-aim a capture session at arm 1.

			Nil means "whatever `profileWindow` would default to" (`profilePass`, else
			`passes[1]`), so an untouched lab behaves exactly as it did before this
			existed and every recorded capture stays valid. ]]
		local profileArm: { [string]: number } = {}
		local rampIndex = 0
		local lastCapture: any = nil

		-- overlay model signals
		local statusLine = labScope:own(core:signal("idle"))
		local countdown = labScope:own(core:signal(""))
		local counterLines = labScope:own(core:signal({ "no workload mounted" }))
		local currentScenario = labScope:own(core:signal(settings.scenario))
		local overlayHandle: any = nil
		-- forward: `mount` raises the overlay, and the overlay helpers are defined
		-- below it (they need the step table). A plain later `local` would be nil at
		-- call time — which is exactly how the first version failed.
		local raiseOverlay: () -> boolean
		-- forward, for the same reason: the action row is built above the arm helpers
		local selectedArmPayload: () -> string?

		local function clock(): number
			return telemetry.clock()
		end

		-- ---- the mounted-window bound (PL-4) ------------------------------
		-- Stated as a RULE, not a remembered number, and asserted after every
		-- mount and every scroll: a "virtualized" list that mounts the whole
		-- logical collection must fail here rather than merely be slow.
		--
		-- THE LIST'S HEIGHT IS DERIVED, NOT A CONSTANT (2026-08-05). It was a flat 420,
		-- which is taller than a landscape phone's whole screen — so on 844x390 the
		-- workload screen overflowed itself by 69px, and on 706x339 by 120px. The same
		-- mistake as the fixed row height, one level up: a magic number that does not
		-- adapt is a magic number that is wrong on some real device.
		--
		-- Derived from the live viewport minus the screen's own chrome, floored so a
		-- very short screen still windows something rather than collapsing to nothing.
		-- THE SAFE-AREA INSETS ARE PART OF THE CHROME (found live on a 706x339 landscape
		-- phone: the screen overflowed its own vstack by 33px). Subtracting a flat 64
		-- was a guess that ignored the CoreGui topbar, and the SOLVER insets the content
		-- rect by exactly that fact — so the screen was handed less room than the
		-- arithmetic assumed. `coreSafeInsets` is an environment fact both sides can
		-- read, which is the whole point of it being a fact.
		local MIN_LIST_H = 100
		-- the workload screen's own chrome, named once so the blueprint and the
		-- arithmetic that subtracts it can never disagree
		local SCREEN_PADDING = 8
		local SCREEN_GAP = 6
		-- one header line at type scale 1.0, with slack. Over-reserving chrome only
		-- ever makes the list SHORTER, which cannot overflow anything; under-reserving
		-- paints the list over the header. When a constant has to be approximate, make
		-- it approximate in the safe direction and say which direction that is.
		local HEAD_H = 42

		-- EVERY INSET THE SOLVER APPLIES, INCLUDING THE ONE THAT IS NOT `coreSafeInsets`.
		-- This arithmetic has now been wrong twice, both times by subtracting less than
		-- the renderer did: a flat 64px ignored the CoreGui topbar (706x339 landscape,
		-- 33px over), and adding `coreSafeInsets` still missed the ten-foot OVERSCAN
		-- margins the renderer composes on top of them while the display class is Large
		-- (1920x1080 console, 104px over).
		--
		-- The fix is not a bigger guess. `renderer.solveAndApply` states exactly what it
		-- subtracts, every term of it is a published environment fact, so this reads the
		-- same facts rather than approximating their sum. A platform that invents a new
		-- margin will add a fact, and this will be wrong again — which is why the audit
		-- below is the thing that actually holds the line, not this function.
		local function solverInsetsV(): number
			local insets = env:get("coreSafeInsets"):get()
			local top = if type(insets) == "table" and type(insets.top) == "number" then insets.top else 0
			local bottom = if type(insets) == "table" and type(insets.bottom) == "number" then insets.bottom else 0
			if env:get("distanceProfile"):get() == "ten-foot" then
				local overscan = env:get("effectiveOverscanInsets"):get()
				if type(overscan) == "table" then
					top += if type(overscan.top) == "number" then overscan.top else 0
					bottom += if type(overscan.bottom) == "number" then overscan.bottom else 0
				end
			end
			return top + bottom
		end
		local function chromeV(): number
			local scale = env:get("typographyScale"):get()
			local s = if type(scale) == "number" and scale == scale then math.clamp(scale, 0.5, 3) else 1
			return 2 * SCREEN_PADDING + SCREEN_GAP + math.ceil(HEAD_H * s) + solverInsetsV()
		end
		local function viewportH(): number
			local vp = env:get("viewportRect"):get()
			local h = if type(vp) == "table" and type(vp.h) == "number" then vp.h else 720
			return math.max(MIN_LIST_H, math.floor(h - chromeV()))
		end
		local function windowBound(): number
			return rows.expectedWindow(
				viewportH(),
				isCompact:get() == true,
				env:get("typographyScale"):get(),
				env:get("themeMetrics"):get(),
				splitControls:get()
			)
		end

		listHeight = labScope:own(core:memo(function(use)
			-- SUBSCRIBE to every fact the height depends on, then read the shared
			-- function: two copies of this arithmetic is how the first version drifted
			use(env:get("viewportRect"))
			use(env:get("coreSafeInsets"))
			use(env:get("typographyScale"))
			use(env:get("distanceProfile"))
			use(env:get("effectiveOverscanInsets"))
			return viewportH()
		end))

		local function mountedRowCount(): number
			if mounted == nil then
				return 0
			end
			if mounted.kind == "native" then
				return mounted.mountedRows()
			end
			local n = 0
			for _ in mounted.list.debugWindow() do
				n += 1
			end
			return n
		end

		-- THE LAYOUT AUDIT, ENFORCED (2026-08-05). The lab had a bounded-WINDOW
		-- assertion and no bounded-LAYOUT assertion, on a stage whose entire subject is
		-- a screen. So a row that overflowed its box by 132px and painted over its
		-- neighbours passed every check, every capture and every device-matrix row —
		-- because the matrix asserted `mountedRows <= windowBound` and never asked the
		-- solver what it thought of the geometry.
		--
		-- The solver already knew. It emitted eighteen findings on a 359x718 phone, in
		-- the exact words of the defect ("content overflows this hstack by 132px on the
		-- main axis; it will paint outside its box"). Nobody read them. This makes not
		-- reading them impossible.
		local function surfaceProblem(label: string, controller: any, where: string): string?
			if controller == nil or controller.diagnostics == nil then
				return nil
			end
			local ok, findings = pcall(controller.diagnostics)
			if not ok or type(findings) ~= "table" or #findings == 0 then
				return nil
			end
			-- REPORT SEVERAL, not just the first. A single line sent me guessing at a
			-- ten-foot failure that turned out to be three different causes stacked.
			-- ...WITH THE SOLVED RECT. "overflows by 104px" names a symptom; the box it
			-- overflowed is what says which constant was wrong, and guessing at that
			-- from the message cost a round trip.
			local rectOf = controller.rectOf
			local function rectStr(path: any): string
				if rectOf == nil or type(path) ~= "string" then
					return ""
				end
				local ok2, r = pcall(rectOf, path)
				if not ok2 or type(r) ~= "table" then
					return ""
				end
				return ` [rect {math.floor(r.x or 0)},{math.floor(r.y or 0)} {math.floor(r.w or 0)}x{math.floor(
					r.h or 0
				)}]`
			end
			--[[ ONE FINDING PER LINE, TO THE CONSOLE, BEFORE THE RAISE.

				Device report, game director, 2026-08-13: tapping `mount-ramp` or
				`resize-relayout` on a phone produced this error and it was
				**cut off on screen** — the message packed a count, two sentences
				of explanation and up to four `path [rect] : issue` triples into
				one string, which is unreadable on a 698px-wide device and
				truncates before the findings it exists to deliver.

				That is the diagnostic defeating itself. The whole point of this
				check is that "the solver already knew and nobody read it"; a
				message nobody CAN read is the same failure wearing the opposite
				costume.

				So the findings go to the output as one `warn` per line — which a
				phone's developer console shows scrollably and a Studio session
				shows in Output — and the RAISED error stays short enough to fit
				on the status line. ALL of them are warned, not the first four:
				the truncation existed to keep the string short, and the string
				is no longer where they live. ]]
			for i = 1, #findings do
				warn(
					`[perf lab] {label} finding {i}/{#findings}: `
						.. `{tostring(findings[i].node)}{rectStr(findings[i].node)} — {tostring(findings[i].issue)}`
				)
			end
			-- LEAD WITH THE FIRST FINDING, not with a count and a pointer. A count
			-- tells the reader nothing they can act on, and a device report proved
			-- twice that whatever comes last gets cut off — so the useful part goes
			-- FIRST and the bookkeeping goes last.
			local first = `{tostring(findings[1].node)}: {tostring(findings[1].issue)}`
			return `[perf lab] MOUNT REFUSED — {first}`
				.. (if #findings > 1 then ` (+{#findings - 1} more, one per line in the console)` else "")
		end

		-- BOTH SURFACES, not just the workload. The overlay is its own ScreenGui with
		-- its own controller, and the defect a real device exposed was the two of them
		-- colliding — each individually correct, together unusable. The collision
		-- itself is fixed by the overlay reserving its measured height; auditing the
		-- overlay's own tree is what catches the other half, a control row too wide for
		-- the screen ("Clean capture" clipped at the edge).
		local function layoutProblem(where: string): string?
			if mounted ~= nil and mounted.kind == "facet" then
				local problem = surfaceProblem("workload", mounted.controller, where)
				if problem ~= nil then
					return problem
				end
			end
			if overlayHandle ~= nil then
				return surfaceProblem("overlay", overlayHandle.controller, where)
			end
			return nil
		end

		local function windowProblem(where: string): string?
			if mounted == nil or mounted.kind ~= "facet" then
				return nil
			end
			local n = mountedRowCount()
			local bound = windowBound()
			if n <= bound then
				return nil
			end
			return `[perf lab] virtualization is NOT bounded at {where}: {n} rows mounted for a {viewportH()}px viewport `
				.. `(bound {bound}, logical {#rowsSignal:get()}). A window that grows with the logical collection is `
				.. `the defect this scenario exists to catch.`
		end

		local function assertNoRemountError()
			if lastRemountError ~= nil then
				local msg = lastRemountError
				lastRemountError = nil
				error(`[perf lab] the arrangement remount failed and left nothing mounted: {msg}`, 0)
			end
		end

		local function assertBoundedWindow(where: string)
			local problem = windowProblem(where) or layoutProblem(where)
			if problem ~= nil then
				error(problem, 0)
			end
		end

		-- ---- implementations ----------------------------------------------
		local function buildFacet()
			local list = Facet.newVirtualList(Facet, core, {
				id = "Rows",
				rows = rowsSignal,
				key = function(item: any)
					return item.id
				end,
				rowHeight = rowHeight,
				rowGap = rows.ROW_GAP,
				viewportHeight = listHeight,
				overscan = if settings.faultWindow then #rowsSignal:get() else rows.OVERSCAN,
				selection = "single",
				cell = function(item: any, cellCtx: any)
					return rows.cell(Facet, core, item, {
						scope = cellCtx.scope,
						compact = isCompact:get(),
						splitControls = splitControls:get(),
						-- the row creates its value/toggle signals lazily; they outlive the
						-- CELL scope on purpose and die with the DATA scope instead
						ownerScope = dataScope,
						provider = provider,
						values = values,
						toggles = toggles,
						failImage = settings.resourceState == "failing",
					})
				end,
			})
			local screen = Facet.UI.Screen({
				id = "PerfWorkload",
				padding = SCREEN_PADDING,
				gap = SCREEN_GAP,
				children = {
					Facet.UI.Text({
						id = "Head",
						text = `Facet · {#rowsSignal:get()} rows`,
						textSize = 14,
					}),
					list.blueprint,
				},
			})
			local handle = ctx.presenter.present(screen, {
				recycleInstances = settings.recycle == true,
				incrementalLayout = settings.incremental == true,
			})
			local unbindScroll: any = nil
			if list.bindNativeScroll ~= nil and handle.controller ~= nil then
				local ok, result = pcall(list.bindNativeScroll, handle.controller)
				if ok then
					unbindScroll = result
				end
			end
			return {
				kind = "facet",
				list = list,
				handle = handle,
				controller = handle.controller,
				dispose = function()
					if unbindScroll ~= nil then
						unbindScroll()
					end
					ctx.presenter.dismiss(handle)
					list.dispose()
				end,
			}
		end

		local function buildNative()
			assert(
				host.nativeList ~= nil,
				"[perf lab] the raw-Roblox reference is a HOST seam (examples/performance/client/native_list.luau); "
					.. "it is unavailable in this environment, so the native implementation cannot be mounted here"
			)
			local built = host.nativeList.mount({
				items = rowsSignal:get(),
				rowHeight = rows.ROW_HEIGHT,
				rowGap = rows.ROW_GAP,
				imageSize = rows.IMAGE_SIZE,
				viewportHeight = viewportH(),
				overscan = rows.OVERSCAN,
			})
			return {
				kind = "native",
				native = built,
				mountedRows = built.mountedRows,
				dispose = built.dispose,
			}
		end

		local function unmount()
			if mounted == nil then
				return false
			end
			profile.span("reset", function()
				mounted.dispose()
			end)
			mounted = nil
			return true
		end

		local function mount()
			assert(
				mounted == nil,
				"[perf lab] refusing to mount a second implementation: exactly one may be live during a capture "
					.. "(PL-5). Call `unmount` or `reset` first."
			)
			if settings.implementation == "none" then
				return { mounted = "none" }
			end
			-- synchronous: `mount` builds and presents without waiting for a frame, so a
			-- scope here is legitimate (see the no-yield rule in src/core/profile.luau)
			profile.span("scenario", function()
				if settings.implementation == "native" then
					mounted = buildNative()
				else
					mounted = buildFacet()
				end
			end)
			raiseOverlay()
			ctx.presenter.refresh()
			-- A FAILED MOUNT MUST NOT LEAVE THE LAB WEDGED. Found by the negative
			-- control: raising the bounded-window error straight out of `mount` left
			-- the broken tree assigned to `mounted`, so the very next `mount` refused
			-- with "a second implementation" and the operator's only route back was a
			-- Play restart. A stress tool that cannot recover from the fault it is
			-- built to detect is not usable on a phone.
			local problem = windowProblem("mount") or layoutProblem("mount")
			if problem ~= nil then
				unmount()
				error(problem, 0)
			end
			return {
				mounted = settings.implementation,
				mountedRows = mountedRowCount(),
				windowBound = windowBound(),
				logicalRows = #rowsSignal:get(),
			}
		end

		-- REBUILDING THE DATASET MUST UNMOUNT FIRST (reactive-runtime review, RR-9).
		--
		-- The per-row value/toggle signals are owned by `dataScope`, and disposing it
		-- while rows are still mounted is a use-after-dispose: `UI.ForEach` does not
		-- rebuild a row whose KEY is unchanged, and the ids are `r{i}` — stable across
		-- a seed or content change. Measured: 60 mounted rows, then the declared
		-- `localeSwap` pass, and 18 signals were disposed with zero cells rebuilt.
		--
		-- It also meant `localeSwap` swapped no visible text and timed a no-op, which
		-- is the worse half: a pass that measures nothing while reporting a number.
		--
		-- Unmounting first retires the rows that hold those signals, so the fresh
		-- dataset builds fresh cells. `wasMounted` restores the caller's state, and
		-- `ramp` (which unmounts itself first) is unaffected.
		-- ROTATION REBUILDS THE ROWS (found on a real device, 2026-08-05: mount in
		-- landscape, rotate to portrait, rows paint over each other).
		--
		-- `compact` is read ONCE when a cell is built, and `UI.ForEach` never rebuilds a
		-- row whose key is unchanged — so rows built one-line in landscape survived a
		-- rotation into a 359px-wide, 152px-tall portrait slot. The `rowHeight` memo
		-- updated; the cells did not. Twelve layout findings.
		--
		-- This is the same hazard the reactive-runtime review named as RR-9 (a `:get()`
		-- at build time inside a keyed list), in a second place. `UI.When` cannot switch
		-- the arrangement here because it has no `elseView` and the row's HEIGHT has to
		-- move with it anyway — a VirtualList windows on a fixed pitch, so the height
		-- and the arrangement must stay one decision.
		--
		-- So the lab remounts, which is exactly what it already does when the dataset
		-- changes. A remount is cheap here and it is honest: the arrangement genuinely
		-- is a different tree.
		local remountForArrangement: () -> ()
		local lastRemountError: string? = nil

		local function rebuildDataset()
			local wasMounted = mounted ~= nil
			if wasMounted then
				unmount()
			end
			items = dataset.build({ count = settings.rows, seed = settings.seed, content = settings.content })
			-- a new dataset is a new population: the old per-row signals are released
			-- with their scope, and a fresh child takes over. Clearing the tables
			-- alone would leave one live signal per retired row.
			dataScope:dispose()
			dataScope = labScope:child("perf-lab-data")
			values = {}
			toggles = {}
			rowsSignal:set(items)
			if wasMounted then
				mount()
			end
		end

		-- ---- named passes ---------------------------------------------------
		-- Each returns its own timing and is recorded SEPARATELY in the pass log:
		-- the plan requires scroll, focus, selection, churn and resource work to be
		-- labeled apart, because a blended number cannot be attributed to any of
		-- them. Each is wrapped in the driver's `Facet/scenario` scope so a
		-- MicroProfiler capture can find the workload inside the frame.
		local passes: { [string]: (payload: string?) -> any } = {}

		-- NO SPAN HERE (Roblox-platform review 2026-08-04, MAJOR-1). This used to open a
		-- `Facet/scenario` scope around the whole pass — and a pass body waits a
		-- Heartbeat once per frame, sixty times, INSIDE the scope. `debug.profilebegin`
		-- opens a scope on the executing thread, so a yield leaves the enter and the
		-- leave in different frames, and this module's counters cannot see it: they
		-- count Lua call sites, so `balanced` read true for a stack that was not.
		--
		-- The per-frame `Facet/scenario` scope in the lab bootstrap stays, because that
		-- one wraps `presenter.tick` + `presenter.refresh` and does not yield. A pass is
		-- timed with the wall clock instead, which is what its numbers were anyway.
		local function timed(name: string, body: () -> any): any
			local t0 = clock()
			local detail = body()
			local ms = (clock() - t0) * 1000
			local record = { pass = name, ms = ms, detail = detail, at = clock() }
			table.insert(passLog, record)
			return record
		end

		-- p50/p95/worst over a sample list. A "worst" alone is one unlucky frame and
		-- makes two captures of the same workload look different when they are not —
		-- the loop's compare step needs a distribution, not an extremum.
		local function summarize(samples: { number }): any
			if #samples == 0 then
				return { measured = false }
			end
			local sorted = table.clone(samples)
			table.sort(sorted)
			local function pct(p: number): number
				return sorted[math.clamp(math.ceil(p * #sorted), 1, #sorted)]
			end
			local sum = 0
			for _, v in sorted do
				sum += v
			end
			return {
				measured = true,
				n = #sorted,
				p50_ms = pct(0.5),
				p95_ms = pct(0.95),
				worst_ms = sorted[#sorted],
				mean_ms = sum / #sorted,
			}
		end

		--[[ HOW MANY TIMES A FRAMEWORK PHASE SCOPE OPENED, since the session started.

			`src/core/profile.luau` counts every `Facet/<phase>` span whenever
			scopes are on, which is what the lab boots with. A pass takes the count
			before and after and reports the difference, which makes "how many
			solves did this cost" a FIELD rather than something read out of a binary
			MicroProfiler dump by hand.

			NIL-SAFE rather than asserted: `cleanCapture` deliberately turns scopes
			OFF, and a pass that threw in that configuration would break the one
			measurement a clean capture exists to take. Zero means "not counted",
			never "did not happen" — so a count is only ever quoted as a DELTA
			alongside the ms it is explaining. ]]
		local function scopeCount(key: string): number
			local ok, counters = pcall(profile.counters)
			if not ok or counters == nil or counters.byScope == nil then
				return 0
			end
			return (counters.byScope :: any)[key] or 0
		end

		local function requireList(): any
			assertNoRemountError()
			assert(mounted ~= nil, "[perf lab] no implementation is mounted; call `mount` first")
			return mounted
		end

		-- A LIVE SCROLL TAKES A FRAME (found live, 2026-08-04). `list.scrollTo`
		-- writes the engine's CanvasPosition; the windowing mirror is fed by the
		-- engine's own property-changed signal, which lands on the NEXT frame. A
		-- driver that wrote and immediately measured was therefore scrolling
		-- nothing: 480 Studio scroll steps moved the window not at all (core
		-- counters and the GuiObject census were byte-identical throughout), while
		-- the same code headless looked fine because the fake target echoes
		-- synchronously. The instrument was measuring an idle screen and reporting
		-- it as steady scrolling.
		--
		-- `telemetry.step()` waits one Heartbeat. Headless it is a no-op stub and
		-- the fake echo has already happened, so both worlds do the same thing.
		-- Split in two, because the two halves are different quantities and only one
		-- of them is Facet's. `scrollWrite` is the framework/engine WRITE; the frame
		-- wait that follows it is the engine's echo latency and belongs to nobody's
		-- budget. Timing them together produced a 26.6ms "worst scroll step" that was
		-- ~17ms of Heartbeat and would have been reported as framework cost.
		local function scrollWrite(y: number)
			local m = requireList()
			if m.kind == "native" then
				m.native.scrollTo(y)
				return
			end
			if m.controller ~= nil and m.list.scrollTo ~= nil then
				m.list.scrollTo(m.controller, y)
			else
				m.list.scrollTop:set(y)
			end
		end

		local function scrollTo(y: number)
			scrollWrite(y)
			-- the engine echo lands on the next frame; headless this is a no-op stub
			-- and the fake target has already echoed
			telemetry.step()
		end

		-- STEADY SCROLL: a constant pixel rate per frame, the way a flick or a held
		-- wheel actually moves a list. One or two rows enter the window per frame,
		-- so this measures re-windowing at the margin — the question "is scrolling
		-- smooth" is really asking about.
		passes.scrollSteady = function(payload: string?)
			return timed("scrollSteady", function()
				local frames = tonumber(payload or "") or 60
				local m = requireList()
				local pitch = rowHeight:get() + rows.ROW_GAP
				local extent = math.max(0, #rowsSignal:get() * pitch - viewportH())
				-- 40px/frame at 60Hz is ~2 400px/s: a brisk flick, and about 0.7 of a
				-- row per frame at this pitch
				local rate = 40
				local y = 0
				local writes, refreshes, totals = {}, {}, {}
				for i = 1, frames do
					y = (y + rate) % math.max(1, extent)
					local t0 = clock()
					scrollWrite(y)
					local writeMs = (clock() - t0) * 1000
					telemetry.step()
					local t1 = clock()
					ctx.presenter.refresh()
					local refreshMs = (clock() - t1) * 1000
					table.insert(writes, writeMs)
					table.insert(refreshes, refreshMs)
					table.insert(totals, writeMs + refreshMs)
					if i % 15 == 0 then
						assertBoundedWindow(`steady scroll frame {i}`)
					end
				end
				return {
					frames = frames,
					pixelsPerFrame = rate,
					rowsPerFrame = rate / pitch,
					scrollWriteMs = summarize(writes),
					reWindowMs = summarize(refreshes),
					stepMs = summarize(totals),
					frameWaitExcluded = true,
					mountedRows = mountedRowCount(),
					windowBound = windowBound(),
					logicalRows = #rowsSignal:get(),
					implementation = m.kind,
					drive = "programmatic-steady",
				}
			end)
		end

		-- SEEK: the whole extent divided by the step count. Every step replaces the
		-- entire mounted window, which is what a scrollbar drag or a jump-to-index
		-- does. Kept as its own pass under its own name rather than deleted: it is a
		-- real interaction and it is where structural cost actually lives.
		passes.scrollSeek = function(payload: string?)
			return timed("scrollSeek", function()
				local steps = tonumber(payload or "") or 60
				local m = requireList()
				local pitch = rowHeight:get() + rows.ROW_GAP
				local extent = math.max(0, #rowsSignal:get() * pitch - viewportH())
				local worstWrite, worstRefresh, worstTotal = 0, 0, 0
				for i = 1, steps do
					local y = (i / steps) * extent
					local t0 = clock()
					scrollWrite(y)
					local writeMs = (clock() - t0) * 1000
					-- NOT TIMED: the engine's canvas echo. It is a frame of wall clock
					-- on the live adapter and zero headless, and attributing it to the
					-- framework would make every live scroll look ~17ms expensive.
					telemetry.step()
					local t1 = clock()
					ctx.presenter.refresh()
					local refreshMs = (clock() - t1) * 1000
					if writeMs > worstWrite then
						worstWrite = writeMs
					end
					if refreshMs > worstRefresh then
						worstRefresh = refreshMs
					end
					if writeMs + refreshMs > worstTotal then
						worstTotal = writeMs + refreshMs
					end
					if i % 10 == 0 then
						assertBoundedWindow(`scroll step {i}`)
					end
				end
				return {
					steps = steps,
					-- the framework's share, split so a regression is attributable
					worstScrollWriteMs = worstWrite,
					worstReWindowMs = worstRefresh,
					worstStepMs = worstTotal,
					frameWaitExcluded = true,
					mountedRows = mountedRowCount(),
					windowBound = windowBound(),
					logicalRows = #rowsSignal:get(),
					implementation = m.kind,
					drive = "programmatic-seek",
					note = "every step replaces the whole mounted window. Pointer-wheel and touch-pan rows are NATIVE "
						.. "input and are driven through the Studio input path, then read back through `scrollObserve`",
				}
			end)
		end

		-- The NATIVE-input half. A scenario cannot synthesize a wheel or a touch
		-- pan (contract §3: a scriptable call proves the downstream path only), so
		-- this records the engine's canvas position before and after an externally
		-- injected gesture and reports what the engine actually did.
		passes.scrollObserve = function(payload: string?)
			local m = requireList()
			local before = if m.kind == "native" then m.native.canvasPosition() else m.list.scrollTop:get()
			return {
				pass = "scrollObserve",
				armedAt = clock(),
				canvasBefore = before,
				mountedRows = mountedRowCount(),
				scrollPath = if m.kind == "facet" and m.list.scrollPath ~= nil then m.list.scrollPath() else nil,
				evidence = "engine-observed; pair with an injected wheel/pan and re-read",
				payload = payload,
			}
		end

		passes.focusTraverse = function(payload: string?)
			return timed("focusTraverse", function()
				local steps = tonumber(payload or "") or 24
				local m = requireList()
				assert(
					m.kind == "facet",
					"[perf lab] focus traversal is a Facet pass; the reference has no focus graph"
				)
				local list = m.list
				local all = rowsSignal:get()
				-- SAME FRAME RULE AS `scrollTo`. `focusKey` issues the keep-visible
				-- scroll write and answers `pathOf(key)` immediately, which is nil
				-- while the row is still off-window — and on the live engine it is
				-- ALWAYS still off-window, because the canvas echo has not landed.
				-- The first live run therefore reported 0 of 24 rows visited for a
				-- traversal that was working. Step the frame, then ask.
				local visited = 0
				for i = 1, steps do
					local item = all[((i - 1) * 7) % #all + 1]
					list.focusKey(item.id)
					telemetry.step()
					ctx.presenter.refresh()
					if list.pathOf(item.id) ~= nil then
						visited += 1
					end
				end
				assertBoundedWindow("focusTraverse")
				return {
					steps = steps,
					visited = visited,
					mountedRows = mountedRowCount(),
					evidence = "downstream-action",
					note = "focusKey is the CONTROL API. Raw Tab/arrow delivery is a native-input row driven through "
						.. "the Studio keyboard path and read back from the runner's keyLog",
				}
			end)
		end

		passes.keepVisible = function()
			return timed("keepVisible", function()
				local m = requireList()
				assert(m.kind == "facet", "[perf lab] keep-visible is a Facet pass")
				local all = rowsSignal:get()
				local target = all[math.max(1, math.floor(#all * 0.75))]
				m.list.focusKey(target.id)
				telemetry.step()
				ctx.presenter.refresh()
				local path = m.list.pathOf(target.id)
				assertBoundedWindow("keepVisible")
				return {
					key = target.id,
					path = path,
					scrollTop = m.list.scrollTop:get(),
					mountedRows = mountedRowCount(),
				}
			end)
		end

		passes.selectRow = function(payload: string?)
			return timed("selectRow", function()
				local count = tonumber(payload or "") or 20
				local m = requireList()
				local all = rowsSignal:get()
				for i = 1, count do
					local item = all[((i - 1) * 13) % #all + 1]
					if m.kind == "native" then
						m.native.select(item.id)
					else
						m.list.select(item.id)
					end
					ctx.presenter.refresh()
				end
				return { selections = count, implementation = m.kind }
			end)
		end

		-- WHAT A MOUNTED, UNTOUCHED SURFACE COSTS PER FRAME (added 2026-08-05).
		--
		-- Every other pass drives something. `idle-baseline` measures the place with
		-- NOTHING mounted, which answers a different question. Neither of them answers
		-- the one that decides whether a HUD is affordable on a low-end device: a game
		-- screen is mounted for the whole session and interacted with for a fraction of
		-- it, so the per-frame cost of a surface that nobody is touching is the cost
		-- that is paid ~all the time.
		--
		-- It was worth asking: before the focus-map cache (L-27) an idle frame re-derived
		-- the entire focus map for every presented surface, so a screen doing nothing at
		-- all cost more than half the device budget.
		--
		-- The host frame connection does the work; this pass only waits and measures, so
		-- the number is the real per-frame cost of `tick` + `refresh` with no driver on
		-- top of it.
		passes.idle = function(payload: string?)
			return timed("idle", function()
				local frames = math.clamp(math.floor(tonumber(payload or "") or 120), 10, 600)
				requireList()
				local samples = table.create(frames)
				for i = 1, frames do
					local t0 = clock()
					telemetry.step()
					samples[i] = (clock() - t0) * 1000
				end
				return {
					frames = frames,
					mountedRows = mountedRowCount(),
					-- the frame INTERVAL is not the frame WORK: this pass waits a frame
					-- and reports the wall clock around the wait, so the figure includes
					-- the engine's own frame. It is here for the SCOPE breakdown beside
					-- it (`scopes:idle`), which is where the Facet share is legible.
					intervalMs = summarize(samples),
				}
			end)
		end

		--[[ MOTION FLIGHT — what an interpolating property costs per frame, and what
			the SIZE half costs on top of the position half (game-director question,
			2026-08-14; docs/plans/with-animation-size.md).

			`presenter.withAnimation` paints a change over a spring instead of
			landing it instantly, so for the length of a flight the framework does
			per-frame work it does not otherwise do. Round 3 taught it to animate
			SIZE as well as position, and the reasonable worry is that a second
			interpolated number per node is a second per-frame cost. This pass is how
			that stops being a worry and becomes a number.

			IT MOUNTS ITS OWN SURFACE, and its workload declares `implementation =
			"none"` so nothing else is mounted. A flight's cost is
			`records x subtree size`; measuring it through the virtual list would
			blend it with windowing — which is what made the first MicroProfiler
			capture read as `mount` when the question was about scrolling.

			FOUR ARMS, A/B/C/A', and the last one is not a formality. Three round-2
			"improvements" evaporated when measured properly, so the harness's own
			same-arm spread is on the page BEFORE any delta is claimed: A and A' are
			the same measurement taken twice, and a B-vs-C difference smaller than
			|A - A'| is noise wearing a result's clothes.

			  A   idle       nothing flying; the floor
			  B   position   the rows RE-ORDER — N records, position delta only
			  C   both       the rows RESIZE together — N records carrying BOTH
			  A'  idle       A again

			Both flight arms are sampled only while records are actually live, so a
			settled spring cannot dilute the number with idle frames.

			TIERS (standing rule 3), AND THE HEADLESS ONE IS WEAKER THAN IT LOOKS.
			The lab harness supplies `telemetry.clock` as a MONOTONIC STUB that
			advances a fixed 1 ms per call (tests/perf_lab.spec's `newHarness`), so
			under Lune every `*Ms` field here is synthetic and identical across arms
			by construction. Headless, only the COUNTS mean anything — records,
			flight frames, arms present — and that is what the spec asserts. The
			timings are real only in Studio, inside the lab bootstrap's per-frame
			`Facet/scenario` scope, where they are real engine work with real
			instance counts. Neither tier is a device claim; that needs a physical
			run. Reading a headless `p50_ms` off this pass as a performance result
			would be the `the-solver-already-told-you` mistake in reverse.

			NO YIELD INSIDE A SAMPLE. `telemetry.step()` waits a Heartbeat and the lab
			client binds `motion_driver`, so a sample loop that waited would time the
			engine's frame rather than the framework's work — and would leave a
			profiler scope open across frames (MAJOR-1, above). Each sample times this
			module's own non-yielding `tick` + `refresh`, which is the quantity the
			question is about and the one quantity that means the same thing in both
			tiers. ]]
		local MOTION_FLIGHT_ROWS = 24
		local MOTION_FLIGHT_FRAME = 1 / 60

		passes.motionFlight = function(payload: string?)
			return timed("motionFlight", function()
				local cap = math.clamp(math.floor(tonumber(payload or "") or 90), 20, 300)
				local initial = table.create(MOTION_FLIGHT_ROWS)
				for i = 1, MOTION_FLIGHT_ROWS do
					initial[i] = i
				end
				local order = core:signal(initial)
				local tall = core:signal(false)
				-- the AUTHORED PAINT triple (ADR-0026), one signal so arm D moves all
				-- three on every row at once and its record count matches B's and C's
				local lit = core:signal(false)
				local rowOpacity = core:memo(function(use: any)
					return if use(lit) then 0.4 else 1
				end)
				local rowScale = core:memo(function(use: any)
					return if use(lit) then 0.9 else 1
				end)
				local rowRotation = core:memo(function(use: any)
					return if use(lit) then 6 else 0
				end)
				-- ONE height memo shared by every row, so arm C resizes all N at once
				-- and its record count matches arm B's rather than being a smaller
				-- experiment wearing the same axis
				local rowDim = core:memo(function(use: any)
					return { type = "fixed", px = if use(tall) then 44 else 28 }
				end)
				local U = Facet.UI
				local handle = ctx.presenter.present(U.Screen({
					id = "MotionFlight",
					padding = 8,
					gap = 4,
					children = {
						U.ForEach({
							id = "Flight",
							items = order,
							key = function(item: any): string
								return `r{item}`
							end,
							row = function(item: any)
								-- A ZStack RATHER THAN A VStack, and the change is the
								-- measurement: an authored `opacity` is a fade-group
								-- declaration, so every row here is a real `CanvasGroup`
								-- with its own render buffer. That is the cost the paint
								-- arm exists to price, and hiding it behind a wrapper
								-- would have measured a cheaper thing than the one an
								-- author gets. Arms B and C were re-baselined by it on
								-- 2026-08-14; a one-child ZStack arranges like a one-child
								-- VStack, and A/A' brackets the whole run either way.
								return U.ZStack({
									id = "Row",
									padding = 0,
									height = rowDim,
									opacity = rowOpacity,
									scale = rowScale,
									rotation = rowRotation,
									children = { U.Text({ id = "L", text = `row {item}`, textSize = 12 }) },
								})
							end,
						}),
					},
				}))

				local function sampleIdle(n: number): { number }
					local out = table.create(n)
					for i = 1, n do
						local t0 = clock()
						ctx.presenter.tick(MOTION_FLIGHT_FRAME)
						ctx.presenter.refresh()
						out[i] = (clock() - t0) * 1000
					end
					return out
				end

				-- sample ONLY while records are live: a spring that settled at frame 30
				-- would otherwise contribute 60 idle frames to a "flight" p50
				local function sampleFlight(mutate: () -> ()): ({ number }, number)
					ctx.presenter.withAnimation("container", mutate)
					local seeded = ctx.presenter.animationRecordCount()
					local out = {}
					for _ = 1, cap do
						if ctx.presenter.animationRecordCount() == 0 then
							break
						end
						local t0 = clock()
						ctx.presenter.tick(MOTION_FLIGHT_FRAME)
						ctx.presenter.refresh()
						table.insert(out, (clock() - t0) * 1000)
					end
					-- leave the channel clean for the next arm
					for _ = 1, 240 do
						if ctx.presenter.animationRecordCount() == 0 then
							break
						end
						ctx.presenter.tick(MOTION_FLIGHT_FRAME)
						ctx.presenter.refresh()
					end
					return out, seeded
				end

				--[[ THE OFF-PATH CONTROL (ADR-0026 Decision 9). "A surface that authors
					none of these must not pay" is a claim, and a claim measured against
					nothing is a comment. This is the same tree with the three props
					simply absent — plain VStack rows, no fade group, no composition —
					sampled idle exactly as arm A is.

					Read `offPathDeltaMs` ONLY against `harnessSpreadMs`. It is the price
					of DECLARING the triple and sitting still, and it is not zero by
					construction: an authored opacity buys a CanvasGroup per row. What
					must be ~zero is the other direction — the plain surface paying for a
					feature it never used — and that is what a delta at or below the
					spread says. ]]
				local function samplePlainIdle(n: number): { number }
					local plainOrder = core:signal(initial)
					local plain = ctx.presenter.present(U.Screen({
						id = "MotionFlightPlain",
						padding = 8,
						gap = 4,
						children = {
							U.ForEach({
								id = "Flight",
								items = plainOrder,
								key = function(item: any): string
									return `r{item}`
								end,
								row = function(item: any)
									return U.VStack({
										id = "Row",
										padding = 0,
										gap = 0,
										height = { type = "fixed", px = 28 },
										children = { U.Text({ id = "L", text = `row {item}`, textSize = 12 }) },
									})
								end,
							}),
						},
					}))
					local out = table.create(n)
					for i = 1, n do
						local t0 = clock()
						ctx.presenter.tick(MOTION_FLIGHT_FRAME)
						ctx.presenter.refresh()
						out[i] = (clock() - t0) * 1000
					end
					ctx.presenter.dismiss(plain)
					return out
				end

				local ok, result = pcall(function()
					local idleA = sampleIdle(cap)
					local reversed = table.create(MOTION_FLIGHT_ROWS)
					for i = 1, MOTION_FLIGHT_ROWS do
						reversed[i] = initial[MOTION_FLIGHT_ROWS + 1 - i]
					end
					local posSamples, posRecords = sampleFlight(function()
						order:set(reversed)
					end)
					local bothSamples, bothRecords = sampleFlight(function()
						tall:set(true)
					end)
					-- ARM D: the AUTHORED PAINT triple only. No rect changes at all, so
					-- whatever this costs is the composition and the engine writes it
					-- produces, with the solver's four numbers held still.
					local paintSamples, paintRecords = sampleFlight(function()
						lit:set(true)
					end)
					local idleB = sampleIdle(cap)
					local plain = summarize(samplePlainIdle(cap))
					local a1, a2 = summarize(idleA), summarize(idleB)
					local spread = if a1.measured and a2.measured then math.abs(a1.p50_ms - a2.p50_ms) else 0
					return {
						rows = MOTION_FLIGHT_ROWS,
						-- READ THIS FIRST: any B-vs-C delta smaller than this is noise
						harnessSpreadMs = spread,
						idleMs = a1,
						idleRepeatMs = a2,
						positionMs = summarize(posSamples),
						positionAndSizeMs = summarize(bothSamples),
						positionRecords = posRecords,
						positionAndSizeRecords = bothRecords,
						positionFlightFrames = #posSamples,
						positionAndSizeFlightFrames = #bothSamples,
						paintMs = summarize(paintSamples),
						paintRecords = paintRecords,
						paintFlightFrames = #paintSamples,
						plainIdleMs = plain,
						offPathDeltaMs = if a1.measured and plain.measured then a1.p50_ms - plain.p50_ms else 0,
						note = "arm B re-orders (position delta only); arm C resizes every row "
							.. "(both halves on the same records). The C-minus-B difference is the "
							.. "marginal cost of the size half; arm D moves the AUTHORED paint "
							.. "triple (opacity/scale/rotation, ADR-0026) with every rect held "
							.. "still. plainIdleMs is the same tree DECLARING none of the three, "
							.. "so offPathDeltaMs is what a declaration costs at rest. Compare "
							.. "every one of these against harnessSpreadMs before calling it a "
							.. "cost. Lune = regression signal, Studio = real engine, device = "
							.. "the only device claim.",
					}
				end)
				ctx.presenter.dismiss(handle)
				if not ok then
					error(result, 0)
				end
				return result
			end)
		end

		--[[ WHAT THE PER-CONTROL SENSORY HOOK COSTS (director ask 2026-08-13).

			`UI.sensoryFeedback(bp, { activation = … })` is a CASCADE: `mount.luau`
			resolves it down the tree, so a declaration on a page root touches every
			node under it, and the renderer publishes the resolved verb to the
			adapter for every activatable control. Two cost questions follow, and
			neither is answerable by reading the code:

			  · what does a tree that declares NOTHING pay? (it must be ~zero, or a
			    feature nobody uses is charging every screen in the framework);
			  · what does ONE declaration on a root cost when it reaches N nodes,
			    versus N declarations on N leaves?

			THREE ARMS OVER AN IDENTICAL TREE. Same class, same count, same content,
			same presenter, same sequence — only the declaration differs, which is
			the only way a difference means the declaration. A and A' bracket the
			run so the harness's own same-arm spread is stated BEFORE any delta:
			round 2 lost three "improvements" to exactly that omission.

			PRESSES ARE MEASURED SEPARATELY from mounts, because they are different
			questions: the mount half is the cascade, the press half is one field
			read and one bus emission per activation. `driveActivate` is the
			adapter's own dev-drive seam into the SAME closure a real press reaches,
			so the press arm is not a private code path wearing the name of one.

			Tier discipline unchanged: Lune = regression signal, Studio (this lab) =
			real engine work with real Instance counts, a physical device = the only
			thing that supports a device claim.
		]]
		local SENSORY_ROWS = 120

		passes.sensoryCascade = function(payload: string?)
			return timed("sensoryCascade", function()
				local presses = math.clamp(math.floor(tonumber(payload or "") or 60), 5, 400)
				local U = Facet.UI

				-- one arm: `decorate` decides where (if anywhere) the declaration goes
				local function arm(decorate: string): any
					local children = table.create(SENSORY_ROWS)
					for i = 1, SENSORY_ROWS do
						local button = U.Button({ id = `B{i}`, label = `row {i}` })
						children[i] = if decorate == "leaves"
							then U.sensoryFeedback(button, { activation = "commit" })
							else button
					end
					local page = U.ScrollView({
						id = "Page",
						axis = "y",
						gap = 2,
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = children,
					})
					local screen = U.Screen({ id = "SensoryCascade", padding = 8, children = { page } })
					if decorate == "root" then
						screen = U.sensoryFeedback(screen, { activation = "commit" })
					end
					local before = telemetry.memory()
					local t0 = clock()
					local handle = ctx.presenter.present(screen)
					ctx.presenter.refresh()
					local mountMs = (clock() - t0) * 1000
					local after = telemetry.memory()

					-- the press half, through the adapter's own activate closure
					local heard = 0
					local unsubscribe = handle.onFeedback(function()
						heard += 1
					end)
					local samples = table.create(presses)
					local drove = 0
					for i = 1, presses do
						local path = `/SensoryCascade/Page/B{((i - 1) % SENSORY_ROWS) + 1}`
						local t1 = clock()
						local fired = ctx.adapter.driveActivate ~= nil and ctx.adapter.driveActivate(path) or false
						samples[i] = (clock() - t1) * 1000
						if fired then
							drove += 1
						end
					end
					unsubscribe()
					local guiObjects = telemetry.instances().guiObjects
					ctx.presenter.dismiss(handle)
					ctx.presenter.refresh()
					return {
						mountMs = mountMs,
						pressMs = summarize(samples),
						pressesDriven = drove,
						eventsHeard = heard,
						guiObjects = guiObjects,
						luaHeapKbDelta = if type(after.luaHeapKb) == "number"
								and type(before.luaHeapKb) == "number"
							then after.luaHeapKb - before.luaHeapKb
							else nil,
					}
				end

				local a = arm("none")
				local root = arm("root")
				local leaves = arm("leaves")
				local aPrime = arm("none")
				return {
					rows = SENSORY_ROWS,
					presses = presses,
					-- READ THIS FIRST: any arm-to-arm delta smaller than this is noise
					harnessSpreadMs = math.abs(a.mountMs - aPrime.mountMs),
					undeclared = a,
					undeclaredRepeat = aPrime,
					declaredOnRoot = root,
					declaredOnEveryLeaf = leaves,
					note = "identical tree in all four arms; only the declaration moves. `undeclared` is the "
						.. "off-path cost every screen in the framework pays and must sit inside "
						.. "harnessSpreadMs of `undeclaredRepeat`. `eventsHeard` proves the presses "
						.. "landed — an arm that drove nothing would otherwise report a very fast press. "
						.. "Lune = regression signal, this lab = real engine, device = the only device claim.",
				}
			end)
		end

		--[[ WHAT A VARIABLE-EXTENT WINDOW COSTS AGAINST THE UNIFORM ONE IT REPLACES.

			`src/virtual_extents.luau` (2026-08-14) gave `newVirtualList` a second
			windowing arithmetic: a prefix sum, O(N) to build per data change and
			O(log N) to query, chosen at build time by `itemExtent` being a FUNCTION.
			The uniform path was deliberately left byte-identical, because it is the
			baseline every instance-count and frame-time number in
			`artifacts/performance-stress-places/optimization-log.md` was measured
			against. Nothing in this lab exercised the new path at all — every
			workload above windows by one number — so the feature shipped with no
			perf row of its own. This is that row.

			FOUR ARMS OVER ONE TREE, and the middle one is the point:

			  A  uniform   — `itemExtent` is a number. The pre-feature arithmetic.
			  A' uniform   — the SAME arm again. Its distance from A is the harness's
			                 own spread, and it is reported FIRST because three
			                 separate rounds this month lost an "improvement" that
			                 turned out to sit inside a control band nobody had
			                 measured.
			  B  variable, FLAT — `itemExtent` is a function returning the SAME px for
			                 every row. Identical picture, identical window, identical
			                 rects; the only difference is that the list built and
			                 queried a prefix-sum index instead of dividing. B-minus-A
			                 is therefore the price of the MACHINERY with the feature's
			                 benefit subtracted out, which is the number a shipped
			                 uniform list would pay if the paths were ever merged.
			  C  variable, RAGGED — extents of 1..4 text lines, which is the feature.
			                 C-minus-B is what raggedness itself costs.

			THE ARM IS PROVEN TO HAVE TAKEN THE PATH IT CLAIMS. `dump().itemExtentMode`
			is asserted per arm ("uniform" / "variable"). An A/B whose two arms
			silently ran the same code is the "check that proves nothing" class this
			project has a lesson about, and here it is one typo away: `itemExtent`
			accepts a number, a Readable AND a function, and only the third switches
			arithmetic.

			TWO DATA-CHANGE MEASUREMENTS, BECAUSE THE INDEX IS CACHED. The list keys
			its index on the extents themselves, so an edit that leaves every extent
			where it was returns the SAME index object and rebuilds nothing — but the
			O(N) extent WALK still runs, because that is how it finds out. So:

			  · `sameCountEditMs` — the common case (a value ticks, a row is renamed).
			    Walk, no rebuild.
			  · `growEditMs` — one row appended. The cache misses by construction, so
			    this is the walk PLUS the prefix-sum build, and it is the number that
			    answers "does the index build bite on a large ragged list".

			THE ROW PAINTS EXACTLY WHAT IT DECLARES. `extentFor` is called by the row
			blueprint and by `itemExtent`, so the declared slot and the painted content
			cannot drift — the painted-at-a-size-nobody-measured family
			(`docs/lessons/`) is the defect a lying `itemExtent` produces, and it would
			read here as a fast arm rather than as a broken one.

			Tier discipline unchanged: Lune = regression signal only, this lab under
			Studio = the real engine, a physical device = the only device claim. ]]
		local EXTENT_ROWS = 2000
		local EXTENT_LINE_H = 16
		local EXTENT_PAD = 4
		local EXTENT_GAP = 2
		-- ragged but DETERMINISTIC and seed-free: the same row is the same height in
		-- Lune, in Studio and on the device, which is what makes two captures
		-- comparable at all
		local function extentLines(index: number): number
			return 1 + (index * 7) % 4
		end
		local function extentFor(lines: number): number
			return 2 * EXTENT_PAD + lines * EXTENT_LINE_H + (lines - 1) * EXTENT_GAP
		end
		local EXTENT_UNIFORM_PX = extentFor(1)

		--[[ `frames` or `frames/reps` — the SECOND number is why this helper exists.

			Every sampled quantity in this lab is quoted as a p50 over n, and the
			first cut of the two collection passes hard-coded n. Measured in Studio
			2026-08-14 at n=8, the A/A control spread on the index-build arm was
			**0.49 ms against a ~2.5 ms number** — 20%, which is larger than the
			effect being looked for. An operator who cannot raise n cannot get out of
			that hole, and a device is noisier than a desktop, not quieter. ]]
		local function framesAndReps(payload: string?, defaultFrames: number, defaultReps: number): (number, number)
			local f, r = string.match(payload or "", "^%s*(%d*)%s*/%s*(%d+)%s*$")
			local frames = math.clamp(math.floor(tonumber(f or payload or "") or defaultFrames), 10, 300)
			local reps = math.clamp(math.floor(tonumber(r or "") or defaultReps), 1, 200)
			return frames, reps
		end

		--[[ THE TWO NAMED LEVERS' PASSES, installed here because this is the first
			point at which every helper they share with this file exists.

			They are handed the SAME `timed`, `summarize`, `scopeCount`, `framesAndReps`
			and `viewportH` this file uses, rather than re-deriving any of them, so an
			arm in `levers.luau` and a pass here can never disagree about what a
			millisecond, a percentile or a scope count is. See that file's header for why
			it is a separate module (the 200,000-char live-sync cap) and for what each
			arm isolates. ]]
		leversLib.install({
			Facet = Facet,
			core = core,
			ctx = ctx,
			labScope = labScope,
			dataset = dataset,
			rows = rows,
			settings = settings,
			telemetry = telemetry,
			timed = timed,
			summarize = summarize,
			scopeCount = scopeCount,
			framesAndReps = framesAndReps,
			viewportH = viewportH,
			passes = passes,
		})

		passes.extentArms = function(payload: string?)
			return timed("extentArms", function()
				local frames, EDITS = framesAndReps(payload, 60, 24)
				local U = Facet.UI

				--[[ ONE ARM. `mode` picks the arithmetic and the raggedness; everything
					else — the item count, the cell class, the viewport, the overscan,
					the presenter, the sequence — is held identical, because a
					difference that is not the only difference is not a measurement. ]]
				local function arm(mode: string): any
					--[[ ...AND THE FIFTH ARM, D, MEASURED (Stage 2, 2026-08-15). It builds
						the SAME ragged rows arm C does — same cell, same line counts, same
						picture — and declares nothing about their heights; the list reads
						each row's own solved rect back through `syncGeometry` and windows on
						it. D-minus-C is therefore the price of NOT PREDICTING: identical
						geometry, one arithmetic, and the difference is the measurement seam
						plus the one `Content` wrapper node a measured row mounts. It is the
						only honest comparison for it — measuring D against A or B would be
						comparing two different pictures, which is what arm C's own note
						below already warns about. ]]
					local measured = mode == "measured"
					local ragged = mode == "ragged" or measured
					local variable = mode ~= "uniform"
					local base = dataset.build({
						count = EXTENT_ROWS,
						seed = settings.seed,
						content = "normal",
					})
					-- OWNED AND DISPOSED. Four arms per pass and the pass loops under
					-- `Profile 1`, so an un-owned signal per arm is a leak the soak row
					-- would eventually report as a framework trend — the exact shape
					-- `dataScope` was added for after a reset left 488 live signals.
					local armScope = labScope:child(`extent-arm-{mode}`)
					local armRows = armScope:own(core:signal(base))
					local function linesOf(item: any): number
						return if ragged then extentLines(item.rank) else 1
					end
					local list = Facet.newVirtualList(Facet, core, {
						id = "ExtentRows",
						rows = armRows,
						key = function(item: any)
							return item.id
						end,
						-- THE ONLY LINE THAT DIFFERS BETWEEN THE ARMS
						itemExtent = if measured
							then "measured"
							elseif variable then function(item: any)
								return extentFor(linesOf(item))
							end
							else EXTENT_UNIFORM_PX,
						-- ...and the one field only arm D takes. The estimate is the
						-- SHORTEST row on purpose: it is the pessimal seed (every row it is
						-- wrong about is wrong in the direction that needs correcting), so
						-- this arm pays the maximum convergence work rather than a flattering
						-- amount of it.
						estimatedItemExtent = if measured then EXTENT_UNIFORM_PX else nil,
						rowGap = 0,
						viewportHeight = listHeight,
						overscan = rows.OVERSCAN,
						cell = function(item: any)
							local n = linesOf(item)
							local children = table.create(n)
							for i = 1, n do
								children[i] = U.Text({
									id = `L{i}`,
									text = if i == 1 then item.name else item.detail,
									textSize = 12,
									lineLimit = 1,
									height = { type = "fixed", px = EXTENT_LINE_H },
								})
							end
							return U.VStack({
								id = "Row",
								padding = EXTENT_PAD,
								gap = EXTENT_GAP,
								width = { type = "fill", weight = 1 },
								children = children,
							})
						end,
					})
					--[[ THE PRESENT OPTIONS COME FROM THE SELECTORS, exactly as
						`buildFacet` takes them. A self-mounting pass that presents
						with no options silently ignores `select:recycle=off` and
						`select:incremental=on` — so the lab would answer an A/B
						question with two identical arms and no error, which is the
						"check that proves nothing" class. Instance recycling is worth
						-32% on a flat scroll (L-27), so this is not a small thing to
						leave un-selectable. ]]
					local handle = ctx.presenter.present(
						U.Screen({
							id = "ExtentArm",
							padding = 0,
							gap = 0,
							children = { list.blueprint },
						}),
						{
							recycleInstances = settings.recycle == true,
							incrementalLayout = settings.incremental == true,
						}
					)
					local unbind: any = nil
					if list.bindNativeScroll ~= nil and handle.controller ~= nil then
						local ok, result = pcall(list.bindNativeScroll, handle.controller)
						if ok then
							unbind = result
						end
					end

					local function finish()
						if unbind ~= nil then
							unbind()
						end
						ctx.presenter.dismiss(handle)
						list.dispose()
						armScope:dispose()
					end

					local ok, result = pcall(function()
						local d0 = list.dump()
						--[[ THE ARM TOOK THE PATH IT SAYS IT DID. One typo in the
							`itemExtent` branch above turns this whole pass into four
							copies of arm A that agree with each other beautifully. ]]
						local wantMode = if measured then "measured" elseif variable then "variable" else "uniform"
						assert(
							d0.itemExtentMode == wantMode,
							`[perf lab] extent arm '{mode}' wanted itemExtentMode='{wantMode}' and the list `
								.. `reports '{tostring(d0.itemExtentMode)}' — the A/B is measuring one arithmetic twice`
						)
						--[[ ...AND ARM D HAS TO HAVE ACTUALLY CONVERGED, or its numbers are
							a measurement of the estimate. A measured list whose `syncGeometry`
							never landed reports `measuredRows = 0` and looks like a fast, tidy
							uniform list — the "check that proves nothing" shape, in the arm
							whose entire subject is the measuring. ]]
						if measured then
							assert(
								(d0.measuredRows or 0) > 0,
								`[perf lab] extent arm 'measured' has measured NO rows — the geometry seam never `
									.. "landed, so this arm is timing the estimate rather than the feature"
							)
						end

						-- ---- the data-change halves ----------------------------
						-- SAME COUNT: every extent lands where it was, so the index
						-- cache hits and this is the O(N) extent walk alone.
						local sameCount = {}
						for i = 1, EDITS do
							local next_ = table.clone(armRows:get() :: { any })
							local at = ((i - 1) * 97) % #next_ + 1
							local row = table.clone(next_[at])
							row.value = (row.value + 0.01) % 1
							next_[at] = row
							local t0 = clock()
							armRows:set(next_)
							ctx.presenter.refresh()
							table.insert(sameCount, (clock() - t0) * 1000)
							telemetry.step()
						end
						-- GROWING: one row appended, so the extents array is a
						-- different length and the cached index cannot be reused.
						-- This is walk + prefix-sum build.
						local grow = {}
						local arrangeBeforeGrow = scopeCount("arrange")
						for i = 1, EDITS do
							local next_ = table.clone(armRows:get() :: { any })
							local added = table.clone(next_[1])
							added.id = `grow{i}`
							added.rank = #next_ + 1
							table.insert(next_, added)
							local t0 = clock()
							armRows:set(next_)
							ctx.presenter.refresh()
							table.insert(grow, (clock() - t0) * 1000)
							telemetry.step()
						end
						local arrangePerGrow = (scopeCount("arrange") - arrangeBeforeGrow) / EDITS

						-- ---- steady scroll -------------------------------------
						local d1 = list.dump()
						local extent = math.max(1, d1.contentExtent - viewportH())
						local y = 0
						local steps = {}
						for i = 1, frames do
							y = (y + 40) % extent
							local t0 = clock()
							if list.scrollTo ~= nil and handle.controller ~= nil then
								list.scrollTo(handle.controller, y)
							else
								list.scrollTop:set(y)
							end
							local writeMs = (clock() - t0) * 1000
							telemetry.step()
							local t1 = clock()
							ctx.presenter.refresh()
							table.insert(steps, writeMs + (clock() - t1) * 1000)
							if i % 20 == 0 then
								local w = 0
								for _ in list.debugWindow() do
									w += 1
								end
								--[[ THE BOUND IS DERIVED FROM THE ARM'S OWN SMALLEST
									SLOT, not from `rows.expectedWindow` — that helper
									describes the SHARED perf row, and a ragged list's
									worst case is "every visible row is the shortest
									one". A window that grows with the logical
									collection is the regression this exists to catch,
									and under a variable index it is the FIRST thing a
									wrong binary search would do. ]]
								local bound = math.ceil(viewportH() / extentFor(1)) + 2 * rows.OVERSCAN + 2
								assert(
									w <= bound,
									`[perf lab] extent arm '{mode}' is NOT bounded at scroll frame {i}: {w} rows `
										.. `mounted for a {viewportH()}px viewport (bound {bound}, logical `
										.. `{#(armRows:get() :: { any })})`
								)
							end
						end
						local final = list.dump()
						local windowed = 0
						for _ in list.debugWindow() do
							windowed += 1
						end
						-- the same mechanism readout `tableUnified` carries, for the same
						-- reason: `recycle=on/off` is a selector, and a selector whose
						-- effect is invisible is a selector nobody can trust
						local rstats = if handle.controller ~= nil and handle.controller.stats ~= nil
							then handle.controller.stats()
							else nil
						return {
							itemExtentMode = final.itemExtentMode,
							logicalRows = final.totalRows,
							recycling = if rstats == nil
								then { measured = false }
								else {
									measured = true,
									armed = rstats.recycleArmed,
									parked = rstats.parked,
									parkRefused = rstats.parkRefused,
									recycled = rstats.recycled,
								},
							mountedRows = windowed,
							contentExtent = final.contentExtent,
							sameCountEditMs = summarize(sameCount),
							growEditMs = summarize(grow),
							arrangePerGrow = arrangePerGrow,
							scrollStepMs = summarize(steps),
						}
					end)
					finish()
					if not ok then
						error(result, 0)
					end
					return result
				end

				local a = arm("uniform")
				local aPrime = arm("uniform")
				local flat = arm("flat")
				local ragged = arm("ragged")
				local measuredArm = arm("measured")
				local function spread(x: any, y: any, key: string): number
					if not x[key].measured or not y[key].measured then
						return 0
					end
					return math.abs(x[key].p50_ms - y[key].p50_ms)
				end
				return {
					rows = EXTENT_ROWS,
					frames = frames,
					edits = EDITS,
					--[[ READ THESE TWO FIRST. Any arm-to-arm delta smaller than the
						matching spread is noise, and saying so before the deltas is
						the only thing that stops the next reader quoting one. ]]
					harnessSpreadScrollMs = spread(a, aPrime, "scrollStepMs"),
					harnessSpreadGrowMs = spread(a, aPrime, "growEditMs"),
					uniform = a,
					uniformRepeat = aPrime,
					variableFlat = flat,
					variableRagged = ragged,
					measuredRagged = measuredArm,
					note = "A/A' = the same uniform arm twice; B (variableFlat) is the prefix-sum index over "
						.. "IDENTICAL extents, so B-minus-A is the machinery with the benefit subtracted out; "
						.. "C (variableRagged) is 1..4-line rows, so C-minus-B is raggedness itself; "
						.. "D (measuredRagged) is arm C's picture with NOTHING declared — same rows, same "
						.. "heights, learned from the solve — so D-minus-C is the price of not predicting. "
						.. "`growEditMs` appends a row, which misses the index cache on purpose and is therefore "
						.. "the O(N) build; `sameCountEditMs` hits it and is the extent walk alone. Every arm "
						.. "asserts its own itemExtentMode and its own window bound. Lune = regression signal, "
						.. "this lab = real engine, device = the only device claim.",
				}
			end)
		end

		--[[ THE UNIFIED COLLECTION, PRICED: windowing + multi-selection + reordering
			in ONE container (`newTable{ virtualized = true }`, 2026-08-14).

			`docs/reference/swiftui-parity.md` §13 carried "no container unifying
			virtualization + reorder + selection" as a durable gap, and closing it
			created a path nothing in this lab touches: every windowing number here
			was taken on `newVirtualList`, whose rows carry no columns, no header, no
			selection SET and no reorder model. A Table row is a different, heavier
			animal, and 2 000 of them windowed is the shape a leaderboard actually is.

			WHAT IS DELIBERATELY NOT IN THIS WORKLOAD, and it is a verified refusal
			rather than an omission: **hosted row actions.** `newTable` refuses
			`virtualized` beside `rowActions` at construction (src/controls/table.luau,
			v1) — Table wraps each actionable row, which is the one thing a windowed
			canvas cannot host. So "virtualization + reordering + selection + hosted
			row actions at once" is not a workload that can be built today; the first
			three are, and this is them.

			THE VERBS ARE MEASURED SEPARATELY FROM THE SCROLL, because they answer
			different questions. Scrolling asks "is the window cheap at the margin".
			Each verb asks "does a MODEL operation still reach a row no window has
			ever held" — reveal, a range selection spanning ~200 unmounted rows, and a
			move — and each is timed as well as asserted, because the interesting
			failure is not that they break but that one of them quietly costs a full
			re-solve of a 2 000-row model.

			A' BRACKETS THE RUN. `idleMs` and `idleRepeatMs` are the same idle sample
			taken before and after everything else, and `harnessSpreadMs` is their
			distance. Nothing below it is a result. ]]
		local TABLE_ROWS = 2000
		-- rows chosen so no first window can contain them: the whole claim is that a
		-- row nobody has mounted is still addressable
		local TABLE_FAR_ROW = 1500
		local TABLE_RANGE_FROM, TABLE_RANGE_TO = 900, 1100

		passes.tableUnified = function(payload: string?)
			return timed("tableUnified", function()
				local frames, reps = framesAndReps(payload, 60, 12)
				local U = Facet.UI
				local base = dataset.build({ count = TABLE_ROWS, seed = settings.seed, content = "normal" })
				-- owned, for the reason `extentArms` records: this pass loops under
				-- `Profile 1`, so one un-owned signal per lap is an unbounded trend
				local passScope = labScope:child("table-unified")
				local tableRows = passScope:own(core:signal(base))
				local function keyOf(rank: number): string
					return `r{rank}`
				end

				local tbl = Facet.newTable(Facet, core, {
					id = "UnifiedRows",
					rows = tableRows,
					key = function(item: any)
						return item.id
					end,
					-- HEADERLESS for the same reason `table_virtualized.luau` is: a
					-- header band is a minMax FLOOR, and this lab runs at phone
					-- viewports where that floor is most of the list.
					header = false,
					virtualized = true,
					selection = "multi",
					reorderable = true,
					onReorder = function(keys: { string }, toIndex: number)
						local moving: { [string]: boolean } = {}
						for _, k in keys do
							moving[k] = true
						end
						local carried, staying = {}, {}
						for _, item in tableRows:get() :: { any } do
							table.insert(if moving[item.id] then carried else staying, item)
						end
						local out = {}
						for i = 1, toIndex do
							table.insert(out, staying[i])
						end
						for _, item in carried do
							table.insert(out, item)
						end
						for i = toIndex + 1, #staying do
							table.insert(out, staying[i])
						end
						tableRows:set(out)
					end,
					-- NO rowHeight: the framework derives it per paradigm and per text
					-- preference, which is exactly why a virtualized Table needs no
					-- consumer-side extent prediction (docs/plans/variable-item-extents.md)
					columns = {
						{
							id = "name",
							title = "Entrant",
							width = { type = "fill", weight = 4 },
							minWidth = 90,
							disclose = true,
							value = function(item: any)
								return item.name
							end,
						},
						{
							id = "team",
							title = "Team",
							width = { type = "fill", weight = 3 },
							minWidth = 70,
							disclose = true,
							value = function(item: any)
								return item.team
							end,
						},
						{
							id = "rank",
							title = "#",
							width = { type = "fill", weight = 2 },
							minWidth = 40,
							value = function(item: any)
								return tostring(item.rank)
							end,
						},
					},
					env = env,
				})

				-- the selectors, for the reason `extentArms` records: a pass that
				-- presents with no options makes `select:recycle=off` a no-op
				local handle = ctx.presenter.present(
					U.Screen({
						id = "TableUnified",
						padding = 0,
						gap = 0,
						children = {
							U.ZStack({
								id = "Pane",
								width = { type = "fill", weight = 1 },
								height = { type = "fill", weight = 1 },
								children = { tbl.blueprint },
							}),
						},
					}),
					{
						recycleInstances = settings.recycle == true,
						incrementalLayout = settings.incremental == true,
					}
				)
				local unbind: any = nil
				if tbl.api.bindNativeScroll ~= nil and handle.controller ~= nil then
					local ok, result = pcall(tbl.api.bindNativeScroll, handle.controller)
					if ok then
						unbind = result
					end
				end

				local function windowNow(): number
					local d = tbl.dump()
					return d.windowRows or -1
				end
				local function assertBounded(where: string)
					local w = windowNow()
					--[[ A generous bound stated as a RULE. The table derives its own
						row height from the theme and the text preference, so the lab
						cannot know the pitch — but "a windowed container mounts a
						screenful, not a collection" is checkable without it: a phone
						viewport at the SMALLEST plausible row pitch still cannot hold
						a tenth of 2 000. What this catches is the failure that
						matters, a window that grows with the model. ]]
					assert(
						w >= 0 and w <= math.max(64, math.ceil(TABLE_ROWS / 10)),
						`[perf lab] the virtualized Table is NOT bounded at {where}: {w} rows mounted of `
							.. `{#(tableRows:get() :: { any })} logical`
					)
				end

				local function finish()
					if unbind ~= nil then
						unbind()
					end
					ctx.presenter.dismiss(handle)
					tbl.dispose()
					passScope:dispose()
				end

				local function sampleIdle(n: number): { number }
					local out = table.create(n)
					for i = 1, n do
						local t0 = clock()
						ctx.presenter.refresh()
						out[i] = (clock() - t0) * 1000
						telemetry.step()
					end
					return out
				end
				--[[ ONE VERB, SAMPLED `reps` TIMES — and the repetition is not a nicety.

					The first cut ran each verb ONCE and reported its ms. Studio,
					2026-08-14: `revealRow` came back at **14.76 ms**, which read as the
					pass's headline finding and is n=1 — indistinguishable from a cold
					path, a GC, or the one frame the OS took the core away. A single
					sample is the same mistake as a delta with no control, one level
					down. Each verb now reports a distribution AND the arranges it
					provoked, because a verb that is fast because it did nothing and a
					verb that is fast because it is cheap are otherwise identical. ]]
				local function verb(reps: number, body: (n: number) -> ()): any
					local arrangeBefore = scopeCount("arrange")
					local samples = table.create(reps)
					for i = 1, reps do
						local t0 = clock()
						body(i)
						ctx.presenter.refresh()
						samples[i] = (clock() - t0) * 1000
						telemetry.step()
					end
					local out = summarize(samples)
					out.arrangesPerRep = (scopeCount("arrange") - arrangeBefore) / reps
					return out
				end
				-- far rows that no single window holds, walked so consecutive reps are
				-- genuinely different work rather than a warm repeat of one target
				local FAR_ROWS = { 1500, 120, 1930, 640, 1777, 310 }

				--[[ WHY RECYCLING IS OR IS NOT DOING ANYTHING — the mechanism, not the
					inference. Measured in Studio 2026-08-14: on this workload
					`recycle=on` and `recycle=off` were indistinguishable inside an
					A/B/A control band, which is the same shape L-27 recorded for a
					themed surface. A black-box A/B cannot say WHY, and the renderer
					already counts it: `parked` vs `parkRefused` is the answer, and
					`recycleArmed` is the check that the selector reached the presenter
					at all. Zero parks with a non-zero refusal count means every row
					this container windows is one the pool will not take. ]]
				local function recycling(): any
					if handle.controller == nil or handle.controller.stats == nil then
						return { measured = false }
					end
					local s = handle.controller.stats()
					return {
						measured = true,
						armed = s.recycleArmed,
						parked = s.parked,
						parkRefused = s.parkRefused,
						recycled = s.recycled,
						creates = s.creates,
						removes = s.removes,
					}
				end

				local ok, result = pcall(function()
					assertBounded("mount")
					local idleA = sampleIdle(20)

					-- ---- steady scroll, through the engine's own canvas ----------
					local d0 = tbl.dump()
					local extent = math.max(1, (d0.contentExtent or 0) - viewportH())
					local scrollPath = tbl.api.scrollPath()
					local y = 0
					local steps = {}
					for i = 1, frames do
						y = (y + 40) % extent
						local t0 = clock()
						if scrollPath ~= nil and handle.controller ~= nil then
							handle.controller.scrollTo(scrollPath, { x = 0, y = y })
						end
						local writeMs = (clock() - t0) * 1000
						-- the engine's CanvasPosition echo lands next frame; headless
						-- the fake target has already echoed
						telemetry.step()
						local t1 = clock()
						ctx.presenter.refresh()
						table.insert(steps, writeMs + (clock() - t1) * 1000)
						if i % 20 == 0 then
							assertBounded(`scroll frame {i}`)
						end
					end

					-- ---- the three verbs, each reaching an unmounted row ---------
					local reveals = 0
					local reveal = verb(reps, function(n)
						if tbl.api.revealRow(keyOf(FAR_ROWS[(n - 1) % #FAR_ROWS + 1])) then
							reveals += 1
						end
					end)
					local range = verb(reps, function(n)
						-- the span is constant and the WINDOW it lands in is not, so
						-- every rep selects the same 201 rows from a different scroll
						-- position — a range that happened to be mounted would be a
						-- different, cheaper measurement
						local shift = ((n - 1) % 5) * 100
						tbl.api.select(keyOf(TABLE_RANGE_FROM + shift), { mode = "replace" })
						tbl.api.select(keyOf(TABLE_RANGE_TO + shift), { mode = "range" })
					end)
					local selected = 0
					for _, on in tbl.api.selectedKeys:get() do
						if on then
							selected += 1
						end
					end
					local moves = 0
					local move = verb(reps, function(n)
						if tbl.api.moveRow(keyOf(FAR_ROWS[(n - 1) % #FAR_ROWS + 1]), -1) then
							moves += 1
						end
					end)
					assertBounded("after the verbs")

					--[[ THE VERBS ACTUALLY LANDED. A range spanning 201 rows of which
						the window holds a handful is the whole claim — selection is
						MODEL state and only the mounting is windowed — and a silently
						no-op `select` would report as a very fast verb. ]]
					assert(
						selected == (TABLE_RANGE_TO - TABLE_RANGE_FROM + 1),
						`[perf lab] the range selection spanning unmounted rows selected {selected}, `
							.. `expected {TABLE_RANGE_TO - TABLE_RANGE_FROM + 1}`
					)
					assert(
						reveals == reps and moves == reps,
						`[perf lab] the verbs did not all land: {reveals}/{reps} reveals, {moves}/{reps} moves — `
							.. "a refused verb reports as a very fast one"
					)

					local idleB = sampleIdle(20)
					local final = tbl.dump()
					local a1, a2 = summarize(idleA), summarize(idleB)
					return {
						rows = TABLE_ROWS,
						frames = frames,
						reps = reps,
						-- READ THIS FIRST: nothing below is a result at a smaller size
						harnessSpreadMs = if a1.measured and a2.measured then math.abs(a1.p50_ms - a2.p50_ms) else 0,
						idleMs = a1,
						idleRepeatMs = a2,
						scrollStepMs = summarize(steps),
						mountedRows = final.windowRows,
						contentExtent = final.contentExtent,
						selectedRows = selected,
						recycling = recycling(),
						revealFar = reveal,
						selectRange = range,
						moveFar = move,
						note = "one container doing all three at once: 2 000 rows windowed, a 201-row range "
							.. "selected across rows no window has held, and a move of row 1500. Hosted row "
							.. "actions are ABSENT because newTable refuses them beside `virtualized` (v1). "
							.. "Each verb reports the arranges it provoked, so a verb that is cheap and a verb "
							.. "that did nothing are distinguishable. Lune = regression signal, this lab = real "
							.. "engine, device = the only device claim.",
					}
				end)
				finish()
				if not ok then
					error(result, 0)
				end
				return result
			end)
		end

		passes.updateOne = function(payload: string?)
			return timed("updateOne", function()
				local count = tonumber(payload or "") or 60
				local m = requireList()
				local all = rowsSignal:get()
				local worst = 0
				for i = 1, count do
					local item = all[((i - 1) * 3) % #all + 1]
					local t0 = clock()
					if m.kind == "native" then
						m.native.updateOne(item.id, `{item.name} #{i}`)
					else
						local sig = values[item.id]
						if sig ~= nil then
							sig:set((i % 20) / 20)
						end
					end
					ctx.presenter.refresh()
					local dt = (clock() - t0) * 1000
					if dt > worst then
						worst = dt
					end
				end
				return {
					updates = count,
					worstUpdateMs = worst,
					implementation = m.kind,
					note = "ONE row's value per update; the cost must be proportional to the changed row, not the list",
				}
			end)
		end

		passes.updateBatch = function(payload: string?)
			return timed("updateBatch", function()
				local batches = tonumber(payload or "") or 10
				local m = requireList()
				local all = rowsSignal:get()
				for b = 1, batches do
					if m.kind == "native" then
						m.native.updateBatch(b)
					else
						core:transaction(function()
							for i = 1, 40 do
								local item = all[((b * 40 + i) % #all) + 1]
								local sig = values[item.id]
								if sig ~= nil then
									sig:set(((b + i) % 20) / 20)
								end
							end
						end)
					end
					ctx.presenter.refresh()
				end
				return { batches = batches, perBatch = 40, implementation = m.kind }
			end)
		end

		passes.insert = function(payload: string?)
			return timed("insert", function()
				local n = tonumber(payload or "") or 25
				for i = 1, n do
					local list = table.clone(rowsSignal:get())
					local at = math.max(1, math.floor(#list * 0.25))
					table.insert(list, at, {
						id = `ins{i}-{at}`,
						name = `Inserted {i}`,
						detail = "inserted during churn",
						team = "Ember",
						imageKey = dataset.IMAGE_KEYS[(i % #dataset.IMAGE_KEYS) + 1],
						value = 0.5,
						enabled = true,
						rank = at,
					})
					rowsSignal:set(list)
					ctx.presenter.refresh()
				end
				assertBoundedWindow("insert")
				return { inserted = n, logicalRows = #rowsSignal:get(), mountedRows = mountedRowCount() }
			end)
		end

		passes.remove = function(payload: string?)
			return timed("remove", function()
				local n = tonumber(payload or "") or 25
				for _ = 1, n do
					local list = table.clone(rowsSignal:get())
					if #list > 1 then
						table.remove(list, math.max(1, math.floor(#list * 0.25)))
						rowsSignal:set(list)
						ctx.presenter.refresh()
					end
				end
				assertBoundedWindow("remove")
				return { removed = n, logicalRows = #rowsSignal:get(), mountedRows = mountedRowCount() }
			end)
		end

		passes.reorder = function(payload: string?)
			return timed("reorder", function()
				local n = tonumber(payload or "") or 20
				for i = 1, n do
					local list = table.clone(rowsSignal:get())
					if #list > 4 then
						local from = ((i * 7) % (#list - 1)) + 1
						local item = table.remove(list, from)
						table.insert(list, math.max(1, (from + 3) % #list), item)
						rowsSignal:set(list)
						ctx.presenter.refresh()
					end
				end
				assertBoundedWindow("reorder")
				return { moves = n, logicalRows = #rowsSignal:get(), mountedRows = mountedRowCount() }
			end)
		end

		-- ---- layout / style churn ------------------------------------------
		passes.preferenceSweep = function()
			return timed("preferenceSweep", function()
				local applied = {}
				local resolves = {}
				for _, offset in PREFERENCE_OFFSETS do
					local t0 = clock()
					env:set("preferredTextOffset", offset)
					ctx.presenter.refresh()
					table.insert(applied, offset)
					table.insert(resolves, { offset = offset, ms = (clock() - t0) * 1000 })
				end
				env:set("preferredTextOffset", 0)
				ctx.presenter.refresh()
				return {
					offsets = applied,
					perOffset = resolves,
					note = "the four MEASURED per-preference offsets (Step 8.5): 0/4/10/14. Content is never reduced "
						.. "to make this cheaper — that would be a different workload wearing the same name",
				}
			end)
		end

		-- RESIZE STORM (director ask, 2026-08-05). `resize` above walks three shapes
		-- once. This is the workload that answers a different question: what does a
		-- CONTINUOUS resize cost, and how much of that cost is the framework
		-- re-solving things that did not change?
		--
		-- It reports the two numbers that make the answer attributable rather than a
		-- single blended figure:
		--   * `arrangedPerResize` — nodes the solver re-arranged for a viewport change,
		--     which is legitimately the whole tree;
		--   * `arrangedPerDataChange` — nodes it re-arranged for ONE bound value with
		--     the viewport held still, which SHOULD be a small neighbourhood and today
		--     is the whole tree (see optimization-log L-11).
		-- The ratio between them is the size of the incremental-layout prize, measured
		-- on the real workload rather than argued from the code.
		passes.resizeStorm = function(payload: string?)
			return timed("resizeStorm", function()
				local steps = math.clamp(math.floor(tonumber(payload or "") or 40), 1, 400)
				local m = requireList()
				local original = env:get("viewportRect"):get()
				local baseW = if type(original) == "table" then original.w else 360
				local baseH = if type(original) == "table" then original.h else 640
				local stats = if m.kind == "facet"
						and m.controller ~= nil
						and m.controller.stats ~= nil
					then m.controller.stats
					else nil

				local resizeMs, dataMs = {}, {}
				local arrangedResize, arrangedData = 0, 0

				--[[ THE ROUND-TRIP INSTRUMENT (L-31, director's standing instruction:
					"add whatever the performance lab needs to profile this specific
					cost"). The measure→publish feedback loop was diagnosed on the
					device from exactly two numbers, and neither was available from
					this pass's own report — they had to be read out of a binary
					MicroProfiler dump by hand: reactive FLUSHES per step, and SOLVES
					(arranges) per step. Both are already counted by
					`src/core/profile.luau` whenever scopes are on, which is what the
					lab boots with, so the pass can report them directly.

					WHAT EACH ONE ANSWERS. `reactPerResize` is the count that names a
					feedback loop by itself: the framework's own contribution to a
					batched adapter resize is exactly ONE flush, so anything above 1
					is a write made in response to the resize rather than as part of
					it. `arrangePerResize` is what that costs — every geometry flush
					re-solves every mounted surface, so the two numbers multiply.
					Measured here 2026-08-14: 3 flushes and 7 arranges per step
					before, 2 and 6 after (the residual flush is the data change this
					pass drives on purpose, and the residual arranges are the
					structural re-solve the windowed list legitimately owes).

					`scopeCount` (declared beside `summarize`, shared with the
					collection passes) is nil-safe rather than asserted: a capture
					taken with `cleanCapture` deliberately turns scopes OFF, and a
					pass that threw in that configuration would break the one
					measurement the clean capture exists to take. ]]
				local reactAtStart, arrangeAtStart = scopeCount("react"), scopeCount("arrange")

				for i = 1, steps do
					-- ODD, NON-REPEATING WIDTHS. A resize that lands back on a size the
					-- solver has already seen measures a warm cache, not a resize; the
					-- prime step keeps every step a genuinely new width.
					local w = baseW - ((i * 7) % 61)
					local h = baseH - ((i * 11) % 41)
					local t0 = clock()
					--[[ YIELD PER STEP, not per lap.

						DEVICE REPORT, 2026-08-13 (second round): with the inter-lap
						yield in place the laps DO advance — the director sees "lap 1,
						2, 3" — but "nothing visually changes and the MicroProfiler
						hangs when I try to capture". That is the other half of the
						same defect: one lap is 40 steps x 2 full re-solves = 80
						synchronous solves with no frame between them, so the whole
						lap lands inside ONE frame. Nothing repaints (the viewport is
						set and restored without the engine ever drawing between), and
						a profiler asked to capture during a several-hundred-millisecond
						frame has nothing to sample but that frame.

						A workload that never yields is not measurable BY CONSTRUCTION,
						whatever the loop around it does. ]]
					telemetry.step()
					--[[ A RESIZE IS SIX FACTS, NOT ONE (2026-08-13). This pass used to
						set `viewportRect` alone, which is a resize NO DEVICE PERFORMS:
						`src/client/roblox_env.luau` `pushViewport()` learns SIX facts from
						one rotation or window drag — the viewport, three inset shapes, the
						topbar rect and the size class — and the renderer re-solves for most
						of them. Measuring one fact under-counted the shipped path's solve
						count, which is the very thing L-27 named as the lever.

						So drive what the adapter drives, batched exactly as the adapter
						batches it. The insets are derived from the shape rather than held
						constant: a resize that never moves an inset would let a regression
						in inset-driven re-solving hide here. ]]
					local rw, rh = math.max(240, w), math.max(240, h)
					local compact = rw < 600
					env:batch(function()
						env:set("viewportRect", { x = 0, y = 0, w = rw, h = rh })
						local top = if compact then 36 else 0
						env:set("coreSafeInsets", { top = top, bottom = 0, left = 0, right = 0 })
						env:set("deviceSafeInsets", {
							top = if compact then 44 else 0,
							bottom = if compact then 34 else 0,
							left = 0,
							right = 0,
						})
						env:set("topbarSafeInsets", { top = top, bottom = 0, left = 0, right = 0 })
						env:set("topbarInset", { x = 0, y = 0, w = rw, h = top })
						--[[ displaySize IS NOT THE SIZE CLASS, and a rotation does not
							change it. Its domain is `Small | Medium | Large`
							(`GuiService.ViewportDisplaySize`, environment.luau:86) and
							**`Large` means TELEVISION**: it alone drives
							typographyScale 1.5, distanceProfile "ten-foot" and 60/90px
							overscan insets. Writing `"Compact"`/`"Large"` off the width
							— this pass's first cut, caught by RED-TEAM 2026-08-13 —
							made every wide step measure a 1.5x-scaled ten-foot layout
							and made "Compact" a silent no-op, since anything that is not
							`Large` reads as `near`.

							The adapter DOES publish this fact on every pushViewport, so
							it belongs in the group; what it does not do is change it when
							the device rotates. Held constant, faithfully. ]]
						env:set("displaySize", "Medium")
					end)
					ctx.presenter.refresh()
					table.insert(resizeMs, (clock() - t0) * 1000)
					if stats ~= nil then
						arrangedResize += (stats().lastArranged or 0)
					end

					-- ...then ONE bound value, with the viewport held still, so the two
					-- costs are never blended into one average.
					--
					-- FROM THE LIVE WINDOW, NOT THE WHOLE DATASET. A row's value signal
					-- is created lazily when the row materializes, so indexing across
					-- 2 000 logical rows found a signal on 2 steps out of 40 and the
					-- data-change sample was two readings wide. Picking among the
					-- signals that actually exist keeps every step a real measurement.
					local live = {}
					for id in values do
						table.insert(live, id)
					end
					table.sort(live)
					local sig = if #live > 0 then values[live[((i - 1) % #live) + 1]] else nil
					if sig ~= nil then
						local t1 = clock()
						sig:set((i % 20) / 20)
						ctx.presenter.refresh()
						table.insert(dataMs, (clock() - t1) * 1000)
						if stats ~= nil then
							arrangedData += (stats().lastArranged or 0)
						end
					end
				end

				env:set("viewportRect", original)
				ctx.presenter.refresh()

				local function stat(list: { number })
					if #list == 0 then
						return { n = 0 }
					end
					local sorted = table.clone(list)
					table.sort(sorted)
					local sum = 0
					for _, v in sorted do
						sum += v
					end
					return {
						n = #sorted,
						meanMs = sum / #sorted,
						p50Ms = sorted[math.max(1, math.floor(#sorted * 0.5))],
						p95Ms = sorted[math.max(1, math.floor(#sorted * 0.95))],
						worstMs = sorted[#sorted],
					}
				end
				local perResize = if #resizeMs > 0 then arrangedResize / #resizeMs else 0
				local perData = if #dataMs > 0 then arrangedData / #dataMs else 0
				return {
					steps = steps,
					resize = stat(resizeMs),
					dataChange = stat(dataMs),
					arrangedPerResize = perResize,
					arrangedPerDataChange = perData,
					-- 1.0 means a single bound value costs a whole re-layout
					dataChangeShareOfFullRelayout = if perResize > 0 then perData / perResize else nil,
					-- the measure→publish instrument (L-31); 0 when scopes are off
					reactPerStep = (scopeCount("react") - reactAtStart) / steps,
					arrangePerStep = (scopeCount("arrange") - arrangeAtStart) / steps,
					note = "a resize legitimately re-arranges the whole tree; a single bound value should not. "
						.. "`dataChangeShareOfFullRelayout` at 1.0 is the incremental-layout gap (L-11), and is "
						.. "the number this pass exists to keep visible. `reactPerStep` is the feedback-loop "
						.. "detector (L-31): a batched adapter resize is ONE framework flush, so anything above "
						.. "that plus this pass's own data change is a write made in RESPONSE to the resize, and "
						.. "it multiplies by every mounted surface into `arrangePerStep`. Both read 0 under "
						.. "cleanCapture, where scopes are deliberately off.",
				}
			end)
		end

		passes.localeSwap = function()
			return timed("localeSwap", function()
				local before = settings.content
				local swaps = {}
				for _, variant in { "locale", "identity", before } do
					local t0 = clock()
					settings.content = variant
					rebuildDataset()
					ctx.presenter.refresh()
					table.insert(swaps, { content = variant, ms = (clock() - t0) * 1000 })
				end
				return { swaps = swaps, restoredTo = settings.content }
			end)
		end

		passes.resize = function()
			return timed("resize", function()
				local original = env:get("viewportRect"):get()
				local shapes = {
					{ x = 0, y = 0, w = 390, h = 844 },
					{ x = 0, y = 0, w = 844, h = 390 },
					{ x = 0, y = 0, w = 1280, h = 720 },
				}
				local measured = {}
				for _, shape in shapes do
					local t0 = clock()
					env:set("viewportRect", shape)
					ctx.presenter.refresh()
					table.insert(measured, { w = shape.w, h = shape.h, ms = (clock() - t0) * 1000 })
				end
				env:set("viewportRect", original)
				ctx.presenter.refresh()
				return { shapes = measured, restored = original }
			end)
		end

		-- ---- theme cost (PL-6) ----------------------------------------------
		-- Install, swap+reflow, and teardown are captured SEPARATELY. Averaging an
		-- ornate package's one-time install into its steady-state cost is how a
		-- skin gets blamed for a frame it does not own.
		local function compilePackage(name: string): any?
			if name == "flat" then
				return nil
			end
			local module = ctx.themePackages and ctx.themePackages[name]
			if module == nil then
				return nil
			end
			return if type(module.build) == "function" then (module.build(Facet.themes)) else module
		end

		-- The FULL isolated theme sequence (PL-6): flat -> ornate install -> ornate
		-- steady -> back to flat. Each leg is its own timed pass so cold install,
		-- warm reflow, steady state and teardown never blur together.
		passes.themeCost = function()
			return timed("themeCost", function()
				local legs = {}
				table.insert(legs, { leg = "install-ornate", result = passes.themeSwap(ORNATE_PACKAGE) })
				table.insert(legs, { leg = "steady-ornate", result = passes.scrollSteady("30") })
				table.insert(legs, { leg = "teardown-to-flat", result = passes.themeSwap(FLAT_PACKAGE) })
				table.insert(legs, { leg = "steady-flat", result = passes.scrollSteady("30") })
				return {
					legs = legs,
					flatPackage = FLAT_PACKAGE,
					ornatePackage = ORNATE_PACKAGE,
					note = "identical dataset, content, geometry contract, interactions and sequence on both legs; "
						.. "only the package differs, which is the only way the difference means the package",
				}
			end)
		end

		-- forward: the overlay's blueprint is built (and cached) hundreds of lines below,
		-- and a later `local` is not an upvalue — the same hoist `raiseOverlay` uses.
		local rebuildOverlayForTheme: (() -> ())? = nil

		-- One place that installs a theme package, shared by the selector and the passes,
		-- so "which theme is on screen" and "which theme the capture claims" cannot
		-- disagree. Refuses a name it cannot honour, exactly as `select` refuses an
		-- unknown scenario — a selector that silently does nothing is worse than one
		-- that errors.
		--
		-- A THEME IS TWO HALVES AND THIS INSTALLED ONE (L-26, 2026-08-05). The call
		-- below used to be `ctx.themeChrome.setPackage(pkg)` and nothing else — the
		-- DECORATION half. The METRIC half is the resolved snapshot published as
		-- `themeMetrics`, which is what makes the solver reserve a recipe's
		-- `contentInsets`; it was never committed at all. So the adapter painted
		-- fantasy-ornate art onto a surface the solver had measured with Studio
		-- Neutral, and the paint seam then lifted every label by 14+14 of inset the
		-- layout had never been told about. Live at 360x691: an `Open` button 60x46
		-- at `TextSize = 18` — Studio Neutral's `control` size; ornate's is 17 — and
		-- every lifted label short by exactly 28 - 24 = 4px, at every control size
		-- and every label length, because both terms are constants.
		--
		-- The two halves commit in ONE transaction (ADR-0019 §7), which is the
		-- controller's whole job: sheet derives, decoration and `env:set` land
		-- together or not at all, so there is no frame where paint and geometry
		-- disagree. `themes.resolve` + `env:set` is the fallback for a target with
		-- no controller (the headless harness), and it is the metric half either
		-- way — never optional, because a half-worn theme is exactly what shipped.
		local installedController: any = nil
		local function applyThemeByName(name: string)
			local pkg = compilePackage(name)
			if name ~= "flat" and pkg == nil then
				error(
					`[perf lab] theme '{name}' is not available in this place — selecting it would leave the `
						.. `flat surface on screen while every capture row claimed '{name}'`,
					0
				)
			end
			local controller = if ctx.themeController ~= nil then ctx.themeController() else nil
			local committed = false
			if controller ~= nil and pkg ~= nil then
				-- install once, then swap in place: a second install would re-link the
				-- sheet and double-subscribe the token watchers
				if installedController == nil then
					installedController = controller.install(ctx.adapter, pkg, { env = env })
				else
					installedController.swapPackage(pkg, nil)
				end
				committed = true
			elseif installedController ~= nil and pkg == nil then
				installedController.uninstall()
				installedController = nil
			end
			if not committed then
				-- decoration first, so the chrome children exist when the metrics land
				if ctx.themeChrome ~= nil then
					ctx.themeChrome.setPackage(pkg)
				end
				env:set(
					"themeMetrics",
					if pkg ~= nil then Facet.themes.resolve(pkg, nil, {}) else Facet.themes.neutral()
				)
			end
			-- the overlay's own arrangement is a theme fact too, and it is the one that
			-- cannot re-solve its way out of a change (see `overlayScreen`)
			if rebuildOverlayForTheme ~= nil then
				rebuildOverlayForTheme()
			end
			ctx.presenter.refresh()
			settings.theme = name
		end

		passes.themeSwap = function(payload: string?)
			return timed("themeSwap", function()
				local name = payload or settings.theme
				local pkg = compilePackage(name)
				local geometryBefore = ctx.geometry and ctx.geometry({ "/PerfWorkload/Head" }) or {}
				local instancesBefore = telemetry.instances()
				local t0 = clock()
				local changed = ctx.themeChrome and ctx.themeChrome.setPackage(pkg) or false
				local installMs = (clock() - t0) * 1000
				local t1 = clock()
				ctx.presenter.refresh()
				local reflowMs = (clock() - t1) * 1000
				settings.theme = name
				local geometryAfter = ctx.geometry and ctx.geometry({ "/PerfWorkload/Head" }) or {}
				local moved = 0
				for path, rect in geometryBefore do
					local b = geometryAfter[path]
					if b == nil or b.x ~= rect.x or b.y ~= rect.y or b.w ~= rect.w or b.h ~= rect.h then
						moved += 1
					end
				end
				return {
					package = name,
					packageFound = pkg ~= nil or name == "flat",
					packageCompiled = pkg ~= nil and pkg.identity ~= nil,
					chromeChanged = changed,
					installMs = installMs,
					reflowMs = reflowMs,
					movedRects = moved,
					census = ctx.themeChrome and ctx.themeChrome.census() or nil,
					instancesBefore = instancesBefore.guiObjects,
					instancesAfter = telemetry.instances().guiObjects,
					note = "install and reflow are timed apart on purpose; a palette-only swap must not move geometry "
						.. "and a metric/chrome swap must",
				}
			end)
		end

		-- ---- resources (PL-7 / async-image-churn) ----------------------------
		passes.imagesCold = function()
			return timed("imagesCold", function()
				settings.resourceState = "cold"
				local before = provider.counters and provider.counters() or {}
				ctx.presenter.refresh()
				return {
					resourceState = "cold",
					providerBefore = before,
					providerAfter = provider.counters and provider.counters() or {},
				}
			end)
		end

		passes.imagesWarm = function()
			return timed("imagesWarm", function()
				settings.resourceState = "warm"
				-- BOTH warm paths, because they warm different caches. The provider's
				-- own preload fills the FRAMEWORK cache through the same transport a
				-- row's acquire uses; the host preload asks the ENGINE to fetch and
				-- decode. A capture that warmed only one of them is measuring the
				-- other one cold and calling the result steady state.
				local providerPreloaded = 0
				if provider.preload ~= nil then
					local ok = pcall(function()
						provider.preload(dataset.IMAGE_KEYS)
					end)
					providerPreloaded = if ok then #dataset.IMAGE_KEYS else 0
				end
				local preloaded = 0
				if host.preload ~= nil then
					preloaded = host.preload(dataset.IMAGE_KEYS)
				end
				ctx.presenter.refresh()
				return {
					resourceState = "warm",
					enginePreloaded = preloaded,
					providerPreloaded = providerPreloaded,
					providerAfter = provider.counters and provider.counters() or {},
					note = if host.preload == nil
						then "no host preload seam in this environment; the warm/cold split is unmeasured here"
						else nil,
				}
			end)
		end

		passes.imagesFail = function()
			return timed("imagesFail", function()
				local verdict = provider.complete(dataset.FAILING_IMAGE_KEY, 1, "never-fetched")
				local failVerdict = provider.fail(dataset.FAILING_IMAGE_KEY, 1, "deliberate asset failure")
				ctx.presenter.refresh()
				return {
					staleCompletionVerdict = verdict,
					failVerdict = failVerdict,
					providerAfter = provider.counters and provider.counters() or {},
					note = "a completion against a key with no live request must be STALE, not applied",
				}
			end)
		end

		passes.imagesReuse = function(payload: string?)
			return timed("imagesReuse", function()
				local cycles = tonumber(payload or "") or 8
				local pitch = rowHeight:get() + rows.ROW_GAP
				for i = 1, cycles do
					scrollTo(((i % 2) == 0 and 0 or 40) * pitch)
					ctx.presenter.refresh()
				end
				assertBoundedWindow("imagesReuse")
				return {
					cycles = cycles,
					providerAfter = provider.counters and provider.counters() or {},
					mountedRows = mountedRowCount(),
					note = "rapid window churn over a bounded image set: acquisitions must be reused, and rows leaving "
						.. "the window must cancel rather than accumulate",
				}
			end)
		end

		-- ---- reveal / moving-label audit (PL-7) ------------------------------
		passes.revealAudit = function()
			return timed("revealAudit", function()
				local controller = mounted ~= nil and mounted.kind == "facet" and mounted.controller or nil
				local findings: { any } = {}
				local moving = 0
				if controller ~= nil and controller.diagnostics ~= nil then
					local ok, d = pcall(controller.diagnostics)
					if ok and type(d) == "table" then
						findings = d
						for _, finding in d do
							if type(finding) == "table" and string.find(tostring(finding.issue or ""), "moving") then
								moving += 1
							end
						end
					end
				end
				return {
					findings = #findings,
					movingSurfaceFindings = moving,
					maxAllowedMovingLabels = 1,
					reducedMotion = env:get("reducedMotion") and env:get("reducedMotion"):get() or nil,
					note = "the audit's own moving-text rule caps ACTIVE moving surfaces at one; a finding here means "
						.. "the cap was exceeded, which is the proliferation this row exists to bound",
				}
			end)
		end

		-- ---- ramp with an emergency stop (PL-11) -----------------------------
		passes.ramp = function(payload: string?)
			return timed("ramp", function()
				emergencyStopped = false
				local ladder = dataset.RAMP_STEPS
				local limit = tonumber(payload or "") or #ladder
				local results = {}
				for i = 1, math.min(limit, #ladder) do
					if emergencyStopped then
						table.insert(results, { stoppedAt = i, reason = "emergency stop" })
						break
					end
					-- YIELD PER RUNG, for the reason resizeStorm yields per step: a
					-- rung rebuilds a dataset of up to 40,000 rows and mounts it, and
					-- five of those inside one frame is a freeze whatever the caller
					-- does. Frame-accurate mount timings need a frame boundary anyway.
					telemetry.step()
					rampIndex = i
					local count = math.min(ladder[i], dataset.MAX_ROWS)
					unmount()
					settings.rows = count
					rebuildDataset()
					local before = telemetry.memory()
					local t0 = clock()
					settings.implementation = "facet"
					mount()
					local mountMs = (clock() - t0) * 1000
					local after = telemetry.memory()
					table.insert(results, {
						rows = count,
						mountMs = mountMs,
						mountedRows = mountedRowCount(),
						windowBound = windowBound(),
						guiObjects = telemetry.instances().guiObjects,
						luaHeapKbDelta = if type(after.luaHeapKb) == "number"
								and type(before.luaHeapKb) == "number"
							then after.luaHeapKb - before.luaHeapKb
							else nil,
					})
				end
				return {
					steps = results,
					ceiling = dataset.MAX_ROWS,
					stopped = emergencyStopped,
					note = "a declared ladder with a hard ceiling and a stop, so finding the knee cannot make the "
						.. "device unrecoverable",
				}
			end)
		end

		passes.soak = function(payload: string?)
			return timed("soak", function()
				local cycles = tonumber(payload or "") or 12
				local samples = {}
				for i = 1, cycles do
					if emergencyStopped then
						break
					end
					unmount()
					settings.implementation = "facet"
					mount()
					passes.scrollSteady("10")
					table.insert(samples, {
						cycle = i,
						guiObjects = telemetry.instances().guiObjects,
						connections = telemetry.connections(),
						luaHeapKb = telemetry.memory().luaHeapKb,
						coreCounters = core:counters(),
					})
				end
				return {
					cycles = #samples,
					samples = samples,
					note = "the question is a TREND, not an absolute: Instances, connections, signals and heap must "
						.. "not climb monotonically across identical cycles",
				}
			end)
		end

		-- ---- the overlay -----------------------------------------------------
		-- The overlay renders a FIXED number of counter lines (see overlay.luau for
		-- why a newline-joined block is not an option). Publishing more than it can
		-- show would silently drop the tail, which is the same invisible-content
		-- failure in a different place.
		local COUNTER_LINES = 6

		-- the renderer's own structural counters, so "is recycling actually doing
		-- anything" is a number in the capture rather than an inference from a timing
		local function renderStats(): any
			if mounted == nil or mounted.kind ~= "facet" or mounted.controller == nil then
				return nil
			end
			local ok, s = pcall(mounted.controller.stats)
			return if ok then s else nil
		end

		local function refreshCounters()
			local instances = telemetry.instances()
			local scopes = profile.counters()
			local lines = {
				`impl={settings.implementation} rows={settings.rows} seed={settings.seed} content={settings.content}`,
				`theme={settings.theme} resources={settings.resourceState} clean={tostring(settings.cleanCapture)}`,
				`mountedRows={mountedRowCount()}/{windowBound()} logical={#rowsSignal:get()}`,
				`guiObjects={tostring(instances.guiObjects)} screenGuis={tostring(instances.screenGuis)}`,
				`scopes opens={scopes.opens} balanced={tostring(scopes.balanced)} engine={tostring(scopes.engine)}`,
				`passes={#passLog} ramp={rampIndex} stopped={tostring(emergencyStopped)}`,
			}
			assert(
				#lines == COUNTER_LINES,
				`[perf lab] the counter model publishes {#lines} lines and the overlay renders {COUNTER_LINES}`
			)
			counterLines:set(lines)
		end

		local overlayModel = {
			buildLine = core:memo(function()
				return `Facet {Facet.VERSION} · {SCENARIO_VERSION} · {dataset.VERSION} · {rows.VERSION}`
			end),
			scenarioLine = core:memo(function(use)
				return `scenario: {use(currentScenario)}`
			end),
			deviceLine = core:memo(function(use)
				local vp = use(env:get("viewportRect"))
				local input = use(env:get("preferredInput"))
				return `viewport {math.floor(vp.w)}x{math.floor(vp.h)} · input {tostring(input)}`
			end),
			statusLine = statusLine,
			countdown = countdown,
			counterLines = counterLines,
			currentScenario = currentScenario,
			scenarioNames = WORKLOAD_ORDER,
			-- NO SIZE NUMBERS PASSED IN. The panel's height cap and its action-column
			-- count both used to be computed here, from `viewportRect`, at build time
			-- — and a blueprint is built once, so both were frozen at whichever
			-- orientation happened to be up first. They are now stated declaratively
			-- in the overlay (a `percent` height, `minColumnWidth = "intrinsic"`) and
			-- the solver re-resolves them on every solve, rotation included.
			onSelectScenario = function(_name: string) end,
			onCycleScenario = function(_delta: number) end,
			onRunAll = function() end,
			scenarioPosition = core:memo(function(use)
				local name = use(currentScenario)
				for i, id in WORKLOAD_ORDER do
					if id == name then
						return `{i}/{#WORKLOAD_ORDER}`
					end
				end
				return `?/{#WORKLOAD_ORDER}`
			end),
			actions = {},
		}

		-- THE BLUEPRINT IS BUILT ONCE (found by a four-cycle probe while confirming the
		-- reactive-runtime review's RR-9 fix). `overlayLib.build` allocates one memo per
		-- counter line, so rebuilding it on every raise leaked six memos per mount:
		-- signals and scopes stayed flat while memos climbed 112 -> 130 -> 148 -> 166
		-- -> 184 across four dataset swaps. The Studio soak missed it because that run
		-- had clean capture ON and `raiseOverlay` early-returns there — a leak hiding
		-- behind the one mode that never exercises it.
		--
		-- Re-presenting the SAME blueprint is safe: `present` mounts a fresh tree from
		-- it, and the memos it closes over belong to the lab scope, not to the mount.
		-- THE OVERLAY RESERVES ITS OWN SPACE (found on a real device: the control panel
		-- painted straight over the list). Two presented surfaces are two ScreenGuis, so
		-- the SOLVER cannot see the collision at all — its diagnostics are per-surface,
		-- and each surface is individually correct. Nothing but a person looking at the
		-- screen would catch it.
		--
		-- The fix is the mechanism the showcase bootstrap already uses: publish the
		-- panel's measured height as a safe-area inset, so the solver lays the workload
		-- out in what is left. Measured via `onGeometry`, never guessed — a literal
		-- would be wrong at the first theme or text-size change.
		--
		-- CARRY THE OTHER THREE EDGES THROUGH. `coreSafeInsets` is a four-edge fact and
		-- the platform adapter is its author; writing a whole table with three zeroes
		-- in it reads as "reserve the bottom" and actually means "delete the notch and
		-- the home indicator".
		--[[ COMPARE AGAINST THE LIVE FACT, NEVER A REMEMBERED ONE (L-31,
			2026-08-14). This guard used to be `if want == reservedBottom then
			return end` against a local cache, and the cache was wrong every time
			the ADAPTER republished the fact: `roblox_env.pushViewport()` is the
			author of `coreSafeInsets` and rewrites all four edges on every resize,
			zeroing the reservation without this module ever hearing about it. The
			cache then said "already reserved" and the republication never
			happened, so the workload laid out under a dock that was drawing over
			it. `forgetReservation` below existed to punch a hole in that cache.

			Reading the live fact is both correct and shorter: the equality guard
			now compares what is actually published, so a republication happens
			exactly when the published number is wrong and never otherwise. ]]
		local reservedBottom = 0
		local function reserveBottom(px: number)
			local want = math.max(0, math.floor(px))
			reservedBottom = want
			local live = env:get("coreSafeInsets"):get()
			local other = if type(live) == "table" then live else {}
			if (other.bottom or 0) == want then
				return
			end
			env:set("coreSafeInsets", {
				top = other.top or 0,
				bottom = want,
				left = other.left or 0,
				right = other.right or 0,
			})
		end

		--[[ A RESERVATION DOES NOT SURVIVE THE SCREEN IT WAS MEASURED ON — and this
			stayed, deliberately, when L-31 made it free (2026-08-14).

			THE HAZARD, unchanged. The overlay publishes its measured height into
			`coreSafeInsets.bottom`, and the workload re-solves against that fact the
			instant the viewport changes — BEFORE the overlay has re-solved and
			republished. A rotation from a tall screen to a short one handed the
			workload the tall screen's 268px reservation against a 390px viewport: a
			122px content box, overflowing by 17px, which
			`tests/perf_lab.spec.luau`'s "the full resize pass leaves the workload
			MOUNTED" reproduces the moment these two lines are deleted (verified
			2026-08-14 — it is the mutation proof that they are load-bearing).
			Dropping to zero is the right direction to be wrong in: for the one solve
			before the overlay republishes, the workload believes it has MORE room
			than it does, which cannot overflow.

			WHY THE SETTLE PHASE DOES NOT REMOVE IT. Settle callbacks run in
			REGISTRATION order (src/core/contract.luau), and z-order is present
			order — so the overlay, which is presented ON TOP, settles LAST, after
			the workload it publishes to. The framework has no principled way to know
			that one surface produces what another consumes, and inventing one
			("topmost first", "producers first") would be a rationalisation, not a
			rule. So the CONSUMER still has to say "the number I was given is stale
			now", and this is that statement.

			WHAT CHANGED IS THE PRICE. Both writes now land inside the flush that
			caused them: the zero is absorbed into the propagation of the viewport
			change itself (it happens before any surface solves), and the
			republication settles in the same flush rather than opening a second one
			on the next frame. Measured on this shape, per resize step: 3 reactive
			flushes and 7 arranges before, 2 and 6 after — with the removed flush
			being exactly this dance. The 2026-08-14 device capture had priced it at
			`react` = 3.03 flushes per step where the framework's own contribution is
			1, and `Root=Facet_PerfLabOverlay Relayouts=8` against
			`Root=Facet_PerfWorkload Relayouts=8` — one dock panel provoking as many
			engine relayouts as the entire 2 000-row workload.

			`reserveBottom` above no longer keeps a private cache, so this no longer
			has to punch a hole in one; it just publishes the zero. ]]
		local function forgetReservation()
			reserveBottom(0)
		end
		labScope:own(core:observe(env:get("viewportRect"), forgetReservation))
		labScope:own(core:observe(env:get("typographyScale"), forgetReservation))

		local function overlayOpts(): any
			return {
				responder = "passive",
				-- the overlay owns the strip it draws in, so it is not inset by it
				rootPolicy = "edgeToEdge",
				onGeometry = function(rectOf: (string) -> any)
					local r = rectOf("/PerfLabOverlay/Dock/Panel")
					if type(r) == "table" and type(r.h) == "number" then
						reserveBottom(r.h + 8)
					end
				end,
			}
		end

		local overlayBlueprint: any = nil
		local function overlayScreen(): any
			if overlayBlueprint == nil then
				-- THE ONE STRUCTURAL FACT THE OVERLAY CANNOT STATE DECLARATIVELY (L-26).
				-- Everything else the paragraph in `overlayModel` is about — the panel's
				-- height cap, the action grid's column count — is a `percent` or an
				-- `intrinsic` the solver re-resolves every solve. Whether "Run all" fits
				-- beside the cycler is not: it is a different CHILD LIST, and a blueprint
				-- is built once. So it is read here, at build time, and `applyThemeByName`
				-- drops the cached blueprint when the answer changes — which on a flat
				-- package it never does, because a flat package charges nothing.
				overlayModel.splitAction = rows.themeInset(env:get("themeMetrics"):get()).x > 0
				overlayBlueprint = overlayLib.build(Facet, core, overlayModel)
			end
			return overlayBlueprint
		end

		local function presentOverlay()
			if overlayHandle ~= nil or settings.cleanCapture then
				return false
			end
			overlayHandle = ctx.presenter.present(overlayScreen(), overlayOpts())
			return true
		end

		-- Z-ORDER IS PRESENT ORDER (presenter §2.2), so the overlay is re-presented
		-- after anything else mounts. The showcase bootstrap raises its chrome the
		-- same way and for the same reason.
		raiseOverlay = function(): boolean
			if overlayHandle == nil or settings.cleanCapture then
				return false
			end
			ctx.presenter.dismiss(overlayHandle)
			overlayHandle = ctx.presenter.present(overlayScreen(), overlayOpts())
			return true
		end

		local function dismissOverlay()
			if overlayHandle == nil then
				return false
			end
			ctx.presenter.dismiss(overlayHandle)
			overlayHandle = nil
			-- clean capture gets the whole screen back
			reserveBottom(0)
			return true
		end

		-- assigned to the forward declaration above `applyThemeByName`, which is defined
		-- earlier in this function and cannot close over a later local
		rebuildOverlayForTheme = function()
			local want = rows.themeInset(env:get("themeMetrics"):get()).x > 0
			if overlayBlueprint == nil or overlayModel.splitAction == want then
				return
			end
			overlayBlueprint = nil
			if overlayHandle ~= nil then
				ctx.presenter.dismiss(overlayHandle)
				overlayHandle = nil
				presentOverlay()
			end
		end

		-- ---- steps (the MCP + overlay surface) --------------------------------
		local steps: { [string]: any } = {}

		-- `select:scenario=dense-scroll,rows=2000,seed=7,content=normal,theme=flat`
		steps.select = function(_self: any, payload: string?)
			local applied: { string } = {}
			for pair in string.gmatch(payload or "", "[^,]+") do
				local key, value = string.match(pair, "^%s*([%w_]+)%s*=%s*(.-)%s*$")
				if key == nil then
					continue
				end
				if key == "scenario" then
					local w = WORKLOAD_BY_ID[value]
					assert(
						w ~= nil,
						`[perf lab] unknown scenario '{value}' (have: {table.concat(WORKLOAD_ORDER, ", ")})`
					)
					settings.scenario = value
					settings.implementation = w.implementation
					-- A WORKLOAD THAT DOES NOT DECLARE A SETTING GETS THE DEFAULT, NOT
					-- THE LAST WORKLOAD'S. `if w.content ~= nil` looks harmless and is
					-- the reason Run all was order-dependent: `large-text-overflow`
					-- declares `content = "identity"`, and every workload after it in
					-- the sweep silently inherited long identity strings. Three
					-- workloads failed their layout audit for a reason that had nothing
					-- to do with them, and running any of them alone passed — the worst
					-- shape a determinism bug can take.
					--
					-- Selecting a scenario now states the WHOLE workload-owned setting
					-- set, so "select X" means the same thing whatever ran before it.
					settings.content = w.content or DEFAULT_CONTENT
					settings.theme = w.theme or DEFAULT_THEME
					currentScenario:set(value)
				elseif key == "impl" or key == "implementation" then
					assert(
						value == "facet" or value == "native" or value == "none",
						`[perf lab] implementation must be facet|native|none, got '{value}'`
					)
					settings.implementation = value
				elseif key == "rows" then
					local n = tonumber(value)
					assert(n ~= nil, "[perf lab] rows must be a number")
					settings.rows = math.clamp(math.floor(n), 0, dataset.MAX_ROWS)
				elseif key == "seed" then
					settings.seed = math.floor(tonumber(value) or 1)
				elseif key == "content" then
					settings.content = value
				elseif key == "theme" then
					-- APPLY IT, do not merely record it. `select:theme=X` used to set this
					-- field and nothing else: only the `themeSwap`/`themeCost` passes ever
					-- installed a package, so selecting a theme and mounting produced the
					-- FLAT surface while `settings.theme` said otherwise — and
					-- `steps.export` writes `theme = settings.theme` into every capture
					-- row. A capture that names a theme the surface is not wearing is not
					-- a comparable measurement, it is a wrong one.
					applyThemeByName(value)
				elseif key == "recycle" then
					settings.recycle = value == "on" or value == "true"
				elseif key == "incremental" then
					settings.incremental = value == "on" or value == "true"
				elseif key == "warmup" then
					settings.warmupFrames = math.floor(tonumber(value) or 30)
				elseif key == "frames" then
					settings.captureFrames = math.floor(tonumber(value) or 120)
				else
					error(`[perf lab] unknown setting '{key}'`)
				end
				table.insert(applied, key)
			end
			rebuildDataset()
			-- THE PASS LOG BELONGS TO ONE WORKLOAD. `select` changes the workload
			-- identity (scenario, row count, seed, content), so passes recorded under
			-- the previous one must not travel inside the next capture row — the first
			-- exported row carried 800-row passes beside a 2 000-row header.
			passLog = {}
			refreshCounters()
			statusLine:set("ready")
			return {
				applied = applied,
				settings = table.clone(settings),
				datasetDigest = dataset.digest(rowsSignal:get()),
				workload = WORKLOAD_BY_ID[settings.scenario],
			}
		end

		-- `fault:window=on` / `fault:window=off`
		steps.fault = function(_self: any, payload: string?)
			local which, state = string.match(payload or "", "^([%w_]+)=(%w+)$")
			assert(which == "window", `[perf lab] the only declared fault is 'window', got '{tostring(payload)}'`)
			settings.faultWindow = state == "on" or state == "true"
			return {
				fault = "window",
				active = settings.faultWindow,
				note = "with the fault active the list is built to materialize its whole logical collection; the next "
					.. "`mount` MUST fail the bounded-window assertion. If it does not, the assertion is not wired.",
			}
		end

		steps.mount = function()
			local result = mount()
			refreshCounters()
			statusLine:set("mounted")
			return result
		end

		steps.unmount = function()
			local torn = unmount()
			ctx.presenter.refresh()
			refreshCounters()
			statusLine:set("idle")
			return { torn = torn, guiObjects = telemetry.instances().guiObjects }
		end

		steps.warmup = function(_self: any, payload: string?)
			local frames = math.clamp(math.floor(tonumber(payload or "") or settings.warmupFrames), 0, 600)
			statusLine:set("warming")
			for _ = 1, frames do
				ctx.presenter.refresh()
				telemetry.step()
			end
			statusLine:set("ready")
			return { warmedFrames = frames }
		end

		steps.pass = function(_self: any, payload: string?)
			local name, arg = string.match(payload or "", "^([%w_]+)=(.*)$")
			if name == nil then
				name = payload
			end
			local fn = passes[tostring(name)]
			assert(fn ~= nil, `[perf lab] unknown pass '{tostring(name)}'`)
			statusLine:set(`pass:{name}`)
			local result = fn(arg)
			refreshCounters()
			statusLine:set("ready")
			return result
		end

		-- WHERE THE FRAME ACTUALLY WENT, readable from Lua (PL-17, added 2026-08-05).
		--
		-- The framework already annotates nine phase scopes for the MicroProfiler, and
		-- until now reading them meant a human pressing Ctrl/Cmd+F6 and eyeballing a
		-- dump. That makes the optimization loop manual at exactly the step that has to
		-- repeat: measure, change one thing, measure again.
		--
		-- `profile.setHooks` is the seam that fixes it — the SAME scopes, timed with the
		-- wall clock instead of handed to the engine. INCLUSIVE and EXCLUSIVE are both
		-- reported: inclusive says which phase owns the frame, exclusive says which one
		-- is doing the work, and optimizing against the wrong one of those is how a
		-- caller gets blamed for its callee.
		--
		-- THE HOOKS COST SOMETHING. Two `os.clock()` calls and a table push per scope is
		-- not free, and the scope counts here run to six figures — so these numbers are
		-- for ATTRIBUTION (which phase, what share), never for a capture row. The
		-- headline ms stays the pass's own wall clock, taken with the hooks off. That is
		-- why this is its own step rather than something `pass` always does.
		steps.scopes = function(_self: any, payload: string?)
			local name, arg = string.match(payload or "", "^([%w_]+)=(.*)$")
			if name == nil then
				name = payload
			end
			local fn = passes[tostring(name)]
			assert(fn ~= nil, `[perf lab] unknown pass '{tostring(name)}'`)
			local incl: { [string]: number } = {}
			local excl: { [string]: number } = {}
			local calls: { [string]: number } = {}
			local parents: { [string]: { [string]: number } } = {}
			-- ONE STACK PER THREAD, and this is load-bearing rather than tidy. The pass
			-- body runs on the caller's coroutine and waits a Heartbeat between steps,
			-- while the lab bootstrap opens its own `scenario` scope on the Heartbeat
			-- connection's thread every frame. With a single shared stack those two
			-- interleave, and the first run of this instrument charged `scenario` 2.04
			-- ms/frame of EXCLUSIVE time it does not spend — the sibling phases were
			-- being subtracted from the wrong parent. `debug.profilebegin` is itself
			-- per-thread (see the yield rule in src/core/profile.luau); this matches it.
			local stacks: { [thread]: { any } } = {}
			local function stackFor(): { any }
				local co = coroutine.running()
				local existing = stacks[co]
				if existing == nil then
					existing = {}
					stacks[co] = existing
				end
				return existing
			end
			-- EXCLUSIVE IS TOTAL MINUS CHILD TIME, and `child` accumulates on the way
			-- OUT: a scope adds its own total to its parent's child bucket as it pops.
			--
			-- The first version of this accumulated on the way IN — parent.child += the
			-- gap since the parent was last innermost — which is the parent's OWN self
			-- time, not its children's. That inverts the two numbers for every scope
			-- that has children: `scenario` reported 2.15 ms/frame of "exclusive" work
			-- while its body is two calls that are both scoped, and the real answer was
			-- that it spends essentially nothing itself. Leaf scopes were unaffected,
			-- which is exactly what made it survive a reading.
			local function begin(key: string)
				local now = os.clock()
				local stack = stackFor()
				table.insert(stack, { key = key, t0 = now, child = 0 })
			end
			local function finish()
				local now = os.clock()
				local stack = stackFor()
				local e = table.remove(stack)
				if e == nil then
					return
				end
				local total = now - e.t0
				incl[e.key] = (incl[e.key] or 0) + total
				excl[e.key] = (excl[e.key] or 0) + (total - e.child)
				calls[e.key] = (calls[e.key] or 0) + 1
				local parent = stack[#stack]
				-- WHO OPENED THIS, recorded rather than assumed. The first read of this
				-- instrument showed `scenario` holding 2.15 ms/frame of exclusive time
				-- while its documented children looked free, and there is no way to
				-- tell a real cost from a nesting bug without asking the stack.
				local under = if parent ~= nil then parent.key else "(root)"
				local byKey = parents[e.key]
				if byKey == nil then
					byKey = {}
					parents[e.key] = byKey
				end
				byKey[under] = (byKey[under] or 0) + 1
				if parent ~= nil then
					parent.child += total
				end
			end
			statusLine:set(`scopes:{name}`)
			profile.setHooks(begin, finish)
			local ok, result = pcall(fn, arg)
			-- RESTORED ON THE FAILURE PATH TOO. Leaving the hooks installed would keep
			-- charging every later pass for this instrument and would silently steal the
			-- scopes back from the MicroProfiler for the rest of the session.
			profile.setHooks(nil, nil)
			statusLine:set("ready")
			if not ok then
				error(result, 0)
			end
			local rows = {}
			for key, v in incl do
				local under = {}
				for parentKey, count in parents[key] or {} do
					table.insert(under, `{parentKey}x{count}`)
				end
				table.sort(under)
				table.insert(rows, {
					scope = key,
					inclusiveMs = v * 1000,
					exclusiveMs = (excl[key] or 0) * 1000,
					n = calls[key] or 0,
					under = table.concat(under, ","),
				})
			end
			table.sort(rows, function(a, b)
				return a.exclusiveMs > b.exclusiveMs
			end)
			refreshCounters()
			return {
				pass = name,
				-- the pass's own headline, so a reader can see how much of it the
				-- instrument itself added
				passMs = (result :: any).ms,
				unbalanced = (function(): number
					local left = 0
					for _, st in stacks do
						left += #st
					end
					return left
				end)(),
				scopes = rows,
			}
		end

		-- run the SELECTED workload's declared pass sequence, in order
		steps.run = function()
			local w = WORKLOAD_BY_ID[settings.scenario]
			assert(w ~= nil, "[perf lab] no scenario selected")
			statusLine:set("capturing")
			local results = {}
			for _, name in w.passes do
				if emergencyStopped then
					break
				end
				local fn = passes[name]
				assert(fn ~= nil, `[perf lab] scenario '{w.id}' names an unknown pass '{name}'`)
				table.insert(results, fn(nil))
			end
			refreshCounters()
			statusLine:set("ready")
			return { scenario = w.id, question = w.question, passes = results, stopped = emergencyStopped }
		end

		steps.stop = function()
			emergencyStopped = true
			-- ...and the loop flag, which no pass may clear (see its declaration)
			profileStopRequested = true
			statusLine:set("STOPPED")
			return { stopped = true, note = "the ramp and the soak check this flag between steps" }
		end

		steps.resume = function()
			emergencyStopped = false
			profileStopRequested = false
			statusLine:set("ready")
			return { stopped = false }
		end

		steps.cleanCapture = function(_self: any, payload: string?)
			local on = payload == "on" or payload == "true"
			settings.cleanCapture = on
			if on then
				dismissOverlay()
			else
				presentOverlay()
			end
			ctx.presenter.refresh()
			return {
				cleanCapture = on,
				overlayMounted = overlayHandle ~= nil,
				note = "clean capture DISMISSES the overlay rather than hiding it: a hidden ScreenGui is still a "
					.. "mounted tree the census counts and the frame pays for",
			}
		end

		-- ONE action back to the idle baseline, and it PROVES teardown rather than
		-- asserting it: the census before and after travel in the result.
		steps.reset = function()
			local before = {
				guiObjects = telemetry.instances().guiObjects,
				connections = telemetry.connections(),
				luaHeapKb = telemetry.memory().luaHeapKb,
				core = core:counters(),
			}
			unmount()
			settings.implementation = "none"
			settings.scenario = "idle-baseline"
			currentScenario:set("idle-baseline")
			settings.rows = 2000
			settings.seed = 1
			settings.content = "normal"
			settings.resourceState = "cold"
			emergencyStopped = false
			rampIndex = 0
			passLog = {}
			rebuildDataset()
			presentOverlay()
			ctx.presenter.refresh()
			local after = {
				guiObjects = telemetry.instances().guiObjects,
				connections = telemetry.connections(),
				luaHeapKb = telemetry.memory().luaHeapKb,
				core = core:counters(),
			}
			refreshCounters()
			statusLine:set("idle")
			return {
				before = before,
				after = after,
				mounted = mounted ~= nil,
				overlayMounted = overlayHandle ~= nil,
				note = "back to idle-baseline. The workload's Instances must be gone; the overlay's remain by design "
					.. "and are counted separately",
			}
		end

		steps.counters = function()
			refreshCounters()
			return {
				settings = table.clone(settings),
				mountedRows = mountedRowCount(),
				windowBound = windowBound(),
				logicalRows = #rowsSignal:get(),
				instances = telemetry.instances(),
				connections = telemetry.connections(),
				memory = telemetry.memory(),
				core = core:counters(),
				profiler = profile.counters(),
				provider = provider.counters and provider.counters() or nil,
				render = renderStats(),
				-- the chrome art ledger, including the LIFTED LABEL FIT check: a themed
				-- control whose label was lifted into chrome-derived geometry the solver
				-- never measured. Surfaced here because the layout audit cannot see that
				-- seam — it lives past the solve, in the adapter.
				chromeArt = (function(): any
					if ctx.themeChrome == nil or ctx.themeChrome.artJudgement == nil then
						return nil
					end
					local ok, art = pcall(ctx.themeChrome.artJudgement)
					return if ok then art else nil
				end)(),
				passes = passLog,
			}
		end

		-- The CAPTURE ROW (PL-9). Assembled here, judged by capture.problems, and
		-- refused rather than exported when a required condition is missing.
		steps.export = function(_self: any, payload: string?)
			local repeatN = math.floor(tonumber(payload or "") or 1)
			local frame = telemetry.frameWork and telemetry.frameWork(settings.captureFrames) or { measured = false }
			local hostFacts = if host.facts ~= nil then host.facts() else {}
			local scopes = profile.counters()
			local row: any = {
				schema = capture.SCHEMA,
				evidenceClass = hostFacts.evidenceClass or "lune",
				capturedAtIso = hostFacts.capturedAtIso,
				repeat_ = repeatN,
				-- workload identity
				scenario = settings.scenario,
				scenarioVersion = SCENARIO_VERSION,
				datasetVersion = dataset.VERSION,
				rowVersion = rows.VERSION,
				implementation = settings.implementation,
				rows = settings.rows,
				seed = settings.seed,
				content = settings.content,
				theme = settings.theme,
				datasetDigest = dataset.digest(rowsSignal:get()),
				resourceState = settings.resourceState,
				-- conditions. NOT defaulted: a fact the host did not supply must arrive
				-- here as nil so `capture.problems` refuses the row. Substituting
				-- "unknown" would make every capture admissible and none comparable.
				frameworkVersion = Facet.VERSION,
				sourceStamp = hostFacts.sourceStamp,
				placeName = hostFacts.placeName,
				viewport = hostFacts.viewport,
				orientation = hostFacts.orientation,
				graphicsQualityLevel = hostFacts.graphicsQualityLevel,
				frameTarget = hostFacts.frameTarget,
				studioVersion = hostFacts.studioVersion,
				deviceLabel = hostFacts.deviceLabel,
				thermalNote = hostFacts.thermalNote,
				deviceModel = hostFacts.deviceModel,
				osVersion = hostFacts.osVersion,
				clientVersion = hostFacts.clientVersion,
				powerState = hostFacts.powerState,
				-- method
				warmupFrames = settings.warmupFrames,
				captureFrames = settings.captureFrames,
				cleanCapture = settings.cleanCapture,
				profilerScopes = scopes.enabled and scopes.engine,
				-- results
				frame = frame,
				counters = {
					mountedRows = mountedRowCount(),
					windowBound = windowBound(),
					logicalRows = #rowsSignal:get(),
					instances = telemetry.instances(),
					connections = telemetry.connections(),
					memory = telemetry.memory(),
					core = core:counters(),
					provider = provider.counters and provider.counters() or nil,
					overlayMounted = overlayHandle ~= nil,
				},
				scopes = scopes,
				passes = passLog,
				capturePath = hostFacts.capturePath or "not captured in this run",
				summaryPath = hostFacts.summaryPath or "not derived in this run",
			}
			local problems = capture.problems(row)
			lastCapture = row
			return {
				row = row,
				admissible = #problems == 0,
				problems = problems,
				note = if #problems == 0
					then "admissible: this row carries every condition needed to compare it with another"
					else "INADMISSIBLE — a row missing its conditions cannot be compared with anything",
			}
		end

		-- the automatic sequence: every workload, in order, at the current dataset
		-- RUN EVERYTHING, IN ORDER, FROM ONE PRESS. This is the shape a profiling
		-- session actually wants: arm the MicroProfiler, press one button, let all nine
		-- workloads run back to back, then take a single dump that contains the whole
		-- sweep with every phase scope in it.
		--
		-- ONE WORKLOAD'S FAILURE DOES NOT END THE SWEEP. The first version let the
		-- error out, so a scenario that cannot mount in this environment (the
		-- raw-Roblox reference needs a host seam that only the real place supplies)
		-- aborted everything after it — and the person who pressed the button got a
		-- console error and eight missing results. Each workload is now attempted
		-- independently and its failure is RECORDED, in the results and on the status
		-- line, which is louder than an error nobody scrolls up to read.
		steps.sequence = function(_self: any, payload: string?)
			local only = payload
			local plan = {}
			for _, id in WORKLOAD_ORDER do
				if only == nil or only == "" or only == id then
					table.insert(plan, id)
				end
			end
			local results = {}
			local failed = 0
			local index = 0
			for _, id in plan do
				if emergencyStopped then
					break
				end
				index += 1
				statusLine:set(`running {index}/{#plan} · {id}`)
				refreshCounters()
				local ok, outcome = pcall(function()
					unmount()
					steps.select(nil, `scenario={id}`)
					mount()
					return steps.run()
				end)
				if ok then
					table.insert(results, outcome)
				else
					failed += 1
					pcall(unmount)
					table.insert(results, { scenario = id, failed = true, error = tostring(outcome) })
				end
			end
			pcall(unmount)
			refreshCounters()
			-- THE END STATE IS AN INSTRUCTION. The sweep is over and the profiler buffer
			-- is full; what happens next is a key press, so the panel says which one
			-- rather than leaving the person to remember it.
			local ranAll = index == #plan and not emergencyStopped
			local head = if emergencyStopped
				then `STOPPED at {index}/{#plan}`
				elseif failed > 0 then `DONE {index}/{#plan}, {failed} FAILED`
				else `DONE {index}/{#plan}`
			statusLine:set(`{head} — dump now: Ctrl/Cmd+F6, Ctrl+P to pause`)
			return {
				ran = #results,
				planned = #plan,
				failed = failed,
				completedWholeSweep = ranAll and failed == 0,
				results = results,
				stopped = emergencyStopped,
				dumpNext = "Ctrl+F6 (Cmd+F6 on macOS) opens the MicroProfiler, Ctrl+P pauses it, then "
					.. "Dump -> Dump in binary format. See docs/guide/12-performance-lab.md 12.4.",
			}
		end

		--[[ PROFILE ONE WORKLOAD, ON A LOOP, UNTIL SOMEBODY TAKES THE DUMP.

			WHY THIS EXISTS, from the first physical-device capture this project ever
			had (game director, 2026-08-13, Galaxy A10e, `perfPlace2gb.html`). The
			director armed the MicroProfiler, pressed `Run all` twice, and dumped
			during the second sweep. The dump held **30 frames — 1.08 seconds**. A
			`Run all` sweep is tens of seconds long, so it sampled a random second of
			it, and the second it drew was `dense-scroll-native`: the one workload
			with **no Facet code in it at all**.

			The result: `measure`, `arrange`, `commit`, `mount`, `react` and `reset`
			had ZERO occurrences in the window, and `mutate`/`resource` had never been
			entered in the whole session. Nine of the twelve scopes produced no data,
			and those six are exactly the ones every device estimate in
			`artifacts/performance-stress-places/` rests on. The workloads were fine;
			the SAMPLING failed.

			`Run all` cannot be fixed by pressing it harder. A capture window is ~1s
			and a sweep is ~30s, so any single dump sees ~3% of it and cannot be aimed.
			This step inverts that: it mounts ONE workload and repeats its declared
			pass forever, so wherever the 1s window lands it lands INSIDE the thing
			being measured. Press it, arm the profiler, dump whenever.

			It is deliberately not time-boxed. A fixed duration would just re-create
			the aiming problem one level down — the person taking the dump would have
			to hit a window again. It runs until `Stop`. ]]
		steps.profileWindow = function(_self: any, payload: string?)
			--[[ payload: "" | "<workload>" | "<workload>:<pass>" | "<workload>:<pass>:<laps>"

				`laps` defaults to 0 = UNBOUNDED, which is the shape a profiling
				session wants: a fixed duration would just re-create the aiming
				problem one level down, with the operator having to hit a window
				again. A bounded count exists for two real cases — a scripted run
				that must terminate, and this file's own spec, which cannot
				interrupt an infinite loop because the headless harness's pass is
				synchronous and Lune has no `task` library. ]]
			local wantWorkload, wantPass, wantLaps = nil, nil, nil
			if payload ~= nil and payload ~= "" then
				-- SPLIT ON ":" KEEPING EMPTY SEGMENTS, without `[^:]*` — that pattern
				-- also matches the empty string BETWEEN characters, so
				-- "a:b:2" yields {"a","","b","","2",...} and every index after the
				-- first is shifted. It cost an infinite loop: the laps segment
				-- landed on parts[3] = "scrollSteady", tonumber returned nil, the
				-- cap fell back to 0 = unbounded, and the spec hung the suite.
				local parts = {}
				local from = 1
				while true do
					local at = string.find(payload, ":", from, true)
					if at == nil then
						table.insert(parts, string.sub(payload, from))
						break
					end
					table.insert(parts, string.sub(payload, from, at - 1))
					from = at + 1
				end
				wantWorkload = if parts[1] == nil or parts[1] == "" then nil else parts[1]
				wantPass = if parts[2] == nil or parts[2] == "" then nil else parts[2]
				wantLaps = if parts[3] == nil or parts[3] == "" then nil else tonumber(parts[3])
			end
			local maxLaps = wantLaps or 0
			local id = wantWorkload or settings.scenario
			local w = WORKLOAD_BY_ID[id]
			if w == nil then
				error(
					`[Facet PerfLab] profileWindow: unknown workload '{tostring(id)}'. `
						.. `Legal: {table.concat(WORKLOAD_ORDER, ", ")}.`,
					0
				)
			end
			--[[ REFUSE A WORKLOAD WITH NO FACET IN IT.

				TWO CONSECUTIVE DEVICE CAPTURES SAMPLED `dense-scroll-native`, the one
				workload whose `implementation = "native"` means it runs the raw-Roblox
				reference list and calls no framework code at all. Both dumps therefore
				recorded ZERO occurrences of `measure`, `arrange`, `commit`, `mount`,
				`react` and `reset` — the six scopes every device estimate in
				`artifacts/performance-stress-places/` rests on — and the 22x
				extrapolation in `low-end-target.md` is still untested because of it.

				Nothing on screen said which implementation was mounted, so the mistake
				was invisible until the dump was parsed. It is refused here instead:
				profiling the native reference is a legitimate thing to want, but it has
				to be asked for in words. ]]
			if w.implementation == "native" and wantWorkload == nil then
				error(
					`[Facet PerfLab] profileWindow: '{id}' is the raw-Roblox reference `
						.. `(implementation = "native") — it calls NO Facet code, so a capture of it `
						.. `records zero solver scopes. Two device captures have already been lost this `
						.. `way. Select a Facet workload, or ask for this one explicitly: `
						.. `profileWindow:{id}`,
					0
				)
			end
			--[[ ONE PASS, LOOPED — not the workload's whole declared sequence.

				The first version looped `steps.run()`, which runs every pass the
				workload declares (`dense-scroll` declares seven). `scrollSteady` alone
				is 60 steps ~= 60 Heartbeats, and at the ~23 fps this device achieves a
				MicroProfiler dump holds ~30 frames / ~1.3 s — so the window cannot
				escape pass #1 and the other six were never sampled. The aiming problem
				moved down one level instead of going away.

				So the loop is over ONE pass, named, defaulting to the workload's first.
				A capture then contains that pass and nothing else.

				...AND THE DEFAULT IS `profilePass` WHEN THE WORKLOAD DECLARES ONE.
				`passes[1]` is the first step of the workload's declared SEQUENCE,
				which is not always a step that survives being looped — see
				`async-image-churn`, whose first three passes are one-shot state
				changes and whose device capture is twenty-nine identical frames as a
				result. An explicit `wantPass` still wins over both. ]]
			local passName = wantPass or w.profilePass or w.passes[1]
			if passes[passName] == nil then
				error(
					`[Facet PerfLab] profileWindow: '{id}' declares no pass '{tostring(passName)}'. `
						.. `Its passes: {table.concat(w.passes, ", ")}.`,
					0
				)
			end
			emergencyStopped = false
			profileStopRequested = false
			unmount()
			steps.select(nil, `scenario={id}`)
			mount()
			refreshCounters()
			-- SAY WHAT IS BEING PROFILED, LOUDLY AND ON EVERY LAP. A dump carries no
			-- workload label, so both previous captures had to be identified by
			-- reverse-engineering their Text-write signature. This line is what a
			-- capture session pastes back with the dump.
			--[[ STAMP THE IDENTITY WHERE A LATER READER CAN FIND IT.

				A MicroProfiler dump carries no workload label, and `warn` does not
				survive into the blob. Consequence, measured across five device
				captures: EVERY ONE had to be identified by forensic signature — the
				presence of solver scopes, per-mount child counts, whether
				`Facet/reset` ever fires. Three had sampled a session with nothing
				mounted, one pair turned out to be byte-identical duplicates of each
				other, and a capture filed as `mount-ramp` contained no ramp data at
				all.

				Workspace attributes are the cheapest thing a later reader can check:
				`execute_luau` reads them in the same session, and it is one write per
				profiling run rather than per frame. It does not put the label INSIDE
				the dump — nothing script-side can — but it makes the SESSION
				self-describing, which is the half that was missing.

				Deliberately NOT a new profile scope: `profile.MAX_SCOPES = 12` is
				asserted by `tests/profile_scopes.spec.luau`, and a per-workload scope
				name is exactly the per-call-site label the cardinality rule exists to
				forbid. ]]
			-- pcall'd because `workspace` does not exist under Lune, where this same
			-- step runs in the suite. The lab is engine-free by construction
			-- everywhere else; this is the one write that is not, so it degrades
			-- rather than refusing.
			pcall(function()
				local ws = workspace :: any
				ws:SetAttribute("Facet_ProfilingWorkload", id)
				ws:SetAttribute("Facet_ProfilingPass", passName)
				ws:SetAttribute("Facet_ProfilingImplementation", tostring(w.implementation or "facet"))
				ws:SetAttribute("Facet_ProfilingRows", settings.rows)
				ws:SetAttribute("Facet_ProfilingTheme", tostring(settings.theme))
			end)
			warn(
				`[perf lab] PROFILING workload='{id}' pass='{passName}' implementation='{tostring(
					w.implementation or "facet"
				)}' `
					.. `rows={settings.rows} theme='{tostring(settings.theme)}' viewport={(function()
						local v = env:get("viewportRect"):get()
						return `{math.floor(v.w)}x{math.floor(v.h)}`
					end)()}`
			)
			--[[ WHAT ONE LAP PROVOKED, ON THE PHONE, BEFORE THE DUMP IS TAKEN.

				Three device captures have now been lost to aiming, and each one was
				invisible until a binary MicroProfiler dump had been parsed on a
				laptop: two sampled a workload with no framework in it, and
				`asyncImage.html` (2026-08-15) sampled `imagesCold`, a pass whose lap
				is one solve and no structural work — twenty-nine byte-identical
				frames. `profilePass` above aims the default; this is the guard for
				every future version of the same mistake, including one in a pass
				nobody has written yet.

				A READOUT, NOT A REFUSAL, and deliberately so: `idle-baseline` is a
				legitimate zero, and a threshold separating "inert" from "cheap" would
				be a number invented here rather than measured. The operator holding
				the phone can read `mount=0 arrange=1` and not bother dumping.

				`measured` is the honesty field. `cleanCapture` turns phase scopes OFF
				(`scopeCount` is nil-safe and returns 0 either way), so a bare zero
				would accuse a healthy pass of exactly the defect this exists to
				catch. Zero never stands in for "not counted". ]]
			local LAP_SCOPES = { "arrange", "measure", "mount", "react", "commit", "resource", "reset" }
			local function lapCounts(): { [string]: number }
				local out: { [string]: number } = {}
				for _, key in LAP_SCOPES do
					out[key] = scopeCount(key)
				end
				return out
			end
			local lapWork: any = { measured = false }
			local laps = 0
			while not profileStopRequested and (maxLaps <= 0 or laps < maxLaps) do
				laps += 1
				--[[ THE COUNTERS SURVIVE THE LAP BOUNDARY, and that is a bug fix
					(director, 2026-08-17: "the line flashes really quickly to where
					it's hard to read").

					This used to set a counter-LESS line at the top of every lap and a
					counter-bearing one at the bottom, so the reading an operator has to
					check before spending a dump — `arrange=` — was visible only in the
					gap between one lap ending and the next beginning. On `host-move`
					that gap is a few milliseconds, because a lap is 24 reps and
					finishes well under a second. The number was there and unreadable,
					which for a human-in-the-loop instrument is the same as absent.

					So the last measured lap's counters ride the line until the next
					lap replaces them. Only `lap N` changes on a healthy run, which is
					also what makes "the lap counter is climbing" legible at a glance. ]]
				statusLine:set(
					if lapWork.measured
						then `PROFILING {id}/{passName} · lap {laps} · arrange={lapWork.arrange} mount={lapWork.mount} `
							.. `react={lapWork.react} resource={lapWork.resource} — DUMP NOW: Ctrl/Cmd+F6, then Ctrl+P`
						else `PROFILING {id}/{passName} · lap {laps} — warming up, no counters yet`
				)
				local before = lapCounts()
				local ok, err = pcall(function()
					passes[passName]()
				end)
				if not ok then
					statusLine:set(`PROFILING {id}/{passName} FAILED on lap {laps}: {tostring(err)}`)
					break
				end
				local after = lapCounts()
				local moved = false
				local work: any = {}
				for _, key in LAP_SCOPES do
					work[key] = after[key] - before[key]
					if after[key] > 0 then
						moved = true
					end
				end
				-- ONE scope having ever fired is what says the instrument is on; a lap
				-- whose own deltas are all zero is the finding, not the failure.
				work.measured = moved
				lapWork = work
				if moved then
					statusLine:set(
						`PROFILING {id}/{passName} · lap {laps} · arrange={work.arrange} mount={work.mount} `
							.. `react={work.react} resource={work.resource} — DUMP NOW: Ctrl/Cmd+F6, then Ctrl+P`
					)
				end
				--[[ YIELD BETWEEN LAPS, UNCONDITIONALLY — the loop must not depend
					on the pass to do it.

					DEVICE REPORT, 2026-08-13: `mount-ramp` and `resize-relayout` each
					HUNG the director's phone, `mount-ramp` leaving a blank screen.
					Root cause, from source: of the three passes a window is likely to
					loop, only `scrollSteady` yields — it waits a Heartbeat per step.
					`resizeStorm` and `ramp` have ZERO yield sites and run their whole
					ladder synchronously. Looping either with no yield is a tight
					infinite loop on the driving coroutine, which is exactly what a
					frozen phone looks like. `dense-scroll` worked for precisely the
					reason the other two did not.

					`telemetry.step()` rather than `task.wait()`: it is the lab's own
					frame-yield seam, real on the engine and a no-op stub headless, so
					this loop stays runnable in the suite. ]]
				telemetry.step()
			end
			pcall(unmount)
			refreshCounters()
			statusLine:set(`profileWindow stopped after {laps} lap(s) of {id}/{passName}`)
			return {
				scenario = id,
				pass = passName,
				implementation = w.implementation or "facet",
				laps = laps,
				maxLaps = maxLaps,
				stopped = emergencyStopped,
				-- the scope deltas of the LAST lap; `measured = false` means phase
				-- scopes were off, never that the lap did nothing
				lapWork = lapWork,
				note = "ONE pass on a loop, so a ~1s MicroProfiler window cannot miss it and cannot "
					.. "drift into a later pass. Press Stop to end. Dump: Ctrl+F6 (Cmd+F6 on macOS), "
					.. "Ctrl+P to pause, then Dump -> Dump in binary format.",
			}
		end

		steps.workloads = function()
			return { order = WORKLOAD_ORDER, workloads = WORKLOADS, scenarioVersion = SCENARIO_VERSION }
		end

		--[[ THE ARM POINTER'S TWO OPERATIONS, defined once and reachable from a test.

			A control only a person can press is a control only a person can catch when it
			breaks — the same reason `overlayControls` exposes the scenario cycler. Both
			are exported there. ]]
		local function armIndexOf(w: any): number
			local current = profileArm[w.id]
			if current ~= nil then
				return math.clamp(current, 1, math.max(1, #w.passes))
			end
			-- not yet touched: start from the arm `profileWindow` would pick on its own,
			-- so the FIRST press advances off the default rather than landing back on it
			local want = w.profilePass or w.passes[1]
			for i, name in w.passes do
				if name == want then
					return i
				end
			end
			return 1
		end
		local function advanceArm(): string?
			local w = WORKLOAD_BY_ID[settings.scenario]
			if w == nil or #w.passes == 0 then
				-- `idle-baseline` declares no passes at all, and a button that silently
				-- does nothing is worse than one that says why
				statusLine:set(`'{tostring(settings.scenario)}' declares no passes — nothing to arm`)
				return nil
			end
			local nextIndex = armIndexOf(w) % #w.passes + 1
			profileArm[w.id] = nextIndex
			local name = w.passes[nextIndex]
			statusLine:set(`arm {nextIndex}/{#w.passes}: {name} — press Profile 1`)
			return name
		end
		-- the payload `Profile 1` hands `profileWindow`: nil until the arm button has
		-- been pressed for this workload, so an untouched lab is unchanged
		function selectedArmPayload(): string?
			local id = settings.scenario
			local w = WORKLOAD_BY_ID[id]
			if w == nil or profileArm[id] == nil or #w.passes == 0 then
				return nil
			end
			return `{id}:{w.passes[math.clamp(profileArm[id], 1, #w.passes)]}`
		end

		-- the overlay's action row, wired now that the steps exist
		overlayModel.actions = {
			-- FIRST, because it is what a profiling session actually does: arm the
			-- MicroProfiler, press this, take one dump at the end.
			{
				id = "RunAll",
				label = "Run all",
				-- the same handler the always-visible cycler row calls: one
				-- implementation, two places to press it
				run = function()
					overlayModel.onRunAll()
				end,
			},
			{
				id = "Profile1",
				label = "Profile 1",
				-- profile the SELECTED workload on a loop; the whole point is that a
				-- ~1s capture window cannot miss what it is aimed at
				run = function()
					task.spawn(function()
						-- ...at the arm `Arm >` last landed on, if it was ever pressed. An
						-- explicit payload still wins over both, as it always did.
						steps.profileWindow(nil, selectedArmPayload())
					end)
				end,
			},
			{
				id = "Arm",
				-- NEXT ARM, not "run the next arm": see `profileArm`
				label = "Arm >",
				run = function()
					advanceArm()
				end,
			},
			{
				id = "Run",
				label = "Run",
				run = function()
					task.spawn(function()
						steps.run()
					end)
				end,
			},
			{
				id = "Mount",
				label = "Mount",
				run = function()
					if mounted == nil then
						mount()
					else
						unmount()
					end
					refreshCounters()
				end,
			},
			{
				id = "Reset",
				label = "Reset",
				run = function()
					steps.reset()
				end,
			},
			{
				id = "Stop",
				label = "Stop",
				run = function()
					steps.stop()
				end,
			},
			{
				id = "Clean",
				label = "Clean capture",
				run = function()
					steps.cleanCapture(nil, if settings.cleanCapture then "off" else "on")
				end,
			},
		}
		overlayModel.onSelectScenario = function(name: string)
			local ok, err = pcall(function()
				unmount()
				steps.select(nil, `scenario={name}`)
				mount()
			end)
			if not ok then
				-- ON THE PANEL, not in the output window. A failed mount from a button
				-- press used to raise into the presenter, which logs somewhere the
				-- person holding the phone will never look; the workload is left
				-- unmounted either way, so the only question is whether they can see
				-- WHY. The message stays whole in the returned value for the drivers.
				pcall(unmount)
				statusLine:set(`FAILED: {string.sub(tostring(err), 1, 90)}`)
			else
				statusLine:set("ready")
			end
			refreshCounters()
			return ok
		end
		-- WRAPS at both ends, deliberately: a disabled button at the end of a list is a
		-- control that stops working for a reason the person pressing it cannot see, and
		-- the whole point of this row is to get through nine workloads without thinking.
		overlayModel.onRunAll = function()
			task.spawn(function()
				steps.resume()
				steps.sequence(nil, nil)
			end)
		end
		overlayModel.onCycleScenario = function(delta: number)
			local current = currentScenario:get()
			local index = 1
			for i, id in WORKLOAD_ORDER do
				if id == current then
					index = i
					break
				end
			end
			local n = #WORKLOAD_ORDER
			local nextIndex = ((index - 1 + delta) % n + n) % n + 1
			return overlayModel.onSelectScenario(WORKLOAD_ORDER[nextIndex])
		end

		remountForArrangement = function()
			if mounted == nil then
				return
			end
			local impl = settings.implementation
			unmount()
			settings.implementation = impl
			mount()
		end
		labScope:own(core:observe(isCompact, function()
			local ok, err = pcall(remountForArrangement)
			if not ok then
				-- A REMOUNT THAT FAILS SILENTLY IS WORSE THAN THE DEFECT. The observer
				-- runs inside the reactive flush, which swallows the error, so the lab
				-- would sit unmounted with no explanation — and the next step would
				-- report "call `mount` first" for a rotation problem. Park it and let
				-- the next assertion raise the real message.
				lastRemountError = tostring(err)
			else
				lastRemountError = nil
			end
		end))

		if ctx.bindResourceTransport ~= nil then
			local ok, unbind = pcall(ctx.bindResourceTransport, provider)
			if ok then
				unbindTransport = unbind
			end
		end

		presentOverlay()
		refreshCounters()

		return {
			-- no `screen`: this scenario owns several surfaces (the overlay and the
			-- selected workload) and swaps them in-session, so presentation is its
			-- own job and the runner must not present one for it
			steps = steps,
			-- THE OVERLAY'S OWN CONTROLS, exposed so they can be TESTED. The scenario
			-- cycler is reachable only by pressing a button on a presented surface, and
			-- a control that only a person can reach is a control that only a person can
			-- catch when it breaks.
			-- Stage-1 boundary analysis, exposed so the measurement can be taken from a
			-- test and from a live Studio session through the same call
			boundaryReport = function(): any
				if mounted == nil or mounted.kind ~= "facet" or mounted.controller == nil then
					return nil
				end
				if mounted.controller.analyzeBoundaries == nil then
					return nil
				end
				local ok, report = pcall(mounted.controller.analyzeBoundaries)
				return if ok then report else nil
			end,
			overlayControls = {
				cycleScenario = function(delta: number)
					return overlayModel.onCycleScenario(delta)
				end,
				selectScenario = function(name: string)
					return overlayModel.onSelectScenario(name)
				end,
				currentScenario = function(): string
					return currentScenario:get()
				end,
				scenarioPosition = function(): string
					return overlayModel.scenarioPosition:get()
				end,
				-- THE ARM SELECTOR, for the same reason the cycler is here: an arm
				-- comparison needs one dump per arm, the operator is holding a phone,
				-- and a control only a person can press is a control only a person can
				-- catch when it breaks.
				advanceArm = function(): string?
					return advanceArm()
				end,
				-- the payload `Profile 1` will hand `profileWindow`; nil until `Arm >`
				-- has been pressed for this workload
				selectedArm = function(): string?
					return selectedArmPayload()
				end,
				status = function(): string
					return statusLine:get()
				end,
			},
			report = function()
				return {
					settings = table.clone(settings),
					scenarioVersion = SCENARIO_VERSION,
					datasetVersion = dataset.VERSION,
					rowVersion = rows.VERSION,
					datasetDigest = dataset.digest(rowsSignal:get()),
					workloads = WORKLOAD_ORDER,
					mountedImplementation = if mounted ~= nil then mounted.kind else "none",
					mountedRows = mountedRowCount(),
					windowBound = windowBound(),
					logicalRows = #rowsSignal:get(),
					overlayMounted = overlayHandle ~= nil,
					emergencyStopped = emergencyStopped,
					passes = passLog,
					profiler = profile.counters(),
					lastCaptureAdmissible = if lastCapture ~= nil then #capture.problems(lastCapture) == 0 else nil,
					lastRemountError = lastRemountError,
				}
			end,
			dispose = function()
				unmount()
				dismissOverlay()
				dataScope:dispose()
				if unbindTransport ~= nil then
					unbindTransport()
				end
				labScope:dispose()
			end,
		}
	end,
}
