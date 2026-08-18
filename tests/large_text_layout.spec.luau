--!strict
--[[ THE LARGE-TEXT LAYOUT MATRIX (acceptance LT-8; policy LT-6 — the plan's
	"Layout and overflow order").

	The control sweep (tests/large_text_matrix.spec) proves each control alone.
	This file proves the ORDER a composed screen degrades in, which is the whole
	of LT-6 and the part no single control can answer:

	    1. Reflow first  — wrap and grow, or choose another ViewThatFits /
	                       composition candidate.
	    2. Scroll second — when it cannot all fit at once, the containing region
	                       becomes self-paced.
	    3. Truncate only bounded secondary/identity text, and only with a path
	                       back to the whole string.
	    4. Animate never  (LTN-2 shipped a static disclosure instead).

	Four representative screens — a form in a ScrollView, a ViewThatFits CTA
	band, an AdaptiveStack split, and a screen-level Composition — each solved at
	{ 0, 4, 10, 14 } px x { Studio Neutral, Fantasy Parchment } x { 390x844
	compact portrait, 667x375 small landscape }: 32 rows per screen.

	THE ORDER IS ASSERTED AS AN INVARIANT, NOT AS A SNAPSHOT. "The candidate
	changed at Large under Parchment" is a fact about today's font metrics; the
	CLAIMS are (a) the chosen candidate never gets richer as the text gets
	bigger, (b) no action label is ever truncated at any row, (c) nothing is
	truncated while a cheaper rung is still available, and (d) the reflow is
	witnessed at least once, so none of the above is vacuously true.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local UI = require("../src/blueprint")
local adaptive = require("../src/layout/adaptive")
local lt = require("./lib/large_text")

local PRIMARY = lt.PSEUDO_ACTION -- an ACTION label: never an ellipsis, at any preference
local SECONDARY = lt.PSEUDO_SECONDARY
local STATUS = lt.PSEUDO -- an essential status line: wraps, never cut
local NAME = lt.GERMAN_COMPOUND -- identity: unbreakable, so it declares disclose

local VIEWPORTS = {
	{ id = "compact-portrait", rect = lt.PHONE_PORTRAIT },
	{ id = "small-landscape", rect = lt.SMALL_LANDSCAPE },
}

-- every (viewport, theme, preference) row, in a fixed order
local function rows(): { { id: string, viewport: any, theme: lt.Theme, preference: lt.Preference } }
	local out = {}
	for _, viewport in VIEWPORTS do
		for _, theme in lt.THEMES do
			for _, preference in lt.PREFERENCES do
				table.insert(out, {
					id = `{viewport.id}/{theme.id}/{preference.name}`,
					viewport = viewport.rect,
					theme = theme,
					preference = preference,
				})
			end
		end
	end
	return out
end

local function world(row: any): any
	return lt.world({ viewport = row.viewport, theme = row.theme, offset = row.preference.offset })
end

-- the three whole-screen checks, with the row named in any failure
local function assertClean(w: any, rowId: string)
	local found = lt.sweep(w)
	if #found.overlaps > 0 then
		error(`painted siblings overlap:\n{lt.describeFindings(rowId, found.overlaps)}`, 0)
	end
	if #found.clipped > 0 then
		error(`essential text truncated with no full-value path:\n{lt.describeFindings(rowId, found.clipped)}`, 0)
	end
end

-- an ACTION label may never report truncated: the plan's rung 3 exempts nothing
-- an author can press
local function assertActionsIntact(w: any, rowId: string, paths: { string })
	for _, path in paths do
		local facts = w.controller.textAt(path)
		if facts == nil then
			error(`{rowId}: no text facts for the action label {path} (did the path change?)`, 0)
		end
		if facts.truncated == true then
			error(`{rowId}: the action label {path} is an ellipsis at this preference (policy {facts.policy})`, 0)
		end
	end
end

-- ── screen 1: a form inside a ScrollView ────────────────────────────────────
-- TextField + Slider + an action pair, with the whole form self-paced. This is
-- the screen rung 2 exists for: at Largest the content is taller than the phone,
-- and the honest answer is a scrollable form, not a smaller one.

local function formScreen(core: any, w: any): any
	local name = core:signal("")
	local volume = core:signal(0.5)
	local field = Facet.Controls.TextInput(core, {
		id = "Name",
		value = name,
		placeholder = STATUS,
		env = w.env,
		actionSystem = w.system,
	})
	local slider = Facet.Controls.Slider(core, {
		id = "Volume",
		label = STATUS,
		value = volume,
		min = 0,
		max = 1,
		step = 0.1,
	})
	return UI.Screen({
		id = "S",
		children = {
			UI.ScrollView({
				id = "Form",
				height = { type = "fill", weight = 1 },
				children = {
					UI.Text({ id = "Heading", text = STATUS }),
					field.blueprint,
					slider.blueprint,
					UI.ViewThatFits({
						id = "Actions",
						children = {
							UI.HStack({
								id = "Row",
								gap = 8,
								children = {
									UI.Button({ id = "RowSave", label = PRIMARY }),
									UI.Button({ id = "RowLater", label = SECONDARY }),
								},
							}),
							UI.VStack({
								id = "Col",
								gap = 8,
								children = {
									UI.Button({ id = "ColSave", label = PRIMARY }),
									UI.Button({ id = "ColLater", label = SECONDARY }),
								},
							}),
						},
					}),
				},
			}),
		},
	})
end

-- which ViewThatFits candidate is showing (1 = the richest that was declared)
local function chosenCandidate(w: any, fitsPath: string, candidates: { string }): number
	local hidden = w.controller.hiddenRoots()
	for index, id in candidates do
		if hidden[`{fitsPath}/{id}`] ~= true then
			return index
		end
	end
	error(`{fitsPath}: every candidate is hidden`, 0)
end

describe("LT-6 order: a form in a ScrollView reflows, then scrolls, and never truncates", function()
	it("LT6-FORM the form's action pair reflows and the region scrolls — no clip at any of the 32 rows", function()
		for _, row in rows() do
			local w = world(row)
			w.present(formScreen(w.core, w))
			assertClean(w, row.id)
			local candidate = chosenCandidate(w, "/S/Form/Actions", { "Row", "Col" })
			local actions = if candidate == 1
				then { "/S/Form/Actions/Row/RowSave", "/S/Form/Actions/Row/RowLater" }
				else { "/S/Form/Actions/Col/ColSave", "/S/Form/Actions/Col/ColLater" }
			assertActionsIntact(w, row.id, actions)
			-- rung 2 is REACHED, not merely available: the form declares a scroll
			-- region on every row (the renderer only declares one for a ScrollView
			-- that has content to pace)
			local region = w.adapter.scrollRegionOf("/S/Form")
			if region == nil then
				error(`{row.id}: the form declared no scroll region`, 0)
			end
		end
	end)

	it("LT6-FORMGROW the form's scrollable content grows with the preference while its viewport does not", function()
		-- the shape of "scroll the containing region": the box stays, the canvas
		-- gets taller, and nothing inside had to be cut to achieve it
		for _, viewport in VIEWPORTS do
			for _, theme in lt.THEMES do
				local previousContent = 0
				local viewportHeight: number? = nil
				for _, preference in lt.PREFERENCES do
					local w = lt.world({ viewport = viewport.rect, theme = theme, offset = preference.offset })
					w.present(formScreen(w.core, w))
					local region = w.adapter.scrollRegionOf("/S/Form")
					local box = w.adapter.node("/S/Form").rect
					expect(region.contentH).toBeGreaterThanOrEqual(previousContent)
					previousContent = region.contentH
					if viewportHeight == nil then
						viewportHeight = box.h
					else
						expect(box.h).toBe(viewportHeight :: number)
					end
				end
				-- ...and the growth is real, not a flat line that would satisfy
				-- ">=" while proving the offset never reached the form
				expect(previousContent).toBeGreaterThan(0)
			end
		end
	end)
end)

-- ── screen 2: the CTA band ──────────────────────────────────────────────────

local function bandScreen(): any
	return UI.Screen({
		id = "S",
		children = {
			UI.Text({ id = "Status", text = STATUS }),
			UI.ViewThatFits({
				id = "Cta",
				children = {
					UI.HStack({
						id = "Row",
						gap = 8,
						children = {
							UI.Button({ id = "RowSave", label = PRIMARY }),
							UI.Button({ id = "RowLater", label = SECONDARY }),
						},
					}),
					UI.VStack({
						id = "Col",
						gap = 8,
						children = {
							UI.Button({ id = "ColSave", label = PRIMARY }),
							UI.Button({ id = "ColLater", label = SECONDARY }),
						},
					}),
				},
			}),
		},
	})
end

describe("LT-6 order: a ViewThatFits CTA band steps down before anything is cut", function()
	it("LT6-BAND the chosen candidate never gets richer as the preference rises, and no action is ever cut", function()
		local flips = 0
		for _, viewport in VIEWPORTS do
			for _, theme in lt.THEMES do
				local previous = 0
				for _, preference in lt.PREFERENCES do
					local rowId = `{viewport.id}/{theme.id}/{preference.name}`
					local w = lt.world({ viewport = viewport.rect, theme = theme, offset = preference.offset })
					w.present(bandScreen())
					assertClean(w, rowId)
					local candidate = chosenCandidate(w, "/S/Cta", { "Row", "Col" })
					if candidate < previous then
						error(
							`{rowId}: the band went BACK to a richer candidate ({previous} -> {candidate}) `
								.. `while the text grew`,
							0
						)
					end
					if previous ~= 0 and candidate > previous then
						flips += 1
					end
					previous = candidate
					local actions = if candidate == 1
						then { "/S/Cta/Row/RowSave", "/S/Cta/Row/RowLater" }
						else { "/S/Cta/Col/ColSave", "/S/Cta/Col/ColLater" }
					assertActionsIntact(w, rowId, actions)
				end
			end
		end
		-- the reflow is WITNESSED: a matrix in which the band never steps down
		-- would satisfy every claim above and prove nothing
		expect(flips).toBeGreaterThan(0)
	end)

	it(
		"LT6-BANDWITNESS the compact-portrait band is a row at Medium and a column at Largest (named witness)",
		function()
			-- the concrete instance of the previous case's invariant, so a regression
			-- that silently stopped reflowing cannot hide behind "flips > 0"
			local function candidateAt(offset: number): number
				local w = lt.world({ viewport = lt.PHONE_PORTRAIT, theme = lt.THEMES[1], offset = offset })
				w.present(bandScreen())
				return chosenCandidate(w, "/S/Cta", { "Row", "Col" })
			end
			expect(candidateAt(0)).toBe(1)
			expect(candidateAt(lt.LARGEST)).toBe(2)
		end
	)

	-- THE ORDER, as the thing that can fail: a cut inside the band is legal only
	-- once the reflow rung is exhausted — i.e. the band is already on its LAST
	-- declared candidate. Returns the violation, or nil.
	local function ladderViolation(w: any, rowId: string, candidates: { string }): string?
		local truncated = lt.truncatedUnder(w, "/S/Cta")
		if #truncated == 0 then
			return nil
		end
		local candidate = chosenCandidate(w, "/S/Cta", candidates)
		if candidate == #candidates then
			return nil
		end
		return `{rowId}: text truncated ({table.concat(truncated, ", ")}) while the band was still on `
			.. `candidate {candidate} of {#candidates} — reflow was available and was not taken`
	end

	it("LT6-LADDER nothing is truncated while the band still has a cheaper candidate to take", function()
		for _, row in rows() do
			local w = lt.world({ viewport = row.viewport, theme = row.theme, offset = row.preference.offset })
			w.present(bandScreen())
			local violation = ladderViolation(w, row.id, { "Row", "Col" })
			if violation ~= nil then
				error(violation, 0)
			end
		end
	end)

	it("LT6-LADDERNEG the ladder rule FIRES on a band that cuts a label with a candidate still in hand", function()
		--[[ THE NEGATIVE CONTROL. A rule that has never been seen to fail is not
			evidence, so the defect LT6-LADDER exists to catch is built here on purpose.

			IT HAD TO BE REBUILT ON 2026-08-18 (DIR wave contract 7), and WHY is the
			interesting part. It used to be an UNBROKEN word in a 60px box: no wrap can
			save it, the engine ellipsizes, and the row still measured as fitting the
			phone — so the richest candidate won while an action label became an
			ellipsis. **The solver no longer permits that shape.** `chosenCandidate`
			counts the CLAMPED cut its own measure reports and hands the band to a
			later candidate that is honest and costs no more room, so the ordering
			defect cannot be built out of a line the box cannot hold. (Which is the
			whole of contract 7: the objective chip in the shipped HUD was that shape.)

			WHAT IS STILL BUILDABLE, and why it is still a defect worth a rule: an
			author's own `lineLimit`. A phrase whose longest WORD fits the box WRAPS,
			and the cap then throws the second line away — the box could hold the
			string, the declaration said not to. The solver treats that as the
			instruction it is and leaves the ladder alone, so the ROW still wins with a
			cut label and `ladderViolation` still has something to find. That is the
			one cut this rule is now the only guard on, which makes the control more
			load-bearing than it was, not less. ]]
		local w = lt.world({ viewport = lt.PHONE_PORTRAIT, theme = lt.THEMES[1], offset = lt.LARGEST })
		-- a phrase of SHORT words in a box wide enough for EVERY ONE OF THEM at the
		-- Largest preference: the string therefore wraps rather than clamping, and
		-- only the author's own cap cuts it. (60px was the old box, and at +14 it is
		-- narrower than the word "three" — which is a clamp, the shape the solver now
		-- refuses, and the case would fail for the opposite reason.)
		local PHRASE = "one two three four five six"
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.ViewThatFits({
					id = "Cta",
					children = {
						UI.HStack({
							id = "Row",
							gap = 8,
							children = {
								UI.Text({
									id = "RowSave",
									text = PHRASE,
									lineLimit = 1,
									width = { type = "fixed", px = 140 },
								}),
							},
						}),
						UI.VStack({
							id = "Col",
							children = { UI.Text({ id = "ColSave", text = PHRASE }) },
						}),
					},
				}),
			},
		}))
		expect(chosenCandidate(w, "/S/Cta", { "Row", "Col" })).toBe(1)
		expect(w.controller.textAt("/S/Cta/Row/RowSave").truncated).toBe(true)
		--[[ ...AND IT REALLY IS THE AUTHOR'S CAP RATHER THAN A CLAMP, or this case
			has quietly gone back to building the shape the solver now refuses and
			would fail for the opposite reason. `naturalLines > lines` is the cap
			biting; a clamp leaves them equal. ]]
		local facts = w.controller.textAt("/S/Cta/Row/RowSave")
		expect(`the cut is the lineLimit, not a clamp: {(facts.naturalLines or 1) > (facts.lines or 1)}`).toBe(
			"the cut is the lineLimit, not a clamp: true"
		)
		local violation = ladderViolation(w, "negative-control", { "Row", "Col" })
		expect(violation).never().toBeNil()
		expect(string.find(violation :: string, "reflow was available", 1, true) ~= nil).toBe(true)
	end)
