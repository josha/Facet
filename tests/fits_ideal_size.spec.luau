--!strict
--[[
	ViewThatFits and the `hug` trap (framework-gaps-phase2 §2a).

	A `hug` dimension is "the content size, but never larger than the box the
	parent offered". Inside a `ViewThatFits` candidate that ceiling is fatal: the
	candidate's measured width can never EXCEED the offer, so `w <= availW` is
	true whatever the content wants, the first rung wins at every width, and the
	labels the ladder exists to protect truncate anyway. It is a silent wrong
	answer reached by writing the obvious thing — `hug` is the instinctive
	spelling everywhere else in the framework — and four consumer files
	independently learned it and defended against it in PROSE
	(`examples/gallery/client/showcase_chrome.luau` names it "the p4_foyer trap").

	THE FIX IS NOT A REFUSAL, and that is this round's one design decision. The
	ladder's own doctrine already says what to do: "a candidate is judged at the
	size it would like, not at the size it could be squeezed into" (ruling 2,
	2026-08-14 — the ideal-size rule), and `ctx.fitProbe` is the mechanism that
	makes every squeezing mechanism invisible for the duration of the probe.
	`hug`'s cap-at-the-offer IS a squeezing mechanism — the same family as
	truncation, `lineLimit` and `shrinkWeight` — so the probe suppresses it too,
	and the ladder's existing `w <= availW` test then answers correctly. The
	author's own `min`/`max` on the dim stay in force, because those are a
	declaration and not a shortage (the same split `authoredWidth` draws for text).

	THE WINNER IS STILL CAPPED: the flag is off again by the time the chosen
	candidate is measured and arranged, which is the other half of the same
	ruling — picking is unsqueezed, showing is not. So a `hug` rung that wins
	still stops growing at the offer, and a `hug` ScrollView still hugs a short
	list and scrolls a long one.
]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local solver = require("../src/layout/solver")
local adaptive = require("../src/layout/adaptive")
local customFactory = require("../src/core/custom")

local function fixed(px: number): solver.Dim
	return { type = "fixed", px = px }
end

--[[ THE LADDER, PARAMETERISED BY THE CANDIDATE'S DIM. Both rungs hold the same
	content — three 100px boxes with a 10px gap, so 320px of natural width — and
	differ only in what the rung's own width DECLARES. `content` is the spelling
	the four prose defenses had to reach for; `hug` is the instinctive one.

	The second rung is a single 100px box, so it fits any offer at or above 100
	and the ladder has a real answer to fall to. ]]
local function ladder(rungDim: solver.Dim, offerW: number): any
	local function boxes(prefix: string, n: number): { solver.Node }
		local kids: { solver.Node } = {}
		for i = 1, n do
			table.insert(kids, { kind = "box", id = `{prefix}{i}`, width = fixed(100), height = fixed(20) })
		end
		return kids
	end
	local root: solver.Node = {
		kind = "vstack",
		id = "screen",
		width = fixed(offerW),
		height = fixed(200),
		children = {
			{
				kind = "fits",
				id = "ladder",
				children = {
					{ kind = "hstack", id = "rich", gap = 10, width = rungDim, children = boxes("r", 3) },
					{ kind = "hstack", id = "plain", width = rungDim, children = boxes("p", 1) },
				},
			},
		},
	}
	return solver.solve(root, { w = offerW, h = 200 }, { rootPolicy = "edgeToEdge" })
end

