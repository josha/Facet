--!strict
local Types = require("./types")
local Content = require("./content_types")
local Inputs = require("./input_types")
local ComposeTypes = require("../vendor/compose/core")
local values = require("./content_values")

local SIDES: { { side: Content.VoteValue, name: string, icon: string, label: string } } = {
	{ side = "up", name = "Opt1", icon = "vote.up", label = "Upvote" },
	{ side = "down", name = "Opt2", icon = "vote.down", label = "Downvote" },
}

return function(
	ctx: Types.Context,
	UI: {
		Vote: Types.Constructor<Content.VoteSpec, Frame>,
		Button: Types.Constructor<Inputs.ButtonProps, TextButton>,
	}
): ()
	local Host, Compose, read = ctx.Host, ctx.Compose, ctx.read
	local E, D2, V2, D = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2, ctx.types.UDim
	local function isVote(value: unknown): boolean
		return value == "up" or value == "down" or value == "none"
	end

	UI.Vote = ctx.construct("Vote", function(spec: Content.VoteSpec): Frame
		assert(isVote(read(spec.value)), "Facet UI.Vote: value must be up, down or none")
		assert(spec.onChange == nil or type(spec.onChange) == "function", "Facet UI.Vote: onChange must be a function")
		assert(
			spec.onChange ~= nil or read(spec.readOnly) == true,
			"Facet UI.Vote: onChange(next) is required unless readOnly is true"
		)
		local onChange = spec.onChange
		local checks = values(ctx, "Vote")
		if spec.controls then
			spec.controls.diagnostics = checks.list
		end
		local value = checks.legal("value", spec.value, isVote, "must be up, down or none")
		local refusedReadOnly = false
		local readOnly = Compose.formula(function(use: ComposeTypes.Use): boolean
			local wanted = read(spec.readOnly, use) == true
			if not wanted and onChange == nil then
				if not refusedReadOnly then
					refusedReadOnly = true
					checks.note("Facet UI.Vote: readOnly = false needs onChange; the vote stays read-only")
				end
				return true
			end
			refusedReadOnly = false
			return wanted
		end)
		local enabled = function(use: ComposeTypes.Use?): boolean
			return read(spec.enabled, use) ~= false
		end
		local disposed = false
		Compose.cleanup(function()
			disposed = true
		end)
		local function propose(side: Content.VoteValue)
			local change = onChange
			if disposed or readOnly:peek() or not enabled() or change == nil then
				return
			end
			change(if value:peek() == side then "none" else side)
		end
		local touchFloor = ctx.touchFloor()
		local function side(use: ComposeTypes.Use): UDim2
			local length = ctx.controlSize(spec.controlSize, "height", use)
			return D2.fromOffset(length, length)
		end
		local function strip(name: string, children: { Types.Child }): Frame
			local props: Types.FrameNativeProps = {
				Name = name,
				Size = D2.fromOffset(0, 0),
				AutomaticSize = E.AutomaticSize.XY,
				Host.UIListLayout({
					FillDirection = E.FillDirection.Horizontal,
					SortOrder = E.SortOrder.LayoutOrder,
					Padding = D.new(0, 4),
				}) :: Types.Child,
			}
			for _, child in children do
				props[#props + 1] = child
			end
			return ctx.styled(Host.Frame(props), "segmented")
		end
		local function mark(node: GuiObject, side: Content.VoteValue)
			node:AddTag("facet-segment")
			Compose.watch(function(use: ComposeTypes.Use)
				if use(value) == side then
					node:AddTag("facet-segment-current")
				elseif node:HasTag("facet-segment-current") then
					node:RemoveTag("facet-segment-current")
				end
			end)
		end
		local mode = Compose.show(readOnly, function()
			local marks: { Types.Child } = {}
			for order, entry in SIDES do
				local box = Host.Frame(entry.name)({
					LayoutOrder = order,
					BackgroundTransparency = 1,
					Size = side,
					Attributes = {
						label = entry.label,
						selected = function(use: ComposeTypes.Use): boolean
							return use(value) == entry.side
						end,
					} :: Types.Attributes,
					Host.UICorner({}) :: Types.Child,
					ctx.icon(entry.icon, {
						Name = "Icon",
						AnchorPoint = V2.new(0.5, 0.5),
						Position = D2.fromScale(0.5, 0.5),
						Size = function(use: ComposeTypes.Use)
							local length = ctx.controlSize(spec.controlSize, "iconSize", use)
							return D2.fromOffset(length, length)
						end,
					}) :: Types.Child,
				})
				mark(box, entry.side)
				table.insert(marks, box :: Types.Child)
			end
			local plate = strip("Plate", marks)
			return plate
		end, function()
			local buttons: { Types.Child } = {}
			for order, entry in SIDES do
				local button = UI.Button({
					Name = entry.name,
					LayoutOrder = order,
					label = "",
					name = entry.label,
					icon = entry.icon,
					controlSize = spec.controlSize,
					selected = function(use: ComposeTypes.Use): boolean
						return use(value) == entry.side
					end,
					enabled = enabled,
					onActivate = function()
						propose(entry.side)
					end,
					Size = side,
					AutomaticSize = E.AutomaticSize.None,
					Host.UISizeConstraint({
						MinSize = function(use: ComposeTypes.Use)
							return V2.new(touchFloor(use), touchFloor(use))
						end,
					}) :: Types.Child,
				})
				mark(button, entry.side)
				table.insert(buttons, button :: Types.Child)
			end
			return strip("Choice", buttons)
		end)
		local summary = ctx.text({
			Name = "Summary",
			LayoutOrder = 2,
			Text = function(use: ComposeTypes.Use): string
				return read(spec.summary, use) or ""
			end,
			Visible = function(use: ComposeTypes.Use): boolean
				local text = read(spec.summary, use)
				return text ~= nil and text ~= ""
			end,
			TextWrapped = false,
			TextTruncate = E.TextTruncate.AtEnd,
			Attributes = {
				FacetLabel = function(use: ComposeTypes.Use): string
					return read(spec.summary, use) or ""
				end,
			} :: Types.Attributes,
		})
		summary:AddTag("facet-secondary")
		return Host.Frame(ctx.props(spec, {
			"value",
			"onChange",
			"summary",
			"readOnly",
			"controlSize",
			"enabled",
			"controls",
		}, {
			Name = "Vote",
			BackgroundTransparency = 1,
			Size = D2.fromOffset(0, 0),
			AutomaticSize = E.AutomaticSize.XY,
			Attributes = {
				FacetValue = function(use: ComposeTypes.Use)
					return read(value, use)
				end,
				FacetReadOnly = function(use: ComposeTypes.Use): boolean
					return use(readOnly)
				end,
			} :: Types.Attributes,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				SortOrder = E.SortOrder.LayoutOrder,
				VerticalAlignment = E.VerticalAlignment.Center,
				Padding = function(use: ComposeTypes.Use)
					return D.new(0, ctx.metric("space.s", use))
				end,
			}) :: Types.Child,
			Host.Frame "Mode" {
				LayoutOrder = 1,
				BackgroundTransparency = 1,
				Size = D2.fromOffset(0, 0),
				AutomaticSize = E.AutomaticSize.XY,
				mode,
			} :: Types.Child,
			summary :: Types.Child,
		}))
	end)
end