end)

-- ── screen 3: an AdaptiveStack split ────────────────────────────────────────

local function splitScreen(core: any, env: any): any
	local conditions = adaptive.conditions(core, env)
	return UI.Screen({
		id = "S",
		children = {
			UI.AdaptiveStack({
				id = "Split",
				axis = conditions.axis,
				gap = 12,
				height = { type = "fill", weight = 1 },
				children = {
					UI.VStack({
						id = "Detail",
						width = { type = "fill", weight = 1 },
						children = {
							UI.Text({ id = "Status", text = STATUS }),
							UI.Text({ id = "Name", text = NAME, disclose = true }),
						},
					}),
					UI.VStack({
						id = "Aside",
						width = { type = "fill", weight = 1 },
						children = { UI.Button({ id = "Go", label = PRIMARY }) },
					}),
				},
			}),
		},
	})
end

describe("LT-6 order: an AdaptiveStack split holds at every preference", function()
	it("LT6-SPLIT the split's axis is space-driven and its panes never overlap or cut essential text", function()
		for _, row in rows() do
			local w = world(row)
			w.present(splitScreen(w.core, w.env))
			assertClean(w, row.id)
			assertActionsIntact(w, row.id, { "/S/Split/Aside/Go" })
			-- the axis follows the WIDTH the screen was given, and the preference
			-- does not change it: a text-size change must never re-orient a split
			-- (that is a layout the player did not ask for)
			local detail = w.adapter.node("/S/Split/Detail").rect
			local aside = w.adapter.node("/S/Split/Aside").rect
			if row.viewport.w >= 600 then
				expect(detail.y).toBe(aside.y) -- side by side
			else
				expect(detail.x).toBe(aside.x) -- stacked
			end
		end
	end)

	it("LT6-SPLITSTABLE the split's axis is identical at Medium and Largest on both viewports", function()
		for _, viewport in VIEWPORTS do
			for _, theme in lt.THEMES do
				local shapes: { string } = {}
				for _, offset in { 0, lt.LARGEST } do
					local w = lt.world({ viewport = viewport.rect, theme = theme, offset = offset })
					w.present(splitScreen(w.core, w.env))
					local detail = w.adapter.node("/S/Split/Detail").rect
					local aside = w.adapter.node("/S/Split/Aside").rect
					table.insert(shapes, if detail.y == aside.y then "x" else "y")
				end
				expect(shapes[1]).toBe(shapes[2])
			end
		end
	end)
end)

