--!strict
-- THE ALWAYS-ON OVERFLOW SWEEP (device bug round 2026-08-12, Group B).
--
-- WHY THIS EXISTS. `docs/lessons/the-solver-already-told-you.md` records a defect
-- that shipped past a green suite, a green perf gate, a five-view device matrix
-- and four fresh-context reviews, purely because nothing ever called
-- `controller.diagnostics()`. On 2026-08-12 the same class arrived again, from a
-- phone, three times in one sitting: a table entirely below the fold in landscape
-- with nothing to scroll it, a Match-3 button row sliced by the right screen
-- edge, and an all-controls fixture running past its own box. The solver had
-- already said so, in these exact words, on every one of them:
--
--     content overflows this <stack> by <N>px on the main axis; it will paint
--     outside its box (wrap it in a ScrollView, or give it room)
--
-- Section 13 of that lesson is explicit about why "call it in the fixture you are
-- working on" was not enough: *a fixture must FAIL on it, or the list is a log
-- nobody reads*. So this file asks the question of EVERY showcase surface at
-- EVERY swept viewport, on every `./run-tests.sh`, with nobody deciding to run
-- it.
--
-- WHAT IT COVERS
--   * every engine-free gallery scenario (the demo picker's four fixtures, the
--     eight Sponsor labs, the verification fixtures and the composition/keyboard
--     stages) — the same modules Studio loads;
--   * all seven tutorial examples, through the tutorial build contract;
--   * all five clean-room reference proofs.
--
-- ...at the five canonical device-matrix viewports (the ones
-- `tests/theme_matrix_audit.spec.luau` recorded live, so the headless twin and
-- the Studio drive talk about the same geometry) PLUS the narrowest supported
-- viewport in BOTH orientations. Landscape is not optional: B5 was landscape-only
-- and portrait-clean, which is exactly how it survived a portrait capture set.
--
-- ...under the showcase's OWN chrome reservation. Every one of these surfaces is
-- reached in `LuauUI-Showcase` through the demo picker, which reserves its chip
-- strip by writing `coreSafeInsets.top` (see `examples/gallery/client/init.client`
-- and `demo_picker.barReservation`). A sweep that laid out against the bare
-- viewport would be measuring a screen no player ever sees — 62px taller than the
-- real one, which is the whole margin several of these defects lived in. The
-- number is read from the picker rather than written here, so the two cannot
-- drift.
--
-- WHAT IT IS NOT. It is not a paint check and it cannot see the engine's own text
-- bounds, so a live surface can still overflow on measurements this suite
-- estimates. Nor does it see the scroll host's WINDOW: the engine's visible box is
-- narrower than the frame by the bar thickness even where the layout reserved
-- nothing, which is a second, independent way for content to be clipped on the
-- right — measured and pinned separately in tests/scroll_window_clip.spec.luau. It
-- is the part of "does this fit on a phone" that a machine can answer every time,
-- and the floor under the Studio device matrix rather than a replacement for it.

local t = require("./lib/testkit")
local describe, it = t.describe, t.it

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")
local demo_picker = require("../examples/gallery/client/demo_picker") :: any

