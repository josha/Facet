--!strict
local ControlTypes = require("./control_types")
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local NavigationProps = require("./navigation_props")
local surfaceParts = require("./nav_surface_parts")

return function(
	ctx: Types.Context,
	UI: ControlTypes.BuilderControls,
	surfaces: Nav.Surfaces,
	kit: surfaceParts.SurfaceParts
): ()
	local Host, Compose, runtime = ctx.Host, ctx.Compose, ctx.runtime
	local E, D2 = ctx.types.Enum, ctx.types.UDim2
	local body = kit.body
	UI.DisclosureGroup = ctx.construct("DisclosureGroup", function(spec: NavigationProps.DisclosureGroupSpec): Frame
		assert(
			type(spec.expanded) == "table" and spec.expanded.set,
			"DisclosureGroup.expanded requires a writable Compose cell"
		)
		local gui = surfaces.service("GuiService")
		local side = spec.chevronPosition or "leading"
		assert(side == "leading" or side == "trailing", "Invalid DisclosureGroup.chevronPosition")
		assert(
			spec.appearance == nil or table.find({ "plain", "contained", "divided", "outline" }, spec.appearance),
			"Invalid DisclosureGroup.appearance"
		)
		local indent = spec.indent
		assert(
			indent == nil
				or (type(indent) == "number" and indent >= 0 and indent < math.huge)
				or (type(indent) == "string" and table.find({ "xs", "s", "m", "l", "xl" }, indent) ~= nil),
			"DisclosureGroup.indent must be a spacing step or a number of pixels"
		)
		local function chevron(use: ComposeTypes.Use): string
			return if use(spec.expanded) then "chevron.down" else "chevron.trailing"
		end
		local header = UI.Button "Header" {
			label = spec.label,
			icon = if side == "leading" then chevron else spec.icon,
			trailingIcon = if side == "trailing" then chevron else spec.icon,
			subtitle = spec.description,
			enabled = spec.enabled,
			textSize = spec.textSize,
			Size = D2.new(1, 0, 0, 44),
			selected = if spec.appearance == "outline" then nil else spec.expanded,
			appearance = if spec.appearance == "outline" then "utility" else nil,
			TextXAlignment = if spec.appearance == "outline" then E.TextXAlignment.Left else nil,
			onActivate = function()
				local value = not spec.expanded:peek()
				spec.expanded:set(value)
				if spec.onToggle then
					spec.onToggle(value)
				end
			end,
		}

		local headerContent = header:FindFirstChild("Content")
		local headerLayout = headerContent and headerContent:FindFirstChildWhichIsA("UIListLayout")
		if headerContent and headerLayout then
			headerLayout.HorizontalAlignment = E.HorizontalAlignment.Left
			local captions = headerContent:FindFirstChild("Captions")
			local words = captions or headerContent:FindFirstChild("Title")
			if words and (side == "trailing" or captions) then
				runtime.mount(function()
					return Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill })
				end, words)
			end
			local caption = captions and captions:FindFirstChild("Description")
			if caption and caption:IsA("TextLabel") then
				caption.TextWrapped = true
			end
		end

		local progress, closed, hidden = kit.revealMotion(spec.expanded)
		local caret = header:FindFirstChild(if side == "leading" then "LeadingIcon" else "TrailingIcon", true)
		if caret and caret:IsA("GuiObject") then
			runtime.decorate(caret, {
				Rotation = function(use: ComposeTypes.Use)
					local amount = progress(use)
					return if use(spec.expanded) then -90 * (1 - amount) else 90 * amount
				end,
			})
		end

		local root = ctx.column(
			{
				header,
				Compose.presence(spec.expanded, function(phase: Nav.PresencePhase)
					local node: Instance = body(spec.content)
					if spec.appearance == "divided" then
						node = ctx.column({
							ctx.styled(
								Host.Frame "Divider" { BorderSizePixel = 0, Size = D2.new(1, 0, 0, 1) },
								"divider"
							),
							node,
						})
					end
					local outline = spec.appearance == "outline"
					local function side(use: ComposeTypes.Use): number
						return if outline then 0 else ctx.controlSize(nil, "paddingX", use)
					end
					local inset = Host.UIPadding({
						PaddingTop = ctx.types.UDim.new(0, 8),
						PaddingBottom = ctx.types.UDim.new(0, 8),
						PaddingRight = function(use: ComposeTypes.Use)
							return ctx.types.UDim.new(0, side(use))
						end,
						PaddingLeft = function(use: ComposeTypes.Use)
							local step = indent
							return ctx.types.UDim.new(
								0,
								if type(step) == "number"
									then step
									elseif step then ctx.metric("space." .. step, use)
									else side(use)
							)
						end,
					})
					local fade = ctx.fade({
						Name = "RevealFade",
						BackgroundTransparency = 1,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						GroupTransparency = hidden,
						node,
					}, nil, false)
					surfaces.attach(fade, { inset :: Types.Child })
					local automatic, height = kit.unroll(progress, ctx.observe.AbsoluteSize(fade))
					local reveal = Host.Frame "Reveal" {
						BackgroundTransparency = 1,
						ClipsDescendants = true,
						LayoutOrder = 2,
						Interactable = function(use: ComposeTypes.Use)
							return not use(phase.exiting)
						end,
						AutomaticSize = automatic,
						Size = function(use: ComposeTypes.Use)
							return D2.new(1, 0, 0, height(use) or 0)
						end,
						fade,
					}
					local function handBack()
						if gui and surfaces.within(gui.SelectedObject, reveal) and header.Parent then
							gui.SelectedObject = header
						end
					end
					Compose.watch(function(use: ComposeTypes.Use)
						if use(phase.exiting) then
							handBack()
						end
					end)
					Compose.cleanup(handBack)
					surfaces.keep(spec.content)
					return reveal
				end, {
					exit = function()
						return { completed = closed }
					end,
				}),
			},
			ctx.props(spec, {
				"label",
				"expanded",
				"content",
				"enabled",
				"onToggle",
				"description",
				"icon",
				"chevronPosition",
				"appearance",
				"controlSize",
				"textSize",
				"indent",
			}, { Name = "DisclosureGroup", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
		)
		local rhythm = root:FindFirstChildWhichIsA("UIListLayout")
		if rhythm then
			runtime.decorate(rhythm, { Padding = ctx.types.UDim.new(0, 0) })
		end
		ctx.styled(root, "disclosure-group")
		if spec.appearance == "contained" then
			ctx.styled(root, "panel")
			runtime.decorate(root, { BackgroundTransparency = 0 })
			surfaces.skin(root, "panel")
		end
		if spec.appearance then
			ctx.styled(root, "disclosure-" .. spec.appearance)
		end
		return root
	end)
end
