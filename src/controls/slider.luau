--!strict
-- Slider: a continuous (or stepped) value along a track (docs/plans/
-- parity-next.md investment 4; acceptance rows B-VAL1/B-VAL2/B-VAL3).
-- Shares the value arithmetic with Stepper through src/controls/value_model.luau,
-- so the two cannot disagree at the bounds.
--
-- NATIVE FIRST (roblox-native-audit-corrections §1): live drag acquisition is
-- `UIDragDetector`, reached through `controller.attachDragDetector`. The
-- corrections also require a fallback for targets where the detector is not
-- usable (billboard canvases until their coordinate mapping is proven), so the
-- track is a `UI.Grip` whose capture-based pointer handlers (ADR-0008) drive the
-- SAME `setFromFraction`. Both routes converge on one mutation site; neither is a
-- slider-specific recognizer.
--
-- THREE AXES (affordance matrix §A; UI-PARADIGM-001..003):
--   1. UI (layout)   — label row plus a track whose filled portion and thumb are
--                      positioned by arrange-only offsets, so a drag writes rects
--                      and never re-measures.
--   2. INPUT (reach) — pointer/touch drag or tap-to-position on the track;
--                      keyboard/gamepad use the focus-gated Adjust verb for
--                      predictable increments (the corrections warn against
--                      making a continuous thumbstick mandatory).
--   3. PARADIGM      — pointer: direct drag on the track plus tap-to-position;
--                      touch: the same drag against the enforced 44px floor;
--                      keyboard: focus ring then Adjust; gamepad: focus then
--                      Adjust, dynamically bound so a screen containing a Slider
--                      never shadows gameplay bumper keys.
--      hotSwitch     — a Slider DOES hold in-flight state (an active drag), and
--                      the decision is CANCEL: losing the pointer class mid-drag
--                      reverts to the pre-drag snapshot, so a half-finished drag
--                      never commits a value the player did not choose.
--
-- OWNERSHIP: `value` is the CALLER's settable Signal.

local controlContract = require("../class_contract")
local contribution = require("../input/contribution")
local chrome_slots = require("../tokens/chrome_slots")
-- the rung-2 (per-view override) prop normalizer. Required directly (not through the public
-- `Facet.themes` table) so the schema this control validates against is
-- literally the schema `themes.define` validates recipes against.
local themePackage = require("../themes/package")
local value_model = require("./value_model")
local specGuard = require("../spec_guard")
local rectLib = require("../rect")

local slider = {}

-- THEME METRICS, not literals (ADR-0019 §2). The track is the effective-target
-- floor (B-BTN3); the thumb, rail and readout width are the slider family's own
-- metrics. Each resolves on every solve, so a theme swap re-sizes the control
-- with no rebuild and no state loss.
local TRACK_HEIGHT = "targetSizes.minimum"
local THUMB_SIZE = "controls.slider.thumbSize"
local RAIL_HEIGHT = "controls.slider.railHeight"
local READOUT_MIN_WIDTH = "controls.slider.readoutMinWidth"
-- Label -> track gap (director review 2026-07-24). The row used the `s` step
-- every other control row uses, and it read fine only because the text
-- measurer over-reserved: a label's box was far wider than its glyphs, so the
-- slack in the box was doing the spacing. Exact text measurement removed that
-- slack, and the defect it had been hiding showed up immediately — at value 0
-- the round thumb sits at the track's left edge, so it landed against the
-- final "s" of "Brightness".
--
-- A round thumb needs more clearance than a straight edge does: the small step
-- between a glyph and a circle reads as touching. This row therefore declares
-- the next step up instead of inheriting the generic one, because the shape it
-- has to clear is its own.
local LABEL_GAP = "m"
-- the focused thumb's ring weight, as a THEME TOKEN rather than a literal 2:
-- `stroke.thickness` resolves a string against `style.strokes`, so this is the
-- one name that reaches the same number the adapter draws its own focus ring at
-- (see `focusStroke` below for why the slider draws its own at all)
local FOCUS_RING = "focusRing"

