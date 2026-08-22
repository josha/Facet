--!strict
--[[ THE PROP CHANNEL MANIFEST — which engine-facing prop rides which seam.

	Extracted from `src/render/renderer.luau` on 2026-08-17 for the 200,000-char
	`Source` WRITE cap: over that line a module silently stops live-syncing into
	an open Studio session, so a live check against it tests the place file rather
	than the edits on disk (docs/lessons/the-200k-source-cap-is-on-writing-not-
	loading.md). The renderer was 350 chars from it and three release-candidate
	fixes had to land inside it.

	WHY THIS IS THE SEAM, and not a slice taken because it was the right size.
	Everything here is MODULE-LEVEL DATA plus one pure predicate over that data:
	four tables, two load-time completeness assertions, and `emitsBinding`. Not
	one line reads a `renderer.attach` upvalue — no handle map, no adapter, no
	solver state — so the extraction is one-way by construction, the same test
	`layout_node` and `presentation_channel` were taken by. Nothing changed:
	the four public names are re-exported from `renderer` exactly where every
	caller already looks (`renderer.BINDING_PROPS`, `renderer.STYLE_PROPS`,
	`renderer.EMITTED_PROPS`, `renderer.DIRECT_PROPS`), and `STYLE_PROP_ORDER`
	and `BINDING_PROP_CLASSES` stay private to the render layer exactly as they
	were — `tools/lune/check_prop_parity` reads the latter as TEXT, and its
	source list names this file.
]]

local prop_channels = {}

-- prop -> adapter prop authority mapping for dynamic writes
local BINDING_PROPS: { [string]: boolean } = {
	text = true,
	value = true,
	enabled = true,
	-- input-sinking containers (modal panels): the engine Active flag. It used
	-- to be written only at creation by a bespoke branch, so a REACTIVE `active`
	-- dirtied "semantics" and the refresh loop then dropped it (Milestone 0).
	active = true,
	image = true,
	label = true,
	selected = true,
	cursorHint = true,
	-- TextField (§17 Phase 5): data-driven text-entry props
	placeholder = true,
	editing = true,
	maxLength = true,
	keyboardType = true,
	-- Path (the native substrate): reactive stroke geometry/config — a bound
	-- progress arc updates points as a paint-only prop write (never a re-solve)
	points = true,
	thickness = true,
	closed = true,
	-- THE CONTINUOUS-COLOUR CHANNEL (ADR-0022 Decision 6). Binding rather than
	-- style because the VALUE is data — a blend along a signal, an identity hue —
	-- which is exactly what a selector cannot express. It is applied LAST at
	-- creation (see ensureTree) because it composes over whatever the style props
	-- settled on.
	tint = true,
}

-- style-authority hints (§7.3): surface/text roles + the Phase 4 shadow and
-- corner modifier data. These are written at creation AND on every reactive
-- change. The strict-authoring milestone fixed the second
-- half: a bound `surface`/`role` dirtied "paint" and the refresh loop then
-- dropped it because only BINDING_PROPS were re-applied, so a reactive style
-- hint scheduled work the adapter never performed — the same silent-failure
-- class as Text.color.
local STYLE_PROPS: { [string]: boolean } = {
	surface = true,
	role = true,
	shadow = true,
	-- the per-view gradient modifier: one bespoke adapter-owned UIGradient,
	-- applied at creation and re-applied reactively like every other style prop
	gradient = true,
	corners = true,
	-- horizontal text alignment: paint-only, and it must survive a reactive
	-- change like any other style hint
	textAlign = true,
	-- the circle Button (feature round 2026-07-26): the disc's chrome. Native
	-- mode turns it into the `facet-shape-circle` tag the sheet's phantom
	-- ::UICorner/::UIStroke rules key on; fallback mode re-radiuses the real
	-- UICorner the adapter already built.
	shape = true,
	-- its semantic icon content: a NAME the adapter resolves through the R4
	-- machinery, never an asset id
	icon = true,
	-- the compact representation this button wears when its full label does not
	-- fit. The DECLARATION is style (it selects a representation, and in its icon
	-- form a theme-owned picture); the drawn string still rides the label seam.
	compactLabel = true,
	-- the authored border (ADR-0022 Decision 6): normalized UIStroke data, exactly
	-- the shape and lifecycle `gradient` has — ONE bespoke child, reused
	stroke = true,
	-- how an authored picture fills its box. Style for the same reason `shape` is:
	-- the solved rect does not move, and the single engine write is what makes the
	-- picture fit the box the solver already sized.
	scaleMode = true,
}

