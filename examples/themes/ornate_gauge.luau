--!strict
-- ORNATE GAUGE — the worked RUNG-3 example (rich-skinning-v2 P6).
--
-- Rung 1 is a theme package. Rung 2 is a per-view override. Rung 3 is THIS: the
-- look is not a variation of anything the framework ships, so the answer is a
-- new control — one that brings its OWN art, contributes its OWN namespaced
-- theme roles through the public contribution contract, and still re-themes when
-- the game changes package.
--
-- Everything below goes through the PUBLIC surface and nothing else:
--   * `Facet.themes.checkCoverage` — the pre-play conformance gate;
--   * the `UI.*` primitives, `UI.shadow` and `UI.corners`;
--   * the resolved `ThemeSnapshot` (the `themeMetrics` environment fact) and the
--     compiled package's own plain data.
-- No `chrome_slots`, no adapter reach-through, no internal require. A control
-- written outside this repository has exactly these seams and no more, which is
-- the whole reason this file is the example.
--
-- WHAT THE THEME OWNS AND WHAT THE CONTROL OWNS
--
--   the pictures ............ the CONTROL (assets/themes/ornate-gauge/, its own
--                             provenance + upload manifest; a theme never sees
--                             an asset id of the gauge's)
--   the dial's SIZE ......... the PACKAGE: metrics.controlSizes["gauge:dial"]
--   the glow COLOUR ......... the PACKAGE: style.themes[].extra["gauge:needle"]
--   the corner RADIUS ....... the PACKAGE: metrics.radii["gauge:ring"]
--
-- Those three are the three `checkCoverage` kinds — `controlSize`, `color` and
-- `number` — so this one control exercises the whole contribution vocabulary.
-- A package that declares none of them still runs the gauge: every need carries
-- a `fallback`, so an uncovered package DEGRADES, and the pre-play check is what
-- turns that degradation into a message a human reads before Play.
--
-- WHY THE ART LOOKS THE WAY IT DOES. A control paints through `UI.Image`, which
-- has no `sliceCenter` and no tint — nine-slice geometry and `ImageColor3` are
-- theme-recipe authority (docs/extending/new-theme.md §1). So the face art is
-- authored HORIZONTALLY INVARIANT (every column identical, asserted by the
-- generator) and the needle and end caps are drawn at a fixed px box and never
-- stretched. Design the art for the authority you have.

local ornate_gauge = {}

ornate_gauge.namespace = "gauge"
ornate_gauge.control = "OrnateGauge"

-- The control's OWN art. Published from assets/themes/ornate-gauge/ — see the
-- provenance and upload manifest beside the PNGs. Another project uploads the
-- same three files under its own account and substitutes its own IDs.
ornate_gauge.ART = table.freeze({
	face = "rbxassetid://117569461983627", -- 64x64, horizontally invariant
	needle = "rbxassetid://88340591181438", -- 24x64, fixed
	endcap = "rbxassetid://80585948903459", -- 28x64, fixed, both ends
})

-- fixed px boxes for the art that must never stretch
ornate_gauge.CAP_PX = 28
ornate_gauge.NEEDLE_PX = 24

-- The declaration: type, section, authority, capability and a fallback per need,
-- exactly as the theme contract asks a contributed control to declare them. The
-- SECTIONS are the two places `themes.define` deliberately passes a namespaced
-- key through unvalidated, plus `metrics.radii` for the plain number — a
-- package that FORGETS this control is otherwise indistinguishable, at compile
-- time, from one that covers it, which is the whole reason checkCoverage exists.
ornate_gauge.needs = table.freeze({
	table.freeze({
		name = "gauge:dial",
		kind = "controlSize",
		section = "metrics.controlSizes",
		fields = table.freeze({ "height", "paddingX", "iconSize" }),
		authority = "layout", -- the solver consumes it; a theme may not paint it
		capability = "none",
		fallback = table.freeze({ height = 44, paddingX = 12, iconSize = 18 }),
	}),
	table.freeze({
		name = "gauge:needle",
		kind = "color",
		section = "style.themes[].extra",
		authority = "paint",
		capability = "none",
		-- brass, so an uncovered package still looks deliberate rather than broken
		fallback = table.freeze({ r = 0.75, g = 0.58, b = 0.23 }),
	}),
	table.freeze({
		name = "gauge:ring",
		kind = "number",
		section = "metrics.radii",
		authority = "paint",
		capability = "none",
		fallback = 6,
	}),
})

local function needByName(name: string): any
	for _, need in ornate_gauge.needs do
		if need.name == name then
			return need
		end
	end
	return nil
end

-- check(themes, package) -> { ok, covered, missing = { { name, message, fix } } }
--
-- A THIN CALL into the shipped gate. The Step 3.5 predecessor
-- (examples/themes/custom_control.luau) had to hand-write this because the
-- contribution contract did not exist yet; its own comment promised that "when
-- the contribution contract lands, `check` becomes a thin call into it". It has,
-- so this is what a contributed control's conformance check should now look
-- like: one line, and the framework owns the message.
function ornate_gauge.check(themes: any, package: any): any
	return themes.checkCoverage(package, ornate_gauge.needs)
end

-- resolve(snapshot, package, themeName) -> the values the control actually uses.
--
-- The SNAPSHOT is the metric authority (never the package's raw metrics): it is
-- what the solver reads, it carries derivation and floors, and it is what a
-- metric-only Style-Editor edit moves. The PACKAGE is consulted only for the
-- per-theme paint role, because palettes live per theme and the snapshot is one
-- resolved theme's worth of metrics.
function ornate_gauge.resolve(snapshot: any, package: any?, themeName: string?): any
	local sizeNeed = needByName("gauge:dial")
	local colorNeed = needByName("gauge:needle")
	local ringNeed = needByName("gauge:ring")

	local size = (snapshot.controlSizes or {})["gauge:dial"]
	local usedSize = type(size) ~= "table" or type(size.height) ~= "number"

	local ring = (snapshot.radii or {})["gauge:ring"]
	local usedRing = type(ring) ~= "number"

	local needle: any = nil
	if package ~= nil then
		local wanted = themeName or package.style.defaultTheme
		for _, theme in package.style.themes do
			if theme.name == wanted then
				needle = (theme.extra or {})["gauge:needle"]
			end
		end
	end
	local usedNeedle = type(needle) ~= "table" or type(needle.r) ~= "number"

	return {
		height = if usedSize then sizeNeed.fallback.height else size.height,
		paddingX = if usedSize then sizeNeed.fallback.paddingX else size.paddingX,
		iconSize = if usedSize then sizeNeed.fallback.iconSize else size.iconSize,
		ring = if usedRing then ringNeed.fallback else ring,
		needle = if usedNeedle then colorNeed.fallback else needle,
		usedFallback = { size = usedSize, needle = usedNeedle, ring = usedRing },
	}
end

-- blueprint(UI, core, resolved, opts) -> the control.
--
-- opts = {
--   id?          : node id (default "Gauge")
--   label?       : the caption above the dial
--   fraction     : Readable<number> in 0..1 — where the needle sits
--   heightPx?    : Readable<number> — pass one and the dial re-sizes LIVE when
--                  the theme package changes, with NO rebuild (see below)
-- }
--
-- WHAT RE-THEMES LIVE AND WHAT NEEDS A REBUILD — the honest seam, and worth
-- understanding before you write your own control:
--
--   * `height` is a reactive prop, so a `heightPx` Readable makes a package swap
--     re-solve this control exactly like a framework control: write the new
--     `resolve(...).height` into that signal from your `controller.onChange`
--     handler and the dial changes size in the same frame, no remount, focus
--     and scroll untouched.
--   * `UI.shadow` and `UI.corners` NORMALIZE EAGERLY — they are functions that
--     return a new blueprint, not reactive props you can hand a Readable — so
--     the glow colour and the corner radius are baked at build time. Changing
--     THOSE means rebuilding the blueprint. That is not a bug to route around;
--     it is the modifier contract, and a control that hides it would be lying
--     about when its paint updates.
function ornate_gauge.blueprint(UI: any, core: any, resolved: any, opts: any?): any
	local o: any = opts or {}
	local name: string = o.id or "Gauge"
	local capPx = ornate_gauge.CAP_PX
	local fraction = o.fraction

	local function clamp01(v: any): number
		local n = if type(v) == "number" then v else 0
		return math.clamp(n, 0, 1)
	end

	-- the needle's position is expressed as two FILL WEIGHTS, not as a pixel
	-- offset: the control never has to know how wide the solver made it, and the
	-- needle stays correct through every resize and every metric package. The
	-- floor keeps both weights strictly positive, because a zero-weight fill is
	-- a degenerate box rather than a hidden one.
	local FLOOR = 1e-4
	local lead = core:memo(function(use: any)
		local f = clamp01(if fraction ~= nil then use(fraction) else 0)
		return UI.fill(math.max(f, FLOOR))
	end)
	local trail = core:memo(function(use: any)
		local f = clamp01(if fraction ~= nil then use(fraction) else 0)
		return UI.fill(math.max(1 - f, FLOOR))
	end)

	local dialHeight: any = if o.heightPx ~= nil
		then core:memo(function(use: any)
			return { type = "fixed", px = use(o.heightPx) }
		end)
		else { type = "fixed", px = resolved.height }

	local FILL = UI.fill()

	-- the value token, wearing the THEME's colour as a glow. This is the one
	-- place a contributed control can put a palette colour today: `UI.shadow`
	-- takes an explicit `{ r, g, b }`, and every other public paint channel is
	-- semantic (a `surface` name), by design — a control may not invent fills.
	local needle = UI.shadow(
		UI.Image({
			id = name .. "Needle",
			image = ornate_gauge.ART.needle,
			width = { type = "fixed", px = ornate_gauge.NEEDLE_PX },
			height = FILL,
		}),
		{
			blurRadius = { scale = 0, offset = 18 },
			color = resolved.needle,
			transparency = 0.35,
			zIndex = -1, -- MUST be negative: a shadow renders below its node
		}
	)

	local dial = UI.corners(
		UI.ZStack({
			id = name .. "Dial",
			width = FILL,
			height = dialHeight,
			children = {
				-- the channel: whole art, stretched horizontally, which is
				-- lossless because the art is column-identical by construction
				UI.Image({
					id = name .. "Face",
					image = ornate_gauge.ART.face,
					width = FILL,
					height = FILL,
				}),
				-- the needle rides between the caps: the track is inset by one
				-- cap width per side so the token can never slide under an
				-- ornament at 0 % or 100 %
				UI.HStack({
					id = name .. "Track",
					width = FILL,
					height = FILL,
					gap = 0,
					padding = { top = 0, right = capPx, bottom = 0, left = capPx },
					children = {
						UI.Spacer({ id = name .. "Lead", width = lead, height = FILL }),
						needle,
						UI.Spacer({ id = name .. "Trail", width = trail, height = FILL }),
					},
				}),
				-- the ornaments last, so they paint OVER the needle at the ends
				UI.Anchor({
					id = name .. "Caps",
					width = FILL,
					height = FILL,
					children = {
						UI.Image({
							id = name .. "CapStart",
							image = ornate_gauge.ART.endcap,
							anchor = "left",
							width = { type = "fixed", px = capPx },
							height = FILL,
						}),
						UI.Image({
							id = name .. "CapEnd",
							image = ornate_gauge.ART.endcap,
							anchor = "right",
							width = { type = "fixed", px = capPx },
							height = FILL,
						}),
					},
				}),
			},
		}),
		resolved.ring
	)

	return UI.VStack({
		id = name,
		gap = "xs",
		width = FILL,
		children = {
			UI.Text({
				id = name .. "Label",
				text = o.label or "Boiler pressure (gauge:dial)",
				textSize = "caption",
			}),
			dial,
		},
	})
end

return ornate_gauge
