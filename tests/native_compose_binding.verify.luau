--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
	type Use = <T>(ReadOnlyValue<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")

	local twin = require("./lib/compose_twin")
	local Core = twin.core
	local Roblox = twin.roblox

	local function find(node: any, name: string): any
		for _, child in node:GetChildren() do
			if child.Name == name then
				return child
			end
			local found = find(child, name)
			if found then
				return found
			end
		end
		return nil
	end

	local function failure(body: () -> ()): string
		local ok, err = pcall(function(): boolean
			body()
			return true
		end)
		assert(not ok, "expected an error")
		return tostring(err)
	end

	verifyHarness:suite("Facet on the consumer's Compose instance", function()
		verifyHarness:case("inherits app controls and the 60 pixel Button height", function(context)
			for _, surface in { Facet, Facet.bind(Core, Roblox) } do
				local engine = engineLib.new()
				local runtime: ComposeRuntime = surface.Roblox.createRuntime(engine)
				context:defer(function()
					runtime:dispose()
				end)
				local theme = surface.themes.neutralPackage()
				theme.metrics.controlSizes.regular.height = 60
				local app = surface.app({
					runtime = runtime,
					types = engine.types,
					parent = engine.new("Folder"),
					theme = theme,
					motionLevel = "none",
					guiService = engine.new("GuiService"),
					environment = { preferredTextSize = "Largest" },
				})
				context:defer(app.dispose)
				local function PortableButton(props: Facet.ButtonProps): TextButton
					local UI = surface.controls(runtime)
					Verify.expect(UI):toBe(app.UI)
					Verify.expect(UI.environment().preferredTextSize:peek()):toBe("Largest")
					return UI.Button(props)
				end
				app.mount(function()
					local button = PortableButton({ label = "Continue" })
					local reference = app.UI.Button({ label = "Continue" })
					Verify.expect(button.Size.Y.Offset):toBe(60)
					Verify.expect(button.Size):toBe(reference.Size)
					return app.UI.VStack { button, reference }
				end)
			end
		end)

		verifyHarness:case("inherits app controls in presented content", function(context)
			local engine = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			context:defer(function()
				runtime:dispose()
			end)
			local app = Facet.app({
				runtime = runtime,
				types = engine.types,
				parent = engine.new("Folder"),
				motionLevel = "none",
			})
			context:defer(app.dispose)
			local rendered = 0
			local function PortableContent(): TextButton
				rendered += 1
				local UI = Facet.controls(runtime)
				Verify.expect(UI):toBe(app.UI)
				return UI.Button({ label = "Continue" })
			end
			local close = app.presentAnchored(PortableContent, {
				source = { rect = { x = 100, y = 100, w = 40, h = 40 } },
				modal = false,
			})
			Verify.expect(rendered):toBe(1)
			close()
			local toast = app.presentToast(PortableContent)
			Verify.expect(rendered):toBe(2)
			toast.dismiss()
		end)

		verifyHarness:case("explicit options build fresh controls under a provider", function(context)
			local engine = engineLib.new()
			local runtime: ComposeRuntime = Roblox.createRuntime(engine)
			context:defer(function()
				runtime:dispose()
			end)
			local Bound = Facet.bind(Core, Roblox)
			local theme = Bound.themes.neutralPackage()
			theme.metrics.controlSizes.regular.height = 60
			local UI = Bound.controls(runtime, { types = engine.types, theme = theme })
			runtime.mount(function()
				return UI.provide(function()
					local first = Bound.controls(runtime, { types = engine.types })
					local second = Bound.controls(runtime, { types = engine.types })
					Verify.expect(first == UI):toBe(false)
					Verify.expect(second == first):toBe(false)
					Verify.expect(Bound.controls(runtime)):toBe(UI)
					local button = first.Button({ label = "Standalone" })
					Verify.expect(button.Size.Y.Offset):toBe(44)
					return button
				end)
			end, engine.new("Folder"))
		end)

		verifyHarness:case("no provider and empty options build fresh controls", function(context)
			local engine = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			context:defer(function()
				runtime:dispose()
			end)
			local environment = getfenv(require("../src/ui/context_config"))
			local previous: { [string]: unknown } = {}
			for key, value in engine.types do
				if type(key) == "string" then
					previous[key] = environment[key]
					environment[key] = value
				end
			end
			context:defer(function()
				for key in engine.types do
					if type(key) == "string" then
						environment[key] = previous[key]
					end
				end
			end)
			local first = Facet.controls(runtime)
			Verify.expect(Facet.controls(runtime) == first):toBe(false)
			runtime.mount(function()
				local second = Facet.controls(runtime)
				Verify.expect(second == first):toBe(false)
				return first.provide(function()
					local explicit = Facet.controls(runtime, {})
					Verify.expect(explicit == first):toBe(false)
					Verify.expect(Facet.controls(runtime, {}) == explicit):toBe(false)
					return explicit.Button({ label = "Default" })
				end)
			end, engine.new("Folder"))
			Verify.expect(Facet.controls(runtime) == first):toBe(false)
		end)

		verifyHarness:case("nested providers override controls and retain descendant owners", function(context)
			local engine = engineLib.new()
			local runtime: ComposeRuntime = Roblox.createRuntime(engine)
			context:defer(function()
				runtime:dispose()
			end)
			local Bound = Facet.bind(Core, Roblox)
			local outer = Bound.controls(runtime, { types = engine.types })
			local theme = Bound.themes.neutralPackage()
			theme.metrics.controlSizes.regular.height = 60
			local inner = Bound.controls(runtime, { types = engine.types, theme = theme })
			local shown = Core.cell(false)
			local renders, cleanups = 0, 0
			local stop = runtime.mount(function()
				return outer.provide(function()
					Verify.expect(Bound.controls(runtime)):toBe(outer)
					local result = inner.provide(function()
						Verify.expect(Bound.controls(runtime)):toBe(inner)
						Verify.expect(Facet.bind(Core, Roblox).controls(runtime)):toBe(inner)
						return inner.VStack {
							Core.show(shown, function()
								renders += 1
								Core.cleanup(function()
									cleanups += 1
								end)
								local UI = Bound.controls(runtime)
								Verify.expect(UI):toBe(inner)
								local button = UI.Button({ label = "Nested" })
								Verify.expect(button.Size.Y.Offset):toBe(60)
								return button
							end),
						}
					end)
					Verify.expect(Bound.controls(runtime)):toBe(outer)
					return result
				end)
			end, engine.new("Folder"))
			shown:set(true)
			shown:set(false)
			shown:set(true)
			Verify.expect(renders):toBe(2)
			Verify.expect(cleanups):toBe(1)
			stop()
			Verify.expect(cleanups):toBe(2)
		end)

		verifyHarness:case("providers keep controls separate for each runtime", function(context)
			local engine = engineLib.new()
			local first: ComposeRuntime = Roblox.createRuntime(engine)
			local second: ComposeRuntime = Roblox.createRuntime(engine)
			context:defer(function()
				second:dispose()
				first:dispose()
			end)
			local Bound = Facet.bind(Core, Roblox)
			local outer = Bound.controls(first, { types = engine.types })
			local inner = Bound.controls(second, { types = engine.types })
			first.mount(function()
				return outer.provide(function()
					return inner.provide(function()
						Verify.expect(Bound.controls(first)):toBe(outer)
						Verify.expect(Bound.controls(second)):toBe(inner)
						return outer.Button({ label = "First runtime" })
					end)
				end)
			end, engine.new("Folder"))
		end)

		verifyHarness:case("drives bound controls from consumer cells and nests their disposal under consumer owners", {
			id = "native_compose_binding::Facet on the consumer's Compose instance::drives bound controls from consumer cells and nests their disposal under consumer owners",
			run = function()
				local Bound = Facet.bind(Core, Roblox)
				Verify.expect(Bound.Compose):toBe(Core)
				Verify.expect(Bound.Roblox):toBe(Roblox)
				Verify.expect(Bound.VERSION):toBe(Facet.VERSION)
				Verify.expect(Facet.Compose ~= Core):toBe(true)
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local Host = (runtime.constructors :: unknown) :: RobloxHost
				local UI = Bound.controls(runtime, { types = engine.types })
				local root = engine.new("ScreenGui")
				local baseline = engine.census()
				local shown, checked, caption, amount =
					Core.cell(true), Core.cell(false), Core.cell("One"), Core.cell(2)
				local total = Core.cell(1)
				local cleanups = 0
				local toggle: any, label, button, sheet
				local stop = runtime.mount(function()
					Core.cleanup(function()
						cleanups += 1
					end)
					local doubled = Core.formula(function(use: Use)
						return use(total) * 2
					end)
					sheet = Bound.themes.createStyleSheet(runtime, nil, { types = engine.types })
					return Host.Frame({
						sheet :: unknown,
						Core.show(shown, function()
							toggle = UI.Toggle({
								value = checked,
								presentation = "checkbox" :: "checkbox",
								label = "Enabled",
							})
							return toggle
						end),
						UI.Text({
							text = function(use: Use)
								return `{use(caption)} {use(doubled)}`
							end,
							ref = function(node)
								label = node
							end,
						}),
						UI.Button({
							label = caption,
							ref = function(node)
								button = node
							end,
						}),
						UI.Slider({ value = amount, min = 0, max = 10 }),
					})
				end, root)
				Verify.expect(label.Text):toBe("One 2")
				Verify.expect(button.Text):toBe("One")
				Verify.expect(find(toggle, "Check").Visible):toBe(false)
				checked:set(true)
				Verify.expect(find(toggle, "Check").Visible):toBe(true)
				toggle.Activated:Fire()
				Verify.expect((checked:peek())):toBe(false)
				caption:set("Two")
				Verify.expect(label.Text):toBe("Two 2")
				Verify.expect(button.Text):toBe("Two")
				runtime:batch(function()
					caption:set("Three")
					total:set(5)
				end)
				Verify.expect(label.Text):toBe("Three 10")
				total:set(6)
				Verify.expect(label.Text):toBe("Three 12")
				local hidden = toggle
				shown:set(false)
				Verify.expect((hidden:isDestroyed())):toBe(true)
				checked:set(true)
				stop()
				Verify.expect(cleanups):toBe(1)
				Verify.expect(#root:GetChildren()):toBe(0)
				caption:set("Four")
				Verify.expect(label.Text):toBe("Three 12")
				local after = engine.census()
				Verify.expect(after.live):toBe(baseline.live)
				Verify.expect(after.connections):toBe(baseline.connections)
				runtime:dispose()
			end,
		})

		verifyHarness:case("mounts a component through Facet.app with one theme install and releases it", {
			id = "native_compose_binding::Facet on the consumer's Compose instance::mounts a component through Facet.app with one theme install and releases it",
			run = function()
				local function rules(sheet: any): { string }
					local out = {}
					for _, rule in sheet:GetChildren() do
						local properties = {}
						for key, value in rule:GetProperties() do
							table.insert(properties, `{key}={tostring(value)}`)
						end
						table.sort(properties)
						table.insert(out, `{rule.Selector} {table.concat(properties, ",")}`)
					end
					table.sort(out)
					return out
				end
				for _, surface in { Facet, Facet.bind(Core, Roblox) } do
					local engine = engineLib.new()
					local runtime: ComposeRuntime = surface.Roblox.createRuntime(engine)
					local package = assert(surface.themes.define({
						identity = { id = "app-wide" },
						metrics = { space = { xs = 6, s = 12, m = 20, l = 30, xl = 48 } },
					} :: any))
					local playerGui = engine.new("Folder")
					local app =
						surface.app({ runtime = runtime, theme = package, types = engine.types, parent = playerGui })
					Verify.expect(app.runtime):toBe(runtime)
					local UI = app.UI
					local count = surface.Compose.cell(0)
					local cleaned = 0
					local stop, gui = app.mount(function()
						surface.Compose.cleanup(function()
							cleaned += 1
						end)
						return UI.Screen "Counter" {
							gap = "s",
							UI.Text "Count" {
								text = function(use: Use)
									return `Count {use(count)}`
								end,
							} :: unknown,
							UI.Button "Add" {
								label = "Add one",
								onActivate = function()
									count:update(function(value)
										return value + 1
									end)
								end,
							},
						}
					end)
					Verify.expect(gui.ClassName):toBe("ScreenGui")
					Verify.expect(gui.ZIndexBehavior):toBe(engine.types.Enum.ZIndexBehavior.Sibling)
					Verify.expect(gui.Parent):toBe(playerGui)
					Verify.expect(gui.ResetOnSpawn):toBe(false)
					local sheet = gui:FindFirstChildWhichIsA("StyleSheet")
					local link: any = gui:FindFirstChildWhichIsA("StyleLink")
					Verify.expect(sheet ~= nil and link ~= nil):toBe(true)
					Verify.expect(link.StyleSheet):toBe(sheet)
					local reference
					local stopReference = runtime.mount(function()
						reference = surface.themes.createStyleSheet(runtime, package, { types = engine.types })
						return reference
					end, engine.new("Folder"))
					Verify.expect(#rules(sheet) > 0):toBe(true)
					Verify.expect((rules(sheet))):toEqual(rules(reference))
					stopReference()
					local screen = find(gui, "Counter")
					Verify.expect(screen:FindFirstChildWhichIsA("UIListLayout").Padding)
						:toBe(engine.types.UDim.new(0, 12))
					Verify.expect(screen:FindFirstChildWhichIsA("UIPadding").PaddingLeft)
						:toBe(engine.types.UDim.new(0, 20))
					find(gui, "Add").Activated:Fire()
					Verify.expect(find(gui, "Count").Text):toBe("Count 1")
					local secondParent = engine.new("Folder")
					local second = app.mount(function()
						return UI.Text { text = "Second" }
					end, secondParent)
					Verify.expect(#secondParent:GetChildren()):toBe(1)
					stop()
					stop()
					Verify.expect(cleaned):toBe(1)
					Verify.expect(#playerGui:GetChildren()):toBe(0)
					app.dispose()
					app.dispose()
					Verify.expect(#secondParent:GetChildren()):toBe(0)
					local stopLate, late: any = runtime.mount(function()
						return UI.Text({ text = "Late" })
					end, engine.new("Folder"))
					Verify.expect(late.Text):toBe("Late")
					stopLate()
					second()
					Verify.expect(string.find(
						failure(function()
							app.mount(function()
								return UI.Text({ text = "Late" })
							end)
						end),
						"Facet app.mount: the app is disposed",
						1,
						true
					) ~= nil):toBe(true)
					local palette = ((surface.Compose.cell :: unknown) :: (string) -> Facet.Value<string>)("Dark")
					local styled = (surface.app :: (Facet.AppOptions) -> Facet.App)({
						runtime = (runtime :: unknown) :: Facet.Runtime,
						types = engine.types,
						parent = playerGui,
						theme = surface.themes.neutralPackage(),
						sheet = { theme = palette, transition = false :: false },
						screen = { Name = "Desk", DisplayOrder = 7, ResetOnSpawn = true },
					})
					local stopStyled, desk = styled.mount(function()
						return styled.UI.Text({ text = "Desk" })
					end)
					Verify.expect(desk.Name):toBe("Desk")
					Verify.expect(desk.DisplayOrder):toBe(7)
					Verify.expect(desk.ResetOnSpawn):toBe(true)
					local referencePalette
					local stopPalette = runtime.mount(function()
						referencePalette = surface.themes.createStyleSheet(
							runtime,
							surface.themes.neutralPackage(),
							{ types = engine.types, theme = palette, transition = false :: false }
						)
						return referencePalette
					end, engine.new("Folder"))
					Verify.expect((rules(desk:FindFirstChildWhichIsA("StyleSheet")))):toEqual(rules(referencePalette))
					local dark = table.concat(rules(desk:FindFirstChildWhichIsA("StyleSheet")), "\n")
					palette:set("Light")
					Verify.expect((rules(desk:FindFirstChildWhichIsA("StyleSheet")))):toEqual(rules(referencePalette))
					Verify.expect(table.concat(rules(desk:FindFirstChildWhichIsA("StyleSheet")), "\n") ~= dark)
						:toBe(true)
					stopPalette()
					stopStyled()
					styled.dispose()
					runtime:dispose()
				end
			end,
		})
	end)
end
