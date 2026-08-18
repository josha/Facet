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
--   letters, or one that is not in this tutorial's word list, is REFUSED with a
--   message on the status line and does NOT consume a row. Solve the word to
--   win; six accepted wrong guesses lose and reveal the word. Either ending
--   opens a results card and disables the keyboard — only "New game" and the
--   card's own buttons still respond. "New game" is deterministic: the solution
--   comes from a seed, so the same seed always gives the same word.
--
-- WHAT THIS EXAMPLE TEACHES
--   * DOMAIN RULES BELONG TO THE EXAMPLE. `example.rules` below is a pure
--     table — scoring, the key ladder, the two word lists, the seed — with no
--     UI in it at all, so tests/example_word_game.spec.luau exercises the whole
--     game without mounting anything.
--   * A KEYED GRID. `UI.Grid({ columns = 5 })` lays the board out; the example
--     never positions a tile. Every tile's letter, colour and mark is a memo
--     over the state signals, so the view is a pure function of the state.
--   * STATE AS THEME ROLES, NEVER RAW COLOUR — and never an invented token.
--     A tile is a `UI.Box`, whose one paint channel is `tint`, so tile state is
--     a BLEND ALONG A THEME ROLE and the blend IS the strength of the evidence:
--     absent (a faint contentSecondary wash) -> present (a mid accent wash) ->
--     correct (full accent). A key is a `UI.Button`, which paints from its
--     `surface` role and its own interaction states, so a key's state rides
--     `surface`. Both also carry an ASCII MARK, because colour alone is not a
--     cue: `v` correct, `~` present, `x` absent, `_` "type here".
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
-- deps used: presenter (opens the game and the results card), actionSystem (the
-- hardware-key context). See 01's header for the shared module shape.

local example = {}
example.title = "Word Game (Wordle-style)"

-- ===========================================================================
-- THE PURE RULES — no UI, no engine, no signals. Exported as `example.rules`
-- so the tests can score a guess without mounting a screen.
-- ===========================================================================

local ROWS = 6
local COLS = 5

-- THE COMMON-SOLUTION LIST: the words the game may pick as the answer. Short
-- and ordinary on purpose — a solution list is the *easy* half of the
-- vocabulary.
local SOLUTIONS = { "REACT", "CRANE", "STACK", "LIGHT", "PLANT", "SHINE" }

-- THE ACCEPTED-GUESS DICTIONARY is a SEPARATE, WIDER list. Keeping the two
-- apart is the whole point of the mechanic: a player may guess any word the
-- game accepts, but the answer is only ever drawn from the common list, so the
-- game is never won by luck on an obscure word. (A shipping game would load
-- thousands of words; a tutorial needs exactly enough to be honest.)
local EXTRA_WORDS = {
	"ABBEY",
	"ARRAY",
	"AWARE",
	"CHAIR",
	"CLICK",
	"EERIE",
	"ERROR",
	"FOCUS",
	"GLYPH",
	"GRASP",
	"HOBBY",
	"INPUT",
	"LEVEL",
	"LLAMA",
	"MOUSE",
	"PAINT",
	"PIXEL",
	"ROBOT",
	"RULES",
	"SCOPE",
	"SNAKE",
	"SOLVE",
	"SPEED",
	"STONE",
	"THEME",
	"TILES",
	"TOUCH",
	"TRAIN",
}

local rules = {}
rules.ROWS = ROWS
rules.COLS = COLS
rules.SOLUTIONS = table.freeze(SOLUTIONS)

-- every solution is also an accepted guess, plus the wider list
local ACCEPTED: { [string]: boolean } = {}
for _, word in SOLUTIONS do
	ACCEPTED[word] = true
end
for _, word in EXTRA_WORDS do
	ACCEPTED[word] = true
end
rules.ACCEPTED = table.freeze(ACCEPTED)

