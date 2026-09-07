--!strict
--[[ ── THE COMPOSED RECT'S IDENTITY CHURNS EVERY COMMIT (RED-TEAM C-3) ──────────

	THE CONCERN, stated as it was raised. `render/rect_pass.apply` calls
	`invalidateOrigins()` TWICE per commit, unconditionally — once before the pass so
	nothing cached before it survives, once after so nothing cached DURING it does. So
	`render/rect_reads`' `composedCache` never survives a commit, and `rectOf` on a
	path under a coordinate-space host allocates a FRESH table every frame even when
	all four numbers stand still. `rect_reads`' own header says "~30 sites compare what
	this returns BY IDENTITY", names `slider.luau:183-185` as one, and warns that a
	per-frame identity change would become a signal write per reader per frame. D6a
	made the hosted population ~100x larger — every `ForEach` row and everything under
	it — so if that were true it would now be true of every list row in every game.

	IT IS NOT TRUE, AND THIS FILE IS THE MEASUREMENT THAT SAYS SO. The churn is REAL
	and pinned below; the CONSEQUENCE is nil, because the readers compare VALUES. The
	one the header names says so in its own words (`src/controls/slider.luau`):

	    -- Value equality, not identity. syncGeometry re-feeds this on EVERY refresh,
	    -- so an unchanged rect must be a no-op or both memos re-run each frame ...
	    -- Today the renderer's rectOf happens to hand back the same table until the
	    -- rect actually changes, so identity would also work — this does not depend
	    -- on that, because the day rectOf builds a fresh table the cost would appear
	    -- as a silent per-frame re-solve in every slider rather than as a failure.
	    local rectEq = rectLib.equal

	That day arrived with D6a, for every slider inside a list row, and the line above
	is what makes it a null. The pointer contract (`(path, pos, rectOf)` in
	`table_rows`, `level_picker`, `virtual_list_hosted`) reads x/y/w/h for hit math and
	is called per pointer EVENT rather than per frame, so it has no per-frame cost to
	have.

	SO THE MEASUREMENT IS THE DELIVERABLE, and it is kept because the null is only
	true while the readers stay value-comparing. A reader that starts comparing
	identity would make the surface re-solve forever, and this file's steady-tick pin
	is what would catch it — in the counter, not on a device. Mutation M1 (the
	slider's two rect signals switched to `a == b`) reddens all five cases.

	AND ONE RECORDED NULL, because it is a design fact about `rect_pass` rather than a
	gap here: deleting the FIRST of the two `invalidateOrigins()` calls reddens nothing
	(M2). The second one, at the tail of `apply`, already answers "nothing cached
	during this commit survives it", and on this file's observables that is the same
	answer. The first exists for the ordering property `rect_pass` states at its own
	site — a `rectOf` called from inside the span composing against a half-rewritten
	`lastRects` — which is a WITHIN-commit question this file does not ask.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src")
local UI = Facet.UI
local worldLib = require("./lib/world")

local ROWS = 200
-- the row the slider lives in. Any index does; one that is NOT first or last keeps
-- the row an ordinary member of the list rather than an edge case.
local SLIDER_ROW = 5

local function px(n: number): any
	return { type = "fixed", px = n }
end

--[[ ON `tests/lib/world.luau` RATHER THAN A HAND-ROLLED BUILDER, which is R12's own
	follow-up trigger (`tests/world_substrate.spec.luau`): the next spec file that adds
	a presenter builder migrates instead of writing a twenty-ninth copy of the same six
	lines in one of the two argument orders that collide. ]]
local function makeWorld(): any
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = 900, h = 700 },
		--[[ 200 rows of 30px in a 700px viewport is 6,000px of content, on purpose:
			the list has to be LONG enough to be the shape D6a serves, and this fixture
			is about coordinate spaces rather than about whether the screen fits. ]]
		overflowGuardOff = "a 200-row list is deliberately taller than the viewport: this fixture measures "
			.. "coordinate-space hosts, not containment",
	})
	local core = w.core
	local value = core:signal(0.5)
	local slider = Facet.Controls.Slider(core, { id = "Vol", value = value, min = 0, max = 1, step = 0.1 })
	local items = {}
	local rowValue = {}
	for i = 1, ROWS do
		rowValue[i] = core:signal(`row{i}`)
		items[i] = { id = `k{i}`, n = rowValue[i], slider = i == SLIDER_ROW }
	end
	local rows = core:signal(items)
	w.present(UI.Screen({
		id = "S",
		children = {
			UI.VStack({
				id = "List",
				padding = 0,
				gap = 1,
				children = {
					UI.ForEach({
						id = "Rows",
						items = rows,
						key = function(item: any)
							return item.id
						end,
						--[[ A TWO-CHILD ROW SPLICED INTO A STACK, which is exactly the shape
							`mount.markRow` stamps and `createOptsFor` turns into a coordinate
							space (D6a, `b844915e`). The slider takes the second child's place
							in ONE row, so it is a real control inside a real host and not a
							hand-built approximation of one. ]]
						row = function(item: any)
							return UI.HStack({
								id = "Row",
								padding = 0,
								gap = 2,
								height = px(30),
								children = {
									UI.Text({ id = "Name", textSize = 12, text = item.n }),
									if item.slider
										then slider.blueprint
										else UI.Box({ id = "Bar", width = px(40), height = px(6) }),
								},
							})
						end,
					}),
				},
			}),
		},
	}))
	w.value = value
	w.rows = rows
	w.items = items
	w.rowValue = rowValue
	return w
