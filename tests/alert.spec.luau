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
		-- the modal now dips out on a real (if brief) exit transition, so its
		-- surface scope survives past the `dismiss()` call until the coordinator's
		-- retire completes; past the 500ms hard exit cap, not just past this
		-- transition's own duration, is what proves teardown rather than timing
		for _ = 1, 40 do
			w.pres.tick(1 / 60)
		end
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

t.describe("alert: the modal materializes", function()
	--[[ NOT `fixture`: it presents AND settles 4 frames before handing control
		back (needed by every other `it` in this file, which reads settled
		state), so by the time these two tests could observe it the materialize
		spring is already 4 frames in — measured 0.616 transparency, not the
		freshly-seeded 1 these assertions need. `world.new()` + a direct
		`alert.present(w.pres)`, exactly what "Alert content lifetime" above
		already does, gives the untouched first-frame state instead. ]]
	local FRAME = 1 / 60
	t.it("enters through a fade group and leaves faster than it came", function()
		--[[ MEASURED ON THE PAINT, NOT ON THE CLOCK GOING QUIET (task 7 item 1).
			The first shape of this test compared "frames until transparency
			reached 0" against "frames until the node was gone", and BOTH sides
			were dominated by a settle tolerance rather than by the motion: the
			exit ended on the flat 500 ms cap, so it read as faster no matter
			which exit class was in force — `exitClass = "container"` passed it
			just as happily as `dismiss`. What the round actually claims is that
			the modal DIPS OUT faster than it grows in, so the pin is the frame
			the fade crosses 95% in each direction, plus the fact that the exit
			is ended by its own spring rather than by the cap. ]]
		local w = world.new()
		local alert = Facet.Controls.Alert(w.core, {
			id = "Confirm",
			title = "Delete?",
			actions = { { id = "ok", label = "OK" } },
		})
		local handle = alert.present(w.pres)
		local center = w.adapter.node("/Confirm/Center")
		t.expect(center.canvasGroupInstance ~= nil).toBe(true)
		t.expect(center.canvasGroupInstance.groupTransparency).toBe(1)
		local enterCross = -1
		for f = 1, 120 do
			w.pres.tick(FRAME)
			if enterCross < 0 and center.canvasGroupInstance.groupTransparency <= 0.05 then
				enterCross = f
			end
		end
		t.expect(enterCross > 0).toBe(true)
		w.pres.dismiss(handle)
		local exitCross, goneAt = -1, -1
		for f = 1, 120 do
			w.pres.tick(FRAME)
			local node = w.adapter.node("/Confirm/Center")
			if node == nil then
				if goneAt < 0 then
					goneAt = f
				end
			elseif exitCross < 0 and node.canvasGroupInstance.groupTransparency >= 0.95 then
				exitCross = f
			end
		end
		-- the PACE: 95% dipped out sooner than it was 95% grown in
		t.expect(exitCross > 0 and exitCross < enterCross).toBe(true)
		-- the LIFETIME: the `dismiss` spring ends it, not the flat cap
		t.expect(goneAt > 0 and goneAt < math.ceil(Facet.EXIT_CAP_SECONDS * 60)).toBe(true)
		alert.dispose()
	end)

	--[[ THE TRANSITION IS VALIDATED WHERE IT IS AUTHORED (task 7 item 5). `spec
		.transition` was `any?` with no assert, so an invalid one first met
		`transitions.resolve` inside `presentModal` — and by then the message
		named "Facet transition", never Alert, so nothing pointed at the line
		that was actually wrong. Worse for a BOUND alert (`isPresented`/`item`):
		that `present()` runs inside an observer, outside every pcall the
		control has, so the error surfaced as "the dialog silently never
		opened".

		A bare `"instant"` is the case that makes this more than hygiene — the
		design spec's own §1A sentence invited it ("a caller can override or
		pass `\"instant\"`"), and the schema wants `{ enter = "instant" }`. That
		sentence is fixed too. ]]
	t.it("an invalid transition is refused AT BUILD, by name", function()
		local w = world.new()
		for _, bad in { "instant", 7, { enter = "swirl" }, { enter = "fade", class = 3 } } do
			local ok, err = pcall(function()
				Facet.Controls.Alert(w.core, {
					id = "Bad",
					title = "Hi",
					actions = { { id = "ok", label = "OK" } },
					transition = bad,
				})
			end)
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(err), "Controls.Alert", 1, true) ~= nil).toBe(true)
			t.expect(string.find(tostring(err), "transition", 1, true) ~= nil).toBe(true)
		end
	end)

	t.it("a BOUND alert refuses it at build too, not silently inside its observer", function()
		local w = world.new()
		local isPresented = w.core:signal(false)
		local ok, err = pcall(function()
			Facet.Controls.Alert(w.core, {
				id = "Bound",
				title = "Hi",
				actions = { { id = "ok", label = "OK" } },
				presenter = w.pres,
				isPresented = isPresented,
				transition = "instant",
			})
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "Controls.Alert", 1, true) ~= nil).toBe(true)
		isPresented:dispose()
	end)

	t.it("the message names the shape that WAS meant, so `instant` is one edit away", function()
		local w = world.new()
		local _, err = pcall(function()
			Facet.Controls.Alert(w.core, {
				id = "Bad",
				title = "Hi",
				actions = { { id = "ok", label = "OK" } },
				transition = "instant",
			})
		end)
		t.expect(string.find(tostring(err), 'enter = "instant"', 1, true) ~= nil).toBe(true)
	end)

	t.it("`transition = false` folds to the default instead of being refused (N5)", function()
		--[[ `false` is the framework's own "no transition" spelling on `When`/
			`ForEach`, and `spec.transition or { … }` already folded it to the
			default at the present site — only the BUILD check disagreed, refusing
			the value the very next line was about to ignore. ]]
		local w = world.new()
		local alert = Facet.Controls.Alert(w.core, {
			id = "Falsey",
			title = "Hi",
			actions = { { id = "ok", label = "OK" } },
			transition = false :: any,
		})
		local handle = alert.present(w.pres)
		t.expect(handle.transition.enter).toBe("materialize")
		t.expect(handle.transition.plate).toBe("fades")
		alert.dispose()
	end)

	t.it("a READABLE transition is not judged at build — it is judged on first read (N5, D2)", function()
		--[[ a signal's value at build time is not the value it will carry when
			the alert opens, so refusing on it is a check about the wrong instant;
			it is judged on the first read instead. THE REFUSAL DOES NOT RAISE
			(review D2): it takes the same recorded-and-reset exit as the content
			and dynamic-data failures beside it, because for a BOUND alert this
			read happens inside an observer, where a raise is quarantined. ]]
		local w = world.new()
		local declared = w.core:signal({ enter = "swirl" } :: any)
		local alert = Facet.Controls.Alert(w.core, {
			id = "Late",
			title = "Hi",
			actions = { { id = "ok", label = "OK" } },
			transition = declared :: any,
		})
		-- built clean, and the present RETURNS rather than throwing...
		local ok, opened = pcall(function()
			return alert.present(w.pres)
		end)
		t.expect(ok).toBe(true)
		t.expect(opened).toBeNil()
		-- ...with the reason recorded, by name
		t.expect(alert.dump().presented).toBe(false)
		local recorded = tostring(alert.dump().lastError)
		t.expect(string.find(recorded, "Controls.Alert: transition:", 1, true) ~= nil).toBe(true)
		t.expect(string.find(recorded, "swirl", 1, true) ~= nil).toBe(true)
		-- ...and a corrected value opens it, so the control is not wedged
		declared:set({ enter = "fade" } :: any)
		t.expect(alert.present(w.pres) ~= nil).toBe(true)
		t.expect(alert.dump().presented).toBe(true)
		alert.dispose()
		declared:dispose()
	end)

	t.it("a BOUND alert records the refusal and resets its binding (D2)", function()
		--[[ the shape that made this more than tidiness: `isPresented` drives the
			present from inside an OBSERVER, outside every pcall this control has,
			so a raise there is quarantined — `isPresented` stayed true while
			`dump().presented` said false and `lastError` said nothing. The dialog
			"silently never opened", which is the exact failure task 7 item 5
			existed to remove. ]]
		local w = world.new()
		local declared = w.core:signal({ enter = "swirl" } :: any)
		local isPresented = w.core:signal(false)
		local alert = Facet.Controls.Alert(w.core, {
			id = "BoundBad",
			title = "Hi",
			actions = { { id = "ok", label = "OK" } },
			presenter = w.pres,
			isPresented = isPresented,
			transition = declared :: any,
		})
		isPresented:set(true)
		t.expect(alert.dump().presented).toBe(false)
		-- the binding is RESET, so the flag and the screen agree again
		t.expect(isPresented:get()).toBe(false)
		local recorded = tostring(alert.dump().lastError)
		t.expect(string.find(recorded, "Controls.Alert: transition:", 1, true) ~= nil).toBe(true)
		-- ...and the same binding opens once the value is valid
		declared:set({ enter = "fade" } :: any)
		isPresented:set(true)
		t.expect(alert.dump().presented).toBe(true)
		alert.dispose()
		isPresented:dispose()
		declared:dispose()
	end)

	t.it("the refusal reads as one sentence, not a splice (N5)", function()
		local w = world.new()
		local _, err = pcall(function()
			Facet.Controls.Alert(w.core, {
				id = "Splice",
				title = "Hi",
				actions = { { id = "ok", label = "OK" } },
				transition = { enter = "swirl" },
			})
		end)
		-- `resolve`'s own detail begins lower-case ("unknown enter form …"), so
		-- the address needs its colon or the two run together
		t.expect(string.find(tostring(err), "Controls.Alert: transition: unknown enter form", 1, true) ~= nil)
			.toBe(true)
	end)

	t.it("a VALID transition still builds, and the default (absent) one is untouched", function()
		local w = world.new()
		local a = Facet.Controls.Alert(w.core, {
			id = "Ok1",
			title = "Hi",
			actions = { { id = "ok", label = "OK" } },
			transition = { enter = "instant" },
		})
		a.dispose()
		local b = Facet.Controls.Alert(w.core, {
			id = "Ok2",
			title = "Hi",
			actions = { { id = "ok", label = "OK" } },
		})
		b.dispose()
	end)

	--[[ THE CARD IS A PLATE THAT HAPPENS TO SCROLL (task 7 item 6, pre-existing).
		The modal card is a `UI.ScrollView` — it has to be, so a long message on a
		short screen is reachable — carrying `surface = "raised"`. But
		`chrome_slots.classify` answers by CLASS before it reads the surface, and
		`ScrollView` maps to `scrollbar`, so under every skinned package the card
		classified as a scroll TRACK: no carved frame, no hairline, no shadow, no
		contentInsets. A `decorationHint` of `panel` is the channel for exactly
		this — "a control that declares its own slot knows something the generic
		surface/class map cannot infer" (classify's own header), and the hint wins
		over both rules.

		Classified off the node the ADAPTER was handed, not off the blueprint
		(`anchored_surface.spec`'s own oracle and its reason): a hint that never
		left the tree would make this pass on nothing. ]]
	t.it("the modal card classifies as a PANEL, not as a scroll track", function()
		local chrome_slots = require("../src/tokens/chrome_slots")
		local w = world.new()
		local alert = Facet.Controls.Alert(w.core, {
			id = "Slot",
			title = "Delete?",
			actions = { { id = "ok", label = "OK" } },
		})
		alert.present(w.pres)
		w.pres.refresh()
		local card = w.adapter.node("/Slot/Center/Card")
		t.expect(card ~= nil).toBe(true)
		t.expect(card.class).toBe("ScrollView") -- it really is the scrolling card
		t.expect(card.props.surface).toBe("raised")
		local hint = card.decorationHint
		local slot = chrome_slots.classify({
			class = card.class,
			surface = card.props.surface,
			hint = if type(hint) == "table" then hint.slot else nil,
		})
		t.expect(`the alert card classifies into slot {tostring(slot)}`)
			.toBe("the alert card classifies into slot panel")
		-- ...and the CLASS rule is unchanged for an unhinted ScrollView, which is
		-- what keeps this a hint rather than a weakening of the map
		t.expect(chrome_slots.classify({ class = "ScrollView", surface = "raised" })).toBe("scrollbar")
		alert.dispose()
	end)

	--[[ A1 (owner report 2026-09-13): "the alert's text pops after it opens".
		MEASURED LIVE: Roblox rasterizes text at `floor(TextSize x effectiveScale)`,
		so the ratified 0.96 materialize paints 20px type at 19 for the WHOLE flight
		(TextBounds 127.5x19 at 0.96 AND at 0.9999999) and snaps to 133.5x20 when the
		scale reaches exactly 1 — which the channel only reaches when the spring
		settles, a quarter of a second after the card stopped moving.

		So the modal settles DOWN from just above 1: the written scale never enters
		(0, 1), the type floors to the same pixel on every frame of the enter, and
		the text lands at its final rect on the first painted frame. The oracle is
		the ENGINE-SIDE number — the scale instance the channel materializes — not
		the spec, because the spec is what was wrong about this before. ]]
	t.it("the modal's enter never rasterizes its text a pixel small", function()
		local w = world.new()
		local alert = Facet.Controls.Alert(w.core, {
			id = "Settle",
			title = "Replace this save?",
			message = "Your current progress will replace the previous checkpoint.",
			actions = { { id = "Cancel", label = "Keep previous", role = "cancel" }, { id = "Go", label = "Replace" } },
		})
		local handle = alert.present(w.pres)
		w.pres.refresh()
		local function scaleNow(): number
			local node = w.adapter.node("/Settle/Center")
			return if node ~= nil and node.motionScaleInstance ~= nil then node.motionScaleInstance.scale else 1
		end
		local lowest, moved = math.huge, false
		for _ = 1, 120 do
			local s = scaleNow()
			lowest = math.min(lowest, s)
			if s ~= 1 then
				moved = true
			end
			w.settle(1)
		end
		-- it really is a materialize (something scaled), and it NEVER dipped below 1
		t.expect(moved).toBe(true)
		t.expect(lowest >= 1).toBe(true)
		-- ...and it comes to rest exactly at 1, where the engine floors the type to
		-- the size it was measured at
		t.expect(scaleNow()).toBe(1)
		w.pres.dismiss(handle)
		alert.dispose()
	end)

	--[[ AN AUTHORED MATERIALIZE GETS THE TEXT-SAFE BAND TOO (RED-TEAM F8). `scale`
		answers an ENGINE fact about the type on this card, not a taste this control
		holds, so it is true of every alert — a caller who names the form to change
		its motion class was not asking for their title to re-flow. A caller who
		names a band of their own keeps it, exactly as they keep their own `plate`. ]]
	t.it("an authored materialize is merged with the band, and an authored band wins", function()
		-- the ENGINE-side number, as A1's own case reads it: the scale the channel
		-- materializes on the first frame of the enter IS the band that was resolved
		local function bandOf(declared: any): number
			local w = world.new()
			local alert = Facet.Controls.Alert(w.core, {
				id = "Band",
				title = "Hi",
				actions = { { id = "ok", label = "OK" } },
				transition = declared,
			})
			local handle = alert.present(w.pres)
			w.pres.refresh()
			local node = w.adapter.node("/Band/Center")
			local scale = if node ~= nil and node.motionScaleInstance ~= nil then node.motionScaleInstance.scale else 1
			w.pres.dismiss(handle)
			alert.dispose()
			return scale
		end
		t.expect(bandOf({ enter = "materialize", class = "decay" })).toBeCloseTo(1.015, 1e-6)
		-- their own number survives
		t.expect(bandOf({ enter = "materialize", scale = 0.9 })).toBeCloseTo(0.9, 1e-6)
		-- ...and a form that does not scale writes no scale at all
		t.expect(bandOf({ enter = "slide-up" })).toBe(1)
	end)

	t.it("transition = 'instant' opts out", function()
		local w = world.new()
		local alert = Facet.Controls.Alert(w.core, {
			id = "Quick",
			title = "Hi",
			actions = { { id = "ok", label = "OK" } },
			transition = { enter = "instant" },
		})
		local handle = alert.present(w.pres)
		t.expect(w.adapter.node("/Quick/Center").canvasGroupInstance.groupTransparency).toBe(0)
		w.pres.dismiss(handle)
		alert.dispose()
	end)
end)

