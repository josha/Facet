--!strict
-- Property rules shared by immutable descriptions and the native Compose host.
local policy = require("./motion/policy")
local specGuard = require("./spec_guard")
local schema = require("./blueprint_schema")
local richText = require("./layout/rich_text")
local isFinite = require("./num").isFinite
local properties = {}
local requiredBySchema = {}
properties.direct = table.freeze({
	Screen = true,
	Button = true,
	VStack = true,
	ZStack = true,
	HStack = true,
	Spacer = true,
	Box = true,
	Anchor = true,
	Grid = true,
	GridRow = true,
	Text = true,
	Image = true,
	Path = true,
	Foreign = true,
	Stage = true,
})
function properties.assertCircleSquare(className: string, props: { [string]: any })
	if props.shape ~= "circle" then
		return
	end
	if props.width ~= nil and props.height ~= nil then
		error(
			`Facet UI.{className}: shape = "circle" takes at most ONE of \`width\` / \`height\` — the solver `
				.. `enforces the 1:1 square, so the other axis follows and the author never does the math. `
				.. `Fix: drop one of them (or drop both to size the disc from the control metric).`,
			0
		)
	end
end

-- `bound` names the properties a readable drives: what a bound value holds at
-- mount implies nothing about a construction-only property.
function properties.normalize(class: string, props: any, known: any, bound: { [string]: any }?)
	if props.rich == true and type(props.text) == "string" then
		props.text = richText.normalizeFontSizes(props.text)
	end
	if props.animation ~= nil then
		local ok, why = policy.check(props.animation)
		assert(ok, `Facet UI.{class}.animation: {why or "invalid policy"}`)
		for key in props.animation do
			assert(key == "layout" or known[key], `Facet UI.{class}: cannot animate unsupported property '{key}'`)
		end
		props.animation = table.freeze(table.clone(props.animation))
	end
	local required = requiredBySchema[known]
	if not required then
		required = {}
		for name, definition in known do
			if definition.required then
				table.insert(required, name)
			end
		end
		requiredBySchema[known] = required
	end
	for _, name in required do
		if props[name] == nil then
			error(`Facet UI.{class}.{name} is required ({known[name].doc})`, 0)
		end
	end
	properties.assertCombinations(class, props, bound)
	if
		props.overflow == "clip"
		and props.clipChildren == nil
		and known.clipChildren ~= nil
		and not (bound and bound.overflow ~= nil)
	then
		props.clipChildren = true
	end
end

local EXTENT_METRIC = { types = { "metric" } }
local EXTENT_KEYS = specGuard.keySet({ "width", "height" })
--[[ THE ONE AUTHORED TABLE A SCROLL HOST CARRIES, and it fails SILENTLY without
	this in three different ways: a typo'd axis name resolves to "no axis given",
	which is exactly the derived canvas the key exists to override; an unresolvable
	metric name resolves to nil and does the same; and an axis this host cannot
	SCROLL is clamped back to the window by the live adapter while a headless one
	keeps it, which is the live/headless divergence two targets exist to prevent. ]]
local function assertScrollExtent(props: { [string]: any }, bound: any)
	local extent = props.extent
	if extent == nil then
		return
	end
	specGuard.assertKnownKeys("UI.ScrollView.extent", extent, EXTENT_KEYS, "extent")
	assert(
		extent.width ~= nil or extent.height ~= nil,
		"Facet UI.ScrollView: `extent` must name at least one axis ({ width = … } and/or { height = … }); "
			.. "an empty table states nothing and the derived canvas already covers both"
	)
	for _, axis in { "width", "height" } do
		local v = extent[axis]
		if v == nil then
			continue
		end
		local valid = if type(v) == "string"
			then schema.checkValue(EXTENT_METRIC :: any, v) and string.sub(v, 1, 1) ~= "-"
			else isFinite(v) and v > 0
		assert(
			valid,
			`Facet UI.ScrollView: extent.{axis} must be positive finite pixels or a known, non-negated theme metric (got {tostring(
				v
			)})`
		)
	end
	--[[ THE AXIS HAS TO BE THE STATIC WORD, for the same reason a tile mode does:
		this pairing is decided at construction, and a bound axis has no value here.

		ASKED OF THE PROP, NOT OF A DERIVED WORD. Defaulting an absent-or-bound axis
		to `"y"` made a BOUND axis indistinguishable from an authored one, so the
		refusal below never ran for it and the message named a value the author had
		not written — while a binding that resolved to `"x"` diverged live exactly
		as the cross-axis form this whole check exists to refuse. ]]
	if (bound and bound.axis ~= nil) or (props.axis ~= nil and type(props.axis) ~= "string") then
		error(
			"Facet UI.ScrollView: `extent` needs a static `axis` to know which axes this host can scroll; "
				.. "a bound axis has no value at construction. Fix: author the axis, or drop `extent`.",
			0
		)
	end
	local axis = if type(props.axis) == "string" then props.axis else "y"
	local function refuse(key: string, want: string)
		if extent[key] ~= nil then
			error(
				`Facet UI.ScrollView: extent.{key} needs an axis this host scrolls — axis = "{axis}" cannot `
					.. `move on it, so the adapter clamps the canvas back to the window and the declaration `
					.. `does nothing. Fix: axis = "{want}" or "xy", or drop extent.{key}.`,
				0
			)
		end
	end
	if axis == "y" then
		refuse("width", "x")
	elseif axis == "x" then
		refuse("height", "y")
	end
