--!strict
-- DECORATION SLOTS (ADR-0019 §5, theme-packages-and-skinning package 3).
-- PURE and engine-free. Owns three things the adapter must not decide for
-- itself, because each of them has to be assertable without an engine:
--
--   1. CLASSIFICATION — which semantic decoration slot (if any) a rendered node
--      belongs to, from the same hints `sheet_model.classifyTags` already reads;
--   2. THE PLAN — what the installed package's recipe for that slot asks the
--      adapter to build (nothing at all, for a native recipe);
--   3. THE STATE MACHINE — the per-target census (how many decoration
--      instances each slot created) and the asset-failure -> fallback-tag
--      ledger, so "a flat theme costs zero instances" and "a failed asset
--      flips exactly once and unflips on recovery" are test propositions and
--      not a claim about code someone read.
--
-- `src/client/screen_target.luau` is the only caller that materializes; it
-- holds one `newState()` per target and asks this module what to do.
--
-- WHY A NATIVE RECIPE PRODUCES NOTHING. A nine-slice needs a real ImageLabel
-- because a StyleSheet cannot turn a Frame into one. Fills, corners, strokes
-- and gradients do not: they are sheet paint and phantom modifiers (m7), and
-- materializing a real child for them would DEFEAT the rules (spike m2). So a
-- flat or gradient theme pays no instances at all, and that is enforced here.

local chrome_props = require("./chrome_props")

local chrome_slots = {}

-- The tag vocabulary, extending sheet_model.TAGS. One tag per slot (the
-- decoration child's class is always ImageLabel, so the tag is the only thing
-- distinguishing a panel skin from a field skin) plus one failure tag.
chrome_slots.TAGS = table.freeze({
	slotPrefix = "luau-chrome-", -- + panel|control|field|selection|divider|scrollbar|sliderTrack|sliderThumb|badge
	fallback = "luau-chrome-fallback",
	-- THE MUTE, SPLIT OFF THE FALLBACK (RS-A16-D5, 2026-07-26). `fallback` above
	-- says "this slot is drawing its declared native treatment"; it carries the
	-- FILL. This one says "and this particular art instance must not draw over
	-- it", and it carries the hide (`ImageTransparency = 1`) and nothing else.
	--
	-- They were ONE tag, and that is what made a false failure permanent. The
	-- hide is the engine's own "do not decode" signal, so muting the art of the
	-- asset that was just condemned destroyed the only instrument that could ever
	-- report its recovery: `IsLoaded` can never become true for an image the
	-- engine never decodes, and the one-shot grace deadline has already passed.
	-- The mute exists to stop a HEALTHY sibling from half-painting an ornament
	-- whose other layer is broken — so it is applied to every art instance in a
	-- fallen-back slot EXCEPT the ones whose own asset is the failed one
	-- (`state.isArtMuted`). Broken art draws nothing, so leaving it enabled costs
	-- no pixels and buys back the recovery signal.
	mute = "luau-chrome-mute",
	-- the chrome text lift (TP-M8): the managed label above a text-bearing
	-- node's decoration; its paint rides `.luau-chrome-text` rules
	text = "luau-chrome-text",
	-- a TextBox yielding its chrome while the engine caret needs the parent
	-- layer; rules flatten the decoration while the tag is present
	editing = "luau-chrome-editing",
	-- THE IMAGE IS THE BUTTON (director review 2026-07-25). The slot tag above
	-- rides the DECORATION; this one rides its PARENT, and it is what lets the
	-- package suppress the native plate the art now replaces: background,
	-- ::UICorner radius and ::UIStroke hairline all go to nothing under a skin.
	-- Without it a parchment button sat inside a rounded Studio-Neutral slab —
	-- "there should not be extra button border around it".
	skinnedPrefix = "luau-skinned-", -- + <slot>, on the DECORATED NODE
	-- THE SLOT IDENTITY TAG (director follow-up 2026-07-25). `skinnedPrefix`
	-- above says "art is covering this node"; this one says "this node IS a
	-- slider thumb", and it is present whether or not the package skins it.
	--
	-- It exists because a hinted node used to borrow a public SURFACE for its
	-- native paint — the thumb declared `surface = "raised"` — which quietly
	-- subscribed it to the whole panel treatment. Glossy Mobile's panel gradient
	-- carries ALPHA, so the thumb went translucent and the accent fill behind it
	-- read straight through: "in glossy_shadows, the slider button should be
	-- solid." A value control's chrome is not a panel and not a button; its
	-- native paint is ITS OWN.
	hintPrefix = "luau-slot-", -- + <slot>, on the HINTED NODE
	-- ONE PARENT TAG HIDES THE WHOLE STACK (ADR-0020 R1, probe rs-m2). A layered
	-- slot's decoration is N siblings, so the single-decoration `editing` tag
	-- above cannot express "yield" without the adapter touching every layer.
	-- rs-m2 measured the alternative and it works: one tag on the DECORATED NODE
	-- plus a child-combinator rule blanks the entire ladder.
	stackYield = "luau-chrome-yield", -- on the DECORATED NODE
	-- THE ERROR STATE (ADR-0020 R2). `default/hover/pressed/selected/disabled`
	-- all ride an engine GuiState pseudo or a tag the renderer already emits;
	-- `error` has no engine state at all, so the variant grammar's sixth state
	-- needs a tag of its own. It rides the DECORATED NODE like `selected` does.
	stateError = "luau-state-error",
	-- SEMANTIC ICON ART (ADR-0020 R4). A control that requests an icon draws the
	-- framework's ASCII glyph as its OWN text, so a theme with no art is legible
	-- by construction. When the installed package DOES declare art for that
	-- name, the adapter parents a managed picture over the node — and the glyph
	-- underneath has to stop drawing, or the two overprint.
	--
	-- TextTransparency is sheet-owned in native mode (authority.nativeSheetOwned:
	-- the `:NonInteractable` rules write it), so the suppression cannot be an
	-- explicit write. It is a TAG the package's own sheet carries a rule for —
	-- the same channel every other LuauUI state reaches native selectors by.
	iconArt = "luau-icon-art", -- on the NODE whose glyph the art replaced
	-- THE HELD SOURCE (director round five): the node a live drag session is
	-- carrying. Every theme's sheet empties its label — "the slot sits empty
	-- until it lands or returns" is a framework guarantee, not consumer code.
	dragHeld = "luau-drag-held",
})

-- The decoration child's fixed identity. Named, so a Studio reader can tell a
-- theme's decoration from game content at a glance, and so the adapter can
-- find its own instance again without bookkeeping.
chrome_slots.DECORATION_NAME = "LuauUIChrome"
chrome_slots.TEXT_LIFT_NAME = "LuauUIChromeText"
-- the managed semantic-icon picture (ADR-0020 R4), same naming discipline
chrome_slots.ICON_NAME = "LuauUIIcon"
-- Above every layer a stack may declare (R1 caps a stack at 8) and above the
-- chrome text lift, which sits at `#layers + 1`. A picture that the plate it
-- names could cover would be worse than no picture at all.
chrome_slots.ICON_Z_INDEX = 20

-- iconTagFor(name): the tag a managed icon picture wears so the package's own
-- rule can reach it.
--
-- TWO reasons for the exact spelling. (1) Semantic names carry DOTS
-- ("chevron.trailing") and namespaced ones carry a COLON, and both are selector
-- syntax — a raw name after `.` would parse as two classes and silently match
-- nothing. (2) It carries the `luau-chrome-` prefix because that prefix is what
-- earns a rule the IMAGE-property allowance in the sheet compiler, and an icon
-- picture is chrome by any reading: it is theme-owned art on an adapter-managed
-- instance, exactly like a decoration.
chrome_slots.ICON_TAG_PREFIX = "luau-chrome-icon-"

function chrome_slots.iconTagFor(name: string): string
	return chrome_slots.ICON_TAG_PREFIX .. (string.gsub(string.gsub(name, "%.", "-"), ":", "--"))
end