-- validate(guess) -> "ok" | "short" | "unknown". The two refusals are DIFFERENT
-- messages on screen, and neither consumes a row.
function rules.validate(guess: string): string
	if #guess < COLS then
		return "short"
	end
	if not ACCEPTED[guess] then
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
function rules.solutionForSeed(seed: number): string
	local n = math.max(1, math.floor(seed))
	return SOLUTIONS[((n - 1) % #SOLUTIONS) + 1]
end

example.rules = rules

-- ===========================================================================
-- PRESENTATION VOCABULARY — every value below names a THEME role or a theme
-- metric. There is not a raw colour or a device pixel in this file.
-- ===========================================================================

-- A tile is `targetSizes.minimum` square: the theme's own smallest comfortable
-- target, which is also the smallest square a five-column board can use and
-- still be readable on a phone. It moves with the theme, unlike a literal 48.
local TILE = { type = "fixed", px = "targetSizes.minimum" }
local KEY_HEIGHT = { type = "fixed", px = "targetSizes.minimum" }
local FILL = { type = "fill", weight = 1 }
local WIDE_KEY = { type = "fill", weight = 1.5 }

-- TILE STATE -> the continuous colour channel, as a blend along a theme role.
-- `blend` is the strength of the evidence, which is exactly the kind of value a
-- closed surface enum cannot express — and the reason `tint` exists.
local TILE_TINT: { [string]: any } = {
	empty = { role = "surfaceStrong", blend = 0.6 },
	caret = { role = "surfaceStrong", blend = 1 },
	filled = { role = "control", blend = 1 },
	absent = { role = "contentSecondary", blend = 0.3 },
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

function example.build(Facet: any, core: any, deps: any)
	local UI = Facet.UI
	local pres = deps.presenter
	local actions = deps.actionSystem

	-- gameScope owns everything this example creates, so dispose() returns the
	-- registries to exactly where they were before build().
	local gameScope = core:scope("example-05-word-game")
	local function reg(readable: any): any
		gameScope:own(function()
			readable:dispose()
		end)
		return readable
	end

	-- ---- state --------------------------------------------------------------
	local rowsSig = reg(core:signal(emptyRows()))
	local activeSig = reg(core:signal(1)) -- the row letters land in; ROWS+1 = finished
	local keysSig = reg(core:signal({} :: { [string]: string }))
	local phaseSig = reg(core:signal("playing")) -- "playing" | "won" | "lost"
	local noticeSig = reg(core:signal("")) -- refusal / outcome copy for the status line
	local seedSig = reg(core:signal(1))
	local solutionSig = reg(core:memo(function(use)
		return rules.solutionForSeed(use(seedSig))
	end))
	local playingSig = reg(core:memo(function(use)
		return use(phaseSig) == "playing"
	end))
	local modalHandle: any = nil

	-- ---- game commands (pure state; they know nothing about the view) -------
	local function isPlaying(): boolean
		return phaseSig:get() == "playing"
	end

	local function typeLetter(letter: string)
		if not isPlaying() then
			return -- input is disabled after a win or a loss
		end
		local rows = cloneRows(rowsSig:get())
		local row = rows[activeSig:get()]
		if row == nil or #row.letters >= COLS then
			return
		end
		row.letters ..= letter
		core:transaction(function()
			rowsSig:set(rows)
			noticeSig:set("") -- editing clears a refusal message
		end)
	end

	local function backspace()
		if not isPlaying() then
			return
		end
		local rows = cloneRows(rowsSig:get())
		local row = rows[activeSig:get()]
		if row == nil or #row.letters == 0 then
			return
		end
		row.letters = row.letters:sub(1, #row.letters - 1)
		core:transaction(function()
			rowsSig:set(rows)
			noticeSig:set("")
		end)
	end

	local function closeResults()
		if modalHandle ~= nil then
			pres.dismiss(modalHandle)
			modalHandle = nil
		end
	end

	local function restart(seed: number?)
		closeResults()
		local nextSeed = if seed ~= nil then math.max(1, math.floor(seed)) else seedSig:get() + 1
		core:transaction(function()
			seedSig:set(nextSeed)
			rowsSig:set(emptyRows())
			activeSig:set(1)
			keysSig:set({})
			phaseSig:set("playing")
			noticeSig:set("")
		end)
	end

	-- The results card. Presented ON TOP of the board, so the board stays
	-- readable behind the scrim. It is built at open time from plain strings —
	-- nothing in it needs to react, because it is replaced on the next ending.
	local function openResults(solved: boolean, solution: string, guesses: number)
		closeResults()
		modalHandle = pres.presentModal(UI.Screen({
			id = "WordleResult",
			surface = "scrim",
			padding = "m",
			children = {
				-- A Screen's own alignH/alignV are ZSTACK-CHILD props and are
				-- silently ignored here; centring a card means putting a filling
				-- ZStack in between and letting its children inherit its alignment.
				UI.ZStack({
					id = "centre",
					width = FILL,
					height = FILL,
					alignH = "center",
					alignV = "center",
					children = {
						UI.VStack({
							id = "Card",
							surface = "raised",
							padding = "m",
							gap = "s",
							align = "center",
							children = {
								UI.Text({
									id = "Msg",
									text = if solved then "Solved!" else "Out of guesses",
									textSize = "heading",
								}),
								UI.Text({
									id = "Word",
									text = if solved
										then `{solution} in {guesses} {if guesses == 1 then "guess" else "guesses"}.`
										else `The word was {solution}.`,
									textSize = "body",
								}),
								UI.Button({
									id = "Again",
									label = "New game",
									onActivate = function()
										restart()
									end,
								}),
								UI.Button({
									id = "Close",
									label = "Close",
									onActivate = closeResults,
								}),
							},
						}),
					},
				}),
			},
		}))
	end

	local function submit()
		if not isPlaying() then
			return
		end
		local active = activeSig:get()
		local rows = cloneRows(rowsSig:get())
		local row = rows[active]
		if row == nil then
			return
		end
		local guess = row.letters

		-- REFUSALS NEVER CONSUME A ROW: the letters stay where they are, the
		-- active row does not move, and the player is told why.
		local verdict = rules.validate(guess)
		if verdict == "short" then
			noticeSig:set(`Not enough letters — {#guess} of {COLS}. This row is still yours.`)
			return
		elseif verdict == "unknown" then
			noticeSig:set(`"{guess}" is not in this tutorial's word list. Try another.`)
			return
		end

		local solution = solutionSig:get()
		local states = rules.evaluate(guess, solution)
		row.submitted = true
		row.states = states
		local keys = rules.mergeKeys(keysSig:get(), guess, states)
		core:transaction(function()
			rowsSig:set(rows) -- the scored row keeps its verdict from here on
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
		if phaseSig:get() ~= "playing" then
			openResults(phaseSig:get() == "won", solution, active)
		end
	end

	-- ---- the board: one UI.Grid, thirty bound tiles -------------------------
	local tiles = {}
	local tileStateOf: { [string]: any } = {}
	for r = 1, ROWS do
		for c = 1, COLS do
			local rr, cc = r, c
			local state = reg(core:memo(function(use)
				return tileState(use(rowsSig), use(activeSig), rr, cc)
			end))
			local letter = reg(core:memo(function(use)
				return use(rowsSig)[rr].letters:sub(cc, cc)
			end))
			local tint = reg(core:memo(function(use)
				return TILE_TINT[use(state)]
			end))
			local mark = reg(core:memo(function(use)
				return TILE_MARK[use(state)]
			end))
			tileStateOf[`{rr}:{cc}`] = state
			table.insert(
				tiles,
				UI.ZStack({
					id = `tile{r}_{c}`,
					width = TILE,
					height = TILE,
					alignH = "center",
					alignV = "center",
					children = {
						-- the plate. A Box's one paint channel is `tint`, so this is
						-- where the state colour lives.
						UI.Box({ id = "fill", width = FILL, height = FILL, tint = tint }),
						UI.Text({ id = "ch", text = letter, textSize = "heading" }),
						-- ...and the same fact again, without colour.
						UI.Text({
							id = "mark",
							text = mark,
							textSize = "caption",
							role = "secondary",
							alignH = "end",
							alignV = "end",
						}),
					},
				})
			)
		end
	end
	-- `columns` is the whole board layout — the example never places a tile.
	-- `itemSizing = "uniform"` is what makes it a BOARD rather than five columns
	-- of whatever width the screen happens to be: every cell takes the widest
	-- measured cell (one tile), so the grid reports 5 tiles + 4 gaps as its own
	-- width and the parent stack's `align = "center"` can centre it. Without it
	-- a grid says "I need the whole offer", and the tiles scatter across a
	-- desktop with a hundred pixels of nothing between them.
	local board =
		UI.Grid({ id = "board", columns = COLS, gap = "xs", rowGap = "xs", itemSizing = "uniform", children = tiles })

	-- ---- the on-screen keyboard: three HStack rows --------------------------
	-- Each key carries its APP SEMANTICS on its own node `onActivate`: a tap, or
	-- Return/A on the focused key, runs that key's command. The presenter
	-- dispatches Activate here with no consumer routing, and derives the two-
	-- dimensional navigation directly from these HStack rows (ADR-0013
	-- layout-derived groups): Left/Right within a row, Up/Down between rows
	-- landing on the nearest key in the same column. No navigation map here.
	local keyPathByLetter: { [string]: string } = {}
	local keyboardRows = {}
	for ri, keys in KEYBOARD do
		local rowId = "kbrow" .. ri
		local buttons = {}
		for ki, key in keys do
			local thisKey = key
			local isCommand = key == "Enter" or key == "Back"
			local labelOf: any
			local surfaceOf: any
			if isCommand then
				labelOf = if key == "Enter" then "Enter" else "Delete"
			else
				local state = reg(core:memo(function(use)
					return use(keysSig)[thisKey] or "unknown"
				end))
				labelOf = reg(core:memo(function(use)
					local s = use(state)
					local m = KEY_MARK[s]
					return if m ~= nil then thisKey .. m else thisKey
				end))
				surfaceOf = reg(core:memo(function(use)
					return KEY_SURFACE[use(state)]
				end))
			end
			buttons[ki] = UI.Button({
				id = "key_" .. key,
				label = labelOf,
				-- `compactLabel` is what a Button draws when the full label does not
				-- fit the box it ends up with — on a narrow phone "Delete" becomes
				-- "Del" rather than an ellipsis.
				compactLabel = if key == "Back" then "Del" else nil,
				surface = surfaceOf,
				-- after a win or a loss the whole keyboard goes dead; only "New
				-- game" and the results card still respond.
				enabled = playingSig,
				textSize = "label",
				-- a key is a LETTER IN A BOX: the theme's button inset would leave
				-- no room for the glyph in a tenth of a phone's width, and the box
				-- itself already carries the target height.
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
		keyboardRows[ri] = UI.HStack({ id = rowId, width = FILL, gap = "xs", children = buttons })
	end
	local keyboard = UI.VStack({ id = "kb", width = FILL, gap = "xs", children = keyboardRows })

	-- ---- the status line ----------------------------------------------------
	local statusSig = reg(core:memo(function(use)
		local notice = use(noticeSig)
		if notice ~= "" then
			return notice
		end
		return `Guess the five-letter word — row {math.min(use(activeSig), ROWS)} of {ROWS}.`
	end))

	local screen = UI.Screen({
		id = "Wordle",
		-- A screen with no surface floats transparently over whatever is behind
		-- it; `base` is the app background this game is meant to sit on.
		surface = "base",
		padding = "m",
		children = {
			-- The board plus a keyboard is tall. It fits a compact phone at the
			-- default text size and does NOT fit at the largest accessibility
			-- size, so the whole page scrolls rather than running off the screen.
			UI.ScrollView({
				id = "page",
				width = FILL,
				height = FILL,
				children = {
					UI.VStack({
						id = "col",
						width = FILL,
						gap = "s",
						-- cross-axis alignment of a stack's children is `align`;
						-- alignH/alignV would be accepted and ignored here.
						align = "center",
						children = {
							UI.Text({ id = "Title", text = "Facet Wordle", textSize = "title" }),
							UI.Text({ id = "Status", text = statusSig, textSize = "label", textAlign = "center" }),
							board,
							UI.Text({
								id = "Legend",
								text = "v correct   ~ present   x absent",
								textSize = "caption",
								role = "secondary",
							}),
							keyboard,
							UI.Button({
								id = "Restart",
								label = "New game",
								onActivate = function()
									restart()
								end,
							}),
						},
					}),
				},
			}),
		},
	})

	-- ---- present + wire the hardware keyboard -------------------------------
	-- Activation (tap / gamepad A on the focused key) rides each key's node
	-- onActivate, and grid navigation is auto-derived from the keyboard's HStack
	-- rows — neither needs an option.
	--
	-- `keyboardNavigation` is the ONE opt this screen asks for, and it is asked
	-- for because of what the hardware context below does: Return is bound to
	-- SUBMIT, so a keyboard player who has arrowed onto a key has no other way to
	-- press it. Turning the desktop conventions on gives them Tab/Shift+Tab
	-- traversal and Space-as-Activate, and makes this surface sink those keys
	-- while it is engaged — correct for a full-screen game.
	local handle = pres.present(screen, { keyboardNavigation = true })

	-- A dedicated, higher-priority input context for the HARDWARE keys a real
	-- keyboard sends — the genuinely app-semantic part that stays at the consumer
	-- level. It SINKS so its keys shadow the presenter's default Activate: a
	-- physical letter key TYPES into the grid (rather than activating whatever
	-- on-screen key is focused), Enter SUBMITS, and Backspace deletes.
	-- Navigation keys are intentionally NOT bound here — arrows/D-pad fall
	-- through to the presenter's auto grid navigation, so a player can switch
	-- between typing and navigating without losing the guess in flight.
	local ctx = actions.createContext({ name = "WordleInput", priority = 2000, sink = true })
	gameScope:own(function()
		ctx.destroy()
	end)
	for i = 0, 25 do
		local letter = string.char(65 + i)
		local a = ctx.createAction("Type_" .. letter, "Bool")
		a.bind({ keyCode = letter })
		a.onPressed(function()
			typeLetter(letter)
		end)
	end
	local submitAction = ctx.createAction("Submit", "Bool")
	submitAction.bind({ keyCode = "Return" })
	submitAction.onPressed(submit)
	local backAction = ctx.createAction("Backspace", "Bool")
	backAction.bind({ keyCode = "Backspace" })
	backAction.onPressed(backspace)

	-- ---- public / test API --------------------------------------------------
	return {
		title = example.title,
		screen = screen,
		handle = handle,
		rules = rules,

		-- fire a hardware key through the arbitrated action pipeline
		press = function(keyCode: string)
			actions.deviceKey(keyCode, true)
			actions.deviceKey(keyCode, false)
		end,
		row = function(i: number): string
			return rowsSig:get()[i].letters
		end,
		state = function(r: number, c: number): string
			return tileState(rowsSig:get(), activeSig:get(), r, c)
		end,
		tint = function(r: number, c: number): any
			return TILE_TINT[tileStateOf[`{r}:{c}`]:get()]
		end,
		mark = function(r: number, c: number): string
			return TILE_MARK[tileStateOf[`{r}:{c}`]:get()]
		end,
		keyState = function(letter: string): string?
			return keysSig:get()[letter]
		end,
		activeRow = function(): number
			return activeSig:get()
		end,
		phase = function(): string
			return phaseSig:get()
		end,
		won = function(): boolean
			return phaseSig:get() == "won"
		end,
		lost = function(): boolean
			return phaseSig:get() == "lost"
		end,
		status = function(): string
			return statusSig:get()
		end,
		seed = function(): number
			return seedSig:get()
		end,
		solution = function(): string
			return solutionSig:get()
		end,
		resultsOpen = function(): boolean
			return modalHandle ~= nil
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
			pres.dismiss(handle)
			gameScope:dispose()
		end,
	}
end

return example
