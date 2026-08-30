--!strict
-- THE ALWAYS-ON READOUT SWEEP: *is the content this example declares actually
-- rendered, at every supported viewport?*
--
-- WHY THIS EXISTS. On 2026-08-12 the device-bug round fixed a real overflow in
-- `06_tile_game` by wrapping its score/progress line in a `UI.ViewThatFits` with
-- two named candidate stacks. `./run-tests.sh` stayed green through it — and the
-- example's OWN test, the one named "progress and completion are visible", stayed
-- green too, because all it ever proved was that a node with that path existed in
-- the adapter and carried the right `text`. Both of those are true of a LOSING
-- ViewThatFits candidate: the framework keeps losers mounted, so their nodes,
-- their props and their text are all still there — arranged at a deliberate zero
-- rect that no player can see (src/layout/solver.luau, "unchosen ViewThatFits
-- candidates, which get a deliberate 0x0 rect").
--
-- The instrument that DID catch it was `tools/lune/check_flat_baseline`, which
-- noticed the two readouts had left the paths the baseline recorded. It is not in
-- `./run-tests.sh`; it only speaks when somebody runs it. That is the same shape
-- as the overflow diagnostic that let nine device bugs ship — see
-- `docs/lessons/the-solver-already-told-you.md` §13, *a fixture must FAIL on it,
-- or the list is a log nobody reads*.
--
-- WHAT IT ASSERTS, AND WHY IT IS THIS AND NOT MORE. For each tutorial example, a
-- SHORT hand-written list of the paths that example's own docs describe as things
-- the player reads or presses. Every one of them must, at every swept viewport:
--   * exist in the render, and
--   * carry a rect with non-zero width AND non-zero height.
--
-- Those two predicates are the whole check, and between them they cover the two
-- ways declared content stops being content: it moves to a path nothing publishes
-- any more (re-parenting under a wrapper, a renamed container), or it stays at its
-- path and is arranged to nothing (a losing candidate, a zero-width fill, a
-- collapsed hug).
--
-- IT IS DELIBERATELY NOT A GENERIC RULE OVER EVERY NODE. "Every Text with
-- non-empty text must have area" is false by construction here — a losing
-- ViewThatFits candidate is *supposed* to measure to zero, and so is a collapsed
-- disclosure and an unselected tab page. A generic rule would have to exempt
-- exactly the case that hid this defect, which is how a check becomes noise and
-- then becomes disabled. A named list is smaller, it never fires on a legitimate
-- zero, and when an author re-parents a readout on purpose the failure is the
-- moment they update the list — which is the notification that was missing.
--
-- IT IS ALSO NOT A PAINT CHECK. A non-zero rect is not proof a player can read
-- the text; the engine's own bounds, the theme's contrast and the scroll window
-- are elsewhere (`tests/overflow_sweep.spec.luau`, `tests/scroll_window_clip.spec.luau`,
-- the Studio device matrix). Being BELOW THE FOLD is explicitly fine: every one of
-- these screens is a page ScrollView, so the question is "does it exist with a
-- size", not "is it on screen right now".
--
-- IT ASKS AT EVERY TEXT SIZE (accessibility round, 2026-08-13). The sibling
-- overflow sweep gained the same axis in the same commit, and the reason is
-- sharper here than there: the defect this file was written for is a readout that
-- lost a ViewThatFits candidate ladder, and WHICH CANDIDATE WINS IS A FUNCTION OF
-- THE TEXT PREFERENCE. A ladder that keeps every readout at Medium can drop to a
-- rung that does not carry one at Largest, and the losing candidate keeps its
-- node, its props and its text — exactly the shape that stayed green here for a
-- whole mission. Same swing the overflow sweep uses (one mount per view, then the
-- live preference seam `tests/large_text_hot_swap.spec` pins as equivalent to a
-- fresh mount), measured at +0.4s on a 0.1s check.

local t = require("./lib/testkit")
local describe, it = t.describe, t.it

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")
local device_views = require("./lib/device_views")
local demo_picker = require("../examples/gallery/client/demo_picker") :: any
local large_text = require("./lib/large_text")

local VIEWS = device_views.VIEWS
local CAPABILITIES = device_views.CAPABILITIES
local SHOWCASE_TOP = demo_picker.barReservation(device_views.CORE_TOP, nil, 8)

-- the four measured accessibility preferences, from the file that records what the
-- engine does with them (see tests/lib/large_text.luau's header, decision LTN-1)
local OFFSETS: { number } = {}
for _, preference in large_text.PREFERENCES do
	table.insert(OFFSETS, preference.offset)
end
table.sort(OFFSETS)

-- THE DECLARED READOUTS. One entry per tutorial example: the text the tutorial
-- tells the reader to watch, and the control it tells them to press. Adding a
-- path here is cheap; REMOVING one is a claim that the example no longer shows it,
-- and belongs in the same commit as the change that stopped showing it.
local READOUTS: { { example: string, paths: { string } } } = {
	{
		example = "01_temperature_converter",
		-- the two-way conversion tutorial: the prompt, the live preview, the
		-- committed result, and the button that clears it
		paths = {
			"/TempConverter/Page/Title",
			"/TempConverter/Page/Prompt",
			"/TempConverter/Page/Preview",
			"/TempConverter/Page/Result",
			"/TempConverter/Page/Clear",
		},
	},
	{
		example = "02_playlist_table",
		-- the table tutorial: the hint that names the gestures AND reports which
		-- column the keys belong to, the primary-action result line, the live
		-- per-column width line, and the restore button.
		--
		-- `Widths` is here because it is the ONLY thing on the page that can show a
		-- resize happened — a table whose first column is 218px and one that was
		-- always 218px are the same screenshot — so a viewport where it is arranged
		-- to nothing is a viewport where the resize feature is invisible.
		paths = {
			"/Playlist/Page/Title",
			"/Playlist/Page/Hint",
			"/Playlist/Page/NowPlaying",
			"/Playlist/Page/Widths",
			"/Playlist/Page/Tracks",
			"/Playlist/Page/Restore",
		},
	},
	{
		example = "03_settings_sync",
		-- the async-state tutorial: the lesson text, the sync status line, and the
		-- three buttons that drive it
		paths = {
			"/Settings/Page/Title",
			"/Settings/Page/Lesson",
			"/Settings/Page/Status",
			"/Settings/Page/Hint",
			"/Settings/Page/Deliver",
			"/Settings/Page/Reset",
		},
	},
	{
		example = "04_confirm_dialog",
		-- the confirmation tutorial: the outcome line is the ENTIRE point of the
		-- example — it is what proves the dialog's answer came back
		paths = {
			"/DangerScreen/Page/Title",
			"/DangerScreen/Page/Outcome",
			"/DangerScreen/Page/Delete",
			"/DangerScreen/Page/Restore",
		},
	},
	{
		example = "05_word_game",
		-- the Wordle proof: the status line, the colour legend, one board tile
		-- (the grid is generated, so one is enough to prove the grid arrived) and
		-- the restart button
		paths = {
			"/Wordle/page/col/Title",
			"/Wordle/page/col/Status",
			"/Wordle/page/col/Legend",
			"/Wordle/page/col/board/tile1_1",
			"/Wordle/page/col/Restart",
		},
	},
	{
		example = "06_tile_game",
		--[[ THE FINDING THIS FILE WAS WRITTEN FOR. Score and Progress are the two
			readouts that spent a mission inside a ViewThatFits candidate ladder,
			present in the tree and absent from these paths. They are still here,
			at the same two paths, now carrying "0 of 60 points" and "6 turns left"
			— the goal-and-budget line the crossword's design asks for.

			FOUR PATHS WERE ADDED when the example became a crossword (the
			example-games-and-standalones stage), and each is here for the reason
			this list exists: it is something the player reads or presses, so a
			re-parenting or a collapsed hug that removed it would otherwise be
			invisible to the suite.
			  * `Word` is the LIVE VERDICT line — "Making BRAIN — 7 points", or the
			    exact sentence explaining why the turn cannot be submitted. It is
			    the only channel the nine refusals reach, so a Word node with no
			    rect is a game that has stopped explaining itself.
			  * `Actions/Submit` and `Actions/Undo` are the two turn verbs. They
			    live inside a `minColumnWidth = "intrinsic"` Grid that stacks them
			    on a narrow phone, which is exactly the adaptive shape that hid the
			    readouts last time.
			  * `board/cell4_4/plate` is ONE board square's plate — the starred
			    centre, which the first turn has to cover. The board is generated,
			    so one cell is enough to prove the 49-square grid arrived AND that
			    a cell's plate is a real rect rather than a zero-height nothing;
			    the per-theme contrast of all 49 is tests/example_tile_game.spec.
			`Hint` keeps its path and is now the instruction line only. ]]
		paths = {
			"/TileGame/Page/Title",
			"/TileGame/Page/Stats/Score",
			"/TileGame/Page/Stats/Progress",
			"/TileGame/Page/Hint",
			"/TileGame/Page/Word",
			"/TileGame/Page/board/cell4_4/plate",
			"/TileGame/Page/RackLabel",
			"/TileGame/Page/Actions/Submit",
			"/TileGame/Page/Actions/Undo",
			"/TileGame/Page/Reset",
		},
	},
	{
		example = "07_match3",
		-- the same two-readout stats line, one example over: score and moves, plus
		-- the async-artwork status the art buttons drive
		paths = {
			"/Match3/Page/Title",
			"/Match3/Page/Hint",
			"/Match3/Page/Stats/Score",
			"/Match3/Page/Stats/Moves",
			"/Match3/Page/ArtStatus",
			"/Match3/Page/Reset",
		},
	},
}

-- A surface may publish its own measured geometry back into its tree (the picker
-- strip writes `coreSafeInsets` from `onGeometry`), and the frame that does it is
-- not the frame that shows it — same bounded settle the overflow sweep uses.
local SETTLE_FRAMES = 3

local function world(view: any): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = SHOWCASE_TOP, bottom = 0, left = 0, right = 0 })
	env:set("displaySize", view.displaySize)
	env:set("preferredInput", view.input)
	env:set("capabilities", CAPABILITIES[view.input])
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new();
	(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
	local presenter = Facet.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, presenter = presenter, system = system }
