--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local Facet = require("../src")
local Compose = Facet.Compose
local scenarioCtx = require("./lib/scenario_ctx")
local skeleton = require("../src/controls/skeleton")
local function people(n)
	local out = {}
	for i = 1, n do
		table.insert(out, { id = "p" .. i, name = "Player " .. i })
	end
	return out
end
local function mount(w, spec)
	local record
	spec = table.clone(spec)
	spec.ref = function(value)
		record = value
	end
	w.present(function()
		return w.UI.Screen("S")({ w.UI.AvatarGroup("Group")(spec) })
	end)
	return record
end
local function node(w, path)
	return assert(w.adapter.node(path), path)
end
local function facePath(id, source)
	return "/S/Group/Members/[" .. id .. "]/" .. id .. "/Source/[" .. (source or "initials") .. "]/Face"
end
local CHIP = "/S/Group/Overflow/then/More+target/More"
t.afterEach(function()
	t.expect(skeleton.liveDrivers()).toBe(0)
end)
t.describe("AvatarGroup", function()
	t.it("caps the caller order, reports the hidden count, and leaves informational faces outside focus", function()
		local w = world.new()
		local record = mount(w, { items = people(6) })
		t.expect(record.dump().shown).toEqual({ "p1", "p2", "p3", "p4" })
		t.expect(record.dump().hidden).toBe(2)
		t.expect(record.dump().chipLabel).toBe("2 more")
		t.expect(node(w, "/S/Group/Overflow/then/More/Face/Count").props.text).toBe("+2")
		t.expect(require("../src/paths").nodeAt(w.handle.root.node, "/S/Group").props.gap).toBe(-14)
		t.expect(node(w, "/S/Group").props.align).toBeNil()
		t.expect(#w.handle.focusOrder().traversal).toBe(0)
	end)
	t.it("refuses every bad member before any provider lease is allocated", function()
		local w = world.new()
		local provider = w.app.newResourceProvider({ bind = false })
		local good = { id = "good", name = "Good", key = "good" }
		for _, bad in
			{
				{},
				{ id = "good", name = "Duplicate" },
				{ id = "bad", name = "" },
				{ id = "bad", name = "Bad", image = "art", key = "key" },
				{ id = "bad", name = "Bad", presence = "unknown" },
				{ id = "bad", name = "Bad", userId = 0 / 0 },
			}
		do
			local ok, message = pcall(function()
				w.scoped(function()
					w.UI.AvatarGroup({ items = { good, bad }, provider = provider })
				end)
			end)
			t.expect(ok).toBe(false)
			if bad.id == "bad" then
				t.expect(string.find(tostring(message), "member 'bad'", 1, true) ~= nil).toBe(true)
			end
			t.expect(provider.counters().handles).toBe(0)
		end
	end)
	t.it("keeps paint and dump on the last valid roster and recovers with a new legal list", function()
		local w = world.new()
		local items = Compose.cell(people(3))
		local record = mount(w, { items = items, max = 2 })
		local before = node(w, "/S/Group").rect
		for _, invalid in
			{
				"bad",
				{ { id = "same", name = "A" }, { id = "same", name = "B" } },
				{ { id = "p1", name = "A", presence = "bad" } },
			}
		do
			items:set(invalid)
			w.pres.refresh()
			t.expect(record.dump().shown).toEqual({ "p1", "p2" })
			t.expect(record.dump().hidden).toBe(1)
			t.expect(node(w, "/S/Group").rect).toEqual(before)
		end
		items:set({ { id = "new", name = "New" } })
		w.pres.refresh()
		t.expect(record.dump().shown).toEqual({ "new" })
		t.expect(record.dump().hidden).toBe(0)
		t.expect(w.adapter.node("/S/Group/Overflow/then/More")).toBeNil()
		t.expect(w.adapter.node(facePath("p1"))).toBeNil()
		t.expect(w.adapter.node(facePath("p2"))).toBeNil()
		t.expect(node(w, facePath("new") .. "/Initials").props.text).toBe("N")
	end)
end)

t.describe("AvatarGroup retained rows", function()
	t.it("retains factories and leases on reorder and replaces only a changed source", function()
		local w = world.new()
		local provider = w.app.newResourceProvider({ bind = false })
		local acquire, calls = provider.acquire, 0
		provider.acquire = function(owner, key)
			calls += 1
			return acquire(owner, key)
		end
		local a, b =
			{ id = "a", name = "Ada", key = "shared", presence = "online" }, { id = "b", name = "Bo", key = "shared" }
		local items = Compose.cell({ a, b })
		mount(w, { items = items, provider = provider, layout = "spread" })
		t.expect(calls).toBe(2)
		t.expect(provider.counters().handles).toBe(2)
		t.expect(#provider.pendingRequests()).toBe(1)
		local request = provider.pendingRequests()[1]
		provider.complete(request.key, request.generation, "rbxassetid://1")
		w.pres.refresh()
		t.expect(skeleton.liveDrivers()).toBe(0)
		local ap, bp = facePath("a", "key:shared"), facePath("b", "key:shared")
		local af, bf = node(w, ap), node(w, bp)
		local creates = w.controller.stats().creates
		items:set({ b, { id = "a", name = "Alice Quill", key = "shared", presence = "away", presenceLabel = "Out" } })
		w.pres.refresh()
		t.expect(node(w, ap)).toBe(af)
		t.expect(node(w, bp)).toBe(bf)
		t.expect(node(w, bp).rect.x < node(w, ap).rect.x).toBe(true)
		t.expect(w.controller.stats().creates).toBe(creates)
		t.expect(calls).toBe(2)
		items:set({ { id = "a", name = "Alice Quill", key = "new" }, b })
		w.pres.refresh()
		t.expect(calls).toBe(3)
		t.expect(provider.counters().handles).toBe(2)
		t.expect(node(w, bp)).toBe(bf)
		t.expect(w.adapter.node(ap)).toBeNil()
		t.expect(node(w, facePath("a", "key:new")) ~= af).toBe(true)
		items:set({ b })
		w.pres.refresh()
		t.expect(provider.counters().handles).toBe(1)
		w.close()
		t.expect(provider.counters().handles).toBe(0)
	end)
	t.it("updates current initials and keeps stacked presence semantic while spread paints it", function()
		for _, layout in { "stacked", "spread" } do
			local w = world.new()
			local items = Compose.cell({ { id = "a", name = "Ada", presence = "online" } })
			mount(w, { items = items, layout = layout })
			local path = facePath("a")
			local old = node(w, path)
			items:set({ { id = "a", name = "Émile Noël", presence = "offline", presenceLabel = "Local offline" } })
			w.pres.refresh()
			t.expect(node(w, path)).toBe(old)
			t.expect(node(w, path .. "/Initials").props.text).toBe("ÉN")
			t.expect(scenarioCtx.of(w).controlRecord("Face").dump().label).toBe("Émile Noël, Local offline")
			t.expect(w.adapter.node(path .. "/Presence") ~= nil).toBe(layout == "spread")
			t.expect(#w.handle.focusOrder().traversal).toBe(0)
			w.close()
		end
	end)
	t.it("uses localized overflow semantics for either visual word", function()
		for _, form in { "count", "ellipsis" } do
			local w = world.new()
			local phrase = Compose.cell("Deux autres")
			local record = mount(
				w,
				{ items = people(3), max = 1, overflow = form, overflowLabel = phrase, onOverflow = function() end }
			)
			local raw = require("../src/paths").nodeAt(w.handle.root.node, CHIP)
			t.expect(raw.props.label).toBe("Deux autres")
			t.expect(node(w, CHIP .. "/Face/Count").props.text).toBe(if form == "count" then "+2" else "…")
			phrase:set("Encore deux")
			w.pres.refresh()
			t.expect(raw.props.label).toBe("Encore deux")
			t.expect(record.dump().chipLabel).toBe("Encore deux")
			t.expect(#w.handle.focusOrder().traversal).toBe(1)
			w.close()
		end
	end)
	t.it("keeps parent alignment and derives overlap and targets from live checked theme rungs", function()
		local snapshot = require("../src/themes/snapshot")
		local metrics = table.clone(snapshot.neutral())
		metrics.targetSizes = table.clone(metrics.targetSizes)
		metrics.targetSizes.minimum = 60
		local w = world.new({ themeMetrics = metrics })
		local rung = Compose.cell("compact")
		mount(w, { items = people(3), max = 2, controlSize = rung, onOverflow = function() end })
		local group = require("../src/paths").nodeAt(w.handle.root.node, "/S/Group")
		local target = "/S/Group/Overflow/then/More+target"
		t.expect(group.props.align).toBeNil()
		t.expect(group.props.gap).toBe(-12)
		t.expect(node(w, facePath("p1")).rect.h).toBe(36)
		t.expect(node(w, target).rect.w).toBe(60)
		t.expect(node(w, target).rect.h).toBe(60)
		rung:set("bad")
		w.pres.refresh()
		t.expect(group.props.gap).toBe(-12)
		t.expect(node(w, facePath("p1")).rect.h).toBe(36)
		rung:set("large")
		w.pres.refresh()
		t.expect(group.props.gap).toBe(-18)
		t.expect(node(w, facePath("p1")).rect.h).toBe(56)
		rung:set(nil)
		w.pres.refresh()
		t.expect(group.props.gap).toBe(-14)
		t.expect(node(w, facePath("p1")).rect.h).toBe(44)
		w.env:set("themeMetrics", snapshot.neutral())
		w.pres.refresh()
		t.expect(node(w, target).rect.h).toBe(44)
	end)
end)

t.describe("AvatarGroup validated publication", function()
	t.it("keeps bound-nil localized presence valid through source replacement and later presence", function()
		local w = world.new()
		local provider = w.app.newResourceProvider({ bind = false })
		local originalAcquire, acquisitions = provider.acquire, 0
		provider.acquire = function(owner, key)
			acquisitions += 1
			return originalAcquire(owner, key)
		end
		local presence = Compose.cell(nil)
		local function roster(key)
			return {
				{ id = "a", name = "Ada", key = key, presence = presence, presenceLabel = "Localized" },
				{ id = "b", name = "Bo" },
			}
		end
		local items, activations = Compose.cell(roster("first")), 0
		local record = mount(w, {
			items = items,
			max = 1,
			layout = "spread",
			provider = provider,
			onOverflow = function()
				activations += 1
			end,
		})
		local firstPath = facePath("a", "key:first")
		local first = node(w, firstPath)
		local function faceDump()
			return scenarioCtx.of(w).controlRecord("Face").dump()
		end
		t.expect(faceDump().label).toBe("Ada")
		t.expect(provider.counters().handles).toBe(1)
		presence:set("online")
		w.pres.refresh()
		t.expect(node(w, firstPath)).toBe(first)
		t.expect(faceDump().label).toBe("Ada, Localized")
		presence:set("invalid")
		w.pres.refresh()
		t.expect(faceDump().presence).toBe("online")
		presence:set(nil)
		w.pres.refresh()
		t.expect(faceDump().label).toBe("Ada")
		items:set(roster("replacement"))
		w.pres.refresh()
		local nextPath = facePath("a", "key:replacement")
		t.expect(w.adapter.node(firstPath)).toBeNil()
		t.expect(node(w, nextPath) ~= first).toBe(true)
		t.expect(faceDump().label).toBe("Ada")
		t.expect(acquisitions).toBe(2)
		t.expect(provider.counters().handles).toBe(1)
		presence:set("busy")
		w.pres.refresh()
		t.expect(faceDump().label).toBe("Ada, Localized")
		t.expect(
			node(w, nextPath .. "/Presence/Visible/then/Status/Footprint/then/Rectangle/Inset/Body/MarkShape/then/Mark").props.shape
		).toBe("rect")
		t.expect(record.dump().shown).toEqual({ "a" })
		w.adapter.tap(CHIP)
		t.expect(activations).toBe(1)
		t.expect(#w.handle.focusOrder().traversal).toBe(1)
		items:set({})
		w.pres.refresh()
		t.expect(provider.counters().handles).toBe(0)
		t.expect(record.dump().shown).toEqual({})
		t.expect(w.adapter.node(CHIP)).toBeNil()
	end)
	t.it("refuses non-string overflow labels before allocation and recovers the mounted semantic label", function()
		local bad = world.new()
		local provider = bad.app.newResourceProvider({ bind = false })
		local ok, message = pcall(function()
			mount(
				bad,
				{ items = { { id = "a", name = "Ada", key = "picture" } }, provider = provider, overflowLabel = 42 }
			)
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(message), "overflowLabel", 1, true) ~= nil).toBe(true)
		t.expect(provider.counters().handles).toBe(0)
		local w = world.new()
		local phrase, calls = Compose.cell("More players"), 0
		local record = mount(w, {
			items = people(3),
			max = 1,
			overflowLabel = phrase,
			onOverflow = function()
				calls += 1
			end,
		})
		local raw = require("../src/paths").nodeAt(w.handle.root.node, CHIP)
		phrase:set(42)
		w.pres.refresh()
		t.expect(raw.props.label).toBe("More players")
		t.expect(record.dump().chipLabel).toBe("More players")
		t.expect(phrase:peek()).toBe(42)
		phrase:set("Tout le monde")
		w.pres.refresh()
		t.expect(raw.props.label).toBe("Tout le monde")
		phrase:set("")
		w.pres.refresh()
		t.expect(raw.props.label).toBe("2 more")
		phrase:set(nil)
		w.pres.refresh()
		t.expect(record.dump().chipLabel).toBe("2 more")
		w.adapter.tap(CHIP)
		t.expect(calls).toBe(1)
	end)
end)

t.describe("AvatarGroup inputs", function()
	for _, case in
		{
			{ device = "pointer", name = "AvatarGroup pointer: overflow activates through the presenter" },
			{ device = "touch", name = "AvatarGroup touch: overflow activates through the presenter" },
			{ device = "keyboard", name = "AvatarGroup keyboard: overflow activates through the presenter" },
			{ device = "gamepad", name = "AvatarGroup gamepad: overflow activates through the presenter" },
		}
	do
		t.it(case.name, function()
			local w = world.new({
				preferredInput = if case.device == "touch"
					then "Touch"
					elseif case.device == "gamepad" then "Gamepad"
					else "KeyboardAndMouse",
				capabilities = { keyboard = true, mouse = true, touch = true, gamepad = true },
			})
			local calls = 0
			mount(w, {
				items = people(5),
				onOverflow = function()
					calls += 1
				end,
			})
			if case.device == "pointer" then
				w.adapter.tap(CHIP)
			elseif case.device == "touch" then
				w.adapter.touchTap(CHIP)
			else
				w.pres.focus.focusOn(CHIP)
				w.press(if case.device == "keyboard" then "Return" else "ButtonA")
			end
			t.expect(calls).toBe(1)
			t.expect(#w.handle.focusOrder().traversal).toBe(1)
		end)
	end
	t.it("AvatarGroup pointer affordance: hover belongs only to the overflow target", function()
		local w = world.new()
		mount(w, { items = people(5), onOverflow = function() end })
		t.expect(node(w, CHIP).hoverEnabled).toBe(true)
		t.expect(node(w, facePath("p1")).hoverEnabled).toBeNil()
	end)
	t.it("AvatarGroup touch affordance: compact faces leave one whole overflow target", function()
		local w = world.new({ preferredInput = "Touch", capabilities = { touch = true } })
		mount(w, { items = people(5), controlSize = "compact", onOverflow = function() end })
		local target = node(w, "/S/Group/Overflow/then/More+target").rect
		local plate = node(w, CHIP).rect
		t.expect(plate.w).toBe(36)
		t.expect(target.w).toBe(44)
		t.expect(target.h).toBe(44)
		t.expect(plate.y + plate.h / 2).toBe(target.y + target.h / 2)
		t.expect(node(w, facePath("p1")).rect.h).toBe(36)
		t.expect(#w.handle.focusOrder().traversal).toBe(1)
	end)
	t.it("AvatarGroup keyboard affordance: one Tab rank and ordinary focus treatment", function()
		local w = world.new()
		mount(w, { items = people(5), onOverflow = function() end })
		t.expect(w.handle.focusOrder().traversal[1].path).toBe(CHIP)
		t.expect(node(w, CHIP).props.focusVisual).toBeNil()
		w.pres.focus.focusOn(CHIP)
		t.expect(w.pres.focus.focused:peek()).toBe(CHIP)
	end)
	t.it("AvatarGroup gamepad affordance: A activates while B stays with the screen", function()
		local w = world.new({ preferredInput = "Gamepad", capabilities = { gamepad = true } })
		local calls = 0
		mount(w, {
			items = people(5),
			onOverflow = function()
				calls += 1
			end,
		})
		w.pres.focus.focusOn(CHIP)
		w.press("ButtonA")
		w.press("ButtonB")
		t.expect(calls).toBe(1)
		t.expect(w.pres.focus.focused:peek()).toBe(CHIP)
	end)
end)

t.describe("AvatarGroup source and scenario", function()
	t.it("keeps distinct content identities and accepts repeated user ids with one shared request", function()
		local w = world.new()
		local provider = w.app.newResourceProvider({ bind = false })
		local items = Compose.cell({
			{ id = "a", name = "Ada", image = "rbxassetid://123" },
			{ id = "b", name = "Bo", image = "rbxassetid://456" },
			{ id = "c", name = "Côte", userId = 1 },
			{ id = "d", name = "Dan", userId = 1 },
		})
		mount(w, { items = items, provider = provider })
		t.expect(provider.counters().handles).toBe(2)
		t.expect(#provider.pendingRequests()).toBe(1)
		local first = node(w, facePath("a", "image:rbxassetid://123"))
		t.expect(node(w, facePath("b", "image:rbxassetid://456") .. "/Picture").props.image).toBe("rbxassetid://456")
		items:set({ { id = "a", name = "Ada", image = "rbxassetid://789" } })
		w.pres.refresh()
		t.expect(w.adapter.node(facePath("a", "image:rbxassetid://123"))).toBeNil()
		t.expect(node(w, facePath("a", "image:rbxassetid://789")) ~= first).toBe(true)
		t.expect(provider.counters().handles).toBe(0)
	end)
	t.it("refuses malformed container policies and keeps an empty group informational", function()
		local w = world.new()
		for _, spec in
			{
				{},
				{ items = false },
				{ items = { [2] = { id = "a", name = "A" } } },
				{ items = {}, max = 0 },
				{ items = {}, max = math.huge },
				{ items = {}, max = 1.5 },
				{ items = {}, layout = "grid" },
				{ items = {}, overflow = "more" },
				{ items = {}, form = "photo" },
				{ items = {}, onOverflow = true },
				{ items = {}, controlSize = "huge" },
				{ items = {}, over = "photo" },
				{ items = { { id = "a", name = "A", key = "portrait" } } },
			}
		do
			t.expect(pcall(function()
				w.scoped(function()
					w.UI.AvatarGroup(spec)
				end)
			end)).toBe(false)
		end
		local record = mount(w, { items = {} })
		t.expect(record.dump().shown).toEqual({})
		t.expect(record.dump().hidden).toBe(0)
		t.expect(record.dump().chipText).toBeNil()
		t.expect(#w.handle.focusOrder().traversal).toBe(0)
	end)
	t.it("loads the mounted gallery at rest and drives real roster layout size and overflow commands", function()
		local w = world.new()
		local scenario = require("../examples/gallery/scenarios/avatar_group").build(scenarioCtx.of(w))
		t.expect(scenario.report()).toBeNil()
		w.present(scenario.screen)
		w.pres.tick(0.05)
		local initial = scenario.report()
		t.expect(initial.group.shown).toEqual({ "ada", "bo", "noel", "cote" })
		t.expect(initial.imageBranches).toBe(2)
		t.expect(initial.providerHandles).toBe(2)
		t.expect(skeleton.liveDrivers()).toBe(0)
		local base = "/AvatarGroup/Content/GroupRecipe"
		w.adapter.tap(base .. "/RosterActions/Reorder")
		t.expect(scenario.report().group.shown).toEqual({ "bo", "noel", "cote", "kai" })
		t.expect(scenario.report().providerHandles).toBe(1)
		t.expect(scenario.steps.restore().group.hidden).toBe(2)
		local compact = scenario.steps.compact()
		t.expect(compact.faces.ada.h).toBe(36)
		t.expect(compact.overflowRect.h).toBe(36)
		t.expect(scenario.steps.large().faces.ada.h).toBe(56)
		t.expect(scenario.steps.spread().group.presenceMark).toBe(true)
		t.expect(scenario.steps.ellipsis().group.chipText).toBe("…")
		w.adapter.tap(base .. "/Variant/[ellipsis]/Team/Overflow/then/More+target/More")
		t.expect(scenario.report().activations).toBe(1)
		scenario.steps.source()
		w.pres.tick(0.05)
		t.expect(scenario.report().imageBranches).toBe(2)
		for _ = 1, 3 do
			scenario.steps.fewer()
		end
		t.expect(scenario.report().group.hidden).toBe(0)
		t.expect(scenario.report().overflowRect).toBeNil()
		w.close()
		t.expect(scenario.report()).toBeNil()
		scenario.dispose()
	end)
	t.it("embeds both identity recipes in one Indicators child tab with branch teardown", function()
		local catalog = require("../examples/gallery/scenarios/all_controls")
		local found
		for _, group in catalog.groups do
			if group.id == "indicators" then
				for _, entry in group.tabs do
					if entry.id == "identity" then
						t.expect(found).toBeNil()
						found = entry.scenario
					end
				end
			end
		end
		local w = world.new()
		local scenario = assert(found).build(scenarioCtx.of(w))
		w.present(scenario.screen)
		w.pres.tick(0.05)
		t.expect(scenario.report().avatar.imageMounted).toBe(true)
		t.expect(scenario.report().group.imageBranches).toBe(2)
		w.close()
		t.expect(scenario.report().avatar).toBeNil()
		t.expect(scenario.report().group).toBeNil()
		scenario.dispose()
	end)
end)
