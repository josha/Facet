--!strict
local FixtureRoblox = require("../tools/vendor/verify/src/roblox")
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
	type Use = <T>(ReadOnlyValue<T>) -> T
	type Record = { id: number, label: string }

	local nativeApp = require("../bench/native_app")
	verifyHarness:suite("native text preference updates", function()
		verifyHarness:case("keeps editing focus row identity and scroll position across text and theme changes", {
			id = "native_text_preference::native text preference updates::keeps editing focus row identity and scroll position across text and theme changes",
			run = function()
				local world = nativeApp()
				local Compose: ComposeModule, Host, T = world.Compose, world.Host, world.types
				local text, size = Compose.cell("Initial"), Compose.cell(16)
				local package = Compose.cell(world.Facet.themes.neutralPackage())
				local UI = world.Facet.controls(world.runtime, { types = T, theme = package })
				local field: TextBox, list: ScrollingFrame, button: TextButton
				local records: { Record } = {}
				for index = 1, 100 do
					records[index] = { id = index, label = tostring(index) }
				end
				world.runtime.mount(function()
					local sheet = world.Facet.themes.createStyleSheet(world.runtime, package, { types = T })
					field = UI.TextInput { value = text, TextSize = size } :: TextBox
					button = UI.Button { label = "Save", TextSize = size }
					local spec: Facet.KeyedCollectionSpec<Record, number> = {
						from = records,
						key = function(row)
							return row.id
						end,
						itemSize = 56,
						render = function(current): GuiObject
							return UI.Text {
								text = function(use: Use)
									return use(current).label
								end,
								TextSize = size,
							}
						end,
					}
					list = UI.VirtualList(spec)
					return Host.ScreenGui {
						sheet,
						Host.StyleLink { StyleSheet = Compose.static(sheet) },
						field,
						button,
						list,
					}
				end, world.target)
				world.engine.environment.poke(
					FixtureRoblox.assertInstance(list),
					"AbsoluteWindowSize",
					T.Vector2.new(320, 400)
				)
				list.CanvasPosition = T.Vector2.new(0, 137)
				field:CaptureFocus()
				field.Text = "Typed and uncommitted"
				local nodes = world.target:GetDescendants()
				for _, value in { 28, 40, 16 } do
					size:set(value)
					Verify.expect((field:IsFocused())):toBe(true)
					Verify.expect(field.TextSize):toBe(value)
					Verify.expect(button.TextSize):toBe(value)
					Verify.expect(field.Text):toBe("Typed and uncommitted")
					Verify.expect((text:peek())):toBe("Typed and uncommitted")
					Verify.expect(list.CanvasPosition.Y):toBe(137)
					local current = world.target:GetDescendants()
					Verify.expect(#current):toBe(#nodes)
					for index, node in nodes do
						Verify.expect(current[index]):toBe(node)
					end
				end
				local updated = world.Facet.themes.neutralPackage()
				updated.metrics.controlSizes.regular.height = 48
				package:set(updated)
				Verify.expect((field:IsFocused())):toBe(true)
				Verify.expect(field.Text):toBe("Typed and uncommitted")
				Verify.expect(list.CanvasPosition.Y):toBe(137)
				world.dispose()
			end,
		})
	end)
end
