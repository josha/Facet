--!strict

local Facet = require("../../src")

export type RowsItem = { id: string, label: string }

export type Props = {
	rows: Facet.ReadOnlyValue<{ RowsItem }>,
}

local _design = {
	contract = {
		inputs = {
			{
				fields = { { id = "id", type = "string" }, { id = "label", type = "string" } },
				id = "rows",
				kind = "readable",
				required = true,
				type = "list",
			},
		},
		outputs = {},
	},
	name = "DesignConsumers",
	state = {
		{ id = "selection", initial = "first", type = "string" },
		{ id = "presented", initial = false, type = "boolean" },
	},
}

return function(UI: Facet.Controls, props: Props): GuiObject
	local sheetDetents: { Facet.SheetDetent } = {
		"medium",
		{ fraction = 1, id = "large" },
		{ height = 180, id = "short" },
	}
	local state = { selection = Facet.Compose.cell "first", presented = Facet.Compose.cell(false) }
	local tableColumns: { Facet.TableColumn<RowsItem, string> } = {
		{
			align = "start",
			id = "label",
			label = "Label",
			render = function(current: Facet.ReadOnlyValue<RowsItem>)
				return UI.Text "Text" {
					text = function(use)
						return use(current).label
					end,
					textRole = "body",
					wrap = true,
				}
			end,
		},
	}
	local tabViewTabs: { Facet.Tab } = {
		{
			badgeAnchor = "topTrailing",
			content = function()
				return UI.Text "Text" {
					text = "A little possibility",
					textRole = "body",
					wrap = true,
				}
			end,
			id = "first",
			indicator = { form = "dot", status = "info" },
			label = "Overview",
		},
		{
			content = function()
				return UI.Text "Text" {
					text = "A little possibility",
					textRole = "body",
					wrap = true,
				}
			end,
			id = "second",
			indicator = { form = "ring", status = "success" },
			label = "Details",
		},
	}
	return UI.VStack "VStack" {
		gap = "s",
		width = "fill",
		UI.Table "Table" {
			Size = UDim2.fromOffset(320, 240),
			columns = tableColumns,
			itemSize = 44,
			from = props.rows,
			key = "id",
		},
		UI.Sheet "Sheet" {
			detent = "medium",
			detents = sheetDetents,
			isPresented = state.presented,
			title = "A little more detail",
			content = function()
				return UI.Text "Text" {
					text = "Make this content yours",
					textRole = "body",
					wrap = true,
				}
			end,
		},
		UI.TabView "TabView" {
			placement = "topBar",
			selection = state.selection,
			tabs = tabViewTabs,
		},
	}
end
