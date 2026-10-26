--!strict

type ExampleContext = typeof(require("@repo/examples/types").Context)
type Built = typeof(require("@repo/examples/types").Built)

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
type Use = <T>(ReadOnlyValue<T>) -> T

local ALIGN_BOX_ROWS = 10

local TAG_GAP = 6

local TAG_COUNT = 14
local SHORT_COUNT = 4
local COPY: { [string]: string } = {
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
	build = function(ctx: ExampleContext): Built
		local UI, Compose: ComposeModule = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local nativeTypes = ctx.types
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum

		local wrapping = Compose.cell(true)
		local blockAlign = Compose.cell("start")

		local status = Compose.formula(function(use: Use)
			return if use(wrapping) then COPY.fitting else COPY.overflowing
		end)

		local function tag(id: string, label: string): TextButton
			return UI.Button({
				Name = id,
				label = label,
				onActivate = function() end,
			})
		end

		local function tagRow(prefix: string, key: string, count: number): { TextButton }
			local tags: { TextButton } = {}
			for i = 1, count do
				table.insert(tags, tag(`{prefix}{i}`, COPY[`{key}{i}`]))
			end
			return tags
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
					UI.Text "Title" {
						LayoutOrder = 1,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.title,
						textRole = "body",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					UI.Toggle "WrapToggle" {
						LayoutOrder = 2,
						label = COPY.wrapLabel,
						value = wrapping,
					},
					UI.Text "Status" {
						LayoutOrder = 3,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = status,
						textRole = "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					UI.Text "CloudCaption" {
						LayoutOrder = 4,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.cloudCaption,
						textRole = "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					Host.Frame "Cloud" {
						LayoutOrder = 5,
						Size = UDim2.new(1, 0, 0, 0),
						BackgroundTransparency = 1,
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({
							SortOrder = Enum.SortOrder.LayoutOrder,
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 8),
							Wraps = wrapping,
						}),
						table.unpack(tagRow("T", "tag", TAG_COUNT)),
					},
					UI.Text "AlignCaption" {
						LayoutOrder = 6,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.alignCaption,
						textRole = "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					UI.Picker "BlockAlign" {
						LayoutOrder = 7,
						label = COPY.alignLabel,
						style = "segmented",
						options = {
							{ value = "start", label = COPY.alignStart },
							{ value = "center", label = COPY.alignCenter },
							{ value = "end", label = COPY.alignEnd },
						},
						selected = blockAlign,
					},
					Host.Frame "AlignBox" {
						LayoutOrder = 8,
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
						}),
						table.unpack(tagRow("S", "short", SHORT_COUNT)),
					},
				},
			}
		end

		return {
			screen = Example,
			present = {},

			wrapping = wrapping,
			blockAlign = blockAlign,

			steps = {

				setWrap = function(_built: unknown, payload: string?)
					wrapping:set(payload ~= "off")
					return { wrap = wrapping:peek() }
				end,
				setAlign = function(_built: unknown, payload: string?)
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
