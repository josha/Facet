--!strict
--[[ LevelPicker: a run of discrete segments that reads as ONE value.

	The control generalizes `newRating` (director ruling 2026-08-16): a
	caller-chosen `count`, three ways to PAINT one level (`bar` | `glyph` |
	`image`), and a `tint` pair for the filled and empty halves. `newRating`
	becomes a preset over it — count 5, glyph segments, star glyphs — and its
	closed spec, including `starSize`, is unchanged, which `tests/rating.spec.luau`
	proves by staying green without an edit.

	These cases pin, in order: the value model and the closed spec; the three
	paint modes and where `tint` lands in each; the ONE-control invariants the
	rating header argues for (no plate, no per-segment focus stop, one 44px
	target); the four input classes plus the hot-switch; the high-count
	diagnostic and the measurement its threshold comes from; and the preset. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local LuauUI = require("../src") :: any
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local presenterLib = require("../src/present/presenter")
local actionsLib = require("../src/input/actions")
local fake_target = require("../tests/lib/fake_target")
local chrome_slots = require("../src/tokens/chrome_slots")
local level_picker = require("../src/controls/level_picker")

local STRIP = "/S/Quality/Strip"
local function markPath(index: number): string
	return `/S/Quality/Levels/Level{index}`
end

local function world(viewport: { w: number, h: number }?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set(
		"viewportRect",
		{ x = 0, y = 0, w = if viewport then viewport.w else 400, h = if viewport then viewport.h else 600 }
	)
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	return core, env, adapter, system, pres
end

local function mount(specOverrides: any?, start: number?)
	local core, env, adapter, system, pres = world()
	local value = core:signal(start or 2)
	local spec: any = { id = "Quality", value = value, count = 10 }
	for k, v in (specOverrides or {}) :: any do
		spec[k] = v
	end
	local control = LuauUI.newLevelPicker(LuauUI, core, spec)
	local handle = pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
	pres.refresh()
	return core, adapter, system, pres, value, control, env, handle
end

--[[ EVERY FOCUS STOP INSIDE THE CONTROL, read off the presenter's own focus map
	rather than off the adapter. This is not a stylistic preference: `focusable` is
	a SEMANTIC-channel prop and the adapter never records it, so
	`node.props.focusable` is `nil` for the strip and for every segment alike — a
	spec asserting `never().toBe(true)` on it would pass with ten focusable
	segments and prove nothing (the class `docs/lessons/` calls a check that cannot
	fail). `handle.focusOrder()` is the map the ring actually walks. ]]
local function focusStopsIn(handle: any, prefix: string): { string }
	local out: { string } = {}
	for _, entry in handle.focusOrder().traversal do
		if string.find(entry.path, prefix, 1, true) == 1 then
			table.insert(out, entry.path)
		end
	end
	return out
end

-- a point at the given fraction across the strip's solved rect
local function pointAt(adapter: any, fraction: number): (number, number)
	local rect = adapter.node(STRIP).rect
	return rect.x + rect.w * fraction, rect.y + rect.h / 2
end

local function tap(system: any, pres: any, key: string)
	system.deviceKey(key, true)
	system.deviceKey(key, false)
	pres.refresh()
end

-- ===========================================================================
describe("LevelPicker: the value model and the closed spec", function()
	it("a read-only Memo is refused at BUILD, not on the first tap", function()
		local core = customFactory.new()
		expect(pcall(function()
			return LuauUI.newLevelPicker(LuauUI, core, {
				id = "L",
				value = core:memo(function()
					return 3
				end),
			})
		end)).toBe(false)
	end)

	it("a count that is not a whole number >= 1 is a build error", function()
		local core = customFactory.new()
		for _, bad in { 0, -3, 2.5 } do
			expect(pcall(function()
				return LuauUI.newLevelPicker(LuauUI, core, { id = "L", value = core:signal(1), count = bad })
			end)).toBe(false)
		end
	end)

	it("an unknown spec key is an authoring error that names the key", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			return LuauUI.newLevelPicker(LuauUI, core, { id = "L", value = core:signal(1), starSize = "small" })
		end)
		expect(ok).toBe(false)
		-- `starSize` is newRating's spelling and is NOT on this control's spec:
		-- the rename must be a refusal that names it, never a silent no-op
		expect(string.find(tostring(err), "starSize", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "newLevelPicker", 1, true) ~= nil).toBe(true)
	end)

	it("an unknown segment is a build error naming the three that exist", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			return LuauUI.newLevelPicker(LuauUI, core, { id = "L", value = core:signal(1), segment = "dots" })
		end)
		expect(ok).toBe(false)
		for _, name in { "bar", "glyph", "image" } do
			expect(`{name} named={string.find(tostring(err), name, 1, true) ~= nil}`).toBe(`{name} named=true`)
		end
	end)

	it("an unknown segmentSize is a build error, not a silently-default segment", function()
		local core = customFactory.new()
		expect(pcall(function()
			return LuauUI.newLevelPicker(LuauUI, core, { id = "L", value = core:signal(1), segmentSize = "huge" })
		end)).toBe(false)
	end)

	it("a glyph pair on a bar picker is refused rather than silently ignored", function()
		local core = customFactory.new()
		-- `glyphs` describes a glyph segment, `images` an image one: declaring the
		-- wrong pair is the accepted-and-ignored class the closed spec exists to
		-- remove (the progress_view refusal shape)
		expect(pcall(function()
			return LuauUI.newLevelPicker(
				LuauUI,
				core,
				{ id = "L", value = core:signal(1), segment = "bar", glyphs = { filled = "x", empty = "o" } }
			)
		end)).toBe(false)
		expect(pcall(function()
			return LuauUI.newLevelPicker(
				LuauUI,
				core,
				{ id = "L", value = core:signal(1), segment = "glyph", images = { filled = "a", empty = "b" } }
			)
		end)).toBe(false)
		-- ...and an image segment with NO images is refused too: an image picker
		-- with nothing to draw is an empty strip, not a default
		expect(pcall(function()
			return LuauUI.newLevelPicker(LuauUI, core, { id = "L", value = core:signal(1), segment = "image" })
		end)).toBe(false)
	end)

	it("the value is clamped to the run, and to zero only when zero is allowed", function()
		local _, adapter, _, pres, value = mount()
		adapter.pointerDown(STRIP, pointAt(adapter, -2))
		pres.refresh()
		expect(value:get()).toBe(0)
		local _, adapter2, _, pres2, value2 = mount({ allowZero = false })
		adapter2.pointerDown(STRIP, pointAt(adapter2, -2))
		pres2.refresh()
		expect(value2:get()).toBe(1)
		-- ...and the top of the run is the count, however far past it you drag
		adapter.pointerUp(pointAt(adapter, -2))
		adapter.pointerDown(STRIP, pointAt(adapter, 3))
		pres.refresh()
		expect(value:get()).toBe(10)
	end)

	it("semantic text reports the level IN ITS RANGE, never a bare number", function()
		local _, _, _, _, _, control = mount()
		expect(control.semanticText:get()).toBe("2 of 10")
	end)

	it("dump reports segment, count, value and semanticText, and is deterministic", function()
		local serde = require("@lune/serde")
		local _, adapter, _, pres, _, control = mount()
		local d = control.dump()
		expect(d.schema).toBe("luauui-level-picker-dump/1")
		expect(`{d.segment}/{d.count}/{d.value}/{d.semanticText}`).toBe("bar/10/2/2 of 10")
		local first = serde.encode("json", control.dump(), true)
		expect(first).toBe(serde.encode("json", control.dump(), true))
		adapter.pointerDown(STRIP, pointAt(adapter, 0.95))
		pres.refresh()
		local second = serde.encode("json", control.dump(), true)
		expect(second).toBe(serde.encode("json", control.dump(), true))
		expect(second ~= first).toBe(true)
	end)

	it("build/interact/dispose returns the registry to its baseline", function()
		local core, env, adapter, _, pres = world()
		local baseline = core:counters() -- AFTER the long-lived singletons

		local value = core:signal(2)
		local control = LuauUI.newLevelPicker(LuauUI, core, { id = "Quality", value = value, count = 10, env = env })
		local handle = pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		adapter.pointerDown(STRIP, pointAt(adapter, 0.9))
		pres.refresh()
		control.dump()
		control.diagnostics()

		pres.dismiss(handle)
		control.dispose()
		value:dispose()

		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)
end)

-- ===========================================================================
describe("LevelPicker: three ways to paint one level", function()
	it("segment = bar paints a Box per level and needs no assets", function()
		local _, adapter, _, pres, value = mount()
		for i = 1, 10 do
			expect(adapter.node(markPath(i)).class).toBe("Box")
		end
		-- the run divides the offer: ten segments, none of them zero-width
		local first = adapter.node(markPath(1)).rect
		local last = adapter.node(markPath(10)).rect
		expect(first.w > 0).toBe(true)
		expect(math.abs(last.w - first.w) <= 1).toBe(true)
		-- a level change is PAINT: no node is created or destroyed
		local before = adapter.liveCount()
		value:set(7)
		pres.refresh()
		expect(adapter.liveCount()).toBe(before)
	end)

	it("segment = glyph paints a Text per level, filled up to the value", function()
		local _, adapter = mount({ segment = "glyph", count = 5, glyphs = { filled = "#", empty = "." } }, 3)
		local out = ""
		for i = 1, 5 do
			local node = adapter.node(markPath(i))
			expect(node.class).toBe("Text")
			out ..= node.props.text
		end
		expect(out).toBe("###..")
	end)

	it("segment = image paints an Image per level, and swaps the asset at the value", function()
		local _, adapter, _, pres, value =
			mount({ segment = "image", count = 4, images = { filled = "rbxassetid://1", empty = "rbxassetid://2" } }, 2)
		local function assets(): string
			local out = ""
			for i = 1, 4 do
				local node = adapter.node(markPath(i))
				expect(node.class).toBe("Image")
				out ..= string.sub(node.props.image, -1)
			end
			return out
		end
		expect(assets()).toBe("1122")
		value:set(4)
		pres.refresh()
		expect(assets()).toBe("1111")
	end)

	it("the bar's filled and empty halves carry DIFFERENT theme tints by default", function()
		-- a bar has no glyph and no asset, so the ONLY thing that can say "filled"
		-- is its colour. Both defaults are ROLE tints, so a package retints them.
		local _, adapter = mount(nil, 3)
		local filled = adapter.node(markPath(1)).props.tint
		local empty = adapter.node(markPath(10)).props.tint
		expect(`{filled.role}@{filled.blend}`).toBe("accent@1")
		expect(`{empty.role}@{empty.blend}`).toBe("control@1")
		expect(filled.role ~= empty.role).toBe(true)
		-- neither default is `direct`: a bar that painted a hard-coded hue would be
		-- theming-exempt, which is exactly what a themable control must not be
		expect(filled.direct).toBeNil()
		expect(empty.direct).toBeNil()
	end)

	it("tint.filled reaches the filled half and tint.empty the empty one", function()
		local _, adapter, _, pres, value = mount({
			tint = { filled = { direct = "#ff0000" }, empty = { direct = "#00ff00" } },
		}, 3)
		expect(adapter.node(markPath(3)).props.tint.direct).toBe("#ff0000")
		expect(adapter.node(markPath(4)).props.tint.direct).toBe("#00ff00")
		-- ...and the boundary MOVES with the value rather than being fixed at build
		value:set(7)
		pres.refresh()
		expect(adapter.node(markPath(7)).props.tint.direct).toBe("#ff0000")
		expect(adapter.node(markPath(8)).props.tint.direct).toBe("#00ff00")
	end)

	it("tint reaches a glyph and an image segment too, not only a bar", function()
		local _, adapterG = mount({
			segment = "glyph",
			count = 3,
			tint = { filled = { direct = "#ff0000" } },
		}, 2)
		expect(adapterG.node(markPath(1)).props.tint.direct).toBe("#ff0000")
		local _, adapterI = mount({
			segment = "image",
			count = 3,
			images = { filled = "rbxassetid://1", empty = "rbxassetid://2" },
			tint = { filled = { direct = "#ff0000" } },
		}, 2)
		expect(adapterI.node(markPath(1)).props.tint.direct).toBe("#ff0000")
	end)

	it("an omitted tint half is left to the theme, not painted with the other one", function()
		-- glyph/image segments carry NO default tint: the mark itself says which
		-- state it is in, so an undeclared half must reach paint as nothing at all
		local _, adapter = mount({ segment = "glyph", count = 3, tint = { filled = { direct = "#ff0000" } } }, 2)
		expect(adapter.node(markPath(1)).props.tint.direct).toBe("#ff0000")
		expect(adapter.node(markPath(3)).props.tint).toBeNil()
	end)
end)

-- ===========================================================================
-- ONE CONTROL, NOT N BUTTONS — the argument `src/controls/rating.luau`'s header
-- makes for five stars, held here for an arbitrary `count`. It gets STRICTER
-- with the generalization, not looser: ten focus stops for one number is worse
-- than five, and ten theme plates worse than five.
-- ===========================================================================
describe("LevelPicker: one control, not N buttons", function()
	it("no segment is a Button or a focusable, so no theme can paint a plate behind one", function()
		for _, mode in { "bar", "glyph" } do
			local _, adapter, _, _, _, _, _, handle = mount({ segment = mode })
			for i = 1, 10 do
				local node = adapter.node(markPath(i))
				expect(`{mode}:{node.class}`).never().toBe(`{mode}:Button`)
				expect(chrome_slots.classify({ class = node.class, surface = node.props.surface })).toBeNil()
			end
			-- ...and not one of them is in the focus map either (see focusStopsIn:
			-- the adapter never records `focusable`, so only the map can say)
			local stops = focusStopsIn(handle, "/S/Quality")
			expect(`{mode}: {table.concat(stops, ",")}`).toBe(`{mode}: {STRIP}`)
		end
	end)

	it("the whole strip is ONE focus stop, not one per level", function()
		local _, _, system, pres = mount()
		local seen: { [string]: boolean } = {}
		for _ = 1, 8 do
			tap(system, pres, "DPadDown")
			seen[tostring(pres.focus.focused:get())] = true
			tap(system, pres, "DPadRight")
			seen[tostring(pres.focus.focused:get())] = true
		end
		expect(seen[STRIP]).toBe(true)
		for i = 1, 10 do
			expect(seen[markPath(i)]).never().toBe(true)
		end
	end)

	it("a read-only picker paints but is not focusable and refuses every input", function()
		local _, adapter, _, pres, value, _, _, handle = mount({ readOnly = true })
		expect(adapter.node(markPath(1)).class).toBe("Box")
		-- NOTHING inside a read-only picker is in the focus map at all
		expect(#focusStopsIn(handle, "/S/Quality")).toBe(0)
		local _, _, system2, pres2 = mount({ readOnly = true })
		tap(system2, pres2, "DPadDown")
		expect(tostring(pres2.focus.focused:get())).never().toBe(STRIP)
		adapter.pointerDown(STRIP, pointAt(adapter, 0.9))
		pres.refresh()
		expect(value:get()).toBe(2)
	end)

	it("a disabled picker refuses every input class, not just the pointer", function()
		local _, adapter, system, pres, value = mount({ enabled = false })
		adapter.pointerDown(STRIP, pointAt(adapter, 0.9))
		pres.refresh()
		expect(value:get()).toBe(2)
		tap(system, pres, "DPadDown")
		tap(system, pres, "Period")
		expect(value:get()).toBe(2)
	end)
end)

-- ===========================================================================
describe("LevelPicker reaches the same arithmetic from every input class", function()
	it("LevelPicker pointer: tapping a segment sets the level to that segment", function()
		local _, adapter, _, pres, value = mount()
		adapter.pointerDown(STRIP, pointAt(adapter, 0.95))
		adapter.pointerUp(pointAt(adapter, 0.95))
		pres.refresh()
		expect(value:get()).toBe(10)
		adapter.pointerDown(STRIP, pointAt(adapter, 0.35))
		adapter.pointerUp(pointAt(adapter, 0.35))
		pres.refresh()
		expect(value:get()).toBe(4)
	end)

	it("LevelPicker touch: a finger drag across the strip scrubs the level live", function()
		local _, adapter, _, pres, value = mount()
		adapter.pointerDown(STRIP, pointAt(adapter, 0.05), "touch")
		pres.refresh()
		expect(value:get()).toBe(1)
		adapter.pointerMove(pointAt(adapter, 0.65))
		pres.refresh()
		expect(value:get()).toBe(7)
		adapter.pointerUp(pointAt(adapter, 0.65))
		pres.refresh()
		expect(value:get()).toBe(7)
	end)

	it("LevelPicker keyboard: Adjust on the focused strip sets the level", function()
		local _, _, system, pres, value = mount()
		tap(system, pres, "DPadDown")
		tap(system, pres, "Period")
		expect(value:get()).toBe(3)
		tap(system, pres, "Comma")
		expect(value:get()).toBe(2)
	end)

	it("LevelPicker gamepad: the bumpers Adjust the focused level picker", function()
		local _, _, system, pres, value = mount()
		tap(system, pres, "DPadDown")
		tap(system, pres, "ButtonR1")
		expect(value:get()).toBe(3)
		tap(system, pres, "ButtonL1")
		expect(value:get()).toBe(2)
	end)

	it("LevelPicker pointer affordance: ONE drag target covers the run, at every count", function()
		-- the pointer idiom is DIRECT manipulation with no grip and no per-segment
		-- hit surface: the same Grip answers a tap and a drag, and it spans the run
		local _, adapter = mount()
		local strip = adapter.node(STRIP).rect
		local first = adapter.node(markPath(1)).rect
		local last = adapter.node(markPath(10)).rect
		expect(strip.x <= first.x).toBe(true)
		expect(strip.x + strip.w >= last.x + last.w).toBe(true)
		-- one Grip, however many segments there are
		local grips = 0
		for _, path in adapter.paths() do
			if string.find(path, "/S/Quality", 1, true) == 1 and adapter.node(path).class == "Grip" then
				grips += 1
			end
		end
		expect(grips).toBe(1)
	end)

	it("LevelPicker touch affordance: the strip declares the 44px effective target", function()
		-- a bar segment has no content height of its own, so without a declared
		-- floor the whole strip solves to nothing a finger can hit
		local _, adapter = mount()
		expect(adapter.node(STRIP).rect.h >= 44).toBe(true)
		local _, adapterG = mount({ segment = "glyph", count = 5 })
		expect(adapterG.node(STRIP).rect.h >= 44).toBe(true)
	end)

	it("LevelPicker keyboard affordance: no Adjust key is bound while focus sits outside", function()
		local core, _, _, system, pres = world()
		local value = core:signal(2)
		local control = LuauUI.newLevelPicker(LuauUI, core, { id = "Quality", value = value, count = 10 })
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "Elsewhere", label = "elsewhere", height = { type = "fixed", px = 44 } }),
				control.blueprint,
			},
		}))
		pres.refresh()
		-- focus is on the first focusable, which is OUTSIDE the picker
		tap(system, pres, "ButtonR1")
		expect(value:get()).toBe(2)
	end)

	it("LevelPicker gamepad affordance: at the limit the arrow goes back to navigation", function()
		local core, _, _, system, pres = world()
		local value = core:signal(9)
		local control = LuauUI.newLevelPicker(LuauUI, core, { id = "Quality", value = value, count = 10 })
		local STRIP_IN_ROW = "/S/Row/Quality/Strip"
		local AFTER = "/S/Row/After"
		pres.present(
			UI.Screen({
				id = "S",
				children = {
					UI.HStack({
						id = "Row",
						gap = 8,
						children = {
							UI.Button({ id = "Before", label = "Before", height = { type = "fixed", px = 44 } }),
							control.blueprint,
							UI.Button({ id = "After", label = "After", height = { type = "fixed", px = 44 } }),
						},
					}),
				},
			}),
			{
				navigationGroups = {
					{ name = "row", axis = "horizontal", order = { "/S/Row/Before", STRIP_IN_ROW, AFTER } },
				},
			}
		)
		pres.refresh()
		tap(system, pres, "DPadRight") -- onto the strip
		expect(tostring(pres.focus.focused:get())).toBe(STRIP_IN_ROW)
		tap(system, pres, "DPadRight") -- 9 -> 10, the ring must NOT move
		expect(`{value:get()}@{pres.focus.focused:get()}`).toBe(`10@{STRIP_IN_ROW}`)
		tap(system, pres, "DPadRight") -- at the maximum: the ring moves, the value does not
		expect(`{value:get()}@{pres.focus.focused:get()}`).toBe(`10@{AFTER}`)
	end)

	it("LevelPicker hot-switch: losing the pointer mid-scrub CANCELS back, it never commits", function()
		local _, adapter, _, pres, value, control = mount()
		adapter.pointerDown(STRIP, pointAt(adapter, 0.95))
		pres.refresh()
		expect(value:get()).toBe(10)
		control.onInteractionClassLost("pointer")
		pres.refresh()
		expect(value:get()).toBe(2) -- the pre-scrub value, not the half-finished one
	end)