-- The five canonical rows of docs/plans/studio-device-verification.md at the
-- viewports the driver RECORDED (artifacts/rich-skinning-v2/rs-a16-matrix.json),
-- kept identical to tests/theme_matrix_audit.spec.luau's VIEWS, plus the
-- narrowest supported viewport in both orientations (the lesson's "sweep the
-- narrowest supported viewport, not your own" — and its rotation, because a
-- short landscape is where a screen's fixed chrome eats the whole canvas).
local VIEWS = {
	{ id = "compact-phone-portrait", w = 359, h = 718, displaySize = "Small", input = "Touch" },
	{ id = "compact-phone-landscape", w = 705, h = 338, displaySize = "Small", input = "Touch" },
	{ id = "tablet-landscape", w = 1079, h = 809, displaySize = "Small", input = "Touch" },
	{ id = "desktop-standard", w = 1232, h = 1067, displaySize = "Medium", input = "KeyboardAndMouse" },
	{ id = "console-ten-foot", w = 1920, h = 1078, displaySize = "Large", input = "Gamepad" },
	{ id = "narrow-portrait", w = 320, h = 640, displaySize = "Small", input = "Touch" },
	{ id = "narrow-landscape", w = 640, h = 320, displaySize = "Small", input = "Touch" },
	-- the DESKTOP Studio client the director drove on 2026-08-12, at the size the
	-- right-edge clipping was captured at. It is here because "a defect that
	-- survives at 1320px wide is a stronger signal than one that only appears at
	-- 320px" — a sweep that only runs compact sizes teaches the wrong lesson about
	-- what overflow is.
	{ id = "desktop-studio-1320", w = 1320, h = 742, displaySize = "Medium", input = "KeyboardAndMouse" },
}

local CAPABILITIES: { [string]: any } = {
	Touch = { touch = true, mouse = false, keyboard = false, gamepad = false },
	KeyboardAndMouse = { touch = false, mouse = true, keyboard = true, gamepad = false },
	Gamepad = { touch = false, mouse = false, keyboard = false, gamepad = true },
}

-- The CoreGui topbar inset every matrix row measured, plus the strip the showcase
-- reserves for its two picker chips — `barReservation(coreTop, nil, slack)` is
-- the same call `init.client` makes on the frame before any chip geometry exists,
-- which is the floor it never goes below.
local CORE_TOP = 58
local SHOWCASE_TOP = demo_picker.barReservation(CORE_TOP, nil, 8)

-- Engine-free gallery scenarios. `examples` and the five `ref_*` scenarios are
-- absent ON PURPOSE: both are thin delegations that resolve their real module
-- through a replicated folder, so this file mounts those modules DIRECTLY below
-- (the same thing the delegation would have built, minus an engine).
local SCENARIOS = {
	"probe",
	"safe_area",
	"scroll_host",
	"path_ring",
	"async_images",
	"selection_bridge",
	"preferred_text",
	"drag_session",
	"virtual_list_native",
	"native_style",
	"authoring",
	"adaptive_controls",
	"theme_authoring",
	"perf_capture",
	"sponsor_motion",
	"sponsor_celebration",
	"sponsor_list",
	"sponsor_drop",
	"sponsor_toast",
	"sponsor_avatars",
	"sponsor_markers",
	"sponsor_billboard",
	"composition",
	"keyboard_navigation",
	"row_actions",
	-- SwiftUI-parity round 2's two new showcase surfaces. Both are reached
	-- through the demo picker, so both are swept under the same chrome
	-- reservation as every other one: `card_rail` derives its rail width from
	-- the live viewport (a constant painted a rail off the right edge of a 320px
	-- phone in the fixture it was modelled on), and `with_animation` puts two
	-- motion columns, a picker and a button in the ~200px a 640x320 landscape
	-- phone has left.
	"card_rail",
	"with_animation",
}

local EXAMPLES = {
	"01_temperature_converter",
	"02_playlist_table",
	"03_settings_sync",
	"04_confirm_dialog",
	"05_word_game",
	"06_tile_game",
	"07_match3",
}

local PROOFS = { "p1_glade", "p2_cartwheel", "p3_sipworks", "p4_foyer", "p5_wardrobe" }

local MAIN_AXIS = "on the main axis"

-- A SURFACE MAY PUBLISH ITS OWN MEASURED GEOMETRY BACK INTO ITS TREE, and the
-- frame that does it is not the frame that shows it. The showcase's picker strip
-- writes `coreSafeInsets` from `onGeometry`; the row-actions fixture's hosted list
-- takes its window from its own solved pane the same way. Both are fixed points —
-- the published value never depends on what it feeds — so a bounded settle is the
-- frame a player sees, and a screen that does NOT converge still fails here,
-- because it is still overflowing at the end of the loop.
local SETTLE_FRAMES = 3

local function settle(presenter: any)
	for _ = 1, SETTLE_FRAMES do
		presenter.refresh()
	end
end

local function world(view: any): any
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = SHOWCASE_TOP, bottom = 0, left = 0, right = 0 })
	env:set("displaySize", view.displaySize)
	env:set("preferredInput", view.input)
	env:set("capabilities", CAPABILITIES[view.input])
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new();
	-- THE LIVE BAR THICKNESS, OPTED INTO. The fake publishes none by default —
	-- "which is WHY no headless sweep ever saw this class" (scroll_bar_measure.spec)
	-- — while the live adapter publishes `SCROLL_BAR_THICKNESS` under EVERY
	-- indicator policy (the 2026-08-12 reversal; it briefly published zero for an
	-- overlay/touch session, which is the defect in bugs/IMG_3691.jpeg, and
	-- tests/scroll_indicators.spec.luau now pins the live line itself). A sweep laid
	-- out without it is 8px wider than the device it claims to model — on every
	-- input class, not just the pointer views. See tests/scroll_window_clip.spec.luau
	-- for the half of this the reserve does NOT cover.
	(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, presenter = presenter, system = system }
end

