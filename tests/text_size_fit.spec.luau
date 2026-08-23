--!strict
--[[
	`textSize = "fit"` — the declarative face of `Facet.text.fit` (audit §10,
	framework-gaps-phase2). THE HIGHEST-SEVERITY GAP IN THAT AUDIT, because unlike
	the others it was shipping wrong pixels: api.md's own `text` section records
	that a 2026-08 survey found SEVEN near-duplicates of this arithmetic in this
	repository and exactly one of them correct.

	WHY THE IMPERATIVE ROUTE LOST, and it is not a taste argument: a character
	count times a constant is ONE LINE, while `text.fit` costs a memo, a `use`, an
	env read and a font name — per site. So four copies grew in one consumer's
	Sponsor package alone, each mirroring the framework's private
	`AVG_GLYPH_FRACTION = 0.62` and `LINE_HEIGHT_FACTOR = 1.2` under a comment
	naming the source, and three of the four were wrong.

	THE FIRST BLOCK BELOW MEASURES THAT WRONGNESS as a class, against the
	framework's own arithmetic, because "three of four are wrong" is the claim the
	prop exists to answer and a claim in a report is not evidence. The second block
	is the prop.
]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("../tests/lib/fake_target")
local textMetrics = require("../src/layout/text_metrics")
local textFit = require("../src/layout/text_fit")
local themeSnapshot = require("../src/themes/snapshot")

describe('the two constants, copied wrong — the class `textSize = "fit"` closes', function()
	--[[ DEFECT 1: A LINE-HEIGHT FACTOR OF 1.25 AGAINST THE LIBRARY'S 1.2.
		`ResultsParts.lineBox` in the consumer computes `ceil(textSize * 1.25)` while
		the same file declares `LINE_HEIGHT = 1.2` as "Facet's own default line-height
		factor" two hundred lines below it. The direction is safe — it over-reserves —
		but it is not the framework's answer, so a box predicted with it and a box the
		solver arranges cannot be compared, which is what makes a differential oracle
		impossible and lets the SECOND defect hide. ]]
	it("a 1.25 line box is not the framework's line box, and the gap grows with the size", function()
		local rows = {}
		for _, size in { 14, 18, 24, 34, 44 } do
			local mine = math.ceil(size * 1.25)
			local framework = textMetrics.lineBoxPx(size, 1)
			table.insert(rows, `{size}:{mine}-vs-{framework}`)
		end
		expect(table.concat(rows, " ")).toBe("14:18-vs-17 18:23-vs-22 24:30-vs-29 34:43-vs-41 44:55-vs-53")
		expect(`the declared factor is {textMetrics.LINE_HEIGHT_FACTOR}`).toBe("the declared factor is 1.2")
	end)

	--[[ DEFECT 2, AND IT IS THE ONE THAT SHIPS WRONG PIXELS: none of the four copies
		applies `max(typographyScale, typographyPaintScale)`. Every one of them is a
		module-level constant or a derivation from one, so at a ten-foot display —
		where the framework scales unauthored text by the type floor (ADR-0040 B-6/B-7)
		— the reserve does not move while the paint does. UNDER-reserve, in the unsafe
		direction, by exactly the ladder's factor. ]]
	it("a reserve that ignores the type ladder under-reserves by the ladder's own factor", function()
		local near = themeSnapshot.measureScale("Medium", nil)
		local tenFoot = themeSnapshot.measureScale("Large", nil)
		expect(`near={near} tenFoot={tenFoot}`).toBe("near=1 tenFoot=1.5")
		-- the shape all four copies have: a band computed once, at the authored size
		local frozen = textMetrics.lineBoxPx(textMetrics.reservedSize(24, 1, 0), 1)
		-- ...against what the same line actually costs on the ten-foot display
		local painted = textMetrics.lineBoxPx(textMetrics.reservedSize(24, tenFoot, 0), 1)
		expect(`frozen={frozen} painted={painted}`).toBe("frozen=29 painted=44")
		expect(`short by {painted - frozen}px on ONE line`).toBe("short by 15px on ONE line")
	end)

	--[[ ...AND THE TWO DEFECTS TOGETHER, which is the shipped case: a two-line band
		reserved at 1.25 and scale 1 against the same band drawn at 1.2 and scale 1.5.
		The 1.25 over-reserve does NOT cover the missing scale — it is a rounding-sized
		error hiding a 50% one, which is the reason a "conservative" constant is not a
		defence. ]]
	it("the safe-looking 1.25 does not cover the missing scale", function()
		local theirs = 2 * math.ceil(24 * 1.25)
		local ours = textMetrics.lineBoxPx(textMetrics.reservedSize(24, 1.5, 0), 2)
		expect(`theirs={theirs} ours={ours} short={ours - theirs}`).toBe("theirs=60 ours=87 short=27")
	end)
end)

--[[ ===== THE PROP ==========================================================

	Every case here drives the SHIPPED path — blueprint, mount, renderer, solver,
	adapter — because the whole claim of the prop is that the four seams cannot
	disagree, and a solver-only case would prove only one of them.
]]
local function mount(bp: any, viewport: { w: number, h: number }, facts: { [string]: any }?): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = viewport.w, h = viewport.h })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	for key, value in facts or {} do
		env:set(key, value)
	end
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return adapter, controller
end

--[[ THE PRODUCTION SHAPE, and it is the one api.md cites by name: Rascal Rally's
	role-pick CTA is a fixed 240x52 button whose label is held to ONE line
	(`RolePickScreen.textFit(str, M.buttonWidth, M.secondaryHeight, 1, off)`), so
	the WIDTH is what refuses a size. `lineLimit = 1` is how that is spelled in
	Facet, and it lives on `UI.Text`. ]]
local LONG_LABEL = "Sponsor a Race"

local function oneLine(text: string, boxW: number, boxH: number, textSize: any): any
	return UI.Screen({
		id = "S",
		children = {
			UI.Text({
				id = "Cta",
				text = text,
				width = { type = "fixed", px = boxW },
				height = { type = "fixed", px = boxH },
				lineLimit = 1,
				textSize = textSize,
			}),
		},
	})
end

local function bodyRole(): any
	return themeSnapshot.neutral().type.body
end

describe('textSize = "fit": the solver picks the size, and paint writes what it picked', function()
	it("paints the CAP when the label already fits it", function()
		local adapter = mount(oneLine("Go", 240, 52, "fit"), { w = 400, h = 300 })
		local painted = adapter.node("/S/Cta").props.textSize
		expect(`painted={painted} cap={bodyRole().size}`).toBe(`painted={bodyRole().size} cap={bodyRole().size}`)
	end)

	--[[ THE PRODUCTION SHAPE. A 120px box whose label wants more than the body role
		gives it: the size comes DOWN until the line fits, and the number it lands on
		is verified against the measurer rather than against the search. ]]
	it("steps the size down until the line fits the box, and the answer is the largest that does", function()
		local adapter = mount(oneLine(LONG_LABEL, 120, 52, "fit"), { w = 400, h = 300 })
		local painted = adapter.node("/S/Cta").props.textSize
		local role = bodyRole()
		expect(`came down from the cap: {painted < role.size}`).toBe("came down from the cap: true")
		--[[ THE ANSWER IS THE MAXIMUM, checked against `text_metrics` directly so the
			solver cannot mark its own homework: this size fits on one line and the next
			one up does not. ]]
		local at = textMetrics.measure(LONG_LABEL, role.fontKey, painted, 120, role.lineHeight, 1)
		local above = textMetrics.measure(LONG_LABEL, role.fontKey, painted + 1, 120, role.lineHeight, 1)
		expect(`fits at {painted}: {at.naturalLines <= 1}`).toBe(`fits at {painted}: true`)
		expect(`overflows at {painted + 1}: {above.naturalLines > 1}`).toBe(`overflows at {painted + 1}: true`)
	end)

	--[[ THE MEASURE AND THE PAINT AGREE, which is the property the four hand copies
		could not have: the box the solver reserved is the box the engine will draw
		into, at the size it was told to draw at. ]]
	it("the reserved box holds the painted line", function()
		local adapter = mount(oneLine(LONG_LABEL, 120, 52, "fit"), { w = 400, h = 300 })
		local node = adapter.node("/S/Cta")
		local role = bodyRole()
		local drawn = textMetrics.measure(LONG_LABEL, role.fontKey, node.props.textSize, math.huge, role.lineHeight)
		expect(`fits the width: {drawn.width <= node.rect.w}`).toBe("fits the width: true")
		expect(`fits the height: {drawn.height <= node.rect.h}`).toBe("fits the height: true")
	end)

	--[[ ===== THE HEADLINE: IT IS TYPOGRAPHY-SCALE CORRECT BY CONSTRUCTION =====
		The four hand copies each froze a size at scale 1. Here the SAME declaration,
		on the same box, at a ten-foot display, comes back DIFFERENT — because the
		ladder moved the cap and the box did not grow. No consumer arithmetic moved;
		the prop cannot be written scale-blind. ]]
	it("re-derives on a ten-foot display, where every hand copy froze", function()
		expect(`the ladder is live: {themeSnapshot.typographyPaintScale("Large")}`).toBe("the ladder is live: 1.5")
		local near = mount(oneLine("Go", 240, 52, "fit"), { w = 400, h = 300 })
		local far = mount(oneLine("Go", 240, 52, "fit"), { w = 400, h = 300 }, { displaySize = "Large" })
		local nearSize = near.node("/S/Cta").props.textSize
		local farSize = far.node("/S/Cta").props.textSize
		--[[ A LABEL THAT FITS AT BOTH CAPS PAINTS AT BOTH CAPS, and the ten-foot cap
			is the near cap through the ladder — which is the whole claim: the band the
			fit picks from is the theme's, scaled, not a frozen literal. ]]
		expect(`near={nearSize} far={farSize}`).toBe(`near={bodyRole().size} far={bodyRole().size * 1.5}`)
	end)

	--[[ ...AND THE SAME DECLARATION IN A BOX THAT DID NOT GROW COMES DOWN. This is
		the shipped failure the four copies produce: their frozen size stays put while
		the paint seam scales, so the ink lands outside the band. Here the fit sees
		the bigger band, finds it does not fit the unchanged box, and steps. ]]
	it("a ten-foot cap that no longer fits the same box steps down instead of overflowing", function()
		-- 200px holds this label on one line up to 23px of type; the ten-foot cap is
		-- 24, so the band moved past what the box can hold and the fit has to step
		local far = mount(oneLine(LONG_LABEL, 200, 52, "fit"), { w = 400, h = 300 }, { displaySize = "Large" })
		local painted = far.node("/S/Cta").props.textSize
		local role = bodyRole()
		expect(`below the ten-foot cap: {painted < role.size * 1.5}`).toBe("below the ten-foot cap: true")
		local drawn = textMetrics.measure(LONG_LABEL, role.fontKey, painted, 200, role.lineHeight, 1)
		expect(`still one line: {drawn.naturalLines <= 1}`).toBe("still one line: true")
		--[[ ...AND IT IS STILL BIGGER THAN THE NEAR ANSWER, which is what separates
			"the ladder moved the type" from "the ladder broke it": a television gets
			LARGER words than a phone even when the box refused the full 1.5x. ]]
		local near = mount(oneLine(LONG_LABEL, 200, 52, "fit"), { w = 400, h = 300 })
		expect(`ten-foot {painted} > near {near.node("/S/Cta").props.textSize}`).toBe(`ten-foot {painted} > near 16`)
		expect(`grew: {painted > near.node("/S/Cta").props.textSize}`).toBe("grew: true")
	end)

	--[[ ...AND ON THE PREFERRED-TEXT OFFSET, which is the other half of the same
		defect and the one api.md cites by name: "the production role-pick CTA
		ellipsized at Largest exactly this way". The engine adds the offset at DRAW
		time, so a size chosen without it overflows the moment the player raises their
		preference. Here the chosen size comes down by the offset's worth instead. ]]
	it("pays the preferred-text offset, so a raised preference re-sizes instead of ellipsizing", function()
		-- 240px holds this label on one line up to 27px of type: the body cap (16)
		-- fits, and the SAME cap plus the Largest preference's 14px offset does not
		local plain = mount(oneLine(LONG_LABEL, 240, 52, "fit"), { w = 400, h = 300 })
		local raised = mount(oneLine(LONG_LABEL, 240, 52, "fit"), { w = 400, h = 300 }, { preferredTextOffset = 14 })
		local plainSize = plain.node("/S/Cta").props.textSize
		local raisedSize = raised.node("/S/Cta").props.textSize
		expect(`plain={plainSize} raised={raisedSize} came down={raisedSize < plainSize}`).toBe(
			`plain={plainSize} raised={raisedSize} came down=true`
		)
		--[[ AND THE PAINTED FORM STILL FITS. `raisedSize + 14` is what the engine
			draws, and that is the number the box has to hold — the exact split the
			`offset` parameter was added to `text.fit` for. ]]
		local role = bodyRole()
		local drawn = textMetrics.measure(LONG_LABEL, role.fontKey, raisedSize + 14, 240, role.lineHeight, 1)
		expect(`painted form fits: {drawn.naturalLines <= 1}`).toBe("painted form fits: true")
	end)

	it("honours an explicit cap and floor, and never paints below the floor", function()
		local adapter = mount(oneLine(LONG_LABEL, 40, 52, { fit = { cap = "title", floor = 12 } }), {
			w = 400,
			h = 300,
		})
		expect(`floored at {adapter.node("/S/Cta").props.textSize}`).toBe("floored at 12")
	end)

	it("a cap that names a role uses that role's size as the ceiling", function()
		local adapter = mount(oneLine("Go", 240, 52, { fit = { cap = "caption" } }), { w = 400, h = 300 })
		local caption = themeSnapshot.neutral().type.caption
		expect(`painted={adapter.node("/S/Cta").props.textSize}`).toBe(`painted={caption.size}`)
	end)

	--[[ THE DEFAULT FLOOR IS THE THEME'S, NOT A LITERAL — every package is required
		to carry `caption` (`themes/package.REQUIRED_TYPE_ROLES`), so "never below this
		theme's smallest type role" survives a package swap and the ten-foot ladder in
		a way `floor = 11` never could. `text.fit`'s own raw default is 1, which would
		let a label paint unreadably rather than let the layout decide. ]]
	it("defaults its floor to the theme's caption role", function()
		local adapter = mount(oneLine(LONG_LABEL, 20, 52, "fit"), { w = 400, h = 300 })
		local caption = themeSnapshot.neutral().type.caption
		expect(`floored at the caption role: {adapter.node("/S/Cta").props.textSize}`).toBe(
			`floored at the caption role: {caption.size}`
		)
	end)

	--[[ WRAPPING IS FREE WHEN THE AUTHOR ALLOWED IT: with no `lineLimit` the
		question is the HEIGHT alone, so a phrase reflows at the cap rather than
		shrinking. That is the honest reading — only the box it must live in can
		refuse a size — and it is why the solver passes `math.huge` for the line count
		when the author named none. ]]
	it("wraps rather than shrinking when the box has the height and no lineLimit", function()
		local COPY = "Cause chaos for the other racers and earn rally points"
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.Text({
					id = "Copy",
					text = COPY,
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 120 },
					textSize = "fit",
				}),
			},
		})
		local adapter = mount(bp, { w = 400, h = 300 })
		local painted = adapter.node("/S/Copy").props.textSize
		local role = bodyRole()
		local drawn = textMetrics.measure(COPY, role.fontKey, painted, 200, role.lineHeight)
		expect(`used more than one line: {drawn.lines > 1}`).toBe("used more than one line: true")
		expect(`inside 120px: {drawn.height <= 120}`).toBe("inside 120px: true")
	end)
end)

--[[ THE PROP IS THE SHARED `textSize`, SO IT REACHES ALL FOUR TEXT-BEARING
	CLASSES. `textOf` is one function with four callers, which is what makes that
	true rather than a claim — but "one function" is exactly the sentence that goes
	stale when a fifth caller is added and forgets the third return value, so the
	classes are driven rather than reasoned about. ]]
describe('textSize = "fit": every class that carries a textSize', function()
	it("a Toggle fits its label into the box the switch leaves it", function()
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.Toggle({
					id = "Tg",
					label = "Enable the long option name",
					value = customFactory.new():signal(false),
					onActivate = function() end,
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 40 },
					textSize = "fit",
				}),
			},
		})
		local adapter = mount(bp, { w = 400, h = 300 })
		local painted = adapter.node("/S/Tg").props.textSize
		local caption = themeSnapshot.neutral().type.caption
		--[[ A Toggle's label column is its box MINUS the switch chrome, so this
			label cannot hold its role size there and the fit comes down to the floor —
			which is the answer, and the point: the prop is not silently ignored on a
			class that reaches `textOf` through a different branch. ]]
		expect(`painted={painted} floor={caption.size}`).toBe(`painted={caption.size} floor={caption.size}`)
		expect(`below the body role: {painted < themeSnapshot.neutral().type.body.size}`).toBe(
			"below the body role: true"
		)
	end)