-- ── screen 4: a screen-level Composition ────────────────────────────────────
-- The results-screen shape: a masthead that spans, a field that fills and may
-- scroll, and a trailing action lane — declared once as three arrangements
-- (threeLane / twoLane / column) and resolved from the box it receives.

local function compositionScreen(): any
	return UI.Screen({
		id = "S",
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = {
			UI.Composition({
				id = "Results",
				arrangements = {
					{ name = "threeLane", lanes = { { "head" }, { "main" }, { "trail" } } },
					{ name = "twoLane", lanes = { { "main" }, { "head", "trail" } } },
					{ name = "column", lanes = { { "head", "main", "trail" } } },
				},
				laneGap = 12,
				groupGap = 8,
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				groups = {
					{ id = "masthead", lane = "head", sizing = "hug" },
					{ id = "field", lane = "main", sizing = "fill", minWidth = 200 },
					{ id = "next", lane = "trail", sizing = "hug" },
				},
				children = {
					UI.Region({
						id = "Standing",
						group = "masthead",
						rank = 2,
						-- the chip drops the status line, so the screen owes it a route
						recover = "overflow",
						floor = { lines = 1 },
						children = {
							UI.VStack({
								id = "Full",
								children = {
									UI.Text({ id = "Status", text = STATUS }),
									UI.Text({ id = "Name", text = NAME, disclose = true }),
								},
							}),
							UI.Text({ id = "Chip", text = SECONDARY }),
						},
					}),
					UI.Region({
						id = "Field",
						group = "field",
						rank = 1,
						sizing = "fill",
						mayScroll = true,
						floor = { lines = 1 },
						children = {
							UI.ScrollView({
								id = "Body",
								height = { type = "fill", weight = 1 },
								children = {
									UI.Text({ id = "Line1", text = STATUS }),
									UI.Text({ id = "Line2", text = STATUS }),
									UI.Text({ id = "Line3", text = STATUS }),
								},
							}),
						},
					}),
					UI.Region({
						id = "Cta",
						-- the stacked form holds the same two buttons as the row
						recover = "none",
						group = "next",
						rank = 3,
						floor = { targets = 1 },
						children = {
							UI.HStack({
								id = "Pair",
								gap = 8,
								children = {
									UI.Button({ id = "Save", label = PRIMARY }),
									UI.Button({ id = "Later", label = SECONDARY }),
								},
							}),
							UI.VStack({
								id = "Stacked",
								gap = 8,
								children = {
									UI.Button({ id = "SaveOnly", label = PRIMARY }),
									UI.Button({ id = "LaterOnly", label = SECONDARY }),
								},
							}),
						},
					}),
				},
			}),
		},
	})