end
--[[ MIDDLE TRUNCATION AND MARKUP ARE THE ONE ILLEGAL PAIR. Middle truncation
	cuts a string in half and joins the halves round an ellipsis; doing that to
	markup would cut a tag, and a cut tag is not markup — the engine would draw the
	remains as text or drop a whole span. The displayed form could be cut instead,
	but then the node would paint a string the author never wrote and the escape
	back to the whole value (`disclose`) would hand back a different one again.
	Refused at construction, with the two ways out named. ]]
local function assertTruncate(props: { [string]: any })
	if props.truncate ~= "middle" then
		return
	end
	if props.rich == true then
		error(
			'Facet UI.Text: truncate = "middle" and rich = true cannot both be set — a middle cut would '
				.. "fall inside a tag. Fix: keep the markup and take the engine's end ellipsis "
				.. '(truncate = "end"), or drop `rich` and middle-truncate the plain string.',
			0
		)
	end
	--[[ ...AND A MIDDLE CUT IS ONE LINE BY DEFINITION. The head-plus-tail form is
		a SINGLE line — that is the whole point, the value fits across rather than
		down — so a label that also asks for a taller box reserves lines nothing will
		ever fill and loses far more of the value than the engine's own end ellipsis
		would. A METRIC NAME resolves per solve and cannot be read here, so this
		refuses the authored number it can see and leaves the name to the ladder. ]]
	local lines = props.lineLimit
	if type(lines) == "number" and lines ~= 1 then
		error(
			`Facet UI.Text: truncate = "middle" needs lineLimit = 1 (got {lines}) — a head-plus-ellipsis-plus-tail `
				.. "form is one line by definition, so the extra lines reserve a box nothing fills. Fix: "
				.. 'lineLimit = 1, or take the engine\'s end ellipsis (truncate = "end") on a wrapping label.',
			0
		)
	end
end
--[[ THE TWO GEOMETRY KEYS AND THEIR MODES ARE ONE DECLARATION, checked both
	ways. A `tileSize` with no tile mode paints nothing and reads as a working
	line; a tile mode with no `tileSize` takes the engine's default of one repeat
	across the whole box, which is indistinguishable from `stretch` — both are the
	silent no-op the closed-key rule exists to refuse. The mode must therefore be
	the STATIC word, which is also why the two are construction-only: a bound
	`scaleMode` has no value at construction to pair a geometry key with. ]]
