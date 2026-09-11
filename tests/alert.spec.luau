--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local fake = require("./lib/fake_target")
local Facet = require("../src") :: any
local UI = Facet.UI
local function fixture(opts, spec)
	local o = opts or {}
	o.newAdapter = function()
		local a = fake.new()
		a.scrollBarThickness = fake.SCROLL_BAR_THICKNESS
		return a
	end
	local w = world.new(o)
	local events = {}
	local s = spec
		or {
			id = "Confirm",
			title = "Delete this save?",
			message = "This cannot be undone.",
			actions = {
				{
					id = "Delete",
					label = "Delete save",
					role = "destructive",
					onActivate = function()
						table.insert(events, "delete")
					end,
				},
				{
					id = "Cancel",
					label = "Cancel",
					role = "cancel",
					onActivate = function()
						table.insert(events, "cancel")
					end,
				},
			},
		}
	local alert = Facet.Controls.Alert(w.core, s)
	w.present(UI.Screen({ id = "Base", children = { UI.Button({ id = "Open", label = "Open" }) } }))
	w.pres.focus.focusOn("/Base/Open")
	local handle = alert.present(w.pres)
	w.settle(4)
	return w, alert, events, handle
end
local function action(id, screen)
	return `/{screen or "Confirm"}/Center/Card/Actions/Order/[{id}]/{id}`
end
local CANCEL = action("Cancel")
local DELETE = action("Delete")
local function clean(w, alert)
	alert.dispose()
	w.pres.dismiss(w.handle)
end

