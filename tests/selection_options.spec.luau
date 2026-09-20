--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/harness_world")
local themePackage = require("../src/themes/package")
local Compose = require("../src/vendor/compose/core")
local observeChange = require("../src/core/on_change")

local function nodeWithSuffix(w, suffix)
	for _, path in w.adapter.paths() do
		if string.sub(path, -#suffix) == suffix then
			return w.adapter.node(path)
		end
	end
	return nil
end
local function painted(w, suffix)
	local node = nodeWithSuffix(w, suffix)
	return if node then node.props.text else nil
end

t.describe("Selection options", function()
	t.it("live segmented sizing and textSize change in place", function()
		local w = world.new()
		local sizing, textSize = Compose.cell("fill"), Compose.cell("caption")
		local control = harness.Controls.Picker(w.core, {
			id = "R",
			presentation = "segmented",
			sizing = sizing,
			textSize = textSize,
			selected = Compose.cell("a"),
			options = Compose.cell({ { value = "a", label = "Route" } }),
		})
		w.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
		local before = w.adapter.node("/S/R/Options/Rows/[a]/Option-a")
		local width = w.controller.rectOf("/S/R").w
		local size = nodeWithSuffix(w, "/Label").props.textSize
		sizing:set("hug")
		textSize:set("body")
		w.pres.refresh()
		t.expect(w.controller.rectOf("/S/R").w < width).toBe(true)
		t.expect(nodeWithSuffix(w, "/Label").props.textSize > size).toBe(true)
		t.expect(w.adapter.node("/S/R/Options/Rows/[a]/Option-a")).toBe(before)
		w.pres.dismiss(w.handle)
		control.dispose()
	end)

	t.it("live iconOnly renders the glyph and refuses incompatible radio or absent icons", function()
		local w = world.new()
		local options = Compose.cell({ { value = "a", label = "Route", icon = "checkmark" } })
		local control = harness.Controls.Picker(w.core, {
			id = "R",
			presentation = "segmented",
			iconOnly = true,
			options = options,
			selected = Compose.cell("a"),
		})
		w.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
		t.expect(painted(w, "/Icon")).toBe(themePackage.iconGlyph("checkmark"))
		t.expect(nodeWithSuffix(w, "/Label")).toBeNil()
		for _, spec in
			{
				{ presentation = "radio", options = options },
				{ presentation = "segmented", options = Compose.cell({ { value = "a", label = "Route" } }) },
			}
		do
			spec.iconOnly = true
			spec.selected = Compose.cell("a")
			local ok = pcall(function()
				harness.Controls.Picker(w.core, spec)
			end)
			t.expect(ok).toBe(false)
		end
		w.pres.dismiss(w.handle)
		control.dispose()
	end)
	t.it("live selection and its onChange redirect publish one final owner value", function()
		local w = world.new()
		local selected = Compose.cell("a")
		local observations = 0
		local off = observeChange(w.core.owner, selected, function()
			observations += 1
		end)
		local control = harness.Controls.Picker(w.core, {
			id = "R",
			presentation = "radio",
			selected = selected,
			options = Compose.cell({ { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } }),
			onChange = function()
				selected:set("a")
			end,
		})
		w.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
		w.adapter.tap("/S/R/Options/Rows/[b]/Option-b")
		t.expect(selected:peek()).toBe("a")
		t.expect(observations).toBe(0)
		w.pres.dismiss(w.handle)
		control.dispose()
		off()
	end)
	t.it("live radio metadata replacements preserve the row and clear absent descriptions", function()
		local w = world.new()
		local options = Compose.cell({ { id = "one", value = "a", label = "Alpha", icon = "checkmark", badge = 3 } })
		local control = harness.Controls.Picker(w.core, {
			id = "R",
			presentation = "radio",
			options = options,
			selected = Compose.cell("a"),
		})
		w.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
		local row = w.adapter.node("/S/R/Options/Rows/[one]/Option-one")
		local focused = w.pres.focus.focused:peek()
		t.expect(control.dump().axis).toBe("y")
		t.expect(nodeWithSuffix(w, "/Description")).toBeNil()
		-- the count is a node INSIDE the seal (2026-09-12; badge_centering.spec)
		t.expect(painted(w, "/Badge/Count")).toBe("3")
		options:set({
			{ id = "one", value = "a", label = "Alpine", description = "A mountain route", icon = "close", badge = 7 },
		})
		w.pres.refresh()
		t.expect(w.adapter.node("/S/R/Options/Rows/[one]/Option-one")).toBe(row)
		t.expect(w.pres.focus.focused:peek()).toBe(focused)
		t.expect(painted(w, "/Label")).toBe("Alpine")
		t.expect(painted(w, "/Description")).toBe("A mountain route")
		t.expect(painted(w, "/Icon")).toBe(themePackage.iconGlyph("close"))
		t.expect(painted(w, "/Badge/Count")).toBe("7")
		options:set({ { id = "one", value = "a", label = "Alpine" } })
		w.pres.refresh()
		t.expect(nodeWithSuffix(w, "/Description")).toBeNil()
		t.expect(w.pres.focus.focused:peek()).toBe(focused)
		t.expect(painted(w, "/Badge/Count")).toBe("")
		t.expect(painted(w, "/Icon")).toBeNil()
		t.expect(w.adapter.node("/S/R/Options/Rows/[one]/Option-one")).toBe(row)
		w.pres.dismiss(w.handle)
		control.dispose()
	end)

	for _, live in { false, true } do
		t.it(`{if live then "live" else "static"} Picker refuses malformed option and callback contracts`, function()
			local core = harness.newCore()
			for _, list in
				{
					{ named = { value = "a", label = "Alpha" } },
					{ [1] = { value = "a", label = "Alpha" }, [3] = { value = "b", label = "Beta" } },
					{ { value = "a", label = "Alpha" }, { value = "a", label = "Again" } },
				}
			do
				local ok = pcall(function()
					harness.Controls.Picker(core, {
						presentation = "radio",
						options = if live then Compose.cell(list) else list,
						selected = Compose.cell("a"),
					})
				end)
				t.expect(ok).toBe(false)
			end
			for _, invalid in
				{
					{ label = "" },
					{ description = false },
					{ enabled = "false" },
					{ badge = {} },
					{ icon = false },
					{ misspelled = true },
				}
			do
				local option = { value = "a", label = "Alpha" }
				for key, value in invalid do
					option[key] = value
				end
				local list = { option }
				local ok = pcall(function()
					harness.Controls.Picker(core, {
						presentation = "radio",
						options = if live then Compose.cell(list) else list,
						selected = Compose.cell("a"),
					})
				end)
				t.expect(ok).toBe(false)
			end
			for _, invalid in { { required = "false" }, { onChanging = true }, { enabled = "false" } } do
				local list = { { value = "a", label = "Alpha" } }
				local spec = {
					presentation = "radio",
					options = if live then Compose.cell(list) else list,
					selected = Compose.cell("a"),
				}
				for key, value in invalid do
					spec[key] = value
				end
				local ok = pcall(function()
					harness.Controls.Picker(core, spec)
				end)
				t.expect(ok).toBe(false)
			end
		end)

		t.it(`{if live then "live" else "static"} Picker does not commit when its veto callback disables it`, function()
			local w = world.new()
			local enabled = Compose.cell(true)
			local ancestorEnabled = Compose.cell(false)
			local selected = Compose.cell("a")
			local changes, vetoes = 0, 0
			local list = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } }
			local control = harness.Controls.Picker(w.core, {
				id = "R",
				presentation = "radio",
				options = if live then Compose.cell(list) else list,
				selected = selected,
				enabled = enabled,
				onChanging = function()
					vetoes += 1
					enabled:set(false)
					return true
				end,
				onChange = function()
					changes += 1
				end,
			})
			w.present(harness.UI.Screen({ id = "S", enabled = ancestorEnabled, children = { control.blueprint } }))
			local path = if live then "/S/R/Options/Rows/[b]/Option-b" else "/S/R/Options/Opt2"
			w.adapter.tap(path)
			t.expect(vetoes).toBe(0)
			ancestorEnabled:set(true)
			w.pres.refresh()
			w.adapter.tap(path)
			t.expect(vetoes).toBe(1)
			t.expect(selected:peek()).toBe("a")
			t.expect(changes).toBe(0)
			enabled:set(true)
			w.pres.refresh()
			control.dispose()
			w.adapter.tap(path)
			t.expect(vetoes).toBe(1)
			w.pres.dismiss(w.handle)
		end)
	end
	t.it("radio selection remains exclusive and skips disabled options without rewriting owner state", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
		local core, env = w.core, w.env
		local selected = Compose.cell("a")
		local enabled = Compose.cell(false)
		local control = harness.Controls.Picker(core, {
			id = "R",
			presentation = "radio",
			selected = selected,
			options = {
				{ value = "a", label = "Open" },
				{ value = "b", label = "Club", description = "Requires club membership", enabled = enabled },
			},
		})
		local adapter = w.adapter
		local pres = w.pres
		pres.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		adapter.tap("/S/R/Options/Opt2")
		t.expect(selected:peek()).toBe("a")
		enabled:set(true)
		pres.refresh()
		adapter.tap("/S/R/Options/Opt2")
		t.expect(selected:peek()).toBe("b")
		enabled:set(false)
		pres.refresh()
		t.expect(selected:peek()).toBe("b")
		t.expect(adapter.node("/S/R/Options/Opt2").props.selected).toBe(true)
	end)
	t.it("live radio rows retain stable focus through replacement and preserve missing selected values", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
		local core, env = w.core, w.env
		local options = Compose.cell({
			{ id = "one", value = "a", label = "Alpine" },
			{ id = "two", value = "b", label = "Beach" },
		})
		local selected = Compose.cell("a")
		local control =
			harness.Controls.Picker(core, { id = "R", presentation = "radio", options = options, selected = selected })
		local target = w.adapter
		local pres = w.pres
		pres.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		local before = pres.focus.focused:peek()
		options:set({ { id = "one", value = "a", label = "Alpine pass" }, { id = "two", value = "c", label = "Coast" } })
		pres.refresh()
		t.expect(pres.focus.focused:peek()).toBe(before)
		t.expect(selected:peek()).toBe("a")
		options:set({ { id = "two", value = "c", label = "Coast" } })
		pres.refresh()
		t.expect(selected:peek()).toBe("a")
		local focused = pres.focus.focused:peek()
		target.tap(focused)
		t.expect(selected:peek()).toBe("c")
		control.dispose()
	end)
end)
