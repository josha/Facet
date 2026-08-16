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
-- the semantic feedback vocabulary and the `UI.sensoryFeedback` declaration
-- contract (round 2 §3.3). Required for the same reason `drag_contract` is: the
-- ruling on what a declaration may say lives with the vocabulary it cites, so
-- the twelve verbs exist in exactly one place. The module requires nothing
-- itself — no presentation code arrives with it.
local feedbackContract = require("./present/feedback")

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
	-- "fixed" | "content" | "hug" | "fill" | "percent" | "minMax" | "aspect" |
	-- "containerRelative"
	type: string,
	px: (number | Metric)?, -- fixed
	weight: number?, -- fill
	fraction: number?, -- percent | containerRelative
	offset: number?, -- percent: pixel adjustment applied before clamping
	min: (number | Metric)?, -- percent clamp / minMax
	preferred: (number | Metric)?, -- minMax
	max: (number | Metric)?, -- percent clamp / minMax
	ratio: number?, -- aspect
	-- containerRelative's paging form (§2.5); write it with UI.containerRelativeFrame
	count: number?,
	span: number?,
	spacing: number?,
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
	-- THIS child's own cross-axis alignment inside its stack parent's line
	-- (Roblox `ItemLineAlignment`). Outranks the container's `align` and a nested
	-- stack's own `align`, and unlike either it is legal on a LEAF
	lineAlign: Bound<string>?,
	-- the shrink pass (§2.4): `layoutPriority` is the tier (lowest gives way
	-- first, default 0), `shrinkWeight` the proportion inside a tier (default 0 =
	-- never shrinks, Roblox's `UIFlexMode.None`)
	layoutPriority: Bound<number>?,
	shrinkWeight: Bound<number>?,
	-- how many of its row's columns this cell covers inside a UI.GridRow (§2.2,
	-- default 1); read by nothing anywhere else
	gridSpan: Bound<number>?,
	alignH: Bound<string>?,
	alignV: Bound<string>?,
	shadow: Bound<any>?,
	gradient: Bound<any>?,
	corners: Bound<any>?,
	-- normalized UI.stroke data (bind a memo of UI.strokeData(…) to pulse it)
	stroke: Bound<any>?,
	-- paint-order override inside the parent's stacking scope; read once at mount
	zIndex: number?,
	-- SwiftUI's `hidden()`: keep the layout box, stop painting, leave focus order
	-- and stop taking taps — with the whole subtree. `UI.When` is the other answer
	-- (it removes the node and the space closes up)
	hidden: Bound<boolean>?,
	-- AUTHORED PRESENTATION (ADR-0026), paint-only and animatable. Neither moves
	-- layout, hit geometry or focus — the solver never sees them. A `scale`
	-- MULTIPLIES with any scale the framework is applying and a `rotation` (degrees,
	-- positive = clockwise) ADDS to any rotation it is applying; the composition
	-- happens at the one presentation write site, so neither is a second writer.
	scale: Bound<number>?,
	rotation: Bound<number>?,
	-- view lifetime, measured on the RENDER instance rather than the mounted node.
	-- `onAppear` fires once after the first solve that includes this node;
	-- `onDisappear` fires once after its render instance has been released
	onAppear: ((path: string) -> ())?,
	onDisappear: ((path: string) -> ())?,
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

export type ScreenSpec = BoxProps & ContainerProps & {
	gap: Bound<number | Metric>?,
	align: Bound<string>?,
	-- main-axis distribution of the leftover (§2.6): "start" (default) | "center" |
	-- "end" | "spaceBetween" | "spaceAround" | "spaceEvenly"
	distribute: Bound<string>?,
}
-- ...plus the one word `Screen` does not get: FLOW-WRAP (round 3 item A). A
-- wrapping stack is the SAME class in a second mode — Roblox's
-- `UIListLayout.Wraps` — so it is a prop rather than a class, and it is reactive,
-- so "wrap this row on a phone" is a re-solve and never a remount.
export type VStackSpec = ScreenSpec & { wrap: Bound<boolean>? }
export type HStackSpec = ScreenSpec & { wrap: Bound<boolean>? }
--[[ ONE SLOT OF A FIXED-PITCH WINDOWED LIST (`ZStack.virtualSlot`, 2026-08-13).
	`list` is the naming the finding quotes, `extent` the DECLARED px extent each
	slot was windowed at, `axis` the list's scroll axis ("y" default), and
	`contentFrom` the first child index that is CONTENT rather than the control's
	own furniture (1 by default). `newVirtualList` declares this for every row it
	builds; anything else that windows by `index x extent` may declare it too. ]]
