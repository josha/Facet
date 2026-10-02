--!strict
local loadTabs = require :: (string) -> typeof(require("@repo/examples/gallery/scenarios/demo_tabs"))
return function(ctx: any)
	local demoTabs = if ctx.load then ctx.load("fixture", "demo_tabs") else loadTabs("../scenarios/demo_tabs")
	local UI, Host, Compose: typeof(require("@repo/src/vendor/compose/core")) = ctx.UI, ctx.Host, ctx.Compose
	local D2, V3, CF, C3, E = ctx.types.UDim2, ctx.types.Vector3, ctx.types.CFrame, ctx.types.Color3, ctx.types.Enum
	local view: any = {}
	function view.text(name: string, text, role)
		return UI.Text(name)({
			text = text,
			textRole = role or "body",
			wrap = true,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		})
	end
	function view.page(name: string, title, subtitle, children)
		return UI.ScrollView(name)({
			padding = "l",
			gap = "m",
			view.text("Title", title, "title") :: unknown,
			view.text("Subtitle", subtitle),
			table.unpack(children),
		})
	end
	function view.actions(children)
		return UI.HStack {
			width = "fill" :: "fill",
			wrap = true,
			gap = "s",
			table.unpack((children :: unknown) :: { unknown }),
		}
	end
	function view.button(name: string, label, action, enabled)
		return UI.Button(name)({ label = label, onActivate = action, enabled = enabled })
	end
	function view.part(name: string, size, position, color, extra)
		local props = {
			Anchored = true,
			CanCollide = false,
			Size = size,
			CFrame = CF.new(position),
			Color = color,
			Material = E.Material.SmoothPlastic,
		}
		for key, value in extra or {} do
			props[key] = value
		end
		return Host.Part(name)(props)
	end
	function view.stage(name: string, content, camera, height)
		return UI.Stage(name)({
			Size = D2.new(1, 0, 0, height or 260),
			BackgroundColor3 = C3.fromRGB(22, 29, 43),
			BackgroundTransparency = 0,
			Ambient = C3.fromRGB(175, 181, 196),
			LightColor = C3.fromRGB(255, 239, 214),
			LightDirection = V3.new(-1, -2, -1),
			camera = camera or CF.lookAt(V3.new(8, 6, 10), V3.new(0, 1, 0)),
			fieldOfView = 40,
			content = function(runtime, world): (() -> ())?
				return runtime.mount(content, world)
			end,
		})
	end
	function view.observeWidth(width)
		return function(node: any)
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
	end
	function view.tabs(id, pages, report)
		local groups = {}
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
		local navigationReport = built.report
		built.report = function()
			local state = if report then report() else {}
			state.navigation = navigationReport().selected
			return state
		end
		return built
	end
	return view
end