export type Spec = {
	id: string?,
	label: string?,
	value: any, -- owner-held Signal<number>
	min: number,
	max: number,
	step: number?, -- nil = continuous
	format: ((value: number) -> string)?,
	enabled: any?, -- boolean | Readable<boolean>
	tapToPosition: boolean?, -- default true
	onChange: ((value: number) -> ())?,
	onCommit: ((value: number) -> ())?,
	-- RUNG 2 OF THE CUSTOMIZATION LADDER (docs/guide/09-custom-themes.md §11).
	-- A content URI painted on THIS slider's thumb / rail instead of whatever
	-- the installed theme's `sliderThumb` / `sliderTrack` recipe says. Setting
	-- one opts that node out of theme changes — the standing opt-out rule — and
	-- leaves everything else (sizes, palette, the rest of the screen) on the
	-- theme. Painted whole, because a bare URI carries no slice geometry.
	--
	-- v2 (ADR-0020 R2): the value may also be a PER-STATE map — `{ default =
	-- "...", hover = "...", disabled = "..." }` — over exactly the states a
	-- recipe accepts. It is normalized by `themes.normalizeVariant`, the SAME
	-- function the recipe schema uses, so the prop grammar cannot fork from the
	-- theme grammar (ADR-0020 R2: one grammar, one normalizer, both rungs).
	-- Unstated states fall back to `default`.
	thumbImage: (string | { [string]: any })?,
	trackImage: (string | { [string]: any })?,
}

-- normalize a rung-2 image prop into the shape `chrome_slots.planFor` reads.
-- A bad map is an authoring error raised HERE — at the control boundary, naming
-- the prop — rather than a decoration that silently paints its default forever.
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
		error(`Facet newSlider('{id}'): {prop} — {first.message} ({first.fix})`, 0)
	end
	return { slot = slot, imageVariants = variant }
end

-- CLOSED SPEC (constitution §4). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local SLIDER_KEYS = specGuard.keySet({
	"enabled",
	"format",
	"id",
	"label",
	"max",
	"min",
	"onChange",
	"onCommit",
	"step",
	"tapToPosition",
	"thumbImage",
	"trackImage",
	"value",
})