end)

-- ===========================================================================
-- THE HIGH-COUNT DIAGNOSTIC, AND THE MEASUREMENT ITS NUMBER COMES FROM
--
-- Apple's HIG, Gauges: "A large value range can make the segments of a discrete
-- capacity indicator too small to be useful." A DIAGNOSTIC and never a refusal —
-- the caller may have more room than a phone, and refusing a count the caller
-- can afford would be the framework overruling a measurement it has not taken.
-- ===========================================================================
describe("LevelPicker: a high count is diagnosed, never refused", function()
	local themes = LuauUI.themes
	local PACKAGES = {
		"glossy_touch",
		"glossy_mobile",
		"pixel_quest",
		"fantasy_ornate",
		"scifi_hud",
		"compact_pointer",
		"classic_desktop",
		"fantasy_parchment",
	}

	it("a count within the threshold has no diagnostics at all", function()
		local _, _, _, _, _, control = mount({ count = level_picker.HIGH_COUNT })
		expect(#control.diagnostics()).toBe(0)
		expect(#control.dump().diagnostics).toBe(0)
	end)

	it("a count above the threshold adds a diagnostic and still BUILDS", function()
		local _, adapter, _, _, _, control = mount({ count = level_picker.HIGH_COUNT + 1 })
		local notes = control.diagnostics()
		expect(#notes).toBe(1)
		expect(string.find(notes[1], tostring(level_picker.HIGH_COUNT + 1), 1, true) ~= nil).toBe(true)
		expect(string.find(notes[1], "too small to be useful", 1, true) ~= nil).toBe(true)
		-- ...and it BUILT: the strip is on screen with every segment present
		expect(adapter.node(markPath(level_picker.HIGH_COUNT + 1)).class).toBe("Box")
		expect(control.dump().diagnostics[1]).toBe(notes[1])
	end)

	-- THE THRESHOLD IS MEASURED, NOT PICKED. `HIGH_COUNT` is the largest count at
	-- which every shipped theme package still solves each bar segment at least as
	-- wide as the narrowest mark that package draws (`iconSizes.small`), on the
	-- narrowest viewport this framework sweeps (320x640) with the run spaced for
	-- TOUCH — the paradigm with the wider gap, which is where the segments run out
	-- of room first. One more level and at least one shipped package falls below.
	local function narrowestSegment(pkgName: string, count: number): (number, number)
		local core, env, adapter, _, pres = world({ w = 320, h = 640 })
		env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
		env:set("preferredInput", "Touch")
		local control =
			LuauUI.newLevelPicker(LuauUI, core, { id = "Quality", value = core:signal(1), count = count, env = env })
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		local snap = themes.resolve((require)(`../examples/themes/{pkgName}`).build(themes), nil, {})
		env:set("themeMetrics", snap)
		pres.refresh()
		local narrowest = math.huge
		for i = 1, count do
			narrowest = math.min(narrowest, adapter.node(markPath(i)).rect.w)
		end
		return narrowest, snap.iconSizes.small
	end

	it("the threshold is the MEASURED one: every package clears it, and one fails at +1", function()
		for _, name in PACKAGES do
			local width, mark = narrowestSegment(name, level_picker.HIGH_COUNT)
			expect(`{name}:{width >= mark}`).toBe(`{name}:true`)
		end
		local anyFails = false
		for _, name in PACKAGES do
			local width, mark = narrowestSegment(name, level_picker.HIGH_COUNT + 1)
			if width < mark then
				anyFails = true
			end
		end
		expect(anyFails).toBe(true)
	end)
end)

-- ===========================================================================
describe("newRating is a thin preset over newLevelPicker", function()
	it("newRating is count 5, glyph segments and the star pair — nothing else", function()
		local core, _, adapter, _, pres = world()
		local control = LuauUI.newRating(LuauUI, core, { id = "Stars", value = core:signal(3) })
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		local out = ""
		for i = 1, 5 do
			local node = adapter.node(`/S/Stars/Stars/Star{i}`)
			expect(node.class).toBe("Text")
			out ..= node.props.text
		end
		expect(out).toBe("★★★☆☆")
		-- there is no sixth star: the preset's count is 5, not the level picker's
		expect(adapter.node("/S/Stars/Stars/Star6")).toBeNil()
		-- ...and a rating carries NO tint: a star already says which state it is in
		expect(adapter.node("/S/Stars/Stars/Star1").props.tint).toBeNil()
		expect(control.dump().segment).toBe("glyph")
		expect(control.dump().count).toBe(5)
	end)

	it("newRating still accepts starSize and maps it to the segment size", function()
		local core, _, adapter, _, pres = world()
		local small = LuauUI.newRating(LuauUI, core, { id = "A", value = core:signal(3) })
		local large = LuauUI.newRating(LuauUI, core, { id = "B", value = core:signal(3), starSize = "large" })
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.VStack({ id = "Col", children = { small.blueprint, large.blueprint } }),
			},
		}))
		pres.refresh()
		-- the adapter sees a RESOLVED number, not the metric name, so the proof is
		-- that the two rungs differ and that the default is the small one: a
		-- mapping that dropped `starSize` on the floor would make them equal
		local a = adapter.node("/S/Col/A/Stars/Star1").props.textSize
		local b = adapter.node("/S/Col/B/Stars/Star1").props.textSize
		expect(b > a).toBe(true)
		local explicitSmall = LuauUI.newRating(LuauUI, core, { id = "C", value = core:signal(3), starSize = "small" })
		pres.present(UI.Screen({ id = "T", children = { explicitSmall.blueprint } }))
		pres.refresh()
		expect(adapter.node("/T/C/Stars/Star1").props.textSize).toBe(a)
	end)

	it("newRating keeps its own dump schema, and gains `segment` additively", function()
		local core = customFactory.new()
		local control = LuauUI.newRating(LuauUI, core, { id = "Stars", value = core:signal(3) })
		local d = control.dump()
		-- every key the schema carried before this control was generalized still
		-- carries the value it carried: the schema stays /1 because nothing moved
		expect(d.schema).toBe("luauui-rating-dump/1")
		expect(`{d.id}/{d.value}/{d.count}/{d.min}/{d.readOnly}/{d.enabled}/{d.semanticText}`).toBe(
			"Stars/3/5/0/false/true/3 of 5"
		)
		expect(d.segment).toBe("glyph")
		control.dispose()
	end)

	it("newRating diagnoses a high count through exactly the same rule", function()
		local core = customFactory.new()
		local control = LuauUI.newRating(
			LuauUI,
			core,
			{ id = "Stars", value = core:signal(3), count = level_picker.HIGH_COUNT + 1 }
		)
		expect(#control.diagnostics()).toBe(1)
		control.dispose()
	end)
end)

