--!strict
--[[ A COVER'S TOUCH FLOOR STOPS AT THE FIRST THING IT COULD STEAL (DIR5 review H1).

	THE DEFECT, MEASURED. A control under the effective touch floor gets an
	invisible hit expander inflated around its solved rect
	(`render/commit_walks.hitRects`). For a chevron that is a ~44px column at the
	region's trailing edge and it overhangs nothing that matters. For a COVER it is
	the region's WHOLE BOX — so a 44px floor on a 20px-tall region necessarily
	leaves the region by 12px above and below, ACROSS THE FULL WIDTH, and the
	engine delivers input to the topmost interactive object only. Measured in
	`region_expand.spec`'s own `ringScreen` fixture at 390x150, before this rule:

	    cover rect  0,46 390x20     cover floor  0,34 390x44
	    /S/C/Before/First  80x46  overlap 80x12 =  960 px2  (26% of the button)
	    /S/C/After/Last    69x46  overlap 69x12 =  828 px2  (26% of the button)

	A press in the bottom 12px of `First`, or the top 12px of `Last`, opened the
	Clock's expand plate instead of pressing the button the player aimed at. That
	is the one-gesture-two-meanings collision R18 exists to prevent, arriving
	ACROSS a region boundary instead of inside one.

	THE RULE, AND WHY IT IS A GROWTH RATHER THAN A BOX. R18's ruling splits by what
	is UNDERNEATH: the 44px floor is EXEMPT over PASSIVE content — it is the F1
	accessibility floor and the convention every platform ships — and BANNED over
	INTERACTIVE content. So a cover's floor GROWS, one side at a time, and each side
	stops at the first pressable thing outside its own region. It may never hand
	back less than the node already paints.

	CLAMPING INTO THE REGION BOX WAS TRIED FIRST AND THE MEASUREMENT REFUSED IT. On
	the shipped HUD demo three stepped-down covers whose floors reach nothing at all
	lost the floor purely because their regions are 21-30px tall, and
	`overflow_sweep`'s "no dead-end compact" guard reported it on five viewports — a
	route the thumb cannot land on is a route on paper. Both directions are defects,
	and both have cases below.

	WHY NOT `effectiveHitFloor`. The other candidate fix was to hand that function
	the NODE instead of `node.class` and return nil for a cover. It is refused:
	`syncZOrder` calls the same function to reserve the expander's z slot, and
	NM-H4a (live 2026-08-17) fixed a whole-band paint defect by making that
	reservation a function of the CLASS rather than of the current state. A
	node-aware floor would move every z below every cover and put the reservation
	back on the history it was taken off.

	WHAT DOES NOT CHANGE, and it is the half a clamp is easiest to get wrong: an
	ordinary sub-floor control — the F1 case, director-approved — keeps its FULL
	floor, including the part that leaves its parent. This file's control case is
	that one, and the mutation that over-applies the clamp reddens it.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local commit_walks = require("../src/render/commit_walks")
local worldLib = require("./lib/world")

--[[ `region_expand.spec`'s `ringScreen(false)`, rebuilt here because it is local
	to that file. Its geometry is pinned below against the review's own
	measurement, so this is provably the same fixture rather than a lookalike: a
	stop BEFORE the region and a stop AFTER it, and a four-line rich form that has
	to be genuinely bigger than the compact one or the ladder never steps down. ]]
local function ringScreen(): any
	return UI.Screen({
		id = "S",
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = {
			UI.Composition({
				id = "C",
				arrangements = { "column" },
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				groups = { { id = "body", lane = "main", sizing = "fill" } },
				children = {
					UI.Region({
						id = "Before",
						group = "body",
						rank = 1,
						children = { UI.Button({ id = "First", label = "first", onActivate = function() end }) },
					}),
					UI.Region({
						id = "Clock",
						group = "body",
						rank = 3,
						recover = "overflow",
						children = {
							UI.VStack({
								id = "Full",
								children = {
									UI.Text({ id = "Timer", text = "2:14", textSize = 16 }),
									UI.Text({ id = "Scores", text = "12 - 9", textSize = 16 }),
									UI.Text({ id = "Home", text = "Home 12", textSize = 16 }),
									UI.Text({ id = "Away", text = "Away 9", textSize = 16 }),
								},
							}),
							UI.Text({ id = "Compact", text = "2:14", textSize = 16 }),
						},
					}),
					UI.Region({
						id = "After",
						group = "body",
						rank = 2,
						children = { UI.Button({ id = "Last", label = "last", onActivate = function() end }) },
					}),
				},
			}),
		},
	})
end

local COVER = "/S/C/Clock/Expand"
local REGION = "/S/C/Clock"

local function overlapArea(a: any, b: any): number
	if a == nil or b == nil then
		return 0
	end
	local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	if ox <= 0 or oy <= 0 then
		return 0
	end
	return ox * oy
end

local function steppedDown(): any
	local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 150 } })
	w.present(ringScreen(), { initialFocus = "none" })
	return w
