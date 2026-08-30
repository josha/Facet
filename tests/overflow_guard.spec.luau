--!strict
--[[ THE CONTAINMENT INVARIANT'S OWN PROOFS (overflow guard layer 1, 2026-08-21).

	`tests/lib/overflow_guard.luau` runs after every settle in every fixture world
	and, on the corpus it was rolled out over, reports NOTHING. That is the good
	outcome and it is also the dangerous one: a check that reports nothing on a
	clean tree is indistinguishable from a check that is not looking. So this file
	is the other half — every rule the guard owns, shown biting on a screen built
	to break it, and shown SILENT on the screen one edit away that is legal.

	It is also where the WAIVER machinery is held to its own promise. The registry
	ships empty (measured: nothing in this framework needs an exception), and an
	empty registry makes "every waiver still fires" a sentence about nothing. The
	no-rot case therefore proves the DETECTOR on a ledger of its own — a waiver
	that matches nothing is named — and then applies the real one to the real
	registry. The first half is what makes the second half worth reading.

	WHY THIS FILE IS REQUIRED LAST in `tests/run.luau`: `unusedWaivers` counts uses
	across the WHOLE process, so the answer is only true once every other spec has
	run. testkit registers on require and runs afterwards in registration order,
	which makes "last require" and "last case" the same thing.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local world = require("./lib/world")
local overflow_guard = require("./lib/overflow_guard")

-- every fixture below turns the guard OFF on the world itself and asks it by
-- hand, because the whole point is to look at violations rather than to be
-- stopped by them
local OFF = "this file's own fixtures are deliberately broken screens; it asks the guard by hand"

local function violationsOf(screen: any, opts: any?): { any }
	local o: any = opts or {}
	o.overflowGuardOff = OFF
	local w = world.new(o)
	w.present(screen)
	w.settle(2)
	return overflow_guard.violations(w.adapter)
end

local function only(found: { any }): any
	expect(#found).toBe(1)
	return found[1]
end

describe("overflow guard: a plate that does not hold its own content", function()
	--[[ THE ESCAPE'S SHAPE, in the smallest screen that has it: a panel DECLARED
		narrower than the row inside it. This is the region-expand plate's defect
		with the fixture removed — `plate.w` written onto a padded box, content
		measured against the outer width — and it is the case that says the guard
		can see the class rather than the instance. ]]
	local function plateScreen(plateWidth: number): any
		return UI.Screen({
			id = "Plate",
			padding = 12,
			children = {
				UI.VStack({
					id = "Panel",
					surface = "raised",
					padding = 8,
					width = { type = "fixed", px = plateWidth },
					children = {
						UI.HStack({
							id = "Row",
							children = {
								UI.Box({
									id = "Score",
									surface = "control",
									width = { type = "fixed", px = 120 },
									height = { type = "fixed", px = 24 },
								}),
							},
						}),
					},
				}),
			},
		})
	end

	it("names the node, the box it escaped, the edge and the overhang in px", function()
		-- 120px of content inside a panel whose CONTENT box is 100 - 16 = 84
		local v = only(violationsOf(plateScreen(100)))
		expect(v.kind).toBe("outside-parent")
		expect(v.node).toBe("/Plate/Panel/Row/Score")
		expect(v.boundary).toBe("/Plate/Panel")
		expect(v.edge).toBe("right")
		expect(v.overhang).toBeCloseTo(28, 0.5)
		-- the message a reader actually gets, in one line
		expect(
			string.find(overflow_guard.describe(v), "overflows /Plate/Panel past its right edge by 28", 1, true) ~= nil
		).toBe(true)
	end)

	it("...and the SAME plate, one edit wider, is silent", function()
		-- content 120 + two 8px insets = 136: the width the plate should have had
		expect(#violationsOf(plateScreen(136))).toBe(0)
	end)

	--[[ SUB-PIXEL IS NOT AN OVERHANG. Solved rects carry fractions from fill
		weights and metric ladders, and a guard that reddened on 0.5px would be
		turned off within a week. The floor is stated in the module and pinned
		here so a future tightening has to move both. ]]
	it("a fractional px is arithmetic, not an escape", function()
		expect(#violationsOf(plateScreen(135.4))).toBe(0)
	end)
end)

describe("overflow guard: what counts as paint", function()
	--[[ THE MEASURED FALSE POSITIVE. With a bare Button counted as paint, this
		guard's first suite run reported nineteen scroll-snap cases: a row's
		full-width transparent `Hit` target overhanging its list by exactly the
		scroll bar. Nothing there is painted and nothing there is visible.
		`tools/lune/triage_overflow_waivers` had already measured the same rule from
		the other direction, and this case is the two agreeing. ]]
	local function hitScreen(label: string?): any
		return UI.Screen({
			id = "Hit",
			children = {
				UI.VStack({
					id = "Panel",
					surface = "raised",
					width = { type = "fixed", px = 60 },
					children = {
						--[[ THE ROW IS LOAD-BEARING. A container's ONLY child is fitted to
							its cross axis, so a lone 200px Button inside a 60px panel comes
							back 60px wide and there is nothing to see. The overflow this
							family is about is a MAIN-axis one — a row of fixed things wider
							than the box holding it — which is exactly the shape the escape
							had. ]]
						UI.HStack({
							id = "Row",
							children = {
								UI.Button({
									id = "Target",
									label = label or "",
									width = { type = "fixed", px = 200 },
									height = { type = "fixed", px = 20 },
									onActivate = function() end,
								}),
							},
						}),
					},
				}),
			},
		})
	end

	it("a transparent hit target paints nothing, so it cannot paint outside anything", function()
		expect(#violationsOf(hitScreen(nil))).toBe(0)
	end)

	it("...and the same Button with a LABEL is paint, and is reported", function()
		local v = only(violationsOf(hitScreen("Buy")))
		expect(v.node).toBe("/Hit/Panel/Row/Target")
		expect(v.text).toBe("Buy")
		expect(v.overhang).toBeCloseTo(140, 0.5)
	end)
end)

describe("overflow guard: a scroll host is a window on one axis and a wall on the other", function()
	--[[ CONTENT YOU CAN SCROLL TO IS CONTENT YOU CAN READ, and content pushed off
		the CROSS axis is content the engine cuts. The §14a live pass had to make
		this correction mid-sweep for scroll canvases; it is made once here, and
		these two cases are what stop it being made again in the wrong direction. ]]
	local function scrollScreen(rowWidth: number): any
		local rows: { any } = {}
		for i = 1, 30 do
			table.insert(
				rows,
				UI.Box({
					id = `R{i}`,
					surface = "control",
					width = { type = "fixed", px = rowWidth },
					height = { type = "fixed", px = 30 },
				})
			)
		end
		return UI.Screen({
			id = "Scroll",
			children = {
				UI.ScrollView({
					id = "List",
					axis = "y",
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 120 },
					children = rows,
				}),
			},
		})
	end

	it("a tall canvas past the window along the SCROLLED axis is silent", function()
		-- 30 rows of 30px in a 120px window: 780px of canvas below the fold, and
		-- every one of them reachable
		expect(#violationsOf(scrollScreen(120))).toBe(0)
	end)

	it("...and a row wider than the window on the CROSS axis is reported", function()
		local found = violationsOf(scrollScreen(400))
		expect(#found).toBeGreaterThan(0)
		expect(found[1].edge).toBe("right")
		expect(string.find(found[1].boundary, "/Scroll/List", 1, true)).toBe(1)
	end)
end)

describe("overflow guard: a visible string in a box with no area", function()
	--[[ THE THIRD HOLE. A non-empty Text solved to zero width is copy the player
		cannot read, and nothing in this suite forbade one. It has no waiver class
		and never will. ]]
	it("a visible non-empty Text with a zero-width box is reported", function()
		local screen = UI.Screen({
			id = "Zero",
			children = {
				UI.HStack({
					id = "Row",
					width = { type = "fixed", px = 0 },
					children = {
						UI.Text({ id = "Value", text = "9" }),
					},
				}),
			},
		})
		local v = only(violationsOf(screen))
		expect(v.kind).toBe("zero-box")
		expect(v.node).toBe("/Zero/Row/Value")
		expect(v.edge).toBe("width")
		expect(v.text).toBe("9")
	end)

	--[[ THE INSTRUMENT LESSON THIS GUARD WAS BUILT AROUND. The forensics on the
		escape reported the collapsed `12`/`9` solving width 0 as a second defect;
		they are not, they are the HIDDEN form-1 subtree, and every node of it is
		marked invisible by the framework. A guard reading a node's OWN flag would
		have inherited that misreading. The chain is what makes this silent. ]]
	it("...and the identical box inside a HIDDEN subtree is not, because visibility is the ancestor chain", function()
		local screen = UI.Screen({
			id = "Zero",
			children = {
				UI.VStack({
					id = "Variant",
					hidden = true,
					children = {
						UI.HStack({
							id = "Row",
							width = { type = "fixed", px = 0 },
							children = {
								UI.Text({ id = "Value", text = "9" }),
							},
						}),
					},
				}),
			},
		})
		expect(#violationsOf(screen)).toBe(0)
	end)
end)

describe("overflow guard: the world runs it by default", function()
	local function brokenScreen(): any
		return UI.Screen({
			id = "Broken",
			children = {
				UI.VStack({
					id = "Panel",
					surface = "raised",
					width = { type = "fixed", px = 40 },
					children = {
						UI.HStack({
							id = "Row",
							children = {
								UI.Box({
									id = "Wide",
									surface = "control",
									width = { type = "fixed", px = 200 },
									height = { type = "fixed", px = 20 },
								}),
							},
						}),
					},
				}),
			},
		})
	end

	it("a settle over an overflowing screen is RED with no fixture opting in", function()
		local w = world.new()
		local ok, err = pcall(function()
			w.present(brokenScreen())
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "containment invariant", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "/Broken/Panel/Row/Wide", 1, true) ~= nil).toBe(true)
	end)

	--[[ OFF IS A REASON, NOT A BOOLEAN. A fixture that deliberately builds a
		broken screen says so in the constructor, where the next reader sees it;
		`false` is not accepted at all, because an unexplained "off" is how an
		always-on check quietly stops being one. ]]
	it("...and a fixture that states WHY it is exempt is not", function()
		local w = world.new({ overflowGuardOff = "this case is about the guard being off" })
		w.present(brokenScreen())
		w.settle(2)
		expect(#overflow_guard.violations(w.adapter)).toBe(1)
	end)
end)

describe("overflow guard: the waiver registry cannot rot", function()
	local function waivedScreen(): any
		return UI.Screen({
			id = "Waived",
			children = {
				UI.VStack({
					id = "Panel",
					surface = "raised",
					width = { type = "fixed", px = 40 },
					children = {
						UI.HStack({
							id = "Row",
							children = {
								UI.Box({
									id = "Disc",
									surface = "control",
									width = { type = "fixed", px = 60 },
									height = { type = "fixed", px = 20 },
								}),
							},
						}),
					},
				}),
			},
		})
	end

	local function adapterOf(): any
		local w = world.new({ overflowGuardOff = OFF })
		w.present(waivedScreen())
		w.settle(2)
		return w.adapter
	end

	it("a matching waiver silences its violation and is counted as used", function()
		local ledger = overflow_guard.newLedger({
			{
				id = "test-disc",
				kind = "outside-parent",
				node = "/Disc$",
				maxPx = 40,
				reason = "a synthetic straddle, for this case only",
				owner = "tests/overflow_guard.spec.luau",
			},
		})
		expect(#overflow_guard.violations(adapterOf(), ledger)).toBe(0)
		expect(ledger.hits["test-disc"]).toBe(1)
		expect(#overflow_guard.unusedWaivers(ledger)).toBe(0)
	end)

	--[[ A WAIVER FORGIVES A SHAPE UP TO A SIZE. Deliberate overflow has a
		magnitude — half a disc is designed, the same disc 200px off the plate is a
		defect wearing the same path — so a cap that could not refuse would make
		every waiver a permanent blindfold over its own node. ]]
	it("...and the same waiver with a smaller cap refuses, naming itself in the message", function()
		local ledger = overflow_guard.newLedger({
			{
				id = "test-disc",
				kind = "outside-parent",
				node = "/Disc$",
				maxPx = 4,
				reason = "a synthetic straddle, for this case only",
				owner = "tests/overflow_guard.spec.luau",
			},
		})
		local v = only(overflow_guard.violations(adapterOf(), ledger))
		expect(string.find(overflow_guard.describe(v), "test-disc", 1, true) ~= nil).toBe(true)
		expect(string.find(overflow_guard.describe(v), "cap 4px exceeded", 1, true) ~= nil).toBe(true)
		expect(ledger.hits["test-disc"]).toBe(0)
	end)

	--[[ THE DETECTOR ITSELF, on a ledger of its own. This is what makes the case
		below worth reading: with the shipped registry empty, "every waiver fired"
		is a sentence about nothing unless the machinery that would catch an unfired
		one is shown to work. ]]
	it("NEGATIVE CONTROL: a waiver that matches nothing is NAMED as unused", function()
		local ledger = overflow_guard.newLedger({
			{
				id = "test-never-fires",
				kind = "outside-parent",
				node = "/NoSuchNodeAnywhere$",
				reason = "deliberately unmatchable",
				owner = "tests/overflow_guard.spec.luau",
			},
		})
		overflow_guard.violations(adapterOf(), ledger)
		expect(overflow_guard.unusedWaivers(ledger)).toEqual({ "test-never-fires" })
	end)

	--[[ AND THE REAL ONE, over the whole process. Every other spec has run by the
		time this case does (see the header), so a registered waiver that never
		matched anything is a defect somebody fixed and a line nobody deleted. ]]
	it("every waiver in the shipped registry fired at least once across this suite", function()
		local unused = overflow_guard.unusedWaivers()
		if #unused > 0 then
			error(
				`{#unused} waiver(s) in tests/lib/overflow_waivers.luau matched NOTHING across the whole `
					.. `suite. A waiver nobody needs is a hole nobody is watching: the defect it forgave is `
					.. `either fixed (delete the line) or is no longer reachable from any fixture (say so, or `
					.. `give it one). Unused: {table.concat(unused, ", ")}`,
				0
			)
		end
		expect(#unused).toBe(0)
	end)
end)

--[[ THE COMPOSITION-REGION CLASS, TRIAGED AND PINNED (follow-up, 2026-08-21).

	THE HANDOVER. The solver-split round (`435dade`), while scoping its own
	settle-time containment diagnostic, counted a class it did not ship: **a
	composition REGION placed below its composition's own content box, 312 times
	suite-wide** on `/HudScreen/Hud/*`, `/CompositionScreen/.../Summary/*` and
	`/S/C/*`, overhangs 2-235px. Its report booked it and routed it here, on the
	grounds that the collision finding compares regions against EACH OTHER and
	never against the box, and that the adapter-side harness can see paint.

	REPRODUCED EXACTLY — 312, with the same probe placed at the composition's own
	arrange branch — AND THE VERDICT IS: **DELIBERATE, and already reported.**
	The measurement is what decides it, in four parts:

	  1. **312 of 312 carry `fallback = true`. Not one is a legal composition.**
	     The fallback is the framework's own declaration that NOTHING FITS: it is
	     the one finding in this framework marked `designed = true`, it fires once
	     per solve on the composition itself, and it names the offer and the last
	     rejection ("no declared arrangement is legal in 304x0 — showing 'hud' as
	     the declared fallback (last rejection: overflow — lane 1 (left) needs
	     78px...)"). A second, per-region telling of that would be the same
	     duplication the solver round rejected 4,103 main-axis rows for — and it
	     would contradict the `designed` verdict at the same time.
	  2. **312 of 312 are the BOTTOM edge.** There is no horizontal instance,
	     because `placed.rect` is the SLOT the partition allotted and the partition
	     is clamped to the box. Only the fallback column's tail runs past it.
	  3. **A LEGAL composition cannot do it** — this clause WAS wrong, and the
	     give-way rule
	     is the counterexample. It said the fact was "a measured structural fact
	     rather than an empirical absence", reasoning that "the legality check
	     bounds vertical fit, so 'a region left the box' and 'the composition fell
	     back' are the same event". They are not: the legality check bounds whether
	     the content FITS, and `UI.Composition{ exclusions }` shipped a give-way
	     whose placement arithmetic put a fitting zone `inset` px outside a lane it
	     fits inside — legal, no rejection, no collision, and up to 300px out
	     is its counterexample. The clause is now true
	     again for the arithmetic reason rather than the fit reason: a legal
	     composition's placement sums to the lane exactly. THE THREE CASES BELOW
	     ARE THE BOUNDARY IT ACTUALLY NEEDED — at hero 400 the three-lane
	     arrangement is legal and every region is inside the box; at hero 420,
	     twenty pixels later, the arrangement is REJECTED and the fallback places
	     its regions outside; and the third declares a chrome row, because the
	     first two declare no `exclusions` and an inset of 0 made them structurally
	     incapable of failing on the class that actually shipped.
	  4. **Where it fires, nothing escapes paint.** On the worst cell in the suite
	     (narrow-portrait 320x640, `preferredTextOffset` +14, Pixel Quest, strip
	     down) the composition is offered **304x0** and yet: zero region-vs-region
	     collisions, no region outside the SCREEN, and this guard reports zero. The
	     underlying pressure is the fixture's own and is already documented in
	     `examples/gallery/scenarios/hud.luau` — the demo carries two developer
	     `UI.Toggle`s (`Drivers`) on the same Screen as the HUD, they wrap to two
	     lines at that size under that package, and hud.luau's own comment records
	     "This Screen has UNDER 8px of headroom at 320x640 with
	     preferredTextOffset = +14".

	SO THE GUARD STAYS SILENT ON IT, DELIBERATELY, the way `anchor` and `zstack`
	are deliberately unpoliced one layer down (`layout/placement_audit.luau`) — and
	the silence is PINNED HERE rather than merely decided, because a class that is
	countable but invisible is exactly how this one reached a second round. These
	two cases fail if any part of the verdict stops being true: if a legal
	composition ever places a region outside its box, if the fallback stops filing
	its `designed` finding, or if the fallback's geometry ever escapes a panel. ]]
describe("overflow guard: a composition region outside its box IS the declared fallback", function()
	local function box(id: string, w: number, h: number): any
		return UI.Box({
			id = id,
			surface = "control",
			width = { type = "fixed", px = w },
			height = { type = "fixed", px = h },
		})
	end

	--[[ 700x400, and the ONE variable is the lead region's height. The three-lane
		arrangement is legal while the tallest form fits the box and is rejected the
		moment it does not, which is the boundary the first two cases sit either side
		of. THE SECOND VARIABLE is `exclusions` — a declared chrome row — and it
		exists because the first two cases DECLARE NONE: with an inset of 0 they are
		structurally incapable of failing on the class the give-way rule fixed, so the
		property they name ("a legal composition keeps every region inside its own
		box") was pinned by a case that could not break. The third case supplies the
		arm that can. ]]
	local function screenWith(heroH: number, exclusions: { any }?): any
		return UI.Screen({
			id = "S",
			children = {
				UI.Composition({
					id = "C",
					arrangements = { "threeLane", "column" },
					laneGap = 12,
					groupGap = 8,
					exclusions = exclusions,
					width = { type = "fixed", px = 700 },
					height = { type = "fixed", px = 400 },
					groups = {
						{ id = "ceremony", lane = "lead", sizing = "hug", place = "center" },
						{ id = "field", lane = "main", sizing = "fill", minWidth = 200 },
						{ id = "next", lane = "trail", sizing = "hug", place = "end" },
					},
					children = {
						UI.Region({
							id = "Hero",
							group = "ceremony",
							rank = 3,
							children = { box("HeroFull", 150, heroH) },
						}),
						UI.Region({
							id = "Field",
							group = "field",
							rank = 2,
							sizing = "fill",
							floor = { lines = 1 },
							children = { box("FieldBody", 200, 60) },
						}),
						UI.Region({ id = "Ctas", group = "next", rank = 1, children = { box("CtaRow", 120, 60) } }),
					},
				}),
			},
		})
	end

	-- how far each mounted region's rect falls below the composition's own box
	local function belowBox(w: any): { [string]: number }
		local comp = w.adapter.node("/S/C").rect
		local out: { [string]: number } = {}
		for _, path in w.adapter.paths() do
			local n = w.adapter.node(path)
			if n ~= nil and n.class == "Region" and n.rect ~= nil and n.visible ~= false then
				out[path] = (n.rect.y + n.rect.h) - (comp.y + comp.h)
			end
		end
		return out
	end

	local function mount(heroH: number, exclusions: { any }?): any
		local w = world.new({
			viewport = { x = 0, y = 0, w = 900, h = 700 },
			overflowGuardOff = OFF,
		})
		w.present(screenWith(heroH, exclusions))
		w.settle(2)
		return w
	end

	it("A LEGAL composition keeps every region inside its own box — the property, positive", function()
		local w = mount(400)
		expect(w.controller.compositionAt("/S/C").fallback).toBe(false)
		for path, below in belowBox(w) do
			expect(`{path} below by {below}`).toBe(`{path} below by 0`)
		end
		expect(#overflow_guard.violations(w.adapter)).toBe(0)
	end)

	it("...and twenty pixels later NOTHING is legal, so the regions leave the box AND the framework says so", function()
		local w = mount(420)
		local dump = w.controller.compositionAt("/S/C")
		-- the class, reproduced in miniature: the same bottom-edge escape the 312
		-- are, on a composition that has run out of legal arrangements
		expect(dump.fallback).toBe(true)
		local below = belowBox(w)
		expect(below["/S/C/Hero"]).toBeCloseTo(20, 0.5)
		expect(below["/S/C/Ctas"]).toBeGreaterThan(0)

		--[[ AND THIS IS WHY THERE IS NO SECOND FINDING: the framework has already
			filed one, on the composition, marked `designed`, naming the offer it could
			not satisfy. Re-reporting it once per region would say the same thing three
			more times and call the framework's own designed behaviour a defect. ]]
		local designed = 0
		for _, finding in w.controller.diagnostics() do
			if finding.node == "/S/C" and finding.designed == true then
				expect(string.find(finding.issue, "no declared arrangement is legal", 1, true)).toBe(1)
				designed += 1
			end
		end
		expect(designed).toBe(1)

		-- ...and no PAINT escapes: the fallback is a layout verdict, not a leak
		expect(#overflow_guard.violations(w.adapter)).toBe(0)
	end)

	--[[ THE ARM THAT CAN ACTUALLY FAIL. The two cases above declare no
		`exclusions`, so every lane's give-way inset is 0 and the placement term this
		guard's verdict depends on is never exercised — they were green before the
		give-way fix and green after, on a defect that put a region up to 300px
		outside its lane while the composition reported `legal = true`.

		THE ROW IS DERIVED FROM THE MOUNTED BOX rather than guessed at a literal,
		because `exclusions` are WINDOW-space and where a fixed 700x400 composition
		lands inside a 900x700 Screen is the Screen's business. Mount once to read
		the box, then re-mount with a row that reaches into it. Both halves of the
		premise are asserted — every lane must actually give way, and the composition
		must still be LEGAL — so this case reports a broken premise instead of
		passing vacuously the way the two above did.

		HERO 300, NOT 400: at 400 the arrangement is already one pixel from its own
		boundary, so ANY inset tips it into the `column` fallback and the case would
		be measuring the SECOND case's event instead of this one (measured: hero 400
		+ a 40px row = `arrangement = column, fallback = true`). 300 leaves the
		three-lane arrangement legal with a 40px row on every lane, which is the
		only shape in which this property has anything to say. ]]
	it("...AND IT HOLDS WITH A CHROME ROW DECLARED — the arm the first case could not fail on", function()
		local probe = mount(300)
		local box = probe.adapter.node("/S/C").rect
		-- a row across the whole composition, reaching 40px into its top edge: every
		-- lane's own content shares an x range with it, so every lane gives way
		local w = mount(300, { { x = box.x, y = box.y, w = box.w, h = 40 } })
		local dump = w.controller.compositionAt("/S/C")

		local gaveWay: { string } = {}
		for _, lane in dump.lanes do
			if (lane.exclusion or 0) > 0 then
				table.insert(gaveWay, `{lane.index}:{lane.exclusion}`)
			end
		end
		expect(`lanes that gave way: {#gaveWay}`).toBe("lanes that gave way: 3")
		expect(`still legal: {dump.legal == true and dump.fallback == false}`).toBe("still legal: true")

		--[[ THE PROPERTY, now on a tree that can break it: `ceremony` is
			`place = "center"` and `next` is `place = "end"`, the two shapes the give-way rule
			moved. Containment is `<= 0` here rather than the first case's `== 0`
			because hero 300 leaves real slack — a region ENDING above the box's
			bottom edge is the lane placing it, not an escape. The `end`-placed group
			is asserted at exactly 0 separately: that one is load-bearing, it is the
			shape that used to land `inset` px out, and "flush with the bottom" is the
			whole claim. ]]
		local escaped: { string } = {}
		for path, below in belowBox(w) do
			if below > 0.5 then
				table.insert(escaped, `{path} below by {below}`)
			end
		end
		table.sort(escaped)
		expect(table.concat(escaped, ", ")).toBe("")
		expect(`Ctas below by {belowBox(w)["/S/C/Ctas"]}`).toBe("Ctas below by 0")
		expect(#overflow_guard.violations(w.adapter)).toBe(0)
	end)
end)
