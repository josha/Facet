--!strict

local words = require("./words")

local example = {}
example.title = "Word Game (Wordle-style)"

local ROWS = 6
local COLS = 5

local rules = {}
rules.ROWS = ROWS
rules.COLS = COLS

rules.solutionCount = words.solutionCount
rules.acceptedCount = words.bankCount(COLS)

function rules.isWord(guess: string): boolean
	return #guess == COLS and words.isWord(guess)
end

function rules.isSolution(word: string): boolean
	return words.isSolution(word)
end

function rules.validate(guess: string): string
	if #guess < COLS then
		return "short"
	end
	if not rules.isWord(guess) then
		return "unknown"
	end
	return "ok"
end

function rules.evaluate(guess: string, solution: string): { string }
	local states: { string } = {}
	local budget: { [string]: number } = {}
	for i = 1, #solution do
		local ch = solution:sub(i, i)
		budget[ch] = (budget[ch] or 0) + 1
	end

	for i = 1, COLS do
		local g = guess:sub(i, i)
		if g ~= "" and g == solution:sub(i, i) then
			states[i] = "correct"
			budget[g] = (budget[g] or 0) - 1
		end
	end

	for i = 1, COLS do
		if states[i] == nil then
			local g = guess:sub(i, i)
			if (budget[g] or 0) > 0 then
				states[i] = "present"
				budget[g] -= 1
			else
				states[i] = "absent"
			end
		end
	end
	return states
end

rules.KEY_RANK = table.freeze({ absent = 1, present = 2, correct = 3 })

function rules.strongest(a: string?, b: string?): string?
	if a == nil then
		return b
	end
	if b == nil then
		return a
	end
	local ra = (rules.KEY_RANK :: any)[a] or 0
	local rb = (rules.KEY_RANK :: any)[b] or 0
	return if rb > ra then b else a
end

function rules.mergeKeys(keys: { [string]: string }, guess: string, states: { string }): { [string]: string }
	local out = table.clone(keys)
	for i = 1, COLS do
		local ch = guess:sub(i, i)
		if ch ~= "" then
			out[ch] = rules.strongest(out[ch], states[i]) :: string
		end
	end
	return out
end

function rules.solutionForSeed(seed: number): string
	return string.upper(words.solutionForSeed(math.max(1, math.floor(seed))))
end

example.rules = rules

local TILE_TINT: { [string]: any } = {
	empty = { role = "contentSecondary", blend = 0.2 },

	caret = { role = "contentSecondary", blend = 0.2 },
	filled = { role = "contentSecondary", blend = 0.35 },
	absent = { role = "contentSecondary", blend = 0.55 },
	present = { role = "accent", blend = 0.55 },
	correct = { role = "accent", blend = 1 },
}

local TILE_MARK: { [string]: string } = {
	empty = "",
	caret = "_",
	filled = "",
	absent = "x",
	present = "~",
	correct = "v",
}

local ACTIVE_ROW_PLATE = { surface = "chip" }
local IDLE_ROW_PLATE = { surface = "plain" }

local KEY_SURFACE: { [string]: string } = {
	unknown = "control",
	absent = "base",
	present = "chip",
	correct = "accent",
}
local KEY_MARK: { [string]: string } = { absent = "x", present = "~", correct = "v" }