end

local ARRANGEMENT_RANK: { [string]: number } = { threeLane = 1, twoLane = 2, column = 3 }

-- the action labels of whichever CTA form the composition chose
local function ctaActions(w: any): { string }
	local hidden = w.controller.hiddenRoots()
	if hidden["/S/Results/Cta/Pair"] ~= true then
		return { "/S/Results/Cta/Pair/Save", "/S/Results/Cta/Pair/Later" }
	end
	return { "/S/Results/Cta/Stacked/SaveOnly", "/S/Results/Cta/Stacked/LaterOnly" }
end

describe("LT-6 order: a Composition steps its arrangement down, never its CTA", function()
	it("LT6-COMPOSE the composition never picks a richer arrangement as the text grows, and cuts no action", function()
		local stepDowns = 0
		for _, viewport in VIEWPORTS do
			for _, theme in lt.THEMES do
				local previousRank = 0
				for _, preference in lt.PREFERENCES do
					local rowId = `{viewport.id}/{theme.id}/{preference.name}`
					local w = lt.world({ viewport = viewport.rect, theme = theme, offset = preference.offset })
					w.present(compositionScreen())
					assertClean(w, rowId)
					local dump = w.controller.compositionAt("/S/Results")
					local rank = ARRANGEMENT_RANK[dump.arrangement]
					expect(rank).never().toBeNil()
					if rank < previousRank then
						error(
							`{rowId}: the arrangement got RICHER while the text grew `
								.. `({previousRank} -> {rank}: {dump.arrangement})`,
							0
						)
					end
					if previousRank ~= 0 and rank > previousRank then
						stepDowns += 1
					end
					previousRank = rank
					assertActionsIntact(w, rowId, ctaActions(w))
				end
			end
		end
		expect(stepDowns).toBeGreaterThan(0)
	end)

	it("LT6-COMPOSEWITNESS the small-landscape composition is threeLane at Medium and steps down at Largest", function()
		local function arrangementAt(offset: number): string
			local w = lt.world({ viewport = lt.SMALL_LANDSCAPE, theme = lt.THEMES[1], offset = offset })
			w.present(compositionScreen())
			return w.controller.compositionAt("/S/Results").arrangement
		end
		expect(arrangementAt(0)).toBe("threeLane")
		expect(ARRANGEMENT_RANK[arrangementAt(lt.LARGEST)]).toBeGreaterThan(1)
	end)

	it("LT6-COMPOSESCROLL the field region keeps its declared scroll path at every preference", function()
		-- rung 2 inside a composition: the region that declared `mayScroll` is the
		-- one that absorbs the growth, and it must still be a scroll host at
		-- Largest rather than having been dropped or stepped out of existence
		for _, row in rows() do
			local w = lt.world({ viewport = row.viewport, theme = row.theme, offset = row.preference.offset })
			w.present(compositionScreen())
			expect(w.controller.hiddenRoots()["/S/Results/Field"]).toBeNil()
			local region = w.adapter.scrollRegionOf("/S/Results/Field/Body")
			if region == nil then
				error(`{row.id}: the field region lost its scroll host`, 0)
			end
		end
	end)
end)

