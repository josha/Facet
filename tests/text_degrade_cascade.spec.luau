--!strict
--[[ THE DEGRADE CASCADE AND THE WRAP RULE — director rulings 1 and 5, 2026-08-13
	(docs/handoff/2026-08-13-rulings-needed.md §1 and §5).

	TWO RULINGS, ONE MECHANISM. They arrived as separate rows on the round-3
	ledger and they are the same fact seen from two sides:

	  RULING 1 (the cascade). A shrinkable label could land outside its box:
	  `absorbTier` absorbs at most `Sum(basis - floor)` and the residual deficit
	  was simply not absorbed. Measured: three `shrinkWeight = 1` texts in a 120px
	  box solved to `x0 w120 / x120 w120 / x240 w100` — two wholly outside.
	  Director, verbatim: *"clip is ok; should we switch to compact and then
	  truncate the text before clipping (with '...')?"* So the derived floor
	  DESCENDS a ladder — the longest word, the compact form's longest word, one
	  ellipsis — and whatever is still left is CLIPPED at the box edge.

	  RULING 5 (the wrap rule). Wrapping is right only when the phrase's LONGEST
	  WORD fits the drawable width. Below that the engine does not produce more
	  lines of the word, it BREAKS the word — and the solver's own wrap model
	  breaks only at whitespace, so it reserves a box for a shape the engine will
	  not draw.

	  Ruling 5 is what makes ruling 1's truncate rung actually paint: squeezed
	  below its longest word, a label is measured on ONE line and the engine's
	  TextTruncate.AtEnd (on for every text node) cuts it with a `…`.

	WHAT LIVES ELSEWHERE, so this file stays about the rulings and not about the
	pass they extend:
	  * the rungs and the priority-tier arithmetic — tests/stack_distribution.spec
	    ("§2.4 shrink — the floor cascade");
	  * the ledger's own three-label case, inverted — tests/layout_vocabulary.spec
	    ("(a) THE CASCADE");
	  * the word/phrase asymmetry the wrap rule sits on top of —
	    tests/button_shape.spec ("a Button's label wraps only where a break is
	    legal");
	  * the large-text consequences — tests/large_text_matrix.spec (LT6-ACTION).
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local solver = require("../src/layout/solver")
local text_metrics = require("../src/layout/text_metrics")
local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")
local l10n = require("./fixtures/a11y_l10n_fixtures")

local function fixed(px: number)
	return { type = "fixed", px = px }
end
local function fill(weight: number?)
	return { type = "fill", weight = weight or 1 }
end
local function solve(root: any, w: number, h: number)
	return solver.solve(root, { w = w, h = h }, { rootPolicy = "edgeToEdge" })
end

local function overflowIssue(result: any): string?
	for _, d in result.diagnostics do
		if string.find(d.issue, "content overflows", 1, true) ~= nil then
			return d.issue
		end
	end
	return nil
end

-- "does every child end inside its parent's box" as one readable string, so a
-- failure names the offender and its geometry instead of saying `false`
local function insideReport(result: any, ids: { string }, right: number): string
	local out: { string } = {}
	for _, id in ids do
		local rect = result.rects[id].rect
		table.insert(out, `{id}:{if rect.x + rect.w <= right then "in" else `OUT({rect.x}+{rect.w})`}`)
	end
	return table.concat(out, " ")
end

-- ===========================================================================
-- RULING 1 — the cascade, rung by rung and in order
-- ===========================================================================

describe("ruling 1: the degrade cascade descends only as far as it must", function()
	-- one row shape, one rigid sibling that decides how much room is left. Every
	-- case below is that row at a different deficit, so the ORDER of the rungs is
	-- visible as one sweep rather than as four unrelated fixtures.
	local function row(rigid: number, label: any): any
		local child: any = { kind = "text", id = "label", shrinkWeight = 1 }
		for k, v in label do
			child[k] = v
		end
		return solve({
			kind = "hstack",
			id = "R",
			width = fill(),
			children = {
				{ kind = "box", id = "rigid", width = fixed(rigid), height = fixed(20) },
				child,
			},
		}, 400, 400)
	end

	it("a row that FITS is untouched — the cascade never opens", function()
		-- "nothing that fits today moves" is a claim like any other. The label is
		-- offered more than its natural one-line width, so no rung is entered and
		-- the text keeps its whole string, wrapping unchanged.
		local r = row(100, { text = "Configuration options" })
		expect(overflowIssue(r)).toBeNil()
		local facts = r.rects.label.textFacts
		expect(`truncated={facts.truncated} wraps={facts.wraps} compact={tostring(r.rects.label.compact)}`).toBe(
			"truncated=false wraps=true compact=nil"
		)
	end)

	it("rung 1: it gives up its WRAP first, and keeps every character", function()
		-- squeezed but still wider than its longest word ("changes", ~62px at the
		-- body size, inside 100): the label reflows and nothing is cut. This is the
		-- rung that shipped before the ruling, and it has to stay reachable or the
		-- cascade has quietly replaced it rather than extended it.
		local r = row(300, { text = "Save the changes now" })
		expect(overflowIssue(r)).toBeNil()
		local facts = r.rects.label.textFacts
		expect(`w={r.rects.label.rect.w} truncated={facts.truncated} wraps={facts.wraps} lines={facts.lines}`).toBe(
			"w=100 truncated=false wraps=true lines=3"
		)
	end)

	it("rung 2: a declared COMPACT form is spent before any character is", function()
		-- the director's order, in his words: "switch to compact and THEN truncate".
		-- The floor drops to the compact form's own longest word, and the re-measure
		-- at that reduced offer is what makes the compact ladder choose it — the
		-- existing mechanism, not a parallel one.
		local r = row(340, { text = "Configuration", compactText = "Cfg" })
		expect(overflowIssue(r)).toBeNil()
		expect(r.rects.label.compact).toBe(true)
		expect(r.rects.label.textFacts.truncated).toBe(false)
	end)

	it("rung 3: with nothing better to say it TRUNCATES, on one line, with the box intact", function()
		local r = row(390, { text = "Configuration options" })
		expect(overflowIssue(r)).toBeNil()
		expect(insideReport(r, { "rigid", "label" }, 400)).toBe("rigid:in label:in")
		local facts = r.rects.label.textFacts
		expect(`lines={facts.lines} truncated={facts.truncated} wraps={facts.wraps}`).toBe(
			"lines=1 truncated=true wraps=false"
		)
	end)

	it("the rungs are ORDERED: the same deficit truncates without a compact form and does not with one", function()
		-- the two arms of the same width, which is what makes "compact first" a
		-- measured claim rather than a sentence in a comment
		local bare = row(340, { text = "Configuration" })
		local declared = row(340, { text = "Configuration", compactText = "Cfg" })
		expect(`bare={bare.rects.label.textFacts.truncated} declared={declared.rects.label.textFacts.truncated}`).toBe(
			"bare=true declared=false"
		)
	end)

	it("an authored `minMax.min` is a CONTRACT, not a rung — the cascade never descends below it", function()
		-- the framework's derived floor gives way; a number the author wrote does
		-- not. Without this the cascade would silently undo a deliberate minimum,
		-- which is a different bug wearing the fix's clothes.
		local function withMin(boxW: number)
			return solve({
				kind = "hstack",
				id = "R",
				width = fill(),
				children = {
					{ kind = "box", id = "rigid", width = fixed(340), height = fixed(20) },
					{
						kind = "text",
						id = "label",
						text = "Configuration options",
						width = { type = "minMax", min = 120, preferred = 200 },
						shrinkWeight = 1,
					},
				},
			}, boxW, 400)
		end
		-- a deficit of exactly 80 (340 + 200 - 460): the pass takes the label to its
		-- authored minimum and STOPS, with no clip in play to confuse the reading
		local exact = withMin(460)
		expect(exact.rects.label.rect.w).toBe(120)
		expect(overflowIssue(exact)).toBeNil()
		-- ...and asked for more than that, it still does not descend: the extra 60px
		-- is unabsorbable, so it reaches the clip rung instead of eating the minimum
		local jammed = withMin(400)
		expect(overflowIssue(jammed) ~= nil).toBe(true)
		expect(insideReport(jammed, { "rigid", "label" }, 400)).toBe("rigid:in label:in")
		-- the label was placed 120 wide (its contract) at x = 340 and CROPPED to the
		-- 60px the box had left — cropped, not shrunk past its minimum
		expect(`{jammed.rects.label.rect.x}+{jammed.rects.label.rect.w}`).toBe("340+60")
	end)
end)

describe("ruling 1: clip is the floor of the cascade, never its first move", function()
	-- two children whose authored minimums make the deficit genuinely unabsorbable
	local function jammed(boxW: number): any
		local function cell(id: string)
			return {
				kind = "box",
				id = id,
				width = { type = "minMax", min = 180, preferred = 200 },
				height = fixed(20),
				shrinkWeight = 1,
			}
		end
		return solve({ kind = "hstack", id = "R", children = { cell("a"), cell("b") } }, boxW, 100)
	end

	it("what the cascade cannot absorb is CROPPED at the box, not painted past it", function()
		local r = jammed(300)
		expect(insideReport(r, { "a", "b" }, 300)).toBe("a:in b:in")
		-- the crop is on the EXTENT; the position is where the flow put it, because
		-- cropping is not re-flowing
		expect(`{r.rects.b.rect.x}+{r.rects.b.rect.w}`).toBe("180+120")
	end)

	it("...and it is still LOUD: the diagnostic names the deficit, the tiers, and the clip", function()
		local issue = overflowIssue(jammed(300))
		expect(issue ~= nil).toBe(true)
		for _, fragment in { "by 60px", "already at its floor", "layoutPriority", "CLIPPED the remaining 60px" } do
			expect(`{fragment}: {string.find(issue :: string, fragment, 1, true) ~= nil}`).toBe(`{fragment}: true`)
		end
	end)

	it("a stack that declared NO shrinkWeight is untouched — it still paints outside its box", function()
		-- the scope of the crop, stated as a test. Cropping every overflowing stack
		-- in the library would be the silent re-flow of shipped screens the overflow
		-- diagnostic has always refused to be; declaring `shrinkWeight` is what opts
		-- a stack into the cascade, and the crop is that cascade's floor.
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "a", width = fixed(400), height = fixed(20) },
				{ kind = "box", id = "b", width = fixed(400), height = fixed(20) },
			},
		}, 500, 100)
		expect(insideReport(r, { "a", "b" }, 500)).toBe("a:in b:OUT(400+400)")
		expect(overflowIssue(r) ~= nil).toBe(true)
	end)