-- The engine classes whose text the chrome lift has to raise above a
-- decoration. TextLabel joined the list in the director fix round: a BADGE is a
-- TextLabel and its count was painting UNDER the seal ("values like '3'
-- unreadable"). Under `Sibling` z-behavior a child draws over its parent's
-- engine text at ANY ZIndex, so this is about the class hierarchy, not about
-- whether the node happens to be interactive.
chrome_slots.LIFTED_TEXT_CLASSES = table.freeze({ "TextButton", "TextBox", "TextLabel" })

-- Slots whose lifted label CENTRES on both axes whatever the parent's own
-- alignment says. A badge's number belongs in the middle of its seal; a
-- button's label keeps the alignment the author chose.
local CENTRED_LIFT_SLOTS: { [string]: boolean } = { badge = true }

function chrome_slots.centresLiftedText(slot: string?): boolean
	return slot ~= nil and CENTRED_LIFT_SLOTS[slot] == true
end

-- liftGeometry(plan) -> the lifted label's box as engine-shaped scale/offset
-- pairs, INSET BY THE RECIPE'S OWN contentInsets.
--
-- Director fix round: the lift used to be full-bleed (0,0 → 1,1) while the
-- SOLVER had already reserved the recipe's inset for the parent's content — so
-- every value under a skin sat on the painted border instead of inside it. One
-- source for both halves now: this reads exactly the `contentInsets` the
-- snapshot composes into the slot's reservation.
export type LiftBox = {
	position: { xScale: number, xOffset: number, yScale: number, yOffset: number },
	size: { xScale: number, xOffset: number, yScale: number, yOffset: number },
}

-- `hostW`/`hostH` are the host's PADDED space — the box a scale-1 child actually
-- resolves against, which is the node's rect minus its own `UIPadding`. They are
-- what turns this from arithmetic into a decision (director report 2026-07-28,
-- defect 3): a lift inset by more than the space it has solves to ZERO WIDTH and
-- draws nothing, and the label is not decoration — it is the only thing that
-- redraws the node's text above the plate covering it. Measured live under Glossy
-- Touch: `Size = {1, -28}` inside 28px of padded space, `AbsoluteSize = 0, 47`,
-- a blank button.
--
-- The lift is a COPY of the node's engine text, so it must never be smaller than
-- that text's own box. When the recipe's inset cannot be afforded, the lift falls
-- back to the host's full padded box — the exact box the engine text it replaces
-- would have used. Same rule as `spendInset`, at the seam that paints rather than
-- the one that measures, because the two read the numbers independently.
--
-- Omitting both is the create path (a lift can exist before the first rect) and
-- means "no constraint known": honour the recipe, and the caller re-fits when the
-- rect lands.
function chrome_slots.liftGeometry(plan: any, hostW: number?, hostH: number?): LiftBox
	local ci = if type(plan) == "table" then plan.contentInsets else nil
	local top = (if type(ci) == "table" then ci.top else nil) or 0
	local right = (if type(ci) == "table" then ci.right else nil) or 0
	local bottom = (if type(ci) == "table" then ci.bottom else nil) or 0
	local left = (if type(ci) == "table" then ci.left else nil) or 0
	if type(hostW) == "number" and hostW - (left + right) <= 0 then
		left, right = 0, 0
	end
	if type(hostH) == "number" and hostH - (top + bottom) <= 0 then
		top, bottom = 0, 0
	end
	return {
		position = { xScale = 0, xOffset = left, yScale = 0, yOffset = top },
		size = { xScale = 1, xOffset = -(left + right), yScale = 1, yOffset = -(top + bottom) },
	}
end

chrome_slots.SLOTS = table.freeze({
	"panel",
	"control",
	"field",
	"selection",
	"divider",
	"scrollbar",
	-- value-control chrome (director review 2026-07-25: "just changing the
	-- colour isn't enough" for a slider). The rail is a nine-slice because it
	-- stretches; the thumb is a WHOLE image because it is a fixed-size token
	-- and slicing a 28px jewel would smear its centre pixel.
	"sliderTrack",
	"sliderThumb",
	-- the counter seal behind a badge's number. Whole image for the same reason.
	"badge",
	-- ===== v2 value-display and toggle chrome (ADR-0020 R3) =================
	-- Registered here as VOCABULARY; the controls that publish these hints and
	-- the adapter structure that clips a fill are P3's wiring. A package that
	-- declares none of them costs exactly what it costs today.
	--
	-- The bar family. `barTrack` stretches (nine-slice); `barFill` is sliced and
	-- lives inside the adapter's ClipsDescendants window at FULL track size, so
	-- percent is one window write and the art never re-derives its nine-patch
	-- (rs-m4 rejected ImageRect cropping for exactly that reason). `barCap` and
	-- `barCenter` are fixed-size ornaments that must survive every percent, so
	-- they are separate whole-image layers rather than part of the fill art.
	"barTrack",
	"barFill",
	"barCap",
	"barCenter",
	-- the plate behind a stepper's glyph (the glyph itself becomes an icon
	-- request — ADR-0020 R4). Whole image: a plate is a fixed-size token.
	"stepperPlate",
	-- the iOS-6 sliding switch. The track stretches, the knob does not; the
	-- Step 3.5 `togglePalette` contract stays the flat truth for both, so
	-- neither carries own-paint rules (see OWN_PAINT_SLOTS).
	"toggleTrack",
	"toggleKnob",
})

local SLOT_SET: { [string]: boolean } = {}
for _, name in chrome_slots.SLOTS do
	SLOT_SET[name] = true
end
chrome_slots.isSlot = function(name: any): boolean
	return type(name) == "string" and SLOT_SET[name] == true
end

-- WHOLE-IMAGE SLOTS: painted edge to edge with no slice geometry at all. A
-- recipe may still say `sliced = false` (or `sliced = true`) explicitly; this
-- table is only the DEFAULT for slots whose art is a fixed-size token rather
-- than a stretchable frame, so an author does not have to remember the flag.
-- v2 (ADR-0020 R3) classifies the new slots the same way: a bar's caps and
-- centrepiece, a stepper plate and a toggle knob are fixed-size tokens; a bar
-- track, a bar fill and a toggle track stretch and therefore slice.
local WHOLE_IMAGE_SLOTS: { [string]: boolean } = {
	sliderThumb = true,
	badge = true,
	barCap = true,
	barCenter = true,
	stepperPlate = true,
	toggleKnob = true,
}

function chrome_slots.isWholeImageSlot(slot: any): boolean
	return type(slot) == "string" and WHOLE_IMAGE_SLOTS[slot] == true
end

-- A SLOT THAT BORROWS ANOTHER SLOT'S RECIPE WHEN THE PACKAGE HAS NOTHING TO SAY
-- (ADR-0020 R3, P3). A stepper's +/- affordance is a Button, so every package
-- published before this stage skins it through the `control` recipe. Giving it
-- its own slot unconditionally would UN-SKIN it under exactly those packages —
-- a v2 slot that makes a v1 theme worse. So `stepperPlate` declares `control` as
-- its fallback: a package that names a stepper plate gets one, and a package
-- that does not keeps painting the stepper exactly as it does today.
--
-- The bar family is deliberately ABSENT. Its whole reason for existing is the
-- Step 3.5 cosmetic leak: the track declared `surface = "control"`, so an ornate
-- package stretched a BUTTON plate across it. Falling back to `control` would
-- reinstate the defect this row closes.
local SLOT_FALLBACK: { [string]: string } = { stepperPlate = "control" }
chrome_slots.SLOT_FALLBACK = table.freeze(table.clone(SLOT_FALLBACK))

-- resolveSlot(package, slot) -> the slot this node actually PAINTS as under the
-- installed package. Pure, so "a package with no stepper plate still skins the
-- stepper" is a headless proposition. Identity for every slot with no fallback,
-- and for one the package does declare.
function chrome_slots.resolveSlot(package: any, slot: string?): string?
	if slot == nil then
		return nil
	end
	local fallback = SLOT_FALLBACK[slot]
	if fallback == nil then
		return slot
	end
	local recipe: any = nil
	if type(package) == "table" and type(package.chrome) == "table" then
		recipe = package.chrome[slot]
	end
	if type(recipe) == "table" and (recipe.kind == "nineSlice" or recipe.kind == "layered") then
		return slot
	end
	return fallback
end

function chrome_slots.tagFor(slot: string): string
	return chrome_slots.TAGS.slotPrefix .. slot
end

-- ===== the LAYER vocabulary (ADR-0020 R1) ==================================
--
-- A layered recipe declares a bounded ARRAY of layers, each a fixed kind with a
-- CLOSED geometry vocabulary. It is data, never an instance tree: an author can
-- say "a sliced frame above a tiled fill with four 24px corner ornaments and a
-- title plaque overhanging the top edge" and can say nothing else.
--
-- Z-ORDER IS ARRAY ORDER (the adapter assigns ZIndex 1..N; the chrome text lift
-- rides above N — rs-m2), and every paint property is RULE-owned from birth.
-- rs-m2's defeat refinement is why that last part is load-bearing: a paint value
-- written at create time, before the node joins the styled tree, SURVIVES and
-- permanently defeats a rule that only starts matching later.
chrome_slots.MAX_LAYERS = 8
chrome_slots.LAYER_KINDS = table.freeze({ "fill", "frame", "corners", "edges", "plaque", "tile" })

-- The per-kind geometry vocabulary, exactly the ADR-0020 R1 table. `kind` and
-- `asset` are common to every layer; everything below is closed per kind, so a
-- `margin` on a plaque or a `tileSize` on a corner is a compile error naming the
-- kind and its legal fields rather than a field the adapter silently ignores.
-- `inset` is the ONE field the three FULL-BLEED kinds share (director round 5b).
-- A full-bleed layer paints the node's whole rect, which is right for the layer
-- that IS the plate and wrong for one that rides ON it: glossy-touch's stripe
-- tile painted its square corners over the trough's rounded, anti-aliased ends,
-- so the bar read blocky at both ends with nothing behind it to blame.
-- `inset = { x = px, y = px }` shrinks the layer's box SYMMETRICALLY per axis —
-- the same rectangle an `edges` rail already gets from `margin`, expressed on
-- both axes — so a decorative repeat can stop short of the plate's corners. It
-- is meaningless on the fixed-size kinds (a corner ornament, a rail and a plaque
-- each anchor their own box), so it stays out of their vocabularies and the
-- closed-set error rejects it there by name.
-- `mask` is the second field the three FULL-BLEED kinds share (director round
-- 5c, probe rs-m9). `inset` decides how far a layer is held OFF the edges;
-- `mask` decides its SILHOUETTE. They compose, and they answer different
-- questions: 5b's inset removed the stripe tile's square corners by stopping it
-- short, which cost a bare gap at each end. A mask lets the hatch run to the tip
-- and be clipped along the trough's arc instead.
--
-- ONE VALUE for now (`"pill"` = UICorner at scale 0.5). rs-m9 measured exactly
-- that shape; a vocabulary that shipped unmeasured mask shapes is how a skin
-- ends up almost right (the same reason PLAQUE_EDGES is one edge).
chrome_slots.LAYER_MASKS = table.freeze({ "pill" })

local LAYER_MASK_SET: { [string]: boolean } = {}
for _, name in chrome_slots.LAYER_MASKS do
	LAYER_MASK_SET[name] = true
end
function chrome_slots.isLayerMask(name: any): boolean
	return type(name) == "string" and LAYER_MASK_SET[name] == true
end

-- layerMaskOf(layer) -> "pill" | nil. The single reader, so "no mask" is one
-- decision. A kind with no `mask` in its vocabulary can never carry one
-- (`layerGeometryOf` copies only the allowed fields), so this answers nil for a
-- corners/edges/plaque layer by construction.
function chrome_slots.layerMaskOf(layer: any): string?
	local geometry: any = if type(layer) == "table" then layer.geometry or layer else {}
	local declared: any = if type(geometry) == "table" then geometry.mask else nil
	return if chrome_slots.isLayerMask(declared) then declared else nil
end

chrome_slots.LAYER_FIELDS = table.freeze({
	fill = table.freeze({ inset = true, mask = true }),
	frame = table.freeze({ inset = true, mask = true }),
	corners = table.freeze({
		size = true,
		topLeft = true,
		topRight = true,
		bottomLeft = true,
		bottomRight = true,
	}),
	edges = table.freeze({ sides = true, thickness = true, margin = true, tile = true }),
	-- `text` is the nameplate sub-slot (R1): the decorated node's own text moves
	-- onto the plaque instead of sitting in its content rect. `textInsets` is the
	-- px padding INSIDE the plate, so a carved banner's border never eats its own
	-- title; both are meaningless without `text = true` and are rejected there.
	plaque = table.freeze({ size = true, edge = true, overhang = true, text = true, textInsets = true }),
	tile = table.freeze({ tileSize = true, inset = true, mask = true }),
})
chrome_slots.LAYER_SIDES = table.freeze({ "top", "bottom", "left", "right" })
chrome_slots.CORNER_FIELDS = table.freeze({ "topLeft", "topRight", "bottomLeft", "bottomRight" })
-- v1 anchors a plaque to the TOP edge only. The other three are not forbidden
-- because they are impossible — they are unproven: rs-m3 measured the top-centre
-- overhang and nothing else, and a vocabulary that ships unmeasured anchors is
-- how a skin ends up almost right.
chrome_slots.PLAQUE_EDGES = table.freeze({ "top" })

local LAYER_KIND_SET: { [string]: boolean } = {}
for _, kind in chrome_slots.LAYER_KINDS do
	LAYER_KIND_SET[kind] = true
end
function chrome_slots.isLayerKind(kind: any): boolean
	return type(kind) == "string" and LAYER_KIND_SET[kind] == true
end

-- WHICH LAYERS SLICE. `fill`, `frame` and a non-tiled `edges` rail stretch, so
-- their art is nine-sliced and the asset MUST declare a slice centre (validated
-- at compile, never guessed). Corners and plaques are fixed-size tokens painted
-- whole. `tile` — and an `edges` rail that declared `tile` — repeats through
-- ScaleType=Tile + TileSize, which rs-m1 proved fully rule-settable.
function chrome_slots.layerScaleType(layer: any): string
	local kind = if type(layer) == "table" then layer.kind else nil
	if kind == "tile" then
		return "Tile"
	elseif kind == "edges" then
		return if type(layer) == "table" and layer.tile ~= nil then "Tile" else "Slice"
	elseif kind == "fill" or kind == "frame" then
		return "Slice"
	end
	return "Stretch"
end

-- the tag a single layer's rules key on: the slot family plus the layer's
-- position, so a state rule can reach ONE layer of a stack (rs-m2 proved the
-- compound-tag isolation) while `luau-chrome-<slot>` stays the whole-family
-- prefix every chrome-scope check already looks for.
function chrome_slots.layerTagFor(slot: string, index: number): string
	return `{chrome_slots.TAGS.slotPrefix}{slot}-{index}`
end

-- a corners layer paints four ornaments from ONE tag; a corner that declared its
-- own art gets this second tag as well, so its rule lands later in insertion
-- order and wins on that one instance without touching its three siblings.
function chrome_slots.cornerTagFor(slot: string, index: number, corner: string): string
	return `{chrome_slots.TAGS.slotPrefix}{slot}-{index}-{corner}`
end

-- the tag that rides the DECORATED NODE (the parent), which the package's
-- suppression rules key on
function chrome_slots.skinnedTagFor(slot: string): string
	return chrome_slots.TAGS.skinnedPrefix .. slot
end

-- the tag that rides a node which DECLARED a slot through the meta hint,
-- skinned or not; the package's own native paint for that slot keys on it
function chrome_slots.slotTagFor(slot: string): string
	return chrome_slots.TAGS.hintPrefix .. slot
end

-- SLOTS WITH THEIR OWN NATIVE PAINT. These are reached only through the
-- internal decoration hint (never through a public `surface`), so nothing else
-- paints them and the package has to. They are exactly the value-control family:
-- a rail and a thumb are chrome OF a control rather than controls themselves.
--
-- `badge` is deliberately NOT here. It is a public surface an author writes by
-- hand (`UI.Text{ surface = "badge" }`), so it already has native paint — the
-- `Badge` rule, solid at transparency 0 — and a package that wants to wash it is
-- making a choice rather than inheriting someone else's.
--
-- v2 (ADR-0020 R9) extends the guarantee to the BAR family's two flat-existing
-- slots. `barTrack` and `barFill` are what a progress bar is made of when no
-- package skins it, so they need solid paint for exactly the reason the rail and
-- the thumb did. `barCap`/`barCenter` are deliberately ABSENT: they have no
-- unskinned counterpart at all (a flat bar has no jewelled end-cap), so an
-- own-paint rule for them could only paint a coloured block where the theme
-- meant art. `toggleTrack`/`toggleKnob` are absent too — their colours are
-- VALUE-driven and `togglePalette` owns them (ADR-0020 R3 keeps that contract
-- untouched), so a solid rule here would fight the adapter's own writes.
chrome_slots.OWN_PAINT_SLOTS = table.freeze({ "sliderTrack", "sliderThumb", "barTrack", "barFill" })

local OWN_PAINT: { [string]: boolean } = {}
for _, name in chrome_slots.OWN_PAINT_SLOTS do
	OWN_PAINT[name] = true
end

-- A GRADIENT MAY NEVER TARGET A VALUE CONTROL'S CHROME. A wash is a surface
-- treatment: it belongs on the panels and buttons an author opted into, and its
-- alpha is exactly what made the thumb see-through. `themes.define` rejects a
-- gradient declared on one of these, so the refusal is an authoring error with a
-- reason rather than a rule that silently does not exist.
--
-- The refusal covers the whole VALUE-CONTROL family, not only the slots that
-- carry own paint: a wash over a toggle knob, a stepper plate or a bar cap
-- would make it see-through over the value it is reporting, which is the same
-- defect one control down.
local NO_GRADIENT: { [string]: boolean } = {
	barCap = true,
	barCenter = true,
	stepperPlate = true,
	toggleTrack = true,
	toggleKnob = true,
}
for name in OWN_PAINT do
	NO_GRADIENT[name] = true
end

function chrome_slots.isGradientable(slot: string): boolean
	return chrome_slots.isSlot(slot) and not NO_GRADIENT[slot]
end

function chrome_slots.hasOwnPaint(slot: any): boolean
	return type(slot) == "string" and OWN_PAINT[slot] == true
end

-- ===== the decoration HINT (internal meta channel) =========================
--
-- A composite control knows things the generic surface/class hints cannot say:
-- a Slider's rail is not a "control" and its thumb is not a "panel". It says so
-- through the blueprint's INTERNAL metadata channel — the same `bp.meta`
-- channel the input contribution rides, never the public prop bag, because a
-- public prop would have to be whitelisted into every class's schema and taught
-- to authors who must never set it (see src/input/contribution.luau).
--
--   hint = { slot = "sliderThumb", image = "rbxassetid://..."? }
--
-- `slot` names the decoration slot this node belongs to and beats classification.
-- `image` is the RUNG-2 per-view override (a local value that leaves theme
-- ownership for this node — see `planFor`).
chrome_slots.META_KEY = "decoration"

-- `slot = "none"` is a control saying "this node is NOT a decoration surface,
-- whatever you would have guessed". A Slider's accent FILL is the case that
-- needed it: it declares `surface = "accent"`, which classifies as `control`, so
-- an ornate package painted a stretched BUTTON plate over the fill bar. Nothing
-- generic can tell that apart from a real accent button — only the control can.
chrome_slots.NO_SLOT = "none"

-- fullBleedBox(l, r, t, b): how a decoration must be offset and grown to cover
-- its host's OWN box rather than its padded CONTENT box.
--
-- A scale size resolves against the parent's content box, so a `UIPadding` on
-- the host silently shrinks any child sized `fromScale(1, 1)` -- including the
-- plate that is supposed to BE the node's surface. Found live 2026-07-27 under
-- Compact Pointer: a playlist row's host was x=16 w=357 with a 12px padding, so
-- its plate drew at x=28 while the first cell's text sat at x=26, leaving the
-- text hanging 2px off the left edge of its own plate.
--
-- PURE, and here rather than in the adapter, so the arithmetic can be tested
-- headlessly -- `screen_chrome` cannot load under Lune, and this is exactly the
-- kind of off-by-the-padding rule that needs a spec with real numbers.
function chrome_slots.fullBleedBox(
	l: number,
	r: number,
	t: number,
	b: number
): { x: number, y: number, w: number, h: number }
	return { x = -l, y = -t, w = l + r, h = t + b }
end

--- iconBoxPx(wantPx, rectW, rectH, padX, padY): the px a semantic icon may
--- actually DRAW at inside the node it belongs to.
---
--- The picture is a fixed square from the theme's `iconSizes` and it is centred
--- on its node, so a node smaller than the rung overhangs by half the difference
--- on EVERY side. Measured live 2026-07-28: a Fantasy Ornate disclosure caret was
--- a 6x23 box carrying a 32x32 picture — 13px into the frame on one side and into
--- the label on the other.
---
--- The renderer now reserves the rung wherever the axis is content-derived, which
--- fixes that at the measure seam. This is the OTHER direction, and it is not
--- redundant: an AUTHORED size still wins, so a node the author fixed too small
--- (the report's compact-label button, `width = 52` under a package whose frame
--- leaves 28) can never be grown by measure. A picture must not paint outside the
--- box it was given, whoever chose that box.
---
--- `rectW`/`rectH` are the SOLVED rect — what `setRect` wrote, not AbsoluteSize,
--- which is a frame behind and zero before the first layout. `padX`/`padY` are
--- the host's `UIPadding` totals, because the picture is positioned by scale and
--- a scale resolves against the padded CONTENT box (the same trap `fullBleedBox`
--- above exists for).
---
--- A rect that has not arrived yet (nil) means "no constraint known": draw the
--- theme's rung and re-fit when it lands, which is exactly what the caller's
--- cache key change makes happen. Never returns below 1 — a zero-size picture is
--- an invisible defect where a small one is merely a tight box.
---
--- PURE, and here for the reason `fullBleedBox` is: `screen_chrome` cannot load
--- under Lune, and this is the arithmetic that needs real numbers in a spec.
--- spendInset(extent, authored, inset): how much of a slot's `contentInsets`
--- this node can actually afford on one axis.
---
--- A CHROME INSET IS A REQUEST, NOT A RIGHT (director report 2026-07-28, defect
--- 3). The skin's carved border is added to the node's padding so content clears
--- it (ADR-0019 §5), and on a node whose size was decided FOR it that sum can
--- swallow the whole box. Measured live: a Glossy Touch Button costs 12+12 of
--- button padding and 14+14 of `control` inset -- 52px -- and the scenario asked
--- for a 52px button. The content box was exactly zero, so the lifted label solved
--- 0px wide and the control rendered blank, with no error anywhere.
---
--- ALL OR NOTHING, deliberately. A proportional give-back needs a "how much
--- content is enough" constant, and there is no honest one -- so the rule is the
--- one that needs no number: the inset is spent only if the content box survives
--- it. A border with no room to be cleared is a border that cannot be honoured,
--- and the art still PAINTS either way (a decoration is sized full-bleed, not
--- from this) -- what is given back is only the reservation.
---
--- AUTHORED PADDING IS NEVER TOUCHED. That is an explicit instruction from the
--- author; the framework does not get to overrule it, and a box collapsed by
--- authored padding alone is still reported and still collapsed.
---
--- An unbounded extent affords everything: a node free to grow pays its chrome
--- and grows by it, which is the overwhelmingly common path and must not move.
function chrome_slots.spendInset(extent: number, authored: number, inset: number): number
	if extent == math.huge then
		return inset
	end
	if extent - authored - inset > 0 then
		return inset
	end
	return 0
end

function chrome_slots.iconBoxPx(wantPx: number, rectW: number?, rectH: number?, padX: number, padY: number): number
	local px = wantPx
	if type(rectW) == "number" then
		px = math.min(px, rectW - padX)
	end
	if type(rectH) == "number" then
		px = math.min(px, rectH - padY)
	end
	return math.max(1, math.floor(px))
end

-- `imageVariants` is the RUNG-2 per-state map, already normalized by the
-- control through `themes.normalizeVariant` (ADR-0020 R2 — one grammar for both
-- rungs). It travels the same internal channel `image` does.
-- `icon` is the SEMANTIC ICON REQUEST (ADR-0020 R4): a meaning, never an asset
-- id. It travels the same internal channel because it is the same kind of fact —
-- something the composite control knows about one of its own nodes and no
-- generic classifier could infer. The control ALSO draws the framework's ASCII
-- fallback glyph as that node's text, so the request is an upgrade rather than a
-- dependency: no theme art, no problem.
export type Hint = {
	slot: string?,
	image: string?,
	imageVariants: { [string]: { asset: string } }?,
	icon: string?,
	-- which `iconSizes` role this request draws at ("small" | "medium" |
	-- "large"); the snapshot owns the px, so a metric package resizes icons
	iconSize: string?,
}

-- attach(blueprint, hint) -> a NEW frozen blueprint carrying the hint. Mirrors
-- contribution.attach so both metadata channels look and behave the same.
function chrome_slots.attachHint(blueprint: any, hint: Hint): any
	assert(type(blueprint) == "table", "chrome_slots.attachHint: expected a blueprint")
	assert(
		hint.slot == nil or hint.slot == chrome_slots.NO_SLOT or chrome_slots.isSlot(hint.slot),
		`chrome_slots.attachHint: '{tostring(hint.slot)}' is not a decoration slot `
			.. `(v1 slots: {table.concat(chrome_slots.SLOTS, " | ")}, or "{chrome_slots.NO_SLOT}")`
	)
	assert(
		hint.icon == nil or (type(hint.icon) == "string" and hint.icon ~= ""),
		'chrome_slots.attachHint: `icon` is a semantic icon NAME (e.g. "chevron.trailing"), never an asset id'
	)
	local meta = if blueprint.meta ~= nil then table.clone(blueprint.meta) else {}
	meta[chrome_slots.META_KEY] = table.freeze({
		slot = hint.slot,
		image = hint.image,
		imageVariants = hint.imageVariants,
		icon = hint.icon,
		iconSize = hint.iconSize,
	})
	return table.freeze({
		class = blueprint.class,
		id = blueprint.id,
		props = blueprint.props,
		children = blueprint.children,
		meta = table.freeze(meta),
	}) :: any
end

-- read the hint off a MOUNTED node (nil when it carries none). Type-guarded for
-- the same reason contribution.read is: the reserved key is a convention.
function chrome_slots.readHint(node: any): Hint?
	if type(node) ~= "table" or type(node.meta) ~= "table" then
		return nil
	end
	local value = node.meta[chrome_slots.META_KEY]
	if type(value) ~= "table" then
		return nil
	end
	return value
end

-- ===== 1. classification ===================================================
--
-- THE MAPPING (ADR-0019 §5 slot vocabulary <- the renderer's existing surface/
-- class hints). Read top to bottom; the FIRST match wins, and the order is the
-- decision:
--
--   an explicit meta HINT             -> that slot   a composite control that
--                                                    KNOWS (Slider's rail and
--                                                    thumb); nothing generic can
--                                                    infer "this Box is a rail"
--   Divider class                     -> divider     the hairline itself
--   ScrollView class                  -> scrollbar   the scrolling host
--   TextField class                   -> field       a text field is never a
--                                                    plain control: its skin
--                                                    has to read as editable
--   declares a `selected` binding     -> selection   a selectable ROW, skinned
--     (and is not one of the above)                  as a selection surface;
--                                                    the selected/unselected
--                                                    STATE is a tint rule over
--                                                    the one base image, never
--                                                    a second slot
--   surface = raised                  -> panel       the raised-panel family
--   surface = control | chip | accent -> control     the interactive family
--   class = Button | Toggle           -> control     ...including a Button that
--                                                    never declared a surface
--   surface = badge (not an Image)    -> badge       the counter seal (director
--                                                    review 2026-07-25: a '3' on
--                                                    a flat circle was
--                                                    unreadable). Costs NOTHING
--                                                    unless the active package
--                                                    declares a badge recipe —
--                                                    `planFor` is what gates it,
--                                                    so a flat theme keeps the
--                                                    native circle exactly. An
--                                                    IMAGE badge is excluded: it
--                                                    already IS art, and the
--                                                    decoration draws over it.
--   anything else                     -> nil         NO decoration instance
--
-- `base`, `scrim` and `plain` deliberately fall through to nil: the app
-- backdrop, the modal scrim and chrome-less nodes are not decoration surfaces,
-- and giving them one would cost an instance per node for something no theme
-- wants to skin.
export type SlotInput = {
	class: string?,
	surface: string?,
	hasSelection: boolean?,
	-- the internal meta hint (see chrome_slots.readHint); wins over everything
	hint: string?,
}

local CONTROL_SURFACES: { [string]: boolean } = { control = true, chip = true, accent = true }
local CONTROL_CLASSES: { [string]: boolean } = { Button = true, Toggle = true }

function chrome_slots.classify(input: SlotInput): string?
	local class, surface = input.class, input.surface
	-- THE HINT WINS. A control that declares its own slot knows something the
	-- generic surface/class map cannot infer, and silently overruling it would
	-- put a "control" skin on a slider rail.
	if input.hint ~= nil then
		if input.hint == chrome_slots.NO_SLOT then
			return nil -- an explicit "not a decoration surface" (see NO_SLOT)
		end
		assert(
			chrome_slots.isSlot(input.hint),
			`chrome_slots.classify: decoration hint '{tostring(input.hint)}' is not a slot `
				.. `(v1 slots: {table.concat(chrome_slots.SLOTS, " | ")}, or "{chrome_slots.NO_SLOT}")`
		)
		return input.hint
	end
	-- AN EXPLICIT `plain` PAINTS NOTHING — including chrome (director round 10,
	-- found live 2026-07-26 on a phone).
	--
	-- `surface = "plain"` already meant "no plate" to the NATIVE paint path
	-- (screen_target's `applySurfaceNative` sets `nativeSurface = nil`, so no
	-- `.luau-surface-control` tag and no sheet fill). It meant nothing at all
	-- here, because the fallback below classifies by CLASS — and every Button is
	-- a control. So a package's `control` recipe was still materialized on a node
	-- whose author had explicitly asked for no surface, and the two subsystems
	-- disagreed about the same word.
	--
	-- Live: the playlist demo's five star buttons declare `plain` precisely so a
	-- rating reads as five glyphs. Under Glossy Touch they came out as five
	-- glossy PILLS; under Glossy Mobile, whose `control` is `{ kind = "native",
	-- shadow = "raised" }`, each star grew a drop shadow and the five overlapped
	-- into the smeared dark band the director reported behind the row's stars.
	-- Neither theme was wrong: both were painting a slot nothing should have
	-- classified into.
	--
	-- Placed ABOVE the class rules so it also covers a plain Divider/ScrollView/
	-- TextField, and BELOW the hint so a control that names its own slot still
	-- wins — a hint is a control's considered decision, `plain` is the caller's.
	if surface == "plain" then
		return nil
	end
	if class == "Divider" then
		return "divider"
	elseif class == "ScrollView" then
		return "scrollbar"
	elseif class == "TextField" then
		return "field"
	end
	if input.hasSelection == true and (CONTROL_CLASSES[class or ""] or CONTROL_SURFACES[surface or ""]) then
		return "selection"
	end
	if surface == "raised" then
		return "panel"
	end
	-- ...but never an IMAGE badge. An avatar headshot already IS its own art, and
	-- under `Sibling` z-behavior the decoration child renders ABOVE its parent at
	-- any ZIndex — so a seal behind an image badge would be a seal ON TOP of the
	-- face. The slot exists for the TEXT badge whose count was unreadable.
	if surface == "badge" and class ~= "Image" then
		return "badge"
	end
	if CONTROL_SURFACES[surface or ""] or CONTROL_CLASSES[class or ""] then
		return "control"
	end
	return nil
end

-- ===== 2. the plan =========================================================

export type Plan = {
	slot: string,
	-- nil ONLY for a RUNG-2 per-view override: an untagged decoration is
	-- deliberately outside the sheet's ownership (see below)
	tag: string?,
	assetName: string,
	contentId: string,
	-- false = paint the whole image edge to edge (no ScaleType=Slice at all)
	sliced: boolean,
	sliceCenter: chrome_props.Rect?,
	sliceScale: number,
	-- PER-STATE ART (ADR-0020 R2), nil when the recipe named a bare string —
	-- which means "same art in every state" and needs no extra rules at all.
	-- Resolved from the compiled recipe's normalized `assetVariants`, so the
	-- rule compiler and the adapter read ONE shape.
	variants: { [string]: { assetName: string, contentId: string } }?,
	contentInsets: { top: number, right: number, bottom: number, left: number },
	preload: string, -- "install" | "lazy"
	-- true when this plan came from a LOCAL prop rather than from the theme
	localOverride: boolean,
	-- explicit-write values for FALLBACK MODE (a target with no StyleSheets):
	-- the same numbers the rules carry, so both paths paint from ONE source
	tint: { r: number, g: number, b: number },
	transparency: number,
}

-- a per-view override: the RUNG-2 rung of the customization ladder.
--
-- `imageVariants` is the SAME normalized shape `themes.normalizeVariant` writes
-- for a recipe (ADR-0020 R2: one grammar, one normalizer, both rungs) — the
-- control normalizes its prop and hands the result over, so the prop schema
-- cannot fork from the recipe schema. Rung 2 has no package asset table, so a
-- normalized entry's `asset` IS the content URI.
export type Override = { image: string?, imageVariants: { [string]: { asset: string } }? }

-- the rung-2 map, converted into the SAME { [state] = { assetName, contentId } }
-- shape a recipe's `variants` carries, so the adapter reads one thing
local function overrideVariantsOf(declared: any): { [string]: { assetName: string, contentId: string } }?
	if type(declared) ~= "table" then
		return nil
	end
	local out: { [string]: { assetName: string, contentId: string } } = {}
	local any = false
	for state, entry in declared do
		local uri = if type(entry) == "table" then entry.asset else nil
		if type(uri) == "string" and uri ~= "" then
			out[state] = { assetName = `<local:{state}>`, contentId = uri }
			any = true
		end
	end
	return if any then out else nil
end

-- THE CHROME TINT LADDER, shared by the rule compiler and the explicit-write
-- fallback so the two paths cannot disagree about what "at rest" looks like.
-- An `ImageColor3` can only multiply DOWN from white, so a skin painted at full
-- brightness has no hover headroom: the resting tint sits slightly under white
-- and hover returns to it.
--
-- RETUNED 2026-07-25 (director fix round). Once the native plate is suppressed
-- under the art ("the image IS the button"), this ladder is the ONLY interaction
-- feedback a skinned control has — there is no fill left to change. The old
-- 0.92/1.00/0.78 spread read as almost nothing on parchment, so rest drops
-- slightly (to keep hover headroom, which is hard-capped at white) and press
-- deepens well past it: at 0.66 a pressed slab is unmistakably darker than a
-- resting one at arm's length on a phone.
chrome_slots.TINT = table.freeze({ rest = 0.90, hover = 1.0, pressed = 0.66 })

-- THE DISABLED ACCESSIBILITY FLOOR (ADR-0020 R2), in ONE place.
--
-- Rung 1 dims a decoration through the emitted `:NonInteractable > .<tag>` rule,
-- whose `ImageTransparency` is the style's `disabledContentOpacity` and whose
-- default is this number. Rung 2's decoration is deliberately UNTAGGED (an
-- explicit local value is the documented theme opt-out), so no rule can reach
-- it and the adapter has to apply the same floor itself. Two writers, one
-- constant — the rung-2 override and its themed sibling cannot drift apart,
-- which is exactly the failure the architecture verifier found (F3): a map
-- omitting `disabled` rendered its resting art at full opacity while the
-- neighbouring themed control dimmed.
chrome_slots.DISABLED_CONTENT_OPACITY = 0.4

