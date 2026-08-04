--!strict
-- THE AUTO REVEAL (director ruling 2026-08-04, superseding LTN-2 for declared
-- surfaces; the plan's overflow rung 4). A `UI.Text{ reveal = "auto" }` that
-- TRUNCATED auto-scrolls its full value: the string rests in its engine
-- ellipsis, and after a quiet delay the presenter slides the whole line through
-- the box — out to the tail, a pause, and back — then rests again.
--
-- The plan's constraint list binds every line of this file:
--   · quiet START DELAY before anything moves (the rest phase);
--   · READING-DIRECTION travel (the strip slides left, revealing the tail);
--   · GRAPHEME boundaries — the whole string travels as ONE strip, never
--     re-segmented; at rest the paint is the engine's own ellipsis;
--   · PAUSE AT ENDS (the tail holds before the return leg);
--   · a STATIC full-value alternative — a reveal node is ALSO a disclosure
--     source, so hover dwell / long-press raise the LTN-4 plate;
--   · REDUCED MOTION disables travel entirely (the static plate remains);
--   · AT MOST ONE moving text surface (`presenter.movingText()` feeds the
--     `text_audit.movingText` rule);
--   · NO per-label frame loops — the one presenter tick drives it, and an idle
--     presenter only pays a timer-gated rescan.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local actionsLib = require("../src/input/actions")
local presenterLib = require("../src/present/presenter")
local text_audit = require("../src/layout/text_audit")
local fake_target = require("../tests/lib/fake_target")

-- the production string this ships for: the finish-screen recap tally
local TALLY = "0 passes created · 0 recoveries sparked · Drama Score 0"
local FULL = "/__reveal__/Layer/Window/Inner/Full"

local function makeWorld()
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	return core, env, adapter, system, pres
end

-- a narrow one-line tally: the recap's REDUCED form, as a fixture
local function tallyScreen(opts: any?): any
	local o: any = opts or {}
	return UI.Screen({
		id = "Results",
		children = {
			UI.VStack({
				id = "Masthead",
				width = { type = "fixed", px = o.width or 160 },
				children = {
					UI.Text({
						id = "Recap",
						text = o.text or TALLY,
						textSize = 16,
						lineLimit = 1,
						reveal = if o.reveal == false then nil else "auto",
						width = { type = "fill", weight = 1 },
					}),
				},
			}),
		},
	})
end

local RECAP = "/Results/Masthead/Recap"

-- run the presenter clock forward in small steps (one tick per frame, as live)
local function run(pres: any, seconds: number)
	local step = 1 / 30
	local n = math.max(1, math.floor(seconds / step + 0.5))
	for _ = 1, n do
		pres.tick(step)
	end
end

describe("reveal: the declaration and its solve facts", function()
	it("`reveal = 'auto'` is construction-only and enum-checked", function()
		expect(function()
				UI.Text({ id = "T", text = "x", reveal = "auto" })
			end)
			.never()
			.toThrow()
		expect(function()
			UI.Text({ id = "T", text = "x", reveal = "marquee" :: any })
		end).toThrow()
		expect(function()
			UI.Text({ id = "T", text = "x", reveal = true :: any })
		end).toThrow()
	end)

	it("a truncated reveal text publishes reveal facts: policy, flag, natural width", function()
		local _, _, _, _, pres = makeWorld()
		local h = pres.present(tallyScreen())
		local facts = h.controller.textAt(RECAP)
		expect(facts.truncated).toBe(true)
		expect(facts.reveal).toBe(true)
		expect(facts.policy).toBe("truncate+reveal")
		-- the travel distance's other half: the one-line width the string WANTS,
		-- measured by the same solve that produced the truncation verdict
		expect(facts.naturalWidth > 160).toBe(true)
	end)

	it("clippedEssential accepts a reveal path as full-value access", function()
		local _, _, _, _, pres = makeWorld()
		local h = pres.present(tallyScreen())
		local rects: { [string]: any } = {}
		rects[RECAP] = { rect = { x = 0, y = 0, w = 160, h = 20 }, textFacts = h.controller.textAt(RECAP) }
		expect(#text_audit.clippedEssential(rects)).toBe(0)
	end)
end)

describe("reveal: the auto cycle", function()
	it("rests in the engine ellipsis for the quiet delay: nothing moves at present", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(tallyScreen())
		expect(pres.reveal().present).toBe(false)
		expect(pres.movingText()).toBe(0)
		run(pres, 0.8) -- rescan has found the target; the delay has not elapsed
		expect(pres.reveal().present).toBe(false)
		expect(adapter.node(FULL)).toBe(nil)
		expect(adapter.visibleOf(RECAP) ~= false).toBe(true)
	end)

	it("after the delay the strip mounts, the source paint yields, and travel advances left", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(tallyScreen())
		run(pres, 2.0) -- past rescan + rest delay, into the out leg
		local r = pres.reveal()
		expect(r.present).toBe(true)
		expect(r.sourcePath).toBe(RECAP)
		expect(r.phase).toBe("out")
		expect(r.travel > 0).toBe(true)
		expect(pres.movingText()).toBe(1)
		-- the strip carries the WHOLE string at natural width; the source's own
		-- ellipsized paint is held while the strip covers it
		expect(adapter.node(FULL).props.text).toBe(TALLY)
		expect(adapter.visibleOf(RECAP)).toBe(false)
		local before = pres.reveal().travel
		run(pres, 0.5)
		expect(pres.reveal().travel > before).toBe(true)
	end)

	it("pauses at the end with the tail fully shown, returns, and rests again as the ellipsis", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(tallyScreen())
		-- SAMPLE one full cycle: every phase must be observed, the travel must
		-- REACH the distance (the tail fully shown before the pause), and the
		-- cycle must come back to the ellipsis rest with the strip gone
		local seen: { [string]: boolean } = {}
		local maxTravel, distance = 0, 0
		local restedAfterTravel = false
		local step = 1 / 30
		for _ = 1, math.floor(45 / step) do
			pres.tick(step)
			local r = pres.reveal()
			if r.present then
				seen[r.phase] = true
				maxTravel = math.max(maxTravel, r.travel)
				distance = math.max(distance, r.distance)
			elseif seen.back == true then
				restedAfterTravel = true
				break
			end
		end
		expect(seen.out).toBe(true)
		expect(seen["end"]).toBe(true)
		expect(seen.back).toBe(true)
		expect(distance > 0).toBe(true)
		expect(maxTravel).toBe(distance) -- the end pose showed the string's end
		expect(restedAfterTravel).toBe(true)
		expect(adapter.node(FULL)).toBe(nil)
		expect(adapter.visibleOf(RECAP) ~= false).toBe(true)
	end)

	it("never runs for text that fits, or for truncated text that did not declare it", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(tallyScreen({ text = "Drama 0" }))
		run(pres, 3)
		expect(pres.reveal().present).toBe(false)

		local _, _, _, _, pres2 = makeWorld()
		pres2.present(tallyScreen({ reveal = false }))
		run(pres2, 3)
		expect(pres2.reveal().present).toBe(false)
	end)

	it("a re-solve that makes room retires the reveal cleanly", function()
		local core, _, adapter, _, pres = makeWorld()
		local text = core:signal(TALLY)
		local bp = UI.Screen({
			id = "Results",
			children = {
				UI.VStack({
					id = "Masthead",
					width = { type = "fixed", px = 160 },
					children = {
						UI.Text({
							id = "Recap",
							text = text,
							textSize = 16,
							lineLimit = 1,
							reveal = "auto",
							width = { type = "fill", weight = 1 },
						}),
					},
				}),
			},
		})
		pres.present(bp)
		run(pres, 2.0)
		expect(pres.reveal().present).toBe(true)
		text:set("Drama 0") -- the tally now fits; the debt is paid by reflow
		pres.refresh() -- the host's per-frame duty: re-render the surfaces
		run(pres, 0.2)
		expect(pres.reveal().present).toBe(false)
		expect(adapter.visibleOf(RECAP) ~= false).toBe(true)
	end)

	it("a source that goes HIDDEN mid-flight retires the strip (found live, 2026-08-04)", function()
		--[[ The recap's reduced form lives in a losing arrangement candidate at
			some preferences: a hidden candidate keeps its mount, its rects AND its
			truncation facts — only visibility knows it does not paint (the same
			F-1 class the disclosure already fixed). Measured live: dropping the
			preference to Medium made the composition pick the rich form, the
			reduced line went hidden, and the strip kept running over it. The tick
			verify must read hiddenness, not only the facts. ]]
		local _, env, adapter, _, pres = makeWorld()
		local narrow = UI.VStack({
			id = "Narrow",
			width = { type = "fixed", px = 160 },
			children = {
				UI.Text({
					id = "Recap",
					text = TALLY,
					textSize = 16,
					lineLimit = 1,
					reveal = "auto",
					width = { type = "fill", weight = 1 },
				}),
			},
		})
		local wide = UI.VStack({
			id = "Wide",
			width = { type = "fixed", px = 360 },
			children = { UI.Text({ id = "Full", text = TALLY, textSize = 16 }) },
		})
		pres.present(UI.Screen({
			id = "Results",
			children = {
				UI.ViewThatFits({
					id = "Recaps",
					width = { type = "fill", weight = 1 },
					children = { wide, narrow },
				}),
			},
		}))
		-- the 390 viewport fits the WIDE candidate; shrink so only NARROW fits
		env:set("viewportRect", { x = 0, y = 0, w = 200, h = 844 })
		pres.refresh()
		run(pres, 2.0)
		local r = pres.reveal()
		expect(r.present).toBe(true)
		expect(r.sourcePath).toBe("/Results/Recaps/Narrow/Recap")
		-- the viewport grows back: WIDE wins again, NARROW is hidden — the strip
		-- must go with it on the next tick, and the held paint must release
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		pres.refresh()
		run(pres, 0.2)
		expect(pres.reveal().present).toBe(false)
		expect(adapter.node(FULL)).toBe(nil)
		expect(adapter.visibleOf("/Results/Recaps/Narrow/Recap")).toBe(false) -- hidden CANDIDATE, not held paint
	end)

	it("dismissing the owning surface retires the reveal with it", function()
		local _, _, adapter, _, pres = makeWorld()
		local h = pres.present(tallyScreen())
		run(pres, 2.0)
		expect(pres.reveal().present).toBe(true)
		pres.dismiss(h)
		run(pres, 0.2)
		expect(pres.reveal().present).toBe(false)
		expect(adapter.node(FULL)).toBe(nil)
	end)
end)

describe("reveal: the constraint rails", function()
	it("reduced motion disables travel entirely — and the static plate remains reachable", function()
		local _, env, adapter, _, pres = makeWorld()
		env:set("reducedMotion", true)
		pres.present(tallyScreen())
		run(pres, 5)
		expect(pres.reveal().present).toBe(false)
		expect(pres.movingText()).toBe(0)
		expect(adapter.node(FULL)).toBe(nil)
		-- the static full-value alternative: a reveal node is a disclosure source
		pres._discloseLongPress(RECAP)
		local d = pres.disclosure()
		expect(d.present).toBe(true)
		expect(d.text).toBe(TALLY)
	end)

	it("a reduced-motion flip mid-flight retires the strip on the next tick", function()
		local _, env, adapter, _, pres = makeWorld()
		pres.present(tallyScreen())
		run(pres, 2.0)
		expect(pres.reveal().present).toBe(true)
		env:set("reducedMotion", true)
		run(pres, 0.1)
		expect(pres.reveal().present).toBe(false)
		expect(adapter.visibleOf(RECAP) ~= false).toBe(true)
	end)

	it("at most ONE strip runs: the first declared target in document order wins", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(UI.Screen({
			id = "Results",
			children = {
				UI.VStack({
					id = "Masthead",
					width = { type = "fixed", px = 160 },
					children = {
						UI.Text({
							id = "RecapA",
							text = TALLY,
							textSize = 16,
							lineLimit = 1,
							reveal = "auto",
							width = { type = "fill", weight = 1 },
						}),
						UI.Text({
							id = "RecapB",
							text = TALLY .. " again",
							textSize = 16,
							lineLimit = 1,
							reveal = "auto",
							width = { type = "fill", weight = 1 },
						}),
					},
				}),
			},
		}))
		run(pres, 2.0)
		expect(pres.reveal().sourcePath).toBe("/Results/Masthead/RecapA")
		expect(pres.movingText()).toBe(1)
		-- the rule itself stays pure and still fires above the allowance
		expect(#text_audit.movingText(pres.movingText(), 1)).toBe(0)
		expect(#text_audit.movingText(2, 1)).toBe(1)
	end)

	it("a live disclosure plate for the same label outranks the strip: the reveal rests", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(tallyScreen())
		run(pres, 2.0)
		expect(pres.reveal().present).toBe(true)
		pres._discloseLongPress(RECAP) -- the reader asked for the static answer
		run(pres, 0.1)
		expect(pres.disclosure().present).toBe(true)
		expect(pres.reveal().present).toBe(false)
		expect(adapter.visibleOf(RECAP) ~= false).toBe(true)
		-- releasing the press lets the cycle resume from rest
		pres._discloseLongPress(nil)
		run(pres, 2.0)
		expect(pres.reveal().present).toBe(true)
	end)
end)
