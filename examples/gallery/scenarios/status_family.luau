--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ExampleContext = typeof(require("@repo/examples/types").Context)
type Built = typeof(require("@repo/examples/types").Built)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T

return {
	title = "Status",
	ledgerRows = {},
	build = function(ctx: ExampleContext): Built
		local UI = ctx.UI
		local Host = ctx.Host
		local Compose: ComposeModule = ctx.Compose
		local nativeTypes = ctx.types
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local marks = require("./status_indicator").build(ctx)
		local badges = require("./badge").build(ctx)
		local notices = require("./notice").build(ctx)
		local function reset()
			marks.reset()
			badges.reset()
			notices.reset()
		end
		local function reserved(content: GuiObject)
			local top, bottom = Compose.cell(0), Compose.cell(0)
			local function measure()
				local layer = content:FindFirstAncestorWhichIsA("LayerCollector")
				if layer == nil then
					return
				end
				local offset = content.AbsolutePosition.Y - layer.AbsolutePosition.Y
				local height = layer.AbsoluteSize.Y
				local below = height - (offset + content.AbsoluteSize.Y)
				local insetTop, insetBottom =
					layer:GetAttribute("FacetInsetTop"), layer:GetAttribute("FacetInsetBottom")
				top:set(math.max(0, (if type(insetTop) == "number" then insetTop else 0) - offset))
				bottom:set(math.max(0, (if type(insetBottom) == "number" then insetBottom else 0) - below))
			end
			return top, bottom, measure
		end
		return {
			screen = function()
				local padding = Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				})
				local frame = Host.Frame("StatusFamily")({
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					padding,
					UI.ScrollView "Content" {
						gap = 24,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						ScrollBarThickness = 6,
						UI.Button "Reset" { label = "Reset status", onActivate = reset },
						notices.section(2),
						marks.section(),
						badges.section(),
					},
				})
				local top, bottom, measure = reserved(frame)
				ctx.runtime.decorate(padding, {
					PaddingTop = function(use: Use)
						return UDim.new(0, 16 + use(top))
					end,
					PaddingBottom = function(use: Use)
						return UDim.new(0, 16 + use(bottom))
					end,
				})
				local connections: { RBXScriptConnection } = {}
				local watched: Instance? = nil
				local function follow()
					local layer = frame:FindFirstAncestorWhichIsA("LayerCollector")
					if layer and layer ~= watched then
						watched = layer
						table.insert(connections, layer:GetAttributeChangedSignal("FacetInsetTop"):Connect(measure))
						table.insert(connections, layer:GetAttributeChangedSignal("FacetInsetBottom"):Connect(measure))
					end
					measure()
				end
				table.insert(connections, frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(measure))
				table.insert(connections, frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure))
				table.insert(connections, frame.AncestryChanged:Connect(follow))
				Compose.cleanup(function()
					for _, connection in connections do
						connection:Disconnect()
					end
				end)
				return Host.Frame("StatusPage")({
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					frame,
					notices.affixed(),
				})
			end,
			notices = notices,
			reset = reset,
			steps = { reset = reset },
			report = function()
				local status, badge = marks.report(), badges.report()
				return if status and badge then { status = status, badge = badge } else nil
			end,
		}
	end,
}
