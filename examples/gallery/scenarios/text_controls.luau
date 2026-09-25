--!strict
return {
	title = "Writing and search",
	ledgerRows = { "CONTROL-TEXT" },
	build = function(ctx)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local text = Compose.cell("Write your race notes here.")
		local query = Compose.cell("")
		local draft = Compose.cell("3")
		local laps = Compose.cell(3)
		local enabled = Compose.cell(true)
		local saved = Compose.cell("No notes saved yet.")
		local handle = Compose.cell("")
		local nameError = Compose.cell("")
		local pasted = Compose.cell(0)
		local joinCode = Compose.cell("RALLY-8H2K")
		local brief = Compose.cell("Tell your crew what to expect on this track.")
		local feeDraft = Compose.cell("2.50")
		local fee = Compose.cell(2.5)
		local feeReason = Compose.cell("not committed yet")
		local speedDraft = Compose.cell("120")
		local speed = Compose.cell(120)
		local fields: { [string]: GuiObject } = {}
		local function keep(name: string)
			return function(node: GuiObject)
				fields[name] = node
			end
		end
		local function part(name: string, path: string): Instance?
			local at: Instance? = fields[name]
			for step in string.gmatch(path, "[^/]+") do
				at = if at then at:FindFirstChild(step) else nil
			end
			return at
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
			speedDraft:set("120")
			speed:set(120)
		end
		local function caption(name: string, text: string, role: string?)
			return UI.Label(name)({
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = text,
				textRole = role,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
		local function body()
			return Host.Frame "Body" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				UI.Label({

					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Writing and search",
					textRole = "title",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Host.Frame "Toolbar" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					UI.Button "Enable" {
						LayoutOrder = 1,
						label = function(use)
							return if use(enabled) then "Disable fields" else "Enable fields"
						end,
						onActivate = function()
							enabled:set(not enabled:peek())
						end,
					},
					UI.Button "Reset" { LayoutOrder = 2, label = "Reset", appearance = "utility", onActivate = reset },
				},
				UI.Label({

					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Race notes",
					textRole = "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({

					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Enter starts a new line. Save notes commits your text.",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.TextInput "Editor" {
					value = text,
					multiline = true,
					enabled = enabled,
					onCommit = function(v)
						saved:set(v)
					end,
				},
				UI.Button "Save" {
					label = "Save notes",
					enabled = enabled,
					onActivate = function()
						saved:set(text:peek())
					end,
				},
				UI.Label "Saved" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = saved,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				UI.Label({

					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Find a track",
					textRole = "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.TextInput "Search" {
					value = query,
					presentation = "search",
					enabled = enabled,
				},
				Compose.OrderedCollection({
					from = matches,
					key = function(name)
						return name
					end,
					render = function(name)
						return UI.Label({
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = function(use)
								return use(name)
							end,
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						})
					end,
				}),
				UI.Label({

					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Lap count · 1 to 99",
					textRole = "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.NumberInput "Laps" {
					value = draft,
					numericValue = laps,
					min = 1,
					max = 99,
					stepButtons = true,
					enabled = enabled,
					ref = keep("Laps"),
				},
				UI.Label "Committed" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = function(use)
						return "Committed laps: " .. tostring(use(laps))
					end,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				UI.NumberInput "Fee" {
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
				},
				UI.Label "CommittedFee" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = function(use)
						return "Committed fee: " .. use(feeReason)
					end,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				UI.NumberInput "Speed" {
					value = speedDraft,
					numericValue = speed,
					enabled = enabled,
					min = 0,
					max = 300,
					step = 5,
					suffix = "km/h",
					label = "Pit lane limit",
					hint = "Drag sideways to change it. Focusing selects the number.",
					scrub = true,
					selectOnFocus = "all",
					ref = keep("Speed"),
				},
				caption("FurnitureHeading", "Fields with furniture", "heading"),
				UI.TextInput "Handle" {
					value = handle,
					enabled = enabled,
					label = "Display name",
					requiredMark = "required",
					hint = "Other racers see this above your kart.",
					errorText = nameError,
					trailing = UI.Button "Paste" {
						label = "Paste",
						enabled = enabled,
						onActivate = function()
							pasted:set(pasted:peek() + 1)
							handle:set("Ada Lovelace")
						end,
					},
					ref = keep("Handle"),
				},
				UI.Label "Pasted" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = function(use)
						return "Paste pressed " .. tostring(use(pasted)) .. " times"
					end,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				UI.TextInput "JoinCode" {
					value = joinCode,
					label = "Join code",
					hint = "Share this with friends. It cannot be edited here.",
					readOnly = true,
					clearButtonMode = "always",
					ref = keep("JoinCode"),
				},
				UI.TextInput "Briefing" {
					value = brief,
					multiline = true,
					visibleLines = 3,
					enabled = enabled,
					label = "Crew briefing",
					hint = "Three lines are shown; the rest scrolls.",
					ref = keep("Briefing"),
				},
			}
		end
		return {
			screen = function()
				return Host.Frame "TextControls" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					Host.UIPadding({
						PaddingTop = UDim.new(0, 16),
						PaddingBottom = UDim.new(0, 16),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
					}),
					Host.ScrollingFrame "Content" {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						CanvasSize = UDim2.new(),
						ScrollBarThickness = 6,
						Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
						body(),
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
				nameError = function()
					nameError:set(if nameError:peek() == "" then "That name is taken." else "")
					local mark = part("Handle", "Message/MessageMark")
					return {
						error = nameError:peek(),
						errorMark = if mark and mark:IsA("GuiObject") then mark.Visible else nil,
						trailing = part("Handle", "Input/Trailing/Paste") ~= nil,
					}
				end,
				briefLines = function()
					local viewport = part("Briefing", "Input/Viewport")
					local before = if viewport and viewport:IsA("GuiObject") then viewport.Size.Y.Offset else nil
					brief:set(string.rep("Another line of the crew briefing.\n", 12))
					local after = if viewport and viewport:IsA("GuiObject") then viewport.Size.Y.Offset else nil
					return { before = before, after = after }
				end,
				stepFee = function()
					local field = part("Fee", "Input/Field")
					if field and field:IsA("TextBox") then
						field:CaptureFocus()
						field.Text = "3 + 5"
						field:ReleaseFocus(true)
					end
					return {
						committed = feeReason:peek(),
						value = fee:peek(),
						draft = feeDraft:peek(),
						buttons = part("Laps", "Input/Increment") ~= nil and part("Laps", "Input/Decrement") ~= nil,
					}
				end,
			},
			report = function()
				return {
					text = text:peek(),
					query = query:peek(),
					laps = laps:peek(),
					enabled = enabled:peek(),
					editor = text:peek(),
					number = draft:peek(),
					saved = saved:peek(),
					handle = handle:peek(),
					nameError = nameError:peek(),
					pasted = pasted:peek(),
					joinCode = joinCode:peek(),
					briefing = brief:peek(),
					fee = fee:peek(),
					feeReason = feeReason:peek(),
					speed = speed:peek(),
				}
			end,

			dispose = function() end,
		}
	end,
}