t.describe("Alert control", function()
	t.it("centers a content-sized card and keeps desktop actions in one row, cancel leading", function()
		local w, alert = fixture({ viewport = { x = 0, y = 0, w = 1280, h = 800 } })
		local card = w.adapter.node("/Confirm/Center/Card").rect
		local a, b = w.adapter.node(DELETE).rect, w.adapter.node(CANCEL).rect
		t.expect(card.w < 800 and card.h < 400).toBe(true)
		t.expect(math.abs(card.x + card.w / 2 - 640) < 1).toBe(true)
		t.expect(math.abs(card.y + card.h / 2 - 400) < 1).toBe(true)
		-- the platform row: cancel on the leading side whatever the author order
		t.expect(a.y == b.y and b.x + b.w <= a.x).toBe(true)
		t.expect(w.core:lastError()).toBe(nil)
		clean(w, alert)
	end)
	t.it("Alert pointer: a tap activates through the presenter (device-true)", function()
		local w, alert, events = fixture()
		w.adapter.tap(DELETE)
		w.settle(3)
		t.expect(events).toEqual({ "delete" })
		t.expect(alert.dump().presented).toBe(false)
		t.expect(w.pres.focus.focused:get()).toBe("/Base/Open")
		clean(w, alert)
	end)
	t.it("Alert touch: a touch tap/pan drives the control (device-true)", function()
		local w, alert, events = fixture({ preferredInput = "Touch" })
		w.adapter.tap(CANCEL, { source = "pointer", pointer = "touch" })
		w.settle(3)
		t.expect(events).toEqual({ "cancel" })
		t.expect(alert.dump().presented).toBe(false)
		clean(w, alert)
	end)
	for _, case in
		{
			{ "Alert keyboard: focus + Return drives the control", "Return", "MouseKeyboard" },
			{ "Alert gamepad: focus + ButtonA drives the control", "ButtonA", "Gamepad" },
		}
	do
		t.it(case[1], function()
			local w, alert, events = fixture({ preferredInput = case[3] })
			t.expect(w.pres.focus.focused:get()).toBe(CANCEL)
			w.press(case[2])
			t.expect(events).toEqual({ "cancel" })
			t.expect(alert.dump().presented).toBe(false)
			clean(w, alert)
		end)
	end
	t.it("Alert pointer affordance: hover on actions and a compact modal", function()
		local w, alert = fixture({ preferredInput = "MouseKeyboard" })
		t.expect(w.adapter.node(DELETE).hoverEnabled).toBe(true)
		w.adapter.hover(DELETE)
		t.expect(w.adapter.node(DELETE).hovered).toBe(true)
		clean(w, alert)
	end)
	t.it("Alert touch affordance: theme-sized targets and wrapping actions", function()
		local w, alert = fixture({
			preferredInput = "Touch",
			capabilities = { mouse = false, keyboard = false, touch = true, gamepad = false },
			viewport = { x = 0, y = 0, w = 240, h = 600 },
		})
		local a, b = w.adapter.node(DELETE).rect, w.adapter.node(CANCEL).rect
		t.expect(a.h >= 44 and b.h >= 44).toBe(true)
		t.expect(b.y >= a.y + a.h).toBe(true)
		t.expect(w.adapter.node(DELETE).hoverEnabled ~= true).toBe(true)
		clean(w, alert)
	end)
	t.it("Alert keyboard affordance: safe initial focus and trapped navigation", function()
		local w, alert = fixture({ preferredInput = "MouseKeyboard" })
		t.expect(w.adapter.node(CANCEL).focused).toBe(true)
		-- a compact phone stacks the actions, cancel at the bottom
		w.press("Up")
		t.expect(w.pres.focus.focused:get()).toBe(DELETE)
		w.press("Tab")
		t.expect(w.pres.focus.focused:get():sub(1, 9)).toBe("/Confirm/")
		w.press("Escape") -- reserved for Roblox
		t.expect(alert.dump().presented).toBe(true)
		w.pres.focus.focusOn(CANCEL)
		w.press("Return")
		t.expect(w.pres.focus.focused:get()).toBe("/Base/Open")
		clean(w, alert)
	end)
	t.it("Alert gamepad affordance: safe focus, B cancellation and ten-foot ring", function()
		local w, alert, events = fixture({
			preferredInput = "Gamepad",
			env = { viewingDistance = "ten-foot" },
			viewport = { x = 0, y = 0, w = 1920, h = 1080 },
		})
		t.expect(w.adapter.node(CANCEL).focusProfile).toBe("ten-foot")
		w.press("ButtonB")
		t.expect(events).toEqual({ "cancel" })
		t.expect(alert.dump().presented).toBe(false)
		clean(w, alert)
	end)
	t.it("stacks three actions on a desktop with cancel last and the likely action on top", function()
		local w, alert = fixture({ viewport = { x = 0, y = 0, w = 1280, h = 800 } }, {
			id = "Confirm",
			title = "Leave the race?",
			actions = {
				{ id = "Cancel", label = "Stay", role = "cancel" },
				{ id = "Save", label = "Save and leave" },
				{ id = "Delete", label = "Leave without saving", role = "destructive" },
			},
		})
		local save, delete, cancel =
			w.adapter.node(action("Save")).rect, w.adapter.node(action("Delete")).rect, w.adapter.node(CANCEL).rect
		t.expect(save.y + save.h <= delete.y and delete.y + delete.h <= cancel.y).toBe(true)
		t.expect(save.x == cancel.x and save.w == cancel.w and delete.w == cancel.w).toBe(true)
		t.expect(w.pres.focus.focused:get()).toBe(CANCEL)
		w.press("Up")
		t.expect(w.pres.focus.focused:get()).toBe(action("Delete"))
		clean(w, alert)
	end)
	t.it("ten-foot stacks two actions full width like a television alert", function()
		local w, alert = fixture({
			preferredInput = "Gamepad",
			env = { viewingDistance = "ten-foot" },
			viewport = { x = 0, y = 0, w = 1920, h = 1080 },
		})
		local card = w.adapter.node("/Confirm/Center/Card")
		local a, b = w.adapter.node(DELETE).rect, w.adapter.node(CANCEL).rect
		t.expect(a.y + a.h <= b.y and a.x == b.x and a.w == b.w).toBe(true)
		t.expect(a.w >= w.adapter.node("/Confirm/Center/Card/Message").rect.w).toBe(true)
		t.expect(card.rect.w <= 1920 - 2 * 90).toBe(true)
		local policy = require("../src/controls/alert")
		t.expect(policy.resolveStacked(2, "regular", "ten-foot", 0)).toBe(true)
		t.expect(policy.resolveStacked(2, "regular", "near", 0)).toBe(false)
		t.expect(policy.resolveStacked(2, "regular", "near", 14)).toBe(true)
		t.expect(policy.resolveStacked(3, "wide", "near", 0)).toBe(true)
		t.expect(policy.resolveStacked(2, "compact", "near", 0)).toBe(true)
		clean(w, alert)
	end)
	t.it("a live distance flip moves the same mounted actions and keeps focus", function()
		local w, alert = fixture({ viewport = { x = 0, y = 0, w = 1280, h = 800 } })
		local cancel, delete = w.adapter.node(CANCEL), w.adapter.node(DELETE)
		t.expect(cancel.rect.x < delete.rect.x).toBe(true)
		w.env:set("viewingDistance", "ten-foot")
		w.settle(4)
		t.expect(w.adapter.node(CANCEL)).toBe(cancel)
		t.expect(w.adapter.node(DELETE)).toBe(delete)
		t.expect(cancel.rect.y > delete.rect.y).toBe(true)
		t.expect(w.pres.focus.focused:get()).toBe(CANCEL)
		w.env:set("viewingDistance", "near")
		w.settle(4)
		t.expect(cancel.rect.x < delete.rect.x and cancel.rect.y == delete.rect.y).toBe(true)
		t.expect(w.core:lastError()).toBe(nil)
		clean(w, alert)
	end)
	t.it("Alert hot-switch: carries the open decision without remounting actions", function()
		local w, alert, _, handle = fixture()
		local node = w.adapter.node(CANCEL)
		local before = handle.root.counters().factoryRuns
		w.env:set("preferredInput", "Gamepad")
		w.env:set("viewingDistance", "ten-foot")
		w.env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 800 })
		w.settle(4)
		t.expect(alert.dump().presented).toBe(true)
		t.expect(w.adapter.node(CANCEL)).toBe(node)
		t.expect(handle.root.counters().factoryRuns).toBe(before)
		clean(w, alert)
	end)
	t.it("deduplicates presentation, reopens after Back, and has a deterministic dump", function()
		local w, alert, _, handle = fixture()
		t.expect(alert.present(w.pres)).toBe(handle)
		t.expect(alert.dump()).toEqual(alert.dump())
		w.press("ButtonB")
		t.expect(alert.dump().presented).toBe(false)
		alert.present(w.pres)
		w.settle(4)
		t.expect(alert.dump().presented).toBe(true)
		clean(w, alert)
	end)
	t.it("disposing an open alert restores the registry and prevents reopening", function()
		local w = world.new()
		w.present(UI.Screen({ id = "Base", children = { UI.Button({ id = "Open", label = "Open" }) } }))
		local before = w.core:counters()
		local alert = Facet.Controls.Alert(w.core, { title = "Continue?", actions = { { id = "ok", label = "OK" } } })
		alert.present(w.pres)
		alert.dispose()
		w.settle(4)
		for key, value in before do
			t.expect(w.core:counters()[key]).toBe(value)
		end
		t.expect(pcall(function()
			alert.present(w.pres)
		end)).toBe(false)
		w.pres.dismiss(w.handle)
	end)
	t.it("B can leave an alert with a disabled cancel without invoking it", function()
		local calls = 0
		local w, alert = fixture(nil, {
			title = "Wait?",
			actions = {
				{
					id = "cancel",
					label = "Cancel",
					role = "cancel",
					enabled = false,
					onActivate = function()
						calls += 1
					end,
				},
			},
		})
		w.press("ButtonB")
		t.expect(alert.dump().presented).toBe(false)
		t.expect(calls).toBe(0)
		clean(w, alert)
	end)
	for _, theme in { "pixel_quest", "fantasy_ornate" } do
		for _, size in { { 320, 640 }, { 844, 390 }, { 1280, 800 }, { 1920, 1080 } } do
			t.it(
				"contains alert chrome and actions at largest text: " .. theme .. " " .. size[1] .. "x" .. size[2],
				function()
					local metrics =
						Facet.themes.resolve(require("../examples/themes/" .. theme).build(Facet.themes), nil, {})
					local w, alert = fixture({
						viewport = { x = 0, y = 0, w = size[1], h = size[2] },
						themeMetrics = metrics,
						env = {
							preferredTextOffset = 14,
							viewingDistance = if size[1] == 1920 then "ten-foot" else "near",
						},
					})
					local card = w.adapter.node("/Confirm/Center/Card").rect
					t.expect(card.x >= 0 and card.y >= 0 and card.x + card.w <= size[1] and card.y + card.h <= size[2])
						.toBe(true)
					local a, b = w.adapter.node(DELETE).rect, w.adapter.node(CANCEL).rect
					t.expect(a.x + a.w <= b.x or b.y >= a.y + a.h).toBe(true)
					w.pres.focus.focusOn(DELETE)
					w.settle(6)
					clean(w, alert)
				end
			)
		end
	end

	t.it("supplies an OK action when no actions are authored", function()
		local w, alert = fixture(nil, { id = "Confirm", title = "Checkpoint saved" })
		w.adapter.tap(action("OK"))
		t.expect(alert.dump().presented).toBe(false)
		clean(w, alert)
	end)
	t.it("binds presentation in both directions without stacking or action callbacks", function()
		local w = world.new()
		local shown = w.core:signal(false)
		local calls = 0
		local alert = Facet.Controls.Alert(w.core, {
			title = "Continue?",
			isPresented = shown,
			presenter = w.pres,
			actions = {
				{
					id = "cancel",
					label = "Cancel",
					role = "cancel",
					onActivate = function()
						calls += 1
					end,
				},
			},
		})
		t.expect(w.pres.depth()).toBe(0)
		shown:set(true)
		w.pres.refresh()
		t.expect(w.pres.depth()).toBe(1)
		shown:set(true)
		t.expect(w.pres.depth()).toBe(1)
		shown:set(false)
		t.expect(w.pres.depth()).toBe(0)
		t.expect(calls).toBe(0)
		shown:set(true)
		w.press("ButtonB")
		t.expect(shown:get()).toBe(false)
		t.expect(calls).toBe(1)
		alert.dispose()
		shown:dispose()
	end)
	t.it("snapshots presented data for labels and callbacks and waits for a nonnil item", function()
		local w = world.new()
		local item = w.core:signal(nil)
		local chosen = nil
		local alert = Facet.Controls.Alert(w.core, {
			id = "Data",
			presenter = w.pres,
			item = item,
			title = function(data)
				return "Delete " .. data.name .. "?"
			end,
			actions = function(data)
				return {
					{
						id = "delete",
						label = "Delete " .. data.name,
						role = "destructive",
						onActivate = function(value)
							chosen = value.name
						end,
					},
				}
			end,
		})
		t.expect(w.pres.depth()).toBe(0)
		item:set({ name = "Alpha" })
		w.pres.refresh()
		item:set({ name = "Beta" })
		w.pres.refresh()
		w.adapter.tap("/Data/Center/Decision/then/Card/Actions/Order/[delete]/delete")
		t.expect(chosen).toBe("Alpha")
		t.expect(item:get()).toBe(nil)
		alert.dispose()
		item:dispose()
	end)

	t.it("refuses misspelled fields and ambiguous action identities or cancel roles", function()
		local w = world.new()
		for _, spec in
			{
				{ title = "Hi", actions = {}, paddding = "l" },
				{ title = "Hi", message = 42 },
				{ title = "Hi", actions = { { id = "a", label = "A", role = "wrong" } } },
				{ title = "Hi", actions = { unexpected = true } },
				{
					title = "Hi",
					presenting = {},
					actions = { { id = "a", label = "A", shortcut = { typo = "Return" } } },
				},
				{ title = "Hi", isPresented = false },
				{ title = "Hi", actions = { { id = "a", label = "A" }, { id = "a", label = "B" } } },
				{
					title = "Hi",
					actions = { { id = "a", label = "A", role = "cancel" }, { id = "b", label = "B", role = "cancel" } },
				},
			}
		do
			t.expect(pcall(function()
				Facet.Controls.Alert(w.core, spec)
			end)).toBe(false)
		end
	end)
