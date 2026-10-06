--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T
	local fs = require("@lune/fs")

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")

	local Core = require("./lib/compose_twin/core")
	local Roblox = require("./lib/compose_twin/roblox")

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
		verifyHarness:case("loads a second, separate Compose instance for these cases", {
			id = "native_compose_binding::Facet on the consumer's Compose instance::loads a second, separate Compose instance for these cases",
			run = function()
				Verify.expect(Core ~= Facet.Compose):toBe(true)
				Verify.expect(Core.cell ~= Facet.Compose.cell):toBe(true)
			end,
		})

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
				toggle.Activated.fire()
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

		verifyHarness:case("names the control when a runtime from another Compose instance reaches default controls", {
			id = "native_compose_binding::Facet on the consumer's Compose instance::names the control when a runtime from another Compose instance reaches default controls",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local UI = Facet.controls(runtime, { types = engine.types })
				local message = failure(function()
					runtime.mount(function()
						return UI.Toggle({ value = Core.cell(false), label = "Enabled" })
					end, engine.new("ScreenGui"))
				end)
				Verify.expect(string.find(message, "Facet UI.Toggle", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(message, "Facet.bind", 1, true) ~= nil):toBe(true)
				runtime:dispose()
			end,
		})

		verifyHarness:case("names the control and option when a readable comes from another Compose instance", {
			id = "native_compose_binding::Facet on the consumer's Compose instance::names the control and option when a readable comes from another Compose instance",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local UI = Facet.controls(runtime, { types = engine.types })
				local message = failure(function()
					runtime.mount(function()
						return UI.Text({ text = Core.cell("Foreign") })
					end, engine.new("ScreenGui"))
				end)
				Verify.expect(string.find(message, "Facet UI.Text", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(message, "'text'", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(message, "Facet.bind", 1, true) ~= nil):toBe(true)
				local nested = failure(function()
					runtime.mount(function()
						return UI.Menu({
							label = "Menu",
							items = {
								{ id = "a", label = "A", checked = Core.cell(false) } :: FixtureNavigationTypes.MenuItem<any>,
							},
						})
					end, engine.new("ScreenGui"))
				end)
				Verify.expect(string.find(nested, "Facet UI.Menu", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(nested, "'items.checked'", 1, true) ~= nil):toBe(true)
				local native = Facet.Compose.cell("Native")
				local stop, node: any = runtime.mount(function()
					return UI.Text({ text = native })
				end, engine.new("ScreenGui"))
				Verify.expect(node.Text):toBe("Native")
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("uses the vendored Compose inside src/ui for types only", {
			id = "native_compose_binding::Facet on the consumer's Compose instance::uses the vendored Compose inside src/ui for types only",
			run = function()
				local offenders = {}
				for _, file in fs.readDir("src/ui") do
					local source = fs.readFile("src/ui/" .. file)
					for name in string.gmatch(source, 'local (%w+) = require%("%.%./vendor/compose/core"%)') do
						local number = 0
						for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
							number += 1
							local at = string.find(line, name .. "%.%l")
							if at and not string.find(string.sub(line, 1, at), "typeof%(") then
								table.insert(offenders, `{file}:{number}`)
							end
						end
					end
				end
				Verify.expect((table.concat(offenders, ", "))):toBe("")
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
					find(gui, "Add").Activated.fire()
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
					local palette = ((surface.Compose.cell :: unknown) :: (string) -> Facet.Cell<string>)("Dark")
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

		verifyHarness:case("rejects a Compose module that lacks a function Facet uses", {
			id = "native_compose_binding::Facet on the consumer's Compose instance::rejects a Compose module that lacks a function Facet uses",
			run = function()
				for _, name in { "presence", "focusNeighbor" } do
					local partial = table.clone(Core) :: any
					partial[name] = nil
					local message = failure(function()
						Facet.bind(partial, Roblox)
					end)
					Verify.expect(string.find(message, name, 1, true) ~= nil):toBe(true)
					Verify.expect(string.find(message, string.sub(Facet.COMPOSE_COMMIT, 1, 7), 1, true) ~= nil)
						:toBe(true)
				end
			end,
		})
	end)
end
