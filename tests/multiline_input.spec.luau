--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/world")
t.describe("Native multiline input contract", function()
	for _, presentation in { "plain", "search", "number" } do
		t.it(presentation .. " keeps its frame outside the focused native editor", function()
			local ornate = require("../examples/themes/fantasy_ornate").build(Facet.themes)
			local w = world.new({ themeMetrics = Facet.themes.resolve(ornate) })
			local enabled = w.core:signal(true)
			local c = Facet.Controls.TextInput(w.core, {
				id = "Editor",
				value = w.core:signal("3"),
				presentation = presentation,
				enabled = enabled,
				numericValue = if presentation == "number" then w.core:signal(3) else nil,
			})
			w.present(Facet.UI.Screen({ id = "S", children = { c.blueprint } }))
			local path = "/S/Editor" .. (if presentation == "number" then "/Input" else "")
			local frame = w.adapter.node(path)
			local field = w.adapter.node(path .. "/Field")
			w.adapter.tap(path .. "/Field")
			w.pres.refresh()
			t.expect(c.dump().editing).toBe(true)
			t.expect(w.adapter.node(path)).toBe(frame)
			t.expect(frame.decorationHint.slot).toBe("field")
			t.expect(frame.props.editing).toBe(nil)
			t.expect(field.props.surface).toBe("plain")
			t.expect(field.rect.h >= field.props.textSize).toBe(true)
			enabled:set(false)
			w.pres.refresh()
			enabled:set(true)
			w.pres.refresh()
			w.adapter.tap(path .. "/Field")
			w.pres.refresh()
			t.expect(c.dump().disabled).toBe(false)
			t.expect(c.dump().editing).toBe(true)
		end)
	end

	t.it("a short ornate editor fills its viewport without a shadow scroll tail", function()
		local ornate = require("../examples/themes/fantasy_ornate").build(Facet.themes)
		local w = world.new({ themeMetrics = Facet.themes.resolve(ornate) })
		local c = Facet.Controls.TextInput(w.core, { id = "Editor", value = w.core:signal("Notes"), multiline = true })
		w.present(Facet.UI.Screen({ id = "S", children = { c.blueprint } }))
		local viewport = w.adapter.node("/S/Editor/Viewport")
		local field = w.adapter.node("/S/Editor/Viewport/Field")
		t.expect(field.rect.y).toBe(viewport.rect.y)
		t.expect(field.rect.h).toBe(viewport.rect.h)
		t.expect(viewport.scrollRegion.contentH).toBe(viewport.rect.h)
		t.expect(field.props.surface).toBe("plain")
	end)

	t.it("a caller's fixed field height gives back unaffordable border insets", function()
		local ornate = require("../examples/themes/fantasy_ornate").build(Facet.themes)
		local w = world.new({ themeMetrics = Facet.themes.resolve(ornate) })
		local field = Facet.Controls.TextInput(
			w.core,
			{ id = "Fixed", value = w.core:signal("Write"), height = { type = "fixed", px = 44 } }
		)
		w.present(Facet.UI.Screen({ id = "S", children = { field.blueprint } }))
		local node = w.adapter.node("/S/Fixed/Field")
		t.expect(w.adapter.node("/S/Fixed").rect.h).toBe(44)
		t.expect(node.rect.h >= node.props.textSize).toBe(true)
		t.expect(node.props.surface).toBe("plain")
	end)

	t.it("the multiline frame stays outside the scrolling native editor while editing", function()
		local w = world.new()
		local editor =
			Facet.Controls.TextInput(w.core, { id = "Editor", value = w.core:signal("Notes"), multiline = true })
		w.present(Facet.UI.Screen({ id = "S", children = { editor.blueprint } }))
		local frame = w.adapter.node("/S/Editor")
		local field = w.adapter.node("/S/Editor/Viewport/Field")
		t.expect(frame.decorationHint.slot).toBe("field")
		t.expect(field.decorationHint.slot).toBe("none")
		w.adapter.tap("/S/Editor/Viewport/Field")
		w.pres.refresh()
		t.expect(editor.dump().editing).toBe(true)
		t.expect(w.adapter.node("/S/Editor")).toBe(frame)
		t.expect(frame.props.editing).toBe(nil)
		t.expect(field.rect.h >= w.adapter.node("/S/Editor/Viewport").rect.h).toBe(true)
	end)
	t.it("native fields receive the same border padding reserved by the themed layout", function()
		local ornate = require("../examples/themes/fantasy_ornate").build(Facet.themes)
		local w = world.new({ themeMetrics = Facet.themes.resolve(ornate) })
		local editor =
			Facet.Controls.TextInput(w.core, { id = "Editor", value = w.core:signal("Write"), multiline = true })
		local search =
			Facet.Controls.TextInput(w.core, { id = "Search", value = w.core:signal(""), presentation = "search" })
		w.present(Facet.UI.Screen({ id = "S", children = { editor.blueprint, search.blueprint } }))
		for _, path in { "/S/Editor/Viewport/Field", "/S/Search/Field" } do
			local padding = w.adapter.node(path).props.padding
			local isEditor = string.find(path, "/Viewport/", 1, true) ~= nil
			if isEditor then
				t.expect(padding).toBe(12)
			else
				local node = w.adapter.node(path)
				local frame = w.adapter.node("/S/Search")
				t.expect(node.rect.x - frame.rect.x + padding.left >= 24).toBe(true)
			end
		end
		local field = w.adapter.node("/S/Editor/Viewport/Field")
		t.expect(field.props.textFont.lineHeight).toBe(1.35)
		t.expect(field.props.textSize).toBe(17)
		w.env:set("themeMetrics", require("../src/themes/snapshot").neutral())
		w.pres.refresh()
		t.expect(w.adapter.node("/S/Editor/Viewport/Field")).toBe(field)
		t.expect(field.props.padding).toBe(12)
		t.expect(field.props.text).toBe("Write")
		t.expect(field.props.textFont.lineHeight).toBe(1.2)
		t.expect(field.props.textSize).toBe(18)
	end)
	t.it("a landscape keyboard shrinks the multiline viewport without replacing the native editor", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 750, h = 362 } })
		local core, env = w.core, w.env
		env:set("coreSafeInsets", { top = 58, bottom = 0, left = 0, right = 0 })
		local value = core:signal("First line\nSecond line")
		local control = Facet.Controls.TextInput(core, { id = "Editor", value = value, multiline = true })
		local adapter = w.adapter
		local pres = w.pres
		local handle = pres.present(Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.ScrollView({
					id = "Page",
					width = Facet.UI.fill(),
					height = Facet.UI.fill(),
					children = { Facet.UI.Box({ height = { type = "fixed", px = 260 } }), control.blueprint },
				}),
			},
		}))
		pres.refresh()
		local field = adapter.node("/S/Page/Editor/Viewport/Field")
		adapter.tap("/S/Page/Editor/Viewport/Field")
		env:set("keyboardOcclusionRect", { x = 0, y = 159, w = 874, h = 181 })
		pres.refresh()
		t.expect(adapter.node("/S/Page/Editor").rect.h <= 93).toBe(true)
		t.expect(adapter.node("/S/Page/Editor/Viewport/Field")).toBe(field)
		t.expect(value:get()).toBe("First line\nSecond line")
		t.expect(control.dump().editing).toBe(true)
		local page = handle.controller.screenRectOf("/S/Page")
		local editorRect = handle.controller.screenRectOf("/S/Page/Editor")
		t.expect(editorRect.y >= page.y).toBe(true)
		t.expect(editorRect.y + editorRect.h <= math.min(page.y + page.h, 151)).toBe(true)
		t.expect(handle.controller.scrollPosition("/S/Page").y > 0).toBe(true)
	end)
	t.it("multiline forwards to the adapter and preserves newlines until explicit submit", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local core, env = w.core, w.env
		local value = core:signal("")
		local commits = 0
		local control = Facet.Controls.TextInput(core, {
			id = "Editor",
			value = value,
			multiline = true,
			height = { type = "fixed", px = 180 },
			onCommit = function()
				commits += 1
			end,
		})
		local adapter = w.adapter
		local pres = w.pres
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		t.expect(adapter.node("/S/Editor/Viewport/Field").props.multiline).toBe(true)
		adapter.tap("/S/Editor/Viewport/Field")
		adapter.pasteText("/S/Editor/Viewport/Field", "first\nsecond")
		pres.refresh()
		t.expect(value:get()).toBe("first\nsecond")
		t.expect(control.dump().editing).toBe(true)
		t.expect(commits).toBe(0)
		control.api.submit()
		t.expect(commits).toBe(1)
		t.expect(control.dump().editing).toBe(false)
		pres.dismiss(handle)
		control.dispose()
	end)
	t.it("long multiline text has a native scroll viewport and a content-sized editor", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 600 } })
		local core, env = w.core, w.env
		local control = Facet.Controls.TextInput(
			core,
			{ id = "Editor", value = core:signal(string.rep("A line of notes.\n", 30)), multiline = true }
		)
		local adapter = w.adapter
		local pres = w.pres
		pres.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		t.expect(adapter.node("/S/Editor/Viewport").class).toBe("ScrollView")
		local field = adapter.node("/S/Editor/Viewport/Field")
		t.expect(field.rect.h > adapter.node("/S/Editor").rect.h).toBe(true)
	end)
	t.it("native edits grow a wide viewport for hard breaks and a final empty line", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 1600, h = 1000 } })
		local value = w.core:signal("Lap")
		local control = Facet.Controls.TextInput(w.core, { id = "Editor", value = value, multiline = true })
		w.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }))
		local path = "/S/Editor/Viewport/Field"
		w.adapter.tap(path)
		w.adapter.pasteText(path, string.rep("\nLap", 20))
		w.pres.refresh()
		local field = w.adapter.node(path)
		local height = field.rect.h
		t.expect(height > w.adapter.node("/S/Editor/Viewport").rect.h).toBe(true)
		w.adapter.pasteText(path, "\n")
		w.pres.refresh()
		t.expect(w.adapter.node(path)).toBe(field)
		t.expect(field.rect.h > height).toBe(true)
		t.expect(w.adapter.node("/S/Editor/Viewport").scrollRegion.contentH).toBe(field.rect.h)
		t.expect(control.dump().editing).toBe(true)
	end)
	t.it("native caret geometry reveals its line through the existing scroll authority", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 1200, h = 1000 } })
		local c = Facet.Controls.TextInput(w.core, {
			id = "Editor",
			value = w.core:signal(string.rep("Lap\n", 30)),
			multiline = true,
		})
		w.present(Facet.UI.Screen({ id = "S", children = { c.blueprint } }))
		local path = "/S/Editor/Viewport/Field"
		local field = w.adapter.node(path)
		local viewport = w.adapter.node("/S/Editor/Viewport")
		w.adapter.tap(path)
		field.textHandlers.onCaretRect({ x = 0, y = field.rect.h - 24, w = 1, h = 24 })
		local bottom = w.controller.scrollPosition("/S/Editor/Viewport").y
		t.expect(bottom).toBe(field.rect.h - viewport.rect.h)
		field.textHandlers.onCaretRect({ x = 0, y = 12, w = 1, h = 24 })
		t.expect(w.controller.scrollPosition("/S/Editor/Viewport").y).toBe(12)
		t.expect(w.adapter.node(path)).toBe(field)
		t.expect(c.dump().editing).toBe(true)
	end)
end)
