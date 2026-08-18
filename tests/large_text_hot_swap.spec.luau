--!strict
--[[ THE PREFERENCE SWING, WITH THE SCREEN ALIVE (acceptance LT-2 through the
	LT-8 matrix's own live rows).

	`PreferredTextSize` is read-only and can change WHILE the experience runs
	(the probe watched the change signal fire on every step in both directions),
	so the framework's promise is not "a screen laid out at Largest looks right".
	It is: a change remeasures and reflows the mounted tree WITHOUT remounting
	it, and without losing control state, focus, input ownership or scroll
	position — and stepping back returns exactly what was there before.

	tests/preferred_text_seam.spec proves that on a two-node screen with nothing
	going on. This file proves it with the screen BUSY: a control focused, a
	field mid-edit with typed text that has not been committed, and a list
	scrolled away from its top. Those are the three things a rebuild silently
	eats, and each of them is read back through the same public seam a consumer
	would use.

	THE SWING IS 0 -> 14 -> 0 on purpose. A one-way change can be made to look
	correct by a rebuild that happens to produce a similar tree; the round trip
	cannot, because the geometry at the end has to be byte-identical to the
	geometry at the start and every live piece of state has to still be there.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local UI = require("../src/blueprint")
local lt = require("./lib/large_text")

local FIELD = "/S/Body/Name/Field"
local LIST = "/S/Body/List"
local STATUS = lt.PSEUDO
local PRIMARY = lt.PSEUDO_ACTION

-- a busy screen: a scrollable list, a text field, and two buttons to focus
local function busyScreen(core: any, w: any): any
	local rows: { any } = {}
	for i = 1, 12 do
		table.insert(rows, UI.Text({ id = `Row{i}`, text = `{i} — {STATUS}` }))
	end
	local field = Facet.newTextInput(Facet, core, {
		id = "Name",
		value = w.fieldValue,
		placeholder = STATUS,
		env = w.env,
		actionSystem = w.system,
		onCommit = function(text: string, reason: string)
			table.insert(w.commits, { text = text, reason = reason })
		end,
	})
	w.field = field
	return UI.Screen({
		id = "S",
		children = {
			UI.VStack({
				id = "Body",
				height = { type = "fill", weight = 1 },
				children = {
					field.blueprint,
					UI.ScrollView({ id = "List", height = { type = "fixed", px = 240 }, children = rows }),
					UI.Button({ id = "Save", label = PRIMARY }),
					UI.Button({ id = "Later", label = lt.PSEUDO_SECONDARY }),
				},
			}),
		},
	})
end

-- present the busy screen and put it in the live state the swing has to survive
local function liveWorld(opts: any?): any
	local options: any = opts or {}
	local w = lt.world({
		viewport = lt.PHONE_PORTRAIT,
		theme = options.theme,
		offset = 0,
		input = "desktop", -- a hardware keyboard, so focus is a real thing to lose
	})
	w.fieldValue = w.core:signal("")
	w.commits = {}
	w.present(busyScreen(w.core, w))
	-- 1. a field MID-EDIT: entered, typed into, never committed
	w.adapter.tap(FIELD)
	w.adapter.focusText(FIELD)
	w.adapter.typeText(FIELD, "Kai")
	-- 2. a list scrolled away from its top
	w.adapter.driveScroll(LIST, { x = 0, y = 120 })
	-- 3. SETTLE. Typing writes the value signal, which dirties the field: the
	-- geometry that reflects "Kai" only exists after the next solve. Snapshotting
	-- before this refresh compares the swing against a frame that shows the
	-- PLACEHOLDER, and reports the edit's own re-measure as a preference defect
	-- (which is exactly what the first draft of this file did).
	w.pres.refresh()
	return w
end

local function scrollPosition(w: any): number
	local pos = w.adapter.scrollPositionOf(LIST)
	return if pos == nil then 0 else pos.y
end

local function maxScroll(w: any): number
	local region = w.adapter.scrollRegionOf(LIST)
	local box = w.adapter.node(LIST).rect
	return math.max(0, (region.contentH or 0) - box.h)
end

describe("LT-2 hot swap: a live screen survives the preference swing 0 -> 14 -> 0", function()
	it("LTSWING-IDENTITY the swing writes rects and props only — not one create or remove", function()
		local w = liveWorld()
		local creates, removes = w.controller.stats().creates, w.controller.stats().removes
		w.adapter.takeOps()
		for _, offset in { lt.LARGEST, 0 } do
			w.env:set("preferredTextOffset", offset)
			w.pres.refresh()
			local structural = lt.structuralOps(w.adapter.takeOps())
			if #structural > 0 then
				error(`the preference change rebuilt the tree at +{offset}: {table.concat(structural, ", ")}`, 0)
			end
		end
		-- ...and the controller's own counters agree with the op log
		expect(w.controller.stats().creates).toBe(creates)
		expect(w.controller.stats().removes).toBe(removes)
	end)

	it("LTSWING-FOCUS the focused path is the same node before, during and after the swing", function()
		local w = liveWorld()
		local before = w.pres.focus.focused:get()
		expect(before).toBe(FIELD)
		w.env:set("preferredTextOffset", lt.LARGEST)
		w.pres.refresh()
		expect(w.pres.focus.focused:get()).toBe(before)
		w.env:set("preferredTextOffset", 0)
		w.pres.refresh()
		expect(w.pres.focus.focused:get()).toBe(before)
	end)

	it("LTSWING-EDIT the field keeps its typed, uncommitted text and stays in edit mode", function()
		local w = liveWorld()
		expect(w.fieldValue:get()).toBe("Kai")
		expect(w.field.api.editing:get()).toBe(true)
		expect(#w.commits).toBe(0)
		w.env:set("preferredTextOffset", lt.LARGEST)
		w.pres.refresh()
		expect(w.fieldValue:get()).toBe("Kai")
		-- INPUT OWNERSHIP survives too: the edit's sinking context is still up, so
		-- keystrokes are still text rather than navigation
		expect(w.field.api.editing:get()).toBe(true)
		-- a re-solve must not look like a focus loss to the field: an accidental
		-- commit here is the defect that eats a half-typed racer name
		expect(#w.commits).toBe(0)
		expect(w.adapter.node(FIELD).props.text).toBe("Kai")
		w.env:set("preferredTextOffset", 0)
		w.pres.refresh()
		expect(w.fieldValue:get()).toBe("Kai")
		expect(w.field.api.editing:get()).toBe(true)
		expect(#w.commits).toBe(0)
	end)

	it("LTSWING-SCROLL the list keeps its scroll offset, or is legally clamped to its new extent", function()
		local w = liveWorld()
		local before = scrollPosition(w)
		expect(before).toBe(120)
		w.env:set("preferredTextOffset", lt.LARGEST)
		w.pres.refresh()
		local during = scrollPosition(w)
		-- taller rows can only make the canvas LONGER, so the position it was at
		-- is still legal and must be kept
		expect(during).toBe(before)
		expect(during).toBeLessThanOrEqual(maxScroll(w))
		w.env:set("preferredTextOffset", 0)
		w.pres.refresh()
		local after = scrollPosition(w)
		expect(after).toBeGreaterThanOrEqual(0)
		expect(after).toBeLessThanOrEqual(maxScroll(w))
		expect(after).toBe(before)
	end)

	it("LTSWING-GEOMETRY every rect returns byte-identical when the preference comes back to Medium", function()
		local w = liveWorld()
		local before = lt.geometryOf(w)
		w.env:set("preferredTextOffset", lt.LARGEST)
		w.pres.refresh()
		local grown = lt.geometryOf(w)
		-- the swing has to have MOVED something, or "identical on return" is a
		-- claim about a preference that never arrived
		local moved = 0
		for path, rect in before do
			if grown[path] ~= rect then
				moved += 1
			end
		end
		expect(moved).toBeGreaterThan(0)
		w.env:set("preferredTextOffset", 0)
		w.pres.refresh()
		local after = lt.geometryOf(w)
		for path, rect in before do
			if after[path] ~= rect then
				error(`{path} came back as {tostring(after[path])}, was {rect}`, 0)
			end
		end
		for path in after do
			expect(before[path]).never().toBeNil()
		end
	end)

	it("LTSWING-CLEAN the busy screen files no overlap or undisclosed-clip finding at either end", function()
		local w = liveWorld()
		for _, offset in { 0, lt.LARGEST, 0 } do
			w.env:set("preferredTextOffset", offset)
			w.pres.refresh()
			local found = lt.sweep(w)
			if #found.overlaps > 0 then
				error(lt.describeFindings(`swing+{offset}`, found.overlaps), 0)
			end
			if #found.clipped > 0 then
				error(lt.describeFindings(`swing+{offset}`, found.clipped), 0)
			end
		end
	end)
end)

describe("LT-5 composition: a theme swap and the preference compose on a live screen", function()
	it("LTSWAP-THEME installing Fantasy Parchment at Largest re-solves in place with no finding", function()
		-- the two authorities that own text geometry, moved one after the other on
		-- the SAME mounted tree: the preference (an additive px offset) and the
		-- theme snapshot (faces, metrics, chrome). Neither may rebuild the tree,
		-- and their composition may not clip anything.
		local w = liveWorld()
		w.env:set("preferredTextOffset", lt.LARGEST)
		w.pres.refresh()
		w.adapter.takeOps()
		local creates = w.controller.stats().creates

		w.env:set("themeMetrics", lt.THEMES[2].metrics)
		w.pres.refresh()

		local structural = lt.structuralOps(w.adapter.takeOps())
		expect(#structural).toBe(0)
		expect(w.controller.stats().creates).toBe(creates)
		expect(w.pres.focus.focused:get()).toBe(FIELD)
		expect(w.fieldValue:get()).toBe("Kai")

		local found = lt.sweep(w)
		if #found.overlaps > 0 then
			error(lt.describeFindings("parchment@Largest", found.overlaps), 0)
		end
		if #found.clipped > 0 then
			error(lt.describeFindings("parchment@Largest", found.clipped), 0)
		end
	end)

	it("LTSWAP-ORDER the same pair applied in the other order lands on identical geometry", function()
		-- theme-then-preference and preference-then-theme must agree: if they do
		-- not, one of the two is being applied to a stale snapshot of the other
		local themeFirst = liveWorld()
		themeFirst.env:set("themeMetrics", lt.THEMES[2].metrics)
		themeFirst.pres.refresh()
		themeFirst.env:set("preferredTextOffset", lt.LARGEST)
		themeFirst.pres.refresh()

		local preferenceFirst = liveWorld()
		preferenceFirst.env:set("preferredTextOffset", lt.LARGEST)
		preferenceFirst.pres.refresh()
		preferenceFirst.env:set("themeMetrics", lt.THEMES[2].metrics)
		preferenceFirst.pres.refresh()

		local a, b = lt.geometryOf(themeFirst), lt.geometryOf(preferenceFirst)
		for path, rect in a do
			if b[path] ~= rect then
				error(`{path}: theme-first solved {rect}, preference-first solved {tostring(b[path])}`, 0)
			end
		end
		for path in b do
			expect(a[path]).never().toBeNil()
		end
	end)

	it("LTSWAP-BORN a screen BORN at Largest under Parchment matches one swung there live", function()
		-- the strongest statement of "no remount": the reflow path and the
		-- first-mount path have to arrive at the same screen, or a player who
		-- changed the setting is looking at something a fresh launch never shows
		local swung = liveWorld()
		swung.env:set("preferredTextOffset", lt.LARGEST)
		swung.pres.refresh()
		swung.env:set("themeMetrics", lt.THEMES[2].metrics)
		swung.pres.refresh()

		local born = lt.world({
			viewport = lt.PHONE_PORTRAIT,
			theme = lt.THEMES[2],
			offset = lt.LARGEST,
			input = "desktop",
		})
		born.fieldValue = born.core:signal("")
		born.commits = {}
		born.present(busyScreen(born.core, born))
		born.adapter.tap(FIELD)
		born.adapter.focusText(FIELD)
		born.adapter.typeText(FIELD, "Kai")
		born.adapter.driveScroll(LIST, { x = 0, y = 120 })

		local a, b = lt.geometryOf(swung), lt.geometryOf(born)
		for path, rect in a do
			if b[path] ~= rect then
				error(`{path}: swung to {rect}, born at {tostring(b[path])}`, 0)
			end
		end
		for path in b do
			expect(a[path]).never().toBeNil()
		end
	end)
end)
