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
