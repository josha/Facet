--!strict
--[[ ColorPicker — a colour well that opens a panel, or the panel inline (phase5
	P5a, D7).

	CONTROLLED. `value` (a Color3, or nil with `allowEmpty`) and `alpha` (0..1,
	optional) are the caller's. Every accepted change proposes `onChange(color)` /
	`onAlphaChange(alpha)` and the panel repaints from what the caller then holds,
	so a refused proposal never paints. `onCommit(color)` ends a gesture (drag end,
	slider release, swatch press, field commit) — or, with `draft = true`, fires
	only on Apply.

	CANONICAL STATE IS HSV FLOATS beside the caller's Color3 (`color_value`): a
	grey keeps the hue the player set, and readouts are formatted from canonical
	and never parsed back except on an explicit field commit.

	THE CLOSED FORM is a well: labelled, a form row (label, swatch, value text,
	chevron); bare, the swatch alone with the value as its name. It owns its open
	state unless the caller binds `isPresented`/`onPresentedChange`, and it opens
	through `UI.Popover`: an anchored panel, a `hug` sheet on a compact touch
	screen, and a centred sheet at ten feet. `style = "inline"` mounts the panel as
	layout content.

	ONE COMMIT MODEL, every route and input. Without `draft`, every change commits
	as it happens (once per gesture or stick session), and B, Escape, an outside
	tap or the sheet's Close only close: nothing is restored. With `draft = true`
	nothing commits until Apply, and every other close restores the open-time
	snapshot through `onChange`/`onAlphaChange` (a caller write while the panel is
	open re-bases that snapshot).

	THE PANEL: technique tabs (`modes`: swatches | spectrum | sliders | brick), the
	technique, opacity when `alpha` is supplied, and a preview + RGB/HSV/Hex
	readout on every tab — the non-drag route for every quantity. The spectrum
	plane drags 1:1 (and through the native drag detector), cancels on a lost
	pointer class, and on a pad is steered by the RIGHT stick while it holds focus
	(the left stick and D-pad keep navigating), with a live hint saying so. There
	is no eyedropper: the engine has no screen-pixel read. ]]
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local ownedFormula = require("../core/owned_formula")
local contribution = require("../input/contribution")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local surfaceEnv = require("../env/surface_env")
local themeSnapshot = require("../themes/snapshot")
local vocabulary = require("./control_vocabulary")
local fieldChrome = require("./field_chrome")
local labelControl = require("./label")
local colorValue = require("./color_value")

type Hsv = colorValue.Hsv

local color_picker = {}

local specTypes = require("../spec_types/color_picker")
export type Spec = specTypes.Spec

local KEYS = guard.keySet({
	"allowEmpty",
	"alpha",
	"appearance",
	"controlSize",
	"corners",
	"draft",
	"enabled",
	"env",
	"errorText",
	"hint",
	"id",
	"isPresented",
	"label",
	"modes",
	"onAlphaChange",
	"onChange",
	"onCommit",
	"onDismiss",
	"onPresentedChange",
	"placeholder",
	"readOnly",
	"requiredMark",
	"style",
	"swatches",
	"value",
})
local MODE_WORDS = { "swatches", "spectrum", "sliders", "brick" }
local MODE_SET = guard.keySet(MODE_WORDS)
local MODE_LABEL = { swatches = "Swatches", spectrum = "Spectrum", sliders = "Sliders", brick = "Bricks" }
local DEFAULT_MODES = { "swatches", "spectrum", "sliders" }
local FORMATS = {
	{ value = "rgb", label = "RGB" },
	{ value = "hsv", label = "HSV" },
	{ value = "hex", label = "Hex" },
}
local DUMP_SCHEMA = "facet-color_picker-dump/1"
-- the grid's widest line; a narrower panel drops columns, never shrinks a target
local MAX_COLUMNS = 8
-- the plane's value bands: each band is exact across saturation (a white -> hue
-- ramp at its own value); a gradient's alpha ceiling rules out one black overlay
local PLANE_BANDS = 24
-- a gradient's rotation in degrees: 0 runs left to right (the default is down)
local ACROSS = 0
-- plane fractions per second at a full right-stick deflection
local STICK_SPEED = 0.6
local STICK_DEADZONE = 0.2
-- the opacity slider and field run in percent
local PERCENT = 100

local function isColor(v: any): boolean
	return typeof(v) == "Color3"
end

local function finite01(v: any): boolean
	return type(v) == "number" and v == v and v >= 0 and v <= 1
end

-- `swatches` items: a bare Color3 or { color, label? }; key = label or hex
local function normalizeSwatches(list: any, where: string): ({ colorValue.Swatch }?, string?)
	if type(list) ~= "table" then
		return nil, "is an array of Color3 or { color, label? }"
	end
	local out: { colorValue.Swatch } = {}
	local seen: { [string]: boolean } = {}
	for i, item in list do
		local color, label = item, nil
		if type(item) == "table" and not isColor(item) then
			color, label = item.color, item.label
			for key in item do
				if key ~= "color" and key ~= "label" then
					return nil, `item {i} has an unknown key '{tostring(key)}' (it is \{ color, label? })`
				end
			end
		end
		if not isColor(color) or (label ~= nil and type(label) ~= "string") then
			return nil, `item {i} is a Color3 or \{ color = Color3, label = string? }`
		end
		local key = label or colorValue.hex(color)
		if seen[key] then
			return nil, `repeats '{key}' (a label or hex is the item's key)`
		end
		seen[key] = true
		table.insert(out, { color = color, label = label, key = key })
	end
	return out, nil
end

