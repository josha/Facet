--!strict
--[[
	text_fit — the derivation three separate consumer sites had each grown a
	private approximation of (2026-08-02). These pin the two properties that make
	it safe to replace those copies with: the answer is the LARGEST size that
	genuinely fits (verified against the measurer, not against the search), and
	where it cannot fit it says so rather than returning a size that clips.
]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local textFit = require("../src/layout/text_fit")
local textMetrics = require("../src/layout/text_metrics")

local FONT = "BuilderSans"

describe("text_fit.fit — the largest size that actually fits", function()
	it("returns the cap untouched when the string already fits at it", function()
		local fit = textFit.fit({ text = "1st place", font = FONT, cap = 44, width = 4000, lines = 1 })
		expect(`size={fit.size}`).toBe("size=44")
		expect(`fits={fit.fits}`).toBe("fits=true")
	end)

	it("the answer FITS and the next size up does NOT — verified against the measurer", function()
		--[[ The property that makes this a replacement for three character-count
			estimates: it is not "close enough", it is the maximum. Checked against
			`measure` directly so the search cannot mark its own homework. ]]
		for _, case in
			{
				{ text = "You earned 100 points towards the Chaos Cup!", width = 240, lines = 2, cap = 44 },
				{ text = "BEACH-BALL BUMPER", width = 86, lines = 1, cap = 18 },
				{ text = "Drag to steer", width = 173, lines = 2, cap = 22 },
			}
		do
			local fit = textFit.fit({
				text = case.text,
				font = FONT,
				cap = case.cap,
				width = case.width,
				lines = case.lines,
			})
			local at = textMetrics.measure(case.text, FONT, fit.size, case.width, nil, case.lines)
			expect(`{case.text}:fits={at.naturalLines <= case.lines}`).toBe(`{case.text}:fits=true`)
			if fit.size < case.cap then
				local above = textMetrics.measure(case.text, FONT, fit.size + 1, case.width, nil, case.lines)
				expect(`{case.text}:maximal={above.naturalLines > case.lines}`).toBe(`{case.text}:maximal=true`)
			end
		end
	end)

	it("a box that cannot hold the string at its floor says `fits = false`", function()
		--[[ The caller's cue to DROP or STEP DOWN. Returning a size that clips
			would push a layout decision into a type decision, which is exactly the
			trade the character-count estimates were making silently. ]]
		local fit =
			textFit.fit({ text = "BEACH-BALL BUMPER", font = FONT, cap = 18, width = 20, lines = 1, floor = 11 })
		expect(`fits={fit.fits}`).toBe("fits=false")
		expect(`floored={fit.size}`).toBe("floored=11")
	end)

	it("honours a HEIGHT constraint as well as a width", function()
		local wide =
			{ text = "You earned 25 coins towards kart upgrades.", font = FONT, cap = 40, width = 240, lines = 2 }
		local unbounded = textFit.fit(wide)
		local bounded = textFit.fit({
			text = wide.text,
			font = FONT,
			cap = 40,
			width = 240,
			lines = 2,
			height = 30,
		})
		expect(`smaller={bounded.size < unbounded.size}`).toBe("smaller=true")
		expect(`inBox={bounded.height <= 30}`).toBe("inBox=true")
	end)

	it("is monotone: a wider box never returns a smaller size", function()
		local last = 0
		for _, w in { 60, 100, 160, 240, 400, 900 } do
			local size =
				textFit.size({ text = "You earned Rally Points!", font = FONT, cap = 44, width = w, lines = 1 })
			expect(`w{w}:monotone={size >= last}`).toBe(`w{w}:monotone=true`)
			last = size
		end
	end)

	it("an empty string is a fit at the cap, and a zero-width box never errors", function()
		expect(`empty={textFit.fit({ text = "", font = FONT, cap = 20, width = 100 }).fits}`).toBe("empty=true")
		local zero = textFit.fit({ text = "x", font = FONT, cap = 20, width = 0 })
		expect(`zeroFits={zero.fits}`).toBe("zeroFits=false")
	end)

	it("reports whether the answer is EXACT or the conservative fallback", function()
		-- an uncalibrated font takes the over-estimating path, so the size it
		-- returns is smaller than strictly necessary — never larger.
		local unknown = textFit.fit({ text = "Rally Points", font = "NotACalibratedFace", cap = 24, width = 90 })
		expect(`known={type(unknown.exact)}`).toBe("known=boolean")
	end)

	it("the paint-time offset shrinks the answer: a Largest player fits fewer authored px (LTN-1)", function()
		-- the box that exactly holds the string at Medium must NOT hold it once
		-- the engine paints +14 on top: the returned size gives the offset back
		local spec = { text = "Sponsor a Race", font = FONT, cap = 24, width = 160 }
		local medium = textFit.fit(spec)
		local largest = textFit.fit({
			text = spec.text,
			font = spec.font,
			cap = spec.cap,
			width = spec.width,
			offset = 14,
		})
		expect(`shrinks={largest.size < medium.size}`).toBe("shrinks=true")
		-- the fit claim is about the PAINTED form: authored size + 14 must fit
		-- the same box the painted Medium answer fit
		local painted = textFit.fit({
			text = spec.text,
			font = spec.font,
			cap = largest.size + 14,
			width = spec.width,
		})
		expect(`paintedFits={painted.fits}`).toBe("paintedFits=true")
	end)

	it("offset zero and absent are byte-identical (the pre-8.5 answer); NaN is refused at the boundary", function()
		local base = textFit.fit({ text = "Rally", font = FONT, cap = 24, width = 60 })
		local zero = textFit.fit({ text = "Rally", font = FONT, cap = 24, width = 60, offset = 0 })
		expect(`size={zero.size == base.size} fits={zero.fits == base.fits}`).toBe("size=true fits=true")
		local ok = pcall(function()
			return textFit.fit({ text = "Rally", font = FONT, cap = 24, width = 60, offset = 0 / 0 })
		end)
		expect(ok).toBe(false)
	end)
end)

--[[ ONE NAMESPACE, ONE ARGUMENT CONVENTION (api-architecture-consistency F-31).
	`LuauUI.text` shipped `fit`/`size` taking a spec table and `measure` taking six
	positional arguments — the same question asked two ways, in three functions
	exported in one commit. `measure` now ALSO accepts the spec table (detected by
	a table-typed first argument), with the vocabulary its siblings use. The
	positional form is untouched: every existing caller, internal and shipped,
	keeps working. ]]
describe("text.measure — the spec-table form (F-31)", function()
	it("both forms answer identically for the same inputs", function()
		local cases = {
			{ text = "You earned 100 points towards the Chaos Cup!", size = 18, width = 240, maxLines = 2 },
			{ text = "BEACH-BALL BUMPER", size = 24, width = 86 },
			{ text = "", size = 14, width = 100 },
			{ text = "Drag to steer", size = 22, width = 173, lineHeight = 1.35, maxLines = 3 },
		}
		for _, case in cases do
			local positional =
				textMetrics.measure(case.text, FONT, case.size, case.width, case.lineHeight, case.maxLines)
			local spec = textMetrics.measure({
				text = case.text,
				font = FONT,
				size = case.size,
				width = case.width,
				lineHeight = case.lineHeight,
				maxLines = case.maxLines,
			})
			expect(`w={spec.width} h={spec.height} l={spec.lines} n={spec.naturalLines}`).toBe(
				`w={positional.width} h={positional.height} l={positional.lines} n={positional.naturalLines}`
			)
			expect(`trunc={spec.truncated} state={spec.state} exact={spec.exact}`).toBe(
				`trunc={positional.truncated} state={positional.state} exact={positional.exact}`
			)
		end
	end)

	it("a missing or mistyped key fails at the call site, naming the legal set", function()
		local ok, err = pcall(function()
			-- `fontSize` is the POSITIONAL parameter's name, and the likeliest typo
			return textMetrics.measure({ text = "x", font = FONT, fontSize = 18, width = 100 } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "fontSize", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "size", 1, true) ~= nil).toBe(true)

		local missing = pcall(function()
			return textMetrics.measure({ text = "x", font = FONT, width = 100 } :: any)
		end)
		expect(missing).toBe(false)
	end)
end)

--[[ `Fit` CARRIES THE MEASURE'S STATE (api-architecture-consistency F-32).
	`Metrics.state` distinguishes "the font is uncalibrated, the engine has not
	answered yet" (`pending`) from "an engine measurement failed" (`failed`) from
	`ready`; `Fit` kept only `exact`, which covers both. The state reported is the
	state of the measure at the CHOSEN size — the one the caller is about to
	paint at. ]]
describe("text_fit.fit — the state of the measure at the chosen size (F-32)", function()
	it("a calibrated font reports the same state its measure does", function()
		local spec = { text = "Rally Points", font = FONT, cap = 24, width = 90, lines = 1 }
		local fit = textFit.fit(spec)
		local atChosen = textMetrics.measure(spec.text, spec.font, fit.size, spec.width, nil, spec.lines)
		expect(fit.state).toBe(atChosen.state)
		expect(fit.state).toBe("ready")
	end)

	it("an uncalibrated font says `pending`, not merely `exact = false`", function()
		local fit = textFit.fit({ text = "Rally Points", font = "NotACalibratedFace", cap = 24, width = 90 })
		expect(fit.state).toBe("pending")
	end)

	it("the cap-fits and empty-string paths carry it too", function()
		local wide = textFit.fit({ text = "ok", font = "NotACalibratedFace", cap = 20, width = 4000 })
		expect(wide.size).toBe(20) -- the cap fit outright
		expect(wide.state).toBe("pending")
		local empty = textFit.fit({ text = "", font = FONT, cap = 20, width = 100 })
		expect(empty.state).toBe("ready")
	end)
end)

describe("text.fit is strict at its boundary (architecture review F-6)", function()
	it("an unknown spec key is refused, naming it", function()
		local ok, err = pcall(function()
			return textFit.fit({ text = "x", font = FONT, cap = 20, width = 100, offsetx = 5 })
		end)
		expect(`ok={ok} names={string.find(tostring(err), "offsetx") ~= nil}`).toBe("ok=false names=true")
	end)

	it("a mistyped offset is refused, never silently measured at 0", function()
		local ok, err = pcall(function()
			return textFit.fit({ text = "x", font = FONT, cap = 20, width = 100, offset = "big" })
		end)
		expect(`ok={ok} names={string.find(tostring(err), "offset") ~= nil}`).toBe("ok=false names=true")
	end)
end)