end

describe("a cover's touch floor takes nothing pressable (H1)", function()
	it("the fixture is the review's: a standing COVER over the region's whole box", function()
		--[[ THE INSTRUMENT BEFORE THE CLAIM. Every number below is meaningless if
			the ladder did not step down, if the affordance came out a chevron, or if
			the two neighbours are not where the review measured them. ]]
		local w = steppedDown()
		expect(w.controller.compositionAt("/S/C").regions[2].activeForm).toBe(2)
		local cover = w.adapter.node(COVER)
		local region = w.adapter.node(REGION)
		expect(cover).never().toBeNil()
		expect(`{cover.rect.x},{cover.rect.y} {cover.rect.w}x{cover.rect.h}`).toBe("0,46 390x20")
		expect(`{region.rect.x},{region.rect.y} {region.rect.w}x{region.rect.h}`).toBe("0,46 390x20")
		local first = w.adapter.node("/S/C/Before/First")
		local last = w.adapter.node("/S/C/After/Last")
		expect(`first {first.rect.w}x{first.rect.h}`).toBe("first 80x46")
		expect(`last {last.rect.w}x{last.rect.h}`).toBe("last 69x46")
	end)

	it("it takes NO part of either neighbouring Button — 960 and 828 px2 become 0", function()
		local w = steppedDown()
		local hit = w.adapter.hitRectOf(COVER)
		local first = w.adapter.node("/S/C/Before/First")
		local last = w.adapter.node("/S/C/After/Last")
		expect(`First {overlapArea(hit, first.rect)} px2`).toBe("First 0 px2")
		expect(`Last {overlapArea(hit, last.rect)} px2`).toBe("Last 0 px2")
	end)

	it("...and in THIS fixture there is no room at all, so it grows nothing", function()
		--[[ THE GENERAL FORM, so the case above cannot pass by the two neighbours
			having moved. `ringScreen`'s regions are edge to edge — the composition
			gives them no gutter — so both vertical asks are refused entirely and the
			cover is left with the box it already paints. That is what retracts the
			expander: an expander equal to its host's rect is a transparent duplicate
			of it. ]]
		local w = steppedDown()
		local hit = w.adapter.hitRectOf(COVER)
		local region = w.adapter.node(REGION).rect
		local outside = 0
		if hit ~= nil then
			outside = (hit.w * hit.h) - overlapArea(hit, region)
		end
		expect(`outside its region: {outside} px2, expander: {tostring(hit)}`).toBe(
			"outside its region: 0 px2, expander: nil"
		)
	end)

	it("no framework node of the affordance reaches any author node in another region", function()
		--[[ THE WHOLE AFFORDANCE, not just the Button: the cover's own subtree and
			both of its rects, against every author node outside the Clock region. ]]
		local w = steppedDown()
		local offenders: { string } = {}
		for _, path in w.adapter.paths() do
			-- the affordance's own region, and its ANCESTORS, which contain it by
			-- construction: neither is a node in another region
			if string.find(path, REGION, 1, true) == 1 or string.find(COVER, path, 1, true) == 1 then
				continue
			end
			local n = w.adapter.node(path)
			if n == nil or n.rect == nil or n.rect.w <= 0 or n.rect.h <= 0 then
				continue
			end
			for _, markPath in { COVER, `{COVER}/Zone` } do
				local mark = w.adapter.node(markPath)
				if mark == nil then
					continue
				end
				for _, markRect in { mark.rect, w.adapter.hitRectOf(markPath) } do
					if overlapArea(markRect, n.rect) > 0 then
						table.insert(offenders, `{markPath} over {path}`)
					end
				end
			end
		end
		expect(table.concat(offenders, " | ")).toBe("")
	end)
end)

