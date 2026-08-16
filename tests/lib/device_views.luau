--!strict
-- THE SWEPT VIEWPORT SET, IN ONE PLACE.
--
-- Two always-on suite sweeps ask a question of every showcase surface at every
-- supported viewport: `tests/overflow_sweep.spec.luau` asks *does anything paint
-- outside its own box*, and `tests/example_readouts.spec.luau` asks *is the
-- content the example declares actually rendered*. They are different questions
-- and they must be asked at the SAME sizes — a readout that vanishes only at
-- 320x640 and a row that overflows only at 320x640 are the same phone.
--
-- These rows were extracted from `overflow_sweep` when the second sweep was
-- added (2026-08-13, the tile-game readout finding). Copying the table would
-- have let the two lists drift, and a viewport that only one sweep visits is a
-- viewport where one of the two questions is never asked.
--
-- The five canonical rows of docs/plans/studio-device-verification.md at the
-- viewports the driver RECORDED (artifacts/rich-skinning-v2/rs-a16-matrix.json),
-- kept identical to tests/theme_matrix_audit.spec.luau's VIEWS, plus the
-- narrowest supported viewport in both orientations (the lesson's "sweep the
-- narrowest supported viewport, not your own" — and its rotation, because a
-- short landscape is where a screen's fixed chrome eats the whole canvas).
export type View = { id: string, w: number, h: number, displaySize: string, input: string }

local VIEWS: { View } = {
	{ id = "compact-phone-portrait", w = 359, h = 718, displaySize = "Small", input = "Touch" },
	{ id = "compact-phone-landscape", w = 705, h = 338, displaySize = "Small", input = "Touch" },
	{ id = "tablet-landscape", w = 1079, h = 809, displaySize = "Small", input = "Touch" },
	{ id = "desktop-standard", w = 1232, h = 1067, displaySize = "Medium", input = "KeyboardAndMouse" },
	{ id = "console-ten-foot", w = 1920, h = 1078, displaySize = "Large", input = "Gamepad" },
	{ id = "narrow-portrait", w = 320, h = 640, displaySize = "Small", input = "Touch" },
	{ id = "narrow-landscape", w = 640, h = 320, displaySize = "Small", input = "Touch" },
	-- the DESKTOP Studio client the director drove on 2026-08-12, at the size the
	-- right-edge clipping was captured at. It is here because "a defect that
	-- survives at 1320px wide is a stronger signal than one that only appears at
	-- 320px" — a sweep that only runs compact sizes teaches the wrong lesson about
	-- what overflow is.
	{ id = "desktop-studio-1320", w = 1320, h = 742, displaySize = "Medium", input = "KeyboardAndMouse" },
	--[[ THE MODERN PHONE (O-19, added 2026-08-15). 390x844 is the iPhone-class
		portrait the round-3 ledger measured `p4_foyer`'s TopBar at: clean in English
		at every preference, 33px over at +10 and 58px at +14 under the shipping 1.4x
		`xa` locale. It is NOT redundant with the two narrow rows above — 320x640 is
		the narrowest supported box and 359x718 the matrix's compact row, and this one
		is TALLER than both while barely wider, which is the shape that keeps a page
		fitting vertically while a chrome row keeps running off the right edge. A
		viewport nobody sweeps is a viewport where both of this file's questions go
		unasked, so it lands here rather than in one sweep's own list. ]]
	{ id = "phone-390x844", w = 390, h = 844, displaySize = "Small", input = "Touch" },
}

local CAPABILITIES: { [string]: any } = {
	Touch = { touch = true, mouse = false, keyboard = false, gamepad = false },
	KeyboardAndMouse = { touch = false, mouse = true, keyboard = true, gamepad = false },
	Gamepad = { touch = false, mouse = false, keyboard = false, gamepad = true },
}

-- The CoreGui topbar inset every matrix row measured. The showcase strip the
-- sweeps reserve on top of it is derived from `demo_picker.barReservation`, which
-- is the caller's job because only the caller knows whether the surface is
-- reached through the picker.
local CORE_TOP = 58

return {
	VIEWS = VIEWS,
	CAPABILITIES = CAPABILITIES,
	CORE_TOP = CORE_TOP,
}
