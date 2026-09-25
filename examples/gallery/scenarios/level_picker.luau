--!strict

local COPY = {
	title = "Level pickers",
	intro = "A run of discrete segments that reads as one value. The plus and minus beside each one are a separate stepper sharing the same signal — not part of the picker.",
	balanced = "Balanced",
	fidelity = "Fidelity",
	difficulty = "Difficulty",
	trophies = "Trophies",
	tinted = "Tinted",
	balancedHint = "Ten bars, two filled. Drag across them, or step.",
	fidelityHint = "Three blocks, none filled: zero is a real state.",
	difficultyHint = "The same control with glyph segments, and the pair is the caller's.",
	trophiesHint = "Image segments: the control never names an asset, so you hand it two.",
	tintedHint = "Both halves overridden with fixed hues, so a theme swap moves everything above and not this.",
	readoutTitle = "What every picker reports",
	note = "One focus stop each: put the ring on a strip and press Left or Right, or the bumpers. At the end of the run the arrow goes back to navigation.",
}

local GLYPHS = { filled = "◆", empty = "◇" }

local IMAGES = { filled = "rbxassetid://93821473650946", empty = "rbxassetid://76283014616825" }

return {
	title = "Level pickers",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum

		local balanced = Compose.cell(2)
		local fidelity = Compose.cell(0)
		local difficulty = Compose.cell(3)
		local trophies = Compose.cell(1)
		local tinted = Compose.cell(6)

		local function row(id: string, label: string, hint: string, value: any, pickerId: string, spec: any): any
			spec.value = value
			return Host.Frame({
				Name = id,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 8),
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
				}),
				UI.Text({
					LayoutOrder = 1,
					Name = "Label",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = label,
					textRole = "caption",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Text({
					LayoutOrder = 2,
					Name = "Hint",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = hint,
					textRole = "caption",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Host.Frame({
					LayoutOrder = 3,
					Name = "Pair",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					UI.LevelPicker(pickerId)(spec),
					UI.Stepper({

						Name = `{id}Step`,
						value = value,
						min = if spec.allowZero == false then 1 else 0,
						max = spec.count,
					}),
				}),
			})
		end

		local function rows(): { any }
			return {
				row("Balanced", COPY.balanced, COPY.balancedHint, balanced, "BalancedBars", {
					count = 10,
					segment = "bar",
				}),
				row("Fidelity", COPY.fidelity, COPY.fidelityHint, fidelity, "FidelityBars", {
					count = 3,
					segment = "bar",
				}),
				row("Difficulty", COPY.difficulty, COPY.difficultyHint, difficulty, "DifficultyGlyphs", {
					count = 5,
					segment = "glyph",
					glyphs = GLYPHS,
				}),
				row("Trophies", COPY.trophies, COPY.trophiesHint, trophies, "TrophyIcons", {
					count = 3,
					segment = "image",
					images = IMAGES,
				}),
				row("Tinted", COPY.tinted, COPY.tintedHint, tinted, "TintedBars", {
					count = 10,
					segment = "bar",
					tint = { filled = Color3.fromHex("#7ad4a0"), empty = Color3.fromHex("#2a3340") },
				}),
			}
		end

		local readout = Compose.formula(function(use)
			return `{COPY.balanced}: {use(balanced)} of 10  ·  {COPY.fidelity}: {use(fidelity)} of 3  ·  `
				.. `{COPY.difficulty}: {use(difficulty)} of 5  ·  {COPY.trophies}: {use(trophies)} of 3  ·  `
				.. `{COPY.tinted}: {use(tinted)} of 10`
		end)

		local function screen()
			local page: { any } = {

				UI.Text "Title" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = COPY.title,
					textRole = "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				UI.Text "Intro" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = COPY.intro,
					textRole = "caption",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
			}
			for _, node in rows() do
				table.insert(page, node)
			end
			table.insert(
				page,
				Host.Frame "Readout" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 4),
					}),
					Host.UIPadding({
						PaddingTop = UDim.new(0, 8),
						PaddingBottom = UDim.new(0, 8),
						PaddingLeft = UDim.new(0, 8),
						PaddingRight = UDim.new(0, 8),
					}),
					UI.Text({
						LayoutOrder = 1,
						Name = "ReadoutTitle",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.readoutTitle,
						textRole = "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Text({
						LayoutOrder = 2,
						Name = "ReadoutBody",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = readout,
						textRole = "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
				}
			)
			table.insert(
				page,
				UI.Text "Note" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = COPY.note,
					textRole = "caption",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}
			)

			return Host.Frame "LevelPickerDemo" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				Host.ScrollingFrame "Page" {
					Size = UDim2.new(1, 0, 1, 0),
					BackgroundTransparency = 1,
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(),
					Host.UIListLayout({
						SortOrder = Enum.SortOrder.LayoutOrder,
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 8),
					}),
					table.unpack(page),
				},
			}
		end

		return {
			screen = screen,
			present = {},
			balanced = balanced,
			fidelity = fidelity,

			steps = {

				zero = function()
					balanced:set(0)
					return { balanced = balanced:peek() }
				end,
				full = function()
					balanced:set(10)
					return { balanced = balanced:peek() }
				end,
				reference = function()
					balanced:set(2)
					fidelity:set(0)
					return { balanced = balanced:peek(), fidelity = fidelity:peek() }
				end,
			},

			report = function()
				return {
					values = {
						balanced = balanced:peek(),
						fidelity = fidelity:peek(),
						difficulty = difficulty:peek(),
						trophies = trophies:peek(),
						tinted = tinted:peek(),
					},
				}
			end,
		}
	end,
}
