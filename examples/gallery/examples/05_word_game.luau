--!strict
-- ============================================================================
-- Example 5 of the Facet tutorial: a complete word game (Wordle-like).
-- ============================================================================
--
-- WHAT THE PLAYER SEES AT STARTUP
--   A title, a status line, a SIX-ROW BY FIVE-COLUMN board of empty tiles with
--   a caret ("_") in the cell the next letter lands in, a legend, a three-row
--   on-screen keyboard, and a "New game" button.
--
-- WHAT THE PLAYER DOES
--   Type five letters — with a hardware key, by tapping an on-screen key, or by
--   moving focus to one with the arrows/D-pad and activating it. Letters only
--   ever land in the ACTIVE row. Enter scores the guess; the scored row keeps
--   its colours while the next row becomes active. A guess shorter than five
--   letters, or one the game does not recognise, is REFUSED with a message on
--   the status line and does NOT consume a row. Solve the word to
--   win; six accepted wrong guesses lose and reveal the word. Either ending
--   opens a results card and disables the keyboard — only "New game" and the
--   card's own buttons still respond. "New game" is deterministic: the solution
--   comes from a seed, so the same seed always gives the same word.
--
-- WHAT THIS EXAMPLE TEACHES
--   * DOMAIN RULES BELONG TO THE EXAMPLE. `example.rules` below is a pure
--     table — scoring, the key ladder, the seed, and the two questions it asks
--     the shared word data — with no UI in it at all, so
--     tests/example_word_game.spec.luau exercises the whole game without
--     mounting anything.
--   * A KEYED GRID. `UI.Grid({ columns = 5 })` lays the board out; the example
--     never positions a tile. Every tile's letter, colour and mark is a memo
--     over the state signals, so the view is a pure function of the state.
--   * STATE AS THEME ROLES, NEVER RAW COLOUR — and never an invented token.
--     A tile is a `UI.Box`, whose one paint channel is `tint`, so tile state is
--     a BLEND ALONG A THEME ROLE and the blend IS how much has been decided
--     about the cell: empty (a faint contentSecondary wash) -> filled -> absent
--     -> present (a mid accent wash) -> correct (full accent). A key is a
--     `UI.Button`, which paints from its `surface` role and its own interaction
--     states, so a key's state rides `surface`. Both also carry an ASCII MARK,
--     because colour alone is not a cue: `v` correct, `~` present, `x` absent,
--     `_` "type here" — and the ACTIVE ROW wears the theme's outlined `chip`
--     plate, so "where am I typing" is a border, not a shade.
--   * MULTI-INPUT. One command, three arrival paths: a hardware key through the
--     arbitrated action system, a tap on an on-screen key, or focus + Activate
--     from a keyboard/gamepad. The three `UI.HStack` keyboard rows ARE the
--     navigation map — the presenter derives 2D movement from them, so there is
--     no navigation table in this file.
--   * A RESULTS MODAL presented on top of the board, centred by a ZStack (a
--     `Screen`'s own alignH/alignV would be accepted and ignored), whose Close
--     button actually closes it.
--
-- Everything runs headless: no engine calls, so the same file drives the tests
-- and a real Roblox client unchanged.
--
-- ctx used: app (mounts the game and the results card), actionSystem (the
-- hardware-key context). `build(ctx)` is the shape every example shares.
--
-- data used: `./words`, the shared generated English word data both word games
-- run on. It is EXAMPLE CONTENT, not framework code — `src/` does not know it
-- exists — and its two sets, the licence it ships under and the command that
-- regenerates it are all written down in `words/PROVENANCE.md`.

local words = require("./words")

local example = {}
example.title = "Word Game (Wordle-style)"

-- ===========================================================================
-- THE PURE RULES — no UI, no engine, no signals. Exported as `example.rules`
-- so the tests can score a guess without mounting a screen.
-- ===========================================================================

local ROWS = 6
local COLS = 5

-- THE TWO SETS, AND WHY THERE ARE TWO. Both are GENERATED from one pinned,
-- hash-verified SCOWL release by `tools/build_word_lists.py` — nothing here is
-- typed by hand and nothing is fetched at runtime (`words/PROVENANCE.md` has
-- the archive, its digest, the exact filters and the licence notices).
--
--   * ACCEPTED GUESSES — 6,421 five-letter words, deliberately generous.
--     A player who types an ordinary English word and is told it is not one
--     blames the game, and is right to.
--   * ANSWERS — 2,096 familiar five-letter words, a much smaller and more
--     conservative cut, minus simple plurals and past tenses. An answer nobody
--     knows is not a puzzle.
--
-- Keeping them apart is the whole mechanic: a player may guess anything the
-- game accepts, but the answer is only ever drawn from the familiar set, so the
-- game is never lost to a word nobody has heard of. Every answer is also an
-- accepted guess — the generator refuses to write the files when that is untrue.
--
-- Everything `words` returns is LOWERCASE; this game works in uppercase, so the
-- case flip happens once, at the boundary, in `solutionForSeed` below.
local rules = {}
rules.ROWS = ROWS
rules.COLS = COLS

-- The two sets, as the counts and the membership predicates a caller can
-- actually use. A 2,096-entry frozen array and a 6,421-entry set would be the
-- data itself smuggled through the rules table; these are the questions the
-- game asks it.
rules.solutionCount = words.solutionCount
rules.acceptedCount = words.bankCount(COLS)

function rules.isWord(guess: string): boolean
	return #guess == COLS and words.isWord(guess)
end

function rules.isSolution(word: string): boolean
	return words.isSolution(word)
end

-- validate(guess) -> "ok" | "short" | "unknown". The two refusals are DIFFERENT
-- messages on screen, and neither consumes a row.
function rules.validate(guess: string): string
	if #guess < COLS then
		return "short"
	end
	if not rules.isWord(guess) then
		return "unknown"
	end
	return "ok"
end

-- evaluate(guess, solution) -> { "correct" | "present" | "absent" } per column.
--
-- THE DUPLICATE-LETTER RULE, which is the only genuinely subtle part of Wordle
-- and the reason this runs in two passes: the solution's letters are a BUDGET.
-- Exact matches spend that budget FIRST (pass 1), and only what is left can pay
-- for a misplaced letter (pass 2). Anything unpaid is `absent`, so a guess with
-- three R's against a solution with one gets one verdict and two greys.
--
-- Guessing AWARE against CRANE is the case worth reading twice: the guess's
-- first A is `absent`, not `present`, because the A in column 3 already spent
-- the solution's only A.
function rules.evaluate(guess: string, solution: string): { string }
	local states: { string } = {}
	local budget: { [string]: number } = {}
	for i = 1, #solution do
		local ch = solution:sub(i, i)
		budget[ch] = (budget[ch] or 0) + 1
	end
	-- pass 1 — exact matches consume the budget before anything else can
	for i = 1, COLS do
		local g = guess:sub(i, i)
		if g ~= "" and g == solution:sub(i, i) then
			states[i] = "correct"
			budget[g] = (budget[g] or 0) - 1
		end
	end
	-- pass 2 — a misplaced letter is `present` only while budget remains
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

-- THE KEY LADDER. An on-screen key remembers the STRONGEST thing ever learned
-- about its letter, so evidence only ever accumulates: correct beats present,
-- present beats absent, and a later weaker verdict never downgrades a key. (It
-- happens constantly — guess REACT's R correct, then guess RULES and R is
-- correct again but the E is now absent; a key that took the last verdict would
-- flicker backwards.)
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

-- mergeKeys(keys, guess, states) -> a NEW key table (never a mutation, so the
-- signal sees a real change)
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

-- THE DETERMINISTIC SEED. No randomness anywhere: seed N always yields the same
-- word, so "New game" is reproducible and a test can restart to a known answer.
-- The choice itself belongs to the shared data (which MIXES the seed rather than
-- indexing it, so two restarts do not hand out two neighbours in an alphabetical
-- list); the only thing this game adds is the case it plays in.
function rules.solutionForSeed(seed: number): string
	return string.upper(words.solutionForSeed(math.max(1, math.floor(seed))))
end

example.rules = rules

-- ===========================================================================
-- PRESENTATION VOCABULARY — every value below names a THEME role or a theme
-- metric. There is not a raw colour or a device pixel in this file.
-- ===========================================================================

-- A tile is `targetSizes.minimum` square AT THE DEFAULT TEXT SIZE: the theme's
-- own smallest comfortable target, which is also the smallest square a
-- five-column board can use and still be readable on a phone. It moves with the
-- theme, unlike a literal 48.
--
-- A FLOOR, NOT A CAP, and that word is the whole point. A `fixed` px height
-- against content that is not fixed is the defect class
-- of a px height fixed against unfixed content: the letter inside a tile grows
-- with the player's text-size preference, and at the largest preference under a
-- theme with a taller type ramp the glyph was 5px out of a 44px box — the
-- solver said so, on a screen nobody had asked it about. `minMax` with a `min`
-- lets the whole board grow instead, and `itemSizing = "uniform"` keeps every
-- cell the same size as it does.
local TILE = { type = "minMax", min = "targetSizes.minimum" }
local KEY_HEIGHT = { type = "fixed", px = "targetSizes.minimum" }
local FILL = { type = "fill", weight = 1 }
local WIDE_KEY = { type = "fill", weight = 1.5 }

-- TILE STATE -> the continuous colour channel, as a blend along a theme role.
-- `blend` is how much has been decided about the cell, which is exactly the kind
-- of value a closed surface enum cannot express — and the reason `tint` exists.
--
-- WHY THE EMPTY PLATE IS NOT `surfaceStrong`, WHICH IS WHAT IT USED TO BE.
-- `surfaceStrong` is the PANEL colour: every shipped theme deliberately keeps it
-- within a few percent of `surface`, because a panel is meant to sit quietly on
-- the page. Measured across all fifteen themes in `examples/themes`, the old
-- `{ role = "surfaceStrong", blend = 0.6 }` reached a contrast ratio of 1.036:1
-- against the page it sits on under Sci-Fi HUD — thirty rectangles that are
-- perfectly present in the tree and invisible on the screen, which is the
-- failure a default-valued write produces: it claims nothing.
-- `contentSecondary` is contrast-gated against `surface` by the palette
-- contract, so a small blend along it is a plate a player can actually see in
-- every theme; `tests/example_word_game.spec.luau` pins the floor.
local TILE_TINT: { [string]: any } = {
	empty = { role = "contentSecondary", blend = 0.2 },
	-- the caret's plate is the EMPTY plate: its cue is structural (see
	-- TILE_SURFACE below) and typographic (`_`), never a shade of the same colour
	caret = { role = "contentSecondary", blend = 0.2 },
	filled = { role = "contentSecondary", blend = 0.35 },
	absent = { role = "contentSecondary", blend = 0.55 },
	present = { role = "accent", blend = 0.55 },
	correct = { role = "accent", blend = 1 },
}

