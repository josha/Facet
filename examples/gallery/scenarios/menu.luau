--!strict

local COPY = {
	title = "Five ways into one list of verbs",
	intro = "Each card below opens the same avatar menu through a different gesture. The routes a card accepts are printed on it, because the framework reports no open reason — see the note at the bottom.",

	tap = "Tap",
	tapRoutes = "activate — a tap, Return, or ButtonA",
	chord = "Context key",
	chordRoutes = "keyboard, gamepad — a tap does nothing here, on purpose",
	secondary = "Right-click",
	secondaryRoutes = "Right click here; focus here for Menu / Shift+F10 / Y",
	hold = "Press and hold",
	holdRoutes = "activate, longPress — it opens before you lift your finger",
	disabled = "Nothing available",
	disabledRoutes = "activate — every item is unavailable, and it still opens",

	accessory = "Accessory Adjustment",
	layering = "Layering",
	clothing = "Clothing Layering",
	makeup = "Makeup Layering",
	lips = "Lip Color",
	eyes = "Eye Color",
	skin = "Skin Color",
	report = "Report Avatar",
	reset = "Reset Avatar",

	saveOutfit = "Save Outfit",
	shareOutfit = "Share Outfit",
	deleteOutfit = "Delete Outfit",

	idiomTitle = "Idiom",
	idiomAuto = "Automatic",
	idiomPanel = "Panel",
	idiomSheet = "Sheet",
	idiomNote = "Automatic shows a floating panel for a mouse and a sheet for touch or a narrow screen. Panel and Sheet force one presentation, so you can compare them on one device.",

	openedTitle = "What opened, and what this app can tell about it",
	nothingYet = "nothing yet — open one of the cards above",
	closed = "closed",
	open = "open",
	stateTitle = "What the framework reports",
	countsTitle = "Opens per card",
	ranTitle = "Last verb run",
	ranNothing = "none — a disabled item runs nothing, which is the whole point of the last card",
	honestTitle = "The one thing this readout cannot say",
	honest = "Which trigger opened the menu. onOpen has no argument, so each card declares one set of routes and the readout names the card.",
	depthNote = "Layering ▸ Makeup Layering is two levels deep. Right and Left enter and leave a level on a keyboard; Cancel or ButtonB closes one level and a tap outside closes all of them.",
}

local IDIOMS = { "auto", "panel", "sheet" }