end

local ROW_PATH = `/S/List/Rows/[k{SLIDER_ROW}]/Row`
local SLIDER_PATH = `{ROW_PATH}/Vol`

describe("RED-TEAM C-3: the composed rect churns, and nothing downstream cares", function()
	it("THE PRECONDITION: the slider really is inside a coordinate-space host", function()
		--[[ NON-VACUITY, and it is the whole file's licence. A fixture whose rows were
			NOT hosts would take `rectOf`'s (0,0) early return and hand back the stored
			table every time — the measurement below would read "no churn" and prove
			nothing at all. ]]
		local w = makeWorld()
		expect(`row is a space host: {tostring(w.adapter.hostSpaceAt(ROW_PATH))}`).toBe("row is a space host: true")
		expect(`slider stores against: {tostring((w.adapter.hostOf(SLIDER_PATH) or {}).path)}`).toBe(
			`slider stores against: {ROW_PATH}`
		)
		expect(w.controller.rectOf(SLIDER_PATH) ~= nil).toBe(true)
	end)

	it("A STEADY TICK DOES NOT COMMIT AT ALL, so the epoch never bumps and the table is the same one", function()
		--[[ THE FIRST HALF OF THE CONCERN, RETIRED BY MEASUREMENT. "Every commit" is
			the right description of the bump and the wrong description of a settled
			frame: `presenter.refresh` on a surface where nothing is dirty does not
			SOLVE, so `rect_pass.apply` does not run, so `invalidateOrigins` does not
			fire and `composedCache` survives. Five bare ticks on a 200-host list cost
			zero solves and hand back the identical table. ]]
		local w = makeWorld()
		local st0 = w.controller.stats()
		local before = w.controller.rectOf(SLIDER_PATH)
		for _ = 1, 5 do
			w.pres.refresh()
		end
		local after = w.controller.rectOf(SLIDER_PATH)
		local st = w.controller.stats()
		expect(
			`solves={st.solves - st0.solves} rectWrites={st.rectWrites - st0.rectWrites} `
				.. `same table={tostring(before == after)} hosts={w.adapter.hostCount()}`
		).toBe("solves=0 rectWrites=0 same table=true hosts=200")
	end)

	it("THE CHURN IS REAL on a commit that moves something ELSE, and the numbers stand still", function()
		--[[ THE SECOND HALF, WHICH IS THE ONE THE REPORT MEANT. Any commit bumps the
			epoch — twice — whatever it moved, so a relabel two hundred rows away
			re-allocates the slider's composed rect while all four of its numbers are
			identical. That IS a fresh table per hosted path per commit per read, and it
			is what an identity-comparing reader would see as "the rect changed".

			The control is the SCREEN ROOT — a path with no space host above it and a rect
			nothing in this drive can move — which takes `rectOf`'s (0,0) early return and
			hands back the STORED table. Byte-identical at the allocation level, which is
			Plan C ruling R-6 and still holds. ]]
		local w = makeWorld()
		local before = w.controller.rectOf(SLIDER_PATH)
		local rootBefore = w.controller.rectOf("/S")
		w.rowValue[150]:set("relabelled")
		w.pres.refresh()
		local after = w.controller.rectOf(SLIDER_PATH)
		local rootAfter = w.controller.rectOf("/S")
		expect(`hosted same table: {tostring(before == after)}`).toBe("hosted same table: false")
		expect(
			`hosted same numbers: {tostring(
				before.x == after.x and before.y == after.y and before.w == after.w and before.h == after.h
			)}`
		).toBe("hosted same numbers: true")
		expect(`unhosted same table: {tostring(rootBefore == rootAfter)}`).toBe("unhosted same table: true")
	end)

	it("...AND THE CONSEQUENCE IS NIL: five churning commits cost five solves, not ten", function()
		--[[ THE NULL, READ OFF THE RUN. `presenter.refresh` feeds every contribution's
			`syncGeometry` on EVERY frame, so the slider's two rect signals are written
			five times here — each with a freshly allocated table, because each of these
			ticks commits. If either signal compared by IDENTITY, every write would
			notify, both dependent memos would re-run, each would emit a fresh dim table,
			and the surface would solve a SECOND time per tick and go on doing it: the
			"silent per-frame re-solve" `slider.luau` names in the comment above.

			Five drives, five solves, zero feedback solves. `propWrites` is read beside
			them so the zeros cannot be a surface that has stopped running: the five
			relabels really did reach paint. `rectWrites` is 0 because a label change
			inside a fixed-height row moves no box — which is exactly the frame an
			identity-comparing reader would have turned into work. ]]
		local w = makeWorld()
		local st0 = w.controller.stats()
		for i = 1, 5 do
			w.rowValue[150]:set(`churn{i}`)
			w.pres.refresh()
		end
		local st = w.controller.stats()
		expect(
			`solves={st.solves - st0.solves} feedback={st.feedbackSolves - st0.feedbackSolves} `
				.. `rectWrites={st.rectWrites - st0.rectWrites} propWrites={st.propWrites - st0.propWrites} `
				.. `hosts={w.adapter.hostCount()}`
		).toBe("solves=5 feedback=0 rectWrites=0 propWrites=5 hosts=200")
	end)

	it("...and the slider still tracks its row when the row DOES move", function()
		--[[ THE OTHER DIRECTION, so the null above cannot be a surface that has gone
			deaf. A row leaving above the slider moves the slider's host, and the
			composed rect the reader sees has to move with it — which is the epoch bump
			doing the job it exists for. The STORED rect stands still (it is
			host-relative) and the composed one does not, and that pair is the whole of
			D6a in two numbers. ]]
		local w = makeWorld()
		local storedBefore = w.adapter.liveNodes()[SLIDER_PATH].storedRect
		local composedBefore = w.controller.rectOf(SLIDER_PATH)
		local shorter = table.clone(w.items)
		table.remove(shorter, 1)
		w.rows:set(shorter)
		w.pres.refresh()
		local storedAfter = w.adapter.liveNodes()[SLIDER_PATH].storedRect
		local composedAfter = w.controller.rectOf(SLIDER_PATH)
		expect(`stored y moved: {tostring(storedAfter.y ~= storedBefore.y)}`).toBe("stored y moved: false")
		expect(`composed y moved: {tostring(composedAfter.y ~= composedBefore.y)}`).toBe("composed y moved: true")
	end)
end)
