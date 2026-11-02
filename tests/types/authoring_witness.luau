--!strict
local Facet = require("../../src")
local Compose = Facet.Compose
local runtime = Facet.Roblox.createRuntime()
local UI = Facet.controls(runtime)
local Host = Facet.host(runtime)

local count = Compose.cell(0)
local sound = Compose.cell(true)
local volume = Compose.cell(0.5)
local query = Compose.cell("")
local open = Compose.cell(false)

local function panel(): Frame
	local leave: { Facet.DialogAction } = {
		{ id = "stay", label = "Stay", role = "cancel", onActivate = function() end },
		{ id = "leave", label = "Leave", role = "destructive", onActivate = function() end },
	}
	local detents: { Facet.SheetDetent } = { "medium", "large" }
	local start: { Facet.OverlayAction } = {
		{ id = "start", label = "Start", role = "default", onActivate = function() end },
	}
	local swipe: { Facet.RowAction } = {
		{ id = "delete", label = "Delete", role = "destructive", onActivate = function() end },
	}
	return UI.VStack "Panel" {
		width = "fill",
		align = "stretch",
		distribute = "start",
		gap = "s",
		padding = "m",
		UI.Text "Title" { text = "Garage", textRole = "title", textAlign = "center" },
		UI.Text {
			text = function(use)
				return `{use(count)} laps`
			end,
			textRole = "caption",
			role = "secondary",
		},
		Host.UICorner { CornerRadius = UDim.new(0, 8) },
		UI.HStack "Actions" {
			gap = "xs",
			UI.Button {
				label = "Bump",
				appearance = "emphasis",
				role = "default",
				controlSize = "compact",
				onActivate = function()
					count:update(function(value: number): number
						return value + 1
					end)
				end,
			},
			UI.Button { label = "Close", shape = "circle", icon = "close", underline = "hover" },
		},
		UI.Toggle { label = "Sound", value = sound, presentation = "checkbox" },
		UI.Slider { label = "Volume", value = volume, min = 0, max = 1, axis = "x" },
		UI.TextInput { value = query, placeholder = "Search", leading = Host.ImageLabel { Image = "" } },
		UI.Image { image = "rbxassetid://1", scaleMode = "tile", tileSize = { width = 16, height = 16 } },
		UI.Badge { label = "New", status = "success" },
		UI.ProgressView { value = volume, presentation = "circular" },
		UI.Avatar { name = "Alder", presence = "online" },
		UI.Grid { columns = 2, gap = "xs", align = "center", UI.Text { text = "A" }, UI.Button { label = "B" } },
		UI.Sheet {
			isPresented = open,
			detent = "large",
			detents = detents,
			title = "Filters",
			content = function()
				return UI.Text { text = "Content" }
			end,
			actions = start,
		},
		UI.RowActions { content = UI.Text { text = "Row" }, trailing = swipe },
		UI.Dialog { isPresented = open, title = "Leave the race?", actions = leave, width = "narrow" },
	}
end

local function anchored(): Frame
	local trigger = UI.Button "Trigger" { label = "Open" }
	local row = UI.HStack "Row" { gap = "xs" }
	local edit: Facet.MenuCommand = { id = "edit", label = "Edit", onSelect = function() end }
	local items: { Facet.MenuItem } = { edit }
	local swipe: { Facet.RowAction } = {
		{ id = "delete", label = "Delete", role = "destructive", onActivate = function() end },
	}
	return UI.VStack "Anchored" {
		trigger,
		row,
		UI.Menu { trigger = trigger, items = items },
		UI.Callout {
			anchor = trigger,
			title = "Tip",
			isPresented = open,
			onRetire = function() end,
		},
		UI.Popover {
			trigger = trigger,
			isPresented = open,
			content = function(): Instance
				return UI.Text { text = "Tip" }
			end,
		},
		UI.Flash { target = row, progress = volume },
		UI.RowActions { content = row, trailing = swipe },
	}
end

return { panel = panel, anchored = anchored }
