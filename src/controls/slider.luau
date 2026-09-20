--!strict
-- A shared value model drives pointer dragging, native drag detectors, and
-- keyboard/gamepad adjustment. The caller owns the value cell.
local Compose = require("../vendor/compose/core")
local read = require("../selection_model").read

local controlContract = require("../class_contract")
local contribution = require("../input/contribution")
local chrome_slots = require("../tokens/chrome_slots")
local themePackage = require("../themes/package")
local value_model = require("./value_model")
local specGuard = require("../spec_guard")
local rectLib = require("../rect")

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

local specTypes = require("../spec_types/slider")
type NumberCell = specTypes.NumberCell
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
	specGuard.assertKnownKeys("UI.Slider", spec, SLIDER_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Slider"
	local value = spec.value
	if not (Compose.isReadable(value) and type(value.set) == "function") then
		error(
			`Facet UI.Slider('{id}'): \`value\` must be a writable Compose cell holding a number, owned by the caller `
				.. `(a read-only formula would pass a duck-type check and then fail on the first drag)`,
			0
		)
	end
	local model = value_model.new({ min = spec.min, max = spec.max, step = spec.step, format = spec.format })
	local tapToPosition = spec.tapToPosition ~= false
	local trackOverride = hintFor(id, "sliderTrack", "trackImage", spec.trackImage)
	local thumbOverride = hintFor(id, "sliderThumb", "thumbImage", spec.thumbImage)

	local disposed = false
	local focusOwner

	local function isEnabled(): boolean
		return not disposed and controlContract.enabledNow(spec.enabled)
	end

	local dragging = Compose.cell(false)
	local snapshot: number? = nil
	-- Solved geometry must be reactive, but equal rectangles must not schedule work.
	local rectEq = rectLib.equal
	local trackRect = Compose.cell(nil, rectEq)
	local thumbRect = Compose.cell(nil, rectEq)

	local function apply(next_: number): boolean
		if not isEnabled() then
			return false
		end
		local resolved = model.quantize(next_)
		if resolved == read(value) then
			return false
		end
		value:set(resolved)
		if spec.onChange ~= nil then
			spec.onChange(resolved)
		end
		return true
	end

	local function setFromX(x: number): boolean
		local rect = trackRect:peek()
		if rect == nil or rect.w <= 0 then
			return false
		end
		return apply(model.fromFraction((x - rect.x) / rect.w))
	end

	local function adjust(direction: number): boolean
		return apply(model.stepped(read(value), direction))
	end

	local function beginDrag(x: number): boolean
		if not isEnabled() then
			return false
		end
		snapshot = read(value)
		dragging:set(true)
		if tapToPosition then
			setFromX(x)
		end
		return true
	end

	local function endDrag()
		if not dragging:peek() then
			return
		end
		dragging:set(false)
		snapshot = nil
		if spec.onCommit ~= nil then
			spec.onCommit(read(value))
		end
	end

	local function cancelDrag()
		if not dragging:peek() then
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

	local focusableTrack = Compose.formula(function(use)
		return controlContract.enabledIn(use, spec.enabled)
	end)

	local focusGraph: any = nil
	local focusPaintAllowed: any = nil
	local trackPath: string? = nil
	local trackFocused = Compose.cell(false)
	local function syncTrackFocus()
		local path = trackPath
		local holdsFocus = focusGraph ~= nil and path ~= nil and read(focusGraph.focused) == path
		local mayPaint = focusPaintAllowed == nil or read(focusPaintAllowed) ~= false
		trackFocused:set(holdsFocus and mayPaint)
	end
	-- The Grip suppresses the default focus visual; the thumb paints this ring.
	local focusStroke = Compose.formula(function(use)
		if not use(trackFocused) then
			return nil
		end
		return Facet.UI.strokeData({ color = "accent", thickness = FOCUS_RING, transparency = 0 })
	end)

	-- Both the value and solved geometry determine the resting fill and thumb position.
	local fillWidth = Compose.formula(function(use)
		local f = model.fraction(read(value, use))
		local rect = use(trackRect)
		local w = if rect ~= nil then rect.w else 0
		return { type = "fixed", px = math.floor(w * f + 0.5) }
	end)
	local thumbOffset = Compose.formula(function(use)
		local f = model.fraction(read(value, use))
		local rect = use(trackRect)
		local thumb = use(thumbRect)
		local w = if rect ~= nil then rect.w else 0
		local thumbW = if thumb ~= nil then thumb.w else 0
		return math.floor((w - thumbW) * f + 0.5)
	end)
	local readout = Compose.formula(function(use)
		return model.format(read(value, use))
	end)
	local semantic = Compose.formula(function(use)
		return model.semanticText(read(value, use))
	end)

	local root = UI.HStack({
		id = id,
		gap = LABEL_GAP,
		align = "center",
		width = { type = "fill", weight = 1 },
		children = {
			UI.Text({ id = "Label", text = spec.label or "", textSize = "body" }),
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
							chrome_slots.attachHint(
								UI.Box({
									id = "Rail",
									anchor = "left",
									width = { type = "fill", weight = 1 },
									height = { type = "fixed", px = RAIL_HEIGHT },
								}),
								trackOverride
							),
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
							chrome_slots.attachHint(
								UI.Box({
									id = "Thumb",
									anchor = "left",
									offsetX = thumbOffset,
									width = { type = "fixed", px = THUMB_SIZE },
									height = { type = "fixed", px = THUMB_SIZE },
									stroke = if spec.row then nil else focusStroke,
								}),
								thumbOverride
							),
						},
					}),
					UI.Grip({
						id = "Track",
						focusable = focusableTrack,
						focusVisual = "none",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						onPointerDown = function(_path: string, pos: any)
							return beginDrag(pos.x)
						end,
						onPointerMove = function(_path: string, pos: any)
							if dragging:peek() then
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

	if spec.row then
		assert(spec.row.value == nil, "UI.Slider.row: value is supplied by the slider")
		local header = menuRecipe.semantic(UI, spec.label, spec.row, readout)
		table.insert(header, root.children[2])
		root = UI.corners(
			UI.VStack({
				id = id,
				width = UI.fill(),
				gap = "s",
				padding = "m",
				surface = "control",
				stroke = focusStroke,
				children = header,
			}),
			"control"
		)
	end

	local rootPath: string? = nil
	local thumbPath: string? = nil
	local detachDetector: (() -> ())? = nil
	local nativeDetector = false
	local boundController: any = nil

	-- Attach once after both the controller and solved track path are available.
	-- Targets without native drag support use the same handlers through Grip.
	local function tryAttachDetector()
		if disposed or detachDetector ~= nil or boundController == nil or trackPath == nil then
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
	end

	local built = contribution.attach(root, {
		syncGeometry = function(rectOf: (string) -> any, rootNode: any?)
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
				syncTrackFocus()
			end
			if thumbPath ~= nil then
				thumbRect:set(rectOf(thumbPath))
			end
		end,
		bindController = function(controller: any)
			boundController = controller
			tryAttachDetector()
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
		onStart = function(pos: any)
			beginDrag(if pos ~= nil then pos.x else 0)
		end,
		onContinue = function(pos: any)
			if pos ~= nil then
				setFromX(pos.x)
			end
		end,

		adjustRepeat = true,
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

	function api.onInteractionClassLost(class: string)
		if class == "pointer" or class == "touch" then
			cancelDrag()
		end
	end

	function api.dump()
		local v = read(value)
		return {
			schema = "facet-slider-dump/1",
			id = id,
			value = v,
			formatted = model.format(v),
			semanticText = model.semanticText(v),
			fraction = model.fraction(v),
			min = model.min,
			max = model.max,
			step = model.currentStep(),
			dragging = dragging:peek(),
			nativeDetector = nativeDetector,
			tapToPosition = tapToPosition,
			trackWidth = if trackRect:peek() ~= nil then trackRect:peek().w else nil,
			rootPath = rootPath,
			trackPath = trackPath,
			thumbPath = thumbPath,
			skinRung = if spec.thumbImage ~= nil or spec.trackImage ~= nil then "view" else "theme",
			thumbImage = spec.thumbImage,
			trackImage = spec.trackImage,
		}
	end

	function api.dispose()
		if disposed then
			return
		end
		disposed = true
		if detachDetector then
			detachDetector()
			detachDetector = nil
		end
		if focusOwner then
			focusOwner.dispose()
			focusOwner = nil
		end
		focusableTrack:dispose()
		focusStroke:dispose()
		fillWidth:dispose()
		thumbOffset:dispose()
		readout:dispose()
		semantic:dispose()
	end

	return api
end

return slider
