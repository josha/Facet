--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/harness_world")
local Compose = require("../src/vendor/compose/core")
t.describe("Searchable selection", function()
	t.it("named and sparse options are refused for static and live sources", function()
		local w = world.new()
		for _, list in
			{
				{ named = { id = "a", label = "Alpine" } },
				{ [1] = { id = "a", label = "Alpine" }, [3] = { id = "b", label = "Beach" } },
			}
		do
			for _, live in { false, true } do
				local ok = pcall(harness.Controls.PopupButton, w.core, {
					value = Compose.cell("a"),
					options = if live then Compose.cell(list) else list,
					presentation = "menu",
				})
				t.expect(ok).toBe(false)
			end
		end
	end)
	t.it("keyed live descriptions can appear and disappear without replacing the row", function()
		local w = world.new()
		local options = Compose.cell({ { id = "a", label = "Alpine" } })
		local control = harness.Controls.PopupButton(w.core, {
			id = "P",
			value = Compose.cell("a"),
			options = options,
			presentation = "menu",
		})
		w.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
		control.api.open()
		w.pres.refresh()
		local rowPath
		for _, path in w.adapter.paths() do
			if string.sub(path, -6) == "/Opt-a" then
				rowPath = path
			end
		end
		assert(rowPath, "live option must mount its row")
		local row = w.adapter.node(rowPath)
		local initialHeight = row.rect.h
		w.pres.focus.focusOn(rowPath)
		local function descriptionNode()
			for _, path in w.adapter.paths() do
				if string.sub(path, 1, #rowPath + 1) == rowPath .. "/" and string.sub(path, -12) == "/Description" then
					return w.adapter.node(path)
				end
			end
			return nil
		end
		t.expect(descriptionNode()).toBeNil()
		for _, description in { "Added", "", "Returned" } do
			options:set({ { id = "a", label = "Alpine", description = description } })
			w.pres.refresh()
			t.expect(w.adapter.node(rowPath)).toBe(row)
			t.expect(w.pres.focus.focused:peek()).toBe(rowPath)
			local node = descriptionNode()
			if description == "" then
				t.expect(node).toBeNil()
				t.expect(row.rect.h).toBe(initialHeight)
			else
				assert(node, "nonempty live description must mount")
				t.expect(node.props.text).toBe(description)
			end
		end
		options:set({ { id = "a", label = "Alpine" } })
		w.pres.refresh()
		t.expect(w.adapter.node(rowPath)).toBe(row)
		t.expect(w.pres.focus.focused:peek()).toBe(rowPath)
		t.expect(descriptionNode()).toBeNil()
		t.expect(row.rect.h).toBe(initialHeight)
		control.dispose()
		w.pres.dismiss(w.handle)
	end)
	t.it("dismissing the parent closes its anchored popup before control disposal", function()
		local w = world.new()
		local control = harness.Controls.PopupButton(w.core, {
			id = "P",
			value = Compose.cell("a"),
			options = Compose.cell({ { id = "a", label = "Alpine" } }),
			presentation = "menu",
		})
		w.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
		control.api.open()
		w.pres.refresh()
		t.expect(w.pres.anchoredSurfaces().count).toBe(1)
		w.pres.dismiss(w.handle)
		t.expect(control.dump().open).toBe(false)
		t.expect(w.pres.anchoredSurfaces().count).toBe(0)
		w.pres.refresh()
		t.expect(w.pres.anchoredSurfaces().count).toBe(0)
		control.dispose()
	end)
	t.it("malformed supplied options fail construction before mounting", function()
		local core = harness.newCore()
		Facet.newEnvironment(core)
		for _, option in
			{
				{ id = "a", label = "" },
				{ id = "a", label = "A", description = false },
				{ divider = "yes" },
				{ divider = true, label = "Not an option" },
			}
		do
			local ok = pcall(harness.Controls.PopupButton, core, { value = Compose.cell("a"), options = { option } })
			t.expect(ok).toBe(false)
		end
	end)

	t.it("query and live option replacements preserve selection while multi selection persists", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local core, env = w.core, w.env
		local options = Compose.cell({ { id = "a", label = "Alpine" }, { id = "b", label = "Beach", enabled = false } })
		local query = Compose.cell("")
		local selected = Compose.cell({ a = true })
		local control = harness.Controls.PopupButton(
			core,
			{ id = "P", options = options, query = query, selectedValues = selected, presentation = "menu" }
		)
		local target = w.adapter
		local pres = w.pres
		pres.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		target.tap("/S/P/Trigger")
		pres.refresh()
		t.expect(pres.anchoredSurfaces().count).toBe(1)
		query:set("missing")
		pres.refresh()
		t.expect(control.dump().resultCount).toBe(0)
		t.expect(selected:peek().a).toBe(true)
		control.api.select("b")
		t.expect(selected:peek().b).toBe(nil)
		options:set({ { id = "a", label = "Alpine pass" }, { id = "b", label = "Beach" } })
		query:set("")
		pres.refresh()
		control.api.select("b")
		pres.refresh()
		t.expect(selected:peek().b).toBe(true)
		t.expect(control.dump().open).toBe(true)
		options:set({ { id = "b", label = "Coast" } })
		pres.refresh()
		t.expect(selected:peek().a).toBe(true)
		t.expect(string.find(control.dump().selectedLabel, "Coast", 1, true) ~= nil).toBe(true)
		control.dispose()
		t.expect(pres.anchoredSurfaces().count).toBe(0)
		control.api.select("b")
		t.expect(selected:peek().b).toBe(true)
		pres.dismiss()
	end)
end)