local TILE_SIZE_KEYS = specGuard.keySet({ "width", "height" })
local SLICE_CENTER_KEYS = specGuard.keySet({ "x0", "y0", "x1", "y1" })
local SLICE_CORNERS = { "x0", "y0", "x1", "y1" }
local function assertImageScale(props: { [string]: any }, bound: any)
	local mode = if not (bound and bound.scaleMode ~= nil) and type(props.scaleMode) == "string"
		then props.scaleMode
		else nil
	local function pair(key: string, word: string)
		if props[key] ~= nil and mode ~= word then
			local got = if props.scaleMode == nil then "no scaleMode" else `scaleMode = {tostring(props.scaleMode)}`
			error(
				`Facet UI.Image: \`{key}\` is only meaningful with the static scaleMode = "{word}" ({got}). `
					.. `Fix: author scaleMode = "{word}" beside it, or drop \`{key}\`.`,
				0
			)
		end
		if mode == word and props[key] == nil then
			error(
				`Facet UI.Image: scaleMode = "{word}" needs its geometry — declare \`{key}\`. Without it the `
					.. "engine falls back to one repeat across the whole box, which is `stretch` wearing "
					.. "another name.",
				0
			)
		end
	end
	pair("tileSize", "tile")
	pair("sliceCenter", "slice")
	local tile = props.tileSize
	if tile ~= nil then
		specGuard.assertKnownKeys("UI.Image.tileSize", tile, TILE_SIZE_KEYS, "tileSize")
		--[[ WHOLE PIXELS, GREATER THAN ZERO. `UDim.Offset` is an INTEGER (measured
			2026-08-29), so `UDim2.fromOffset(24.5, …)` tiles at 24 and the author's
			number quietly stops being the author's number; a zero is not a tile size
			at all. Refused where it is written rather than truncated where it is
			applied. ]]
		for _, axis in { "width", "height" } do
			local v = tile[axis]
			assert(
				isFinite(v) and v > 0 and v % 1 == 0,
				`Facet UI.Image: tileSize.{axis} must be a whole number of pixels greater than zero (got {tostring(v)}) `
					.. "— the engine's tile offset is an integer and truncates a fraction silently"
			)
		end
	end
	local centre = props.sliceCenter
	if centre ~= nil then
		specGuard.assertKnownKeys("UI.Image.sliceCenter", centre, SLICE_CENTER_KEYS, "sliceCenter")
		for _, corner in SLICE_CORNERS do
			local v = centre[corner]
			assert(
				isFinite(v) and v >= 0,
				`Facet UI.Image: sliceCenter must be \{ x0, y0, x1, y1 } in SOURCE pixels — \`{corner}\` is missing, `
					.. `not a number, or negative (got {tostring(v)})`
			)
		end
		-- a far edge at or before its near edge is an EMPTY centre: the picture
		-- would have no stretchable middle, which is a nine-slice that does nothing
		assert(
			centre.x1 > centre.x0 and centre.y1 > centre.y0,
			"Facet UI.Image: sliceCenter is the stretchable centre RECTANGLE, so it needs x1 > x0 and "
				.. "y1 > y0 (a 64x64 source with an 8px border is { x0 = 8, y0 = 8, x1 = 56, y1 = 56 }) — "
				.. "these are rectangle edges, never insets"
		)
	end
	local sliceScale = props.sliceScale
	if sliceScale ~= nil then
		assert(
			mode == "slice",
			'Facet UI.Image: `sliceScale` is only meaningful with the static scaleMode = "slice". '
				.. "Fix: declare the mode and its `sliceCenter` beside it, or drop `sliceScale`."
		)
		assert(
			isFinite(sliceScale) and sliceScale > 0,
			`Facet UI.Image: sliceScale must be a finite number greater than zero (got {tostring(sliceScale)}); `
				.. "it is how much the border run is scaled by, and the engine's default is 1"
		)
	end
end

-- A bound mode cannot opt into geometry that is fixed at construction.
function properties.assertBoundValue(class: string, key: string, definition: any, value: any)
	if definition.staticOnly and table.find(definition.staticOnly, value) then
		error(
			`Facet UI.{class}.{key}: '{value}' needs a construction-only companion key; author a static mode and its geometry, or use a reactive fit/fill/crop/stretch mode.`,
			0
		)
	end
end

--[[ THE CROSS-PROPERTY REFUSALS, WHICH ARE CONSTRUCTION ERRORS.

	Each one reads TWO properties, so no per-property schema check can see it, and
	each one is a refusal rather than a normalization — nothing is written, so it
	is idempotent and safe to ask twice.

	IT IS ASKED AT CONSTRUCTION, NOT ONLY AT MOUNT. A Compose host assigns
	properties one at a time, so the pair only exists once the node is built —
	which is `render/compose_scene`'s own constructor wrapper, the first moment
	both values are on the node. Asking only at `insertChild` meant a stack
	authored wrong and never parented (a fixture, a detached recipe, an authoring
	mistake caught before the node reaches a tree) was accepted in silence; asking the whole of `normalize` there instead
	would have run the WRITING half — the clip default, the required-prop sweep,
	Button's content rule — before a binding had delivered anything. ]]
function properties.assertCombinations(class: string, props: any, bound: any?)
	if class == "Text" then
		assertTruncate(props)
	elseif class == "Image" then
		assertImageScale(props, bound)
	elseif class == "ScrollView" then
		assertScrollExtent(props, bound)
	end
	if class == "ZStack" then
		properties.assertCircleSquare(class, props)
	end
	if props.wrap == true and props.align == "stretch" then
		error(
			`Facet UI.{class}: \`align = "stretch"\` has two readings on a wrapping stack — "each child `
				.. `fills its line" and "the lines fill the container" — so it is refused. Put `
				.. '`lineAlign = "stretch"` on the children that should fill their line, and use `align` '
				.. "(start|center|end) for where the block of lines sits.",
			0
		)
	end
end
return properties
