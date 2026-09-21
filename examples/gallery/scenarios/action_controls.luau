--!strict
return {
	title = "Actions and menus",
	ledgerRows = { "CONTROL-ACTIONS" },
	build = function(ctx)
		local Facet = ctx.Facet
		local UI, Compose = ctx.UI, ctx.Compose
		local hintRecipe = require("./shortcut_hint").build(ctx)
		local signal = Compose.cell
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
		local confirming = signal(false)
		local seconds = 0
		local readRung = function(): string?
			return nil
		end
		local setRung = function(_rung: string) end
		local function VocabularySection()
			local rung = Compose.cell("compact")
			readRung = function()
				return rung:peek()
			end
			setRung = function(value)
				rung:set(value)
			end
			Compose.cleanup(function()
				readRung = function()
					return nil
				end
				setRung = function(_value) end
			end)
			local ladder, looks, chips = {}, {}, {}
			for _, step in { "compact", "regular", "large" } do
				table.insert(
					ladder,
					UI.Button("Rung" .. step:sub(1, 1):upper() .. step:sub(2))({
						label = step,
						controlSize = step,
						appearance = if step == "large" then "emphasis" else "standard",
						enabled = enabled,
						onActivate = function()
							rung:set(step)
							status:set(step .. " size chosen.")
						end,
					})
				)
			end
			for _, word in { "standard", "emphasis", "soft", "utility", "link" } do
				table.insert(
					looks,
					UI.Button("Look" .. word:sub(1, 1):upper() .. word:sub(2))({
						label = word,
						appearance = word,
						controlSize = function(use)
							return use(rung)
						end,
						enabled = enabled,
						onActivate = function()
							status:set(word .. " emphasis chosen.")
						end,
					})
				)
			end
			for _, entry in { { "Dry", "compact" }, { "Wet", "regular" }, { "Snow", "large" } } do
				table.insert(
					chips,
					UI.Chip("Chip" .. entry[1])({
						label = entry[1],
						selected = Compose.cell(entry[1] == "Dry"),
						controlSize = entry[2],
						appearance = if entry[1] == "Snow" then "utility" else "standard",
					})
				)
			end
			return UI.VStack("Vocabulary")({
				width = UI.fill(),
				gap = "m",
				UI.Text("CapVocabulary")({
					text = function(use)
						return `The appearance row uses the {use(rung)} size. Compact plates keep full-size tap targets.`
					end,
					textSize = "caption",
					role = "secondary",
					width = UI.fill(),
				}),
				UI.HStack("SizeLadder")({ gap = "s", wrap = true, width = UI.fill(), table.unpack(ladder) }),
				UI.HStack("Appearances")({ gap = "s", wrap = true, width = UI.fill(), table.unpack(looks) }),
				UI.HStack("SizedChips")({ gap = "s", wrap = true, width = UI.fill(), table.unpack(chips) }),
				UI.Button("IconLabelled")({
					label = "Go",
					icon = "facet:search",
					width = UI.fill(),
					controlSize = rung,
					enabled = enabled,
					onActivate = function()
						status:set("Race search opened.")
					end,
				}),
				UI.HStack("IconForms")({
					gap = "s",
					wrap = true,
					width = UI.fill(),
					UI.Button("IconOnly")({
						icon = "close",
						name = "Dismiss the race card",
						corners = "pill",
						controlSize = rung,
						enabled = enabled,
						onActivate = function()
							status:set("Race card dismissed.")
						end,
					}),
					UI.Button("SquareAction")({
						label = "Square",
						corners = "square",
						controlSize = rung,
						appearance = "utility",
						enabled = enabled,
						onActivate = function()
							status:set("Square action chosen.")
						end,
					}),
				}),
				UI.background(
					UI.VStack("OverMedia")({
						width = UI.fill(),
						height = { type = "minMax", min = 96 },
						padding = "m",
						align = "center",
						UI.Button("OverMediaAction")({
							label = "Play this replay",
							over = "media",
							controlSize = "large",
							enabled = enabled,
							onActivate = function()
								status:set("Replay opened.")
							end,
						}),
					}),
					UI.Image("OverMediaArt")({
						width = UI.fill(),
						height = UI.fill(),
						image = "rbxthumb://type=AvatarHeadShot&id=1&w=420&h=420",
						scaleMode = "crop",
					})
				),
			})
		end

		local function openDialog()
			confirming:set(true)
		end
		local function reset()
			setRung("compact")
			busy:set(false)
			enabled:set(true)
			count:set(0)
			favorites:set(false)
			weather:set("any")
			status:set("Ready to race.")
			confirming:set(false)
		end

		local function Example()
			local conditions = Facet.adaptive.conditions(ctx.env)
			local rowToggle = UI.Toggle("Assist")({
				label = "Driving assistance",
				value = assist,
				row = { description = "Keep the car stable on rough terrain", icon = "settings" },
			})
			local rowSlider = UI.Slider("Music")({
				label = "Music volume",
				value = rowVolume,
				min = 0,
				max = 100,
				step = 5,
				row = { description = "Balance music against race sounds", icon = "settings" },
			})
			local rowAction = UI.Button("Equipment")({
				label = "Manage equipment",
				row = { description = "Choose a driver for the next race", value = "2 drivers", icon = "search" },
				onActivate = function()
					scrollTarget:set(nil)
					scrollTarget:set("Drivers")
				end,
			})
			local save = UI.Button("Save")({
				label = "Prepare race",
				busy = busy,
				enabled = enabled,
				onActivate = function()
					busy:set(true)
					seconds = 1.5
					status:set("Preparing your race…")
				end,
			})
			if ctx.presenter then
				Compose.cleanup(ctx.presenter.onTick(function(dt)
					if busy:peek() then
						seconds -= dt
						if seconds <= 0 then
							busy:set(false)
							status:set("Your race is ready.")
						end
					end
				end))
			end
			local repeatButton = UI.Button("Repeat")({
				label = "Add a lap · hold to repeat",
				enabled = enabled,
				repeatDelay = 0.4,
				repeatInterval = 0.1,
				onActivate = function()
					count:set(count:peek() + 1)
				end,
			})
			local shortcut = UI.Button("Shortcut")({
				label = "Restart count · F6",
				shortcut = { keyCode = "F6" },
				enabled = enabled,
				onActivate = function()
					count:set(0)
					status:set("Lap count restarted.")
				end,
			})
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
			local menu = UI.Menu("Filters")({
				label = "Race filters",
				items = items,
			})
			local split = UI.SplitButton("Split")({
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
			})
			local dialog = UI.Alert("RaceConfirmation")({
				isPresented = confirming,
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
			})
			local function heading(text)
				return UI.Text({ text = text, textSize = "heading", width = UI.fill() })
			end

			local drivers: { [any]: any } = { minColumnWidth = 180, gap = "m", width = UI.fill() }
			for i, name in { "Classic driver", "Trailblazer" } do
				local card = UI.Button("Driver" .. i)({
					label = name,
					subtitle = "Choose for the next race",
					image = `rbxthumb://type=AvatarHeadShot&id={i}&w=420&h=420`,
					imageAspectRatio = 1,
					imageFraming = { width = 420, height = 420, focusY = 0.25 },
					enabled = enabled,
					onActivate = function()
						status:set(name .. " selected.")
					end,
				})
				table.insert(drivers, card)
			end
			local driverGrid =
				UI.focusSection(UI.Grid("Drivers")(drivers), { entry = "restore", preferred = "Driver1" })

			local previews: { [any]: any } = { minColumnWidth = 240, width = UI.fill(), gap = "m" }
			for _, mode in { "crop", "none" } do
				table.insert(
					previews,
					UI.VStack("Backdrop" .. mode)({
						width = UI.fill(),
						gap = "s",
						padding = "m",
						surface = "raised",

						UI.background(
							UI.Box("Preview")({ width = UI.fill(), height = { type = "fixed", px = 180 } }),
							UI.Image("Artwork")({
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
					})
				)
			end

			local hero = UI.background(
				UI.focusSection(
					UI.VStack("Hero")({
						width = UI.fill(),
						height = { type = "minMax", min = 240 },
						padding = "m",
						gap = "m",

						UI.Text("HeroTitle")({
							text = "Your next race starts here",
							textSize = "title",
							width = UI.fill(),
						}),
						UI.Text({
							text = "Choose your driver. Tune your ride. Find your next challenge.",
							textSize = "body",
							width = UI.fill(),
						}),
						UI.Button("ChooseDriver")({
							label = "Choose a driver",
							onActivate = function()
								scrollTarget:set(nil)
								scrollTarget:set("Drivers")
							end,
						}),
					}),
					{ preferred = "ChooseDriver" }
				),
				UI.ZStack("HeroScene")({
					clipChildren = true,

					UI.Image("HeroArt")({
						width = UI.fill(),
						height = UI.fill(),
						image = "rbxthumb://type=AvatarHeadShot&id=1&w=420&h=420",
						imageFraming = Compose.formula(function(use)
							local reduced = ctx.env and use(ctx.env:get("motionPolicy")) == "reduced"
							return {
								width = 420,
								height = 420,
								focusY = 0.25,
								scale = if reduced then 1 else 1.04 - 0.04 * use(scrollProgress),
							}
						end),
					}),
					UI.gradient(
						UI.Box("Readability")({ surface = "base", width = UI.fill(), height = UI.fill() }),
						{ colors = { "surface", "surfaceStrong" }, rotation = 90, transparency = { 0.55, 0.08 } }
					),
				})
			)

			local showroom = UI.VStack("Showroom")({
				width = UI.fill(),
				gap = "m",

				hero,
				heading("Choose your driver"),
				driverGrid,
				heading("Image backgrounds"),
				UI.Grid("Backgrounds")(previews),
			})
			local raceSetup = UI.VStack("RaceSetup")({
				width = UI.fill(),
				gap = "m",

				UI.focusSection(UI.VStack("SettingsRows")({
					width = UI.fill(),
					gap = "m",
					rowAction,
					rowToggle,
					rowSlider,
				})),
				heading("Prepare a race"),
				save,
				UI.Text("Status")({ text = status, width = UI.fill() }),
				heading("Set the lap count"),
				repeatButton,
				UI.Text("Count")({
					text = Compose.formula(function(use)
						return tostring(use(count)) .. " laps"
					end),
				}),
				shortcut,
				heading("Filter the grid"),
				menu,
				UI.Text({
					text = Compose.formula(function(use)
						return (if use(favorites) then "Favorites" else "All races")
							.. " · "
							.. use(weather)
							.. " weather"
					end),
					width = UI.fill(),
				}),
				heading("Start or choose a mode"),
				UI.Text("CapSplit")({
					text = "Split button · one control: the action, and its menu (pointer: split; touch: long-press, with a chevron)",
					textSize = "caption",
					role = "secondary",
					width = UI.fill(),
				}),
				split,
				UI.Button("Confirm")({ label = "Confirm race…", enabled = enabled, onActivate = openDialog }),
			})
			local body = UI.AdaptiveStack("Sections")({
				width = UI.fill(),
				gap = "l",
				align = "start",
				axis = Compose.formula(function(use)
					return if use(conditions.isWide) then "x" else "y"
				end),
				showroom,
				raceSetup,
			})
			local page = UI.VStack({
				width = UI.fill(),
				gap = "m",

				UI.Text({ text = "Actions and menus", textSize = "title", width = UI.fill() }),
				UI.Button("Reset")({ label = "Reset", onActivate = reset }),
				UI.Button("Enable")({
					label = "Toggle enabled",
					onActivate = function()
						enabled:set(not enabled:peek())
					end,
				}),
				body,
				UI.Text({ text = "Size and emphasis", textSize = "heading", width = UI.fill() }),
				VocabularySection(),
				hintRecipe.section(),
			})
			local scroller = UI.ScrollView("Content")({
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
				page,
			})
			return UI.Screen("ActionControls")({ surface = "base", padding = "m", scroller })
		end

		return {
			screen = Example,
			states = function()
				return {
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
				sizeCompact = function()
					setRung("compact")
				end,
				sizeRegular = function()
					setRung("regular")
				end,
				sizeLarge = function()
					setRung("large")
				end,
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
					controlSize = readRung(),
					count = count:peek(),
					settings = { assistance = assist:peek(), music = rowVolume:peek() },
					scrollProgress = scrollProgress:peek(),
					heroVisible = heroVisible:peek(),
					busy = busy:peek(),
					status = status:peek(),
				}
			end,
			dispose = function() end,
		}
	end,
}
