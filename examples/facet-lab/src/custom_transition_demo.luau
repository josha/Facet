--!strict
local Catalog = require("./catalog_types")
local journal = require("./journal_demo")
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Transition = typeof(require("@repo/tools/typecheck/aliases").Transition)
type Phase = typeof(require("@repo/tools/typecheck/aliases").TransitionContext)
type Attributes = typeof(require("@repo/tools/typecheck/aliases").Attributes)
type Tab = typeof(require("@repo/tools/typecheck/aliases").Tab)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T

return {
	family = "navigation",
	recipe = true,
	cellHeight = 520,
	cellWidth = 600,
	fills = true,
	matrix = false,
	base = function()
		return {}
	end,
	alias = "Custom transitions",
	purpose = "Turn an opaque page across a book spine, or stagger menu rows, with shared presentation progress.",
	alternatives = "Use default transitions unless the motion explains the screen.",
	snippet = "transition = { apply = function(content, phase) runtime.decorate(content, { Rotation = function(use) return -8 * (1 - use(phase.progress)) end }) end }",
	demonstrates = { "transition" },
	axes = {},
	states = {},
	make = function(UI: Controls, _: never, c: Catalog.Context): Instance
		local Host, runtime, D2 = c.Host, c.app.runtime, c.types.UDim2
		local opened, selected = c.cell("opened", false), c.cell("selected", "Journal")
		local journalSpread = c.cell("journalSpread", "crossing")
		local menu: Transition = {
			motion = "pageTurn",
			apply = function(content: GuiObject, phase: Phase)
				local rows = content:GetDescendants()
				for _, row in rows do
					local order = row:GetAttribute("EntranceOrder")
					if row:IsA("GuiObject") and type(order) == "number" then
						runtime.decorate(row, {
							Position = function(use: Use): UDim2
								local progress =
									math.clamp((use(phase.progress) - order * 0.12) / (1 - order * 0.12), 0, 1)
								return D2.fromOffset(48 * (1 - progress), 0)
							end,
						})
					end
				end
			end,
		}
		local function page(name: string): Instance
			local children: { unknown } = {}
			for index, label in { "Equipment", "Abilities", "Quests" } do
				children[index] = Host.Frame(name .. label) {
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 0),
					AutomaticSize = c.types.Enum.AutomaticSize.Y,
					UI.Button {
						label = `{name}: {label}`,
						Size = D2.fromScale(1, 0),
						AutomaticSize = c.types.Enum.AutomaticSize.Y,
						Attributes = { EntranceOrder = index - 1 } :: Attributes,
						onActivate = function()
							opened:set(true)
						end,
					},
				}
			end
			return UI.VStack "MenuRows" { width = "fill", height = "hug", gap = 12, table.unpack(children) }
		end
		return UI.VStack "TransitionDemo" {
			width = "fill",
			height = "fill",
			gap = 12,
			UI.Text {
				text = "Switch tabs to compare staggered motion. Open the journal to turn a page forward and back. Reduced motion uses a fade.",
				wrap = true,
				Size = D2.fromScale(1, 0),
				AutomaticSize = c.types.Enum.AutomaticSize.Y,
			} :: unknown,
			UI.Button {
				label = "Open journal",
				onActivate = function()
					opened:set(true)
				end,
			} :: unknown,
			UI.TabView {
				selection = selected,
				transition = menu,
				Size = D2.new(1, 0, 0, 340),
				tabs = {
					{
						id = "Journal",
						content = function(): Instance
							return page("Journal")
						end,
					},
					{
						id = "Loadout",
						content = function(): Instance
							return page("Loadout")
						end,
					},
				} :: { Tab },
			} :: unknown,
			UI.Sheet {
				title = "Field journal",
				closeButton = "Close journal",
				isPresented = opened,
				placement = "bottom",
				width = "wide",
				detents = { "hug" :: "hug" },
				content = function(): Instance
					return journal(UI, runtime, c.Compose, c.types, journalSpread)
				end,
			} :: unknown,
		}
	end,
} :: Catalog.PageDefinition
