--!strict
--[[ THE TYPED SENSORY PROFILE (`src/client/sensory_profile.luau`) — the three
	Facet default waveforms, the per-phase override/silence rules, and the preset
	fallback.

	WHY A SEPARATE MODULE AND A SEPARATE SPEC. The waveforms ARE the product: a
	number changed here changes what a player feels, on a surface no headless test
	and no Studio session can ever perceive. So they are pinned BYTE-EXACTLY —
	times, intensities and interpolation modes, as a table equality — rather than
	described. A test that says "press peaks around 0.9" would accept 0.89, and
	nothing downstream of it would ever notice.

	THE TWO CONSTRAINTS THE VALUES CARRY, and why each one is a test rather than a
	comment (docs/research/2026-08-12-haptics-engine-facts.md §7):

	  * peaks stay >= 0.3 — the full-release announcement records that "haptic
	    intensity below 0.1 may not trigger any haptic effects" on some clients, so
	    an authored subtlety below that floor is a silence that reports success;
	  * total durations stay <= 34 ms — rapid interaction (a flicked stepper, a
	    double tap) must not overlap two pulses perceptibly.

	These values are ORIGINAL Facet designs, tuned for the semantic role of each
	phase. Nothing here is copied from another platform's waveform data, and no
	other platform publishes any. Perceived similarity is a DEVICE judgement and
	is recorded as PENDING_DEVICE in
	artifacts/release-candidate-review/haptics/defaults.md — this file cannot feel
	anything and does not claim to.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local profile = require("../src/client/sensory_profile")

describe("sensory profile: the three defaults are the product, pinned exactly", function()
	it("press is `contact` — one short, crisp tap when the action goes down", function()
		expect(profile.DEFAULTS.press).toEqual({
			kind = "custom",
			name = "contact",
			keys = {
				{ timeMs = 0, intensity = 0, mode = "Linear" },
				{ timeMs = 6, intensity = 0.9, mode = "Cubic" },
				{ timeMs = 30, intensity = 0, mode = "Linear" },
			},
		})
	end)

	it("release is `settle` — a lighter, rounder answer when the action completes", function()
		expect(profile.DEFAULTS.release).toEqual({
			kind = "custom",
			name = "settle",
			keys = {
				{ timeMs = 0, intensity = 0, mode = "Linear" },
				{ timeMs = 10, intensity = 0.5, mode = "Cubic" },
				{ timeMs = 34, intensity = 0, mode = "Linear" },
			},
		})
	end)

	it("select is `tick` — the smallest audible-to-the-hand step for a changed choice", function()
		expect(profile.DEFAULTS.select).toEqual({
			kind = "custom",
			name = "tick",
			keys = {
				{ timeMs = 0, intensity = 0, mode = "Linear" },
				{ timeMs = 4, intensity = 0.35, mode = "Linear" },
				{ timeMs = 16, intensity = 0, mode = "Linear" },
			},
		})
	end)

	it("the three names are distinct, and PHASES lists exactly the three phases", function()
		expect(profile.PHASES).toEqual({ "press", "release", "select" })
		local names: { string } = {}
		for _, phase in profile.PHASES do
			local spec: any = profile.DEFAULTS[phase]
			expect(spec.kind).toBe("custom")
			table.insert(names, spec.name)
		end
		expect(names).toEqual({ "contact", "settle", "tick" })
	end)

	it("no default key authors an intensity below the documented trigger floor", function()
		-- research §7: "haptic intensity below 0.1 may not trigger any haptic
		-- effects" on some clients. A zero is a curve ENDPOINT, not an authored
		-- subtlety; what must clear the floor is the PEAK.
		for _, phase in profile.PHASES do
			local spec: any = profile.DEFAULTS[phase]
			local peak = 0
			for _, key in spec.keys do
				expect(key.intensity >= 0 and key.intensity <= 1).toBe(true)
				if key.intensity > peak then
					peak = key.intensity
				end
			end
			expect(`{phase} peak >= {profile.MIN_PEAK}: {peak >= profile.MIN_PEAK}`).toBe(
				`{phase} peak >= {profile.MIN_PEAK}: true`
			)
		end
		expect(profile.MIN_PEAK).toBe(0.3)
	end)

	it("no default outlasts the overlap budget, and every key list rises in time from 0", function()
		expect(profile.MAX_DURATION_MS).toBe(34)
		for _, phase in profile.PHASES do
			local spec: any = profile.DEFAULTS[phase]
			expect(spec.keys[1].timeMs).toBe(0)
			local previous = -1
			for _, key in spec.keys do
				expect(`{phase} {key.timeMs} > {previous}`).toBe(`{phase} {key.timeMs} > {previous}`)
				expect(key.timeMs > previous).toBe(true)
				previous = key.timeMs
			end
			expect(`{phase} duration {previous} <= 34: {previous <= profile.MAX_DURATION_MS}`).toBe(
				`{phase} duration {previous} <= 34: true`
			)
		end
	end)

	it("every mode names a real Enum.KeyInterpolationMode member", function()
		-- the engine's three, and no fourth: a typo here is a runtime throw on the
		-- device and a silent nothing everywhere a test can look
		for _, phase in profile.PHASES do
			local spec: any = profile.DEFAULTS[phase]
			for _, key in spec.keys do
				expect(table.find(profile.MODES, key.mode) ~= nil).toBe(true)
			end
		end
		expect(profile.MODES).toEqual({ "Constant", "Linear", "Cubic" })
	end)

	it("the defaults are FROZEN all the way down — a consumer cannot edit the product", function()
		local ok = pcall(function()
			(profile.DEFAULTS :: any).press = nil
		end)
		expect(ok).toBe(false)
		local deep = pcall(function()
			(profile.DEFAULTS.press :: any).keys[2].intensity = 0.1
		end)
		expect(deep).toBe(false)
	end)
end)

describe("sensory profile: resolve() merges a partial over the defaults", function()
	it("nothing supplied is the defaults, value for value", function()
		expect(profile.resolve(nil)).toEqual(profile.DEFAULTS)
		expect(profile.resolve({})).toEqual(profile.DEFAULTS)
	end)

	it("a game replaces ONE phase and keeps the other two", function()
		local mine =
			{ kind = "custom" :: any, name = "thud", keys = { { timeMs = 0, intensity = 0.6, mode = "Linear" } } }
		local resolved = profile.resolve({ press = mine })
		expect(resolved.press).toEqual(mine)
		expect(resolved.release).toEqual(profile.DEFAULTS.release)
		expect(resolved.select).toEqual(profile.DEFAULTS.select)
	end)

	it("a game swaps a phase for a PRESET without touching any control", function()
		local resolved = profile.resolve({ select = { kind = "preset", effect = "UIHover" } })
		expect(resolved.select).toEqual({ kind = "preset", effect = "UIHover" })
		expect(resolved.press).toEqual(profile.DEFAULTS.press)
	end)

	it("a game SILENCES one phase, and silence is a decision rather than an omission", function()
		local resolved = profile.resolve({ release = { kind = "silent" } })
		expect(resolved.release).toEqual({ kind = "silent" })
		expect(resolved.press).toEqual(profile.DEFAULTS.press)
		expect(resolved.select).toEqual(profile.DEFAULTS.select)
	end)

	it("all three at once, in one call", function()
		local resolved = profile.resolve({
			press = { kind = "silent" },
			release = { kind = "silent" },
			select = { kind = "silent" },
		})
		for _, phase in profile.PHASES do
			expect((resolved :: any)[phase].kind).toBe("silent")
		end
	end)

	it("the result is frozen too, so a resolved profile cannot be edited behind the adapter", function()
		local resolved = profile.resolve({ press = { kind = "silent" } })
		expect(pcall(function()
			(resolved :: any).select = nil
		end)).toBe(false)
	end)

	it("an unknown phase key is an authoring error that names the three phases", function()
		local ok, err = pcall(function()
			return profile.resolve({ hover = { kind = "silent" } } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "press", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "release", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "select", 1, true) ~= nil).toBe(true)
	end)

	it("a Custom phase with NO keys is refused — it is the guaranteed silent no-op", function()
		-- the game-side lesson this framework inherited: a `Custom` effect that was
		-- never handed a waveform plays nothing at all while reporting success. A
		-- profile that asks for one is asking for a silence it cannot see, so it is
		-- an authoring error rather than an accepted declaration.
		local ok, err = pcall(function()
			return profile.resolve({ press = { kind = "custom", name = "empty", keys = {} } } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "silent", 1, true) ~= nil).toBe(true)
	end)

	it("a spec whose `kind` is not one of the three is refused", function()
		expect(pcall(function()
			return profile.resolve({ press = { kind = "rumble" } } :: any)
		end)).toBe(false)
		expect(pcall(function()
			return profile.resolve({ press = "UIClick" } :: any)
		end)).toBe(false)
	end)

	it("a preset naming something that is not a HapticEffectType is refused", function()
		-- `UISelection` is the exact name this repository guessed once, live: the
		-- engine THROWS on the index rather than answering nil, and a fallback to
		-- `Custom` would have been silent
		expect(pcall(function()
			return profile.resolve({ select = { kind = "preset", effect = "UISelection" } } :: any)
		end)).toBe(false)
		expect(pcall(function()
			return profile.resolve({ select = { kind = "preset", effect = "UIHover" } } :: any)
		end)).toBe(true)
	end)

	it("`Custom` may not be named as a PRESET — it is a silent no-op by construction", function()
		expect(pcall(function()
			return profile.resolve({ select = { kind = "preset", effect = "Custom" } } :: any)
		end)).toBe(false)
	end)
end)

describe("sensory profile: the preset FALLBACK, and the limitation it carries", function()
	it("names one preset per phase, and every one is a real HapticEffectType", function()
		expect(profile.FALLBACK).toEqual({ press = "UIClick", release = "UIHover", select = "UIHover" })
		for _, phase in profile.PHASES do
			local name = (profile.FALLBACK :: any)[phase]
			expect(table.find(profile.EFFECT_TYPES, name) ~= nil).toBe(true)
			expect(name == "Custom").toBe(false)
		end
	end)

	it("is TOTAL over the phases — a fourth phase would be a visible gap", function()
		local covered = 0
		for phase in profile.FALLBACK :: any do
			expect(table.find(profile.PHASES, phase) ~= nil).toBe(true)
			covered += 1
		end
		expect(covered).toBe(#profile.PHASES)
	end)

	it("release and select SHARE UIHover, and that is the documented limitation", function()
		-- the platform ships exactly three UI presets (UIHover / UIClick /
		-- UINotification) and one of them — UINotification — is described as
		-- drawing attention away from gameplay, which is not what a released button
		-- or a changed choice means. So under fallback the two quiet phases are
		-- distinct only BY CAUSE, and press keeps UIClick's crisp character.
		expect(profile.FALLBACK.release).toBe(profile.FALLBACK.select)
		expect(profile.FALLBACK.press).never().toBe(profile.FALLBACK.release)
		local uiPresets = 0
		for _, name in profile.EFFECT_TYPES do
			if string.sub(name, 1, 2) == "UI" then
				uiPresets += 1
			end
		end
		expect(uiPresets).toBe(3)
	end)

	it("fallbackFor(phase) hands back the phase's preset SPEC, ready to pool", function()
		expect(profile.fallbackFor("press")).toEqual({ kind = "preset", effect = "UIClick" })
		expect(profile.fallbackFor("release")).toEqual({ kind = "preset", effect = "UIHover" })
		expect(profile.fallbackFor("select")).toEqual({ kind = "preset", effect = "UIHover" })
	end)
end)

describe("sensory profile: key() is what makes pooling possible", function()
	it("two specs that would FEEL the same share a key; different ones do not", function()
		expect(profile.key(profile.DEFAULTS.press)).toBe("custom:contact")
		expect(profile.key(profile.DEFAULTS.release)).toBe("custom:settle")
		expect(profile.key(profile.DEFAULTS.select)).toBe("custom:tick")
		expect(profile.key({ kind = "preset", effect = "UIClick" })).toBe("preset:UIClick")
		expect(profile.key({ kind = "silent" })).toBe("silent")
	end)

	it("the three default keys are distinct — three waveforms, three instances", function()
		local seen: { [string]: boolean } = {}
		local n = 0
		for _, phase in profile.PHASES do
			local k = profile.key((profile.DEFAULTS :: any)[phase])
			if not seen[k] then
				seen[k] = true
				n += 1
			end
		end
		expect(n).toBe(3)
	end)

	it("label() names a sensation for a reader — the waveform, or the preset, or nothing", function()
		expect(profile.label(profile.DEFAULTS.press)).toBe("contact")
		expect(profile.label({ kind = "preset", effect = "UINotification" })).toBe("UINotification")
		expect(profile.label({ kind = "silent" })).toBeNil()
		expect(profile.label(nil)).toBeNil()
	end)
end)

describe("sensory profile: it is ENGINE-FREE, which is why any of this is provable", function()
	it("requires nothing and names no engine global — in CODE, not in prose", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/client/sensory_profile.luau")
		-- THE COMMENTS ARE STRIPPED FIRST, and that is the whole reason this case
		-- can be trusted: the header explains `FloatCurveKey.new(ms, 0..1,
		-- Enum.KeyInterpolationMode)` in prose because a reader needs to know where
		-- that construction DOES happen. A scan that matched the word would fail on
		-- the documentation and pass on a file whose docs were deleted.
		local code = string.gsub(source, "%-%-%[%[.-%]%]", "")
		code = string.gsub(code, "\n%s*%-%-[^\n]*", "\n")
		-- CONSTRUCTION and IMPORT, not vocabulary: the error messages below name
		-- `Instance` and `Enum.KeyInterpolationMode` in their text on purpose,
		-- because an author reading a refusal needs the engine's own words.
		for _, symbol in { "FloatCurveKey.new", "Instance.new", ":GetService(", "require(", "getfenv" } do
			expect(`{symbol}:{string.find(code, symbol, 1, true) ~= nil}`).toBe(`{symbol}:false`)
		end
		-- ...and the stripper really did leave the code behind
		expect(string.find(code, "sensory_profile.DEFAULTS", 1, true) ~= nil).toBe(true)
		expect(string.find(code, "contact", 1, true) ~= nil).toBe(true)
	end)
end)
