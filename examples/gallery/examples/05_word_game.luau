--!strict

local words = require("./words")

type Use = (any) -> any

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

local STATUS: { [string]: string } = { absent = "neutral", present = "warning", correct = "success" }

local TILE_MARK: { [string]: string } = {
	empty = "",
	caret = "_",
	filled = "",
	absent = "x",
	present = "~",
	correct = "v",
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
	local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
	local UDim2, Vector2, Enum = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum

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
	local keyPathByLetter: { [string]: any } = {}
	local function statusTag(node: Instance, state: any): Instance
		local previous: string? = nil
		Compose.watch(function(use)
			local status = STATUS[use(state)]
			local tag = if status ~= nil then `facet-status-{status}` else nil
			if tag == previous then
				return
			end
			if previous ~= nil then
				node:RemoveTag(previous)
			end
			if tag ~= nil then
				node:AddTag(tag)
			end
			previous = tag
		end)
		return node
	end

	local function measure(name: string, sample: string, size: number)
		local probe = UI.Text(name) {
			Visible = false,
			text = sample,
			TextSize = size,
			Size = UDim2.new(),
			AutomaticSize = Enum.AutomaticSize.XY,
		}
		local bounds = Compose.cell(probe.TextBounds)
		local connection = probe:GetPropertyChangedSignal("TextBounds"):Connect(function()
			bounds:set(probe.TextBounds)
		end)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
		return probe, bounds
	end

	local function WordGame()
		local letterProbe, letterBounds = measure("LetterMeasure", "W", 24)
		local markProbe, markBounds = measure("MarkMeasure", "~", 12)
		local markHeight = Compose.formula(function(use: Use): number
			local bounds: Vector2 = use(markBounds)
			return math.max(14, math.ceil(bounds.Y))
		end)
		local board: { any } = {
			columns = COLS,
			gap = "xs",
			cellHeight = function(use: Use): number
				local bounds: Vector2 = use(letterBounds)
				local mark: number = use(markHeight)
				return math.max(48, math.ceil(bounds.Y) + mark + 4)
			end,
			width = COLS * 52 - 4,
		}
		for r = 1, ROWS do
			for c = 1, COLS do
				local rr, cc = r, c
				local state = Compose.formula(function(use: Use)
					return tileState(use(rowsSig), use(activeSig), rr, cc)
				end)
				tileStateOf[`{rr}:{cc}`] = state
				local fill = Host.Frame "fill" {
					Size = UDim2.fromScale(1, 1),
					Host.UICorner({}),
					UI.Text "ch" {
						text = function(use)
							return use(rowsSig)[rr].letters:sub(cc, cc)
						end,
						TextSize = 24,
						AutomaticSize = Enum.AutomaticSize.None,
						Size = function(use)
							return UDim2.new(1, 0, 1, -use(markHeight))
						end,
						TextXAlignment = Enum.TextXAlignment.Center,
					},
					UI.Text "mark" {
						text = function(use)
							return TILE_MARK[use(state)]
						end,
						TextSize = 12,
						AutomaticSize = Enum.AutomaticSize.None,
						Position = function(use)
							return UDim2.new(0, 0, 1, -use(markHeight))
						end,
						Size = function(use)
							return UDim2.new(1, 0, 0, use(markHeight))
						end,
						TextXAlignment = Enum.TextXAlignment.Center,
					},
				}
				fill:AddTag("facet-control")
				statusTag(fill, state)
				local outline = Host.UIStroke "ActiveRow" {
					Thickness = 2,
					Enabled = function(use)
						return use(playingSig) and use(activeSig) == rr
					end,
				}
				outline:AddTag("facet-status-ring")
				local tile = UI.ZStack(`tile{r}_{c}`) { width = "fill", height = "fill", fill, outline }
				tile:AddTag("facet-status-accent")
				table.insert(board, tile)
			end
		end
		local keyboard: { any } =
			{ width = "fill", gap = "s", Host.UISizeConstraint({ MaxSize = Vector2.new(472, math.huge) }) }
		for ri, keys in KEYBOARD do
			local units = #keys
			local row: { any } = { width = "fill", gap = "xs" }
			for _, key in keys do
				local isCommand = key == "Enter" or key == "Back"
				local state = Compose.formula(function(use)
					return if isCommand then nil else use(keysSig)[key] or "unknown"
				end)
				local button = UI.Button("key_" .. key) {
					if ri == 3 and not isCommand then UI.fill() else nil,
					Size = if ri == 3
						then UDim2.fromOffset(0, 44)
						else UDim2.new(1 / units, -math.ceil(4 * (units - 1) / units), 0, 44),
					AutomaticSize = if isCommand then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
					TextSize = if isCommand then 14 else 16,
					enabled = playingSig,
					label = if key == "Enter"
						then "Enter"
						elseif key == "Back" then "Delete"
						else function(use)
							return key .. (KEY_MARK[use(state)] or "")
						end,
					onActivate = function()
						if key == "Enter" then
							submit()
						elseif key == "Back" then
							backspace()
						else
							typeLetter(key)
						end
					end,
				}
				statusTag(button, state)
				table.insert(row, button)
				keyPathByLetter[key] = `/Wordle/page/kb/kbrow{ri}/key_{key}`
			end
			table.insert(keyboard, UI.HStack("kbrow" .. ri)(row))
		end
		statusSig = Compose.formula(function(use: Use)
			local notice = use(noticeSig)
			if notice ~= "" then
				return notice
			end
			return `Guess the five-letter word — row {math.min(use(activeSig), ROWS)} of {ROWS}.`
		end)
		return UI.ScrollView "page" {
			gap = "s",
			align = "center",
			UI.Text "Title" { text = "Facet Wordle", textRole = "title" },
			UI.Text "Status" {
				text = statusSig,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
			},
			UI.Grid "board"(board),
			letterProbe,
			markProbe,
			UI.Text "Legend" { text = "v correct   ~ present   x absent", textRole = "caption" },
			UI.VStack "kb"(keyboard),
			UI.Button "Restart" {
				label = "New game",
				onActivate = function()
					restart()
				end,
			},
		}
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
		Host.InputAction "Submit" {
			Type = Enum.InputActionType.Bool,
			Pressed = submit,
			Host.InputBinding({ KeyCode = Enum.KeyCode.Return }),
		}
	)
	table.insert(
		bindings,
		Host.InputAction "Backspace" {
			Type = Enum.InputActionType.Bool,
			Pressed = backspace,
			Host.InputBinding({ KeyCode = Enum.KeyCode.Backspace }),
		}
	)
	Host.InputContext "WordGameInput" {
		Parent = ctx.inputTarget,
		Priority = 2000,
		Sink = true,
		table.unpack(bindings),
	}

	return {
		title = example.title,
		screen = function()
			return UI.Screen "Wordle" {
				WordGame(),
				UI.Alert "WordleResult" {
					isPresented = resultOpen,
					title = resultTitle,
					message = resultMessage,
					actions = {
						{ id = "Again", label = "New game", onActivate = restart },
						{ id = "Close", label = "Close", role = "cancel", onActivate = closeResults },
					},
				},
			}
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
		mark = function(r: number, c: number): string
			return TILE_MARK[tileStateOf[`{r}:{c}`]:peek()]
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
			return `/Wordle/page/board/tile{r}_{c}`
		end,
		dispose = function()
			closeResults()
		end,
	}
end
return example
