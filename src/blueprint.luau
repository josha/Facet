--!strict
-- Blueprint layer (design §4.3 #1, §5): immutable declarative node
-- descriptions built by strictly-shaped plain-table constructors. Blueprints
-- carry stable identity (explicit id or deterministic generated id at mount),
-- a class, validated props, and (for containers) ordered children.
-- No reactivity here: props MAY be core Readables (signal/memo) — the mount
-- layer subscribes them per the class's declared prop->dirty-class map.
-- Structural regions (When/ForEach) are ordinary blueprint nodes whose mount
-- behavior owns branch/item scopes (design §5.4).

local stylingLib = require("./tokens/styling")
local chromeSlots = require("./tokens/chrome_slots")
local schema = require("./blueprint_schema")
-- the R4 icon vocabulary. Required for ONE pure predicate (`isIconName`): a
-- typo'd semantic name is an icon that silently never resolves, which is the
-- accepted-and-ignored class the strict boundary exists to remove.
local themePackage = require("./themes/package")
-- the public drag/drop declaration channel (ADR-0022 D5): validation and the
-- reserved metadata keys live there so this module stays a thin authoring face
local dragContract = require("./input/drag_contract")
-- the declared-content composition normalizer (ADR-0023): ONE ruling on what a
-- composition declaration may say, read here for construction and by the solver
-- on every solve, so the two can never disagree about what is legal
local compositionLib = require("./layout/composition")

local blueprint = {}

export type Blueprint = {
	class: string,
	id: string?,
	props: { [string]: any },
	children: { Blueprint }?,
	-- framework metadata channel (Milestone 0, investment 1): input
	-- contributions and other library-internal attachments ride HERE, not in
	-- the public prop bag, so strict prop validation and the internal channel
	-- can never be confused for one another.
	meta: { [string]: any }?,
}

blueprint.schema = schema

-- ===== public spec types (Milestone 0, investment 1) =======================
-- Every constructor takes an exported, useful spec type instead of an
-- implicit `any`. These are the SAME contract the runtime schema enforces:
-- `tools/lune/check_prop_parity` fails when an exported type and
-- `blueprint_schema` disagree about a class's fields, so the editor hint and
-- the runtime error can never drift apart.
--
-- `Bound<T>` = a plain value OR a Signal/Memo of it. A prop typed as plain `T`
-- is read once at mount and REJECTS a Readable at construction.

local coreContract = require("./core/contract")

export type Readable<T> = coreContract.Readable<T>
export type Bound<T> = T | Readable<T>

-- A THEME METRIC NAME (ADR-0019 §2): a spacing step ("xs".."xl") or a dotted
-- path into the active ThemeSnapshot ("controls.slider.thumbSize",
-- "targetSizes.minimum"). Accepted anywhere a theme-owned number is, and
-- resolved to pixels on every solve — a literal number opts that value OUT of
-- theming, which is the documented escape hatch.
export type Metric = string
-- a typography role name: "caption" | "label" | "body" | "heading" | "title" | "control"
export type TypeRole = string

-- a layout dimension: exactly one `type` with its own payload field
export type Dim = {
	type: string, -- "fixed" | "content" | "hug" | "fill" | "percent" | "minMax" | "aspect"
	px: (number | Metric)?, -- fixed
	weight: number?, -- fill
	fraction: number?, -- percent
	offset: number?, -- percent: pixel adjustment applied before clamping
	min: (number | Metric)?, -- percent clamp / minMax
	preferred: (number | Metric)?, -- minMax
	max: (number | Metric)?, -- percent clamp / minMax
	ratio: number?, -- aspect
}

-- padding / margin: one number or metric name, or per-side
export type SideValue = number | Metric
export type Sides = SideValue | { top: SideValue?, right: SideValue?, bottom: SideValue?, left: SideValue? }

-- pointer-zone callbacks (ADR-0008). `rectOf(path)` returns the solved rect.
export type PointerHandlers = {
	onPointerDown: ((path: string, pos: { x: number, y: number }, rectOf: (string) -> any) -> boolean?)?,
	onPointerMove: ((path: string, pos: { x: number, y: number }, rectOf: (string) -> any) -> ())?,
	onPointerUp: ((path: string, pos: { x: number, y: number }, rectOf: (string) -> any) -> ())?,
	onPointerCancel: ((path: string, reason: string?) -> boolean?)?,
}

-- props every rendered node accepts: its own box, plus the placement props a
-- container parent reads off its children
export type BoxProps = {
	id: string?,
	width: Bound<Dim>?,
	height: Bound<Dim>?,
	margin: Bound<Sides>?,
	anchor: Bound<string>?,
	offsetX: Bound<number | Metric>?,
	offsetY: Bound<number | Metric>?,
	alignH: Bound<string>?,
	alignV: Bound<string>?,
	shadow: Bound<any>?,
	gradient: Bound<any>?,
	corners: Bound<any>?,
	-- normalized UI.stroke data (bind a memo of UI.strokeData(…) to pulse it)
	stroke: Bound<any>?,
	-- paint-order override inside the parent's stacking scope; read once at mount
	zIndex: number?,
}

-- props every container accepts on top of BoxProps
export type ContainerProps = {
	padding: Bound<Sides>?,
	overflow: Bound<string>?,
	clipChildren: boolean?,
	active: Bound<boolean>?,
	surface: Bound<string>?,
	children: { Blueprint }?,
}

export type ScreenSpec = BoxProps & ContainerProps & { gap: Bound<number | Metric>?, align: Bound<string>? }
export type VStackSpec = ScreenSpec
export type HStackSpec = ScreenSpec
export type ZStackSpec = BoxProps & ContainerProps & { canvasGroup: boolean? }
export type AnchorSpec = BoxProps & ContainerProps
export type ScrollViewSpec = BoxProps & ContainerProps & {
	gap: Bound<number | Metric>?,
	axis: string?,
	onScrollWheel: ((path: string, delta: number, rectOf: (string) -> any) -> ())?,
	autoscroll: (boolean | { [string]: any })?,
}
export type GridSpec = BoxProps & ContainerProps & {
	gap: Bound<number | Metric>?,
	rowGap: Bound<number | Metric>?,
	columns: Bound<number>?,
	minColumnWidth: Bound<number | string>?,
	itemSizing: Bound<string>?,
}

export type AdaptiveStackSpec = BoxProps & ContainerProps & {
	gap: Bound<number | Metric>?,
	align: Bound<string>?,
	axis: Bound<string>?,
}
export type ViewThatFitsSpec = BoxProps & { children: { Blueprint } }

-- DECLARED-CONTENT ADAPTIVE COMPOSITION (ADR-0023). A screen declares WHAT it
-- has to say, ranked, with a richest-to-minimum form list per region; the
-- framework decides WHERE, from the box it actually received, on both axes.
export type CompositionGroup = {
	id: string,
	-- EITHER a lane affinity an arrangement absorbs, OR `span` — a full-width row
	-- of its own, in that position relative to the lanes, in every arrangement
	lane: string?,
	span: string?, -- "above" | "below"
	sizing: string?,
	weight: number?,
	place: (string | number)?,
	minWidth: (number | Metric)?,
	gap: number?,
}
export type CompositionArrangement = string | { name: string, lanes: { { string } } }
export type CompositionSpec = BoxProps & ContainerProps & {
	arrangements: { CompositionArrangement },
	groups: { CompositionGroup },
	laneGap: (number | Metric)?,
	groupGap: (number | Metric)?,
	maxMeasure: (number | Metric)?,
}
export type RegionFloor = { lines: number?, role: TypeRole?, targets: number? }
export type RegionSpec = {
	id: string?,
	group: string,
	rank: number,
	floor: RegionFloor?,
	sizing: string?,
	weight: number?,
	mayScroll: boolean?,
	mayDrop: boolean?,
	reserved: boolean?,
	children: { Blueprint },
}
export type DividerSpec = BoxProps & {
	axis: Bound<string>?,
	thickness: Bound<number>?,
}

-- `tint` is the continuous-colour channel: { role, blend, from? } (themable) or
-- { direct = {r,g,b} | "#rrggbb" } (declared theming-exempt). `canvasGroup` makes
-- this Box its subtree's fade group — see blueprint_schema for both rulings.
export type BoxSpec = BoxProps & {
	surface: Bound<string>?,
	active: Bound<boolean>?,
	tint: Bound<any>?,
	canvasGroup: boolean?,
}
export type SpacerSpec = BoxProps

export type TextSpec = BoxProps & {
	text: Bound<string | number>,
	textSize: Bound<number | TypeRole>?,
	textAlign: Bound<string>?,
	-- at most this many lines (SwiftUI `.lineLimit`); beyond it the engine
	-- ellipsizes instead of the box growing. The owner's knowledge, not the
	-- string's — see blueprint_schema's LINE_LIMIT for the ruling
	lineLimit: Bound<number>?,
	padding: Bound<Sides>?,
	role: Bound<string>?,
	-- "badge" | "chip" only — a Text is not interactive, so it is offered the
	-- read-only surfaces and no others (see blueprint_schema for the ruling)
	surface: Bound<string>?,
	tint: Bound<any>?,
}

export type ImageSpec = BoxProps & {
	image: Bound<string>?,
	surface: Bound<string>?,
	tint: Bound<any>?,
	-- "fit" | "fill" | "crop" | "stretch" (nine-slice stays theme-owned chrome)
	scaleMode: Bound<string>?,
}

export type ButtonSpec = BoxProps & PointerHandlers & {
	children: { Blueprint }?,
	role: Bound<string>?,
	gap: Bound<number | Metric>?,
	align: Bound<string>?,
	shape: string?,
	icon: string?,
	label: Bound<string | number>,
	compactLabel: (string | { text: string?, icon: string?, image: string? })?,
	enabled: Bound<boolean>?,
	selected: Bound<boolean>?,
	focusable: Bound<boolean>?,
	surface: Bound<string>?,
	padding: Bound<Sides>?,
	textSize: Bound<number | TypeRole>?,
	onActivate: ((path: string, meta: any?) -> ())?,
}

export type ToggleSpec = BoxProps & {
	label: Bound<string | number>,
	value: Bound<boolean>?,
	enabled: Bound<boolean>?,
	focusable: Bound<boolean>?,
	padding: Bound<Sides>?,
	textSize: Bound<number | TypeRole>?,
	onActivate: ((path: string, meta: any?) -> ())?,
}

export type TextFieldSpec = BoxProps & {
	text: Bound<string>?,
	placeholder: Bound<string>?,
	editing: Bound<boolean>?,
	enabled: Bound<boolean>?,
	focusable: Bound<boolean>?,
	padding: Bound<Sides>?,
	textSize: Bound<number | TypeRole>?,
	maxLength: Bound<number>?,
	keyboardType: Bound<string>?,
	onTextChanged: ((text: string) -> ())?,
	onFocusGained: ((path: string) -> ())?,
	onFocusLost: ((reason: string) -> ())?,
}

export type GripSpec = BoxProps & PointerHandlers & {
	cursorHint: Bound<string>?,
	focusable: Bound<boolean>?,
}

export type PathSpec = BoxProps & {
	points: Bound<{ any }>,
	thickness: Bound<number>?,
	closed: Bound<boolean>?,
	role: Bound<string>?,
	tint: Bound<any>?,
}

-- A structural region's enter/exit declaration (ADR-0022 Decision 3). `exit`
-- defaults to the mirror of `enter`; `class` names a motion class (default
-- "container"); `fade` pairs a slide with a transparency fade, which — like the
-- fading forms themselves — needs the child to be a declared `canvasGroup` node.
export type TransitionSpec = {
	enter: string,
	exit: string?,
	class: string?,
	fade: boolean?,
}

export type WhenSpec = {
	id: string?,
	condition: Readable<boolean>,
	thenView: () -> Blueprint,
	transition: TransitionSpec?,
}

export type ForEachSpec = {
	id: string?,
	items: Readable<{ any }>,
	key: (item: any) -> string,
	row: (item: any, itemScope: any) -> Blueprint,
	transition: TransitionSpec?,
}

export type ErrorBoundarySpec = {
	id: string?,
	view: () -> Blueprint,
	fallback: (err: any) -> Blueprint,
}

-- prop -> dirty classes invalidated when a dynamic prop changes (§6.4),
-- DERIVED from the public schema (src/blueprint_schema.luau) so the schema,
-- the mount layer's subscription classes, and the documentation can no longer
-- disagree. mount.luau reads this table.
local PROP_DIRTY: { [string]: { [string]: { string } } } = schema.propDirty()

blueprint.PROP_DIRTY = PROP_DIRTY

local CONTAINER: { [string]: boolean } = {}
for name, classSpec in schema.all() do
	if classSpec.container then
		CONTAINER[name] = true
	end
end

local function isReadable(v: any): boolean
	return type(v) == "table" and (v.kind == "signal" or v.kind == "memo")
end
blueprint.isReadable = isReadable

-- ===== strict construction (Milestone 0, investment 1) =====================
-- Every public constructor funnels through make(). An unknown, wrongly-typed,
-- missing-required, or diagnosed-unsupported property fails HERE, naming the
-- control, the property, and the closest valid alternatives — instead of
-- freezing into the node and being dropped somewhere downstream.

local CONTAINER_NAMES: { string } = {}
for name in CONTAINER do
	table.insert(CONTAINER_NAMES, name)
end
table.sort(CONTAINER_NAMES)

local function quoteList(names: { string }): string
	local parts = {}
	for _, n in names do
		table.insert(parts, `'{n}'`)
	end
	return table.concat(parts, ", ")
end

local function unknownPropError(class: string, key: string): string
	local suggestions = schema.suggest(class, key)
	local msg = `LuauUI UI.{class}: unknown property '{key}'.`
	if #suggestions > 0 then
		msg ..= ` Did you mean {quoteList(suggestions)}?`
	end
	msg ..= ` Valid properties: {table.concat(schema.propNames(class), ", ")}.`
	return msg
end

local function validateProp(class: string, key: string, value: any, propSpec: schema.PropSpec)
	local dep = propSpec.deprecated
	if dep ~= nil then
		error(
			`LuauUI UI.{class}.{key} is not supported (deprecated {dep.since}, removable in {dep.removeNoEarlierThan}). `
				.. `Use {dep.replacement}. {dep.note or ""}`,
			0
		)
	end
	if isReadable(value) then
		if not propSpec.reactive then
			error(
				`LuauUI UI.{class}.{key} does not accept a Signal/Memo (it is read once at mount). `
					.. `Pass a plain value, or rebuild the subtree through UI.When/UI.ForEach.`,
				0
			)
		end
		return -- a reactive value is checked when it is read, not at construction
	end
	local ok, detail = schema.checkValue(propSpec, value)
	if not ok then
		local expected = table.concat(propSpec.types, " | ")
		error(
			`LuauUI UI.{class}.{key} expects {expected}, got {typeof(value)}`
				.. (if detail ~= nil then ` — {detail}` else "")
				.. `. ({propSpec.doc})`,
			0
		)
	end
end

local function make(class: string, spec: any): Blueprint
	if type(spec) ~= "table" then
		error(`LuauUI UI.{class}: the constructor takes one spec table, got {typeof(spec)}`, 0)
	end
	local classSpec = schema.forClass(class)
	if classSpec == nil then
		error(`LuauUI: unknown blueprint class '{class}'`, 0)
	end
	local known = classSpec.props
	local props: { [string]: any } = {}
	local children: { Blueprint }? = nil
	local id: string? = nil
	for k, v in spec do
		if k == "id" then
			if type(v) ~= "string" or v == "" then
				error(`LuauUI UI.{class}.id must be a non-empty string, got {typeof(v)}`, 0)
			end
			id = v
		elseif k == "children" then
			if not classSpec.container then
				error(
					`LuauUI UI.{class} does not take children (it is a leaf). `
						.. `Containers: {table.concat(CONTAINER_NAMES, ", ")}.`,
					0
				)
			end
			if type(v) ~= "table" then
				error(`LuauUI UI.{class}.children must be an array of blueprints, got {typeof(v)}`, 0)
			end
			children = table.clone(v)
		else
			if type(k) ~= "string" then
				error(`LuauUI UI.{class}: spec keys must be strings (got a {typeof(k)} key)`, 0)
			end
			local propSpec = known[k]
			if propSpec == nil then
				error(unknownPropError(class, k), 0)
			end
			validateProp(class, k, v, propSpec)
			props[k] = v
		end
	end
	for propName, propSpec in known do
		if propSpec.required and props[propName] == nil then
			error(`LuauUI UI.{class}.{propName} is required ({propSpec.doc})`, 0)
		end
	end
	local node: Blueprint = { class = class, id = id, props = props, children = children }
	return table.freeze(node) :: any
end

-- public constructors (§10.1 subset for Phase 1)
function blueprint.Screen(spec: ScreenSpec): Blueprint
	return make("Screen", spec)
end
function blueprint.VStack(spec: VStackSpec): Blueprint
	return make("VStack", spec)
end
function blueprint.HStack(spec: HStackSpec): Blueprint
	return make("HStack", spec)
end
function blueprint.ZStack(spec: ZStackSpec): Blueprint
	return make("ZStack", spec)
end
function blueprint.ScrollView(spec: ScrollViewSpec?): Blueprint
	-- native-substrate NS-A2: a scroll region is ALWAYS a clip host — on the
	-- native path the adapter mounts it as a ScrollingFrame (engine scroll +
	-- clip); on the fallback path the same declaration still crops overflow
	-- through the proven Frame+ClipsDescendants clip-host mechanism.
	local merged = if spec ~= nil then table.clone(spec) else {}
	if merged.clipChildren == nil then
		merged.clipChildren = true
	end
	return make("ScrollView", merged)
end
function blueprint.Spacer(spec: SpacerSpec?): Blueprint
	return make("Spacer", (spec :: any) or {})
end
function blueprint.Box(spec: BoxSpec): Blueprint
	return make("Box", spec)
end
function blueprint.Anchor(spec: AnchorSpec): Blueprint
	return make("Anchor", spec)
end
function blueprint.Grid(spec: GridSpec): Blueprint
	return make("Grid", spec)
end
-- AdaptiveStack (A-AL2): a stack whose axis is a REACTIVE prop, so a viewport or
-- orientation change re-solves in place instead of remounting the subtree the way
-- a VStack/HStack swap through UI.When would.
function blueprint.AdaptiveStack(spec: AdaptiveStackSpec): Blueprint
	return make("AdaptiveStack", spec)
end
-- ViewThatFits (A-AL1): tries its children as candidate layouts in DECLARED
-- order against the space this container actually received, and shows the first
-- that fits (the last is the fallback). Every candidate stays mounted, so a
-- resize re-chooses without rebuilding; the unchosen ones are hidden AND removed
-- from focus order, so navigation can never land on an invisible control.
function blueprint.ViewThatFits(spec: ViewThatFitsSpec): Blueprint
	local bp = make("ViewThatFits", spec)
	if bp.children == nil or #bp.children == 0 then
		error(
			"LuauUI UI.ViewThatFits needs at least one candidate in `children` (they are the candidate layouts, in preference order)",
			0
		)
	end
	return bp
end
-- Region (ADR-0023): ONE ranked thing a composition has to say. Its children are
-- its FORMS, richest first, and the last one is its minimum-viable form — the
-- smallest thing the author is willing to show. Declared in READING order; the
-- `rank` is adaptation priority only, and the two are deliberately independent.
function blueprint.Region(spec: RegionSpec): Blueprint
	local bp = make("Region", spec)
	if bp.id == nil then
		error(
			"LuauUI UI.Region needs an explicit `id`: it is what the resolution, the dump and the "
				.. "focus ring address, and a generated one would change the diagnosis between runs",
			0
		)
	end
	if bp.children == nil or #bp.children == 0 then
		error(
			`LuauUI UI.Region '{bp.id}' needs at least one form in \`children\` (the forms are the `
				.. `representations of this region, richest first)`,
			0
		)
	end
	return bp
end
-- Composition (ADR-0023): the screen-level sibling of AdaptiveStack (one bound
-- axis) and ViewThatFits (one container's candidate). Every declaration error it
-- can catch, it catches HERE — an unknown field, a second scroll region, a group
-- with no home in some arrangement — because every one of those is a screen that
-- looks right on the device you tested and is wrong on the one you did not.
function blueprint.Composition(spec: CompositionSpec): Blueprint
	local bp = make("Composition", spec)
	local children = bp.children or {}
	if #children == 0 then
		error("LuauUI UI.Composition needs at least one UI.Region in `children` — the regions ARE the declaration", 0)
	end
	local regions = {}
	for i, child in children do
		if child.class ~= "Region" then
			error(
				`LuauUI UI.Composition child {i} is a {child.class}, not a UI.Region. A composition places `
					.. "RANKED regions; wrap it in UI.Region{ id, group, rank, children = { <forms> } }",
				0
			)
		end
		table.insert(regions, {
			id = child.id,
			group = child.props.group,
			rank = child.props.rank,
			forms = #(child.children or {}),
			sizing = child.props.sizing,
			weight = child.props.weight,
			floor = child.props.floor,
			mayScroll = child.props.mayScroll,
			mayDrop = child.props.mayDrop,
			-- A LIVE `reserved` IS STILL A RESERVATION AT CONSTRUCTION. The read
			-- answers WHEN the box is held, never WHETHER this region is the kind that
			-- holds one — so the floor requirement and the mayDrop exclusivity below
			-- must fire at the call site either way. Reading the signal here instead
			-- would make those two errors depend on the value it happened to hold on
			-- the frame the screen was built.
			reserved = if isReadable(child.props.reserved) then true else child.props.reserved,
		})
	end
	-- A metric NAME inside a group is validated with the same ruling every other
	-- theme-owned number gets — nested inside an array, the prop schema cannot
	-- reach it, and an unresolvable name is a minimum width that silently becomes
	-- zero (the accepted-and-ignored class this boundary exists to remove).
	local METRIC_OR_PX = { types = { "number", "metric" }, reactive = false, channel = "layout", doc = "" }
	for _, group in bp.props.groups or {} do
		for _, field in { "minWidth", "gap" } do
			local value = (group :: any)[field]
			if value ~= nil then
				local ok, detail = schema.checkValue(METRIC_OR_PX :: any, value)
				if not ok then
					error(
						`LuauUI UI.Composition group '{tostring((group :: any).id)}'.{field} expects a px `
							.. `number or a theme metric name{if detail ~= nil then ` — {detail}` else ""}`,
						0
					)
				end
			end
		end
	end
	-- THE DECLARATION IS VALIDATED AT CONSTRUCTION, by the same pure normalizer
	-- the solver runs, so the error names the mistake at the call site instead of
	-- surfacing as a missing region three devices later.
	--[[ A LIVE `eligible` IS STILL A GATE AT CONSTRUCTION — the same ruling
		`reserved` gets just above. The read answers WHEN this candidate is offered,
		never WHETHER the declaration is well-formed, so the shape check must fire at
		the call site whatever the signal happened to hold on the frame the screen
		was built. The solver resolves the read per solve. ]]
	local arrangements = {}
	for _, a in bp.props.arrangements or {} do
		if type(a) == "table" and isReadable((a :: any).eligible) then
			local copy = table.clone(a :: any)
			copy.eligible = true
			table.insert(arrangements, copy)
		else
			table.insert(arrangements, a)
		end
	end

	compositionLib.normalize({
		id = bp.id,
		groups = bp.props.groups,
		regions = regions,
		arrangements = arrangements,
		-- metric names are resolved per solve; the normalizer only rules on shape,
		-- so the numeric fields are deliberately not handed to it here
	})
	return bp
end
-- Divider (A-LV3): an axis-aware hairline. It infers its orientation from the
-- enclosing stack, so one declaration works in both.
function blueprint.Divider(spec: DividerSpec?): Blueprint
	return make("Divider", (spec :: any) or {})
end
function blueprint.Grip(spec: GripSpec): Blueprint
	return make("Grip", spec)
end
function blueprint.Text(spec: TextSpec): Blueprint
	return make("Text", spec)
end
function blueprint.Image(spec: ImageSpec): Blueprint
	return make("Image", spec)
end
-- Button (B-BTN1): custom content is allowed, but it must stay inside ONE
-- activation surface. A focusable in the content would give the button a second
-- focus site AND double-fire Activate (the presenter dispatches to the node's own
-- handler and then to the longest-prefix contribution), so it is rejected here —
-- at the boundary, with the offending node named — rather than producing a screen
-- that misbehaves only under keyboard or gamepad navigation.
local CONTENT_FOCUSABLE: { [string]: boolean } = { Button = true, Toggle = true, TextField = true }

local function assertNoFocusableContent(children: { Blueprint }?)
	if children == nil then
		return
	end
	local function walk(node: Blueprint)
		if CONTENT_FOCUSABLE[node.class] or (node.class == "Grip" and node.props.focusable == true) then
			error(
				`LuauUI UI.Button: custom content must stay inside one activation surface, but it `
					.. `contains a focusable UI.{node.class} ('{node.id or "unnamed"}'). Put the control `
					.. `beside the Button, not inside it.`,
				0
			)
		end
		for _, child in node.children or {} do
			walk(child)
		end
	end
	for _, child in children do
		walk(child)
	end
end

-- THE CIRCLE BUTTON'S BOUNDARY RULES (feature round 2026-07-26).
--
-- A disc has room for ONE mark. Everything below is refused HERE, at
-- construction, with the field named, the rule stated and the fix spelled out —
-- rather than at paint, where the failure is a clipped label nobody sees until a
-- device screenshot. Same discipline as the focusable-content refusal above.
local CIRCLE_MAX_CHARS = 3

local function circleDrawnLabel(props: { [string]: any }, children: { Blueprint }?): (string | number)?
	-- the label is the DRAWN content only when nothing else occupies the disc:
	-- an `icon` puts the framework's glyph (or the theme's art) there and a
	-- content button draws its children, and in both cases the label is purely
	-- the semantic name — exactly as it already is for a content button.
	if props.icon ~= nil or (children ~= nil and #children > 0) then
		return nil
	end
	local label = props.label
	if isReadable(label) then
		return nil -- a bound label is checked when it is read, like every reactive prop
	end
	return label
end

local function assertShape(props: { [string]: any }, children: { Blueprint }?)
	local shape = props.shape
	if props.icon ~= nil and shape ~= "circle" then
		error(
			`LuauUI UI.Button.icon is only supported with shape = "circle" (got shape = `
				.. `{if shape == nil then "nil" else `'{tostring(shape)}'`}). A circle's content is ONE mark, `
				.. `which is what a semantic icon name describes. Fix: add shape = "circle", or put an icon `
				.. `BESIDE a title with LuauUI.newLabel inside the button's children.`,
			0
		)
	end
	if props.icon ~= nil and not themePackage.isIconName(props.icon) then
		local known: { string } = {}
		for name in themePackage.ICON_FALLBACK_GLYPHS :: any do
			table.insert(known, name)
		end
		table.sort(known)
		error(
			`LuauUI UI.Button.icon: '{tostring(props.icon)}' names no semantic icon. It must be a framework `
				.. `name ({table.concat(known, ", ")}) or a namespaced one a package contributes ("ns:name"). `
				.. `Fix: use a framework name, or namespace your own and declare it in the package's `
				.. `\`icons\` map.`,
			0
		)
	end
	if shape ~= "circle" then
		return
	end
	if props.width ~= nil and props.height ~= nil then
		error(
			`LuauUI UI.Button: shape = "circle" takes at most ONE of \`width\` / \`height\` — the solver `
				.. `enforces the 1:1 square, so the other axis follows and the author never does the math. `
				.. `Fix: drop one of them (or drop both to size the disc from the control metric).`,
			0
		)
	end
	local drawn = circleDrawnLabel(props, children)
	if drawn == nil then
		return
	end
	local text = tostring(drawn)
	if string.find(text, "%s") ~= nil or utf8.len(text) == nil or (utf8.len(text) :: number) > CIRCLE_MAX_CHARS then
		error(
			`LuauUI UI.Button.label: '{text}' cannot be the drawn content of shape = "circle" — a disc holds `
				.. `ONE icon or up to {CIRCLE_MAX_CHARS} characters with no spaces, and a longer label has `
				.. `nowhere to go inside a 1:1 target. Fix: pass icon = "<semantic name>" (e.g. "more", `
				.. `"close", "menu") and keep this label as the semantic name, shorten the label, or drop `
				.. `shape = "circle" for the default rectangular Button.`,
			0
		)
	end
end

-- THE SEMANTIC HALF of the compact-label grammar. `blueprint_schema` proved the
-- SHAPE (one key from a closed set, non-empty strings); these are the rules that
-- need to know what the value MEANS, which is the same split `icon` already uses.
local function assertCompactLabel(props: { [string]: any }, children: { Blueprint }?)
	local compact = props.compactLabel
	if compact == nil then
		return
	end
	-- A CONTENT BUTTON DRAWS NO TEXT OF ITS OWN (B-BTN1), so it has no label to
	-- shorten: `applyProp` writes its label as "" precisely so custom content is
	-- not drawn over. A compact form here would be silently inert.
	if children ~= nil and #children > 0 then
		error(
			`LuauUI UI.Button.compactLabel is not supported on a CONTENT button — a button with children `
				.. `draws no text of its own (its label is semantics only), so there is nothing to shorten. `
				.. `Fix: drop compactLabel, or make the content itself adapt with UI.ViewThatFits.`,
			0
		)
	end
	local text = if type(compact) == "string"
		then compact
		else (if type(compact) == "table" then (compact :: any).text else nil)
	-- NO WHITESPACE, and this is the point of the whole feature rather than a nit.
	-- A compact form is chosen BECAUSE the full label did not fit; a phrase has a
	-- legal break point, so the engine would wrap it and the button would be
	-- exactly as tall as the case we were escaping (director round 6, "Don"/"e").
	if type(text) == "string" and string.find(text, "%s") ~= nil then
		error(
			`LuauUI UI.Button.compactLabel: '{text}' contains whitespace, and a compact label must be ONE `
				.. `word. It is drawn only when the full label did not fit, and a phrase has a legal break `
				.. `point — so the engine would wrap it and the button would be as tall as the case the `
				.. `compact form exists to avoid. Fix: use a single word, or icon = "<semantic name>".`,
			0
		)
	end
	local icon = if type(compact) == "table" then (compact :: any).icon else nil
	if icon ~= nil and not themePackage.isIconName(icon) then
		local known: { string } = {}
		for name in themePackage.ICON_FALLBACK_GLYPHS :: any do
			table.insert(known, name)
		end
		table.sort(known)
		error(
			`LuauUI UI.Button.compactLabel.icon: '{tostring(icon)}' names no semantic icon. It must be a `
				.. `framework name ({table.concat(known, ", ")}) or a namespaced one a package contributes `
				.. `("ns:name"). Fix: use a framework name, or namespace your own and declare it in the `
				.. `package's \`icons\` map.`,
			0
		)
	end
end

function blueprint.Button(spec: ButtonSpec): Blueprint
	local bp = make("Button", spec)
	assertNoFocusableContent(bp.children)
	assertShape(bp.props, bp.children)
	assertCompactLabel(bp.props, bp.children)
	return bp
end
function blueprint.Toggle(spec: ToggleSpec): Blueprint
	return make("Toggle", spec)
end
-- TextField: the text-entry leaf primitive (§17 Phase 5). No required prop —
-- text/placeholder default empty; the composite UI.newTextInput wires them.
-- The engine adapter maps this to a TextBox; headless it is the setProp/
-- setTextInputHandlers seam proved under Lune.
function blueprint.TextField(spec: TextFieldSpec): Blueprint
	return make("TextField", spec)
end

-- structural regions (§5.4)
function blueprint.Path(spec: PathSpec): Blueprint
	return make("Path", spec)
end
function blueprint.When(spec: WhenSpec): Blueprint
	return make("When", spec)
end

function blueprint.ForEach(spec: ForEachSpec): Blueprint
	return make("ForEach", spec)
end

-- SwiftUI-style style modifiers (§17 Phase 4 engine styling; UI-STYLE-001).
-- Each returns a NEW blueprint (blueprints are frozen/immutable) whose style
-- props ride the STYLE authority: applied to a single element they style
-- that element; applied to a container they style the container's own
-- rendered surface; UI.styleGroup applies the modifier set to EVERY element
-- of a collection (SwiftUI Group semantics). Token names resolve against
-- the active style (optional third argument; default: Studio Neutral).
local function withProps(bp: Blueprint, extra: { [string]: any }): Blueprint
	-- modifiers write through the SAME validation as a constructor. Without this
	-- they would be a hole straight through Milestone 0's strict authoring:
	-- `UI.alignment(bp, "middle")` used to freeze an unrecognised value into the
	-- node exactly as a bad spec key once did.
	local classSpec = schema.forClass(bp.class)
	if classSpec == nil then
		error(`LuauUI: unknown blueprint class '{bp.class}'`, 0)
	end
	for k, v in extra do
		local propSpec = classSpec.props[k]
		if propSpec == nil then
			error(unknownPropError(bp.class, k), 0)
		end
		validateProp(bp.class, k, v, propSpec)
	end
	local props = table.clone(bp.props)
	for k, v in extra do
		props[k] = v
	end
	return table.freeze({ class = bp.class, id = bp.id, props = props, children = bp.children, meta = bp.meta }) :: any
end

-- UI.shadow(bp, presetNameOrParams, style?) — UIShadow-backed drop shadow
function blueprint.shadow(bp: Blueprint, spec: any, style: any?): Blueprint
	return withProps(bp, { shadow = stylingLib.normalizeShadow(spec, style) })
end

-- UI.gradient(bp, { colors, rotation?, transparency?, enabled? }, style?) —
-- a UIGradient-backed per-view wash (charter cap 11; ADR-0020 R8 rung 2).
--
-- Two refusals live HERE rather than in the normalizer, because both are facts
-- about the NODE and not about the ramp:
--
--  1. A VALUE CONTROL'S OWN CHROME NEVER TAKES A WASH. This is the ADR-0019
--     ruling `themes.define` already enforces on the theme rung, and a rung-2
--     modifier that walked around it would reopen a shipped decision: a wash's
--     alpha makes the node see-through and whatever the control draws behind it
--     reads straight through the glass (that is literally how a slider thumb
--     went translucent). Same wall, same reason, same shape of message.
--  2. A TEXT-BEARING NODE REFUSES IT. `UIGradient` multiplies the parent's own
--     rendering — its engine-drawn GLYPHS included, not just its fill — so a
--     wash on a Button darkens its label with it. `UI.shadow` has no such rule
--     because a shadow cannot touch a glyph; the analogous shipped treatment is
--     the slot shadow, which rides the DECORATION when one exists. A per-view
--     modifier has no decoration to fall back on under a flat theme, and a
--     modifier whose effect moves depending on the installed package would be
--     worse than a refusal. So it refuses at construction, exactly as
--     `surface = "control"` on a `UI.Text` does, and names the same fix: put
--     the wash on the `UI.Box` behind the label.
local TEXT_BEARING_CLASSES: { [string]: boolean } = { Text = true, Button = true, Toggle = true, TextField = true }

-- The two construction-time gradient walls, hoisted so EVERY entry point that can
-- write a `gradient` prop goes through the same refusal. `UI.styleGroup` used to
-- normalize the identical spec and call `withProps` directly, which meant the
-- collection form silently accepted what the singular form refuses (rich-skinning-v2
-- architecture verifier F1). One function, two callers — the walls cannot drift.
local function assertGradientable(bp: Blueprint, entry: string)
	local hint = chromeSlots.readHint(bp)
	local slot = if hint ~= nil then hint.slot else nil
	if type(slot) == "string" and chromeSlots.isSlot(slot) and not chromeSlots.isGradientable(slot) then
		error(
			`LuauUI: {entry} cannot paint '{slot}' — it is a value control's own chrome, and a wash's alpha `
				.. "would make it see-through so whatever the control draws behind it reads straight through the "
				.. "glass. Gradient the surfaces an author opted into instead (a panel, a card, a control's own "
				.. "box), or retune the slot's flat colour. This is the same ruling themes.define enforces on a "
				.. "theme's chromeGradient.",
			0
		)
	end
	if TEXT_BEARING_CLASSES[bp.class] then
		error(
			`LuauUI: {entry} cannot paint a {bp.class} — UIGradient multiplies the node's OWN rendering, its `
				.. "engine-drawn glyphs included, so the wash would darken the label with the fill. Wrap it: put "
				.. `the gradient on a UI.Box (or the container) behind the {bp.class} and leave the text node `
				.. "alone. (This is the same construction-time ruling `surface` uses on a UI.Text.)",
			0
		)
	end
end

function blueprint.gradient(bp: Blueprint, spec: any, style: any?): Blueprint
	assertGradientable(bp, "UI.gradient")
	return withProps(bp, { gradient = stylingLib.normalizeGradient(spec, style) })
end

-- UI.corners(bp, radius|token|{radius}|{topLeft..bottomRight}, style?) —
-- per-corner UICorner rounding; exactly ONE form per node
function blueprint.corners(bp: Blueprint, spec: any, style: any?): Blueprint
	return withProps(bp, { corners = stylingLib.normalizeCorners(spec, style) })
end

-- UI.stroke(bp, { thickness?, color?, transparency? }, style?) — a reactive
-- authored border (ADR-0022 Decision 6, row SF-P3). Defaults are the theme's
-- hairline, so `UI.stroke(bp, {})` is the hairline the adapter already draws on a
-- raised panel. The adapter materializes ONE bespoke `LuauUIStroke` child and
-- reuses it, exactly as `UI.gradient` does — so no reactive update and no theme
-- swap can ever stack two borders on one node.
--
-- ADDITIVE, not a replacement: a theme's own chrome stroke is a phantom
-- `::UIStroke` RULE, and the engine renders a real UIStroke child alongside it
-- (ADR-0020 R8, measured live). A node that must show only one border should name
-- a surface that carries none.
function blueprint.stroke(bp: Blueprint, spec: any, style: any?): Blueprint
	return withProps(bp, { stroke = stylingLib.normalizeStroke(spec, style) })
end

-- UI.strokeData(spec, style?) — the same normalization WITHOUT a blueprint, for
-- the reactive idiom. Normalized style data is read once, so a pulse is a pulsing
-- PROP rather than a Signal buried inside the data:
--   stroke = core:memo(function() return UI.strokeData({ thickness = pulse:get() }) end)
function blueprint.strokeData(spec: any, style: any?): any
	return stylingLib.normalizeStroke(spec, style)
end

-- ===== drag and drop (ADR-0022 Decision 5; SF-D1/SF-D5) =====================
-- UI.draggable(bp, { payload, dragMotion?, proxy?, onCommitProxy?, grabAnchor?,
-- declineTouch?, promotionPx? }) and UI.dropTarget(bp, { accepts?, onDrop,
-- onEnter?, onLeave? })
-- are DECLARATIONS, not wiring: they ride the metadata channel and the renderer
-- picks them up when the node mounts, which is what makes drag/drop work the
-- same on a node the author wrote and a row a control generated. Everything the
-- gesture then does — promotion tokens, the session, enter/leave, the predicted
-- verdict, the return flight, the semantic events — lives in `input/`, so there
-- is exactly one policy path for pointer, touch, keyboard and gamepad.
--
-- LEGALITY IS ALWAYS THE GAME'S. `accepts(payload) -> (legal, reason?)` is the
-- only place a rule enters, and the reason code comes back out through the
-- `reject` event so a refusal is never silent.
function blueprint.draggable(bp: Blueprint, spec: dragContract.SourceSpec): Blueprint
	return dragContract.attach(bp, dragContract.SOURCE_PROP, dragContract.source(spec))
end

function blueprint.dropTarget(bp: Blueprint, spec: dragContract.TargetSpec): Blueprint
	return dragContract.attach(bp, dragContract.TARGET_PROP, dragContract.target(spec))
end

-- UI.styleGroup({ shadow?, gradient?, corners? }, blueprints, style?) — Group
-- semantics:
-- the modifier set applies to EACH contained element
function blueprint.styleGroup(
	spec: { shadow: any?, corners: any?, gradient: any? },
	blueprints: { Blueprint },
	style: any?
): { Blueprint }
	local extra: { [string]: any } = {}
	if spec.shadow ~= nil then
		extra.shadow = stylingLib.normalizeShadow(spec.shadow, style)
	end
	if spec.gradient ~= nil then
		-- SAME walls as UI.gradient, checked BEFORE any blueprint is produced so a
		-- refusal never leaves a half-styled collection behind (arch-F1).
		for _, bp in blueprints do
			assertGradientable(bp, "UI.styleGroup's gradient")
		end
		extra.gradient = stylingLib.normalizeGradient(spec.gradient, style)
	end
	if spec.corners ~= nil then
		extra.corners = stylingLib.normalizeCorners(spec.corners, style)
	end
	local out = {}
	for _, bp in blueprints do
		table.insert(out, withProps(bp, extra))
	end
	return out
end

-- ===== composable layout modifiers (A-LV2) =================================
-- Each returns a NEW blueprint (blueprints are frozen) and writes only
-- properties the SCHEMA already declares, so `make`'s validation, the dirty
-- classification and the property-authority manifest all still apply. A
-- modifier can therefore never silently claim a value another subsystem owns —
-- the rule investment 6 asks for.
--
-- ORDER: a modifier is a function call, so the reading order is the application
-- order and the LAST writer of a property wins. `UI.frame(UI.frame(bp, {width
-- = 50}), {width = 90})` is 90.

local FRAME_FIELDS: { [string]: boolean } = {
	width = true,
	height = true,
	minWidth = true,
	maxWidth = true,
	minHeight = true,
	maxHeight = true,
	idealWidth = true,
	idealHeight = true,
}

export type FrameSpec = {
	width: number?,
	height: number?,
	minWidth: number?,
	maxWidth: (number | string)?, -- "infinity" fills the available space
	minHeight: number?,
	maxHeight: (number | string)?,
	idealWidth: number?,
	idealHeight: number?,
}

local function frameDim(exact: number?, min: number?, max: any, ideal: number?): Dim?
	if exact ~= nil then
		return { type = "fixed", px = exact }
	end
	if max == "infinity" then
		return { type = "fill", weight = 1 }
	end
	if min ~= nil or max ~= nil or ideal ~= nil then
		return { type = "minMax", min = min, preferred = ideal, max = max :: number? }
	end
	return nil
end

-- UI.frame(bp, spec) — exact size, or a min/preferred/max band. `maxWidth =
-- "infinity"` is SwiftUI's fill idiom.
function blueprint.frame(bp: Blueprint, spec: FrameSpec): Blueprint
	if type(spec) ~= "table" then
		error(`LuauUI UI.frame: expected a spec table, got {typeof(spec)}`, 0)
	end
	for k in spec :: any do
		if not FRAME_FIELDS[k] then
			local names = {}
			for f in FRAME_FIELDS do
				table.insert(names, f)
			end
			table.sort(names)
			error(`LuauUI UI.frame: unknown field '{tostring(k)}'. Valid fields: {table.concat(names, ", ")}.`, 0)
		end
	end
	local extra: { [string]: any } = {}
	local w = frameDim(spec.width, spec.minWidth, spec.maxWidth, spec.idealWidth)
	local h = frameDim(spec.height, spec.minHeight, spec.maxHeight, spec.idealHeight)
	if w ~= nil then
		extra.width = w
	end
	if h ~= nil then
		extra.height = h
	end
	return withProps(bp, extra)
end

-- UI.padding(bp, sides) — inner spacing. Only classes whose schema declares
-- `padding` can inset (containers, the three text controls, and Text, whose
-- measure adds it); anything else is told to wrap rather than silently ignoring
-- the call.
function blueprint.padding(bp: Blueprint, sides: Sides): Blueprint
	local classSpec = schema.forClass(bp.class)
	if classSpec == nil or classSpec.props.padding == nil then
		error(
			`LuauUI UI.padding: UI.{bp.class} has no inner spacing to set — wrap it in a `
				.. `UI.VStack/UI.HStack and pad that instead.`,
			0
		)
	end
	return withProps(bp, { padding = sides })
end

-- UI.offset(bp, x, y) — arrange-only placement offset (no re-measure). Meaningful
-- for a child of UI.Anchor.
function blueprint.offset(bp: Blueprint, x: number?, y: number?): Blueprint
	local extra: { [string]: any } = {}
	if x ~= nil then
		extra.offsetX = x
	end
	if y ~= nil then
		extra.offsetY = y
	end
	return withProps(bp, extra)
end

-- UI.aspectRatio(bp, ratio) — derive the unconstrained axis from the other.
function blueprint.aspectRatio(bp: Blueprint, ratio: number): Blueprint
	if type(ratio) ~= "number" or ratio ~= ratio or ratio <= 0 then
		error(`LuauUI UI.aspectRatio: ratio must be a positive number (got {tostring(ratio)})`, 0)
	end
	-- the solver's `aspect` dim resolves against the resolved other axis; applying
	-- it to HEIGHT is the common case (a 16:9 media box with a known width)
	return withProps(bp, { height = { type = "aspect", ratio = ratio } })
end

-- UI.alignment(bp, horizontal?, vertical?) — placement inside a ZStack parent.
function blueprint.alignment(bp: Blueprint, horizontal: string?, vertical: string?): Blueprint
	local extra: { [string]: any } = {}
	if horizontal ~= nil then
		extra.alignH = horizontal
	end
	if vertical ~= nil then
		extra.alignV = vertical
	end
	return withProps(bp, extra)
end

-- UI.overlay(bp, content, alignment?) / UI.background(bp, content, alignment?)
-- Layer `content` above / behind `bp`. These are the two modifiers that must
-- change STRUCTURE (a layered pair is a ZStack), so the wrapper takes a derived
-- id and the base keeps its own — the base stays addressable by focus, tests and
-- dumps at `<parent>/<base.id>+overlay/<base.id>`.
local function layered(
	bp: Blueprint,
	content: Blueprint,
	suffix: string,
	contentFirst: boolean,
	align: string?
): Blueprint
	if bp.id == nil then
		error(`LuauUI UI.{suffix}: the base blueprint needs an explicit id (the wrapper's id derives from it)`, 0)
	end
	local children = if contentFirst then { content, bp } else { bp, content }
	local spec: { [string]: any } = { id = `{bp.id}+{suffix}`, children = children }
	-- the WRAPPER inherits the base's dimensions. Without this a fill-width base
	-- inside a content-sized ZStack collapses to the OVERLAY's width — found live,
	-- where a badged grid tile rendered 12px wide (its badge) instead of filling
	-- its column. The base keeps its own dims too; they simply agree.
	if bp.props.width ~= nil then
		spec.width = bp.props.width
	end
	if bp.props.height ~= nil then
		spec.height = bp.props.height
	end
	if align ~= nil then
		spec.alignH = align
	end
	return make("ZStack", spec)
end

function blueprint.overlay(bp: Blueprint, content: Blueprint, align: string?): Blueprint
	-- an overlay is an ORNAMENT — a badge, a caret, a corner ribbon — so it keeps
	-- its own size and is aligned on the base
	return layered(bp, content, "overlay", false, align)
end

-- A BACKGROUND BACKS THE THING IT IS BEHIND (RS-A16-D2's second half, found by
-- the headless matrix audit). The layer therefore FILLS the wrapper unless it
-- declares dimensions of its own: a ZStack child keeps its content size, so a
-- plate written as `UI.background(tile, UI.Box({ surface = "control" }))` solved
-- to 0x0 and painted nothing at all. Worse than nothing once a package skins it —
-- the adapter anchors a `corners` ornament to each corner of the host, and on a
-- zero-size host the bottom pair hangs a whole ornament ABOVE the row (measured
-- live under fantasy-ornate: 21 stat tiles, 84 px2 each, into the panel border of
-- the row above). An explicit dim still wins, so a deliberately smaller backing
-- plate is unchanged.
function blueprint.background(bp: Blueprint, content: Blueprint, align: string?): Blueprint
	local backing = content
	if content.props.width == nil or content.props.height == nil then
		local props: { [string]: any } = table.clone(content.props)
		props.width = props.width or { type = "fill", weight = 1 }
		props.height = props.height or { type = "fill", weight = 1 }
		backing = table.freeze({
			class = content.class,
			id = content.id,
			props = props,
			children = content.children,
		}) :: any
	end
	return layered(bp, backing, "background", true, align)
end

-- error boundary (§17 Phase 4): view() errors — at mount or during a later
-- structural rebuild inside the subtree — swap to fallback(err) instead of
-- taking the screen down. Errors inside the FALLBACK stay hard.
function blueprint.ErrorBoundary(spec: ErrorBoundarySpec): Blueprint
	return make("ErrorBoundary", spec)
end

return blueprint
