--!strict
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
	timerTiny = "2",
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
	healthLabel = "Health",
	action1 = "Shop",
	action2 = "Squad",
	action3 = "Menu",
	round1 = "HUD actions",
	round2 = "Report",
	round3 = "Show what's hidden",
	overflowTitle = "Hidden right now",
	overflowClose = "Close",
	overflowEmpty = "Nothing is hidden — every zone is showing everything it has.",
	overflowNote = "Every simplified zone remains available here.",
	feed = "Ravi eliminated Mo",
	urlBarOn = "URL bar",
	urlBarField = "example.com/play",
	objective = "Round 3 · Capture",
	objectiveShort = "R3",
}
return {
	title = "Screen-anchored HUD",
	copy = copy,
	build = function(ctx)
		local Host, UI, Compose = ctx.Host, ctx.UI, ctx.Compose
		local D, D2, V2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
		local health, roundLeft, seconds = Compose.cell(0.84), Compose.cell(0.62), Compose.cell(134)
		local tasks = { Compose.cell(0.2), Compose.cell(0.4), Compose.cell(0.6) }
		local urlBar, overflow, reportOpen = Compose.cell(false), Compose.cell(false), Compose.cell(false)
		local notice, selectedWeapon = Compose.cell(nil), Compose.cell(1)
		local bodySize = Compose.cell(V2.zero)
		local function read(source, use)
			return if Compose.isReadable(source) then use(source) else source
		end
		local offer = Compose.formula(function(use)
			local measured = use(bodySize)
			if measured.X > 0 and measured.Y > 0 then
				return { width = measured.X, height = measured.Y }
			end
			local viewport = ctx.viewport and read(ctx.viewport, use) or { width = 960, height = 640 }
			return {
				width = math.max(1, viewport.width - 24),
				height = math.max(1, viewport.height - 140 - (if use(urlBar) then 64 else 0)),
			}
		end)
		local forms = Compose.formula(function(use)
			local area = use(offer)
			local width, height = (area.width - 24) / 3, area.height
			return {
				Tasks = if height >= 420 and width >= 200 then "full" elseif height >= 240 then "compact" else "hidden",
				Clock = if width >= 160 and height >= 260 then "full" elseif width >= 100 then "compact" else "tiny",
				Rail = if width >= 140 and height >= 320 then "full" else "compact",
				Health = if width >= 140 and height >= 240 then "full" else "compact",
				Actions = if height >= 320 then "full" else "compact",
				Feed = if height >= 440 and width >= 180 then "full" else "hidden",
				Readout = if height >= 520 and width >= 160 then "full" else "hidden",
				Weapon = if height >= 400 and width >= 160 then "full" else "hidden",
			}
		end)
		local order = { "Tasks", "Clock", "Rail", "Health", "Actions", "Feed", "Readout", "Weapon" }
		local unshown = Compose.formula(function(use)
			local current, result = use(forms), {}
			for _, id in order do
				if current[id] ~= "full" then
					table.insert(result, id)
				end
			end
			return result
		end)
		local function text(name, label, size)
			return UI.Text({
				Name = name,
				text = label,
				TextSize = size or 15,
				TextWrapped = true,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			})
		end
		local function stack(name, children, horizontal)
			local properties = {
				Name = name,
				BackgroundTransparency = 1,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = if horizontal then E.FillDirection.Horizontal else E.FillDirection.Vertical,
					Wraps = horizontal == true,
					Padding = D.new(0, 8),
					SortOrder = E.SortOrder.LayoutOrder,
				}),
			}
			for index, child in children do
				child.LayoutOrder = index
				table.insert(properties, child)
			end
			return Host.Frame(properties)
		end
		local function action(name, label, callback, icon)
			return UI.Button({
				Name = name,
				label = label,
				icon = icon,
				Size = D2.new(1, 0, 0, 44),
				onActivate = callback,
			})
		end
		local function showNotice(message)
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
		local function timerText(style, use)
			local value = use(seconds)
			if style == "full" then
				return string.format("%d:%02d", math.floor(value / 60), value % 60)
			end
			return tostring(math.floor(value / 60)) .. (if style == "compact" then "m" else "")
		end
		local function taskRow(index)
			return stack("TaskRow" .. index, {
				text("TaskName" .. index, copy["task" .. index]),
				UI.ProgressView({ Name = "Task" .. index, value = tasks[index], Size = D2.new(1, 0, 0, 14) }),
				UI.Badge({ Name = "Reward" .. index, label = copy["reward" .. index] }),
			})
		end
		local rich = {}
		rich.Tasks = function()
			return stack("TasksFull", { text("TasksTitle", copy.tasksTitle, 18), taskRow(1), taskRow(2), taskRow(3) })
		end
		rich.Clock = function()
			return stack("ClockFull", {
				UI.ProgressView "TimerRing" {
					value = roundLeft,
					presentation = "circular",
					diameter = 72,
					Size = D2.fromOffset(72, 72),
				},
				text("TimerText", function(use)
					return timerText("full", use)
				end, 26),
				text("TeamScores", copy.scoreHome .. "  —  " .. copy.scoreAway, 22),
			})
		end
		rich.Rail = function()
			local children = {}
			for index = 1, 3 do
				table.insert(
					children,
					UI.Button({
						Name = "Weapon" .. index,
						label = copy["weapon" .. index],
						subtitle = copy["ammo" .. index],
						selected = function(use)
							return use(selectedWeapon) == index
						end,
						Size = D2.new(1, 0, 0, 64),
						onActivate = function()
							selectedWeapon:set(index)
						end,
					})
				)
			end
			return stack("RailFull", children)
		end
		rich.Health = function()
			return stack("HealthFull", {
				text("HealthLabel", copy.healthLabel),
				UI.ProgressView "HealthBar" {
					value = health,
					segments = 4,
					trail = { delay = 0.2, duration = 0.3 },
					Size = D2.new(1, 0, 0, 14),
				},
				text("HealthNum", function(use)
					return tostring(math.floor(use(health) * 100 + 0.5))
				end, 22),
			})
		end
		rich.Actions = function()
			return stack("ActionsFull", {
				action("Shop", copy.action1, function()
					showNotice("Shop opened")
				end, "more"),
				action("Squad", copy.action2, function()
					showNotice("Squad ready")
				end, "more"),
				action("ActionMenu", copy.action3, steps.openOverflow, "menu"),
			})
		end
		rich.Feed = function()
			return text("FeedText", copy.feed)
		end
		rich.Readout = function()
			return text("ReadoutText", copy.readout, 12)
		end
		rich.Weapon = function()
			return text("WeaponText", copy.weaponName, 16)
		end
		local function chip(name, icon, label)
			return UI.Button({
				Name = name,
				icon = icon,
				label = label,
				appearance = "soft",
				onActivate = steps.openOverflow,
			})
		end
		local function compact(id)
			if id == "Clock" then
				return chip("ClockCompact", "clock", function(use)
					return timerText(use(forms).Clock, use)
				end)
			elseif id == "Health" then
				return chip("HealthCompact", "person", function(use)
					return `{copy.healthLabel} {math.floor(use(health) * 100 + 0.5)}`
				end)
			elseif id == "Rail" then
				return chip("RailCompact", "flag", function(use)
					return copy["weapon" .. use(selectedWeapon)]
				end)
			elseif id == "Tasks" then
				return chip("TasksCompact", "checkmark", copy.tasksChip)
			end
			return chip(id .. "Compact", "more", id)
		end
		local function region(id)
			return Host.Frame({
				Name = id,
				BackgroundTransparency = 1,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				Compose.switch(function(use)
					return use(forms)[id]
				end, {
					full = rich[id],
					compact = function()
						return compact(id)
					end,
					tiny = function()
						return compact(id)
					end,
					hidden = function()
						return Host.Frame({ Size = D2.fromOffset(0, 0), BackgroundTransparency = 1 })
					end,
				}),
			})
		end
		local function lane(name, ids)
			local children = {}
			for _, id in ids do
				table.insert(children, region(id))
			end
			return Host.ScrollingFrame({
				Name = name,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = D2.fromOffset(0, 0),
				AutomaticCanvasSize = E.AutomaticSize.Y,
				ScrollBarThickness = 3,
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
				stack("Content", children),
			})
		end
		return {
			screen = function()
				local body = Host.Frame "HudBody" {
					LayoutOrder = 5,
					BackgroundTransparency = 1,
					Size = D2.new(1, 0, 0, 0),
					Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
					Host.UIGridLayout({
						FillDirectionMaxCells = 3,
						CellSize = D2.new(1 / 3, -8, 1, 0),
						CellPadding = D2.fromOffset(12, 0),
						SortOrder = E.SortOrder.LayoutOrder,
					}),
					lane("Left", { "Tasks", "Health", "Feed" }),
					lane("Center", { "Clock" }),
					lane("Right", { "Rail", "Readout", "Weapon", "Actions" }),
				}
				local connection = body:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					bodySize:set(body.AbsoluteSize)
				end)
				Compose.cleanup(function()
					connection:Disconnect()
				end)
				bodySize:set(body.AbsoluteSize)
				return Host.Frame "HudScreen" {
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Host.UIPadding({
						PaddingTop = D.new(0, 12),
						PaddingBottom = D.new(0, 12),
						PaddingLeft = D.new(0, 12),
						PaddingRight = D.new(0, 12),
					}),
					Host.UIListLayout({ Padding = D.new(0, 8), SortOrder = E.SortOrder.LayoutOrder }),
					Host.Frame "BrowserChrome" {
						LayoutOrder = 1,
						Visible = urlBar,
						Size = D2.new(1, 0, 0, 64),
						text("Address", copy.urlBarField, 16),
					},
					Host.Frame "Rounds" {
						LayoutOrder = 2,
						Size = D2.new(1, 0, 0, 48),
						BackgroundTransparency = 1,
						Host.UIListLayout({
							FillDirection = E.FillDirection.Horizontal,
							Padding = D.new(0, 8),
							SortOrder = E.SortOrder.LayoutOrder,
						}),
						UI.Menu "HudActions" {
							trigger = UI.Button "HudActionsTrigger" {
								label = "",
								name = copy.round1,
								icon = "menu",
								shape = "circle",
								Size = D2.fromOffset(44, 44),
							},
							AutomaticSize = E.AutomaticSize.None,
							Size = D2.fromOffset(44, 44),
							items = {
								{ id = "damage", label = "Take damage", onSelect = steps.takeDamage },
								{ id = "heal", label = "Restore health", onSelect = steps.heal },
								{ id = "notice", label = "Show notification", onSelect = steps.notify },
							},
						},
						UI.Button "Report" {
							label = "",
							name = copy.round2,
							icon = "flag",
							shape = "circle",
							Size = D2.fromOffset(44, 44),
							onActivate = function()
								reportOpen:set(true)
							end,
						},
						UI.Button "Overflow" {
							label = "",
							name = copy.round3,
							icon = "more",
							shape = "circle",
							Size = D2.fromOffset(44, 44),
							onActivate = steps.openOverflow,
						},
						UI.Text "Objective" {
							text = function(use)
								return if use(offer).width < 360 then copy.objectiveShort else copy.objective
							end,
							TextWrapped = true,
							Size = D2.new(1, -156, 1, 0),
						},
					},
					Host.Frame "ChromeControls" {
						LayoutOrder = 3,
						BackgroundTransparency = 1,
						Size = D2.new(1, 0, 0, 40),
						Host.UIListLayout({ FillDirection = E.FillDirection.Horizontal, Padding = D.new(0, 8) }),
						UI.Toggle "UrlBar" {
							label = copy.urlBarOn,
							value = urlBar,
							Size = D2.new(0.5, -4, 1, 0),
						},
						UI.Button "Tick" {
							label = "Advance clock",
							onActivate = steps.tickRound,
							Size = D2.new(0.5, -4, 1, 0),
						},
					},
					Host.Frame "Notice" {
						LayoutOrder = 4,
						Visible = function(use)
							return use(notice) ~= nil
						end,
						Size = D2.new(1, 0, 0, 40),
						UI.Button({
							label = function(use)
								return use(notice) or ""
							end,
							onActivate = steps.clearNotice,
							Size = D2.fromScale(1, 1),
						}),
					},
					body,
					UI.Sheet "HudOverflow" {
						isPresented = overflow,
						detent = Compose.cell("large"),
						title = copy.overflowTitle,
						content = function()
							return Host.ScrollingFrame "OverflowBody" {
								BackgroundTransparency = 1,
								Size = D2.fromScale(1, 1),
								CanvasSize = D2.fromOffset(0, 0),
								AutomaticCanvasSize = E.AutomaticSize.Y,
								ScrollBarThickness = 6,
								Host.UIListLayout({ Padding = D.new(0, 16), SortOrder = E.SortOrder.LayoutOrder }),
								text("OverflowNote", copy.overflowNote),
								Compose.show(function(use)
									return #use(unshown) == 0
								end, function()
									return text("OverflowEmpty", copy.overflowEmpty)
								end),
								Compose.keyed({
									from = unshown,
									render = function(current, index)
										local node = rich[current:peek()]()
										ctx.runtime.decorate(node, { LayoutOrder = index })
										return node
									end,
								}),
							}
						end,
					},
					UI.Alert "ReportDialog" {
						isPresented = reportOpen,
						title = "Round report",
						message = "Your report was recorded.",
						actions = { { id = "close", label = "Done", role = "cancel" } },
					},
				}
			end,
			steps = steps,
			model = {
				health = health,
				roundLeft = roundLeft,
				seconds = seconds,
				tasks = tasks,
				urlBar = urlBar,
				overflow = overflow,
				selectedWeapon = selectedWeapon,
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
					notice = notice:peek(),
				}
			end,
		}
	end,
}