describe("ViewThatFits: a candidate is judged at its IDEAL size, `hug` included", function()
	--[[ THE CONTROL ARM. `content` is uncapped, so the rich rung reports 320
		against a 200px offer, the test says no and the ladder steps. This is the
		behaviour the four prose defenses were buying by hand, and it does not move. ]]
	it("a `content` rung reports its true width and the ladder steps down", function()
		local r = ladder({ type = "content" }, 200)
		expect(`rich hidden={r.rects.rich.hidden == true}`).toBe("rich hidden=true")
		expect(`plain hidden={r.rects.plain.hidden == true}`).toBe("plain hidden=false")
	end)

	--[[ THE DEFECT, STATED AS THE MEASUREMENT THAT PROVES IT. Same tree, same
		offer, same content — only the dim word changes — and before the fix the
		rich rung won at 200px because `hug` clamped its 320px measure to 200. ]]
	it("a `hug` rung ALSO reports its true width, so the same ladder steps", function()
		local r = ladder({ type = "hug" }, 200)
		expect(`rich hidden={r.rects.rich.hidden == true}`).toBe("rich hidden=true")
		expect(`plain hidden={r.rects.plain.hidden == true}`).toBe("plain hidden=false")
	end)

	--[[ ...AND THE TWO SPELLINGS NOW AGREE AT EVERY WIDTH, which is the property
		rather than the case. The sweep crosses the rich rung's 320px natural width,
		so it contains both verdicts; if `hug` were still capped it would answer
		"rich" at every rung of the sweep while `content` answers honestly. ]]
	it("`hug` and `content` choose the same rung across a width sweep", function()
		local disagreements = {}
		for offerW = 120, 400, 20 do
			local hugChoice = if ladder({ type = "hug" }, offerW).rects.rich.hidden == true then "plain" else "rich"
			local contentChoice = if ladder({ type = "content" }, offerW).rects.rich.hidden == true
				then "plain"
				else "rich"
			if hugChoice ~= contentChoice then
				table.insert(disagreements, `{offerW}:hug={hugChoice},content={contentChoice}`)
			end
		end
		expect(`disagreements={table.concat(disagreements, " ")}`).toBe("disagreements=")
	end)

	--[[ THE SWEEP IS NOT VACUOUS: it has to contain a width where the answer is
		"rich" and one where it is "plain", or two constant columns would agree
		trivially and the case above would pass on a broken solver. ]]
	it("the sweep really does contain both verdicts", function()
		local wide = ladder({ type = "hug" }, 400)
		local narrow = ladder({ type = "hug" }, 120)
		expect(`wide picks rich={wide.rects.rich.hidden ~= true}`).toBe("wide picks rich=true")
		expect(`narrow picks plain={narrow.rects.plain.hidden ~= true}`).toBe("narrow picks plain=true")
	end)

	--[[ PICKING IS UNSQUEEZED; SHOWING IS NOT. The winner is measured and arranged
		with the flag off, so a `hug` rung that wins is still capped at the offer —
		which is the whole reason `hug` exists (a panel "as big as it needs and no
		bigger"). At 250px the rich rung loses; at 400 it wins and takes its natural
		320, not the 400 a `fill` would have taken. ]]
	it("a `hug` FALLBACK rung — the one never probed — is capped by the offer it is shown in", function()
		--[[ THE CAP HAS TO BITE FOR THIS CASE TO SAY ANYTHING, and the first version
			of it did not: it took a 320 px rung at a 400 px offer, where nothing is
			capped and `hug`, `content` and `fill` would all have answered 320.

			THE FALLBACK RUNG IS THE HONEST SUBJECT. It is NEVER PROBED — the loop stops
			one short of it, because rule 8 promises the fallback resolves whatever it
			measures — so the probe's suppression can never reach it, and whatever it
			paints is the cap doing its ordinary job. A 210 px `hug` row shown in a 90
			px and then a 150 px box must paint 90 and 150: "picking is unsqueezed;
			showing is not", stated where only the showing half exists. ]]
		local function soloFallback(offerW: number): any
			local kids: { solver.Node } = {}
			for i = 1, 3 do
				table.insert(kids, { kind = "box", id = `f{i}`, width = fixed(70), height = fixed(20) })
			end
			local root: solver.Node = {
				kind = "vstack",
				id = "screen",
				width = fixed(offerW),
				height = fixed(200),
				children = {
					{
						kind = "fits",
						id = "ladder",
						children = { { kind = "hstack", id = "only", width = { type = "hug" }, children = kids } },
					},
				},
			}
			return solver.solve(root, { w = offerW, h = 200 }, { rootPolicy = "edgeToEdge" })
		end
		-- 3 x 70 with no gap = 210 of natural width, and it is the only rung
		expect(`uncapped at 400: {soloFallback(400).rects.only.rect.w}`).toBe("uncapped at 400: 210")
		expect(`capped at 150: {soloFallback(150).rects.only.rect.w}`).toBe("capped at 150: 150")
		expect(`capped at 90: {soloFallback(90).rects.only.rect.w}`).toBe("capped at 90: 90")
	end)

	--[[ ...AND A `hug` CAP INSIDE THE OFFER IS AN INSTRUCTION, NOT A SHORTAGE.
		`{ type = "hug", max = 150 }` says "never wider than 150" — the author's own
		declaration — so the probe honours it and the rung genuinely does not want
		more than 150. The distinction is the same one `recordTextFacts` draws with
		`authoredWidth`: a pin that cuts is the author's pin, not the box being too
		small. So this rung FITS a 200px offer and wins. ]]
	it("an author's own `max` on a `hug` rung is honoured by the probe", function()
		local r = ladder({ type = "hug", max = 150 }, 200)
		expect(`rich hidden={r.rects.rich.hidden == true}`).toBe("rich hidden=false")
		expect(`rich w={r.rects.rich.rect.w}`).toBe("rich w=150")
	end)

	--[[ THE PROBE IS SCOPED TO THE PROBE. A `hug` node OUTSIDE any ladder is
		untouched — this is the case that would catch a fix applied to
		`resolveAxis` unconditionally, which would break every hugging panel in the
		library at once. ]]
	it("a `hug` node outside a ladder still caps at the offer", function()
		local root: solver.Node = {
			kind = "vstack",
			id = "screen",
			width = fixed(200),
			height = fixed(200),
			children = {
				{
					kind = "hstack",
					id = "panel",
					gap = 10,
					width = { type = "hug" },
					children = {
						{ kind = "box", id = "a", width = fixed(100), height = fixed(20) },
						{ kind = "box", id = "b", width = fixed(100), height = fixed(20) },
						{ kind = "box", id = "c", width = fixed(100), height = fixed(20) },
					},
				},
			},
		}
		local r = solver.solve(root, { w = 200, h = 200 }, { rootPolicy = "edgeToEdge" })
		expect(`panel w={r.rects.panel.rect.w}`).toBe("panel w=200")
	end)
end)

--[[ ===== THE DECISION AS A VALUE (framework-gaps-phase2 §2b) ================

	`ViewThatFits` answers "does it fit?" by mounting a subtree. A consumer often
	needs the same answer as a VALUE — to reserve space in a sibling, to place or
	skip a minimap, to choose between two SURFACES before either is built — and
	`adaptive.conditions` could not help because every condition there is
	viewport-relative.

	THE PROPERTY THAT MAKES IT SAFE TO USE is not that the arithmetic is right,
	it is that it is the SAME arithmetic: a screen that reserves room for an
	arrangement the solver then refuses to use is worse than one that never
	reserved. So the sweep below drives the ladder and the helper side by side and
	requires that they never disagree. ]]
describe("adaptive.fits — the container-relative decision as a value", function()
	local function laddersChoice(offerW: number): string
		return if ladder({ type = "content" }, offerW).rects.rich.hidden == true then "plain" else "rich"
	end

	it("agrees with the ViewThatFits ladder at every width in a sweep", function()
		-- the rich rung is three 100px boxes with a 10px gap between them, which is
		-- exactly what `needs` names — the parts, not a pre-computed 320
		local core = customFactory.new()
		local disagreements = {}
		for offerW = 120, 400, 20 do
			local decides = adaptive.fits(core, { needs = { 100, 100, 100 }, gap = 10, container = offerW })
			local asValue = if decides:get() then "rich" else "plain"
			if asValue ~= laddersChoice(offerW) then
				table.insert(disagreements, `{offerW}:value={asValue},ladder={laddersChoice(offerW)}`)
			end
		end
		expect(`disagreements={table.concat(disagreements, " ")}`).toBe("disagreements=")
	end)

	it("re-resolves when a part moves, which a pre-summed constant cannot", function()
		--[[ THE HAND-SUM DEFECT, as a measurement. Rascal Rally's
			`GROUP_NATURAL_W = 100 + 10 + 200` is a literal mirrored from another file
			under a "keep this in sync" comment; the chips it sums are theme metrics
			that ride the ten-foot ladder, so at a `Large` display the parts grow 1.5x
			and the constant does not. Here the second part moves and the answer
			follows it — the constant's whole failure mode, closed by naming the
			parts instead of adding them up once. ]]
		local core = customFactory.new()
		local dial = core:signal(200)
		local decides = adaptive.fits(core, { needs = { 100, dial }, gap = 10, container = 320 })
		expect(`at 200: {decides:get()}`).toBe("at 200: true")
		dial:set(300) -- the ten-foot ladder moving the dial 1.5x
		expect(`at 300: {decides:get()}`).toBe("at 300: false")
	end)

	it("clearance is subtracted from the container, not from the content", function()
		local core = customFactory.new()
		expect(`exact: {adaptive.fits(core, { needs = 310, container = 310 }):get()}`).toBe("exact: true")
		expect(`with 24 clearance: {adaptive.fits(core, { needs = 310, container = 310, clearance = 24 }):get()}`).toBe(
			"with 24 clearance: false"
		)
	end)

	it("an unbounded container fits everything, exactly as the ladder's own test does", function()
		expect(`fitsIn(1e9, huge)={adaptive.fitsIn(1e9, math.huge)}`).toBe("fitsIn(1e9, huge)=true")
	end)

	--[[ A PART THAT ARRIVES `nil` IS REFUSED. That is the hand sum's real failure
		mode — `a + b + c` where `b` went away silently counts it as nothing and
		reports a fit — so the helper that replaces the sum may not reproduce it. ]]
	--[[ A LIVE PART THAT RESOLVES TO nil CANNOT BE REFUSED AT CONSTRUCTION, so it
		is refused where it resolves — and a memo's compute is pcall-quarantined by
		the reactive core, which means the refusal lands on `core:lastError()` and
		the decision holds its LAST GOOD answer rather than unwinding. That is the
		core's universal contract for a contained failure, not a rule this helper
		invented, and it is exactly the difference from the hand sum: `a + b + c`
		with `b` gone reports a NEW, wrong, confident answer, while this reports the
		last honest one and says on the core that it could not be recomputed. ]]
	it("a live part that resolves to nil reaches the core's error channel", function()
		local core = customFactory.new()
		local gone = core:signal(200 :: any)
		local decides = adaptive.fits(core, { needs = { 100, gone }, gap = 10, container = 400 })
		expect(`while the part is there: {decides:get()}`).toBe("while the part is there: true")
		gone:set(nil)
		decides:get()
		expect(`core recorded it: {string.find(tostring(core:lastError()), "spec.needs", 1, true) ~= nil}`).toBe(
			"core recorded it: true"
		)
		--[[ ...AND IT DID NOT INVENT A NEW ANSWER. The hand sum's failure is that a
			missing part makes the total SMALLER and the verdict MORE permissive; here
			the verdict cannot move at all while the input is unreadable. ]]
		expect(`held its last good answer: {decides:get()}`).toBe("held its last good answer: true")
	end)

	it("refuses a static part that is not a number, at construction", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			return adaptive.fits(core, { needs = { 100, "wide" :: any }, container = 400 })
		end)
		expect(`refused={not ok}`).toBe("refused=true")
		expect(`names the part={string.find(tostring(err), "spec.needs[2]", 1, true) ~= nil}`).toBe(
			"names the part=true"
		)
	end)

	--[[ ...AND A HOLE IN THE LIST IS THE SAME DEFECT WRITTEN AS A LITERAL. Lua
		reports `#{ 100, nil, 200 }` as 1 on this VM, so a naive sum drops two thirds
		of the row and answers "it fits" — the hand sum's failure reproduced one
		layer down, which is why the count is checked against the length. ]]
	it("refuses a list with a hole in it, at construction", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			return adaptive.fits(core, { needs = { 100, nil :: any, 200 }, gap = 10, container = 400 })
		end)
		expect(`refused={not ok}`).toBe("refused=true")
		expect(`says which={string.find(tostring(err), "nil in the", 1, true) ~= nil}`).toBe("says which=true")
	end)

	it("refuses an unknown key, so a misspelled `clearence` cannot be silently ignored", function()
		local core = customFactory.new()
		local ok = pcall(function()
			return adaptive.fits(core, { needs = 10, container = 20, clearence = 5 } :: any)
		end)
		expect(`refused={not ok}`).toBe("refused=true")
	end)
end)
