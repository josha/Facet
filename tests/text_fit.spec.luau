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
end)
