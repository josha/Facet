--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local ThemeTypes = require("../src/ui/theme_types")
	local FixtureEngineTypes = require("../src/ui/engine_types")

	local Facet = require("../src")
	local context = require("../src/ui/context")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	verifyHarness:suite("native public surface", function()
		verifyHarness:case("exposes controls over the unwrapped Compose Roblox runtime", {
			id = "native_public_surface::native public surface::exposes controls over the unwrapped Compose Roblox runtime",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local Host = (runtime.constructors :: unknown) :: RobloxHost
				local UI = Facet.controls(runtime, { types = engine.types })
				Verify.expect(((Facet :: unknown) :: { [string]: unknown }).new):toBeNil()
				Verify.expect((type(UI.Screen))):toBe("function")
				Verify.expect(((UI :: unknown) :: { [string]: unknown }).ForEach):toBeNil()
				Verify.expect(((UI :: unknown) :: { [string]: unknown }).When):toBeNil()
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
				Verify.expect(reference.ClassName):toBe("TextButton")
				Verify.expect(reference.Parent):toBe(frame)
				Verify.expect((reference:GetAttribute("meaning"))):toBe("test")
				label:set("After")
				Verify.expect(reference.Text):toBe("After")
				Verify.expect(calls):toBe(1)
				shown:set(false)
				Verify.expect((reference:isDestroyed())):toBe(true)
				shown:set(true)
				Verify.expect(calls):toBe(2)
				stop()
				Verify.expect(#root:GetChildren()):toBe(0)
				runtime:dispose()
			end,
		})

		verifyHarness:case("gates native actions through retained ancestors and detaches observations", {
			id = "native_public_surface::native public surface::gates native actions through retained ancestors and detaches observations",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local Host = (runtime.constructors :: unknown) :: RobloxHost
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
				Verify.expect(input.Enabled):toBe(true)
				action.Pressed.fire()
				panel.Visible = false
				Verify.expect(input.Enabled):toBe(false)
				action.Pressed.fire()
				panel.Visible = true
				root.Enabled = false
				Verify.expect(input.Enabled):toBe(false)
				root.Enabled = true
				panel.Interactable = false
				Verify.expect(input.Enabled):toBe(false)
				panel.Interactable = true
				Verify.expect(input.Enabled):toBe(true)
				Verify.expect(activated):toBe(1)
				stop()
				Verify.expect((action.Pressed.count())):toBe(0)
				Verify.expect((root:GetPropertyChangedSignal("Enabled").count())):toBe(0)
				runtime:dispose()
			end,
		})

		verifyHarness:case("resolves named icons reactively without a second theme runtime", {
			id = "native_public_surface::native public surface::resolves named icons reactively without a second theme runtime",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local first = Facet.themes.neutralPackage()
				first.icons = { test = "rbxassetid://1" } :: { [string]: ThemeTypes.IconEntry }
				local package = Compose.cell(first)
				local ctx = context(Facet.Compose, runtime, { types = engine.types, theme = package })
				local stop, icon: any = runtime.mount(function()
					return ctx.icon("test")
				end, engine.new("ScreenGui"))
				Verify.expect(icon.Image):toBe("rbxassetid://1")
				local second = table.clone(first)
				second.icons = { test = "rbxassetid://2" } :: { [string]: ThemeTypes.IconEntry }
				package:set(second)
				Verify.expect(icon.Image):toBe("rbxassetid://2")
				stop()
				runtime:dispose()
			end,
		})
	end)
end