describe("a cover with ROOM keeps its whole floor — the other arm of R18", function()
	--[[ THE ARM THAT MADE THE FIRST RULE WRONG, and it is a SHIPPED fixture rather
		than a constructed one. `examples/gallery/scenarios/hud` steps three regions
		down at 359x718 and every one of them takes a cover: `Tasks` at 75x23,
		`Health` at 44x30, `Clock` at 80x30 — all three under the touch floor on at
		least one axis, and NOT ONE of their un-clamped floors reaches an interactive
		node outside its own region, because those regions have room around them.

		An unconditional clamp to the region box took the F1 floor off all three, and
		`overflow_sweep`'s "no dead-end compact" guard reported it on five viewports
		("a route the thumb cannot land on is a route on paper"). R18's ruling is by
		what is UNDERNEATH, not by a box: exempt over passive content, banned over
		interactive. So these three keep 44px and `ringScreen`'s cover does not. ]]
	local hud = require("../examples/gallery/scenarios/hud") :: any

	local function mountHud(vw: number, vh: number): any
		local w = worldLib.new({
			viewport = { x = 0, y = 0, w = vw, h = vh },
			overflowGuardOff = "the containment sweep for this scenario is `tests/overflow_sweep.spec`'s; this case reads hit geometry only",
		})
		local built = hud.build({
			Facet = require("../src") :: any,
			core = w.core,
			env = w.env,
			actionSystem = w.system,
			presenter = w.pres,
			adapter = w.adapter,
			record = function() end,
			bindResourceTransport = function()
				return function() end
			end,
		})
		built.handle = w.pres.present(built.screen, built.present)
		w.pres.refresh()
		w.built = built
		return w
	end

	it("the HUD's three stepped-down covers keep 44px, because their floors reach nothing", function()
		local w = mountHud(359, 718)
		local dump = w.built.handle.controller.compositionAt("/HudScreen/Hud")
		local seen: { string } = {}
		for _, r in dump.regions do
			if (r.activeForm or 0) <= 1 then
				continue
			end
			local path = `{r.id}/Expand`
			local node = w.adapter.node(path)
			local hit = w.adapter.hitRectOf(path)
			if node == nil or node.rect.w <= 0 then
				continue
			end
			-- the population: a cover under the floor on at least one axis
			if node.rect.w >= 44 and node.rect.h >= 44 then
				continue
			end
			table.insert(seen, `{r.id} {if hit ~= nil then `{hit.w}x{hit.h}` else "NO FLOOR"}`)
		end
		expect(table.concat(seen, " | ")).toBe(
			"/HudScreen/Hud/Tasks 75x44 | /HudScreen/Hud/Health 44x44 | /HudScreen/Hud/Clock 80x44"
		)
	end)
end)

describe("the F1 accessibility floor is UNTOUCHED by the clamp", function()
	--[[ THE CONTROL CASE, and it is the half a clamp is easiest to get wrong. R18
		and F1 both say a sub-44px control gets a 44px target, and the director
		approved that floor extending over adjacent passive content — clamping it to
		the control's own box would put a below-floor target on the one thing on the
		row that exists to be tapped. Only a COVER is clamped, and only to its own
		region, because only a cover's floor is the width of a whole region. ]]
	local function subFloorScreen(): any
		return UI.Screen({
			id = "F",
			padding = 8,
			children = {
				UI.VStack({
					id = "List",
					gap = 0,
					children = {
						UI.Button({
							id = "Small",
							label = "s",
							width = { type = "fixed", px = 20 },
							height = { type = "fixed", px = 20 },
							onActivate = function() end,
						}),
						UI.Button({
							id = "Below",
							label = "b",
							width = { type = "fixed", px = 120 },
							height = { type = "fixed", px = 40 },
							onActivate = function() end,
						}),
					},
				}),
			},
		})
	end

	--[[ ...AND ITS NEIGHBOUR HAS TO BE IN ANOTHER SUBTREE. The first version of
		this control put the sub-floor Button and the row it overhangs in ONE stack,
		and applying the cover rule to every expander reddened nothing (mutation
		B-M2): a blocker contained in the node's own host skips on all four sides by
		construction, so the two arms of the rule were never told apart. The pair
		below sits in two columns, so the small Button's floor really does reach a
		pressable rect in another subtree — the exact condition that retracts a
		cover's floor, and the exact condition an ordinary control is exempt from. ]]
	local function crossHostScreen(): any
		return UI.Screen({
			id = "X",
			padding = 8,
			children = {
				UI.HStack({
					id = "Row",
					gap = 4,
					children = {
						UI.VStack({
							id = "LeftCol",
							children = {
								UI.Button({
									id = "Tiny",
									label = "t",
									width = { type = "fixed", px = 20 },
									height = { type = "fixed", px = 20 },
									onActivate = function() end,
								}),
							},
						}),
						UI.VStack({
							id = "RightCol",
							children = {
								UI.Button({
									id = "Neighbour",
									label = "n",
									width = { type = "fixed", px = 80 },
									height = { type = "fixed", px = 60 },
									onActivate = function() end,
								}),
							},
						}),
					},
				}),
			},
		})
	end

	it("a sub-floor Button keeps its WHOLE floor over a pressable node in ANOTHER subtree", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 200 } })
		w.present(crossHostScreen(), { initialFocus = "none" })
		local hit = w.adapter.hitRectOf("/X/Row/LeftCol/Tiny")
		local neighbour = w.adapter.node("/X/Row/RightCol/Neighbour")
		expect(`floor {hit.w}x{hit.h}`).toBe("floor 44x44")
		--[[ NON-VACUOUS: the floor really does land on the other column's Button.
			An ordinary control is EXEMPT from the cover rule — R18 and F1 both — and
			this is the case that says so. ]]
		expect(`reaches the other column: {overlapArea(hit, neighbour.rect) > 0}`).toBe(
			"reaches the other column: true"
		)
	end)

	it("a 20x20 Button still asks for the full 44x44, and it still leaves its parent", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 200 } })
		w.present(subFloorScreen(), { initialFocus = "none" })
		local small = w.adapter.node("/F/List/Small")
		local hit = w.adapter.hitRectOf("/F/List/Small")
		expect(`rect {small.rect.w}x{small.rect.h}`).toBe("rect 20x20")
		expect(`floor {hit.w}x{hit.h}`).toBe("floor 44x44")
		--[[ ...AND IT REALLY DOES OVERHANG, or the case above would pass on a
			control whose floor happened to fit. The 20px box is inside a hugging
			`List` of the same width, so 12px of the floor is outside the stack on
			each side and the row below is under it. ]]
		local list = w.adapter.node("/F/List")
		local below = w.adapter.node("/F/List/Below")
		expect(`inside its stack: {overlapArea(hit, list.rect) == hit.w * hit.h}`).toBe("inside its stack: false")
		expect(`reaches the row below: {overlapArea(hit, below.rect) > 0}`).toBe("reaches the row below: true")
	end)
end)

