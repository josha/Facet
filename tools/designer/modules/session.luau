--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T

local session = {}

function session.mount(Facet: any, parent: Instance, preview: any, options: any): any
	local Compose: ComposeModule = Facet.Compose
	local runtime: ComposeRuntime = Facet.Roblox.createRuntime(options.engine)
	local Host = (runtime.constructors :: unknown) :: RobloxHost
	local UDim2 = if options.types then options.types.UDim2 else UDim2
	local Vector2 = if options.types then options.types.Vector2 else Vector2
	local owner = Compose.createOwner(runtime.reactor)
	local config = Compose.withOwner(owner, function()
		return Compose.cell(options.config)
	end)
	local disposed = false
	local function dispose()
		if disposed then
			return
		end
		disposed = true
		owner.dispose()
		runtime:dispose()
	end
	if options.register then
		options.register(dispose)
	end
	local theme = options.theme or Facet.themes.define(Facet.themes.neutralPackage())
	local root, overlay, content, UI
	local ok, stop = xpcall(function()
		return Compose.withOwner(owner, function()
			return runtime.mount(function()
				local function field(key: string)
					return Compose.formula(function(use: Use)
						return use(config)[key]
					end)
				end
				overlay =
					Host.Frame "Overlay" { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1000 }
				UI = Facet.controls(runtime, {
					theme = theme,
					types = options.types,
					services = options.services,
					inputParent = options.inputParent or parent,
					overlayParent = overlay,
					keyboardNavigation = options.keyboardNavigation == true,
					motionLevel = field("motionLevel"),
					environment = {
						viewportSize = Compose.formula(function(use: Use)
							local value = use(config)
							return Vector2.new(value.width, value.height)
						end),
						preferredInput = field("input"),
						touchEnabled = Compose.formula(function(use: Use)
							return use(config).input == "Touch"
						end),
						mouseEnabled = Compose.formula(function(use: Use)
							return use(config).input == "KeyboardAndMouse"
						end),
						gamepadEnabled = Compose.formula(function(use: Use)
							return use(config).input == "Gamepad"
						end),
						keyboardEnabled = Compose.formula(function(use: Use)
							return use(config).input == "KeyboardAndMouse"
						end),
						preferredTextSize = field("textSize"),
						displaySize = field("display"),
						viewingDistance = field("distance"),
						overscanInsets = "none",
					},
					onError = options.onError,
				})
				local sheet = Facet.themes.createStyleSheet(runtime, theme, {
					theme = field("palette"),
					motionLevel = field("motionLevel"),
					types = options.types,
					tenFoot = UI.environment().isTenFoot,
				})
				content = preview.render({
					Facet = Facet,
					Compose = Compose,
					runtime = runtime,
					Host = Host,
					UI = UI,
					state = preview.name,
					overlay = overlay,
					types = options.types,
				})
				assert(content ~= nil and content:IsA("GuiObject"), "Preview render must return a GuiObject")
				root = Host.Frame "FacetDesignSurface" {
					Size = function(use: Use)
						local value = use(config)
						return UDim2.fromOffset(value.width, value.height)
					end,
					ClipsDescendants = true,
					BorderSizePixel = 0,
					sheet :: unknown,
					Host.StyleLink { StyleSheet = Compose.static(sheet) },
					content,
					overlay,
				}
				root:AddTag("facet-pane")
				return root
			end, parent)
		end)
	end, function(err)
		return debug.traceback(tostring(err), 2)
	end)
	if not ok then
		dispose()
		error(stop, 0)
	end
	return {
		root = root,
		content = content,
		overlay = overlay,
		UI = UI,
		runtime = runtime,
		update = function(value)
			assert(not disposed, "Preview session is closed")
			config:set(value)
		end,
		dispose = dispose,
	}
end

return session