-- The report names the BOX as well as the overflow (lesson §11: "overflows by
-- 104px" is a symptom; the box it overflowed is what identifies the wrong
-- constant), so one failure is one measurement rather than a guessing loop.
local function describeFinding(w: any, view: any, finding: any): string
	local node = w.adapter.node(finding.node)
	local rect = if node ~= nil and node.rect ~= nil
		then string.format(" [box %dx%d at %d,%d]", node.rect.w, node.rect.h, node.rect.x, node.rect.y)
		else ""
	return `  {view.id} ({view.w}x{view.h}): {finding.node}{rect}\n      {finding.issue}`
end

-- A SWEEP ONLY COVERS THE CONFIGURATIONS ITS FIXTURE ACTUALLY BUILDS
-- (`the-solver-already-told-you.md` §13.1 — an LT-8 sweep mounted a Table without
-- `reorderable`, so the toolbar the header collided with did not exist in a single
-- swept row). `row_actions` is ONE screen with three surfaces behind a mode
-- signal, and the two the default mount does not build are exactly where a
-- hard-coded 336px VirtualList window was painting 245px past its pane. Any
-- fixture whose shape is chosen by a step belongs here.
local VARIANTS: { [string]: { step: string, values: { string } } } = {
	row_actions = { step = "mode", values = { "list", "table", "vlist" } },
}

-- one surface, every view (and every declared variant): collect instead of
-- stopping at the first, because the set of views a screen fails at is what tells
-- an author whether it is a width problem or a height problem
local function sweep(label: string, variantKey: string?, mount: (any) -> any)
	it(`{label}: no main-axis overflow at any swept viewport`, function()
		local variant = if variantKey ~= nil then VARIANTS[variantKey] else nil
		local problems: { string } = {}
		for _, view in VIEWS do
			local w = world(view)
			local built = mount(w)
			settle(w.presenter)
			local function collect(suffix: string)
				for _, finding in built.handle.controller.diagnostics() do
					if string.find(finding.issue, MAIN_AXIS, 1, true) ~= nil then
						table.insert(problems, describeFinding(w, view, finding) .. suffix)
					end
				end
			end
			if variant == nil then
				collect("")
			else
				for _, value in variant.values do
					built.steps[variant.step](built, value)
					settle(w.presenter)
					collect(`\n      [{variant.step} = {value}]`)
				end
			end
		end
		if #problems > 0 then
			error(
				`{label}: the solver reports {#problems} main-axis overflow(s) — content wider or taller `
					.. `than its own box with nothing to scroll it:\n{table.concat(problems, "\n")}`,
				0
			)
		end
	end)
end

local function scenarioCtx(w: any): any
	return {
		LuauUI = LuauUI,
		core = w.core,
		env = w.env,
		adapter = w.adapter,
		presenter = w.presenter,
		actionSystem = w.system,
		record = function() end,
		flags = {},
		geometry = function(paths: { string }): { [string]: any }
			local out: { [string]: any } = {}
			for _, path in paths do
				local node = w.adapter.node(path)
				if node ~= nil and node.rect ~= nil then
					out[path] = node.rect
				end
			end
			return out
		end,
		-- the one runner-owned seam a scenario in this list actually calls
		-- (async_images); every other engine seam is deliberately absent so the
		-- scenario takes its "degrade honestly" branch
		bindResourceTransport = function()
			return function() end
		end,
	}
end

local function present(w: any, built: any): any
	if built.handle == nil and built.screen ~= nil then
		built.handle = w.presenter.present(built.screen, built.present)
	end
	assert(built.handle ~= nil, "surface presented no screen")
	return built
end

describe("overflow sweep: gallery scenarios", function()
	for _, name in SCENARIOS do
		local module = require(`../examples/gallery/scenarios/{name}`) :: any
		sweep(`scenario '{name}'`, name, function(w)
			return present(w, module.build(scenarioCtx(w)))
		end)
	end
end)

describe("overflow sweep: tutorial examples", function()
	for _, name in EXAMPLES do
		local module = require(`../examples/gallery/examples/{name}`) :: any
		sweep(`example '{name}'`, nil, function(w)
			return present(
				w,
				module.build(
					LuauUI,
					w.core,
					{ env = w.env, actionSystem = w.system, presenter = w.presenter, adapter = w.adapter }
				)
			)
		end)
	end
end)

describe("overflow sweep: reference proofs", function()
	for _, name in PROOFS do
		local module = require(`../examples/reference/{name}`) :: any
		sweep(`proof '{name}'`, nil, function(w)
			return present(
				w,
				module.build(
					LuauUI,
					w.core,
					{ env = w.env, actionSystem = w.system, presenter = w.presenter, adapter = w.adapter }
				)
			)
		end)
	end
end)
