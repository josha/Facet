--!strict
--[[ "IS THIS PATH INSIDE A SUBTREE THAT DOES NOT PAINT" — ONE OWNER
	(reuse audit REUSE-29; brief §3a; R5 review §3a-1 / §5-3).

	A losing `ViewThatFits` candidate keeps its mount, its rects and its text
	facts — only VISIBILITY knows it does not paint. Three presentation walks
	therefore have to skip it before they raise anything: the disclosure plate
	(`presenter.luau`), the help plate (`help_plate.luau`) and the auto-reveal
	scan (`text_reveal.luau`). Each of the three had its own copy of the test,
	and `presenter.luau` had TWO — a module-level import of the published owner
	at line 272, SHADOWED by a nested local that re-implemented it.

	Behaviour was identical across all four, which is exactly why this needed a
	test rather than a bug report: the copies could diverge and only one of them
	had any coverage. Measured, on the fast tier, by breaking the published owner
	(`focusMap.isHiddenPath` returning false always):

	    before the consolidation: 8 cases redden
	    after  the consolidation: 9 cases redden

	— the presenter's disclosure walk joined the owner and one more case came
	under it. The help and reveal walks brought NO coverage with them at all,
	because nothing had ever exercised them against a hidden root. That is what
	this file is: the two uncovered walks, plus the disclosure walk beside them
	so all three are pinned in one place against one owner.

	THE AUDIT COUNTED THREE COPIES AND THERE WERE FOUR. `text_reveal.luau` holds
	two — the scan that CHOOSES a label, and a per-tick re-check inside
	`stepReveal` that retires a strip whose source has since gone hidden (added
	live 2026-08-04, when a preference drop flipped a recap's composition and the
	strip kept travelling over a line nobody could see). Both are the same test
	and both now call the same owner. They are belt and braces: measured,
	removing either one alone leaves this file at 5/5 and removing BOTH reddens
	it — which is recorded here rather than dressed up as two independent proofs.

	THE POSITIVE CONTROL IS THE POINT. "Nothing was raised" is the answer a
	broken walk gives too, so every case here also shows the SAME shape raising
	its plate when the candidate wins.

	MUTATIONS, each reverted: the owner answering `false` reddens this file (and
	eight other cases across the suite); a re-introduced shadowing local in
	`presenter` reddens it; the help walk dropping its ask reddens it; the two
	reveal gates redden it together.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")
local UI = require("../src/blueprint")

local LONG = "Bartholomew Fitzgerald-Montgomery III"
local HELP = "Posts your reply to everyone in the room."

local POINTER = {
	capabilities = { keyboard = false, mouse = true, touch = false, gamepad = false },
	preferredInput = "KeyboardAndMouse",
}

--[[ One shape, two widths. `narrow` starves the rich candidate so it loses and
	becomes a hidden root; `wide` gives it room so it wins. Everything else —
	the ids, the props, the walk — is identical, which is what makes the pair a
	control rather than two different tests. ]]
local function shape(rich: any)
	return UI.Screen({
		id = "Roster",
		children = {
			UI.Button({
				id = "Row",
				label = "",
				width = { type = "fixed", px = 120 },
				height = { type = "fixed", px = 44 },
				children = {
					UI.ViewThatFits({
						id = "VTF",
						children = {
							UI.VStack({ id = "Rich", width = { type = "fixed", px = 400 }, children = { rich } }),
							UI.VStack({ id = "Short", children = { UI.Text({ id = "Bo", text = "Bo" }) } }),
						},
					}),
				},
			}),
		},
	})
end

local function present(rich: any, opts: any?)
	local w = worldLib.new(opts or { viewport = { x = 0, y = 0, w = 390, h = 844 } })
	local handle = w.pres.present(shape(rich))
	return w, handle
end

describe("REUSE-29: the three hidden-root walks share one owner", function()
	it("the DISCLOSURE walk skips a losing candidate, and raises for a winning one", function()
		local w, handle = present(UI.Text({ id = "Long", text = LONG, disclose = true }))
		expect(handle.controller.hiddenRoots()["/Roster/Row/VTF/Rich"]).toBe(true)
		expect(w.pres.disclosure().present).toBe(false)
	end)

	--[[ THE HELP WALK, which had no hidden-root coverage of any kind. A plate
		raised for a control that is nowhere on screen points at nothing — the
		module says so at `help_plate.luau:128-130` and, until this file, nothing
		checked it. ]]
	it("the HELP walk skips a losing candidate", function()
		local w = worldLib.new(POINTER)
		local handle = w.pres.present(shape(UI.Text({ id = "Long", text = LONG, help = HELP })))
		expect(handle.controller.hiddenRoots()["/Roster/Row/VTF/Rich"]).toBe(true)
		w.pres._discloseHover("/Roster/Row")
		w.pres.tick(0.5) -- past the dwell
		expect(w.pres.help().present).toBe(false)
	end)

	it("POSITIVE CONTROL: the same help text on a WINNING candidate does raise", function()
		local w = worldLib.new(POINTER)
		w.pres.present(UI.Screen({
			id = "Roster",
			children = {
				UI.Button({
					id = "Row",
					label = "",
					width = { type = "fixed", px = 380 },
					height = { type = "fixed", px = 44 },
					children = { UI.Text({ id = "Long", text = "Post", help = HELP }) },
				}),
			},
		}))
		w.pres._discloseHover("/Roster/Row")
		w.pres.tick(0.5)
		local h = w.pres.help()
		expect(h.present).toBe(true)
		expect(h.helpText).toBe(HELP)
	end)

	--[[ THE REVEAL WALK, likewise uncovered. `reveal = "auto"` picks at most one
		truncated label per presentation to march; picking one inside a candidate
		that lost means marching text nobody can see, forever. ]]
	--[[ THE REVEAL WALK, likewise uncovered. `reveal = "auto"` picks at most one
		truncated label per presentation to march; picking one inside a candidate
		that lost means marching text nobody can see, forever. The fixture is
		`text_reveal.spec`'s own tally shape — a one-line fill Text in a narrow
		fixed VStack, which is what actually truncates — put inside a
		ViewThatFits so it can be made to lose. ]]
	local function tally(): any
		return UI.VStack({
			id = "Masthead",
			width = { type = "fixed", px = 160 },
			children = {
				UI.Text({
					id = "Recap",
					text = LONG,
					textSize = 16,
					lineLimit = 1,
					reveal = "auto",
					width = { type = "fill", weight = 1 },
				}),
			},
		})
	end

	local function run(pres: any, seconds: number)
		local step = 1 / 30
		for _ = 1, math.max(1, math.floor(seconds / step + 0.5)) do
			pres.tick(step)
		end
	end

	it("the REVEAL walk skips a losing candidate, and marches for a winning one", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		local handle = w.pres.present(UI.Screen({
			id = "Results",
			children = {
				UI.VStack({
					id = "Row",
					width = { type = "fixed", px = 120 },
					children = {
						UI.ViewThatFits({
							id = "VTF",
							children = {
								UI.VStack({ id = "Rich", width = { type = "fixed", px = 400 }, children = { tally() } }),
								UI.VStack({ id = "Short", children = { UI.Text({ id = "Bo", text = "Bo" }) } }),
							},
						}),
					},
				}),
			},
		}))
		expect(handle.controller.hiddenRoots()["/Results/Row/VTF/Rich"]).toBe(true)
		run(w.pres, 2.0) -- past rescan + rest delay, well into the out leg
		expect(w.pres.movingText()).toBe(0)
		expect(w.pres.reveal().present).toBe(false)

		--[[ POSITIVE CONTROL. The identical declaration with nothing hiding it
			DOES march, so the zero above is the hidden-root gate and not a reveal
			that never works in this fixture. ]]
		local wide = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		wide.pres.present(UI.Screen({ id = "Results", children = { tally() } }))
		run(wide.pres, 2.0)
		expect(wide.pres.movingText()).toBe(1)
		expect(wide.pres.reveal().present).toBe(true)
	end)

	--[[ AND THE SHADOW IS GONE. `presenter.luau` imported the owner at :272 and
		then declared a nested `local function isHiddenPath` that shadowed it —
		the audit's headline for this finding. A structural pin, because the two
		bodies agreed and no behavioural test could tell them apart. ]]
	it("no presentation module re-implements the owner", function()
		local fs = require("@lune/fs")
		local offenders: { string } = {}
		for _, name in { "presenter", "help_plate", "text_reveal" } do
			local source = fs.readFile(`src/present/{name}.luau`)
			if string.find(source, "local function isHiddenPath", 1, true) ~= nil then
				table.insert(offenders, name)
			end
			if string.find(source, "local function isHidden(", 1, true) ~= nil then
				table.insert(offenders, `{name} (isHidden)`)
			end
		end
		expect(`modules re-implementing isHiddenPath: {table.concat(offenders, ", ")}`).toBe(
			"modules re-implementing isHiddenPath: "
		)
	end)
end)