end)

t.describe("Alert custom content and shortcuts", function()
	t.it("does not interpret a custom content ID as an alert action", function()
		local w, a = fixture(nil, {
			id = "Confirm",
			title = "Confirm",
			content = function()
				return UI.VStack({ id = "Custom", children = { UI.Button({ id = "OK", label = "Preview" }) } })
			end,
		})
		w.adapter.tap("/Confirm/Center/Decision/then/Card/Custom/OK")
		w.settle(2)
		t.expect(a.dump().presented).toBe(true)
		clean(w, a)
	end)
	t.it("preserves compact copy and emphasis when an action has a shortcut", function()
		local w, a = fixture(nil, {
			id = "Confirm",
			title = "Confirm",
			actions = {
				{
					id = "Go",
					label = "Proceed with this journey",
					compactLabel = "Go",
					role = "default",
					shortcut = "defaultAction",
				},
			},
		})
		local p = w.adapter.node(action("Go")).props
		t.expect(p.compactLabel).toBe("Go")
		t.expect(p.surface).toBe("accent")
		clean(w, a)
	end)
	t.it("contains a bad data factory and allows a corrected item to present", function()
		local w = world.new()
		local bad = true
		local a = Facet.Controls.Alert(w.core, {
			title = function()
				if bad then
					error("bad datum")
				end
				return "Ready"
			end,
		})
		local ok = pcall(a.present, w.pres)
		t.expect(ok).toBe(true)
		t.expect(a.dump().presented).toBe(false)
		t.expect(a.dump().lastError ~= nil).toBe(true)
		bad = false
		t.expect(a.present(w.pres) ~= nil).toBe(true)
		t.expect(a.dump().lastError ~= nil).toBe(true)
		a.dispose()
	end)
end)

