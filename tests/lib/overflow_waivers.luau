--!strict
--[[ THE WAIVER REGISTRY for the containment invariant (`tests/lib/overflow_guard`).

	A waiver is a NAMED, OWNED, REASONED exception to "nothing paints outside the
	box it lives in". It is not a suppression list and it is not allowed to rot:

	  * every waiver names a node PATTERN, a KIND, a REASON and an OWNER;
	  * a waiver that never fires across the full suite is RED
	    (`tests/overflow_guard.spec.luau`, "no waiver rot"), because a waiver
	    nobody needs is a hole nobody is watching;
	  * a waiver caps the overhang it forgives (`maxPx`). Deliberate overflow has
	    a SIZE — a disc that straddles a corner by half its diameter is designed,
	    the same disc 200px off the plate is a defect wearing the same path — so
	    the cap is what keeps the waiver from covering the next bug.

	WHY THE LIST IS SHORT, AND WHY THAT IS THE POINT. The escape this whole guard
	answers (the region-expand plate painting its `9` 8px past its own panel edge,
	live, under a green suite) was not an unusual shape. It was an ordinary
	container declared one width and filled with another. Every entry below had to
	earn its place by being measured firing, on a named surface, with a reason that
	is about the DESIGN rather than about the test being noisy.

	THE LIST IS EMPTY, AND THAT IS A MEASUREMENT RATHER THAN AN OMISSION. Rolled
	out on 2026-08-21 over the whole suite (33 fixture worlds) and the whole
	overflow-sweep corpus (46 surfaces x 9 viewports = 630 mounted cells, 49,224
	nodes, 24,892 of them painting), the invariant found ONE class of finding and
	it was the instrument's own — a row's transparent `Hit` Button, which paints
	nothing (fixed in the guard, not waived). Zero shipped surfaces need an
	exception. The registry stays because the day one does, the alternative is a
	suppression somebody writes into the oracle.

	THE FOUR THINGS THAT ARE NOT HERE, stated so a reader does not go looking:

	  * the R18 hit-expander floor. A sub-44px control's expanded target really
	    does exceed its own visual box, and it really does exceed its parent's —
	    but it is not a NODE. Both targets carry it as `setHitRect`, a field on the
	    control's own handle (`fake_target.setHitRect`), so it never enters the
	    node census this guard walks. The invariant is a PAINT invariant; the hit
	    floor is pinned where it belongs, in `tests/hit_expander.spec.luau`.
	  * motion. A slide-in, a marquee and a reveal all put a node outside its box
	    MID-FLIGHT, and none of them is waived here, because the guard reads the
	    SOLVED rect and the presentation offset is composed separately
	    (`presentedPosition`). A travelling node is inside its
	    box as far as this census is concerned, which is the honest answer: the
	    layout is what is being judged.
	  * a COMPOSITION REGION below its composition's box (the class the
	    solver-split round routed here, 2026-08-21). Not waived because it is not
	    a violation this guard files at all: a composition is deliberately not a
	    containment boundary, for the measured reason written in
	    `overflow_guard.luau` — 312 of 312 occurrences are the declared FALLBACK,
	    which the framework already reports as `designed = true`. A waiver would
	    have hidden a class; a stated rule with two cases behind it does not.
	  * the region-expand plate's CORNER CLOSE DISC (DIR5 item 4). This one was
	    expected to need a waiver and MEASURED NOT TO, which is the ruling's own
	    construction proving itself: "the straddle is a MARGIN on the plate rather
	    than an offset on the disc, which is what keeps the disc inside the panel's
	    box". Driven at HEAD on all three of the HUD's expand states at
	    compact-phone portrait, `ExpandPanel/ExpandClose` sits inside its panel on
	    every edge. A waiver written from the prose rather than the geometry would
	    have been rot on the day it was added.
]]

export type Waiver = {
	-- unique; the id the unused-waiver check reports
	id: string,
	-- "outside-parent" | "zero-box"
	kind: string,
	-- Lua pattern, matched against the violating node's path
	node: string,
	-- optional Lua pattern, matched against the containment boundary's path
	boundary: string?,
	-- the largest overhang this waiver forgives, in px. Above it the violation is
	-- red anyway, with the waiver named in the message.
	maxPx: number?,
	reason: string,
	owner: string,
}

local waivers: { Waiver } = {}

return table.freeze(waivers)
