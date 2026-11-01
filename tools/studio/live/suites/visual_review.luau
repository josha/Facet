--!strict
type StringCell = typeof(require("@repo/tools/typecheck/aliases").StringCell)

type Case = {
	id: string,
	contracts: { string },
	run: ((any) -> ())?,
	setup: ((any) -> any)?,
	steps: { [string]: (any, any) -> () }?,
	keepGallery: boolean?,
}
local cases: { Case } = {}

local function themeOf(t: any): any
	local options = shared.FacetVisual or {}
	for _, entry in t.themes do
		if entry.name == options.theme then
			return entry.package
		end
	end
	return nil
end

local function sizeOf(): Vector2
	local options = shared.FacetVisual or {}
	return Vector2.new(options.width or 1200, options.height or 700)
end

table.insert(cases, {
	id = "changed-controls-board",
	contracts = {},
	setup = function(t: any)
		local stage = t.mount(function(UI: any, Host: any, Compose: any)
			local pages = {}
			for _, id in { "one", "two", "three" } do
				table.insert(pages, {
					id = id,
					label = id,
					content = Host.Frame {
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						UI.Text { text = "Page " .. id },
					},
				})
			end
			local wide = sizeOf().X >= 700
			local long = "A long description that does not fit on one line of this header and must wrap inside it"
			return UI.Screen "Board" {
				padding = "m",
				UI.ScrollView "ReviewScroll" {
					gap = "m",
					Size = UDim2.fromScale(1, 1),
					UI.Text { text = "Button: icon and label at an authored 52 px width", textRole = "caption" },
					UI.HStack {
						gap = "s",
						UI.Button "Tight" {
							icon = "chevron.leading",
							label = "Back",
							Size = UDim2.fromOffset(52, 44),
							AutomaticSize = Enum.AutomaticSize.None,
						},
						UI.Button "Both" {
							icon = "chevron.leading",
							trailingIcon = "chevron.trailing",
							label = "Step",
							Size = UDim2.fromOffset(52, 44),
							AutomaticSize = Enum.AutomaticSize.None,
						},
						UI.Button "Wide" { icon = "chevron.leading", label = "Back to the lobby" },
					},
					UI.Text { text = "DisclosureGroup: long description", textRole = "caption" },
					UI.DisclosureGroup "Trailing" {
						Size = UDim2.fromOffset(if wide then 420 else 340, 0),
						label = "Details",
						description = long,
						chevronPosition = "trailing",
						appearance = "contained",
						expanded = Compose.cell(false),
						content = function(): Instance
							return UI.Text { text = "Body" }
						end,
					},
					UI.DisclosureGroup "Leading" {
						Size = UDim2.fromOffset(if wide then 420 else 340, 0),
						label = "Details",
						description = long,
						chevronPosition = "leading",
						appearance = "contained",
						expanded = Compose.cell(true),
						content = function(): Instance
							return UI.Text { text = "Body" }
						end,
					},
					UI.Text { text = "Slider: range fill under the handles", textRole = "caption" },
					UI.Slider "Range" {
						Size = UDim2.fromOffset(if wide then 420 else 320, 0),
						value = Compose.cell({ lower = 4, upper = 12 }),
						min = 1,
						max = 20,
						range = true,
					},
					UI.Text { text = "Stepper and PageView dots", textRole = "caption" },
					UI.Stepper "Step" { value = Compose.cell(10), max = 10 },
					Host.Frame {
						Size = UDim2.fromOffset(if wide then 420 else 320, 160),
						BackgroundTransparency = 1,
						UI.PageView "Courses" { pages = pages, selection = Compose.cell("one") },
					},
				},
			}
		end, { size = sizeOf(), theme = themeOf(t), frames = 20 })
		return { stage = stage }
	end,
	steps = {
		held = function(t: any, value: any)
			t.check("the board is mounted", value.stage ~= nil)
			local scroll = t.find(value.stage, "ReviewScroll")
			t.check("native wheel input reaches the lower controls", scroll.CanvasPosition.Y > 0, scroll.CanvasPosition)
			t.inside("the PageView is reachable inside the review viewport", t.find(value.stage, "Courses"), scroll, 1)
		end,
	},
})

table.insert(cases, {
	id = "radial-menu-board",
	contracts = {},
	setup = function(t: any)
		local options = shared.FacetVisual or {}
		local open: any
		local selected: StringCell
		local stage = t.mount(function(UI: any, _Host: any, Compose: any)
			open = Compose.cell(false)
			selected = Compose.cell("")
			local items = {}
			for _, entry in
				{
					{ "N", "chevron.up" },
					{ "E", "chevron.trailing" },
					{ "S", "chevron.down" },
					{ "W", "chevron.leading" },
				}
			do
				table.insert(items, {
					id = entry[1],
					slot = entry[1],
					label = options.label or entry[1],
					icon = entry[2],
					labelStyle = if options.iconOnly then "icon" else nil,
					completion = "stay",
					onSelect = function()
						selected:set(entry[1])
					end,
				})
			end
			return UI.RadialMenu "Quick" { isPresented = open, items = items, preset = options.preset }
		end, { size = sizeOf(), theme = themeOf(t), frames = 20 })
		open:set(true)
		t.settle(60)
		return { stage = stage, selected = selected }
	end,
	steps = {
		held = function(t: any, value: any)
			t.check("the board is mounted", value.stage ~= nil)
			t.check(
				"native pointer input activates the north command",
				value.selected:peek() == "N",
				value.selected:peek()
			)
			for _, id in { "N", "E", "S", "W" } do
				local item = t.find(value.stage, id)
				local caption = item and (t.find(item, "Title") or item)
				local icon = item and t.find(item, "LeadingIcon")
				local namedIcon = icon ~= nil
					and t.visible(icon)
					and icon.AbsoluteSize.X > 0
					and icon.AbsoluteSize.Y > 0
				t.check(
					id .. " keeps its command name",
					item ~= nil and item:GetAttribute("label") == ((shared.FacetVisual or {}).label or id)
				)
				t.check(
					id .. " presents a fitting caption or icon",
					item ~= nil and t.visible(item) and ((caption ~= nil and t.fits(caption)) or namedIcon),
					caption and { caption.ContentText, caption.TextBounds, caption.AbsoluteSize }
				)
				if namedIcon then
					t.inside(id .. " icon stays inside its target", icon, item, 1)
				end
			end
		end,
	},
})

return cases