return {
	title = "Menus and their five triggers",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum

		local lastOpen = Compose.cell(COPY.nothingYet)
		local ran = Compose.cell(COPY.ranNothing)
		local counts: { [string]: number } = {}
		local countsLine = Compose.cell("")
		local idiom = Compose.cell("auto")

		local presentation = Compose.formula(function(use)
			local mode = use(idiom)
			return if mode == "panel" then "menu" elseif mode == "sheet" then "sheet" else "automatic"
		end)

		local function verbs(): { any }
			local function run(key: string)
				return function()
					ran:set(COPY[key])
				end
			end
			return {
				{ id = "accessory", label = COPY.accessory, icon = "edit", onSelect = run("accessory") },
				{
					id = "layering",
					label = COPY.layering,
					icon = "more",
					children = {
						{ id = "clothing", label = COPY.clothing, onSelect = run("clothing") },
						{
							id = "makeup",
							label = COPY.makeup,
							children = {
								{ id = "lips", label = COPY.lips, onSelect = run("lips") },
								{ id = "eyes", label = COPY.eyes, onSelect = run("eyes") },
							},
						},
					},
				},
				{ id = "skin", label = COPY.skin, icon = "edit", onSelect = run("skin") },
				{ divider = true },
				{ id = "report", label = COPY.report, icon = "flag", onSelect = run("report") },
				{
					id = "reset",
					label = COPY.reset,
					icon = "trash",
					role = "destructive",
					onSelect = run("reset"),
				},
			}
		end

		local function unavailable(): { any }
			return {
				{ id = "save", label = COPY.saveOutfit, icon = "edit", enabled = false, onSelect = function() end },
				{ id = "share", label = COPY.shareOutfit, icon = "flag", enabled = false, onSelect = function() end },
				{ divider = true },
				{
					id = "delete",
					label = COPY.deleteOutfit,
					icon = "trash",
					role = "destructive",
					enabled = false,
					onSelect = function() end,
				},
			}
		end

		local CARDS = {
			{ id = "Tap", label = COPY.tap, routes = COPY.tapRoutes, triggers = { "activate" }, items = verbs },
			{
				id = "Chord",
				label = COPY.chord,
				routes = COPY.chordRoutes,
				triggers = { "keyboard", "gamepad" },
				items = verbs,
			},
			{
				id = "Secondary",
				label = COPY.secondary,
				routes = COPY.secondaryRoutes,
				triggers = { "secondary", "keyboard", "gamepad" },
				items = verbs,
			},
			{
				id = "Hold",
				label = COPY.hold,
				routes = COPY.holdRoutes,
				triggers = { "activate", "longPress" },
				items = verbs,
			},
			{
				id = "Blocked",
				label = COPY.disabled,
				routes = COPY.disabledRoutes,
				triggers = { "activate" },
				items = unavailable,
			},
		}

		local function countsText(): string
			local parts: { string } = {}
			for _, entry in CARDS do
				table.insert(parts, `{entry.label} {counts[entry.id] or 0}`)
			end
			return table.concat(parts, " · ")
		end
		countsLine:set(countsText())

		local stateLine = Compose.cell(COPY.closed)

		local function card(entry: any, conditions: any): any
			local menu = UI.Menu({
				Name = entry.id,
				label = entry.label,
				items = entry.items(),
				triggers = entry.triggers,
				presentation = presentation,

				onOpen = function()
					counts[entry.id] = (counts[entry.id] or 0) + 1

					lastOpen:set(`{entry.label} · routes: {entry.routes}`)
					countsLine:set(countsText())
					stateLine:set(`{entry.label}: {COPY.open}`)
				end,
				onClose = function()
					stateLine:set(COPY.closed)
				end,
			})
			return Host.Frame({
				Name = `Card{entry.id}`,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 4),
				}),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 8),
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
				}),
				menu,
				UI.Label "Routes" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = entry.routes,
					textRole = "caption",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
			})
		end

		local function readout(id: string, title: string, body: any): any
			return Host.Frame({
				Name = id,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 4),
				}),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 8),
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
				}),
				UI.Label({
					LayoutOrder = 1,
					Name = "Title",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = title,
					textRole = "caption",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({
					LayoutOrder = 2,
					Name = "Body",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = body,
					textRole = "caption",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			})
		end

		local function screen()
			local conditions = {
				sizeClass = Compose.formula(function(use)
					return if use(ctx.viewport).width < 600 then "compact" else "regular"
				end),
			}
			local cardRow: { any } = {}
			for _, entry in CARDS do
				table.insert(cardRow, card(entry, conditions))
			end
			return Host.Frame "MenuDemo" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 4),
					PaddingLeft = UDim.new(0, 4),
					PaddingRight = UDim.new(0, 4),
				}),
				Host.ScrollingFrame "Page" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 6,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 4),
					}),
					UI.Label "Title" {
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.title,
						textRole = "heading",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					UI.Label "Intro" {
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.intro,
						textRole = "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					Host.Frame "Cards" {
						Size = UDim2.new(1, 0, 0, 0),
						BackgroundTransparency = 1,
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({
							SortOrder = Enum.SortOrder.LayoutOrder,
							FillDirection = Enum.FillDirection.Vertical,
							Padding = UDim.new(0, 8),
						}),
						table.unpack(cardRow),
					},
					Host.Frame "IdiomBox" {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Vertical,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 4),
						}),
						Host.UIPadding({
							PaddingTop = UDim.new(0, 8),
							PaddingBottom = UDim.new(0, 8),
							PaddingLeft = UDim.new(0, 8),
							PaddingRight = UDim.new(0, 8),
						}),
						UI.Picker({
							LayoutOrder = 1,
							Name = "Idiom",
							label = COPY.idiomTitle,
							style = "segmented",
							options = {
								{ value = "auto", label = COPY.idiomAuto },
								{ value = "panel", label = COPY.idiomPanel },
								{ value = "sheet", label = COPY.idiomSheet },
							},
							selected = idiom,
						}),
						UI.Label({
							LayoutOrder = 2,
							Name = "IdiomNote",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = COPY.idiomNote,
							textRole = "caption",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
					},
					readout("Opened", COPY.openedTitle, lastOpen),
					readout("State", COPY.stateTitle, stateLine),
					readout("Counts", COPY.countsTitle, countsLine),
					readout("Ran", COPY.ranTitle, ran),
					UI.Label "DepthNote" {
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.depthNote,
						textRole = "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					readout("Honest", COPY.honestTitle, COPY.honest),
				},
			}
		end

		return {
			screen = screen,
			present = {},
			idiom = idiom,
			ran = ran,

			steps = {
				idiom = function(_built: any, payload: string?)
					idiom:set(if payload ~= nil and table.find(IDIOMS, payload) ~= nil then payload else "auto")
					return { idiom = idiom:peek() }
				end,
			},

			report = function()
				return {
					idiom = idiom:peek(),
					ran = ran:peek(),
					lastOpen = lastOpen:peek(),
					state = stateLine:peek(),
					counts = table.clone(counts),
				}
			end,
		}
	end,
}
