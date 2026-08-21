--!strict
--[[ THE TYPED SENSORY PROFILE — what Facet's three interaction PHASES feel like.

	CLIENT-ONLY BY LOCATION, ENGINE-FREE BY CONSTRUCTION. This module requires
	nothing and names no engine global: a `WaveKey` here is plain data
	(`{ timeMs, intensity, mode }`), and the `FloatCurveKey.new(ms, 0..1,
	Enum.KeyInterpolationMode)` construction that turns it into something the
	engine can play happens in `haptics.luau`, the one file allowed to touch the
	platform. That split is why the waveforms below are provable at all: they are
	pinned byte-exactly by `tests/sensory_profile.spec.luau` under Lune, where
	there is no `Instance`, no `Enum` and no motor.

	THREE PHASES, NOT TWELVE VERBS. `src/present/feedback.luau`'s taxonomy says
	WHAT HAPPENED; a phase says WHEN IN THE INTERACTION a hand is touched:

	  press    the action goes DOWN. Owned by the ENGINE, through
	           `GuiButton.PressHapticEffect` — Facet hands over a reference and
	           never calls `Play()` on it.
	  release  the action COMPLETES. Owned by the bus: `GuiButton.Activated` (and
	           the presenter's collapsed keyboard/gamepad pair) is the completed
	           edge, so a press that was dragged away from never reaches it and is
	           structurally silent.
	  select   a CHOICE CHANGED (`select` / `adjust`). Rate-limited, leading-edge:
	           a suppressed pulse is DROPPED, because a haptic that arrives after
	           the gesture is a phantom.

	THE THREE WAVEFORMS BELOW ARE THE PRODUCT. They are ORIGINAL Facet designs,
	tuned for the semantic role of each phase and for the two constraints the
	platform actually documents (docs/research/2026-08-12-haptics-engine-facts.md
	§7):

	  * PEAKS STAY >= 0.3. The full-release announcement records that "haptic
	    intensity below 0.1 may not trigger any haptic effects" on some clients, so
	    a subtlety authored under that floor is a silence that reports success.
	    0.3 is the floor with margin, not the floor itself.
	  * TOTAL DURATIONS STAY <= 34 ms. Rapid interaction — a flicked stepper, a
	    double tap, a fast list scrub — must not overlap two pulses perceptibly.

	NOTHING HERE IS COPIED FROM ANOTHER PLATFORM. No other UI framework publishes
	waveform data for its semantic feedback (the comparable surface exposes
	named kinds and a single `intensity` scalar and nothing else), so there is
	nothing to copy even in principle. Whether these FEEL like anything a player
	has met elsewhere is a judgement only a hand on a device can make, and it is
	recorded as PENDING_DEVICE in
	artifacts/release-candidate-review/haptics/defaults.md. Studio cannot feel.

	AND `Custom` IS A TRAP IF IT IS EMPTY. A `HapticEffect` whose `Type` is
	`Custom` and which was never handed a waveform plays NOTHING while reporting
	success — this repository's game side shipped that bug once. So `resolve`
	refuses a custom spec with no keys, and refuses `Custom` as a PRESET name
	outright: the fallback for a custom phase that will not build is a real
	preset (`FALLBACK` below), never `Custom`.
]]

local sensory_profile = {}

-- `Enum.KeyInterpolationMode`'s three members, as data. A fourth spelling is a
-- runtime throw on the device and a silent nothing everywhere a test can look, so
-- the vocabulary is closed here and checked at resolve time.
sensory_profile.MODES = table.freeze({ "Constant", "Linear", "Cubic" })

-- `Enum.HapticEffectType`, all six members (API dump, client 0.734.0.7340915).
-- Owned HERE rather than in `haptics.luau` because this is the module that
-- validates a preset name, and `haptics.EFFECT_TYPES` re-exports this exact table
-- so the two can never disagree.
sensory_profile.EFFECT_TYPES = table.freeze({
	"Custom",
	"UIHover",
	"UIClick",
	"UINotification",
	"GameplayExplosion",
	"GameplayCollision",
})

sensory_profile.PHASES = table.freeze({ "press", "release", "select" })

-- the two constraints the defaults are held to, as numbers a test can read
sensory_profile.MIN_PEAK = 0.3
sensory_profile.MAX_DURATION_MS = 34

export type WaveKey = { timeMs: number, intensity: number, mode: "Constant" | "Linear" | "Cubic" }

export type PhaseSpec =
	{ kind: "custom", name: string, keys: { WaveKey } }
	| { kind: "preset", effect: string } -- a HapticEffectType name
	| { kind: "silent" }

export type SensoryProfile = { press: PhaseSpec, release: PhaseSpec, select: PhaseSpec }

export type PartialProfile = { press: PhaseSpec?, release: PhaseSpec?, select: PhaseSpec? }

local function freezeSpec(spec: any): any
	if spec.kind == "custom" then
		local keys = {}
		for i, key in spec.keys do
			keys[i] = table.freeze({ timeMs = key.timeMs, intensity = key.intensity, mode = key.mode })
		end
		return table.freeze({ kind = "custom", name = spec.name, keys = table.freeze(keys) })
	end
	if spec.kind == "preset" then
		return table.freeze({ kind = "preset", effect = spec.effect })
	end
	return table.freeze({ kind = "silent" })
end

--[[ THE THREE DEFAULTS. Read the CHARACTER line before the numbers: the numbers
	are how the character was reached, and a future edit that keeps the numbers and
	loses the character has changed the product without changing the test. ]]
sensory_profile.DEFAULTS = table.freeze({
	-- "one short, crisp tap when the action goes down". The rise is 6 ms — under
	-- the ~10 ms where a tap starts to read as a push — and the tail is Cubic so
	-- the decay rounds off instead of clicking twice.
	press = freezeSpec({
		kind = "custom",
		name = "contact",
		keys = {
			{ timeMs = 0, intensity = 0, mode = "Linear" },
			{ timeMs = 6, intensity = 0.9, mode = "Cubic" },
			{ timeMs = 30, intensity = 0, mode = "Linear" },
		},
	}),
	-- "a lighter, rounder answer when the action completes". Deliberately WEAKER
	-- and SLOWER than press: the down edge is the event the hand is expecting, and
	-- an equal answer on the way up reads as a double tap rather than a reply.
	release = freezeSpec({
		kind = "custom",
		name = "settle",
		keys = {
			{ timeMs = 0, intensity = 0, mode = "Linear" },
			{ timeMs = 10, intensity = 0.5, mode = "Cubic" },
			{ timeMs = 34, intensity = 0, mode = "Linear" },
		},
	}),
	-- "the smallest audible-to-the-hand step for a changed choice". All Linear and
	-- 16 ms end to end: a scrubbed picker fires this repeatedly, so it has to be
	-- over before the next one is due (the adapter's own >= 50 ms floor is the
	-- other half of that guarantee).
	select = freezeSpec({
		kind = "custom",
		name = "tick",
		keys = {
			{ timeMs = 0, intensity = 0, mode = "Linear" },
			{ timeMs = 4, intensity = 0.35, mode = "Linear" },
			{ timeMs = 16, intensity = 0, mode = "Linear" },
		},
	}),
}) :: SensoryProfile

--[[ THE FALLBACK, AND ITS LIMITATION, WRITTEN DOWN RATHER THAN DISCOVERED.

	If a client cannot construct or key a `Custom` effect, the phase falls back to
	a PRESET — never to a bare `Custom`, which would be a guaranteed silence.

	The platform ships exactly THREE UI presets: `UIHover` ("subtle and does not
	disrupt"), `UIClick` ("crisp … immediate feedback") and `UINotification`
	("draw the player's attention AWAY from their current gameplay"). A released
	button and a changed choice are neither crisp-and-immediate nor
	attention-grabbing, so both quiet phases land on `UIHover` and are distinct
	only BY CAUSE under fallback. Press keeps `UIClick`'s crisp character, which is
	the one phase the preset vocabulary actually has a word for. ]]
sensory_profile.FALLBACK = table.freeze({
	press = "UIClick",
	release = "UIHover",
	select = "UIHover",
})

-- the fallback as a poolable spec, so the adapter's build path has ONE shape
function sensory_profile.fallbackFor(phase: string): PhaseSpec
	local name = (sensory_profile.FALLBACK :: any)[phase]
	if name == nil then
		error(
			`Facet sensory_profile.fallbackFor: unknown phase '{tostring(phase)}'. The phases are: `
				.. table.concat(sensory_profile.PHASES, ", "),
			0
		)
	end
	return table.freeze({ kind = "preset", effect = name }) :: any
end

-- THE POOL KEY. Two phases that would FEEL identical must share one Instance (the
-- documented "fewer than 100 simultaneous effects" budget), and the only honest
-- identity for a sensation is the waveform's name or the preset's name.
function sensory_profile.key(spec: PhaseSpec): string
	local kind = (spec :: any).kind
	if kind == "custom" then
		return `custom:{(spec :: any).name}`
	end
	if kind == "preset" then
		return `preset:{(spec :: any).effect}`
	end
	return "silent"
end

-- what a READER should be told this phase feels like: the waveform's name, or the
-- preset's, or nothing at all for a silence. Used by the showcase fixture and the
-- docs so a written-out table cannot drift from the shipped one.
function sensory_profile.label(spec: PhaseSpec?): string?
	if spec == nil then
		return nil
	end
	local kind = (spec :: any).kind
	if kind == "custom" then
		return (spec :: any).name
	end
	if kind == "preset" then
		return (spec :: any).effect
	end
	return nil
end

local function validate(phase: string, spec: any)
	if type(spec) ~= "table" then
		error(
			`Facet sensory_profile: the '{phase}' phase must be a spec table — \{ kind = "custom", name, keys }, `
				.. `\{ kind = "preset", effect = "UIClick" } or \{ kind = "silent" } — got {typeof(spec)}.`,
			0
		)
	end
	local kind = spec.kind
	if kind == "silent" then
		return
	end
	if kind == "preset" then
		if type(spec.effect) ~= "string" or table.find(sensory_profile.EFFECT_TYPES, spec.effect) == nil then
			error(
				`Facet sensory_profile: '{phase}' names '{tostring(spec.effect)}', which is not a HapticEffectType. `
					.. `The six members are: {table.concat(sensory_profile.EFFECT_TYPES, ", ")}. `
					.. "(`UISelection` is the name this repository guessed once — the engine THROWS on that index.)",
				0
			)
		end
		if spec.effect == "Custom" then
			error(
				`Facet sensory_profile: '{phase}' names \`Custom\` as a preset. A Custom effect with no waveform plays `
					.. 'NOTHING while reporting success — declare `{ kind = "custom", name, keys }` with real keys, '
					.. 'or `{ kind = "silent" }` if silence is what you mean.',
				0
			)
		end
		return
	end
	if kind ~= "custom" then
		error(
			`Facet sensory_profile: '{phase}' has kind '{tostring(kind)}'. The three kinds are: custom, preset, silent.`,
			0
		)
	end
	if type(spec.name) ~= "string" or spec.name == "" then
		error(
			`Facet sensory_profile: a custom '{phase}' needs a \`name\` (got {typeof(spec.name)}). The name is the `
				.. "pool identity — two waveforms sharing one name would share one Instance.",
			0
		)
	end
	if type(spec.keys) ~= "table" or #spec.keys == 0 then
		error(
			`Facet sensory_profile: the custom '{phase}' waveform '{tostring(spec.name)}' has no keys. A Custom effect `
				.. 'with no waveform is a GUARANTEED silent no-op — pass real keys, or `{ kind = "silent" }`.',
			0
		)
	end
	local previous = -1
	for index, key in spec.keys do
		if type(key) ~= "table" or type(key.timeMs) ~= "number" or type(key.intensity) ~= "number" then
			error(`Facet sensory_profile: '{phase}' key #{index} must be \{ timeMs, intensity, mode }.`, 0)
		end
		if key.intensity < 0 or key.intensity > 1 then
			error(
				`Facet sensory_profile: '{phase}' key #{index} has intensity {key.intensity}; the engine's range is `
					.. "0 (no haptic) to 1 (full intensity).",
				0
			)
		end
		if key.timeMs <= previous then
			error(
				`Facet sensory_profile: '{phase}' key #{index} is at {key.timeMs} ms, which does not come after the `
					.. `previous key at {previous} ms. A waveform is a curve in time.`,
				0
			)
		end
		previous = key.timeMs
		if table.find(sensory_profile.MODES, key.mode) == nil then
			error(
				`Facet sensory_profile: '{phase}' key #{index} has mode '{tostring(key.mode)}'. `
					.. `Enum.KeyInterpolationMode has three members: {table.concat(sensory_profile.MODES, ", ")}.`,
				0
			)
		end
	end
end

--[[ resolve(partial) -> SensoryProfile. A game replaces a phase, swaps one for a
	preset, or silences it — without touching a single control.

	WHAT IS *NOT* ENFORCED HERE, deliberately: the >= 0.3 peak and <= 34 ms budget
	are constraints on FACET'S OWN defaults, not on a game's taste. A game that
	wants a long, gentle rumble for its own reasons is not making an error; it is
	making a decision this module has no standing to refuse. What IS refused is a
	declaration that could only ever produce SILENCE while looking like sound — an
	empty custom waveform, a `Custom` preset, an unknown effect name. ]]
function sensory_profile.resolve(partial: PartialProfile?): SensoryProfile
	if partial == nil then
		return sensory_profile.DEFAULTS
	end
	if type(partial) ~= "table" then
		error(
			`Facet sensory_profile.resolve: expected a partial profile table \{ press?, release?, select? }, got `
				.. `{typeof(partial)}.`,
			0
		)
	end
	for key in partial :: any do
		if table.find(sensory_profile.PHASES, key) == nil then
			error(
				`Facet sensory_profile.resolve: unknown phase '{tostring(key)}'. Facet has three interaction phases: `
					.. `{table.concat(sensory_profile.PHASES, ", ")}. Hover is the ENGINE's `
					.. "(`GuiButton.HoverHapticEffect`) and is not a Facet phase.",
				0
			)
		end
	end
	local resolved: any = {}
	for _, phase in sensory_profile.PHASES do
		local override = (partial :: any)[phase]
		if override == nil then
			resolved[phase] = (sensory_profile.DEFAULTS :: any)[phase]
		else
			validate(phase, override)
			resolved[phase] = freezeSpec(override)
		end
	end
	return table.freeze(resolved) :: SensoryProfile
end

return sensory_profile