-- variantOpacityFor(flags, resting, floor?) -> the ImageTransparency the rung-2
-- adapter writes. Unconditional on `disabled`, matching the emitted rule (which
-- also fires whether or not the map declares disabled ART — the swap and the dim
-- are separate rules and both match).
function chrome_slots.variantOpacityFor(flags: any, resting: number, floor: number?): number
	if type(flags) == "table" and flags.disabled == true then
		return if type(floor) == "number" then floor else chrome_slots.DISABLED_CONTENT_OPACITY
	end
	return resting
end

local DEFAULT_TINT = table.freeze({
	r = chrome_slots.TINT.rest,
	g = chrome_slots.TINT.rest,
	b = chrome_slots.TINT.rest,
})

-- sliceCenterOf: an asset declares `sliceCenter = { x0, y0, x1, y1 }` in image
-- pixels. `nil` is an authoring error rather than a default, because guessing a
-- slice centre produces a skin that looks almost right at one size and wrong at
-- every other — the failure this contract exists to make impossible.
local function sliceCenterOf(assetName: string, asset: any): chrome_props.Rect
	local sc = asset.sliceCenter
	assert(
		type(sc) == "table",
		`chrome_slots: asset '{assetName}' is used by a nineSlice recipe but declares no sliceCenter `
			.. "(add sliceCenter = { x0 = <px>, y0 = <px>, x1 = <px>, y1 = <px> })"
	)
	return chrome_props.rect(sc.x0, sc.y0, sc.x1, sc.y1)
