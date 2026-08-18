--!nocheck
--[[ THE SHOWCASE'S OWN CHIP ROW, MEASURED RATHER THAN WRITTEN DOWN (DIR wave
	contract 5, 2026-08-18).

	WHY IT EXISTS. `tests/overflow_sweep.spec.luau` has always laid its surfaces out
	under the showcase's chrome RESERVATION — `coreSafeInsets.top`, a bounding box
	— and never under the chrome itself. A bounding box says "the top 120px of this
	screen are spoken for"; the thing a screen actually collides with is a ROW
	300-ish px wide at one end of that band, and `appChromeRects` is the fact the
	live host declares it through (`examples/gallery/client/init.client.luau` feeds
	it from `showcase_chrome`'s `onGeometry`). A sweep that never declares it cannot
	see a HUD painting on the app's own chips, which is exactly the defect the
	director photographed on 2026-08-17.

	IT IS DERIVED, NEVER HARDCODED, and that is the whole design. A chip is a THEMED
	control — its height is its package's chrome plus its label at the player's own
	text size, and its WIDTH decides which rung of `showcase_chrome`'s
	`UI.ViewThatFits` ladder wins (the two full chips, or two icons). Measured here:
	the same package produces a 128px row on a 359px phone and a 452px row on a
	705px one, and `classic_desktop` produces 312 where `pixel_quest` produces 440.
	A literal would have been wrong on 79 of the 81 cells the sweep walks.

	SO IT MOUNTS THE REAL CHROME. `showcase_chrome.mount` with the real composed
	`demo_picker` and `settings_panel`, and it reads the rect back through
	`onChipsRect` — the SAME callback the shipped host reads it through, which is
	what makes this immune to the drift a re-implementation of the ladder would
	have. `mountDemo` is a stub because the demo under the chrome cannot move the
	chrome: the strip is a separate surface presented edge-to-edge.

	MEMOISED per (view, package, offset). One mount is ~3ms and the sweep asks for
	the same cell many times.

	WHAT IT IS NOT: a claim about the DEVICE's pixels. Headless text measurement is
	an estimate and a wider one than the engine reports, so these rows are wider
	than the ones a phone draws. That is the right direction for a collision check
	(it over-states the obstacle), and the device's own measured row is pinned
	separately in `tests/hud_chrome_rotation.spec.luau` so neither number can drift
	into standing for the other. ]]

local UI = require("../../src/blueprint")
local demo_picker = require("../../examples/gallery/client/demo_picker")
local settings_panel = require("../../examples/gallery/client/settings_panel")
local showcase_chrome = require("../../examples/gallery/client/showcase_chrome")
local fake_target = require("./fake_target")
local device_views = require("./device_views")

local showcase_chips = {}

local cache: { [string]: any } = {}

--[[ rectFor(Facet, view, packageId, snapshot, offset) -> { x, y, w, h }?

	`packageId` is the cache key only — nil means the neutral pass. `snapshot` nil
	means the same. Returns nil when the chrome declined to mount at all, which a
	caller must treat as "no chrome declared" rather than as a zero rect. ]]
function showcase_chips.rectFor(Facet: any, view: any, packageId: string?, snapshot: any?, offset: number?): any
	local key = `{view.id}|{tostring(packageId)}|{tostring(offset or 0)}`
	local hit = cache[key]
	if hit ~= nil then
		return hit.rect
	end

	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = device_views.CORE_TOP, bottom = 0, left = 0, right = 0 })
	env:set("displaySize", view.displaySize)
	env:set("preferredInput", view.input)
	env:set("capabilities", device_views.CAPABILITIES[view.input])
	env:set("preferredTextOffset", offset or 0)
	if snapshot ~= nil then
		env:set("themeMetrics", snapshot)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new();
	(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
	local presenter = Facet.newPresenter(core, env, adapter, system)

	local rect: any = nil
	local demos = demo_picker.mount({
		Facet = Facet,
		core = core,
		env = env,
		presenter = presenter,
		composed = true,
		-- the demo cannot move the chrome: the strip is its own edge-to-edge
		-- surface, so a stub is not a simplification, it is the real coupling
		mountDemo = function()
			return { screen = UI.Screen({ id = "Demo", children = { UI.Spacer({ id = "Fill" }) } }) }
		end,
		onChip = function() end,
		onChose = function() end,
		onRaise = function() end,
		warn = function() end,
	})
	local settings = settings_panel.mount({ Facet = Facet, core = core, env = env })
	showcase_chrome.mount({
		Facet = Facet,
		core = core,
		env = env,
		presenter = presenter,
		actionSystem = system,
		demos = demos,
		settings = settings,
		coreTop = core:signal(device_views.CORE_TOP),
		onChipsRect = function(r: any)
			rect = r
		end,
	})
	for _ = 1, 4 do
		presenter.refresh()
	end
	local frozen = if type(rect) == "table"
		then table.freeze({ x = rect.x, y = rect.y, w = rect.w, h = rect.h })
		else nil
	cache[key] = { rect = frozen }
	return frozen
end

-- the reservation the live host publishes beside the rect, so a surface swept
-- under the declared chrome is also swept under the band the chrome inflated
function showcase_chips.reservationFor(rect: any): number
	return demo_picker.barReservation(device_views.CORE_TOP, if rect ~= nil then rect.y + rect.h else nil, 8)
end

return showcase_chips
