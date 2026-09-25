--!strict
local t = require("./lib/testkit")
local nativeApp = require("../bench/native_app")
t.describe("native text preference updates", function()
	t.it("keeps editing focus row identity and scroll position across text and theme changes", function()
		local world = nativeApp()
		local Compose, Host, T = world.Compose, world.Host, world.types
		local text, size = Compose.cell("Initial"), Compose.cell(16)
		local package = Compose.cell(world.Facet.themes.neutralPackage())
		local UI = world.Facet.controls(world.runtime, { types = T, theme = package })
		local field, list, button
		local records = {}
		for index = 1, 100 do
			records[index] = { id = index, label = tostring(index) }
		end
		world.runtime.mount(function()
			local sheet = world.Facet.themes.createStyleSheet(world.runtime, package, { types = T })
			field = UI.TextInput({ value = text, TextSize = size })
			button = UI.Button({ label = "Save", TextSize = size })
			list = UI.VirtualList({
				from = records,
				key = function(row)
					return row.id
				end,
				itemSize = 56,
				render = function(current)
					return UI.Text({
						text = function(use)
							return use(current).label
						end,
						TextSize = size,
					})
				end,
			})
			return Host.ScreenGui({ sheet, Host.StyleLink({ StyleSheet = Compose.static(sheet) }), field, button, list })
		end, world.target)
		list.AbsoluteWindowSize = T.Vector2.new(320, 400)
		list.CanvasPosition = T.Vector2.new(0, 137)
		field:CaptureFocus()
		field.Text = "Typed and uncommitted"
		local nodes = world.target:GetDescendants()
		for _, value in { 28, 40, 16 } do
			size:set(value)
			t.expect(field:IsFocused()).toBe(true)
			t.expect(field.TextSize).toBe(value)
			t.expect(button.TextSize).toBe(value)
			t.expect(field.Text).toBe("Typed and uncommitted")
			t.expect(text:peek()).toBe("Typed and uncommitted")
			t.expect(list.CanvasPosition.Y).toBe(137)
			local current = world.target:GetDescendants()
			t.expect(#current).toBe(#nodes)
			for index, node in nodes do
				t.expect(current[index]).toBe(node)
			end
		end
		local updated = world.Facet.themes.neutralPackage()
		updated.metrics.controlSizes.regular.height = 48
		package:set(updated)
		t.expect(field:IsFocused()).toBe(true)
		t.expect(field.Text).toBe("Typed and uncommitted")
		t.expect(list.CanvasPosition.Y).toBe(137)
		world.dispose()
	end)
end)
