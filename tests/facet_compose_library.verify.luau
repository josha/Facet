--!strict
local Verify = require("../tools/vendor/verify/src/core")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")

return function(verifyHarness: Verify.Harness)
	local Facet = require("../src")
	local FacetDesign = require("../src/design")
	local ComposeDesign = require("../src/vendor/compose/design")
	local Kit = Facet.design()
	local Design = Kit.Design
	local engines = require("./lib/native_engine")
	local overlay = require("./lib/overlay_world")

	type Context = { UI: Facet.Controls, types: typeof(engines.new().types), runtime: Facet.Runtime }
	type Engine = typeof(engines.new())

	local function mount(render: (ctx: Context, engine: Engine) -> unknown): { dispose: () -> () }
		local engine = engines.new()
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		engine.environment.poke(input, "PreferredInput", engine.types.Enum.PreferredInput.KeyboardAndMouse)
		input.GetFocusedTextBox = function()
			return nil
		end
		local runtime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, {
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			motionLevel = "none",
		})
		local stop = runtime.mount(function()
			local built = render({ UI = UI, types = engine.types, runtime = runtime }, engine)
			assert(typeof(built) == "Instance", "a design renders to an Instance")
			return built
		end, engine.new("ScreenGui"))
		return {
			dispose = function()
				stop()
				runtime:dispose()
			end,
		}
	end

	local function designEnvironment(ctx: Context, engine: Engine)
		local types = ctx.types
		return Facet.Roblox.designEnvironment({
			service = function(name: string): unknown
				return engine.new(name)
			end,
			values = {
				vector2 = types.Vector2.new,
				vector3 = types.Vector3.new,
				udim = types.UDim.new,
				udim2 = types.UDim2.new,
				color = types.Color3.new,
				font = function(family: string, weight: string): unknown
					return types.Font.new(family, types.Enum.FontWeight:FromName(weight))
				end,
				enum = function(name: string, item: string): unknown
					return types.Enum[name][item]
				end,
				cframe = function(components: { number }): unknown
					local c = components
					if #c == 3 then
						return types.CFrame.new(c[1], c[2], c[3])
					elseif #c == 7 then
						return types.CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7])
					elseif #c == 12 then
						return types.CFrame.new(
							c[1],
							c[2],
							c[3],
							c[4],
							c[5],
							c[6],
							c[7],
							c[8],
							c[9],
							c[10],
							c[11],
							c[12]
						)
					end
					return types.CFrame.new()
				end,
				raycastParams = function(): unknown
					return nil
				end,
			},
		})
	end

	local function sample(field: Facet.DesignField, preset: Facet.DesignLiteral?): Facet.DesignValue?
		local kind = field.type
		local default = if preset ~= nil then preset else field.default
		local bindsOnly = kind == "node" or kind == "event" or kind == "content"
		if default ~= nil and not bindsOnly then
			return { literal = default }
		elseif kind == "string" then
			return { literal = "Sample" }
		elseif kind == "number" then
			return { literal = 1 }
		elseif kind == "boolean" then
			return { literal = true }
		elseif kind == "choice" then
			local options = field.options
			return if options ~= nil and options[1] ~= nil then { literal = options[1] } else nil
		elseif kind == "color" then
			return { literal = "#336699" }
		elseif kind == "vector3" then
			return { literal = { 1, 2, 3 } }
		elseif kind == "node" then
			return { node = "n1" }
		end
		return nil
	end

	local function names(): { string }
		local list: { string } = {}
		for name in Kit.controls do
			table.insert(list, name)
		end
		table.sort(list)
		return list
	end

	local function offline(): Facet.DesignLibrary
		return Kit.library({
			UI = {},
		})
	end

	local function live(
		ctx: { UI: Facet.Controls, types: typeof(engines.new().types) },
		motion: Facet.DesignMotion?
	): Facet.DesignLibrary
		return Kit.library({
			UI = ctx.UI,
			types = ctx.types,
			motion = motion,
		})
	end

	local function anchoredCallout(library: Facet.DesignLibrary): Facet.DesignDocument
		local value = Design.document.new("AnchoredHelp", library, "VStack")
		local trigger, callout
		value, trigger = Design.document.insert(value, library, "n1", "Button")
		value = Design.document.rename(value, library, trigger, "AuthoredTrigger")
		value = Design.document.change(value, library, trigger, "label", { literal = "Learn more" })
		value, callout = Design.document.insert(value, library, "n1", "Callout")
		return Design.document.change(value, library, callout, "anchor", { node = trigger })
	end

	verifyHarness:case("round trips captured optional Callout references", function()
		local library = offline()
		local code = Design.emit(anchoredCallout(library), library)
		Verify.expect(string.find(code, "Facet.Value<GuiObject?>", 1, true) ~= nil):toBe(true)
		Verify.expect(string.find(code, "Facet.Compose.cell<<GuiObject?>>(nil)", 1, true) ~= nil):toBe(true)
		local parsed = Design.parse(code, library)
		Verify.expect(parsed.root.children[2].props.anchor.node):toBe(parsed.root.children[1].id)
		Verify.expect(Design.emit(parsed, library)):toBe(code)
	end)

	verifyHarness:case("keeps the authored Callout anchor in live rendering", function(test: Verify.Context)
		local received: Instance? = nil
		local trigger: unknown = nil
		test:defer(mount(function(ctx: Context): unknown
			local controls = setmetatable({
				Callout = function(props: Facet.CalloutSpec, name: string?): Frame
					received = props.anchor
					return ctx.UI.Callout(props, name)
				end,
			}, { __index = ctx.UI })
			local library = Kit.library({ UI = controls, types = ctx.types })
			return Design.render(anchoredCallout(library), library, {
				decorate = function(node: Facet.DesignNode, made: unknown)
					if node.name == "AuthoredTrigger" then
						trigger = made
					elseif node.kind == "Callout" then
						local root = VerifyRoblox.assertInstance(made)
						Verify.expect(root.Name):toBe("Callout")
					end
				end,
			})
		end).dispose)
		Verify.expect(received ~= nil):toBe(true)
		Verify.expect(received):toBe(trigger)
	end)

	verifyHarness:case("keeps the authored Callout anchor at every editor device stage", function(test: Verify.Context)
		local DesignEditor = require("../src/vendor/compose/design-editor")
		local editor: DesignEditor.Editor? = nil
		local runtime: Facet.Runtime? = nil
		local anchors: { unknown } = {}
		test:defer(mount(function(ctx: Context, engine: Engine): unknown
			runtime = ctx.runtime
			local controls = setmetatable({
				Callout = function(props: Facet.CalloutSpec, name: string?): Frame
					table.insert(anchors, props.anchor)
					return ctx.UI.Callout(props, name)
				end,
			}, { __index = ctx.UI })
			local library = Kit.library({ UI = controls, types = ctx.types })
			local host = ctx.UI.VStack "Editor" { width = "fill" }
			editor = DesignEditor.create(library, anchoredCallout(library), host, {
				runtime = ctx.runtime,
				environment = designEnvironment(ctx, engine),
				devices = DesignEditor.devices.all,
			})
			return host
		end).dispose)
		local opened = assert(editor)
		test:defer(opened.dispose)
		for _, device in DesignEditor.devices.all do
			Verify.expect(opened.execute({ action = "Device", id = device.id }).ok):toBe(true)
			assert(runtime):settle()
			Verify.expect(opened.session.problem:peek()):toBeNil()
			local frame = opened.canvas.current()
			Verify.expect(frame.device.id):toBe(device.id)
			local stage = assert(frame.stage)
			local trigger = VerifyRoblox.assertInstance(stage.nodes.n2)
			Verify.expect(trigger.Name):toBe("AuthoredTrigger")
			Verify.expect(table.find(anchors, trigger) ~= nil):toBe(true)
			local callout = VerifyRoblox.assertInstance(stage.nodes.n3)
			Verify.expect(callout.Name):toBe("Callout")
			Verify.expect(VerifyRoblox.assertInstance(stage.nodes.n1):FindFirstChild("CalloutAnchor", true)):toBeNil()
		end
	end)

	for _, mode in { "Sheet", "Dialog", "Toast", "ActionToast" } do
		verifyHarness:case(`resolves the presented {mode} surface inside its preview stage`, function()
			local presented = Facet.Compose.cell(true)
			local selected: unknown = nil
			local anchor: Instance? = nil
			local stage: Frame? = nil
			local resolve: ((unknown, Facet.Use) -> unknown)? = nil
			local function peek<T>(value: Facet.ReadOnlyValue<T>): T
				return value:peek()
			end
			local session = mount(function(ctx: Context): unknown
				local Host = Facet.host(ctx.runtime)
				local container = Host.Frame "DeviceStage" { Size = ctx.types.UDim2.fromOffset(480, 320) }
				stage = container
				local UI = Facet.controls(ctx.runtime, {
					types = ctx.types,
					motionLevel = "none",
					overlayParent = container,
					strictBuild = true,
				})
				local library = Kit.library({ UI = UI, types = ctx.types })
				resolve = assert(library.kinds[if mode == "ActionToast" then "Toast" else mode].selectionTarget)
				ctx.runtime.mount(function(): Instance
					local built: Frame
					if mode == "Sheet" then
						built = UI.Sheet {
							isPresented = presented,
							title = "Details",
							content = function(): Instance
								return UI.Text { text = "Details" }
							end,
						}
					elseif mode == "Dialog" then
						built = UI.Dialog { isPresented = presented, title = "Details", closeButton = false }
					else
						built = UI.Toast {
							isPresented = presented,
							onPresentedChange = function(value: boolean)
								presented:set(value)
							end,
							message = "Saved",
							duration = 0,
							action = if mode == "ActionToast"
								then { label = "Done", onActivate = function() end }
								else nil,
						}
					end
					anchor = built
					Facet.Compose.watch(function(use: Facet.Use)
						selected = assert(resolve)(built, use)
					end)
					return built
				end, container)
				return container
			end)
			local first = selected
			assert(typeof(first) == "Instance" and first:IsA("GuiObject"))
			Verify.expect(first == anchor):toBe(false)
			Verify.expect(first:IsDescendantOf(assert(stage))):toBe(true)
			Verify.expect(first.Name):toBe(
				if mode == "Sheet"
					then "SheetPanel"
					elseif mode == "Dialog" then "Panel"
					elseif mode == "Toast" then "ToastRow"
					else "Snack"
			)
			presented:set(false)
			Verify.expect(selected):toBeNil()
			presented:set(true)
			local reopened = selected
			assert(typeof(reopened) == "Instance" and reopened:IsA("GuiObject"))
			Verify.expect(reopened:IsDescendantOf(assert(stage))):toBe(true)
			Verify.expect(reopened == first):toBe(false)
			session.dispose()
			Verify.expect(assert(resolve)(anchor, peek)):toBeNil()
		end)
	end

	local function documentWith(kinds: { string }, library: Facet.DesignLibrary): Facet.DesignDocument
		local nextId = 2
		local function seeded(seed: Facet.DesignSeed): Facet.DesignNode
			local props: { [string]: Facet.DesignValue } = {}
			local literals = seed.props
			if literals ~= nil then
				for key, value in literals do
					props[key] = { literal = value }
				end
			end
			local node: Facet.DesignNode =
				{ id = `n{nextId}`, kind = seed.kind, name = `{seed.kind}{nextId}`, props = props, children = {} }
			nextId += 1
			local nested = seed.children
			if nested ~= nil then
				for _, child in nested do
					table.insert(node.children, seeded(child))
				end
			end
			return node
		end
		local children: { Facet.DesignNode } = {}
		for _, name in kinds do
			if library.kinds[name].children == "template" then
				local list = seeded({ kind = name })
				list.bind = { from = "rows", key = "id" }
				if library.kinds[name].template ~= nil then
					local row = seeded({ kind = "Text" })
					row.props.text = { item = "label" }
					table.insert(list.children, row)
				end
				table.insert(children, list)
				continue
			end
			table.insert(children, seeded({ kind = name, children = Kit.seeds(name) }))
		end
		local first: Facet.DesignLiteral = { id = "a", label = "First" }
		local second: Facet.DesignLiteral = { id = "b", label = "Second" }
		local idField: Facet.DesignItemField = { id = "id", type = "string" }
		local labelField: Facet.DesignItemField = { id = "label", type = "string" }
		local preview: Facet.DesignLiteral = { first, second }
		local rows: Facet.DesignInput = {
			id = "rows",
			kind = "value",
			type = "list",
			preview = preview,
			fields = { idField, labelField },
		}
		return {
			schema = "compose-design/1",
			name = "Every control",
			library = library.name,
			nextId = nextId,
			contract = { inputs = { rows }, outputs = {} },
			root = { id = "n1", kind = "ScrollView", name = "Root", props = {}, children = children },
		}
	end

	verifyHarness:suite("Facet library in Compose Design", function()
		local sceneProperties: { [string]: { [string]: Facet.DesignLiteral } } = {
			Part = {
				Color = "#123456",
				Transparency = 0.4,
				Anchored = true,
				CanCollide = false,
				CastShadow = false,
				Reflectance = 0.2,
				MaterialVariant = "OakFloor",
				Shape = "Ball",
			},
			PointLight = { Color = "#123456", Brightness = 3, Range = 24, Shadows = true, Enabled = false },
			SurfaceLight = {
				Color = "#123456",
				Brightness = 3,
				Range = 24,
				Shadows = true,
				Enabled = false,
				Face = "Top",
				Angle = 75,
			},
			Decal = { Texture = "rbxassetid://123", Color3 = "#123456", Transparency = 0.4, Face = "Front", ZIndex = 2 },
			Texture = {
				Texture = "rbxassetid://123",
				Color3 = "#123456",
				Transparency = 0.4,
				Face = "Top",
				ZIndex = 2,
				StudsPerTileU = 3,
				StudsPerTileV = 4,
				OffsetStudsU = 1,
				OffsetStudsV = 2,
			},
		}
		for className, properties in sceneProperties do
			verifyHarness:case("authors native scene properties for " .. className, {
				id = "facet_compose_library::authors native scene properties for " .. className,
				run = function(test: Verify.Context)
					local amount = Facet.Compose.cell<<Facet.DesignLiteral?>>(0.4)
					local target: { [string]: unknown }? = nil
					test:defer(mount(function(ctx: Context): unknown
						local Host = ctx.runtime.constructors
						local library = Kit.library({
							UI = ctx.UI,
							types = ctx.types,
							space = "3d",
							host = function(name: string, layer: string, props: { [unknown]: unknown }): unknown
								return Host[name](props, layer)
							end,
						})
						local value = Design.document.new("SceneProperties", library, "Part")
						local id = "n1"
						if className ~= "Part" then
							value, id = Design.document.insert(value, library, id, className)
						end
						for key, literal in properties do
							value = Design.document.change(value, library, id, key, { literal = literal })
						end
						value = Design.document.setContract(value, library, {
							inputs = { { id = "amount", kind = "readable", type = "number" } },
							outputs = {},
						})
						local liveProperty = if className == "Part"
							then "Reflectance"
							elseif className == "PointLight" or className == "SurfaceLight" then "Brightness"
							else "Transparency"
						value = Design.document.change(value, library, id, liveProperty, { input = "amount" })
						local code = Design.emit(value, library)
						Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
						local built = Design.render(value, library, { bindings = { amount = { readable = amount } } })
						assert(typeof(built) == "Instance")
						local node = if className == "Part"
							then built
							else assert(built:FindFirstChildWhichIsA(className))
						local actual = (node :: unknown) :: { [string]: unknown }
						for key, literal in properties do
							local expected: unknown = if key == liveProperty then 0.4 else literal
							if key == "Color" or key == "Color3" then
								expected = ctx.types.Color3.fromHex("123456")
							elseif key == "Shape" then
								expected = ctx.types.Enum.PartType.Ball
							elseif key == "Face" then
								expected = if literal == "Top"
									then ctx.types.Enum.NormalId.Top
									else ctx.types.Enum.NormalId.Front
							end
							Verify.expect(actual[key]):toBe(expected)
						end
						target = actual
						return built
					end).dispose)
					amount:set(0.7)
					local key = if className == "Part"
						then "Reflectance"
						elseif className == "PointLight" or className == "SurfaceLight" then "Brightness"
						else "Transparency"
					Verify.expect(assert(target)[key]):toBe(0.7)
				end,
			})
		end

		verifyHarness:case("keeps native TextSize live beside a typography role", {
			id = "facet_compose_library::keeps native TextSize live beside a typography role",
			run = function(test: Verify.Context)
				local size = Facet.Compose.cell<<Facet.DesignLiteral?>>(23)
				local label: TextLabel? = nil
				test:defer(mount(function(ctx: Context): unknown
					local library = live(ctx)
					local value = Design.document.new("SizedText", library, "Text")
					value = Design.document.setContract(value, library, {
						inputs = { { id = "size", kind = "readable", type = "number" } },
						outputs = {},
					})
					value = Design.document.change(value, library, "n1", "textRole", { literal = "title" })
					value = Design.document.change(value, library, "n1", "textSize", { literal = 17 })
					value = Design.document.change(value, library, "n1", "TextSize", { input = "size" })
					local code = Design.emit(value, library)
					Verify.expect(string.find(code, "TextSize = props.size", 1, true) ~= nil):toBe(true)
					Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
					local built = Design.render(value, library, { bindings = { size = { readable = size } } })
					assert(typeof(built) == "Instance" and built:IsA("TextLabel"))
					Verify.expect(built:HasTag("facet-type-title")):toBe(true)
					Verify.expect(built.TextSize):toBe(23)
					label = built
					local Host = ctx.runtime.constructors
					local sheet =
						Facet.themes.createStyleSheet(ctx.runtime, Facet.themes.neutralPackage(), { types = ctx.types })
					return Host.Frame { sheet, Host.StyleLink { StyleSheet = Facet.Compose.static(sheet) }, built }
				end).dispose)
				Verify.expect(assert(label):GetStyled("TextSize")):toBe(23)
				size:set(31)
				Verify.expect(assert(label).TextSize):toBe(31)
				Verify.expect(assert(label):GetStyled("TextSize")):toBe(31)
			end,
		})

		verifyHarness:case("binds tag lists until the Compose owner is disposed", {
			id = "facet_compose_library::binds tag lists until the Compose owner is disposed",
			run = function(test: Verify.Context)
				local tags = Facet.Compose.cell({ "consumer-owned", "first", "second" })
				local direct = Facet.Compose.cell<<string | { string }>>("direct")
				local evaluations = 0
				local node: Frame? = nil
				local mounted = mount(function(ctx: Context): unknown
					local frame = ctx.UI.HStack {}
					Facet.tag(frame, "consumer-owned")
					Facet.tag(frame, { "fixed" })
					Facet.tag(frame, direct)
					Facet.tag(frame, function(use: Facet.Use): { string }
						evaluations += 1
						return use(tags)
					end)
					node = frame
					return frame
				end)
				test:defer(mounted.dispose)
				local frame = assert(node)
				Verify.expect(frame:HasTag("first")):toBe(true)
				Verify.expect(frame:HasTag("second")):toBe(true)
				Verify.expect(frame:HasTag("direct")):toBe(true)
				direct:set({ "updated" })
				Verify.expect(frame:HasTag("direct")):toBe(false)
				Verify.expect(frame:HasTag("updated")):toBe(true)
				tags:set({ "second", "third" })
				Verify.expect(frame:HasTag("first")):toBe(false)
				Verify.expect(frame:HasTag("second")):toBe(true)
				Verify.expect(frame:HasTag("third")):toBe(true)
				tags:set({})
				Verify.expect(frame:HasTag("second")):toBe(false)
				Verify.expect(frame:HasTag("third")):toBe(false)
				Verify.expect(frame:HasTag("consumer-owned")):toBe(true)
				Verify.expect(frame:HasTag("fixed")):toBe(true)
				mounted.dispose()
				local stoppedAt = evaluations
				tags:set({ "late" })
				Verify.expect(evaluations):toBe(stoppedAt)
			end,
		})

		verifyHarness:case("accepts emitted bound tag formulas and replaces owned tags", {
			id = "facet_compose_library::accepts emitted bound tag formulas and replaces owned tags",
			run = function(test: Verify.Context)
				local current = Facet.Compose.cell({ id = "rail", paint = "rail-hot" })
				local rail: Frame? = nil
				test:defer(mount(function(ctx: Context): unknown
					local library = live(ctx)
					local value = Design.document.new("Rail", library, "HStack")
					value = Design.document.setContract(value, library, {
						inputs = {
							{
								id = "rails",
								kind = "readable",
								type = "list",
								fields = { { id = "id", type = "string" }, { id = "paint", type = "string" } },
							},
						},
						outputs = {},
					})
					local child
					value, child = Design.document.insert(value, library, "n1", "HStack")
					value = Design.document.bind(value, library, "n1", { from = "rails", key = "id" })
					value = Design.document.bindTags(value, library, child, { item = "paint" })
					local code = Design.emit(value, library)
					Verify.expect(string.find(code, "return use(current).paint", 1, true) ~= nil):toBe(true)
					Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
					local node = ctx.UI.HStack "Rail" {}
					node:AddTag("consumer-owned")
					Verify.expect(Facet.tag(node, function(use: Facet.Use): string
						return use(current).paint
					end)):toBe(node)
					rail = node
					Verify.expect(node:HasTag("rail-hot")):toBe(true)
					return node
				end).dispose)
				current:set({ id = "rail", paint = "rail-cold" })
				local node = assert(rail)
				Verify.expect(node:HasTag("rail-hot")):toBe(false)
				Verify.expect(node:HasTag("rail-cold")):toBe(true)
				Verify.expect(node:HasTag("consumer-owned")):toBe(true)
			end,
		})

		verifyHarness:case("replaces bound input tags through public Design rendering", {
			id = "facet_compose_library::replaces bound input tags through public Design rendering",
			run = function(test: Verify.Context)
				local paint = Facet.Compose.cell<<Facet.DesignLiteral?>>("rail-hot")
				local rail: Instance? = nil
				test:defer(mount(function(ctx: Context): unknown
					local library = live(ctx)
					local value = Design.document.new("Rail", library, "HStack")
					value = Design.document.setContract(value, library, {
						inputs = { { id = "paint", kind = "readable", type = "string" } },
						outputs = {},
					})
					value = Design.document.bindTags(value, library, "n1", { input = "paint" })
					local code = Design.emit(value, library)
					Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
					local built = Design.render(value, library, { bindings = { paint = { readable = paint } } })
					assert(typeof(built) == "Instance")
					built:AddTag("consumer-owned")
					rail = built
					Verify.expect(built:HasTag("rail-hot")):toBe(true)
					return built
				end).dispose)
				paint:set("rail-cold")
				local node = assert(rail)
				Verify.expect(node:HasTag("rail-hot")):toBe(false)
				Verify.expect(node:HasTag("rail-cold")):toBe(true)
				Verify.expect(node:HasTag("consumer-owned")):toBe(true)
			end,
		})

		verifyHarness:case("authors NavBar trailing as content and a caller slot", {
			id = "facet_compose_library::authors NavBar trailing as content and a caller slot",
			run = function(test: Verify.Context)
				for _, form in { "child", "slot", "direct" } do
					test:defer(mount(function(ctx: Context): unknown
						if form == "direct" then
							local action = ctx.UI.Button "Action" { label = "Filter" }
							return ctx.UI.NavBar { title = "Collection", trailing = action }
						end
						local library = live(ctx)
						local value = Design.document.new("Navigation", library, "NavBar")
						if form == "child" then
							value = Design.document.content(value, library, "n1", "trailing", "Button")
						else
							value = Design.document.setContract(value, library, {
								inputs = { { id = "actions", kind = "value", type = "slot", required = true } },
								outputs = {},
							})
							value = Design.document.change(value, library, "n1", "trailing", { input = "actions" })
						end
						local code = Design.emit(value, library)
						Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
						local calls = 0
						local built = Design.render(value, library, {
							bindings = {
								actions = {
									slot = function(): unknown
										calls += 1
										return ctx.UI.Button "Action" { label = "Filter" }
									end,
								},
							},
						})
						assert(typeof(built) == "Instance")
						local trailing = assert(built:FindFirstChild("Trailing"))
						Verify.expect(trailing:FindFirstChildWhichIsA("TextButton") ~= nil):toBe(true)
						Verify.expect(calls):toBe(if form == "slot" then 1 else 0)
						return built
					end).dispose)
				end
			end,
		})

		verifyHarness:case("authors TextInput trailing as content and a caller slot", {
			id = "facet_compose_library::authors TextInput trailing as content and a caller slot",
			run = function(test: Verify.Context)
				for _, form in { "child", "slot" } do
					test:defer(mount(function(ctx: Context): unknown
						local library = live(ctx)
						local value = Design.document.new("Search", library, "TextInput")
						if form == "child" then
							value = Design.document.content(value, library, "n1", "trailing", "Button")
						else
							value = Design.document.setContract(value, library, {
								inputs = { { id = "find", kind = "value", type = "slot", required = true } },
								outputs = {},
							})
							value = Design.document.change(value, library, "n1", "trailing", { input = "find" })
						end
						local code = Design.emit(value, library)
						Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
						local calls = 0
						local built = Design.render(value, library, {
							bindings = {
								find = {
									slot = function(): unknown
										calls += 1
										return ctx.UI.Button "Find" { label = "Find" }
									end,
								},
							},
						})
						assert(typeof(built) == "Instance")
						Verify.expect(built:FindFirstChildWhichIsA("TextButton", true) ~= nil):toBe(true)
						Verify.expect(calls):toBe(if form == "slot" then 1 else 0)
						return built
					end).dispose)
				end
			end,
		})

		verifyHarness:case("round trips and renders capped natural layout dimensions", function(test)
			for _, kind in { "ScrollView", "VStack", "HStack", "ZStack", "AdaptiveStack" } do
				test:defer(mount(function(ctx)
					local library = live(ctx)
					local document = Design.document.new("CappedPanel", library, kind)
					document = Design.document.setContract(document, library, {
						inputs = { { id = "limit", kind = "readable", type = "number", preview = 240 } },
						outputs = {},
					})
					document =
						Design.document.change(document, library, document.root.id, "height", { literal = "hug" })
					document =
						Design.document.change(document, library, document.root.id, "maxWidth", { literal = 320 })
					document =
						Design.document.change(document, library, document.root.id, "maxHeight", { input = "limit" })
					local source = Design.emit(document, library, { name = document.name })
					local parsed = Design.parse(source, library)
					Verify.expect(Design.emit(parsed, library, { name = parsed.name })):toBe(source)
					Verify.expect(source):toContain("maxHeight = props.limit")
					Verify.expect(source):toContain("maxWidth = 320")
					local limit = Facet.Compose.cell<<Facet.DesignLiteral?>>(240)
					local built = Design.render(parsed, library, { bindings = { limit = { readable = limit } } })
					assert(typeof(built) == "Instance")
					local constraint = assert(built:FindFirstChildWhichIsA("UISizeConstraint"))
					Verify.expect(constraint.MaxSize.X):toBe(320)
					Verify.expect(constraint.MaxSize.Y):toBe(240)
					limit:set(120)
					Verify.expect(constraint.MaxSize.Y):toBe(120)
					local tokenLibrary = Kit.library({
						UI = ctx.UI,
						types = ctx.types,
						tokens = { path = "T.", require = "local T = require(game.ReplicatedStorage.Tokens)" },
					})
					local tokenDocument =
						Design.document.change(document, tokenLibrary, document.root.id, "maxHeight", {
							token = "size.panelHeight",
						})
					local tokenSource = Design.emit(tokenDocument, tokenLibrary, { name = tokenDocument.name })
					Verify.expect(tokenSource):toContain("maxHeight = T.size.panelHeight")
					Verify.expect(
						Design.emit(
							Design.parse(tokenSource, tokenLibrary),
							tokenLibrary,
							{ name = tokenDocument.name }
						)
					)
						:toBe(tokenSource)
					return built
				end).dispose)
			end
		end)

		verifyHarness:case("round trips Button hover and selection actions without activation", {
			id = "facet_compose_library::round trips Button hover and selection actions without activation",
			run = function(test: Verify.Context)
				local exercise: (() -> ())? = nil
				test:defer(mount(function(ctx: Context, engine: Engine): unknown
					local library = live(ctx)
					local value =
						Design.document.setContract(Design.document.new("Preview", library, "Button"), library, {
							inputs = {},
							outputs = {
								{ id = "onEnter", args = { "number", "number" } },
								{ id = "onLeave", args = { "number", "number" } },
								{ id = "onFocus" },
								{ id = "onActivate" },
							},
						})
					local events: { [string]: string } = {
						MouseEnter = "onEnter",
						MouseLeave = "onLeave",
						SelectionGained = "onFocus",
					}
					for event, output in events do
						value = Design.document.change(value, library, "n1", event, { output = output })
					end
					value = Design.document.change(value, library, "n1", "onActivate", { output = "onActivate" })
					local source = Design.emit(value, library)
					local parsed = Design.parse(source, library)
					Verify.expect(Design.emit(parsed, library)):toBe(source)
					for event, output in events do
						Verify.expect(Kit.controls.Button.fields[event].type):toBe("event")
						Verify.expect(library.kinds.Button.fields[event].type):toBe("event")
						Verify.expect(parsed.root.props[event].output):toBe(output)
					end
					local entered, left, focused, activated = 0, 0, 0, 0
					local built = Design.render(parsed, library, {
						outputs = {
							onEnter = function(args: { Facet.DesignLiteral })
								entered += 1
								Verify.expect(args):toEqual({ 24, 36 })
							end,
							onLeave = function(args: { Facet.DesignLiteral })
								left += 1
								Verify.expect(args):toEqual({ 140, 90 })
							end,
							onFocus = function(args: { Facet.DesignLiteral })
								focused += 1
								Verify.expect(args):toEqual({})
							end,
							onActivate = function()
								activated += 1
							end,
						},
					})
					assert(typeof(built) == "Instance" and built:IsA("TextButton"))
					exercise = function()
						engine.environment.fire(VerifyRoblox.assertInstance(built), "MouseEnter", 24, 36)
						Verify.expect(entered):toBe(1)
						Verify.expect(left):toBe(0)
						Verify.expect(focused):toBe(0)
						engine.environment.fire(VerifyRoblox.assertInstance(built), "MouseLeave", 140, 90)
						engine.environment.fire(VerifyRoblox.assertInstance(built), "SelectionGained")
						ctx.runtime:settle()
						Verify.expect(entered):toBe(1)
						Verify.expect(left):toBe(1)
						Verify.expect(focused):toBe(1)
						Verify.expect(activated):toBe(0)
						engine.environment.fire(VerifyRoblox.assertInstance(built), "Activated")
						Verify.expect(activated):toBe(1)
					end
					return built
				end).dispose)
				assert(exercise)()
			end,
		})

		verifyHarness:case("round trips Sheet initialFocus and selects the named action on opening", {
			id = "facet_compose_library::round trips Sheet initialFocus and selects the named action on opening",
			run = function(test: Verify.Context)
				local shown = Facet.Compose.cell(false)
				local world = overlay.new(function(UI, _Host, engine)
					local library = live({ UI = UI, types = engine.types })
					local value =
						Design.document.setContract(Design.document.new("Actions", library, "Sheet"), library, {
							inputs = { { id = "shown", kind = "cell", type = "boolean", required = true } },
							outputs = {},
						})
					value = Design.document.change(value, library, "n1", "isPresented", { input = "shown" })
					value = Design.document.change(value, library, "n1", "placement", { literal = "center" })
					value = Design.document.change(value, library, "n1", "closeButton", { literal = true })
					local body: string
					value, body = Design.document.insert(value, library, "n1", "VStack")
					for _, name in { "First", "Chosen" } do
						local action: string
						value, action = Design.document.insert(value, library, body, "Button")
						value = Design.document.rename(value, library, action, name)
					end
					value = Design.document.change(value, library, "n1", "initialFocus", { literal = "Chosen" })
					local source = Design.emit(value, library)
					local parsed = Design.parse(source, library)
					Verify.expect(Design.emit(parsed, library)):toBe(source)
					Verify.expect(Kit.controls.Sheet.fields.initialFocus.type):toBe("string")
					Verify.expect(library.kinds.Sheet.fields.initialFocus.type):toBe("string")
					Verify.expect(parsed.root.props.initialFocus.literal):toBe("Chosen")
					local built = Design.render(parsed, library, { bindings = { shown = { readable = shown } } })
					assert(typeof(built) == "Instance")
					return built
				end, { motionLevel = "none" })
				test:defer(world.stop)
				world.engine.environment.poke(world.input, "PreferredInput", world.Enum.PreferredInput.Gamepad)
				Verify.expect(world.gui.SelectedObject):toBe(nil)
				for _ = 1, 2 do
					shown:set(true)
					world.advance(1 / 60, 3)
					local chosen = world.find("Chosen")
					Verify.expect(chosen ~= nil):toBe(true)
					Verify.expect(if world.gui.SelectedObject then world.gui.SelectedObject.Name else "nil")
						:toBe("Chosen")
					Verify.expect(world.gui.SelectedObject == chosen):toBe(true)
					shown:set(false)
					world.advance(1 / 60, 3)
				end
			end,
		})

		verifyHarness:case("forwards native TextInput edits and focus through Design events", {
			id = "facet_compose_library::forwards native TextInput edits and focus through Design events",
			run = function(test: Verify.Context)
				local exercise: (() -> ())? = nil
				test:defer(mount(function(ctx: Context, engine: Engine): unknown
					local library = live(ctx)
					local value =
						Design.document.setContract(Design.document.new("Editor", library, "VStack"), library, {
							inputs = {
								{
									id = "rows",
									kind = "readable",
									type = "list",
									required = true,
									fields = { { id = "rowKey", type = "string" }, { id = "text", type = "string" } },
								},
							},
							outputs = {
								{ id = "onEdit", args = { "string" } },
								{ id = "onFocus", args = { "string" } },
							},
						})
					local rowId: string
					value, rowId = Design.document.insert(value, library, "n1", "TextInput")
					value = Design.document.bind(value, library, "n1", { from = "rows", key = "rowKey" })
					value = Design.document.change(value, library, rowId, "value", { item = "text" })
					value = Design.document.change(value, library, rowId, "onChange", { output = "onEdit" })
					value = Design.document.change(
						value,
						library,
						rowId,
						"Focused",
						{ output = "onFocus", fields = { "rowKey" } }
					)
					local source = Design.emit(value, library)
					local parsed = Design.parse(source, library)
					Verify.expect(Design.emit(parsed, library)):toBe(source)
					local row = { rowKey = "r1", text = "Before" }
					local edits, focused = 0, 0
					local built = Design.render(parsed, library, {
						inputs = { rows = { row } },
						outputs = {
							onEdit = function(args: { Facet.DesignLiteral })
								edits += 1
								Verify.expect(args):toEqual({ "After" })
							end,
							onFocus = function(args: { Facet.DesignLiteral })
								focused += 1
								Verify.expect(args):toEqual({ "r1" })
							end,
						},
					})
					assert(typeof(built) == "Instance")
					local input = assert(built:FindFirstChild("TextInput", true))
					assert(input:IsA("TextBox"))
					exercise = function()
						engine.environment.fire(VerifyRoblox.assertInstance(input), "Focused")
						input.Text = "After"
						ctx.runtime:settle()
						Verify.expect(edits):toBe(1)
						Verify.expect(focused):toBe(1)
						Verify.expect(row.text):toBe("Before")
					end
					return built
				end).dispose)
				assert(exercise)()
			end,
		})

		verifyHarness:case("round trips Toggle requests from readable inputs to one named host action", {
			id = "facet_compose_library::round trips Toggle requests from readable inputs to one named host action",
			run = function(test: Verify.Context)
				test:defer(mount(function(ctx: Context, engine: Engine): unknown
					local library = live(ctx)
					Verify.expect(Kit.controls.Toggle.fields.onChange.type):toBe("event")
					Verify.expect(library.kinds.Toggle.fields.onChange.type):toBe("event")
					local value =
						Design.document.setContract(Design.document.new("Setting", library, "Toggle"), library, {
							inputs = { { id = "checked", kind = "readable", type = "boolean", required = true } },
							outputs = { { id = "onChecked", args = { "boolean" } } },
						})
					value = Design.document.change(value, library, "n1", "presentation", { literal = "button" })
					value = Design.document.change(value, library, "n1", "value", { input = "checked" })
					value = Design.document.change(value, library, "n1", "onChange", { output = "onChecked" })
					local source = Design.emit(value, library)
					local parsed = Design.parse(source, library)
					Verify.expect(Design.emit(parsed, library)):toBe(source)
					Verify.expect(parsed.root.props.value.input):toBe("checked")
					Verify.expect(parsed.root.props.onChange.output):toBe("onChecked")
					local checked = Facet.Compose.cell(false)
					local readable = Facet.Compose.formula(function(use: Facet.Use): boolean
						return use(checked)
					end)
					local calls = 0
					local built = Design.render(parsed, library, {
						bindings = { checked = { readable = readable } },
						outputs = {
							onChecked = function(args: { Facet.DesignLiteral })
								calls += 1
								Verify.expect(args):toEqual({ true })
								local nextValue = args[1]
								assert(type(nextValue) == "boolean")
								checked:set(nextValue)
							end,
						},
					})
					assert(typeof(built) == "Instance" and built:IsA("TextButton"))
					Verify.expect(built:HasTag("facet-selected")):toBe(false)
					engine.environment.fire(VerifyRoblox.assertInstance(built), "Activated")
					Verify.expect(calls):toBe(1)
					Verify.expect(checked:peek()):toBe(true)
					Verify.expect(built:HasTag("facet-selected")):toBe(true)
					checked:set(false)
					Verify.expect(built:HasTag("facet-selected")):toBe(false)
					Verify.expect(calls):toBe(1)
					return built
				end).dispose)
			end,
		})

		verifyHarness:case("round trips generic Picker changes with readable options and one named host action", {
			id = "facet_compose_library::round trips generic Picker changes with readable options and one named host action",
			run = function(test: Verify.Context)
				test:defer(mount(function(ctx: Context, engine: Engine): unknown
					local library = live(ctx)
					Verify.expect(Kit.controls.Picker.fields.onChange.type):toBe("event")
					Verify.expect(library.kinds.Picker.fields.onChange.type):toBe("event")
					local value =
						Design.document.setContract(Design.document.new("Setting", library, "Picker"), library, {
							inputs = {
								{ id = "selected", kind = "cell", type = "string", required = true },
								{
									id = "options",
									kind = "readable",
									type = "list",
									required = true,
									fields = { { id = "label", type = "string" }, { id = "value", type = "string" } },
								},
							},
							outputs = { { id = "onSelected", args = { "string" } } },
						})
					value = Design.document.change(value, library, "n1", "selected", { input = "selected" })
					value = Design.document.change(value, library, "n1", "options", { input = "options" })
					value = Design.document.change(value, library, "n1", "onChange", { output = "onSelected" })
					local source = Design.emit(value, library)
					local parsed = Design.parse(source, library)
					Verify.expect(Design.emit(parsed, library)):toBe(source)
					Verify.expect(parsed.root.props.options.input):toBe("options")
					Verify.expect(parsed.root.props.onChange.output):toBe("onSelected")
					local selected = Facet.Compose.cell("first")
					local options: Facet.DesignLiteral = {
						{ label = "First", value = "first" },
						{ label = "Second", value = "second" },
					}
					local sourceOptions = Facet.Compose.cell(options)
					local readableOptions = Facet.Compose.formula(function(use: Facet.Use): Facet.DesignLiteral
						return use(sourceOptions)
					end)
					local calls = 0
					local built = Design.render(parsed, library, {
						bindings = { selected = { readable = selected }, options = { readable = readableOptions } },
						outputs = {
							onSelected = function(args: { Facet.DesignLiteral })
								calls += 1
								Verify.expect(args):toEqual({ "second" })
								Verify.expect(selected:peek()):toBe("second")
							end,
						},
					})
					assert(typeof(built) == "Instance")
					local second = assert(built:FindFirstChild("second", true))
					assert(second:IsA("TextButton"))
					Verify.expect(second:HasTag("facet-selected")):toBe(false)
					engine.environment.fire(VerifyRoblox.assertInstance(second), "Activated")
					Verify.expect(calls):toBe(1)
					Verify.expect(selected:peek()):toBe("second")
					Verify.expect(second:HasTag("facet-selected")):toBe(true)
					engine.environment.fire(VerifyRoblox.assertInstance(second), "Activated")
					Verify.expect(calls):toBe(1)
					selected:set("first")
					Verify.expect(second:HasTag("facet-selected")):toBe(false)
					Verify.expect(calls):toBe(1)
					sourceOptions:set({ { label = "First", value = "first" }, { label = "Updated", value = "second" } })
					local label = assert(second:FindFirstChild("Title", true))
					assert(label:IsA("TextLabel"))
					Verify.expect(label.Text):toBe("Updated")
					Verify.expect(calls):toBe(1)
					return built
				end).dispose)
			end,
		})

		verifyHarness:case("imports edits exports and renders readable group transparency", {
			id = "facet_compose_library::imports edits exports and renders readable group transparency",
			run = function(test: Verify.Context)
				test:defer(mount(function(ctx: Context): unknown
					local library = live(ctx)
					Verify.expect(library.kinds.Group.children):toBe("list")
					Verify.expect(library.kinds.Group.fields.groupTransparency.type):toBe("number")
					local value = Design.document.setContract(Design.document.new("Strip", library, "Group"), library, {
						inputs = { { id = "dim", kind = "readable", type = "number", required = true } },
						outputs = {},
					})
					for _, kind in { "Image", "Text", "Button" } do
						value = Design.document.insert(value, library, "n1", kind)
					end
					value = Design.document.change(value, library, "n1", "groupTransparency", { input = "dim" })
					local source = Design.emit(value, library)
					value = Design.parse(source, library)
					Verify.expect(Design.emit(value, library)):toBe(source)
					value = Design.document.change(value, library, "n1", "groupTransparency", { literal = 0.7 })
					local edited = Design.emit(value, library)
					Verify.expect(Design.emit(Design.parse(edited, library), library)):toBe(edited)
					Verify.expect(edited == source):toBe(false)
					value = Design.document.change(value, library, "n1", "groupTransparency", { input = "dim" })
					Verify.expect(Design.emit(value, library)):toBe(source)
					local dim = Facet.Compose.cell(0.4)
					local built = Design.render(value, library, { bindings = { dim = { readable = dim } } })
					assert(typeof(built) == "Instance" and built:IsA("CanvasGroup"))
					Verify.expect(built.GroupTransparency):toBe(0.4)
					Verify.expect(built:FindFirstChild("Image") ~= nil):toBe(true)
					Verify.expect(built:FindFirstChild("Text") ~= nil):toBe(true)
					Verify.expect(built:FindFirstChild("Button") ~= nil):toBe(true)
					dim:set(0.8)
					Verify.expect(built.GroupTransparency):toBe(0.8)
					return built
				end).dispose)
			end,
		})

		verifyHarness:case("keeps Pagination native children through source and rendering", {
			id = "facet_compose_library::keeps Pagination native children through source and rendering",
			run = function(test: Verify.Context)
				test:defer(mount(function(ctx: Context): unknown
					local Host = ctx.runtime.constructors
					local library = Kit.library({
						UI = ctx.UI,
						types = ctx.types,
						host = function(className: string, name: string, props: { [unknown]: unknown }): unknown
							return Host[className](props, name)
						end,
					})
					Verify.expect(library.kinds.Pagination.children):toBe("list")
					Verify.expect(Kit.seeds("Pagination")):toHaveLength(0)
					local value, fill = Design.document.insert(
						Design.document.new("Pages", library, "Pagination"),
						library,
						"n1",
						"UIFlexItem"
					)
					value = Design.document.change(value, library, fill, "FlexMode", { literal = "Fill" })
					local code = Design.emit(value, library)
					Verify.expect(string.find(code, 'Host.UIFlexItem "UIFlexItem"', 1, true) ~= nil):toBe(true)
					local parsed = Design.parse(code, library)
					Verify.expect(Design.emit(parsed, library)):toBe(code)
					local built = Design.render(parsed, library)
					assert(typeof(built) == "Instance" and built:IsA("Frame"))
					local actual = assert(built:FindFirstChildWhichIsA("UIFlexItem"))
					Verify.expect(actual.FlexMode):toBe(ctx.types.Enum.UIFlexMode.Fill)
					return built
				end).dispose)
			end,
		})

		verifyHarness:case("round trips and renders native room scene kinds", {
			id = "facet_compose_library::round trips and renders native room scene kinds",
			run = function(test: Verify.Context)
				local initial: Facet.DesignLiteral? = 2
				local brightness = Facet.Compose.cell(initial)
				local light: PointLight? = nil
				test:defer(mount(function(ctx: Context): unknown
					local Host = ctx.runtime.constructors
					local library = Kit.library({
						UI = ctx.UI,
						types = ctx.types,
						space = "3d",
						host = function(className: string, name: string, props: { [unknown]: unknown }): unknown
							return Host[className](props, name)
						end,
					})
					Verify.expect(library.space):toBe("3d")
					Verify.expect(library.containerKind):toBe("Model")
					Verify.expect(library.kinds.PointLight.children):toBe("none")
					local value = Design.document.new("RoomScene", library, "Model")
					value = Design.document.setContract(value, library, {
						inputs = { { id = "brightness", kind = "readable", type = "number" } },
						outputs = {},
					})
					local part, lamp
					value, part = Design.document.insert(value, library, "n1", "Part")
					local properties: { [string]: Facet.DesignLiteral } = {
						CFrame = { 2, 3, 4, 0, 0, -1, 0, 1, 0, 1, 0, 0 },
						Size = { 12, 1, 10 },
						Color = "#334455",
						Material = "WoodPlanks",
						Transparency = 0.25,
						Anchored = true,
						CanCollide = false,
					}
					for key, literal in properties do
						value = Design.document.change(value, library, part, key, { literal = literal })
					end
					value, lamp = Design.document.insert(value, library, part, "PointLight")
					value = Design.document.change(value, library, lamp, "Brightness", { input = "brightness" })
					value = Design.document.change(value, library, lamp, "Range", { literal = 24 })
					value = Design.document.change(value, library, lamp, "Color", { literal = "#FFE8C2" })
					local code = Design.emit(value, library)
					for _, expected in
						{
							"): Instance",
							'Host.Model "Model"',
							'Host.Part "Part"',
							'Host.PointLight "PointLight"',
							"CFrame = CFrame.new(2, 3, 4, 0, 0, -1, 0, 1, 0, 1, 0, 0)",
							"Size = Vector3.new(12, 1, 10)",
							"Material = Enum.Material.WoodPlanks",
						}
					do
						Verify.expect(string.find(code, expected, 1, true) ~= nil):toBe(true)
					end
					local parsed = Design.parse(code, library)
					Verify.expect(Design.emit(parsed, library)):toBe(code)
					local built =
						Design.render(parsed, library, { bindings = { brightness = { readable = brightness } } })
					assert(typeof(built) == "Instance" and built:IsA("Model"))
					local actual = assert(built:FindFirstChildWhichIsA("Part"))
					Verify.expect(actual.CFrame):toBe(ctx.types.CFrame.new(2, 3, 4, 0, 0, -1, 0, 1, 0, 1, 0, 0))
					Verify.expect(actual.Size):toBe(ctx.types.Vector3.new(12, 1, 10))
					Verify.expect(actual.Color):toBe(ctx.types.Color3.fromHex("334455"))
					Verify.expect(actual.Material):toBe(ctx.types.Enum.Material.WoodPlanks)
					Verify.expect(actual.Transparency):toBe(0.25)
					Verify.expect(actual.Anchored):toBe(true)
					Verify.expect(actual.CanCollide):toBe(false)
					local actualLight = assert(actual:FindFirstChildWhichIsA("PointLight"))
					Verify.expect(actualLight.Brightness):toBe(2)
					Verify.expect(actualLight.Range):toBe(24)
					Verify.expect(actualLight.Color):toBe(ctx.types.Color3.fromHex("FFE8C2"))
					light = actualLight
					return built
				end).dispose)
				brightness:set(3)
				Verify.expect(assert(light).Brightness):toBe(3)
			end,
		})

		verifyHarness:case("converts native CFrame constructor forms and live components", {
			id = "facet_compose_library::converts native CFrame constructor forms and live components",
			run = function(test: Verify.Context)
				local initial: Facet.DesignLiteral? = 5
				local x = Facet.Compose.cell(initial)
				local part: Part? = nil
				test:defer(mount(function(ctx: Context): unknown
					local Host = ctx.runtime.constructors
					local library = Kit.library({
						UI = ctx.UI,
						types = ctx.types,
						space = "3d",
						host = function(className: string, name: string, props: { [unknown]: unknown }): unknown
							return Host[className](props, name)
						end,
					})
					local value = Design.document.new("Transforms", library, "Part")
					local forms: { Facet.DesignLiteral } = { {}, { 1, 2, 3 }, { 1, 2, 3, 0, 0, 0, 1 } }
					for _, components in forms do
						assert(type(components) == "table")
						value = Design.document.change(value, library, "n1", "CFrame", { literal = components })
						local code = Design.emit(value, library)
						local parsed = Design.parse(code, library)
						Verify.expect(Design.emit(parsed, library)):toBe(code)
						local built = Design.render(parsed, library)
						assert(typeof(built) == "Instance" and built:IsA("Part"))
						Verify.expect(built.CFrame)
							:toBe(if #components == 0 then ctx.types.CFrame.new() else ctx.types.CFrame.new(1, 2, 3))
					end
					value = Design.document.setContract(value, library, {
						inputs = { { id = "x", kind = "readable", type = "number", required = true } },
						outputs = {},
					})
					value =
						Design.document.change(value, library, "n1", "CFrame", { literal = { { input = "x" }, 2, 3 } })
					local code = Design.emit(value, library)
					local parsed = Design.parse(code, library)
					Verify.expect(Design.emit(parsed, library)):toBe(code)
					local built = Design.render(parsed, library, { bindings = { x = { readable = x } } })
					assert(typeof(built) == "Instance" and built:IsA("Part"))
					Verify.expect(built.CFrame.Position.X):toBe(5)
					part = built
					return built
				end).dispose)
				x:set(8)
				Verify.expect(assert(part).CFrame.Position.X):toBe(8)
			end,
		})

		verifyHarness:case("keeps theme-derived Path points through source and rendering", {
			id = "facet_compose_library::keeps theme-derived Path points through source and rendering",
			run = function(test: Verify.Context)
				local pinch = Facet.Compose.cell(0.2)
				local points = Facet.Compose.formula(function(use: Facet.Use): Facet.DesignLiteral?
					return {
						{ x = 0, y = 0.5, inX = 0, inY = 0, outX = use(pinch), outY = 0 },
						{ x = 1, y = 0.5, inX = -use(pinch), inY = 0, outX = 0, outY = 0 },
					}
				end)
				local stroke: Path2D? = nil
				local runtime: Facet.Runtime? = nil
				test:defer(mount(function(ctx: Context): unknown
					runtime = ctx.runtime
					local library = Kit.library({
						UI = ctx.UI,
						types = ctx.types,
						tokens = { path = "T.", require = 'local T = require "../DesignTokens"' },
					})
					local value = Design.document.change(
						Design.document.new("Glyph", library, "Path"),
						library,
						"n1",
						"points",
						{ token = "glyph.sparkle.points" }
					)
					local code = Design.emit(value, library)
					Verify.expect(string.find(code, "points = T.glyph.sparkle.points,", 1, true) ~= nil):toBe(true)
					local parsed = Design.parse(code, library)
					Verify.expect(parsed.root.props.points.token):toBe("glyph.sparkle.points")
					Verify.expect(Design.emit(parsed, library)):toBe(code)
					local built = Design.render(parsed, library, {
						resolveToken = function(name: string): Facet.DesignResolved
							Verify.expect(name):toBe("glyph.sparkle.points")
							return { readable = points }
						end,
					})
					assert(typeof(built) == "Instance")
					local path = assert(built:FindFirstChild("Stroke"))
					assert(path:IsA("Path2D"))
					stroke = path
					return built
				end).dispose)
				Verify.expect(assert(stroke):GetControlPoints()[1].RightTangent.X.Scale):toBeCloseTo(0.2, 1e-6)
				pinch:set(0.35)
				assert(runtime):settle()
				local native = assert(stroke):GetControlPoints()
				Verify.expect(native[1].RightTangent.X.Scale):toBeCloseTo(0.35, 1e-6)
				Verify.expect(native[2].LeftTangent.X.Scale):toBeCloseTo(-0.35, 1e-6)
			end,
		})

		verifyHarness:case("maps a RadialMenu skin token to the public skin prop", {
			id = "facet_compose_library::maps a RadialMenu skin token to the public skin prop",
			run = function(test: Verify.Context)
				test:defer(mount(function(ctx: Context, engine: Engine): unknown
					local library = Kit.library({
						UI = ctx.UI,
						types = ctx.types,
						tokens = { path = "T.", require = 'local T = require "../DesignTokens"' },
					})
					local value = Design.document.change(
						Design.document.new("Commands", library, "RadialMenu"),
						library,
						"n1",
						"skin",
						{ token = "skins.commands" }
					)
					local code = Design.emit(value, library)
					Verify.expect(string.find(code, "skin = T.skins.commands,", 1, true) ~= nil):toBe(true)
					Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
					local built = Design.render(value, library, {
						token = function(name: string): Facet.DesignLiteral
							Verify.expect(name):toBe("skins.commands")
							return { launcher = { default = "rbxassetid://100", hover = "rbxassetid://101" } }
						end,
					})
					assert(typeof(built) == "Instance")
					local launcher = assert(built:FindFirstChild("Launcher", true))
					local skin = assert(launcher:FindFirstChild("RadialSkin", true))
					assert(skin:IsA("ImageLabel"))
					Verify.expect(skin.Image):toBe("rbxassetid://100")
					engine.environment.poke(
						VerifyRoblox.assertInstance(launcher),
						"GuiState",
						ctx.types.Enum.GuiState.Hover
					)
					ctx.runtime:settle()
					Verify.expect(skin.Image):toBe("rbxassetid://101")
					return built
				end).dispose)
			end,
		})

		verifyHarness:case("composes registered host Designs with shared controls and named actions", {
			id = "facet_compose_library::composes registered host Designs with shared controls and named actions",
			run = function(test: Verify.Context)
				test:defer(mount(function(ctx: Context, engine: Engine): unknown
					local balance = Facet.Compose.cell(42)
					local chosen = 0
					local registration: Facet.DesignRegistered = {
						contract = {
							inputs = {
								{ id = "label", kind = "value", type = "string", preview = "Open" },
								{ id = "balance", kind = "readable", type = "number", preview = 0 },
							},
							outputs = { { id = "onChoose" } },
						},
						call = "Game.Surface",
						prelude = { 'local Game = require "../GameDesigns"' },
						build = function(UI: unknown, props: { [string]: unknown }, name: string): unknown
							Verify.expect(UI == ctx.UI):toBe(true)
							Verify.expect(props.balance == balance):toBe(true)
							local label = props.label
							local callback = props.onChoose :: (...Facet.DesignLiteral) -> ()
							assert(type(label) == "string")
							return ctx.UI.Button(name) {
								label = label,
								onActivate = function()
									callback()
								end,
							}
						end,
					}
					local library =
						Kit.library({ UI = ctx.UI, types = ctx.types, designs = { Surface = registration } })
					local value =
						Design.document.setContract(Design.document.new("Parent", library, "VStack"), library, {
							inputs = {
								{ id = "title", kind = "value", type = "string", required = true },
								{ id = "balance", kind = "readable", type = "number", required = true },
							},
							outputs = { { id = "onOpen" } },
						})
					value = Design.document.insert(value, library, "n1", "Surface")
					local child = value.root.children[#value.root.children]
					value = Design.document.change(value, library, child.id, "label", { input = "title" })
					value = Design.document.change(value, library, child.id, "balance", { input = "balance" })
					value = Design.document.change(value, library, child.id, "onChoose", { output = "onOpen" })
					local code = Design.emit(value, library)
					Verify.expect(string.find(code, 'Game.Surface "Surface"', 1, true) ~= nil):toBe(true)
					Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
					local built = Design.render(value, library, {
						inputs = { title = "Edit row" },
						bindings = { balance = { readable = balance } },
						outputs = {
							onOpen = function()
								chosen += 1
							end,
						},
					})
					assert(typeof(built) == "Instance")
					local button = assert(built:FindFirstChild("Surface"))
					assert(button:IsA("TextButton"))
					Verify.expect(button.Text):toBe("Edit row")
					engine.environment.fire(VerifyRoblox.assertInstance(button), "Activated")
					Verify.expect(chosen):toBe(1)
					Verify.expect(offline().kinds.Surface):toBe(nil)
					local collision: Facet.DesignContext = { UI = {}, designs = { Text = registration } }
					local ok = pcall(Kit.library, collision)
					Verify.expect(ok):toBe(false)
					return built
				end).dispose)
			end,
		})

		verifyHarness:case("registers consumer leaves with typed props and lossless source", {
			id = "facet_compose_library::registers consumer leaves with typed props and lossless source",
			run = function(test: Verify.Context)
				test:defer(mount(function(ctx: Context, engine: Engine): unknown
					local activated = 0
					local function Emblem(name: string)
						return function(props: { label: string, onActivate: (InputObject?, number?) -> () }): GuiObject
							return ctx.UI.Button(name) { label = props.label, onActivate = props.onActivate }
						end
					end
					local kind: Facet.DesignKind = {
						fields = { label = { type = "string" }, onActivate = { type = "event" } },
						defaults = { label = "Emblem" },
						children = "none",
						category = "Game",
						call = "Game.Emblem",
						build = function(
							props: { [string]: Facet.DesignResolved },
							_children: { unknown },
							name: string
						): unknown
							local label = props.label.literal
							assert(type(label) == "string")
							local callback = assert(props.onActivate.callback)
							return Emblem(name) {
								label = label,
								onActivate = function()
									callback()
								end,
							}
						end,
					}
					local extension: Facet.DesignExtension =
						{ kinds = { Emblem = kind }, prelude = { 'local Game = require "../GameComponents"' } }
					local library = Kit.library({ UI = ctx.UI, types = ctx.types, extension = extension })
					local value =
						Design.document.setContract(Design.document.new("Badge", library, "Emblem"), library, {
							inputs = { { id = "label", kind = "value", type = "string", required = true } },
							outputs = { { id = "onChoose" } },
						})
					value = Design.document.change(value, library, "n1", "label", { input = "label" })
					value = Design.document.change(value, library, "n1", "onActivate", { output = "onChoose" })
					local code = Design.emit(value, library)
					for _, expected in
						{
							'local Game = require "../GameComponents"',
							'Game.Emblem "Emblem"',
							"label = props.label,",
							"label: string",
						}
					do
						Verify.expect(string.find(code, expected, 1, true) ~= nil):toBe(true)
					end
					local parsed = Design.parse(code, library)
					Verify.expect(parsed.root.kind):toBe("Emblem")
					Verify.expect(Design.emit(parsed, library)):toBe(code)
					local built = Design.render(parsed, library, {
						inputs = { label = "Captain" },
						outputs = {
							onChoose = function()
								activated += 1
							end,
						},
					})
					assert(typeof(built) == "Instance" and built:IsA("TextButton"))
					Verify.expect(built.Text):toBe("Captain")
					engine.environment.fire(VerifyRoblox.assertInstance(built), "Activated")
					Verify.expect(activated):toBe(1)
					Verify.expect(offline().kinds.Emblem):toBe(nil)
					local collision: Facet.DesignContext = { UI = {}, extension = { kinds = { Text = kind } } }
					local ok = pcall(Kit.library, collision)
					Verify.expect(ok):toBe(false)
					return built
				end).dispose)
			end,
		})

		verifyHarness:case("edits a registered consumer leaf in the Design editor", {
			id = "facet_compose_library::edits a registered consumer leaf in the Design editor",
			run = function(test: Verify.Context)
				local DesignEditor = require("../src/vendor/compose/design-editor")
				local editor: DesignEditor.Editor? = nil
				local runtime: Facet.Runtime? = nil
				test:defer(mount(function(ctx: Context, engine: Engine): unknown
					runtime = ctx.runtime
					local library = Kit.library({
						UI = ctx.UI,
						types = ctx.types,
						extension = {
							kinds = {
								Emblem = {
									fields = { label = { type = "string", default = "Emblem" } },
									defaults = { label = "Emblem" },
									children = "none",
									category = "Game",
									call = "Game.Emblem",
									build = function(
										props: { [string]: Facet.DesignResolved },
										_children: { unknown },
										name: string
									): unknown
										local label = props.label.literal
										assert(type(label) == "string")
										return ctx.UI.Text(name) { text = label }
									end,
								},
							},
							prelude = { 'local Game = require "../GameComponents"' },
						},
					})
					local host = ctx.UI.VStack "Editor" { width = "fill" }
					editor = DesignEditor.create(library, Design.document.new("Badge", library, "VStack"), host, {
						runtime = ctx.runtime,
						environment = designEnvironment(ctx, engine),
						stageSize = { X = 480, Y = 320 },
					})
					return host
				end).dispose)
				local opened = assert(editor)
				test:defer(opened.dispose)
				Verify.expect(opened.session.insert("Emblem")):toBe(true)
				Verify.expect(opened.session.change("label", { literal = "Captain" })):toBe(true)
				assert(runtime):settle()
				Verify.expect(opened.session.problem:peek()):toBe(nil)
				local id = opened.session.selected:peek()
				local built = assert(assert(opened.canvas.current().stage).nodes[id])
				assert(typeof(built) == "Instance" and built:IsA("TextLabel"))
				Verify.expect(built.Text):toBe("Captain")
				local code = Design.emit(opened.session.document:peek(), opened.session.library)
				Verify.expect(Design.emit(Design.parse(code, opened.session.library), opened.session.library))
					:toBe(code)
				Verify.expect(opened.session.undo()):toBe(true)
				assert(runtime):settle()
				local restored = assert((Design.document.find(opened.session.document:peek().root, id)))
				Verify.expect(restored.props.label.literal):toBe("Emblem")
			end,
		})

		verifyHarness:case("describes every Facet control as a Compose Design kind", {
			id = "facet_compose_library::describes every Facet control as a Compose Design kind",
			run = function()
				local library = offline()
				local list = names()
				Verify.expect(Kit.controls == FacetDesign.controls):toBe(true)
				Verify.expect(#list):toBeGreaterThan(60)
				for _, name in list do
					Verify.expect(library.kinds[name].call):toBe("UI." .. name)
					Verify.expect(library.kinds[name].category ~= nil):toBe(true)
				end
			end,
		})

		verifyHarness:case("keeps native design field metadata independent across controls", {
			id = "facet_compose_library::keeps native design field metadata independent across controls",
			run = function()
				local seen: { [unknown]: boolean } = {}
				for _, spec in Kit.controls do
					for _, key in
						{
							"BackgroundColor3",
							"BackgroundTransparency",
							"Visible",
							"Rotation",
							"ClipsDescendants",
							"LayoutOrder",
						}
					do
						local field = spec.fields[key]
						if field then
							Verify.expect(seen[field]):toBe(nil)
							seen[field] = true
						end
					end
				end
				Verify.expect(Kit.controls.VirtualList.fields.BackgroundColor3):toEqual({
					type = "color",
					label = "Background color",
					order = 11,
					format = "color",
				})
				Verify.expect(Kit.controls.AdaptiveStack.fields.LayoutOrder):toEqual({
					type = "number",
					label = "Layout order",
					order = 11,
				})
			end,
		})

		verifyHarness:case("inserts every Facet control with its defaults into a valid design", {
			id = "facet_compose_library::inserts every Facet control with its defaults into a valid design",
			run = function()
				local library = offline()
				local failures: { string } = {}
				for _, name in names() do
					local ok, problem = pcall(function()
						local value = Design.document.new("Probe", library, "VStack")
						Design.document.insert(value, library, "n1", name)
					end)
					if not ok then
						table.insert(failures, `{name}: {problem}`)
					end
				end
				Verify.expect(table.concat(failures, "\n")):toBe("")
			end,
		})

		verifyHarness:case("renders every Facet control through Compose Design", {
			id = "facet_compose_library::renders every Facet control through Compose Design",
			run = function()
				local built: { [string]: boolean } = {}
				local misnamed: { string } = {}
				local mounted = mount(function(ctx: Context)
					local library = live(ctx)
					return Design.render(documentWith(names(), library), library, {
						decorate = function(node: Facet.DesignNode, instance: unknown)
							if typeof(instance) == "Instance" then
								built[node.kind] = true
								local named = instance.Name
								if named ~= node.name and named ~= node.name .. "Host" then
									table.insert(misnamed, `{node.kind}: {named} ~= {node.name}`)
								end
							elseif instance ~= nil then
								built[node.kind] = true
							end
						end,
					})
				end)
				for _, name in names() do
					Verify.expect(`{name} {built[name] == true}`):toBe(`{name} true`)
				end
				Verify.expect(table.concat(misnamed, "\n")):toBe("")
				mounted.dispose()
			end,
		})

		verifyHarness:case("edits a Facet design in the Compose design editor", {
			id = "facet_compose_library::edits a Facet design in the Compose design editor",
			run = function()
				local DesignEditor = require("../src/vendor/compose/design-editor")
				local editor: DesignEditor.Editor? = nil
				local runtime: Facet.Runtime? = nil
				local mounted = mount(function(ctx: Context, engine: Engine)
					runtime = ctx.runtime
					local types = ctx.types
					local library = live(ctx)
					local environment = designEnvironment(ctx, engine)
					local host = ctx.UI.VStack "Editor" { width = "fill" }
					editor = DesignEditor.create(library, Design.document.new("Shop", library, "VStack"), host, {
						runtime = ctx.runtime,
						environment = environment,
						stageSize = { X = 480, Y = 320 },
						slots = {
							body = function(): unknown
								return ctx.UI.Text { text = "Prepared" }
							end,
						},
					})
					return host
				end)
				local opened = assert(editor)
				Verify.expect(opened.session.insert("Button")):toBe(true)
				Verify.expect(opened.session.change("label", { literal = "Buy" })):toBe(true)
				local value = opened.session.document:peek()
				local found = Design.document.find(value.root, opened.session.selected:peek())
				assert(found)
				Verify.expect(found.kind):toBe("Button")
				Verify.expect(found.props.label.literal):toBe("Buy")
				Verify.expect(string.find(Design.emit(value, opened.session.library), 'label = "Buy"', 1, true) ~= nil)
					:toBe(true)
				local library = opened.session.library
				for _, kind in { "Dialog", "Sheet", "DisclosureGroup" } do
					opened.session.replace(
						Design.document.setContract(Design.document.new("Prepared", library, kind), library, {
							inputs = { { id = "body", kind = "value", type = "slot", required = true } },
							outputs = {},
						})
					)
					opened.session.select("n1")
					Verify.expect(opened.session.change("content", { input = "body" })):toBe(true)
					assert(runtime):settle()
					Verify.expect(opened.session.problem:peek()):toBe(nil)
					Verify.expect(assert(opened.canvas.current().stage).nodes.n1 ~= nil):toBe(true)
					local code = Design.emit(opened.session.document:peek(), library)
					Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
					Verify.expect(opened.session.content("content", "Text")):toBe(true)
					Verify.expect(opened.session.undo()):toBe(true)
					Verify.expect(opened.session.document:peek().root.props.content.input):toBe("body")
				end
				opened.dispose()
				mounted.dispose()
			end,
		})

		verifyHarness:case("edits every field of every Facet control in the Compose design editor", {
			id = "facet_compose_library::edits every field of every Facet control in the Compose design editor",
			run = function()
				local DesignEditor = require("../src/vendor/compose/design-editor")
				local editor: DesignEditor.Editor? = nil
				local runtime: Facet.Runtime? = nil
				local mounted = mount(function(ctx: Context, engine: Engine)
					local library = live(ctx)
					runtime = ctx.runtime
					local host = ctx.UI.VStack "Editor" { width = "fill" }
					editor = DesignEditor.create(library, Design.document.new("Every", library, "VStack"), host, {
						runtime = ctx.runtime,
						environment = designEnvironment(ctx, engine),
						stageSize = { X = 1280, Y = 720 },
					})
					return host
				end)
				local opened = assert(editor)
				local library = opened.session.library
				local failures: { string } = {}
				local edited = 0
				for _, name in names() do
					opened.session.replace(Design.document.new("Every", library, "VStack"))
					local anchor: string? = nil
					if name == "Callout" then
						opened.session.select("n1")
						Verify.expect(opened.session.insert("Button")):toBe(true)
						anchor = opened.session.selected:peek()
					end
					opened.session.select("n1")
					if not opened.session.insert(name) then
						table.insert(failures, `{name}: insert`)
						continue
					end
					local id = opened.session.selected:peek()
					local kind = library.kinds[name]
					local stage = assert(opened.canvas.current().stage)
					assert(runtime):settle()
					if stage.nodes[id] == nil then
						table.insert(failures, `{name}: {opened.session.problem:peek() or "not rendered"}`)
						continue
					end
					local keys: { string } = {}
					for key in kind.fields do
						table.insert(keys, key)
					end
					table.sort(keys)
					for _, key in keys do
						local defaults = kind.defaults
						local value = sample(kind.fields[key], if defaults then defaults[key] else nil)
						if value ~= nil and value.node ~= nil and anchor ~= nil then
							value.node = anchor
						end
						local field = kind.fields[key]
						local steps = 0
						local pending: { [string]: Facet.DesignValue } = {}
						local requires: { [string]: { Facet.DesignLiteral } } = field.requires or {}
						for other, allowed in requires do
							local needed: Facet.DesignValue? = if #allowed > 0
								then { literal = allowed[1] }
								else sample(kind.fields[other], if defaults then defaults[other] else nil)
							if needed == nil then
								value = nil
							else
								pending[other] = needed
							end
						end
						local progressed = value ~= nil
						while progressed and next(pending) ~= nil do
							progressed = false
							for other, needed in pending do
								opened.session.select(id)
								if opened.session.change(other, needed) then
									steps += 1
									pending[other] = nil
									progressed = true
								end
							end
						end
						if value ~= nil then
							opened.session.select(id)
							local ok, changed = pcall(opened.session.change, key, value)
							assert(runtime):settle()
							if not ok or not changed then
								table.insert(
									failures,
									`{name}.{key}: {if ok then opened.session.problem:peek() else changed}`
								)
							elseif stage.nodes[id] == nil then
								table.insert(
									failures,
									`{name}.{key}: {opened.session.problem:peek() or "not rendered"}`
								)
							else
								edited += 1
							end
							if ok and changed then
								steps += 1
							end
						end
						for _ = 1, steps do
							opened.session.undo()
						end
					end
				end
				Verify.expect(table.concat(failures, "\n")):toBe("")
				Verify.expect(edited):toBeGreaterThan(900)
				opened.dispose()
				mounted.dispose()
			end,
		})

		verifyHarness:case("tags Facet controls for theme rules from Compose Design", {
			id = "facet_compose_library::tags Facet controls for theme rules from Compose Design",
			run = function()
				local tagged: Instance? = nil
				local mounted = mount(function(ctx: Context)
					local library = live(ctx)
					local value, id = Design.document.insert(
						Design.document.new("Tagged", library, "VStack"),
						library,
						"n1",
						"Button"
					)
					value = Design.document.tag(value, library, id, { "amigos-stat" })
					local code = Design.emit(value, library)
					Verify.expect(string.find(code, "Facet.tag(", 1, true) ~= nil):toBe(true)
					Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
					return Design.render(value, library, {
						decorate = function(node: Facet.DesignNode, instance: unknown)
							if node.id == id and typeof(instance) == "Instance" then
								tagged = instance
							end
						end,
					})
				end)
				Verify.expect(assert(tagged):HasTag("amigos-stat")):toBe(true)
				mounted.dispose()
			end,
		})

		verifyHarness:case("writes a game's design tokens as table paths", {
			id = "facet_compose_library::writes a game's design tokens as table paths",
			run = function()
				local library = Kit.library({
					UI = {},
					tokens = {
						path = "T.",
						require = 'local T = require(game:GetService("ReplicatedStorage").Shared.UI.DesignSystem)',
					},
				})
				local value, text =
					Design.document.insert(Design.document.new("Tokens", library, "VStack"), library, "n1", "Text")
				value = Design.document.change(value, library, "n1", "gap", { token = "space.md" })
				value = Design.document.change(value, library, text, "ZIndex", { token = "layer.overlay" })
				local code = Design.emit(value, library, { name = "Tokens" })
				for _, expected in
					{
						'local T = require(game:GetService("ReplicatedStorage").Shared.UI.DesignSystem)',
						"gap = T.space.md,",
						"ZIndex = T.layer.overlay,",
					}
				do
					Verify.expect(`{expected} {string.find(code, expected, 1, true) ~= nil}`):toBe(`{expected} true`)
				end
				Verify.expect(Design.emit(Design.parse(code, library), library, { name = "Tokens" })):toBe(code)
			end,
		})

		verifyHarness:case("round trips native datatype tokens and button toggles", {
			id = "facet_compose_library::round trips native datatype tokens and button toggles",
			run = function()
				local library = Kit.library({
					UI = {},
					host = function(): unknown
						return nil
					end,
					tokens = { path = "T.", require = 'local T = require "../DesignTokens"' },
				})
				for _, kind in { "Frame", "Button" } do
					local value = Design.document.new("Tokens", library, kind)
					for _, key in { "Size", "Position", "AnchorPoint" } do
						value = Design.document.change(value, library, "n1", key, { token = "example" })
						local code = Design.emit(value, library)
						Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
						local parts: Facet.DesignLiteral = if key == "AnchorPoint"
							then { 0, { token = "values.size.ratio" } }
							else { 1, 0, 0, { token = "values.size.minimumTouch" } }
						value = Design.document.change(value, library, "n1", key, { literal = parts })
					end
					local code = Design.emit(value, library)
					Verify.expect(string.find(code, "T.values.size.minimumTouch", 1, true) ~= nil):toBe(true)
					Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
				end
				local value = Design.document.change(
					Design.document.new("Choice", library, "Toggle"),
					library,
					"n1",
					"presentation",
					{ literal = "button" }
				)
				local code = Design.emit(value, library)
				Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
				value = Design.document.change(value, library, "n1", "presentation", { literal = "checkbox" })
				value = Design.document.change(value, library, "n1", "mixed", { literal = true })
				value = Design.document.change(value, library, "n1", "presentation", { literal = "button" })
				Verify.expect(value.root.props.mixed):toBe(nil)
				local session = mount(function(ctx: Context): unknown
					return Design.render(value, live(ctx))
				end)
				session.dispose()
			end,
		})

		verifyHarness:case("hoists typed action tables for each action control", {
			id = "facet_compose_library::hoists typed action tables for each action control",
			run = function()
				local library = offline()
				local shapes: { [string]: string } = {
					Dialog = "{ Facet.DialogAction }",
					Notice = "{ Facet.OverlayAction }",
					Sheet = "{ Facet.OverlayAction }",
					Callout = "{ Facet.OverlayAction }",
					Alert = "{ Facet.AlertAction }",
					RowActions = "{ Facet.RowAction }",
				}
				for kind, shape in shapes do
					local value = Design.document.setContract(Design.document.new("Confirm", library, kind), library, {
						inputs = {},
						outputs = { { id = "onReady", args = {} } },
					})
					local key = if kind == "RowActions" then "leading" else "actions"
					local actions: Facet.DesignLiteral = {
						{ id = "ready", label = "I'm ready", onActivate = { ["$output"] = "onReady" } },
					}
					value = Design.document.change(value, library, "n1", key, { literal = actions })
					local code = Design.emit(value, library)
					Verify.expect(string.find(code, `: {shape} =`, 1, true) ~= nil):toBe(true)
					Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
				end
				local value =
					Design.document.change(Design.document.new("Panel", library, "Sheet"), library, "n1", "detents", {
						literal = { "medium", { id = "large", fraction = 1 }, { id = "short", height = 180 } },
					})
				local code = Design.emit(value, library)
				Verify.expect(string.find(code, ": { Facet.SheetDetent } =", 1, true) ~= nil):toBe(true)
				Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
			end,
		})

		verifyHarness:case("round trips strict Table Sheet and TabView consumers without casts", function()
			local fs = require("@std/fs")
			local code = fs.readFileToString("tests/types/design_consumers.luau")
			local library = offline()
			library.prelude = { 'local Facet = require("../../src")' }
			local value = Design.parse(code, library)
			Verify.expect(Design.emit(value, library)):toBe(code)
			for _, shape in { "{ Facet.TableColumn<RowsItem, string> }", "{ Facet.SheetDetent }", "{ Facet.Tab }" } do
				Verify.expect(string.find(code, `: {shape} =`, 1, true) ~= nil):toBe(true)
			end
			Verify.expect(string.find(code, "::", 1, true)):toBeNil()
			local tabs = Design.document.find(value.root, "n6")
			assert(tabs)
			Verify.expect(tabs.kind):toBe("TabView")
			Verify.expect(#tabs.children):toBe(2)
			Verify.expect(tabs.props.selection.state):toBe("selection")
		end)

		verifyHarness:case("represents fill and constrained Text with native editable children", {
			id = "facet_compose_library::represents fill and constrained Text with native editable children",
			run = function()
				for _, weighted in { false, true } do
					local session = mount(function(ctx: Context): unknown
						local library = Kit.library({
							UI = ctx.UI,
							types = ctx.types,
							host = function(className: string, name: string, props: { [unknown]: unknown }): unknown
								return ctx.runtime.constructors[className](props, name)
							end,
						})
						local value, text = Design.document.insert(
							Design.document.new("Identity", library, "VStack"),
							library,
							"n1",
							"Text"
						)
						local limit
						value, limit = Design.document.insert(value, library, text, "UISizeConstraint")
						value = Design.document.change(value, library, limit, "MaxSize", { literal = { 240, 80 } })
						local fill
						value, fill = Design.document.insert(value, library, "n1", "UIFlexItem")
						value = Design.document.change(
							value,
							library,
							fill,
							"FlexMode",
							{ literal = if weighted then "Custom" else "Fill" }
						)
						if weighted then
							for _, key in { "GrowRatio", "ShrinkRatio" } do
								value = Design.document.change(value, library, fill, key, { literal = 2 })
							end
						end
						local code = Design.emit(value, library)
						Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
						local root = Design.render(value, library)
						assert(typeof(root) == "Instance")
						local actual = assert(root:FindFirstChildWhichIsA("UIFlexItem"))
						local expected = ctx.UI.fill(if weighted then 2 else nil)
						local read = assert(ctx.runtime.host.observation).readProperty
						for _, key in { "FlexMode", "GrowRatio", "ShrinkRatio" } do
							Verify.expect(read(actual, key)):toBe(read(expected, key))
						end
						local constraint = root:FindFirstChildWhichIsA("UISizeConstraint", true)
						Verify.expect(read(assert(constraint), "MaxSize")):toBe(ctx.types.Vector2.new(240, 80))
						return root
					end)
					session.dispose()
				end
			end,
		})

		verifyHarness:case("binds prepared content inputs on lazy controls", {
			id = "facet_compose_library::binds prepared content inputs on lazy controls",
			run = function()
				for _, kind in { "Dialog", "Sheet", "DisclosureGroup" } do
					local calls = 0
					local session = mount(function(ctx: Context): unknown
						local library = live(ctx)
						local value = Design.document.new("Prepared", library, kind)
						for _, child in value.root.children do
							value = Design.document.remove(value, library, child.id)
						end
						value = Design.document.setContract(value, library, {
							inputs = {
								{ id = "body", kind = "value", type = "slot", required = true },
							},
							outputs = {},
						})
						value = Design.document.change(value, library, "n1", "content", { input = "body" })
						local code = Design.emit(value, library)
						Verify.expect(string.find(code, "content = props.body", 1, true) ~= nil):toBe(true)
						Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
						return Design.render(value, library, {
							slots = {
								body = function(): unknown
									calls += 1
									return ctx.UI.Text "PreparedBody" { text = "Prepared" }
								end,
							},
						})
					end)
					Verify.expect(calls):toBe(1)
					session.dispose()
				end
			end,
		})

		verifyHarness:case("designs a Menu trigger and a Button glyph as content subtrees", {
			id = "facet_compose_library::designs a Menu trigger and a Button glyph as content subtrees",
			run = function()
				local triggered: Instance? = nil
				local mounted = mount(function(ctx: Context)
					local library = live(ctx)
					local value, menu = Design.document.insert(
						Design.document.new("Commands", library, "VStack"),
						library,
						"n1",
						"Menu"
					)
					local trigger
					value, trigger = Design.document.content(value, library, menu, "trigger", "Button")
					value = Design.document.change(value, library, trigger, "label", { literal = "More" })
					local code = Design.emit(value, library, { name = "Commands" })
					Verify.expect(string.find(code, "trigger = function()", 1, true) ~= nil):toBe(true)
					Verify.expect(Design.emit(Design.parse(code, library), library, { name = "Commands" })):toBe(code)
					return Design.render(value, library, {
						decorate = function(node: Facet.DesignNode, instance: unknown)
							if node.id == trigger and typeof(instance) == "Instance" then
								triggered = instance
							end
						end,
					})
				end)
				Verify.expect(assert(triggered):IsA("GuiButton")):toBe(true)
				mounted.dispose()
			end,
		})

		verifyHarness:case("authors whole game views with typed props, outputs and Roblox values", {
			id = "facet_compose_library::authors whole game views with typed props, outputs and Roblox values",
			run = function()
				local library = Kit.library({
					UI = {},
					host = function(className: string, name: string, props: { [unknown]: unknown }): unknown
						return { className = className, name = name, props = props }
					end,
				})
				local rowFields: { Facet.DesignItemField } =
					{ { id = "id", type = "string" }, { id = "title", type = "string" } }
				local retryArgs: { Facet.DesignInputType } = {}
				local retry: Facet.DesignOutput = { id = "onRetry", args = retryArgs }
				local value = Design.document.new("ChooseGameView", library, "VStack")
				value = Design.document.setContract(value, library, {
					inputs = {
						{ id = "name", kind = "value", type = "string", required = true },
						{ id = "games", kind = "readable", type = "list", fields = rowFields },
						{ id = "offered", kind = "readable", type = "boolean" },
					},
					outputs = { retry },
				})
				value = Design.document.nameFromInput(value, library, "n1", "name")
				local size: Facet.DesignLiteral = { 1, 0, 0, 320 }
				value = Design.document.change(value, library, "n1", "Size", { literal = size })
				value = Design.document.change(value, library, "n1", "AutomaticSize", { literal = "Y" })
				local list, row, button
				value, list = Design.document.insert(value, library, "n1", "VStack")
				value, row = Design.document.insert(value, library, list, "Text")
				value = Design.document.bind(value, library, list, { from = "games", key = "id" })
				value = Design.document.change(value, library, row, "text", { item = "title" })
				value, button = Design.document.insert(value, library, "n1", "Button")
				local badge
				value, badge = Design.document.insert(value, library, button, "Text")
				value = Design.document.change(value, library, badge, "text", { literal = "3 new" })
				value = Design.document.change(value, library, button, "onActivate", { output = "onRetry" })
				value = Design.document.change(value, library, button, "selected", { literal = true })
				value = Design.document.showWhen(value, library, button, "offered")
				local code = Design.emit(value, library, {
					name = "ChooseGameView",
					controls = "local UI = Facet.controls(runtime)",
				})
				for _, expected in
					{
						"local function ChooseGameView(props: Props): GuiObject",
						"UI.VStack(props.name",
						"Size = UDim2.new(1, 0, 0, 320)",
						"AutomaticSize = Enum.AutomaticSize.Y",
						"from = props.games,",
						"Facet.Compose.show(props.offered, function()",
						"if props.onRetry then",
						'UI.Text "Text"',
						"export type GamesItem = { id: string, title: string }",
						"games: Facet.ReadOnlyValue<{ GamesItem }>?",
						"\tname: string,",
					}
				do
					Verify.expect(`{expected} {string.find(code, expected, 1, true) ~= nil}`):toBe(`{expected} true`)
				end
				Verify.expect(Design.emit(Design.parse(code, library), library, {
					name = "ChooseGameView",
					controls = "local UI = Facet.controls(runtime)",
				})):toBe(code)

				local panel = Design.document.new("MatchmakingPanel", library, "Frame")
				panel = Design.document.change(panel, library, "n1", "BackgroundTransparency", { literal = 1 })
				local inner
				panel, inner = Design.document.insert(panel, library, "n1", "Text")
				panel = Design.document.change(panel, library, inner, "text", { literal = "Finding players" })
				local panelCode = Design.emit(panel, library)
				Verify.expect(string.find(panelCode, 'Host.Frame "Frame" {', 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("accepts the literals Facet controls take at runtime", {
			id = "facet_compose_library::accepts the literals Facet controls take at runtime",
			run = function()
				local library = offline()
				local value = Design.document.new("Drawer", library, "VStack")
				value = Design.document.change(value, library, "n1", "gap", { literal = 8 })
				local sideTable: { [string | number]: Facet.DesignLiteral } = { left = 8, right = 8, top = 12 }
				local sides: Facet.DesignLiteral = sideTable
				value = Design.document.change(value, library, "n1", "padding", { literal = sides })
				local text, sheet, alert
				value, text = Design.document.insert(value, library, "n1", "Text")
				value = Design.document.change(value, library, text, "textSize", { literal = "body" })
				value = Design.document.change(value, library, text, "TextColor3", { literal = "#986325" })
				value, sheet = Design.document.insert(value, library, "n1", "Sheet")
				value = Design.document.change(value, library, sheet, "closeButton", { literal = "Cancel" })
				local reportArgs: { Facet.DesignInputType } = {}
				local report: Facet.DesignOutput = { id = "onReport", args = reportArgs }
				value = Design.document.setContract(value, library, { inputs = {}, outputs = { report } })
				value, alert = Design.document.insert(value, library, "n1", "Alert")
				local call: { [string | number]: Facet.DesignLiteral } = {}
				call["$output"] = "onReport"
				local action: { [string | number]: Facet.DesignLiteral } = { id = "report", label = "Report" }
				action.onActivate = call
				local actions: Facet.DesignLiteral = { action }
				value = Design.document.change(value, library, alert, "actions", { literal = actions })
				local picker
				value, picker = Design.document.insert(value, library, "n1", "Picker")
				local option: { [string | number]: Facet.DesignLiteral } = { value = "Medium", label = "Standard" }
				local pickerOptions: Facet.DesignLiteral = { option }
				value = Design.document.change(value, library, picker, "options", { literal = pickerOptions })
				local emitOptions: Facet.DesignEmitOptions = {
					name = "Drawer",
					rowFunctions = true,
					controls = "local UI = Facet.controls(runtime)",
					localControls = true,
				}
				local code = Design.emit(value, library, emitOptions)
				for _, expected in
					{
						"gap = 8,",
						"local vStackPadding: Facet.Sides = { left = 8, right = 8, top = 12 }",
						"padding = vStackPadding,",
						"local UI = Facet.controls(runtime)",
						'textSize = "body",',
						'TextColor3 = Color3.fromHex "986325",',
						'closeButton = "Cancel",',
						"if props.onReport then",
					}
				do
					Verify.expect(`{expected} {string.find(code, expected, 1, true) ~= nil}`):toBe(`{expected} true`)
				end
				Verify.expect(Design.emit(Design.parse(code, library), library, emitOptions)):toBe(code)
			end,
		})

		verifyHarness:case("authors second-batch views with collection rows, statics and chosen nodes", {
			id = "facet_compose_library::authors second-batch views with collection rows, statics and chosen nodes",
			run = function()
				local library = offline()
				local rowFields: { Facet.DesignItemField } =
					{ { id = "revision", type = "string" }, { id = "word", type = "string" } }
				local value = Design.document.new("MatchHistory", library, "VStack")
				value = Design.document.setContract(value, library, {
					inputs = { { id = "turns", kind = "readable", type = "list", fields = rowFields } },
					outputs = {},
				})
				local list, row, empty
				value, list = Design.document.insert(value, library, "n1", "VirtualList")
				value = Design.document.bind(value, library, list, { from = "turns", key = "revision" })
				value, row = Design.document.insert(value, library, list, "Text")
				value = Design.document.change(value, library, row, "text", { item = "word" })
				value = Design.document.bind(value, library, list, { from = "turns", key = "revision", row = row })
				value = Design.document.change(value, library, list, "recycle", { literal = false })
				value = Design.document.change(value, library, list, "mode", { literal = "all" })
				value, empty = Design.document.insert(value, library, list, "Text")
				value = Design.document.rename(value, library, empty, "NoTurns")
				local code = Design.emit(value, library, { name = "MatchHistory", rowFunctions = true })
				for _, expected in { "recycle = false,", 'mode = "all",', 'UI.Text "NoTurns"' } do
					Verify.expect(`{expected} {string.find(code, expected, 1, true) ~= nil}`):toBe(`{expected} true`)
				end
				Verify.expect(
					Design.emit(Design.parse(code, library), library, { name = "MatchHistory", rowFunctions = true })
				)
					:toBe(code)
				local marker = Design.document.new("Rewards", library, "VStack")
				local markerState: Facet.DesignState = { id = "source", type = "string", initial = "Stage" }
				marker = Design.document.setState(marker, library, { markerState })
				local stage, flash
				marker, stage = Design.document.insert(marker, library, "n1", "VStack")
				marker = Design.document.rename(marker, library, stage, "Stage")
				marker, flash = Design.document.insert(marker, library, "n1", "WorldMarker")
				local anchorFields: { Facet.DesignItemField } = {}
				marker = Design.document.setContract(marker, library, {
					inputs = { { id = "anchor", kind = "readable", type = "record", fields = anchorFields } },
					outputs = {},
				})
				marker = Design.document.change(marker, library, flash, "anchor", { input = "anchor" })
				Verify.expect(string.find(Design.emit(marker, library), "anchor = props.anchor,", 1, true) ~= nil)
					:toBe(true)
			end,
		})

		verifyHarness:case("moves designed values and plays designed sequences with theme motion", {
			id = "facet_compose_library::moves designed values and plays designed sequences with theme motion",
			run = function()
				local library = offline()
				local charge: Facet.DesignState = { id = "charge", type = "number", initial = 0 }
				local value = Design.document.new("Charge", library, "VStack")
				value = Design.document.setState(value, library, { charge })
				local bar, button
				value, bar = Design.document.insert(value, library, "n1", "ProgressView")
				value = Design.document.change(value, library, bar, "value", { state = "charge", motion = "move" })
				local fill: { Facet.DesignSequence } =
					{ { id = "fill", steps = { { duration = "glide", state = "charge", to = 1 } } } }
				value = Design.document.setSequences(value, library, fill)
				value, button = Design.document.insert(value, library, "n1", "Button")
				value = Design.document.change(value, library, button, "onActivate", { play = "fill" })
				local code = Design.emit(value, library)
				for _, expected in
					{
						'value = UI.follow(state.charge, "move")',
						'{ duration = "glide", sample = UI.toward(state.charge, 1) },',
						"onActivate = sequences.fill.play",
					}
				do
					Verify.expect(`{expected} {string.find(code, expected, 1, true) ~= nil}`):toBe(`{expected} true`)
				end
				Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
				local played: Facet.DesignPlayer? = nil
				local shown: { number } = {}
				local session = mount(function(ctx: Context): unknown
					for _, role in assert(library.motion).roles do
						ctx.UI.follow(Facet.Compose.cell(0), role)
					end
					local motion = Kit.motion(ctx.UI)
					local built = Design.render(value, live(ctx, motion), {
						players = function(players: { [string]: Facet.DesignPlayer })
							played = players.fill
						end,
					})
					return built
				end)
				local player = assert(played, "the design makes a player for its sequence")
				player.play()
				table.insert(shown, 1)
				Verify.expect(#shown):toBe(1)
				session.dispose()
			end,
		})

		verifyHarness:case("converts native datatype and enum fields a design sets on a Facet control", {
			id = "facet_compose_library::converts native datatype and enum fields a design sets on a Facet control",
			run = function()
				local button: unknown = nil
				local session = mount(function(ctx: Context, engine: Engine): unknown
					local types = ctx.types
					local library = Kit.library({
						UI = ctx.UI,
						types = ctx.types,
					})
					local value = Design.document.new("Sized", library, "VStack")
					local id
					value, id = Design.document.insert(value, library, "n1", "Button")
					value = Design.document.change(value, library, id, "Size", { literal = { 0, 160, 0, 59 } })
					value = Design.document.change(value, library, id, "AnchorPoint", { literal = { 0.5, 0.5 } })
					value = Design.document.change(value, library, id, "AutomaticSize", { literal = "None" })
					local built = Design.render(value, library, {
						decorate = function(node: Facet.DesignNode, made: unknown)
							if node.id == id then
								button = made
							end
						end,
					})
					local _ = engine
					return built
				end)
				local made = button
				if typeof(made) ~= "Instance" or not made:IsA("GuiObject") then
					error("the Button did not render")
				end
				Verify.expect(made.Size.X.Offset):toBe(160)
				Verify.expect(made.Size.Y.Offset):toBe(59)
				Verify.expect(made.AnchorPoint.X):toBe(0.5)
				session.dispose()
			end,
		})

		verifyHarness:case("renders reactive token components as native datatypes", {
			id = "facet_compose_library::renders reactive token components as native datatypes",
			run = function()
				local initial: Facet.DesignLiteral? = 59
				local height = Facet.Compose.cell(initial)
				for _, kind in { "Button", "Frame" } do
					local made: GuiObject? = nil
					local session = mount(function(ctx: Context): unknown
						local library = Kit.library({
							UI = ctx.UI,
							types = ctx.types,
							host = function(className: string, name: string, props: { [unknown]: unknown }): unknown
								return ctx.runtime.constructors[className](props, name)
							end,
							tokens = { path = "T.", require = 'local T = require "../DesignTokens"' },
						})
						local value = Design.document.new("Sized", library, kind)
						local parts: Facet.DesignLiteral = { 0, 160, 0, { token = "size.minimumTouch" } }
						value = Design.document.change(value, library, "n1", "Size", { literal = parts })
						value = Design.document.change(value, library, "n1", "AutomaticSize", { literal = "None" })
						return Design.render(value, library, {
							resolveToken = function(): ComposeDesign.Resolved
								return { readable = height }
							end,
							decorate = function(_node: Facet.DesignNode, built: unknown)
								if typeof(built) == "Instance" and built:IsA("GuiObject") then
									made = built
								end
							end,
						})
					end)
					Verify.expect(assert(made).Size.Y.Offset):toBe(59)
					height:set(72)
					Verify.expect(assert(made).Size.Y.Offset):toBe(72)
					session.dispose()
					height:set(59)
				end
			end,
		})

		verifyHarness:case("emits Facet source for a design that uses every control", {
			id = "facet_compose_library::emits Facet source for a design that uses every control",
			run = function()
				local library = offline()
				local code = Design.emit(documentWith(names(), library), library, { name = "EveryControl" })
				for _, name in names() do
					Verify.expect(string.find(code, `UI.{name} "{name}%d+"`) ~= nil):toBe(true)
				end
				Verify.expect(Design.parse(code, library).root.kind):toBe("ScrollView")
			end,
		})
	end)
end
