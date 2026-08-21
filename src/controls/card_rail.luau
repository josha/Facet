--!strict
--[[ THE CARD PARADIGM'S ARRANGEMENT — how many cards belong in view, and
	therefore how wide one card is (director ruling 2026-08-18).

	WHAT IT IS FOR. `newVirtualList`'s `itemExtent` takes four forms that all answer
	"how big is one item" with a number the AUTHOR knows. A card rail's answer is
	not a number at all, it is an ARRANGEMENT: how many cards should be in view
	*here*, which is a question about the space this rail actually got and about how
	the player is driving it. `itemExtent = "cards"` is that fifth form, and this
	module is the decision behind it.

	THE AUDIT'S FINDING, in its own words: a card set is one column at all six
	combos (B-1), the compact carousel does not exist even as an authored route
	(B-7), and "carousel on phone, grid on tablet" was something every author had to
	write for themselves. The framework already knew everything needed to answer it.

	WHY IT IS A MODULE RATHER THAN A BLOCK IN THE LIST. Two reasons, and the second
	is the load-bearing one:

	  · COHESION — the arrangement is one decision with three overrides, it depends
	    on nothing else in `virtual_list.luau`, and every input arrives through the
	    parameter object below (the same seam `virtual_window.luau` and
	    `table_rows.luau` were extracted behind);
	  · THE 200,000-CHARACTER `Source` WRITE CAP. `virtual_list.luau` sat 18,972
	    characters from it and this feature spent 14,824 of that, which would have
	    put the file inside the warning band the ledger exists to keep it out of
	    (`docs/handoff/SOURCE_CAP_LEDGER.md`). Over the cap a module silently stops
	    live-syncing into an open Studio session, so a live check tests the built
	    place rather than the edits on disk. The extraction is not tidying; it is
	    what keeps the file checkable.

	WHERE THE THRESHOLDS LIVE, AND WHY NOT HERE. `adaptive.CARD_MIN_WIDTH`,
	`adaptive.CARD_PEEK` and the two pure functions over them are in
	`src/layout/adaptive.luau`, beside `BREAKPOINTS` and `columnsFor`. "How many
	cards belong in view" is the same kind of question as "how many columns", it is
	pure arithmetic over numbers, and it is exported so a caller can predict it and
	so the NEXT card surface reaches it without copying a constant out of a control.
	This module decides only when to ASK, and what the author said instead.

	THE REFUSAL BELONGS TO THE CONTROL, NOT TO THIS MODULE. A rail that
	declares no `cards.perView` adapts, so it needs an environment and must REFUSE
	to construct without one — `tab_view`'s shape and `tab_view`'s reason:
	adaptation must not be able to silently not happen. But the message names the
	CONTROL, and the guard that checks every refusal is documented reads each
	control's OWN source for the shared refusal helper called with that control's
	own name (`tests/adaptive_defaults.spec.luau`) — so the host resolves its
	environment and hands the two facts in. This module says WHICH facts it needs by requiring them
	when `perView` is absent; the host says who is asking. A rail that pins
	`perView` needs neither, which is how a control that must not adapt says so.

	Public interface: `card_rail.OPTION_KEYS`, `card_rail.new(ctx) -> Arrangement`.
]]

local adaptive = require("../layout/adaptive")
local menuRecipe = require("./menu_recipe")
local specGuard = require("../spec_guard")

local card_rail = {}

--[[ CLOSED (constitution §4). Every key is a way to OVERRIDE one of the three
	decisions the facts otherwise make, so a misspelled one is an author believing
	they pinned an arrangement that is still adapting under them. ]]
card_rail.OPTION_KEYS = specGuard.keySet({ "minWidth", "peek", "perView" })

export type Ctx = {
	-- the control's name, for the refusals it raises about `cards`
	control: string,
	-- the control's `spec.cards` (nil, or the options table)
	options: any,
	--[[ THE TWO LIVE FACTS THE ARRANGEMENT READS, resolved by the HOST from its
		own environment (see the header) and REQUIRED whenever `options.perView` is
		absent — an adapting rail handed no facts would silently take the
		large-screen answer, which is the whole of ADAPT-1. Readables, so a class
		flip or a distance change re-derives the arrangement in place. ]]
	interactionClasses: any,
	distanceProfile: any,
	-- the rail's own extent along its scroll axis, and its gutter, in both the
	-- reactive and the immediate form the host already keeps
	viewportIn: (use: any) -> number,
	viewportNow: () -> number,
	gapIn: (use: any) -> number,
	gapNow: () -> number,
}

export type Arrangement = {
	-- how many whole cards are in view (>= 1)
	perView: (use: any?) -> number,
	-- ONE card's size along the scroll axis: the rail, less the peek, less the
	-- gutters, divided by the count
	extent: (use: any?) -> number,
	-- how much of the NEXT card shows past the edge (0 above one card per view)
	peek: (use: any?) -> number,
}

--[[ VALIDATE THE OPTIONS TABLE, or refuse it outright.

	`declared` is whether the host resolved `itemExtent = "cards"`. `cards` without
	it is a field that drives nothing, which is constitution §4's exact prohibition
	and the defect class the placement audit was written to end — so it is refused
	by name rather than accepted and ignored. ]]