end)

-- ===========================================================================
-- RULING 5 — the wrap rule
-- ===========================================================================

describe("ruling 5: wrapping is attempted only where it can succeed", function()
	local TEXT = "Configuration options"

	local function measured(px: number): any
		local r = solve({
			kind = "vstack",
			id = "R",
			width = fixed(px),
			height = fill(),
			children = { { kind = "text", id = "label", text = TEXT } },
		}, 600, 400)
		return r.rects.label.textFacts
	end

	it("a phrase whose longest word FITS still wraps — the round-9 chips keep their two lines", function()
		-- the regression guard. "Classic Desktop" growing to two lines on a narrow
		-- phone is deliberate, and a blanket single-line rule would clip it to
		-- "Classic Deskt…" — which is what this ruling must not become.
		local wide = text_metrics.minWidth(TEXT, "BuilderSans", 16) + 20
		local facts = measured(wide)
		expect(`wraps={facts.wraps} truncated={facts.truncated}`).toBe("wraps=true truncated=false")
		expect(facts.lines > 1).toBe(true)
	end)

	it("...and one whose longest word does NOT fit is measured on ONE line instead of breaking it", function()
		local narrow = text_metrics.minWidth(TEXT, "BuilderSans", 16) - 8
		local facts = measured(narrow)
		expect(`wraps={facts.wraps} lines={facts.lines} truncated={facts.truncated}`).toBe(
			"wraps=false lines=1 truncated=true"
		)
	end)

	it("the verdict is RE-DECIDED, never latched — a wider box wraps again", function()
		-- the same discipline `compact` carries: a verdict that could only latch
		-- would keep a label single-line after a re-solve made room for the wrap.
		local wide = text_metrics.minWidth(TEXT, "BuilderSans", 16) + 20
		expect(`{measured(wide - 28).wraps} -> {measured(wide).wraps}`).toBe("false -> true")
	end)

	it("a ZERO-width box gives no verdict: a collapsed control is not a label being cut", function()
		-- measured 2026-08-13 on the row-actions tray, whose action labels sit at
		-- w = 0 while the tray is closed. Reporting those as truncated would file a
		-- finding about text nobody is being shown.
		local facts = measured(0)
		expect(`truncated={facts.truncated}`).toBe("truncated=false")
	end)
end)