describe("a HIDDEN target is not a target", function()
	--[[ `solverHidden` is written by the visibility walk that runs immediately
		before the hit walk, and a node the player cannot see cannot take a press from
		anybody. Without the filter a `hidden` Button — a losing `ViewThatFits`
		candidate, an authored hide — would shrink a real control's floor for nothing.
		Driven through the RULE with the two blocker sets the walk would build, so the
		case names the difference the filter makes rather than asserting the filter
		exists. ]]
	it("a hidden pressable rect is absent from the blocker set, so the floor grows", function()
		local own = { x = 10, y = 10, w = 100, h = 20 }
		local want = { x = 10, y = -2, w = 100, h = 44 }
		local ghost = { x = 10, y = 0, w = 100, h = 8 }
		-- what the walk builds when the node is VISIBLE...
		expect(commit_walks.growWithin(own, want, { ghost }).h).toBe(34)
		-- ...and when it is hidden, which is the same call with an empty list
		expect(commit_walks.growWithin(own, want, {}).h).toBe(44)
	end)

	it("...and the walk really does drop one, on a live tree, both arms measured", function()
		--[[ THE LIVE HALF, because the arithmetic above proves only that an absent
			blocker is absent. ONE fixture, TWO arms: a fill-width Button laid over the
			bottom of a standing cover's growth band, `hidden` in one arm and standing
			in the other. Everything else is byte-identical, so the difference in the
			cover's floor IS the filter. ]]
		local function overlaid(ghostHidden: boolean): any
			return UI.Screen({
				id = "G",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.ZStack({
						id = "Z",
						children = {
							UI.Composition({
								id = "C",
								arrangements = { "column" },
								width = { type = "fill", weight = 1 },
								height = { type = "fill", weight = 1 },
								groups = { { id = "body", lane = "main", sizing = "fill" } },
								children = {
									UI.Region({
										id = "Clock",
										group = "body",
										rank = 1,
										recover = "overflow",
										children = {
											UI.VStack({
												id = "Full",
												children = {
													UI.Text({ id = "T1", text = "2:14", textSize = 16 }),
													UI.Text({ id = "T2", text = "12 - 9", textSize = 16 }),
													UI.Text({ id = "T3", text = "Home 12", textSize = 16 }),
													UI.Text({ id = "T4", text = "Away 9", textSize = 16 }),
												},
											}),
											UI.Text({ id = "Compact", text = "2:14", textSize = 16 }),
										},
									}),
								},
							}),
							UI.Button({
								id = "Ghost",
								label = "g",
								hidden = ghostHidden,
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 26 },
								onActivate = function() end,
							}),
						},
					}),
				},
			})
		end

		local function floorWith(ghostHidden: boolean): string
			local w = worldLib.new({
				viewport = { x = 0, y = 0, w = 390, h = 46 },
				overflowGuardOff = "this case reads hit geometry only; the fixture deliberately overlays two layers",
			})
			w.present(overlaid(ghostHidden), { initialFocus = "none" })
			local cover = w.adapter.node("/G/Z/C/Clock/Expand")
			local hit = w.adapter.hitRectOf("/G/Z/C/Clock/Expand")
			-- non-vacuity: the cover is standing over the region's whole box, and the
			-- ghost really does lie in the band the floor wants to grow into
			expect(`cover {cover.rect.w}x{cover.rect.h}`).toBe("cover 390x20")
			local ghost = w.adapter.node("/G/Z/Ghost")
			expect(`ghost reaches past the cover: {ghost.rect.y + ghost.rect.h > cover.rect.y + cover.rect.h}`).toBe(
				"ghost reaches past the cover: true"
			)
			expect(`ghost visible: {tostring(w.adapter.visibleOf("/G/Z/Ghost"))}`).toBe(
				`ghost visible: {tostring(not ghostHidden)}`
			)
			return `{hit.x},{hit.y} {hit.w}x{hit.h}`
		end

		-- hidden: nothing is in the way, so the floor grows 12px each way
		expect(floorWith(true)).toBe("0,-12 390x44")
		-- standing: the downward half is refused, and only that half
		expect(floorWith(false)).toBe("0,-12 390x32")
	end)
end)

