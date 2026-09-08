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
		local busy = signal(false)
		local enabled = signal(true)
		local count = signal(0)
		local status = signal("Ready to race.")
		local favorites = signal(false)
		local weather = signal("any")
		local seconds = 0
		local dialog
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
		local function dismiss()
			if dialog and ctx.presenter then
				ctx.presenter.dismiss(dialog)
				dialog = nil
			end
		end
		scope:own(dismiss)
		local function openDialog()
			if not ctx.presenter then
				return
			end
			dismiss()
			local dialogScope = scope:child("confirmation")
			local accept = dialogScope:own(Facet.Controls.Button(core, {
				id = "Accept",
				label = "Start",
				dialogAction = "default",
				onActivate = function()
					status:set("Race confirmed.")
					dismiss()
					dialogScope:dispose()
				end,
			}))
			local cancel = dialogScope:own(Facet.Controls.Button(core, {
				id = "Cancel",
				label = "Cancel",
				dialogAction = "cancel",
				onActivate = function()
					status:set("Race cancelled.")
					dismiss()
					dialogScope:dispose()
				end,
			}))

			local panel = UI.Screen({
				id = "RaceConfirmation",
				padding = "l",
				gap = "m",
				surface = "raised",
				children = {
					UI.Text({ text = "Start this race?", textSize = "heading" }),
					UI.Text({ text = "Press Enter to start or use Cancel.", width = UI.fill() }),
					UI.VStack({ gap = "s", children = { accept.blueprint, cancel.blueprint } }),
				},
			})
			dialog = ctx.presenter.presentModal(panel, { cancelPolicy = "none" })
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

		local body = UI.VStack({
			width = UI.fill(),
			gap = "m",
			children = {
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
				split.blueprint,
				UI.Button({ id = "Confirm", label = "Confirm race…", enabled = enabled, onActivate = openDialog }),
			},
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
		local scroller = UI.ScrollView({ id = "Content", width = UI.fill(), height = UI.fill(), children = { page } })
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