end

-- resolve a normalized `assetVariants` map ({ state -> { asset, ... } }, written
-- by themes.define) against the package's asset table. nil in, nil out — a bare
-- string recipe carries no variants and emits no per-state art rules.
local function variantsOf(package: any, declared: any): { [string]: { assetName: string, contentId: string } }?
	if type(declared) ~= "table" then
		return nil
	end
	local assets = if type(package) == "table" then package.assets or {} else {}
	local out: { [string]: { assetName: string, contentId: string } } = {}
	local any = false
	for state, entry in declared do
		local name = if type(entry) == "table" then entry.asset else nil
		local asset = if type(name) == "string" then assets[name] else nil
		if type(asset) == "table" and type(asset.contentId) == "string" then
			out[state] = { assetName = name :: string, contentId = asset.contentId }
			any = true
		end
	end
	return if any then out else nil
end

local function insetsOf(recipe: any): { top: number, right: number, bottom: number, left: number }
	local ci = if type(recipe) == "table" then recipe.contentInsets else nil
	if type(ci) ~= "table" then
		return { top = 0, right = 0, bottom = 0, left = 0 }
	end
	return { top = ci.top or 0, right = ci.right or 0, bottom = ci.bottom or 0, left = ci.left or 0 }
end

-- planFor(package, slot, override?) -> Plan | nil. nil means "this slot creates
-- NOTHING": the package has no recipe for it, or the recipe is native, and no
-- local override asked for art anyway.
--
-- RUNG 2 OF THE CUSTOMIZATION LADDER (docs/guide/09-custom-themes.md §11).
-- `override.image` is a per-VIEW value — one Slider's `thumbImage`, say. When
-- present it beats the theme for THAT node, and the plan comes back
-- `localOverride = true` with NO slot tag: the decoration deliberately leaves
-- the sheet's ownership, because a tagged instance would keep taking the
-- package's `Image` rule and the local value would lose on the next swap. The
-- adapter explicit-writes it instead (documented at the write site), which is
-- exactly the standing opt-out rule — an explicit local value opts that node
-- out of theme changes, visibly and deliberately.
--
-- A local override is always WHOLE-IMAGE: a bare content URI carries no slice
-- geometry, and inventing one would produce a skin that looks almost right at
-- one size and wrong at every other.
function chrome_slots.planFor(package: any, slot: string, override: Override?): Plan?
	local recipe: any = nil
	if type(package) == "table" and type(package.chrome) == "table" then
		recipe = package.chrome[slot]
	end
	local localVariants = if type(override) == "table" then overrideVariantsOf(override.imageVariants) else nil
	local localImage = if type(override) == "table"
			and type(override.image) == "string"
			and override.image ~= ""
		then override.image
		else nil
	if localImage == nil and localVariants ~= nil and localVariants.default ~= nil then
		-- a map-only override still has a RESTING picture: its `default`, which
		-- normalizeVariant guarantees exists
		localImage = localVariants.default.contentId
	end
	if localImage ~= nil then
		return {
			slot = slot,
			tag = nil,
			assetName = `<local:{slot}>`,
			contentId = localImage,
			sliced = false,
			sliceCenter = nil,
			sliceScale = 1,
			-- RUNG-2 PER-STATE ART. The decoration is untagged on purpose, so no
			-- rule can reach it and the adapter applies these itself on the state
			-- flips it already observes (see screen_target's override state watch).
			variants = localVariants,
			contentInsets = insetsOf(recipe),
			preload = "install",
			localOverride = true,
			tint = DEFAULT_TINT,
			transparency = 0,
		}
	end
	if type(recipe) ~= "table" or recipe.kind ~= "nineSlice" then
		return nil
	end
	-- a per-state map (ADR-0020 R2) resolves its RESTING art through the
	-- canonical `assetVariants` sibling `themes.define` wrote; a bare string is
	-- itself, which is why nothing about a package published before this stage
	-- moves at all
	local declaredVariants = recipe.assetVariants
	local assetName = if type(declaredVariants) == "table" and type(declaredVariants.default) == "table"
		then declaredVariants.default.asset
		else recipe.asset
	local asset = (package.assets or {})[assetName]
	assert(
		type(asset) == "table",
		`chrome_slots: the '{slot}' recipe names asset '{tostring(assetName)}', which the package does not declare`
	)
	-- WHOLE IMAGE vs NINE SLICE. `sliced` is explicit when the recipe says so;
	-- otherwise the slot's own nature decides (a thumb and a badge seal are
	-- fixed-size tokens, everything else is a stretchable frame).
	local sliced: boolean = if type(recipe.sliced) == "boolean"
		then recipe.sliced
		else not (WHOLE_IMAGE_SLOTS[slot] == true)
	return {
		slot = slot,
		tag = chrome_slots.tagFor(slot),
		assetName = assetName,
		contentId = asset.contentId,
		sliced = sliced,
		-- a nine-slice with no declared slice centre stays an authoring ERROR;
		-- a whole-image recipe never needed one
		sliceCenter = if sliced then sliceCenterOf(assetName, asset) else nil,
		sliceScale = if type(asset.sliceScale) == "number" then asset.sliceScale else 1,
		variants = variantsOf(package, recipe.assetVariants),
		contentInsets = insetsOf(recipe),
		preload = if asset.preload == "lazy" then "lazy" else "install",
		localOverride = false,
		-- the resting tint the FALLBACK path explicit-writes. Native mode uses
		-- the `$ChromeTint` token (or the recipe's tintRole token) instead, so a
		-- theme can retint the art without touching this.
		tint = DEFAULT_TINT,
		transparency = 0,
	}
end

-- ===== the LAYERED stack plan (ADR-0020 R1) ================================
--
-- `planFor` above answers "what ONE decoration child does this slot need". A
-- layered recipe needs N of them, ordered, each with its own tag and its own
-- anchoring geometry — so it gets its own plan rather than an overloaded one.
-- `planFor` returns nil for a layered recipe, which is what keeps every existing
-- caller (and every flat package) byte-identical.

export type LayerPlan = {
	index: number,
	kind: string,
	tag: string,
	assetName: string,
	contentId: string,
	sliced: boolean,
	scaleType: string, -- "Slice" | "Stretch" | "Tile"
	sliceCenter: chrome_props.Rect?,
	sliceScale: number,
	variants: { [string]: { assetName: string, contentId: string } }?,
	-- per-corner ART for a `corners` layer, resolved to the same shape (empty
	-- for every other kind, and for a corners layer whose four ornaments share
	-- one asset)
	cornerVariants: { [string]: { [string]: { assetName: string, contentId: string } } },
	-- the kind's declared geometry, verbatim (size / sides / thickness / margin /
	-- tile / tileSize / edge / overhang / text / per-corner overrides). The
	-- adapter anchors from these; nothing here interprets them.
	geometry: { [string]: any },
	preload: string,
}

export type StackPlan = {
	slot: string,
	layers: { LayerPlan },
	contentInsets: { top: number, right: number, bottom: number, left: number },
	-- WHAT THE STACK PAINTS OUTSIDE ITS RECT (rs-m3). A plaque overhangs its
	-- edge, so the solved rectangle is not the painted one. Published here — and
	-- in the census — so an ancestor that clips is a compile-visible fact rather
	-- than a runtime surprise, and RESERVED from the same numbers by the
	-- snapshot's `chromeOutsets` (RS-A16-D2).
	overhang: { top: number, right: number, bottom: number, left: number },
}

local OVERHANG_SIDES = table.freeze({ "top", "right", "bottom", "left" })

local function layerGeometryOf(layer: any): { [string]: any }
	local allowed = (chrome_slots.LAYER_FIELDS :: any)[layer.kind]
	local out: { [string]: any } = {}
	if type(allowed) ~= "table" then
		return out
	end
	for field in allowed do
		local v = layer[field]
		if v ~= nil then
			out[field] = if type(v) == "table" then table.clone(v) else v
		end
	end
	return out
end