--[[ A3 (owner report 2026-09-13): "the red alert icon is overblown — I don't
	think we need the giant alert icon", and its addendum: with the giant icon
	gone, CENTRE the title. The mark used to be `targetSizes.minimum` — 44 px,
	the HIT floor — beside a 20 px heading, so it was more than twice the height
	of the line it qualifies and read as the card's subject rather than as its
	punctuation. ]]
t.describe("Alert header: a mark is punctuation, and the title is centred", function()
	local function open(spec: any, opts: any?)
		local w = world.new(opts or { viewport = { x = 0, y = 0, w = 1280, h = 800 } })
		local alert = Facet.Controls.Alert(w.core, spec)
		alert.present(w.pres)
		w.settle(4)
		return w, alert
	end

	--[[ …AND "TYPE-HEIGHT" HAS TO MEAN IT UNDER A PACKAGE THAT PITCHES ITS PICTURE
		LADDER HIGH (RED-TEAM F4). `iconSizes.medium` is 32 against a 22 px heading
		under Fantasy Ornate and 32 against 20 under Pixel Quest, so the default this
		round is named for came back 1.5x the title it qualifies. The heading is the
		ceiling; a package finer than its own type keeps its number. ]]
	for _, pkgName in { "fantasy_ornate", "pixel_quest", "glossy_touch", "compact_pointer" } do
		t.it(`{pkgName}: the mark never stands taller than the heading it leads`, function()
			local snapshot = require("../src/themes/snapshot")
			local metrics = snapshot.resolve((require)(`../examples/themes/{pkgName}`).build(Facet.themes), nil, {})
			local w, alert = open({
				id = "Mark",
				title = "Replace this save?",
				severity = "critical",
				actions = { { id = "ok", label = "OK" } },
			}, { viewport = { x = 0, y = 0, w = 1280, h = 800 }, themeMetrics = metrics })
			local caution = w.adapter.node("/Mark/Center/Card/Header/Caution").rect
			t.expect(`{pkgName}: mark {caution.h} <= heading {metrics.type.heading.size}`)
				.toBe(
					`{pkgName}: mark {math.min(caution.h, metrics.type.heading.size)} <= heading {metrics.type.heading.size}`
				)
			-- ...and it is still the ladder's own number wherever that fits
			t.expect(caution.h).toBe(math.min(metrics.iconSizes.medium, metrics.type.heading.size))
			alert.dispose()
		end)
	end

	t.it("the critical mark is one type-height glyph, not a whole hit target", function()
		local w, alert = open({
			id = "Mark",
			title = "Replace this save?",
			severity = "critical",
			actions = { { id = "ok", label = "OK" } },
		})
		local metrics = w.env:get("themeMetrics"):get()
		local caution = w.adapter.node("/Mark/Center/Card/Header/Caution").rect
		t.expect(`{caution.w}x{caution.h}`).toBe(`{metrics.iconSizes.medium}x{metrics.iconSizes.medium}`)
		-- ...and that really is the height of the heading it leads, not a hit floor
		t.expect(caution.h).toBe(metrics.type.heading.size)
		t.expect(caution.h < metrics.targetSizes.minimum).toBe(true)
		alert.dispose()
	end)

	t.it("with no mark, the title's box is centred in the card", function()
		local w, alert = open({
			id = "Plain",
			title = "Start this race?",
			message = "Your selected driver is ready.",
			actions = { { id = "ok", label = "OK" } },
		})
		local card = w.adapter.node("/Plain/Center/Card").rect
		local title = w.adapter.node("/Plain/Center/Card/Header/Title").rect
		local message = w.adapter.node("/Plain/Center/Card/Message").rect
		t.expect(math.abs((title.x + title.w / 2) - (card.x + card.w / 2)) <= 1).toBe(true)
		t.expect(math.abs((message.x + message.w / 2) - (card.x + card.w / 2)) <= 1).toBe(true)
		-- a lone title centres its own glyphs inside that box
		t.expect(w.adapter.node("/Plain/Center/Card/Header/Title").props.textAlign).toBe("center")
		alert.dispose()
	end)

	--[[ AN UNMARKED TITLE HAS TO HUG TOO (RED-TEAM F12). `fill` answers "whatever I
		am given", and the card's own width is a HUG — so a lone long title reported
		the width of its longest word and the card collapsed around a single 60 px
		line. Hugging, it asks for the line it wants, the card grows to its cap, and
		the line wraps inside it. ]]
	--[[ A BLANK TITLE IS NO TITLE (NEW-5). A hugging Text asks for the width of what
		it draws and whitespace draws nothing, so `" "` mounted a visible node 0 px
		wide — which the containment guard reports, correctly. Folded with `""`: no
		glyphs, no node. ]]
	t.it("a whitespace-only title mounts no title node at all", function()
		for _, blank in { " ", "", "   \t " } do
			local w, alert = open({
				id = "Blank",
				title = blank,
				message = "Your selected driver is ready.",
				actions = { { id = "ok", label = "OK" } },
			}, { viewport = { x = 0, y = 0, w = 390, h = 844 } })
			t.expect(w.adapter.node("/Blank/Center/Card/Header/Title")).toBe(nil)
			-- ...and the card is still a card: the message and the action are there
			t.expect(w.adapter.node("/Blank/Center/Card/Message") ~= nil).toBe(true)
			t.expect(w.core:lastError()).toBe(nil)
			alert.dispose()
		end
		-- a title with any glyph at all still mounts
		local w, alert = open({
			id = "Kept",
			title = " Start ",
			actions = { { id = "ok", label = "OK" } },
		}, { viewport = { x = 0, y = 0, w = 390, h = 844 } })
		t.expect(w.adapter.node("/Kept/Center/Card/Header/Title") ~= nil).toBe(true)
		alert.dispose()
	end)

	t.it("a long unmarked title wraps inside a full-width card instead of collapsing it", function()
		local LONG = "Are you absolutely certain you want to replace this saved checkpoint now"
		t.expect(#LONG >= 67).toBe(true)
		local w, alert = open({
			id = "Long",
			title = LONG,
			actions = { { id = "ok", label = "OK" } },
		}, { viewport = { x = 0, y = 0, w = 390, h = 844 } })
		local card = w.adapter.node("/Long/Center/Card").rect
		local title = w.adapter.node("/Long/Center/Card/Header/Title").rect
		t.expect(`card {card.w} >= 300`).toBe(`card {math.max(card.w, 300)} >= 300`)
		-- ...and the title really did WRAP: two heading lines or more
		local heading = w.env:get("themeMetrics"):get().type.heading
		t.expect(`title lines {title.h >= heading.size * 2}`).toBe("title lines true")
		alert.dispose()
	end)

	t.it("with a mark, the pair is centred as a unit and the title reads from the mark", function()
		local w, alert = open({
			id = "Pair",
			title = "Replace this save?",
			severity = "critical",
			actions = { { id = "ok", label = "OK" } },
		})
		local header = w.adapter.node("/Pair/Center/Card/Header").rect
		local mark = w.adapter.node("/Pair/Center/Card/Header/Caution").rect
		local title = w.adapter.node("/Pair/Center/Card/Header/Title").rect
		-- the mark LEADS: it sits before the title, and they touch across one gap
		t.expect(mark.x + mark.w <= title.x).toBe(true)
		-- ...and the pair, not the title, is what the row centres
		local lead = mark.x - header.x
		local trail = (header.x + header.w) - (title.x + title.w)
		t.expect(math.abs(lead - trail) <= 1).toBe(true)
		local card = w.adapter.node("/Pair/Center/Card").rect
		local pairMid = (mark.x + (title.x + title.w)) / 2
		t.expect(math.abs(pairMid - (card.x + card.w / 2)) <= 1).toBe(true)
		alert.dispose()
	end)
end)

--[[ A4 (owner report 2026-09-13): "portrait with plenty of space — the alert
	scrolls instead of growing". Under a carved package the card showed a scrollbar
	on a phone with 800 px of room behind it. Two causes, both about a box that
	cannot reproduce its own measurement:

	  1. the card HUGGED its width, so its children were measured against the
	     parent's inner width and then arranged in the narrower box the hug landed
	     on — every string re-wrapped taller than the height that was hugged to;
	  2. the scroll CANVAS carries a trailing chrome-bleed allowance
	     (`render/commit_walks.luau`: a package's shadow paints outside the last
	     child's rect, so the canvas grows by `chromeBleed` to make it reachable)
	     and the content-sized measure counted only the LEADING one — so a hugging
	     scroller under any package with a shadow overflowed its own box by exactly
	     that allowance, forever.

	The oracle is the canvas against the host: a card that fits has a canvas no
	taller than the window it is drawn in. ]]
t.describe("Alert card: it grows to fit, and scrolls only when it cannot", function()
	local parchment = require("../examples/themes/fantasy_parchment") :: any
	local snapshot = require("../src/themes/snapshot")

	local function openWith(opts: any, spec: any)
		local o = opts
		o.newAdapter = function()
			local a = fake.new()
			a.scrollBarThickness = fake.SCROLL_BAR_THICKNESS
			return a
		end
		local w = world.new(o)
		local alert = Facet.Controls.Alert(w.core, spec)
		alert.present(w.pres)
		w.settle(5)
		return w, alert
	end

	local CONFIRM = {
		id = "Fit",
		title = "Replace this save?",
		severity = "critical",
		message = "Your current progress will replace the previous checkpoint.",
		actions = {
			{ id = "Cancel", label = "Keep previous", role = "cancel" },
			{ id = "Replace", label = "Replace save", role = "destructive" },
		},
	}

	for _, pkg in { "fantasy_parchment", "fantasy_ornate", "scifi_hud", "glossy_touch" } do
		t.it(`a phone with room does not scroll the card under {pkg}`, function()
			local w, alert = openWith({
				viewport = { x = 0, y = 0, w = 390, h = 844 },
				themeMetrics = snapshot.resolve((require)(`../examples/themes/{pkg}`).build(Facet.themes), nil, {}),
			}, CONFIRM)
			local card = w.adapter.node("/Fit/Center/Card")
			t.expect(`{pkg}: canvas {card.scrollRegion.contentH} <= host {card.rect.h}`)
				.toBe(`{pkg}: canvas {math.min(card.scrollRegion.contentH, card.rect.h)} <= host {card.rect.h}`)
			-- ...and the room really was there: the card is nowhere near the screen
			t.expect(card.rect.h < 812).toBe(true)
			alert.dispose()
		end)
	end

	t.it("...and it still scrolls when the screen genuinely has no room", function()
		local w, alert = openWith({
			viewport = { x = 0, y = 0, w = 640, h = 320 },
			themeMetrics = snapshot.resolve(parchment.build(Facet.themes), nil, {}),
			overflowGuardOff = "a deliberately over-long message is the point",
		}, {
			id = "Fit",
			title = "Review changes",
			message = string.rep("Check your selected equipment before continuing. ", 40),
			actions = { { id = "Cancel", label = "Cancel", role = "cancel" }, { id = "Go", label = "Continue" } },
		})
		local card = w.adapter.node("/Fit/Center/Card")
		t.expect(card.scrollRegion.contentH > card.rect.h).toBe(true)
		alert.dispose()
	end)
end)

--[[ A5 (owner ruling 2026-09-13): "a modal's action label must never be cut."
	Under a carved theme at the Largest preference on a 390 px phone, an alert's
	one-word primary action ellipsized and the only route to the whole string was
	`disclose` — a long press that also fires the button on release, which is the
	wrong affordance for a confirm. Three levers, in the order the ruling puts
	them:

	  1. the card YIELDS its own padding to the carved frame instead of stacking
	     with it, and stops reserving a chrome-bleed lane its own frame already
	     provides — 288 px of content on that phone becomes 322;
	  2. the row/stack decision MEASURES the labels against the width the row
	     actually has, so a pair that cannot share a line stacks full width;
	  3. `disclose` stays underneath both as the last resort it was meant to be.
]]
t.describe("Alert actions: the label fits before anything is cut", function()
	local lt = require("./lib/large_text")
	local snapshot = require("../src/themes/snapshot")

	local function packageOf(name: string): any
		return snapshot.resolve((require)(`../examples/themes/{name}`).build(Facet.themes), nil, {})
	end

	-- the LT-8 Alert fixture's own shape (tests/lib/large_text_fixtures.luau):
	-- a pseudo-localized cancel that CAN wrap, and a one-word primary that cannot
	local function mount(themeName: string, offset: number, viewport: any, input: string?)
		local w = lt.world({
			offset = offset,
			theme = { id = themeName, metrics = if themeName == "facet-neutral" then nil else packageOf(themeName) },
			input = input or "touch",
			viewport = viewport,
		})
		local alert = Facet.Controls.Alert(w.core, {
			id = "Ctl",
			title = lt.PSEUDO,
			message = lt.GERMAN_COMPOUND,
			actions = {
				{ id = "Cancel", label = lt.PSEUDO_ACTION, role = "cancel" },
				{ id = "Accept", label = "Continue", shortcut = "defaultAction" },
			},
		})
		w.present(UI.Screen({ id = "S", children = { alert.blueprint } }))
		return w, alert
	end

	local function truncatedActions(w: any): { string }
		local out: { string } = {}
		for path, entry in lt.sweep(w).rects do
			local facts = if type(entry) == "table" then entry.textFacts else nil
			if type(facts) == "table" and facts.truncated == true and string.find(path, "/Actions/", 1, true) then
				table.insert(out, path)
			end
		end
		table.sort(out)
		return out
	end

	for _, themeName in { "fantasy_parchment", "glossy_touch" } do
		t.it(`{themeName}: at the Largest preference on a 390 phone no action label is cut`, function()
			local w, alert = mount(themeName, lt.LARGEST, lt.PHONE_PORTRAIT)
			t.expect(`{themeName}: cut {table.concat(truncatedActions(w), ",")}`).toBe(`{themeName}: cut `)
			-- ...and they are stacked, full width, which is what gave them the room
			local a = w.adapter.node("/S/Ctl/Center/Card/Actions/Order/[Accept]/Accept").rect
			local c = w.adapter.node("/S/Ctl/Center/Card/Actions/Order/[Cancel]/Cancel").rect
			t.expect(a.y + a.h <= c.y).toBe(true)
			t.expect(a.x).toBe(c.x)
			t.expect(a.w).toBe(c.w)
			alert.dispose()
		end)
	end

	--[[ …AND THE LANE IS ONLY REDUNDANT WHERE A FRAME IS CARVED (RED-TEAM F3).
		Sci-Fi HUD reserves a 24 px glow and carves nothing; Glossy Mobile reserves
		17 and carves nothing. Dropping the chrome lane on those cuts the very glow
		it exists for, so the opt-out is gated on the carve and they keep theirs. ]]
	for _, case in
		{
			{ name = "scifi_hud", carved = false },
			{ name = "glossy_mobile", carved = false },
			{ name = "fantasy_parchment", carved = true },
			{ name = "glossy_touch", carved = true },
		}
	do
		t.it(`{case.name}: the bleed lane is kept exactly when the frame is not carved`, function()
			local w, alert = mount(case.name, 0, lt.PHONE_PORTRAIT)
			local metrics = w.metrics()
			local carved = metrics.chromeInsets.panel.left
			local bleed = metrics.chromeBleed
			t.expect(`{case.name}: carved>0 {carved > 0}`).toBe(`{case.name}: carved>0 {case.carved}`)
			local card = w.adapter.node("/S/Ctl/Center/Card").rect
			local actions = w.adapter.node("/S/Ctl/Center/Card/Actions").rect
			local spent = actions.x - card.x
			if case.carved then
				-- the carve plus the `xs` floor, and nothing more: the double-count
				-- AND the redundant lane are both gone
				t.expect(`{case.name}: spent {spent}`).toBe(`{case.name}: spent {carved + metrics.space.xs}`)
				t.expect(`{case.name}: under {spent < carved + metrics.space.m}`).toBe(`{case.name}: under true`)
			else
				--[[ nothing carved, so the glow has nowhere else to live: the lane the
					package asked for is still there. The reserve is a `max` against the
					authored step, so the number is `max(m, bleed)` — and THAT is what
					decides whether this arm can catch a removed lane (NEW-3):

					  scifi_hud      m  4, bleed 24 -> 24, and 4 with no lane: CATCHES
					  glossy_mobile  m 18, bleed 17 -> 18, and 18 with no lane: CANNOT

					Glossy Mobile's own padding is already wider than its glow reaches,
					so no assertion about its spend can distinguish a kept lane from a
					dropped one. It is swept anyway, as the negative control for the
					GATE — it is the package whose carve is zero, and the point of its
					arm is that the carve-gated branch does not fire on it. Sci-Fi HUD
					is the arm that fails when the lane goes (verified: `spent 14 to be
					spent 24`). ]]
				local authored = metrics.space.m
				t.expect(`{case.name}: spent {spent}`).toBe(`{case.name}: spent {math.max(authored, bleed)}`)
				t.expect(`{case.name}: lane {spent >= bleed}`).toBe(`{case.name}: lane true`)
				t.expect(`{case.name}: carve {carved}`).toBe(`{case.name}: carve 0`)
			end
			alert.dispose()
		end)
	end

	--[[ …AND THE LANE IS DECIDED PER SOLVE, NOT AT CONSTRUCTION (NEW-1, 2026-09-13).
		The first cut of the gate read the metrics once, in `card()`, which runs
		ONCE on the static path — so an alert built under Facet Neutral and then
		shown under Fantasy Parchment spent 35 px a side (the double-count A5
		removed), and one built under Parchment and shown under Sci-Fi HUD cut the
		24 px glow. The showcase reaches both by "open the Alert demo, then pick the
		theme". The decision now lives at the layout-time reader
		(`chrome_slots.bleedLane`, read by `render/layout_node.luau` on every solve
		and by the canvas beside it), and the control declares nothing. ]]
	t.it("a theme swapped under a LIVE alert moves its lane with it", function()
		local snapshot = require("../src/themes/snapshot")
		local w = world.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		local alert = Facet.Controls.Alert(w.core, {
			id = "Swap",
			title = "Replace this save?",
			message = "Your current progress will replace the previous checkpoint.",
			actions = {
				{ id = "Cancel", label = "Keep previous", role = "cancel" },
				{ id = "Replace", label = "Replace save", role = "destructive" },
			},
		})
		alert.present(w.pres)
		w.settle(3)
		local function spent(): number
			local card = w.adapter.node("/Swap/Center/Card").rect
			return w.adapter.node("/Swap/Center/Card/Actions").rect.x - card.x
		end
		local function swap(name: string): any
			local metrics = snapshot.resolve((require)(`../examples/themes/{name}`).build(Facet.themes), nil, {})
			w.env:set("themeMetrics", metrics)
			w.settle(3)
			return metrics
		end
		-- built under Neutral (no carve, no bleed) and then shown carved: the card
		-- spends the carve plus its `xs` floor, and NOT the lane on top of it
		local parchment = swap("fantasy_parchment")
		t.expect(spent()).toBe(parchment.chromeInsets.panel.left + parchment.space.xs)
		-- ...and swapped again to a package that glows WITHOUT carving, the lane is
		-- there: nothing else is holding that glow off the clip edge
		local scifi = swap("scifi_hud")
		t.expect(`scifi spent {spent()} >= bleed {scifi.chromeBleed}`)
			.toBe(`scifi spent {math.max(spent(), scifi.chromeBleed)} >= bleed {scifi.chromeBleed}`)
		-- the canvas agrees with the box on both, which is what keeps a card that
		-- fits from scrolling forever
		local card = w.adapter.node("/Swap/Center/Card")
		t.expect(card.scrollRegion.contentH <= card.rect.h).toBe(true)
		alert.dispose()
	end)

	t.it("the card's padding yields to the carved frame instead of stacking with it", function()
		local w, alert = mount("fantasy_parchment", lt.LARGEST, lt.PHONE_PORTRAIT)
		local card = w.adapter.node("/S/Ctl/Center/Card").rect
		local actions = w.adapter.node("/S/Ctl/Center/Card/Actions").rect
		local metrics = w.metrics()
		local carved = metrics.chromeInsets.panel
		--[[ the frame the package carves, plus ONE `xs` and nothing else: the
			authored "m" is spent only where the art does not already cover it, and
			never all the way to nothing — a carved inset is where the ART ends, not
			where a line of type wants to start (live capture, 2026-09-13: spending
			exactly it put the message flush against Parchment's painted border). ]]
		local floor = metrics.space.xs
		t.expect(actions.x - card.x).toBe(carved.left + floor)
		t.expect((card.x + card.w) - (actions.x + actions.w)).toBe(carved.right + floor)
		-- ...and that really is a yield: the authored step is NOT added on top
		t.expect(carved.left + floor < carved.left + metrics.space.m).toBe(true)
		alert.dispose()
	end)

	t.it("at the default preference on a desktop the row form is unchanged", function()
		local w, alert = mount("facet-neutral", 0, { x = 0, y = 0, w = 1280, h = 800 }, "desktop")
		local a = w.adapter.node("/S/Ctl/Center/Card/Actions/Order/[Accept]/Accept").rect
		local c = w.adapter.node("/S/Ctl/Center/Card/Actions/Order/[Cancel]/Cancel").rect
		-- one row, cancel leading, nothing cut
		t.expect(a.y).toBe(c.y)
		t.expect(c.x + c.w <= a.x).toBe(true)
		t.expect(truncatedActions(w)).toEqual({})
		alert.dispose()
	end)

	--[[ A BROKEN `themeMetrics` FACT MUST NOT QUARANTINE THE CONTROL (RED-TEAM F2).
		The fact is whatever an adapter or a fixture pushed — §8.2's rule is that a
		broken one never leaks past the seam that read it — and the measured rung
		reads it twice: for the label's own font descriptor and for the row's gap.
		Both used to raise on a partial table, which quarantines the memo, records
		`lastError`, and leaves a screen that rendered clean before this round
		showing nothing. Only reachable on a regular-width NEAR display, because
		every other rung short-circuits the measurement. ]]
	t.it("a partial themeMetrics fact degrades the rung instead of quarantining it", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 1280, h = 800 }, themeMetrics = {} })
		local alert = Facet.Controls.Alert(w.core, {
			id = "Broken",
			title = "Start this race?",
			message = "Your selected driver is ready.",
			actions = { { id = "Cancel", label = "Cancel", role = "cancel" }, { id = "Go", label = "Start" } },
		})
		alert.present(w.pres)
		w.settle(3)
		t.expect(w.core:lastError()).toBe(nil)
		t.expect(alert.dump().lastError).toBe(nil)
		t.expect(alert.dump().presented).toBe(true)
		t.expect(w.adapter.node("/Broken/Center/Card") ~= nil).toBe(true)
		alert.dispose()

		--[[ …AND IT DEGRADES TOWARD THE FORM THAT CANNOT CUT (NEW-2). Reporting a
			label of NO width was the first fallback and it is the wrong direction: a
			label that always fits picks the ROW, which is the one form of the two
			that can put a button outside the card — measured here at 331 px of
			overflow before the direction was corrected. An unmeasurable label is
			charged as "does not fit", so the degraded answer is a STACK, which is
			full width by construction and cannot overflow the box it stacks in. ]]
		local wide = world.new({ viewport = { x = 0, y = 0, w = 1280, h = 800 }, themeMetrics = {} })
		local long = Facet.Controls.Alert(wide.core, {
			id = "Long",
			title = "Start this race?",
			actions = {
				{ id = "Cancel", label = "Keep the previous checkpoint", role = "cancel" },
				{ id = "Go", label = "Permanently delete this saved progress" },
			},
		})
		long.present(wide.pres)
		wide.settle(3)
		local card = wide.adapter.node("/Long/Center/Card").rect
		local a = wide.adapter.node("/Long/Center/Card/Actions/Order/[Go]/Go").rect
		local c = wide.adapter.node("/Long/Center/Card/Actions/Order/[Cancel]/Cancel").rect
		t.expect(`form {if a.y == c.y then "row" else "stack"}`).toBe("form stack")
		local overflow = math.max(0, (a.x + a.w) - (card.x + card.w), card.x - a.x)
		t.expect(`overflow {overflow}`).toBe("overflow 0")
		t.expect(wide.core:lastError()).toBe(nil)
		long.dispose()
	end)

	--[[ AN ACTION THAT CARRIES A COMPACT LABEL IS STILL CHARGED FOR THE ONE THE ROW
		WILL DRAW (RED-TEAM F11, measured and declined — see the rung's own comment).
		The compact ladder swaps the short string in when the offer is NARROWER than
		the natural width, and an alert's row is a stack of HUGGING buttons that is
		never offered less than it asks for. Charged the compact width, this very
		case kept the row and then drew the full label 12 px outside the card. The
		claim here is therefore containment, not the form: the card holds what it
		lays out, with or without a compact form on the action. ]]
	t.it("the rung charges the label the row will actually draw, and the card holds it", function()
		local LONG = "Permanently delete this saved progress"
		local function probe(compact: string?): (string, number)
			local w = lt.world({
				offset = 0,
				theme = { id = "facet-neutral" },
				input = "desktop",
				viewport = { x = 0, y = 0, w = 1280, h = 800 },
			})
			local alert = Facet.Controls.Alert(w.core, {
				id = "Ctl",
				title = "Delete this save?",
				actions = {
					{ id = "Cancel", label = "Cancel", role = "cancel" },
					{ id = "Go", label = LONG, compactLabel = compact },
				},
			})
			w.present(UI.Screen({ id = "S", children = { alert.blueprint } }))
			local card = w.adapter.node("/S/Ctl/Center/Card").rect
			local a = w.adapter.node("/S/Ctl/Center/Card/Actions/Order/[Go]/Go").rect
			local c = w.adapter.node("/S/Ctl/Center/Card/Actions/Order/[Cancel]/Cancel").rect
			local overflow = math.max(0, (a.x + a.w) - (card.x + card.w), card.x - a.x)
			alert.dispose()
			return (if a.y == c.y then "row" else "stack"), overflow
		end
		local plainForm, plainOverflow = probe(nil)
		local compactForm, compactOverflow = probe("Delete")
		-- the long label cannot share a row either way, and neither arrangement puts
		-- a button outside the card that holds it
		t.expect(plainForm).toBe("stack")
		t.expect(compactForm).toBe("stack")
		t.expect(`plain {plainOverflow} compact {compactOverflow}`).toBe("plain 0 compact 0")
	end)

	--[[ the PURE half, so a caller can predict the form from numbers it already
		holds — and so the rule is checkable without mounting anything ]]
	t.it("rowFits is the measured rung, and it is exported", function()
		local policy = require("../src/controls/alert")
		t.expect(policy.rowFits({ 100, 100 }, 24, 16, 264)).toBe(true)
		t.expect(policy.rowFits({ 100, 100 }, 24, 16, 263)).toBe(false)
		t.expect(policy.rowFits({}, 24, 16, 0)).toBe(true)
	end)
end)