export type VirtualSlot = {
	list: string,
	extent: number,
	axis: string?,
	contentFrom: number?,
}
export type ZStackSpec = BoxProps & ContainerProps & {
	canvasGroup: boolean?,
	-- authored subtree fade (ADR-0026): 1 = opaque, 0 = invisible-but-still-there.
	-- Declaring it IS declaring a fade group, so `canvasGroup` is implied
	opacity: Bound<number>?,
	virtualSlot: Bound<VirtualSlot>?,
}
export type AnchorSpec = BoxProps & ContainerProps
export type ScrollViewSpec = BoxProps & ContainerProps & {
	gap: Bound<number | Metric>?,
	axis: string?,
	onScrollWheel: ((path: string, delta: number, rectOf: (string) -> any) -> ())?,
	autoscroll: (boolean | { [string]: any })?,
	indicators: string?, -- "auto" (default) | "none" — carousel indicator opt-out
}
export type GridSpec = BoxProps & ContainerProps & {
	gap: Bound<number | Metric>?,
	rowGap: Bound<number | Metric>?,
	columns: Bound<number>?,
	minColumnWidth: Bound<number | string>?,
	itemSizing: Bound<string>?,
	-- "row" (default) | "column" — which way the cells wrap; see the schema
	flow: Bound<string>?,
}
-- A ROW OF A ROW GRID (§2.2). Its own box is the grid's business, so it accepts no
-- box properties at all — only its identity, its cells and the paint a full-width
-- band wants. (`Region` is the other class shaped this way, for the same reason.)
export type GridRowSpec = {
	id: string?,
	surface: Bound<string>?,
	shadow: Bound<any>?,
	gradient: Bound<any>?,
	corners: Bound<any>?,
	stroke: Bound<any>?,
	zIndex: number?,
	children: { Blueprint }?,
}

