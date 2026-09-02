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
	SQUEEZED INTO (ruling 2, 2026-08-14, director: "follow swiftui's behavior").
	Apple's reference sentence for `ViewThatFits` is "it selects the first child
	whose IDEAL SIZE on the constrained axes fits within the proposed size", and an
	ideal size is what a view reports when nothing is proposed to it — so every
	mechanism that makes a view smaller than that ideal (truncation, `lineLimit`,
	`minimumScaleFactor`) is invisible to the choice. `shrinkWeight` is this
	framework's member of that family, and `ctx.fitProbe` is how it is made
	invisible: the flag suppresses the measure-side shrink for the duration of the
	probe, and nothing else.

	WHAT IT REPLACES: PASS 1.5 made a candidate REPORT its squeezed extent, so a
	candidate that could not fit "fit" and won. Swept 150-420px that flipped the
	winner at 10 of 28 widths (which carries the SwiftUI citations this was decided on).

	THE WINNER IS STILL SHRUNK — the flag is off again by the time the chosen
	candidate is measured and arranged, which is SwiftUI's other half: the winner
	receives its parent's real proposal. Picking is unshrunk; showing is not. ]]
function candidate.choose(deps: Deps, ctx: any, node: any, availW: number, availH: number): number
	local children = node.children or {}
	if #children == 0 then
		return 0
	end
	local wasProbing = ctx.fitProbe
	deps.setFitProbe(ctx, true)
	local chosen = #children -- the last candidate is the declared fallback
	-- the first candidate that fits but only because its label was CUT, and how
	-- tall it is: see the note in the loop
	local cutIndex: number? = nil
	local cutHeight = 0
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
			SwiftUI's ideal-size rule, and the one that leaves a prose candidate
			exactly where it was.

			THE LAST CANDIDATE IS EXEMPT BY CONSTRUCTION: it is never probed (the
			loop stops one short of it), because rule 8's fallback has to resolve
			even when nothing fits. A screen degrades; it never blanks. ]]
		local uncut = ctx.fitCuts == cutsBefore
		if fitsW and fitsH then
			if uncut then
				--[[ ...AND IT MAY NOT COST MORE ROOM THAN THE CUT ONE DID (DIR wave
					contract 7, and the half that is a MEASUREMENT rather than a
					principle).

					Refusing a cut candidate outright was run through the whole suite
					first: `adaptive_controls` and `theme_authoring` moved from a
					three-button ROW onto the three-button COLUMN their ladder declares
					below it, and their page then overflowed by 24-138px at 640x320 at
					the Largest preference under seven packages. That is trading a cut
					label for a screen painting outside its own box — the same defect
					one level out, and a worse one.

					So a cut candidate is not refused, it is UNDERCUT: a later candidate
					wins only if it is honest AND costs no more room than the cut one
					did. The objective chip's "R3" rung is shorter than the cut
					"Round 3 · Capture" rung, so it wins; a stacked action column is
					taller than the row it would replace, so the row keeps its place and
					the ladder is exactly where it was. ]]
				if cutIndex == nil or h <= cutHeight + 0.01 then
					chosen = i
					break
				end
				-- an honest candidate that costs MORE than the cut one: the cut one
				-- was the better screen, and it is what this ladder has always chosen
				chosen = cutIndex :: number
				break
			end
			if cutIndex == nil then
				cutIndex = i
				cutHeight = h
			end
		end
	end
	if chosen == #children and cutIndex ~= nil then
		--[[ THE FALLBACK IS NEVER PROBED — rule 8 promises it resolves whatever it
			measures — so when a cut candidate is in hand it has to be measured HERE to
			know whether it undercuts one. It usually does, and that is the objective
			chip: "R3" is the last rung and it is shorter than the clamped
			"Round 3 · Capture" above it.

			If it costs MORE room, the cut candidate stands, which is byte-for-byte
			what this ladder did before contract 7 — a cut label is a worse screen than
			a full one and a better screen than one that does not fit. ]]
		local cutsBefore = ctx.fitCuts
		local w, h = deps.measure(ctx, children[#children], availW, availH)
		cutsOf[#children] = ctx.fitCuts - cutsBefore
		local fitsW = availW == math.huge or w <= availW
		local fitsH = availH == math.huge or h <= availH
		if not (fitsW and fitsH and h <= cutHeight + 0.01) then
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
