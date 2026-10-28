--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)
export type Callbacks = { scan: () -> (), command: ("map" | "journal") -> () }
local pages = {
	{ "Survey the river", "Follow the bank to a survey marker and scan the water." },
	{
		"Choose supplies",
		"Inspect plants, tools and habitats before spending seeds. Match each supply to the river's needs.",
	},
	{
		"Restore a stretch",
		"Place supplies from your field kit. Survey again to see what changed; keep discoveries in your journal.",
	},
}

return {
	theme = require(script.Parent.Parent.assets["riverbank-theme"]),
	build = function(app: Facet.App, inputParent: Instance, callbacks: Callbacks): Frame
		local Compose, UI = Facet.Compose, app.UI
		local Host = Facet.host(app.runtime)
		local env = UI.environment()
		local guideOpen, page, menuOpen = Compose.cell(false), Compose.cell(1), Compose.cell(false)
		local available = Compose.formula(function(use: Facet.Use)
			return not use(env.gameplaySuspended) and not use(guideOpen)
		end)
		local function scanBeacon()
			if available:peek() and not menuOpen:peek() then
				callbacks.scan()
			end
		end
		local scan = Host.InputAction "ScanBeacon" {
			Type = Enum.InputActionType.Bool,
			Enabled = function(use: Facet.Use)
				return not use(menuOpen)
			end,
			Pressed = scanBeacon,
			Host.InputBinding { KeyCode = Enum.KeyCode.E },
			Host.InputBinding { KeyCode = Enum.KeyCode.ButtonX },
		}
		local quick = Host.InputAction "QuickCommands" {
			Type = Enum.InputActionType.Bool,
			Host.InputBinding { KeyCode = Enum.KeyCode.Q },
			Host.InputBinding { KeyCode = Enum.KeyCode.ButtonY },
		}
		Host.InputContext "ExplorationInputs" {
			Parent = inputParent,
			Enabled = available,
			Priority = Facet.inputPriority.belowControls,
			Sink = true,
			scan,
			quick,
		}
		local stripPadding: Facet.Sides = { top = 0, bottom = 0, left = 12, right = 12 }
		local map: Facet.RadialAction<string> = {
			id = "Map",
			label = "Map",
			onSelect = function()
				callbacks.command("map")
			end,
		}
		local journal: Facet.RadialAction<string> = {
			id = "Journal",
			label = "Journal",
			onSelect = function()
				callbacks.command("journal")
			end,
		}
		local help: Facet.RadialAction<string> = {
			id = "Guide",
			label = "Field guide",
			onSelect = function()
				guideOpen:set(true)
			end,
		}
		local commands: { Facet.RadialItem<string> } = { map, journal, help }
		local hud = UI.Composition "ExplorationHUD" {
			padding = "m",
			UI.Region "Objective" {
				zone = "topbar",
				leading = true,
				rank = 2,
				UI.HStack "FullObjective" {
					height = 44,
					align = "center",
					gap = "m",
					padding = stripPadding,
					surface = "panel",
					UI.Text "Place" { text = "RIVERBANK", textRole = "strong" },
					UI.Text "Goal" { text = "Survey the river", textRole = "caption" },
				},
				UI.HStack "CompactObjective" {
					height = 44,
					align = "center",
					padding = stripPadding,
					surface = "panel",
					UI.Text "Goal" { text = "Survey the river", textRole = "strong" },
				},
			},
			UI.Region "PrimaryAction" {
				zone = "bottom",
				rank = 1,
				UI.VStack "Group" {
					width = env.scaled(140),
					align = "stretch",
					UI.Button "ScanButton" {
						label = "Scan water",
						appearance = "emphasis",
						shortcutHint = scan,
						enabled = available,
						onActivate = scanBeacon,
					},
				},
			},
			UI.Region "SecondaryCommands" {
				zone = "topbar",
				trailing = true,
				rank = 1,
				UI.RadialMenu "QuickActions" {
					label = "Field kit",
					preset = "top-right",
					appearance = "buttons",
					isPresented = menuOpen,
					holdAction = quick,
					enabled = available,
					items = commands,
				},
			},
		}
		local navigation: { Facet.OverlayAction } = {
			{
				id = "GuideBack",
				label = "Back",
				enabled = function(use: Facet.Use)
					return use(page) > 1
				end,
				onActivate = function()
					page:update(function(value)
						return math.max(1, value - 1)
					end)
				end,
			},
			{
				id = "GuideNext",
				label = function(use: Facet.Use)
					return if use(page) == #pages then "Done" else "Next"
				end,
				role = "default",
				onActivate = function()
					if page:peek() == #pages then
						guideOpen:set(false)
					else
						page:update(function(value)
							return value + 1
						end)
					end
				end,
			},
		}
		local guideDetent = Compose.cell("hug")
		local guideDetents: { Facet.SheetDetent } = { "hug", { id = "reading", fraction = 0.85 } }
		Compose.watch(function(use: Facet.Use)
			guideDetent:set(if use(env.isShort) then "reading" else "hug")
		end)
		local guide = UI.Sheet "FieldGuide" {
			isPresented = guideOpen,
			title = "Riverbank / Field guide",
			placement = "center",
			width = "narrow",
			closeButton = true,
			detents = guideDetents,
			detent = guideDetent,
			initialFocus = "GuideNext",
			actionLayout = "row",
			content = function()
				return UI.VStack "GuideBody" {
					width = "fill",
					gap = "m",
					UI.Text { text = "RIVER RESTORATION", textRole = "label", role = "secondary" },
					UI.ProgressView "GuidePages" {
						value = function(use: Facet.Use): number
							return use(page)
						end,
						max = #pages,
						segments = #pages,
						showValue = false,
					},
					UI.Text {
						text = function(use: Facet.Use)
							return pages[use(page)][1]
						end,
						textRole = "heading",
						wrap = true,
					},
					UI.Text {
						text = function(use: Facet.Use)
							return pages[use(page)][2]
						end,
						wrap = true,
					},
					UI.Button "GuideSkip" {
						label = "Skip guide",
						appearance = "link",
						onActivate = function()
							guideOpen:set(false)
						end,
					},
				}
			end,
			actions = navigation,
		}
		return Host.Frame "Exploration" { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), hud, guide }
	end,
}
