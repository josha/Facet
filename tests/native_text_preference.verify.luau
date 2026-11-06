--!strict
local FixtureRoblox = require("../tools/vendor/verify/src/roblox")
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local Theme = require("../src/ui/theme_types")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
	type Use = <T>(ReadOnlyValue<T>) -> T
	type Record = { id: number, label: string }

	local nativeApp = require("../bench/native_app")
	verifyHarness:suite("native text preference updates", function()
		verifyHarness:case("keeps size tokens live through preference and compiled theme changes", {
			id = "native_text_preference::native text preference updates::keeps size tokens live through preference and compiled theme changes",
			run = function()
				local engine = require("./lib/native_engine").new()
				local Compose = Facet.Compose
				local runtime = Facet.Roblox.createRuntime(engine)
				local preference = Compose.cell("Medium")
				Facet.controls(runtime, { types = engine.types, environment = { preferredTextSize = preference } })
				local authored = Facet.themes.neutralPackage()
				authored.rules = { { selector = ".size-probe", properties = { TextSize = 14.5 } } }
				local first = assert((Facet.themes.define(authored)))
				local retuned = Facet.themes.neutralPackage()
				retuned.metrics.typography.body.size = 22
				retuned.metrics.controls.typography.preferredSizeStep = 4
				retuned.rules = { { selector = ".size-probe", properties = { TextSize = 19.5 } } }
				local second = assert((Facet.themes.define(retuned)))
				local warm = runtime.mount(function()
					return Facet.themes.createStyleSheet(runtime, second, { types = engine.types })
				end, engine.new("Folder"))
				warm()
				local source = Compose.cell(first)
				local stop, result = runtime.mount(function()
					return Facet.themes.createStyleSheet(runtime, source, { types = engine.types })
				end, engine.new("Folder"))
				local sheet = result :: StyleSheet
				local properties = require("./lib/style_properties")
				local function sizeFor(selector: string): number
					for _, child in sheet:GetChildren() do
						local rule = child :: StyleRule
						if rule.Selector == selector then
							return properties(rule).TextSize :: number
						end
					end
					error("missing size rule " .. selector)
				end
				local ruleWrites = 0
				local sizes: { [string]: number } = {}
				for _, child in sheet:GetChildren() do
					local rule = child :: StyleRule
					local value = rule:GetProperties().TextSize
					if type(value) == "string" then
						local token = string.sub(value, 2)
						sizes[token] = sheet:GetAttribute(token) :: number
					end
					local methods = (rule :: unknown) :: {
						SetProperties: (StyleRule, Theme.RuleProperties) -> (),
					}
					local set = methods.SetProperties
					methods.SetProperties = function(self, nextProperties)
						ruleWrites += 1
						set(self, nextProperties)
					end
				end
				local writes: { string } = {}
				local observer = engine.environment.observe(function(event)
					if event.operation == "setAttribute" then
						Verify.expect(event.object):toBe(sheet)
						table.insert(writes, assert(event.member))
					else
						error("text preference changed " .. event.operation)
					end
				end)
				preference:set("Largest")
				observer:Disconnect()
				local expected = 0
				for token, base in sizes do
					expected += 1
					Verify.expect(sheet:GetAttribute(token)):toBe(base + 6)
				end
				Verify.expect(#writes):toBe(expected)
				Verify.expect(ruleWrites):toBe(0)
				Verify.expect(sizeFor(".size-probe")):toBe(20.5)
				source:set(second)
				Verify.expect(sizeFor(".facet-type-body")):toBe(34)
				Verify.expect(sizeFor(".size-probe")):toBe(31.5)
				ruleWrites = 0
				preference:set("Medium")
				Verify.expect(ruleWrites):toBe(0)
				Verify.expect(sizeFor(".facet-type-body")):toBe(22)
				Verify.expect(sizeFor(".size-probe")):toBe(19.5)
				source:set(first)
				Verify.expect(sizeFor(".facet-type-body")):toBe(first.metrics.typography.body.size)
				Verify.expect(sizeFor(".size-probe")):toBe(14.5)
				stop()
				runtime:dispose()
			end,
		})
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