-- ===========================================================================
--[[ A MARK MUST PAINT A RECTANGLE SOMEBODY CAN SEE (device report 2026-08-16).

	*"three of the five demo rows are blank."* The showcase's glyph and image rows
	rendered; every `segment = "bar"` row — the DEFAULT, and the shape the control
	was asked for — painted nothing at all. The marks were there, the tints were
	there, the strip reserved its 44px: each bar solved to `12x0`, a rectangle with
	no area (`src/layout/grid.luau`, "a line takes the grid's own flow extent").

	WHY THE 17 MUTATIONS THIS CONTROL SHIPPED WITH DID NOT CATCH IT. Every one of
	them asked a question about a DECLARATION — which segment, which tint, which
	half, which count, which threshold — and the one geometric case it had asserted
	`first.w > 0` and that the ten bars were equal WIDTH. Nothing ever multiplied
	the two sides together. A rect with a width is not a rect you can see, which is
	the same shape as `docs/lessons/a-default-valued-write-never-claims.md`: there,
	a probe read the tint off a plate that was never painted; here, a probe read the
	width off a plate that was never given a height. In both, THE INSTRUMENT
	REPORTED A NUMBER AND THE SCREEN WAS EMPTY.

	SO THE INSTRUMENT HERE IS THE AREA OF THE SOLVED RECT, and it is asked of the
	whole surface rather than of a path somebody remembered to list: `blankFills`
	walks every live node and reports each one whose ONLY possible paint is its own
	fill — a leaf `UI.Box` carrying a `tint`, i.e. a node with no text, no image and
	no child to be seen through — and whose rect has no area. That predicate is what
	generalizes: it does not know what a level picker is, so the next control that
	paints a run of tinted plates is covered by it on the day it ships.

	WHAT IS *NOT* REACHABLE FROM HERE, stated plainly. The other half of the
	invisible-plate family is the engine's own refusal of a default-valued write,
	and `GetStyled` is the only instrument that can see it — the fake adapter models
	the write rather than the engine's refusal of it, so no headless assertion can
	distinguish a claimed fill from a rejected one. That half is covered by the
	`luau-tint-fill` TAG (`sheet_model.TAGS`, `tests/sheet_model.spec.luau`) and by
	a Studio pass. The half a headless suite CAN see is the geometry, and it is the
	half that was blind here. ]]