function slider.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newSlider", spec, SLIDER_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Slider"
	local scope = core:scope("slider-" .. tostring(id))
	local value = spec.value
	if type(value) ~= "table" or (value :: any).kind ~= "signal" then
		error(
			`Facet newSlider('{id}'): \`value\` must be a SETTABLE Signal<number> the caller owns `
				.. `(a read-only Memo would pass a duck-type check and then fail on the first drag)`,
			0
		)
	end
	local model = value_model.new({ min = spec.min, max = spec.max, step = spec.step, format = spec.format })
	local tapToPosition = spec.tapToPosition ~= false
	-- RUNG-2 OVERRIDES, normalized ONCE at build: a bad per-state map names the
	-- prop here instead of quietly painting `default` in every state forever.
	local trackOverride = hintFor(id, "sliderTrack", "trackImage", spec.trackImage)
	local thumbOverride = hintFor(id, "sliderThumb", "thumbImage", spec.thumbImage)

	-- the contract's one reading of `enabled` (a one-shot read: never subscribes)
	local function isEnabled(): boolean
		return controlContract.enabledNow(spec.enabled)
	end

	-- in-flight drag state (the hot-switch subject)
	local dragging = scope:own(core:signal(false))
	local snapshot: number? = nil
	-- Track geometry, fed by the contribution's syncGeometry so the fraction math
	-- reads SOLVED rects rather than guessing.
	--
	-- A SIGNAL, not a plain upvalue (director review 2026-07-24). The fill width
	-- and thumb offset are memos over this rect, and a memo cannot see an upvalue
	-- change: the rect arrives on the first solve, AFTER the memos have already
	-- run against `nil`, so at rest the control drew no accent fill and parked
	-- its thumb at offset 0 no matter what the value was. It only looked right
	-- once something else moved the value and re-ran the memos by another route.
	-- Reading geometry non-reactively in a reactive framework means rendering a
	-- value you are not showing.
	--
	-- Value equality, not identity. syncGeometry re-feeds this on EVERY refresh,
	-- so an unchanged rect must be a no-op or both memos re-run each frame, each
	-- emits a fresh dim table, and the surface re-solves forever. Today the
	-- renderer's rectOf happens to hand back the same table until the rect
	-- actually changes, so identity would also work — this does not depend on
	-- that, because the day rectOf builds a fresh table the cost would appear as
	-- a silent per-frame re-solve in every slider rather than as a failure.
	local rectEq = rectLib.equal
	local trackRect = scope:own(core:signal(nil, rectEq))
	-- the THUMB's solved rect, for the same reason. The offset math needs the
	-- thumb's width to keep it inside the track, and that width is now a theme
	-- metric — reading it from the solve rather than from a constant means a
	-- theme with a fatter thumb parks it correctly with no arithmetic here.
	local thumbRect = scope:own(core:signal(nil, rectEq))

	-- the ONE mutation site every route converges on
	local function apply(next_: number): boolean
		if not isEnabled() then
			return false
		end
		local resolved = model.quantize(next_)
		if resolved == value:get() then
			return false
		end
		value:set(resolved)
		if spec.onChange ~= nil then
			spec.onChange(resolved)
		end
		return true
	end

	local function setFromX(x: number): boolean
		local rect = trackRect:get()
		if rect == nil or rect.w <= 0 then
			return false
		end
		return apply(model.fromFraction((x - rect.x) / rect.w))
	end

	local function adjust(direction: number): boolean
		return apply(model.stepped(value:get(), direction))
	end

	local function beginDrag(x: number): boolean
		if not isEnabled() then
			return false
		end
		snapshot = value:get()
		dragging:set(true)
		if tapToPosition then
			setFromX(x)
		end
		return true
	end

	local function endDrag()
		if not dragging:get() then
			return
		end
		dragging:set(false)
		snapshot = nil
		if spec.onCommit ~= nil then
			spec.onCommit(value:get())
		end
	end

	-- hot-switch CANCEL (UI-PARADIGM-002): the pointer class disappearing mid-drag
	-- must not commit a half-chosen value. Revert to the pre-drag snapshot.
	local function cancelDrag()
		if not dragging:get() then
			return
		end
		if snapshot ~= nil then
			value:set(snapshot)
			if spec.onChange ~= nil then
				spec.onChange(snapshot)
			end
		end
		dragging:set(false)
		snapshot = nil
	end

	-- Grip is opt-in focusable; bind that to `enabled` so a disabled Slider is
	-- skipped by navigation exactly as a disabled Button is
	-- the same reading, but SUBSCRIBED: a bound `enabled` that flips must move the
	-- track in and out of focus order without a remount
	local focusableTrack = scope:own(core:memo(function(use)
		return controlContract.enabledIn(use, spec.enabled)
	end))

	-- THE SLIDER'S OWN FOCUSED STATE (director playtest 2026-08-03). The track
	-- declares `focusVisual = "none"`, so nothing paints a focused treatment unless
	-- this control does. The fact comes from the screen's focus graph through the
	-- contribution's `bindFocusGraph` — the canonical route (constitution §13); a
	-- consumer never hands a control the graph. Absent (no presenter, a headless
	-- mount), `focused` simply stays false and the slider paints its resting look.
	local focusGraph: any = nil
	-- MAY WE PAINT IT? Handed over with the graph by the presenter (round 6). The
	-- graph answers "does this control hold focus"; this answers "is a focused
	-- treatment legal on this surface right now" — hidden after a pointer move, and
	-- absent entirely while the surface is passive and owns no input. Without it the
	-- thumb kept its ring after the player clicked the world and the responder had
	-- already handed the keyboard back. nil (no presenter, a headless mount) reads
	-- as permitted, so nothing that never had a responder changes.
	local focusPaintAllowed: any = nil
	-- DECLARED HERE, ABOVE ITS READER. `syncTrackFocus` closes over `trackPath`,
	-- and a `local` written further down is not the same variable — the closure
	-- would resolve a nil GLOBAL and the focus fact would never become true. Same
	-- trap `newTextInput`'s `idPattern` hit in this stage; it is silent both times,
	-- because nothing errors, the answer is just permanently false.
	local trackPath: string? = nil
	local trackFocused = scope:own(core:signal(false))
	local function syncTrackFocus()
		local path = trackPath
		local holdsFocus = focusGraph ~= nil and path ~= nil and focusGraph.focused:get() == path
		local mayPaint = focusPaintAllowed == nil or focusPaintAllowed:get() ~= false
		trackFocused:set(holdsFocus and mayPaint)
	end
	-- the ring, as a pulsing PROP rather than a Signal buried inside normalized
	-- data (the idiom UI.strokeData documents). `accent` is a role, so every theme
	-- package answers it in its own palette instead of a literal colour landing on
	-- a parchment thumb.
	--
	-- IT MUST BE VISIBLE, WHICH TOOK A SECOND ROUND (director playtest
	-- 2026-08-03, round 2: "i don't see any visual affordance when the slider's
	-- focused"). The first version passed `{ color = "accent" }` and nothing else,
	-- and `normalizeStroke`'s unstated defaults are the theme's HAIRLINE —
	-- `strokes.hairline` (1px) and `extra.hairlineOpacity` (0.92). So the ring was
	-- painting correctly and was an accent-tinted hairline at 8% visibility,
	-- stacked under the thumb's own resting hairline. Measured live on the focused
	-- thumb: two UIStrokes, both `thick=1 trans=0.92`.
	--
	-- The adapter's ring, which this stands in for, is `Thickness =
	-- extra.focusRingThickness` at `Transparency = 0` (screen_target). So both are
	-- named here rather than defaulted: a focus ring is not a hairline, and every
	-- value a focus treatment depends on has to be stated by the thing claiming to
	-- draw one.
	local focusStroke = scope:own(core:memo(function(use)
		if not use(trackFocused) then
			return nil
		end
		return Facet.UI.strokeData({ color = "accent", thickness = FOCUS_RING, transparency = 0 })
	end))

	-- both read the track through `use`, so a solve that resizes the track moves
	-- the fill and the thumb with it — no value change required
	local fillWidth = scope:own(core:memo(function(use)
		local f = model.fraction(use(value))
		local rect = use(trackRect)
		local w = if rect ~= nil then rect.w else 0
		return { type = "fixed", px = math.floor(w * f + 0.5) }
	end))
	local thumbOffset = scope:own(core:memo(function(use)
		local f = model.fraction(use(value))
		local rect = use(trackRect)
		local thumb = use(thumbRect)
		local w = if rect ~= nil then rect.w else 0
		local thumbW = if thumb ~= nil then thumb.w else 0
		return math.floor((w - thumbW) * f + 0.5)
	end))
	local readout = scope:own(core:memo(function(use)
		return model.format(use(value))
	end))
	local semantic = scope:own(core:memo(function(use)
		return model.semanticText(use(value))
	end))

	local root = UI.HStack({
		id = id,
		gap = LABEL_GAP,
		align = "center",
		-- a slider row is full-width by nature, and it MUST be: a fill-width track
		-- inside a content-sized parent would resolve to zero, which is the classic
		-- content-sizing trap (the track then has no space to drag along)
		width = { type = "fill", weight = 1 },
		children = {
			UI.Text({ id = "Label", text = spec.label or "", textSize = "body" }),
			-- the TRACK is a Grip: a non-button pointer zone with capture-based
			-- routing, opt-in focusable so keyboard and gamepad reach it. The
			-- renderer wires its pointer handlers automatically — that is the
			-- corrections-mandated fallback, live with no extra work.
			-- the visible groove sits BEHIND a transparent Grip: the Grip is a leaf
			-- (it is a pointer zone, not a container), so the visuals are siblings in
			-- a ZStack with the Grip last, i.e. on top. Found live: without the
			-- groove the control rendered as an invisible zone with only its readout.
			UI.ZStack({
				id = "TrackHost",
				width = { type = "fill", weight = 1 },
				height = { type = "fixed", px = TRACK_HEIGHT },
				children = {
					UI.Anchor({
						id = "Groove",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							-- THE SLOT HINT (ADR-0019 fix round). Nothing generic can
							-- infer "this Box is a slider rail" — `surface = "control"`
							-- would have made it a plain control skin, i.e. a button
							-- plate stretched into a groove. The control therefore
							-- DECLARES its slot on the blueprint's internal meta
							-- channel, and `chrome_slots.classify` takes the hint over
							-- everything else. A flat theme is unaffected: with no
							-- sliderTrack recipe the hint plans nothing and the
							-- painted groove below is exactly what it always was.
							chrome_slots.attachHint(
								UI.Box({
									id = "Rail",
									anchor = "left",
									width = { type = "fill", weight = 1 },
									height = { type = "fixed", px = RAIL_HEIGHT },
								}),
								trackOverride
							),
							-- the FILL is not a decoration surface at all. It declares
							-- `surface = "accent"`, which classifies as `control`, so
							-- an ornate package used to paint a stretched BUTTON plate
							-- over the filled portion of the bar. Nothing generic can
							-- tell that apart from a real accent button — only this
							-- control can, so it says so.
							chrome_slots.attachHint(
								UI.Box({
									id = "Fill",
									surface = "accent",
									anchor = "left",
									width = fillWidth,
									height = { type = "fixed", px = RAIL_HEIGHT },
								}),
								{ slot = chrome_slots.NO_SLOT }
							),
							-- NO PUBLIC `surface` ON EITHER (director follow-up
							-- 2026-07-25). The thumb used to declare
							-- `surface = "raised"` purely to get a fill, and that
							-- subscribed it to the whole PANEL treatment — Glossy
							-- Mobile's panel gradient carries alpha, so the thumb
							-- went translucent and the accent fill behind it read
							-- straight through it. A thumb is not a panel and a rail
							-- is not a button. The slot hint is now their whole
							-- paint identity: the package's `Slot — <slot>` rules
							-- paint them SOLID and no gradient can reach them.
							-- THE RING GOES ON THE VALUE INDICATOR (director playtest
							-- 2026-08-03). Focus used to land on the full-width Track
							-- grip, so the focus ring drew a box around the whole
							-- slider and told the player nothing about where the value
							-- is. The thumb IS the value, so it is what takes focus and
							-- what the ring frames — and it is a themed chrome slot, so
							-- every package's own focus treatment applies to it rather
							-- than to a rail-shaped rectangle. The Track keeps the
							-- pointer story (press anywhere on it to jump the value);
							-- it is simply no longer the focus stop.
							chrome_slots.attachHint(
								UI.Box({
									id = "Thumb",
									anchor = "left",
									offsetX = thumbOffset,
									width = { type = "fixed", px = THUMB_SIZE },
									height = { type = "fixed", px = THUMB_SIZE },
									-- the focused treatment, on the thing that IS the
									-- value. A stroke rather than a fill or a size
									-- change: the thumb keeps its package's own shape
									-- and paint, and the ring reads against every one
									-- of them because it uses the theme's focus role
									-- rather than a literal colour.
									stroke = focusStroke,
								}),
								thumbOverride
							),
						},
					}),
					UI.Grip({
						id = "Track",
						-- a disabled Slider must leave focus order, not merely refuse the
						-- verb (verifier finding V13): Grip has no `enabled` prop, so its
						-- opt-IN focusability carries the control's enabled state
						focusable = focusableTrack,
						-- THE SLIDER PAINTS ITS OWN FOCUSED STATE (director playtest
						-- 2026-08-03). The adapter's Grip treatment fills the focused
						-- grip with accent, which is right for a thin resize handle and
						-- wrong here: this grip is the full width of the control, so
						-- filling it paints a solid bar over the value the player is
						-- reading. The focused treatment belongs on the THUMB, which is
						-- where the value is — see `thumbFocused` below.
						focusVisual = "none",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						onPointerDown = function(_path: string, pos: any)
							return beginDrag(pos.x)
						end,
						onPointerMove = function(_path: string, pos: any)
							if dragging:get() then
								setFromX(pos.x)
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
			}),
			UI.Text({
				id = "Value",
				text = readout,
				textSize = "body",
				width = { type = "minMax", min = READOUT_MIN_WIDTH },
			}),
		},
	})

	local rootPath: string? = nil
	local thumbPath: string? = nil
	local detachDetector: (() -> ())? = nil
	local nativeDetector = false
	local boundController: any = nil

	-- native drag acquisition (corrections §1). The presenter binds the controller
	-- BEFORE the first geometry feed, so the track path is not known yet — attach
	-- lazily as soon as both are available, and stay idempotent because a
	-- structural sync re-feeds geometry.
	local function tryAttachDetector()
		if detachDetector ~= nil or boundController == nil or trackPath == nil then
			return
		end
		if boundController.attachDragDetector == nil then
			return -- adapter without the seam: the Grip capture path is the fallback
		end
		detachDetector = boundController.attachDragDetector(trackPath, {
			onStart = function(pos: any)
				beginDrag(if pos ~= nil then pos.x else 0)
			end,
			onContinue = function(pos: any)
				if pos ~= nil then
					setFromX(pos.x)
				end
			end,
			onEnd = function()
				endDrag()
			end,
		})
		nativeDetector = detachDetector ~= nil
		if detachDetector ~= nil then
			scope:own(detachDetector)
		end
	end

	local built = contribution.attach(root, {
		-- SOLVED track geometry: the fraction math must read the real rect, not a
		-- remembered one (a resize or an orientation flip changes it)
		syncGeometry = function(rectOf: (string) -> any, rootNode: any?)
			-- resolve the TRACK by identity, not by string arithmetic: the mounted
			-- path depends on where the consumer placed this control, so guessing it
			-- is exactly the kind of assumption that breaks silently
			if rootNode ~= nil then
				rootPath = rootNode.path
				if trackPath == nil or thumbPath == nil then
					local function find(node: any)
						if node.id == "Track" and node.class == "Grip" then
							trackPath = node.path
						elseif node.id == "Thumb" then
							thumbPath = node.path
						end
						for _, child in node.children or {} do
							find(child)
						end
					end
					find(rootNode)
				end
			end
			if trackPath ~= nil then
				trackRect:set(rectOf(trackPath))
				tryAttachDetector()
				-- the path is LEARNED here, so the focus fact cannot be resolved
				-- until it is: re-ask now that we know what to compare against
				syncTrackFocus()
			end
			if thumbPath ~= nil then
				thumbRect:set(rectOf(thumbPath))
			end
		end,
		-- native drag acquisition where available (corrections §1), falling back to
		-- the Grip capture path above. Both call the same setFromX.
		bindController = function(controller: any)
			boundController = controller
			tryAttachDetector()
		end,
		-- the canonical route to the screen's focus graph (constitution §13): a
		-- control is handed it by the PRESENTER, never by its consumer
		bindFocusGraph = function(graph: any, paintAllowed: any)
			focusGraph = graph
			focusPaintAllowed = paintAllowed
			scope:own(core:observe(graph.focused, syncTrackFocus))
			-- ...and on the PERMISSION flipping under a standing focus: resigning
			-- moves no focus, so the focused observer never fires and the ring would
			-- sit there until something else happened to move it
			if paintAllowed ~= nil then
				scope:own(core:observe(paintAllowed, syncTrackFocus))
			end
			syncTrackFocus()
		end,
		onStart = function(pos: any)
			beginDrag(if pos ~= nil then pos.x else 0)
		end,
		onContinue = function(pos: any)
			if pos ~= nil then
				setFromX(pos.x)
			end
		end,

		-- focus-gated Adjust: keyboard/gamepad get predictable increments rather
		-- than a mandatory continuous thumbstick (corrections §1)
		-- The presenter hands this the control's OWN mounted root (the same node
		-- `focusGroups` gets). The track is still found by WALKING rather than by
		-- assuming a path shape, because where the consumer placed this control
		-- decides the mounted path and guessing it is what breaks silently.
		adjustTargets = function(ownRoot: any): { [string]: boolean }
			if trackPath == nil then
				local function walk(node: any)
					if node.id == "Track" and node.class == "Grip" then
						trackPath = node.path
						return true
					end
					for _, child in node.children or {} do
						if walk(child) then
							return true
						end
					end
					return false
				end
				walk(ownRoot)
			end
			return if trackPath ~= nil then { [trackPath] = true } else {}
		end,
		-- the value runs LEFT to RIGHT, so Left/Right ARE this control (roadmap
		-- Step 8): while the track holds focus those arrows decrement/increment and
		-- Up/Down keep navigating away from the slider.
		adjustAxis = "horizontal",
		handleAdjust = function(_path: string, direction: number): boolean
			return adjust(direction)
		end,
	})

	local api = {}
	api.blueprint = built
	api.model = model
	api.semanticText = semantic
	api.fillWidth = fillWidth
	api.thumbOffset = thumbOffset

	-- the hot-switch entry point a live class flip drives (UI-PARADIGM-002)
	function api.onInteractionClassLost(class: string)
		if class == "pointer" or class == "touch" then
			cancelDrag()
		end
	end

	function api.dump()
		local v = value:get()
		return {
			schema = "facet-slider-dump/1",
			id = id,
			value = v,
			formatted = model.format(v),
			semanticText = model.semanticText(v),
			fraction = model.fraction(v),
			min = model.min,
			max = model.max,
			step = model.step,
			dragging = dragging:get(),
			nativeDetector = nativeDetector,
			tapToPosition = tapToPosition,
			trackWidth = if trackRect:get() ~= nil then trackRect:get().w else nil,
			rootPath = rootPath,
			trackPath = trackPath,
			thumbPath = thumbPath,
			-- which rung of the customization ladder is painting this control
			-- ("theme" = the package's sliderTrack/sliderThumb recipes; "view" =
			-- a local thumbImage/trackImage, which opts those nodes out of theme
			-- changes)
			skinRung = if spec.thumbImage ~= nil or spec.trackImage ~= nil then "view" else "theme",
			thumbImage = spec.thumbImage,
			trackImage = spec.trackImage,
		}
	end

	function api.dispose()
		scope:dispose()
	end

	return api
end

return slider