local function build(Facet: any, core: any, spec: Spec, owner: any)
	guard.assertKnownKeys("UI.ColorPicker", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "ColorPicker"
	local where = `UI.ColorPicker('{id}')`
	local function refuse(message: string)
		error(`Facet {where}: {message}`, 0)
	end

	-- ===== the contract, refused at construction ==========================
	local allowEmpty = spec.allowEmpty == true
	if spec.allowEmpty ~= nil and type(spec.allowEmpty) ~= "boolean" then
		refuse("`allowEmpty` is true or false.")
	end
	local valueNow = selection.read(spec.value)
	if not (isColor(valueNow) or (valueNow == nil and allowEmpty)) then
		refuse("`value` is a Color3 (or a bound one); nil only with `allowEmpty = true`.")
	end
	for _, key in { "onChange", "onCommit", "onAlphaChange", "onPresentedChange", "onDismiss" } do
		if (spec :: any)[key] ~= nil and type((spec :: any)[key]) ~= "function" then
			refuse(`\`{key}\` is a function.`)
		end
	end
	local readOnlyNow = selection.read(spec.readOnly)
	if readOnlyNow ~= nil and type(readOnlyNow) ~= "boolean" then
		refuse("`readOnly` is a boolean or a bound boolean.")
	end
	if spec.onChange == nil and readOnlyNow ~= true then
		refuse("an interactive ColorPicker needs `onChange(color)`; only a readOnly one may omit it.")
	end
	local hasAlpha = spec.alpha ~= nil
	if hasAlpha then
		if not finite01(selection.read(spec.alpha)) then
			refuse("`alpha` is a number from 0 to 1 (or a bound one).")
		end
		if spec.onAlphaChange == nil and readOnlyNow ~= true then
			refuse("`alpha` needs `onAlphaChange(alpha)`: the pair is what mounts the opacity control.")
		end
	elseif spec.onAlphaChange ~= nil then
		refuse("`onAlphaChange` needs `alpha`: without it there is no opacity to change.")
	end
	local style = spec.style or "automatic"
	if style ~= "automatic" and style ~= "inline" then
		refuse('`style` is "automatic" (a well that opens the panel) or "inline" (the panel in place).')
	end
	if style == "inline" and (spec.isPresented ~= nil or spec.onPresentedChange ~= nil) then
		refuse("an inline panel is always shown: `isPresented`/`onPresentedChange` belong to the well.")
	end
	if spec.draft ~= nil and type(spec.draft) ~= "boolean" then
		refuse("`draft` is true or false.")
	end
	local draft = spec.draft == true
	if spec.placeholder ~= nil and type(spec.placeholder) ~= "string" then
		refuse("`placeholder` is a string.")
	end
	local modes: { string } = {}
	do
		local listed = spec.modes or DEFAULT_MODES
		if selection.isSource(listed) or type(listed) ~= "table" or #listed == 0 then
			refuse(
				'`modes` is a non-empty list of "swatches" | "spectrum" | "sliders" | "brick", fixed at construction.'
			)
		end
		local seen: { [string]: boolean } = {}
		for _, word in listed :: { any } do
			if not MODE_SET[word] or seen[word] then
				refuse(
					`\`modes\` names each of "swatches" | "spectrum" | "sliders" | "brick" at most once (got '{tostring(
						word
					)}').`
				)
			end
			seen[word] = true
			table.insert(modes, word)
		end
	end
	if spec.swatches ~= nil then
		local _, why = normalizeSwatches(selection.read(spec.swatches), where)
		if why ~= nil then
			refuse(`\`swatches\` {why}.`)
		end
	end
	fieldChrome.assertSpec("UI.ColorPicker", spec)
	local env = if spec.env ~= nil then spec.env else surfaceEnv.find(core)
	local onChange: any = spec.onChange

	-- ===== legal values only ==============================================
	local diagnostics: { string } = {}
	local function legal(key: string, source: any, ok: (any) -> boolean, what: string): any
		local last = selection.read(source)
		local refused = false
		return ownedFormula(owner, function(use)
			local v = selection.read(source, use)
			if ok(v) then
				last, refused = v, false
			elseif not refused then
				refused = true
				selection.note(diagnostics, `Facet {where}: \`{key}\` {what} — keeping the last legal value`)
			end
			return last
		end)
	end
	local value = legal("value", spec.value, function(v)
		return isColor(v) or (v == nil and allowEmpty)
	end, if allowEmpty then "is a Color3 or nil" else "is a Color3")
	local alpha = if hasAlpha
		then legal("alpha", spec.alpha, finite01, "is a number from 0 to 1")
		else ownedFormula(owner, function()
			return 1
		end)
	local swatchList = ownedFormula(owner, function(use)
		if spec.swatches == nil then
			return colorValue.standard()
		end
		local list, why = normalizeSwatches(selection.read(spec.swatches, use), where)
		if list == nil then
			selection.note(diagnostics, `Facet {where}: \`swatches\` {why} — showing none`)
			return {}
		end
		return list
	end)
	local enabled = ownedFormula(owner, function(use)
		return selection.read(spec.enabled, use) ~= false
	end)
	local readOnly = legal("readOnly", spec.readOnly, function(v)
		return (v == nil or type(v) == "boolean") and (v == true or onChange ~= nil)
	end, "cannot turn off without onChange")
	local interactive = ownedFormula(owner, function(use)
		return use(enabled) and use(readOnly) ~= true
	end)

	-- ===== canonical HSV beside the caller's colour ========================
	local canon = Compose.cell(if isColor(valueNow) then colorValue.hsvOf(valueNow) else { h = 0, s = 0, v = 1 })
	local empty = ownedFormula(owner, function(use)
		return use(value) == nil
	end)
	local proposing = false
	local snapshot: any = nil
	local function takeSnapshot()
		snapshot = { value = value:peek(), alpha = alpha:peek(), canon = canon:peek() }
	end
	takeSnapshot()
	-- a caller write that is not this panel's own echo moves canonical (keeping
	-- a grey's hue) and re-bases the Cancel snapshot to the new authority
	owner.watchStatic(value, function(v: any)
		if isColor(v) and not colorValue.same(v, colorValue.toColor(canon:peek())) then
			canon:set(colorValue.hsvOf(v, canon:peek()))
		end
		if not proposing then
			takeSnapshot()
		end
	end)
	owner.watchStatic(alpha, function()
		if not proposing and snapshot ~= nil then
			snapshot.alpha = alpha:peek()
		end
	end)

	local disposed = false
	owner.own(function()
		disposed = true
	end)
	local function mayEdit(): boolean
		return not disposed and interactive:peek()
	end

	-- a watch under whichever owner is building now (a presentation's, or this control's)
	local function follow(source: any, fn: (any) -> ())
		(Compose.currentOwner() or owner).watchStatic(source, fn)
	end

	-- the ONE colour write: propose, and adopt canonical only if the caller took it
	local function propose(next: Hsv): boolean
		if not mayEdit() then
			return false
		end
		local color = colorValue.toColor(next)
		local held = value:peek()
		if held ~= nil and colorValue.same(held, color) then
			-- the same bytes (a hue moved under a grey): nothing to ask the caller
			canon:set(next)
			return true
		end
		proposing = true
		local ok, err = pcall(onChange, color)
		proposing = false
		if not ok then
			error(err, 0)
		end
		local now = value:peek()
		if now ~= nil and colorValue.same(now, color) then
			canon:set(next)
			return true
		end
		canon:set(canon:peek()) -- a refusal repaints every readout from canonical
		return false
	end
	local function proposeAlpha(next: number): boolean
		if not mayEdit() or spec.onAlphaChange == nil then
			return false
		end
		next = math.clamp(next, 0, 1)
		if next == alpha:peek() then
			return false
		end
		proposing = true
		local ok, err = pcall(spec.onAlphaChange :: any, next)
		proposing = false
		if not ok then
			error(err, 0)
		end
		return alpha:peek() == next
	end
	local function commit()
		if disposed or draft or spec.onCommit == nil then
			return
		end
		local v = value:peek()
		if v ~= nil then
			spec.onCommit(v)
		end
	end
	local function apply()
		if spec.onCommit ~= nil and value:peek() ~= nil then
			spec.onCommit(value:peek())
		end
		takeSnapshot()
	end
	local function restore()
		local saved = snapshot
		if saved == nil or disposed then
			return
		end
		if not colorValue.same(value:peek(), saved.value) or (value:peek() == nil) ~= (saved.value == nil) then
			proposing = true
			pcall(onChange, saved.value)
			proposing = false
		end
		if hasAlpha and spec.onAlphaChange ~= nil and alpha:peek() ~= saved.alpha then
			proposing = true
			pcall(spec.onAlphaChange :: any, saved.alpha)
			proposing = false
		end
		canon:set(saved.canon)
	end

	-- ===== the words a colour is written in ================================
	local brickMode = table.find(modes, "brick") ~= nil
	local function brickName(c: any): string?
		for _, entry in colorValue.brick() do
			if colorValue.same(entry.color, c) then
				return entry.label
			end
		end
		return nil
	end
	local valueText = ownedFormula(owner, function(use)
		local v = use(value)
		if v == nil then
			return spec.placeholder or ""
		end
		local a = use(alpha)
		return colorValue.hex(v, if hasAlpha and a < 1 then a else nil)
	end)
	local semanticName = ownedFormula(owner, function(use)
		local v = use(value)
		local name = if v ~= nil and brickMode then brickName(v) else nil
		local words = name or use(valueText)
		local label = selection.read(spec.label, use)
		return if type(label) == "string" and label ~= "" then `{label}, {words}` else words
	end)

	-- ===== paint: the swatch every part of the control draws ================
	local function metric(use: any, path: string, fallback: number): number
		local metrics = if env ~= nil then use(env:get("themeMetrics")) else themeSnapshot.neutral()
		return themeSnapshot.resolveNumber(metrics or themeSnapshot.neutral(), path) or fallback
	end
	--[[ A swatch: a hairline-ringed plate over a 2 × 2 leaf-tinted checker (only
		under a translucent colour), or an empty plate crossed by one stroke. No
		surface anywhere: every part paints through its own leaf's tint, so a theme
		package cannot put a plate behind it. `paint` answers { color?, alpha }. ]]
	local function swatchView(swatchId: string, edge: any, paint: any): any
		local function cell(cellId: string, role: string): any
			return UI.Box({ id = cellId, width = UI.fill(), height = UI.fill(), tint = { role = role, blend = 1 } })
		end
		local translucent = Compose.formula(function(use)
			local p = use(paint)
			return p.color ~= nil and p.alpha < 1
		end)
		return UI.stroke(
			UI.corners(
				UI.ZStack({
					id = swatchId,
					width = edge,
					height = edge,
					children = {
						UI.VStack({
							id = "Checker",
							width = UI.fill(),
							height = UI.fill(),
							gap = 0,
							hidden = Compose.formula(function(use)
								return not use(translucent)
							end),
							children = {
								UI.HStack({
									id = "Top",
									width = UI.fill(),
									height = UI.fill(),
									gap = 0,
									children = { cell("A", "surface"), cell("B", "surfaceStrong") },
								}),
								UI.HStack({
									id = "Bottom",
									width = UI.fill(),
									height = UI.fill(),
									gap = 0,
									children = { cell("C", "surfaceStrong"), cell("D", "surface") },
								}),
							},
						}),
						UI.Box({
							id = "Plate",
							width = UI.fill(),
							height = UI.fill(),
							tint = Compose.formula(function(use)
								local p = use(paint)
								if p.color == nil then
									return { role = "surface", blend = 1 }
								end
								return { direct = colorValue.tintHex(p.color), transparency = 1 - p.alpha }
							end),
						}),
						UI.Path({
							id = "Empty",
							points = {
								{ x = 0.15, y = 0.85, inX = 0, inY = 0, outX = 0, outY = 0 },
								{ x = 0.85, y = 0.15, inX = 0, inY = 0, outX = 0, outY = 0 },
							},
							width = UI.fill(),
							height = UI.fill(),
							thickness = "strokes.hairline",
							tint = { role = "contentSecondary", blend = 1 },
							hidden = Compose.formula(function(use)
								return use(paint).color ~= nil
							end),
						}),
					},
				}),
				"control"
			),
			{}
		)
	end
	local currentPaint = ownedFormula(owner, function(use)
		return { color = use(value), alpha = use(alpha) }
	end)

	-- ===== presentation: owned unless the caller binds it ===================
	local openCell = Compose.cell(false)
	local presented = if spec.isPresented ~= nil
		then ownedFormula(owner, function(use)
			return selection.read(spec.isPresented, use) == true
		end)
		else openCell
	local closeWhy: string? = nil -- the reason this control itself closed for
	local asked = false -- the popover proposed a close (Cancel / outside)
	local function requestPresented(next: boolean)
		if next and (not interactive:peek() or disposed) then
			return
		end
		if spec.onPresentedChange ~= nil then
			spec.onPresentedChange(next)
		elseif spec.isPresented == nil then
			openCell:set(next)
		end
	end
	owner.watchStatic(presented, function(on: boolean)
		if on then
			takeSnapshot()
		end
	end)
	local popoverApi: any = nil
	local function close(why: string)
		closeWhy = why
		requestPresented(false)
	end

	-- ===== the panel ========================================================
	local modeCell = Compose.cell(modes[1])
	local formatCell = Compose.cell("rgb")
	local hexError = Compose.cell("")
	local planeRect = Compose.cell(nil :: any)
	local focusedPath = Compose.cell(nil :: string?)
	local planePath: string? = nil
	local swatchPaths: { string } = {}
	local columns = Compose.cell(MAX_COLUMNS)
	-- the most an anchored panel may be tall: the room beside its well (set on sync)
	local roomPx = Compose.cell(math.huge)
	local wellPath: string? = nil
	local wellController: any = nil
	local stick = { x = 0, y = 0 }
	local stickTimer: any = nil
	local stickWatch: (() -> ())? = nil
	local motionClock: any = nil
	local boundController: any = nil
	local dragStart: Hsv? = nil
	local dragging = Compose.cell(false)

	local function setFromPoint(px: number, py: number, rectOf: any?)
		local rect = (rectOf ~= nil and planePath ~= nil and rectOf(planePath)) or planeRect:peek()
		if rect == nil or rect.w <= 0 or rect.h <= 0 then
			return
		end
		local now = canon:peek()
		propose({
			h = now.h,
			s = math.clamp((px - rect.x) / rect.w, 0, 1),
			v = math.clamp(1 - (py - rect.y) / rect.h, 0, 1),
		})
	end
	local function beginDrag(px: number, py: number, rectOf: any?): boolean
		if not mayEdit() then
			return false
		end
		if not dragging:peek() then
			dragStart = canon:peek()
			dragging:set(true)
		end
		setFromPoint(px, py, rectOf)
		return true
	end
	local function endDrag()
		if not dragging:peek() then
			return
		end
		dragging:set(false)
		dragStart = nil
		commit()
	end
	-- a lost pointer class or a cancelled capture restores where the drag began
	local function cancelDrag()
		if not dragging:peek() then
			return
		end
		dragging:set(false)
		local start = dragStart
		dragStart = nil
		if start ~= nil then
			propose(start)
		end
	end
	if env ~= nil then
		owner.watch(function(use)
			local classes = use(env:get("interactionClasses"))
			if type(classes) == "table" and classes.pointer ~= true and classes.touch ~= true then
				cancelDrag()
			end
		end)
	end

	-- the right stick steers the plane while it holds focus: one frame source
	-- while the stick is off-centre, none at rest
	local function stopStick()
		if stickTimer ~= nil then
			stickTimer:dispose()
			stickTimer = nil
		end
		if stickWatch ~= nil then
			stickWatch()
			stickWatch = nil
		end
	end
	local function steer(dt: number)
		if dt <= 0 or focusedPath:peek() ~= planePath or not mayEdit() then
			return
		end
		local now = canon:peek()
		propose({
			h = now.h,
			s = math.clamp(now.s + stick.x * STICK_SPEED * dt, 0, 1),
			v = math.clamp(now.v - stick.y * STICK_SPEED * dt, 0, 1),
		})
	end
	local function onStick(x: number, y: number)
		local live = math.sqrt(x * x + y * y) >= STICK_DEADZONE
		stick.x, stick.y = if live then x else 0, if live then y else 0
		if not live then
			if stickTimer ~= nil then
				stopStick()
				commit()
			end
			return
		end
		if stickTimer == nil and motionClock ~= nil then
			local timer = motionClock:timer({ from = 0, to = 1e6, duration = 1e6, kind = "informational" })
			local last = 0
			stickTimer = timer
			stickWatch = owner.watchStatic(timer, function(t: number)
				if stickTimer == timer then
					steer(t - last)
				end
				last = t
			end)
		end
	end
	owner.own(stopStick)

	local function planeView(): any
		local bands: { any } = {}
		for i = 1, PLANE_BANDS do
			local v = 1 - (i - 1) / (PLANE_BANDS - 1)
			table.insert(
				bands,
				UI.Box({
					id = `Band{i}`,
					width = UI.fill(),
					height = UI.fill(),
					tint = { direct = "#ffffff" },
					gradient = Compose.formula(function(use)
						local hue = colorValue.toColor({ h = use(canon).h, s = 1, v = v })
						local grey = colorValue.toColor({ h = 0, s = 0, v = v })
						return UI.gradientData({
							colors = { colorValue.tintHex(grey), colorValue.tintHex(hue) },
							rotation = ACROSS,
						})
					end),
				})
			)
		end
		local ring = Compose.formula(function(use)
			return metric(use, "controls.slider.thumbSize", 20)
		end)
		local function along(axis: string)
			return Compose.formula(function(use)
				local rect = use(planeRect)
				local c = use(canon)
				local size = use(ring)
				if rect == nil then
					return 0
				end
				local extent = if axis == "x" then rect.w else rect.h
				local f = if axis == "x" then c.s * rect.w else (1 - c.v) * rect.h
				-- the whole ring stays on the plane, so no edge clips it
				return math.clamp(math.floor(f - size / 2 + 0.5), 0, math.max(0, extent - size))
			end)
		end
		local ringEdge = Compose.formula(function(use)
			return { type = "fixed", px = use(ring) }
		end)
		return UI.ZStack({
			id = "Plane",
			width = UI.fill(),
			height = Compose.formula(function(use)
				-- four touch targets tall: a plane a thumb can travel
				local target = metric(use, "targetSizes.minimum", 44)
				return { type = "fixed", px = target * 4 }
			end),
			children = {
				UI.VStack({ id = "Field", width = UI.fill(), height = UI.fill(), gap = 0, children = bands }),
				UI.Anchor({
					id = "Marks",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.stroke(
							UI.corners(
								UI.ZStack({
									id = "Ring",
									anchor = "topLeft",
									offsetX = along("x"),
									offsetY = along("y"),
									width = ringEdge,
									height = ringEdge,
									hidden = empty,
									children = {
										UI.stroke(
											UI.corners(
												UI.Box({ id = "Inner", width = UI.fill(), height = UI.fill() }),
												999
											),
											{ thickness = "hairline", color = "#000000" }
										),
									},
								}),
								999
							),
							{ thickness = "focusRing", color = "#ffffff" }
						),
					},
				}),
				UI.Grip({
					id = "Surface",
					width = UI.fill(),
					height = UI.fill(),
					focusable = interactive,
					onPointerDown = function(_path: string, pos: any, rectOf: any)
						return beginDrag(pos.x, pos.y, rectOf)
					end,
					onPointerMove = function(_path: string, pos: any, rectOf: any)
						if dragging:peek() then
							setFromPoint(pos.x, pos.y, rectOf)
						end
					end,
					onPointerUp = function()
						endDrag()
					end,
					onPointerCancel = function()
						cancelDrag()
						return nil
					end,
				}),
			},
		})
	end

	-- the plane's pad hint: shown while the plane holds focus and a pad is live
	local function stickHint(): any
		local hint = require("./shortcut_hint").build(Facet, core, {
			id = "StickKey",
			keys = { { require("../input/key_names").label("Thumbstick2") or "Right Stick" } },
			controlSize = "compact",
			env = spec.env,
		})
		return UI.HStack({
			id = "StickHint",
			gap = "xs",
			align = "center",
			hidden = Compose.formula(function(use)
				local classes = if env ~= nil then use(env:get("interactionClasses")) else nil
				local pad = type(classes) == "table" and classes.gamepad == true
				return not (pad and use(focusedPath) ~= nil and use(focusedPath) == planePath)
			end),
			children = {
				hint.blueprint,
				UI.Text({
					id = "Words",
					text = "Move saturation and brightness",
					textSize = "caption",
					role = "secondary",
				}),
			},
		})
	end

	-- a Slider over one canonical channel: its cell follows canonical, its moves propose
	local function channelSlider(
		sliderId: string,
		words: string,
		max: number,
		get: (Hsv) -> number,
		with: (Hsv, number) -> Hsv
	): any
		local cell = Compose.cell(get(canon:peek()) * max)
		local sync = Compose.formula(function(use)
			return get(use(canon)) * max
		end)
		follow(sync, function(v: number)
			if cell:peek() ~= v then
				cell:set(v)
			end
		end)
		local built = require("./slider").build(Facet, core, {
			id = sliderId,
			label = words,
			value = cell,
			min = 0,
			max = max,
			step = 1,
			enabled = interactive,
			format = function(n: number): string
				return tostring(math.floor(n + 0.5))
			end,
			onChange = function(n: number)
				if not propose(with(canon:peek(), n / max)) then
					cell:set(get(canon:peek()) * max)
				end
			end,
			onCommit = function()
				commit()
			end,
		})
		Compose.cleanup(function()
			built.dispose()
		end)
		return built.blueprint
	end
	local function hueSlider(): any
		return channelSlider("Hue", "Hue", 360, function(c)
			return c.h
		end, function(c, f)
			return { h = f, s = c.s, v = c.v }
		end)
	end

	-- one grid of colour cells, one 2-D focus group
	local function gridView(gridId: string, items: any): any
		return UI.Grid({
			id = gridId,
			columns = columns,
			gap = "xs",
			children = {
				UI.ForEach({
					id = "Cells",
					items = items,
					key = function(item: colorValue.Swatch): string
						return item.key
					end,
					row = function(item: colorValue.Swatch): any
						local chosen = Compose.formula(function(use)
							local v = use(value)
							return v ~= nil and colorValue.same(v, item.color)
						end)
						return UI.Button({
							id = "Cell",
							label = item.label or colorValue.hex(item.color),
							surface = "plain",
							padding = "xs",
							selected = chosen,
							enabled = interactive,
							width = { type = "fixed", px = "targetSizes.minimum" },
							height = { type = "fixed", px = "targetSizes.minimum" },
							onActivate = function()
								local next = colorValue.hsvOf(item.color, canon:peek())
								if propose(next) then
									commit()
								end
							end,
							children = {
								UI.ZStack({
									id = "Layers",
									width = UI.fill(),
									height = UI.fill(),
									alignH = "center",
									alignV = "center",
									children = {
										swatchView(
											"Swatch",
											UI.fill(),
											Compose.formula(function()
												return { color = item.color, alpha = 1 }
											end)
										),
										labelControl.icon(UI, "checkmark", {
											id = "Check",
											size = "iconSizes.small",
											tint = { role = "onAccent", blend = 1 },
											hidden = Compose.formula(function(use)
												return not use(chosen)
											end),
										}),
									},
								}),
							},
						})
					end,
				}),
			},
		})
	end

	local function brickView(): any
		return UI.VStack({
			id = "Brick",
			width = UI.fill(),
			gap = "s",
			children = {
				gridView(
					"BrickGrid",
					Compose.formula(function()
						return colorValue.brick()
					end)
				),
				UI.Text({
					id = "BrickName",
					textSize = "caption",
					role = "secondary",
					text = Compose.formula(function(use)
						local v = use(value)
						return (if v ~= nil then brickName(v) else nil) or "No engine colour matches"
					end),
				}),
			},
		})
	end

	local function numberField(
		fieldId: string,
		words: string,
		max: number,
		get: (any, Hsv) -> number,
		apply: (number) -> Hsv?
	): any
		local text = Compose.cell("")
		local number = Compose.cell(0)
		local sync = Compose.formula(function(use)
			local v = use(value)
			return if v == nil then nil else get(v, use(canon))
		end)
		local function resync(n: number?)
			number:set(n or 0)
			text:set(if n ~= nil then tostring(n) else "")
		end
		resync(sync:peek())
		follow(sync, resync)
		local built = require("./text_input").buildNumber(Facet, core, {
			id = fieldId,
			label = words,
			value = text,
			numericValue = number,
			min = 0,
			max = max,
			step = 1,
			precision = 0,
			enabled = interactive,
			env = spec.env,
			onCommit = function(n: any)
				local next = apply(n)
				if next ~= nil and propose(next) then
					commit()
				else
					resync(sync:peek())
				end
			end,
		})
		Compose.cleanup(function()
			built.dispose()
		end)
		return built.blueprint
	end
	local function rgbFields(): any
		local function channel(i: number, words: string): any
			return numberField(`Field{words}`, words, 255, function(v)
				return (select(i, colorValue.channels(v)))
			end, function(n: number)
				local r, g, b = colorValue.channels(value:peek() or colorValue.toColor(canon:peek()))
				local bytes = { r, g, b }
				bytes[i] = n
				return colorValue.hsvOf(colorValue.fromBytes(bytes[1], bytes[2], bytes[3]), canon:peek())
			end)
		end
		return UI.HStack({
			id = "Fields",
			width = UI.fill(),
			gap = "s",
			children = { channel(1, "R"), channel(2, "G"), channel(3, "B") },
		})
	end
	local function hsvFields(): any
		local function channel(key: string, words: string, max: number): any
			return numberField(`Field{words}`, words, max, function(_v, c: any)
				return math.floor(c[key] * max + 0.5)
			end, function(n: number)
				local c = table.clone(canon:peek()) :: any
				c[key] = n / max
				return c
			end)
		end
		return UI.HStack({
			id = "Fields",
			width = UI.fill(),
			gap = "s",
			children = { channel("h", "H", 360), channel("s", "S", 100), channel("v", "V", 100) },
		})
	end
	local function hexField(): any
		local text = Compose.cell("")
		local sync = Compose.formula(function(use)
			local v = use(value)
			local a = use(alpha)
			return if v == nil then "" else colorValue.hex(v, if hasAlpha then a else nil)
		end)
		text:set(sync:peek())
		follow(sync, function(s: string)
			text:set(s)
			hexError:set("")
		end)
		local built = require("./text_input").build(Facet, core, {
			id = "FieldHex",
			label = "Hex",
			value = text,
			enabled = interactive,
			errorText = hexError,
			env = spec.env,
			onCommit = function(typed: any)
				local color, a, why = colorValue.parseHex(typed, hasAlpha)
				if color == nil then
					-- the typed text stays; nothing is committed
					hexError:set(why or "")
					return
				end
				hexError:set("")
				local moved = propose(colorValue.hsvOf(color, canon:peek()))
				if a ~= nil then
					moved = proposeAlpha(a) or moved
				end
				if moved then
					commit()
				end
				text:set(sync:peek())
			end,
		})
		Compose.cleanup(function()
			built.dispose()
		end)
		return UI.HStack({ id = "Fields", width = UI.fill(), children = { built.blueprint } })
	end

	local function segmented(segId: string, options: { any }, cell: any): any
		-- the Picker's own space rule: a strip too crowded for a compact screen is
		-- a menu there, never a row of truncated segments
		local pickerLib = require("./picker")
		local longest = 0
		for _, option in options do
			longest = math.max(longest, #option.label)
		end
		local sizeClass = if env ~= nil then env:get("sizeClass"):peek() else nil
		local fits = pickerLib.resolvePresentation(#options, sizeClass, longest) == "segmented"
		local built = pickerLib.build(Facet, core, {
			id = segId,
			options = options,
			selected = cell,
			style = if fits then "segmented" else "menu",
			env = spec.env,
		})
		Compose.cleanup(function()
			built.dispose()
		end)
		return built.blueprint
	end

	local function actionButton(buttonId: string, words: string, fn: () -> ()): any
		return UI.Button({ id = buttonId, label = words, onActivate = fn })
	end

	local function panelView(overlay: boolean): any
		local children: { any } = {}
		if #modes > 1 then
			local options = {}
			for _, mode in modes do
				table.insert(options, { value = mode, label = MODE_LABEL[mode] })
			end
			table.insert(children, segmented("Modes", options, modeCell))
		end
		local views: { [string]: () -> any } = {
			swatches = function()
				return gridView("Swatches", swatchList)
			end,
			spectrum = function()
				return UI.VStack({
					id = "Spectrum",
					width = UI.fill(),
					gap = "s",
					children = { planeView(), stickHint(), hueSlider() },
				})
			end,
			sliders = function()
				return UI.VStack({
					id = "Sliders",
					width = UI.fill(),
					gap = "s",
					children = {
						hueSlider(),
						channelSlider("Saturation", "Saturation", 100, function(c)
							return c.s
						end, function(c, f)
							return { h = c.h, s = f, v = c.v }
						end),
						channelSlider("Brightness", "Brightness", 100, function(c)
							return c.v
						end, function(c, f)
							return { h = c.h, s = c.s, v = f }
						end),
					},
				})
			end,
			brick = brickView,
		}
		local techniques: { any } = {}
		for _, mode in modes do
			table.insert(
				techniques,
				UI.When({
					id = `Show{MODE_LABEL[mode]}`,
					condition = Compose.formula(function(use)
						return use(modeCell) == mode
					end),
					thenView = views[mode],
				})
			)
		end
		-- an anchored panel fits the room beside its well: the technique scrolls
		-- when it must, and everything around it stays put
		table.insert(
			children,
			if overlay
				then UI.ScrollView({
					id = "Body",
					axis = "y",
					width = UI.fill(),
					shrinkWeight = 1,
					children = { UI.VStack({ id = "Technique", width = UI.fill(), children = techniques }) },
				})
				else UI.VStack({ id = "Technique", width = UI.fill(), children = techniques })
		)
		if hasAlpha then
			local cell = Compose.cell(alpha:peek() * 100)
			follow(alpha, function(a: number)
				cell:set(a * 100)
			end)
			local opacity = require("./slider").build(Facet, core, {
				id = "Opacity",
				label = "Opacity",
				value = cell,
				min = 0,
				max = PERCENT,
				step = 1,
				enabled = interactive,
				format = function(n: number): string
					return `{math.floor(n + 0.5)}%`
				end,
				onChange = function(n: number)
					if not proposeAlpha(n / 100) then
						cell:set(alpha:peek() * 100)
					end
				end,
				onCommit = function()
					commit()
				end,
			})
			Compose.cleanup(function()
				opacity.dispose()
			end)
			table.insert(children, opacity.blueprint)
		end
		local fieldViews: { [string]: () -> any } = { rgb = rgbFields, hsv = hsvFields, hex = hexField }
		local fields: { any } = {}
		for _, format in FORMATS do
			table.insert(
				fields,
				UI.When({
					id = `Show{format.label}`,
					condition = Compose.formula(function(use)
						return use(formatCell) == format.value
					end),
					thenView = fieldViews[format.value],
				})
			)
		end
		table.insert(
			children,
			UI.VStack({
				id = "Readout",
				width = UI.fill(),
				gap = "s",
				children = {
					UI.HStack({
						id = "Head",
						width = UI.fill(),
						gap = "s",
						align = "center",
						children = {
							swatchView("Preview", { type = "fixed", px = "targetSizes.minimum" }, currentPaint),
							segmented("Format", FORMATS, formatCell),
						},
					}),
					UI.VStack({ id = "Values", width = UI.fill(), children = fields }),
				},
			})
		)
		local actions: { any } = {}
		if draft then
			table.insert(
				actions,
				actionButton("Cancel", "Cancel", function()
					restore()
					if overlay then
						close("cancel")
					end
				end)
			)
			table.insert(
				actions,
				actionButton("Apply", "Apply", function()
					apply()
					if overlay then
						close("apply")
					end
				end)
			)
		elseif overlay and popoverApi ~= nil and popoverApi.route:peek() == "sheet" then
			-- a sheet's visible way out; every change has already committed
			table.insert(
				actions,
				actionButton("Done", "Done", function()
					close("activate")
				end)
			)
		end
		if #actions > 0 then
			table.insert(
				children,
				UI.HStack({ id = "Actions", width = UI.fill(), gap = "s", distribute = "end", children = actions })
			)
		end

		local panelWidth = if overlay
			then Compose.formula(function(use)
				local cell = metric(use, "targetSizes.minimum", 44)
				local gap = metric(use, "xs", 4)
				local want = MAX_COLUMNS * cell + (MAX_COLUMNS - 1) * gap
				local view = if env ~= nil then use(env:get("viewportRect")) else nil
				local room = if type(view) == "table" then view.w - 6 * metric(use, "m", 16) else want
				return { type = "fixed", px = math.max(cell, math.min(want, room)) }
			end)
			else UI.fill()
		local panel = UI.VStack({
			id = "Panel",
			width = panelWidth,
			height = if overlay
				then Compose.formula(function(use)
					local room = use(roomPx)
					return if room == math.huge then { type = "hug" } else { type = "hug", max = room }
				end)
				else nil,
			gap = "m",
			children = children,
		})
		local panelOwner = Compose.currentOwner() or owner
		local detectorPath: string? = nil
		local detach: (() -> ())? = nil
		Compose.cleanup(function()
			if detach ~= nil then
				detach()
			end
			stopStick()
		end)
		return contribution.attach(panel, {
			syncGeometry = function(rectOf: (string) -> any, node: any?)
				if node == nil then
					return
				end
				local paths: { string } = {}
				planePath = nil
				local function walk(n: any)
					if n.id == "Surface" and n.class == "Grip" then
						planePath = n.path
					elseif n.id == "Cell" and n.class == "Button" then
						table.insert(paths, n.path)
					end
					for _, child in n.children or {} do
						walk(child)
					end
				end
				walk(node)
				swatchPaths = paths
				local r = if planePath ~= nil then rectOf(planePath) else nil
				planeRect:set(r)
				-- the grid's column count follows the width the technique is given
				-- (the scrolling body's, less the bar it takes)
				local bodyPath = `{node.path}/Body`
				local own = rectOf(if overlay then bodyPath else node.path)
				local bar = if overlay
						and boundController ~= nil
						and boundController.scrollBarInsetOf ~= nil
					then boundController.scrollBarInsetOf(bodyPath)
					else nil
				if own ~= nil and type(bar) == "table" then
					own = { w = own.w - (tonumber(bar.right) or 0) }
				end
				if own ~= nil and env ~= nil then
					local metrics = env:get("themeMetrics"):peek() or themeSnapshot.neutral()
					local cell = themeSnapshot.resolveNumber(metrics, "targetSizes.minimum") or 44
					local gap = themeSnapshot.resolveNumber(metrics, "xs") or 4
					local fit = math.clamp(math.floor((own.w + gap) / (cell + gap)), 1, MAX_COLUMNS)
					if fit ~= columns:peek() then
						columns:set(fit)
					end
				end
				-- the anchored panel's room: the larger space above or below the well,
				-- less the anchor's gap and the popover's own chrome around its body
				local popBody = string.match(node.path, "^(.*)/[^/]+$")
				local popPanel = if popBody ~= nil then string.match(popBody, "^(.*)/[^/]+$") else nil
				local outer = if popPanel ~= nil then rectOf(popPanel) else nil
				local inner = if popBody ~= nil then rectOf(popBody) else nil
				local well = if wellController ~= nil and wellPath ~= nil
					then wellController.screenRectOf(wellPath)
					else nil
				local view = if env ~= nil then env:get("viewportRect"):peek() else nil
				local room = math.huge
				if
					overlay
					and popoverApi ~= nil
					and popoverApi.route:peek() == "popover"
					and outer
					and inner
					and well
					and view
				then
					local insets = env:get("coreSafeInsets"):peek() or {}
					local metrics = env:get("themeMetrics"):peek() or themeSnapshot.neutral()
					local gap = themeSnapshot.resolveNumber(metrics, "s") or 8
					local top = view.y + (tonumber(insets.top) or 0)
					local bottom = view.y + view.h - (tonumber(insets.bottom) or 0)
					local beside = math.max(well.y - top, bottom - (well.y + well.h)) - gap
					room = math.max(
						2 * (themeSnapshot.resolveNumber(metrics, "targetSizes.minimum") or 44),
						beside - (outer.h - inner.h)
					)
				end
				if room ~= roomPx:peek() then
					roomPx:set(room)
				end
				-- the native detector drives the same begin/move/end, once per plane node;
				-- a plane that left (another tab) detaches, so its return re-attaches
				if boundController ~= nil and planePath ~= detectorPath then
					if detach ~= nil then
						detach()
						detach = nil
					end
					detectorPath = planePath
					if planePath ~= nil and boundController.attachDragDetector ~= nil then
						detach = boundController.attachDragDetector(planePath, {
							onStart = function(pos: any)
								if pos ~= nil then
									beginDrag(pos.x, pos.y)
								end
							end,
							onContinue = function(pos: any)
								if pos ~= nil and dragging:peek() then
									setFromPoint(pos.x, pos.y)
								end
							end,
							onEnd = function()
								endDrag()
							end,
						})
					end
				end
			end,
			bindController = function(controller: any)
				boundController = controller
			end,
			bindMotion = function(clock: any)
				motionClock = clock
			end,
			bindFocusGraph = function(graph: any)
				panelOwner.watchStatic(graph.focused, function(path: any)
					focusedPath:set(path)
					if path ~= planePath then
						stick.x, stick.y = 0, 0
						if stickTimer ~= nil then
							stopStick()
							commit()
						end
					end
				end)
				focusedPath:set(graph.focused:peek())
			end,
			bindActionSystem = function(system: any)
				-- SINK: while the plane steers, the right stick is the plane's alone —
				-- a default camera's own Thumbstick2 binding sits below and must not
				-- orbit behind the panel. Enabled only while the plane holds focus.
				local ctx = system.createContext({ name = `ColorPlane-{id}`, priority = 1100, sink = true })
				local steerAction = ctx.createAction("Steer", "Direction2D")
				steerAction.bindAxis({ axis = "Thumbstick2" })
				ctx.setEnabled(false)
				panelOwner.watchStatic(steerAction.state, function(v: any)
					if type(v) == "table" then
						onStick(v.x or 0, v.y or 0)
					end
				end)
				panelOwner.watch(function(use)
					local here = use(focusedPath)
					ctx.setEnabled(here ~= nil and here == planePath and use(interactive))
				end)
				panelOwner.own(function()
					ctx.destroy()
				end)
			end,
		})
	end

	-- ===== the closed form ================================================
	local chrome = Compose.withOwner(owner, function()
		return fieldChrome.new({
			UI = UI,
			control = "UI.ColorPicker",
			spec = {
				hint = spec.hint,
				errorText = spec.errorText,
				appearance = spec.appearance,
				controlSize = spec.controlSize,
			},
		})
	end)
	local rung = spec.controlSize or "regular"
	local swatchEdge = vocabulary.derive(rung, function(word)
		return { type = "fixed", px = vocabulary.iconSizeFor(word) or "controlSizes.regular.iconSize" }
	end)
	local labelled = spec.label ~= nil
	local function well(): any
		local parts: { any } = {}
		if labelled then
			table.insert(
				parts,
				UI.Text({
					id = "Title",
					text = fieldChrome.labelText(spec.label, spec.requiredMark),
					textSize = "body",
					shrinkWeight = 1,
					disclose = true,
					width = UI.fill(),
				})
			)
		end
		table.insert(parts, swatchView("Swatch", swatchEdge, currentPaint))
		if labelled then
			-- the value gives way after the label, one line, its full words disclosed
			table.insert(
				parts,
				UI.Text({
					id = "Value",
					text = valueText,
					textSize = "body",
					role = "secondary",
					lineLimit = 1,
					disclose = true,
					shrinkWeight = 1,
				})
			)
			table.insert(
				parts,
				labelControl.icon(
					UI,
					"chevron.down",
					{ id = "Chevron", size = vocabulary.iconSizeFor(rung) or "iconSizes.small" }
				)
			)
		end
		local floor = { type = "minMax", min = "targetSizes.minimum" }
		local button = UI.Button({
			id = "Well",
			label = semanticName,
			enabled = enabled,
			surface = if labelled then chrome.surface else "plain",
			padding = if labelled then chrome.padding else 0,
			gap = "s",
			align = "center",
			width = if labelled then UI.fill() else floor,
			height = if labelled then (chrome.height or floor) else floor,
			children = {
				UI.HStack({
					id = "Row",
					width = if labelled then UI.fill() else nil,
					gap = "s",
					align = "center",
					children = parts,
				}),
			},
		})
		local corners = vocabulary.cornerRadiusFor(spec.corners)
		return if corners ~= nil then UI.corners(button, corners) else button
	end

	local root: any
	if style == "inline" then
		root = Compose.withOwner(owner, function()
			local panel = panelView(false)
			local wrapped = fieldChrome.new({ UI = UI, control = "UI.ColorPicker", spec = spec }).wrap(panel, id)
			return if wrapped == panel then UI.VStack({ id = id, width = UI.fill(), children = { panel } }) else wrapped
		end)
	else
		local pop = require("./popover").build(Facet, core, {
			id = id,
			isPresented = presented,
			onPresentedChange = function(next: boolean)
				if not next then
					asked = true
				end
				requestPresented(next)
			end,
			onDismiss = function(reason: string)
				local mine = closeWhy
				closeWhy = nil
				local proposed = asked
				asked = false
				-- a draft closed any way but Apply discards; otherwise every change
				-- already committed and the close keeps it
				if mine == nil and proposed and draft then
					restore()
				end
				if spec.onDismiss ~= nil then
					spec.onDismiss(mine or reason)
				end
			end,
			trigger = well(),
			content = function()
				return panelView(true)
			end,
			edge = "bottom",
			align = "start",
			tail = false,
			env = spec.env,
		}, { tenFoot = true, hug = true })
		popoverApi = pop.api
		owner.own(function()
			pop.dispose()
		end)
		root = Compose.withOwner(owner, function()
			return chrome.wrap(pop.blueprint, id)
		end)
		if root == pop.blueprint then
			root = UI.VStack({ id = id, width = if labelled then UI.fill() else nil, children = { pop.blueprint } })
		end
		-- where the well is on screen, read live by the panel for its room
		root = contribution.attach(root, {
			bindController = function(controller: any)
				wellController = controller
			end,
			syncGeometry = function(_rectOf: any, node: any?)
				local function find(n: any): string?
					if n.id == "Well" and n.class == "Button" then
						return n.path
					end
					for _, child in n.children or {} do
						local hit = find(child)
						if hit ~= nil then
							return hit
						end
					end
					return nil
				end
				wellPath = if node ~= nil then find(node) else nil
			end,
		})
	end

	local function dump()
		local c = canon:peek()
		return {
			schema = DUMP_SCHEMA,
			id = id,
			style = style,
			value = if value:peek() ~= nil then colorValue.hex(value:peek()) else nil,
			alpha = if hasAlpha then alpha:peek() else nil,
			hsv = { h = c.h * 360, s = c.s * 100, v = c.v * 100 },
			text = valueText:peek(),
			name = semanticName:peek(),
			modes = table.clone(modes),
			mode = modeCell:peek(),
			format = formatCell:peek(),
			draft = draft,
			presented = presented:peek(),
			route = if popoverApi ~= nil then popoverApi.route:peek() else "inline",
			planePath = planePath,
			columns = columns:peek(),
			swatchPaths = table.clone(swatchPaths),
			hexError = hexError:peek(),
			diagnostics = table.clone(diagnostics),
			-- what this control's owner holds: flat across gestures, or it leaks
			owned = owner.size(),
		}
	end

	return {
		blueprint = root,
		api = {
			diagnostics = function(): { string }
				return table.clone(diagnostics)
			end,
		},
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	}
end

function color_picker.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end

return color_picker
