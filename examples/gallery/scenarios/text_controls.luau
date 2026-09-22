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
		-- the field's furniture, a read-only value, a box measured in lines and a
		-- numeric field with units and arithmetic; records arrive through `ref`
		local handle = Compose.cell("")
		local nameError = Compose.cell("")
		local pasted = Compose.cell(0)
		local joinCode = Compose.cell("RALLY-8H2K")
		local brief = Compose.cell("Tell your crew what to expect on this track.")
		local feeDraft = Compose.cell("2.50")
		local fee = Compose.cell(2.5)
		local feeReason = Compose.cell("not committed yet")
		local records: { [string]: any } = {}
		local function keep(id: string)
			return function(r: any)
				records[id] = r
			end
		end
		local rootPath: string? = nil
		local function rectOf(b: any, suffix: string): any
			local controller = if type(b) == "table" and b.handle ~= nil then b.handle.controller else nil
			if controller == nil or rootPath == nil then
				return nil
			end
			controller.refresh()
			return controller.rectOf(rootPath .. "/Content/Body/" .. suffix)
		end
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
			handle:set("")
			nameError:set("")
			pasted:set(0)
			joinCode:set("RALLY-8H2K")
			brief:set("Tell your crew what to expect on this track.")
			feeDraft:set("2.50")
			fee:set(2.5)
			feeReason:set("not committed yet")
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
					stepButtons = true,
					enabled = enabled,
				}),
				UI.Text("Committed")({
					text = function(use)
						return "Committed laps: " .. tostring(use(laps))
					end,
					width = UI.fill(),
				}),
				UI.NumberInput("Fee")({
					value = feeDraft,
					numericValue = fee,
					enabled = enabled,
					min = 0,
					max = 25,
					precision = 2,
					prefix = "$",
					suffix = "ea",
					label = "Entry fee",
					hint = "Type a sum, or an expression like 3 + 5.",
					parse = ctx.Facet.recipes.arithmetic.parse,
					onCommit = function(value, reason)
						feeReason:set(`{tostring(value)} ({reason})`)
					end,
					ref = keep("Fee"),
				}),
				UI.Text("CommittedFee")({
					text = function(use)
						return "Committed fee: " .. use(feeReason)
					end,
					width = UI.fill(),
				}),
				UI.Text({ text = "Fields with furniture", textSize = "heading", width = UI.fill() }),
				UI.TextInput("Handle")({
					value = handle,
					enabled = enabled,
					label = "Display name",
					requiredMark = "required",
					hint = "Other racers see this above your kart.",
					errorText = nameError,
					trailing = UI.Button("Paste")({
						label = "Paste",
						enabled = enabled,
						onActivate = function()
							pasted:set(pasted:peek() + 1)
							handle:set("Ada Lovelace")
						end,
					}),
				}),
				UI.Text("Pasted")({
					text = function(use)
						return "Paste pressed " .. tostring(use(pasted)) .. " times"
					end,
					width = UI.fill(),
				}),
				UI.TextInput("JoinCode")({
					value = joinCode,
					label = "Join code",
					hint = "Share this with friends. It cannot be edited here.",
					readOnly = true,
					clearButtonMode = "always",
					ref = keep("JoinCode"),
				}),
				UI.TextInput("Briefing")({
					value = brief,
					multiline = true,
					visibleLines = 3,
					enabled = enabled,
					label = "Crew briefing",
					hint = "Three lines are shown; the rest scrolls.",
					ref = keep("Briefing"),
				}),
			})
		end
		return {
			screen = function()
				return UI.Screen("TextControls")({
					surface = "base",
					onAppear = function(path)
						rootPath = path
					end,
					onDisappear = function()
						rootPath = nil
					end,
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
							draft:set("1.2.3")
							number.api.handleActivate(
								(rootPath or "/TextControls") .. "/Content/Body/Laps/Input/Row/Field"
							)
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
				-- each step answers with the screen: solved rects and mounted nodes
				nameError = function(b)
					nameError:set(if nameError:peek() == "" then "That name is taken." else "")
					local label, plate = rectOf(b, "Handle/Label"), rectOf(b, "Handle/Input")
					return {
						error = nameError:peek(),
						labelAbove = if label and plate then label.y + label.h <= plate.y else nil,
						errorMark = rectOf(b, "Handle/Message/MarkWhen/then/MessageMark") ~= nil,
						trailing = rectOf(b, "Handle/Input/Row/Trailing/Paste") ~= nil,
						plateY = if plate then plate.y else nil,
					}
				end,
				-- height BEFORE the growth, then after: the box must hold still
				briefLines = function(b)
					local before = rectOf(b, "Briefing/Input")
					brief:set(string.rep("Another line of the crew briefing.\n", 12))
					local after = rectOf(b, "Briefing/Input")
					return { before = if before then before.h else nil, after = if after then after.h else nil }
				end,
				-- type an expression into the fee and commit it through the field
				stepFee = function(b)
					local control = records.Fee
					if control ~= nil and rootPath ~= nil then
						control.api.handleActivate(rootPath .. "/Content/Body/Fee/Input/Row/Field")
						feeDraft:set("3 + 5")
						control.api.submit()
					end
					local prefix, field = rectOf(b, "Fee/Input/Row/Prefix"), rectOf(b, "Fee/Input/Row/Field")
					return {
						committed = feeReason:peek(),
						value = fee:peek(),
						draft = feeDraft:peek(),
						unitOutside = if prefix and field then prefix.x + prefix.w <= field.x else nil,
						buttons = rectOf(b, "Laps/Input/Row/Increment") ~= nil
							and rectOf(b, "Laps/Input/Row/Decrement") ~= nil,
					}
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
					handle = handle:peek(),
					nameError = nameError:peek(),
					pasted = pasted:peek(),
					joinCode = if records.JoinCode then records.JoinCode.dump() else nil,
					briefing = if records.Briefing then records.Briefing.dump() else nil,
					fee = if records.Fee then records.Fee.dump() else nil,
					feeReason = feeReason:peek(),
				}
			end,
			-- nothing outlives the screen
			dispose = function() end,
		}
	end,
}