end

describe("readout sweep: every tutorial example renders the content it declares", function()
	for _, entry in READOUTS do
		local module = require(`../examples/gallery/examples/{entry.example}`) :: any
		it(
			`example '{entry.example}': every declared readout has a real rect at every swept viewport, at every text size`,
			function()
				local problems: { string } = {}
				for _, view in VIEWS do
					local w = world(view)
					local built = module.build(
						Facet,
						w.core,
						{ env = w.env, actionSystem = w.system, presenter = w.presenter, adapter = w.adapter }
					)
					if built.handle == nil and built.screen ~= nil then
						built.handle = w.presenter.present(built.screen, built.present)
					end
					assert(built.handle ~= nil, `{entry.example} presented no screen`)
					for _, offset in OFFSETS do
						w.env:set("preferredTextOffset", offset)
						for _ = 1, SETTLE_FRAMES do
							w.presenter.refresh()
						end
						for _, path in entry.paths do
							local node = w.adapter.node(path)
							if node == nil then
								table.insert(
									problems,
									`  {view.id} ({view.w}x{view.h}) @ +{offset}: {path} is NOT IN THE RENDER — `
										.. "declared content that reaches no node is invisible at this viewport"
								)
								continue
							end
							local rect = node.rect
							if rect == nil then
								table.insert(
									problems,
									`  {view.id} ({view.w}x{view.h}) @ +{offset}: {path} was never arranged (no rect)`
								)
								continue
							end
							if rect.w <= 0 or rect.h <= 0 then
								table.insert(
									problems,
									string.format(
										"  %s (%dx%d) @ +%d: %s is arranged to nothing — rect %dx%d at %d,%d",
										view.id,
										view.w,
										view.h,
										offset,
										path,
										rect.w,
										rect.h,
										rect.x,
										rect.y
									)
								)
							end
						end
					end
					if built.dispose ~= nil then
						built.dispose()
					end
				end
				if #problems > 0 then
					error(
						`{entry.example}: {#problems} declared readout(s) are not rendered:\n`
							.. table.concat(problems, "\n"),
						0
					)
				end
			end
		)
	end
end)