-- ...AND THE NON-COLOUR CUE for the same fact. Plain ASCII, because ASCII is
-- the only range every Roblox font is guaranteed to draw (the same rule the
-- framework's own icon fallbacks follow).
local TILE_MARK: { [string]: string } = {
	empty = "",
	caret = "_",
	filled = "",
	absent = "x",
	present = "~",
	correct = "v",
}

-- THE ACTIVE ROW'S CUE, AND WHY IT IS A SURFACE. "Which row am I typing into"
-- used to be a blend difference — 1.0 against 0.6 of the same role — and a blend
-- difference IS a colour-only difference, which is the one cue a player who
-- cannot separate those two colours never receives. `chip` is the theme's own
-- small outlined plate: it carries a BORDER the idle rows do not have, drawn by
-- the theme's own chrome rules, so the cue survives a greyscale screen, a
-- repainted palette, and a `tint` nobody can tell apart.
--
-- WRITTEN AS TWO `surface = …` DECLARATIONS, which is not an accident: an enum
-- prop accepts any string and silently paints nothing when it is not a member
-- (an enum prop accepts any string — the earlier draft of this very
-- example bound `surface = "tileCorrect"` and rendered thirty transparent
-- tiles). Spelled this way, `tools/lune/check_example_drift` checks both names
-- against the Box surface enum the renderer actually resolves.
local ACTIVE_ROW_PLATE = { surface = "chip" }
local IDLE_ROW_PLATE = { surface = "plain" }

-- KEY STATE -> a surface ROLE. A Button paints from its role and its own
-- interaction states, so it takes the semantic surface rather than a tint: an
-- eliminated key sinks to the page colour, a known-present key wears the
-- outlined chip plate, and a solved letter takes the primary-action accent.
local KEY_SURFACE: { [string]: string } = {
	unknown = "control",
	absent = "base",
	present = "chip",
	correct = "accent",
}
local KEY_MARK: { [string]: string } = { absent = "x", present = "~", correct = "v" }

-- The classic three-row on-screen keyboard. Enter and Back are keys too, and
-- they are half again as wide — expressed as fill WEIGHT, so the row divides
-- whatever width it is given instead of adding up to a fixed number.
local KEYBOARD = {
	{ "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
	{ "A", "S", "D", "F", "G", "H", "J", "K", "L" },
	{ "Enter", "Z", "X", "C", "V", "B", "N", "M", "Back" },
}

-- ===========================================================================

type Row = { letters: string, submitted: boolean, states: { string }? }

local function emptyRows(): { Row }
	local out: { Row } = {}
	for _ = 1, ROWS do
		table.insert(out, { letters = "", submitted = false, states = nil })
	end
	return out
end

-- Signals hold IMMUTABLE SNAPSHOTS: every edit produces a NEW rows table, so
-- the core sees a real change and recomputes only the tile bindings that moved.
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

-- tileState(rows, active, r, c) -> the one word the tile's colour AND its mark
-- are both derived from.
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
	local UI, Compose, app = ctx.UI, ctx.Compose, ctx.app
	local actions = ctx.actionSystem
	-- Game state and hardware input survive view branches and result overlays.
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
	local closeModal: (() -> ())? = nil
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
		app.runtime:batch(function()
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
		app.runtime:batch(function()
			rowsSig:set(rows)
			noticeSig:set("")
		end)
	end
	local function closeResults()
		local close = closeModal
		if close ~= nil then
			closeModal = nil
			close()
		end
	end
	local function restart(seed: number?)
		closeResults()
		local nextSeed = if seed ~= nil then math.max(1, math.floor(seed)) else seedSig:peek() + 1
		app.runtime:batch(function()
			seedSig:set(nextSeed)
			rowsSig:set(emptyRows())
			activeSig:set(1)
			keysSig:set({})
			phaseSig:set("playing")
			noticeSig:set("")
		end)
	end
	local function openResults(solved: boolean, solution: string, guesses: number)
		closeResults()
		closeModal = app.presentModal(function()
			return UI.Screen("WordleResult")({
				surface = "scrim",
				padding = "m",
				UI.ZStack("centre")({
					width = FILL,
					height = FILL,
					alignH = "center",
					alignV = "center",
					UI.VStack("Card")({
						surface = "raised",
						padding = "m",
						gap = "s",
						align = "center",
						UI.Text("Msg")({
							text = if solved then "Solved!" else "Out of guesses",
							textSize = "heading",
						}),
						UI.Text("Word")({
							text = if solved
								then `{solution} in {guesses} {if guesses == 1 then "guess" else "guesses"}.`
								else `The word was {solution}.`,
							textSize = "body",
						}),
						UI.Button("Again")({
							label = "New game",
							onActivate = function()
								restart()
							end,
						}),
						UI.Button("Close")({
							label = "Close",
							onActivate = closeResults,
						}),
					}),
				}),
			})
		end)
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
		app.runtime:batch(function()
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
	local function WordGame()
		-- Custom board/keyboard hit targets use UI.Button for surface and
		-- compact glyph sizing; ordinary actions use UI.Button.
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
					UI.ZStack(`tile{r}_{c}`)({
						width = TILE,
						height = TILE,
						alignH = "center",
						alignV = "center",
						UI.Box("fill")({ width = FILL, height = FILL, tint = tint, surface = surface }),
						UI.Text("ch")({ text = letter, textSize = "heading" }),
						UI.Text("mark")({
							text = mark,
							textSize = "caption",
							role = "secondary",
							alignH = "end",
							alignV = "end",
						}),
					})
				)
			end
		end
		local board = UI.Grid("board")(tiles)
		local keyboardRows: { any } = { width = FILL, gap = "xs" }
		for ri, keys in KEYBOARD do
			local rowId = "kbrow" .. ri
			local buttons: { any } = { width = FILL, gap = "xs" }
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
				buttons[ki] = UI.Button("key_" .. key)({
					label = labelOf,
					compactLabel = if key == "Back" then "Del" else nil,
					surface = surfaceOf,
					enabled = playingSig,
					textSize = "label",
					padding = 0,
					width = if isCommand then WIDE_KEY else FILL,
					height = KEY_HEIGHT,
					onActivate = function()
						if thisKey == "Enter" then
							submit()
						elseif thisKey == "Back" then
							backspace()
						else
							typeLetter(thisKey)
						end
					end,
				})
				keyPathByLetter[key] = `/Wordle/page/col/kb/{rowId}/key_{key}`
			end
			keyboardRows[ri] = UI.HStack(rowId)(buttons)
		end
		local keyboard = UI.VStack("kb")(keyboardRows)
		statusSig = Compose.formula(function(use)
			local notice = use(noticeSig)
			if notice ~= "" then
				return notice
			end
			return `Guess the five-letter word — row {math.min(use(activeSig), ROWS)} of {ROWS}.`
		end)
		return UI.Screen("Wordle")({
			surface = "base",
			padding = "m",
			UI.ScrollView("page")({
				width = FILL,
				height = FILL,
				UI.VStack("col")({
					width = FILL,
					gap = "s",
					align = "center",
					UI.Text("Title")({ text = "Facet Wordle", textSize = "title" }),
					UI.Text("Status")({ text = statusSig, textSize = "label", textAlign = "center" }),
					board,
					UI.Text("Legend")({
						text = "v correct   ~ present   x absent",
						textSize = "caption",
						role = "secondary",
					}),
					keyboard,
					UI.Button("Restart")({
						label = "New game",
						onActivate = function()
							restart()
						end,
					}),
				}),
			}),
		})
	end
	local close, _, handle = app.mount(WordGame, { keyboardNavigation = true })
	local input = actions.createContext({ name = "WordleInput", priority = 2000, sink = true })
	for i = 0, 25 do
		local letter = string.char(65 + i)
		local a = input.createAction("Type_" .. letter, "Bool")
		a.bind({ keyCode = letter })
		a.onPressed(function()
			typeLetter(letter)
		end)
	end
	local submitAction = input.createAction("Submit", "Bool")
	submitAction.bind({ keyCode = "Return" })
	submitAction.onPressed(submit)
	local backAction = input.createAction("Backspace", "Bool")
	backAction.bind({ keyCode = "Backspace" })
	backAction.onPressed(backspace)
	return {
		title = example.title,
		handle = handle,
		rules = rules,
		press = function(keyCode: string)
			actions.deviceKey(keyCode, true)
			actions.deviceKey(keyCode, false)
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
			return closeModal ~= nil
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
			input.destroy()
			close()
		end,
	}
end
return example
