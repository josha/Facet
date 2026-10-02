--!strict
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type ExampleContext = typeof(require("@repo/examples/types")(nil :: any))
local copy = {
	tasksTitle = "Beginner tasks",
	task1 = "Win a round",
	task2 = "Land 25 hits",
	task3 = "Open a crate",
	reward1 = "+50",
	reward2 = "+120",
	reward3 = "+300",
	tasksChip = "Tasks 1/3",
	timer = "2:14",
	timerShort = "2m",
	scoreHome = "12",
	scoreAway = "9",
	weapon1 = "Rifle",
	weapon2 = "Pistol",
	weapon3 = "Knife",
	ammo1 = "24/90",
	ammo2 = "7/21",
	ammo3 = "--",
	weaponName = "Ranger rifle",
	readout = "60 FPS · 42 ms",
	action1 = "Shop",
	action2 = "Squad",
	action3 = "Menu",
	round1 = "HUD actions",
	round2 = "Report",
	overflowTitle = "Hidden right now",
	overflowEmpty = "Nothing is hidden — every zone is showing everything it has.",
	overflowNote = "Nothing is deleted. A zone that gives way is listed here.",
	feed = "Ravi eliminated Mo",
	urlBarOn = "URL bar",
	urlBarField = "example.com/play",
	rideOn = "Topbar strip",
	objective = "Round 3 · Capture",
	objectiveShort = "R3",
	ladder = "Gives way first: fps, feed, tasks, weapon, health, rail, actions, clock, buttons. Tap a smaller piece or its ··· to see the rest.",
}
local FORMS = {
	Strip = { "full", "short" },
	Rounds = { "full", "column" },
	Tasks = { "full", "one", "chip" },
	Health = { "full", "compact" },
	Feed = { "full" },
	Clock = { "full", "timer", "short" },
	Rail = { "full", "chip" },
	Readout = { "full" },
	Actions = { "full", "compact" },
	Weapon = { "full" },
}
local LOSSLESS = { Rounds = true, Actions = true }
local ORDER = { "Strip", "Rounds", "Tasks", "Health", "Feed", "Clock", "Rail", "Readout", "Actions", "Weapon" }
return {
	title = "Screen-anchored HUD",
	copy = copy,
	forms = FORMS,
	build = function(ctx: ExampleContext)
		local Host, UI, Compose: typeof(require("@repo/src/vendor/compose/core")), Facet =
			ctx.Host, ctx.UI, ctx.Compose, ctx.Facet
		local D, D2, V2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
		local health, roundLeft, seconds = Compose.cell(0.84), Compose.cell(0.62), Compose.cell(134)
		local tasks = { Compose.cell(0.2), Compose.cell(0.4), Compose.cell(0.6) }
		local urlBar, ride, overflow, reportOpen =
			Compose.cell(false), Compose.cell(true), Compose.cell(false), Compose.cell(false)
		local notice, selectedWeapon =
			(function(value: string?): typeof(require("@repo/tools/typecheck/example_shapes").optionalStringCell(nil))
				return Compose.cell(value)
			end)(nil), Compose.cell(1)
		local chosen = {}
		for _, id in ORDER do
			chosen[id] = Compose.cell(1)
		end
		local forms = Compose.formula(function(use: Use)
			local named = {}
			for _, id in ORDER do
				local index = use(chosen[id])
				named[id] = if index == 0 then "hidden" else FORMS[id][index] or "reveal"
			end
			return named
		end)
		local unshown = Compose.formula(function(use: Use)
			local result = {}
			for _, id in ORDER do
				if use(chosen[id]) ~= 1 and id ~= "Rounds" then
					table.insert(result, id)
				end
			end
			return result
		end)
		local short = Compose.formula(function(use: Use)
			local viewport = if ctx.viewport then use(ctx.viewport) else nil
			return viewport ~= nil and viewport.height < 480
		end)
		local function row(
			name: string,
			children: { GuiObject },
			gap: number?,
			vertical: boolean?,
			align: Enum.HorizontalAlignment?
		): Frame
			local fields: { [any]: any } = {
				Name = name,
				BackgroundTransparency = 1,
				Size = D2.new(),
				AutomaticSize = E.AutomaticSize.XY,
				Host.UIListLayout({
					FillDirection = if vertical then E.FillDirection.Vertical else E.FillDirection.Horizontal,
					HorizontalAlignment = align or E.HorizontalAlignment.Left,
					VerticalAlignment = E.VerticalAlignment.Center,
					Padding = D.new(0, gap or 6),
					SortOrder = E.SortOrder.LayoutOrder,
				}),
			}
			for index, child in children do
				child.LayoutOrder = index
				table.insert(fields, child)
			end
			return Host.Frame(fields)
		end
		local function plate(name: string, slot: string, content: GuiObject, padX: number, padY: number): Frame
			local node = Host.Frame({
				Name = name,
				Size = D2.new(),
				AutomaticSize = E.AutomaticSize.XY,
				Host.UICorner({}) :: unknown,
				Host.UIPadding({}),
				Host.Frame({
					Name = "Inset",
					BackgroundTransparency = 1,
					Size = D2.new(),
					AutomaticSize = E.AutomaticSize.XY,
					Host.UIPadding({
						PaddingLeft = D.new(0, padX),
						PaddingRight = D.new(0, padX),
						PaddingTop = D.new(0, padY),
						PaddingBottom = D.new(0, padY),
					}) :: unknown,
					content,
				}),
			})
			node:AddTag("facet-" .. slot)
			if ctx.theme then
				Compose.cleanup((ctx.runtime.mount(function()
					return Facet.themes.skin(ctx.runtime, ctx.theme, slot, { types = ctx.types, target = node })
				end, node)))
			end
			return node
		end
		local function text(
			name: string,
			label: string | ((Use) -> string),
			role: ("caption" | "label" | "body" | "heading" | "title" | "control" | "strong" | "numeral")?
		): GuiObject
			return UI.Text({
				Name = name,
				text = label,
				textRole = role or ("caption" :: "caption"),
				Size = D2.new(),
				AutomaticSize = E.AutomaticSize.XY,
			})
		end
		local function pill(
			name: string,
			label: any,
			role: ("caption" | "label" | "body" | "heading" | "title" | "control" | "strong" | "numeral")?
		): Frame
			return plate(name, "control", text(name .. "Text", label, role), 10, 4)
		end
		local function disc(name: string, label: string, icon: string, onActivate: (() -> ())?): TextButton
			return UI.Button({
				Name = name,
				label = "",
				name = label,
				icon = icon,
				shape = "circle" :: "circle",
				Size = D2.fromOffset(44, 44),
				onActivate = onActivate,
			})
		end
		local function showNotice(message: string)
			notice:set(message)
		end
		local steps = {
			takeDamage = function()
				health:set(math.max(0, health:peek() - 0.25))
				return { fraction = health:peek() }
			end,
			heal = function()
				health:set(1)
				return { fraction = 1 }
			end,
			tickRound = function()
				seconds:set(math.max(0, seconds:peek() - 10))
				roundLeft:set(math.max(0, roundLeft:peek() - 0.05))
				return { fraction = roundLeft:peek() }
			end,
			openUrlBar = function()
				urlBar:set(true)
			end,
			closeUrlBar = function()
				urlBar:set(false)
			end,
			rideStrip = function(on)
				ride:set(on ~= false)
			end,
			openOverflow = function()
				overflow:set(true)
				return { open = true }
			end,
			closeOverflow = function()
				overflow:set(false)
			end,
			notify = function()
				showNotice("Supplies delivered")
			end,
			clearNotice = function()
				notice:set(nil)
			end,
			advanceTask = function(index, value)
				tasks[index]:set(math.clamp(value, 0, 1))
			end,
		}
		local function timerText(style: string, use: Use)
			local value = use(seconds)
			if style == "short" then
				return tostring(math.floor(value / 60)) .. "m"
			end
			return string.format("%d:%02d", math.floor(value / 60), value % 60)
		end
		local function bar(name: string, value: Readable<number>, width: number, segments: number?): Frame
			return UI.ProgressView({
				Name = name,
				value = value,
				segments = segments,
				trail = if segments then { delay = 0.2, duration = 0.3 } else nil,
				Size = D2.fromOffset(width, 8),
			})
		end
		local function taskRow(index: number)
			local mark = Host.Frame({
				Name = "Mark" .. index,
				Size = D2.fromOffset(8, 8),
				Host.UICorner({ CornerRadius = D.new(1, 0) }),
			})
			mark:AddTag("facet-accent")
			return row("TaskRow" .. index, {
				mark,
				text("TaskName" .. index, copy["task" .. index]),
				bar("Task" .. index, tasks[index], 72),
				UI.Badge({ Name = "Reward" .. index, label = copy["reward" .. index] }),
			})
		end
		local rich = {}
		rich.Strip = function()
			return pill("Objective", copy.objective)
		end
		rich.Tasks = function()
			return plate(
				"TasksFull",
				"panel",
				row(
					"TasksBody",
					{ text("TasksTitle", copy.tasksTitle, "label"), taskRow(1), taskRow(2), taskRow(3) },
					6,
					true
				),
				12,
				10
			)
		end
		rich.Clock = function()
			local ring = UI.ProgressView({
				Name = "TimerRing",
				value = roundLeft,
				presentation = "circular" :: "circular",
				diameter = 28,
				Size = D2.fromOffset(28, 28),
			})
			return row("ClockFull", {
				pill("ScoreHome", copy.scoreHome, "numeral"),
				plate(
					"TimerPod",
					"control",
					row("TimerRow", {
						ring,
						text("TimerText", function(use: Use)
							return timerText("full", use)
						end, "numeral"),
					}, 8),
					12,
					4
				),
				pill("ScoreAway", copy.scoreAway, "numeral"),
			})
		end
		rich.Rail = function()
			local rows: { GuiObject } = {}
			for index = 1, 3 do
				table.insert(
					rows,
					row("WeaponRow" .. index, {
						UI.Button({
							Name = "Weapon" .. index,
							label = copy["weapon" .. index],
							controlSize = "compact" :: "compact",

							selected = function(use: Use)
								return use(selectedWeapon) == index
							end,
							onActivate = function()
								selectedWeapon:set(index)
							end,
						}),
						UI.Badge({ Name = "Ammo" .. index, label = copy["ammo" .. index] }),
					})
				)
			end
			return row("RailFull", rows, 4, true, E.HorizontalAlignment.Right)
		end
		rich.Health = function()
			return plate(
				"HealthPod",
				"control",
				row("HealthRow", {
					text("HealthNum", function(use: Use)
						return tostring(math.floor(use(health) * 100 + 0.5))
					end, "numeral"),
					bar("HealthBar", health, 96, 4),
				}, 8),
				12,
				4
			)
		end
		rich.Actions = function()
			local node = UI.AdaptiveStack({
				Name = "ActionsFull",
				axis = function(use: Use): "x" | "y"
					return if use(short) then "x" else "y"
				end,
				gap = "s",
				width = "hug" :: "hug",
				disc("Shop", copy.action1, "more", function()
					showNotice("Shop opened")
				end) :: unknown,
				disc("Squad", copy.action2, "menu", function()
					showNotice("Squad ready")
				end),
				disc("ActionMenu", copy.action3, "checkmark", steps.openOverflow),
			})
			return node
		end
		rich.Feed = function()
			return text("FeedText", copy.feed)
		end
		rich.Readout = function()
			return text("ReadoutText", copy.readout)
		end
		rich.Weapon = function()
			return text("WeaponText", copy.weaponName)
		end
		local menuItems: { typeof(require("@repo/tools/typecheck/example_shapes").MenuItem_any(nil :: any)) } = {
			{
				id = "damage",
				label = "Take damage",
				onSelect = function()
					steps.takeDamage()
				end,
			},
			{
				id = "heal",
				label = "Restore health",
				onSelect = function()
					steps.heal()
				end,
			},
			{
				id = "tick",
				label = "Advance clock",
				onSelect = function()
					steps.tickRound()
				end,
			},
			{
				id = "notice",
				label = "Show notification",
				onSelect = function()
					steps.notify()
				end,
			},
		}
		local function rounds(suffix: string, vertical: boolean)
			return row(if vertical then "RoundsColumn" else "RoundsRow", {
				UI.Menu({
					trigger = disc("HudActions" .. suffix .. "Trigger", copy.round1, "menu") :: GuiObject,
					items = menuItems,
				}),
				disc("Report" .. suffix, copy.round2, "flag", function()
					reportOpen:set(true)
				end),
			}, 8, vertical)
		end
		local function region(id, zone, rank, mayDrop, ...)
			return UI.Region({
				Name = id,
				zone = zone,
				rank = rank,
				mayDrop = mayDrop,
				form = chosen[id],
				reveal = not LOSSLESS[id],
				...,
			})
		end
		return {
			screen = function()
				local composition = UI.Composition({
					Name = "HudBody",
					LayoutOrder = 3,
					Size = D2.fromScale(1, 0),
					topbar = ride,
					UI.fill() :: unknown,
					region("Strip", "topbar", 6, false, rich.Strip(), pill("ObjectiveShort", copy.objectiveShort)),
					region("Rounds", "topLeft", 1, false, rounds("", false), rounds("Column", true)),
					region(
						"Tasks",
						"left",
						7,
						true,
						rich.Tasks(),
						plate(
							"TasksOne",
							"panel",
							row("TasksOneBody", { text("TasksOneName", copy.task1), bar("TasksOneBar", tasks[1], 72) }),
							10,
							6
						),
						pill("TasksCompact", copy.tasksChip, "label")
					),
					region(
						"Health",
						"bottomLeft",
						5,
						true,
						rich.Health(),
						pill("HealthCompact", function(use: Use)
							return tostring(math.floor(use(health) * 100 + 0.5))
						end, "numeral")
					),
					region("Feed", "bottomLeft", 8, true, rich.Feed()),
					region(
						"Clock",
						"top",
						2,
						false,
						rich.Clock(),
						pill("ClockCompact", function(use: Use)
							return timerText("full", use)
						end, "numeral"),
						pill("ClockShort", function(use: Use)
							return timerText("short", use)
						end, "numeral")
					),
					region(
						"Rail",
						"topRight",
						4,
						true,
						rich.Rail(),
						pill("RailCompact", function(use: Use)
							return copy["weapon" .. use(selectedWeapon)]
						end)
					),
					region("Readout", "topRight", 9, true, rich.Readout()),
					region(
						"Actions",
						"bottomRight",
						3,
						false,
						rich.Actions(),
						disc("ActionsCompact", copy.action3, "more", steps.openOverflow)
					),
					region("Weapon", "bottomRight", 6, true, rich.Weapon()),
				})
				return Host.Frame({
					Name = "HudScreen",
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Host.UIListLayout({ Padding = D.new(0, 4), SortOrder = E.SortOrder.LayoutOrder }) :: unknown,
					Host.Frame({
						Name = "BrowserChrome",
						LayoutOrder = 1,
						Visible = urlBar,
						Size = D2.new(1, 0, 0, 64),
						Host.UIPadding({ PaddingLeft = D.new(0, 16), PaddingTop = D.new(0, 12) }) :: unknown,
						text("Address", copy.urlBarField, "body"),
					}),
					Host.Frame({
						Name = "Notice",
						LayoutOrder = 2,
						Visible = function(use: Use)
							return use(notice) ~= nil
						end,
						Size = D2.new(1, 0, 0, 40),
						BackgroundTransparency = 1,
						UI.Button({
							label = function(use: Use)
								return use(notice) or ""
							end,
							onActivate = steps.clearNotice,
							Size = D2.fromScale(1, 1),
						}),
					}),
					composition,
					Host.Frame({
						Name = "Drivers",
						LayoutOrder = 4,
						BackgroundTransparency = 1,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						Host.UIPadding({
							PaddingLeft = D.new(0, 8),
							PaddingRight = D.new(0, 8),
							PaddingBottom = D.new(0, 4),
						}) :: unknown,
						Host.UIListLayout({
							FillDirection = E.FillDirection.Horizontal,
							Wraps = true,
							VerticalAlignment = E.VerticalAlignment.Center,
							Padding = D.new(0, 16),
							SortOrder = E.SortOrder.LayoutOrder,
						}),
						UI.Toggle({ Name = "UrlBar", LayoutOrder = 1, label = copy.urlBarOn, value = urlBar }),
						UI.Toggle({ Name = "RideStrip", LayoutOrder = 2, label = copy.rideOn, value = ride }),
						UI.Text({
							Name = "Ladder",
							LayoutOrder = 3,
							text = copy.ladder,
							textRole = "caption" :: "caption",
							TextWrapped = true,
							Size = D2.new(0, 280, 0, 0),
							AutomaticSize = E.AutomaticSize.Y,
							Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
						}),
					}),
					UI.Sheet({
						Name = "HudOverflow",
						isPresented = overflow,
						detent = Compose.cell("large"),
						title = copy.overflowTitle,
						content = function(): Instance
							return Host.ScrollingFrame({
								Name = "OverflowBody",
								BackgroundTransparency = 1,
								Size = D2.fromScale(1, 1),
								CanvasSize = D2.fromOffset(0, 0),
								AutomaticCanvasSize = E.AutomaticSize.Y,
								ScrollBarThickness = 6,
								Host.UIListLayout({ Padding = D.new(0, 16), SortOrder = E.SortOrder.LayoutOrder }) :: unknown,
								text("OverflowNote", copy.overflowNote),
								Compose.show(function(use: Use)
									return #use(unshown) == 0
								end, function()
									return text("OverflowEmpty", copy.overflowEmpty)
								end),
								Compose.keyed({
									from = unshown,
									render = function(current, index): GuiObject
										return Host.Frame({
											Name = "Rich" .. current:peek(),
											LayoutOrder = index,
											BackgroundTransparency = 1,
											Size = D2.new(),
											AutomaticSize = E.AutomaticSize.XY,
											rich[current:peek()](),
										})
									end,
								}),
							})
						end,
					}),
					UI.Alert({
						Name = "ReportDialog",
						isPresented = reportOpen,
						title = "Round report",
						message = "Your report was recorded.",
						actions = {
							{ id = "close", label = "Done", role = "cancel" :: "cancel" } :: typeof(require("@repo/tools/typecheck/example_shapes").AlertAction_any(nil :: any)),
						},
					}),
				})
			end,
			steps = steps,
			model = {
				health = health,
				roundLeft = roundLeft,
				seconds = seconds,
				tasks = tasks,
				urlBar = urlBar,
				ride = ride,
				overflow = overflow,
				selectedWeapon = selectedWeapon,
				forms = chosen,
			},
			report = function()
				return {
					health = health:peek(),
					roundLeft = roundLeft:peek(),
					seconds = seconds:peek(),
					forms = forms:peek(),
					unshown = unshown:peek(),
					overflowOpen = overflow:peek(),
					urlBar = urlBar:peek(),
					ride = ride:peek(),
					notice = notice:peek(),
				}
			end,
		}
	end,
}