local KEYBOARD = {
	{ "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
	{ "A", "S", "D", "F", "G", "H", "J", "K", "L" },
	{ "Enter", "Z", "X", "C", "V", "B", "N", "M", "Back" },
}

type Row = { letters: string, submitted: boolean, states: { string }? }

local function emptyRows(): { Row }
	local out: { Row } = {}
	for _ = 1, ROWS do
		table.insert(out, { letters = "", submitted = false, states = nil })
	end
	return out
end

local function cloneRows(rows: { Row }): { Row }
	local out: { Row } = {}
	for _, row in rows do
		table.insert(out, {
			letters = row.letters,
			submitted = row.submitted,
			states = if row.states ~= nil then table.clone(row.states) else nil,
		})
	end
	return out
end

local function tileState(rows: { Row }, active: number, r: number, c: number): string
	local row = rows[r]
	if row == nil then
		return "empty"
	end
	if row.submitted and row.states ~= nil then
		return (row.states :: { string })[c]
	end
	if c <= #row.letters then
		return "filled"
	end
	if r == active and c == #row.letters + 1 then
		return "caret"
	end
	return "empty"
end

function example.build(ctx: any)
	local UI, Compose = ctx.UI, ctx.Compose
	local Host = ctx.Host
	local Compose = ctx.Compose
	local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
	local UDim, UDim2, Vector2, Color3, Enum =
		nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum

	local rowsSig = Compose.cell(emptyRows())
	local activeSig = Compose.cell(1)
	local keysSig = Compose.cell({} :: { [string]: string })
	local phaseSig = Compose.cell("playing")
	local noticeSig = Compose.cell("")
	local seedSig = Compose.cell(1)
	local solutionSig = Compose.formula(function(use)
		return rules.solutionForSeed(use(seedSig))
	end)
	local playingSig = Compose.formula(function(use)
		return use(phaseSig) == "playing"
	end)
	local resultOpen = Compose.cell(false)
	local resultMessage = Compose.cell("")
	local resultTitle = Compose.cell("")
	local function isPlaying(): boolean
		return phaseSig:peek() == "playing"
	end
	local function typeLetter(letter: string)
		if not isPlaying() then
			return
		end
		local rows = cloneRows(rowsSig:peek())
		local row = rows[activeSig:peek()]
		if row == nil or #row.letters >= COLS then
			return
		end
		row.letters ..= letter
		ctx.runtime:batch(function()
			rowsSig:set(rows)
			noticeSig:set("")
		end)
	end
	local function backspace()
		if not isPlaying() then
			return
		end
		local rows = cloneRows(rowsSig:peek())
		local row = rows[activeSig:peek()]
		if row == nil or #row.letters == 0 then
			return
		end
		row.letters = row.letters:sub(1, #row.letters - 1)
		ctx.runtime:batch(function()
			rowsSig:set(rows)
			noticeSig:set("")
		end)
	end
	local function closeResults()
		resultOpen:set(false)
	end
	local function restart(seed: number?)
		closeResults()
		local nextSeed = if seed ~= nil then math.max(1, math.floor(seed)) else seedSig:peek() + 1
		ctx.runtime:batch(function()
			seedSig:set(nextSeed)
			rowsSig:set(emptyRows())
			activeSig:set(1)
			keysSig:set({})
			phaseSig:set("playing")
			noticeSig:set("")
		end)
	end
	local function openResults(solved: boolean, solution: string, guesses: number)
		resultTitle:set(if solved then "Solved!" else "Out of guesses")
		resultMessage:set(if solved then `{solution} in {guesses} guesses.` else `The word was {solution}.`)
		resultOpen:set(true)
	end
	local function submit()
		if not isPlaying() then
			return
		end
		local active = activeSig:peek()
		local rows = cloneRows(rowsSig:peek())
		local row = rows[active]
		if row == nil then
			return
		end
		local guess = row.letters
		local verdict = rules.validate(guess)
		if verdict == "short" then
			noticeSig:set(`Not enough letters — {#guess} of {COLS}. This row is still yours.`)
			return
		elseif verdict == "unknown" then
			noticeSig:set(`{guess} — this game doesn't know that word. Try another.`)
			return
		end
		local solution = solutionSig:peek()
		local states = rules.evaluate(guess, solution)
		row.submitted = true
		row.states = states
		local keys = rules.mergeKeys(keysSig:peek(), guess, states)
		ctx.runtime:batch(function()
			rowsSig:set(rows)
			keysSig:set(keys)
			activeSig:set(active + 1)
			if guess == solution then
				phaseSig:set("won")
				noticeSig:set(`Solved in {active} {if active == 1 then "guess" else "guesses"}!`)
			elseif active >= ROWS then
				phaseSig:set("lost")
				noticeSig:set(`Out of guesses — the word was {solution}.`)
			else
				noticeSig:set("")
			end
		end)
		if phaseSig:peek() ~= "playing" then
			openResults(phaseSig:peek() == "won", solution, active)
		end
	end
	local statusSig: any
	local tileStateOf: { [string]: any } = {}
	local tileSurfaceOf: { [string]: any } = {}
	local keyPathByLetter: { [string]: any } = {}
	local tileColors = {
		empty = Color3.fromRGB(58, 67, 82),
		caret = Color3.fromRGB(70, 83, 104),
		filled = Color3.fromRGB(78, 89, 109),
		absent = Color3.fromRGB(76, 82, 90),
		present = Color3.fromRGB(155, 124, 30),
		correct = Color3.fromRGB(37, 126, 79),
	}

	local function WordGame()
		local tiles: { any } = { columns = COLS, gap = "xs", rowGap = "xs", itemSizing = "uniform" }
		for r = 1, ROWS do
			for c = 1, COLS do
				local rr, cc = r, c
				local state = Compose.formula(function(use)
					return tileState(use(rowsSig), use(activeSig), rr, cc)
				end)
				local letter = Compose.formula(function(use)
					return use(rowsSig)[rr].letters:sub(cc, cc)
				end)
				local tint = Compose.formula(function(use)
					return TILE_TINT[use(state)]
				end)
				local mark = Compose.formula(function(use)
					return TILE_MARK[use(state)]
				end)
				local surface = Compose.formula(function(use)
					local taking = use(playingSig) and use(activeSig) == rr
					return if taking then ACTIVE_ROW_PLATE.surface else IDLE_ROW_PLATE.surface
				end)
				tileStateOf[`{rr}:{cc}`] = state
				tileSurfaceOf[`{rr}:{cc}`] = surface
				table.insert(
					tiles,
					Host.Frame({
						Name = `tile{r}_{c}`,
						BackgroundTransparency = 1,
						Size = function(use)
							return UDim2.new(0, 44, 0, 44)
						end,
						Host.Frame({
							Name = "fill",
							Size = UDim2.fromScale(1, 1),
							BorderSizePixel = 0,
							BackgroundColor3 = function(use)
								return tileColors[use(state)]
							end,
							Host.UICorner({ CornerRadius = UDim.new(0, 4) }),
						}),
						UI.Label({
							Name = "ch",
							Text = letter,
							TextColor3 = Color3.new(1, 1, 1),
							TextSize = 24,
							Size = UDim2.new(1, 0, 1, -12),
							TextXAlignment = Enum.TextXAlignment.Center,
							TextYAlignment = Enum.TextYAlignment.Center,
						}),
						UI.Label({
							Name = "mark",
							Text = mark,
							TextColor3 = Color3.new(1, 1, 1),
							TextSize = 12,
							Position = UDim2.new(0, 0, 1, -14),
							Size = UDim2.new(1, 0, 0, 14),
							TextXAlignment = Enum.TextXAlignment.Center,
						}),
					})
				)
			end
		end
		local board = Host.Frame({
			Name = "board",
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Host.UIGridLayout({
				SortOrder = Enum.SortOrder.LayoutOrder,
				CellSize = UDim2.fromOffset(48, 48),
				CellPadding = UDim2.fromOffset(4, 4),
				FillDirectionMaxCells = tiles.columns or 4,
			}),
			table.unpack(tiles),
		})
		local keyboardRows: { any } = {}
		for ri, keys in KEYBOARD do
			local rowId = "kbrow" .. ri
			local units = #keys
			local buttons: { any } = {}
			for ki, key in keys do
				local thisKey = key
				local isCommand = key == "Enter" or key == "Back"
				local labelOf: any
				local surfaceOf: any
				if isCommand then
					labelOf = if key == "Enter" then "Enter" else "Delete"
				else
					local state = Compose.formula(function(use)
						return use(keysSig)[thisKey] or "unknown"
					end)
					labelOf = Compose.formula(function(use)
						local s = use(state)
						local m = KEY_MARK[s]
						return if m ~= nil then thisKey .. m else thisKey
					end)
					surfaceOf = Compose.formula(function(use)
						return KEY_SURFACE[use(state)]
					end)
				end
				buttons[ki] = UI.Button({
					Name = "key_" .. key,
					Size = if ri == 3
						then UDim2.fromOffset(0, 44)
						else UDim2.new(1 / units, -math.ceil(4 * (#keys - 1) / units), 0, 44),
					AutomaticSize = if isCommand then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
					TextWrapped = false,
					Host.UIFlexItem({
						FlexMode = if ri == 3 and not isCommand then Enum.UIFlexMode.Fill else Enum.UIFlexMode.None,
					}),
					LayoutOrder = ki,
					label = labelOf,

					enabled = playingSig,
					TextSize = if isCommand then 14 else 16,
					onActivate = function()
						if thisKey == "Enter" then
							submit()
						elseif thisKey == "Back" then
							backspace()
						else
							typeLetter(thisKey)
						end
					end,
					Host.UIPadding({
						PaddingTop = UDim.new(0, 0),
						PaddingBottom = UDim.new(0, 0),
						PaddingLeft = UDim.new(0, 0),
						PaddingRight = UDim.new(0, 0),
					}),
				})
				keyPathByLetter[key] = `/Wordle/page/col/kb/{rowId}/key_{key}`
			end
			keyboardRows[ri] = Host.Frame({
				Name = rowId,
				Size = UDim2.new(1, 0, 0, 44),
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.None,
				Host.UIListLayout({
					SortOrder = Enum.SortOrder.LayoutOrder,
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalFlex = if ri == 3 then Enum.UIFlexAlignment.Fill else Enum.UIFlexAlignment.None,
					Padding = UDim.new(0, 4),
				}),
				table.unpack(buttons),
			})
		end
		local keyboard = Host.Frame({
			Name = "kb",
			Size = UDim2.new(1, 0, 0, 0),
			Host.UISizeConstraint({ MaxSize = Vector2.new(472, math.huge) }),
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Host.UIListLayout({
				SortOrder = Enum.SortOrder.LayoutOrder,
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 8),
			}),
			table.unpack(keyboardRows),
		})
		statusSig = Compose.formula(function(use)
			local notice = use(noticeSig)
			if notice ~= "" then
				return notice
			end
			return `Guess the five-letter word — row {math.min(use(activeSig), ROWS)} of {ROWS}.`
		end)
		return Host.Frame({
			Name = "Wordle",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Host.UIPadding({
				PaddingTop = UDim.new(0, 16),
				PaddingBottom = UDim.new(0, 16),
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
			}),
			Host.ScrollingFrame({
				Name = "page",
				BackgroundTransparency = 1,
				Size = function(use)
					return UDim2.new(1, 0, 1, 0)
				end,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				ScrollBarThickness = 6,
				Host.Frame({
					Name = "col",
					BackgroundTransparency = 1,
					Size = function(use)
						return UDim2.new(1, 0, 0, 0)
					end,
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					UI.Label({

						Name = "Title",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = "Facet Wordle",
						TextSize = 28,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Label({

						Name = "Status",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = statusSig,
						TextSize = 16,
						TextXAlignment = Enum.TextXAlignment.Center,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
					}),
					board,
					UI.Label({

						Name = "Legend",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = "v correct   ~ present   x absent",
						TextSize = 12,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					keyboard,
					UI.Button({

						Name = "Restart",
						label = "New game",
						onActivate = function()
							restart()
						end,
					}),
				}),
			}),
		})
	end

	local bindings = {}
	for i = 0, 25 do
		local letter = string.char(65 + i)
		table.insert(
			bindings,
			Host.InputAction({
				Name = "Type_" .. letter,
				Type = Enum.InputActionType.Bool,
				Pressed = function()
					typeLetter(letter)
				end,
				Host.InputBinding({ KeyCode = Enum.KeyCode[letter] }),
			})
		)
	end
	table.insert(
		bindings,
		Host.InputAction({
			Name = "Submit",
			Type = Enum.InputActionType.Bool,
			Pressed = submit,
			Host.InputBinding({ KeyCode = Enum.KeyCode.Return }),
		})
	)
	table.insert(
		bindings,
		Host.InputAction({
			Name = "Backspace",
			Type = Enum.InputActionType.Bool,
			Pressed = backspace,
			Host.InputBinding({ KeyCode = Enum.KeyCode.Backspace }),
		})
	)
	Host.InputContext({
		Name = "WordGameInput",
		Parent = ctx.inputTarget,
		Priority = 2000,
		Sink = true,
		table.unpack(bindings),
	})

	return {
		title = example.title,
		screen = function()
			return Host.Frame({
				Name = "WordGame",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				WordGame(),
				UI.Alert({
					Name = "WordleResult",
					isPresented = resultOpen,
					title = resultTitle,
					message = resultMessage,
					actions = {
						{ id = "Again", label = "New game", onActivate = restart },
						{ id = "Close", label = "Close", role = "cancel", onActivate = closeResults },
					},
				}),
			})
		end,
		rules = rules,
		press = function(keyCode: string)
			if keyCode == "Return" then
				submit()
			elseif keyCode == "Backspace" then
				backspace()
			else
				typeLetter(keyCode)
			end
		end,
		row = function(i: number): string
			return rowsSig:peek()[i].letters
		end,
		state = function(r: number, c: number): string
			return tileState(rowsSig:peek(), activeSig:peek(), r, c)
		end,
		tint = function(r: number, c: number): any
			return TILE_TINT[tileStateOf[`{r}:{c}`]:peek()]
		end,
		mark = function(r: number, c: number): string
			return TILE_MARK[tileStateOf[`{r}:{c}`]:peek()]
		end,
		tileSurface = function(r: number, c: number): string
			return tileSurfaceOf[`{r}:{c}`]:peek()
		end,
		keyState = function(letter: string): string?
			return keysSig:peek()[letter]
		end,
		activeRow = function(): number
			return activeSig:peek()
		end,
		phase = function(): string
			return phaseSig:peek()
		end,
		won = function(): boolean
			return phaseSig:peek() == "won"
		end,
		lost = function(): boolean
			return phaseSig:peek() == "lost"
		end,
		status = function(): string
			return statusSig:peek()
		end,
		seed = function(): number
			return seedSig:peek()
		end,
		solution = function(): string
			return solutionSig:peek()
		end,
		resultsOpen = function(): boolean
			return resultOpen:peek()
		end,
		restart = restart,
		keyPath = function(letter: string): string
			return keyPathByLetter[letter]
		end,
		tilePath = function(r: number, c: number): string
			return `/Wordle/page/col/board/tile{r}_{c}`
		end,
		dispose = function()
			closeResults()
		end,
	}
end
return example
