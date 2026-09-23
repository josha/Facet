--!strict
--[[ Pickers: `UI.ColorPicker` over caller-owned colours (docs/reference/api.md#uicolorpicker).
	A labelled well with opacity and every technique, a bare well over a team
	palette, a draft well that commits only on Apply, and the panel inline on the
	page. The committed line changes only on a commit; a toggle refuses proposals,
	to show the wells repaint only from the caller's own value. ]]
local COPY = {
	refuse = "Refuse changes",
	body = "Kart body",
	bodyHint = "Shown on the track and in the garage",
	trim = "Trim",
	livery = "Livery",
	fog = "Fog colour",
	committed = "Committed:",
	none = "nothing yet",
	colours = "Colours",
}

return {
	title = "Pickers",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local refuse = Compose.cell(false)
		local body = Compose.cell(Color3.fromRGB(46, 125, 255))
		local bodyAlpha = Compose.cell(1)
		local trim = Compose.cell(Color3.fromRGB(255, 196, 0))
		local livery = Compose.cell(Color3.fromRGB(220, 40, 60))
		local fog = Compose.cell(Color3.fromRGB(180, 200, 220))
		local committed = Compose.cell(COPY.none)
		local function accept(cell: any): (any) -> ()
			return function(next: any)
				if not refuse:peek() then
					cell:set(next)
				end
			end
		end
		local function record(c: any)
			committed:set(
				string.format(
					"#%02X%02X%02X",
					math.floor(c.R * 255 + 0.5),
					math.floor(c.G * 255 + 0.5),
					math.floor(c.B * 255 + 0.5)
				)
			)
		end
		local team = {
			{ color = Color3.fromRGB(255, 196, 0), label = "Gold" },
			{ color = Color3.fromRGB(20, 20, 24), label = "Carbon" },
			{ color = Color3.fromRGB(240, 240, 240), label = "Chalk" },
			{ color = Color3.fromRGB(0, 170, 140), label = "Teal" },
		}

		local function section(): any
			return UI.VStack("Pickers")({
				width = UI.fill(),
				gap = "m",
				UI.Text("ColoursTitle")({ text = COPY.colours, textSize = "label", width = UI.fill() }),
				UI.Toggle("Refuse")({ label = COPY.refuse, value = refuse }),
				UI.Text("Committed")({
					width = UI.fill(),
					text = function(use: any): string
						return `{COPY.committed} {use(committed)}`
					end,
				}),
				UI.ColorPicker("Body")({
					label = COPY.body,
					hint = COPY.bodyHint,
					value = body,
					onChange = accept(body),
					onCommit = record,
					alpha = bodyAlpha,
					onAlphaChange = accept(bodyAlpha),
					modes = { "swatches", "spectrum", "sliders", "brick" },
				}),
				UI.HStack("Wells")({
					gap = "m",
					align = "center",
					UI.Text("TrimLabel")({ text = COPY.trim }),
					UI.ColorPicker("Trim")({
						value = trim,
						onChange = accept(trim),
						onCommit = record,
						swatches = team,
					}),
				}),
				UI.ColorPicker("Livery")({
					label = COPY.livery,
					value = livery,
					onChange = accept(livery),
					onCommit = record,
					draft = true,
				}),
				UI.ColorPicker("Fog")({
					label = COPY.fog,
					style = "inline",
					modes = { "sliders" },
					value = fog,
					onChange = accept(fog),
					onCommit = record,
				}),
			})
		end

		return {
			section = section,
			screen = function()
				return UI.Screen("PickersScreen")({
					surface = "base",
					padding = { top = "m", bottom = "m" },
					UI.ScrollView("Content")({
						width = UI.fill(),
						height = UI.fill(),
						padding = { left = "m", right = "m" },
						section(),
					}),
				})
			end,
			steps = {},
		}
	end,
}
