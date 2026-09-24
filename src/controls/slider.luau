--!strict
-- A shared value model drives pointer dragging, native drag detectors, and
-- keyboard/gamepad adjustment. The caller owns the value cell: a number, or a
-- `{ lower, upper }` pair when `range = true`. One begin/move/end/cancel pipeline
-- serves the track, both range handles and the native detector.
local Compose = require("../vendor/compose/core")
local selection = require("../selection_model")
local read = selection.read

local controlContract = require("../class_contract")
local contribution = require("../input/contribution")
local chrome_slots = require("../tokens/chrome_slots")
local themePackage = require("../themes/package")
local value_model = require("./value_model")
local specGuard = require("../spec_guard")
local rectLib = require("../rect")
local ownedBuild = require("../core/owned_build")
local surfaceEnv = require("../env/surface_env")
local vocabulary = require("./control_vocabulary")

local menuRecipe = require("./menu_recipe")
local slider = {}

-- Resolve sizes through theme metrics so theme changes preserve control identity.
local TRACK_HEIGHT = "targetSizes.minimum"
local THUMB_SIZE = "controls.slider.thumbSize"
local RAIL_HEIGHT = "controls.slider.railHeight"
local READOUT_MIN_WIDTH = "controls.slider.readoutMinWidth"
-- Leave clearance between the label and the thumb at the start of the track.
local LABEL_GAP = "m"
local FOCUS_RING = "focusRing"
-- the fill is the theme's selection ink (its accent unless the theme authors one)
local SELECTION_INK = table.freeze({ role = "selection", blend = 1 })
-- a quarantined range keeps at most this many refusal lines
local MAX_DIAGNOSTICS = 16

local specTypes = require("../spec_types/slider")
type NumberCell = specTypes.NumberCell
type Range = specTypes.Range
export type Spec<V = NumberCell> = specTypes.Spec<V>

local function hintFor(id: string, slot: string, prop: string, value: any): chrome_slots.Hint
	if value == nil then
		return { slot = slot }
	end
	if type(value) == "string" then
		return { slot = slot, image = value }
	end
	local variant, errors = themePackage.normalizeVariant(value, prop)
	if #errors > 0 then
		local first = errors[1]
		error(`Facet UI.Slider('{id}'): {prop} — {first.message} ({first.fix})`, 0)
	end
	return { slot = slot, imageVariants = variant }
end

local SLIDER_KEYS = specGuard.keySet({
	"row",
	"axis",
	"controlSize",
	"enabled",
	"format",
	"id",
	"label",
	"max",
	"min",
	"minGap",
	"onChange",
	"onCommit",
	"range",
	"rotation",
	"step",
	"tapToPosition",
	"thumb",
	"thumbContent",
	"thumbImage",
	"trackContent",
	"trackImage",
	"value",
})
local AXES = table.freeze({ "x", "y" })
local THUMB_MODES = table.freeze({ "always", "auto", "none" })
-- what the control IS: read once, so a bound one is refused rather than frozen
local CONSTRUCTION_ONLY = table.freeze({ "axis", "range", "thumb", "minGap" })

local function assertWord(id: string, key: string, value: any, allowed: { string })
	if table.find(allowed, value) == nil then
		error(
			`Facet UI.Slider('{id}'): \`{key}\` must be {table.concat(allowed, " | ")} `
				.. `(got {typeof(value)} '{tostring(value)}')`,
			0
		)
	end
end

local function merge(props: { [string]: any }, placement: { [string]: any }): { [string]: any }
	for key, val in placement do
		props[key] = val
	end
	return props
end

