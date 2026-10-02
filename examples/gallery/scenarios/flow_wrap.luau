--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T

local ALIGN_BOX_ROWS = 10

local TAG_GAP = 6

local TAG_COUNT = 14
local SHORT_COUNT = 4
local COPY = {
	title = "wrap — the row that runs out of room",
	wrapLabel = "Wrap the tags",
	cloudCaption = "Fourteen tags in one HStack. Turn wrapping off and watch them leave the box.",
	alignCaption = "Where the BLOCK of lines sits — the container's ordinary `align`, no new word.",
	alignLabel = "Block",
	alignStart = "Start",
	alignCenter = "Center",
	alignEnd = "End",
	fitting = "Fitting: the solver reports nothing.",
	overflowing = "Overflowing: the solver is reporting it, live.",
	tag1 = "Rally",
	tag2 = "Drift",
	tag3 = "Circuit",
	tag4 = "Sprint",
	tag5 = "Endurance",
	tag6 = "Time attack",
	tag7 = "Hill climb",
	tag8 = "Rallycross",
	tag9 = "Autocross",
	tag10 = "Gymkhana",
	tag11 = "Touge",
	tag12 = "Karting",
	tag13 = "Formula",
	tag14 = "Off-road",
	short1 = "One",
	short2 = "Two",
	short3 = "Three",
	short4 = "Four",
}

return {
	title = "Native wrapping rows",
	ledgerRows = {},
	copy = COPY,

	tagCount = TAG_COUNT,
	shortCount = SHORT_COUNT,
	build = function(ctx: any)
		local UI, Compose: ComposeModule = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose: ComposeModule = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum

		local wrapping = Compose.cell(true)
		local blockAlign = Compose.cell("start")

		local status = Compose.formula(function(use: Use)
			return if use(wrapping) then COPY.fitting else COPY.overflowing
		end)

		local function tag(id: string, label: string): any
			return UI.Button({
				Name = id,
				label = label,
				onActivate = function() end,
			})
		end

		local function tagRow(props: { [any]: any }, prefix: string, key: string, count: number)
			for i = 1, count do
				table.insert(props, tag(`{prefix}{i}`, (COPY :: any)[`{key}{i}`]))
			end
			return props
		end

		local function Example()
			return Host.Frame "FlowWrap" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				UI.ScrollView "Page" {
					padding = 16,
					gap = 8,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					ScrollBarThickness = 6,
					UI.Text({
						LayoutOrder = 1,
						Name = "Title",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.title,
						textRole = "body" :: "body",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}) :: unknown,
					UI.Toggle({
						LayoutOrder = 2,
						Name = "WrapToggle",
						label = COPY.wrapLabel,
						value = wrapping,
					}),
					UI.Text({
						LayoutOrder = 3,
						Name = "Status",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = status,
						textRole = "caption" :: "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Text({
						LayoutOrder = 4,
						Name = "CloudCaption",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.cloudCaption,
						textRole = "caption" :: "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Host.Frame({
						LayoutOrder = 5,
						Name = "Cloud",
						Size = UDim2.new(1, 0, 0, 0),
						BackgroundTransparency = 1,
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({
							SortOrder = Enum.SortOrder.LayoutOrder,
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 8),
							Wraps = wrapping,
						}) :: unknown,
						table.unpack(tagRow({}, "T", "tag", TAG_COUNT)),
					}),
					UI.Text({
						LayoutOrder = 6,
						Name = "AlignCaption",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.alignCaption,
						textRole = "caption" :: "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Picker({
						LayoutOrder = 7,
						Name = "BlockAlign",
						label = COPY.alignLabel,
						style = "segmented" :: "segmented",
						options = {
							{ value = "start", label = COPY.alignStart } :: PickerOption,
							{ value = "center", label = COPY.alignCenter } :: PickerOption,
							{ value = "end", label = COPY.alignEnd } :: PickerOption,
						},
						selected = blockAlign,
					}),
					Host.Frame({
						LayoutOrder = 8,
						Name = "AlignBox",
						Size = UDim2.new(1, 0, 0, 0),
						BackgroundTransparency = 1,
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({
							SortOrder = Enum.SortOrder.LayoutOrder,
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 8),
							Wraps = true,
							HorizontalAlignment = function(use: Use)
								local value = use(blockAlign)
								return if value == "center"
									then Enum.HorizontalAlignment.Center
									elseif value == "end" then Enum.HorizontalAlignment.Right
									else Enum.HorizontalAlignment.Left
							end,
						}) :: unknown,
						table.unpack(tagRow({}, "S", "short", SHORT_COUNT)),
					}),
				},
			}
		end

		return {
			screen = Example,
			present = {},

			wrapping = wrapping,
			blockAlign = blockAlign,

			steps = {

				setWrap = function(_built: any, payload: string?)
					wrapping:set(payload ~= "off")
					return { wrap = wrapping:peek() }
				end,
				setAlign = function(_built: any, payload: string?)
					local value = if payload == "center" or payload == "end" then payload else "start"
					blockAlign:set(value)
					return { align = value }
				end,
			},

			report = function()
				return {
					wrap = wrapping:peek(),
					align = blockAlign:peek(),
					tags = TAG_COUNT,
				}
			end,

			dispose = function() end,
		}
	end,
}