function card_rail.assertOptions(control: string, options: any, declared: boolean)
	if options == nil then
		return
	end
	assert(
		declared,
		`{control}.cards is the options table for itemExtent = "cards" and drives nothing without it — the same `
			.. `relationship estimatedItemExtent has with "measured". Declare itemExtent = "cards" (the card `
			.. "arrangement, derived from the space this rail got and how the player is driving it), or drop cards."
	)
	assert(type(options) == "table", `{control}.cards must be a table \{ perView?, minWidth?, peek? }`)
	specGuard.assertKnownKeys(control, options, card_rail.OPTION_KEYS, "spec.cards")
	assert(
		options.perView == nil or (type(options.perView) == "number" and options.perView >= 1),
		`{control}.cards.perView must be a number >= 1: how many whole cards are in view at once. Leave it out and `
			.. "the rail answers from the facts — one card and a peek on a compact touch surface, a multi-up rail "
			.. "everywhere else."
	)
	assert(
		options.minWidth == nil or (type(options.minWidth) == "number" and options.minWidth > 0),
		`{control}.cards.minWidth must be a positive number: the narrowest a card may be squeezed to before the rail `
			.. "drops a lane."
	)
	assert(
		options.peek == nil or (type(options.peek) == "number" and options.peek >= 0),
		`{control}.cards.peek must be a number >= 0 px: how much of the NEXT card shows past the edge of a one-up `
			.. "rail (0 removes the peek). It is not spent when more than one card is in view — there the next card "
			.. "is already the affordance."
	)
end

function card_rail.new(ctx: Ctx): Arrangement
	local options: any = if type(ctx.options) == "table" then ctx.options else {}

	--[[ NEEDED ONLY WHEN THE ANSWER IS NOT ALREADY AUTHORED. A pinned `perView`
		reads no interaction class and no distance profile, so a pinned rail never
		reaches for an environment and its host never refuses for want of one. When
		it is NOT pinned the facts are mandatory, and their absence is a build error
		here rather than a large-screen answer nobody chose. ]]
	local classes: any = if options.perView == nil then ctx.interactionClasses else nil
	local distance: any = if options.perView == nil then ctx.distanceProfile else nil
	assert(
		options.perView ~= nil or classes ~= nil,
		`{ctx.control}: an adaptive card rail needs its live interaction class, and none was handed in. The control `
			.. "resolves this from its environment before building the arrangement — that is where the refusal that "
			.. "names the environment lives."
	)

	-- a live fact, read reactively inside a memo and immediately outside one. Both
	-- forms exist because `itemExtent` itself has both (`itemExtentIn`/`Now`).
	local function fact(use: any?, source: any): any
		if source == nil then
			return nil
		end
		return if use ~= nil then use(source) else (source :: any):get()
	end
	local function width(use: any?): number
		return if use ~= nil then ctx.viewportIn(use) else ctx.viewportNow()
	end
	local function gap(use: any?): number
		return if use ~= nil then ctx.gapIn(use) else ctx.gapNow()
	end

	local self: Arrangement = {} :: any

	--[[ AUTHORED WINS OUTRIGHT. Otherwise `adaptive.cardsPerView` answers: the
		compact-touch rung is one card, and every other combination is the shared
		lane arithmetic `UI.Grid` uses, so a rail and a grid at the same width with
		the same floor never disagree.

		THE RAIL'S OWN EXTENT, NOT THE SCREEN'S `sizeClass`. A rail inside a sidebar
		on a 1600px desktop has 300px to work with and the screen's class says
		"wide". The class function is pure and takes a number, so it is asked about
		the number that is actually true here; the ten-foot cap still applies,
		because it arrives through `distanceProfile` rather than through the width.

		`touchPrimary`, NOT `classes.touch`: merely HAVING touch is what put a sheet
		on a mouse-driven touchscreen laptop, and the framework settled
		that argument once, in `menu_recipe.touchPrimary`. ]]
	function self.perView(use: any?): number
		if options.perView ~= nil then
			return math.max(1, math.floor(options.perView))
		end
		return adaptive.cardsPerView(width(use), {
			touchPrimary = menuRecipe.touchPrimary(fact(use, classes)),
			gap = gap(use),
			minWidth = options.minWidth,
			distanceProfile = fact(use, distance),
		})
	end

	function self.peek(use: any?): number
		local perView = self.perView(use)
		if options.peek ~= nil then
			-- an authored peek is still not spent above one card per view: there the
			-- next card is already the affordance, and narrowing every card to make
			-- room for a sliver of one more buys nothing
			return if perView > 1 then 0 else options.peek
		end
		return adaptive.cardPeek(width(use), perView)
	end

	function self.extent(use: any?): number
		local available = width(use)
		local perView = self.perView(use)
		-- FLOORED, never rounded: a card a fraction of a pixel too wide puts the
		-- last one past the rail's own clip, which is the defect class the card_rail
		-- fixture's `RAIL_SLACK` over-reserve exists for.
		return math.max(1, math.floor((available - self.peek(use) - (perView - 1) * gap(use)) / perView))
	end

	return self
end

return card_rail