describe("the rule itself, as a decision", function()
	--[[ WHY THE RULE IS PINNED HERE AND NOT ONLY THROUGH A FIXTURE. A floor's
		growth is a function of three things — the rect the node paints, the floor it
		asks for, and every pressable rect around it — and the arithmetic that
		reconciles them is where the two ways to get this wrong live: granting too
		much (the defect) and granting too little (the first attempt at the fix,
		which took the F1 floor off three shipped covers that were colliding with
		nothing). Both directions are cases here. ]]
	local function fmt(r: any): string
		if r == nil then
			return "nil"
		end
		return `{r.x},{r.y} {r.w}x{r.h}`
	end

	-- a 100x20 box asking for the 44px floor: 12 above and 12 below
	local OWN = { x = 10, y = 10, w = 100, h = 20 }
	local WANT = { x = 10, y = -2, w = 100, h = 44 }

	it("with nothing in the way it grows the whole floor", function()
		expect(fmt(commit_walks.growWithin(OWN, WANT, {}))).toBe("10,-2 100x44")
		-- ...and a blocker that is beside it on the other axis is not in its way
		expect(fmt(commit_walks.growWithin(OWN, WANT, { { x = 200, y = -2, w = 40, h = 44 } }))).toBe("10,-2 100x44")
	end)

	it("each side stops at the first blocker, and keeps the room on the other side", function()
		--[[ THE CASE THE MEASUREMENT COMMISSIONED. In the HUD demo at 705x338 the
			gaps above and below the Tasks chip are 9.5px against a 10.5px ask, so an
			all-or-nothing rule threw away 19 of the 21 px it could have had. ]]
		local blockedAbove = { x = 10, y = 0, w = 100, h = 8 }
		expect(fmt(commit_walks.growWithin(OWN, WANT, { blockedAbove }))).toBe("10,8 100x34")
		local blockedBelow = { x = 10, y = 34, w = 100, h = 8 }
		expect(fmt(commit_walks.growWithin(OWN, WANT, { blockedAbove, blockedBelow }))).toBe("10,8 100x26")
	end)

	it("boxed in on both sides it grows NOTHING and gives back exactly the painted rect", function()
		-- `ringScreen`'s geometry: the regions are edge to edge, so there is no room
		-- at all and the answer is the cover's own box — which is what retracts the
		-- expander entirely
		local flush = {
			{ x = 10, y = -30, w = 100, h = 40 },
			{ x = 10, y = 30, w = 100, h = 40 },
		}
		expect(fmt(commit_walks.growWithin(OWN, WANT, flush))).toBe("10,10 100x20")
	end)

	it("a blocker already overlapping the painted rect takes nothing away", function()
		--[[ The floor may never hand back LESS than the node already paints: that
			would be a worse defect than the one being fixed, and it is reachable
			through an anchored or negatively-offset sibling. ]]
		local inside = { { x = 0, y = 0, w = 200, h = 200 } }
		expect(fmt(commit_walks.growWithin(OWN, WANT, inside))).toBe("10,10 100x20")
	end)

	it("NEGATIVE CONTROL: the rule reads the ASK, not the blockers alone", function()
		-- a node already at or over the floor asks for nothing and gets nothing,
		-- however much room is around it
		local big = { x = 0, y = 0, w = 80, h = 80 }
		expect(fmt(commit_walks.growWithin(big, big, {}))).toBe("0,0 80x80")
		-- ...and a one-sided ask grows one side only
		local rightOnly = { x = 10, y = 10, w = 130, h = 20 }
		expect(fmt(commit_walks.growWithin(OWN, rightOnly, {}))).toBe("10,10 130x20")
	end)
end)
