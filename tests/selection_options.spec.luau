--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/world")
local themePackage = require("../src/themes/package")

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
		local sizing, textSize = w.core:signal("fill"), w.core:signal("caption")
		local control = Facet.Controls.Picker(w.core, {
			id = "R",
			presentation = "segmented",
			sizing = sizing,
			textSize = textSize,
			selected = w.core:signal("a"),
			options = w.core:signal({ { value = "a", label = "Route" } }),
		})
		w.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }))
		local before = w.adapter.node("/S/R/Options/Rows/[a]/Option")
		local width = w.controller.rectOf("/S/R").w
		local size = nodeWithSuffix(w, "/Label").props.textSize
		sizing:set("hug")
		textSize:set("body")
		w.pres.refresh()
		t.expect(w.controller.rectOf("/S/R").w < width).toBe(true)
		t.expect(nodeWithSuffix(w, "/Label").props.textSize > size).toBe(true)
		t.expect(w.adapter.node("/S/R/Options/Rows/[a]/Option")).toBe(before)
		w.pres.dismiss(w.handle)
		control.dispose()
	end)

	t.it("live iconOnly renders the glyph and refuses incompatible radio or absent icons", function()
		local w = world.new()
		local options = w.core:signal({ { value = "a", label = "Route", icon = "checkmark" } })
		local control = Facet.Controls.Picker(w.core, {
			id = "R",
			presentation = "segmented",
			iconOnly = true,
			options = options,
			selected = w.core:signal("a"),
		})
		w.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }))
		t.expect(painted(w, "/Icon")).toBe(themePackage.iconGlyph("checkmark"))
		t.expect(nodeWithSuffix(w, "/Label")).toBeNil()
		for _, spec in
			{
				{ presentation = "radio", options = options },
				{ presentation = "segmented", options = w.core:signal({ { value = "a", label = "Route" } }) },
			}
		do
			spec.iconOnly = true
			spec.selected = w.core:signal("a")
			local ok = pcall(function()
				Facet.Controls.Picker(w.core, spec)
			end)
			t.expect(ok).toBe(false)
		end
		w.pres.dismiss(w.handle)
		control.dispose()
	end)
	t.it("live selection and its onChange redirect publish one final owner value", function()
		local w = world.new()
		local selected = w.core:signal("a")
		local observations = 0
		local off = w.core:observe(selected, function()
			observations += 1
		end)
		local control = Facet.Controls.Picker(w.core, {
			id = "R",
			presentation = "radio",
			selected = selected,
			options = w.core:signal({ { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } }),
			onChange = function()
				selected:set("a")
			end,
		})
		w.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }))
		w.adapter.tap("/S/R/Options/Rows/[b]/Option")
		t.expect(selected:get()).toBe("a")
		t.expect(observations).toBe(0)
		w.pres.dismiss(w.handle)
		control.dispose()
		off()
	end)
	t.it("live radio metadata replacements preserve the row and clear absent descriptions", function()
		local w = world.new()
		local options = w.core:signal({ { id = "one", value = "a", label = "Alpha", icon = "checkmark", badge = 3 } })
		local control = Facet.Controls.Picker(w.core, {
			id = "R",
			presentation = "radio",
			options = options,
			selected = w.core:signal("a"),
		})
		w.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }))
		local row = w.adapter.node("/S/R/Options/Rows/[one]/Option")
		local focused = w.pres.focus.focused:get()
		t.expect(control.dump().axis).toBe("y")
		t.expect(nodeWithSuffix(w, "/Description")).toBeNil()
		t.expect(painted(w, "/Badge")).toBe("3")
		options:set({
			{ id = "one", value = "a", label = "Alpine", description = "A mountain route", icon = "close", badge = 7 },
		})
		w.pres.refresh()
		t.expect(w.adapter.node("/S/R/Options/Rows/[one]/Option")).toBe(row)
		t.expect(w.pres.focus.focused:get()).toBe(focused)
		t.expect(painted(w, "/Label")).toBe("Alpine")
		t.expect(painted(w, "/Description")).toBe("A mountain route")
		t.expect(painted(w, "/Icon")).toBe(themePackage.iconGlyph("close"))
		t.expect(painted(w, "/Badge")).toBe("7")
		options:set({ { id = "one", value = "a", label = "Alpine" } })
		w.pres.refresh()
		t.expect(nodeWithSuffix(w, "/Description")).toBeNil()
		t.expect(w.pres.focus.focused:get()).toBe(focused)
		t.expect(painted(w, "/Badge")).toBe("")
		t.expect(painted(w, "/Icon")).toBeNil()
		t.expect(w.adapter.node("/S/R/Options/Rows/[one]/Option")).toBe(row)
		w.pres.dismiss(w.handle)
		control.dispose()
	end)

	for _, live in { false, true } do
		t.it(`{if live then "live" else "static"} Picker refuses malformed option and callback contracts`, function()
			local core = Facet.newCore()
			for _, list in
				{
					{ named = { value = "a", label = "Alpha" } },
					{ [1] = { value = "a", label = "Alpha" }, [3] = { value = "b", label = "Beta" } },
					{ { value = "a", label = "Alpha" }, { value = "a", label = "Again" } },
				}
			do
				local ok = pcall(function()
					Facet.Controls.Picker(core, {
						presentation = "radio",
						options = if live then core:signal(list) else list,
						selected = core:signal("a"),
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
					Facet.Controls.Picker(core, {
						presentation = "radio",
						options = if live then core:signal(list) else list,
						selected = core:signal("a"),
					})
				end)
				t.expect(ok).toBe(false)
			end
			for _, invalid in { { required = "false" }, { onChanging = true }, { enabled = "false" } } do
				local list = { { value = "a", label = "Alpha" } }
				local spec = {
					presentation = "radio",
					options = if live then core:signal(list) else list,
					selected = core:signal("a"),
				}
				for key, value in invalid do
					spec[key] = value
				end
				local ok = pcall(function()
					Facet.Controls.Picker(core, spec)
				end)
				t.expect(ok).toBe(false)
			end
		end)

		t.it(`{if live then "live" else "static"} Picker does not commit when its veto callback disables it`, function()
			local w = world.new()
			local enabled = w.core:signal(true)
			local ancestorEnabled = w.core:signal(false)
			local selected = w.core:signal("a")
			local changes, vetoes = 0, 0
			local list = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } }
			local control = Facet.Controls.Picker(w.core, {
				id = "R",
				presentation = "radio",
				options = if live then w.core:signal(list) else list,
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
			w.present(Facet.UI.Screen({ id = "S", enabled = ancestorEnabled, children = { control.blueprint } }))
			local path = if live then "/S/R/Options/Rows/[b]/Option" else "/S/R/Options/Opt2"
			w.adapter.tap(path)
			t.expect(vetoes).toBe(0)
			ancestorEnabled:set(true)
			w.pres.refresh()
			w.adapter.tap(path)
			t.expect(vetoes).toBe(1)
			t.expect(selected:get()).toBe("a")
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
		local selected = core:signal("a")
		local enabled = core:signal(false)
		local control = Facet.Controls.Picker(core, {
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
		pres.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		adapter.tap("/S/R/Options/Opt2")
		t.expect(selected:get()).toBe("a")
		enabled:set(true)
		pres.refresh()
		adapter.tap("/S/R/Options/Opt2")
		t.expect(selected:get()).toBe("b")
		enabled:set(false)
		pres.refresh()
		t.expect(selected:get()).toBe("b")
		t.expect(adapter.node("/S/R/Options/Opt2").props.selected).toBe(true)
	end)
	t.it("live radio rows retain stable focus through replacement and preserve missing selected values", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
		local core, env = w.core, w.env
		local options =
			core:signal({ { id = "one", value = "a", label = "Alpine" }, { id = "two", value = "b", label = "Beach" } })
		local selected = core:signal("a")
		local control =
			Facet.Controls.Picker(core, { id = "R", presentation = "radio", options = options, selected = selected })
		local target = w.adapter
		local pres = w.pres
		pres.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		local before = pres.focus.focused:get()
		options:set({ { id = "one", value = "a", label = "Alpine pass" }, { id = "two", value = "c", label = "Coast" } })
		pres.refresh()
		t.expect(pres.focus.focused:get()).toBe(before)
		t.expect(selected:get()).toBe("a")
		options:set({ { id = "two", value = "c", label = "Coast" } })
		pres.refresh()
		t.expect(selected:get()).toBe("a")
		local focused = pres.focus.focused:get()
		target.tap(focused)
		t.expect(selected:get()).toBe("c")
		control.dispose()
	end)
end)
