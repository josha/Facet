--!strict
-- THE CANONICAL FIVE-VIEW DEVICE MATRIX (docs/plans/studio-device-verification.md).
-- Pure, engine-free, and headlessly tested: this module is the SELECTION POLICY
-- the Studio driver (tools/studio/device_matrix.luau) runs against the live
-- device catalog. Keeping the policy here rather than in the driver is what
-- makes "no catalog id is hard-coded" a checkable claim instead of a promise —
-- tests/matrix_rows.spec.luau feeds it a recorded catalog and asserts what it
-- picks and why.
--
-- Studio is a rolling platform: presets appear, are renamed and are retired. So
-- a row does not name a device. It declares a ROLE ("the narrowest supported
-- phone"), a RANKING over whatever the catalog currently offers, and the
-- REQUIREMENTS the chosen preset must actually satisfy once selected. The
-- driver walks the ranked candidates and accepts the first that meets the
-- requirements live, recording which one it was and why.
--
-- Catalog entry shape (normalized by the driver from GetDeviceInfoAsync, whose
-- live fields are DeviceId/Name/DeviceForm/Width/Height/ResolutionScale/
-- PixelDensity/IsCustom/PortraitKeyboardHeight/LandscapeKeyboardHeight):
--   { id, name, form, w, h, scale, dpi, portraitKeyboardHeight, landscapeKeyboardHeight }
-- `form` is the DeviceForm enum NAME ("Phone" | "Tablet" | "Desktop" |
-- "Console" | "VR"), not the enum value, so this module stays engine-free.
--
-- Public interface:
--   matrix_rows.ROWS                     -- the five canonical rows, in order
--   matrix_rows.list() -> { string }     -- row ids
--   matrix_rows.get(id) -> Row
--   matrix_rows.resolve(catalog, id) -> Resolution
--   matrix_rows.checkRequirements(row, observed) -> { ok, problems }

local matrix_rows = {}

export type CatalogEntry = {
	id: string,
	name: string,
	form: string,
	w: number,
	h: number,
	scale: number?,
	dpi: number?,
	portraitKeyboardHeight: number?,
	landscapeKeyboardHeight: number?,
}

export type Row = {
	id: string,
	role: string,
	orientation: string, -- "Portrait" | "LandscapeLeft" | "Default"
	risk: string,
	-- what must be TRUE of the running session once this preset is selected.
	-- Checked against observed facts, not against the catalog: a preset that
	-- claims to be a console but does not publish a gamepad primary proves
	-- nothing about ten-foot input, and the driver must be able to say so.
	requires: { [string]: any },
	-- what this row can never close, restated at the point of use so a reader
	-- of one row's result does not have to find the plan document
	cannotProve: { string },
}

-- The project's standard development viewport, matching
-- src/preview/device_profiles.luau's `desktop` class. Kept as a number pair
-- rather than a device id: the desktop row is about a known viewport, and any
-- catalog entry that provides it will do.
local STANDARD_DESKTOP = { w = 1280, h = 720 }
-- A television is a low-density panel viewed from across a room. Roblox's
-- catalog classifies its Android TV entry as a Tablet (1920×1080 at 44 dpi) and
-- its handheld consoles as Console (1280x720 at 274 dpi and 1920x1080 at 411 dpi), so FORM ALONE picks
-- the wrong device in both directions. Density is the fact that actually
-- separates them.
-- These thresholds are CATALOG densities. `GetPixelDensityAsync` returns the
-- EFFECTIVE density (catalog dpi / ResolutionScale — 501/4 = 125.25 on a phone),
-- which is a different quantity; testing the live number against these numbers
-- would compare two things through one threshold. The driver passes the catalog
-- value to `checkRequirements` and records the live one beside it.
local TV_MAX_DPI = 120
local TABLET_MIN_DPI = 100
-- SCALING-MODE SLACK, not an emulator quirk. `SetScalingModeAsync` decides
-- whether the emulated viewport is the resolution you asked for:
-- `ActualResolution` renders at exact pixel resolution and returns exactly
-- 1280x720, while leaving the mode unset returned 1280x719. The driver sets and
-- records the mode; this tolerance is the slack for a caller that does not.
local VIEWPORT_FIT_TOLERANCE = 2

matrix_rows.ROWS = {
	{
		id = "compact-phone-portrait",
		role = "narrowest supported built-in phone preset with stable output",
		orientation = "Portrait",
		risk = "minimum width, vertical compression, safe insets, touch-sized geometry",
		requires = { form = "Phone", maxViewportMinorAxis = 480 },
		cannotProve = {
			"physical touch targeting, gestures or touch feel (E4)",
			"the mobile operating-system keyboard",
			"low-end CPU/GPU/memory/thermal behavior — the narrowest CANVAS is not the weakest HARDWARE",
		},
	},
	{
		id = "compact-phone-landscape",
		role = "the same phone preset as compact-phone-portrait, rotated",
		orientation = "LandscapeLeft",
		risk = "short height, orientation adaptation, state and focus survival across the rotation",
		requires = { form = "Phone", sameDeviceAs = "compact-phone-portrait" },
		cannotProve = {
			"physical rotation behavior or the real orientation-change animation",
			"physical touch targeting or touch feel (E4)",
		},
	},
	{
		id = "tablet-landscape",
		role = "representative built-in tablet preset",
		orientation = "LandscapeLeft",
		risk = "mid-size reflow and density assumptions",
		requires = { form = "Tablet", minDpi = TABLET_MIN_DPI },
		cannotProve = { "physical touch targeting or touch feel (E4)" },
	},
	{
		id = "desktop-standard",
		role = "desktop profile at the project's standard development viewport",
		orientation = "Default",
		risk = "pointer/keyboard layout and uncapped-width mistakes",
		requires = { form = "Desktop", viewport = STANDARD_DESKTOP },
		cannotProve = { "retail-client behavior or non-Studio display scaling (E4)" },
	},
	{
		id = "console-ten-foot",
		role = "console form at 1920×1080 (or the closest built-in preset) on a television-density panel",
		orientation = "Default",
		risk = "ten-foot sizing, focus visibility, and large-view composition",
		--[[ the row is worth running only if the session really enters the
			ten-foot presentation: Large display class is what drives the ×1.5 type
			floor, the ×1.5 METRIC ladder (ADAPT-8, director ruling 2026-08-20 —
			control heights, spacing, icon sizes and the hit floor scale with the
			type, so every text-to-control proportion at three metres equals its
			near proportion), the overscan margins and the strengthened focus
			visual.

			WHAT THIS ROW'S CAPTURES ARE RE-BASELINED AGAINST (wave TEN-FOOT):
			every console-row geometry pinned before 2026-08-20 was measured with
			the metric ladder at 1.0, so a stored capture from that era is a
			DIFFERENT layout, not a regression — the type is the same and the
			chrome around it is half again as large. The floor a reviewer checks
			at arm's length is 66 px, not 44. ]]
		requires = { form = "Console", maxDpi = TV_MAX_DPI, displaySize = "Large" },
		cannotProve = {
			"gamepad DELIVERY, platform arbitration, or Button A contention (E4)",
			"television overscan on real hardware",
			"console performance",
		},
	},
} :: { Row }

-- optional sixth row for text-entry work (plan: "add one optional
-- phone-keyboard-occluded row using a custom device configuration with a
-- recorded virtual keyboard height"). Not part of the canonical five and not
-- run by default — it proves the layout responds to a DECLARED occluded area,
-- never that a real mobile keyboard appeared.
matrix_rows.OPTIONAL = {
	{
		id = "phone-keyboard-occluded",
		role = "the compact phone preset with its reported virtual-keyboard height declared as an occlusion",
		orientation = "Portrait",
		risk = "layout response to an occluded area during text entry",
		requires = { form = "Phone", sameDeviceAs = "compact-phone-portrait", keyboardHeightDeclared = true },
		cannotProve = { "that a real mobile operating-system keyboard appeared or behaves this way (E4)" },
	},
} :: { Row }

local BY_ID: { [string]: Row } = {}
for _, row in matrix_rows.ROWS do
	BY_ID[row.id] = row
end
for _, row in matrix_rows.OPTIONAL do
	BY_ID[row.id] = row
end

function matrix_rows.list(): { string }
	local out = {}
	for _, row in matrix_rows.ROWS do
		table.insert(out, row.id)
	end
	return out
end

function matrix_rows.get(id: string): Row
	local row = BY_ID[id]
	assert(row ~= nil, `matrix_rows: unknown row '{id}'`)
	return row
end

local function minorAxis(e: CatalogEntry): number
	return math.min(e.w, e.h)
end
local function area(e: CatalogEntry): number
	return e.w * e.h
end

-- Deterministic ordering helper: rank by the supplied key list, then always by
-- id ascending so two equally-good presets never swap between runs. A matrix
-- that silently changes which device it measured is not a regression gate.
local function ranked(pool: { CatalogEntry }, keys: { (CatalogEntry) -> number }): { CatalogEntry }
	local out = table.clone(pool)
	table.sort(out, function(a, b)
		for _, key in keys do
			local ka, kb = key(a), key(b)
			if ka ~= kb then
				return ka < kb
			end
		end
		return a.id < b.id
	end)
	return out
end

export type Candidate = { entry: CatalogEntry, why: string }
export type Resolution = {
	row: Row,
	candidates: { Candidate },
	excluded: { { id: string, reason: string } },
	-- rows that must reuse another row's device say so here; the driver resolves
	-- that row first and passes the chosen entry back in through `pinned`
	sameDeviceAs: string?,
}

-- Rank the live catalog for one row. Returns an ORDERED candidate list rather
-- than a single answer: the driver takes the first candidate that satisfies the
-- row's requirements in the running session, so a preset that looks right in
-- the catalog but does not behave right live is skipped with a recorded reason
-- instead of quietly producing a bad row.
function matrix_rows.resolve(catalog: { CatalogEntry }, rowId: string, pinned: CatalogEntry?): Resolution
	local row = matrix_rows.get(rowId)
	local excluded: { { id: string, reason: string } } = {}

	if row.requires.sameDeviceAs ~= nil then
		if pinned ~= nil then
			return {
				row = row,
				candidates = {
					{
						entry = pinned,
						why = `pinned to the device resolved for '{row.requires.sameDeviceAs}' — the pair of `
							.. `phone rows must be the SAME device in two orientations, or the row proves `
							.. `orientation adaptation of two different layouts`,
					},
				},
				excluded = excluded,
				sameDeviceAs = row.requires.sameDeviceAs,
			}
		end
		return { row = row, candidates = {}, excluded = excluded, sameDeviceAs = row.requires.sameDeviceAs }
	end

	local pool: { CatalogEntry } = {}
	for _, e in catalog do
		if e.form ~= row.requires.form then
			-- not an exclusion worth recording: it is simply a different form
			continue
		end
		if row.requires.minDpi ~= nil and (e.dpi or 0) < row.requires.minDpi then
			table.insert(excluded, {
				id = e.id,
				reason = `{e.dpi or 0} dpi is below the {row.requires.minDpi} dpi tablet floor — a low-density `
					.. `panel of this size is a television, whatever the catalog calls its form`,
			})
			continue
		end
		if row.requires.maxDpi ~= nil and (e.dpi or 0) > row.requires.maxDpi then
			table.insert(excluded, {
				id = e.id,
				reason = `{e.dpi} dpi is above the {row.requires.maxDpi} dpi television ceiling — this is a `
					.. `handheld held at arm's length, not a ten-foot display`,
			})
			continue
		end
		table.insert(pool, e)
	end

	local candidates: { Candidate } = {}

	if rowId == "compact-phone-portrait" then
		-- narrowest first; among equal minor axes the SMALLEST TOTAL CANVAS,
		-- because that is the tightest layout. This deliberately selects by
		-- canvas, not by how weak the hardware is: the weakest-device question
		-- is a physical row (XP-P1) that no emulator can answer.
		for _, e in ranked(pool, { minorAxis, area }) do
			table.insert(candidates, {
				entry = e,
				why = `minor axis {minorAxis(e)}px, canvas {e.w}x{e.h} ({area(e)}px²) — ranked narrowest-then-smallest`,
			})
		end
	elseif rowId == "tablet-landscape" then
		-- REPRESENTATIVE, not extreme: the median tablet by canvas area. An
		-- extreme pick (the smallest or the largest) would test an edge the
		-- phone and desktop rows already cover.
		local byArea = ranked(pool, { area })
		local median = math.max(1, math.ceil(#byArea / 2))
		if byArea[median] ~= nil then
			table.insert(candidates, {
				entry = byArea[median],
				why = `median tablet by canvas area (rank {median} of {#byArea}) — representative, not extreme`,
			})
		end
		for i, e in byArea do
			if i ~= median then
				table.insert(candidates, { entry = e, why = `fallback tablet, area rank {i} of {#byArea}` })
			end
		end
	elseif rowId == "desktop-standard" then
		local want = row.requires.viewport
		local exact: { CatalogEntry } = {}
		local rest: { CatalogEntry } = {}
		for _, e in pool do
			if (e.w == want.w and e.h == want.h) or (e.w == want.h and e.h == want.w) then
				table.insert(exact, e)
			else
				table.insert(rest, e)
			end
		end
		for _, e in ranked(exact, {}) do
			table.insert(candidates, {
				entry = e,
				why = `exactly the project's standard development viewport ({want.w}x{want.h})`,
			})
		end
		-- otherwise the smallest desktop preset at or above the standard, so the
		-- row never silently becomes a test of an enormous monitor
		local above: { CatalogEntry } = {}
		for _, e in rest do
			if e.w >= want.w and e.h >= want.h then
				table.insert(above, e)
			end
		end
		for _, e in ranked(above, { area }) do
			table.insert(candidates, { entry = e, why = `smallest desktop preset at or above {want.w}x{want.h}` })
		end
		for _, e in ranked(rest, { area }) do
			table.insert(candidates, { entry = e, why = "fallback desktop preset (below the standard viewport)" })
		end
	elseif rowId == "console-ten-foot" then
		-- prefer exactly 1920×1080 (the plan's target), then any remaining
		-- television-density console form
		local target: { CatalogEntry } = {}
		local rest: { CatalogEntry } = {}
		for _, e in pool do
			if e.w == 1920 and e.h == 1080 then
				table.insert(target, e)
			else
				table.insert(rest, e)
			end
		end
		for _, e in ranked(target, {}) do
			table.insert(candidates, { entry = e, why = "console form at 1920x1080 on a television-density panel" })
		end
		for _, e in ranked(rest, { area }) do
			table.insert(candidates, { entry = e, why = "fallback console form (not 1920x1080)" })
		end
	else
		for _, e in ranked(pool, { area }) do
			table.insert(candidates, { entry = e, why = "form match, ranked by canvas area" })
		end
	end

	return { row = row, candidates = candidates, excluded = excluded, sameDeviceAs = nil }
end

-- Check a row's requirements against what the RUNNING session reported. This is
-- the half a catalog cannot answer: whether selecting the preset actually put
-- the client into the presentation the row is about.
--
-- observed = { form?, viewport = {w,h}, dpi?, displaySize?, preferredInput?,
--              deviceId?, keyboardHeight? }
function matrix_rows.checkRequirements(row: Row, observed: any): { ok: boolean, problems: { string } }
	local problems: { string } = {}
	local req = row.requires

	if observed == nil or type(observed.viewport) ~= "table" then
		return { ok = false, problems = { "no observed viewport — the instrument reported nothing to check" } }
	end
	local vp = observed.viewport
	if vp.w <= 1 or vp.h <= 1 then
		table.insert(problems, `viewport is {vp.w}x{vp.h} — a 1x1 viewport is a blind instrument, not a layout`)
	end
	if req.form ~= nil and observed.form ~= nil and observed.form ~= req.form then
		table.insert(problems, `device form is '{observed.form}', row requires '{req.form}'`)
	end
	if req.maxViewportMinorAxis ~= nil then
		local minor = math.min(vp.w, vp.h)
		if minor > req.maxViewportMinorAxis then
			table.insert(
				problems,
				`viewport minor axis {minor}px exceeds the row's compact ceiling of {req.maxViewportMinorAxis}px`
			)
		end
	end
	if req.viewport ~= nil then
		local want = req.viewport
		-- SCALING-MODE SLACK. Asking for 1280x720 without setting the scaling
		-- mode returned 1280x719, and demanding an exact match rejected every
		-- desktop candidate — strictness that proves nothing. With
		-- `SetScalingModeAsync(ActualResolution)` the viewport is exact, so this
		-- tolerance only covers a caller that did not set it. The EXACT reported
		-- viewport is recorded on the row either way.
		local tolerance = req.viewportTolerance or VIEWPORT_FIT_TOLERANCE
		local function near(a: number, b: number): boolean
			return math.abs(a - b) <= tolerance
		end
		local matches = (near(vp.w, want.w) and near(vp.h, want.h)) or (near(vp.w, want.h) and near(vp.h, want.w))
		if not matches then
			table.insert(
				problems,
				`viewport {vp.w}x{vp.h} is not the standard {want.w}x{want.h} (tolerance {tolerance}px)`
			)
		end
	end
	if req.minDpi ~= nil and observed.dpi ~= nil and observed.dpi < req.minDpi then
		table.insert(problems, `{observed.dpi} dpi is below the row's floor of {req.minDpi}`)
	end
	if req.maxDpi ~= nil and observed.dpi ~= nil and observed.dpi > req.maxDpi then
		table.insert(problems, `{observed.dpi} dpi is above the row's television ceiling of {req.maxDpi}`)
	end
	if req.displaySize ~= nil and observed.displaySize ~= req.displaySize then
		table.insert(
			problems,
			`displaySize is '{tostring(observed.displaySize)}', row requires '{req.displaySize}' — without it the `
				.. `ten-foot type floor, overscan margins and focus strengthening never engage, so the row would `
				.. `measure a large desktop and call it a console`
		)
	end
	if req.keyboardHeightDeclared == true and (observed.keyboardHeight or 0) <= 0 then
		table.insert(problems, "no virtual-keyboard height was declared, so there is no occlusion to respond to")
	end

	return { ok = #problems == 0, problems = problems }
end

return matrix_rows