export type AdaptiveStackSpec = BoxProps & ContainerProps & {
	gap: Bound<number | Metric>?,
	align: Bound<string>?,
	distribute: Bound<string>?,
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
	-- "none" | "self" | "overflow": where the content a reduced form stops showing
	-- went (D7.1). Required with more than one form, refused with one
	recover: string?,
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
	-- authored fade (ADR-0026): 1 = opaque, 0 = invisible-but-still-there.
	-- Declaring it IS declaring a fade group, so `canvasGroup` is implied
	opacity: Bound<number>?,
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
	-- bounded secondary/identity text whose full value must stay reachable once it
	-- truncates (LTN-4). Construction-only, so never a `Bound<…>`
	disclose: boolean?,
	-- "auto": when this one-line text truncates, the presenter auto-scrolls its
	-- whole value through the box (director 2026-08-04; the plan's rung-4
	-- constraint list binds). Construction-only, like `disclose` above
	reveal: string?,
	-- one sentence about what this view does, shown on POINTER HOVER (after a
	-- dwell) and on keyboard/gamepad FOCUS. Nothing on touch, by specification —
	-- see blueprint_schema's HELP. Construction-only, like `disclose`
	help: string?,
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
	-- `prefer` is a MODIFIER rather than a content form — it names nothing to
	-- draw, so it rides alongside whichever of text/icon/image was declared (see
	-- `blueprint_schema.COMPACT_MODIFIERS` and api.md's Button section). Declared
	-- here because api.md documents it as public — without it a `--!strict`
	-- caller cannot write the very spelling the docs prescribe.
	compactLabel: (string | { text: string?, icon: string?, image: string?, prefer: boolean? })?,
	enabled: Bound<boolean>?,
	selected: Bound<boolean>?,
	focusable: Bound<boolean>?,
	traversalPriority: number?,
	surface: Bound<string>?,
	padding: Bound<Sides>?,
	textSize: Bound<number | TypeRole>?,
	-- one sentence about what this view does, shown on POINTER HOVER (after a
	-- dwell) and on keyboard/gamepad FOCUS. Nothing on touch, by specification —
	-- see blueprint_schema's HELP. Construction-only, like `disclose`
	help: string?,
	onActivate: ((path: string, meta: any?) -> ())?,
}

export type ToggleSpec = BoxProps & {
	label: Bound<string | number>,
	value: Bound<boolean>?,
	enabled: Bound<boolean>?,
	focusable: Bound<boolean>?,
	traversalPriority: number?,
	padding: Bound<Sides>?,
	textSize: Bound<number | TypeRole>?,
	disclose: boolean?,
	-- one sentence about what this view does, shown on POINTER HOVER (after a
	-- dwell) and on keyboard/gamepad FOCUS. Nothing on touch, by specification —
	-- see blueprint_schema's HELP. Construction-only, like `disclose`
	help: string?,
	onActivate: ((path: string, meta: any?) -> ())?,
}

export type TextFieldSpec = BoxProps & {
	text: Bound<string>?,
	placeholder: Bound<string>?,
	editing: Bound<boolean>?,
	enabled: Bound<boolean>?,
	focusable: Bound<boolean>?,
	traversalPriority: number?,
	padding: Bound<Sides>?,
	textSize: Bound<number | TypeRole>?,
	maxLength: Bound<number>?,
	keyboardType: Bound<string>?,
	-- one sentence about what this view does, shown on POINTER HOVER (after a
	-- dwell) and on keyboard/gamepad FOCUS. Nothing on touch, by specification —
	-- see blueprint_schema's HELP. Construction-only, like `disclose`
	help: string?,
	onTextChanged: ((text: string) -> ())?,
	onFocusGained: ((path: string) -> ())?,
	onFocusLost: ((reason: string) -> ())?,
}

export type GripSpec = BoxProps & PointerHandlers & {
	cursorHint: Bound<string>?,
	focusable: Bound<boolean>?,
	traversalPriority: number?,
	focusVisual: string?,
}

-- the engine-content box (ViewportFrame adoption). The whole authored surface is
-- the box + its plate + its one paint channel; the CONTENT of a stage (camera,
-- lighting, models) rides `controller.stageHost(path)`, which is the only place
-- engine types exist.
export type StageSpec = BoxProps & {
	surface: Bound<string>?,
	tint: Bound<any>?,
}

-- the FOREIGN box (ADR-0034): Stage's 2-D sibling. The authored surface is the
-- box and the plate behind it and NOTHING else — no engine props, deliberately —
-- and what goes in it rides `controller.foreignHost(path).adopt(instance)`, which
-- is the only place a caller's Instance is ever mentioned.
export type ForeignSpec = BoxProps & {
	surface: Bound<string>?,
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

-- `thenView`'s `branchScope` is the BRANCH's ownership scope, disposed when the
-- branch closes — the symmetric twin of `ForEachSpec.row`'s `itemScope`. Own a
-- MotionValue, a timer or an async handle on it rather than hoisting it to the
-- enclosing scope, where it would outlive the panel (react-lua-comparison.md §5
-- rank 2). Ignoring the argument still typechecks: a zero-parameter
-- `() -> Blueprint` is assignable to a one-parameter function type in Luau, so
-- no existing factory changes. There is no `elseView` — src/mount.luau's
-- `mountWhen` header carries that refusal and its reason.
export type WhenSpec = {
	id: string?,
	condition: Readable<boolean>,
	thenView: (branchScope: any) -> Blueprint,
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

-- FROZEN, because it is PUBLIC (api-architecture-consistency F-34 / ledger
-- BP-F17). `UI.PROP_DIRTY` is the live map `mount.luau` reads to decide which
-- dirty classes a reactive prop schedules, so an unfrozen handle on it is a
-- mutable handle on mount-time subscription behaviour. mount only ever reads it.
-- The innermost arrays come from the schema and are already frozen, so the walk
-- checks before freezing (`table.freeze` throws on a frozen table).
for _, byProp in PROP_DIRTY do
	for _, classes in byProp do
		if not table.isfrozen(classes) then
			table.freeze(classes)
		end
	end
	table.freeze(byProp)
end
blueprint.PROP_DIRTY = table.freeze(PROP_DIRTY)

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

--[[ DETERMINISTIC DICTIONARY ITERATION (fusion-comparison.md §5 gap G-3).

	`UI.ForEach` takes an ARRAY, so a consumer holding a dictionary flattens it
	first — and the obvious flatten is wrong. Luau's `pairs` order is a function of
	the table's hash layout, and the hash layout is a function of its CONSTRUCTION
	HISTORY: measured 2026-08-15, four constructions of the same twelve-key map
	iterate four different ways. The row order of a leaderboard would then depend
	on the order the players happened to join. A framework that guarantees
	deterministic dumps must not hand its consumers a one-liner that breaks
	determinism inside their own screen, so the flatten ships here, once.

	AND IT IS NOT A LUNE ARTEFACT. Confirmed the same day in ROBLOX'S OWN LUAU VM,
	in a live Studio Play session: the same twelve player ids inserted ascending
	and descending gave `player_1021,player_1014,…` and `player_1070,player_1014,…`
	respectively, while `sortedEntries` gave one order for both. That is the fact
	this helper exists for — a headless-only measurement would have left open the
	reading that the engine's VM is stabler than the test harness's, and it is not.

	IT IS PURE, AND THAT IS THE WHOLE DESIGN. The gap note sketched it returning a
	`Readable`, but building one would force the helper to take a core AND a scope
	it has no other use for, to duplicate the `core:memo` a consumer already writes
	for every derived value. Rung 4 of the simplicity ladder: the reactive half is
	`core:memo(function(use) return UI.sortedEntries(use(scores)) end)`, which is
	the idiom already in the file.

	`compare` ORDERS KEYS, NOT ENTRIES, and that is a guarantee rather than an
	omission. Keys are unique, so any strict order over them is a TOTAL order and
	the result is deterministic whatever comparator arrives. Had it ordered
	entries, a caller sorting a leaderboard by score would hit ties, `table.sort`
	is not stable, and the tie order would fall back to the `pairs` order this
	helper exists to remove — the same defect wearing the helper's name. To rank by
	value, sort the returned array yourself with an explicit key tiebreak.

	Not a blueprint class: the construction ladder's own question ("does it need
	layout, paint or input semantics an existing class cannot compose?") says
	helper. A `UI.ForPairs` would be a second structural region with the first
	one's semantics. ]]
-- numbers before strings, because `1 < "a"` is an ERROR in Luau rather than an
-- order — a default of just `a < b` would throw on a mixed map instead of
-- ordering it. Any type absent here has no default order and is refused below.
local KEY_TYPE_RANK: { [string]: number } = { number = 1, string = 2 }

local function defaultKeyOrder(a: any, b: any): boolean
	local rankA, rankB = KEY_TYPE_RANK[type(a)], KEY_TYPE_RANK[type(b)]
	if rankA ~= rankB then
		return rankA < rankB
	end
	return a < b
end

export type Entry<K, V> = { key: K, value: V }

function blueprint.sortedEntries<K, V>(dict: { [K]: V }, compare: ((a: K, b: K) -> boolean)?): { Entry<K, V> }
	if type(dict) ~= "table" then
		error(
			`LuauUI sortedEntries: expected a dictionary table, got '{typeof(dict)}'. It flattens a map into the array UI.ForEach takes.`,
			0
		)
	end
	if compare ~= nil and type(compare) ~= "function" then
		error(
			`LuauUI sortedEntries: 'compare' must be a function (a: key, b: key) -> boolean, got '{typeof(compare)}'.`,
			0
		)
	end
	local entries: { Entry<K, V> } = {}
	for key, value in dict do
		if compare == nil and KEY_TYPE_RANK[type(key)] == nil then
			-- REFUSED AT CONSTRUCTION, naming the alternative. Ordering these by
			-- `tostring` would be ordering by ADDRESS, which is exactly the
			-- run-to-run instability the helper exists to remove — a silent wrong
			-- answer is worse here than a loud refusal.
			error(
				`LuauUI sortedEntries: a key of type '{typeof(key)}' has no default order — pass 'compare', e.g. sortedEntries(dict, function(a, b) return a.id < b.id end). It must be a strict order on KEYS; string and number keys are ordered for you.`,
				0
			)
		end
		table.insert(entries, { key = key, value = value })
	end
	local order = compare or defaultKeyOrder
	table.sort(entries, function(a: Entry<K, V>, b: Entry<K, V>): boolean
		return order(a.key, b.key)
	end)
	return entries
end

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

-- MODIFIER ATTRIBUTION (api-architecture-consistency F-7 / ledger BP-F4).
-- `withProps` runs a modifier's writes through the SAME validation a
-- constructor uses, which is right — but the message it produced named only the
-- class and the INTERNAL prop the modifier had chosen. `UI.alignment(when,
-- "center")` reported *"LuauUI UI.When: unknown property 'alignH'"*: a property
-- the author never typed, on a class they may not have written, followed by
-- that class's valid properties — none of which is the fix. The two helpers
-- below therefore take the modifier the author actually called, and every
-- UI.* modifier passes its own name. A DIRECT constructor error passes nil and
-- is byte-identical to what it always was.
local function unknownPropError(class: string, key: string, modifier: string?): string
	-- A REFUSED CAPABILITY, NAMED AS ONE (ADR-0029). `opacity`/`canvasGroup` are
	-- absent from this class because the framework declined them, not because the
	-- schema forgot: the suggester and the valid list are the wrong answer, and
	-- the right one is a spelling. Everything else falls through unchanged.
	local refusal = schema.refusal(class, key)
	if refusal ~= nil then
		local head = if modifier == nil then `LuauUI UI.{class}:` else `LuauUI UI.{modifier} on UI.{class}:`
		return `{head} '{key}' is REFUSED on UI.{class}, not missing. {refusal}`
	end
	local suggestions = schema.suggest(class, key)
	local msg = if modifier == nil
		then `LuauUI UI.{class}: unknown property '{key}'.`
		else `LuauUI UI.{modifier} on UI.{class}: UI.{class} has no property '{key}'.`
	if #suggestions > 0 then
		msg ..= ` Did you mean {quoteList(suggestions)}?`
	end
	msg ..= ` Valid properties: {table.concat(schema.propNames(class), ", ")}.`
	return msg
end

-- "LuauUI UI.Text.text" for a constructor; "LuauUI UI.frame on UI.When:
-- UI.When.height" when a modifier wrote it
local function propErrorHead(class: string, key: string, modifier: string?): string
	if modifier == nil then
		return `LuauUI UI.{class}.{key}`
	end
	return `LuauUI UI.{modifier} on UI.{class}: UI.{class}.{key}`
end

local function validateProp(class: string, key: string, value: any, propSpec: schema.PropSpec, modifier: string?)
	local head = propErrorHead(class, key, modifier)
	local dep = propSpec.deprecated
	if dep ~= nil then
		error(
			`{head} is not supported (deprecated {dep.since}, removable in {dep.removeNoEarlierThan}). `
				.. `Use {dep.replacement}. {dep.note or ""}`,
			0
		)
	end
	if isReadable(value) then
		if not propSpec.reactive then
			error(
				`{head} does not accept a Signal/Memo (it is read once at mount). `
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
			`{head} expects {expected}, got {typeof(value)}`
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
	-- `overflow = "clip"` IS a clip host (api-architecture-consistency F-19 /
	-- ledger BP-F11). `overflow` was accepted on nine container classes and drove
	-- nothing at all — a second public spelling of `clipChildren` that did not do
	-- the thing it names. It is normalized HERE, at construction, by the same
	-- mechanism `UI.ScrollView` already uses to default the flag, so the solver
	-- and the renderer are untouched. An explicitly authored `clipChildren` (of
	-- either polarity) always wins, and every other overflow value stays what it
	-- has always been: declared intent, read by the overflow diagnostic.
	--
	-- A BOUND `overflow` implies nothing, deliberately: `clipChildren` is
	-- construction-only (it decides whether the adapter mounts a clip host), so a
	-- value that can change later cannot drive it.
	if props.overflow == "clip" and props.clipChildren == nil and known.clipChildren ~= nil then
		props.clipChildren = true
	end
	-- `align = "stretch"` ON A WRAPPING STACK MEANS TWO THINGS, so it means none
	-- (round 3 item A). On a single-line stack the word has exactly one reading —
	-- "a child fills its line on the cross axis" — and on a wrapping one it could
	-- equally be "the LINES grow to fill the container". One word doing two jobs is
	-- the ambiguity `lineAlign` was created to end (§2.1), so it is refused rather
	-- than picked for the author.
	--
	-- THIS CATCHES THE LITERAL CASE ONLY, and that is the whole of what a
	-- construction check can honestly claim: both props are reactive, so a value
	-- that only a solve can know is refused by the solver's own wrapping branch,
	-- with the same message. Two seams, one rule; the equality below cannot see a
	-- bound value and does not pretend to.
	if props.wrap == true and props.align == "stretch" then
		error(
			`LuauUI UI.{class}: \`align = "stretch"\` has two readings on a wrapping stack — "each child `
				.. `fills its line" and "the lines fill the container" — so it is refused. Put `
				.. '`lineAlign = "stretch"` on the children that should fill their line, and use `align` '
				.. "(start|center|end) for where the block of lines sits.",
			0
		)
	end
	-- IMMUTABLE ALL THE WAY DOWN (api-architecture-consistency F-22 / ledger
	-- BP-F18). api.md says "blueprints are immutable plain tables" and the whole
	-- modifier-returns-a-new-blueprint contract rests on it, but the freeze was
	-- one level deep: a shared template reused across rows could be mutated in
	-- place through `bp.props` or `bp.children`. Every internal builder composes
	-- its table BEFORE make (mount copies into its own node, the modifiers clone,
	-- Composition/Region only read), so freezing both is a pure tightening.
	local node: Blueprint = {
		class = class,
		id = id,
		props = table.freeze(props),
		children = if children ~= nil then table.freeze(children) else nil,
	}
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
-- GridRow (§2.2): one row of a ROW grid. A `UI.Grid` whose children are all
-- `UI.GridRow` switches to row mode — column n is as wide as the widest natural cell
-- in column n across every row, rather than the one shared width the flow grid gives
-- every column. A Grid with NO GridRow child is the flow grid it has always been; a
-- MIX is an authoring error, reported by the solve.
function blueprint.GridRow(spec: GridRowSpec?): Blueprint
	return make("GridRow", (spec :: any) or {})
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
--[[ THE ONE SET THAT MEANS "A PLAYER CAN REACH THIS" — `focus_map.FOCUSABLE` plus
	the Grip's opt-in, which is the same rule the presenter walks to build focus
	order. Two consumers: `UI.Button` refuses one INSIDE its content (a second focus
	site on one activation surface), and `UI.Region` requires one in the last form of
	a `recover = "self"` region (D7.2). Same set, opposite polarity, one definition —
	the day a fourth control becomes focusable both rules learn it together. ]]
local CONTENT_FOCUSABLE: { [string]: boolean } = { Button = true, Toggle = true, TextField = true }

local function isFocusable(node: Blueprint): boolean
	if CONTENT_FOCUSABLE[node.class] and node.props.focusable ~= false then
		return true
	end
	return node.class == "Grip" and node.props.focusable == true
end

local function containsFocusable(node: Blueprint): boolean
	if isFocusable(node) then
		return true
	end
	for _, child in node.children or {} do
		if containsFocusable(child) then
			return true
		end
	end
	return false
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
	--[[ D7.2 — A TERMINAL FORM ON A "SELF" ROUTE MUST BE ACTIONABLE.
		`recover = "self"` says "the reduced form IS the route: the player taps what is
		left to get the rest". If the last form holds nothing focusable then there is
		nothing to tap, and the declaration has promised a route that does not exist —
		which is strictly worse than "overflow", because it also tells the overflow
		surface not to list this region. Measured on the HUD showcase: `TasksChip` was
		a glass pill wrapping two `UI.Text`, so three tasks and their rewards were
		gone and the thing left behind could not be touched.

		THE WALK IS OF THE DECLARED TREE. Content a `UI.When` or `UI.ForEach` produces
		lazily is not visible here (their views are functions), so a `self` route must
		declare its control rather than manufacture it — which is the right constraint
		anyway: a route that exists only in some states is not a route. ]]
	--[[ `recover` IS REFUSED ON A ONE-FORM REGION, and this is the only place that
		can say so: the count reaching the solver is the count of MOUNTED forms, and a
		form behind a `UI.When` is absent while its condition reads false — so the
		pure normalizer would reject a good declaration on the frame a condition
		flipped. Here the count is the DECLARED one, which is what the rule is about.
		(The other half, "required with more than one form", is the normalizer's: it
		has to hold for a declaration driven straight from a test as well.) ]]
	if spec.recover ~= nil and #bp.children == 1 then
		error(
			`LuauUI UI.Region '{bp.id}' declares one form, so 'recover' has nothing to describe — a `
				.. "single-form region can only stop showing content by being DROPPED, and a dropped region "
				.. "has no form left to be its own route, so the screen's overflow surface is the only "
				.. "possible answer. `mayDrop` is already that declaration",
			0
		)
	end
	--[[ EVERY REDUCED FORM, NOT ONLY THE LAST ONE. The ladder can stop at ANY rung
		— a three-form region resolves to form 2 on plenty of screens — so checking
		only the terminal form leaves a dead end on exactly the middle-sized devices
		nobody fixtures. Form 1 is the richest and is exempt by definition: it is not
		showing less than anything. ]]
	if spec.recover == "self" then
		for i = 2, #bp.children do
			local form = bp.children[i]
			if not containsFocusable(form) then
				error(
					`LuauUI UI.Region '{bp.id}' declares recover = "self", so every form below the richest is `
						.. `the route to what that form stopped showing — but form {i} of {#bp.children} (a `
						.. `UI.{form.class}) contains nothing focusable, so there is nothing for a player to `
						.. "activate while it is the one on screen. Put a UI.Button (or Toggle/TextField, or a "
						.. 'focusable Grip) in it, or declare recover = "overflow" and let the screen\'s '
						.. "overflow surface carry it. A route nobody can reach is the defect wearing the "
						.. "fix's clothes",
					0
				)
			end
		end
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
			recover = child.props.recover,
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
--
-- The SET is `CONTENT_FOCUSABLE` above (shared with UI.Region's D7.2 rule); this
-- refusal reads it directly rather than through `isFocusable`, because a
-- `focusable = false` Button is still a second activation surface inside a Button
-- even though it is out of focus order.
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
-- Stage: the engine-content box. A leaf like Box (it measures 0x0 without dims);
-- the adapter materializes it as a ViewportFrame and owns the WorldModel/Camera
-- behind `controller.stageHost`.
-- Foreign: the box for a GuiObject LuauUI does not wrap (ADR-0034). A leaf like
-- Box and Stage (it measures 0x0 without dims); the adapter materializes it as a
-- CLIPPING Frame and makes exactly one claim on what the caller adopts into it —
-- `Parent`, on the `host` authority — behind `controller.foreignHost`.
function blueprint.Foreign(spec: ForeignSpec): Blueprint
	return make("Foreign", spec)
end
function blueprint.Stage(spec: StageSpec): Blueprint
	return make("Stage", spec)
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
-- `modifier` is the UI.* name the AUTHOR typed (F-7). Every caller below passes
-- its own, so an unknown-prop or wrong-type refusal names the call site as well
-- as the class it landed on.
local function withProps(bp: Blueprint, extra: { [string]: any }, modifier: string?): Blueprint
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
			error(unknownPropError(bp.class, k, modifier), 0)
		end
		validateProp(bp.class, k, v, propSpec, modifier)
	end
	local props = table.clone(bp.props)
	for k, v in extra do
		props[k] = v
	end
	-- frozen like `make`'s (F-22): a modifier's output is a blueprint, and a
	-- blueprint is immutable all the way down
	return table.freeze({
		class = bp.class,
		id = bp.id,
		props = table.freeze(props),
		children = bp.children,
		meta = bp.meta,
	}) :: any
end

-- UI.shadow(bp, presetNameOrParams, style?) — UIShadow-backed drop shadow
function blueprint.shadow(bp: Blueprint, spec: any, style: any?): Blueprint
	return withProps(bp, { shadow = stylingLib.normalizeShadow(spec, style) }, "shadow")
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
	return withProps(bp, { gradient = stylingLib.normalizeGradient(spec, style) }, "gradient")
end

-- UI.corners(bp, radius|token|{radius}|{topLeft..bottomRight}, style?) —
-- per-corner UICorner rounding; exactly ONE form per node
function blueprint.corners(bp: Blueprint, spec: any, style: any?): Blueprint
	return withProps(bp, { corners = stylingLib.normalizeCorners(spec, style) }, "corners")
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
	return withProps(bp, { stroke = stylingLib.normalizeStroke(spec, style) }, "stroke")
end

-- UI.strokeData(spec, style?) — the same normalization WITHOUT a blueprint, for
-- the reactive idiom. Normalized style data is read once, so a pulse is a pulsing
-- PROP rather than a Signal buried inside the data:
--   stroke = core:memo(function() return UI.strokeData({ thickness = pulse:get() }) end)
function blueprint.strokeData(spec: any, style: any?): any
	return stylingLib.normalizeStroke(spec, style)
end

-- ...AND THE OTHER THREE (ledger BP-F7, disposition FIX F-39). The pulse idiom
-- above is documented as the way to animate authored paint, and it was reachable
-- for exactly one of the four style modifiers: `shadow`, `gradient` and `corners`
-- are all normalized-data props on the same schema, all read once by the adapter,
-- and all animatable in principle — but with no data producer the only way to
-- pulse a shadow was to rebuild the blueprint, which is a remount for a paint
-- change. Each is the SAME normalizer its modifier uses, so the two forms cannot
-- drift and a value legal in one is legal in the other.
--
-- `gradientData` deliberately does NOT run the gradientable wall: there is no
-- blueprint here to judge, and the wall still stands where the data is APPLIED
-- (UI.gradient / UI.styleGroup, and the schema's own prop check on bind).
function blueprint.shadowData(spec: any, style: any?): any
	return stylingLib.normalizeShadow(spec, style)
end

function blueprint.gradientData(spec: any, style: any?): any
	return stylingLib.normalizeGradient(spec, style)
end

function blueprint.cornersData(spec: any, style: any?): any
	return stylingLib.normalizeCorners(spec, style)
end

-- ===== drag and drop (ADR-0022 Decision 5; SF-D1/SF-D5) =====================
-- UI.draggable(bp, { payload, dragMotion?, proxy?, onCommitProxy?, grabAnchor?,
-- declineTouch?, recycled?, promotionPx? }) and UI.dropTarget(bp, { accepts?, onDrop,
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

-- ===== sensory feedback (round 2 §3.3; the control form, round 3) ===========
-- UI.sensoryFeedback(bp, { trigger, event }) — SwiftUI's `.sensoryFeedback(_:
-- trigger:)`. When `trigger` changes, `{ type = event, path = <this node> }` is
-- emitted on the presenter's feedback bus, synchronously, in the write that
-- moved it.
--
-- UI.sensoryFeedback(bp, { activation = "commit" }) — the PER-CONTROL form,
-- which SwiftUI has no equivalent of. It names what THIS control's own press
-- feels like, replacing the generic `activate` the presenter would otherwise
-- emit, and it CASCADES: declared on a container it reaches every control
-- inside, which is what lets it serve the ten composite controls without one
-- line of per-control plumbing. `activation = "none"` is a control that is
-- deliberately unfelt. Resolution lives in `mount.luau`; the vocabulary and the
-- reasoning live in `src/present/feedback.luau`.
--
-- LuauUI STILL PLAYS NOTHING (`src/present/feedback.luau:4-5`). SwiftUI's
-- modifier names a HAPTIC (`.impact`, `.selection`); this one names a semantic
-- verb from the closed twelve, and what — if anything — is played is the
-- subscriber's ruling. `src/client/haptics.luau` is one opt-in, default-off
-- subscriber; a game that wants a sound instead subscribes the same bus.
--
-- Like the drag declarations it rides `meta` rather than the public prop bag
-- (see drag_contract's "WHY `meta` AND NOT A PROP"), and for the same reason it
-- is refused on a structural region: `When`/`ForEach`/`ErrorBoundary` mount no
-- node of their own, `mount` copies `meta` only onto ordinary nodes, and an
-- accepted-and-inert declaration is the defect class this boundary removes.
local SENSORY_STRUCTURAL: { [string]: boolean } = { When = true, ForEach = true, ErrorBoundary = true }

function blueprint.sensoryFeedback(bp: Blueprint, spec: feedbackContract.SensoryFeedbackSpec): Blueprint
	if type(bp) ~= "table" or type(bp.class) ~= "string" then
		error("LuauUI UI.sensoryFeedback: the first argument must be a blueprint", 0)
	end
	if SENSORY_STRUCTURAL[bp.class] then
		error(
			`LuauUI UI.sensoryFeedback cannot be applied to a UI.{bp.class} — a structural region mounts no node `
				.. "of its own, so the declaration would be accepted and never emit anything. Fix: put it on the "
				.. `blueprint the region returns, or on a UI.Box/UI.VStack around the UI.{bp.class}.`,
			0
		)
	end
	local decl = feedbackContract.declaration(spec)
	local meta = if type(bp.meta) == "table" then table.clone(bp.meta) else {}
	local declared: { any } = {}
	for _, existing in (meta[feedbackContract.SENSORY_PROP] or {}) :: { any } do
		table.insert(declared, existing)
	end
	-- ONE CONTROL, ONE SENSATION. Change-form declarations compose (two triggers
	-- are two independent causes), but a node cannot have two answers to "what
	-- does pressing this feel like" — a silent last-writer-wins here would make
	-- the two orderings of the same two modifiers produce different sensations.
	if decl.activation ~= nil then
		local existing = feedbackContract.activationIn(declared)
		if existing ~= nil then
			error(
				`LuauUI UI.sensoryFeedback: this blueprint already declares activation = '{existing}', so `
					.. `'{decl.activation}' would silently replace it. A control has ONE activation sensation — `
					.. "declare it once, or put the second one on a different node.",
				0
			)
		end
	end
	table.insert(declared, decl)
	meta[feedbackContract.SENSORY_PROP] = table.freeze(declared)
	return table.freeze({
		class = bp.class,
		id = bp.id,
		props = bp.props,
		children = bp.children,
		meta = table.freeze(meta),
	}) :: any
end

-- UI.styleGroup({ shadow?, gradient?, corners?, stroke? }, blueprints, style?) —
-- Group semantics: the modifier set applies to EACH contained element.
--
-- THE SET IS THE WHOLE FAMILY, AND IT IS CLOSED (api-architecture-consistency
-- F-4 / ledger BP-F1). This used to read three keys and validate none, so
-- `stroke` — the fourth member of the style-modifier family — was silently
-- dropped: an author reaching for the collection form of `UI.stroke` got no
-- border on any element, with no error, while the singular form worked, so the
-- bug read as a theme problem. An unknown key was dropped the same way. Both are
-- now refused at the call site, naming the modifier and the legal set.
local STYLE_GROUP_KEYS: { string } = { "corners", "gradient", "shadow", "stroke" }

function blueprint.styleGroup(
	spec: { shadow: any?, corners: any?, gradient: any?, stroke: any? },
	blueprints: { Blueprint },
	style: any?
): { Blueprint }
	if type(spec) ~= "table" then
		error(`LuauUI UI.styleGroup: expected a spec table first, got {typeof(spec)}`, 0)
	end
	local legal: { [string]: boolean } = {}
	for _, key in STYLE_GROUP_KEYS do
		legal[key] = true
	end
	for key in spec :: any do
		if legal[key] ~= true then
			error(
				`LuauUI UI.styleGroup: unknown spec key '{tostring(key)}'. `
					.. `Valid keys: {table.concat(STYLE_GROUP_KEYS, ", ")}.`,
				0
			)
		end
	end
	local extra: { [string]: any } = {}
	if spec.stroke ~= nil then
		extra.stroke = stylingLib.normalizeStroke(spec.stroke, style)
	end
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
		table.insert(out, withProps(bp, extra, "styleGroup"))
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
	return withProps(bp, extra, "frame")
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
	return withProps(bp, { padding = sides }, "padding")
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
	return withProps(bp, extra, "offset")
end

-- UI.containerRelativeFrame(bp, spec) — size one axis against the nearest
-- CONTAINER, not against the parent (§2.5).
--
-- THE WHOLE DISTINCTION IS THE RULER. `percent` already means "a fraction of what
-- my parent offered me", and that is the wrong number for the two shapes SwiftUI
-- introduced this for: a card that should be half the SCROLLER's viewport however
-- many wrappers sit between it and the scroller, and a carousel whose pages are
-- exactly a third of the viewport each. The container is the nearest ancestor that
-- owns a viewport — a `UI.ScrollView`'s content viewport, else the surface root —
-- so inserting a padded VStack between the page and the scroller does not resize
-- the page, which with `percent` it would.
--
-- Two forms, and exactly one of them per call:
--   { axis, fraction = 0.5 }                       half the container
--   { axis, count = 3, span = 1, spacing = 8 }     SwiftUI's paging arithmetic,
--       size = (viewport - spacing x (count - 1)) / count x span + spacing x (span - 1)
--
-- A SPEC TABLE, not positional arguments: three-or-more fields is the constitution's
-- own rule for the shape a modifier takes (§16 E-18), and the closed key set means a
-- misspelled `fractoin` is an error at the call site rather than a silent full-width
-- box. `spacing` is a px number — it is the gutter between PAGES, which is the
-- author's own paging arithmetic and not a theme-owned space step.
local CRF_FIELDS: { [string]: boolean } = {
	axis = true,
	fraction = true,
	count = true,
	span = true,
	spacing = true,
}
local CRF_AXES: { [string]: string } = { horizontal = "width", vertical = "height" }
export type ContainerRelativeFrameSpec = {
	axis: string, -- "horizontal" | "vertical"
	fraction: number?, -- the fractional form
	count: number?, -- the paging form: how many pages fill the container
	span: number?, -- ...and how many of them this view covers (default 1)
	spacing: number?, -- ...and the gutter between them (default 0)
}
function blueprint.containerRelativeFrame(bp: Blueprint, spec: ContainerRelativeFrameSpec): Blueprint
	if type(spec) ~= "table" then
		error(`LuauUI UI.containerRelativeFrame: expected a spec table, got {typeof(spec)}`, 0)
	end
	for k in spec :: any do
		if not CRF_FIELDS[k] then
			local names = {}
			for f in CRF_FIELDS do
				table.insert(names, f)
			end
			table.sort(names)
			error(
				`LuauUI UI.containerRelativeFrame: unknown field '{tostring(k)}'. Valid fields: {table.concat(
					names,
					", "
				)}.`,
				0
			)
		end
	end
	local prop = CRF_AXES[spec.axis :: any]
	if prop == nil then
		error(
			`LuauUI UI.containerRelativeFrame: axis must be "horizontal" or "vertical" (got {tostring(spec.axis)})`,
			0
		)
	end
	local function positive(name: string, value: any)
		if type(value) ~= "number" or value ~= value or value <= 0 then
			error(`LuauUI UI.containerRelativeFrame: {name} must be a positive number (got {tostring(value)})`, 0)
		end
	end
	-- ONE FORM PER CALL. `fraction` and `count` are two different rulers for the same
	-- axis, and a call carrying both would have to pick one silently.
	if spec.fraction ~= nil then
		if spec.count ~= nil or spec.span ~= nil or spec.spacing ~= nil then
			error(
				"LuauUI UI.containerRelativeFrame: `fraction` is the fractional form and `count`/`span`/"
					.. "`spacing` are the paging form — pass one form or the other, not both.",
				0
			)
		end
		positive("fraction", spec.fraction)
	elseif spec.count ~= nil then
		positive("count", spec.count)
		if spec.count ~= math.floor(spec.count :: number) then
			error(`LuauUI UI.containerRelativeFrame: count must be a whole number (got {tostring(spec.count)})`, 0)
		end
		if spec.span ~= nil then
			positive("span", spec.span)
			if spec.span ~= math.floor(spec.span :: number) then
				error(`LuauUI UI.containerRelativeFrame: span must be a whole number (got {tostring(spec.span)})`, 0)
			end
			if (spec.span :: number) > (spec.count :: number) then
				error(
					`LuauUI UI.containerRelativeFrame: span ({spec.span}) cannot exceed count ({spec.count}) — a `
						.. "view cannot cover more pages than the container holds.",
					0
				)
			end
		end
		if spec.spacing ~= nil and (type(spec.spacing) ~= "number" or spec.spacing ~= spec.spacing) then
			error(`LuauUI UI.containerRelativeFrame: spacing must be a number (got {tostring(spec.spacing)})`, 0)
		end
	else
		error(
			"LuauUI UI.containerRelativeFrame: pass either `fraction` (a share of the container) or `count` "
				.. "(the paging form, with optional `span` and `spacing`).",
			0
		)
	end
	return withProps(bp, {
		[prop] = {
			type = "containerRelative",
			fraction = spec.fraction,
			count = spec.count,
			span = spec.span,
			spacing = spec.spacing,
		},
	}, "containerRelativeFrame")
end

-- UI.aspectRatio(bp, ratio) — derive the unconstrained axis from the other.
function blueprint.aspectRatio(bp: Blueprint, ratio: number): Blueprint
	if type(ratio) ~= "number" or ratio ~= ratio or ratio <= 0 then
		error(`LuauUI UI.aspectRatio: ratio must be a positive number (got {tostring(ratio)})`, 0)
	end
	-- the solver's `aspect` dim resolves against the resolved other axis; applying
	-- it to HEIGHT is the common case (a 16:9 media box with a known width)
	return withProps(bp, { height = { type = "aspect", ratio = ratio } }, "aspectRatio")
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
	return withProps(bp, extra, "alignment")
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
		-- `meta` RIDES ALONG (api-architecture-consistency F-3 / ledger BP-F3).
		-- This rebuild is the only place in the layer that reconstructed a frozen
		-- node without carrying the framework metadata channel, so a drag
		-- declaration or an input contribution on the backing plate vanished
		-- silently — and only in the COMMON case, the one where the author gave the
		-- plate no dimensions of its own. `withProps` has always carried it; so
		-- does this now.
		backing = table.freeze({
			class = content.class,
			id = content.id,
			props = table.freeze(props),
			children = content.children,
			meta = content.meta,
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
