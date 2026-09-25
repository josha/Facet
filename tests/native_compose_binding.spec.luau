--!strict
local fs = require("@lune/fs")
local t = require("./lib/testkit")
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
	local ok, err = pcall(body)
	assert(not ok, "expected an error")
	return tostring(err)
end

t.describe("Facet on the consumer's Compose instance", function()
	t.it("loads a second, separate Compose instance for these cases", function()
		t.expect(Core ~= Facet.Compose).toBe(true)
		t.expect(Core.cell ~= Facet.Compose.cell).toBe(true)
	end)

	t.it("drives bound controls from consumer cells and nests their disposal under consumer owners", function()
		local Bound = Facet.bind(Core, Roblox)
		t.expect(Bound.Compose).toBe(Core)
		t.expect(Bound.Roblox).toBe(Roblox)
		t.expect(Bound.VERSION).toBe(Facet.VERSION)
		t.expect(Facet.Compose ~= Core).toBe(true)
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local Host = runtime.constructors
		local UI = Bound.controls(runtime, { types = engine.types })
		local root = engine.new("ScreenGui")
		local baseline = engine.census()
		local shown, checked, caption, amount = Core.cell(true), Core.cell(false), Core.cell("One"), Core.cell(2)
		local total = Core.cell(1)
		local cleanups = 0
		local toggle, label, button, sheet
		local stop = runtime.mount(function()
			Core.cleanup(function()
				cleanups += 1
			end)
			local doubled = Core.formula(function(use)
				return use(total) * 2
			end)
			sheet = Bound.themes.createStyleSheet(runtime, nil, { types = engine.types })
			return Host.Frame({
				sheet,
				Core.show(shown, function()
					toggle = UI.Toggle({ value = checked, presentation = "checkbox", label = "Enabled" })
					return toggle
				end),
				UI.Label({
					text = function(use)
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
		t.expect(label.Text).toBe("One 2")
		t.expect(button.Text).toBe("One")
		t.expect(find(toggle, "Check").Visible).toBe(false)
		checked:set(true)
		t.expect(find(toggle, "Check").Visible).toBe(true)
		toggle.Activated.fire()
		t.expect(checked:peek()).toBe(false)
		caption:set("Two")
		t.expect(label.Text).toBe("Two 2")
		t.expect(button.Text).toBe("Two")
		runtime:batch(function()
			caption:set("Three")
			total:set(5)
		end)
		t.expect(label.Text).toBe("Three 10")
		total:set(6)
		t.expect(label.Text).toBe("Three 12")
		local hidden = toggle
		shown:set(false)
		t.expect(hidden:isDestroyed()).toBe(true)
		checked:set(true)
		stop()
		t.expect(cleanups).toBe(1)
		t.expect(#root:GetChildren()).toBe(0)
		caption:set("Four")
		t.expect(label.Text).toBe("Three 12")
		local after = engine.census()
		t.expect(after.live).toBe(baseline.live)
		t.expect(after.connections).toBe(baseline.connections)
		runtime:dispose()
	end)

	t.it("names the control when a runtime from another Compose instance reaches default controls", function()
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, { types = engine.types })
		local message = failure(function()
			runtime.mount(function()
				return UI.Toggle({ value = Core.cell(false), label = "Enabled" })
			end, engine.new("ScreenGui"))
		end)
		t.expect(string.find(message, "Facet UI.Toggle", 1, true) ~= nil).toBe(true)
		t.expect(string.find(message, "Facet.bind", 1, true) ~= nil).toBe(true)
		runtime:dispose()
	end)

	t.it("names the control and option when a readable comes from another Compose instance", function()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, { types = engine.types })
		local message = failure(function()
			runtime.mount(function()
				return UI.Label({ text = Core.cell("Foreign") })
			end, engine.new("ScreenGui"))
		end)
		t.expect(string.find(message, "Facet UI.Label", 1, true) ~= nil).toBe(true)
		t.expect(string.find(message, "'text'", 1, true) ~= nil).toBe(true)
		t.expect(string.find(message, "Facet.bind", 1, true) ~= nil).toBe(true)
		local nested = failure(function()
			runtime.mount(function()
				return UI.Menu({
					label = "Menu",
					items = { { id = "a", label = "A", checked = Core.cell(false) } },
				})
			end, engine.new("ScreenGui"))
		end)
		t.expect(string.find(nested, "Facet UI.Menu", 1, true) ~= nil).toBe(true)
		t.expect(string.find(nested, "'items.checked'", 1, true) ~= nil).toBe(true)
		local native = Facet.Compose.cell("Native")
		local stop, node = runtime.mount(function()
			return UI.Label({ text = native })
		end, engine.new("ScreenGui"))
		t.expect(node.Text).toBe("Native")
		stop()
		runtime:dispose()
	end)

	t.it("uses the vendored Compose inside src/ui for types only", function()
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
		t.expect(table.concat(offenders, ", ")).toBe("")
	end)

	t.it("mounts a component through Facet.app with one theme install and releases it", function()
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
			local runtime = surface.Roblox.createRuntime(engine)
			local package = assert(surface.themes.define({
				identity = { id = "app-wide" },
				metrics = { space = { xs = 6, s = 12, m = 20, l = 30, xl = 48 } },
			} :: any))
			local playerGui = engine.new("Folder")
			local app = surface.app({ runtime = runtime, theme = package, types = engine.types, parent = playerGui })
			t.expect(app.runtime).toBe(runtime)
			local UI = app.UI
			local count = surface.Compose.cell(0)
			local cleaned = 0
			local stop, gui = app.mount(function()
				surface.Compose.cleanup(function()
					cleaned += 1
				end)
				return UI.Screen "Counter" {
					gap = "s",
					UI.Label "Count" {
						text = function(use)
							return `Count {use(count)}`
						end,
					},
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
			t.expect(gui.ClassName).toBe("ScreenGui")
			t.expect(gui.Parent).toBe(playerGui)
			t.expect(gui.ResetOnSpawn).toBe(false)
			local sheet = gui:FindFirstChildWhichIsA("StyleSheet")
			local link = gui:FindFirstChildWhichIsA("StyleLink")
			t.expect(sheet ~= nil and link ~= nil).toBe(true)
			t.expect(link.StyleSheet).toBe(sheet)
			local reference
			local stopReference = runtime.mount(function()
				reference = surface.themes.createStyleSheet(runtime, package, { types = engine.types })
				return reference
			end, engine.new("Folder"))
			t.expect(#rules(sheet) > 0).toBe(true)
			t.expect(rules(sheet)).toEqual(rules(reference))
			stopReference()
			local screen = find(gui, "Counter")
			t.expect(screen:FindFirstChildWhichIsA("UIListLayout").Padding).toBe(engine.types.UDim.new(0, 12))
			t.expect(screen:FindFirstChildWhichIsA("UIPadding").PaddingLeft).toBe(engine.types.UDim.new(0, 20))
			find(gui, "Add").Activated.fire()
			t.expect(find(gui, "Count").Text).toBe("Count 1")
			local secondParent = engine.new("Folder")
			local second = app.mount(function()
				return UI.Label { text = "Second" }
			end, secondParent)
			t.expect(#secondParent:GetChildren()).toBe(1)
			stop()
			stop()
			t.expect(cleaned).toBe(1)
			t.expect(#playerGui:GetChildren()).toBe(0)
			app.dispose()
			app.dispose()
			t.expect(#secondParent:GetChildren()).toBe(0)
			local stopLate, late = runtime.mount(function()
				return UI.Label({ text = "Late" })
			end, engine.new("Folder"))
			t.expect(late.Text).toBe("Late")
			stopLate()
			second()
			t.expect(string.find(
				failure(function()
					app.mount(function()
						return UI.Label({ text = "Late" })
					end)
				end),
				"Facet app.mount: the app is disposed",
				1,
				true
			) ~= nil).toBe(true)
			local palette = surface.Compose.cell("Dark")
			local styled = surface.app({
				runtime = runtime,
				types = engine.types,
				parent = playerGui,
				theme = surface.themes.neutralPackage(),
				sheet = { theme = palette, transition = false },
				screen = { Name = "Desk", DisplayOrder = 7, ResetOnSpawn = true },
			})
			local stopStyled, desk = styled.mount(function()
				return styled.UI.Label({ text = "Desk" })
			end)
			t.expect(desk.Name).toBe("Desk")
			t.expect(desk.DisplayOrder).toBe(7)
			t.expect(desk.ResetOnSpawn).toBe(true)
			local referencePalette
			local stopPalette = runtime.mount(function()
				referencePalette = surface.themes.createStyleSheet(
					runtime,
					surface.themes.neutralPackage(),
					{ types = engine.types, theme = palette, transition = false }
				)
				return referencePalette
			end, engine.new("Folder"))
			t.expect(rules(desk:FindFirstChildWhichIsA("StyleSheet"))).toEqual(rules(referencePalette))
			local dark = table.concat(rules(desk:FindFirstChildWhichIsA("StyleSheet")), "\n")
			palette:set("Light")
			t.expect(rules(desk:FindFirstChildWhichIsA("StyleSheet"))).toEqual(rules(referencePalette))
			t.expect(table.concat(rules(desk:FindFirstChildWhichIsA("StyleSheet")), "\n") ~= dark).toBe(true)
			stopPalette()
			stopStyled()
			styled.dispose()
			runtime:dispose()
		end
	end)

	t.it("rejects a Compose module that lacks a function Facet uses", function()
		local partial = table.clone(Core) :: any
		partial.presence = nil
		local message = failure(function()
			Facet.bind(partial, Roblox)
		end)
		t.expect(string.find(message, "presence", 1, true) ~= nil).toBe(true)
		t.expect(string.find(message, "869d260", 1, true) ~= nil).toBe(true)
	end)
end)