describe("ruling 5: the two seams agree, because only one of them decides", function()
	local function drawAt(text: string, px: number): any
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				padding = 0,
				children = { UI.Text({ id = "T", text = text, width = { type = "fixed", px = px } }) },
			})
		)
		local controller = rendererLib.attach(core, root, env, adapter, {})
		controller.initialRender()
		local out = {
			textWrapped = adapter.node("/S/T").props.textWrapped,
			writes = controller.stats().propWrites,
			controller = controller,
			adapter = adapter,
			root = root,
		}
		return out
	end

	it("the SOLVER's verdict reaches the adapter, which cannot compute it", function()
		-- `screen_target`'s TextWrapped rule sees the string and not the box, so a
		-- phrase in a box narrower than its own longest word would wrap at paint no
		-- matter what the solve reserved — the measure/paint split this framework
		-- keeps meeting (docs/lessons/one-word-two-subsystems.md).
		local tight = drawAt("Configuration options", 40)
		expect(`tight textWrapped={tostring(tight.textWrapped)}`).toBe("tight textWrapped=false")
		tight.root.dispose()
	end)

	it("...and a box that fits costs ZERO writes: `nil` IS the adapter's wrapping default", function()
		local roomy = drawAt("Configuration options", 400)
		expect(`roomy textWrapped={tostring(roomy.textWrapped)}`).toBe("roomy textWrapped=nil")
		roomy.root.dispose()
	end)

	it("a steady re-solve writes the verdict once and never again", function()
		local w = drawAt("Configuration options", 40)
		local after = w.controller.stats().propWrites
		w.controller.refresh()
		expect(`writes after a second render: {w.controller.stats().propWrites - after}`).toBe(
			"writes after a second render: 0"
		)
		w.root.dispose()
	end)
