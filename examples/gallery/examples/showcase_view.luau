--!strict

type DemoTabs = typeof(require("@repo/examples/gallery/scenarios/demo_tabs"))
type ExampleContext = typeof(require("@repo/examples/types").Context)
type DemoTab = typeof(require("@repo/examples/types").DemoTab)
type PartProps = typeof(require("@repo/tools/typecheck/aliases").PartProps)
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
type NumberCell = typeof(require("@repo/tools/typecheck/aliases").NumberCell)
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Runtime = typeof(require("@repo/tools/typecheck/aliases").Runtime)
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
type Input<T> = T | ReadOnlyValue<T> | (Use) -> T
type TextRole = "caption" | "label" | "body" | "heading" | "title" | "control" | "strong" | "numeral"
type Page = { id: string, label: string, content: () -> Instance }
local loadTabs: (ModuleScript | string) -> DemoTabs = require
return function(ctx: ExampleContext)
	local demoTabs = loadTabs(if ctx.find then ctx.find("fixture", "demo_tabs") else "../scenarios/demo_tabs")
	local UI, Host, Compose = ctx.UI, ctx.Host, ctx.Compose
	local D2, V3, CF, C3, E = ctx.types.UDim2, ctx.types.Vector3, ctx.types.CFrame, ctx.types.Color3, ctx.types.Enum
	local view = {}
	function view.text(name: string, text: Input<string>, role: TextRole?)
		return UI.Text(name)({
			text = text,
			textRole = role or "body",
			wrap = true,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		})
	end
	function view.page(name: string, title: Input<string>, subtitle: Input<string>, children: { Child })
		return UI.ScrollView(name)({
			padding = "l",
			gap = "m",
			view.text("Title", title, "title"),
			view.text("Subtitle", subtitle),
			table.unpack(children),
		})
	end
	function view.actions(children: { Child })
		return UI.HStack {
			width = "fill",
			wrap = true,
			gap = "s",
			table.unpack(children),
		}
	end
	function view.button(name: string, label: Input<string>, action: () -> (), enabled: Input<boolean>?)
		return UI.Button(name)({
			label = label,
			onActivate = function()
				action()
			end,
			enabled = enabled,
		})
	end
	function view.part(
		name: string,
		size: Input<Vector3>,
		position: Vector3,
		color: Input<Color3>,
		extra: PartProps?
	): Part
		local props: PartProps = if extra then table.clone(extra) else {}
		if props.Anchored == nil then
			props.Anchored = true
		end
		if props.CanCollide == nil then
			props.CanCollide = false
		end
		if props.Size == nil then
			props.Size = size
		end
		if props.CFrame == nil then
			props.CFrame = CF.new(position)
		end
		if props.Color == nil then
			props.Color = color
		end
		if props.Material == nil then
			props.Material = E.Material.SmoothPlastic
		end
		return Host.Part(props, name)
	end
	function view.stage(name: string, content: () -> Instance, camera: CFrame?, height: number?)
		return UI.Stage(name)({
			Size = D2.new(1, 0, 0, height or 260),
			BackgroundColor3 = C3.fromRGB(22, 29, 43),
			BackgroundTransparency = 0,
			Ambient = C3.fromRGB(175, 181, 196),
			LightColor = C3.fromRGB(255, 239, 214),
			LightDirection = V3.new(-1, -2, -1),
			camera = camera or CF.lookAt(V3.new(8, 6, 10), V3.new(0, 1, 0)),
			fieldOfView = 40,
			content = function(runtime: Runtime, world: WorldModel): (() -> ())?
				local stop = runtime.mount(content, world)
				return stop
			end,
		})
	end
	function view.observeWidth(width: NumberCell, node: GuiObject)
		local function measure()
			local scale = if ctx.previewScale then ctx.previewScale:peek() else 1
			width:set(node.AbsoluteSize.X / math.max(0.01, scale))
		end
		measure()
		local connection = node:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
	end
	function view.tabs(id: string, pages: { Page }, report: (() -> { [string]: unknown })?)
		local groups: { DemoTab } = {}
		for _, page in pages do
			table.insert(groups, {
				id = page.id,
				label = page.label,
				scenario = {
					build = function()
						return { screen = page.content }
					end,
				},
			})
		end
		local built = demoTabs(ctx, id, groups)
		return {
			screen = built.screen,
			select = built.select,
			report = function(): { [string]: unknown }
				local state: { [string]: unknown } = if report then report() else {}
				state.navigation = built.report().selected
				return state
			end,
		}
	end
	return view
end