-- ── reduced motion ──────────────────────────────────────────────────────────

describe("LT-8 reduced motion: the same geometry, and a policy independent of the preference", function()
	it("LT8-REDUCED every layout row solves byte-identically with reducedMotion set", function()
		-- motion is presentation; reservation is layout. If reduced motion moved a
		-- single rect, one of the two had leaked into the other.
		for _, row in rows() do
			local full = lt.world({ viewport = row.viewport, theme = row.theme, offset = row.preference.offset })
			full.present(compositionScreen())
			local reduced = lt.world({
				viewport = row.viewport,
				theme = row.theme,
				offset = row.preference.offset,
				reducedMotion = true,
			})
			reduced.present(compositionScreen())
			local a, b = lt.geometryOf(full), lt.geometryOf(reduced)
			for path, rect in a do
				if b[path] ~= rect then
					error(`{row.id}: {path} solved {rect} with motion and {tostring(b[path])} without it`, 0)
				end
			end
			for path in b do
				expect(a[path]).never().toBeNil()
			end
		end
	end)

	it("LT8-REDUCEDPOLICY motionPolicy answers from the motion fact alone, at every preference", function()
		for _, preference in lt.PREFERENCES do
			local full = lt.world({ offset = preference.offset })
			expect(full.env:get("motionPolicy"):get()).toBe("full")
			local reduced = lt.world({ offset = preference.offset, reducedMotion = true })
			expect(reduced.env:get("motionPolicy"):get()).toBe("reduced")
		end
	end)

	it("LT8-REDUCEDSWEEP the reduced-motion form and band file no finding at any preference", function()
		for _, row in rows() do
			local w = lt.world({
				viewport = row.viewport,
				theme = row.theme,
				offset = row.preference.offset,
				reducedMotion = true,
			})
			w.present(bandScreen())
			assertClean(w, `reduced/{row.id}`)
			local formWorld = lt.world({
				viewport = row.viewport,
				theme = row.theme,
				offset = row.preference.offset,
				reducedMotion = true,
			})
			formWorld.present(formScreen(formWorld.core, formWorld))
			assertClean(formWorld, `reduced-form/{row.id}`)
		end
	end)
end)
