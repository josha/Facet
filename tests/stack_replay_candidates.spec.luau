--!strict
--[[ D2c — THE ARRANGE REPLAY WALKS THE DIRTY CHILDREN, NOT EVERY SIBLING TWICE.

	T14's replay re-places only the children that moved, and it decides that with TWO
	full sibling walks: an identity scan that reads `pIds[idx]` and `dirty[child.id]` for
	every child, and a commit walk that asks `hot[idx]` for every child. On `battle_hud L
	updateItem-hp` that is 2 x 1,124 iterations to place ONE child — 0.065 ms of a
	0.229 ms class after D1 and D2a, and `ctx.placeSkipped` is literally the census of
	the first walk (FacetBench §D1/§D3).

	WHAT MADE THE SCAN MANDATORY, and what replaces it. `render/layout_node` splices a
	`UI.ForEach` REGION's children into the parent's flat child list while `mount`
	replaces the REGION's children and never the enclosing panel's — so an insert into a
	spliced sibling shifts every later index while every gate term the replay has still
	holds. The scan's own header records the witness: `battle_hud L removeItem-damage`
	reaches this arm with `dirty ~= nil`, ZERO dirty children and an unmoved box over
	1,123 children, so an arm that trusted its indices would return having placed
	NOTHING while the splice moved every surviving row.

	`node.kidToken` answers that without reading a single id. `render/layout_node` stamps
	a container with a FRESH table whenever it rebuilt the children array and the SAME
	table whenever it kept (T15) or patched (D2a) one — and both of those preserve every
	id at every index, the patch by three layers of validation and the kept arm by being
	the same array. A splice is a structural refresh, which is a COLLECTING build, which
	refuses the patch and rebuilds: a new token, every time. So a payload recorded under
	a token that is still the node's own describes exactly the sequence standing here.

	── THE OWED LIST ────────────────────────────────────────────────────────────────
	Everything the two walks did per CLEAN child, and what serves it now.

	 #  what the walk did per clean child   verdict
	 1  `pIds[idx] ~= child.id` — the       SERVED BY `node.kidToken`, compared against
	    splice/reorder guard                the token the RECORDING pass wrote. Two
	                                        builds sharing a token hold the same ids at
	                                        the same indices. The token is compared
	                                        against a recorded NON-NIL value, so a
	                                        store-less solve (a hand-built tree, the
	                                        fuzzer, `dump.fromSolve`) has nil on both
	                                        sides and takes the scan. Cases: the splice,
	                                        the rebuild, and the zero-dirty-children
	                                        shape the scan was written for
	 2  `pRect[idx] == nil` — the "this     SERVED BY THE SAME TOKEN. The full pass
	    index was never placed" guard       writes `pRect[idx]` for every index it
	                                        placed and writes `pN = #children` last, and
	                                        `pN == #children` is a gate term — so under
	                                        a matching token every index below `pN` has
	                                        a rect
	 3  `dirty[child.id] ~= true` ->        SERVED BY ENUMERATING THE DIRTY SET instead
	    `continue`                          of the children, through an id -> index map
	                                        built once per token from `pIds`. Nothing is
	                                        published on this branch; it is the loop
	                                        itself that costs
	 4  the ORDER the dirty children are    PRESERVED BY SORTING. It matters on the
	    reached in                          REFUSING path: the loop calls `deps.measure`
	                                        for each dirty child before a later one can
	                                        refuse, so a different order would measure a
	                                        different subset before the same refusal and
	                                        move `lastMeasured` for nothing
	 5  the commit walk's `hot[idx]` ->     SERVED BY THE `pNoted` GATE. `noteContainment`
	    nil -> `elseif noted`               for a clean child runs only when the
	                                        RECORDING pass filed a containment finding;
	                                        the indexed arm is refused outright when it
	                                        did, so the branch it skips is one that does
	                                        nothing. Its cases are the three CONTAINMENT
	                                        cases already in
	                                        `tests/stack_replay.spec.luau` — the only
	                                        fixture in this suite whose stack files one —
	                                        and dropping this term reddens them, which
	                                        the battery below records
	 6  `pRect[idx] = r` / `pCross[idx]`    UNCHANGED — written for the hot children, who
	    for the re-placed children          are exactly the members of the short list
	 7  `cmemo.pNoted = filed`              UNCHANGED. `filed` is the OR over the
	                                        children that were re-noted, and a clean
	                                        child under `noted == false` contributes
	                                        nothing to it
	 8  `cmemo.pIssues` re-filed            UNCHANGED, and it is the container's own
	                                        findings — not a per-child channel
	 9  `ctx.placeSkipped`                  UNCHANGED, AND DELIBERATELY SO. It is a
	                                        statement about `arrangeBody` — the children
	                                        this stack did not re-place — and those are
	                                        the same children whatever enumeration found
	                                        them. Eleven pins in
	                                        `tests/stack_replay.spec.luau` read it and
	                                        none of them moves
	10  the cost of the walks themselves    `ctx.placeScanned` is the new counter, and it
	                                        is the only one that can see this lever.
	                                        Budgeted the same way `layout_node`'s patch
	                                        is: the DIRTY SET is what gets walked, so a
	                                        dirt set wider than a quarter of the children
	                                        refuses. The refusal is a pure function of
	                                        the MATCH COUNT, never of the hash order

	Every count pin carries `solves=N`, and `lastArranged` / `lastArrangeEntries` /
	`lastPlaceSkipped` are pinned in the same string as `lastPlaceScanned` — an arm that
	placed a different set of children would move the first two, and an arm that changed
	what the replay SKIPS would move the third. Every number was read off the run.

	── THE MUTATION BATTERY ─────────────────────────────────────────────────────────
	9 run, 6 bite, 3 recorded nulls. It is run over a WIDER target than this file, because
	three of the terms have their witnesses elsewhere: dropping the `pNoted` gate reddens
	six cases in `tests/stack_replay.spec.luau` (the only fixture in this suite whose
	stack files a containment finding), dropping the indexed commit walk's payload
	write-back reddens four more there, and dropping the TOKEN gate reddens twenty-six
	across the whole suite — including "a CLEAN child whose INDEX moved under a
	two-region splice refuses", which is the defect this mechanism could have shipped.
	The full transcript is in the ledger; the three nulls are:

	  * the `cmemo.pToken ~= nil` half. It guards a solve whose layout nodes carry no
	    token — a hand-built tree, `dump.fromSolve`, the fuzzer — where a plain `==`
	    would read nil against nil as a match. Nothing here solves a store-less tree WITH
	    a `reuse` set, so the state is not currently reachable; the term only makes the
	    gate stricter and it is kept for the reason `AdaptiveStack` taught one lane over,
	    where an inference about what could not happen was false.

	  * the BUDGET (owed row 10). No drive in this suite dirties more than a quarter of a
	    container's children while every other gate term still holds: the drives that
	    dirty many children at once move the container's box or the measure stamp, and
	    the replay refuses on those first. It is a COST guard, not a correctness one —
	    removing it changes no output, only the worst case — and it is kept because
	    `render/layout_node`'s patch carries the identical budget for the identical
	    reason and IS exercised there, by a spec that can hand `build` any dirty set.
	  * the `table.sort` on the short list (owed row 4). Order is observable only on the
	    REFUSING path with two or more dirty children reaching different terms, and the
	    dirty set's enumeration order is a hash order this suite cannot control. The
	    argument is written at the call site instead. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/deep_stack_scene")
local device_views = require("./lib/device_views")

local function line(s: any, before: any): string
	local st = s.stats()
	return `solves={st.solves - before.solves} scanned={st.lastPlaceScanned} skipped={st.lastPlaceSkipped} `
		.. `arranged={st.lastArranged} entries={st.lastArrangeEntries}`
end

describe("D2c: the indexed replay, on the thousand-row list", function()
	it("THE HEADLINE: a cross-only change on one row walks one index, not two thousand", function()
		local s = scene.new({ rows = 1000 })
		s.width(2, 41) -- the warm-up: it RECORDS the payload under the current token
		s.width(3, 42)
		local before = s.stats()
		s.width(4, 43)
		--[[ `scanned=2` is the two walks over the ONE dirty child; at `7a17a43d` it was
			`2000`, the same two walks over every sibling. `skipped` is UNMOVED at 999 —
			it counts the placements the replay did not spend, which is a statement about
			`arrangeBody` and not about this loop — and `arranged`/`entries` say the same
			children were placed. ]]
		expect(line(s, before)).toBe("solves=1 scanned=3 skipped=999 arranged=5 entries=5")
		s.dispose()
	end)

	it("...and a LEAF text write, which is the arena's own drive", function()
		local s = scene.new({ rows = 1000 })
		s.text(2, "warm")
		s.text(3, "warm")
		local before = s.stats()
		s.text(4, "x")
		expect(line(s, before)).toBe("solves=1 scanned=4 skipped=999 arranged=5 entries=5")
		s.dispose()
	end)
end)

describe("D2c: what refuses the short list", function()
	it("THE SPLICE the scan was written for: a rebuilt array is a new token", function()
		--[[ OWED ROW 1, and the case the whole gate exists for. `deep_stack_scene`'s
			`foreach` arm splices a region BEFORE the rows, so an insert into it shifts
			every later index of `List`'s flat child list while `List`'s own mount
			children table — the term T15's carrier compares — is untouched. The insert
			is a STRUCTURAL refresh, so `render/layout_node` rebuilds the array and stamps
			a fresh token, and the replay on that tick cannot trust the indices it holds.
			The geometry half is the oracle below; this is the counter half. ]]
		local s = scene.new({ rows = 200, foreach = true })
		s.width(2, 41)
		s.width(3, 42)
		local before = s.stats()
		s.insertItem("k1")
		local afterInsert = line(s, before)
		before = s.stats()
		s.width(4, 43)
		expect(`{afterInsert} | {line(s, before)}`).toBe(
			"solves=1 scanned=1 skipped=0 arranged=205 entries=205 | solves=1 scanned=3 skipped=202 arranged=5 entries=5"
		)
		--[[ ...and the tick AFTER that one is indexed again: the array was kept, so the
			token the recording pass just wrote is still the node's own. ]]
		before = s.stats()
		s.width(5, 44)
		expect(line(s, before)).toBe("solves=1 scanned=3 skipped=202 arranged=3 entries=5")
		s.dispose()
	end)

	it("ZERO DIRTY CHILDREN after a splice still places every row that moved", function()
		--[[ THE WITNESS THE SCAN'S OWN HEADER NAMES. A removal from the spliced region
			leaves `List` with an unmoved box and NOTHING dirty among its children, so an
			arm that trusted its indices would return having placed nothing while every
			surviving row shifted up. What refuses it is the token — the structural tick
			rebuilt the array — and the proof is the geometry: the same surface rebuilt
			from scratch. ]]
		local s = scene.new({ rows = 60, foreach = true })
		s.insertItem("k1")
		s.insertItem("k2")
		s.width(2, 41)
		local before = s.stats()
		s.removeItem("k1")
		local removed = line(s, before)
		local shot = s.snapshot()
		s.dispose()
		local cold = scene.new({ rows = 60, foreach = true })
		cold.insertItem("k1")
		cold.insertItem("k2")
		cold.width(2, 41)
		cold.removeItem("k1")
		local coldShot = cold.snapshot()
		cold.dispose()
		expect(`scanned={string.match(removed, "scanned=(%d+)")} equal={tostring(shot == coldShot)}`).toBe(
			"scanned=1 equal=true"
		)
	end)
end)

--[[ ── THE DIFFERENTIAL ORACLE ─────────────────────────────────────────────────
	The switch-independent arm: `incremental = false` forces a FULL solve every refresh,
	where the replay is structurally unreachable. Nine views, the drive kinds the gate
	has terms for, with the structural splice interleaved so a short list built on one
	tick has to be refused on the next. `deep_stack_scene.snapshot` compares every live
	node's rect, hit rect, visibility, engine position and the public readers. ]]
describe("D2c oracle: byte-equal to a full solve, every view", function()
	local FIXTURES: { any } = {
		{ name = "plain", rows = 10 },
		{ name = "foreach", rows = 10, foreach = true },
		{ name = "wide", rows = 10, listWidth = true },
	}
	for _, fixture in FIXTURES do
		it(`{fixture.name}: rects and the public readers survive the indexed replay`, function()
			for _, view in device_views.VIEWS do
				local o = table.clone(fixture)
				o.viewport = { x = 0, y = 0, w = view.w, h = view.h }
				local a = scene.new(o)
				local c = scene.new((function(): any
					local q = table.clone(o)
					q.incremental = false
					return q
				end)())
				local label = `{fixture.name}/{view.id}`
				local function agree(step: string)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: {step} diverged from a FULL solve`, 0)
					end
				end
				agree("mount")
				--[[ A ROW FAR WIDER THAN THE LIST'S OFFER, driven before the loop so the
					container spends the run with an overflowing child. ]]
				a.width(2, 4000)
				c.width(2, 4000)
				agree("wide row")
				for step = 1, 3 do
					a.width(step + 1, 30 + step * 7)
					c.width(step + 1, 30 + step * 7)
					agree(`width {step}`)
					a.height(step + 1, 14 + step * 3)
					c.height(step + 1, 14 + step * 3)
					agree(`height {step}`)
					a.text(step + 2, `t{step}`)
					c.text(step + 2, `t{step}`)
					agree(`text {step}`)
					if fixture.foreach then
						a.insertItem(`k{step}`)
						c.insertItem(`k{step}`)
						agree(`insert {step}`)
						a.width(step + 1, 26 + step)
						c.width(step + 1, 26 + step)
						agree(`width after insert {step}`)
						a.removeItem(`k{step}`)
						c.removeItem(`k{step}`)
						agree(`remove {step}`)
						a.width(step + 1, 24 + step)
						c.width(step + 1, 24 + step)
						agree(`width after remove {step}`)
					end
					a.viewport(view.w - step, view.h - step)
					c.viewport(view.w - step, view.h - step)
					agree(`viewport {step}`)
				end
				a.dispose()
				c.dispose()
			end
		end)
	end
end)