t.describe("Alert presentation features", function()
	t.it("provides error copy and critical artwork and clears its error binding on Back", function()
		local w = world.new({ reducedMotion = true })
		local problem =
			w.core:signal({ errorDescription = "Save failed", recoverySuggestion = "Reconnect and try again." })
		local a = Facet.Controls.Alert(w.core, { id = "Error", error = problem, presenter = w.pres })
		w.settle(2)
		t.expect(w.adapter.node("/Error/Center/Decision/then/Card/Header/Title").props.text).toBe("Save failed")
		t.expect(w.adapter.node("/Error/Center/Decision/then/Card/Message").props.text).toBe("Reconnect and try again.")
		t.expect(a.dump().severity).toBe("critical")
		w.press("ButtonB")
		w.settle(2)
		t.expect(problem:get()).toBe(nil)
		t.expect(a.dump().presented).toBe(false)
		a.dispose()
	end)
	t.it("contains an initially bound bad factory without stranding the binding", function()
		local w = world.new()
		local shown = w.core:signal(true)
		local ok, a = pcall(Facet.Controls.Alert, w.core, {
			isPresented = shown,
			presenter = w.pres,
			title = function()
				error("invalid initial data")
			end,
		})
		t.expect(ok).toBe(true)
		t.expect(shown:get()).toBe(false)
		t.expect(a.dump().lastError ~= nil).toBe(true)
		a.dispose()
	end)
	t.it("keeps a long message scrollable to its actions on short landscape screens", function()
		local w, a, _, h = fixture({ viewport = { x = 0, y = 0, w = 640, h = 320 }, reducedMotion = true }, {
			id = "Confirm",
			title = "Review changes",
			message = string.rep("Check your selected equipment before continuing. ", 40),
			actions = { { id = "Cancel", label = "Cancel", role = "cancel" }, { id = "Go", label = "Continue" } },
		})
		local card = w.adapter.node("/Confirm/Center/Card")
		t.expect(card.scrollRegion.contentH > card.rect.h).toBe(true)
		w.press("DPadRight")
		w.settle(3)
		local offset = h.controller.scrollPosition("/Confirm/Center/Card")
		t.expect(offset.y > 0).toBe(true)
		local r = h.controller.screenRectOf(action("Go"))
		t.expect(r.y >= card.rect.y - 1 and r.y + r.h <= card.rect.y + card.rect.h + 1).toBe(true)
		clean(w, a)
	end)
end)

