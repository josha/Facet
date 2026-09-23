--!strict
--[[ FIT-CANDIDATE SELECTION, lifted out of `layout/solver.luau` on 2026-09-02
	because the solver had 861 characters of Source-write headroom and the
	wicked-fast round needs several hundred of them (`source-cap-ledger.md`'s
	trigger for that row named this function by name).

	IT IS A ONE-WAY SPLIT. The only things it needed from the host were the
	mutually-recursive `measure` and `setFitProbe` — both forward locals there,
	both handed in as a bind-time `Deps` record exactly as `GRID_DEPS` /
	`FLOW_DEPS` / `COMPOSITION_DEPS` already are. Everything else it reads is a
	field of the `ctx` or `node` it is given (`ctx.fitProbe`, `ctx.fitCuts`),
	so no mutable upvalue of the solver crosses this boundary and no behavior
	changes: `tests/fits_ideal_size.spec.luau` and the three reuse oracles are
	the proof, not this comment. ]]
local candidate = {}

export type Deps = {
	measure: (any, any, number, number) -> (number, number),
	setFitProbe: (any, boolean) -> (),
}

--[[ ViewThatFits candidate choice (A-AL1). Pure and side-effect free apart from
	the measure cache, so measure and arrange always agree on the winner.

	A CANDIDATE IS JUDGED AT THE SIZE IT WOULD LIKE, NOT AT THE SIZE IT COULD BE
	SQUEEZED INTO (ruling 2, 2026-08-14 — the director ruled: follow the reference
	framework's behavior). The reference framework's own sentence for its
	`ViewThatFits` is "it selects the first child whose IDEAL SIZE on the
	constrained axes fits within the proposed size", and an
	ideal size is what a view reports when nothing is proposed to it — so every
	mechanism that makes a view smaller than that ideal (truncation, `lineLimit`,
	`minimumScaleFactor`) is invisible to the choice. `shrinkWeight` is this
	framework's member of that family, and `ctx.fitProbe` is how it is made
	invisible: the flag suppresses the measure-side shrink for the duration of the
	probe, and nothing else.

	WHAT IT REPLACES: PASS 1.5 made a candidate REPORT its squeezed extent, so a
	candidate that could not fit "fit" and won. Swept 150-420px that flipped the
	winner at 10 of 28 widths (which carries the reference citations this was decided on).

	THE WINNER IS STILL SHRUNK — the flag is off again by the time the chosen
	candidate is measured and arranged, which is the reference rule's other half: the winner
	receives its parent's real proposal. Picking is unshrunk; showing is not. ]]
function candidate.choose(deps: Deps, ctx: any, node: any, availW: number, availH: number): number
	local children = node.children or {}
	if #children == 0 then
		return 0
	end
	local wasProbing = ctx.fitProbe
	deps.setFitProbe(ctx, true)
	local chosen = #children -- the last candidate is the declared fallback
	-- the first candidate that fits but only because its label was CUT
	local cutIndex: number? = nil
	--[[ WHAT THIS LADDER OWES ITS CALLER (M1a, review 2026-08-18): the cuts of the
		configuration it ACTUALLY CHOSE, and not one more.

		`ctx.fitCuts` is solve-wide and an enclosing `ViewThatFits` reads its delta
		across this whole subtree — so every rung this ladder REJECTED was being
		billed to the ladder above it. A/B with identical painted content, only the
		inner ladder's first rung differing: with an inner rung that is cut (and
		correctly rejected in favour of an uncut one) the OUTER ladder dropped its
		rich rung; with an inner first rung that fits, the outer kept it. Both trees
		paint the same characters. The inner ladder did its job and the outer one was
		charged for it.

		So the counter is restored to its entry value and the chosen rung's own cuts
		are added back. A nested ladder that resolves internally therefore costs its
		parent nothing, while a chosen rung that really is cut still reports it —
		which is the difference between "this subtree contains a cut" and "this
		subtree WILL PAINT a cut", and only the second one is a fit failure. ]]
	local entryCuts = ctx.fitCuts
	local cutsOf: { [number]: number } = {}
	for i = 1, #children - 1 do
		local cutsBefore = ctx.fitCuts
		local w, h = deps.measure(ctx, children[i], availW, availH)
		cutsOf[i] = ctx.fitCuts - cutsBefore
		local fitsW = availW == math.huge or w <= availW
		local fitsH = availH == math.huge or h <= availH
		--[[ ...AND IT MAY NOT HAVE BEEN CUT TO GET THERE (DIR wave contract 7,
			2026-08-18; director device round 2026-08-17).

			THE WIDTH TEST ALONE CAN NEVER SAY NO ABOUT TEXT. Both of the solver's
			cutting paths report a width no bigger than the offer — a single line is
			CLAMPED to it (`min(measured, availW)`, so `truncated` stays honest for
			`clippedEssential`), and a wrapping one is capped by `lineLimit` AFTER
			wrapping into it. So a rung holding a label always passed `w <= availW`,
			the first candidate always won, and every `ViewThatFits` over text has
			been picking its richest rung and letting the engine ellipsize it.
			Measured on the shipped HUD under fantasy-ornate at the Larger and
			Largest preferences: the topbar objective chip drew "Round 3 · Capt…"
			rather than swapping to the "R3" rung it declares for exactly this.

			THE VERDICT IS THE TEST, and it is the verdict the solve already
			computes: `recordTextFacts` decides `truncated` on every measure, and the
			probe counts it (`ctx.fitCuts`). Re-deriving a second "would this be cut"
			rule here is how the two seams end up disagreeing — the defect class this
			file has fixed four times.

			WRAPPING IS STILL FITTING. A candidate whose label reflows onto two lines
			inside the offer is cut nowhere and still wins; only a candidate the
			engine would ellipsize is refused. That is the narrow reading of
			the reference ideal-size rule, and the one that leaves a prose candidate
			exactly where it was.

			THE LAST CANDIDATE IS EXEMPT BY CONSTRUCTION: it is never probed (the
			loop stops one short of it), because rule 8's fallback has to resolve
			even when nothing fits. A screen degrades; it never blanks. ]]
		local uncut = ctx.fitCuts == cutsBefore
		--[[ AN HONEST CANDIDATE THAT FITS WINS (owner ruling 2026-09-23, the
			reference rule). A scrolling axis is offered `math.huge`, so there only
			the cross axis decides. The old undercut kept a cut rung whenever the
			honest one was taller, which picked the cut row even with room to
			spare for the column; a stack now offers a ViewThatFits only the room
			its siblings' gaps leave, so an honest fit is a real one. A cut rung that
			fits is kept only for when nothing honest does. ]]
		if fitsW and fitsH then
			if uncut then
				chosen = i
				break
			end
			if cutIndex == nil then
				cutIndex = i
			end
		end
	end
	if chosen == #children and cutIndex ~= nil then
		-- THE FALLBACK IS NEVER PROBED (rule 8 promises it resolves), so with a
		-- cut rung in hand it is measured here: a cut label beats one that does
		-- not fit at all.
		local cutsBefore = ctx.fitCuts
		local w, h = deps.measure(ctx, children[#children], availW, availH)
		cutsOf[#children] = ctx.fitCuts - cutsBefore
		local fitsW = availW == math.huge or w <= availW
		local fitsH = availH == math.huge or h <= availH
		if not (fitsW and fitsH) then
			chosen = cutIndex :: number
		end
	end
	-- ...and the ladder reports only what its winner will paint (see `entryCuts`).
	-- The fallback rung is `nil` here whenever it was never probed, which is the
	-- common path and correctly costs the caller nothing.
	ctx.fitCuts = entryCuts + (cutsOf[chosen] or 0)
	deps.setFitProbe(ctx, wasProbing)
	return chosen
end

return candidate