end)

-- ===========================================================================
-- The standing localization rule (~1.4x pseudo-loc expansion) under both rulings
-- ===========================================================================

describe("the cascade holds under the studio's standing 1.4x pseudo-loc rule", function()
	-- CLAUDE.md binds this repo to copy that survives a German/Finnish-class
	-- expansion. The cascade is what makes that safe when the box cannot grow: the
	-- expanded string degrades through compact and the ellipsis instead of leaving
	-- the box, and the LAST rung guarantees nothing paints outside whatever happens.
	local SOURCE = { "Configuration options", "Save changes", "Alphabetical order" }

	it("every expanded label still lands INSIDE a box far too small for it", function()
		local children: { any } = {}
		local ids: { string } = {}
		for index, source in SOURCE do
			local id = `t{index}`
			table.insert(ids, id)
			table.insert(children, {
				kind = "text",
				id = id,
				text = l10n.pseudoLocalize(source),
				shrinkWeight = 1,
			})
		end
		local r = solve({ kind = "hstack", id = "R", gap = 0, children = children }, 120, 60)
		expect(insideReport(r, ids, 120)).toBe("t1:in t2:in t3:in")
	end)

	it("...and the expansion is REAL, or the case above proves nothing", function()
		-- the fixture's own contract is a ~1.3-1.4x width expansion; assert it here
		-- too, because a pseudo-localizer that quietly became the identity function
		-- would make every case in this describe vacuous
		for _, source in SOURCE do
			local plain = text_metrics.measure(source, "BuilderSans", 16, math.huge).width
			local expanded = text_metrics.measure(l10n.pseudoLocalize(source), "BuilderSans", 16, math.huge).width
			expect(`{source}: expanded {expanded > plain * 1.25}`).toBe(`{source}: expanded true`)
		end
	end)
end)

-- ===========================================================================
-- The break model the wrap rule reads from
-- ===========================================================================

describe("min-content width: whitespace is not the only legal break", function()
	local CJK = "\u{901F}\u{5EA6}\u{5236}\u{9650}\u{6A19}\u{8B58}\u{3068}\u{8A2D}\u{5B9A}\u{753B}\u{9762}"

	it("an ideographic run breaks between CHARACTERS, so it never claims the whole run", function()
		-- before this, `minWidth` split on `%S+` only, so a ten-character CJK line
		-- claimed a minimum ten times its true one. Harmless while it only raised a
		-- shrink floor; NOT harmless once the wrap rule decides from it, because
		-- every CJK line would report that it cannot wrap at all and be ellipsized.
		local whole = text_metrics.measure(CJK, "BuilderSans", 16, math.huge).width
		local minimum = text_metrics.minWidth(CJK, "BuilderSans", 16)
		expect(`min {minimum} << whole {whole}: {minimum <= whole / 8}`).toBe(
			`min {minimum} << whole {whole}: true`
		)
	end)

	it("...and a CJK line therefore still WRAPS rather than ellipsizing", function()
		local r = solve({
			kind = "vstack",
			id = "R",
			width = fixed(120),
			height = fill(),
			children = { { kind = "text", id = "label", text = CJK } },
		}, 600, 400)
		expect(`wraps={r.rects.label.textFacts.wraps}`).toBe("wraps=true")
	end)

	it("an EMOJI cluster is NOT split — the minimum may never be under-stated", function()
		-- the other direction is the dangerous one: splitting a ZWJ sequence would
		-- report a minimum no box can actually draw the cluster in. Everything at
		-- U+10000 and above is excluded by construction, which is what keeps it whole.
		local family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
		local whole = text_metrics.measure(family, "BuilderSans", 16, math.huge).width
		expect(text_metrics.minWidth(family, "BuilderSans", 16)).toBe(math.ceil(whole))
	end)

	it("a latin phrase is BYTE-IDENTICAL to the whitespace-only model it replaced", function()
		-- the common path must not have moved: every measured number in this repo
		-- rests on it
		for _, pair in { { "Classic Desktop", "Desktop" }, { "Edit item", "item" }, { "Save changes", "changes" } } do
			expect(`{pair[1]} -> {text_metrics.minWidth(pair[1], "BuilderSans", 16)}`).toBe(
				`{pair[1]} -> {text_metrics.minWidth(pair[2], "BuilderSans", 16)}`
			)
		end
	end)
end)
