--!strict
return {
	title = "Writing and search",
	ledgerRows = { "CONTROL-TEXT" },
	build = function(ctx)
		local UI, Compose = ctx.UI, ctx.Compose
		-- The host may expose a control's record for drivers and reports.
		local function record(id: string): any
			return if ctx.controlRecord ~= nil then ctx.controlRecord(id) else nil
		end
		local function dumpOf(id: string): any
			local control = record(id)
			return if control ~= nil then control.dump() else nil
		end
		local text = Compose.cell("Write your race notes here.")
		local query = Compose.cell("")
		local draft = Compose.cell("3")
		local laps = Compose.cell(3)
		local enabled = Compose.cell(true)
		local saved = Compose.cell("No notes saved yet.")
		local matches = Compose.formula(function(use)
			local out = {}
			for _, name in
				{ "Coastal circuit", "Forest sprint", "Harbor loop", "Mountain pass", "Night rally", "Riverside run" }
			do
				if string.find(string.lower(name), string.lower(use(query)), 1, true) then
					table.insert(out, name)
				end
			end
			return if #out == 0 then { "No matching tracks." } else out
		end)
		local function reset()
			text:set("Write your race notes here.")
			query:set("")
			draft:set("3")
			laps:set(3)
			enabled:set(true)
			saved:set("No notes saved yet.")
		end
		local function body()
			return UI.VStack("Body")({
				width = UI.fill(),
				gap = "m",

				UI.Text({ text = "Writing and search", textSize = "title", width = UI.fill() }),
				UI.Button("Enable")({
					label = function(use)
						return if use(enabled) then "Disable fields" else "Enable fields"
					end,
					onActivate = function()
						enabled:set(not enabled:peek())
					end,
				}),
				UI.Button("Reset")({ label = "Reset", onActivate = reset }),
				UI.Text({ text = "Race notes", textSize = "heading", width = UI.fill() }),
				UI.Text({
					text = "Enter starts a new line. Save notes commits your text.",
					role = "secondary",
					width = UI.fill(),
				}),
				UI.TextInput("Editor")({
					value = text,
					multiline = true,
					enabled = enabled,
					onCommit = function(v)
						saved:set(v)
					end,
				}),
				UI.Button("Save")({
					label = "Save notes",
					enabled = enabled,
					onActivate = function()
						saved:set(text:peek())
					end,
				}),
				UI.Text("Saved")({ text = saved, width = UI.fill() }),
				UI.Text({ text = "Find a track", textSize = "heading", width = UI.fill() }),
				UI.TextInput("Search")({ value = query, presentation = "search", enabled = enabled }),
				UI.ForEach("Matches")({
					Compose.keyed({
						from = matches,
						key = function(name)
							return name
						end,
						render = function(name)
							return UI.Text({
								text = function(use)
									return use(name)
								end,
								width = UI.fill(),
							})
						end,
					}),
				}),
				UI.Text({ text = "Lap count · 1 to 99", textSize = "heading", width = UI.fill() }),
				UI.TextInput("Laps")({
					value = draft,
					presentation = "number",
					numericValue = laps,
					min = 1,
					max = 99,
					enabled = enabled,
				}),
				UI.Text("Committed")({
					text = function(use)
						return "Committed laps: " .. tostring(use(laps))
					end,
					width = UI.fill(),
				}),
			})
		end
		return {
			screen = function()
				return UI.Screen("TextControls")({
					surface = "base",
					padding = "m",

					UI.ScrollView("Content")({ width = UI.fill(), height = UI.fill(), body() }),
				})
			end,

			states = function()
				return {
					{
						id = "numeric-error",
						kind = "validation",
						open = function()
							local number = record("Laps")
							if number == nil then
								return false
							end
							draft:set("-")
							number.api.handleActivate("/TextControls/Content/Body/Laps/Input/Field")
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
					text = text:peek(),
					query = query:peek(),
					laps = laps:peek(),
					enabled = enabled:peek(),
					editor = dumpOf("Editor"),
					number = dumpOf("Laps"),
					saved = saved:peek(),
				}
			end,
			-- nothing outlives the screen
			dispose = function() end,
		}
	end,
}
