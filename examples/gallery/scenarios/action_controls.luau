--!strict
return {
	title = "Actions and menus",
	ledgerRows = { "CONTROL-ACTIONS" },
	build = function(ctx)
		local Facet, core = ctx.Facet, ctx.core
		local UI = Facet.UI
		local scope = core:scope("action-controls")
		local function signal(v)
			return scope:own(core:signal(v))
		end
		local function own(v)
			return scope:own(v)
		end
		local conditions = Facet.adaptive.conditions(core, ctx.env, { scope = scope })
		local busy = signal(false)
		local enabled = signal(true)
		local count = signal(0)
		local status = signal("Ready to race.")
		local favorites = signal(false)
		local weather = signal("any")
		local scrollTarget = signal(nil)
		local scrollProgress = signal(0)
		local heroVisible = signal(true)
		local rowVolume = signal(60)
		local assist = signal(true)
		local rowToggle = own(Facet.Controls.Toggle(core, {
			id = "Assist",
			label = "Driving assistance",
			value = assist,
			row = { description = "Keep the car stable on rough terrain", icon = "settings" },
		}))
		local rowSlider = own(Facet.Controls.Slider(core, {
			id = "Music",
			label = "Music volume",
			value = rowVolume,
			min = 0,
			max = 100,
			step = 5,
			row = { description = "Balance music against race sounds", icon = "settings" },
		}))
		local rowAction = own(Facet.Controls.Button(core, {
			id = "Equipment",
			label = "Manage equipment",
			row = { description = "Choose a driver for the next race", value = "2 drivers", icon = "search" },
			onActivate = function()
				scrollTarget:set(nil)
				scrollTarget:set("Drivers")
			end,
		}))
		local seconds = 0
		local save = own(Facet.Controls.Button(core, {
			id = "Save",
			label = "Prepare race",
			busy = busy,
			enabled = enabled,
			onActivate = function()
				busy:set(true)
				seconds = 1.5
				status:set("Preparing your race…")
			end,
		}))
		if ctx.presenter then
			scope:own(ctx.presenter.onTick(function(dt)
				if busy:get() then
					seconds -= dt
					if seconds <= 0 then
						busy:set(false)
						status:set("Your race is ready.")
					end
				end
			end))
		end
		local repeatButton = own(Facet.Controls.Button(core, {
			id = "Repeat",
			label = "Add a lap · hold to repeat",
			enabled = enabled,
			repeatDelay = 0.4,
			repeatInterval = 0.1,
			onActivate = function()
				count:set(count:get() + 1)
			end,
		}))
		local shortcut = own(Facet.Controls.Button(core, {
			id = "Shortcut",
			label = "Restart count · F6",
			shortcut = { keyCode = "F6" },
			enabled = enabled,
			onActivate = function()
				count:set(0)
				status:set("Lap count restarted.")
			end,
		}))
		local items = {
			{ id = "favorites", label = "Favorites only", checked = favorites },
			{ divider = true },
			{ id = "any", label = "Any weather", selected = weather, value = "any" },
			{ id = "dry", label = "Dry weather", selected = weather, value = "dry" },
			{
				id = "snow",
				label = "Snow",
				selected = weather,
				value = "snow",
				enabled = false,
				description = "Winter races are closed.",
			},
			{ divider = true },
			{
				id = "done",
				label = "Apply filters",
				onSelect = function()
					status:set("Filters applied.")
				end,
			},
		}
		local menu = own(Facet.Controls.Menu(core, {
			id = "Filters",
			trigger = UI.Button({ id = "Filters", label = "Race filters", enabled = enabled }),
			items = items,
		}))
		local split = own(Facet.Controls.SplitButton(core, {
			id = "Split",
			label = "Start race",
			enabled = enabled,
			onActivate = function()
				status:set("Race started.")
			end,
			items = {
				{
					id = "practice",
					label = "Practice",
					onSelect = function()
						status:set("Practice started.")
					end,
				},
				{
					id = "time",
					label = "Time trial",
					onSelect = function()
						status:set("Time trial started.")
					end,
				},
			},
		}))
		local dialog = own(Facet.Controls.Alert(core, {
			id = "RaceConfirmation",
			title = "Start this race?",
			message = "Your selected driver is ready.",
			actions = {
				{
					id = "Cancel",
					label = "Cancel",
					role = "cancel",
					onActivate = function()
						status:set("Race cancelled.")
					end,
				},
				{
					id = "Accept",
					label = "Start",
					role = "default",
					onActivate = function()
						status:set("Race confirmed.")
					end,
				},
			},
		}))
		local dismiss = dialog.dismiss
		local function openDialog()
			if ctx.presenter then
				dialog.present(ctx.presenter)
			end
		end

		local function reset()
			busy:set(false)
			enabled:set(true)
			count:set(0)
			favorites:set(false)
			weather:set("any")
			status:set("Ready to race.")
			dismiss()
		end
		local function heading(text)
			return UI.Text({ text = text, textSize = "heading", width = UI.fill() })
		end

		local drivers = {}
		for i, name in { "Classic driver", "Trailblazer" } do
			local card = own(Facet.Controls.Button(core, {
				id = "Driver" .. i,
				label = name,
				subtitle = "Choose for the next race",
				image = `rbxthumb://type=AvatarHeadShot&id={i}&w=420&h=420`,
				imageAspectRatio = 1,
				imageFraming = { width = 420, height = 420, focusY = 0.25 },
				enabled = enabled,
				onActivate = function()
					status:set(name .. " selected.")
				end,
			}))
			table.insert(drivers, card.blueprint)
		end
		local driverGrid = UI.focusSection(
			UI.Grid({ id = "Drivers", minColumnWidth = 180, gap = "m", width = UI.fill(), children = drivers }),
			{ entry = "restore", preferred = "Driver1" }
		)

		local previews = {}
		for _, mode in { "crop", "none" } do
			table.insert(
				previews,
				UI.VStack({
					id = "Backdrop" .. mode,
					width = UI.fill(),
					gap = "s",
					padding = "m",
					surface = "raised",
					children = {
						UI.background(
							UI.Box({ id = "Preview", width = UI.fill(), height = { type = "fixed", px = 180 } }),
							UI.Image({
								id = "Artwork",
								image = "rbxthumb://type=AvatarHeadShot&id=1&w=420&h=420",
								imageFraming = { width = 420, height = 420, mode = mode, focusX = 0.5, focusY = 0.25 },
							})
						),
						UI.Text({
							text = if mode == "crop"
								then "Focal crop · keeps the face in view"
								else "Natural pixels · crop as the view shrinks",
							width = UI.fill(),
						}),
					},
				})
			)
		end

		local hero = UI.background(
			UI.focusSection(
				UI.VStack({
					id = "Hero",
					width = UI.fill(),
					height = { type = "minMax", min = 240 },
					padding = "m",
					gap = "m",
					children = {
						UI.Text({
							id = "HeroTitle",
							text = "Your next race starts here",
							textSize = "title",
							width = UI.fill(),
						}),
						UI.Text({
							text = "Choose your driver. Tune your ride. Find your next challenge.",
							textSize = "body",
							width = UI.fill(),
						}),
						UI.Button({
							id = "ChooseDriver",
							label = "Choose a driver",
							onActivate = function()
								scrollTarget:set(nil)
								scrollTarget:set("Drivers")
							end,
						}),
					},
				}),
				{ preferred = "ChooseDriver" }
			),
			UI.ZStack({
				id = "HeroScene",
				clipChildren = true,
				children = {
					UI.Image({
						id = "HeroArt",
						width = UI.fill(),
						height = UI.fill(),
						image = "rbxthumb://type=AvatarHeadShot&id=1&w=420&h=420",
						imageFraming = own(core:memo(function(use)
							local reduced = ctx.env and use(ctx.env:get("motionPolicy")) == "reduced"
							return {
								width = 420,
								height = 420,
								focusY = 0.25,
								scale = if reduced then 1 else 1.04 - 0.04 * use(scrollProgress),
							}
						end)),
					}),
					UI.gradient(
						UI.Box({ id = "Readability", surface = "base", width = UI.fill(), height = UI.fill() }),
						{ colors = { "surface", "surfaceStrong" }, rotation = 90, transparency = { 0.55, 0.08 } }
					),
				},
			})
		)

		local showroom = UI.VStack({
			id = "Showroom",
			width = UI.fill(),
			gap = "m",
			children = {
				hero,
				heading("Choose your driver"),
				driverGrid,
				heading("Image backgrounds"),
				UI.Grid({ id = "Backgrounds", minColumnWidth = 240, width = UI.fill(), gap = "m", children = previews }),
			},
		})
		local raceSetup = UI.VStack({
			id = "RaceSetup",
			width = UI.fill(),
			gap = "m",
			children = {
				UI.focusSection(UI.VStack({
					id = "SettingsRows",
					width = UI.fill(),
					gap = "m",
					children = { rowAction.blueprint, rowToggle.blueprint, rowSlider.blueprint },
				})),
				heading("Prepare a race"),
				save.blueprint,
				UI.Text({ id = "Status", text = status, width = UI.fill() }),
				heading("Set the lap count"),
				repeatButton.blueprint,
				UI.Text({
					id = "Count",
					text = scope:own(core:memo(function(use)
						return tostring(use(count)) .. " laps"
					end)),
				}),
				shortcut.blueprint,
				heading("Filter the grid"),
				menu.blueprint,
				UI.Text({
					text = scope:own(core:memo(function(use)
						return (if use(favorites) then "Favorites" else "All races")
							.. " · "
							.. use(weather)
							.. " weather"
					end)),
					width = UI.fill(),
				}),
				heading("Start or choose a mode"),
				UI.Text({
					id = "CapSplit",
					text = "Split button · one control: the action, and its menu (pointer: split; touch: long-press, with a chevron)",
					textSize = "caption",
					role = "secondary",
					width = UI.fill(),
				}),
				split.blueprint,
				UI.Button({ id = "Confirm", label = "Confirm race…", enabled = enabled, onActivate = openDialog }),
			},
		})
		local body = UI.AdaptiveStack({
			id = "Sections",
			width = UI.fill(),
			gap = "l",
			align = "start",
			axis = own(core:memo(function(use)
				return if use(conditions.isWide) then "x" else "y"
			end)),
			children = { showroom, raceSetup },
		})
		local page = UI.VStack({
			width = UI.fill(),
			gap = "m",
			children = {
				UI.Text({ text = "Actions and menus", textSize = "title", width = UI.fill() }),
				UI.Button({ id = "Reset", label = "Reset", onActivate = reset }),
				UI.Button({
					id = "Enable",
					label = "Toggle enabled",
					onActivate = function()
						enabled:set(not enabled:get())
					end,
				}),
				body,
			},
		})
		local scroller = UI.ScrollView({
			id = "Content",
			width = UI.fill(),
			height = UI.fill(),
			navigation = {
				focus = "target",
				targets = { "Hero", "SettingsRows", "Drivers" },
				target = scrollTarget,
				progress = scrollProgress,
				onVisibilityChanged = function(id, visible)
					if id == "Hero" then
						heroVisible:set(visible)
					end
				end,
			},
			children = { page },
		})
		local screen = UI.Screen({ id = "ActionControls", surface = "base", padding = "m", children = { scroller } })
		return {
			screen = screen,
			states = function()
				return {
					{
						id = "stateful-menu",
						kind = "menu",
						open = function()
							return menu.api.open()
						end,
					},
					{
						id = "confirmation",
						kind = "dialog",
						open = function()
							openDialog()
							return true
						end,
					},
					{
						id = "busy",
						kind = "busy",
						open = function()
							busy:set(true)
							return true
						end,
					},
				}
			end,
			steps = {
				showDrivers = function()
					scrollTarget:set(nil)
					scrollTarget:set("Drivers")
				end,
				showHero = function()
					scrollTarget:set(nil)
					scrollTarget:set("Hero")
				end,
				showSettings = function()
					scrollTarget:set(nil)
					scrollTarget:set("SettingsRows")
				end,
				reset = reset,
				disable = function()
					enabled:set(false)
				end,
				busy = function()
					busy:set(true)
					seconds = 1.5
				end,
			},
			report = function()
				return {
					count = count:get(),
					settings = { assistance = assist:get(), music = rowVolume:get() },
					scrollProgress = scrollProgress:get(),
					heroVisible = heroVisible:get(),
					busy = busy:get(),
					status = status:get(),
					menu = menu.dump(),
					split = split.dump(),
					button = repeatButton.dump(),
				}
			end,
			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