-- Creation-time application order. This used to be a SECOND hardcoded list
-- inline in ensureTree, so adding a style prop to STYLE_PROPS above wired it for
-- reactive updates but silently never applied it at creation — `textAlign` was
-- set on a node and simply did not paint until something else changed it
-- (director review 2026-07-24). One ordered list, asserted to cover the set, so
-- the two views cannot drift again. Order is fixed rather than table iteration
-- because paint application must be deterministic.
-- `shape` is FIRST: it is the fact every later chrome write consults (the
-- fallback path's `corner()` reads handle.shape), so a shape applied after a
-- surface would leave the surface's square radius on a disc until something
-- else touched it. `icon` is LAST because it paints OVER whatever the chrome
-- above it settled on — and `compactLabel` goes immediately BEFORE it, because
-- when the compact form is an icon it becomes an icon request, which `icon` then
-- carries to the chrome subsystem through the one reconcile entry point.
-- `stroke` sits beside `corners` (both are the node's own border chrome) and
-- `scaleMode` beside `textAlign` (both are leaf paint that no other write reads).
-- exported for the renderer's creation-time application loop (the ORDER is the
-- point; see the block above)
local STYLE_PROP_ORDER: { string } = {
	"shape",
	"surface",
	"role",
	"shadow",
	"gradient",
	"corners",
	"stroke",
	"textAlign",
	"scaleMode",
	"compactLabel",
	"icon",
}
do
	local covered: { [string]: boolean } = {}
	for _, prop in STYLE_PROP_ORDER do
		assert(STYLE_PROPS[prop], `STYLE_PROP_ORDER lists '{prop}', which is not a style prop`)
		covered[prop] = true
	end
	for prop in STYLE_PROPS do
		assert(covered[prop], `style prop '{prop}' is missing from STYLE_PROP_ORDER and would never apply at creation`)
	end
end
prop_channels.STYLE_PROPS = STYLE_PROPS
prop_channels.BINDING_PROPS = BINDING_PROPS

-- ONE NAME, TWO PROPERTIES. `thickness` is `Path`'s engine stroke width — a real
-- binding write — and `Divider`'s hairline size, which the SOLVER consumes into
-- the node's own box and no adapter ever sees (see the Divider branch of
-- `toLayoutNode`). The binding dispatch below is keyed on the prop NAME, so a
-- Divider tried to write it too and hit the authority wall: `UI.Divider{
-- thickness = … }` errored at first render for EVERY value, and always had —
-- found while giving both props the metric grammar. The name is
-- therefore restricted to the class that actually emits it; everything else
-- stays loud (an undeclared write is still an assertWrite error).
local BINDING_PROP_CLASSES: { [string]: { [string]: boolean } } = {
	thickness = { Path = true },
}

function prop_channels.emitsBinding(class: string, prop: string): boolean
	if not BINDING_PROPS[prop] then
		return false
	end
	local only = BINDING_PROP_CLASSES[prop]
	return only == nil or only[class] == true
end

-- EVERY PROP NAME THIS MODULE CAN HAND TO `adapter.setProp`, and the seam each
-- one rides. The two channel tables above cover most of them; these are the
-- writes that go out through their own seam instead, so the set is complete.
--
-- WHY THIS EXISTS (found defect the headless-green/device-wrong class, 2026-07-27 audit). `FakeTarget.setProp`
-- recorded any prop generically, so a headless suite proved a channel the LIVE
-- adapter had no branch for: the keyboard keep-visible transform was written,
-- recorded, asserted green — and never landed on a device for as long as the
-- feature had shipped. A declared set turns "both adapters implement the same
-- props" into a conformance test (tests/render_target_contract.spec.luau) instead
-- of a thing nobody can see. Add a new setProp write site, add it here.
local DIRECT_PROPS: { [string]: string } = {
	clipChildren = "ensureTree's clip-host declaration (layout authority)",
	textSize = "commit_walks.textScale — the scaled-text paint seam",
	textFont = "commit_walks.textScale — the typography role's FACE, beside its size (F2)",
	-- THE WRAP RULE'S PAINT HALF (director ruling 5, 2026-08-13). The solver is the
	-- only seam that knows the drawable width, so it decides whether wrapping can
	-- succeed and publishes the verdict; this carries it to the adapter, which
	-- otherwise sees the string and not the box.
	textWrapped = "commit_walks.textVerdicts — the wrap-rule paint seam (layout authority)",
	padding = "commit_walks.padding — the Button and padded-Text text-inset paint seam",
	transform = "controller.setPresentationTransform / setPresentationOffset (presentation authority)",
	transparency = "controller.setPresentationTransparency (presentation authority)",
}
do
	local emitted: { [string]: boolean } = {}
	for prop in BINDING_PROPS do
		emitted[prop] = true
	end
	for prop in STYLE_PROPS do
		emitted[prop] = true
	end
	for prop in DIRECT_PROPS do
		emitted[prop] = true
	end
	-- the registry-driven held-source state (director round five): renderer-owned,
	-- never authored — declared here so the adapter parity pin holds
	emitted.dragHeld = true
	prop_channels.EMITTED_PROPS = table.freeze(emitted)
	prop_channels.DIRECT_PROPS = table.freeze(table.clone(DIRECT_PROPS))
end

prop_channels.STYLE_PROP_ORDER = STYLE_PROP_ORDER

return prop_channels
