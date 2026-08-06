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
-- EXACTLY ONE IMPLEMENTATION IS MOUNTED (PL-5). The LuauUI list and the matched
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
-- scrolling, and the first MicroProfiler capture read exactly that: LuauUI/mount
-- at 12.5ms mean while measure/arrange/commit together were under 2ms. Answering
-- "is steady scrolling smooth" with a seek profile would have blamed the wrong
-- phase. `scrollSteady` advances a fixed pixel rate per frame the way a flick
-- does; `scrollSeek` keeps the old behaviour under its honest name. Both are
-- captured, because both are real.
--
-- /3 (2026-08-05): the row restacks on a compact width (perf-row/2) and the list's
-- rowHeight follows the same decision, so a phone no longer paints rows over each
-- other. The layout audit is now enforced at mount and after every pass.
local SCENARIO_VERSION = "perf-scenarios/4"

-- ---- the declared workloads ----------------------------------------------
-- Each isolates ONE cost so a profile has an interpretable cause. The plan is
-- explicit that a giant "everything churns" workload is worse than none.
local WORKLOADS = {
	{
		id = "idle-baseline",
		implementation = "none",
		question = "What does the place cost before any LuauUI work?",
		passes = {},
	},
	{
		id = "mount-ramp",
		implementation = "luauui",
		question = "How do initial mount, layout, Instance creation and memory scale with row count?",
		passes = { "ramp" },
	},
	{
		id = "dense-scroll",
		implementation = "luauui",
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
		question = "Which cost is unavoidable engine UI work versus LuauUI overhead?",
		passes = { "scrollSteady", "scrollSeek", "selectRow", "updateOne", "updateBatch" },
	},
	{
		id = "collection-churn",
		implementation = "luauui",
		question = "Do updates stay proportional to changed and visible content?",
		passes = { "insert", "remove", "reorder", "selectRow", "scrollSteady" },
	},
	{
		id = "layout-style-churn",
		implementation = "luauui",
		question = "Which invalidations cause unnecessary whole-tree work?",
		passes = { "preferenceSweep", "resize", "themeCost" },
	},
	{
		id = "resize-relayout",
		implementation = "luauui",
		question = "What does a continuous resize cost, and how much of it is re-solving what did not change?",
		passes = { "resizeStorm", "scrollSteady", "updateOne" },
	},
	{
		id = "large-text-overflow",
		implementation = "luauui",
		content = "identity",
		question = "Are measurement, disclosure and any motion bounded without hiding content?",
		passes = { "preferenceSweep", "localeSwap", "scrollSteady", "revealAudit" },
	},
	{
		id = "async-image-churn",
		implementation = "luauui",
		question = "Are decoding, resource lifecycle and UI updates separated and bounded?",
		passes = { "imagesCold", "imagesWarm", "imagesFail", "imagesReuse" },
	},
	{
		id = "lifecycle-soak",
		implementation = "luauui",
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
	title = "LuauUI performance lab",
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
		local LuauUI = ctx.LuauUI
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
			type(lab) == "table" and lab.dataset ~= nil and lab.rows ~= nil and lab.capture ~= nil,
			"[perf lab] ctx.lab must carry { dataset, rows, capture, overlay } — see examples/performance/client/init.client.luau"
		)
		local dataset = lab.dataset
		local rows = lab.rows
		local capture = lab.capture
		local overlayLib = lab.overlay
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
				use(splitControls)
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
		local provider = LuauUI.newResourceProvider(core, { maxConcurrent = 8 })
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
			local shown = {}
			for i = 1, math.min(4, #findings) do
				table.insert(
					shown,
					`{tostring(findings[i].node)}{rectStr(findings[i].node)}: {tostring(findings[i].issue)}`
				)
			end
			return `[perf lab] the solver reported {#findings} layout finding(s) on the {label} surface at {where} — `
				.. `it is painting outside its own boxes, so any number taken from it describes a screen nobody `
				.. `would ship. {table.concat(shown, " | ")}`
		end

		-- BOTH SURFACES, not just the workload. The overlay is its own ScreenGui with
		-- its own controller, and the defect a real device exposed was the two of them
		-- colliding — each individually correct, together unusable. The collision
		-- itself is fixed by the overlay reserving its measured height; auditing the
		-- overlay's own tree is what catches the other half, a control row too wide for
		-- the screen ("Clean capture" clipped at the edge).
		local function layoutProblem(where: string): string?
			if mounted ~= nil and mounted.kind == "luauui" then
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
			if mounted == nil or mounted.kind ~= "luauui" then
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
		local function buildLuauUI()
			local list = LuauUI.newVirtualList(LuauUI, core, {
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
					return rows.cell(LuauUI, core, item, {
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
			local screen = LuauUI.UI.Screen({
				id = "PerfWorkload",
				padding = SCREEN_PADDING,
				gap = SCREEN_GAP,
				children = {
					LuauUI.UI.Text({
						id = "Head",
						text = `LuauUI · {#rowsSignal:get()} rows`,
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
				kind = "luauui",
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
					mounted = buildLuauUI()
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
		-- them. Each is wrapped in the driver's `LuauUI/scenario` scope so a
		-- MicroProfiler capture can find the workload inside the frame.
		local passes: { [string]: (payload: string?) -> any } = {}

		-- NO SPAN HERE (Roblox-platform review 2026-08-04, MAJOR-1). This used to open a
		-- `LuauUI/scenario` scope around the whole pass — and a pass body waits a
		-- Heartbeat once per frame, sixty times, INSIDE the scope. `debug.profilebegin`
		-- opens a scope on the executing thread, so a yield leaves the enter and the
		-- leave in different frames, and this module's counters cannot see it: they
		-- count Lua call sites, so `balanced` read true for a stack that was not.
		--
		-- The per-frame `LuauUI/scenario` scope in the lab bootstrap stays, because that
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
		-- of them is LuauUI's. `scrollWrite` is the framework/engine WRITE; the frame
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
				scrollPath = if m.kind == "luauui" and m.list.scrollPath ~= nil then m.list.scrollPath() else nil,
				evidence = "engine-observed; pair with an injected wheel/pan and re-read",
				payload = payload,
			}
		end

		passes.focusTraverse = function(payload: string?)
			return timed("focusTraverse", function()
				local steps = tonumber(payload or "") or 24
				local m = requireList()
				assert(
					m.kind == "luauui",
					"[perf lab] focus traversal is a LuauUI pass; the reference has no focus graph"
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
				assert(m.kind == "luauui", "[perf lab] keep-visible is a LuauUI pass")
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
					-- it (`scopes:idle`), which is where the LuauUI share is legible.
					intervalMs = summarize(samples),
				}
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
				local stats = if m.kind == "luauui"
						and m.controller ~= nil
						and m.controller.stats ~= nil
					then m.controller.stats
					else nil

				local resizeMs, dataMs = {}, {}
				local arrangedResize, arrangedData = 0, 0

				for i = 1, steps do
					-- ODD, NON-REPEATING WIDTHS. A resize that lands back on a size the
					-- solver has already seen measures a warm cache, not a resize; the
					-- prime step keeps every step a genuinely new width.
					local w = baseW - ((i * 7) % 61)
					local h = baseH - ((i * 11) % 41)
					local t0 = clock()
					env:set("viewportRect", { x = 0, y = 0, w = math.max(240, w), h = math.max(240, h) })
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
					note = "a resize legitimately re-arranges the whole tree; a single bound value should not. "
						.. "`dataChangeShareOfFullRelayout` at 1.0 is the incremental-layout gap (L-11), and is "
						.. "the number this pass exists to keep visible.",
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
			return if type(module.build) == "function" then (module.build(LuauUI.themes)) else module
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
					if pkg ~= nil then LuauUI.themes.resolve(pkg, nil, {}) else LuauUI.themes.neutral()
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
				local controller = mounted ~= nil and mounted.kind == "luauui" and mounted.controller or nil
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
					rampIndex = i
					local count = math.min(ladder[i], dataset.MAX_ROWS)
					unmount()
					settings.rows = count
					rebuildDataset()
					local before = telemetry.memory()
					local t0 = clock()
					settings.implementation = "luauui"
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
					settings.implementation = "luauui"
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
			if mounted == nil or mounted.kind ~= "luauui" or mounted.controller == nil then
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
				return `LuauUI {LuauUI.VERSION} · {SCENARIO_VERSION} · {dataset.VERSION} · {rows.VERSION}`
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
		local reservedBottom = 0
		local function reserveBottom(px: number)
			local want = math.max(0, math.floor(px))
			if want == reservedBottom then
				return
			end
			reservedBottom = want
			local live = env:get("coreSafeInsets"):get()
			local other = if type(live) == "table" then live else {}
			env:set("coreSafeInsets", {
				top = other.top or 0,
				bottom = want,
				left = other.left or 0,
				right = other.right or 0,
			})
		end

		-- A RESERVATION DOES NOT SURVIVE THE SCREEN IT WAS MEASURED ON. The overlay
		-- publishes its measured height into `coreSafeInsets.bottom`, and the workload
		-- re-solves against that fact the instant the viewport changes — BEFORE the
		-- overlay has re-solved and republished. So a rotation from a tall screen to a
		-- short one handed the workload the tall screen's 268px reservation against a
		-- 390px viewport: a 64px content box, overflowing by 75px, and the remount that
		-- the arrangement observer had just started failed inside a reactive flush.
		--
		-- Dropping the reservation to zero is the right direction to be wrong in: for
		-- the one solve before the overlay republishes, the workload believes it has
		-- MORE room than it does, which cannot overflow. Holding a stale reservation
		-- makes it believe it has less, which is exactly the failure above.
		--
		-- This is the same rule as `rowHeight` and the list height: a number derived
		-- from the viewport is invalid the moment the viewport changes, whether it was
		-- computed or measured.
		local function forgetReservation()
			reservedBottom = -1 -- force the next publish through the equality guard
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
				overlayBlueprint = overlayLib.build(LuauUI, core, overlayModel)
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
						value == "luauui" or value == "native" or value == "none",
						`[perf lab] implementation must be luauui|native|none, got '{value}'`
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
			statusLine:set("STOPPED")
			return { stopped = true, note = "the ramp and the soak check this flag between steps" }
		end

		steps.resume = function()
			emergencyStopped = false
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
				frameworkVersion = LuauUI.VERSION,
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

		steps.workloads = function()
			return { order = WORKLOAD_ORDER, workloads = WORKLOADS, scenarioVersion = SCENARIO_VERSION }
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
				if mounted == nil or mounted.kind ~= "luauui" or mounted.controller == nil then
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
