--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local storage = game:GetService("ReplicatedStorage")

local PAD = {
	open = "ButtonA",
	close = "ButtonB",
	moves = { "DPadDown", "DPadLeft", "DPadRight", "StickUp", "StickDown", "StickLeft", "StickRight" },
}
local KEYS = { open = "Return", close = "Escape", moves = { "Up", "Down", "Left", "Right" } }

local CASES: {
	{
		id: string,
		show: string,
		tab: string?,
		trigger: string | nil,
		before: string?,
		inline: boolean?,
		anywhere: boolean?,
		anchor: string?,
	}
} =
	{
		{ id = "menu", show = "all-controls", tab = "actions/menus", trigger = "Trigger" },
		{ id = "menu-sheet", show = "all-controls", tab = "actions/menus", before = "sheet", trigger = "Trigger" },
		{ id = "collapsible", show = "all-controls", tab = "navigation/disclosure", trigger = "Settings" },
		{
			id = "disclosure-group",
			show = "all-controls",
			tab = "navigation/disclosure",
			trigger = "Practice",
			inline = true,
		},
		{ id = "sheet-lobby", show = "all-controls", tab = "actions/sheets", trigger = "OpenLobby" },
		{ id = "sheet-filters", show = "all-controls", tab = "actions/sheets", trigger = "OpenFilters" },
		{ id = "popover-filter", show = "all-controls", tab = "actions/overlays", trigger = "Filter" },
		{ id = "dialog", show = "all-controls", tab = "actions/overlays", trigger = "DialogButton" },
		{ id = "alert", show = "all-controls", tab = "actions/alerts", trigger = "Open" },
		{ id = "sheet", show = "all-controls", tab = "actions/sheets", trigger = "Open" },
		{ id = "date-picker", show = "all-controls", tab = "inputs/pickers", trigger = "Open" },
		{ id = "color-picker", show = "all-controls", tab = "inputs/pickers", trigger = "Well" },
		{ id = "callout", show = "all-controls", tab = "actions/help", trigger = "Show", anchor = "Plus" },
		{ id = "radial", show = "radial-menu", trigger = "Launcher" },
		{ id = "demo-popover", show = "all-controls", trigger = "Showcase", anywhere = true },
	}

local function api(command: string, argument: any): any
	return (workspace:WaitForChild("FacetShowcaseAPI") :: any):Invoke(command, argument)
end

type Case = {
	id: string,
	contracts: { string },
	run: ((any) -> ())?,
	setup: ((any) -> any)?,
	steps: { [string]: (any, any) -> () }?,
	keepGallery: boolean?,
}
local cases: { Case } = {}
for _, spec in CASES do
	table.insert(cases, {
		id = "opened-" .. spec.id,
		contracts = {},
		run = function(t: any)
			local live = (require :: any)(storage.FacetLive)
			local focus = (require :: any)(storage.FacetLive.focus)
			local root = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
			local options = shared.FacetFocusOpened or {}
			local keys = table.clone(if options.keys then KEYS else PAD)
			keys.up = if options.keys then nil else options.up
			keys.closeFrom = if spec.inline then "trigger" else nil
			if spec.inline then
				keys.close = keys.open
			end
			api("show", spec.show)
			t.settle(30)
			if spec.tab then
				api("tab", string.split(spec.tab, "/")[1])
				t.settle(10)
				api("tab", spec.tab)
				t.settle(30)
			end
			local scope = if spec.tab then "Content." .. string.split(spec.tab, "/")[2] else spec.show
			local function find(name: string?): GuiObject?
				for _, node in focus.stops(root) do
					if
						(name == nil or node.Name == name)
						and (spec.anywhere or string.find(node:GetFullName(), scope, 1, true))
					then
						return node
					end
				end
				return nil
			end
			if spec.before then
				local choice = find(spec.before)
				if choice then
					game:GetService("GuiService").SelectedObject = choice
					t.settle(3)
					live.press({ keys.open })
					t.settle(10)
				end
			end
			local trigger = find(spec.trigger)
			t.check("trigger found", trigger ~= nil, spec.trigger)
			if trigger == nil then
				return
			end
			if spec.anchor then
				local gui = game:GetService("GuiService")
				local before: { [Instance]: boolean } = {}
				for _, node in focus.stops(root) do
					before[node] = true
				end
				gui.SelectedObject = trigger
				t.settle(3)
				live.press({ keys.open })
				t.settle(40)
				local anchor = find(spec.anchor)
				local action: GuiObject? = nil
				for _, node in focus.stops(root) do
					if not before[node] then
						action = action or node
					end
				end
				t.check("the plate shows an action", action ~= nil)
				t.check("the anchor is a stop", anchor ~= nil, spec.anchor)
				if not (anchor and action) then
					return
				end
				t.check(
					"the anchor links to the action of the plate",
					anchor.NextSelectionUp == action or anchor.NextSelectionDown == action,
					{ up = tostring(anchor.NextSelectionUp), down = tostring(anchor.NextSelectionDown) }
				)
				gui.SelectedObject = action
				t.settle(3)
				live.press({ keys.close })
				t.settle(40)
				t.check("the plate closes from its action", table.find(focus.stops(root), action) == nil)
				t.check("focus returns to the anchor", gui.SelectedObject == anchor, tostring(gui.SelectedObject))
				return
			end
			local report = focus.opened(root, trigger, keys)
			report.moves = nil
			t.check("focus moves into it", report.landedInside or spec.inline == true, report.landed)
			t.check("every item reachable", #report.unreached == 0, report.unreached)
			t.check("no escape to the page behind", spec.inline == true or #report.escapes == 0, report.escapes)
			t.check("closes", report.closed, report.closePresses)
			t.check("focus returns to the trigger", report.returned, report.after)
			t.note("report", report)
			live.save(
				`focus-opened-{spec.id}{if options.keys then "-keys" else ""}`,
				HttpService:JSONEncode(report),
				"live"
			)
		end,
	})
end

return cases
