--!strict
local ThemeTypes = require("../src/ui/theme_types")
local FixtureEngineTypes = require("../src/ui/engine_types")
local t = require("./lib/testkit")
local Facet = require("../src")
local context = require("../src/ui/context")
local engineLib = require("./lib/native_engine")
local Compose: typeof(require("@repo/src/vendor/compose/core")) = Facet.Compose

t.describe("native public surface", function()
	t.it("exposes controls over the unwrapped Compose Roblox runtime", function()
		local engine = engineLib.new()
		local runtime: typeof(require("@repo/src/vendor/compose/roblox").createRuntime(nil :: any)) =
			Facet.Roblox.createRuntime(engine)
		local Host = (
			runtime.constructors :: unknown
		) :: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
		local UI = Facet.controls(runtime, { types = engine.types })
		t.expect(((Facet :: unknown) :: { [string]: unknown }).new).toBeNil()
		t.expect(type(UI.Screen)).toBe("function")
		t.expect(((UI :: unknown) :: { [string]: unknown }).ForEach).toBeNil()
		t.expect(((UI :: unknown) :: { [string]: unknown }).When).toBeNil()
		local shown, label = Compose.cell(true), Compose.cell("Before")
		local root = engine.new("ScreenGui")
		local reference: any, calls
		calls = 0
		local stop, frame: any = runtime.mount(function()
			return Host.Frame({
				Compose.show(shown, function()
					return UI.Button("Action")({
						label = label,
						Attributes = { meaning = "test" } :: FixtureEngineTypes.Attributes,
						ref = function(node)
							reference = node
							calls += 1
						end,
					})
				end),
			})
		end, root)
		t.expect(reference.ClassName).toBe("TextButton")
		t.expect(reference.Parent).toBe(frame)
		t.expect(reference:GetAttribute("meaning")).toBe("test")
		label:set("After")
		t.expect(reference.Text).toBe("After")
		t.expect(calls).toBe(1)
		shown:set(false)
		t.expect(reference:isDestroyed()).toBe(true)
		shown:set(true)
		t.expect(calls).toBe(2)
		stop()
		t.expect(#root:GetChildren()).toBe(0)
		runtime:dispose()
	end)

	t.it("gates native actions through retained ancestors and detaches observations", function()
		local engine = engineLib.new()
		local runtime: typeof(require("@repo/src/vendor/compose/roblox").createRuntime(nil :: any)) =
			Facet.Roblox.createRuntime(engine)
		local Host = (
			runtime.constructors :: unknown
		) :: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
		local ctx = context(Facet.Compose, runtime, { types = engine.types })
		local root = engine.new("ScreenGui")
		local action: any, input: any, button: any, activated: number = nil, nil, nil, 0
		local stop, panel: any = runtime.mount(function()
			button = Host.TextButton({})
			action, input = ctx.action(button, "Test", { engine.types.Enum.KeyCode.X }, true, function()
				activated += 1
			end)
			return Host.Frame({ button :: unknown })
		end, root)
		t.expect(input.Enabled).toBe(true)
		action.Pressed.fire()
		panel.Visible = false
		t.expect(input.Enabled).toBe(false)
		action.Pressed.fire()
		panel.Visible = true
		root.Enabled = false
		t.expect(input.Enabled).toBe(false)
		root.Enabled = true
		panel.Interactable = false
		t.expect(input.Enabled).toBe(false)
		panel.Interactable = true
		t.expect(input.Enabled).toBe(true)
		t.expect(activated).toBe(1)
		stop()
		t.expect(action.Pressed.count()).toBe(0)
		t.expect(root:GetPropertyChangedSignal("Enabled").count()).toBe(0)
		runtime:dispose()
	end)

	t.it("resolves named icons reactively without a second theme runtime", function()
		local engine = engineLib.new()
		local runtime: typeof(require("@repo/src/vendor/compose/roblox").createRuntime(nil :: any)) =
			Facet.Roblox.createRuntime(engine)
		local first = Facet.themes.neutralPackage()
		first.icons = { test = "rbxassetid://1" } :: { [string]: ThemeTypes.IconEntry }
		local package = Compose.cell(first)
		local ctx = context(Facet.Compose, runtime, { types = engine.types, theme = package })
		local stop, icon: any = runtime.mount(function()
			return ctx.icon("test")
		end, engine.new("ScreenGui"))
		t.expect(icon.Image).toBe("rbxassetid://1")
		local second = table.clone(first)
		second.icons = { test = "rbxassetid://2" } :: { [string]: ThemeTypes.IconEntry }
		package:set(second)
		t.expect(icon.Image).toBe("rbxassetid://2")
		stop()
		runtime:dispose()
	end)
end)