-- layerPlanFor(package, slot) -> StackPlan | nil. nil means "this slot declares
-- no layer stack": no recipe, a native or nineSlice recipe, or a stack whose
-- assets the package does not declare (which `themes.define` already refused).
function chrome_slots.layerPlanFor(package: any, slot: string): StackPlan?
	local recipe: any = nil
	if type(package) == "table" and type(package.chrome) == "table" then
		recipe = package.chrome[slot]
	end
	if type(recipe) ~= "table" or recipe.kind ~= "layered" or type(recipe.layers) ~= "table" then
		return nil
	end
	local assets = (package.assets or {}) :: any
	local layers: { LayerPlan } = {}
	local overhang = { top = 0, right = 0, bottom = 0, left = 0 }
	for index, layer in recipe.layers do
		local declaredVariants = layer.assetVariants
		local assetName = if type(declaredVariants) == "table" and type(declaredVariants.default) == "table"
			then declaredVariants.default.asset
			else layer.asset
		local asset = assets[assetName]
		assert(
			type(asset) == "table",
			`chrome_slots: the '{slot}' recipe's layer {index} names asset '{tostring(assetName)}', `
				.. "which the package does not declare"
		)
		local scaleType = chrome_slots.layerScaleType(layer)
		local sliced = scaleType == "Slice"
		-- per-corner overrides resolve to the SAME shape as the layer's own art,
		-- whether the author wrote a bare name or a per-state map
		local cornerVariants: { [string]: any } = {}
		if layer.kind == "corners" then
			for _, corner in chrome_slots.CORNER_FIELDS do
				local declared = layer[corner]
				if declared == nil then
					continue
				end
				local resolved = variantsOf(package, layer[`{corner}Variants`])
				if resolved == nil and type(declared) == "string" then
					local cornerAsset = assets[declared]
					if type(cornerAsset) == "table" and type(cornerAsset.contentId) == "string" then
						resolved = { default = { assetName = declared, contentId = cornerAsset.contentId } }
					end
				end
				if resolved ~= nil then
					cornerVariants[corner] = resolved
				end
			end
		end
		table.insert(layers, {
			index = index,
			kind = layer.kind,
			tag = chrome_slots.layerTagFor(slot, index),
			assetName = assetName,
			contentId = asset.contentId,
			sliced = sliced,
			scaleType = scaleType,
			sliceCenter = if sliced then sliceCenterOf(assetName, asset) else nil,
			sliceScale = if type(asset.sliceScale) == "number" then asset.sliceScale else 1,
			variants = variantsOf(package, layer.assetVariants),
			cornerVariants = cornerVariants,
			geometry = layerGeometryOf(layer),
			preload = if asset.preload == "lazy" then "lazy" else "install",
		})
		-- WHAT THIS LAYER PAINTS OUTSIDE THE RECT, derived from the boxes the
		-- adapter will actually materialize rather than from one kind's field
		-- (RS-A16-D2). The plaque's `overhang` is still the only non-zero answer
		-- in v1 — `layerBoxes` anchors it at the parent's top edge and offsets it
		-- by -overhang — but the derivation is per KIND, so a kind whose
		-- vocabulary later paints outside its host reserves without a second
		-- writer being remembered.
		local outward = chrome_slots.layerOutwardExtent(layers[#layers])
		for _, side in OVERHANG_SIDES do
			overhang[side] = math.max(overhang[side], outward[side])
		end
	end
	return {
		slot = slot,
		layers = layers,
		contentInsets = insetsOf(recipe),
		overhang = overhang,
	}
end

-- ===== the layer ANCHORING vocabulary, as data (ADR-0020 R1, probe rs-m3) ===
--
-- rs-m3 measured the whole vocabulary in one idiom: AnchorPoint plus a
-- scale-Position, with fixed px sizes. Corners pin at all three test sizes,
-- rails stretch on ONE axis with px margins, and a plaque renders OUTSIDE the
-- parent rect by its declared overhang. Nothing needs per-frame Luau, so the
-- geometry is PURE — the adapter materializes UDim2s from these numbers and
-- decides nothing.
--
-- A LAYER IS NOT AN INSTANCE. `corners` is four ornaments and `edges` is one
-- rail per declared side; every other kind is a single full-bleed child. The
-- boxes below are the authority for how many, in what order, and where — so
-- "the adapter built the ladder the plan asked for" is a headless proposition
-- rather than something only a capture can show.
export type LayerBox = {
	-- "" for a single-instance layer; the corner or side name otherwise. Part of
	-- the instance NAME, so a Studio reader can see which ornament is which.
	key: string,
	name: string,
	-- set only for a `corners` box: the second tag its per-corner override rule
	-- keys on (rs-m2's compound-tag isolation). nil everywhere else.
	corner: string?,
	anchor: { x: number, y: number },
	position: { xScale: number, xOffset: number, yScale: number, yOffset: number },
	size: { xScale: number, xOffset: number, yScale: number, yOffset: number },
}

chrome_slots.LAYER_NAME_PREFIX = "LuauUIChromeL"

-- the adapter-owned CanvasGroup a masked layer is wrapped in (R1 `mask`, probe
-- rs-m9). Suffixed onto the layer's own name so the Explorer still reads in
-- z-order and one layer's wrapper is never confused with another's.
chrome_slots.LAYER_MASK_SUFFIX = "Mask"

-- "LuauUIChromeL5TopLeft" — index first so the ladder reads in z-order in the
-- Explorer, key suffixed so the four ornaments of one layer are distinguishable
function chrome_slots.layerInstanceName(index: number, key: string): string
	if key == "" then
		return `{chrome_slots.LAYER_NAME_PREFIX}{index}`
	end
	return `{chrome_slots.LAYER_NAME_PREFIX}{index}{key:sub(1, 1):upper()}{key:sub(2)}`
end

local function box(
	key: string,
	index: number,
	anchorX: number,
	anchorY: number,
	pxScale: number,
	pxOffset: number,
	pyScale: number,
	pyOffset: number,
	swScale: number,
	swOffset: number,
	shScale: number,
	shOffset: number
): LayerBox
	return {
		key = key,
		name = chrome_slots.layerInstanceName(index, key),
		corner = nil,
		anchor = { x = anchorX, y = anchorY },
		position = { xScale = pxScale, xOffset = pxOffset, yScale = pyScale, yOffset = pyOffset },
		size = { xScale = swScale, xOffset = swOffset, yScale = shScale, yOffset = shOffset },
	}
end

local FULL_BLEED_KINDS: { [string]: boolean } = { fill = true, frame = true, tile = true }

chrome_slots.FULL_BLEED_KINDS = table.freeze({ "fill", "frame", "tile" })

-- layerInsetOf(layer) -> { x, y } px, both non-negative. The single reader of a
-- full-bleed layer's `inset`, so the default (nothing declared = full bleed) is
-- one decision rather than one per call site. A kind that has no `inset` in its
-- vocabulary can never carry one — `layerGeometryOf` copies only the allowed
-- fields — so this answers { 0, 0 } for a corners/edges/plaque layer by
-- construction rather than by a second check.
function chrome_slots.layerInsetOf(layer: any): { x: number, y: number }
	local geometry: any = if type(layer) == "table" then layer.geometry or layer else {}
	local declared: any = if type(geometry) == "table" then geometry.inset else nil
	if type(declared) ~= "table" then
		return { x = 0, y = 0 }
	end
	local x = if type(declared.x) == "number" and declared.x > 0 then declared.x else 0
	local y = if type(declared.y) == "number" and declared.y > 0 then declared.y else 0
	return { x = x, y = y }
end

-- THE FOCUS VISUAL RIDES THE DRAWN ART (director fix round 2026-07-25).
--
-- "The green selection outline around the volume-down stepper has excessive
-- horizontal negative space." Measured live at desktop under pixel-quest: the
-- Dec button solved to 53x68 at x=265 while its plate painted 29x68 at x=277 —
-- the 12px UIPadding the adapter gives every Button so its ENGINE label clears
-- the edges also insets the decoration, because a decoration is a CHILD. The
-- ring hung off the node, so it wrapped the padded solved rect and left 12px of
-- empty air on each side of the plate it was supposed to be outlining.
--
-- The fix is not to widen the art or to shrink the node: hit geometry stays
-- full-size and invisible (the 47px floor is untouched). The ring simply moves
-- onto the instance that IS the drawn plate. For a nine-slice recipe that is the
-- one decoration; for a LAYER STACK it is the first FULL-BLEED layer, because
-- that is the layer whose box is the node's own rect — a corner ornament or a
-- plaque is a detail ON the plate, not the plate.
--
-- Returns nil when the stack paints no full-bleed layer at all (a corners-only
-- skin has no plate to hug), in which case the caller keeps the node's rect.
function chrome_slots.focusArtLayer(stack: StackPlan?): number?
	if type(stack) ~= "table" or type((stack :: any).layers) ~= "table" then
		return nil
	end
	for _, layer in stack.layers do
		if FULL_BLEED_KINDS[layer.kind] then
			return layer.index
		end
	end
	return nil
end

-- the anchor pair a corner ornament pins with. The POSITION scale is the same
-- pair, which is the whole trick: anchor (1,0) at scale (1,0) puts the
-- ornament's right edge on the parent's right edge at every width.
local CORNER_ANCHOR: { [string]: { x: number, y: number } } = {
	topLeft = { x = 0, y = 0 },
	topRight = { x = 1, y = 0 },
	bottomLeft = { x = 0, y = 1 },
	bottomRight = { x = 1, y = 1 },
}

-- layerBoxes(layer) -> every child instance that layer needs, in creation
-- order. All of them carry `layer.tag`; a corners box additionally carries its
-- per-corner tag when the recipe declared art for that corner.
function chrome_slots.layerBoxes(layer: LayerPlan): { LayerBox }
	local kind = layer.kind
	local geometry: any = layer.geometry or {}
	local index = layer.index
	if FULL_BLEED_KINDS[kind] then
		-- SYMMETRIC per axis: the box starts `x` in from the left and is `2x`
		-- narrower, so the same number is the gap at both ends. `{ x = 0, y = 0 }`
		-- and an absent `inset` produce the identical rectangle full-bleed always
		-- produced, which is what keeps every existing package byte-unchanged.
		local inset = chrome_slots.layerInsetOf(layer)
		-- `-2 * 0` is IEEE NEGATIVE zero, which compares equal to 0 but serializes
		-- as "-0" — and a signature or a dump that reads "-0" where it used to read
		-- "0" is a diff nobody made. Branch, so an absent inset is literally the
		-- old expression.
		local shrinkX = if inset.x > 0 then -2 * inset.x else 0
		local shrinkY = if inset.y > 0 then -2 * inset.y else 0
		return { box("", index, 0, 0, 0, inset.x, 0, inset.y, 1, shrinkX, 1, shrinkY) }
	end
	if kind == "corners" then
		local size = if type(geometry.size) == "number" then geometry.size else 0
		local out: { LayerBox } = {}
		for _, corner in chrome_slots.CORNER_FIELDS do
			local anchor = CORNER_ANCHOR[corner]
			local made = box("", index, anchor.x, anchor.y, anchor.x, 0, anchor.y, 0, 0, size, 0, size)
			made.key = corner
			made.name = chrome_slots.layerInstanceName(index, corner)
			-- the second tag exists only where the recipe declared that corner's
			-- own art; tagging a corner with no rule would be a selector that
			-- matches an instance and says nothing
			made.corner = if layer.cornerVariants[corner] ~= nil then corner else nil
			table.insert(out, made)
		end
		return out
	end
	if kind == "edges" then
		local thickness = if type(geometry.thickness) == "number" then geometry.thickness else 0
		local margin = if type(geometry.margin) == "number" then geometry.margin else 0
		local sides: any = if type(geometry.sides) == "table" then geometry.sides else chrome_slots.LAYER_SIDES
		local out: { LayerBox } = {}
		-- iterate the CANONICAL side order, not the author's: two packages that
		-- declared { "left", "top" } and { "top", "left" } must build the same
		-- ladder, or a swap would churn instances for a reordering
		for _, side in chrome_slots.LAYER_SIDES do
			local declared = false
			for _, name in sides do
				declared = declared or name == side
			end
			if not declared then
				continue
			end
			local made: LayerBox
			if side == "top" then
				made = box("", index, 0, 0, 0, margin, 0, 0, 1, -2 * margin, 0, thickness)
			elseif side == "bottom" then
				made = box("", index, 0, 1, 0, margin, 1, 0, 1, -2 * margin, 0, thickness)
			elseif side == "left" then
				made = box("", index, 0, 0, 0, 0, 0, margin, 0, thickness, 1, -2 * margin)
			else
				made = box("", index, 1, 0, 1, 0, 0, margin, 0, thickness, 1, -2 * margin)
			end
			made.key = side
			made.name = chrome_slots.layerInstanceName(index, side)
			table.insert(out, made)
		end
		return out
	end
	if kind == "plaque" then
		local size: any = if type(geometry.size) == "table" then geometry.size else {}
		local w = if type(size.w) == "number" then size.w else 0
		local h = if type(size.h) == "number" then size.h else 0
		local overhang = if type(geometry.overhang) == "number" then geometry.overhang else 0
		-- v1 anchors to the TOP edge only (PLAQUE_EDGES). rs-m3 measured the
		-- centred half-overhang idiom — AnchorPoint(.5,.5) at Position(.5,0) with
		-- overhang = h/2 — and this is the same rectangle written so the DECLARED
		-- overhang is literally the number of pixels above the parent's edge:
		-- anchor y = 0 at scale y = 0, offset -overhang.
		return { box("", index, 0.5, 0, 0.5, 0, 0, -overhang, 0, w, 0, h) }
	end
	return { box("", index, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0) }
end

-- ===== WHAT A LAYER PAINTS OUTSIDE ITS HOST (RS-A16-D2) ====================
--
-- The defect this closes: a plaque's `overhang` was validated, materialized,
-- published in `census.overhang` — and reserved by nobody, so the ornate
-- nameplate painted through the label of the row above it at every viewport.
-- The reservation seam (`ThemeSnapshot.chromeOutsets` -> the node's margin) had
-- exactly one writer, for the bar family, and a second hand-written branch per
-- kind is how that happens again.
--
-- So the extent is DERIVED from `layerBoxes` — the same boxes the adapter
-- materializes. Along x, a box's edges against a host of extent W are
--
--   near(W) = W*posXScale + posXOffset - anchorX*(W*sizeXScale + sizeXOffset)
--   far(W)  = near(W) + W*sizeXScale + sizeXOffset
--
-- and the outward extent is whatever falls outside [0, W]. Only the
-- HOST-INDEPENDENT part is a reservation: when the W terms cancel (`nearCoef`
-- is 0, i.e. the edge is pinned to that side of the parent; `farCoef` is 1 for
-- the far edge), the constant IS the protrusion at every host size. When they do
-- not cancel the box is proportional to its host, and a protrusion there means a
-- host too small for its own ornament — a clip to fix at the source, not a
-- margin to add to every healthy node. A 176px plaque on a 100px panel is that
-- case; reserving 38px of air on both sides of every panel is not the answer.
local function edgeOutward(
	anchor: number,
	posScale: number,
	posOffset: number,
	sizeScale: number,
	sizeOffset: number
): (number, number)
	local nearCoef = posScale - anchor * sizeScale
	local nearConst = posOffset - anchor * sizeOffset
	local near = if nearCoef == 0 then math.max(0, -nearConst) else 0
	local far = if nearCoef + sizeScale == 1 then math.max(0, nearConst + sizeOffset) else 0
	return near, far
end

-- layerOutwardExtent(layer) -> px per side this layer paints outside its host.
-- Zero for the five kinds that anchor inside (proven, not assumed: a corner
-- ornament puts its own corner ON the parent's, a rail's `margin` holds it in,
-- and a full-bleed `inset` shrinks the box).
function chrome_slots.layerOutwardExtent(layer: any): { top: number, right: number, bottom: number, left: number }
	local out = { top = 0, right = 0, bottom = 0, left = 0 }
	if type(layer) ~= "table" or type(layer.kind) ~= "string" then
		return out
	end
	for _, box in chrome_slots.layerBoxes(layer :: any) do
		local left, right =
			edgeOutward(box.anchor.x, box.position.xScale, box.position.xOffset, box.size.xScale, box.size.xOffset)
		local top, bottom =
			edgeOutward(box.anchor.y, box.position.yScale, box.position.yOffset, box.size.yScale, box.size.yOffset)
		-- ceil, like the bar reservation: a fractional extent still has to be
		-- cleared by a whole pixel
		out.left = math.max(out.left, math.ceil(left))
		out.right = math.max(out.right, math.ceil(right))
		out.top = math.max(out.top, math.ceil(top))
		out.bottom = math.max(out.bottom, math.ceil(bottom))
	end
	return out
end

-- THE PLAQUE TEXT SUB-SLOT (ADR-0020 R1; architecture verifier F2).
--
-- `plaque.text = true` promises a nameplate: the decorated node's own text reads
-- ON the plaque rather than in its content rect. It shipped validated,
-- documented and declared by two reference packages with NOTHING reading it —
-- the accepted-and-ignored class.
--
-- It is implemented as pure GEOMETRY, wired into machinery that already exists.
-- The chrome text lift is already a copy of the node's text riding above the
-- whole ladder (rs-m2); a plaque that asks for text simply moves that copy onto
-- the plaque rect, inset by the layer's declared `textInsets`. So there is no
-- second label, no second mirror, no second set of connections to leak, and the
-- box is asserted headlessly against the same numbers `layerBoxes` produces.
--
-- Returns nil when the stack has no plaque, or its plaque did not ask for text —
-- in which case the lift stays on the recipe's `contentInsets` as before. The
-- FIRST plaque wins (a stack may declare several; one nameplate is the feature).
function chrome_slots.plaqueTextBox(stack: StackPlan?): LayerBox?
	-- a nine-slice PLAN reaches the same call site as a layered STACK (one lift,
	-- two shapes); only the latter has layers at all
	if type(stack) ~= "table" or type((stack :: any).layers) ~= "table" then
		return nil
	end
	for _, layer in stack.layers do
		if layer.kind ~= "plaque" or layer.geometry.text ~= true then
			continue
		end
		local box = chrome_slots.layerBoxes(layer)[1]
		local insets: any = if type(layer.geometry.textInsets) == "table" then layer.geometry.textInsets else {}
		local top = if type(insets.top) == "number" then insets.top else 0
		local right = if type(insets.right) == "number" then insets.right else 0
		local bottom = if type(insets.bottom) == "number" then insets.bottom else 0
		local left = if type(insets.left) == "number" then insets.left else 0
		-- the plaque is anchored at its own CENTRE on x (AnchorPoint .5), so
		-- shrinking it by asymmetric horizontal insets moves the centre by half
		-- the difference; on y it is anchored at the top, so `top` shifts it down
		-- directly. Written out rather than derived so the numbers are readable.
		box.position.xOffset += (left - right) / 2
		box.position.yOffset += top
		box.size.xOffset -= left + right
		box.size.yOffset -= top + bottom
		box.name = `{box.name}Text`
		box.key = "text"
		return box
	end
	return nil
end

-- how many INSTANCES a stack costs. `census.layers` counts declared layers (the
-- authoring unit); this is the DataModel unit, and the two are different numbers
-- for corners and rails — which is exactly why both are published. The plaque
-- TEXT sub-slot is deliberately absent: it is the existing text lift's geometry,
-- not a new instance.
function chrome_slots.stackInstanceCount(stack: StackPlan?): number
	if stack == nil then
		return 0
	end
	local n = 0
	for _, layer in stack.layers do
		n += #chrome_slots.layerBoxes(layer)
	end
	return n
end

-- WHERE A LAYER SITS IN ITS HOST'S Z BAND (director report 2026-08-05).
--
-- The single-decoration path has always parented its `LuauUIChrome` at **ZIndex 0**,
-- with the ruling written on the line: *below anything the node's own content draws*.
-- The LAYERED path never got it. It numbered its layers 1..N, and a control's own
-- adapter-built content sits at 1 and 2 — `Label`, `Track`, `Knob`. Equal ZIndex is
-- broken by SIBLING ORDER, and a decoration is created after the content it decorates,
-- so `LuauUIChromeL1` painted straight over both.
--
-- Live under fantasy-ornate: a Toggle's `Label` ("Ready") and its `Track` were BURIED
-- under an opaque full-bleed layer; only the `Knob` at 2 survived, and only because
-- the corner ornaments that share its ZIndex do not overlap it. Under pixel-quest —
-- one nine-slice, ZIndex 0 — the same control reads correctly. That A/B is the whole
-- diagnosis, and it is the same shape as the `applyFullBleed` defect (L-25): a ruling
-- that lived at ONE call site while the layered route took another.
--
-- The band is therefore `<= 0` for decoration and `>= 1` for content, and the ladder
-- keeps its own order INSIDE it: layer i of N sits at `i - N`, so the topmost layer
-- lands exactly where a single decoration does (0) and the rest stack below it. That
-- is byte-identical for a one-layer package and strictly correct for the rest.
--
-- NOT sibling order. Two layers could collapse to one z slot and rely on creation
-- order, but a re-sync rebuilds only the layers that changed — an order the array does
-- not control is an order that drifts.
chrome_slots.DECORATION_Z_INDEX = 0

function chrome_slots.layerZIndexFor(index: number, count: number): number
	return index - count
end

-- the chrome text lift rides ABOVE the whole ladder (rs-m2: a layer covers the
-- parent's engine text at any ZIndex, so the lift is mandatory at every depth).
-- Layers occupy `1-N .. 0`; a single nine-slice decoration sits at 0 and keeps 1.
-- Unchanged by the band move above: `N + 1` already cleared every layer, and it also
-- clears the content band, which is what a redrawn copy of the host's own text wants.
function chrome_slots.liftZIndexFor(stack: StackPlan?): number
	if stack == nil then
		return 1
	end
	return #stack.layers + 1
end

-- ===== the BAR assembly (ADR-0020 R3, probe rs-m4) =========================
--
-- rs-m4 measured two ways to clip an image fill to a percent and REJECTED the
-- ImageRect crop: `ImageRect` and `ScaleType = Slice` both address the texture,
-- so composing them re-derives the nine-patch from the CROPPED rect and the
-- right cap gets cut out of mid-texture. The winner is a WINDOW: a
-- ClipsDescendants frame over a fill image that stays FULL TRACK SIZE at every
-- percent, so the rail texture and its caps are byte-stable from 1% to 100%.
--
-- WHERE EACH PIECE LIVES, and why:
--
--   the TRACK node (hint `barTrack`)   the nine-slice decoration, plus the caps
--                                      and the centrepiece — they must survive
--                                      EVERY percent, so they are anchored to
--                                      the track and never inside the window
--   the FILL node (hint `barFill`)     the solver already sizes this to the
--                                      percent (it is what a flat bar's accent
--                                      block is), so it IS the window's rect.
--                                      The adapter parents a ClipsDescendants
--                                      window over it and puts the full-track
--                                      art inside — one instance pair, and only
--                                      when the package declares fill art
--
-- A FLAT bar therefore costs ZERO extra instances: its fill is the solved node
-- itself, painted solid by the `luau-slot-barFill` rules (R9's OWN_PAINT_SLOTS).
chrome_slots.BAR_WINDOW_NAME = "LuauUIBarWindow"
chrome_slots.BAR_FILL_NAME = "LuauUIBarFill"
chrome_slots.BAR_CENTER_NAME = "LuauUIBarCenter"
chrome_slots.BAR_CAP_NAMES = table.freeze({ start = "LuauUIBarCapStart", finish = "LuauUIBarCapEnd" })
-- "start" is the end the fill GROWS FROM and "finish" is the far end, so the two
-- names keep meaning the same thing when `direction` flips. `finish` rather than
-- `end` because `end` is a Luau keyword and a field nobody can write without
-- brackets is a field authors get wrong.
chrome_slots.BAR_ENDS = table.freeze({ "start", "finish" })

-- The declared fill DIRECTION (ADR-0020 R3: "fill `direction` is declared data").
-- It decides which axis the window reveals and which edge of the art is pinned
-- to the window's origin — nothing else. `ltr` is the default because it is what
-- a horizontal progress bar is.
chrome_slots.BAR_DIRECTIONS = table.freeze({ "ltr", "rtl", "ttb", "btt" })
chrome_slots.BAR_DEFAULT_DIRECTION = "ltr"

local BAR_DIRECTION_SET: { [string]: boolean } = {}
for _, name in chrome_slots.BAR_DIRECTIONS do
	BAR_DIRECTION_SET[name] = true
end

function chrome_slots.isBarDirection(value: any): boolean
	return type(value) == "string" and BAR_DIRECTION_SET[value] == true
end

-- the axis a direction drives, and the anchor pair the art pins with. Written as
-- data because the adapter must not do this arithmetic twice (once for the art,
-- once for the caps) and disagree with itself.
local BAR_AXIS: { [string]: { vertical: boolean, ax: number, ay: number } } = {
	ltr = { vertical = false, ax = 0, ay = 0 },
	rtl = { vertical = false, ax = 1, ay = 0 },
	ttb = { vertical = true, ax = 0, ay = 0 },
	btt = { vertical = true, ax = 0, ay = 1 },
}

function chrome_slots.barDirectionOf(package: any, slot: string?): string
	local recipe: any = nil
	if type(package) == "table" and type(package.chrome) == "table" then
		recipe = package.chrome[slot or "barFill"]
	end
	local declared = if type(recipe) == "table" then recipe.direction else nil
	return if chrome_slots.isBarDirection(declared) then declared else chrome_slots.BAR_DEFAULT_DIRECTION
end

function chrome_slots.isVerticalBar(direction: string): boolean
	local axis = BAR_AXIS[direction] or BAR_AXIS.ltr
	return axis.vertical
end

-- barFillBox(direction, trackPx) -> the art's box INSIDE the window. `trackPx` is
-- the whole track's extent on the driven axis: the art never changes size with
-- the value, which is the entire point (rs-m4: "fill stays 300px wide at every
-- pct"), so a value change costs ONE window write and zero art re-derivation.
function chrome_slots.barFillBox(direction: string, trackPx: number): LayerBox
	local axis = BAR_AXIS[direction] or BAR_AXIS.ltr
	if axis.vertical then
		return {
			key = "",
			name = chrome_slots.BAR_FILL_NAME,
			corner = nil,
			anchor = { x = 0, y = axis.ay },
			position = { xScale = 0, xOffset = 0, yScale = axis.ay, yOffset = 0 },
			size = { xScale = 1, xOffset = 0, yScale = 0, yOffset = trackPx },
		}
	end
	return {
		key = "",
		name = chrome_slots.BAR_FILL_NAME,
		corner = nil,
		anchor = { x = axis.ax, y = 0 },
		position = { xScale = axis.ax, xOffset = 0, yScale = 0, yOffset = 0 },
		size = { xScale = 0, xOffset = trackPx, yScale = 1, yOffset = 0 },
	}
end

-- barCapBox(which, direction, size) -> an end-cap CENTRED on the track's edge, so
-- a 36px jewel on a 28px rail overhangs evenly and reads as a cap rather than as
-- a block that happens to be at the end. `which` is "start" | "finish".
function chrome_slots.barCapBox(which: string, direction: string, size: any): LayerBox
	local axis = BAR_AXIS[direction] or BAR_AXIS.ltr
	local w = if type(size) == "table" and type(size.w) == "number" then size.w else 0
	local h = if type(size) == "table" and type(size.h) == "number" then size.h else 0
	-- the START sits where the fill grows FROM (the anchor edge of the axis)
	local originScale = if axis.vertical then axis.ay else axis.ax
	local scale = if which == "start" then originScale else 1 - originScale
	local name = if which == "start" then chrome_slots.BAR_CAP_NAMES.start else chrome_slots.BAR_CAP_NAMES.finish
	if axis.vertical then
		return {
			key = which,
			name = name,
			corner = nil,
			anchor = { x = 0.5, y = 0.5 },
			position = { xScale = 0.5, xOffset = 0, yScale = scale, yOffset = 0 },
			size = { xScale = 0, xOffset = w, yScale = 0, yOffset = h },
		}
	end
	return {
		key = which,
		name = name,
		corner = nil,
		anchor = { x = 0.5, y = 0.5 },
		position = { xScale = scale, xOffset = 0, yScale = 0.5, yOffset = 0 },
		size = { xScale = 0, xOffset = w, yScale = 0, yOffset = h },
	}
end

-- barCenterBox(size) -> the centrepiece (the fantasy kits' crown), dead centre on
-- both axes at every percent. Direction-independent by construction.
function chrome_slots.barCenterBox(size: any): LayerBox
	local w = if type(size) == "table" and type(size.w) == "number" then size.w else 0
	local h = if type(size) == "table" and type(size.h) == "number" then size.h else 0
	return {
		key = "",
		name = chrome_slots.BAR_CENTER_NAME,
		corner = nil,
		anchor = { x = 0.5, y = 0.5 },
		position = { xScale = 0.5, xOffset = 0, yScale = 0.5, yOffset = 0 },
		size = { xScale = 0, xOffset = w, yScale = 0, yOffset = h },
	}
end

-- the second tag an end-cap carries when it declared its OWN art, exactly the
-- per-corner idiom: the layer tag paints both caps, and the later-inserted
-- per-end rule wins on the one instance without touching its sibling.
function chrome_slots.barCapTagFor(which: string): string
	return `{chrome_slots.tagFor("barCap")}-{which}`
end

-- barCapAssetOf(recipe, which) -> the asset NAME this end paints with: its own
-- override when declared, the recipe's shared `asset` otherwise.
function chrome_slots.barCapAssetOf(recipe: any, which: string): string?
	if type(recipe) ~= "table" then
		return nil
	end
	local own = if which == "start" then recipe.startAsset else recipe.endAsset
	if type(own) == "string" then
		return own
	end
	return if type(recipe.asset) == "string" then recipe.asset else nil
end

-- barOrnamentSize(recipe) -> the declared px box for a cap or a centrepiece.
-- A whole-image ornament has no intrinsic size the solver knows about, so the
-- recipe states it (the plaque idiom); zeros mean "declare it" and the compiler
-- says so rather than the adapter painting a 0x0 instance.
function chrome_slots.barOrnamentSize(recipe: any): { w: number, h: number }
	local size = if type(recipe) == "table" then recipe.size else nil
	return {
		w = if type(size) == "table" and type(size.w) == "number" then size.w else 0,
		h = if type(size) == "table" and type(size.h) == "number" then size.h else 0,
	}
end

-- barReservation(package, crossPx) -> what the bar's ORNAMENTS paint outside the
-- track, per side, in px (all zeros when the package declares none).
--
-- DIRECTOR FIX ROUND 2026-07-25: "the caps/centrepiece imagery overlaps the
-- value/label text at either end of the bar AND the row above". Measured live at
-- desktop under pixel-quest: a 40x40 heart cap centred on the end of an 8px
-- track spans 20px past each end and 16px past each edge, so it sat ON the
-- "Download" label (12px of overlap), ON the "0.35" readout (12px) and 2px into
-- the toolbar row above. Nothing was wrong with the ART: `barCapBox` centres a
-- cap on the track's edge on purpose (a jewel that reads as a cap rather than as
-- a block at the end), and `barCenterBox` centres the crown. What was missing is
-- that the declared extents never reached the SOLVER, so the neighbours had no
-- reason to move.
--
-- This is the same reservation consequence a plaque's `overhang` has (rs-m3), on
-- the other rung: a plaque publishes ONE authored number, a bar's overhang is
-- DERIVED from the ornament boxes and the track's own cross extent.
--
--   ends  (the fill axis)   capW / 2, because the cap is centred ON the edge
--   cross (the other axis)  max(0, (ornamentH - crossPx) / 2), because both
--                           ornaments are centred on the track's centre line
--
-- `crossPx` is the track's extent on the axis the fill does NOT drive (its
-- height for the shipped horizontal bar). 0 is legal and conservative: it
-- reserves the ornament's whole half-extent, which over-reserves rather than
-- clipping.
function chrome_slots.barReservation(
	package: any,
	crossPx: number?
): { top: number, right: number, bottom: number, left: number }
	local chrome = if type(package) == "table" and type(package.chrome) == "table" then package.chrome else nil
	if chrome == nil then
		return { top = 0, right = 0, bottom = 0, left = 0 }
	end
	local cap = chrome_slots.barOrnamentSize((chrome :: any).barCap)
	local centre = chrome_slots.barOrnamentSize((chrome :: any).barCenter)
	local vertical = chrome_slots.isVerticalBar(chrome_slots.barDirectionOf(package, "barFill"))
	-- the ends are the CAP's job (a centrepiece never sits on an end); the cross
	-- axis is whichever ornament is thickest across the rail
	local endExtent = if vertical then cap.h else cap.w
	local crossExtent = math.max(if vertical then cap.w else cap.h, if vertical then centre.w else centre.h)
	local ends = math.ceil(math.max(0, endExtent) / 2)
	local cross = math.max(0, math.ceil((crossExtent - (crossPx or 0)) / 2))
	if vertical then
		return { top = ends, right = cross, bottom = ends, left = cross }
	end
	return { top = cross, right = ends, bottom = cross, left = ends }
end

-- ===== the TOGGLE assembly (ADR-0020 R3 cap 10) ============================
--
-- The knob-and-track is ADAPTER-OWNED control chrome in every theme (it predates
-- this stage and the `togglePalette` contract stays its flat truth), so the two
-- slots do not create instances — they put ART on instances that already exist.
-- The ON/OFF state is a VALUE, and no engine GuiState reports a value, so it
-- rides a tag on the interactive node exactly as `togglePalette` rides the same
-- value in the adapter's colour writes.
chrome_slots.TOGGLE_ON_TAG = "luau-toggle-on"

-- The two toggle parts are DIRECT CHILDREN of the Toggle button (P3 moved the
-- knob out of the track for exactly this reason): every per-state rule the
-- package emits is a child combinator off the interactive node, and a knob
-- nested one level deeper could never be reached by `:Hover > `. Published here
-- so the adapter and the specs agree about the shape rather than about a comment.
chrome_slots.TOGGLE_PARTS = table.freeze({ toggleTrack = "Track", toggleKnob = "Knob" })

-- THE VARIANT PRECEDENCE, highest first. It is the emitted cascade written out:
-- rule groups run base < surfaces < roles < chrome < hover < press < disabled
-- and the later rule wins, so `disabled` beats `pressed` beats `hover`; within
-- the chrome group the per-state art rules are emitted in VARIANT_STATES order,
-- which puts `error` after `selected`.
--
-- It exists because a RUNG-2 override is deliberately untagged (no rule can
-- reach it), so the adapter picks its state art by hand — and a hand-picked
-- order that disagreed with the cascade would make one Slider behave unlike its
-- themed neighbour in exactly the states this stage exists to prove.
chrome_slots.VARIANT_PRECEDENCE = table.freeze({ "disabled", "pressed", "hover", "error", "selected" })

-- variantStateFor(flags) -> the state whose art applies, "default" when none do
export type VariantFlags = {
	disabled: boolean?,
	pressed: boolean?,
	hover: boolean?,
	error: boolean?,
	selected: boolean?,
}

function chrome_slots.variantStateFor(flags: VariantFlags): string
	for _, state in chrome_slots.VARIANT_PRECEDENCE do
		if (flags :: any)[state] == true then
			return state
		end
	end
	return "default"
end

-- variantContentFor(variants, flags) -> the content id to paint. Unstated states
-- fall back to `default` (ADR-0020 R2), which is what makes "supply exactly as
-- much art as you have" true rather than a promise.
function chrome_slots.variantContentFor(variants: any, flags: VariantFlags): string?
	if type(variants) ~= "table" then
		return nil
	end
	local entry = variants[chrome_slots.variantStateFor(flags)] or variants.default
	if type(entry) ~= "table" then
		return nil
	end
	return entry.contentId
end

-- overhangFor(package, slot) -> the reservation metadata (all zeros when the
-- slot paints inside its rect). Never nil, so a caller has one shape to read.
function chrome_slots.overhangFor(
	package: any,
	slot: string
): { top: number, right: number, bottom: number, left: number }
	local stack = chrome_slots.layerPlanFor(package, slot)
	if stack == nil then
		return { top = 0, right = 0, bottom = 0, left = 0 }
	end
	return stack.overhang
end

-- outwardExtents(package) -> { [slot] = extent } for every slot whose LAYER
-- STACK paints outside its rect. The census publishes these same per-slot
-- numbers for inspection (`census.overhang`) and the snapshot reserves them
-- (`chromeOutsets`): ONE table, read twice, which is what makes
-- "painted-published-and-never-reserved" structurally impossible (RS-A16-D2).
function chrome_slots.outwardExtents(
	package: any
): { [string]: { top: number, right: number, bottom: number, left: number } }
	local out: { [string]: { top: number, right: number, bottom: number, left: number } } = {}
	for _, slot in chrome_slots.SLOTS do
		local stack = chrome_slots.layerPlanFor(package, slot)
		if stack ~= nil and chrome_slots.hasOverhang(stack.overhang) then
			out[slot] = stack.overhang
		end
	end
	return out
end

function chrome_slots.hasOverhang(overhang: any): boolean
	if type(overhang) ~= "table" then
		return false
	end
	for _, side in OVERHANG_SIDES do
		if (overhang[side] or 0) > 0 then
			return true
		end
	end
	return false
end

-- ===== slot SHADOWS (director review 2026-07-25: "buttons should have shadows")
--
-- A recipe may declare `shadow = "raised" | "overlay" | { … }`. This is the ONE
-- piece of slot chrome the StyleSheet cannot own: `::UIShadow` rules are
-- silently accepted and paint nothing on 0.731 (feasibility m7), so the shadow
-- is deliberately ADAPTER-OWNED paint, materialized through the bespoke
-- `UIShadow` machinery behind its capability probe (ADR-0018). It is not dual
-- authority: no rule this compiler emits ever shadows the node.
--
-- Returns the raw declaration (a preset name or a parameter table); the adapter
-- normalizes it through `styling.normalizeShadow`, which is also the contract
-- `themes.define` validated it against. A flat package declares none, so a flat
-- theme still pays zero shadow instances.
function chrome_slots.shadowFor(package: any, slot: string): any
	if type(package) ~= "table" or type(package.chrome) ~= "table" then
		return nil
	end
	local recipe = package.chrome[slot]
	if type(recipe) ~= "table" then
		return nil
	end
	return recipe.shadow
end

-- assetsToPreload(package, policy): the content IDs a nineSlice recipe needs,
-- filtered by preload policy. "install" resolves when the package is installed;
-- "lazy" resolves the first time a node claims that slot. Both ride the app's
-- resource provider, which owns the generation/stale rules — nothing here
-- caches a content ID or decides when a load is stale.
--
-- v2 (ADR-0020 R2/R4) widens the walk to everything else a package can paint
-- with: every layer of a layered stack, every per-state VARIANT asset, and the
-- semantic icon map. A variant that is only fetched when the pointer first
-- enters a control is exactly the cold-decode flash rs-m6 could not measure in
-- Studio, so belt-and-braces preloading is the declared policy — and it can only
-- happen if the asset is on this list.
function chrome_slots.assetsToPreload(package: any, policy: string): { { name: string, contentId: string } }
	local out: { { name: string, contentId: string } } = {}
	local seen: { [string]: boolean } = {}
	local assets = if type(package) == "table" and type(package.assets) == "table" then package.assets else {}
	local function consider(name: any)
		if type(name) ~= "string" or seen[name] then
			return
		end
		local asset = (assets :: any)[name]
		if type(asset) ~= "table" or type(asset.contentId) ~= "string" then
			return
		end
		local declared = if asset.preload == "lazy" then "lazy" else "install"
		if declared ~= policy then
			return
		end
		seen[name] = true
		table.insert(out, { name = name, contentId = asset.contentId })
	end
	local function considerVariants(variants: any)
		if type(variants) ~= "table" then
			return
		end
		for _, entry in variants do
			consider(entry.assetName)
		end
	end
	local chrome = if type(package) == "table" and type(package.chrome) == "table" then package.chrome else {}
	for _, slot in chrome_slots.SLOTS do
		local plan = chrome_slots.planFor(package, slot)
		if plan ~= nil then
			consider(plan.assetName)
			considerVariants(plan.variants)
		end
		-- a bar's two end-caps may each name their own art (the per-corner idiom
		-- one control down); a cap that is only fetched when the bar first paints
		-- is exactly the cold-decode flash the preload seam exists to remove
		if slot == "barCap" then
			for _, which in chrome_slots.BAR_ENDS do
				consider(chrome_slots.barCapAssetOf((chrome :: any)[slot], which))
			end
		end
		local stack = chrome_slots.layerPlanFor(package, slot)
		if stack ~= nil then
			for _, layer in stack.layers do
				consider(layer.assetName)
				considerVariants(layer.variants)
				for _, corner in layer.cornerVariants do
					considerVariants(corner)
				end
			end
		end
	end
	for _, entry in chrome_slots.iconAssets(package) do
		consider(entry.assetName)
	end
	return out
end

-- iconAssets(package): the { name, assetName } pairs the package's semantic icon
-- map resolves to, variants included. Pure; the resolution ruling itself lives
-- in `themes.resolveIcon` (ADR-0020 R4) — this is only the inventory.
function chrome_slots.iconAssets(package: any): { { name: string, assetName: string } }
	local out: { { name: string, assetName: string } } = {}
	local icons = if type(package) == "table" and type(package.icons) == "table" then package.icons else nil
	if icons == nil then
		return out
	end
	local names: { string } = {}
	for name in icons do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local entry = (icons :: any)[name]
		if type(entry) == "string" then
			table.insert(out, { name = name, assetName = entry })
		elseif type(entry) == "table" then
			local states: { string } = {}
			for state in entry do
				table.insert(states, state)
			end
			table.sort(states)
			for _, state in states do
				-- an icon map holds the AUTHORED reference, where a state is
				-- either a bare name or an { asset, … } table (the same two
				-- shapes `themes.normalizeVariant` accepts)
				local declared = entry[state]
				if type(declared) == "string" then
					table.insert(out, { name = name, assetName = declared })
				elseif type(declared) == "table" and type(declared.asset) == "string" then
					table.insert(out, { name = name, assetName = declared.asset })
				end
			end
		end
	end
	return out
end

-- ===== the FOCUS treatment (director review 2026-07-25) ====================
--
-- "In parchment, the blue selection ring for the stepper looks bad. Let's make
-- selection a glow."
--
-- TWO defects sat on top of each other. The ring was painted from a STATIC
-- accent constant, so it stayed Studio-Neutral blue no matter which package was
-- installed; and a hairline ring is the wrong IDIOM for an ornate skin, where
-- everything else is soft, warm and painted.
--
-- WHY A GLOW, AND WHY NOT AN IMAGE. Roblox has no glow element, but a `UIShadow`
-- at a high `BlurRadius` with zero offset IS one — measured live: BlurRadius 30
-- at Transparency 0 renders an unmistakable soft halo, and at 0.35/14 it reads
-- at 1:1. Doing it with art instead would mean an asset pipeline per theme, a
-- fixed colour per asset, and a nine-sliced radial gradient whose falloff BANDS
-- on stretched edges at sizes the author never tried. A shadow is resolution-
-- free, any colour, any control size, and zero assets. Shaped selection ART
-- stays the `selection` decoration slot's job.
--
-- WHERE IT LIVES. `chrome.focus` — a RESERVED NON-SLOT key in the chrome table.
-- Focus is not a decoration surface: it is a treatment applied to whichever node
-- currently has focus, so making it a slot would have given it a plan, a census
-- of decoration instances, a skinned tag and suppression rules, none of which
-- mean anything here. It rides `chrome` because that is where "how this package
-- paints its chrome" lives, and it is validated by its own branch.
--
--   chrome.focus = { kind = "ring" }            -- the default; byte-identical
--                                               -- to what shipped
--   chrome.focus = {
--       kind = "glow",
--       color = "$FocusGlow" | { r = .., g = .., b = .. },
--       blurRadius = { scale? = 0, offset = 26 },
--       transparency = 0.25,
--       spread? = { x = {...}, y = {...} },
--       offset?  = { x = {...}, y = {...} },     -- default 0: a glow is centred
--       zIndex?  = -1,                           -- NEGATIVE (engine rule)
--   }
--
-- `"$Name"` resolves per THEME against that theme's `colors` then its `extra`,
-- so one recipe tints itself differently in Daylight and Candlelight — the same
-- shape `chromeGradient` uses, and the same reason (a colour is palette, and
-- palette is per theme). `themes.define` checks that the name resolves in EVERY
-- theme, because a token that resolves to nothing paints nothing and is
-- invisible until a device shows it.

chrome_slots.FOCUS_KINDS = table.freeze({ ring = true, glow = true })
chrome_slots.FOCUS_DEFAULT = table.freeze({ kind = "ring" })

-- The TEN-FOOT ("strong") variant, derived rather than authored. §8.4 requires
-- focus to be unmistakable across a room, and the ring answers that by
-- thickening (style.extra.tenFootFocusRingThickness vs focusRingThickness). A
-- glow answers it the same way: MORE blur and LESS transparency. Deriving it
-- from the near values keeps the recipe to one set of numbers — an author tunes
-- the look once and both distances follow — and keeps the two profiles from
-- drifting apart, which is exactly what two hand-authored sets would do.
chrome_slots.FOCUS_TEN_FOOT = table.freeze({ blurScale = 1.6, transparencyScale = 0.55 })

-- focusRecipeOf(package) -> the recipe, defaulting to the ring. Never nil, so
-- every caller has a kind to switch on and "no package installed" and "a package
-- that says nothing about focus" are the same thing — which they are.
function chrome_slots.focusRecipeOf(package: any): any
	if type(package) ~= "table" or type(package.chrome) ~= "table" then
		return chrome_slots.FOCUS_DEFAULT
	end
	local recipe = package.chrome.focus
	if type(recipe) ~= "table" or type(recipe.kind) ~= "string" then
		return chrome_slots.FOCUS_DEFAULT
	end
	return recipe
end

-- "$AccentHover" -> "accentHover"; the palette roles are camelCase and the
-- token spelling is PascalCase, exactly as the sheet's attributes are
local function paletteRoleOf(token: string): string?
	local name = string.match(token, "^%$([%a][%w_]*)$")
	if name == nil then
		return nil
	end
	return name:sub(1, 1):lower() .. name:sub(2)
end
chrome_slots.paletteRoleOf = paletteRoleOf

-- resolveFocusColor(recipe, theme) -> { r, g, b } | nil.
-- `theme` is one entry of package.style.themes ({ colors, extra }). nil means
-- the token named nothing in THIS theme, which is what `define` rejects.
function chrome_slots.resolveFocusColor(recipe: any, theme: any): { r: number, g: number, b: number }?
	local color = if type(recipe) == "table" then recipe.color else nil
	if type(color) == "table" then
		if type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
			return { r = color.r, g = color.g, b = color.b }
		end
		return nil
	end
	if type(color) ~= "string" then
		return nil -- no colour declared: the caller falls back to the accent
	end
	local role = paletteRoleOf(color)
	if role == nil or type(theme) ~= "table" then
		return nil
	end
	local found = (theme.colors or {})[role]
	if type(found) ~= "table" then
		found = (theme.extra or {})[role]
	end
	if type(found) ~= "table" or type(found.r) ~= "number" then
		return nil
	end
	return { r = found.r, g = found.g, b = found.b }
end

-- focusShadowSpec(recipe, strong) -> the parameter table `styling.normalizeShadow`
-- consumes (colour excluded — that is per theme and resolved separately).
-- A GLOW IS CENTRED: offset and spread default to zero, unlike a drop shadow,
-- because a halo that leans is a shadow and reads as depth rather than focus.
function chrome_slots.focusShadowSpec(recipe: any, strong: boolean): any
	local blur = (if type(recipe) == "table" then recipe.blurRadius else nil) or { scale = 0, offset = 24 }
	local transparency = if type(recipe) == "table" and type(recipe.transparency) == "number"
		then recipe.transparency
		else 0.25
	local factors = chrome_slots.FOCUS_TEN_FOOT
	return {
		blurRadius = {
			scale = (blur.scale or 0) * (if strong then factors.blurScale else 1),
			offset = (blur.offset or 0) * (if strong then factors.blurScale else 1),
		},
		transparency = math.clamp(transparency * (if strong then factors.transparencyScale else 1), 0, 1),
		offset = (if type(recipe) == "table" then recipe.offset else nil) or nil,
		spread = (if type(recipe) == "table" then recipe.spread else nil) or nil,
		zIndex = (if type(recipe) == "table" then recipe.zIndex else nil) or -1,
		enabled = true,
	}
end

-- ===== IS THIS ART EVIDENCE ABOUT LOADING? (RS-A16-D5) =====================
--
-- `ImageLabel` has no `LoadingImageFailed` (native-substrate spike m10): a decode
-- SUCCESS arrives as an `IsLoaded` property change and a FAILURE arrives as
-- SILENCE. The client target therefore runs a grace timer and reads silence at
-- the deadline as failure — which is only sound where the engine was actually
-- ASKED for the picture. THE ENGINE NEVER DECODES AN IMAGE THE PLAYER CANNOT
-- SEE, so silence from art that was never drawn is not evidence about the asset.
-- Five faces of that one rule, every one of them found live:
--
--   detached/hidden   art under a hidden ancestor — a losing ViewThatFits
--                     candidate, a collapsed disclosure (TP matrix 2026-07-25:
--                     three hidden buttons condemned a shared asset that every
--                     visible consumer had loaded)
--   muted/transparent a fully transparent image (2026-07-25, layered stacks: the
--                     fallback's own hide made five healthy siblings report
--                     "failed" too)
--   zeroArea          a value display's art before its track is laid out, or at
--                     0% (2026-07-25, the bar assembly)
--   noSource          the window between a target being built and its package
--                     sheet being linked, in which every decoration is tagged,
--                     rule-owned and therefore blank (2026-07-25)
--   clipped           CLIPPED ENTIRELY AWAY by an ancestor `ClipsDescendants`
--                     host — a ScrollView's off-window rows (RS-A16-D5,
--                     2026-07-26). Off-window art is Visible, opaque, sized and
--                     sourced, so the first four clauses all pass, and the timer
--                     condemned the shared asset for every ON-screen consumer
--                     too. It took a real device preset to find: only then was
--                     the engine viewport small enough for two thirds of the
--                     fixture to sit outside the scroll window.
--
-- Pure on purpose. The adapter reads the facts off real Instances in ONE ancestor
-- walk (`Visible`, `ClipsDescendants` rects, styled transparency/source) and this
-- decides. `reason` is the FIRST failing clause, so a live probe can report WHY
-- art was not judged rather than only that it was not.
export type ArtRect = { x: number, y: number, w: number, h: number }

export type ArtFacts = {
	-- did the ancestor walk reach a LayerCollector? A detached decoration draws
	-- nothing and is nobody's evidence
	attached: boolean,
	-- `Visible` on the art AND on every ancestor
	visible: boolean,
	-- the EFFECTIVE (styled where the sheet owns it) ImageTransparency and Image
	transparency: number,
	image: string,
	-- true when the transparency above is the FALLBACK's own hide rather than the
	-- package's intent: same verdict, different reason, and the difference is what
	-- RS-A16-D5's recoverability half turns on
	mutedByFallback: boolean?,
	rect: ArtRect,
	-- one rect per ancestor whose `ClipsDescendants` is true, in any order
	clips: { ArtRect },
}

export type ArtJudgement = { judgeable: boolean, reason: string? }

local function intersects(a: ArtRect, b: ArtRect): boolean
	local x0, y0 = math.max(a.x, b.x), math.max(a.y, b.y)
	local x1, y1 = math.min(a.x + a.w, b.x + b.w), math.min(a.y + a.h, b.y + b.h)
	return x1 > x0 and y1 > y0
end

function chrome_slots.judgeArt(facts: ArtFacts): ArtJudgement
	if not facts.attached then
		return { judgeable = false, reason = "detached" }
	end
	if not facts.visible then
		return { judgeable = false, reason = "hidden" }
	end
	if facts.transparency >= 1 then
		return { judgeable = false, reason = if facts.mutedByFallback then "muted" else "transparent" }
	end
	if facts.rect.w <= 0 or facts.rect.h <= 0 then
		return { judgeable = false, reason = "zeroArea" }
	end
	if facts.image == "" then
		return { judgeable = false, reason = "noSource" }
	end
	for _, clip in facts.clips do
		if not intersects(facts.rect, clip) then
			return { judgeable = false, reason = "clipped" }
		end
	end
	return { judgeable = true }
end

-- ===== 3. the per-target state machine =====================================

export type Census = {
	created: number,
	destroyed: number,
	live: number,
	perSlot: { [string]: { created: number, destroyed: number, live: number } },
	fallbackSlots: { string },
	failedAssets: { string },
	-- adapter-owned slot shadows (see shadowFor): counted here so "a flat
	-- package pays zero shadows" is a measurement rather than a claim
	shadows: number,
	shadowsPerSlot: { [string]: number },
	-- LAYER COST (ADR-0020 R1, ledger RS-A17). A layered slot creates N
	-- decoration instances instead of one, so "an ornate package is expensive"
	-- has to be a counted number per KIND rather than an impression. Flat and
	-- nine-slice packages leave both empty.
	layers: number,
	layersPerKind: { [string]: number },
	-- live focus GLOWS (see the focus treatment above). At most one per focused
	-- node, so a number above 1 is a leak and a stuck 1 after blur is the other
	-- kind of leak — both visible here rather than only on a device.
	focusGlows: number,
	-- live CanvasGroup wrappers, one per masked full-bleed layer (R1 `mask`,
	-- probe rs-m9 measured ~7 KB and ~18 microseconds each, Studio-derated).
	-- A canvas that outlives its layer shows up here as a stuck number.
	canvasMasks: number,
}

export type State = {
	setPackage: (package: any?) -> boolean,
	package: () -> any?,
	planFor: (slot: string, override: Override?) -> Plan?,
	layerPlanFor: (slot: string) -> StackPlan?,
	shadowFor: (slot: string) -> any,
	-- `layerKind` is present when the instance is one layer of a stack; the
	-- per-kind census is what makes an unbounded stack visible as cost
	noteCreated: (slot: string, layerKind: string?) -> (),
	noteDestroyed: (slot: string, layerKind: string?) -> (),
	noteShadow: (slot: string, on: boolean) -> (),
	noteFocusGlow: (on: boolean) -> (),
	-- one CanvasGroup per MASKED layer (R1 `mask`, probe rs-m9). A canvas is a
	-- real cost — rs-m9 measured ~7 KB and ~18 microseconds each, Studio-derated
	-- — so it is counted rather than assumed free, exactly like a layer instance.
	noteCanvasMask: (on: boolean) -> (),
	setAssetLoaded: (assetName: string, ok: boolean) -> boolean,
	-- the TARGET'S OWN grace-deadline verdict, as opposed to the authoritative
	-- report a resource provider pushes through setAssetLoaded (RS-A16-D5)
	observeAssetFailed: (assetName: string) -> boolean,
	everLoaded: (assetName: string) -> boolean,
	isAssetFailed: (assetName: string) -> boolean,
	isFallback: (slot: string) -> boolean,
	-- may THIS art instance draw while its slot is in fallback? (RS-A16-D5)
	isArtMuted: (slot: string, assetName: string?, artDecoded: boolean?) -> boolean,
	census: () -> Census,
}

function chrome_slots.newState(package: any?): State
	local current: any = package
	local counts: { [string]: { created: number, destroyed: number, live: number } } = {}
	local shadowCounts: { [string]: number } = {}
	local layerCounts: { [string]: number } = {}
	local focusGlows = 0
	local canvasMasks = 0
	local failed: { [string]: boolean } = {}
	-- every asset this target has ever seen decode, under the package now
	-- installed (cleared with the ledger on a package swap — RS-A16-D5)
	local loadedEver: { [string]: boolean } = {}
	local state = {}

	local function bucket(slot: string)
		local entry = counts[slot]
		if entry == nil then
			entry = { created = 0, destroyed = 0, live = 0 }
			counts[slot] = entry
		end
		return entry
	end

	-- setPackage returns whether the CHROME actually changed. A palette-only
	-- theme swap re-resolves the whole package and must not churn a single
	-- decoration instance, so the adapter asks this before touching anything.
	function state.setPackage(next: any?): boolean
		local function signature(p: any): string
			if type(p) ~= "table" or type(p.chrome) ~= "table" then
				return "<none>"
			end
			local parts: { string } = {}
			for _, slot in chrome_slots.SLOTS do
				local plan = chrome_slots.planFor(p, slot)
				-- the SHADOW is chrome too: a package that changes only its slot
				-- shadows still has to re-materialize them, so it belongs in the
				-- signature the adapter compares
				local shadow = chrome_slots.shadowFor(p, slot)
				local shadowKey = if shadow == nil then "-" elseif type(shadow) == "string" then shadow else "params"
				-- a LAYERED slot's whole ladder rides the signature: two packages
				-- that differ only in layer 3's art still have to re-materialize
				-- THE VALUE-DISPLAY GEOMETRY IS CHROME TOO (ADR-0020 R3). Two
				-- packages that differ only in a bar's fill DIRECTION, an end-cap's
				-- art or an ornament's px box build different instances, so the
				-- signature has to see them or a swap would repaint the old shape.
				local valueKey = ""
				if slot == "barFill" or slot == "barCap" or slot == "barCenter" then
					local recipe: any = if type(p) == "table" and type(p.chrome) == "table" then p.chrome[slot] else nil
					if type(recipe) == "table" then
						local size = chrome_slots.barOrnamentSize(recipe)
						valueKey = `<{chrome_slots.barDirectionOf(p, slot)}:{size.w}x{size.h}:`
							.. `{tostring(chrome_slots.barCapAssetOf(recipe, "start"))}:`
							.. `{tostring(chrome_slots.barCapAssetOf(recipe, "finish"))}>`
					end
				end
				local stack = chrome_slots.layerPlanFor(p, slot)
				local stackKey = ""
				if stack ~= nil then
					local layerParts: { string } = {}
					for _, layer in stack.layers do
						table.insert(layerParts, `{layer.index}:{layer.kind}:{layer.contentId}:{layer.scaleType}`)
					end
					stackKey = "[" .. table.concat(layerParts, ";") .. "]"
				end
				table.insert(
					parts,
					if plan == nil
						then `{slot}=native/{shadowKey}{stackKey}{valueKey}`
						else `{slot}={plan.contentId}#` .. `{if plan.sliceCenter ~= nil
							then chrome_props.describe(plan.sliceCenter)
							else "whole"}#` .. `{plan.sliceScale}/{shadowKey}{stackKey}{valueKey}`
				)
			end
			return table.concat(parts, "|")
		end
		local changed = signature(current) ~= signature(next)
		current = next
		if changed then
			-- a new package's assets have not failed yet; keeping the old
			-- ledger would leave a slot permanently in fallback for an asset
			-- the new package never references
			failed = {}
			-- ...and the decode history goes with it: the terminal `loaded` state
			-- is a claim about THIS package's art being resident, so a swap can
			-- still condemn a new asset that really is broken
			loadedEver = {}
		end
		return changed
	end

	function state.package(): any?
		return current
	end

	function state.planFor(slot: string, override: Override?): Plan?
		return chrome_slots.planFor(current, slot, override)
	end

	function state.layerPlanFor(slot: string): StackPlan?
		return chrome_slots.layerPlanFor(current, slot)
	end

	function state.shadowFor(slot: string): any
		return chrome_slots.shadowFor(current, slot)
	end

	function state.noteCreated(slot: string, layerKind: string?)
		local entry = bucket(slot)
		entry.created += 1
		entry.live += 1
		if layerKind ~= nil then
			layerCounts[layerKind] = (layerCounts[layerKind] or 0) + 1
		end
	end

	function state.noteDestroyed(slot: string, layerKind: string?)
		local entry = bucket(slot)
		entry.destroyed += 1
		entry.live = math.max(0, entry.live - 1)
		if layerKind ~= nil then
			layerCounts[layerKind] = math.max(0, (layerCounts[layerKind] or 0) - 1)
		end
	end

	function state.noteShadow(slot: string, on: boolean)
		local next_ = (shadowCounts[slot] or 0) + (if on then 1 else -1)
		shadowCounts[slot] = math.max(0, next_)
	end

	function state.noteFocusGlow(on: boolean)
		focusGlows = math.max(0, focusGlows + (if on then 1 else -1))
	end

	function state.noteCanvasMask(on: boolean)
		canvasMasks = math.max(0, canvasMasks + (if on then 1 else -1))
	end

	-- setAssetLoaded(name, ok) -> did the fallback set change? Idempotent in
	-- BOTH directions: a provider that reports the same failure twice must not
	-- produce a second tag flip, and a recovery must clear it exactly once.
	function state.setAssetLoaded(assetName: string, ok: boolean): boolean
		local was = failed[assetName] == true
		local now = not ok
		if ok then
			-- POSITIVE DECODE EVIDENCE IS DURABLE (RS-A16-D5). A picture the engine
			-- has decoded once is resident for the session, so a later silence from
			-- some drawn instance is never evidence that the ASSET is broken.
			loadedEver[assetName] = true
		end
		if was == now then
			return false
		end
		failed[assetName] = if now then true else nil
		return true
	end

	-- THE NO-OSCILLATION SEAM (RS-A16-D5). Two sources answer "is this asset
	-- broken": the app's resource provider, which is authoritative and keeps the
	-- unconditional `setAssetLoaded` above, and the target's own grace deadline,
	-- which infers failure from SILENCE and comes through here. The inferred
	-- verdict is refused once the asset has ever been observed loaded, so the
	-- ledger the deadline can drive is a monotone lattice —
	--
	--     unknown --(observed silence)--> failed --(decode)--> loaded (terminal)
	--
	-- — every asset moves at most twice per installed package, and a decoration
	-- can therefore be tagged and untagged at most twice. A flip/unflip cycle on
	-- the grace cadence is not merely unlikely, it is unreachable.
	function state.observeAssetFailed(assetName: string): boolean
		if loadedEver[assetName] then
			return false
		end
		return state.setAssetLoaded(assetName, false)
	end

	function state.everLoaded(assetName: string): boolean
		return loadedEver[assetName] == true
	end

	function state.isAssetFailed(assetName: string): boolean
		return failed[assetName] == true
	end

	-- WHICH ART HIDES UNDER A FALLBACK (RS-A16-D5). The mute exists so a stack
	-- whose frame is broken does not half-paint its healthy tile ladder over the
	-- declared native fill — it is about the SIBLINGS. Applied to the condemned
	-- asset's own UNDECODED art it does real damage: a fully transparent image is
	-- never decoded, so the one instance that could report "actually, it loaded" is
	-- silenced and the fallback becomes permanent. Undecoded art draws nothing on
	-- its own, so sparing it costs no pixels.
	--
	-- `artDecoded` is why the exemption is exactly that narrow. An art instance the
	-- engine has ALREADY decoded is not an instrument — its `IsLoaded` is true and
	-- cannot change again — so sparing it would buy no recovery and would paint the
	-- picture the fallback exists to replace over the declared native fill. It
	-- hides, exactly as it did before this fix (the RS-DIR6-F1 case).
	function state.isArtMuted(slot: string, assetName: string?, artDecoded: boolean?): boolean
		if not state.isFallback(slot) then
			return false
		end
		if assetName == nil or not state.isAssetFailed(assetName) then
			return true -- a healthy sibling of a broken asset: hide, as before
		end
		return artDecoded == true
	end

	function state.isFallback(slot: string): boolean
		local plan = chrome_slots.planFor(current, slot)
		if plan ~= nil then
			return failed[plan.assetName] == true
		end
		-- a LAYERED slot falls back as a whole: one broken layer means the stack
		-- no longer reads as the thing it was drawing, so the declared native
		-- treatment takes over rather than a half-painted ornament ladder
		local stack = chrome_slots.layerPlanFor(current, slot)
		if stack == nil then
			return false
		end
		for _, layer in stack.layers do
			if failed[layer.assetName] == true then
				return true
			end
		end
		return false
	end

	function state.census(): Census
		local out: Census = {
			created = 0,
			destroyed = 0,
			live = 0,
			perSlot = {},
			fallbackSlots = {},
			failedAssets = {},
			shadows = 0,
			shadowsPerSlot = {},
			layers = 0,
			layersPerKind = {},
			focusGlows = focusGlows,
			canvasMasks = canvasMasks,
		}
		for kind, count in layerCounts do
			if count > 0 then
				out.layersPerKind[kind] = count
				out.layers += count
			end
		end
		for _, slot in chrome_slots.SLOTS do
			local entry = counts[slot]
			if entry ~= nil then
				out.perSlot[slot] = { created = entry.created, destroyed = entry.destroyed, live = entry.live }
				out.created += entry.created
				out.destroyed += entry.destroyed
				out.live += entry.live
			end
			local shadows = shadowCounts[slot]
			if shadows ~= nil and shadows > 0 then
				out.shadowsPerSlot[slot] = shadows
				out.shadows += shadows
			end
			if state.isFallback(slot) then
				table.insert(out.fallbackSlots, slot)
			end
		end
		for name in failed do
			table.insert(out.failedAssets, name)
		end
		table.sort(out.failedAssets)
		return out
	end

	return state :: any
end

-- ===== headless census over a rendered tree ================================
-- The adapter's census counts real instances; this counts what the SAME
-- classification would create for a list of node descriptors, so the
-- "flat theme = 0 instances / ornate theme = N" proposition can be asserted
-- against the real fixture under the headless target.
function chrome_slots.censusOf(
	package: any,
	nodes: { SlotInput }
): {
	total: number,
	perSlot: { [string]: number },
	shadows: number,
	layers: number,
	layersPerKind: { [string]: number },
	overhang: { [string]: { top: number, right: number, bottom: number, left: number } },
}
	local perSlot: { [string]: number } = {}
	local layersPerKind: { [string]: number } = {}
	local overhang: { [string]: { top: number, right: number, bottom: number, left: number } } = {}
	local total = 0
	local shadows = 0
	local layers = 0
	for _, node in nodes do
		local slot = chrome_slots.classify(node)
		if slot ~= nil then
			if chrome_slots.planFor(package, slot) ~= nil then
				perSlot[slot] = (perSlot[slot] or 0) + 1
				total += 1
			end
			-- a LAYERED node costs one instance per layer, counted per KIND: the
			-- bench guard against an ornate package quietly doubling its ladder
			local stack = chrome_slots.layerPlanFor(package, slot)
			if stack ~= nil then
				perSlot[slot] = (perSlot[slot] or 0) + #stack.layers
				total += #stack.layers
				layers += #stack.layers
				for _, layer in stack.layers do
					layersPerKind[layer.kind] = (layersPerKind[layer.kind] or 0) + 1
				end
				if chrome_slots.hasOverhang(stack.overhang) then
					overhang[slot] = stack.overhang
				end
			end
			if chrome_slots.shadowFor(package, slot) ~= nil then
				shadows += 1
			end
		end
	end
	return {
		total = total,
		perSlot = perSlot,
		shadows = shadows,
		layers = layers,
		layersPerKind = layersPerKind,
		overhang = overhang,
	}
end

return chrome_slots