describe("LevelPicker: every mark paints a rectangle with AREA", function()
	local device_views = require("./lib/device_views")
	local demo_picker = require("../examples/gallery/client/demo_picker") :: any
	local scenario = require("../examples/gallery/scenarios/level_picker") :: any

	-- A NODE WHOSE ONLY PAINT IS ITS FILL, AND WHOSE FILL HAS NO AREA. Deliberately
	-- not "every zero-area node": a spacer, an elided row and a collapsed group are
	-- all legitimately zero, and a check that fails on them is a check somebody
	-- waives. A tinted leaf Box has asked for a colour and can show it in exactly
	-- one place.
	local function blankFills(adapter: any): { string }
		local paths = adapter.paths()
		local hasChild: { [string]: boolean } = {}
		for _, path in paths do
			local cut = string.match(path, "^(.*)/[^/]+$")
			if cut ~= nil and cut ~= "" then
				hasChild[cut] = true
			end
		end
		local out: { string } = {}
		for _, path in paths do
			local node = adapter.node(path)
			local props = node.props or {}
			if node.class ~= "Box" or props.tint == nil or hasChild[path] then
				continue
			end
			local rect = node.rect
			if rect == nil or rect.w * rect.h <= 0 then
				table.insert(out, `{path} = {if rect then `{rect.w}x{rect.h}` else "no rect"}`)
			end
		end
		return out
	end

	it("a bar mark standing alone has HEIGHT as well as width", function()
		local _, adapter = mount()
		for i = 1, 10 do
			local rect = adapter.node(markPath(i)).rect
			expect(`Level{i} area: {rect.w * rect.h > 0}`).toBe(`Level{i} area: true`)
		end
		-- the strip declares the 44px effective target and the run fills it, so the
		-- mark's height IS that floor rather than some fraction of it
		expect(`mark height: {adapter.node(markPath(1)).rect.h}`).toBe(`mark height: {adapter.node(STRIP).rect.h}`)
		expect(#blankFills(adapter)).toBe(0)
	end)

	it("...and in the composition the showcase ships: a strip beside a stepper", function()
		-- the gallery's row is a `fill` picker in an HStack with `align = "center"`
		-- next to a content-sized stepper, which is where this was reported. A
		-- centred cross axis does not stretch its children, so the strip's own
		-- declared floor is the only thing holding the run open.
		local core, _, adapter, _, pres = world()
		local value = core:signal(2)
		local picker = LuauUI.newLevelPicker(LuauUI, core, { id = "Quality", value = value, count = 10 })
		local stepper = LuauUI.newStepper(LuauUI, core, { id = "QualityStep", value = value, min = 0, max = 10 })
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Card",
					surface = "control",
					padding = 8,
					width = { type = "fill", weight = 1 },
					children = {
						UI.HStack({
							id = "Pair",
							gap = 8,
							align = "center",
							width = { type = "fill", weight = 1 },
							children = { picker.blueprint, stepper.blueprint },
						}),
					},
				}),
			},
		}))
		pres.refresh()
		for i = 1, 10 do
			local rect = adapter.node(`/S/Card/Pair/Quality/Levels/Level{i}`).rect
			expect(`Level{i} area: {rect.w * rect.h > 0}`).toBe(`Level{i} area: true`)
		end
		expect(#blankFills(adapter)).toBe(0)
		picker.dispose()
		stepper.dispose()
	end)

	--[[ THE SURFACE THE DIRECTOR ACTUALLY LOOKED AT, at every viewport this
		framework sweeps. The two cases above are the control in a box this file
		built; this one mounts the SHIPPED fixture through the SHIPPED chrome
		reservation, which is the only thing that can claim the screen in the bug
		report is fixed. It walks the whole tree rather than the five rows by name,
		so a sixth row added tomorrow is swept without an edit. ]]
	it("the shipped gallery surface paints every tinted mark, at every swept viewport", function()
		local showcaseTop = demo_picker.barReservation(device_views.CORE_TOP, nil, 8)
		for _, view in device_views.VIEWS do
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
			env:set("coreSafeInsets", { top = showcaseTop, bottom = 0, left = 0, right = 0 })
			env:set("displaySize", view.displaySize)
			env:set("preferredInput", view.input)
			local adapter = fake_target.new()
			local system = actionsLib.newSystem(core)
			local pres = presenterLib.new(core, env, adapter, system)
			local built = scenario.build({
				LuauUI = LuauUI,
				core = core,
				env = env,
				adapter = adapter,
				presenter = pres,
				actionSystem = system,
				record = function() end,
				flags = {},
				geometry = function()
					return {}
				end,
			})
			pres.present(built.screen, built.present)
			for _ = 1, 3 do
				pres.refresh()
			end
			expect(`{view.id} blank fills: {table.concat(blankFills(adapter), ", ")}`).toBe(`{view.id} blank fills: `)
			-- ...and the two bar runs by name, so the case still says something if a
			-- future fixture stops carrying tinted marks at all
			for _, row in
				{
					{ id = "Balanced", picker = "BalancedBars", count = 10 },
					{ id = "Fidelity", picker = "FidelityBars", count = 3 },
				}
			do
				for i = 1, row.count do
					local node = adapter.node(`/LevelPickerDemo/Page/{row.id}/Pair/{row.picker}/Levels/Level{i}`)
					expect(`{view.id} {row.picker} Level{i} present: {node ~= nil}`).toBe(
						`{view.id} {row.picker} Level{i} present: true`
					)
					local rect = node.rect
					expect(`{view.id} {row.picker} Level{i} area: {rect.w * rect.h > 0}`).toBe(
						`{view.id} {row.picker} Level{i} area: true`
					)
				end
			end
			built.dispose()
		end
	end)
end)