t.describe("Alert content lifetime", function()
	t.it("contains a failing content factory and releases its resources before retry", function()
		local w = world.new()
		local bad = true
		local a = Facet.Controls.Alert(w.core, {
			title = "Edit name",
			content = function(scope)
				local value = scope:own(w.core:signal("Name"))
				if bad then
					error("bad content")
				end
				return UI.Text({ id = "Name", text = value })
			end,
		})
		local before = w.core:counters()
		t.expect(pcall(a.present, w.pres)).toBe(true)
		t.expect(a.dump().presented).toBe(false)
		t.expect(w.core:counters()).toEqual(before)
		bad = false
		t.expect(a.present(w.pres) ~= nil).toBe(true)
		a.dismiss()
		t.expect(w.core:counters()).toEqual(before)
		a.dispose()
	end)
end)

t.describe("Brief critical phone alert", function()
	t.it("keeps a brief critical decision and both actions visible on a short phone", function()
		local w, a = fixture(
			{ viewport = { x = 0, y = 0, w = 749, h = 235 }, preferredInput = "Touch", reducedMotion = true },
			{
				id = "Confirm",
				title = "Replace this save?",
				severity = "critical",
				message = "Your current progress will replace the previous checkpoint.",
				actions = {
					{ id = "Cancel", label = "Keep previous", role = "cancel" },
					{ id = "Delete", label = "Replace save", role = "destructive" },
				},
			}
		)
		local card = w.adapter.node("/Confirm/Center/Card").rect
		for _, path in { CANCEL, DELETE } do
			local r = w.adapter.node(path).rect
			t.expect(r.y >= card.y and r.y + r.h <= card.y + card.h).toBe(true)
		end
		clean(w, a)
	end)
end)