local function build(Facet: any, core: any, spec: Spec, owner: any)
	specGuard.assertKnownKeys("UI.Slider", spec, SLIDER_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Slider"
	local value = spec.value
	if not selection.isWritable(value) then
		error(
			`Facet UI.Slider('{id}'): \`value\` must be a writable Compose cell holding a number, owned by the caller `
				.. `(a read-only formula would pass a duck-type check and then fail on the first drag)`,
			0
		)
	end
	for _, key in CONSTRUCTION_ONLY do
		if selection.isSource((spec :: any)[key]) then
			error(
				`Facet UI.Slider('{id}'): \`{key}\` is construction-only and cannot be bound — it decides what `
					.. `this Slider IS. Mount a different Slider (a keyed region) when it really changes.`,
				0
			)
		end
	end
	local axis = spec.axis or "x"
	assertWord(id, "axis", axis, AXES)
	local vertical = axis == "y"
	local thumbMode = spec.thumb or "always"
	assertWord(id, "thumb", thumbMode, THUMB_MODES)
	if spec.thumbContent ~= nil and type(spec.thumbContent) ~= "function" then
		error(`Facet UI.Slider('{id}'): \`thumbContent\` must be a function(info) returning a node`, 0)
	end
	if spec.trackContent ~= nil and (type(spec.trackContent) ~= "function" or spec.trackImage ~= nil) then
		error(
			`Facet UI.Slider('{id}'): \`trackContent\` is a function() returning the track's node, and paints `
				.. "the track instead of `trackImage`",
			0
		)
	end
	if spec.thumbContent ~= nil and spec.thumbImage ~= nil then
		error(
			`Facet UI.Slider('{id}'): \`thumbImage\` and \`thumbContent\` both paint the handle. `
				.. `Keep the image (the theme's knob, your art) or the content (your knob), not both.`,
			0
		)
	end
	vocabulary.assertSize("UI.Slider", spec.controlSize)
	local model = value_model.new({ min = spec.min, max = spec.max, step = spec.step, format = spec.format })
	local isRange = spec.range == true
	local minGap = if spec.minGap ~= nil then spec.minGap else 0
	if type(minGap) ~= "number" or minGap ~= minGap or minGap < 0 or minGap > model.max - model.min then
		error(
			`Facet UI.Slider('{id}'): \`minGap\` must be a number from 0 to the range width `
				.. `({model.max - model.min}) (got {tostring(spec.minGap)})`,
			0
		)
	end

	-- ONE legality rule for a pair, used at build and on every read
	local function illegal(v: any): string?
		if type(v) ~= "table" or type(v.lower) ~= "number" or type(v.upper) ~= "number" then
			return `\`value\` is not a lower/upper pair of numbers (got {typeof(v)})`
		end
		if
			v.lower ~= v.lower
			or v.upper ~= v.upper
			or math.abs(v.lower) == math.huge
			or math.abs(v.upper) == math.huge
		then
			return "`value` carries a number that is not finite"
		end
		if v.lower > v.upper then
			return `\`value.lower\` ({v.lower}) is above \`value.upper\` ({v.upper})`
		end
		if v.upper - v.lower < minGap then
			return `\`value\` ({v.lower}..{v.upper}) is narrower than \`minGap\` ({minGap})`
		end
		return nil
	end
	local initial = read(value)
	if isRange then
		local reason = illegal(initial)
		if reason ~= nil then
			error(`Facet UI.Slider('{id}'): with \`range = true\`, {reason}`, 0)
		end
	elseif type(initial) ~= "number" then
		error(
			`Facet UI.Slider('{id}'): \`value\` must hold a number (got {typeof(initial)}) — `
				.. `a lower/upper pair needs \`range = true\``,
			0
		)
	end
	local tapToPosition = spec.tapToPosition ~= false
	local trackOverride = hintFor(id, "sliderTrack", "trackImage", spec.trackImage)
	local thumbOverride = hintFor(id, "sliderThumb", "thumbImage", spec.thumbImage)
	local env = surfaceEnv.find(core)

	local disposed = false
	local focusOwner

	local function isEnabled(): boolean
		return not disposed and controlContract.enabledNow(spec.enabled)
	end

	--[[ A REFUSED PAIR KEEPS THE LAST LEGAL ONE (warn and quarantine, never a
		crash inside a solve and never a write back to the caller). A refusal is
		recorded once per consecutive distinct reason; a legal read resets that, and
		at most MAX_DIAGNOSTICS lines are kept (oldest dropped). ]]
	local diagnostics: { string } = {}
	local lastLegal: Range = if isRange
		then { lower = initial.lower, upper = initial.upper }
		else { lower = 0, upper = 0 }
	local lastRefusal: string? = nil
	local function validated(v: any): Range
		local reason = illegal(v)
		if reason == nil then
			lastRefusal = nil
			lastLegal = { lower = v.lower, upper = v.upper }
			return { lower = v.lower, upper = v.upper }
		end
		if lastRefusal ~= reason then
			lastRefusal = reason
			local line = `Facet UI.Slider('{id}'): {reason} — keeping the last legal pair`
			table.insert(diagnostics, line)
			if #diagnostics > MAX_DIAGNOSTICS then
				table.remove(diagnostics, 1)
			end
			warn(line)
		end
		return { lower = lastLegal.lower, upper = lastLegal.upper }
	end
	local function pairNow(): Range
		return validated(value:peek())
	end
	local function pairIn(use: any): Range
		return validated(use(value))
	end

	local dragging = Compose.cell(false)
	local engaged = Compose.cell(false) -- range adjust mode (pad only)
	local snapshot: any = nil
	-- Solved geometry must be reactive, but equal rectangles must not schedule work.
	local rectEq = rectLib.equal
	local trackRect = Compose.cell(nil, rectEq)
	local thumbRect = Compose.cell(nil, rectEq)
	-- each range handle is measured on its own: custom knobs may differ in size
	local upperThumbRect = Compose.cell(nil, rectEq)
	local trackPath: string? = nil
	local boundController: any = nil

	local function rotationNow(): number
		local deg = read(spec.rotation)
		return if type(deg) == "number" and deg == deg then deg else 0
	end

	--[[ POINTER -> FRACTION. Pointer positions are window-space, so the track is
		read at event time through the controller's screen rect (scroll and
		presentation shifts included), falling back to the solved rect. Rotation is
		paint-only about the track's centre: un-rotate the vector by the painted
		angle, then the upright arithmetic applies. Floats until the final write. ]]
	local function fractionAt(px: number, py: number, screenRectOf: any?): number?
		local rectOf = screenRectOf or (boundController and boundController.screenRectOf)
		local rect = if rectOf ~= nil and trackPath ~= nil then rectOf(trackPath) else nil
		rect = rect or trackRect:peek()
		if rect == nil then
			return nil
		end
		local len = if vertical then rect.h else rect.w
		if len <= 0 then
			return nil
		end
		local x, y = px, py
		local deg = rotationNow()
		if deg % 360 ~= 0 then
			local cx, cy = rect.x + rect.w / 2, rect.y + rect.h / 2
			local a = -math.rad(deg)
			local dx, dy = px - cx, py - cy
			local cos, sin = math.cos(a), math.sin(a)
			x = cx + dx * cos - dy * sin
			y = cy + dx * sin + dy * cos
		end
		-- a vertical track runs BOTTOM to TOP for increasing value
		return if vertical then (rect.y + rect.h - y) / len else (x - rect.x) / len
	end

	--[[ THE ONE MUTATION SITE. The caller's cell is written first, then the caller
		is told. A range writes a fresh pair (never the caller's own table), never
		crosses, and walks a proposal past the other thumb ± minGap back onto the
		grid; no-op proposals write nothing. ]]
	local function applyThumb(which: string, next_: number): boolean
		if not isEnabled() then
			return false
		end
		local resolved = model.quantize(next_)
		if not isRange then
			if resolved == value:peek() then
				return false
			end
			value:set(resolved)
			if spec.onChange ~= nil then
				spec.onChange(resolved)
			end
			return true
		end
		local pair = pairNow()
		if which == "lower" then
			local limit = pair.upper - minGap
			if resolved > limit then
				resolved = model.quantize(limit)
				if resolved > limit then
					resolved = model.stepped(resolved, -1)
				end
			end
			if resolved > limit or resolved == pair.lower then
				return false
			end
			pair.lower = resolved
		else
			local limit = pair.lower + minGap
			if resolved < limit then
				resolved = model.quantize(limit)
				if resolved < limit then
					resolved = model.stepped(resolved, 1)
				end
			end
			if resolved < limit or resolved == pair.upper then
				return false
			end
			pair.upper = resolved
		end
		value:set(pair)
		if spec.onChange ~= nil then
			spec.onChange(pair, { thumb = which })
		end
		return true
	end

	--[[ WHICH THUMB A PRESS MEANS, read from the CONTINUOUS fraction before any
		quantization. A coincident pair: below takes lower, above takes upper; an
		exact hit takes the thumb that can still move (upper at min, lower at max,
		upper otherwise). Overlapping handle targets resolve here, not by z-order. ]]
	local function pickThumb(fraction: number): string
		local pair = pairNow()
		local raw = model.min + math.clamp(fraction, 0, 1) * (model.max - model.min)
		if pair.lower == pair.upper then
			if raw < pair.lower then
				return "lower"
			elseif raw > pair.upper then
				return "upper"
			elseif model.atMax(pair.upper) then
				return "lower"
			end
			return "upper"
		end
		if raw <= pair.lower then
			return "lower"
		elseif raw >= pair.upper then
			return "upper"
		end
		return if raw - pair.lower <= pair.upper - raw then "lower" else "upper"
	end

	-- the thumb this gesture owns, fixed for the whole gesture
	local activeThumb = if isRange then "lower" else "value"
	local activeCell = Compose.cell(activeThumb)
	local function setActive(which: string)
		activeThumb = which
		activeCell:set(which)
	end
	local function setFromPoint(px: number, py: number, screenRectOf: any?): boolean
		local f = fractionAt(px, py, screenRectOf)
		if f == nil then
			return false
		end
		return applyThumb(activeThumb, model.fromFraction(f))
	end

	local function adjust(direction: number): boolean
		if not isRange then
			return applyThumb("value", model.stepped(value:peek(), direction))
		end
		local pair = pairNow()
		return applyThumb(
			activeThumb,
			model.stepped(if activeThumb == "upper" then pair.upper else pair.lower, direction)
		)
	end

	local function beginDrag(px: number, py: number, screenRectOf: any?): boolean
		if not isEnabled() or dragging:peek() then
			return isEnabled()
		end
		if isRange then
			snapshot = pairNow()
			local f = fractionAt(px, py, screenRectOf)
			setActive(if f ~= nil then pickThumb(f) else "lower")
		else
			snapshot = value:peek()
		end
		dragging:set(true)
		if tapToPosition then
			setFromPoint(px, py, screenRectOf)
		end
		return true
	end

	local function info(): any
		return if isRange then { thumb = activeThumb } else nil
	end

	local function endDrag()
		if not dragging:peek() then
			return
		end
		dragging:set(false)
		snapshot = nil
		if spec.onCommit ~= nil then
			spec.onCommit(if isRange then pairNow() else value:peek(), info())
		end
	end

	-- a lost pointer/touch class or a cancelled capture restores the WHOLE start
	local function cancelDrag()
		if not dragging:peek() then
			return
		end
		local restore = snapshot
		dragging:set(false)
		snapshot = nil
		if restore ~= nil then
			value:set(if isRange then { lower = restore.lower, upper = restore.upper } else restore)
			if spec.onChange ~= nil then
				spec.onChange(if isRange then { lower = restore.lower, upper = restore.upper } else restore, info())
			end
		end
	end
	-- the live class set is the production hot-switch route: a drag whose pointer
	-- and touch classes both go away cancels, and a later move/release finds no drag
	if env ~= nil then
		owner.watch(function(use)
			local classes = use(env:get("interactionClasses"))
			if type(classes) == "table" and classes.pointer ~= true and classes.touch ~= true then
				cancelDrag()
			end
		end)
	end

	local focusableTrack = Compose.formula(function(use)
		return controlContract.enabledIn(use, spec.enabled)
	end)

	local focusGraph: any = nil
	local focusPaintAllowed: any = nil
	local handlePaths: { [string]: string? } = {}
	-- which part holds focus: "track" | "lower" | "upper" | nil
	local focusedPart = Compose.cell(nil :: string?)
	local trackFocused = Compose.formula(function(use)
		return use(focusedPart) ~= nil
	end)
	local function syncTrackFocus()
		local mayPaint = focusPaintAllowed == nil or read(focusPaintAllowed) ~= false
		local focused = if focusGraph ~= nil and mayPaint then read(focusGraph.focused) else nil
		local part: string? = nil
		if focused ~= nil then
			if focused == trackPath then
				part = "track"
			elseif focused == handlePaths.lower then
				part = "lower"
			elseif focused == handlePaths.upper then
				part = "upper"
			end
		end
		focusedPart:set(part)
		if part == nil then
			engaged:set(false) -- nothing stays armed behind a ring that left
		end
		-- focus picks the thumb for keyboard and gamepad; a live drag owns it
		if (part == "lower" or part == "upper") and not dragging:peek() then
			setActive(part)
		end
	end
	local ringData = UI.strokeData({ color = "accent", thickness = FOCUS_RING, transparency = 0 })
	local focusStroke = Compose.formula(function(use)
		return if use(trackFocused) then ringData else nil
	end)
	local function strokeForPart(part: string)
		return Compose.formula(function(use)
			return if use(focusedPart) == part then ringData else nil
		end)
	end

	local function lengthOf(rect: any): number
		return if rect == nil then 0 elseif vertical then rect.h else rect.w
	end
	local function numberOf(which: string, use: any): number
		if not isRange then
			return read(value, use)
		end
		local pair = pairIn(use)
		return if which == "upper" then pair.upper else pair.lower
	end
	-- one rounding, at the write, of the same two endpoints
	local function fillEnds(use: any): (number, number)
		local len = lengthOf(use(trackRect))
		local lower = if isRange then math.floor(len * model.fraction(numberOf("lower", use)) + 0.5) else 0
		local upper = math.floor(len * model.fraction(numberOf(if isRange then "upper" else "value", use)) + 0.5)
		return lower, upper
	end
	local fillWidth = Compose.formula(function(use)
		local a, b = fillEnds(use)
		return { type = "fixed", px = math.max(b - a, 0) }
	end)
	local fillLead = Compose.formula(function(use)
		local a, b = fillEnds(use)
		return if vertical then lengthOf(use(trackRect)) - b else a
	end)
	-- a thumb's travel is the track minus its OWN measured extent
	local function leadFor(which: string)
		return Compose.formula(function(use)
			local own = if which == "upper" then use(upperThumbRect) else nil
			local travel = math.max(lengthOf(use(trackRect)) - lengthOf(own or use(thumbRect)), 0)
			local f = model.fraction(numberOf(which, use))
			return math.floor(travel * (if vertical then 1 - f else f) + 0.5)
		end)
	end
	local thumbOffset = leadFor(if isRange then "lower" else "value")
	local upperOffset = if isRange then leadFor("upper") else nil
	local readout = Compose.formula(function(use)
		if not isRange then
			return model.format(read(value, use))
		end
		local pair = pairIn(use)
		return `{model.format(pair.lower)}–{model.format(pair.upper)}`
	end)
	local semantic = Compose.formula(function(use)
		if not isRange then
			return model.semanticText(read(value, use))
		end
		local pair = pairIn(use)
		return `{model.format(pair.lower)} to {model.format(pair.upper)}, of {model.format(model.min)} to {model.format(
			model.max
		)}`
	end)

	--[[ WHEN THE HANDLE IS PAINTED. "none" and "auto" hide paint only: targets,
		focus, readout and every adjust route stay. "auto" shows it on hover, focus
		and drag, and always on a touch-primary surface (a finger needs a handle). ]]
	local hovered = Compose.cell(false)
	local thumbHidden: any = nil
	if thumbMode == "none" then
		thumbHidden = true
	elseif thumbMode == "auto" then
		thumbHidden = Compose.formula(function(use)
			if use(dragging) or use(trackFocused) or use(hovered) then
				return false
			end
			return not (env ~= nil and menuRecipe.touchPrimary(use(env:get("interactionClasses"))))
		end)
	end

	local FILL = { type = "fill", weight = 1 }
	-- the value axis floors at one target of travel: a hugging cell offers no
	-- length, and a track that fills nothing cannot be dragged or read
	local TRACK_LENGTH = { type = "fill", weight = 1, min = TRACK_HEIGHT }
	-- a named rung paints a thinner track inside a reserved whole target
	local trackThickness = vocabulary.deriveSize("UI.Slider", spec.controlSize, function(rung)
		local path = vocabulary.metricPath(rung, "height")
		return { type = "fixed", px = path or TRACK_HEIGHT }
	end) or { type = "fixed", px = TRACK_HEIGHT }
	local railThickness = { type = "fixed", px = RAIL_HEIGHT }
	-- a named rung draws its thumb at the rung's icon size, so the ladder reads
	local thumbBox = vocabulary.deriveSize("UI.Slider", spec.controlSize, function(rung)
		return { type = "fixed", px = vocabulary.iconSizeFor(rung) or THUMB_SIZE }
	end) or { type = "fixed", px = THUMB_SIZE }
	-- a node's placement along the track: offset on the value axis from its anchor
	local function along(lead: any, span: any?, thickness: any?): { [string]: any }
		if vertical then
			return { anchor = "top", offsetY = lead, width = thickness or thumbBox, height = span or thumbBox }
		end
		return { anchor = "left", offsetX = lead, width = span or thumbBox, height = thickness or thumbBox }
	end

	-- what a custom knob is told: readables only, built once per thumb
	local function thumbInfo(which: string): any
		return table.freeze({
			thumb = which,
			value = Compose.formula(function(use)
				return numberOf(which, use)
			end),
			fraction = Compose.formula(function(use)
				return model.fraction(numberOf(which, use))
			end),
			dragging = Compose.formula(function(use)
				return use(dragging) and (not isRange or use(activeCell) == which)
			end),
			enabled = Compose.formula(function(use)
				return controlContract.enabledIn(use, spec.enabled)
			end),
		})
	end

	--[[ THE HANDLE, one node either way. Themed: a slot-hinted Box at the theme's
		thumb size. Custom: the caller's node centred in a ZStack floored at that
		size (it grows to fit, and travel is priced off what is drawn), which drops
		only its own sliderThumb slot. ]]
	local function knobView(which: string, suffix: string, lead: any, stroke: any): any
		local base = { id = "Thumb" .. suffix, hidden = thumbHidden, stroke = if spec.row then nil else stroke }
		if spec.thumbContent == nil then
			return chrome_slots.attachHint(UI.Box(merge(base, along(lead))), thumbOverride)
		end
		base.alignH = "center"
		base.alignV = "center"
		base.children = { spec.thumbContent(thumbInfo(which)) }
		local placed = along(lead)
		placed.width = { type = "minMax", min = THUMB_SIZE }
		placed.height = { type = "minMax", min = THUMB_SIZE }
		return UI.ZStack(merge(base, placed))
	end

	local function gripHandlers(): { [string]: any }
		return {
			onPointerDown = function(_path: string, pos: any, screenRectOf: any)
				return beginDrag(pos.x, pos.y, screenRectOf)
			end,
			onPointerMove = function(_path: string, pos: any, screenRectOf: any)
				if dragging:peek() then
					setFromPoint(pos.x, pos.y, screenRectOf)
				end
			end,
			onPointerUp = function()
				endDrag()
			end,
			onPointerCancel = function()
				cancelDrag()
				return nil
			end,
		}
	end

	-- the caller's track (a colour ramp) replaces the rail and its fill: the strip
	-- IS the value's scale, so a fill over it would hide what it shows
	local grooveChildren: { any } = if spec.trackContent ~= nil
		then {
			UI.ZStack(merge({
				id = "Rail",
				alignH = "center",
				alignV = "center",
				children = { spec.trackContent() },
			}, along(0, FILL, FILL))),
		}
		else {
			chrome_slots.attachHint(UI.Box(merge({ id = "Rail" }, along(0, FILL, railThickness))), trackOverride),
			chrome_slots.attachHint(
				UI.Box(
					merge(
						{ id = "Fill", surface = "accent", tint = SELECTION_INK },
						along(fillLead, fillWidth, railThickness)
					)
				),
				{ slot = chrome_slots.NO_SLOT }
			),
		}
	local handleViews: { any } = {}
	if isRange then
		-- the handles sit above the track; whichever takes a press, `beginDrag`
		-- picks the thumb, so overlap never depends on draw order
		table.insert(handleViews, knobView("lower", "Lower", thumbOffset, strokeForPart("lower")))
		table.insert(handleViews, knobView("upper", "Upper", upperOffset, strokeForPart("upper")))
		for _, suffix in { "Lower", "Upper" } do
			local lead = if suffix == "Lower" then thumbOffset else upperOffset
			local grip =
				merge({ id = "Handle" .. suffix, focusable = focusableTrack, focusVisual = "none" }, along(lead))
			table.insert(handleViews, UI.Grip(merge(grip, gripHandlers())))
		end
	else
		table.insert(grooveChildren, knobView("value", "", thumbOffset, focusStroke))
	end

	local trackHostChildren: { any } = {
		UI.Anchor({ id = "Groove", width = FILL, height = FILL, children = grooveChildren }),
		UI.Grip(merge({
			id = "Track",
			-- a range's stops are its two handles; a third on the rail moves nothing
			focusable = if isRange then false else focusableTrack,
			focusVisual = "none",
			width = FILL,
			height = FILL,
		}, gripHandlers())),
	}
	if #handleViews > 0 then
		table.insert(
			trackHostChildren,
			UI.Anchor({ id = "Handles", width = FILL, height = FILL, children = handleViews })
		)
	end
	-- rotation is paint-only about THIS node's centre: label and readout stay
	-- upright and the row keeps its unrotated box (the caller reserves the room)
	local trackHost: any = UI.ZStack({
		id = "TrackHost",
		width = if vertical then trackThickness else TRACK_LENGTH,
		height = if vertical then TRACK_LENGTH else trackThickness,
		rotation = spec.rotation,
		children = trackHostChildren,
	})
	if spec.controlSize ~= nil then
		-- paint shrinks, the target does not; the value axis carries its fill
		trackHost = vocabulary.reserveTarget(
			UI,
			core,
			"TrackHost",
			trackHost,
			if vertical then nil else TRACK_LENGTH,
			if vertical then TRACK_LENGTH else nil
		)
	end

	--[[ THE LABEL GIVES WAY (shrinks, with the full name disclosed) before the
		track or the readout. In the vertical form both text rows span the column
		and centre their glyphs on the track's centre line. ]]
	local textSpan: { [string]: any } = if vertical then { width = FILL, textAlign = "center" } else {}
	local rowChildren = {
		UI.Text(merge({
			id = "Label",
			text = spec.label or "",
			textSize = "body",
			shrinkWeight = 1,
			disclose = true,
		}, textSpan)),
		trackHost,
		UI.Text(merge({
			id = "Value",
			text = readout,
			textSize = "body",
			width = if vertical then nil else { type = "minMax", min = READOUT_MIN_WIDTH },
		}, textSpan)),
	}
	local root = if vertical
		then UI.VStack({ id = id, gap = LABEL_GAP, align = "center", height = FILL, children = rowChildren })
		else UI.HStack({ id = id, gap = LABEL_GAP, align = "center", width = FILL, children = rowChildren })

	if spec.row then
		assert(spec.row.value == nil, "UI.Slider.row: value is supplied by the slider")
		local header = menuRecipe.semantic(UI, spec.label, spec.row, readout)
		table.insert(header, rowChildren[2])
		root = UI.corners(
			UI.VStack({
				id = id,
				width = UI.fill(),
				gap = "s",
				-- the Button row's own inset, so stacked rows share one icon column
				padding = "controls.button.padding",
				surface = "control",
				stroke = focusStroke,
				children = header,
			}),
			"control"
		)
	end

	local rootPath: string? = nil
	local thumbPath: string? = nil
	local upperThumbPath: string? = nil
	local nativeDetector = false
	local detectorAttached = false
	local hoverAttached = false

	-- Attach once after both the controller and solved track path are available.
	-- Targets without native drag support use the same handlers through Grip.
	local function tryAttach()
		if disposed or boundController == nil or trackPath == nil then
			return
		end
		if not detectorAttached and boundController.attachDragDetector ~= nil then
			detectorAttached = true
			local detach = boundController.attachDragDetector(trackPath, {
				onStart = function(pos: any)
					beginDrag(if pos ~= nil then pos.x else 0, if pos ~= nil then pos.y else 0)
				end,
				onContinue = function(pos: any)
					if pos ~= nil then
						setFromPoint(pos.x, pos.y)
					end
				end,
				onEnd = function()
					endDrag()
				end,
			})
			nativeDetector = detach ~= nil
			if detach ~= nil then
				owner.own(detach)
			end
		end
		-- hover only for "auto"; asked of the engine's hover stream so the handle
		-- appears before the press
		if not hoverAttached and thumbMode == "auto" and boundController.attachContextGestures ~= nil then
			hoverAttached = true
			local off = boundController.attachContextGestures(trackPath, {
				onHoverChanged = function(on: boolean)
					hovered:set(on == true)
				end,
			})
			if off ~= nil then
				owner.own(off)
			end
		end
	end

	-- resolve this control's own nodes by identity, whichever seam asks first
	local function learnPaths(rootNode: any?)
		if rootNode == nil then
			return
		end
		if
			trackPath ~= nil
			and thumbPath ~= nil
			and (not isRange or (handlePaths.upper ~= nil and upperThumbPath ~= nil))
		then
			return
		end
		local function find(node: any)
			if node.id == "Track" and node.class == "Grip" then
				trackPath = node.path
			elseif node.id == "HandleLower" then
				handlePaths.lower = node.path
			elseif node.id == "HandleUpper" then
				handlePaths.upper = node.path
			elseif node.id == "Thumb" or node.id == "ThumbLower" then
				thumbPath = node.path
			elseif node.id == "ThumbUpper" then
				upperThumbPath = node.path
			end
			for _, child in node.children or {} do
				find(child)
			end
		end
		find(rootNode)
	end

	-- a pad has no Tab: on a range its arrows reach the other thumb until
	-- Activate engages adjust mode
	local function padPrimary(): boolean
		local classes: any = if env ~= nil then env:get("interactionClasses"):peek() else nil
		return type(classes) == "table" and classes.primary == "gamepad"
	end
	local function disengage(): boolean
		if not engaged:peek() then
			return false
		end
		engaged:set(false)
		return true
	end

	local built = contribution.attach(root, {
		syncGeometry = function(rectOf: (string) -> any, rootNode: any?)
			if rootNode ~= nil then
				rootPath = rootNode.path
				learnPaths(rootNode)
			end
			if trackPath ~= nil then
				trackRect:set(rectOf(trackPath))
				tryAttach()
				syncTrackFocus()
			end
			if thumbPath ~= nil then
				thumbRect:set(rectOf(thumbPath))
			end
			if upperThumbPath ~= nil then
				upperThumbRect:set(rectOf(upperThumbPath))
			end
		end,
		bindController = function(controller: any)
			boundController = controller
			tryAttach()
		end,
		-- Rebinding replaces subscriptions rather than retaining the previous graph.
		bindFocusGraph = function(graph: any, paintAllowed: any)
			focusGraph = graph
			focusPaintAllowed = paintAllowed
			if focusOwner then
				focusOwner.dispose()
			end
			focusOwner = Compose.createOwner()
			focusOwner.watch(function(use)
				use(graph.focused)
				if paintAllowed ~= nil then
					use(paintAllowed)
				end
				syncTrackFocus()
			end)
			syncTrackFocus()
		end,
		-- one group for the two handles: Tab walks both, then leaves
		focusGroups = if isRange
			then function(rootNode: any)
				learnPaths(rootNode)
				local lower, upper = handlePaths.lower, handlePaths.upper
				if lower == nil or upper == nil then
					return {}
				end
				return {
					{
						name = `slider-{id}-thumbs`,
						axis = if vertical then "vertical" else "horizontal",
						entry = "first",
						order = if vertical then { upper, lower } else { lower, upper },
					},
				}
			end
			else nil,
		-- Activate toggles adjust mode on a handle, for a pad only
		handleActivate = if isRange
			then function(path: string): boolean
				if path ~= handlePaths.lower and path ~= handlePaths.upper then
					return false
				end
				if not isEnabled() or not padPrimary() then
					return false
				end
				engaged:set(not engaged:peek())
				return true
			end
			else nil,
		handleCancel = if isRange
			then function(): boolean
				return disengage()
			end
			else nil,
		-- Tab is always a way out: drop the mode, let traversal move on
		handleTraverse = if isRange
			then function(): boolean
				disengage()
				return false
			end
			else nil,
		adjustRepeat = true,
		adjustTargets = function(ownRoot: any): { [string]: boolean }
			learnPaths(ownRoot)
			local targets: { [string]: boolean } = {}
			for _, path in (if isRange then { handlePaths.lower, handlePaths.upper } else { trackPath }) :: { any } do
				targets[path] = true
			end
			return targets
		end,
		-- the arrows follow the AUTHORED axis, never the painted rotation
		adjustAxis = if vertical then "vertical" else "horizontal",
		handleAdjust = function(path: string, direction: number): boolean
			-- vertical Adjust reads Down as +1; up increases a bottom-to-top track
			if vertical then
				direction = -direction
			end
			if isRange then
				if path == handlePaths.lower then
					setActive("lower")
				elseif path == handlePaths.upper then
					setActive("upper")
				else
					return false
				end
				if not engaged:peek() and padPrimary() then
					return false -- not engaged on a pad: the arrow reaches the other thumb
				end
				-- a thumb stopped by its partner keeps the arrow: it never hops over
				return adjust(direction) or (activeThumb == "lower") == (direction > 0)
			end
			return adjust(direction)
		end,
	})

	local api = {}
	api.blueprint = built
	api.model = model
	api.semanticText = semantic
	api.fillWidth = fillWidth
	api.thumbOffset = thumbOffset

	function api.onInteractionClassLost(class: string)
		if class == "pointer" or class == "touch" then
			cancelDrag()
		end
	end

	function api.dump()
		local v: any = if isRange then pairNow() else value:peek()
		local scalar: number = if isRange then v.lower else v
		return {
			schema = "facet-slider-dump/1",
			id = id,
			value = v,
			formatted = if isRange then readout:peek() else model.format(scalar),
			semanticText = semantic:peek(),
			fraction = model.fraction(scalar),
			min = model.min,
			max = model.max,
			step = model.currentStep(),
			axis = axis,
			range = isRange,
			minGap = minGap,
			thumb = thumbMode,
			thumbContent = spec.thumbContent ~= nil,
			trackContent = spec.trackContent ~= nil,
			rotation = rotationNow(),
			controlSize = read(spec.controlSize),
			activeThumb = if isRange then activeThumb else nil,
			engaged = if isRange then engaged:peek() else nil,
			upperFraction = if isRange then model.fraction(v.upper) else nil,
			dragging = dragging:peek(),
			nativeDetector = nativeDetector,
			tapToPosition = tapToPosition,
			trackWidth = if trackRect:peek() ~= nil then trackRect:peek().w else nil,
			rootPath = rootPath,
			trackPath = trackPath,
			thumbPath = thumbPath,
			handlePaths = if isRange then { lower = handlePaths.lower, upper = handlePaths.upper } else nil,
			skinRung = if spec.thumbImage ~= nil or spec.trackImage ~= nil then "view" else "theme",
			thumbImage = spec.thumbImage,
			trackImage = spec.trackImage,
		}
	end

	-- what a range refused, in order (bounded; see `validated`)
	function api.diagnostics(): { string }
		return table.clone(diagnostics)
	end

	function api.dispose()
		if disposed then
			return
		end
		disposed = true
		if focusOwner then
			focusOwner.dispose()
			focusOwner = nil
		end
		owner.dispose()
	end

	return api
end

-- The handle owns one Compose lifetime, including subscriptions made after mount.
function slider.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end

return slider
