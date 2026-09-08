--!strict
return {
	title = "Writing and search",
	ledgerRows = { "CONTROL-TEXT" },
	build = function(ctx)
		local Facet, core = ctx.Facet, ctx.core
		local UI = Facet.UI
		local scope = core:scope("text-controls")
		local text = scope:own(core:signal("Write your race notes here."))
		local query = scope:own(core:signal(""))
		local draft = scope:own(core:signal("3"))
		local laps = scope:own(core:signal(3))
		local enabled = scope:own(core:signal(true))
		local saved = scope:own(core:signal("No notes saved yet."))
		local editor = scope:own(Facet.Controls.TextInput(core, {
			id = "Editor",
			value = text,
			multiline = true,
			enabled = enabled,
			onCommit = function(v)
				saved:set(v)
			end,
		}))
		local search = scope:own(
			Facet.Controls.TextInput(core, { id = "Search", value = query, presentation = "search", enabled = enabled })
		)
		local number = scope:own(Facet.Controls.TextInput(core, {
			id = "Laps",
			value = draft,
			presentation = "number",
			numericValue = laps,
			min = 1,
			max = 99,
			enabled = enabled,
		}))
		local matches = scope:own(core:memo(function(use)
			local out = {}
			for _, name in
				{ "Coastal circuit", "Forest sprint", "Harbor loop", "Mountain pass", "Night rally", "Riverside run" }
			do
				if string.find(string.lower(name), string.lower(use(query)), 1, true) then
					table.insert(out, name)
				end
			end
			return if #out == 0 then { "No matching tracks." } else out
		end))
		local function reset()
			text:set("Write your race notes here.")
			query:set("")
			draft:set("3")
			laps:set(3)
			enabled:set(true)
			saved:set("No notes saved yet.")
		end
		local body = UI.VStack({
			width = UI.fill(),
			gap = "m",
			children = {
				UI.Text({ text = "Writing and search", textSize = "title", width = UI.fill() }),
				UI.Button({
					id = "Enable",
					label = scope:own(core:memo(function(use)
						return if use(enabled) then "Disable fields" else "Enable fields"
					end)),
					onActivate = function()
						enabled:set(not enabled:get())
					end,
				}),
				UI.Button({ id = "Reset", label = "Reset", onActivate = reset }),
				UI.Text({ text = "Race notes", textSize = "heading", width = UI.fill() }),
				UI.Text({
					text = "Enter starts a new line. Save notes commits your text.",
					role = "secondary",
					width = UI.fill(),
				}),
				editor.blueprint,
				UI.Button({
					id = "Save",
					label = "Save notes",
					enabled = enabled,
					onActivate = function()
						editor.api.submit()
					end,
				}),
				UI.Text({ id = "Saved", text = saved, width = UI.fill() }),
				UI.Text({ text = "Find a track", textSize = "heading", width = UI.fill() }),
				search.blueprint,
				UI.ForEach({
					id = "Matches",
					items = matches,
					key = function(name)
						return name
					end,
					row = function(name)
						return UI.Text({ text = name, width = UI.fill() })
					end,
				}),
				UI.Text({ text = "Lap count · 1 to 99", textSize = "heading", width = UI.fill() }),
				number.blueprint,
				UI.Text({
					id = "Committed",
					text = scope:own(core:memo(function(use)
						return "Committed laps: " .. tostring(use(laps))
					end)),
					width = UI.fill(),
				}),
			},
		})
		return {
			screen = UI.Screen({
				id = "TextControls",
				surface = "base",
				padding = "m",
				children = {
					UI.ScrollView({ id = "Content", width = UI.fill(), height = UI.fill(), children = { body } }),
				},
			}),

			states = function()
				return {
					{
						id = "numeric-error",
						kind = "validation",
						open = function()
							draft:set("-")
							number.api.handleActivate("/TextControls/Content/VStack#1/Laps/Input/Field")
							number.api.submit()
							return true
						end,
					},
				}
			end,
			steps = {
				disable = function()
					enabled:set(false)
				end,
				enable = function()
					enabled:set(true)
				end,
				no_results = function()
					query:set("no such track")
				end,
			},
			report = function()
				return {
					text = text:get(),
					query = query:get(),
					laps = laps:get(),
					enabled = enabled:get(),
					editor = editor.dump(),
					number = number.dump(),
					saved = saved:get(),
				}
			end,
			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
