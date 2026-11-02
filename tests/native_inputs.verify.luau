--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")
local ThemeTypes = require("../src/ui/theme_types")
local InputProps = require("../src/ui/input_props")
local FixtureBridge = require("../tools/vendor/verify/src/roblox/fixture-bridge")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	type TextButtonConstructor = typeof(require("@repo/tools/typecheck/aliases").TextButtonConstructor)
	local FixtureEngineTypes = require("../src/ui/engine_types")
	local ComposeTypes = require("../src/vendor/compose/core")
	type Use = ComposeTypes.Use
	local SharedTypes = require("../src/ui/control_types")

	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local context = require("../src/ui/context")
	local register = require("../src/ui/inputs")
	local Facet = require("../src")
	local function fixtureTheme(definition: ThemeTypes.ThemeDefinition): ThemeTypes.ThemePackage
		local package = Facet.themes.define(definition)
		return assert(package)
	end
	local engineLib = require("./lib/native_engine")
	local readSource = require("../src/ui/source_read")

	it("source reads track bodies only when a reader is supplied", function()
		local source = Compose.cell(2)
		local root = Compose.createRootOwner(function()
			local function body(use: Compose.Use): number
				return use(source) * 3
			end
			local tracked = Compose.formula(function(use: Compose.Use): number
				return readSource(body, use)
			end)
			local sampled = Compose.formula(function(): number
				return readSource(body)
			end)
			expect(readSource(source)):toBe(2)
			expect(tracked:peek()):toBe(6)
			expect(sampled:peek()):toBe(6)
			source:set(4)
			expect(readSource(source)):toBe(4)
			expect(tracked:peek()):toBe(12)
			expect(sampled:peek()):toBe(6)
		end)
		root.dispose()
		source:dispose()
	end)

	local function world(
		build: (SharedTypes.Controls, engineLib.Engine, Compose.Runtime) -> Compose.Node,
		configure: ((engineLib.Engine, FixtureBridge.Bridge) -> SharedTypes.Config)?
	)
		local engine, fixture = engineLib.new()
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local UI = ({} :: unknown) :: SharedTypes.Controls
		local options: SharedTypes.Config = if configure then configure(engine, fixture) else {}
		options.types = engine.types
		local ctx = context(Compose, runtime, options)
		register(ctx, UI)
		local stop, node: any = runtime.mount(function()
			return build(UI, engine, runtime)
		end, engine.new("ScreenGui"))
		return node, stop, engine, runtime, ctx
	end

	local function find(root: any, name: string): any
		if root.Name == name then
			return root
		end
		for _, child in root:GetChildren() do
			local found = find(child, name)
			if found then
				return found
			end
		end
		return nil
	end

	local function enabledAction(root: Instance, name: string): InputAction?
		local found: InputAction? = nil
		for _, child in root:GetChildren() do
			if child:IsA("InputContext") and child.Enabled then
				local action = child:FindFirstChild(name)
				if action and action:IsA("InputAction") then
					found = action
					break
				end
			end
		end
		return found
	end

	local function actionContext(action: InputAction): InputContext
		local parent = assert(action.Parent)
		assert(parent:IsA("InputContext"))
		return parent
	end

	describe("native input controls", function()
		it("actions share ancestry while retaining independent conditions and owner lifetimes", function()
			local node, stop, engine, runtime, ctx = world(function(_, _, runtime)
				return Facet.host(runtime).Frame({})
			end)
			local first = Compose.createOwner(runtime.reactor)
			local second = Compose.createOwner(runtime.reactor)
			local enabled = Compose.cell(true)
			local _, firstContext = Compose.withOwner(first, function()
				return ctx.action(node, "First", { "A" }, enabled, function() end)
			end)
			local _, groupedContext = Compose.withOwner(first, function()
				return ctx.action(node, "Grouped", { "B" }, nil, function() end, { group = "Shared" })
			end)
			local _, sameContext = Compose.withOwner(first, function()
				return ctx.action(node, "GroupedAgain", { "C" }, nil, function() end, { group = "Shared" })
			end)
			local _, secondContext = Compose.withOwner(second, function()
				return ctx.action(node, "Second", { "D" }, nil, function() end)
			end)
			expect(sameContext):toBe(groupedContext)
			expect(firstContext.Enabled):toBe(true)
			enabled:set(false)
			expect(firstContext.Enabled):toBe(false)
			expect(groupedContext.Enabled):toBe(true)
			local screen = node.Parent
			local parent = engine.new("Frame")
			parent.Parent = screen
			node.Parent = parent
			parent.Visible = false
			expect(groupedContext.Enabled):toBe(false)
			expect(secondContext.Enabled):toBe(false)
			parent.Visible = true
			enabled:set(true)
			expect(firstContext.Enabled):toBe(true)
			expect(groupedContext.Enabled):toBe(true)
			node.Parent = nil
			expect(firstContext.Parent):toBeNil()
			expect(secondContext.Enabled):toBe(false)
			node.Parent = screen
			parent.Visible = false
			expect(firstContext.Enabled):toBe(true)
			Compose.owner.dispose(first)
			node.Interactable = false
			expect(secondContext.Enabled):toBe(false)
			node.Interactable = true
			expect(secondContext.Enabled):toBe(true)
			Compose.owner.dispose(second)
			parent:Destroy()
			stop()
		end)

		it("inline targets keep touch height while compacting adjacent choices", function()
			local input: UserInputService
			local node, stop, engine = world(function(UI, engine)
				return UI.Button {
					name = "Page one",
					target = "inline",
					Size = engine.types.UDim2.fromOffset(24, 44),
					AutomaticSize = engine.types.Enum.AutomaticSize.None,
				}
			end, function(engine)
				input = (engine.new("UserInputService") :: unknown) :: UserInputService
				engine.environment.poke(VerifyRoblox.assertInstance(input), "TouchEnabled", true)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "GamepadEnabled", false)
				return { services = { UserInputService = input } }
			end)
			local floor = node:FindFirstChild("TargetFloor")
			expect(floor.MinSize.X):toBe(24)
			expect(floor.MinSize.Y):toBe(44)
			engine.environment.poke(VerifyRoblox.assertInstance(input), "TouchEnabled", false)
			expect(node:FindFirstChild("TargetFloor")):toBe(nil)
			engine.environment.poke(VerifyRoblox.assertInstance(input), "GamepadEnabled", true)
			expect(node:FindFirstChild("TargetFloor").MinSize.X):toBe(24)
			expect(node:FindFirstChild("TargetFloor").MinSize.Y):toBe(44)
			stop()
		end)
		it("a new press releases consumption left by an earlier control", function()
			local activation = require("../src/ui/activation")
			local press = {}
			activation.consume(press)
			local input
			local calls = 0
			local node, stop, engine = world(function(UI: FacetControls)
				return UI.Button {
					label = "Next",
					onActivate = function()
						calls += 1
					end,
				}
			end, function(engine)
				input = (engine.new("UserInputService") :: unknown) :: UserInputService
				return { services = { UserInputService = input } }
			end)
			node.Activated:Fire(press)
			expect(calls):toBe(0)
			engine.environment.fire(VerifyRoblox.assertInstance(input), "InputBegan", press)
			node.Activated:Fire(press)
			expect(calls):toBe(1)
			activation.release(press)
			stop()
		end)
		it("floors default button widths on touch and releases the idle constraint", {
			id = "native_inputs::native input controls::floors default button widths on touch and releases the idle constraint",
			run = function()
				local input: UserInputService
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button { label = "All" }
				end, function(engine)
					input = (engine.new("UserInputService") :: unknown) :: UserInputService
					engine.environment.poke(VerifyRoblox.assertInstance(input), "TouchEnabled", false)
					engine.environment.poke(VerifyRoblox.assertInstance(input), "GamepadEnabled", false)
					return { services = { UserInputService = input } }
				end)
				expect(node:FindFirstChild("TargetFloor")):toBe(nil)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "TouchEnabled", true)
				expect(node:FindFirstChild("TargetFloor").MinSize.X):toBe(44)
				expect(node:FindFirstChild("TargetFloor").MinSize.Y):toBe(44)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "TouchEnabled", false)
				expect(node:FindFirstChild("TargetFloor")):toBe(nil)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "GamepadEnabled", true)
				expect(node:FindFirstChild("TargetFloor").MinSize.X):toBe(44)
				stop()
			end,
		})
		it("tracks modal portal eligibility after entering and leaving a modal", {
			id = "native_inputs::native input controls::tracks modal portal eligibility after entering and leaving a modal",
			run = function()
				local node, stop, engine, runtime, ctx = world(function(UI: FacetControls)
					return UI.Button { label = "Portal" }
				end)
				local modal = engine.new("Frame")
				modal.Parent = node.Parent
				local available = false
				local owner = Compose.createRootOwner(function(root)
					Compose.owner.watch(root, function(use)
						available = ctx.available(node, use)
					end)
				end)
				expect(available):toBe(true)
				ctx.modalPortals:set({ { node = node, anchor = modal } })
				ctx.modalScopes:set({ modal })
				expect(available):toBe(true)
				ctx.modalPortals:set({})
				expect(available):toBe(false)
				ctx.modalScopes:set({})
				expect(available):toBe(true)
				ctx.modalScopes:set({ modal })
				expect(available):toBe(false)
				ctx.modalPortals:set({ { node = node, anchor = modal } })
				expect(available):toBe(true)
				owner.dispose()
				stop()
				modal:Destroy()
				runtime:dispose()
			end,
		})
		it("installs text editing contexts once on first focus", {
			id = "native_inputs::native input controls::installs text editing contexts once on first focus",
			run = function()
				local tracking: FixtureBridge.Tracking
				local value = Compose.cell("Player")
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.TextInputCellProps = { value = value }
					return UI.TextInput(props)
				end, function(_, fixture)
					tracking = fixture.track()
					return {}
				end)
				local function contexts(): number
					local count = 0
					for _, instance in tracking.created do
						if instance.ClassName == "InputContext" then
							count += 1
						end
					end
					return count
				end
				expect(contexts()):toBe(0)
				node:CaptureFocus()
				expect(contexts()):toBe(2)
				node:ReleaseFocus(false)
				node:CaptureFocus()
				expect(contexts()):toBe(2)
				node:ReleaseFocus(false)
				stop()
				tracking.stop()
				expect(engine.census().connections):toBe(0)
			end,
		})

		it("shares native property observations until the last owner releases them", {
			id = "native_inputs::native input controls::shares native property observations until the last owner releases them",
			run = function()
				local node, stop, engine, runtime, ctx = world(function(_UI: FacetControls, _engine, runtime)
					return runtime.constructors.TextButton { Text = "Save" }
				end)
				local firstOwner, secondOwner =
					Compose.createOwner(runtime.reactor), Compose.createOwner(runtime.reactor)
				local before = engine.census().connections
				local first = Compose.withOwner(firstOwner, function()
					return ctx.observe.Text(node)
				end)
				local second = Compose.withOwner(secondOwner, function()
					return ctx.observe.Text(node)
				end)
				expect(first):toBe(second)
				expect(engine.census().connections):toBe(before + 1)
				node.Text = "First"
				expect(first:peek()):toBe("First")
				Compose.owner.dispose(firstOwner)
				node.Text = "Second"
				expect(second:peek()):toBe("Second")
				expect(engine.census().connections):toBe(before + 1)
				Compose.owner.dispose(secondOwner)
				expect(engine.census().connections):toBe(before)
				node.Text = "Released"
				expect(second:peek()):toBe("Second")
				for _, property in { "AbsoluteSize", "SelectedObject" } do
					local gui = (engine.new("GuiService") :: unknown) :: GuiService
					local target: Instance = if property == "AbsoluteSize" then node else gui
					local function observe(): Compose.ReadOnlyValue<unknown>
						return if property == "AbsoluteSize"
							then ctx.observe.AbsoluteSize(node)
							else ctx.observe.SelectedObject(gui)
					end
					local a, b = Compose.createOwner(runtime.reactor), Compose.createOwner(runtime.reactor)
					local baseline = engine.census().connections
					local left, right = Compose.withOwner(a, observe), Compose.withOwner(b, observe)
					expect(left):toBe(right)
					expect(engine.census().connections):toBe(baseline + 1)
					Compose.owner.dispose(a)
					local value: unknown = if property == "AbsoluteSize" then engine.types.Vector2.new(80, 40) else node
					engine.environment.poke(VerifyRoblox.assertInstance(target), property, value)
					expect(right:peek()):toBe(value)
					expect(engine.census().connections):toBe(baseline + 1)
					Compose.owner.dispose(b)
					expect(engine.census().connections):toBe(baseline)
				end
				stop()
				runtime:dispose()
			end,
		})
		it("shares styled observations without ending another owners subscription", {
			id = "native_inputs::native input controls::shares styled observations without ending another owners subscription",
			run = function()
				local node, stop, engine, runtime, ctx = world(function(_UI: FacetControls, _engine, runtime)
					return runtime.constructors.TextLabel { Text = "Shared" }
				end)
				local size = 14
				engine.environment.fakeOn(node, "GetStyled", function(_object, property)
					assert(property == "TextSize")
					return size
				end)
				local firstOwner, secondOwner =
					Compose.createOwner(runtime.reactor), Compose.createOwner(runtime.reactor)
				local before = engine.census().connections
				local function observe()
					return ctx.observeStyled.TextSize(node)
				end
				local first, second = Compose.withOwner(firstOwner, observe), Compose.withOwner(secondOwner, observe)
				expect(first):toBe(second)
				expect(engine.census().connections):toBe(before + 2)
				size = 20
				engine.environment.fire(node, "StyledPropertiesChanged")
				expect(first:peek()):toBe(20)
				Compose.owner.dispose(firstOwner)
				size = 24
				engine.environment.fire(node, "StyledPropertiesChanged")
				expect(second:peek()):toBe(24)
				expect(engine.census().connections):toBe(before + 2)
				Compose.owner.dispose(secondOwner)
				expect(engine.census().connections):toBe(before)
				size = 28
				engine.environment.fire(node, "StyledPropertiesChanged")
				expect(second:peek()):toBe(24)
				stop()
				runtime:dispose()
			end,
		})

		it("empty button captions never tighten custom content padding", {
			id = "native_inputs::native input controls::empty button captions never tighten custom content padding",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls, engine)
					return UI.Button {
						Size = engine.types.UDim2.fromOffset(44, 44),
						AutomaticSize = engine.types.Enum.AutomaticSize.None,
					}
				end)
				engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(44, 44))
				engine.environment.poke(node, "TextFits", false)
				expect(node:HasTag("facet-button-tight")):toBe(false)
				node.Text = "Saved"
				expect(node:HasTag("facet-button-tight")):toBe(true)
				node.Text = ""
				expect(node:HasTag("facet-button-tight")):toBe(false)
				stop()
			end,
		})

		it("owns font observations only when a bounded caption needs overflow measurement", {
			id = "native_inputs::native input controls::owns font observations only when a bounded caption needs overflow measurement",
			run = function()
				local node, stop, engine, runtime = world(function(UI: FacetControls, engine)
					return UI.Button {
						Size = engine.types.UDim2.fromOffset(44, 44),
						AutomaticSize = engine.types.Enum.AutomaticSize.None,
					}
				end)
				local environment, V2 = engine.environment, engine.types.Vector2
				local function fontConnections(): number
					return environment.connectionsOf(node:GetPropertyChangedSignal("FontFace"))
						+ environment.connectionsOf(node:GetPropertyChangedSignal("TextSize"))
				end
				environment.poke(node, "TextFits", false)
				expect(fontConnections()):toBe(0)
				node.Text = "Saved"
				expect(fontConnections()):toBe(0)
				expect(node:HasTag("facet-button-tight")):toBe(false)
				environment.poke(node, "AbsoluteSize", V2.new(44, 44))
				expect(node:HasTag("facet-button-tight")):toBe(true)
				expect(fontConnections()):toBe(2)
				local style = { size = node.TextSize, face = node.FontFace }
				local reads = 0
				environment.fakeOn(node, "GetStyled", function(object, property)
					if property == "TextSize" then
						reads += 1
						return style.size
					elseif property == "FontFace" then
						reads += 1
						return style.face
					end
					return environment.propertyOf(object, property)
				end)
				style.size += 4
				style.face = engine.types.Font.new("rbxasset://fonts/families/GothamSSm.json")
				environment.fire(node, "StyledPropertiesChanged")
				expect(reads >= 2):toBe(true)
				expect(fontConnections()):toBe(2)
				expect(node:HasTag("facet-button-tight")):toBe(true)
				environment.poke(node, "TextBounds", V2.new(20, 14))
				environment.poke(node, "TextFits", true)
				environment.poke(node, "AbsoluteSize", V2.new(300, 44))
				expect(node:HasTag("facet-button-tight")):toBe(false)
				node.Text = ""
				expect(fontConnections()):toBe(0)
				node.Text = "Again"
				expect(fontConnections()):toBe(0)
				environment.poke(node, "TextFits", false)
				expect(node:HasTag("facet-button-tight")):toBe(true)
				expect(fontConnections()):toBe(2)
				stop()
				runtime:dispose()
				expect(fontConnections()):toBe(0)
			end,
		})

		it("creates a subtitle when text arrives and reuses it after clearing", {
			id = "native_inputs::native input controls::creates a subtitle when text arrives and reuses it after clearing",
			run = function()
				local subtitle = Compose.cell("")
				local node, stop = world(function(UI: FacetControls)
					return UI.Button "Action" { label = "Action", subtitle = subtitle }
				end)
				expect(find(node, "Description")):toBe(nil)
				subtitle:set("Details")
				local caption = find(node, "Description")
				expect(caption.Text):toBe("Details")
				expect(caption.Visible):toBe(true)
				subtitle:set("")
				expect(find(node, "Description")):toBe(caption)
				expect(caption.Visible):toBe(false)
				subtitle:set("Updated")
				expect(caption.Text):toBe("Updated")
				expect(caption.Visible):toBe(true)
				stop()
			end,
		})
		it("keeps the checkbox image asset through activation and theme changes", {
			id = "native_inputs::native input controls::keeps the checkbox image asset through activation and theme changes",
			run = function()
				local value = Compose.cell(false)
				local theme = Compose.cell(Facet.themes.neutralPackage())
				local node, stop = world(function(UI: FacetControls)
					local props: InputProps.ToggleCellProps =
						{ label = "Club", presentation = "checkbox" :: "checkbox", value = value }
					return UI.Toggle(props)
				end, function()
					return { theme = theme }
				end)
				local mark = find(node, "Check")
				expect(mark.Image):toBe(Facet.themes.resolveIcon(theme:peek(), "checkmark"))
				node.Activated:Fire()
				expect(value:peek()):toBe(true)
				expect(mark.Visible):toBe(true)
				for _, themeModule in
					{
						require("../examples/themes/glossy_mobile"),
						require("../examples/themes/fantasy_parchment"),
						require("../examples/themes/scifi_hud"),
					}
				do
					local package = themeModule.build(Facet.themes)
					theme:set(package)
					expect(mark.Image):toBe(Facet.themes.resolveIcon(theme:peek(), "checkmark"))
					expect(mark.Image ~= ""):toBe(true)
					node.Activated:Fire()
					node.Activated:Fire()
					expect(mark.Visible):toBe(true)
				end
				stop()
			end,
		})

		it("finishes an activation that removes its own Button without reading released state", {
			id = "native_inputs::native input controls::finishes an activation that removes its own Button without reading released state",
			run = function()
				local shown = Compose.cell(true)
				local presses = 0
				local node, stop = world(function(UI: FacetControls, _engine, runtime)
					return Facet.host(runtime).Frame({
						Compose.show(shown, function()
							local allowed = Compose.formula(function(use: Use)
								return use(shown)
							end)
							return UI.Button "Dismiss" {
								label = "Dismiss",
								enabled = allowed,
								onActivate = function()
									presses += 1
									shown:set(false)
								end,
							}
						end),
					})
				end)
				local button = find(node, "Dismiss")
				button.Activated:Fire()
				expect(presses):toBe(1)
				expect((find(node, "Dismiss"))):toBe(nil)
				stop()
			end,
		})

		it("uses native properties and events and releases them with its Compose owner", {
			id = "native_inputs::native input controls::uses native properties and events and releases them with its Compose owner",
			run = function()
				local value, enabled = Compose.cell("Before"), Compose.cell(true)
				local activated, nativeEvent = 0, 0
				local node, stop = world(function(UI: FacetControls)
					return UI.Button "Continue" {
						label = value,
						enabled = enabled,
						Attributes = { task = "continue" } :: FixtureEngineTypes.Attributes,
						onActivate = function()
							activated += 1
						end,
						MouseEnter = function()
							nativeEvent += 1
						end,
					}
				end)
				expect(node.Text):toBe("Before")
				expect((node:GetAttribute("task"))):toBe("continue")
				value:set("After")
				expect(node.Text):toBe("After")
				expect((find(node, "Label"))):toBe(nil)
				node.Text = "Native text"
				expect(node.Text):toBe("Native text")
				node.Activated:Fire()
				node.MouseEnter:Fire()
				enabled:set(false)
				node.Activated:Fire()
				expect(activated):toBe(1)
				expect(nativeEvent):toBe(1)
				expect(node.Interactable):toBe(false)
				stop()
				expect((engineLib.connections(node.Activated))):toBe(0)
				expect((engineLib.connections(node.MouseEnter))):toBe(0)
			end,
		})

		it("keeps Toggle requests controlled and clears a writable mixed state", {
			id = "native_inputs::native input controls::keeps Toggle requests controlled and clears a writable mixed state",
			run = function()
				local value, mixed = Compose.cell(false), Compose.cell(true)
				local node, stop = world(function(UI: FacetControls)
					local props: InputProps.ToggleCellProps = {
						value = value,
						mixed = mixed,
						presentation = "checkbox" :: "checkbox",
						label = "Enabled",
					}
					return UI.Toggle(props)
				end)
				node.Activated:Fire()
				expect((value:peek())):toBe(true)
				expect((mixed:peek())):toBe(false)
				stop()
				local request
				node, stop = world(function(UI: FacetControls)
					local props: InputProps.ToggleCellProps = {
						value = value,
						label = "Controlled",
						onChange = function(nextValue)
							request = nextValue
						end,
					}
					return UI.Toggle(props)
				end)
				node.Activated:Fire()
				expect(request):toBe(false)
				expect((value:peek())):toBe(true)
				stop()
			end,
		})

		it("keeps Toggle native eligibility semantics and theme tags synchronized with one ref delivery", {
			id = "native_inputs::native input controls::keeps Toggle native eligibility semantics and theme tags synchronized with one ref delivery",
			run = function()
				local value, enabled, busy = Compose.cell(true), Compose.cell(true), Compose.cell(false)
				local role, appearance, size, name =
					Compose.cell("default" :: "cancel" | "default" | "destructive" | "onIndicator"),
					Compose.cell("standard"),
					Compose.cell("regular" :: "compact" | "large" | "regular" | "xsmall"),
					Compose.cell("Ready")
				local references, changes = 0, 0
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.ToggleCellProps = {
						value = value,
						enabled = enabled,
						busy = busy,
						role = role,
						appearance = appearance,
						controlSize = size,
						name = name,
						ref = function()
							references += 1
						end,
						onChange = function(nextValue)
							changes += 1
							value:set(nextValue)
						end,
					}
					return UI.Toggle(props)
				end)
				expect(references):toBe(1)
				expect((node:GetAttribute("selected"))):toBe(true)
				expect((node:HasTag("facet-selected"))):toBe(true)
				role:set("destructive")
				appearance:set("emphasis")
				size:set("large")
				name:set("Confirm")
				expect((node:HasTag("facet-role-default"))):toBe(false)
				expect((node:HasTag("facet-role-destructive"))):toBe(true)
				expect((node:HasTag("facet-accent"))):toBe(true)
				expect((node:GetAttribute("role"))):toBe("destructive")
				expect((node:GetAttribute("appearance"))):toBe("emphasis")
				expect((node:GetAttribute("controlSize"))):toBe("large")
				expect((node:GetAttribute("label"))):toBe("Confirm")
				busy:set(true)
				expect(node.Interactable):toBe(false)
				expect((node:HasTag("facet-busy"))):toBe(true)
				expect((node:HasTag("facet-disabled"))):toBe(true)
				node.Activated:Fire()
				expect(changes):toBe(0)
				busy:set(false)
				node.Activated:Fire()
				expect(changes):toBe(1)
				expect((node:GetAttribute("selected"))):toBe(false)
				expect((node:HasTag("facet-selected"))):toBe(false)
				for _ = 1, 60 do
					engine.heartbeat:Fire(1 / 60)
				end
				expect(find(node, "Mark").Position.X.Scale):toBeCloseTo(0.3, 1e-4)
				enabled:set(false)
				expect(node.Selectable):toBe(false)
				node.Activated:Fire()
				expect(changes):toBe(1)
				stop()
			end,
		})

		it("distinguishes edits from external model updates and disconnects observation", {
			id = "native_inputs::native input controls::distinguishes edits from external model updates and disconnects observation",
			run = function()
				local value = Compose.cell("First")
				local edits: { string } = {}
				local commits: { { string } } = {}
				local node, stop = world(function(UI: FacetControls)
					local props: InputProps.TextInputCellProps = {
						value = value,
						onChange = function(text)
							value:set(text)
							table.insert(edits, text)
						end,
						onCommit = function(text: string, reason: "focusLost" | "submit")
							table.insert(commits, { text, reason })
						end,
					}
					return UI.TextInput(props)
				end)
				value:set("External")
				expect(node.Text):toBe("External")
				expect(#edits):toBe(0)
				node:CaptureFocus()
				node.Text = "User"
				expect((value:peek())):toBe("User")
				expect(#edits):toBe(1)
				value:set("Model while focused")
				expect(node.Text):toBe("Model while focused")
				expect(#edits):toBe(1)
				node:ReleaseFocus(true)
				expect(commits[1][1]):toBe("Model while focused")
				expect(commits[1][2]):toBe("submit")
				stop()
				expect((engineLib.connections(node:GetPropertyChangedSignal("Text")))):toBe(0)
			end,
		})

		it("limits UTF-8 characters, rejects validation and restores an edit on cancel", {
			id = "native_inputs::native input controls::limits UTF-8 characters, rejects validation and restores an edit on cancel",
			run = function()
				local value, edits, canceled = Compose.cell("old"), 0, 0
				local node, stop = world(function(UI: FacetControls)
					local props: InputProps.TextInputCellProps = {
						value = value,
						maxLength = 3,
						validate = function(text)
							return if text == "bad" then nil else text
						end,
						onChange = function(text)
							value:set(text)
							edits += 1
						end,
						onCancel = function()
							canceled += 1
						end,
					}
					return UI.TextInput(props)
				end)
				node:CaptureFocus()
				node.Text = "é🙂好x"
				expect((value:peek())):toBe("é🙂好")
				expect(node.Text):toBe("é🙂好")
				node.Text = "bad"
				expect((value:peek())):toBe("é🙂好")
				expect(node.Text):toBe("é🙂好")
				expect(edits):toBe(1)
				find(node.Parent, "Cancel").Pressed:Fire()
				expect((value:peek())):toBe("old")
				expect(node.Text):toBe("old")
				expect(canceled):toBe(1)
				expect((node:IsFocused())):toBe(false)
				stop()
			end,
		})

		it("commits and formats finite numeric input, clamps out-of-range input and refuses a non-number", {
			id = "native_inputs::native input controls::commits and formats finite numeric input, clamps out-of-range input and refuses a non-number",
			run = function()
				local value, number, invalid = Compose.cell("2"), Compose.cell(2), Compose.cell(false)
				local commits = 0
				local reasons = {}
				local node, stop = world(function(UI: FacetControls)
					local props: InputProps.TextInputNumberCellProps = {
						value = value,
						numericValue = number,
						invalid = invalid,
						presentation = "number" :: "number",
						min = 1,
						max = 10,
						format = function(n)
							return string.format("%.1f", n)
						end,
						onCommit = function(committed, reason)
							commits += 1
							table.insert(reasons, `{committed}:{reason}`)
						end,
					}
					return UI.TextInput(props)
				end)
				node:CaptureFocus()
				node.Text = "7"
				node:ReleaseFocus(true)
				expect((number:peek())):toBe(7)
				expect((value:peek())):toBe("7.0")
				expect(node.Text):toBe("7.0")
				expect(commits):toBe(1)
				node:CaptureFocus()
				node.Text = "11"
				node:ReleaseFocus(true)
				expect((number:peek())):toBe(10)
				expect((value:peek())):toBe("10.0")
				expect((invalid:peek())):toBe(false)
				node:CaptureFocus()
				node.Text = "1e1"
				node:ReleaseFocus(true)
				expect((number:peek())):toBe(10)
				expect(commits):toBe(2)
				expect((invalid:peek())):toBe(true)
				expect((table.concat(reasons, " "))):toBe("7:submit 10:clamped")
				stop()
			end,
		})

		it("steps from the minimum, respects live stepping and gates all activation", {
			id = "native_inputs::native input controls::steps from the minimum, respects live stepping and gates all activation",
			run = function()
				local value, step, enabled = Compose.cell(5), Compose.cell(5), Compose.cell(true)
				local changes = 0
				local node, stop = world(function(UI: FacetControls)
					local props: InputProps.StepperCellProps = {
						value = value,
						min = 5,
						max = 25,
						step = step,
						enabled = enabled,
						onChange = function(nextValue)
							value:set(nextValue)
							changes += 1
						end,
					}
					return UI.Stepper(props)
				end)
				expect(find(node, "Increase"):FindFirstChild("LeadingIcon", true) ~= nil):toBe(true)
				expect(find(node, "Increase").Text):toBe("")
				expect((find(node, "Decrease"):GetAttribute("label"))):toBe("Decrease")
				local decreaseTitle = find(node, "Decrease"):FindFirstChild("Title", true)
				expect(decreaseTitle == nil or decreaseTitle.Text == ""):toBe(true)
				find(node, "Increase").Activated:Fire()
				expect((value:peek())):toBe(10)
				step:set(2)
				find(node, "Increase").Activated:Fire()
				expect((value:peek())):toBe(13)
				enabled:set(false)
				find(node, "Increase").Activated:Fire()
				expect((value:peek())):toBe(13)
				expect(changes):toBe(2)
				stop()
			end,
		})

		it("lets the native drag detector drive one bounded slider model and cancel", {
			id = "native_inputs::native input controls::lets the native drag detector drive one bounded slider model and cancel",
			run = function()
				local value, commits = Compose.cell(25), 0
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.SliderCellProps = {
						value = value,
						min = 0,
						max = 100,
						step = 5,
						onCommit = function()
							commits += 1
						end,
					}
					return UI.Slider(props)
				end)
				local track, drag = find(node, "Track"), find(node, "Drag")
				node.SelectionGained:Fire()
				engine.environment.poke(track, "AbsoluteSize", engine.types.Vector2.new(200, 44))
				engine.environment.poke(track, "AbsolutePosition", engine.types.Vector2.new(20, 0))
				drag.DragStart:Fire(engine.types.Vector2.new(164, 0))
				expect((value:peek())):toBe(75)
				drag.DragContinue:Fire(engine.types.Vector2.new(500, 0))
				expect((value:peek())):toBe(100)
				find(node.Parent, "Cancel").Pressed:Fire()
				expect((value:peek())):toBe(25)
				expect(commits):toBe(0)
				drag.DragStart:Fire(engine.types.Vector2.new(120, 0))
				drag.DragEnd:Fire()
				expect((value:peek())):toBe(50)
				expect(commits):toBe(1)
				stop()
			end,
		})

		it("supports clearing a rating and keeps read-only levels inert", {
			id = "native_inputs::native input controls::supports clearing a rating and keeps read-only levels inert",
			run = function()
				local value = Compose.cell(3)
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.RatingCellProps = { value = value }
					return UI.Rating(props)
				end)
				engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(100, 44))
				node.Activated:Fire({ Position = engine.types.Vector2.new(50, 0) })
				expect((value:peek())):toBe(0)
				node.Activated:Fire({ Position = engine.types.Vector2.new(90, 0) })
				expect((value:peek())):toBe(5)
				stop()
				node, stop = world(function(UI: FacetControls)
					local props: InputProps.LevelPickerReadOnlyProps = { value = value, readOnly = true }
					return UI.LevelPicker(props)
				end)
				node.Activated:Fire({ Position = engine.types.Vector2.new(10, 0) })
				expect((value:peek())):toBe(5)
				stop()
			end,
		})
		it("clears search fields and submits the on-screen keyboard only once", {
			id = "native_inputs::native input controls::clears search fields and submits the on-screen keyboard only once",
			run = function()
				local value, commits, changes = Compose.cell("search"), 0, 0
				local node, stop = world(function(UI: FacetControls)
					local props: InputProps.TextInputCellProps = {
						value = value,
						presentation = "search" :: "search",
						onChange = function(nextValue)
							value:set(nextValue)
							changes += 1
						end,
						onCommit = function()
							commits += 1
						end,
					}
					return UI.TextInput(props)
				end)
				local clear = find(node, "Clear")
				expect(clear.Visible):toBe(true)
				expect((clear:GetAttribute("label"))):toBe("Clear")
				expect(clear:FindFirstChild("LeadingIcon", true) ~= nil):toBe(true)
				expect((clear:FindFirstChild("Title", true))):toBeNil()
				expect(clear.Text):toBe("")
				expect(clear.Size.Y.Offset > 0 and clear.Size.Y.Offset < 36):toBe(true)
				expect((clear:HasTag("facet-shape-circle"))):toBe(true)
				clear.Activated:Fire()
				expect((value:peek())):toBe("")
				expect(clear.Visible):toBe(false)
				expect(changes):toBe(1)
				local field = find(node, "Field")
				field:CaptureFocus()
				field.Text = "find"
				field.ReturnPressedFromOnScreenKeyboard:Fire()
				expect(commits):toBe(1)
				expect((field:IsFocused())):toBe(false)
				stop()
			end,
		})

		it("repeats while held and cancels native frame subscriptions on disposal", {
			id = "native_inputs::native input controls::repeats while held and cancels native frame subscriptions on disposal",
			run = function()
				local activated = 0
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button {
						label = "Repeat",
						repeatDelay = 0.4,
						repeatInterval = 0.1,
						onActivate = function()
							activated += 1
						end,
					}
				end)
				local input = {
					UserInputType = engine.types.Enum.UserInputType.MouseButton1,
					KeyCode = engine.types.Enum.KeyCode:FromValue(0),
				}
				node.InputBegan:Fire(input)
				engine.heartbeat:Fire(0.4)
				engine.heartbeat:Fire(0.1)
				expect(activated):toBe(2)
				node.InputEnded:Fire(input)
				node.Activated:Fire()
				expect(activated):toBe(2)
				stop()
				engine.heartbeat:Fire(1)
				expect(activated):toBe(2)
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
			end,
		})
		it("cancels a held Button exactly once on destruction or owner disposal", {
			id = "native_inputs::native input controls::cancels a held Button exactly once on destruction or owner disposal",
			run = function()
				for _, destroy in { false, true } do
					for _, kind in { "MouseButton1", "Touch" } do
						local cancels, ups = 0, 0
						local node, stop, engine = world(function(UI: FacetControls)
							return UI.Button {
								label = "Hold",
								onPointerCancel = function()
									cancels += 1
								end,
								onPointerUp = function()
									ups += 1
								end,
							}
						end)
						node.InputBegan:Fire({
							UserInputType = engine.types.Enum.UserInputType:FromName(kind),
							KeyCode = engine.types.Enum.KeyCode:FromName("Unknown"),
						})
						if destroy then
							node:Destroy()
						else
							stop()
						end
						expect(cancels):toBe(1)
						expect(ups):toBe(0)
						stop()
						expect(cancels):toBe(1)
					end
				end
			end,
		})

		it("reports a pointer cancel when onPointerCancel is the only pointer option", {
			id = "native_inputs::native input controls::reports a pointer cancel when onPointerCancel is the only pointer option",
			run = function()
				local cancels = 0
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button "Hold" {
						label = "Hold",
						onPointerCancel = function()
							cancels += 1
						end,
					}
				end)
				node.InputBegan:Fire({
					UserInputType = engine.types.Enum.UserInputType.MouseButton1,
					KeyCode = engine.types.Enum.KeyCode:FromValue(0),
				})
				node.MouseLeave:Fire()
				expect(cancels):toBe(1)
				node.MouseLeave:Fire()
				expect(cancels):toBe(1)
				stop()
			end,
		})

		it("follows GuiService.ReducedMotionEnabled for pop, validation pulse and busy dots", {
			id = "native_inputs::native input controls::follows GuiService.ReducedMotionEnabled for pop, validation pulse and busy dots",
			run = function()
				local gui: GuiService
				local busy, value, number = Compose.cell(false), Compose.cell("2"), Compose.cell(2)
				local root, stop, engine = world(function(UI: FacetControls, engine, runtime)
					local amount: InputProps.TextInputNumberCellProps = {
						value = value,
						numericValue = number,
						presentation = "number",
						max = 10,
					}
					return Facet.host(runtime).Frame({
						UI.Button "Pop" { label = "Pop", pop = true, busy = busy, onActivate = function() end },
						UI.TextInput "Amount"(amount),
					})
				end, function(engine)
					gui = (engine.new("GuiService") :: unknown) :: GuiService
					engine.environment.poke(VerifyRoblox.assertInstance(gui), "ReducedMotionEnabled", true)
					return { guiService = gui, services = { GuiService = gui } }
				end)
				local button, field = find(root, "Pop"), find(root, "Amount")
				local scale = button:FindFirstChildWhichIsA("UIScale", true)
				button.Activated:Fire()
				engine.heartbeat:Fire(0.1)
				expect(scale.Scale):toBe(1)
				field:CaptureFocus()
				field.Text = "11"
				field:ReleaseFocus(true)
				engine.heartbeat:Fire(0.08)
				expect(find(field, "ValidationPulse").Scale):toBe(1)
				busy:set(true)
				engine.heartbeat:Fire(0.3)
				expect(find(button, "Dot1").BackgroundTransparency):toBe(0)
				busy:set(false)
				engine.environment.poke(VerifyRoblox.assertInstance(gui), "ReducedMotionEnabled", false)
				button.Activated:Fire()
				engine.heartbeat:Fire(0.1)
				expect(scale.Scale > 1):toBe(true)
				stop()
			end,
		})

		it("does not commit a number TextInput that its parse callback disables", {
			id = "native_inputs::native input controls::does not commit a number TextInput that its parse callback disables",
			run = function()
				local value, number, enabled, commits = Compose.cell("2"), Compose.cell(2), Compose.cell(true), 0
				local node, stop = world(function(UI: FacetControls)
					local props: InputProps.TextInputNumberCellProps = {
						value = value,
						numericValue = number,
						presentation = "number" :: "number",
						enabled = enabled,
						parse = function(text)
							enabled:set(false)
							return tonumber(text)
						end,
						onCommit = function()
							commits += 1
						end,
					}
					return UI.TextInput "Amount"(props)
				end)
				node:CaptureFocus()
				node.Text = "5"
				node:ReleaseFocus(true)
				expect(commits):toBe(0)
				expect((number:peek())):toBe(2)
				stop()
			end,
		})

		it("accepts a readable Button corners value and follows it", {
			id = "native_inputs::native input controls::accepts a readable Button corners value and follows it",
			run = function()
				local corners = Compose.cell("square" :: "pill" | "square")
				local node, stop = world(function(UI: FacetControls)
					return UI.Button "Corners" { label = "Corners", corners = corners }
				end)
				local corner = node:FindFirstChildWhichIsA("UICorner")
				expect(corner.CornerRadius.Scale):toBe(0)
				corners:set("pill")
				expect(corner.CornerRadius.Scale):toBe(1)
				stop()
				expect(function()
					world(function(UI: FacetControls)
						return UI.Button({ Name = "Corners", label = "Corners", corners = "round" } :: any)
					end)
				end):toThrow()
			end,
		})

		it("edits a controlled map field without duplicating durable state", {
			id = "native_inputs::native input controls::edits a controlled map field without duplicating durable state",
			run = function()
				local notes = Compose.cell({ item = "saved" })
				local requests = 0
				local node, stop = world(function(UI: FacetControls)
					local props: InputProps.TextInputRequestProps = {
						value = function(use: Use)
							return use(notes).item
						end,
						onChange = function(value)
							requests += 1
							if value ~= "rejected" then
								notes:set({ item = value })
							end
						end,
					}
					return UI.TextInput(props)
				end)
				node:CaptureFocus()
				node.Text = "updated"
				expect(notes:peek().item):toBe("updated")
				expect(requests):toBe(1)
				node.Text = "rejected"
				expect(node.Text):toBe("updated")
				notes:set({ item = "external" })
				expect(requests):toBe(2)
				expect(node.Text):toBe("external")
				find(node.Parent, "Cancel").Pressed:Fire()
				expect(notes:peek().item):toBe("saved")
				expect(requests):toBe(3)
				stop()
			end,
		})
		it("does not mutate writable controlled models before callbacks accept requests", {
			id = "native_inputs::native input controls::does not mutate writable controlled models before callbacks accept requests",
			run = function()
				local value = Compose.cell(3)
				local requested: number | string | nil = nil
				local node, stop = world(function(UI: FacetControls)
					local props: InputProps.StepperCellProps = {
						value = value,
						min = 0,
						max = 10,
						onChange = function(nextValue)
							requested = nextValue
						end,
					}
					return UI.Stepper(props)
				end)
				find(node, "Increase").Activated:Fire()
				expect(requested):toBe(4)
				expect((value:peek())):toBe(3)
				stop()
				local text = Compose.cell("accepted")
				node, stop = world(function(UI: FacetControls)
					local props: InputProps.TextInputCellProps = {
						value = text,
						onChange = function(nextValue)
							requested = nextValue
						end,
					}
					return UI.TextInput(props)
				end)
				node:CaptureFocus()
				node.Text = "rejected"
				expect(requested):toBe("rejected")
				expect((text:peek())):toBe("accepted")
				expect(node.Text):toBe("accepted")
				stop()
			end,
		})
		it("owns busy animation only while visible and suppresses busy activation", {
			id = "native_inputs::native input controls::owns busy animation only while visible and suppresses busy activation",
			run = function()
				local busy, actions = Compose.cell(false), 0
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button {
						label = "Loading",
						busy = busy,
						onActivate = function()
							actions += 1
						end,
					}
				end)
				expect((find(node, "Busy"))):toBe(nil)
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				for _ = 1, 3 do
					busy:set(true)
					expect(find(node, "Busy") ~= nil):toBe(true)
					expect((engineLib.connections(engine.heartbeat))):toBe(1)
					node.Activated:Fire()
					expect(node.Selectable):toBe(false)
					busy:set(false)
					expect((find(node, "Busy"))):toBe(nil)
					expect((engineLib.connections(engine.heartbeat))):toBe(0)
				end
				expect(actions):toBe(0)
				node.Activated:Fire()
				expect(actions):toBe(1)
				stop()
			end,
		})

		it("keeps pop and rejection scales below stable layout slots", {
			id = "native_inputs::native input controls::keeps pop and rejection scales below stable layout slots",
			run = function()
				local invalid = Compose.cell(false)
				local gui: GuiService
				local node, stop, engine = world(function(UI: FacetControls, engine, runtime)
					local Host = Facet.host(runtime)
					return Host.Frame {
						UI.Button "Pop" { label = "Pop", pop = true, onActivate = function() end },
						UI.TextInput "Field" { value = Compose.cell("abc"), invalid = invalid },
					}
				end, function(engine)
					gui = (engine.new("GuiService") :: unknown) :: GuiService
					return { services = { GuiService = gui } }
				end)
				local button, field = find(node, "Pop"), find(node, "Field")
				engine.environment.poke(button, "AbsoluteSize", engine.types.Vector2.new(80, 44))
				engine.environment.poke(field, "AbsoluteSize", engine.types.Vector2.new(120, 44))
				local beforeButton, beforeField = button.Size, field.Size
				gui.SelectedObject = button
				button.Activated:Fire()
				invalid:set(true)
				engine.heartbeat:Fire(0.08)
				expect(button:FindFirstChildWhichIsA("UIScale")):toBe(nil)
				expect(field:FindFirstChildWhichIsA("UIScale")):toBe(nil)
				expect(find(button, "FeedbackPaint"):FindFirstChild("Pop").Scale > 1):toBe(true)
				expect(find(field, "FeedbackPaint"):FindFirstChild("ValidationPulse").Scale < 1):toBe(true)
				expect(button.Size):toBe(engine.types.UDim2.fromOffset(80, 44))
				expect(field.Size):toBe(engine.types.UDim2.fromOffset(120, 44))
				gui.SelectedObject = nil
				engine.heartbeat:Fire(1)
				expect(gui.SelectedObject):toBe(nil)
				expect(button.Size):toBe(beforeButton)
				expect(field.Size):toBe(beforeField)
				stop()
				expect(engineLib.connections(engine.heartbeat)):toBe(0)
			end,
		})

		it("styles pop feedback paint with the control's tags while it moves", {
			id = "native_inputs::native input controls::styles pop feedback paint with the control's tags while it moves",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls, engine, runtime)
					local Host = Facet.host(runtime)
					return Host.Frame {
						UI.Button "Pop" { label = "Pop", pop = true, onActivate = function() end },
					}
				end)
				local button = find(node, "Pop")
				engine.environment.poke(button, "AbsoluteSize", engine.types.Vector2.new(80, 44))
				button:AddTag("game-round")
				local paint = find(button, "FeedbackPaint")
				expect(paint:HasTag("facet-button")):toBe(false)
				button.Activated:Fire()
				engine.heartbeat:Fire(0.06)
				engine.heartbeat:Fire(0.02)
				expect(paint:FindFirstChild("Pop").Scale > 1):toBe(true)
				local function sorted(tags: { string }): string
					table.sort(tags)
					return table.concat(tags, ",")
				end
				expect(sorted(paint:GetTags())):toBe(sorted(button:GetTags()))
				expect(paint:HasTag("game-round")):toBe(true)
				button:RemoveTag("game-round")
				engine.heartbeat:Fire(0.02)
				expect(paint:HasTag("game-round")):toBe(false)
				engine.heartbeat:Fire(1)
				expect(paint.Visible):toBe(false)
				expect(#paint:GetTags()):toBe(0)
				stop()
			end,
		})

		it("restarts Compose pop feedback and obeys live reduced motion", {
			id = "native_inputs::native input controls::restarts Compose pop feedback and obeys live reduced motion",
			run = function()
				local reduced = Compose.cell(false)
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button { label = "Pop", pop = true, onActivate = function() end }
				end, function()
					return {
						motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
							return if use(reduced) then "none" else "normal"
						end) :: unknown) :: MotionLevel,
					}
				end)
				local scale = find(node, "Pop")
				expect(scale.Scale):toBe(1)
				node.Activated:Fire()
				engine.heartbeat:Fire(0.1)
				expect(scale.Scale > 1):toBe(true)
				local current = scale.Scale
				node.Activated:Fire()
				expect(scale.Scale):toBeCloseTo(current, 1e-4)
				reduced:set(true)
				expect(scale.Scale):toBe(1)
				node.Activated:Fire()
				engine.heartbeat:Fire(1)
				expect(scale.Scale):toBe(1)
				stop()
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
			end,
		})

		it("recovers an automatic compact caption when its parent width returns", {
			id = "native_inputs::native input controls::recovers an automatic compact caption when its parent width returns",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls, engine, runtime)
					return runtime.constructors.Frame {
						Name = "Row",
						UI.Button "Sort" { label = "Sorting", compactLabel = "Srt" },
					}
				end)
				local sort = find(node, "Sort")
				local measure = find(sort, "FullLabelMeasure")
				engine.environment.poke(measure, "TextBounds", engine.types.Vector2.new(45, 18))
				engine.environment.poke(sort, "AbsoluteSize", engine.types.Vector2.new(43, 44))
				for _ = 1, 3 do
					engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(60, 44))
					expect(sort.Text):toBe("Srt")
					engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(300, 44))
					expect(sort.Text):toBe("Sorting")
					expect(sort.AbsoluteSize.X):toBe(43)
				end
				stop()
			end,
		})
		it("chooses compact button text from native measurements and restores the full caption", {
			id = "native_inputs::native input controls::chooses compact button text from native measurements and restores the full caption",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button { label = "Continue to checkout", compactLabel = "Continue" }
				end)
				local measure = find(node, "FullLabelMeasure")
				engine.environment.poke(node.Parent, "AbsoluteSize", engine.types.Vector2.zero)
				engine.environment.poke(measure, "TextBounds", engine.types.Vector2.new(180, 20))
				engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(110, 44))
				expect(node.Text):toBe("Continue")
				engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(240, 44))
				expect(node.Text):toBe("Continue to checkout")
				stop()
			end,
		})

		it("compact captions resolve native width and glyph bounds before the next frame", function(_own, t)
			local engine = engineLib.new()
			local runtime = Roblox.createRuntime(engine)
			local ctx = context(Compose, runtime, { types = engine.types })
			local UI = ({} :: unknown) :: SharedTypes.Controls
			local stale = Compose.cell(engine.types.Vector2.zero)
			ctx.observe.AbsoluteSize = function()
				return stale
			end
			ctx.observe.TextBounds = function()
				return stale
			end
			register(ctx, UI)
			local button: TextButton? = nil
			local stop = runtime.mount(function()
				button = UI.Button {
					label = "Continue to checkout",
					compactLabel = "Continue",
					Size = engine.types.UDim2.fromOffset(110, 44),
					AutomaticSize = engine.types.Enum.AutomaticSize.None,
				}
				return button
			end, engine.new("ScreenGui"))
			local node = assert(button)
			local measure = assert(node:FindFirstChild("FullLabelMeasure"))
			local glyphs = measure
			local box = node
			engine.environment.poke(
				VerifyRoblox.assertInstance(glyphs),
				"TextBounds",
				engine.types.Vector2.new(180, 20)
			)
			engine.environment.poke(VerifyRoblox.assertInstance(box), "AbsoluteSize", engine.types.Vector2.new(110, 44))
			t:expect(node.Text):toBe("Continue")
			engine.environment.poke(VerifyRoblox.assertInstance(box), "AbsoluteSize", engine.types.Vector2.new(240, 44))
			t:expect(node.Text):toBe("Continue to checkout")
			engine.environment.poke(
				VerifyRoblox.assertInstance(glyphs),
				"TextBounds",
				engine.types.Vector2.new(300, 20)
			)
			t:expect(node.Text):toBe("Continue")
			stop()
			runtime:dispose()
			t:expect(engine.census().connections):toBe(0)
		end)

		it("deduplicates shortcut/default bindings and yields shortcuts during native text editing", {
			id = "native_inputs::native input controls::deduplicates shortcut/default bindings and yields shortcuts during native text editing",
			run = function()
				local editing, actions = false, 0
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button {
						label = "Default",
						shortcut = { keyCode = "Return" },
						dialogAction = "default" :: "default",
						onActivate = function()
							actions += 1
						end,
					}
				end, function(engine)
					local input = (engine.new("UserInputService") :: unknown) :: UserInputService
					engine.environment.fakeOn(input, "GetLastInputType", function()
						return engine.types.Enum.UserInputType.MouseMovement
					end)
					engine.environment.fakeOn(input, "IsGamepadButtonDown", function()
						return false
					end)
					engine.environment.fakeOn(input, "IsKeyDown", function()
						return false
					end)
					engine.environment.fakeOn(input, "GetNavigationGamepads", function()
						return {}
					end)
					engine.environment.fakeOn(input, "GetFocusedTextBox", function()
						return if editing then {} else nil
					end)
					return {
						services = {
							UserInputService = input,
						},
					}
				end)
				local action = find(node.Parent, "Shortcut")
				expect(#action:GetChildren()):toBe(1)
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				expect(actions):toBe(1)
				editing = true
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				expect(actions):toBe(1)
				stop()
				expect((engineLib.connections(action.Pressed))):toBe(0)
			end,
		})

		it("binds one shortcut action to the key and the dialog button and activates once per press", {
			id = "native_inputs::native input controls::binds one shortcut action to the key and the dialog button and activates once per press",
			run = function()
				local actions = 0
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button {
						label = "Close",
						shortcut = { keyCode = "K" },
						dialogAction = "cancel" :: "cancel",
						onActivate = function()
							actions += 1
						end,
					}
				end)
				local action = find(node.Parent, "Shortcut")
				local keys = {}
				for _, binding in action:GetChildren() do
					table.insert(keys, binding.KeyCode.Name)
				end
				table.sort(keys)
				expect((table.concat(keys, ","))):toBe("ButtonB,K")
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				expect(actions):toBe(1)
				node.Activated:Fire()
				expect(actions):toBe(2)
				stop()
			end,
		})

		it("clamps a fixed-size button's icon to its content box and never to zero", {
			id = "native_inputs::native input controls::clamps a fixed-size button's icon to its content box and never to zero",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls, host, runtime)
					return Facet.host(runtime).Frame({
						UI.Button "Tight" {
							icon = "rbxassetid://1",
							Size = host.types.UDim2.fromOffset(20, 20),
							AutomaticSize = host.types.Enum.AutomaticSize.None,
						},
						UI.Button "Free" { icon = "rbxassetid://1", label = "Free" },
					})
				end)
				local tight = find(node, "Tight")
				local content = find(tight, "Content")
				local glyph = find(tight, "LeadingIcon")
				local limit = glyph:FindFirstChildWhichIsA("UISizeConstraint")
				expect(limit ~= nil):toBe(true)
				local aspect = glyph:FindFirstChildWhichIsA("UIAspectRatioConstraint")
				expect(aspect.AspectRatio):toBe(1)
				expect(aspect.AspectType):toBe(engine.types.Enum.AspectType.ScaleWithParentSize)
				engine.environment.poke(content, "AbsoluteSize", engine.types.Vector2.new(4, 6))
				expect(limit.MinSize.X):toBe(1)
				expect(limit.MinSize.Y):toBe(1)
				engine.environment.poke(content, "AbsoluteSize", engine.types.Vector2.new(0, 0))
				expect(limit.MinSize.X):toBe(1)
				expect(content.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.None)
				expect((find(find(node, "Free"), "LeadingIcon"):FindFirstChildWhichIsA("UISizeConstraint"))):toBe(nil)
				stop()
			end,
		})

		it("reserves nonzero icon content inside theme insets", {
			id = "native_inputs::native input controls::reserves nonzero icon content inside theme insets",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls, host)
					return UI.Button "Tight" {
						icon = "rbxassetid://1",
						Size = host.types.UDim2.fromOffset(20, 20),
						AutomaticSize = host.types.Enum.AutomaticSize.None,
					}
				end, function()
					return {
						theme = fixtureTheme({
							identity = { id = "native-input-fixture" },
							chrome = {
								control = {
									kind = "native",
									contentInsets = { left = 12, right = 13, top = 14, bottom = 15 },
								},
							},
						}),
					}
				end)
				local floor = node:FindFirstChild("ContentFloor")
				expect(floor.MinSize):toBe(engine.types.Vector2.new(26, 30))
				stop()
			end,
		})

		it("blocks background held repeats when a Compose-owned modal becomes active", {
			id = "native_inputs::native input controls::blocks background held repeats when a Compose-owned modal becomes active",
			run = function()
				local actions = 0
				local node, stop, engine, runtime, ctx = world(function(UI: FacetControls)
					return UI.Button {
						label = "Repeat",
						repeatInterval = 0.1,
						onActivate = function()
							actions += 1
						end,
					}
				end)
				node.InputBegan:Fire({
					UserInputType = engine.types.Enum.UserInputType.MouseButton1,
					KeyCode = engine.types.Enum.KeyCode:FromValue(0),
				})
				engine.heartbeat:Fire(0.4)
				expect(actions):toBe(1)
				local modal = engine.new("Frame")
				modal.Parent = node.Parent
				ctx.modalScopes:set({ modal })
				engine.heartbeat:Fire(0.4)
				expect(actions):toBe(1)
				ctx.modalScopes:set({})
				engine.heartbeat:Fire(0.4)
				expect(actions):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		it("taps a selected level back to zero and scrubs against the visible marks", {
			id = "native_inputs::native input controls::taps a selected level back to zero and scrubs against the visible marks",
			run = function()
				local value = Compose.cell(1)
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.LevelPickerCellProps = { value = value, count = 3, allowZero = true }
					return UI.LevelPicker(props)
				end)
				local V = engine.types.Vector2
				engine.environment.poke(node, "AbsolutePosition", V.new(709, 0))
				engine.environment.poke(node, "AbsoluteSize", V.new(156, 44))
				local marks = find(node, "Marks")
				engine.environment.poke(marks, "AbsolutePosition", V.new(755, 0))
				engine.environment.poke(marks, "AbsoluteSize", V.new(64, 20))
				local detector = find(node, "Scrub")
				detector.DragStart:Fire(V.new(765, 0))
				detector.DragEnd:Fire(V.new(765, 0))
				node.Activated:Fire({ Position = engine.types.Vector3.new(765, 0, 0) })
				expect(value:peek()):toBe(0)
				for i, x in { 765, 787, 809 } do
					detector.DragStart:Fire(V.new(x, 0))
					expect(value:peek()):toBe(i)
					detector.DragContinue:Fire(V.new(810, 0))
					detector.DragEnd:Fire(V.new(809, 0))
					expect(value:peek()):toBe(3)
				end
				stop()
			end,
		})

		it("keeps level marks inert with one focus target and a cancellable native scrub", {
			id = "native_inputs::native input controls::keeps level marks inert with one focus target and a cancellable native scrub",
			run = function()
				local value = Compose.cell(2)
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.LevelPickerCellProps = { value = value, count = 5 }
					return UI.LevelPicker(props)
				end)
				engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(100, 44))
				local selectable = if node.Selectable then 1 else 0
				for _, child in node:GetDescendants() do
					if child:IsA("GuiObject") and child.Selectable then
						selectable += 1
					end
				end
				expect(selectable):toBe(1)
				expect(find(node, "Level3").ClassName):toBe("Frame")
				expect((find(node.Parent, "FacetIncrease"))):toBe(nil)
				node.SelectionGained:Fire()
				expect(find(node.Parent, "FacetIncrease").Enabled):toBe(true)
				find(node, "Scrub").DragStart:Fire(engine.types.Vector2.new(90, 0))
				expect((value:peek())):toBe(5)
				find(node, "Scrub").DragContinue:Fire(engine.types.Vector2.new(10, 0))
				expect((value:peek())):toBe(1)
				find(node.Parent, "Cancel").Pressed:Fire()
				expect((value:peek())):toBe(2)
				stop()
			end,
		})

		it("updates explicit shortcut alternatives without owning input bindings", {
			id = "native_inputs::native input controls::updates explicit shortcut alternatives without owning input bindings",
			run = function()
				local tracking: FixtureBridge.Tracking
				local separator, chords = Compose.cell(" or "), Compose.cell({ { "Ctrl", "K" }, { "F1" } })
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.ShortcutHintKeysProps = { keys = chords, separator = separator }
					return UI.ShortcutHint(props)
				end, function(_, fixture)
					tracking = fixture.track()
					return {}
				end)
				expect(node.Text):toBe("Ctrl+K or F1")
				separator:set("ou")
				expect(node.Text):toBe("Ctrl+K ou F1")
				separator:set(" / ")
				chords:set({ { "Shift", "P" } })
				expect(node.Text):toBe("Shift+P")
				for _, instance in tracking.created do
					expect(instance.ClassName == "InputAction" or instance.ClassName == "InputContext"):toBe(false)
				end
				tracking.stop()
				stop()
				expect(function()
					world(function(UI: FacetControls)
						local props: InputProps.ShortcutHintKeysProps = { keys = { { "" } } }
						return UI.ShortcutHint(props)
					end)
				end):toThrow()
			end,
		})

		it("borrows native preferred bindings and releases replaced hint observers", {
			id = "native_inputs::native input controls::borrows native preferred bindings and releases replaced hint observers",
			run = function()
				local action: InputAction
				local first: InputBinding
				local second: InputBinding
				local node, stop, engine = world(function(UI: FacetControls, engine)
					action, first, second =
						engine.new("InputAction"), engine.new("InputBinding"), engine.new("InputBinding")
					first.KeyCode, first.DisplayName = engine.types.Enum.KeyCode.F, ""
					second.KeyCode, second.DisplayName = engine.types.Enum.KeyCode.ButtonX, "Interact"
					engine.environment.poke(VerifyRoblox.assertInstance(action), "PreferredBinding", first)
					local props: InputProps.ShortcutHintActionProps = { action = action }
					return UI.ShortcutHint(props)
				end)
				expect(find(node, "Key").Text):toBe("F")
				first.DisplayName = "Use"
				expect(find(node, "Key").Text):toBe("Use")
				engine.environment.poke(VerifyRoblox.assertInstance(action), "PreferredBinding", second)
				expect(find(node, "Key").Text):toBe("Interact")
				expect((engineLib.connections(first:GetPropertyChangedSignal("DisplayName")))):toBe(0)
				engine.environment.poke(VerifyRoblox.assertInstance(action), "PreferredBinding", nil)
				expect((find(node, "Key"))):toBe(nil)
				expect((engineLib.connections(second:GetPropertyChangedSignal("DisplayName")))):toBe(0)
				stop()
				expect(engine.environment.isAlive(VerifyRoblox.assertInstance(action))):toBe(true)
				expect((engineLib.connections(action:GetPropertyChangedSignal("PreferredBinding")))):toBe(0)
			end,
		})

		it("hides a keyboard-only binding while the player uses a gamepad", {
			id = "native_inputs::native input controls::hides a keyboard-only binding while the player uses a gamepad",
			run = function()
				local action: InputAction
				local keyboard: InputBinding
				local pad: InputBinding
				local input: UserInputService
				local node, stop, engine = world(function(UI: FacetControls, engine)
					action, keyboard, pad =
						engine.new("InputAction"), engine.new("InputBinding"), engine.new("InputBinding")
					keyboard.KeyCode, keyboard.DisplayName = engine.types.Enum.KeyCode.Slash, "/"
					pad.KeyCode, pad.DisplayName = engine.types.Enum.KeyCode.ButtonY, "Search"
					engine.environment.poke(VerifyRoblox.assertInstance(action), "PreferredBinding", keyboard)
					local props: InputProps.ShortcutHintActionProps = { action = action }
					return UI.ShortcutHint(props)
				end, function(engine)
					input = (engine.new("UserInputService") :: unknown) :: UserInputService
					local service = VerifyRoblox.assertInstance(input)
					engine.environment.poke(service, "PreferredInput", engine.types.Enum.PreferredInput.Gamepad)
					engine.environment.poke(service, "GamepadEnabled", true)
					return { services = { UserInputService = input } }
				end)
				expect((find(node, "Key"))):toBe(nil)
				expect(node.BackgroundTransparency):toBe(1)
				engine.environment.poke(VerifyRoblox.assertInstance(action), "PreferredBinding", pad)
				expect(find(node, "Key").Text):toBe("Search")
				expect(node.BackgroundTransparency):toBe(0)
				local service = VerifyRoblox.assertInstance(input)
				engine.environment.poke(service, "PreferredInput", engine.types.Enum.PreferredInput.KeyboardAndMouse)
				engine.environment.poke(service, "GamepadEnabled", false)
				engine.environment.poke(VerifyRoblox.assertInstance(action), "PreferredBinding", keyboard)
				expect(find(node, "Key").Text):toBe("/")
				stop()
			end,
		})

		it("names whitespace and named keys instead of showing the layout character", {
			id = "native_inputs::native input controls::names whitespace and named keys instead of showing the layout character",
			run = function()
				local action: InputAction
				local binding: InputBinding
				local keyCodes: typeof(Enum.KeyCode)
				local node, stop, engine = world(function(UI: FacetControls, engine)
					action, binding = engine.new("InputAction"), engine.new("InputBinding")
					keyCodes = engine.types.Enum.KeyCode
					binding.KeyCode, binding.DisplayName = keyCodes.Space, ""
					engine.environment.poke(VerifyRoblox.assertInstance(action), "PreferredBinding", binding)
					local props: InputProps.ShortcutHintActionProps = { action = action }
					return UI.ShortcutHint(props)
				end, function(engine)
					local input = (engine.new("UserInputService") :: unknown) :: UserInputService
					engine.environment.fakeOn(input, "GetImageForKeyCode", function()
						return ""
					end)
					engine.environment.fakeOn(
						input,
						"GetStringForKeyCode",
						function(_self: unknown, code: EnumItem): string
							return if code.Name == "Space" then " " elseif code.Name == "Q" then "A" else ""
						end
					)
					return { services = { UserInputService = input } }
				end)
				expect(find(node, "Key").Text):toBe("Space")
				binding.KeyCode = keyCodes.LeftShift
				expect(find(node, "Key").Text):toBe("Shift")
				binding.KeyCode = keyCodes.Q
				expect(find(node, "Key").Text):toBe("A")
				stop()
			end,
		})

		it("inks a platform glyph with the cap text color, so a white console glyph reads on a light cap", {
			id = "native_inputs::native input controls::inks a platform glyph with the cap text color, so a white console glyph reads on a light cap",
			run = function()
				local node, stop = world(function(UI: FacetControls, engine)
					local action, binding = engine.new("InputAction"), engine.new("InputBinding")
					binding.KeyCode = engine.types.Enum.KeyCode.ButtonY
					engine.environment.poke(VerifyRoblox.assertInstance(action), "PreferredBinding", binding)
					local props: InputProps.ShortcutHintActionProps = { action = action }
					return UI.ShortcutHint(props)
				end, function(engine)
					local input = engine.new("UserInputService")
					input.GetImageForKeyCode = function(_self: unknown, code: EnumItem): string
						return if code.Name == "ButtonY"
							then "rbxasset://textures/ui/Controls/XboxController/ButtonY@2x.png"
							else ""
					end
					return { services = { UserInputService = input } }
				end)
				local glyph = find(node, "Glyph")
				expect(glyph.Image):toBe("rbxasset://textures/ui/Controls/XboxController/ButtonY@2x.png")
				expect(glyph:HasTag("facet-shortcut-glyph")):toBe(true)
				stop()
			end,
		})

		it("cap = false draws the keys or the platform glyph without the key cap", {
			id = "native_inputs::native input controls::cap = false draws the keys or the platform glyph without the key cap",
			run = function()
				local keys, stopKeys = world(function(UI: FacetControls)
					local props: InputProps.ShortcutHintKeysProps = { keys = { { "E" } }, cap = false }
					return UI.ShortcutHint(props)
				end)
				expect(keys.BackgroundTransparency):toBe(1)
				expect(keys:HasTag("facet-shortcut-hint-bare")):toBe(true)
				stopKeys()
				local glyph, stopGlyph = world(function(UI: FacetControls, engine)
					local action, binding = engine.new("InputAction"), engine.new("InputBinding")
					binding.KeyCode = engine.types.Enum.KeyCode.ButtonY
					engine.environment.poke(VerifyRoblox.assertInstance(action), "PreferredBinding", binding)
					local props: InputProps.ShortcutHintActionProps = { action = action, cap = false }
					return UI.ShortcutHint(props)
				end)
				expect(glyph.BackgroundTransparency):toBe(1)
				expect(glyph:HasTag("facet-shortcut-hint-bare")):toBe(true)
				stopGlyph()
				local capped, stopCapped = world(function(UI: FacetControls)
					local props: InputProps.ShortcutHintKeysProps = { keys = { { "E" } } }
					return UI.ShortcutHint(props)
				end)
				expect(capped.BackgroundTransparency):toBe(0)
				expect(capped:HasTag("facet-shortcut-hint-bare")):toBe(false)
				stopCapped()
			end,
		})

		it("keeps an authored circle axis dominant instead of fitting inside a zero box", {
			id = "native_inputs::native input controls::keeps an authored circle axis dominant instead of fitting inside a zero box",
			run = function()
				for _, case: { x: number, y: number, axis: "Width" | "Height" } in
					{ { x = 32, y = 0, axis = "Width" :: "Width" }, { x = 0, y = 72, axis = "Height" :: "Height" } } :: { { x: number, y: number, axis: "Width" | "Height" } }
				do
					local node, stop, engine = world(function(UI: FacetControls, engine)
						return UI.Button {
							label = "Close",
							shape = "circle" :: "circle",
							controlSize = "compact" :: "compact",
							Size = engine.types.UDim2.fromOffset(case.x, case.y),
						}
					end)
					local aspect = node:FindFirstChildWhichIsA("UIAspectRatioConstraint")
					expect(aspect.AspectRatio):toBe(1)
					expect(aspect.AspectType):toBe(engine.types.Enum.AspectType.ScaleWithParentSize)
					expect(aspect.DominantAxis):toBe(assert(engine.types.Enum.DominantAxis:FromName(case.axis)))
					expect(node.Size.X.Offset):toBe(case.x)
					expect(node.Size.Y.Offset):toBe(case.y)
					stop()
				end
				local node, stop, engine = world(function(UI: FacetControls, engine)
					return UI.Button {
						label = "Close",
						shape = "circle" :: "circle",
						Size = engine.types.UDim2.fromOffset(40, 40),
					}
				end)
				expect(node:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectType):toBe(
					engine.types.Enum.AspectType.FitWithinMaxSize
				)
				stop()
			end,
		})
		it("names a circle with a caption label inside the Button and respects disabled", {
			id = "native_inputs::native input controls::names a circle with a caption label inside the Button and respects disabled",
			run = function()
				local count, enabled = 0, Compose.cell(true)
				local node, stop = world(function(UI: FacetControls)
					return UI.Button {
						name = "Shop",
						icon = "view.grid",
						shape = "circle" :: "circle",
						caption = "Shop",
						enabled = enabled,
						onActivate = function()
							count += 1
						end,
					}
				end)
				local caption = find(node, "Caption")
				expect(caption.Text):toBe("Shop")
				expect(caption.ClassName):toBe("TextLabel")
				expect(caption.Parent):toBe(node)
				expect(node.ClipsDescendants):toBe(false)
				node.Activated:Fire()
				expect(count):toBe(1)
				enabled:set(false)
				node.Activated:Fire()
				expect(count):toBe(1)
				stop()
			end,
		})
		it("shows a Button's shortcut hint at the trailing edge only while the input has a binding", {
			id = "native_inputs::native input controls::shows a Button's shortcut hint at the trailing edge only while the input has a binding",
			run = function()
				local input: UserInputService
				local action: InputAction
				local PAD = "rbxasset://textures/ui/Controls/XboxController/ButtonX@2x.png"
				local function image(_self: unknown, code: EnumItem): string
					return if code.Name == "ButtonX" then PAD else ""
				end
				local function text(_self: unknown, code: EnumItem): string
					return if code.Name == "B" then "B" else ""
				end
				local node, stop, engine = world(function(UI: FacetControls, engine)
					action = (engine.new("InputAction") :: unknown) :: InputAction
					return UI.Button { label = "Boost", icon = "flag", shortcutHint = action }
				end, function(engine)
					input = (engine.new("UserInputService") :: unknown) :: UserInputService
					engine.environment.fakeOn(input, "GetImageForKeyCode", image)
					engine.environment.fakeOn(input, "GetStringForKeyCode", text)
					return { services = { UserInputService = input } }
				end)
				local P = engine.types.Enum.PreferredInput
				local function prefer(kind: EnumItem)
					engine.environment.poke((input :: unknown) :: VerifyRoblox.Instance, "PreferredInput", kind)
				end
				local function bind(binding: unknown)
					engine.environment.poke((action :: unknown) :: VerifyRoblox.Instance, "PreferredBinding", binding)
				end
				local binding = engine.new("InputBinding")
				binding.KeyCode = engine.types.Enum.KeyCode.ButtonX
				bind(binding)
				local content = find(node, "Content")
				local hint = find(node, "ShortcutHint")
				expect(hint.Parent):toBe(content)
				expect(hint:HasTag("facet-shortcut-hint-bare")):toBe(true)
				expect(find(content, "LeadingIcon") ~= nil):toBe(true)
				expect(find(content, "Title").Text):toBe("Boost")
				for _, child in content:GetChildren() do
					if child:IsA("GuiObject") and child ~= hint then
						expect(child.LayoutOrder < hint.LayoutOrder):toBe(true)
					end
				end
				prefer(P.Gamepad)
				expect(hint.Visible):toBe(true)
				expect(find(hint, "Glyph").Image):toBe(PAD)
				local key = engine.new("InputBinding")
				key.KeyCode = engine.types.Enum.KeyCode.B
				prefer(P.KeyboardAndMouse)
				bind(key)
				expect(hint.Visible):toBe(true)
				expect(find(hint, "Key").Text):toBe("B")
				expect(find(hint, "Glyph")):toBeNil()
				bind(binding)
				prefer(P.Touch)
				expect(hint.Visible):toBe(false)
				prefer(P.Gamepad)
				bind(nil)
				expect(hint.Visible):toBe(false)
				bind(binding)
				expect(hint.Visible):toBe(true)
				action.Enabled = false
				expect(hint.Visible):toBe(false)
				action.Enabled = true
				expect(hint.Visible):toBe(true)
				stop()

				local plain, stopPlain = world(function(UI: FacetControls)
					return UI.Button { label = "Boost" }
				end)
				expect(plain.Text):toBe("Boost")
				expect(find(plain, "ShortcutHint")):toBeNil()
				expect(find(plain, "Content")):toBeNil()
				stopPlain()

				expect(function()
					world(function(UI: FacetControls)
						return UI.Button { label = "Boost", shortcutHint = ("Boost" :: unknown) :: InputAction }
					end)
				end):toThrow("shortcutHint must be a native InputAction")
			end,
		})
		it("places a circle Button's shortcut hint on its rim beside the icon and caption", {
			id = "native_inputs::native input controls::places a circle Button's shortcut hint on its rim beside the icon and caption",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls, engine)
					return UI.Button {
						name = "Boost",
						icon = "flag",
						shape = "circle" :: "circle",
						caption = "Boost",
						shortcutHint = (engine.new("InputAction") :: unknown) :: InputAction,
					}
				end)
				local hint = find(node, "ShortcutHint")
				local rim = 0.5 + 0.5 * math.sqrt(0.5)
				expect(hint.Parent):toBe(node)
				expect(hint:HasTag("facet-button-outside")):toBe(true)
				expect(hint:HasTag("facet-shortcut-hint-bare")):toBe(true)
				expect(hint.AnchorPoint):toBe(engine.types.Vector2.new(0.5, 0.5))
				expect(math.abs(hint.Position.X.Scale - rim) < 1e-6):toBe(true)
				expect(math.abs(hint.Position.Y.Scale - rim) < 1e-6):toBe(true)
				expect(find(find(node, "Content"), "ShortcutHint")):toBeNil()
				expect(find(find(node, "Content"), "LeadingIcon") ~= nil):toBe(true)
				expect(find(node, "Caption"):HasTag("facet-button-outside")):toBe(true)
				expect(node.ClipsDescendants):toBe(false)
				stop()
			end,
		})
		it("shows numeric validation text with interruptible reduced-motion-aware feedback", {
			id = "native_inputs::native input controls::shows numeric validation text with interruptible reduced-motion-aware feedback",
			run = function()
				local value, number, reduced = Compose.cell("2"), Compose.cell(2), Compose.cell(false)
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.TextInputNumberCellProps = {
						value = value,
						numericValue = number,
						presentation = "number" :: "number",
						min = 1,
						max = 10,
					}
					return UI.TextInput(props)
				end, function()
					return {
						motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
							return if use(reduced) then "none" else "normal"
						end) :: unknown) :: MotionLevel,
					}
				end)
				engine.environment.poke(node, "TextBounds", engine.types.Vector2.new(20, 20))
				local label = find(node, "ValidationMessage")
				engine.environment.poke(label, "TextBounds", engine.types.Vector2.new(200, 18))
				node:CaptureFocus()
				node.Text = "1.2.3"
				node:ReleaseFocus(true)
				expect(label.Text):toBe("Enter a valid number.")
				expect(label.Visible):toBe(true)
				expect(node.Size.Y.Offset >= 54):toBe(true)
				engine.heartbeat:Fire(0.08)
				expect(find(node, "ValidationPulse").Scale < 1):toBe(true)
				reduced:set(true)
				expect(find(node, "ValidationPulse").Scale):toBe(1)
				node:CaptureFocus()
				node.Text = "3"
				node:ReleaseFocus(true)
				expect((number:peek())):toBe(3)
				expect(label.Visible):toBe(false)
				stop()
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
			end,
		})

		it("reflects external invalid state and rejects malformed invalid and numeric declarations", {
			id = "native_inputs::native input controls::reflects external invalid state and rejects malformed invalid and numeric declarations",
			run = function()
				local invalid, value = Compose.cell(false), Compose.cell("ready")
				local node, stop = world(function(UI: FacetControls)
					local props: InputProps.TextInputCellProps = { value = value, invalid = invalid }
					return UI.TextInput(props)
				end)
				invalid:set(true)
				expect(find(node, "ValidationMessage").Visible):toBe(true)
				invalid:set(false)
				expect(find(node, "ValidationMessage").Visible):toBe(false)
				stop()
				expect(function()
					world(function(UI: FacetControls)
						local construct = UI.TextInput
						return construct({ value = value, invalid = true } :: any)
					end)
				end):toThrow()
				expect(function()
					world(function(UI: FacetControls)
						local construct = UI.TextInput
						return construct({ value = value, presentation = "number" } :: any)
					end)
				end):toThrow()
			end,
		})

		it("honors every clear-button mode and ends disabled edits without a commit", {
			id = "native_inputs::native input controls::honors every clear-button mode and ends disabled edits without a commit",
			run = function()
				for _, mode in
					{ "never", "always", "whileEditing", "unlessEditing" } :: { "always" | "never" | "unlessEditing" | "whileEditing" }
				do
					local value, enabled, commits = Compose.cell("text"), Compose.cell(true), 0
					local node, stop = world(function(UI: FacetControls)
						local props: InputProps.TextInputCellProps = {
							value = value,
							enabled = enabled,
							clearButtonMode = mode :: "always" | "never" | "unlessEditing" | "whileEditing",
							onCommit = function()
								commits += 1
							end,
						}
						return UI.TextInput(props)
					end)
					local clear = find(node, "Clear")
					if mode == "never" then
						expect(clear):toBe(nil)
					else
						expect(clear.Visible):toBe(mode ~= "whileEditing")
					end
					node:CaptureFocus()
					if clear then
						expect(clear.Visible):toBe(mode ~= "unlessEditing")
					end
					expect(find(node.Parent, "FacetTextEditing").Enabled):toBe(true)
					enabled:set(false)
					expect((node:IsFocused())):toBe(false)
					expect(node.Selectable):toBe(false)
					expect(find(node.Parent, "FacetTextEditing").Enabled):toBe(false)
					expect(commits):toBe(0)
					if clear then
						expect(clear.Visible):toBe(false)
					end
					stop()
				end
			end,
		})
		it("removes keyed chips toward the next then previous native target and caller fallback", {
			id = "native_inputs::native input controls::removes keyed chips toward the next then previous native target and caller fallback",
			run = function()
				local items = Compose.cell({ "A", "B", "C" })
				local gui: GuiService
				local fallback: TextButton
				local node, stop = world(function(UI: FacetControls, engine, runtime)
					fallback = Facet.host(runtime).TextButton({}, "Fallback")
					return Facet.host(runtime).Frame({
						fallback,
						Compose.keyed({
							from = items,
							render = function(current, index): GuiObject
								local id = current:peek()
								local props: InputProps.ChipRemovableProps = {
									Name = id,
									label = id,
									LayoutOrder = index,
									removeFocusFallback = fallback :: GuiObject,
									onRemove = function()
										items:update(function(before)
											local after = {}
											for _, value in before do
												if value ~= id then
													table.insert(after, value)
												end
											end
											return after
										end)
									end,
								}
								return UI.Chip(props)
							end,
						}),
					})
				end, function(engine)
					gui = (engine.new("GuiService") :: unknown) :: GuiService
					return { services = { GuiService = gui } }
				end)
				local function remove(id)
					local target = find(node, id)
					gui.SelectedObject = target
					target.Activated:Fire()
				end
				remove("B")
				expect(gui.SelectedObject):toBe(find(node, "C"))
				remove("C")
				expect(gui.SelectedObject):toBe(find(node, "A"))
				remove("A")
				expect(gui.SelectedObject):toBe(fallback)
				stop()
			end,
		})

		it("does not steal focus after a delayed chip removal request", {
			id = "native_inputs::native input controls::does not steal focus after a delayed chip removal request",
			run = function()
				local show = Compose.cell(true)
				local gui: GuiService
				local fallback: TextButton
				local other: TextButton
				local node, stop = world(function(UI: FacetControls, engine, runtime)
					fallback = Facet.host(runtime).TextButton({}, "Fallback")
					other = Facet.host(runtime).TextButton({}, "Other")
					return Facet.host(runtime).Frame({
						fallback,
						other,
						Compose.show(show, function()
							local props: InputProps.ChipRemovableProps = {
								label = "Delayed",
								removeFocusFallback = fallback :: GuiObject,
								onRemove = function() end,
							}
							return UI.Chip "Delayed"(props)
						end),
					})
				end, function(engine)
					gui = (engine.new("GuiService") :: unknown) :: GuiService
					return { services = { GuiService = gui } }
				end)
				local remove = find(node, "Delayed")
				gui.SelectedObject = remove
				remove.Activated:Fire()
				expect(gui.SelectedObject):toBe(remove)
				gui.SelectedObject = other
				show:set(false)
				expect(gui.SelectedObject):toBe(other)
				stop()
			end,
		})

		it("keeps mixed checkbox geometry live and validates presentation-specific options", {
			id = "native_inputs::native input controls::keeps mixed checkbox geometry live and validates presentation-specific options",
			run = function()
				local value, mixed = Compose.cell(false), Compose.cell(true)
				local node, stop = world(function(UI: FacetControls)
					local props: InputProps.ToggleCellProps = {
						value = value,
						mixed = mixed,
						presentation = "checkbox" :: "checkbox",
						indicatorPosition = "trailing" :: "trailing",
						row = { title = "Mode", description = "Use the current setting" },
					}
					return UI.Toggle(props)
				end)
				expect(find(node, "Mark").Size.Y.Offset):toBe(4)
				expect(find(node, "Mark").Visible):toBe(true)
				expect(find(node, "Check").Visible):toBe(false)
				mixed:set(false)
				expect(find(node, "Mark").Visible):toBe(false)
				expect(find(node, "Check").Visible):toBe(false)
				value:set(true)
				expect(find(node, "Mark").Visible):toBe(false)
				expect(find(node, "Check").Visible):toBe(true)
				stop()
				expect(function()
					world(function(UI: FacetControls)
						local props: InputProps.ToggleCellProps =
							{ value = value, mixed = mixed, presentation = "switch" :: "switch" }
						return UI.Toggle(props)
					end)
				end):toThrow()
			end,
		})
		it("a switch knob glides between its ends, reverses mid-flight without a jump, and lands at once under none", {
			id = "native_inputs::native input controls::a switch knob glides between its ends, reverses mid-flight without a jump, and lands at once under none",
			run = function()
				local value = Compose.cell(false)
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.ToggleCellProps =
						{ label = "Music", value = value, presentation = "switch" :: "switch" }
					return UI.Toggle(props)
				end)
				local mark = find(node, "Mark")
				expect(mark.Position.X.Scale):toBeCloseTo(0.3, 1e-3)
				value:set(true)
				engine.heartbeat:Fire(1 / 60)
				local first = mark.Position.X.Scale
				expect(first > 0.3 and first < 0.7):toBe(true)
				engine.heartbeat:Fire(1 / 60)
				engine.heartbeat:Fire(1 / 60)
				local before = mark.Position.X.Scale
				value:set(false)
				engine.heartbeat:Fire(1 / 60)
				expect(math.abs(mark.Position.X.Scale - before) < 0.1):toBe(true)
				for _ = 1, 60 do
					engine.heartbeat:Fire(1 / 60)
				end
				expect(mark.Position.X.Scale):toBeCloseTo(0.3, 1e-3)
				value:set(true)
				for _ = 1, 60 do
					engine.heartbeat:Fire(1 / 60)
				end
				expect(mark.Position.X.Scale):toBeCloseTo(0.7, 1e-3)
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				stop()
				local snapped = Compose.cell(false)
				local snapNode, stopSnap = world(function(UI: FacetControls)
					local props: InputProps.ToggleCellProps =
						{ label = "Music", value = snapped, presentation = "switch" :: "switch" }
					return UI.Toggle(props)
				end, function()
					return { motionLevel = "none" }
				end)
				snapped:set(true)
				expect(find(snapNode, "Mark").Position.X.Scale):toBeCloseTo(0.7, 1e-3)
				stopSnap()
			end,
		})

		it("maps the named feedback kinds onto pooled engine haptic effects", {
			id = "native_inputs::native input controls::maps the named feedback kinds onto pooled engine haptic effects",
			run = function()
				local kind = Compose.cell("error" :: "error" | "impact" | "selection" | "success" | "warning" | boolean)
				local UIref: FacetControls
				local waveforms: { [unknown]: { FloatCurveKey } } = {}
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					UIref = UI
					return Facet.host(runtime).Frame({
						UI.Button "Saved" { label = "Save", haptic = "success" :: "success" },
						UI.Button "Again" { label = "Save", haptic = "success" :: "success" },
						UI.Button "Careful" { label = "Sell", haptic = "warning" :: "warning" },
						UI.Button "Live" { label = "Try", haptic = kind },
						UI.Button "Plain" { label = "Go", haptic = true },
						UI.Toggle "Sound" { value = Compose.cell(true), label = "Sound" },
					})
				end, function(engine)
					engine.environment.onCreate(function(effect)
						if effect:IsA("HapticEffect") then
							engine.environment.fakeOn(effect, "SetWaveformKeys", function(_, keys: { FloatCurveKey })
								waveforms[effect] = keys
							end)
						end
					end)
					return { pressHaptic = "selection" }
				end)
				local E = engine.types.Enum
				local saved = find(node, "Saved").PressHapticEffect
				local plays = 0
				engine.environment.fakeOn(saved, "Play", function()
					plays += 1
				end)
				expect(saved.ClassName):toBe("HapticEffect")
				expect(saved.Type):toBe(E.HapticEffectType.UINotification)
				expect(find(node, "Again").PressHapticEffect):toBe(saved)
				local warning = find(node, "Careful").PressHapticEffect
				expect(warning.Type):toBe(E.HapticEffectType.Custom)
				expect(#waveforms[warning] >= 4):toBe(true)
				for _, key in waveforms[warning] do
					expect(key.Value == 0 or key.Value >= 0.3):toBe(true)
				end
				local live = find(node, "Live")
				expect(live.PressHapticEffect.Type):toBe(E.HapticEffectType.Custom)
				expect(live.PressHapticEffect == warning):toBe(false)
				kind:set("impact")
				expect(live.PressHapticEffect.Type):toBe(E.HapticEffectType.GameplayCollision)
				kind:set(false)
				expect(live.PressHapticEffect):toBe(nil)
				expect(find(node, "Plain").PressHapticEffect.Type):toBe(E.HapticEffectType.UIClick)
				expect(find(node, "Sound").PressHapticEffect):toBe(find(node, "Plain").PressHapticEffect)
				UIref.feedback("success")
				expect(plays):toBe(1)
				expect(function()
					UIref.feedback("boom" :: any)
				end):toThrow()
				expect(function()
					world(function(UI: FacetControls)
						return UI.Button({ label = "Bad", haptic = "boom" } :: any)
					end)
				end):toThrow()
				stop()
				node, stop = world(function(UI: FacetControls)
					return UI.Button "Bare" { label = "Go", haptic = true }
				end)
				expect(node.PressHapticEffect):toBe(nil)
				stop()
			end,
		})

		it("plays the press haptic once for each slider detent and never for a continuous slider", {
			id = "native_inputs::native input controls::plays the press haptic once for each slider detent and never for a continuous slider",
			run = function()
				local stepped, continuous, plays = Compose.cell(25), Compose.cell(0.5), 0
				local effect: HapticEffect
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return Facet.host(runtime).Frame({
						UI.Slider "Stepped" { value = stepped, min = 0, max = 100, step = 25 },
						UI.Slider "Continuous" { value = continuous },
					})
				end, function(engine)
					effect = engine.new("HapticEffect")
					engine.environment.fakeOn(VerifyRoblox.assertInstance(effect), "Play", function()
						plays += 1
					end)
					return { pressHaptic = effect }
				end)
				local V = engine.types.Vector2
				local track, drag = find(find(node, "Stepped"), "Track"), find(find(node, "Stepped"), "Drag")
				engine.environment.poke(track, "AbsoluteSize", V.new(200, 44))
				engine.environment.poke(track, "AbsolutePosition", V.new(0, 0))
				drag.DragStart:Fire(V.new(50, 0))
				expect((stepped:peek())):toBe(25)
				expect(plays):toBe(0)
				for x = 51, 150 do
					drag.DragContinue:Fire(V.new(x, 0))
				end
				expect((stepped:peek())):toBe(75)
				expect(plays):toBe(2)
				drag.DragEnd:Fire()
				local free, freeDrag = find(find(node, "Continuous"), "Track"), find(find(node, "Continuous"), "Drag")
				engine.environment.poke(free, "AbsoluteSize", V.new(200, 44))
				engine.environment.poke(free, "AbsolutePosition", V.new(0, 0))
				freeDrag.DragStart:Fire(V.new(10, 0))
				for x = 11, 190 do
					freeDrag.DragContinue:Fire(V.new(x, 0))
				end
				freeDrag.DragEnd:Fire()
				expect(continuous:peek() > 0.9):toBe(true)
				expect(plays):toBe(2)
				stop()
			end,
		})

		it("mirrors native caption alignment and typography without a text geometry solver", {
			id = "native_inputs::native input controls::mirrors native caption alignment and typography without a text geometry solver",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button { label = "Centered" }
				end, function()
					return {
						theme = fixtureTheme({
							identity = { id = "native-input-fixture" },
							chrome = { control = { kind = "nineSlice" :: "nineSlice", asset = "control" } },
							assets = { control = { content = "rbxassetid://123" } },
						}),
					}
				end)
				local caption = find(node, "Label")
				expect(caption.TextXAlignment):toBe(node.TextXAlignment)
				expect(caption.TextYAlignment):toBe(node.TextYAlignment)
				engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(67, 44))
				engine.environment.poke(caption.Parent.Parent, "AbsoluteSize", engine.types.Vector2.new(1, 1))
				expect(caption.Parent.Size):toBe(engine.types.UDim2.fromOffset(67, 44))
				expect(caption.Parent.Parent.Size):toBe(engine.types.UDim2.fromOffset(1, 1))
				expect(caption.Parent.Parent.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.None)
				node.TextSize = 44
				node.TextXAlignment = engine.types.Enum.TextXAlignment.Right
				expect(caption.TextSize):toBe(44)
				expect(caption.TextXAlignment):toBe(engine.types.Enum.TextXAlignment.Right)
				expect(node.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.XY)
				stop()
			end,
		})

		it("bounds a button to a reactive authored width", {
			id = "native_inputs::native input controls::bounds a button to a reactive authored width",
			run = function()
				local width = Compose.cell(103)
				local node, stop, engine = world(function(UI: FacetControls, host)
					return UI.Button {
						label = "Boost Board",
						Size = function(use)
							return host.types.UDim2.fromOffset(use(width), 0)
						end,
					}
				end)
				expect(node.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
				expect(node.TextWrapped):toBe(true)
				expect(node.Size.X.Offset):toBe(103)
				width:set(0)
				expect(node.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.XY)
				expect(node.TextWrapped):toBe(false)
				width:set(120)
				expect(node.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
				stop()
			end,
		})

		it("bounds a described button to a reactive authored width", {
			id = "native_inputs::native input controls::bounds a described button to a reactive authored width",
			run = function()
				local width = Compose.cell(103)
				local node, stop, engine = world(function(UI: FacetControls, host)
					return UI.Button {
						label = "Boost Board",
						subtitle = "2 energy",
						Size = function(use)
							return host.types.UDim2.fromOffset(use(width), 0)
						end,
					}
				end)
				expect(node.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
				expect(node.Size.X.Offset):toBe(103)
				local content, captions = find(node, "Content"), find(node, "Captions")
				local title, description = find(node, "Title"), find(node, "Description")
				width:set(0)
				expect(node.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.XY)
				local children: { GuiObject } = { content, captions, title, description }
				for _, child in children do
					expect(child.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.XY)
					expect(child.Size.X.Scale):toBe(0)
				end
				expect(title.TextWrapped):toBe(false)
				expect(description.TextWrapped):toBe(false)
				expect(title.TextTruncate):toBe(engine.types.Enum.TextTruncate.None)
				expect(captions:FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(engine.types.Enum.UIFlexMode.None)
				width:set(120)
				expect(content.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
				expect(content.Size.X.Scale):toBe(1)
				expect(title.TextWrapped):toBe(true)
				expect(description.TextWrapped):toBe(true)
				expect(captions:FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(engine.types.Enum.UIFlexMode.Fill)
				stop()
			end,
		})

		it("gives native dialog contexts ordered sink priority and live eligibility", {
			id = "native_inputs::native input controls::gives native dialog contexts ordered sink priority and live eligibility",
			run = function()
				local tracking: FixtureBridge.Tracking
				local firstEnabled = Compose.cell(false)
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return Facet.host(runtime).Frame({
						UI.Button "First" { dialogAction = "default" :: "default", enabled = firstEnabled },
						UI.Button "Second" { dialogAction = "default" :: "default" },
					})
				end, function(_, fixture)
					tracking = fixture.track()
					return {}
				end)
				local contexts: { VerifyRoblox.Object } = {}
				for _, instance in tracking.created do
					if instance.ClassName == "InputContext" then
						table.insert(contexts, instance)
					end
				end
				tracking.stop()
				expect(#contexts):toBe(2)
				local firstPriority, secondPriority =
					engine.environment.propertyOf(contexts[1], "Priority"),
					engine.environment.propertyOf(contexts[2], "Priority")
				assert(type(firstPriority) == "number" and type(secondPriority) == "number")
				expect(firstPriority > secondPriority):toBe(true)
				expect(engine.environment.propertyOf(contexts[1], "Sink")):toBe(true)
				expect(engine.environment.propertyOf(contexts[1], "Enabled")):toBe(false)
				expect(engine.environment.propertyOf(contexts[2], "Enabled")):toBe(true)
				firstEnabled:set(true)
				expect(engine.environment.propertyOf(contexts[1], "Enabled")):toBe(true)
				find(node, "First").Visible = false
				expect(engine.environment.propertyOf(contexts[1], "Enabled")):toBe(false)
				stop()
				expect(engine.environment.isAlive(contexts[1])):toBe(false)
			end,
		})
		it("a held arrow repeats up to the bound and releases the axis at the bound", {
			id = "native_inputs::native input controls::a held arrow repeats up to the bound and releases the axis at the bound",
			run = function()
				local value = Compose.cell(95)
				local gui: GuiService
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.SliderCellProps = { value = value, min = 0, max = 100, step = 1 }
					return UI.Slider(props)
				end, function(engine)
					gui = (engine.new("GuiService") :: unknown) :: GuiService
					return { services = { GuiService = gui }, guiService = gui }
				end)
				gui.SelectedObject = node
				local increase = assert(enabledAction(node.Parent, "IncreaseArrow"))
				local held = true
				engine.environment.fakeOn(increase, "GetState", function()
					return held
				end)
				engine.environment.fire(VerifyRoblox.assertInstance(increase), "Pressed")
				for _ = 1, 20 do
					engine.heartbeat:Fire(0.1)
				end
				expect((value:peek())):toBe(100)
				expect(actionContext(increase).Enabled):toBe(false)
				held = false
				engine.environment.fire(VerifyRoblox.assertInstance(increase), "Released")
				expect(actionContext(increase).Enabled):toBe(false)
				expect(actionContext(assert(enabledAction(node.Parent, "DecreaseArrow"))).Enabled):toBe(true)
				value:set(99)
				expect(actionContext(increase).Enabled):toBe(true)
				stop()
			end,
		})

		it("releases the axis at value bounds and rearms on focus return", {
			id = "native_inputs::native input controls::releases the axis at value bounds and rearms on focus return",
			run = function()
				local value = Compose.cell(4)
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.RatingCellProps = { value = value }
					return UI.Rating(props)
				end)
				expect((find(node.Parent, "IncreaseArrow"))):toBe(nil)
				node.SelectionGained:Fire()
				local increase = find(node.Parent, "IncreaseArrow")
				local decrease = find(node.Parent, "DecreaseArrow")
				local bumper = find(node.Parent, "Increase")
				local held = true
				for _, action in { increase, decrease } do
					engine.environment.fakeOn(VerifyRoblox.assertInstance(action), "GetState", function()
						return held
					end)
				end
				expect(actionContext(increase).Enabled):toBe(true)
				engine.environment.fire(VerifyRoblox.assertInstance(increase), "Pressed")
				expect((value:peek())):toBe(5)
				expect(actionContext(increase).Enabled):toBe(false)
				held = false
				engine.environment.fire(VerifyRoblox.assertInstance(increase), "Released")
				expect(actionContext(increase).Enabled):toBe(false)
				expect(bumper.Parent.Enabled):toBe(true)
				expect(actionContext(decrease).Enabled):toBe(true)
				held = true
				engine.environment.fire(VerifyRoblox.assertInstance(decrease), "Pressed")
				expect((value:peek())):toBe(4)
				expect(actionContext(increase).Enabled):toBe(true)
				node.SelectionLost:Fire()
				expect(engine.environment.isAlive(increase)):toBe(false)
				expect((find(node.Parent, "IncreaseArrow"))):toBe(nil)
				node.SelectionGained:Fire()
				local rearmed = find(node.Parent, "IncreaseArrow")
				engine.environment.fakeOn(rearmed, "GetState", function()
					return held
				end)
				expect(rearmed ~= increase):toBe(true)
				expect(rearmed.Parent.Enabled):toBe(true)
				rearmed.Pressed:Fire()
				expect((value:peek())):toBe(5)
				stop()
			end,
		})
		it("cancels slider pointer ownership on native gamepad handoff and reports bounded semantics", {
			id = "native_inputs::native input controls::cancels slider pointer ownership on native gamepad handoff and reports bounded semantics",
			run = function()
				local value, input, commits = Compose.cell(0.5), nil, 0
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.SliderCellProps = {
						value = value,
						min = 0,
						max = 1,
						tapToPosition = false,
						onCommit = function()
							commits += 1
						end,
					}
					return UI.Slider(props)
				end, function(engine)
					input = (engine.new("UserInputService") :: unknown) :: UserInputService
					engine.environment.fakeOn(input, "GetLastInputType", function()
						return engine.types.Enum.UserInputType.MouseMovement
					end)
					return { services = { UserInputService = input } }
				end)
				local track, detector = find(node, "Track"), find(node, "Drag")
				engine.environment.poke(track, "AbsoluteSize", engine.types.Vector2.new(100, 44))
				detector.DragStart:Fire(engine.types.Vector2.new(80, 0))
				expect((value:peek())):toBe(0.5)
				detector.DragContinue:Fire(engine.types.Vector2.new(80.4, 0))
				expect((value:peek())):toBeCloseTo(0.9, 1e-4)
				expect((node:GetAttribute("semanticValue"))):toBe("0.9 of 0 to 1")
				engine.environment.poke(
					VerifyRoblox.assertInstance(input),
					"PreferredInput",
					engine.types.Enum.PreferredInput.Gamepad
				)
				expect((value:peek())):toBe(0.5)
				detector.DragEnd:Fire()
				expect(commits):toBe(0)
				value:set(4)
				expect((node:GetAttribute("value"))):toBe(1)
				expect((node:GetAttribute("semanticValue"))):toBe("1 of 0 to 1")
				stop()
			end,
		})
		it("ends a multiline edit when a native ancestor disables without late mutation", {
			id = "native_inputs::native input controls::ends a multiline edit when a native ancestor disables without late mutation",
			run = function()
				local value, commits = Compose.cell("line one\nline two"), 0
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return Facet.host(runtime).Frame({
						UI.TextInput "Editor" {
							value = value,
							multiline = true,
							onCommit = function()
								commits += 1
							end,
						},
					})
				end)
				local editor = find(node, "Editor")
				expect(editor.MultiLine):toBe(true)
				editor:CaptureFocus()
				editor.Text = "first\nsecond\n"
				expect((value:peek())):toBe("first\nsecond\n")
				editor.ReturnPressedFromOnScreenKeyboard:Fire()
				expect(commits):toBe(0)
				expect((editor:IsFocused())):toBe(true)
				node.Interactable = false
				expect((editor:IsFocused())):toBe(false)
				editor.Text = "late mutation"
				editor.FocusLost:Fire(true)
				expect((value:peek())):toBe("first\nsecond\n")
				expect(commits):toBe(0)
				node.Interactable = true
				editor:CaptureFocus()
				editor.Text = "accepted"
				editor:ReleaseFocus(false)
				expect(commits):toBe(1)
				stop()
			end,
		})

		it("grows a multiline field from an unclamped measure of its wrapped text", {
			id = "native_inputs::native input controls::grows a multiline field from an unclamped measure of its wrapped text",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return Facet.host(runtime).Frame({
						UI.TextInput "Notes" {
							value = Compose.cell("a\nb\n"),
							onChange = function() end,
							multiline = true,
						},
					})
				end)
				local field = find(node, "Notes")
				local measure = find(field, "Measure")
				expect(measure ~= nil):toBe(true)
				expect((measure:IsA("TextLabel"))):toBe(true)
				expect(measure.TextTransparency):toBe(1)
				expect(measure.Text):toBe("a\nb\n ")
				expect(field.Size.Y.Offset):toBe(96)
				expect(measure.Visible):toBe(false)
				engine.environment.poke(measure, "TextBounds", engine.types.Vector2.new(280, 300))
				expect(field.Size.Y.Offset):toBe(316)
				stop()
			end,
		})

		it("commits a touch edit when touch leaves with no keyboard and carries it otherwise", {
			id = "native_inputs::native input controls::commits a touch edit when touch leaves with no keyboard and carries it otherwise",
			run = function()
				local value, reasons, input = Compose.cell("seed"), {}, nil
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return Facet.host(runtime).Frame({
						UI.TextInput "Name" {
							value = value,
							onCommit = function(_, reason)
								table.insert(reasons, reason)
							end,
						},
					})
				end, function(engine)
					input = (engine.new("UserInputService") :: unknown) :: UserInputService
					engine.environment.fakeOn(input, "GetLastInputType", function()
						return engine.types.Enum.UserInputType.MouseMovement
					end)
					engine.environment.fakeOn(input, "IsGamepadButtonDown", function()
						return false
					end)
					engine.environment.fakeOn(input, "GetNavigationGamepads", function()
						return {}
					end)
					engine.environment.poke(VerifyRoblox.assertInstance(input), "TouchEnabled", true)
					engine.environment.poke(VerifyRoblox.assertInstance(input), "KeyboardEnabled", false)
					engine.environment.fakeOn(input, "IsKeyDown", function()
						return false
					end)
					return { services = { UserInputService = input } }
				end)
				local field = find(node, "Name")
				field:CaptureFocus()
				field.Text = "hi"
				engine.environment.poke(VerifyRoblox.assertInstance(input), "GamepadEnabled", true)
				expect((field:IsFocused())):toBe(true)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "KeyboardEnabled", true)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "TouchEnabled", false)
				expect((field:IsFocused())):toBe(true)
				expect(#reasons):toBe(0)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "TouchEnabled", true)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "KeyboardEnabled", false)
				expect((field:IsFocused())):toBe(true)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "TouchEnabled", false)
				expect((field:IsFocused())):toBe(false)
				expect(reasons):toEqual({ "focusLost" })
				expect((value:peek())):toBe("hi")
				stop()
			end,
		})

		it("retains native keyboard activation after first focus and gates it on live selection", {
			id = "native_inputs::native input controls::retains native keyboard activation after first focus and gates it on live selection",
			run = function()
				local activated = 0
				local firstEnabled = Compose.cell(true)
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return Facet.host(runtime).Frame({
						UI.Button "First" {
							label = "First",
							enabled = firstEnabled,
							onActivate = function()
								activated += 1
							end,
						},
						UI.Button "Second" {
							label = "Second",
							onActivate = function()
								activated += 10
							end,
						},
					})
				end)
				local first, second = find(node, "First"), find(node, "Second")
				expect((find(node.Parent, "Activate"))):toBe(nil)
				first.SelectionGained:Fire()
				local action = assert(enabledAction(node.Parent, "Activate"))
				expect(action ~= nil):toBe(true)
				expect(actionContext(action).Parent):toBe(node.Parent)
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				expect(activated):toBe(1)
				first.SelectionLost:Fire()
				expect(engine.environment.isAlive(VerifyRoblox.assertInstance(action))):toBe(true)
				expect(actionContext(action).Enabled):toBe(false)
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				expect(activated):toBe(1)
				first.SelectionGained:Fire()
				expect((enabledAction(node.Parent, "Activate"))):toBe(action)
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				expect(activated):toBe(2)
				first.Visible = false
				expect(actionContext(action).Enabled):toBe(false)
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				expect(activated):toBe(2)
				first.Visible = true
				firstEnabled:set(false)
				expect(actionContext(action).Enabled):toBe(false)
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				expect(activated):toBe(2)
				firstEnabled:set(true)
				expect((enabledAction(node.Parent, "Activate"))):toBe(action)
				first.SelectionLost:Fire()
				second.SelectionGained:Fire()
				local secondAction = assert(enabledAction(node.Parent, "Activate"))
				expect(secondAction ~= action):toBe(true)
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				expect(activated):toBe(2)
				engine.environment.fire(VerifyRoblox.assertInstance(secondAction), "Pressed")
				expect(activated):toBe(12)
				stop()
				expect(engine.environment.isAlive(VerifyRoblox.assertInstance(action))):toBe(false)
				expect(engine.environment.isAlive(VerifyRoblox.assertInstance(secondAction))):toBe(false)
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				engine.environment.fire(VerifyRoblox.assertInstance(secondAction), "Pressed")
				expect(activated):toBe(12)
				expect((engineLib.connections(first.SelectionGained))):toBe(0)
			end,
		})
		it("activates programmatically selected buttons through the native GuiService property", {
			id = "native_inputs::native input controls::activates programmatically selected buttons through the native GuiService property",
			run = function()
				local gui: GuiService
				local firstCalls, secondCalls = 0, 0
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return Facet.host(runtime).Frame({
						UI.Button "First" {
							label = "First",
							onActivate = function()
								firstCalls += 1
							end,
						},
						UI.Button "Second" {
							label = "Second",
							onActivate = function()
								secondCalls += 1
							end,
						},
					})
				end, function(engine)
					gui = (engine.new("GuiService") :: unknown) :: GuiService
					return { services = { GuiService = gui } }
				end)
				local first, second = find(node, "First"), find(node, "Second")
				expect((find(node.Parent, "Activate"))):toBe(nil)
				gui.SelectedObject = first
				local action = assert(enabledAction(node.Parent, "Activate"))
				expect(action ~= nil):toBe(true)
				expect(actionContext(action).Enabled):toBe(true)
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				expect(firstCalls):toBe(1)
				gui.SelectedObject = second
				expect(engine.environment.isAlive(VerifyRoblox.assertInstance(action))):toBe(true)
				expect(actionContext(action).Enabled):toBe(false)
				local secondAction = assert(enabledAction(node.Parent, "Activate"))
				expect(secondAction ~= action):toBe(true)
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				engine.environment.fire(VerifyRoblox.assertInstance(secondAction), "Pressed")
				expect(firstCalls):toBe(1)
				expect(secondCalls):toBe(1)
				gui.SelectedObject = nil
				expect((enabledAction(node.Parent, "Activate"))):toBe(nil)
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				engine.environment.fire(VerifyRoblox.assertInstance(secondAction), "Pressed")
				expect(firstCalls):toBe(1)
				expect(secondCalls):toBe(1)
				gui.SelectedObject = first
				expect((enabledAction(node.Parent, "Activate"))):toBe(action)
				expect(actionContext(secondAction).Enabled):toBe(false)
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				expect(firstCalls):toBe(2)
				stop()
				expect(engine.environment.isAlive(VerifyRoblox.assertInstance(action))):toBe(false)
				expect(engine.environment.isAlive(VerifyRoblox.assertInstance(secondAction))):toBe(false)
				expect((engineLib.connections(gui:GetPropertyChangedSignal("SelectedObject")))):toBe(0)
			end,
		})

		it("allocates mirrored captions only while a reactive native theme has control artwork", {
			id = "native_inputs::native input controls::allocates mirrored captions only while a reactive native theme has control artwork",
			run = function()
				local tracking: FixtureBridge.Tracking
				local neutral: ThemeTypes.ThemePackage =
					fixtureTheme({ identity = { id = "native-input-fixture" }, chrome = {} })
				local artwork: ThemeTypes.ThemePackage = fixtureTheme({
					identity = { id = "native-input-fixture" },
					chrome = { control = { kind = "nineSlice" :: "nineSlice", asset = "control" } },
					assets = { control = { content = "rbxassetid://123" } },
				})
				local theme: Compose.Value<ThemeTypes.ThemePackage> = Compose.cell(neutral)
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button { label = "Caption" }
				end, function(_, fixture)
					tracking = fixture.track()
					return { theme = theme }
				end)
				expect((find(node, "Label"))):toBe(nil)
				expect((engineLib.connections(node:GetPropertyChangedSignal("FontFace")))):toBe(0)
				theme:set(artwork)
				local label = find(node, "Label")
				local bounds, boundary = label.Parent, label.Parent.Parent
				expect(label.Text):toBe("Caption")
				expect((node:HasTag("facet-button-captioned"))):toBe(true)
				theme:set(neutral)
				expect(engine.environment.isAlive(label)):toBe(true)
				expect(boundary.Visible):toBe(false)
				expect((node:HasTag("facet-button-captioned"))):toBe(false)
				node.Text = "Retained caption"
				node.TextSize = 22
				engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(80, 44))
				engine.environment.poke(boundary, "AbsoluteSize", engine.types.Vector2.new(2, 2))
				for _ = 1, 100 do
					theme:set(artwork)
					expect((find(node, "Label"))):toBe(label)
					expect(boundary.Visible):toBe(true)
					expect((node:HasTag("facet-button-captioned"))):toBe(true)
					theme:set(neutral)
					expect(boundary.Visible):toBe(false)
					expect((node:HasTag("facet-button-captioned"))):toBe(false)
				end
				theme:set(artwork)
				expect(label.Text):toBe("Retained caption")
				expect(label.TextSize):toBe(22)
				expect(bounds.Size):toBe(engine.types.UDim2.fromOffset(40, 22))
				local created = 0
				for _, item in tracking.created do
					local name = engine.environment.propertyOf(item, "Name")
					if name == "Label" or name == "LabelBounds" or name == "LabelBoundary" then
						created += 1
					end
				end
				expect(created):toBe(3)
				stop()
				tracking.stop()
				expect(engine.environment.isAlive(label)):toBe(false)
				expect(engine.environment.isAlive(bounds)):toBe(false)
				expect(engine.environment.isAlive(boundary)):toBe(false)
				expect((engineLib.connections(node:GetPropertyChangedSignal("FontFace")))):toBe(0)
			end,
		})

		it("allocates native value actions only for the selected control, never for a part inside it", {
			id = "native_inputs::native input controls::allocates native value actions only for the selected control, never for a part inside it",
			run = function()
				local gui: GuiService
				local stepperValue, sliderValue = Compose.cell(3), Compose.cell(0.5)
				local enabled = Compose.cell(true)
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return Facet.host(runtime).Frame({
						UI.Stepper "Stepper" { value = stepperValue, max = 10, enabled = enabled },
						UI.Slider "Slider" { value = sliderValue },
					})
				end, function(engine)
					gui = (engine.new("GuiService") :: unknown) :: GuiService
					return { services = { GuiService = gui } }
				end)
				local function activeContextCount()
					local count = 0
					for _, object in node.Parent:GetDescendants() do
						if object.ClassName == "InputContext" and object.Enabled then
							count += 1
						end
					end
					return count
				end
				expect((activeContextCount())):toBe(0)
				gui.SelectedObject = find(node, "Slider")
				expect((activeContextCount())):toBe(5)
				local sliderAction = find(node.Parent, "FacetIncrease"):FindFirstChild("Increase")
				local held = true
				engine.environment.fakeOn(sliderAction, "GetState", function()
					return held
				end)
				sliderAction.Pressed:Fire()
				expect((sliderValue:peek())):toBe(0.51)
				local stepper = find(node, "Stepper")
				gui.SelectedObject = stepper
				expect((activeContextCount())):toBe(4)
				expect(engine.environment.isAlive(sliderAction)):toBe(false)
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				local action = find(node.Parent, "FacetIncrease"):FindFirstChild("Increase")
				engine.environment.fakeOn(VerifyRoblox.assertInstance(action), "GetState", function()
					return held
				end)
				engine.environment.fire(VerifyRoblox.assertInstance(action), "Pressed")
				expect((stepperValue:peek())):toBe(4)
				enabled:set(false)
				expect((activeContextCount())):toBe(0)
				expect(engine.environment.isAlive(VerifyRoblox.assertInstance(action))):toBe(false)
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				enabled:set(true)
				expect((activeContextCount())):toBe(4)
				gui.SelectedObject = nil
				expect((activeContextCount())):toBe(0)
				stop()
				local initial, initialStop, initialEngine = world(function(UI: FacetControls)
					local props: InputProps.StepperCellProps = {
						value = stepperValue,
						max = 10,
						ref = function(root)
							gui.SelectedObject = root
						end,
					}
					return UI.Stepper(props)
				end, function(engine)
					gui = (engine.new("GuiService") :: unknown) :: GuiService
					return { services = { GuiService = gui } }
				end)
				local initialAction = find(initial.Parent, "FacetIncrease"):FindFirstChild("Increase")
				initialEngine.environment.fakeOn(initialAction, "GetState", function()
					return held
				end)
				expect(initialAction.Parent.Enabled):toBe(true)
				initialAction.Pressed:Fire()
				expect((stepperValue:peek())):toBe(5)
				initialStop()
				expect(initialEngine.environment.isAlive(initialAction)):toBe(false)
			end,
		})

		it("repeats a held Stepper button and a repeating Button only while held", {
			id = "native_inputs::native input controls::repeats a held Stepper button and a repeating Button only while held",
			run = function()
				local value = Compose.cell(0)
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.StepperCellProps = { value = value, max = 100 }
					return UI.Stepper(props)
				end)
				local held = {
					UserInputType = engine.types.Enum.UserInputType.Touch,
					KeyCode = engine.types.Enum.KeyCode:FromValue(0),
				}
				local increase = find(node, "Increase")
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				increase.InputBegan:Fire(held)
				expect((engineLib.connections(engine.heartbeat))):toBe(1)
				engine.heartbeat:Fire(0.4)
				engine.heartbeat:Fire(0.1)
				expect((value:peek())):toBe(2)
				increase.InputEnded:Fire(held)
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				stop()
			end,
		})

		it("lets a game control opt into keyboard and gamepad adjustment with UI.adjustable", {
			id = "native_inputs::native input controls::lets a game control opt into keyboard and gamepad adjustment with UI.adjustable",
			run = function()
				local steps: { number } = {}
				local calls = 0
				local gui: GuiService
				local node, stop, engine = world(function(UI: FacetControls, engine, runtime)
					local dial = Facet.host(runtime).TextButton({
						Name = "Dial",
						Selectable = true,
					})
					UI.adjustable(dial, {
						onAdjust = function(direction)
							calls += 1
							table.insert(steps, direction)
						end,
						axis = "vertical" :: "vertical",
						repeats = true,
					})
					local knob = Facet.host(runtime).TextButton({
						Name = "Knob",
						Selectable = true,
					})
					UI.adjustable(knob, {
						onAdjust = function(direction)
							table.insert(steps, direction * 10)
						end,
						axis = "none" :: "none",
					})
					return Facet.host(runtime).Frame({ dial, knob })
				end, function(engine)
					gui = (engine.new("GuiService") :: unknown) :: GuiService
					return { services = { GuiService = gui }, guiService = gui }
				end)
				local dial, knob, screen = find(node, "Dial"), find(node, "Knob"), node.Parent
				expect((enabledAction(screen, "IncreaseArrow"))):toBe(nil)
				gui.SelectedObject = dial
				local up = assert(enabledAction(screen, "IncreaseArrow"))
				local held = true
				engine.environment.fakeOn(up, "GetState", function()
					return held
				end)
				expect(up ~= nil):toBe(true)
				expect(assert(up:FindFirstChildWhichIsA("InputBinding")).KeyCode):toBe(engine.types.Enum.KeyCode.Up)
				engine.environment.fire(VerifyRoblox.assertInstance(up), "Pressed")
				expect(steps[1]):toBe(1)
				engine.heartbeat:Fire(0.4)
				expect(steps[2]):toBe(1)
				held = false
				engine.environment.fire(VerifyRoblox.assertInstance(up), "Released")
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				local decrease = assert(enabledAction(screen, "Decrease"))
				engine.environment.fakeOn(decrease, "GetState", function()
					return held
				end)
				held = true
				engine.environment.fire(VerifyRoblox.assertInstance(decrease), "Pressed")
				held = false
				expect(steps[3]):toBe(-1)
				gui.SelectedObject = knob
				expect((enabledAction(screen, "IncreaseArrow"))):toBe(nil)
				local shoulder = assert(enabledAction(screen, "Increase"))
				engine.environment.fakeOn(shoulder, "GetState", function()
					return held
				end)
				held = true
				engine.environment.fire(VerifyRoblox.assertInstance(shoulder), "Pressed")
				held = false
				expect(steps[4]):toBe(10)
				engine.heartbeat:Fire(1)
				expect(#steps):toBe(4)
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				stop()
				expect(calls):toBe(3)
			end,
		})

		it("makes the Slider its one selection stop and draws the engine ring on its thumb", {
			id = "native_inputs::native input controls::makes the Slider its one selection stop and draws the engine ring on its thumb",
			run = function()
				local value = Compose.cell(0.5)
				local gui: GuiService
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return Facet.host(runtime).Frame({
						UI.Slider "Volume" { value = value, step = 0.1 },
						UI.Slider "Hidden" { value = Compose.cell(0.5), thumb = "auto" :: "auto" },
					})
				end, function(engine)
					gui = (engine.new("GuiService") :: unknown) :: GuiService
					return { services = { GuiService = gui }, guiService = gui }
				end)
				local volume = find(node, "Volume")
				local thumb, track = find(volume, "ThumbStop"), find(volume, "Track")
				expect(volume.Selectable):toBe(true)
				expect(thumb.Selectable):toBe(false)
				expect(track.Selectable):toBe(false)
				expect((volume:GetAttribute("FacetFocusPart"))):toBe("Track/ThumbStop")
				expect(find(find(node, "Hidden"), "Track").Selectable):toBe(false)
				expect((find(node, "Hidden"):GetAttribute("FacetFocusPart"))):toBe("Track")
				gui.SelectedObject = volume
				local increase = assert(enabledAction(node.Parent, "IncreaseArrow"))
				local held = true
				engine.environment.fakeOn(increase, "GetState", function()
					return held
				end)
				engine.environment.fire(VerifyRoblox.assertInstance(increase), "Pressed")
				expect(math.abs(value:peek() - 0.6) < 1e-9):toBe(true)
				stop()
			end,
		})

		it("repeats focused value adjustments with bounded catch-up and no idle frame subscription", {
			id = "native_inputs::native input controls::repeats focused value adjustments with bounded catch-up and no idle frame subscription",
			run = function()
				local value = Compose.cell(0)
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.StepperCellProps = { value = value, max = 100 }
					return UI.Stepper(props)
				end)
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				node.SelectionGained:Fire()
				local increase = find(node.Parent, "FacetIncrease"):FindFirstChild("Increase")
				local held = true
				engine.environment.fakeOn(increase, "GetState", function()
					return held
				end)
				engine.environment.fire(VerifyRoblox.assertInstance(increase), "Pressed")
				expect((value:peek())):toBe(1)
				expect((engineLib.connections(engine.heartbeat))):toBe(1)
				engine.heartbeat:Fire(0.35)
				expect((value:peek())):toBe(1)
				engine.heartbeat:Fire(0.25)
				expect((value:peek())):toBe(4)
				engine.heartbeat:Fire(20)
				expect((value:peek())):toBe(9)
				held = false
				engine.environment.fire(VerifyRoblox.assertInstance(increase), "Released")
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				held = true
				engine.environment.fire(VerifyRoblox.assertInstance(increase), "Pressed")
				node.SelectionLost:Fire()
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
				stop()
				expect((engineLib.connections(engine.heartbeat))):toBe(0)
			end,
		})
		it("a Stepper's repeatDelay and repeatInterval govern its held arrows and its held buttons alike", {
			id = "native_inputs::native input controls::a Stepper's repeatDelay and repeatInterval govern its held arrows and its held buttons alike",
			run = function()
				local value = Compose.cell(0)
				local node, stop, engine = world(function(UI: FacetControls)
					local props: InputProps.StepperCellProps =
						{ value = value, max = 100, repeatDelay = 1, repeatInterval = 0.5 }
					return UI.Stepper(props)
				end)
				node.SelectionGained:Fire()
				local increase = find(node.Parent, "FacetIncrease"):FindFirstChild("Increase")
				local held = true
				engine.environment.fakeOn(increase, "GetState", function()
					return held
				end)
				engine.environment.fire(VerifyRoblox.assertInstance(increase), "Pressed")
				engine.heartbeat:Fire(0.9)
				expect((value:peek())):toBe(1)
				engine.heartbeat:Fire(0.2)
				expect((value:peek())):toBe(2)
				engine.heartbeat:Fire(0.5)
				expect((value:peek())):toBe(3)
				held = false
				engine.environment.fire(VerifyRoblox.assertInstance(increase), "Released")
				local button
				for _, child in node:GetDescendants() do
					if child.ClassName == "TextButton" and child.Name == "Increase" then
						button = child
					end
				end
				button.InputBegan:Fire({
					UserInputType = engine.types.Enum.UserInputType.MouseButton1,
					KeyCode = engine.types.Enum.KeyCode:FromValue(0),
				})
				engine.heartbeat:Fire(0.9)
				expect((value:peek())):toBe(3)
				engine.heartbeat:Fire(0.2)
				expect((value:peek())):toBe(4)
				stop()
			end,
		})

		it("isolates artwork and mirrored captions from native automatic sizing while following real padding", {
			id = "native_inputs::native input controls::isolates artwork and mirrored captions from native automatic sizing while following real padding",
			run = function()
				local theme: Compose.Value<ThemeTypes.ThemePackage> =
					Compose.cell(fixtureTheme({ identity = { id = "native-input-fixture" }, chrome = {} }))
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button { label = "Enter" }
				end, function()
					return { theme = theme }
				end)
				local nativeSize, automaticSize = node.Size, node.AutomaticSize
				engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(67, 44))
				theme:set(fixtureTheme({
					identity = { id = "native-input-fixture" },
					chrome = { control = { kind = "nineSlice" :: "nineSlice", asset = "control" } },
					assets = { control = { content = "rbxassetid://123" } },
				}))
				local skin, label = find(node, "SkinBounds"), find(node, "LabelBounds")
				local skinHost = find(node, "SkinHost")
				expect(skinHost.Parent):toBe(node)
				expect(skinHost.Size):toBe(engine.types.UDim2.fromOffset(0, 0))
				expect(skinHost.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.None)
				local decorations: { GuiObject } = { skin, label }
				for _, decoration in decorations do
					local bounds = decoration.Parent
					assert(bounds and bounds:IsA("GuiObject"))
					engine.environment.poke(
						VerifyRoblox.assertInstance(bounds),
						"AbsoluteSize",
						engine.types.Vector2.new(1, 1)
					)
					expect(bounds.Parent):toBe(if decoration == skin then skinHost else node)
					expect(bounds.Size):toBe(engine.types.UDim2.fromOffset(1, 1))
					expect(bounds.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.None)
					expect(bounds.ClipsDescendants):toBe(false)
				end
				local padding = node:FindFirstChildWhichIsA("UIPadding")
				padding.PaddingLeft = engine.types.UDim.new(0.1, 2)
				padding.PaddingRight = engine.types.UDim.new(0, 5)
				padding.PaddingTop = engine.types.UDim.new(0, 3)
				padding.PaddingBottom = engine.types.UDim.new(0, 4)
				padding.Parent = node
				engine.environment.poke(skin.Parent, "AbsolutePosition", engine.types.Vector2.new(61, 39))
				engine.environment.poke(label.Parent, "AbsolutePosition", engine.types.Vector2.new(61, 39))
				expect(skin.Size):toBe(engine.types.UDim2.fromOffset(67, 44))
				expect(skin.Position):toBe(engine.types.UDim2.fromOffset(6, 5))
				expect(skin.AnchorPoint):toBe(engine.types.Vector2.new(1, 1))

				expect(label.Size):toBe(engine.types.UDim2.fromOffset(54, 37))
				expect(label.Size.Y.Offset):toBe(37)
				expect(label.Position):toBe(engine.types.UDim2.fromOffset(1, 1))
				padding.PaddingLeft = engine.types.UDim.new(0, 12)
				expect(skin.Position.X.Offset):toBe(6)
				expect(label.Size.X.Offset):toBe(50)
				engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(80, 50))
				expect(skin.Size):toBe(engine.types.UDim2.fromOffset(80, 50))
				expect(label.Size):toBe(engine.types.UDim2.fromOffset(63, 43))
				expect(node.Size):toBe(nativeSize)
				expect(node.AutomaticSize):toBe(automaticSize)
				padding.Parent = nil
				engine.environment.poke(skin.Parent, "AbsolutePosition", engine.types.Vector2.new(79, 49))
				expect(skin.Position):toBe(engine.types.UDim2.fromOffset(1, 1))
				expect(label.Size):toBe(engine.types.UDim2.fromOffset(80, 50))
				expect((engineLib.connections(padding:GetPropertyChangedSignal("PaddingLeft")))):toBe(0)
				stop()
				expect((engineLib.connections(node:GetPropertyChangedSignal("AbsoluteSize")))):toBe(0)
				expect((engineLib.connections(node.ChildAdded))):toBe(0)
				expect((engineLib.connections(node.ChildRemoved))):toBe(0)
			end,
		})

		it("converts rendered decoration bounds through the native one pixel scale reference", {
			id = "native_inputs::native input controls::converts rendered decoration bounds through the native one pixel scale reference",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button { label = "Enter" }
				end, function()
					return {
						theme = fixtureTheme({
							identity = { id = "native-input-fixture" },
							chrome = { control = { kind = "nineSlice" :: "nineSlice", asset = "control" } },
							assets = { control = { content = "rbxassetid://123" } },
						}),
					}
				end)
				local skin, label = find(node, "SkinBounds"), find(node, "LabelBounds")
				engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(100, 55))
				expect(skin.Size):toBe(engine.types.UDim2.fromOffset(0, 0))
				expect(label.Size):toBe(engine.types.UDim2.fromOffset(0, 0))
				for _, scale in { 1.25, 0.5, 2, 0.75, 1.25, 1 } do
					engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(80.25 * scale, 44.5 * scale))
					local decorations: { GuiObject } = { skin, label }
					for _, decoration in decorations do
						engine.environment.poke(
							VerifyRoblox.assertInstance(decoration.Parent),
							"AbsoluteSize",
							engine.types.Vector2.new(scale, scale)
						)
						expect(decoration.Size):toBe(
							if decoration == skin
								then engine.types.UDim2.fromOffset(80.25, 44.5)
								else engine.types.UDim2.fromOffset(81, 45)
						)
						local bounds = decoration.Parent
						assert(bounds and bounds:IsA("GuiObject"))
						expect(bounds.Size):toBe(engine.types.UDim2.fromOffset(1, 1))
					end
				end
				local padding = node:FindFirstChildWhichIsA("UIPadding")
				padding.PaddingLeft = engine.types.UDim.new(0, 12)
				padding.PaddingRight = engine.types.UDim.new(0, 8)
				padding.Parent = node
				engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(100, 55))
				engine.environment.poke(skin.Parent, "AbsoluteSize", engine.types.Vector2.new(1.25, 1.25))
				engine.environment.poke(label.Parent, "AbsoluteSize", engine.types.Vector2.new(1.25, 1.25))
				engine.environment.poke(skin.Parent, "AbsolutePosition", engine.types.Vector2.new(88.75, 53.75))
				engine.environment.poke(label.Parent, "AbsolutePosition", engine.types.Vector2.new(88.75, 53.75))
				expect(skin.Size):toBe(engine.types.UDim2.fromOffset(80, 44))
				expect(skin.Position):toBe(engine.types.UDim2.fromOffset(9, 1))
				expect(label.Size):toBe(engine.types.UDim2.fromOffset(60, 44))
				local skinBoundary, captionBoundary = skin.Parent, label.Parent
				stop()
				expect((engineLib.connections(skinBoundary:GetPropertyChangedSignal("AbsoluteSize")))):toBe(0)
				expect((engineLib.connections(captionBoundary:GetPropertyChangedSignal("AbsoluteSize")))):toBe(0)
			end,
		})

		it("keeps ten large rating marks inside a bounded phone cell and accepts the final mark", {
			id = "native_inputs::native input controls::keeps ten large rating marks inside a bounded phone cell and accepts the final mark",
			run = function()
				local value = Compose.cell(3)
				local root, stop, engine = world(function(UI: FacetControls, engine, runtime)
					return Facet.host(runtime).Frame({
						Size = engine.types.UDim2.fromOffset(353, 44),
						UI.Rating "Stars" { value = value, count = 10, starSize = "large" :: "large" },
					})
				end)
				local V = engine.types.Vector2
				engine.environment.poke(root, "AbsoluteSize", V.new(353, 44))
				local node, marks = find(root, "Stars"), find(root, "Marks")
				engine.environment.poke(node, "AbsoluteSize", V.new(353, 44))
				local spacing = marks:FindFirstChildWhichIsA("UIListLayout").Padding.Offset
				local width = 0
				for index = 1, 10 do
					local mark = find(marks, "Level" .. index)
					expect(mark.Visible):toBe(true)
					expect(mark.Size.X.Offset > 0):toBe(true)
					expect(mark.TextSize <= mark.Size.X.Offset):toBe(true)
					width += mark.Size.X.Offset
				end
				width += 9 * spacing
				expect(width <= 353):toBe(true)
				engine.environment.poke(marks, "AbsolutePosition", V.new(10, 10))
				engine.environment.poke(marks, "AbsoluteSize", V.new(width, 36))
				local detector = find(node, "Scrub")
				detector.DragStart:Fire(V.new(10 + width - 1, 20))
				detector.DragEnd:Fire()
				expect(value:peek()):toBe(10)
				stop()
			end,
		})

		it("a touch rating tightens its spacing to fit a fixed-width holder, such as a Table column", {
			id = "native_inputs::native input controls::a touch rating tightens its spacing to fit a fixed-width holder, such as a Table column",
			run = function()
				local input
				local root, stop, engine = world(function(UI: FacetControls, engine, runtime)
					return Facet.host(runtime).Frame({
						Name = "Column",
						Size = engine.types.UDim2.fromOffset(144, 44),
						UI.Rating "Stars" { value = Compose.cell(3) },
					})
				end, function(engine)
					input = (engine.new("UserInputService") :: unknown) :: UserInputService
					engine.environment.poke(VerifyRoblox.assertInstance(input), "TouchEnabled", true)
					return { services = { UserInputService = input } }
				end)
				local V = engine.types.Vector2
				local node = find(root, "Stars")
				expect(node.Size.X.Offset):toBe(5 * 20 + 4 * 24)
				local mark = find(node, "Marks"):FindFirstChildWhichIsA("GuiObject")
				engine.environment.poke(mark, "AbsoluteSize", V.new(20, 20))
				engine.environment.poke(root, "AbsoluteSize", V.new(144, 44))
				expect(node.Size.X.Offset):toBe(5 * 20 + 4 * 11)
				engine.environment.poke(mark, "AbsoluteSize", V.new(40, 40))
				engine.environment.poke(find(node, "LayoutUnit"), "AbsoluteSize", V.new(200, 2))
				expect(node.Size.X.Offset):toBe(5 * 20 + 4 * 2)
				engine.environment.poke(root, "AbsoluteSize", V.new(800, 88))
				expect(node.Size.X.Offset):toBe(5 * 20 + 4 * 24)
				stop()
			end,
		})

		it("a touch level picker shrinks beside a sibling in a row and spaces its marks to the width it is drawn at", {
			id = "native_inputs::native input controls::a touch level picker shrinks beside a sibling in a row and spaces its marks to the width it is drawn at",
			run = function()
				local input
				local root, stop, engine = world(function(UI: FacetControls, engine, runtime)
					return Facet.host(runtime).Frame({
						Name = "Pair",
						Size = engine.types.UDim2.fromOffset(337, 44),
						UI.LevelPicker "Bars" { value = Compose.cell(2), count = 10 },
					})
				end, function(engine)
					input = (engine.new("UserInputService") :: unknown) :: UserInputService
					engine.environment.poke(VerifyRoblox.assertInstance(input), "TouchEnabled", true)
					return { services = { UserInputService = input } }
				end)
				local V = engine.types.Vector2
				local node = find(root, "Bars")
				local flex = node:FindFirstChildWhichIsA("UIFlexItem")
				expect(flex and flex.FlexMode):toBe(engine.types.Enum.UIFlexMode.Shrink)
				local mark = find(node, "Marks"):FindFirstChildWhichIsA("GuiObject")
				local spacing = find(node, "Marks"):FindFirstChildWhichIsA("UIListLayout")
				engine.environment.poke(mark, "AbsoluteSize", V.new(20, 20))
				engine.environment.poke(root, "AbsoluteSize", V.new(337, 44))
				expect(node.Size.X.Offset):toBe(10 * 20 + 9 * 15)
				engine.environment.poke(node, "AbsoluteSize", V.new(10 * 20 + 9 * 15, 44))
				expect(spacing.Padding.Offset):toBe(15)
				engine.environment.poke(node, "AbsoluteSize", V.new(10 * 20 + 9 * 6, 44))
				expect(spacing.Padding.Offset):toBe(6)
				stop()
			end,
		})
	end);
	(function(verifyHarness: Verify.Harness)
		type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
		type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
		type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
		local FixtureNavigationTypes = require("../src/ui/navigation_types")

		local Facet = require("../src")
		local engineLib = require("./lib/native_engine")
		local Compose: ComposeModule = Facet.Compose
		local themes = Facet.themes

		type Harness = {
			engine: any,
			runtime: any,
			UI: any,
			Host: any,
			gui: any,
			input: any,
			dispose: () -> (),
		}

		local function harness(options: { [string]: any }?): Harness
			local engine: any = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local gui = (engine.new("GuiService") :: unknown) :: GuiService
			local input = (engine.new("UserInputService") :: unknown) :: UserInputService
			engine.environment.fakeOn(input, "GetLastInputType", function()
				return engine.types.Enum.UserInputType.MouseMovement
			end)
			local config: { [string]: any } =
				{ types = engine.types, guiService = gui, services = { GuiService = gui, UserInputService = input } }
			for key, value in (options or {}) :: { [string]: any } do
				config[key] = value
			end
			local UI: FacetControls = Facet.controls(runtime, config :: any)
			return {
				engine = engine,
				runtime = runtime,
				UI = UI,
				Host = Facet.host(runtime),
				gui = gui,
				input = input,
				dispose = function()
					runtime:dispose()
				end,
			}
		end

		local function mount(h: Harness, build: () -> any): (any, () -> ())
			local stop, root = h.runtime.mount(function()
				return h.Host.Frame { build() }
			end, h.engine.new("ScreenGui"))
			return root, stop
		end

		local function find(root: any, name: string): any
			if root.Name == name then
				return root
			end
			for _, child in root:GetChildren() do
				local found = find(child, name)
				if found then
					return found
				end
			end
			return nil
		end

		it("keeps a thumb-target Button at the thumb size of the screen's short edge on touch", {
			id = "native_inputs::native input controls::keeps a thumb-target Button at the thumb size of the screen's short edge on touch",
			run = function()
				local viewport = Compose.cell(engineLib.new().types.Vector2.new(359, 718))
				local h = harness({ environment = { viewportSize = viewport } })
				h.engine.environment.poke(h.input, "TouchEnabled", true)
				h.engine.environment.poke(h.input, "KeyboardEnabled", false)
				local root, stop = mount(h, function()
					return h.UI.Button "Drift" {
						label = "DRIFT",
						target = "thumb" :: "thumb",
						onActivate = function() end,
					}
				end)
				local V2 = h.engine.types.Vector2
				local floor = find(root, "Drift"):FindFirstChild("TargetFloor")
				expect(floor.MinSize):toBe(V2.new(70, 70))
				viewport:set(V2.new(718, 359))
				expect(floor.MinSize):toBe(V2.new(70, 70))
				viewport:set(V2.new(1024, 768))
				expect(floor.MinSize):toBe(V2.new(120, 120))
				h.engine.environment.poke(h.input, "TouchEnabled", false)
				h.engine.environment.poke(h.input, "KeyboardEnabled", true)
				expect(find(root, "Drift"):FindFirstChild("TargetFloor")):toBe(nil)
				stop()
				h.dispose()
			end,
		})

		type Compound = { class: string?, name: string?, tags: { string }, state: string? }
		type Selector = { parts: { Compound }, combinators: { string }, pseudo: string? }

		local function compound(text: string): Compound
			local tags = {}
			for tag in string.gmatch(text, "%.([%w%-]+)") do
				table.insert(tags, tag)
			end
			return {
				class = string.match(text, "^(%a%w*)"),
				name = string.match(text, "#([%w_]+)"),
				tags = tags,
				state = string.match(text, ":(%a+)$"),
			}
		end

		local parsed: { [string]: Selector } = {}

		local function parse(selector: string): Selector
			local cached = parsed[selector]
			if cached then
				return cached
			end
			local pseudo = string.match(selector, "::(%a+)$")
			local rest = if pseudo then string.sub(selector, 1, -(#pseudo + 3)) else selector
			local parts, combinators = {}, {}
			while true do
				local first, last, combinator = string.find(rest, " (>>?) ")
				if not first then
					table.insert(parts, compound(rest))
					break
				end
				table.insert(parts, compound(string.sub(rest, 1, first - 1)))
				table.insert(combinators, combinator :: string)
				rest = string.sub(rest, (last :: number) + 1)
			end
			local result = { parts = parts, combinators = combinators, pseudo = pseudo }
			parsed[selector] = result
			return result
		end

		local function skinPackage(slots: { [string]: any }): any
			local package = themes.neutralPackage()
			package.assets = package.assets or {}
			for slot, asset in slots do
				assert(package.assets)[slot .. "Art"] = { content = asset }
				assert(package.chrome)[slot] = { kind = "nineSlice" :: "nineSlice", asset = slot .. "Art" }
			end
			return package
		end

		describe("native paint strength: skins", function()
			it("keeps full-bleed art on the plate's own box when the padding changes after mount", {
				id = "native_inputs::native paint strength: skins::keeps full-bleed art on the plate's own box when the padding changes after mount",
				run = function()
					local package = skinPackage({ control = "rbxassetid://123" })
					local h = harness({ theme = package })
					local root, stop = mount(h, function()
						return h.UI.Button { Name = "Plate", label = "Mark read" }
					end)
					local plate = find(root, "Plate")
					local skin, label = find(plate, "SkinBounds"), find(plate, "LabelBounds")
					local UDim = h.engine.types.UDim
					local hostX, hostWidth = 10, 83
					h.engine.environment.poke(plate, "AbsoluteSize", h.engine.types.Vector2.new(hostWidth, 28))
					h.engine.environment.poke(plate, "AbsolutePosition", h.engine.types.Vector2.new(hostX, 0))
					local boundsList: { GuiObject } = { skin, label }
					for _, bounds in boundsList do
						h.engine.environment.poke(bounds.Parent, "AbsoluteSize", h.engine.types.Vector2.new(1, 1))
					end
					local padding = plate:FindFirstChildWhichIsA("UIPadding")
					local function painted(bounds: any): (number, number)
						local right = padding.PaddingRight.Offset
						local boundaryLeft = hostX + hostWidth - right - 1
						h.engine.environment.poke(
							bounds.Parent,
							"AbsolutePosition",
							h.engine.types.Vector2.new(boundaryLeft, 28 - padding.PaddingBottom.Offset - 1)
						)
						local rightEdge = boundaryLeft + bounds.Position.X.Offset
						return rightEdge - bounds.Size.X.Offset, rightEdge
					end
					for _, inset in { 12, 8, 0, 8 } do
						padding.PaddingLeft = UDim.new(0, inset)
						padding.PaddingRight = UDim.new(0, inset)
						local left, right = painted(skin)
						expect(`{left}..{right}`):toBe("10..93")
						local textLeft, textRight = painted(label)
						expect(`{textLeft}..{textRight}`):toBe(`{10 + inset}..{93 - inset}`)
					end
					padding.PaddingLeft = UDim.new(0, 12)
					padding.PaddingRight = UDim.new(0, 8)
					local left, right = painted(skin)
					expect(`{left}..{right}`):toBe("10..93")
					local textLeft, textRight = painted(label)
					expect(`{textLeft}..{textRight}`):toBe("22..85")
					stop()
					h.dispose()
				end,
			})
		end)
	end)(verifyHarness);
	(function(verifyHarness: Verify.Harness)
		type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
		type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
		type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
		type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
		local FixtureNavigationTypes = require("../src/ui/navigation_types")

		local Facet = require("../src")
		local engineLib = require("./lib/native_engine")
		local Compose: ComposeModule = Facet.Compose

		type World = {
			engine: any,
			runtime: any,
			UI: any,
			Host: any,
			gui: any,
			input: any,
			root: any,
			node: any,
			stop: () -> (),
		}

		local function setup(
			build: (
				FacetControls,
				RobloxHost,
				engineLib.Engine,
				ComposeTypes.Runtime
			) -> ComposeTypes.Node,
			options: SharedTypes.Config?
		): World
			local engine = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local gui = (engine.new("GuiService") :: unknown) :: GuiService
			local input = (engine.new("UserInputService") :: unknown) :: UserInputService
			engine.environment.fakeOn(input, "GetLastInputType", function()
				return engine.types.Enum.UserInputType.MouseMovement
			end)
			engine.environment.fakeOn(input, "IsKeyDown", function()
				return false
			end)
			local root = engine.new("ScreenGui")
			local config: SharedTypes.Config = if options then table.clone(options) else {}
			config.types = engine.types
			config.guiService = gui
			config.services = { GuiService = gui, UserInputService = input }
			config.inputParent = root
			config.motionLevel = config.motionLevel or "none"
			local UI: FacetControls = Facet.controls(runtime, config)
			local Host = Facet.host(runtime)
			local stop, node: any = runtime.mount(function()
				return build(UI, Host, engine, runtime)
			end, root)
			return {
				engine = engine,
				runtime = runtime,
				UI = UI,
				Host = Host,
				gui = gui,
				input = input,
				root = root,
				node = node,
				stop = function()
					stop()
					runtime:dispose()
				end,
			}
		end

		local function find(root: any, name: string): any
			if root.Name == name then
				return root
			end
			for _, child in root:GetChildren() do
				local found = find(child, name)
				if found then
					return found
				end
			end
			return nil
		end

		local function action(root: any, name: string): any
			for _, child in root:GetDescendants() do
				if child:IsA("InputContext") and child.Name == "Facet" .. name and child.Enabled then
					return child:FindFirstChild(name)
				end
			end
			return nil
		end

		describe("native parity weaker actions", function()
			it("returns a pressed pop to its rest under an authored scale and keeps the native shadow", {
				id = "native_inputs::native parity weaker actions::returns a pressed pop to its rest under an authored scale and keeps the native shadow",
				run = function()
					local package = Facet.themes.neutralPackage()
					assert(package.chrome).control = { kind = "native" :: "native", shadow = "raised" }
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame "Card" {
							Host.UIScale "Authored" { Scale = 0.8 },
							UI.Button "Pop" { label = "Pop", pop = true, onActivate = function() end },
						}
					end, { motionLevel = "normal", theme = package })
					local E = world.engine.types.Enum
					local node = find(world.node, "Pop")
					local authored = find(world.node, "Authored")
					local pop = node:FindFirstChildWhichIsA("UIScale", true)
					local shadow = find(node, "ChromeShadow")
					expect(shadow.ClassName):toBe("UIShadow")
					expect(shadow.Enabled):toBe(true)
					expect(pop.Scale):toBe(1)
					world.engine.environment.poke(node, "GuiState", E.GuiState.Press)
					node.Activated:Fire()
					world.engine.heartbeat:Fire(0.1)
					expect(pop.Scale > 1):toBe(true)
					expect((find(node, "ChromeShadow"))):toBe(shadow)
					expect(shadow.Enabled):toBe(true)
					world.engine.environment.poke(node, "GuiState", E.GuiState.Idle)
					world.engine.heartbeat:Fire(1)
					expect(pop.Scale):toBe(1)
					expect(authored.Scale):toBe(0.8)
					expect((find(node, "ChromeShadow"))):toBe(shadow)
					expect(shadow.Enabled):toBe(true)
					expect(world.engine.environment.isAlive(shadow)):toBe(true)
					world.stop()
					expect(world.engine.environment.isAlive(shadow)):toBe(false)
				end,
			})
			it("gives native chrome no box that holds the control's automatic size", {
				id = "native_inputs::native parity weaker actions::gives native chrome no box that holds the control's automatic size",
				run = function()
					for _, live in { false, true } do
						local package = Facet.themes.neutralPackage()
						assert(package.chrome).control = { kind = "native" :: "native", shadow = "raised" }
						local world = setup(function(UI: FacetControls, Host: RobloxHost)
							return Host.Frame "Card" {
								UI.Button "Plain" { label = "Plain", onActivate = function() end },
							}
						end, { theme = if live then Facet.Compose.cell(package) else package })
						local node = find(world.node, "Plain")
						expect(find(node, "ChromeShadow").ClassName):toBe("UIShadow")
						local boundary = node:FindFirstChild("SkinBoundary", true) :: Frame?
						if boundary then
							expect(boundary.Visible):toBe(false)
						end
						world.stop()
					end
				end,
			})
			it("keeps a native shadow at the opacity of the fill that casts it", {
				id = "native_inputs::native parity weaker actions::keeps a native shadow at the opacity of the fill that casts it",
				run = function()
					local package = Facet.themes.neutralPackage()
					assert(package.chrome).control = { kind = "native" :: "native", shadow = "raised" }
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame "Card" {
							UI.Button "Tint" { label = "Tint", onActivate = function() end },
						}
					end, { theme = package })
					local node = find(world.node, "Tint")
					local shadow = find(node, "ChromeShadow")
					node.BackgroundTransparency = 0
					expect(shadow.Transparency):toBeCloseTo(0.35, 5)
					node.BackgroundTransparency = 0.8
					expect(shadow.Transparency):toBeCloseTo(1 - 0.65 * 0.2, 5)
					node.BackgroundTransparency = 1
					expect(shadow.Transparency):toBe(1)
					node.BackgroundTransparency = 0
					expect(shadow.Transparency):toBeCloseTo(0.35, 5)
					world.stop()
				end,
			})
		end)
	end)(verifyHarness)
end