end)

describe('textSize = "fit": the grammar is closed', function()
	it("reads both spellings and nothing else", function()
		expect(`bare={textFit.fitSpecOf("fit") ~= nil}`).toBe("bare=true")
		expect(`option={textFit.fitSpecOf({ fit = { cap = 24 } }) ~= nil}`).toBe("option=true")
		expect(`a role name={textFit.fitSpecOf("body") ~= nil}`).toBe("a role name=false")
		expect(`a number={textFit.fitSpecOf(18) ~= nil}`).toBe("a number=false")
		expect(`nil={textFit.fitSpecOf(nil) ~= nil}`).toBe("nil=false")
	end)

	--[[ AN ACCEPTED-AND-IGNORED KEY IS THE §4 VIOLATION THE PLACEMENT AUDIT EXISTS
		TO END: `{ fit = { max = 24 } }` reads like a cap and would have been silently
		dropped, leaving the node at its role size with no word anywhere. ]]
	it("refuses a misspelled option at construction", function()
		local ok, err = pcall(function()
			return UI.Text({ id = "T", text = "x", textSize = { fit = { max = 24 } } :: any })
		end)
		expect(`refused={not ok}`).toBe("refused=true")
		expect(`says which={string.find(tostring(err), "cap and floor", 1, true) ~= nil}`).toBe("says which=true")
	end)

	it("refuses a cap that is neither a px number nor a role name", function()
		local ok = pcall(function()
			return UI.Text({ id = "T", text = "x", textSize = { fit = { cap = true } } :: any })
		end)
		expect(`refused={not ok}`).toBe("refused=true")
	end)

	it("still accepts every spelling it accepted before", function()
		for _, spelling in { 18, "body", "title" } do
			local ok = pcall(function()
				return UI.Text({ id = "T", text = "x", textSize = spelling :: any })
			end)
			expect(`{tostring(spelling)} accepted={ok}`).toBe(`{tostring(spelling)} accepted=true`)
		end
	end)
end)
