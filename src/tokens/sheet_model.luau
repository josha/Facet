--!strict
-- Native-sheet MODEL builder (native-stylesheets stage; plan §6.1/§6.2, ledger
-- the native-stylesheets stage). PURE and engine-free: compiles Facet token styles into a
-- declarative StyleSheet model — token names, theme token sets, ordered rules,
-- transitions, and layout-reference mirrors — that the client materializer
-- (src/client/native_style.luau) turns into DataModel instances. Everything a
-- headless test needs to assert (names, values, order, contrast, coverage)
-- lives here; nothing here touches an Instance.
--
-- Engine truths this encodes (docs/research/2026-07-24-native-stylesheet-spike.md):
--   * cascade = Priority first, then INSERTION ORDER (later wins); selector
--     specificity does not participate — so rules[] order is load-bearing:
--     base -> surfaces -> selected -> hover -> pressed -> disabled;
--   * ::UICorner/::UIStroke rules CREATE phantom modifiers — the adapter must
--     NOT materialize those instances in native mode (a real child defeats
--     the phantom);
--   * theme tokens live ONLY in theme sheets (a base-sheet attribute would
--     defeat every derive); the base sheet holds rules + read-only mirrors;
--   * hover rules are compound-gated on the pointer-live tag so a touch
--     paradigm can never match them (:Hover alone has no paradigm gate);
--   * :NonInteractable keys on GuiObject.Interactable=false.

local tokens = require("./tokens")
local chrome_props = require("./chrome_props")
local chrome_slots = require("./chrome_slots")
-- the pure style-modifier layer: `tint`'s value vocabulary and its hex escape
-- live there (it is dependency-light and the public schema validates against it),
-- and this module resolves those roles against a theme's palette
local styling = require("./styling")
local themePackage = require("../themes/package")
-- the PAINT FAMILY's one derivation (`snapshot.paintForDisplay`): a corner
-- radius and a stroke thickness scale with the metric ladder at ten-foot, and
-- the literal this file bakes into a rule is what makes measure and paint agree
local themeSnapshot = require("../themes/snapshot")

local sheet_model = {}

-- The classification vocabulary shared with the adapter (Phase 2): tags are
-- the ONLY channel by which Facet states/roles reach native selectors.
sheet_model.TAGS = table.freeze({
	surfacePrefix = "facet-surface-", -- + base|raised|control|chip|badge|accent|scrim
	selected = "facet-selected",
	interactive = "facet-interactive",
	pointerLive = "facet-pointer-live",
	-- THE SHAPE TAG (feature round 2026-07-26). A SURFACE says what a node is
	-- made of; a SHAPE says what silhouette it is cut to, and the two are
	-- independent — a circle button is still a `control` surface and still takes
	-- every role, state and skin a rectangle does. So the disc's chrome is its
	-- own tag with its own phantom ::UICorner/::UIStroke rules rather than a
	-- seventh surface, which is what keeps `shape` from having to re-declare a
	-- fill, a label colour and a hover treatment it does not change.
	shapePrefix = "facet-shape-", -- + circle (the only non-default shape)
	circleRim = "facet-circle-rim", -- legacy Button/ZStack shape chrome; painted leaves have no implicit rim
	-- THE TYPOGRAPHY ROLE TAG (F2, 2026-08-02). `FontFace` is sheet-owned in
	-- native mode, so a node's typography role — which carries the FACE as well as
	-- the size — cannot reach paint as an explicit write. It reaches it as this
	-- tag, one generated rule per role, each carrying the descriptor the solver
	-- measured with. Distinct from `facet-role-strong`, which is the CONTENT-COLOUR
	-- emphasis a heading-scale size earns: one names a face, the other a colour.
	typePrefix = "facet-type-", -- + caption|label|body|heading|title|control|strong|numeral
	--[[ THE TINTED FILL (director report 2026-08-15, `canvas-group`).

		A `tint` claims `BackgroundColor3` — a colour is per-node DATA and no rule
		can carry it — but it cannot claim the FILL beside it. The tint's default
		alpha is 0, which is exactly `Frame.BackgroundTransparency`'s class default,
		and the engine decides "explicit" BY VALUE: a write equal to the default
		never marks the property explicit, so the `Frame default` rule kept
		ownership and every tinted Box with no `surface` painted nothing at all.
		Measured on the live plate 2026-08-15 — raw 0 / GetStyled 1; write 0.001 ->
		GetStyled 0.001; write 0 again -> GetStyled 1.

		So "this node has a tinted fill" reaches paint as a TAG, which is what
		`gripFocus` below already does for the identical reason. It is emitted in
		the `base` group so a surface, a value slot and a scrim all still out-rank
		it: this is the floor under an otherwise invisible node, never a new
		authority over one that was already painted. ]]
	tintFill = "facet-tint-fill",
	-- Closed partner-role classification for managed icon children.
	letterPrefix = "facet-letters-", -- + readable partner or contentStrong
	--[[ THE LOCAL SIZE AND EMPHASIS VOCABULARY (`src/controls/control_vocabulary.luau`).

		A control may say it is smaller, quieter or louder than its neighbour WITHOUT
		a theme swap. The SIZE half is metrics — the control names
		`controlSizes.<rung>.*` and the solver resolves it — but a rung also changes
		PAINT (a smaller plate wants a tighter corner), and paint keyed on a finite
		state is a tag, never a per-node write. Same for the emphasis word.

		ALL THREE RUNGS EARN A TAG, INCLUDING THE MIDDLE ONE, on the
		`facet-type-<role>` precedent rather than the `facet-shape-rect` one: a rule
		that restates the class default is inert under a package whose ladder shares
		one chrome (Facet Neutral's `regular`) and load-bearing the moment a package
		gives one rung its own. The tag appears only when a control AUTHORS a rung,
		so nothing that predates this vocabulary wears one.

		`appearance = "standard"` EARNS NOTHING, which is the other precedent and the
		right one here: standard IS the paint every untagged control already has, so
		a tag for it would be a rule with nothing to say. ]]
	sizePrefix = "facet-size-", -- + xsmall|compact|regular|large
	appearancePrefix = "facet-appearance-", -- + emphasis|soft|utility|link (standard adds none)
	-- ...and the one surface a control can say it is drawn ON TOP OF. A control
	-- over artwork cannot lean on the theme's resting control fill, so it asks for
	-- the strong opaque pair by name instead of hand-painting a scrim behind itself.
	overMedia = "facet-over-media",
	-- a chosen/checked mark painted with the theme's authored `selection` ink
	-- (`chrome_slots.Hint.selectionMark`)
	selectionMark = "facet-selection-mark",
})

-- the emphasis word that IS the default paint, named once: `classifyTags` skips it
-- and neither sheet builder emits a rule for it, and those two facts have to agree.
sheet_model.DEFAULT_APPEARANCE = "standard"

--[[ THE READABLE PARTNERS A STATUS PLATE CAN CARRY, in the order their rules are
	emitted. The status vocabulary is six words over four plates (`info` and
	`accent` share the accent; `neutral` is content on the page, which needs no
	rule because `content` is what an icon already declares), so this is the whole
	closed set — and it is what keeps the icon rules below a STATUS feature rather
	than a per-node tint channel. `contentStrong` and `danger` are lettering with
	no plate under it: over-media lettering, and a field's error line, whose status
	mark would otherwise keep the page's content colour beside a red sentence. ]]
sheet_model.STATUS_LETTERS =
	table.freeze({ "onAccent", "onSuccess", "onWarning", "onDanger", "contentStrong", "danger" })
local STATUS_LETTER_ROLES: { [string]: boolean } = {}
for _, role in sheet_model.STATUS_LETTERS do
	STATUS_LETTER_ROLES[role] = true
end
sheet_model.STATUS_LETTER_ROLES = table.freeze(STATUS_LETTER_ROLES)

-- the theme token one of those roles spends. Spelled here rather than read from
-- the role-to-token map, because the legacy builder is DEFINED above that table
-- and a later local is not an upvalue — the two are asserted equal where the map
-- itself is declared, so they cannot drift.
local function statusLetterToken(role: string): string
	return "$" .. role:sub(1, 1):upper() .. role:sub(2)
end

--[[ THE BACKDROP RULE, named once. Both sheet builders emit it and the
	adapter patches it live when the player moves their Background Transparency
	preference, so the string is a constant rather than three literals. ]]
sheet_model.SCRIM_RULE = "Scrim backdrop"

--[[ THE PLAYER'S BACKGROUND-TRANSPARENCY PREFERENCE, composed with a theme's own
	backdrop dim (owed row O-26).

	`GuiService.PreferredTransparency` is a 0..1 scalar the player moves in
	Settings; 1 is "paint what the designer said" and 0 is "I want opaque
	backgrounds". Roblox's own reference page states the recipe — *"Multiplying a
	UI element's BackgroundTransparency with PreferredTransparency is the
	recommended approach, such that backgrounds become more opaque as
	PreferredTransparency approaches 0"* — and a multiply is also the only
	composition that preserves a theme's RELATIVE intent: a package that dims at
	0.62 stays darker than one that dims at 0.35 at every setting.

	ONE FUNCTION, TWO WRITERS. The native sheet patches the `Scrim backdrop` rule
	through this; the bespoke painter writes its scrim fill through this. Same
	shape as `chrome_slots.DISABLED_CONTENT_OPACITY` and for the same reason — two
	paint vocabularies that agree today drift apart the moment either is edited
	alone.

	IDENTITY ON GARBAGE. The env memo already clamps, but this is also called from
	the adapter with a value that crossed a seam, and a NaN written into
	`BackgroundTransparency` is a backdrop nobody can see. An unusable preference
	means "leave the theme's value alone", never "guess". ]]
function sheet_model.backdropTransparency(base: number, preference: number): number
	if type(preference) ~= "number" or preference ~= preference then
		return base
	end
	return math.clamp(base * math.clamp(preference, 0, 1), 0, 1)
end

--[[ WHICH RULE PROPS THE PLAYER'S PREFERENCE IS ALLOWED TO MOVE — the same shape
	`metricRuleProps` already uses, for the same reason: the value is baked into a
	rule as a LITERAL (a preference is not a `$Token` any sheet can derive), so a
	mid-session change has to reach the installed rule through the generator's own
	`setRuleProperty`.

	IT IS A LIST WITH ONE ENTRY, AND THE LIST IS THE POINT. The audit that
	commissioned the preference decision walked every rule both builders emit and found exactly one
	`BackgroundTransparency` strictly between 0 and 1 — every other framework
	background is already opaque (a surface) or already invisible (a class default),
	and multiplying either is respectively a no-op or a defect that REVEALS hidden
	plates. `tests/preferred_transparency.spec.luau` re-derives that set from a
	built sheet and asserts this declaration against it, so a translucent
	background cannot appear on either side without a decision.

	THE SECOND TRANSLUCENT BACKGROUND IS DELIBERATELY NOT HERE (2026-09-12). The
	`Divider` rule washes the theme's hairline colour with `hairlineOpacity`, the
	same number every `UIStroke` in this sheet spends — a divider is a BORDER that
	the engine gives no standalone stroke for, so Facet draws it as a Frame. The
	preference's own refusal list already excludes strokes ("a border is not a
	background"), and this is that refusal's second instance rather than a new
	call: `base x preference` would drive the seam to 0 and paint a solid bar of
	the raw hairline colour, which in Facet Neutral is pure white.

	NO BASE HERE, DELIBERATELY. The number the preference composes against is the
	AUTHORED value of the sheet that is actually linked, which after a theme swap is
	a different designer's number than any model this constant could carry. The
	adapter reads it off the live rule once per sheet, before it has written to it
	(screen_target.applyBackdropPreference). ]]
sheet_model.PREFERENCE_RULE_PROPS = table.freeze({
	table.freeze({ rule = sheet_model.SCRIM_RULE, prop = "BackgroundTransparency" }),
})

-- A theme token is a colour in the Step 2 vocabulary. `buildPackage` also emits
-- number and sequence tokens (gradient ramps, gradient rotation) — every one of
-- them a type Roblox accepts as a StyleSheet ATTRIBUTE, which is what makes it
-- theme-swappable at all.
export type TokenValue = any -- { kind = "color"|"number"|"colorseq"|"numseq", ... }
export type Theme = { name: string, tokens: { [string]: TokenValue }, contrast: any }
export type RuleProp = any -- "$Token" | { kind = "color"|"udim"|"number"|"font"|"enum"|"rect"|"colorseq"|"numseq", ... }
export type Rule = {
	name: string,
	selector: string,
	props: { [string]: RuleProp },
	-- propName -> motion token name ("fast" | "normal"); materialized as
	-- SetPropertyTransitions(TweenInfo(motion[token])) when transitions are on
	transitions: { [string]: string }?,
	-- buildPackage only: the explicit cascade position (index * 10) and the
	-- ordered group it belongs to. `build` leaves both nil and the materializer
	-- derives the same priority from the index — identical numbers, so an
	-- existing sheet is unaffected.
	priority: number?,
	group: string?,
}
export type Model = {
	schema: string,
	stamp: string,
	defaultTheme: string,
	themes: { Theme },
	rules: { Rule },
	mirrors: { { name: string, value: number } },
	motion: { fast: number, normal: number },
	-- buildPackage only: rule props baked from metrics (corner radii, stroke
	-- thickness) so a live metric edit can repaint them
	metricRuleProps: { { path: string, rule: string, prop: string, form: string } }?,
	-- buildPackage only: what this package's skin COSTS, counted at compile
	-- (the skinning process rulings). Zero in every field for a flat
	-- package, which is what makes "flat pays nothing" a measurement.
	census: ModelCensus?,
}

export type ModelCensus = {
	-- rules carrying an `Image`, and how many of those carry the Pixelated
	-- stamp. For a pixel package the two are EQUAL, which is the assertable
	-- form of "every image-bearing rule is nearest-neighbour" (rs-m5).
	imageRules: number,
	pixelatedRules: number,
	-- generated native-paint suppression rules (three per skinned slot)
	suppressionRules: number,
	-- per-state art rules and the distinct non-default assets they name
	variantRules: number,
	variantAssets: number,
	-- layer paint rules, layer instances per decorated node, and the per-KIND
	-- breakdown that is the bench guard against an unbounded stack
	layerRules: number,
	layers: number,
	layersPerKind: { [string]: number },
	layeredSlots: { string },
	-- what a stack paints OUTSIDE its solved rect, per slot (rs-m3): a
	-- compile-visible fact for any ancestor that clips
	overhang: { [string]: { top: number, right: number, bottom: number, left: number } },
}

--[[ THE LABEL-ONLY BUTTON ROLE'S TAG (stabilization B'1, 2026-09-07). The role
	NAME lives in `chrome_slots` — the vocabulary module a control may require
	without pulling this whole compiler in, exactly as `TOGGLE_ON_TAG` does for a
	switch's value — and the tag is derived from it here so the two can never
	drift. See `blueprint_schema`'s Button `role` entry for why a role that brings
	no fill is the right shape. ]]
local ON_INDICATOR_TAG = "facet-role-" .. chrome_slots.ON_INDICATOR_ROLE
sheet_model.ON_INDICATOR_TAG = ON_INDICATOR_TAG

-- classifyTags: the PURE hint->tag mapping the native adapter applies with
-- CollectionService (Phase 2, ledger the native stylesheets work/the native stylesheets work). Headlessly tested so the
-- classification decisions never depend on an engine. `plain` and `scrim`
-- surfaces suppress interaction chrome exactly like the bespoke path
-- (suppressStates); `plain` carries no surface tag at all (chrome-less).
export type ClassifyInput = {
	surface: string?, -- base|raised|control|chip|badge|accent|scrim|plain
	selected: boolean?,
	roleSecondary: boolean?,
	strong: boolean?, -- textSize >= heading (bespoke: contentStrong upgrade)
	interactive: boolean?, -- Button/Toggle state chrome (false for scrim/plain)
	pointerLive: boolean?, -- renderer's pointer-class-live decision (hover gate)
	-- focused Grip accent fill (arch verifier 2026-07-24: the bespoke explicit
	-- write would permanently defeat the Frame-default rule in native mode, so
	-- the affordance rides a tag rule instead — theme-aware for free)
	gripFocus: boolean?,
	-- this node carries a `tint` whose colour landed on its BACKGROUND (a Box, a
	-- ZStack, a fade group — never a Text/Image/Path, whose tint claims a colour
	-- the class default already paints). Drives `facet-tint-fill`: see TAGS above
	-- for why the fill cannot be an explicit write.
	tinted: boolean?,
	-- the decoration slot this node is CURRENTLY skinned with (nil = not
	-- skinned). Drives `facet-skinned-<slot>`, which the package's suppression
	-- rules key on so the native plate stops drawing under the art.
	skinnedSlot: string?,
	-- the slot this node DECLARED through the internal decoration hint, skinned
	-- or not. Drives `facet-slot-<slot>`, which is what gives a value control's
	-- chrome its own native paint instead of borrowing a public surface's.
	slotHint: string?,
	-- this node's own tint names a STATUS's readable partner (see TAGS.letterPrefix):
	-- the four `on*` roles a status plate can carry, and nothing else — the value
	-- is the role NAME, so a rule can spend the matching token.
	letterRole: string?,
	-- the sixth variant state. `default/hover/pressed/selected/
	-- disabled` all ride an engine GuiState or a tag the renderer already emits;
	-- `error` has no engine state, so a control that has one publishes it here.
	errorState: boolean?,
	-- THE RESOLVED DISABLED STATE (2026-09-07). `enabled = false` is legal
	-- on a container now, so a Frame / TextLabel / ImageLabel with no GuiState of its
	-- own can be disabled by an ancestor. Drives `facet-state-disabled` — see
	-- `chrome_slots.TAGS` for why the engine state alone cannot carry it.
	disabled: boolean?,
	-- ONE PARENT TAG HIDES THE WHOLE STACK (probe rs-m2). The
	-- single-decoration editing yield tags the DECORATION, which syncTags never
	-- touches; a layered node's yield has to ride the DECORATED NODE, and every
	-- `facet-*` tag on that node is diffed against this desired set. A yield tag
	-- added anywhere else would survive exactly until the next classification
	-- pass — the Step 3.5 fix round's defect class, one slot down.
	chromeYield: boolean?,
	-- A SWITCH'S VALUE. `on` is neither an engine GuiState
	-- nor a selection binding — it is the control's value, and a rule cannot see
	-- a value — so the package's toggle art keys on this tag, flipped from the
	-- same fact `togglePalette` paints its colours from.
	toggleOn: boolean?,
	-- SEMANTIC ICON ART REPLACED THIS NODE'S GLYPH. A control that
	-- requests an icon draws the framework's ASCII glyph itself, so the node
	-- always has legible text; when the installed package declares real art the
	-- adapter parents a picture over it and this tag turns the glyph off. It is a
	-- tag rather than an explicit write because TextTransparency is sheet-owned
	-- in native mode, so a bespoke write would be defeated by the next rule pass.
	iconArt: boolean?,
	-- the node a live drag session is carrying (registry-driven): its label
	-- empties until the drop lands or the return flight arrives
	dragHeld: boolean?,
	-- THE SILHOUETTE (feature round 2026-07-26): "rect" (or nil) is the default
	-- every Button already had; "circle" earns `facet-shape-circle`, which the
	-- disc's phantom corner and hairline rules key on.
	shape: string?,
	shapeRim: boolean?, -- false for Box/Image; absent retains legacy circle chrome
	-- THE TYPOGRAPHY ROLE this text node resolved to (F2, 2026-08-02): the name,
	-- not the descriptor — the FACE lives in the generated rule, so measurement and
	-- paint read the one ramp. nil for a node that draws no text.
	typeRole: string?,
	-- THE LOCAL SIZE RUNG this control was authored at (see TAGS): "compact" |
	-- "regular" | "large", or nil for a control that named none and therefore keeps
	-- the theme's own chrome. The METRICS of a rung are the solver's; this is only
	-- the paint half.
	controlSize: string?,
	-- ...and its EMPHASIS word, which is paint and nothing else. "standard" is the
	-- default every untagged control already wears, so it earns no tag.
	appearance: string?,
	-- the surface this control is drawn over ("media"), when it is not the theme's
	-- own background. One word, one tag.
	over: string?,
	-- the slot of the plate this text paints over (`chrome_slots.withPlateBeneath`)
	onArt: string?,
	-- a chosen/checked mark (`chrome_slots.Hint.selectionMark`)
	selectionMark: boolean?,
}

function sheet_model.classifyTags(input: ClassifyInput): { [string]: boolean }
	local T = sheet_model.TAGS
	local tags: { [string]: boolean } = {}
	local surface = input.surface
	local suppressed = surface == "plain" or surface == "scrim"
	if surface ~= nil and surface ~= "plain" then
		tags[T.surfacePrefix .. surface] = true
	end
	if input.interactive == true and not suppressed then
		tags[T.interactive] = true
		if input.pointerLive == true then
			tags[T.pointerLive] = true
		end
	end
	if input.selected == true and not suppressed then
		tags[T.selected] = true
	end
	if input.roleSecondary == true then
		tags["facet-role-secondary"] = true
	end
	if input.strong == true then
		tags["facet-role-strong"] = true
	end
	if input.gripFocus == true then
		tags["facet-grip-focus"] = true
	end
	-- the tinted fill (see TAGS): the colour is a claim, the fill is a tag, because
	-- an explicit write of the class default never takes the property
	if input.tinted == true then
		tags[T.tintFill] = true
	end
	-- the STATUS LETTERING (see TAGS.letterPrefix): a closed set of four, so a
	-- role this vocabulary does not know earns no tag rather than a rule nothing
	-- ever wrote
	if type(input.letterRole) == "string" and sheet_model.STATUS_LETTER_ROLES[input.letterRole :: string] then
		tags[T.letterPrefix .. (input.letterRole :: string)] = true
	end
	-- the ERROR state's tag. Emitted only when a control says so,
	-- so nothing a package published before this stage renders can carry it.
	if input.errorState == true then
		tags[chrome_slots.TAGS.stateError] = true
	end
	-- ...and the DISABLED state's, which a non-control node has no engine state for
	if input.disabled == true then
		tags[chrome_slots.TAGS.stateDisabled] = true
	end
	-- the layered editing yield (see chromeYield above): one tag, and the
	-- child-combinator rules blank the whole ladder
	if input.chromeYield == true then
		tags[chrome_slots.TAGS.stackYield] = true
	end
	-- the switch's ON state (see toggleOn above). Deliberately NOT `facet-selected`:
	-- that tag carries the row-selection treatment (`TextButton.facet-selected`
	-- repaints the whole button), and a toggle being on is not a row being chosen.
	if input.toggleOn == true then
		tags[chrome_slots.TOGGLE_ON_TAG] = true
	end
	-- the icon-art glyph suppression (see iconArt above). Rides the desired set
	-- for the same reason every other v2 tag does: a tag added outside it lives
	-- exactly until the next classification pass.
	if input.iconArt == true then
		tags[chrome_slots.TAGS.iconArt] = true
	end
	if input.dragHeld == true then
		tags[chrome_slots.TAGS.dragHeld] = true
	end
	-- THE SHAPE (feature round 2026-07-26). "rect" adds no tag for exactly the
	-- reason the "default" button role adds none: the class default already
	-- describes it, and an extra tag would be a rule with nothing to say. It
	-- rides the desired set like every other classification tag, so a later pass
	-- cannot strip a disc back to a rectangle.
	if input.shape ~= nil and input.shape ~= "rect" then
		tags[T.shapePrefix .. input.shape] = true
		if input.shapeRim ~= false then
			tags[T.circleRim] = true
		end
	end
	-- THE LOCAL SIZE RUNG (see TAGS): all three earn a tag, because a rung is
	-- AUTHORED — a control that named none passes nil here and wears nothing.
	if type(input.controlSize) == "string" and input.controlSize ~= "" then
		tags[T.sizePrefix .. (input.controlSize :: string)] = true
	end
	-- ...and the EMPHASIS word, minus the default: `standard` is the paint an
	-- untagged control already has, so a tag for it would be a rule with nothing
	-- to say (the `facet-shape-rect` / `role = "default"` ruling).
	if
		type(input.appearance) == "string"
		and input.appearance ~= ""
		and input.appearance ~= sheet_model.DEFAULT_APPEARANCE
	then
		tags[T.appearancePrefix .. (input.appearance :: string)] = true
	end
	-- "I am drawn over artwork": one word, one tag, no second treatment vocabulary
	if input.over == "media" then
		tags[T.overMedia] = true
	end
	if type(input.onArt) == "string" then
		tags[chrome_slots.TAGS.onArtPrefix .. input.onArt] = true
	end
	if input.selectionMark == true then
		tags[T.selectionMark] = true
	end
	-- THE TYPOGRAPHY ROLE (F2). Emitted for every role a text node resolves to,
	-- including the class defaults: a rule that restates the class default is inert
	-- under a package whose ramp shares one face (Facet Neutral, every existing
	-- screen) and load-bearing the moment a package gives one role its own.
	if type(input.typeRole) == "string" and input.typeRole ~= "" then
		tags[T.typePrefix .. input.typeRole] = true
	end
	-- Divider (A-LV3): the hairline is sheet-painted, so a designer can restyle
	-- every separator in one rule. Never a bespoke fill in native mode.
	if input.divider == true then
		tags["facet-divider"] = true
	end
	-- semantic button role (B-BTN2). "default" adds no tag: the class default
	-- already describes it, and an extra tag would be a rule with nothing to say.
	if input.buttonRole == "destructive" then
		-- A `plain` surface paints no plate, so the role has nothing to put
		-- `$OnDanger` on: there it is a LABEL colour (a menu's destructive row).
		tags[if surface == "plain" then "facet-role-destructive-label" else "facet-role-destructive"] = true
	elseif input.buttonRole == "cancel" then
		tags["facet-role-cancel"] = true
	elseif input.buttonRole == chrome_slots.ON_INDICATOR_ROLE then
		-- THE LABEL-ONLY ROLE (stabilization B'1). Deliberately NOT gated on
		-- `suppressed` the way `selected` and `interactive` are: `plain` suppresses
		-- those two because both bring a PLATE, and this role brings none — it is
		-- the answer to "something else painted my plate", so the one surface it
		-- has to survive is exactly the one that says "I paint nothing".
		tags[ON_INDICATOR_TAG] = true
	end
	-- THE IMAGE IS THE BUTTON: the node carries its skinned-slot tag so the
	-- package's suppression rules can turn off the plate, the corner and the
	-- hairline it now sits under. Kept in the SAME desired-set the adapter
	-- diffs against, or the next classification pass would strip it.
	if type(input.skinnedSlot) == "string" then
		tags[chrome_slots.skinnedTagFor(input.skinnedSlot :: string)] = true
	end
	-- THE SLOT IDENTITY TAG. Emitted for the value-control family only: those
	-- slots are reached solely through the hint, so nothing else paints them.
	-- A node that reaches a slot through a public surface (a badge, a raised
	-- panel) already has that surface's rules and must not get a second set.
	if chrome_slots.hasOwnPaint(input.slotHint) then
		tags[chrome_slots.slotTagFor(input.slotHint :: string)] = true
	end
	return tags
end

local function color(c: any): TokenValue
	return { kind = "color", r = c.r, g = c.g, b = c.b }
end

-- The destructive role's palette (B-BTN2) was added after games already shipped
-- custom styles, so a style that predates it must keep working. These are the
-- library defaults, used only when the style omits the pair; the contrast gate
-- then runs on the EFFECTIVE pair, so a custom style can never end up with an
-- ungated destructive colour.
-- single source moved to tokens.dangerPair (2026-07-25): the theme-package
-- compiler gates the same pair at define time, and requiring sheet_model from
-- there is a cycle (sheet_model already requires ../themes/package)
local dangerPair = tokens.dangerPair
sheet_model.dangerPair = dangerPair
-- ...and the two SEMANTIC pairs beside it, for the same reason and through the
-- same door: the theme-package compiler gates them at define time, this module
-- gates them at build time, and the adapter's fallback palette spends the same
-- answer. A theme that declared neither still resolves both (see tokens).
local successPair = tokens.successPair
local warningPair = tokens.warningPair
sheet_model.successPair = successPair
sheet_model.warningPair = warningPair
--[[ THE SEMANTIC ROLES, each mapped to the pair it belongs to and which END of
	that pair it is. Both readers spend it: the contrast gate runs on the
	EFFECTIVE colours (a theme that omits a role is gated on what it will actually
	paint), and the tint resolver is handed ONE role at a time and has to know
	whether it was asked for the plate or for the colour that reads on it.

	A plate and its partner in one row is the whole point — a destructive seal's
	number, a warning badge's word and the gate that admitted them all read the
	same decision, and white is a guess rather than a theme's answer. ]]
local SEMANTIC_ROLE: { [string]: { pair: (any) -> (any, any), partner: boolean } } = {
	danger = { pair = dangerPair, partner = false },
	onDanger = { pair = dangerPair, partner = true },
	success = { pair = successPair, partner = false },
	onSuccess = { pair = successPair, partner = true },
	warning = { pair = warningPair, partner = false },
	onWarning = { pair = warningPair, partner = true },
}

local function lerp(a: any, b: { r: number, g: number, b: number }, t: number): TokenValue
	return {
		kind = "color",
		r = a.r + (b.r - a.r) * t,
		g = a.g + (b.g - a.g) * t,
		b = a.b + (b.b - a.b) * t,
	}
end

local WHITE = { r = 1, g = 1, b = 1 }
local BLACK = { r = 0, g = 0, b = 0 }

-- a strong divider's transparency: authored, or three times as visible as the hairline
local function strongHairlineOpacity(x: any): number
	return x.strongHairlineOpacity or math.max(0, 1 - (1 - x.hairlineOpacity) * 3)
end

-- THE PHANTOM STROKE'S MODE (director round 10, found live 2026-07-26).
--
-- `UIStroke.ApplyStrokeMode` defaults to **Contextual**, and on a TextButton or
-- TextLabel that means the stroke is drawn around the GLYPHS, not around the
-- border. Every stroke this compiler emits is a border hairline, so every one of
-- them has to say so: the bespoke path always did (`hairline()` in
-- screen_target writes `ApplyStrokeMode.Border` explicitly), the rule-owned path
-- inherited the engine default, and the two diverged silently.
--
-- What it looked like: under classic-desktop the picker's chip outline never
-- drew at all and every chip LABEL grew a hairline-coloured halo — measured at
-- the shipped stamp as a 3.35x larger mid-tone (halo) pixel fraction and 17%
-- softer glyph edges than the same frame with Border. Under Facet Neutral the
-- hairline is white and the label is white, so it hid for two whole stages.
local STROKE_BORDER: RuleProp = { kind = "enum", enum = "ApplyStrokeMode", item = "Border" }
sheet_model.STROKE_BORDER = STROKE_BORDER
-- ...AND INSIDE THE BOX. The engine default is
-- `Outer`, which overhangs the rect by the stroke's thickness, so a scroller's
-- clip sliced the left edge of every stroked card and pill. Inner keeps the band
-- inside the box, and `render/layout_node` pays for it in padding.
local STROKE_INNER: RuleProp = { kind = "enum", enum = "BorderStrokePosition", item = "Inner" }
sheet_model.STROKE_INNER = STROKE_INNER

-- THE SELECTED STATE'S CONTENT COLOUR (director round 8, the palette
-- contract; the 3.5 `togglePalette` ruling is the precedent).
--
-- A theme guarantees exactly two readable pairs: surface/content and
-- accent/onAccent, both gated at 4.5:1 by `gateTheme`. The SELECTED state is a
-- third surface — `extra.controlSelected`, the colour the framework's own
-- `Selected row` rule paints and the colour a package's selected ART is
-- declaring itself to be — and nothing ever paired a content colour with it. So
-- a selected label kept `$Content` whatever the plate underneath became:
-- measured live under glossy-touch at 3.74:1 on its blue gel, which is what the
-- director could not read.
--
-- THE MAPPING, and why each half is what it is:
--
--   content   the status quo, and the answer wherever it still clears the
--             contract's own 4.5 floor against the selected surface — which is
--             every reference theme except pixel-quest. Preferring it (rather
--             than taking whichever scores HIGHER) is what keeps Facet Neutral
--             and every flat package byte-identical: neutral's selected surface
--             reads content at 9.74:1 and onAccent at 11.22:1, and switching it
--             would have been a visible change with no defect behind it.
--   onAccent  the GUARANTEED partner, taken only when content fails. It is the
--             one colour a theme promises is readable against its accent, and a
--             selected surface is an accent-washed control by construction
--             (`effectiveExtra` derives it as control lerped 35% toward accent).
--             Measured on pixel-quest's gold plate: content 1.75:1, onAccent
--             8.47:1.
--
-- A theme whose selected surface can carry NEITHER is a palette defect, not a
-- resolver case: `gateSelectedPair` below refuses it at define time, exactly as
-- `gateTheme` refuses an unreadable accent pair.
--
-- Pure, exported, and read by ONE token (`$OnSelected`) so the skinned lift and
-- the unskinned row resolve the same decision.
local SELECTED_CONTRAST_FLOOR = 4.5

local function selectedSurfaceOf(theme: any): { r: number, g: number, b: number }
	local c = theme.colors
	local x = theme.extra or {}
	if type(x.controlSelected) == "table" then
		return x.controlSelected
	end
	local control = if type(x.control) == "table" then x.control else c.surfaceStrong
	return lerp(control, c.accent, 0.35) :: any
end
sheet_model.selectedSurfaceOf = selectedSurfaceOf

-- SELECTED UNDER HOVER: the selected fill with the theme's own hover step on
-- top (controlHover - control), so a hovered selected row never reads as plain
-- hover. One formula for the sheet token and the fallback painter.
function sheet_model.selectedHoverColor(x: any): { r: number, g: number, b: number }
	local function ch(k: string): number
		return math.clamp(x.controlSelected[k] + x.controlHover[k] - x.control[k], 0, 1)
	end
	return { r = ch("r"), g = ch("g"), b = ch("b") }
end

function sheet_model.selectedContentColor(theme: any): { r: number, g: number, b: number }
	local c = theme.colors
	local surface = selectedSurfaceOf(theme)
	if tokens.contrastRatio(c.content, surface) >= SELECTED_CONTRAST_FLOOR then
		return { r = c.content.r, g = c.content.g, b = c.content.b }
	end
	return { r = c.onAccent.r, g = c.onAccent.g, b = c.onAccent.b }
end

--[[ THE LABEL ON A TINTED CONTROL PLATE: a skinned control's art multiplied by
	`tint`. The art's colour as painted is the package's `extra.controlArt` (its
	sampled centre), else its flat `control`; another slot's art is `extra[art]`
	(`fieldArt`, `badgeArt`). Art that lets the panel through (`a` < 1, a badge
	seal) reads over the surface. `onAccent` when it clears the floor there, else
	`content` when that does, else whichever reads better. ]]
local function chromePlate(theme: any, tint: any, art: string?): { r: number, g: number, b: number }
	local x = theme.extra or {}
	local base = if art ~= nil and type(x[art]) == "table"
		then x[art]
		elseif type(x.controlArt) == "table" then x.controlArt
		elseif type(x.control) == "table" then x.control
		else theme.colors.surfaceStrong
	local a, s = base.a or 1, theme.colors.surface
	return {
		r = base.r * tint.r * a + s.r * (1 - a),
		g = base.g * tint.g * a + s.g * (1 - a),
		b = base.b * tint.b * a + s.b * (1 - a),
	}
end
sheet_model.chromePlate = chromePlate

function sheet_model.onChromeColor(theme: any, tint: any): { r: number, g: number, b: number }
	local c = theme.colors
	local plate = chromePlate(theme, tint)
	local on, content = tokens.contrastRatio(c.onAccent, plate), tokens.contrastRatio(c.content, plate)
	local pick = if on >= SELECTED_CONTRAST_FLOOR or on >= content then c.onAccent else c.content
	return { r = pick.r, g = pick.g, b = pick.b }
end

--[[ ...AND ANY OTHER LIFTED LABEL on its tinted art: the first of `picks` that
	clears the floor there, else whichever reads best. A plain button offers
	content first (every flat-art package keeps its label), then contentStrong and
	onAccent; a destructive one offers onDanger first. ]]
function sheet_model.readableOnChrome(
	theme: any,
	tint: any,
	picks: { any },
	art: string?
): { r: number, g: number, b: number }
	local plate = chromePlate(theme, tint, art)
	local best, bestRatio = picks[1], -1
	for _, pick in picks do
		local ratio = tokens.contrastRatio(pick, plate)
		if ratio >= SELECTED_CONTRAST_FLOOR then
			return { r = pick.r, g = pick.g, b = pick.b }
		end
		if ratio > bestRatio then
			best, bestRatio = pick, ratio
		end
	end
	return { r = best.r, g = best.g, b = best.b }
end

-- the gate the resolver leans on: SOME content role must be readable on the
-- selected surface, or the theme has published a state nobody can read
function sheet_model.selectedPairReport(theme: any): any
	local c = theme.colors
	local surface = selectedSurfaceOf(theme)
	local content = tokens.contrastRatio(c.content, surface)
	local onAccent = tokens.contrastRatio(c.onAccent, surface)
	return {
		surface = surface,
		content = math.floor(content * 100) / 100,
		onAccent = math.floor(onAccent * 100) / 100,
		picked = if content >= SELECTED_CONTRAST_FLOOR then "content" else "onAccent",
		ok = math.max(content, onAccent) >= SELECTED_CONTRAST_FLOOR,
		floor = SELECTED_CONTRAST_FLOOR,
	}
end

-- theme token set from a compiled Facet style (plan §6.1 naming: schema keys
-- PascalCased so the Style Editor shows words designers know from the docs)
local function themeTokens(style: any): { [string]: TokenValue }
	local c, x = style.colors, style.extra
	return {
		Danger = color((select(1, dangerPair(c)))),
		OnDanger = color((select(2, dangerPair(c)))),
		-- role interaction tokens, precomputed with the same edge lerp the control
		-- tokens use so a destructive button's states read as the same family
		DangerHover = lerp((select(1, dangerPair(c))), { r = 1, g = 1, b = 1 }, 0.12),
		DangerPressed = lerp((select(1, dangerPair(c))), { r = 0, g = 0, b = 0 }, 0.12),
		-- the two SEMANTIC fills and their readable partners, from the same
		-- effective pairs the gate runs on. No hover/press twins: neither is a
		-- role a control can be PRESSED in — they are what a status IS
		Success = color((select(1, successPair(c)))),
		OnSuccess = color((select(2, successPair(c)))),
		Warning = color((select(1, warningPair(c)))),
		OnWarning = color((select(2, warningPair(c)))),
		Surface = color(c.surface),
		SurfaceStrong = color(c.surfaceStrong),
		Content = color(c.content),
		ContentStrong = color(c.contentStrong),
		Accent = color(c.accent),
		OnAccent = color(c.onAccent),
		-- the SELECTED state's readable partner (director round 8). Derived, per
		-- theme, from the theme's own selected surface — never a hardcode, and
		-- never a second palette role an author has to remember to declare.
		OnSelected = color(sheet_model.selectedContentColor(style)),
		Control = color(x.control),
		ControlHover = color(x.controlHover),
		ControlPressed = color(x.controlPressed),
		ControlSelected = color(x.controlSelected),
		ControlSelectedHover = color(sheet_model.selectedHoverColor(x)),
		ContentSecondary = color(x.contentSecondary),
		Hairline = color(x.hairline),
		-- optional roles: unauthored, each is the colour its consumers painted before
		Selection = color(x.selection or c.accent),
		OnSelection = color(x.onSelection or c.onAccent),
		Scrim = color(x.scrim or c.surface),
		-- each plate at the disabled content opacity over the page, for a theme that
		-- dims a disabled control whole (`extra.dimDisabledPlates`)
		ControlDisabled = lerp(x.control, c.surface, x.disabledContentOpacity or 0.4),
		ControlSelectedDisabled = lerp(x.controlSelected, c.surface, x.disabledContentOpacity or 0.4),
		AccentDisabled = lerp(c.accent, c.surface, x.disabledContentOpacity or 0.4),
		DangerDisabled = lerp((select(1, dangerPair(c))), c.surface, x.disabledContentOpacity or 0.4),
		SelectionDisabled = lerp(x.selection or c.accent, c.surface, x.disabledContentOpacity or 0.4),
		-- precomputed accent interaction states (bespoke path computes these
		-- with Color3:Lerp at the edge; the sheet needs them as real tokens)
		AccentHover = lerp(c.accent, WHITE, 0.12),
		AccentPressed = lerp(c.accent, BLACK, 0.18),
	}
end

-- every theme's palette re-passes the library contrast gate before it may be
-- selected (§6.7): surface/content, surfaceStrong/contentStrong, accent/onAccent
local function gateTheme(name: string, style: any)
	local report = { ok = true, pairs = {} }
	for _, pair in
		{
			{ "surface", "content" },
			{ "surfaceStrong", "contentStrong" },
			{ "accent", "onAccent" },
			{ "danger", "onDanger" },
			{ "success", "onSuccess" },
			{ "warning", "onWarning" },
		}
	do
		local a, b = style.colors[pair[1]], style.colors[pair[2]]
		local semantic = SEMANTIC_ROLE[pair[1]]
		if semantic ~= nil then
			a, b = semantic.pair(style.colors)
		end
		local ratio = tokens.contrastRatio(a, b)
		local ok = ratio >= 4.5
		if not ok then
			report.ok = false
		end
		table.insert(report.pairs, { pair = `{pair[2]} on {pair[1]}`, ratio = math.floor(ratio * 100) / 100, ok = ok })
	end
	assert(report.ok, `sheet_model: theme '{name}' fails the contrast gate`)
	return report
end

local BUILDER_SANS: RuleProp = { kind = "font", family = "rbxasset://fonts/families/BuilderSans.json" }
-- the two WEIGHT-ROLE faces of the same family (F2, 2026-08-02). SemiBold for
-- `strong` and Bold for `numeral`, which is exactly what
-- `themes.package.deriveTypeRole` derives — stated in both places because the
-- token-style path has no font descriptors to derive FROM, and asserted equal by
-- a spec so the two can never drift.
local BUILDER_SANS_SEMIBOLD: RuleProp =
	{ kind = "font", family = "rbxasset://fonts/families/BuilderSans.json", weight = "SemiBold", style = "Normal" }
local BUILDER_SANS_BOLD: RuleProp =
	{ kind = "font", family = "rbxasset://fonts/families/BuilderSans.json", weight = "Bold", style = "Normal" }
local function udim(scale: number, offset: number): RuleProp
	return { kind = "udim", scale = scale, offset = offset }
end
local function num(v: number): RuleProp
	return { kind = "number", value = v }
end

-- THE class-default naming vocabulary. The engine class is not the name a
-- designer reads: `Label default` and `Field default` are what the styling
-- guide, the Style Editor and every saved edit already call these rules, and
-- `build` established that vocabulary. `buildPackage` applies this map so it
-- cannot drift from it; `sheet_model.spec` asserts the two name sets agree.
local CLASS_DEFAULT_NAME: { [string]: string } = {
	Frame = "Frame",
	TextLabel = "Label",
	TextButton = "Button",
	ImageLabel = "Image",
	TextBox = "Field",
	ScrollingFrame = "Scroll",
	-- the mask wrapper a `mask`ed layer is built in (R1, probe rs-m9). It is a
	-- SILHOUETTE, and a silhouette that paints its own background would put a
	-- solid pill behind the very art it is shaping — found live at stamp
	-- 62b6cdeb-1689276, where the fresh CanvasGroup sat at BackgroundTransparency
	-- 0 because no class rule reached it. Owned by a RULE, not an adapter write,
	-- for the same reason every other class default is (spike m10).
	CanvasGroup = "Canvas",
}
sheet_model.CLASS_DEFAULT_NAME = CLASS_DEFAULT_NAME

-- deterministic FNV-1a over the serialized model content (no clock, resumable)
local function stampOf(parts: { string }): string
	local hash = 2166136261
	for _, s in parts do
		for i = 1, #s do
			hash = bit32.bxor(hash, string.byte(s, i))
			hash = bit32.band(hash * 16777619, 0xFFFFFFFF)
		end
	end
	return string.format("%08x", hash)
end

-- ===========================================================================
-- THE VALUE-CONTROL OWN-PAINT FAMILY — ONE EMITTER, BOTH BUILDERS
-- (rich-skinning v2)
-- ===========================================================================
--
-- These four surfaces (`chrome_slots.OWN_PAINT_SLOTS`: a slider's rail and
-- thumb, a progress bar's track and fill) are reached ONLY through the internal
-- decoration hint, never through a public `surface` — so nothing else paints
-- them and the sheet has to. `Frame default` sets BackgroundTransparency = 1,
-- which means "no rule" does not read as "unstyled": it reads as INVISIBLE.
--
-- WHY THIS IS A SHARED FUNCTION AND NOT A LOOP INSIDE ONE BUILDER. It used to
-- be a loop inside `buildPackage`, whose own comment said "emitted for every
-- package including the flat ones — a value control has to be visible under
-- Facet Neutral too". Facet Neutral was the one path it was not emitted on:
-- with no package installed the live sheet is `build`'s base seed, which emitted
-- none of the family, so the default Download bar painted nothing at all
-- (pixel-identical at 0% and 100%) and the default Brightness slider had no rail
-- and no thumb. Two builders, one requirement, one emitter — a second copy is
-- how this defect class breeds.
--
-- The token map is the same `SLOT_FILL_TOKEN` the asset-failure fallback and the
-- bespoke path (`src/client/screen_chrome.luau`'s `chromeFillOf`) read, so a
-- slot's flat appearance is ONE decision on all three paths.

-- what a slot's declared NATIVE fallback paints when its asset fails to load,
-- and what the own-paint family paints when nothing skins it at all
local SLOT_FILL_TOKEN: { [string]: string } = {
	panel = "$SurfaceStrong",
	control = "$Control",
	field = "$Control",
	selection = "$ControlSelected",
	divider = "$Hairline",
	scrollbar = "$Control",
	sliderTrack = "$Control",
	sliderThumb = "$SurfaceStrong",
	badge = "$SurfaceStrong",
	-- v2 value displays. The track is a control surface and the
	-- fill is the accent, which is what a flat progress bar already looks like;
	-- the caps and the centrepiece are ornaments with no unskinned counterpart,
	-- so their fallback is the accent they decorate rather than a shape of their
	-- own. A toggle's flat truth stays `togglePalette`; these tokens only paint
	-- if its ART fails to load.
	barTrack = "$Control",
	barFill = "$Accent",
	barCap = "$Accent",
	barCenter = "$Accent",
	stepperPlate = "$Control",
	toggleTrack = "$Control",
	toggleKnob = "$SurfaceStrong",
	-- the indeterminate spinner's dot (parity round 2 §3.1): an unskinned
	-- spinner is a ring of accent dots, the same flat truth `barFill` carries
	spinner = "$Accent",
}
-- slots whose fallback shape is a CIRCLE (a thumb, a counter seal, a switch
-- knob): a square fallback under round art reads as a different control, not as
-- a degraded one
local SLOT_ROUND: { [string]: boolean } = { sliderThumb = true, badge = true, toggleKnob = true, spinner = true }

local function slotRadius(metrics: any, slot: string): number
	if slot == "panel" then
		return metrics.radii.panel
	elseif slot == "divider" or slot == "scrollbar" then
		return 0
	end
	return metrics.radii.control
end

-- emitOwnSlotPaint: the three rules that make ONE value slot visible without
-- art — fill, phantom ::UICorner radius, phantom ::UIStroke hairline — keyed on
-- the slot IDENTITY tag (`facet-slot-<slot>`), which the renderer applies whether
-- or not a package skins the node.
--
-- `emit` takes the rule (the caller decides which ordered group it lands in);
-- `fromMetric` is optional because only the package builder can push a live
-- metric edit onto a baked literal.
local function emitOwnSlotPaint(
	slot: string,
	metrics: any,
	hairlineT: RuleProp,
	hairlineW: RuleProp,
	emit: (Rule) -> (),
	fromMetric: ((string, string, string, string) -> ())?
)
	local tag = chrome_slots.slotTagFor(slot)
	emit({
		name = `Slot — {slot}`,
		selector = `.{tag}`,
		props = { BackgroundColor3 = SLOT_FILL_TOKEN[slot], BackgroundTransparency = num(0) },
	})
	emit({
		name = `Slot — {slot} corner`,
		selector = `.{tag}::UICorner`,
		props = {
			CornerRadius = if SLOT_ROUND[slot] then udim(0.5, 0) else udim(0, slotRadius(metrics, slot)),
		},
	})
	if fromMetric ~= nil and not SLOT_ROUND[slot] then
		fromMetric("radii.control", `Slot — {slot} corner`, "CornerRadius", "udimOffset")
	end
	-- the hairline uses the package's OWN stroke vocabulary, so a theme that
	-- thickened its hairlines gets a thumb that matches its buttons
	emit({
		name = `Slot — {slot} outline`,
		selector = `.{tag}::UIStroke`,
		props = {
			Color = "$Hairline",
			Transparency = hairlineT,
			Thickness = hairlineW,
			ApplyStrokeMode = STROKE_BORDER,
			BorderStrokePosition = STROKE_INNER,
		},
	})
	if fromMetric ~= nil then
		fromMetric("strokes.hairline", `Slot — {slot} outline`, "Thickness", "number")
	end
end

-- emitSlotSuppression: the mirror image — the three rules that STOP the native
-- plate being drawn once art covers the node (`facet-skinned-<slot>`). Shared for
-- the same reason the paint is: the pre-arm the base seed needs and the per-slot
-- suppression a package's recipes need are the same three rules.
local function emitSlotSuppression(slot: string, emit: (Rule) -> ())
	local skinnedTag = chrome_slots.skinnedTagFor(slot)
	emit({
		name = `Skinned — {slot}`,
		selector = `.{skinnedTag}`,
		props = { BackgroundTransparency = num(1) },
	})
	emit({
		name = `Skinned — {slot} corner`,
		selector = `.{skinnedTag}::UICorner`,
		props = { CornerRadius = udim(0, 0) },
	})
	emit({
		name = `Skinned — {slot} outline`,
		selector = `.{skinnedTag}::UIStroke`,
		props = {
			Thickness = num(0),
			Transparency = num(1),
			ApplyStrokeMode = STROKE_BORDER,
			BorderStrokePosition = STROKE_INNER,
		},
	})
end

-- Managed pictures inherit a host's explicit partner lettering through native rules.
-- Both builders append these after name colors and generated-content projections.
local function emitStatusIconTint(emit: (Rule) -> ())
	for _, role in sheet_model.STATUS_LETTERS do
		local selector = `.{sheet_model.TAGS.letterPrefix}{role} > .{chrome_slots.ICON_PICTURE_TAG}`
		sheet_model.checkSelector(selector, "Status lettering")
		local allowed, reason = themePackage.lintProperty("ImageColor3", "chrome")
		assert(allowed, reason)
		emit({
			name = `Status lettering — {role}`,
			selector = selector,
			props = { ImageColor3 = statusLetterToken(role) },
		})
	end
end

-- ===========================================================================
-- THE CIRCLE BUTTON'S CHROME — ONE EMITTER, BOTH BUILDERS
-- (feature round 2026-07-26; `UI.Button{ shape = "circle" }`)
-- ===========================================================================
--
-- A disc's silhouette is the pill radius the slider thumb already proved:
-- `CornerRadius = UDim(0.5, 0)` on a phantom `::UICorner`, which costs a FLAT
-- theme zero new instances because the rule creates the modifier. Its rim is a
-- hairline on a phantom `::UIStroke` — and it carries `ApplyStrokeMode = Border`
-- explicitly, because the engine default is `Contextual`, which on a TextButton
-- strokes the GLYPHS instead of the border (director round 10, measured live:
-- every chip label grew a hairline halo and no outline drew at all).
--
-- WHY EXACTLY TWO RULES AND NOT ONE PER STATE. The cascade is Priority first,
-- then insertion order, with NO selector specificity — so a rule that sits after
-- every surface corner beats every surface corner, whichever surface the node
-- happens to wear. That is the finding-11 requirement ("a new surface/shape must
-- carry its own corner rule") satisfied at its source: the SHAPE carries the
-- corner, instead of every surface having to learn about the shape. Duplicating
-- it into the hover/press/disabled groups would be worse than redundant: a rule
-- NAME IS IDENTITY here (see `emitSuppression` below), so five same-named rules
-- are five Style-Editor entries a designer's edit picks between at random. What
-- makes one rule sufficient is an invariant, not a coincidence, so it is
-- asserted rather than assumed: `tests/button_shape.spec.luau` fails if ANY rule
-- after this one writes CornerRadius on a selector a circle Button matches,
-- except the skinned-slot suppression, which must win (see below).
--
-- THE ONE RULE THAT BEATS IT, ON PURPOSE. `Skinned — control corner` sits in the
-- `chrome` group and zeroes the radius of a node whose art has taken over. That
-- is the image-is-the-element posture and it is correct for a
-- circle too: once a package dresses the button, the ART is the silhouette and
-- the node's own plate is invisible underneath it, so its radius means nothing.
local function emitShapeChrome(
	metrics: any,
	hairlineT: RuleProp,
	hairlineW: RuleProp,
	emit: (Rule) -> (),
	fromMetric: ((string, string, string, string) -> ())?
)
	local circle = sheet_model.TAGS.shapePrefix .. "circle"
	emit({
		name = "Circle button — corner",
		selector = `.{circle}::UICorner`,
		props = { CornerRadius = udim(0.5, 0) },
	})
	emit({
		name = "Circle button — hairline",
		selector = `.{circle}.{sheet_model.TAGS.circleRim}::UIStroke`,
		props = {
			Color = "$Hairline",
			Transparency = hairlineT,
			Thickness = hairlineW,
			ApplyStrokeMode = STROKE_BORDER,
			BorderStrokePosition = STROKE_INNER,
		},
	})
	if fromMetric ~= nil then
		fromMetric("strokes.hairline", "Circle button — hairline", "Thickness", "number")
	end
end

-- ===========================================================================
-- THE LOCAL SIZE / EMPHASIS CHROME — ONE EMITTER, BOTH BUILDERS
-- (`src/controls/control_vocabulary.luau`; tags declared in TAGS above)
-- ===========================================================================
--
-- FACET NEUTRAL IS THE REFERENCE, so it paints every tag it mints rather than
-- leaving a package to discover which ones matter. Two families:
--
--   * the SIZE rungs carry a CORNER, each from a PUBLISHED radius and never from
--     arithmetic on one. A rung changes the plate's height through the metric
--     ladder, and a bigger plate wearing a smaller plate's radius reads as a
--     stretched version of it rather than as its own control — so `large` takes
--     the next published radius up (`radii.panel`) while `compact` and `regular`
--     both take `radii.control`, which is all Facet Neutral publishes below it.
--     THE THREE RULES EXIST EVEN WHERE TWO AGREE, on the `facet-type-<role>`
--     precedent: a rule that restates what its neighbour says is inert under a
--     package whose ladder shares one radius and load-bearing the moment a package
--     gives a rung its own. A DERIVED number was tried and refused — `radii.control
--     - space.xs` is not a paint-family number, so it does not ride the ten-foot
--     1.5x the way every other corner in this sheet does (`space` is not a scaled
--     section), and a corner that scales differently from its neighbours is the
--     measure/paint split one property down. Every rung therefore also gets a
--     live-edit push, which a derived value could never have had.
--   * the EMPHASIS words carry a FILL AND ITS READABLE PARTNER, and every pair
--     below is one this library already ships gated: emphasis is ($Accent,
--     $OnAccent) — the theme contract's one guaranteed pair; soft is
--     ($ControlSelected, $OnSelected) — the derived partner the "Selected row"
--     rule already proves; utility is ($Surface, $ContentSecondary) — the shipped
--     "Cancel button" pair, plus a hairline so a quiet control still has an edge;
--     link paints NO plate at all and takes $Accent, which is what a text link is.
--     No new palette role is invented for any of them.
--
-- ORDERING, WHICH IS THE CASCADE. Corners and the utility outline go in
-- `surfaces`, BEFORE `emitShapeChrome`'s `roles`-group disc rules, so a compact
-- circle is still a circle. The fills go in `roles`, after every surface fill they
-- must beat and before the hover/press rules that still layer on top — the same
-- placement the destructive role's own comment argues for.
local function emitVocabularyChrome(
	metrics: any,
	hairlineT: RuleProp,
	hairlineW: RuleProp,
	emitSurface: (Rule) -> (),
	emitRole: (Rule) -> (),
	fromMetric: ((string, string, string, string) -> ())?
)
	local T = sheet_model.TAGS
	local radii = metrics.radii
	emitSurface({
		name = "Control size — xsmall corner",
		selector = `.{T.sizePrefix}xsmall::UICorner`,
		props = { CornerRadius = udim(0, radii.control) },
	})
	emitSurface({
		name = "Control size — compact corner",
		selector = `.{T.sizePrefix}compact::UICorner`,
		props = { CornerRadius = udim(0, radii.control) },
	})
	emitSurface({
		name = "Control size — regular corner",
		selector = `.{T.sizePrefix}regular::UICorner`,
		props = { CornerRadius = udim(0, radii.control) },
	})
	emitSurface({
		name = "Control size — large corner",
		selector = `.{T.sizePrefix}large::UICorner`,
		props = { CornerRadius = udim(0, radii.panel) },
	})
	-- `strokes.utility` (optional, 0 = no outline) retunes this edge alone
	local utilityStroke = metrics.strokes and metrics.strokes.utility
	emitSurface({
		name = "Utility control — outline",
		selector = `.{T.appearancePrefix}utility::UIStroke`,
		props = {
			Color = "$Hairline",
			Transparency = hairlineT,
			Thickness = if utilityStroke ~= nil then num(utilityStroke) else hairlineW,
			ApplyStrokeMode = STROKE_BORDER,
			BorderStrokePosition = STROKE_INNER,
		},
	})
	if fromMetric ~= nil then
		fromMetric("radii.control", "Control size — xsmall corner", "CornerRadius", "udimOffset")
		fromMetric("radii.control", "Control size — compact corner", "CornerRadius", "udimOffset")
		fromMetric("radii.control", "Control size — regular corner", "CornerRadius", "udimOffset")
		fromMetric("radii.panel", "Control size — large corner", "CornerRadius", "udimOffset")
		fromMetric(
			if utilityStroke ~= nil then "strokes.utility" else "strokes.hairline",
			"Utility control — outline",
			"Thickness",
			"number"
		)
	end
	emitRole({
		name = "Emphasis control",
		selector = `.{T.appearancePrefix}emphasis`,
		props = { BackgroundColor3 = "$Accent", BackgroundTransparency = num(0), TextColor3 = "$OnAccent" },
	})
	emitRole({
		name = "Soft emphasis control",
		selector = `.{T.appearancePrefix}soft`,
		props = {
			BackgroundColor3 = "$ControlSelected",
			BackgroundTransparency = num(0),
			TextColor3 = "$OnSelected",
		},
	})
	emitRole({
		name = "Utility control",
		selector = `.{T.appearancePrefix}utility`,
		props = { BackgroundColor3 = "$Surface", BackgroundTransparency = num(0), TextColor3 = "$ContentSecondary" },
	})
	--[[ A LINK HAS NO PLATE, and that is the one thing this rule exists to say.
		Every Button leaf takes the `control` surface at create, so a link has to
		un-paint it rather than merely decline one — and it says so with a
		TRANSPARENCY, which a rule may write freely (the "a write equal to the class
		default claims nothing" trap is about explicit per-node WRITES, not rules). ]]
	emitRole({
		name = "Link control",
		selector = `.{T.appearancePrefix}link`,
		props = { BackgroundTransparency = num(1), TextColor3 = "$Accent" },
	})
	--[[ OVER ARTWORK, THE PAIR IS THE POINT. A control drawn on a photograph cannot
		borrow the contrast of a background the theme controls, so it takes the
		gated ($SurfaceStrong, $ContentStrong) pair opaque — and its interaction
		states move to the OTHER gated pair ($Surface, $Content) rather than to the
		control ramp, so it stays readable through hover and press instead of
		inheriting a fill chosen to sit on the theme's own background. ]]
	emitRole({
		name = "Control over media",
		selector = `.{T.overMedia}`,
		props = {
			BackgroundColor3 = "$SurfaceStrong",
			BackgroundTransparency = num(0),
			TextColor3 = "$ContentStrong",
		},
	})
end

--[[ THE COMPOUND `role` x `appearance` RULES — the composition the docs print in
	four places, made true in the cascade rather than asserted about a tag.

	`role` is the SEMANTIC channel and `appearance` is EMPHASIS, so the two loud
	words hand the plate to the role (a destructive emphasis button IS the danger
	plate, which is what the shipped `Destructive button` rule already paints), and
	the three quiet words keep their own plate while the role colours the CONTENT.
	That is the quiet delete the guide describes: a utility plate carrying danger
	lettering, a link with no plate and danger lettering, a soft tint with the same.

	They are emitted AFTER the role rules, which is the only reason they win: the
	cascade is priority then insertion order, and a compound selector earns no
	specificity here. Round 1 omitted them, so `Destructive button` landed last and
	a destructive link painted $OnDanger — a colour gated only against $Danger — on
	no plate at all. ]]
local function emitVocabularyRoles(emitRole: (Rule) -> ())
	local A = sheet_model.TAGS.appearancePrefix
	emitRole({
		name = "Destructive utility",
		selector = `.facet-role-destructive.{A}utility`,
		props = { BackgroundColor3 = "$Surface", BackgroundTransparency = num(0), TextColor3 = "$Danger" },
	})
	emitRole({
		name = "Destructive soft",
		selector = `.facet-role-destructive.{A}soft`,
		props = { BackgroundColor3 = "$ControlSelected", BackgroundTransparency = num(0), TextColor3 = "$Danger" },
	})
	-- no `BackgroundColor3` at all: a link's plate is its absence, and naming a
	-- colour for a plate nobody paints is how a later rule finds one to reveal
	emitRole({
		name = "Destructive link",
		selector = `.facet-role-destructive.{A}link`,
		props = { BackgroundTransparency = num(1), TextColor3 = "$Danger" },
	})
end

--[[ THE INTERACTION STATES, EMITTED AFTER THE GENERIC ONES IN BOTH BUILDERS.

	`Control — hover`/`Control — pressed` key on the INTERACTIVE tag, not on the
	appearance, so an emphasis button hovered without a later rule repaints itself
	neutral — the defect the shipped `Destructive — hover` pair exists to prevent,
	one axis over. Every word gets a pair, and each pair carries the READABLE
	PARTNER of whatever fill it names: that is the half the generic rule cannot do,
	because it changes the plate and leaves the resting content colour on it.

	`soft` and `utility` deliberately hand their plate BACK to the control ramp on
	interaction — a quiet control becoming an ordinary one is the right read for a
	press — and the rule exists to carry $Content with it rather than to stop the
	fill moving. `link` changes only its lettering; the resting rule keeps its
	plate invisible.

	SEPARATE FROM `emitVocabularyChrome` because the two halves belong at different
	points in the cascade, and `buildPackage` emits the generic states hundreds of
	rules after its surfaces. Round 1 emitted both halves at the surface point, so
	under EVERY installed package all ten rules were dead. ]]
local function emitVocabularyStates(emitHover: (Rule) -> (), emitPress: (Rule) -> (), pointerLive: string)
	local T = sheet_model.TAGS
	local A = T.appearancePrefix
	--[[ THE HOVER EASES THE PROPERTY THE RULE ACTUALLY WRITES. A blanket
		`BackgroundColor3 = "fast"` declared a transition for a property a link's rule
		never names, and left the one it does name — its lettering — snapping. A rule
		says which channel it moved; the transition follows it. ]]
	local function pair(name: string, selector: string, hover: { [string]: RuleProp }, press: { [string]: RuleProp })
		local eased = if hover.BackgroundColor3 ~= nil then "BackgroundColor3" else "TextColor3"
		emitHover({
			name = `{name} — hover`,
			selector = `TextButton.{selector}.{pointerLive}:Hover`,
			props = hover,
			transitions = { [eased] = "fast" },
		})
		emitPress({ name = `{name} — pressed`, selector = `TextButton.{selector}:Press`, props = press })
	end
	pair(
		"Emphasis",
		`{A}emphasis`,
		{ BackgroundColor3 = "$AccentHover", TextColor3 = "$OnAccent" },
		{ BackgroundColor3 = "$AccentPressed", TextColor3 = "$OnAccent" }
	)
	pair(
		"Soft",
		`{A}soft`,
		{ BackgroundColor3 = "$ControlHover", TextColor3 = "$Content" },
		{ BackgroundColor3 = "$ControlPressed", TextColor3 = "$Content" }
	)
	pair(
		"Utility",
		`{A}utility`,
		{ BackgroundColor3 = "$ControlHover", TextColor3 = "$Content" },
		{ BackgroundColor3 = "$ControlPressed", TextColor3 = "$Content" }
	)
	--[[ A LINK'S STATES MOVE ONLY ITS LETTERING, and that is a rule about the SHEET
		rather than a preference: no `:Hover`/`:Press` rule either builder emits may
		carry a `BackgroundTransparency`, because the catcher-paint oracle resolves a
		resting fill by skipping every state rule and would report the wrong number
		for a node that was painting one (`tests/popup_catcher_paint.spec`). The plate
		stays invisible anyway — the resting `Link control` rule owns the
		transparency and nothing in the control ramp touches it. ]]
	pair("Link", `{A}link`, { TextColor3 = "$AccentHover" }, { TextColor3 = "$AccentPressed" })
	-- over artwork the states move to the OTHER gated pair rather than to the
	-- control ramp, so the control stays readable on a photograph it cannot see
	pair(
		"Over media",
		T.overMedia,
		{ BackgroundColor3 = "$Surface", TextColor3 = "$Content" },
		{ BackgroundColor3 = "$SurfaceStrong", TextColor3 = "$ContentStrong" }
	)
	--[[ ...AND THE ROLE SURVIVES THE CLICK, which is the other half of the same
		argument and belongs in this emitter rather than beside it: these rules must
		land immediately after the per-word ones, and the only way to guarantee that
		in two builders is to emit them from the same call.

		`emitVocabularyRoles` composes `role` with `appearance` AT REST — the loud
		words hand the plate to the role, the quiet ones keep their plate and let the
		role colour the content. The per-word state rules above name those same two
		channels and are emitted later, so without these a hovered quiet delete became
		an ordinary neutral control, a destructive link's lettering turned ACCENT, and
		a destructive emphasis button hovered accent rather than danger. Touch has no
		hover, but `:Press` behaves identically, so every device saw it.

		EACH PAIR KEEPS THE DANGER SIGNAL ON THE CHANNEL ITS WORD LEAVES FREE, and
		moves it with the state so the control still acknowledges the press.
		`standard` needs no pair: it mints no appearance tag, so the shipped
		`Destructive — hover/pressed` rules are already the last word on it. And none
		of them carries a transparency — see the link note above. ]]
	local function rolePair(word: string, hover: { [string]: RuleProp }, press: { [string]: RuleProp })
		pair(`Destructive {word}`, `facet-role-destructive.{A}{word}`, hover, press)
	end
	-- the role owns the PLATE here, so the danger family moves on the plate and
	-- carries its gated partner with it
	rolePair(
		"emphasis",
		{ BackgroundColor3 = "$DangerHover", TextColor3 = "$OnDanger" },
		{ BackgroundColor3 = "$DangerPressed", TextColor3 = "$OnDanger" }
	)
	-- ...and here the WORD owns the plate, so the danger signal is the lettering and
	-- the plate is left to the per-word rule above
	rolePair("soft", { TextColor3 = "$DangerHover" }, { TextColor3 = "$DangerPressed" })
	rolePair("utility", { TextColor3 = "$DangerHover" }, { TextColor3 = "$DangerPressed" })
	rolePair("link", { TextColor3 = "$DangerHover" }, { TextColor3 = "$DangerPressed" })
end

--[[ THE SELECTION MARK — painted only when a theme AUTHORS `extra.selection`.
	A selected chip, a checkbox's fill and its tick then wear the selection ink
	and its partner instead of the selected-row wash. No theme that leaves the
	role out gets these rules, so its chips and checkboxes paint as before. The
	hover rule keeps a hovered chosen chip chosen (after every per-word state). ]]
local function authoredSelection(themes: { any }): boolean
	for _, theme in themes do
		if type(theme) == "table" and type(theme.extra) == "table" and theme.extra.selection ~= nil then
			return true
		end
	end
	return false
end

local function emitSelectionMark(emitRest: (Rule) -> (), emitHover: (Rule) -> (), pointerLive: string)
	local T = sheet_model.TAGS
	emitRest({
		name = "Selection mark — chosen",
		selector = `TextButton.{T.selected}.{T.selectionMark}`,
		props = { BackgroundColor3 = "$Selection", TextColor3 = "$OnSelection" },
	})
	emitRest({
		name = "Selection mark — fill",
		selector = `Frame.{T.selectionMark}`,
		props = { BackgroundColor3 = "$Selection", BackgroundTransparency = num(0) },
	})
	emitRest({
		name = "Selection mark — ink",
		selector = `TextLabel.{T.selectionMark}`,
		props = { TextColor3 = "$OnSelection" },
	})
	emitHover({
		name = "Selection mark — chosen hover",
		selector = `TextButton.{T.selected}.{T.selectionMark}.{pointerLive}:Hover`,
		props = { BackgroundColor3 = "$Selection", TextColor3 = "$OnSelection" },
	})
end

--[[ THE WHOLE-CONTROL DISABLED DIM — emitted only when a theme sets
	`extra.dimDisabledPlates = true`. The plate then fades with its label: each fill
	blends toward the page by `disabledContentOpacity`, keyed on the same engine
	state the label dim rides. A quiet word keeps its own plate under a role, as at
	rest. Last in the cascade, so no interaction state repaints a disabled plate. ]]
local function emitDisabledPlates(emit: (Rule) -> (), selectionMarks: boolean)
	local T = sheet_model.TAGS
	local A = T.appearancePrefix
	local D = chrome_slots.TAGS.stateDisabled
	local function plate(name: string, selector: string, token: string)
		emit({ name = `Disabled plate — {name}`, selector = selector, props = { BackgroundColor3 = token } })
	end
	plate("control", "TextButton:NonInteractable", "$ControlDisabled")
	plate("selected", `TextButton.{T.selected}:NonInteractable`, "$ControlSelectedDisabled")
	plate("accent", `TextButton.{T.surfacePrefix}accent:NonInteractable`, "$AccentDisabled")
	plate("emphasis", `TextButton.{A}emphasis:NonInteractable`, "$AccentDisabled")
	plate("soft", `TextButton.{A}soft:NonInteractable`, "$ControlSelectedDisabled")
	plate("utility", `TextButton.{A}utility:NonInteractable`, "$Surface")
	plate("destructive", "TextButton.facet-role-destructive:NonInteractable", "$DangerDisabled")
	plate("destructive soft", `TextButton.facet-role-destructive.{A}soft:NonInteractable`, "$ControlSelectedDisabled")
	plate("destructive utility", `TextButton.facet-role-destructive.{A}utility:NonInteractable`, "$Surface")
	plate("chip box", `Frame.{T.surfacePrefix}chip.{D}`, "$ControlDisabled")
	if selectionMarks then
		plate("chosen", `TextButton.{T.selected}.{T.selectionMark}:NonInteractable`, "$SelectionDisabled")
		plate("mark fill", `Frame.{T.selectionMark}.{D}`, "$SelectionDisabled")
	end
end

export type BuildOpts = {
	-- ordered; the FIRST theme is the base/default unless defaultTheme names another
	themes: { { name: string, style: any } },
	defaultTheme: string?,
	-- the display class this sheet is painted for; see BuildPackageOpts.displaySize
	displaySize: string?,
}

-- Generated primary content is logically owned by a Button even when native
-- instances are flat siblings. Only classification/state travels; paint stays in
-- the sheet. This is semantic control paint, not arbitrary StyleRule inheritance.
sheet_model.CONTENT_OWNER_PREFIX = "facet-content-owner-"
sheet_model.CONTENT_TEXT_TAG = "facet-control-content-text"
sheet_model.CONTENT_ICON_TAG = "facet-control-content-icon"
sheet_model.CONTENT_ART_TAG = "facet-control-content-art"
function sheet_model.contentTags(tags: { string }, state: string): { [string]: boolean }
	local out = { [sheet_model.CONTENT_OWNER_PREFIX .. "button"] = true }
	for _, tag in tags do
		if string.sub(tag, 1, 6) == "facet-" then
			out[sheet_model.CONTENT_OWNER_PREFIX .. tag] = true
		end
	end
	if state == "Hover" or state == "Press" or state == "NonInteractable" then
		out[sheet_model.CONTENT_OWNER_PREFIX .. "state-" .. state] = true
	end
	return out
end

-- ...and every other lifted label takes its role's colour as picked against the art
local LIFT_TOKEN: { [string]: string } = {
	["$OnAccent"] = "$OnAccentChrome",
	["$Content"] = "$OnControlChrome",
	["$ContentStrong"] = "$OnControlChromeStrong",
	["$ContentSecondary"] = "$OnControlChromeSecondary",
	["$OnDanger"] = "$OnDangerChrome",
}

-- A LIFTED label sits on the control's art, never on the accent fill $OnAccent is
-- gated against (see `onChromeColor`); a destructive button's art is
-- danger-tinted whatever its appearance, and a soft one's wears the selection wash
local function liftValue(value: string, owner: string): string
	if value == "$ContentSecondary" and string.find(owner, "role-cancel", 1, true) then
		return "$OnCancelChrome"
	elseif string.sub(value, 1, 7) == "$Danger" and string.find(owner, "role-destructive", 1, true) then
		return "$OnDangerChrome"
	elseif value == "$OnSelected" and string.find(owner, "appearance-soft", 1, true) then
		return "$OnSoftChrome"
	end
	return LIFT_TOKEN[value] or value
end
-- ...and a skinned Button's GENERATED label and icon sit on that same art
local SKINNED_OWNER = "." .. sheet_model.CONTENT_OWNER_PREFIX .. chrome_slots.skinnedTagFor("control")

local function projectContentRules(rules: { Rule })
	local hasLift = false
	for _, rule in rules do
		hasLift = hasLift or string.find(rule.selector, "." .. chrome_slots.TAGS.text, 1, true) ~= nil
	end
	local count = #rules
	for i = 1, count do
		local source = rules[i]
		if source.props.TextColor3 == nil and source.props.TextTransparency == nil then
			continue
		end
		local selector = source.selector
		local rest = string.gsub(selector, "^TextButton", "")
		rest = string.gsub(rest, "%.facet[%w%-]+", "")
		rest = string.gsub(rest, ":Hover", "")
		rest = string.gsub(rest, ":Press", "")
		rest = string.gsub(rest, ":NonInteractable", "")
		-- Only simple owner selectors: no TextLabel/TextBox defaults, descendants,
		-- phantom modifiers, or author combinators silently reinterpreted as ownership.
		if rest ~= "" then
			continue
		end
		selector = string.gsub(selector, "%.(facet[%w%-]+)", function(tag)
			return "." .. sheet_model.CONTENT_OWNER_PREFIX .. tag
		end)
		selector = string.gsub(selector, "^TextButton", "." .. sheet_model.CONTENT_OWNER_PREFIX .. "button")
		selector = string.gsub(selector, ":(%a+)", "." .. sheet_model.CONTENT_OWNER_PREFIX .. "state-%1")
		for _, channel in
			{
				{ "text", sheet_model.CONTENT_TEXT_TAG, "TextColor3", "TextColor3", "rule" },
				{ "icon", sheet_model.CONTENT_ICON_TAG, "ImageColor3", "TextColor3", "chrome" },
				{ "icon opacity", sheet_model.CONTENT_ART_TAG, "ImageTransparency", "TextTransparency", "chrome" },
				{ "lift", "", "TextColor3", "TextColor3", "rule" },
				{ "lift opacity", "", "TextTransparency", "TextTransparency", "rule" },
			}
		do
			local value = source.props[channel[4]]
			if channel[1] == "lift" and value ~= nil then
				value = liftValue(value, source.selector)
			end
			local buttonSelector = string.sub(source.selector, 1, 10) == "TextButton"
			-- Only the control's own opacity decision reaches art. Glyph-suppression
			-- and ordinary subtree text rules must never make its image transparent.
			if
				value == nil
				or (channel[2] == "" and not hasLift)
				or (channel[4] == "TextTransparency" and not buttonSelector)
			then
				continue
			end
			local transition = source.transitions and source.transitions[channel[4]]
			local contentSelector = if channel[2] == ""
				then (if buttonSelector then source.selector else "TextButton" .. source.selector)
					.. " > ."
					.. chrome_slots.TAGS.text
				else "." .. channel[2] .. selector
			sheet_model.checkSelector(contentSelector, source.name)
			local allowed, reason = themePackage.lintProperty(channel[3], channel[5])
			assert(allowed, reason)
			sheet_model.checkContentValue(source.name, channel[3], value)
			table.insert(rules, {
				name = "Control content " .. channel[1] .. " — " .. source.name,
				selector = contentSelector,
				props = { [channel[3]] = value },
				transitions = if transition then { [channel[3]] = transition } else nil,
				priority = (#rules + 1) * 10,
			})
			local onArt = if hasLift and (channel[1] == "text" or channel[1] == "icon")
				then liftValue(value, source.selector)
				else value
			if onArt ~= value then
				table.insert(rules, {
					name = "Control content " .. channel[1] .. " skinned — " .. source.name,
					selector = contentSelector .. SKINNED_OWNER,
					props = { [channel[3]] = onArt },
					transitions = if transition then { [channel[3]] = transition } else nil,
					priority = (#rules + 1) * 10,
				})
			end
		end
	end
end

local TINT_ROLE_TOKEN: { [string]: string } = {
	surface = "$Surface",
	surfaceStrong = "$SurfaceStrong",
	content = "$Content",
	contentStrong = "$ContentStrong",
	contentSecondary = "$ContentSecondary",
	accent = "$Accent",
	onAccent = "$OnAccent",
	onDanger = "$OnDanger",
	success = "$Success",
	onSuccess = "$OnSuccess",
	warning = "$Warning",
	onWarning = "$OnWarning",
	control = "$Control",
	controlSelected = "$ControlSelected",
	onSelected = "$OnSelected",
	danger = "$Danger",
	hairline = "$Hairline",
	selection = "$Selection",
	onSelection = "$OnSelection",
}

function sheet_model.build(opts: BuildOpts): Model
	assert(
		type(opts) == "table" and type(opts.themes) == "table" and #opts.themes >= 1,
		"sheet_model.build: themes required"
	)
	local themes: { Theme } = {}
	for _, entry in opts.themes do
		table.insert(themes, {
			name = entry.name,
			tokens = themeTokens(entry.style),
			contrast = gateTheme(entry.name, entry.style),
		})
	end
	-- the first theme's style is where every metric literal in this sheet comes
	-- from, so the paint family is derived for the display class HERE, once, from
	-- the same `metricScale` the measured snapshot uses
	local base = themeSnapshot.paintForDisplay(opts.themes[1].style, opts.displaySize)
	local x = base.extra
	local T = sheet_model.TAGS
	local S = T.surfacePrefix

	-- Numeric config shared by rules (literals in rules, editable per-rule in
	-- the editor; colors ride $tokens — the designer-editable palette)
	local numbers = {
		HairlineTransparency = x.hairlineOpacity,
		ScrimTransparency = x.scrimOpacity,
		DisabledContentTransparency = x.disabledContentOpacity,
	}

	-- ORDERED rules. Insertion order IS the cascade (later wins on overlap):
	-- class defaults -> surfaces (+phantom chrome) -> selected -> hover ->
	-- pressed -> disabled. Names are what the Style Editor shows (§6.1).
	--
	-- The class-default transparency rules exist because the adapter must NOT
	-- write BackgroundTransparency at create in native mode (an explicit write
	-- would permanently defeat every surface rule's transparency, spike m10) —
	-- so "invisible until a surface says otherwise" is itself sheet-owned.
	local rules: { Rule } = {
		{ name = "Frame default", selector = "Frame", props = { BackgroundTransparency = num(1) } },
		{ name = "Canvas default", selector = "CanvasGroup", props = { BackgroundTransparency = num(1) } },
		{ name = "Label default", selector = "TextLabel", props = { BackgroundTransparency = num(1) } },
		{ name = "Button default", selector = "TextButton", props = { BackgroundTransparency = num(1) } },
		{ name = "Image default", selector = "ImageLabel", props = { BackgroundTransparency = num(1) } },
		{ name = "Field default", selector = "TextBox", props = { BackgroundTransparency = num(1) } },
		{ name = "Scroll default", selector = "ScrollingFrame", props = { BackgroundTransparency = num(1) } },
		-- ...and the ONE exception to "invisible until a surface says otherwise":
		-- a node the author tinted. Directly under the class defaults it beats and
		-- above every surface, slot and scrim, whose own alphas still win. See
		-- TAGS.tintFill for why this is a rule and not the explicit write it looks
		-- like it should be.
		{ name = "Tint fill", selector = "." .. T.tintFill, props = { BackgroundTransparency = num(0) } },
		{ name = "Text default", selector = "TextLabel", props = { TextColor3 = "$Content", FontFace = BUILDER_SANS } },
		{
			name = "Button text default",
			selector = "TextButton",
			props = { TextColor3 = "$Content", FontFace = BUILDER_SANS },
		},
		{
			name = "Field text default",
			selector = "TextBox",
			props = { TextColor3 = "$Content", PlaceholderColor3 = "$ContentSecondary", FontFace = BUILDER_SANS },
		},
		--[[ A HAIRLINE IS A HAIRLINE WHEREVER IT IS DRAWN (owner report 2026-09-12).
			This rule spent `$Hairline` at FULL opacity while every stroke in the
			sheet spends the same token at `hairlineOpacity` — and Facet Neutral's
			hairline is `rgb(255, 255, 255)`, whose own comment in `default_style`
			says "used at 8% opacity". So a segmented picker's seam painted a pure
			white bar louder than the labels beside it. One number, authored by the
			theme, decides both. ]]
		{
			name = "Divider",
			selector = ".facet-divider",
			props = { BackgroundColor3 = "$Hairline", BackgroundTransparency = num(numbers.HairlineTransparency) },
		},
		{
			name = "Strong divider",
			selector = `.facet-divider.{T.appearancePrefix}strong`,
			props = { BackgroundTransparency = num(strongHairlineOpacity(x)) },
		},
		{ name = "Secondary text", selector = ".facet-role-secondary", props = { TextColor3 = "$ContentSecondary" } },
		{ name = "Strong text", selector = ".facet-role-strong", props = { TextColor3 = "$ContentStrong" } },
		-- THE TYPOGRAPHY-ROLE FACES (F2, 2026-08-02). One rule per role that wears
		-- a face this builder can name. A compiled TOKEN style carries sizes only —
		-- font descriptors live in a theme PACKAGE (`buildPackage` below emits all
		-- eight from `type.<role>.font`) — so the built-in model states exactly what
		-- the neutral snapshot derives: the six ladder roles keep the family's
		-- Regular face (already the class default, so these rules are inert and no
		-- existing screen moves) and the two weight roles take the derived faces.
		{ name = "Type — strong", selector = ".facet-type-strong", props = { FontFace = BUILDER_SANS_SEMIBOLD } },
		{ name = "Type — numeral", selector = ".facet-type-numeral", props = { FontFace = BUILDER_SANS_BOLD } },
		{ name = "Scroll bar", selector = "ScrollingFrame", props = { ScrollBarImageColor3 = "$ContentSecondary" } },
		{
			name = "Base surface",
			selector = "." .. S .. "base",
			props = { BackgroundColor3 = "$Surface", BackgroundTransparency = num(0) },
		},
		-- a flush pane: the raised fill with no corner and no edge (a sidebar)
		{
			name = "Pane surface",
			selector = "." .. S .. "pane",
			props = { BackgroundColor3 = "$SurfaceStrong", BackgroundTransparency = num(0) },
		},
		{
			name = "Raised panel",
			selector = "." .. S .. "raised",
			props = { BackgroundColor3 = "$SurfaceStrong", BackgroundTransparency = num(0) },
		},
		{
			name = "Raised panel — corner",
			selector = "." .. S .. "raised::UICorner",
			props = { CornerRadius = udim(0, base.radii.panel) },
		},
		{
			name = "Raised panel — hairline",
			selector = "." .. S .. "raised::UIStroke",
			props = {
				Color = "$Hairline",
				Transparency = num(numbers.HairlineTransparency),
				Thickness = num(base.strokes.hairline),
				ApplyStrokeMode = STROKE_BORDER,
				BorderStrokePosition = STROKE_INNER,
			},
		},
		{
			name = "Control fill",
			selector = "." .. S .. "control",
			props = { BackgroundColor3 = "$Control", BackgroundTransparency = num(0) },
		},
		{
			name = "Control — corner",
			selector = "." .. S .. "control::UICorner",
			props = { CornerRadius = udim(0, base.radii.control) },
		},
		{
			name = "Field — outline",
			selector = "TextBox." .. S .. "control::UIStroke",
			props = {
				Color = "$Hairline",
				Transparency = num(numbers.HairlineTransparency),
				Thickness = num(base.strokes.hairline),
				ApplyStrokeMode = STROKE_BORDER,
				BorderStrokePosition = STROKE_INNER,
			},
		},
		{
			name = "Chip",
			selector = "." .. S .. "chip",
			props = { BackgroundColor3 = "$Control", BackgroundTransparency = num(0) },
		},
		{
			name = "Chip — corner",
			selector = "." .. S .. "chip::UICorner",
			props = { CornerRadius = udim(0, base.radii.control) },
		},
		{
			name = "Chip — outline",
			selector = "." .. S .. "chip::UIStroke",
			props = {
				Color = "$Hairline",
				Transparency = num(numbers.HairlineTransparency),
				Thickness = num(base.strokes.hairline),
				ApplyStrokeMode = STROKE_BORDER,
				BorderStrokePosition = STROKE_INNER,
			},
		},
		{
			name = "Badge",
			selector = "." .. S .. "badge",
			props = { BackgroundColor3 = "$SurfaceStrong", BackgroundTransparency = num(0) },
		},
		{
			name = "Badge — circle",
			selector = "." .. S .. "badge::UICorner",
			props = { CornerRadius = udim(0.5, 0) },
		},
		{
			name = "Primary button",
			selector = "." .. S .. "accent",
			props = { BackgroundColor3 = "$Accent", BackgroundTransparency = num(0) },
		},
		-- THE ACCENT SURFACE'S CORNER (director round 11, found live under
		-- glossy-mobile). Per-surface rules REPLACE, they do not compose: a chip
		-- that becomes the primary action drops `.facet-surface-chip` for
		-- `.facet-surface-accent`, and this rule set carried a fill and a label
		-- colour and no corner — so the selected button went hard square while
		-- every sibling stayed a pill at `radii.control = 16`. The bespoke path
		-- never showed it because `wireInteractiveStates` gives every Button a
		-- REAL UICorner before `applySurface` runs.
		{
			name = "Primary button — corner",
			selector = "." .. S .. "accent::UICorner",
			props = { CornerRadius = udim(0, base.radii.control) },
		},
		{
			name = "Primary button label",
			selector = "TextButton." .. S .. "accent",
			props = { TextColor3 = "$OnAccent" },
		},
	}
	local function push(rule: Rule)
		table.insert(rules, rule)
	end
	local function pushAll(more: { Rule })
		for _, rule in more do
			push(rule)
		end
	end

	-- VALUE-CONTROL CHROME: ITS OWN PAINT (rich-skinning v2). The same three rules per
	-- slot the package builder emits, from the same shared emitter, at the same
	-- cascade position: after every surface fill it must beat, and before the
	-- scrim and the `Grip focus` accent that must still beat IT.
	local hairlineT, hairlineW = num(numbers.HairlineTransparency), num(base.strokes.hairline)
	--[[ THE LOCAL SIZE / EMPHASIS CHROME (see emitVocabularyChrome). The base seed
		pushes into ONE flat ordered list, so the emitter's groups are collected first
		and spliced at the points the cascade needs them: the corners before the
		disc's, the fills after every surface fill, and the compound role rules and
		the interaction states each after the rules they must beat. ]]
	local vocabSurfaces: { Rule }, vocabRoles: { Rule } = {}, {}
	local function into(list: { Rule }): (Rule) -> ()
		return function(rule: Rule)
			table.insert(list, rule)
		end
	end
	emitVocabularyChrome(base, hairlineT, hairlineW, into(vocabSurfaces), into(vocabRoles))
	pushAll(vocabSurfaces)
	-- THE DISC'S CHROME, immediately after every surface corner it has to beat
	-- and before anything that changes only colour (see emitShapeChrome)
	emitShapeChrome(base, hairlineT, hairlineW, push)
	pushAll(vocabRoles)
	for _, slot in chrome_slots.OWN_PAINT_SLOTS do
		emitOwnSlotPaint(slot, base, hairlineT, hairlineW, push)
	end

	pushAll({
		{
			name = sheet_model.SCRIM_RULE,
			selector = "." .. S .. "scrim",
			props = { BackgroundColor3 = "$Scrim", BackgroundTransparency = num(numbers.ScrimTransparency) },
		},
		{
			name = "Grip focus",
			selector = ".facet-grip-focus",
			props = { BackgroundColor3 = "$Accent", BackgroundTransparency = num(0) },
		},
		-- toggle knob-track chrome (director live find 2026-07-24): the
		-- assembly's PRE-PARENT transparency writes are STOMPED when styling
		-- first applies (defeat is order-sensitive — see the spike addendum),
		-- so opacity is sheet-owned via this tag; the value-driven COLOR writes
		-- happen after styling and have no competing rule, so they stay bespoke
		{
			name = "Toggle chrome",
			selector = ".facet-toggle-chrome",
			props = { BackgroundTransparency = num(0) },
		},
		{
			name = "Selected row",
			selector = "TextButton." .. T.selected,
			-- the label pairs with the plate it now sits on (director round 8).
			-- `$OnSelected` resolves to $Content wherever content still clears the
			-- 4.5 floor against this theme's selected surface — which is every
			-- flat reference theme, so this is a no-op there — and to $OnAccent,
			-- the contract's one guaranteed partner, where it does not.
			props = { BackgroundColor3 = "$ControlSelected", TextColor3 = "$OnSelected" },
			transitions = { BackgroundColor3 = "fast" },
		},
		-- semantic button roles (B-BTN2): tag-driven, sheet-painted. No parallel
		-- paint-state system — these are ordinary rules a designer can retheme.
		--
		-- ORDER MATTERS and was found live: the measured cascade is Priority first,
		-- then INSERTION ORDER (later wins), with no selector specificity. Placed
		-- before "Control fill" these rules lost their BackgroundColor3 to it while
		-- TextColor3 survived — a destructive button with white text on a neutral
		-- fill. They therefore sit after the base/surface/selected fills and before
		-- the hover/press rules, so a role owns the resting fill while the engine
		-- states still layer on top.
		{
			name = "Destructive button",
			selector = ".facet-role-destructive",
			props = { BackgroundColor3 = "$Danger", TextColor3 = "$OnDanger" },
		},
		{
			name = "Destructive label",
			selector = "TextButton.facet-role-destructive-label",
			props = { TextColor3 = "$Danger" },
		},
		{
			name = "Cancel button",
			selector = ".facet-role-cancel",
			props = { BackgroundColor3 = "$Surface", TextColor3 = "$ContentSecondary" },
		},
		--[[ THE ROLE WITH NO FILL (stabilization B'1). Its plate is Facet's own
			sliding selection indicator — a `surface = "accent"` chip painted BEHIND
			the option — so the only thing this rule may write is the colour that
			reads on it. A `BackgroundColor3` here would hide the very chip the role
			exists to sit on.

			`TextButton`-scoped, like `Primary button label` one block up and for the
			same reason: the pair it restores is ($Accent, $OnAccent), which is the
			theme contract's ONE gated pair, and the node that has text to paint is
			the Button. Placed with the other roles — after every surface fill it
			must beat, before the hover/press rules that still layer on top. ]]
		{
			name = "Indicator label",
			selector = "TextButton." .. ON_INDICATOR_TAG,
			props = { TextColor3 = "$OnAccent" },
		},
	})
	-- the compound role x appearance rules, immediately after the roles they must
	-- beat (see emitVocabularyRoles)
	emitVocabularyRoles(push)
	local styles: { any } = {}
	for _, entry in opts.themes do
		table.insert(styles, entry.style)
	end
	local selectionMarks = authoredSelection(styles)
	local markHover: { Rule } = {}
	if selectionMarks then
		emitSelectionMark(push, into(markHover), T.pointerLive)
	end

	-- A SKINNED VALUE SLOT SUPPRESSES ITS OWN PAINT TOO — PRE-ARMED, exactly as
	-- in `buildPackage` (director round 5). The base seed needs it for the same
	-- reason a flat package does: the rung-2 per-view override (a Slider's
	-- `thumbImage`) skins a node with NO package installed at all, and a node that
	-- earns `facet-skinned-<slot>` with no rule to match it keeps a solid plate
	-- showing through every transparent pixel of the author's own art.
	--
	-- After the paint above (a floor is only lifted by art) and before the
	-- interaction states, which only change colour — so an invisible plate stays
	-- invisible through hover and press.
	for _, slot in chrome_slots.OWN_PAINT_SLOTS do
		emitSlotSuppression(slot, push)
	end

	pushAll({
		{
			name = "Control — hover",
			selector = "TextButton." .. T.interactive .. "." .. T.pointerLive .. ":Hover",
			props = { BackgroundColor3 = "$ControlHover" },
			transitions = { BackgroundColor3 = "fast" },
		},
		-- after the plain hover it must beat, before every role/accent hover
		{
			name = "Selected — hover",
			selector = "TextButton." .. T.selected .. "." .. T.interactive .. "." .. T.pointerLive .. ":Hover",
			props = { BackgroundColor3 = "$ControlSelectedHover" },
			transitions = { BackgroundColor3 = "fast" },
		},
		{
			name = "Primary — hover",
			selector = "TextButton." .. S .. "accent." .. T.pointerLive .. ":Hover",
			props = { BackgroundColor3 = "$AccentHover" },
			transitions = { BackgroundColor3 = "fast" },
		},
		{
			name = "Control — pressed",
			selector = "TextButton." .. T.interactive .. ":Press",
			props = { BackgroundColor3 = "$ControlPressed" },
		},
		{
			name = "Primary — pressed",
			selector = "TextButton." .. S .. "accent:Press",
			props = { BackgroundColor3 = "$AccentPressed" },
		},
		-- role-aware interaction states (verifier finding V14): the generic
		-- "Control — hover/pressed" rules are keyed on the interactive tag, NOT on
		-- the role, so without these a hovered destructive button repainted itself
		-- neutral and the role visually vanished at the moment of the click.
		{
			name = "Destructive — hover",
			selector = "TextButton.facet-role-destructive." .. T.pointerLive .. ":Hover",
			props = { BackgroundColor3 = "$DangerHover" },
			transitions = { BackgroundColor3 = "fast" },
		},
		{
			name = "Destructive — pressed",
			selector = "TextButton.facet-role-destructive:Press",
			props = { BackgroundColor3 = "$DangerPressed" },
		},
	})
	-- ...and the emphasis words' own interaction states, beside the role's and for
	-- the same reason (see emitVocabularyStates). After the generic control ramp,
	-- before the disabled group which must still beat every interaction state.
	emitVocabularyStates(push, push, T.pointerLive)
	pushAll(markHover)
	pushAll({
		{
			name = "Disabled button",
			selector = "TextButton:NonInteractable",
			props = { TextTransparency = num(numbers.DisabledContentTransparency) },
		},
		{
			name = "Disabled field",
			selector = "TextBox:NonInteractable",
			props = { TextTransparency = num(numbers.DisabledContentTransparency) },
		},
		--[[ ...AND THE SUBTREE A DISABLED CONTAINER TURNED OFF (2026-09-07).
			The two rules above ride an engine GuiState, which only exists on the classes
			the engine considers interactable; `enabled = false` on a container disables
			plain labels too, and those say so with a tag instead. The same number, so a
			control that wears both is dimmed once.

			TEXT ONLY, AND THE LIMIT IS THE FRAMEWORK'S OWN RULE, not an oversight: image
			paint is legal in a theme rule only inside a nineSlice chrome recipe, where
			the slot is what makes the picture meaningful (`themes/package.lintProperty`),
			and the package builder lints the rules it generates by that same test. A
			picture inside a disabled subtree therefore keeps its own paint; api.md says
			so. ]]
		{
			name = "Disabled subtree text",
			selector = `TextLabel.{chrome_slots.TAGS.stateDisabled}`,
			props = { TextTransparency = num(numbers.DisabledContentTransparency) },
		},
		-- SEMANTIC ICON ART. Last in the `disabled` group and so
		-- last in the whole cascade: the node's glyph is a fallback the control
		-- always draws, and when real art covers it the glyph must go — including
		-- over the 0.45 disabled value, which would otherwise leave a ghost "+"
		-- showing through a disabled stepper's plate art.
		{
			name = "Semantic icon replaces the glyph",
			selector = `.{chrome_slots.TAGS.iconArt}`,
			props = { TextTransparency = num(1) },
		},
		-- THE HELD SOURCE EMPTIES (director round five): while a drag session
		-- carries this node's payload, its label is blank — the ghost is the
		-- card's face now, and two faces read as "still here"
		{
			name = "Held drag source empties its label",
			selector = `.{chrome_slots.TAGS.dragHeld}`,
			props = { TextTransparency = num(1) },
		},
	})

	if x.dimDisabledPlates == true then
		emitDisabledPlates(push, selectionMarks)
	end

	-- Layout-reference MIRRORS (§6.9 Fallback B): editor-VISIBLE, generator-
	-- owned attributes regenerated on every apply. Editing them in the editor
	-- does nothing to layout (the solver reads the Luau tokens) — the styling
	-- guide labels them read-only-reference; the freshness check re-stamps them.
	local mirrors: { { name: string, value: number } } = {}
	for _, m in
		{
			{ "Space", base.space, { "xs", "s", "m", "l", "xl" } },
			{ "Type", base.type, { "caption", "label", "body", "heading", "title" } },
			{ "Radius", base.radii, { "control", "panel", "pill" } },
		}
	do
		local prefix, tbl, keys = m[1] :: string, m[2] :: any, m[3] :: { string }
		for _, key in keys do
			if tbl[key] ~= nil then
				table.insert(mirrors, { name = prefix .. key:sub(1, 1):upper() .. key:sub(2), value = tbl[key] })
			end
		end
	end
	table.insert(mirrors, { name = "TargetMinimum", value = base.targetSizes.minimum })
	table.insert(mirrors, { name = "MotionFast", value = base.motion.fast })
	table.insert(mirrors, { name = "MotionNormal", value = base.motion.normal })

	-- No-package art uses the same resolver and checked token vocabulary.
	local iconNames: { string } = {}
	for name in themePackage.ICON_FALLBACK_GLYPHS do
		table.insert(iconNames, tostring(name))
	end
	table.sort(iconNames)
	for _, name in iconNames do
		local resolved = themePackage.resolveIcon(nil, name)
		if resolved and resolved.source == "asset" and resolved.tintRole ~= nil then
			local token = TINT_ROLE_TOKEN[resolved.tintRole]
			assert(token, `sheet_model.build: icon '{name}' names unknown tintRole '{resolved.tintRole}'`)
			push({
				name = `Icon — {name}`,
				selector = "." .. chrome_slots.iconTagFor(name),
				props = {
					ImageColor3 = token,
				},
			})
		end
	end

	projectContentRules(rules)
	-- Explicit partner lettering wins over both name tint and generated-owner color.
	emitStatusIconTint(function(rule: Rule)
		rule.priority = (#rules + 1) * 10
		table.insert(rules, rule)
	end)

	-- deterministic stamp over everything the generator writes
	local parts: { string } = {}
	-- …including the distance its corners were cut for (see buildPackage's stamp)
	if themeSnapshot.metricScale(opts.displaySize) ~= 1 then
		table.insert(parts, `paintScale={themeSnapshot.metricScale(opts.displaySize)}`)
	end
	for _, th in themes do
		local names = {}
		for k in th.tokens do
			table.insert(names, k)
		end
		table.sort(names)
		for _, k in names do
			local v = th.tokens[k]
			table.insert(parts, string.format("%s.%s=%.4f,%.4f,%.4f", th.name, k, v.r, v.g, v.b))
		end
	end
	for _, r in rules do
		table.insert(parts, r.selector)
		local pnames = {}
		for k in r.props do
			table.insert(pnames, k)
		end
		table.sort(pnames)
		for _, k in pnames do
			local v = r.props[k]
			table.insert(
				parts,
				k
					.. "="
					.. (
						if type(v) == "string"
							then v
							else tostring(v.kind) .. tostring(v.value or v.offset or v.family or "")
					)
			)
		end
	end
	for _, m in mirrors do
		table.insert(parts, m.name .. "=" .. tostring(m.value))
	end

	return {
		schema = "facet-native-sheet/1",
		stamp = stampOf(parts),
		defaultTheme = opts.defaultTheme or opts.themes[1].name,
		themes = themes,
		rules = rules,
		mirrors = mirrors,
		motion = { fast = base.motion.fast, normal = base.motion.normal },
	}
end

-- ===========================================================================
-- buildPackage: a compiled ThemePackage -> the ordered sheet model
--
-- ===========================================================================
--
-- `build` above compiles ONE Facet token style and is the legacy path; it is
-- unchanged and byte-stable. `buildPackage` compiles a package's `style` and
-- `chrome` sections, which adds three things `build` cannot express:
--
--   * per-theme TYPOGRAPHY — the package's typography roles carry the font
--     descriptor, so a theme can change the family (build pinned Builder Sans);
--   * NINE-SLICE CHROME — the six image properties on the decoration child's
--     slot tag, plus per-state tint rules that modulate ONE base image rather
--     than swapping to a second asset (feasibility m2);
--   * GRADIENTS — `::UIGradient` phantom rules, confirmed to render with zero
--     child instances (feasibility m7).
--
-- PSEUDO-SELECTOR ALLOWLIST. Only `::UICorner`, `::UIStroke` and `::UIGradient`
-- are proven. `::UIShadow` is accepted by `SetProperties`, reports no
-- `SelectorError`, and paints NOTHING on 0.731 (m7) — a rule that looks correct
-- everywhere except on screen. Every selector this compiler emits or accepts is
-- checked, and an inert pseudo selector is a compile error naming itself.
--
-- CASCADE. Priority is explicit and equals index * 10 (the same number
-- `native_style.priorityFor` computes, so the two can never disagree), and the
-- group order IS the design: base -> surfaces -> roles -> chrome -> hover ->
-- press -> disabled. Chrome sits after roles because the decoration image is
-- the resting appearance a role may not repaint, and before hover/press
-- because interaction state must always win over rest.

sheet_model.ALLOWED_PSEUDO = table.freeze({ UICorner = true, UIStroke = true, UIGradient = true })

-- A phantom-modifier selector addresses a DIFFERENT class's property namespace:
-- `Color` on a `::UIStroke` rule is UIStroke.Color, which is not any GuiObject
-- property and therefore is not in `render/authority`'s manifest (that manifest
-- names them StrokeColor/StrokeTransparency/StrokeThickness, the Facet-side
-- prop names, which is the right vocabulary for the adapter and the wrong one
-- for a rule). So the property gate for a pseudo selector is this closed set,
-- and `package.lintProperty` governs everything else.
sheet_model.PHANTOM_PROPS = table.freeze({
	UICorner = table.freeze({ CornerRadius = true }),
	UIStroke = table.freeze({
		Color = true,
		Transparency = true,
		Thickness = true,
		ApplyStrokeMode = true,
		BorderStrokePosition = true,
		LineJoinMode = true,
		Enabled = true,
	}),
	UIGradient = table.freeze({
		Color = true,
		Transparency = true,
		Rotation = true,
		Offset = true,
		Enabled = true,
	}),
})

-- the ordered rule groups; the array position is the cascade position
sheet_model.RULE_GROUPS = table.freeze({ "base", "surfaces", "roles", "chrome", "hover", "press", "disabled" })

-- checkSelector(selector, ruleName): every `::Pseudo` in a selector must be on
-- the proven list. Returns the selector so call sites read as assertions.
function sheet_model.checkSelector(selector: string, ruleName: string): string
	for pseudo in string.gmatch(selector, "::([%w_]+)") do
		if not (sheet_model.ALLOWED_PSEUDO :: any)[pseudo] then
			local why = if pseudo == "UIShadow"
				then "it is SILENTLY ACCEPTED and paints nothing on 0.731 "
					.. "(artifacts/theme-packages-and-skinning/feasibility/m7-gradient-shadow-phantoms.json) — "
					.. "theme shadows stay on the bespoke UIShadow path behind its capability probe"
				else "only the phantom modifiers proven to render may be styled"
			error(
				`sheet_model.buildPackage: rule '{ruleName}' names the inert pseudo selector '::{pseudo}' — {why}. `
					.. `Allowed pseudo selectors: ::UICorner, ::UIStroke, ::UIGradient.`,
				0
			)
		end
	end
	return selector
end

-- checkContentValue(ruleName, prop, value): a rule that paints art carries a
-- plain STRING and nothing else (probe rs-m7).
--
-- Strings coerce on `Image` and on `ImageContent` alike — even a rule authored
-- with `Content.fromUri` round-trips as a string through `GetProperties`, which
-- is why this stage ships zero Content materialization machinery. An
-- OBJECT-sourced Content is the trap: `SetProperties` ACCEPTS it, reports no
-- selector error, resolves to `Content{SourceType=None}` and paints nothing —
-- the fourth accepted-but-silently-inert engine behaviour this project has
-- catalogued (after ::UIShadow, the Global ZIndex default and the pre-join
-- write defeat). EditableImage skins therefore stay an ADAPTER INSTANCE write,
-- declared as such, and never a rule value.
local CONTENT_PROPS: { [string]: boolean } = { Image = true, ImageContent = true }

function sheet_model.checkContentValue(ruleName: string, prop: string, value: any)
	if not CONTENT_PROPS[prop] then
		return
	end
	if type(value) == "string" then
		return
	end
	local what = if type(value) == "table" and type((value :: any).kind) == "string"
		then `a '{(value :: any).kind}' value`
		else `a {type(value)}`
	error(
		`sheet_model.buildPackage: rule '{ruleName}' sets {prop} to {what} — a theme rule may carry only a plain `
			.. "string URI there. The engine COERCES a string onto ImageContent (rs-m7), but an object-sourced "
			.. "Content in a rule is accepted, reports no error, and paints NOTHING. An EditableImage skin is an "
			.. "adapter instance write, declared in the authority manifest, never a rule value.",
		0
	)
end

-- The slot -> selector map: which nodes a slot's NATIVE paint and gradient
-- apply to. The decoration child carries `.facet-chrome-<slot>`; the slot's
-- native treatment lands on the node the renderer already classified, which is
-- why these reuse the Step 2 surface tags rather than inventing a parallel set.
local SLOT_SELECTOR: { [string]: string } = {
	panel = ".facet-surface-raised",
	control = ".facet-surface-control",
	field = "TextBox.facet-surface-control",
	selection = "TextButton.facet-selected",
	divider = ".facet-divider",
	scrollbar = "ScrollingFrame",
	badge = ".facet-surface-badge",
	-- sliderTrack / sliderThumb are ABSENT on purpose. SLOT_SELECTOR is the
	-- gradient target map, and a wash may never reach a value control's chrome
	-- (chrome_slots.isGradientable) — its alpha is exactly what made the thumb
	-- see-through. Their node-level paint is the shared `Slot — <slot>` family
	-- (emitOwnSlotPaint, above both builders), keyed on the hint tag.
}
local SLOT_STROKED: { [string]: boolean } = { panel = true, control = true, field = true }

local function pascal(name: string): string
	return name:sub(1, 1):upper() .. name:sub(2)
end

-- A palette role a recipe may name as its resting tint, mapped to the theme
-- token that carries it. Anything else is an authoring error rather than a
-- silent white, because a tint that silently does nothing is invisible in
-- review and obvious only on a device.

-- The chrome tint ladder lives in chrome_slots, because the explicit-write
-- fallback path needs the same resting value these rules paint. Every slot
-- shares it, so a package retunes three numbers rather than three per slot.
local CHROME_TINT_REST = chrome_slots.TINT.rest
local CHROME_TINT_HOVER = chrome_slots.TINT.hover
local CHROME_TINT_PRESSED = chrome_slots.TINT.pressed

local function greyToken(v: number): TokenValue
	return { kind = "color", r = v, g = v, b = v }
end

-- A package theme may omit `extra` (the non-contract paint roles). Rather than
-- fail — a third-party package should not have to restate the interaction ramp
-- to change a palette — derive the missing roles from the contract colours with
-- the same lerps the library's own style uses.
local function effectiveExtra(theme: any): any
	local c = theme.colors
	local x: any = {}
	for k, v in (theme.extra or {}) :: any do
		x[k] = v
	end
	local function fill(key: string, value: any)
		if x[key] == nil then
			x[key] = value
		end
	end
	fill("control", { r = c.surfaceStrong.r, g = c.surfaceStrong.g, b = c.surfaceStrong.b })
	fill("controlHover", lerp(x.control, WHITE, 0.12))
	fill("controlPressed", lerp(x.control, BLACK, 0.12))
	fill("controlSelected", lerp(x.control, c.accent, 0.35))
	fill("contentSecondary", lerp(c.content, c.surface, 0.35))
	fill("hairline", { r = 1, g = 1, b = 1 })
	fill("selection", c.accent)
	fill("onSelection", c.onAccent)
	fill("scrim", c.surface)
	fill("scrimOpacity", 0.45)
	fill("hairlineOpacity", 0.92)
	-- shared with the rung-2 adapter path so the accessibility floor is ONE number
	-- (chrome_slots.DISABLED_CONTENT_OPACITY; arch verifier F3)
	fill("disabledContentOpacity", chrome_slots.DISABLED_CONTENT_OPACITY)
	fill("focusRingThickness", 2)
	fill("pressedScale", 0.985)
	fill("tenFootFocusRingThickness", 4)
	fill("tenFootFocusScale", 1.05)
	-- the lerps above return TokenValue tables ({kind="color", ...}); the paint
	-- consumers want plain rgb, and both shapes carry r/g/b, so nothing to strip
	return x
end

-- ===== THE CONTINUOUS-COLOUR CHANNEL (`tint`) =========
--
-- The tint is the SAME class of thing the toggle palette below is, and for the
-- same stated reason: a rule cannot see a VALUE. A blend driven by an energy
-- signal, or an identity hue that arrives as game data, can never be a selector
-- — so the adapter writes it, and this is the pure resolver both the engine
-- adapter and the headless FakeTarget go through, so "the fake and the live
-- target agree about the colour" is a fact rather than a hope.
--
-- The ROLE VOCABULARY IS THE ONE `TINT_ROLE_TOKEN` ALREADY DECLARES for a chrome
-- recipe's resting tint (a role that resolves against a theme's palette), and
-- `styling.TINT_ROLES` is the copy the public schema validates against — the two
-- are asserted equal at load, because a role the schema accepts and this
-- resolver cannot resolve would be a tint that paints nothing.
do
	local declared: { [string]: boolean } = {}
	for _, role in styling.TINT_ROLES do
		declared[role] = true
		assert(TINT_ROLE_TOKEN[role] ~= nil, `styling.TINT_ROLES names '{role}', which no theme token carries`)
	end
	for role in TINT_ROLE_TOKEN do
		assert(declared[role], `TINT_ROLE_TOKEN carries '{role}', which styling.TINT_ROLES does not offer`)
	end
end
sheet_model.TINT_ROLES = styling.TINT_ROLES

-- The base a role-blend tint blends FROM when the author names no `from`, per
-- blueprint class. It is the class's IDENTITY paint — the value that makes
-- `blend = 0` mean "unchanged" — and never an inferred surface fill (see
-- styling.checkTint for why the surface mapping is deliberately not consulted).
--   Box    the page colour: a Box with no surface paints nothing, so a wash rises
--          out of the background it sits on
--   Text   the primary content role, which is what a label already draws in
--   Path   the same, matching UI.Path's default stroke role
--   Image  WHITE, the identity for ImageColor3 — the engine multiplies the
--          picture by it, so white is "the picture as authored"
sheet_model.TINT_IDENTITY = table.freeze({
	Box = "surface",
	Text = "content",
	Path = "content",
	Image = "white",
	-- a Stage tints its rendered SCENE through the same ImageColor3 multiply an
	-- Image uses, so its identity is white for the same reason: white multiplies
	-- to the picture the engine already drew
	Stage = "white",
})

-- paletteColor(theme, role) -> { r, g, b }: a declared tint role resolved
-- against a theme's contract colours and then its (derived) extra roles — the
-- same two-step order every other paint decision in this module uses.
function sheet_model.paletteColor(theme: any, role: string): any
	if role == "white" then
		return { r = WHITE.r, g = WHITE.g, b = WHITE.b }
	end
	local c = if type(theme) == "table" then theme.colors else nil
	local direct = if type(c) == "table" then c[role] else nil
	if type(direct) == "table" and type(direct.r) == "number" then
		return { r = direct.r, g = direct.g, b = direct.b }
	end
	-- `effectiveExtra` DERIVES the missing interaction roles from the contract
	-- colours, so a package theme that never declared `control` still resolves one
	-- — but it reads those contract colours, so a theme without them falls back to
	-- whatever `extra` it does carry rather than crashing a paint write.
	local x = if type(c) == "table"
			and type(c.surfaceStrong) == "table"
			and type(c.content) == "table"
		then effectiveExtra(theme)
		elseif type(theme) == "table" and type(theme.extra) == "table" then theme.extra
		else {}
	local extra = x[role]
	if type(extra) == "table" and type(extra.r) == "number" then
		return { r = extra.r, g = extra.g, b = extra.b }
	end
	local semantic = SEMANTIC_ROLE[role]
	if semantic then
		local plate, on = semantic.pair(if type(c) == "table" then c else {})
		local answer = if semantic.partner then on else plate
		if type(answer) == "table" and type(answer.r) == "number" then
			return { r = answer.r, g = answer.g, b = answer.b }
		end
	end
	-- `onSelected` is the SAME decision `$OnSelected` carries (the theme's own
	-- readable partner for its selected surface), reached as a tint so a child
	-- Text on a selected plate can spend it
	if role == "onSelected" and type(c) == "table" and type(c.content) == "table" then
		local on = sheet_model.selectedContentColor(theme)
		return { r = on.r, g = on.g, b = on.b }
	end
	error(`Facet tint: theme carries no colour for role '{role}'`, 0)
end

-- tintColor(theme, tint, class) -> { r, g, b }. `theme` is one entry of
-- `package.style.themes` ({ colors, extra }) — or, with no package installed,
-- the style the target was built with, which has the same shape. A malformed
-- value is a LOUD error at the write site and not a silent no-op: a bound tint is
-- read long after construction, so this is the only place a reactive one is ever
-- checked.
function sheet_model.tintColor(theme: any, tint: any, class: string): any
	local ok, detail = styling.checkTint(tint)
	if not ok then
		error(`Facet tint on a {class}: {tostring(detail)}`, 0)
	end
	local direct = tint.direct
	if direct ~= nil then
		local hex = styling.hexRgb(direct)
		if hex ~= nil then
			return hex
		end
		return { r = direct.r, g = direct.g, b = direct.b }
	end
	local identity = (sheet_model.TINT_IDENTITY :: any)[class] or "surface"
	local base = sheet_model.paletteColor(theme, tint.from or identity)
	local target = sheet_model.paletteColor(theme, tint.role)
	local blended = lerp(base, target, tint.blend)
	return { r = blended.r, g = blended.g, b = blended.b }
end

-- tintTransparency(tint, class) -> number. The tint's own alpha, engine-true
-- (0 opaque, 1 invisible), defaulting to opaque so every tint authored before the
-- channel existed writes exactly what it wrote before.
--
-- Path alpha is realized by its adapter-owned UIGradient (Studio proof 2026-09-08).
function sheet_model.tintTransparency(tint: any, class: string): number
	local alpha = if type(tint) == "table" then (tint :: any).transparency else nil
	if alpha == nil then
		return styling.TINT_TRANSPARENCY_DEFAULT
	end

	return alpha :: number
end

-- THE TOGGLE PALETTE (director follow-up 2026-07-25). PURE, and exported so the
-- adapter and the specs resolve one mapping rather than two.
--
-- The toggle's knob-and-track is the last piece of value-driven paint the sheet
-- cannot own: its transparency rides the `Toggle chrome` tag rule, but the
-- COLOURS change with the VALUE, and a rule cannot see a value. They were
-- therefore written from constants captured at adapter construction — so a
-- parchment toggle rendered a Facet-Neutral BLUE pill (director screenshot).
-- This is the resolver those two write sites now go through.
--
-- THE MAPPING, and why each half is what it is:
--
--   trackOn  = colors.accent        the palette's "this is active" colour, and
--                                   the only one every theme guarantees a
--                                   readable partner for
--   knobOn   = colors.onAccent      that guaranteed partner. The contract gates
--                                   the accent/onAccent pair at 4.5:1 in every
--                                   theme, which is exactly the job the knob
--                                   needs done: measured 5.54–11.47:1 across the
--                                   five reference packages.
--   trackOff = extra.controlPressed a control surface, RECESSED — which is what
--                                   an off switch's well is. Deliberately NOT
--                                   `colors.surface`, the value this used to
--                                   paint: `surface` is darker than the row on a
--                                   dark palette and LIGHTER on a light one
--                                   (Parchment Daylight surface 226,210,176 vs
--                                   control 214,194,156), so an off track would
--                                   read as a well in one theme and a raised bump
--                                   in another. `controlPressed` is derived as
--                                   control lerped toward black, so it is darker
--                                   than the row it sits in BY CONSTRUCTION, in
--                                   every theme including ones that never
--                                   declared it.
--   knobOff  = colors.content       the primary content role, which is also what
--                                   the knob already painted — so a target with
--                                   no package installed is byte-identical.
--                                   Measured 6.81–14.34:1 against trackOff across
--                                   the reference corpus, i.e. clears the 3:1
--                                   non-text floor by at least 2.2x everywhere.
--
-- Returns plain rgb tables; the adapter converts. `theme` is one entry of
-- package.style.themes ({ colors, extra }).
function sheet_model.togglePalette(theme: any): any
	local c = theme.colors
	local x = effectiveExtra(theme)
	local function rgb(v: any)
		return { r = v.r, g = v.g, b = v.b }
	end
	return {
		trackOn = rgb(x.selection),
		trackOff = rgb(x.controlPressed),
		knobOn = rgb(x.onSelection),
		knobOff = rgb(c.content),
	}
end

-- gradientOf(theme, slot): the per-theme gradient declaration for a slot.
-- A chrome RECIPE cannot carry it — `package.define` closes recipe fields to
-- { kind, asset, contentInsets, fallback } — and it should not: a gradient is
-- colour, and colour is per theme. It therefore rides the theme's `extra`
-- section, which `define` passes through unvalidated for exactly this class of
-- non-contract paint role.
--
--   style.themes[i].extra.chromeGradient.<slot> = {
--       rotation = <degrees>,
--       stops = { { t = 0, r = .., g = .., b = .. }, ... },   -- >= 2
--       alpha = { { t = 0, v = 0 }, ... },                    -- optional
--   }
local function gradientOf(theme: any, slot: string): any
	local declared = (theme.extra or {}).chromeGradient
	if type(declared) ~= "table" then
		return nil
	end
	local entry = declared[slot]
	return if type(entry) == "table" then entry else nil
end

export type BuildPackageOpts = {
	defaultTheme: string?,
	--[[ THE DISPLAY CLASS THIS SHEET IS PAINTED FOR (director ruling 2026-08-21).
		A sheet is generated per package and worn by every surface on the client,
		and a client is one screen at one distance — so the class belongs to the
		BUILD. Absent (or near) bakes the authored paint family unchanged; "Large"
		bakes the ten-foot one, derived through `snapshot.paintForDisplay` from the
		same `metricScale` the measured snapshot uses. Hand this the package's
		AUTHORED metrics, never an already-adapted set: the derivation happens
		here, once. ]]
	displaySize: string?,
	-- Extra author-supplied rules, appended to the chrome group. This is the
	-- surface a Style-Editor round-trip feeds back, and it is why the pseudo
	-- allowlist and the §4 property linter run on INPUT and not only on what
	-- this compiler happens to emit.
	rules: { Rule }?,
}

function sheet_model.buildPackage(package: any, opts: BuildPackageOpts?): Model
	assert(
		type(package) == "table" and package.schema == themePackage.SCHEMA,
		"sheet_model.buildPackage: expected a package compiled by themes.define"
	)
	local o = opts or {}
	-- the paint family AS PAINTED at this display class; everything else in the
	-- metrics table passes through by reference (see `paintForDisplay`)
	local metrics = themeSnapshot.paintForDisplay(package.metrics, o.displaySize, themePackage.pixelUnitOf(package))

	-- ----- metric-derived rule props (live-edit repaint map) ---------------
	-- Corner radii and stroke thickness are baked into rules as LITERALS (a
	-- number-typed metric attribute cannot be a UDim `$Token`), so a designer's
	-- Radii_*/Strokes_* sheet edit would re-solve layout while the paint kept
	-- the seeded value. This map records every rule prop derived from a metric
	-- so the controller's token watcher can push the fresh value onto the live
	-- rules — the paint follows the SAME edit the snapshot does.
	local metricRuleProps: { { path: string, rule: string, prop: string, form: string } } = {}
	local function fromMetric(path: string, rule: string, prop: string, form: string)
		table.insert(metricRuleProps, { path = path, rule = rule, prop = prop, form = form })
	end

	-- ----- which slots need which chrome ----------------------------------
	local ninePlans: { [string]: any } = {}
	local stacks: { [string]: any } = {}
	local gradientSlots: { [string]: boolean } = {}
	for _, slot in chrome_slots.SLOTS do
		local plan = chrome_slots.planFor(package, slot)
		if plan ~= nil then
			ninePlans[slot] = plan
		end
		-- a LAYERED recipe plans a whole ladder instead of one
		-- decoration; `planFor` returns nil for it, which is what keeps every
		-- existing caller and every flat package byte-identical
		local stack = chrome_slots.layerPlanFor(package, slot)
		if stack ~= nil then
			stacks[slot] = stack
		end
		-- a wash may never reach a value control's chrome (see SLOT_SELECTOR);
		-- `themes.define` rejects the declaration, so this is belt-and-braces
		if chrome_slots.isGradientable(slot) then
			for _, theme in package.style.themes do
				if gradientOf(theme, slot) ~= nil then
					gradientSlots[slot] = true
				end
			end
		end
	end

	-- ----- themes ---------------------------------------------------------
	local themes: { Theme } = {}
	local extraByTheme: { [string]: any } = {}
	for _, entry in package.style.themes do
		local x = effectiveExtra(entry)
		local styleLike = { colors = entry.colors, extra = x }
		extraByTheme[entry.name] = x
		local tokenSet = themeTokens(styleLike)
		-- chrome tint ladder (shared across slots — see CHROME_TINT_* above)
		tokenSet.ChromeTint = greyToken(CHROME_TINT_REST)
		tokenSet.ChromeTintHover = greyToken(CHROME_TINT_HOVER)
		tokenSet.ChromeTintPressed = greyToken(CHROME_TINT_PRESSED)
		tokenSet.ChromeTintSelected = lerp({ r = 1, g = 1, b = 1 }, entry.colors.accent, 0.35)
		-- a hovered selected skin: the selection lifted as danger's hover is, so
		-- hover never repaints a selected row as an unselected one
		tokenSet.ChromeTintSelectedHover = lerp(tokenSet.ChromeTintSelected, WHITE, 0.18)
		-- ...and pressed, darkened as danger's press is, so a press never reads unselected
		tokenSet.ChromeTintSelectedPressed = lerp(tokenSet.ChromeTintSelected, BLACK, 0.18)
		-- ROLE TINTS (director review 2026-07-25: "a tint like on delete profile
		-- should tint the IMAGE, not give a random button behind it"). With the
		-- native plate suppressed under the art there is no coloured slab left to
		-- paint a role on, so the role has to reach the ART itself: `ImageColor3`
		-- multiplies the skin, and a red multiplier turns the parchment slab
		-- dangerous while keeping its grain, its torn edge and its ornament.
		--
		-- Each is lifted toward white BEFORE it multiplies: a raw danger colour
		-- multiplied into mid-tone parchment lands almost black, and a warning
		-- nobody can read is not a warning. The hover/press pair uses the same
		-- edge lerps the fill tokens use, so a destructive button's states read
		-- as one family whether it is skinned or flat. Emitted on EVERY theme,
		-- always — a `$Token` that resolves in one theme and not another is a
		-- rule that stops painting on a swap.
		local dangerColor = (select(1, dangerPair(entry.colors)))
		local dangerTint = lerp(dangerColor, WHITE, 0.3)
		tokenSet.ChromeTintDanger = dangerTint
		tokenSet.ChromeTintDangerHover = lerp(dangerTint, WHITE, 0.18)
		tokenSet.ChromeTintDangerPressed = lerp(dangerTint, BLACK, 0.18)
		-- cancel reads RECESSIVE: the resting grey pulled toward the surface, so
		-- a cancel slab sits back from its destructive neighbour
		tokenSet.ChromeTintCancel = lerp(greyToken(CHROME_TINT_REST), entry.colors.surface, 0.45)
		-- the primary action reads as the accent, lifted exactly as danger is
		tokenSet.ChromeTintAccent = lerp(entry.colors.accent, WHITE, 0.3)
		-- ...and its lifted label is the partner that reads on THAT plate: the
		-- theme's control art multiplied by the accent tint is not the accent fill
		-- `onAccent` is gated against (a mid wood or dark lacquer plate under it)
		tokenSet.OnAccentChrome = color(sheet_model.onChromeColor(styleLike, tokenSet.ChromeTintAccent))
		local rest = { r = CHROME_TINT_REST, g = CHROME_TINT_REST, b = CHROME_TINT_REST }
		local c = entry.colors
		-- every lifted label role, picked against the art it sits on: its own
		-- colour where that reads, else the next of the ramp that does
		local function pick(tint: any, picks: { any }, art: string?): TokenValue
			return color(sheet_model.readableOnChrome(styleLike, tint, picks, art))
		end
		local body = { c.content, c.contentStrong, c.onAccent }
		local quiet = { x.contentSecondary, c.content, c.contentStrong, c.onAccent }
		tokenSet.OnControlChrome = pick(rest, body)
		tokenSet.OnControlChromeStrong = pick(rest, { c.contentStrong, c.content, c.onAccent })
		tokenSet.OnControlChromeSecondary = pick(rest, quiet)
		tokenSet.OnCancelChrome = pick(tokenSet.ChromeTintCancel, quiet)
		tokenSet.OnFieldChrome = pick(rest, body, "fieldArt")
		tokenSet.OnFieldChromeSecondary = pick(rest, quiet, "fieldArt")
		tokenSet.OnBadgeChrome = pick(rest, body, "badgeArt")
		tokenSet.OnPanelChrome = pick(rest, body, "panelArt")
		tokenSet.OnPanelChromeStrong = pick(rest, { c.contentStrong, c.content, c.onAccent }, "panelArt")
		tokenSet.OnPanelChromeSecondary = pick(rest, quiet, "panelArt")
		-- a soft button's art wears the selection wash (`Chrome role — soft`)
		tokenSet.OnSoftChrome = pick(
			tokenSet.ChromeTintSelected,
			{ sheet_model.selectedContentColor(styleLike), c.content, c.contentStrong, c.onAccent }
		)
		tokenSet.OnDangerChrome = color(
			sheet_model.readableOnChrome(
				styleLike,
				dangerTint,
				{ (select(2, dangerPair(c))), c.content, c.contentStrong }
			)
		)
		-- the lifted labels' backing transparency (`extra.chromeTextStroke`)
		tokenSet.ChromeTextStroke = num(if type(x.chromeTextStroke) == "number" then x.chromeTextStroke else 1)
		--[[ ...AND THE LABELS KEEP READING WHILE HOVERED AND PRESSED (readability
			round 2026-09-23). A state re-tints the art under an unchanged label: the
			resting grey lifts to 1.0 and presses to 0.66, a role's tint lightens and
			darkens by 0.18, and a package may swap in its own state art. On mid-tone
			art the full excursion carried a label under the floor (parchment
			Daylight pressed 3.49, a hovered emphasis button on Glossy 1.46). So each
			state tint goes as far toward its target as every label on it still
			reads, in tenths, and no further — the state still shows, the words
			still read. A package with no art keeps the constants. ]]
		if type(x.controlArt) == "table" then
			local backed = type(x.chromeTextStroke) == "number"
			-- the furthest tenth of `reach` toward `target` at which every (label, art)
			-- pair still reads — directly, or on the package's glyph backing. A
			-- package's own state art may already have moved the plate past the
			-- label (Compact's pressed button is darker art), so when no step toward
			-- the target reads, the tint leans the other way, no further than needed.
			local function stateTint(base: any, target: any, reach: number, pairs: { { any } }): TokenValue
				local other = if target == WHITE then BLACK else WHITE
				for step = 10, -20, -1 do
					local tint = if step >= 0
						then lerp(base, target, reach * step / 10)
						else lerp(base, other, -step / 20)
					local ok = true
					for _, pair in pairs do
						local plate = sheet_model.chromePlate(styleLike, tint, pair[2])
						ok = ok
							and (
								tokens.contrastRatio(pair[1], plate) >= SELECTED_CONTRAST_FLOOR
								or (backed and tokens.contrastRatio(pair[1], c.surface) >= SELECTED_CONTRAST_FLOOR)
							)
					end
					if ok then
						return tint
					end
				end
				return color(base)
			end
			local t = tokenSet :: any
			for _, state in { "Hover", "Pressed" } do
				local art = if type(x["controlArt" .. state]) == "table" then "controlArt" .. state else "controlArt"
				local target, reach =
					if state == "Hover" then WHITE else BLACK,
					if state == "Hover" then 1 else 1 - CHROME_TINT_PRESSED / CHROME_TINT_REST
				t["ChromeTint" .. state] = stateTint(rest, target, reach, {
					{ t.OnControlChrome, art },
					{ t.OnControlChromeStrong, art },
					{ t.OnControlChromeSecondary, art },
					{ t.OnFieldChrome, "fieldArt" },
					{ t.OnFieldChromeSecondary, "fieldArt" },
					{ t.OnPanelChrome, "panelArt" },
					{ t.OnPanelChromeStrong, "panelArt" },
					{ t.OnPanelChromeSecondary, "panelArt" },
					{ t.OnBadgeChrome, "badgeArt" },
				})
				for _, entry in
					{
						{ "ChromeTintAccent", t.OnAccentChrome },
						{ "ChromeTintCancel", t.OnCancelChrome },
						{ "ChromeTintSelected", t.OnSoftChrome },
						{ "ChromeTintDanger", t.OnDangerChrome },
					}
				do
					t[entry[1] .. state] = stateTint(t[entry[1]], target, 0.18, { { entry[2], art } })
				end
			end
		else
			tokenSet.ChromeTintAccentHover = lerp(tokenSet.ChromeTintAccent, WHITE, 0.18)
			tokenSet.ChromeTintAccentPressed = lerp(tokenSet.ChromeTintAccent, BLACK, 0.18)
			tokenSet.ChromeTintCancelHover = lerp(tokenSet.ChromeTintCancel, WHITE, 0.18)
			tokenSet.ChromeTintCancelPressed = lerp(tokenSet.ChromeTintCancel, BLACK, 0.18)
		end
		-- a stepper's PRESSED plate may be different art altogether (Glossy's is
		-- the accent blue), so its label on that plate is picked there
		tokenSet.OnStepperChromePressed = pick(
			if type(x.stepperArtPressed) == "table"
				then lerp(rest, BLACK, 1 - CHROME_TINT_PRESSED / CHROME_TINT_REST)
				else rest,
			body,
			"stepperArtPressed"
		)
		-- gradient tokens. EVERY theme carries a token for every gradient slot
		-- any theme declares: a `$Token` that resolves in one theme and not in
		-- another is a rule that stops painting on a swap, so a theme that
		-- declared nothing gets an inert flat-white ramp instead of a hole.
		for slot in gradientSlots do
			local key = "Gradient" .. pascal(slot)
			local declared = gradientOf(entry, slot)
			if declared ~= nil then
				tokenSet[key] = chrome_props.colorSeq(declared.stops)
				tokenSet[key .. "Rotation"] = { kind = "number", value = declared.rotation or 90 }
				tokenSet[key .. "Alpha"] = chrome_props.numSeq(declared.alpha or { { t = 0, v = 0 }, { t = 1, v = 0 } })
			else
				tokenSet[key] = chrome_props.colorSeq({
					{ t = 0, r = 1, g = 1, b = 1 },
					{ t = 1, r = 1, g = 1, b = 1 },
				})
				tokenSet[key .. "Rotation"] = { kind = "number", value = 0 }
				tokenSet[key .. "Alpha"] = chrome_props.numSeq({ { t = 0, v = 0 }, { t = 1, v = 0 } })
			end
		end
		table.insert(themes, {
			name = entry.name,
			tokens = tokenSet,
			contrast = gateTheme(entry.name, styleLike),
		})
	end

	local defaultTheme = o.defaultTheme or package.style.defaultTheme or themes[1].name
	local baseExtra = extraByTheme[defaultTheme] or extraByTheme[themes[1].name]
	local S = sheet_model.TAGS.surfacePrefix
	local T = sheet_model.TAGS

	-- THE FACE FOR A ROLE, authored or DERIVED (F2, 2026-08-02). `strong` and
	-- `numeral` are optional in a package, and the theme SNAPSHOT derives an
	-- unauthored one (`themePackage.deriveTypeRole`) — so the sheet has to derive
	-- it the same way or native paint would draw a face the solver did not measure,
	-- which is the whole split this channel exists to close.
	local function fontOf(role: string): RuleProp
		local entry = metrics.typography[role]
			or themePackage.deriveTypeRole(role, metrics.typography)
			or metrics.typography.body
		return { kind = "font", family = entry.font.family, weight = entry.font.weight, style = entry.font.style }
	end

	-- ----- v2 census + the pixel stamp -------------------------------------
	-- rich-skinning v2 reads these: cost honesty is a counted number per kind, not an
	-- impression. A flat package leaves every ART number at zero; the one number
	-- it does not is `suppressionRules`, which carries the value family's
	-- pre-armed 4x3 baseline (director round 5 — see the OWN_PAINT loop in the
	-- chrome section). Counted rather than hidden: it is twelve real rules in
	-- every sheet, and a census that quietly excused its own baseline would be
	-- the impression this table exists to replace.
	local census: any = {
		imageRules = 0,
		pixelatedRules = 0,
		suppressionRules = 0,
		variantRules = 0,
		variantAssets = 0,
		layerRules = 0,
		layers = 0,
		layersPerKind = {},
		layeredSlots = {},
		overhang = {},
	}
	local pixelUnit = themePackage.pixelUnitOf(package)
	-- rs-m5 generation rule 1: EVERY image-bearing rule a pixel package emits
	-- carries ResampleMode=Pixelated. Censused on both sides so a missed rule is
	-- a counted defect (`pixelatedRules == imageRules`) rather than a visual hunt.
	-- The engine ENUM is `ResamplerMode`; the PROPERTY is `ResampleMode`.
	local PIXELATED: RuleProp = { kind = "enum", enum = "ResamplerMode", item = "Pixelated" }
	local function imageProps(props: { [string]: RuleProp }): { [string]: RuleProp }
		census.imageRules += 1
		if pixelUnit ~= nil then
			props.ResampleMode = PIXELATED
			census.pixelatedRules += 1
		end
		return props
	end
	-- distinct art a package reaches for across states, counted once per content
	-- id (the preload seam's cost)
	local variantSeen: { [string]: boolean } = {}
	local function noteVariantAsset(contentId: string)
		if not variantSeen[contentId] then
			variantSeen[contentId] = true
			census.variantAssets += 1
		end
	end

	-- ----- the ordered groups ---------------------------------------------
	local groups: { [string]: { Rule } } = {}
	for _, name in sheet_model.RULE_GROUPS do
		groups[name] = {}
	end
	local function emit(group: string, rule: Rule)
		rule.group = group
		table.insert(groups[group], rule)
	end

	-- ----- per-state ART -------------------------------------
	-- One state, one rule, carrying `Image` and nothing else. The per-state TINT
	-- rules are separate rules on separate props, so they still apply on top —
	-- which is exactly the declared semantics: an unstated state falls back to the
	-- default art WITH its tint, and a supplied `disabled` art still gets the
	-- disabled transparency treatment (the accessibility floor is not a variant's
	-- to remove). The decoration is Active=false and reports no GuiState of its
	-- own, so every selector reads the state from the PARENT through the child
	-- combinator, exactly as the tint rules do.
	--
	-- `error` is the one state with no engine pseudo and no renderer tag today —
	-- it keys on `facet-state-error`, which `classifyTags` emits when a control
	-- publishes it. P3's control wiring is what makes that tag appear; until
	-- then the rule is emitted and matches nothing, which is visible in the
	-- census rather than hidden.
	local VARIANT_RULES: { [string]: { group: string, prefix: string } } = {
		hover = { group = "hover", prefix = `.{T.interactive}.{T.pointerLive}:Hover > ` },
		pressed = { group = "press", prefix = `.{T.interactive}:Press > ` },
		selected = { group = "chrome", prefix = `.{T.selected} > ` },
		disabled = { group = "disabled", prefix = ":NonInteractable > " },
		error = { group = "chrome", prefix = `.{chrome_slots.TAGS.stateError} > ` },
	}

	-- ON/OFF IS A VALUE, NOT A GuiState. Every other variant
	-- state rides an engine pseudo or a tag the renderer already emits; a switch's
	-- ON state is the control's VALUE, and no rule can see a value — which is
	-- exactly why `togglePalette` stayed a bespoke colour write. The art therefore
	-- keys on a tag the adapter flips beside those same colour writes, and the
	-- toggle slots read `selected` as that tag instead of the row-selection one.
	local SLOT_SELECTED_TAG: { [string]: string } =
		{ toggleTrack = chrome_slots.TOGGLE_ON_TAG, toggleKnob = chrome_slots.TOGGLE_ON_TAG }

	local function emitVariantArt(baseName: string, tag: string, variants: any, selectedTag: string?)
		if variants == nil then
			return
		end
		for _, state in themePackage.VARIANT_STATES do
			local entry = variants[state]
			if entry == nil then
				continue
			end
			if state == "default" then
				continue -- the resting rule already paints it
			end
			-- counted per DISTINCT non-default asset: this is the extra art a
			-- per-state map costs the preload seam, which is the number rich-skinning v2
			-- wants and the base art is not part of
			noteVariantAsset(entry.contentId)
			local spec = VARIANT_RULES[state]
			local prefix = if state == "selected" and selectedTag ~= nil then `.{selectedTag} > ` else spec.prefix
			emit(spec.group, {
				name = `{baseName} {state} art`,
				selector = `{prefix}.{tag}`,
				props = imageProps({ Image = entry.contentId }),
			})
			census.variantRules += 1
		end
	end

	-- THE IMAGE IS THE ELEMENT (extending the Step 3.5 machinery).
	-- Before art can BE the control, the control's native plate has to stop being
	-- drawn under it: fill, ::UICorner radius and ::UIStroke hairline all go to
	-- nothing on the DECORATED NODE. Emitted per skinned slot — nine-slice and
	-- layered alike — never globally, so a slot the package paints natively keeps
	-- every bit of its Facet-Neutral chrome.
	--
	-- ONCE PER SLOT. A RULE NAME IS IDENTITY (see the base group below), so the
	-- same slot reaching this twice — a value slot that is both pre-armed below
	-- and declared by a recipe — must produce ONE rule, not a duplicate pair the
	-- Style Editor lists twice and `setRuleProperty` picks between at random.
	local suppressed: { [string]: boolean } = {}
	local function emitSuppression(slot: string)
		if suppressed[slot] then
			return
		end
		suppressed[slot] = true
		-- the same three rules `build`'s base seed pre-arms, from the same shared
		-- emitter (rich-skinning v2): a package sheet and the base sheet must suppress a
		-- skinned value slot identically or a rung-2 override reads differently
		-- depending on whether a package happens to be installed
		emitSlotSuppression(slot, function(rule: Rule)
			emit("chrome", rule)
		end)
		census.suppressionRules += 3
	end

	-- base: class defaults + text/font defaults. As in `build`, the
	-- BackgroundTransparency defaults are RULES rather than adapter writes,
	-- because an explicit write at create would permanently defeat every
	-- surface rule (spike m10).
	-- A RULE NAME IS IDENTITY, not a label. It is what the Style Editor lists,
	-- what a designer's saved edit is keyed to, and what `setRuleProperty` looks
	-- up — so the package builder must speak the SAME vocabulary the legacy
	-- builder taught (`Label default`, never `TextLabel default`). A renamed rule
	-- reads as a deleted rule plus a new one: the designer's edit is orphaned and
	-- every metric push silently misses.
	for _, class in { "Frame", "TextLabel", "TextButton", "ImageLabel", "TextBox", "ScrollingFrame", "CanvasGroup" } do
		emit("base", {
			name = `{CLASS_DEFAULT_NAME[class]} default`,
			selector = class,
			props = { BackgroundTransparency = num(1) },
		})
	end
	-- ...and the tinted fill, in the SAME cascade position the legacy builder gives
	-- it (see that rule, and TAGS.tintFill). A floor only one builder emits is a
	-- floor that vanishes the moment a player picks a package — the rich-skinning v2 decision's defect,
	-- one rule over.
	emit("base", { name = "Tint fill", selector = `.{T.tintFill}`, props = { BackgroundTransparency = num(0) } })
	emit("base", {
		name = "Text default",
		selector = "TextLabel",
		props = { TextColor3 = "$Content", FontFace = fontOf("body") },
	})
	-- A FONT is a metric-derived rule prop exactly like a corner radius is: the
	-- descriptor is baked into the rule as a literal Font, so a designer's
	-- Type_*_font edit re-keyed MEASUREMENT while the paint kept the seeded
	-- face — the solver reserving one family and the engine drawing another,
	-- which is the split this stage exists to close.
	fromMetric("type.body.font", "Text default", "FontFace", "font")
	emit("base", {
		name = "Button text default",
		selector = "TextButton",
		props = { TextColor3 = "$Content", FontFace = fontOf("control") },
	})
	fromMetric("type.control.font", "Button text default", "FontFace", "font")
	emit("base", {
		name = "Field text default",
		selector = "TextBox",
		props = {
			TextColor3 = "$Content",
			PlaceholderColor3 = "$ContentSecondary",
			FontFace = fontOf("control"),
		},
	})
	fromMetric("type.control.font", "Field text default", "FontFace", "font")
	--[[ TEXT ON ANOTHER NODE'S PLATE (readability round 2026-09-23). A field's
		editor, a stepper's mark, a picker's value and an author's label on a skinned
		box are not lifted — their plate is an ancestor or an earlier layer — so the
		renderer tags them with that plate's slot (`chrome_slots.withPlateBeneath`)
		and they take the colours picked against its art, exactly as a lifted label
		does. Here, beside the class defaults they replace, so every appearance,
		role and state rule after them still wins; only slots this package paints
		with art. ]]
	local onArtRoles: { { string } } = {}
	for _, entry in
		{
			{ "control", "$OnControlChrome", "$OnControlChromeStrong", "$OnControlChromeSecondary" },
			{ "field", "$OnFieldChrome", "$OnFieldChrome", "$OnFieldChromeSecondary" },
			{ "badge", "$OnBadgeChrome", "$OnBadgeChrome", "$OnBadgeChrome" },
			{ "panel", "$OnPanelChrome", "$OnPanelChromeStrong", "$OnPanelChromeSecondary" },
		}
	do
		if ninePlans[entry[1]] ~= nil or stacks[entry[1]] ~= nil then
			table.insert(onArtRoles, entry)
		end
	end
	for _, entry in onArtRoles do
		local tag = `.{chrome_slots.TAGS.onArtPrefix}{entry[1]}`
		emit("base", { name = `On plate — {entry[1]}`, selector = tag, props = { TextColor3 = entry[2] } })
		emit("base", {
			name = `On plate — {entry[1]} placeholder`,
			selector = `TextBox{tag}`,
			props = { PlaceholderColor3 = entry[4] },
		})
	end
	-- THE PER-ROLE FACES (F2, 2026-08-02). A node's typography role reaches native
	-- paint as `facet-type-<role>`; this is the rule that gives that tag its face,
	-- from the SAME `type.<role>.font` the solver measured with. Emitted for all
	-- eight roles, class defaults included, so a role always beats the class rule
	-- it sits on (a `strong` Text inside a TextButton, a `body` Button label) — and
	-- inert wherever the package's ramp shares one face, which is every flat
	-- reference package and Facet Neutral.
	--
	-- The live-edit push (`fromMetric`) is registered only for an AUTHORED role: a
	-- derived one has no `type.<role>.font` token attribute for the watcher to read.
	for _, role in themePackage.TYPE_ROLES do
		local ruleName = `Type — {role}`
		emit("base", { name = ruleName, selector = `.{T.typePrefix}{role}`, props = { FontFace = fontOf(role) } })
		if metrics.typography[role] ~= nil then
			fromMetric(`type.{role}.font`, ruleName, "FontFace", "font")
		end
	end
	emit("base", {
		name = "Scroll bar",
		selector = "ScrollingFrame",
		props = { ScrollBarImageColor3 = "$ContentSecondary" },
	})

	-- surfaces (+ the phantom corner/stroke modifiers)
	local hairlineT = num(baseExtra.hairlineOpacity)
	local hairlineW = num(metrics.strokes.hairline)
	emit("surfaces", {
		name = "Base surface",
		selector = "." .. S .. "base",
		props = { BackgroundColor3 = "$Surface", BackgroundTransparency = num(0) },
	})
	emit("surfaces", {
		name = "Pane surface",
		selector = "." .. S .. "pane",
		props = { BackgroundColor3 = "$SurfaceStrong", BackgroundTransparency = num(0) },
	})
	emit("surfaces", {
		name = "Raised panel",
		selector = "." .. S .. "raised",
		props = { BackgroundColor3 = "$SurfaceStrong", BackgroundTransparency = num(0) },
	})
	emit("surfaces", {
		name = "Raised panel — corner",
		selector = "." .. S .. "raised::UICorner",
		props = { CornerRadius = udim(0, metrics.radii.panel) },
	})
	fromMetric("radii.panel", "Raised panel — corner", "CornerRadius", "udimOffset")
	emit("surfaces", {
		name = "Raised panel — hairline",
		selector = "." .. S .. "raised::UIStroke",
		props = {
			Color = "$Hairline",
			Transparency = hairlineT,
			Thickness = hairlineW,
			ApplyStrokeMode = STROKE_BORDER,
			BorderStrokePosition = STROKE_INNER,
		},
	})
	fromMetric("strokes.hairline", "Raised panel — hairline", "Thickness", "number")
	emit("surfaces", {
		name = "Control fill",
		selector = "." .. S .. "control",
		props = { BackgroundColor3 = "$Control", BackgroundTransparency = num(0) },
	})
	emit("surfaces", {
		name = "Control — corner",
		selector = "." .. S .. "control::UICorner",
		props = { CornerRadius = udim(0, metrics.radii.control) },
	})
	fromMetric("radii.control", "Control — corner", "CornerRadius", "udimOffset")
	emit("surfaces", {
		name = "Field — outline",
		selector = "TextBox." .. S .. "control::UIStroke",
		props = {
			Color = "$Hairline",
			Transparency = hairlineT,
			Thickness = hairlineW,
			ApplyStrokeMode = STROKE_BORDER,
			BorderStrokePosition = STROKE_INNER,
		},
	})
	fromMetric("strokes.hairline", "Field — outline", "Thickness", "number")
	emit("surfaces", {
		name = "Chip",
		selector = "." .. S .. "chip",
		props = { BackgroundColor3 = "$Control", BackgroundTransparency = num(0) },
	})
	emit("surfaces", {
		name = "Chip — corner",
		selector = "." .. S .. "chip::UICorner",
		props = { CornerRadius = udim(0, metrics.radii.control) },
	})
	fromMetric("radii.control", "Chip — corner", "CornerRadius", "udimOffset")
	emit("surfaces", {
		name = "Chip — outline",
		selector = "." .. S .. "chip::UIStroke",
		props = {
			Color = "$Hairline",
			Transparency = hairlineT,
			Thickness = hairlineW,
			ApplyStrokeMode = STROKE_BORDER,
			BorderStrokePosition = STROKE_INNER,
		},
	})
	fromMetric("strokes.hairline", "Chip — outline", "Thickness", "number")
	emit("surfaces", {
		name = "Badge",
		selector = "." .. S .. "badge",
		props = { BackgroundColor3 = "$SurfaceStrong", BackgroundTransparency = num(0) },
	})
	emit("surfaces", {
		name = "Badge — circle",
		selector = "." .. S .. "badge::UICorner",
		props = { CornerRadius = udim(0.5, 0) },
	})
	emit("surfaces", {
		name = "Primary button",
		selector = "." .. S .. "accent",
		props = { BackgroundColor3 = "$Accent", BackgroundTransparency = num(0) },
	})
	-- see the base seed: the accent surface REPLACES the chip/control one, so it
	-- has to carry its own corner or a selected button goes square (round 11)
	emit("surfaces", {
		name = "Primary button — corner",
		selector = "." .. S .. "accent::UICorner",
		props = { CornerRadius = udim(0, metrics.radii.control) },
	})
	fromMetric("radii.control", "Primary button — corner", "CornerRadius", "udimOffset")
	emit("surfaces", {
		name = "Primary button label",
		selector = "TextButton." .. S .. "accent",
		props = { TextColor3 = "$OnAccent" },
	})
	-- VALUE-CONTROL CHROME: ITS OWN PAINT (director follow-up 2026-07-25).
	--
	-- "in glossy_shadows, the slider button should be solid." The thumb used to
	-- declare `surface = "raised"` to get a fill, which subscribed it to the
	-- whole PANEL treatment — including Glossy's panel gradient, whose alpha made
	-- it translucent so the accent fill behind it read through. A rail is not a
	-- button and a thumb is not a panel.
	--
	-- These rules are the replacement: keyed on the hint tag (present whether or
	-- not the package skins the slot), SOLID by construction, and drawing their
	-- colour from the SAME `SLOT_FILL_TOKEN` map the asset-failure fallback uses,
	-- so a slot's flat appearance is one decision rather than two that drift.
	-- Emitted for every package including the flat ones — and, since the rich-skinning v2 decision,
	-- by `build`'s base seed through this same shared emitter, because a value
	-- control has to be visible under Facet Neutral too and that is the one path
	-- this loop used not to reach.
	-- the disc's chrome, in the group right after the surfaces whose corners it
	-- replaces and right before `chrome`, whose skinned-slot suppression must
	-- still beat it (see emitShapeChrome)
	-- Preserve the base seed's cascade order: vocabulary surfaces, shape, then roles.
	local vocabRoleRules: { Rule } = {}
	emitVocabularyChrome(metrics, hairlineT, hairlineW, function(rule: Rule)
		emit("surfaces", rule)
	end, function(rule: Rule)
		table.insert(vocabRoleRules, rule)
	end, fromMetric)
	emitShapeChrome(metrics, hairlineT, hairlineW, function(rule: Rule)
		emit("roles", rule)
	end, fromMetric)
	for _, rule in vocabRoleRules do
		emit("roles", rule)
	end
	for _, slot in chrome_slots.OWN_PAINT_SLOTS do
		emitOwnSlotPaint(slot, metrics, hairlineT, hairlineW, function(rule: Rule)
			emit("surfaces", rule)
		end, fromMetric)
	end
	emit("surfaces", {
		name = sheet_model.SCRIM_RULE,
		selector = "." .. S .. "scrim",
		props = { BackgroundColor3 = "$Scrim", BackgroundTransparency = num(baseExtra.scrimOpacity) },
	})

	-- roles
	-- the same one-opacity rule the base seed carries, and for the same reason
	emit("roles", {
		name = "Divider",
		selector = ".facet-divider",
		props = { BackgroundColor3 = "$Hairline", BackgroundTransparency = hairlineT },
	})
	emit("roles", {
		name = "Strong divider",
		selector = `.facet-divider.{T.appearancePrefix}strong`,
		props = { BackgroundTransparency = num(strongHairlineOpacity(baseExtra)) },
	})
	emit(
		"roles",
		{ name = "Secondary text", selector = ".facet-role-secondary", props = { TextColor3 = "$ContentSecondary" } }
	)
	emit("roles", { name = "Strong text", selector = ".facet-role-strong", props = { TextColor3 = "$ContentStrong" } })
	-- ...and the two text roles on a plate's art (see "On plate" above)
	for _, entry in onArtRoles do
		local tag = `.{chrome_slots.TAGS.onArtPrefix}{entry[1]}`
		emit("roles", {
			name = `On plate — {entry[1]} secondary`,
			selector = `{tag}.facet-role-secondary`,
			props = { TextColor3 = entry[4] },
		})
		emit("roles", {
			name = `On plate — {entry[1]} strong`,
			selector = `{tag}.facet-role-strong`,
			props = { TextColor3 = entry[3] },
		})
	end
	emit("roles", {
		name = "Grip focus",
		selector = ".facet-grip-focus",
		props = { BackgroundColor3 = "$Accent", BackgroundTransparency = num(0) },
	})
	emit(
		"roles",
		{ name = "Toggle chrome", selector = ".facet-toggle-chrome", props = { BackgroundTransparency = num(0) } }
	)
	emit("roles", {
		name = "Selected row",
		selector = "TextButton." .. T.selected,
		-- see the base seed: one token, one decision, both builders
		props = { BackgroundColor3 = "$ControlSelected", TextColor3 = "$OnSelected" },
		transitions = { BackgroundColor3 = "fast" },
	})
	emit("roles", {
		name = "Destructive button",
		selector = ".facet-role-destructive",
		props = { BackgroundColor3 = "$Danger", TextColor3 = "$OnDanger" },
	})
	emit("roles", {
		name = "Destructive label",
		selector = "TextButton.facet-role-destructive-label",
		props = { TextColor3 = "$Danger" },
	})
	emit("roles", {
		name = "Cancel button",
		selector = ".facet-role-cancel",
		props = { BackgroundColor3 = "$Surface", TextColor3 = "$ContentSecondary" },
	})
	-- the label-only role: see the base seed for why it carries no fill
	emit("roles", {
		name = "Indicator label",
		selector = "TextButton." .. ON_INDICATOR_TAG,
		props = { TextColor3 = "$OnAccent" },
	})
	-- the compound role x appearance rules, immediately after the roles they must
	-- beat — the same position and the same emitter as the base seed's
	emitVocabularyRoles(function(rule: Rule)
		emit("roles", rule)
	end)
	local markHover: { Rule } = {}
	if authoredSelection(package.style.themes) then
		emitSelectionMark(function(rule: Rule)
			emit("roles", rule)
		end, function(rule: Rule)
			table.insert(markHover, rule)
		end, T.pointerLive)
	end

	-- A SKINNED VALUE SLOT SUPPRESSES ITS OWN PAINT TOO (director round 5,
	-- 2026-07-25). The three `Slot — <slot>` rules above are the ACCESSIBILITY
	-- floor for a value control nothing else paints — and a floor is for a node
	-- with no art on it. The moment a node carries `facet-skinned-<slot>` the art
	-- IS the element (R9), and a solid slab behind it shows through every
	-- transparent pixel the art has: measured live on the rung-2 slider thumb,
	-- whose view-supplied picture sat inside a ring of its own `$SurfaceStrong`
	-- plate (`GetStyled` 0 -> 1 across the fix; capture
	-- `RS-DIR5_zoom6x_rung2-thumb_before-after.png`).
	--
	-- PRE-ARMED, not recipe-driven, which is the whole point. A node earns the
	-- skinned tag from THREE routes — a package nine-slice recipe, a layer stack,
	-- and the rung-2 per-view override — and only the first two run through the
	-- loops below. Under `glossy-touch` (no `sliderThumb` recipe at all) a view
	-- that supplied its own thumb image got the tag and no rule to match it.
	-- Emitting here means the rule exists for every package, flat ones included,
	-- and matches exactly when a node is actually skinned.
	--
	-- The GRADIENT ban is untouched and still a compile error: the hazard the
	-- Step 3.5 ruling was written for was a native wash riding value chrome, not
	-- an author's own art. An unskinned slot carries no skinned tag, so its solid
	-- paint is byte-identical to before.
	for _, slot in chrome_slots.OWN_PAINT_SLOTS do
		emitSuppression(slot)
	end

	-- chrome: gradients first (they paint the node itself), then the
	-- nine-slice decoration child, then its fallback and its selected tint
	for _, slot in chrome_slots.SLOTS do
		if gradientSlots[slot] then
			local key = "Gradient" .. pascal(slot)
			emit("chrome", {
				name = `Gradient — {slot}`,
				selector = SLOT_SELECTOR[slot] .. "::UIGradient",
				props = {
					Color = "$" .. key,
					Rotation = "$" .. key .. "Rotation",
					Transparency = "$" .. key .. "Alpha",
				},
			})
		end
	end
	for _, slot in chrome_slots.SLOTS do
		local plan = ninePlans[slot]
		if plan == nil then
			continue
		end
		local asset = package.assets[plan.assetName]
		local restingTint = "$ChromeTint"
		if type(asset.tintRole) == "string" then
			local token = TINT_ROLE_TOKEN[asset.tintRole]
			assert(
				token ~= nil,
				`sheet_model.buildPackage: asset '{plan.assetName}' names tintRole '{asset.tintRole}', `
					.. "which is not a palette role — a tint that resolves to nothing paints the art unchanged "
					.. "and is invisible until a device shows it"
			)
			restingTint = token
		end
		-- THE IMAGE IS THE BUTTON (director fix round; generalized to every
		-- image-bearing slot and to layer stacks). Sits in the chrome
		-- group, i.e. AFTER every surface rule it has to beat and before the
		-- interaction states (which only change colour, so an invisible plate
		-- stays invisible through hover and press).
		emitSuppression(slot)
		-- WHOLE IMAGE vs NINE SLICE. A sliced recipe owns all six image
		-- properties; a whole-image one (a thumb, a counter seal) owns four and
		-- must NOT name SliceCenter/SliceScale — a slice centre on a 28px token
		-- smears its one centre pixel across the whole middle.
		local restProps: { [string]: RuleProp } = {
			Image = plan.contentId,
			ScaleType = {
				kind = "enum",
				enum = "ScaleType",
				item = if plan.sliced then "Slice" else "Stretch",
			},
			ImageColor3 = restingTint,
			ImageTransparency = num(0),
		}
		if plan.sliced then
			restProps.SliceCenter = plan.sliceCenter
			restProps.SliceScale = num(plan.sliceScale)
		end
		emit("chrome", {
			name = `Chrome — {slot}`,
			selector = "." .. plan.tag,
			props = imageProps(restProps),
		})
		emitVariantArt(`Chrome — {slot}`, plan.tag, plan.variants, SLOT_SELECTED_TAG[slot])
		-- PER-END CAP ART. One recipe paints both ends; an end that
		-- named its own asset gets a second tag whose rule lands later in insertion
		-- order and therefore wins on that one instance — the per-corner idiom.
		if slot == "barCap" then
			local recipe = package.chrome.barCap
			for _, which in chrome_slots.BAR_ENDS do
				local named = chrome_slots.barCapAssetOf(recipe, which)
				if named == nil or named == plan.assetName then
					continue
				end
				local capAsset = package.assets[named]
				assert(
					type(capAsset) == "table",
					`sheet_model.buildPackage: chrome.barCap names cap asset '{named}', `
						.. "which the package does not declare"
				)
				emit("chrome", {
					name = `Chrome — barCap {which}`,
					selector = `.{chrome_slots.barCapTagFor(which)}`,
					props = imageProps({ Image = capAsset.contentId }),
				})
			end
		end
		-- the declared native fallback: tag-driven, so a failed asset repaints
		-- without touching hit geometry, focus or state
		emit("chrome", {
			name = `Chrome — {slot} fallback`,
			selector = `.{plan.tag}.{chrome_slots.TAGS.fallback}`,
			props = {
				BackgroundColor3 = SLOT_FILL_TOKEN[slot],
				BackgroundTransparency = num(0),
			},
		})
		-- THE HIDE IS A SECOND TAG (rich-skinning v2). The fill above lands on every art
		-- instance of a fallen-back slot; the hide lands only on the ones whose own
		-- asset is NOT the failed one, because `ImageTransparency = 1` is the
		-- engine's "do not decode" signal and using it on the condemned art
		-- destroyed the only instrument that could report its recovery. Emitted
		-- after the fill so insertion order still puts it above the resting art.
		emit("chrome", {
			name = `Chrome — {slot} fallback hide`,
			selector = `.{plan.tag}.{chrome_slots.TAGS.mute}`,
			props = { ImageTransparency = num(1) },
		})
		emit("chrome", {
			name = `Chrome — {slot} fallback corner`,
			selector = `.{plan.tag}.{chrome_slots.TAGS.fallback}::UICorner`,
			props = {
				CornerRadius = if SLOT_ROUND[slot] then udim(0.5, 0) else udim(0, slotRadius(metrics, slot)),
			},
		})
		if slot ~= "divider" and slot ~= "scrollbar" and not SLOT_ROUND[slot] then
			fromMetric(
				if slot == "panel" then "radii.panel" else "radii.control",
				`Chrome — {slot} fallback corner`,
				"CornerRadius",
				"udimOffset"
			)
		end
		if SLOT_STROKED[slot] then
			emit("chrome", {
				name = `Chrome — {slot} fallback hairline`,
				selector = `.{plan.tag}.{chrome_slots.TAGS.fallback}::UIStroke`,
				props = {
					Color = "$Hairline",
					Transparency = hairlineT,
					Thickness = hairlineW,
					ApplyStrokeMode = STROKE_BORDER,
					BorderStrokePosition = STROKE_INNER,
				},
			})
			fromMetric("strokes.hairline", `Chrome — {slot} fallback hairline`, "Thickness", "number")
		end
		-- SELECTED is a tint over the base image. A package that wants selection
		-- to change the PICTURE declares a `selected` variant; the
		-- tint then rides on top of that art, so both idioms compose.
		emit("chrome", {
			name = `Chrome — {slot} selected`,
			selector = `.{SLOT_SELECTED_TAG[slot] or T.selected} > .{plan.tag}`,
			props = { ImageColor3 = "$ChromeTintSelected" },
			transitions = { ImageColor3 = "fast" },
		})
	end

	-- ----- LAYER STACKS --------------------------------------
	-- Z-order IS array order, and the adapter assigns ZIndex 1..N from it. Every
	-- paint property here is RULE-owned from birth: rs-m2 measured that a value
	-- written on the instance BEFORE it joins the styled tree survives and
	-- permanently defeats a rule that only starts matching later, which is
	-- precisely what a per-state art swap is.
	for _, slot in chrome_slots.SLOTS do
		local stack = stacks[slot]
		if stack == nil then
			continue
		end
		table.insert(census.layeredSlots, slot)
		emitSuppression(slot)
		if chrome_slots.hasOverhang(stack.overhang) then
			census.overhang[slot] = stack.overhang
		end
		for _, layer in stack.layers do
			census.layers += 1
			census.layersPerKind[layer.kind] = (census.layersPerKind[layer.kind] or 0) + 1
			local asset = package.assets[layer.assetName]
			local restingTint = "$ChromeTint"
			if type(asset.tintRole) == "string" then
				local token = TINT_ROLE_TOKEN[asset.tintRole]
				assert(
					token ~= nil,
					`sheet_model.buildPackage: asset '{layer.assetName}' names tintRole '{asset.tintRole}', `
						.. "which is not a palette role — a tint that resolves to nothing paints the art unchanged "
						.. "and is invisible until a device shows it"
				)
				restingTint = token
			end
			local props: { [string]: RuleProp } = {
				Image = layer.contentId,
				ScaleType = { kind = "enum", enum = "ScaleType", item = layer.scaleType },
				ImageColor3 = restingTint,
				ImageTransparency = num(0),
			}
			if layer.sliced then
				props.SliceCenter = layer.sliceCenter
				props.SliceScale = num(layer.sliceScale)
			end
			if layer.scaleType == "Tile" then
				-- rs-m1: offset components are PIXELS, scale components are a
				-- fraction of the label. The schema authors px, so the rule does.
				local size = layer.geometry.tileSize
				local repeatPx = layer.geometry.tile
				local w = if type(size) == "table" then size.w else repeatPx
				local h = if type(size) == "table" then size.h else repeatPx
				props.TileSize = chrome_props.udim2(0, w or 0, 0, h or 0)
			end
			local baseName = `Chrome — {slot} L{layer.index} {layer.kind}`
			emit("chrome", { name = baseName, selector = `.{layer.tag}`, props = imageProps(props) })
			census.layerRules += 1
			emitVariantArt(baseName, layer.tag, layer.variants, SLOT_SELECTED_TAG[slot])
			-- PER-CORNER ORNAMENTS. The layer tag paints all four; a corner that
			-- declared its own art gets a second tag whose rule lands later in
			-- insertion order and therefore wins on that one instance.
			if layer.kind == "corners" then
				for _, corner in chrome_slots.CORNER_FIELDS do
					local variants = layer.cornerVariants[corner]
					if variants == nil then
						continue
					end
					local cornerName = `{baseName} {corner}`
					local cornerTag = chrome_slots.cornerTagFor(slot, layer.index, corner)
					emit("chrome", {
						name = cornerName,
						selector = `.{cornerTag}`,
						props = imageProps({ Image = variants.default.contentId }),
					})
					census.layerRules += 1
					emitVariantArt(cornerName, cornerTag, variants, SLOT_SELECTED_TAG[slot])
				end
			end
			-- the declared native fallback. The ladder hides; the BACK layer carries
			-- the native paint, because a stack that half-paints reads as a broken
			-- skin rather than a degraded one. THE HIDE IS THE SECOND TAG
			-- (rich-skinning v2): "hide the healthy siblings" is exactly what this rule is
			-- for, and the broken layer — which draws nothing anyway — keeps its art
			-- rules so its `IsLoaded` can still report a recovery.
			local fallbackProps: { [string]: RuleProp } = {}
			if layer.index == 1 then
				fallbackProps.BackgroundColor3 = SLOT_FILL_TOKEN[slot]
				fallbackProps.BackgroundTransparency = num(0)
			end
			if next(fallbackProps) ~= nil then
				emit("chrome", {
					name = `{baseName} fallback`,
					selector = `.{layer.tag}.{chrome_slots.TAGS.fallback}`,
					props = fallbackProps,
				})
			end
			emit("chrome", {
				name = `{baseName} fallback hide`,
				selector = `.{layer.tag}.{chrome_slots.TAGS.mute}`,
				props = { ImageTransparency = num(1) },
			})
			if layer.index == 1 then
				emit("chrome", {
					name = `{baseName} fallback corner`,
					selector = `.{layer.tag}.{chrome_slots.TAGS.fallback}::UICorner`,
					props = {
						CornerRadius = if SLOT_ROUND[slot] then udim(0.5, 0) else udim(0, slotRadius(metrics, slot)),
					},
				})
			end
			emit("chrome", {
				name = `{baseName} selected`,
				selector = `.{SLOT_SELECTED_TAG[slot] or T.selected} > .{layer.tag}`,
				props = { ImageColor3 = "$ChromeTintSelected" },
				transitions = { ImageColor3 = "fast" },
			})
			-- ONE PARENT TAG YIELDS THE WHOLE STACK (rs-m2). Today's only user is
			-- the TextBox editing yield, which has to reveal the engine caret
			-- drawn at the parent layer — with N layers over it, per-layer tagging
			-- would be N tag writes for one decision.
			if slot == "field" then
				emit("chrome", {
					name = `{baseName} editing`,
					selector = `.{chrome_slots.TAGS.stackYield} > .{layer.tag}`,
					props = { ImageTransparency = num(1), BackgroundTransparency = num(1) },
				})
			end
		end
	end
	-- SEMANTIC ROLE TINTS ON THE ART (director fix round; see the ChromeTint*
	-- role tokens above). These sit AFTER the resting `Chrome — control` rule so
	-- they own the resting appearance of a roled button, and before the
	-- interaction states, which layer on top exactly as they do for a flat fill.
	-- Only the `control` slot carries them: a role is a property of an
	-- interactive control, and painting a panel's art red because a descendant
	-- is destructive would be a bug, not a theme.
	-- the control slot's paint surface: one decoration tag, or EVERY layer of a
	-- layered control (a role has to reach whatever art is actually drawn, and a
	-- stack whose frame stayed neutral while its fill turned red is a worse
	-- answer than either)
	local controlTags: { string } = {}
	if ninePlans.control ~= nil then
		table.insert(controlTags, ninePlans.control.tag)
	end
	if stacks.control ~= nil then
		for _, layer in stacks.control.layers do
			table.insert(controlTags, layer.tag)
		end
	end
	for index, controlTag in controlTags do
		local suffix = if #controlTags > 1 then ` L{index}` else ""
		-- an appearance's fill is hidden under the art, so its emphasis reaches the
		-- art as the accent surface's does (before destructive, which outranks it)
		emit("chrome", {
			name = `Chrome role — emphasis{suffix}`,
			selector = `.{T.appearancePrefix}emphasis > .{controlTag}`,
			props = { ImageColor3 = "$ChromeTintAccent" },
			transitions = { ImageColor3 = "fast" },
		})
		emit("chrome", {
			name = `Chrome role — soft{suffix}`,
			selector = `.{T.appearancePrefix}soft > .{controlTag}`,
			props = { ImageColor3 = "$ChromeTintSelected" },
			transitions = { ImageColor3 = "fast" },
		})
		emit("chrome", {
			name = `Chrome role — destructive{suffix}`,
			selector = `.facet-role-destructive > .{controlTag}`,
			props = { ImageColor3 = "$ChromeTintDanger" },
			transitions = { ImageColor3 = "fast" },
		})
		emit("chrome", {
			name = `Chrome role — cancel{suffix}`,
			selector = `.facet-role-cancel > .{controlTag}`,
			props = { ImageColor3 = "$ChromeTintCancel" },
			transitions = { ImageColor3 = "fast" },
		})
		emit("chrome", {
			name = `Chrome role — accent{suffix}`,
			selector = `.{S}accent > .{controlTag}`,
			props = { ImageColor3 = "$ChromeTintAccent" },
			transitions = { ImageColor3 = "fast" },
		})
	end
	-- the chrome TEXT LIFT (a theme integration ruling): a text-bearing
	-- node under nine-slice chrome paints its label on a managed
	-- `.facet-chrome-text` child ABOVE the decoration (under Sibling z-behavior a
	-- child covers the parent's own engine-drawn text at any ZIndex). The lifted
	-- label is a TextLabel, so "Text default" already gives it $Content + the
	-- body font; these rules add the control-role font and the parent-tag
	-- variants via child combinators. TP-M8 is the theme feasibility probe, and
	-- selector validity was measured there.
	-- Emitted only when a text-bearing slot is actually skinned — flat themes
	-- carry none of this.
	-- SELECTION counts: a selectable row is a TextButton, so a selection-only skin
	-- lifts labels exactly like a control skin does. Leaving it out of the
	-- condition produced lifted labels with NO rules to paint them — the label
	-- inherited only "Text default" and every parent-role variant went missing.
	-- BADGE counts too (director fix round): a badge is a TextLabel, its count
	-- paints under the seal without a lift, and "3" was the exact value the
	-- director could not read.
	if
		ninePlans.control ~= nil
		or ninePlans.field ~= nil
		or ninePlans.selection ~= nil
		or ninePlans.badge ~= nil
		-- a LAYERED text-bearing slot lifts its label for exactly the same
		-- reason, and with a stack over it the reason is stronger
		or stacks.control ~= nil
		or stacks.field ~= nil
		or stacks.selection ~= nil
		or stacks.badge ~= nil
	then
		local liftTag = chrome_slots.TAGS.text
		-- THE SELECTED PLATE'S LABEL (director round 8). Emitted FIRST among the
		-- lift's colour rules, and deliberately: on the ART, a role/surface tint
		-- (`Chrome role — accent`, `… destructive`, `… cancel`) is emitted after
		-- the selected tint and therefore wins the picture, so it has to win the
		-- label too. `$OnSelected` is the theme's own decision (see
		-- `selectedContentColor`): $Content wherever it still clears the 4.5
		-- floor against the theme's selected surface, $OnAccent where it does not.
		-- a plain button's label on its resting art; every role and state below wins
		emit("chrome", {
			name = "Chrome text — control",
			selector = `.{chrome_slots.skinnedTagFor("control")} > .{liftTag}`,
			props = { TextColor3 = "$OnControlChrome" },
		})
		emit("chrome", {
			name = "Chrome text — field",
			selector = `.{chrome_slots.skinnedTagFor("field")} > .{liftTag}`,
			props = { TextColor3 = "$OnFieldChrome" },
		})
		emit("chrome", {
			name = "Chrome text — badge",
			selector = `.{chrome_slots.skinnedTagFor("badge")} > .{liftTag}`,
			props = { TextColor3 = "$OnBadgeChrome" },
		})
		-- a thin dark backing behind every lifted label (a glyph outline), only in a
		-- package whose art asks for one (`extra.chromeTextStroke`)
		local backed = false
		for _, x in extraByTheme do
			backed = backed or type(x.chromeTextStroke) == "number"
		end
		if backed then
			-- ...and behind text over another node's plate, which is on the same art
			local backedTags = { liftTag }
			for _, entry in onArtRoles do
				table.insert(backedTags, chrome_slots.TAGS.onArtPrefix .. entry[1])
			end
			for _, tag in backedTags do
				emit("chrome", {
					name = if tag == liftTag then "Chrome text — backing" else `Chrome text — backing ({tag})`,
					selector = `.{tag}::UIStroke`,
					props = {
						Color = "$Surface",
						Thickness = num(1),
						Transparency = "$ChromeTextStroke",
						ApplyStrokeMode = { kind = "enum", enum = "ApplyStrokeMode", item = "Contextual" },
					},
				})
			end
		end
		emit("chrome", {
			name = "Chrome text — selected",
			selector = `.{T.selected} > .{liftTag}`,
			props = { TextColor3 = "$OnSelected" },
		})
		emit("chrome", {
			name = "Chrome text — button font",
			selector = `TextButton > .{liftTag}`,
			props = { FontFace = fontOf("control") },
		})
		fromMetric("type.control.font", "Chrome text — button font", "FontFace", "font")
		emit("chrome", {
			name = "Chrome text — field font",
			selector = `TextBox > .{liftTag}`,
			props = { FontFace = fontOf("control") },
		})
		fromMetric("type.control.font", "Chrome text — field font", "FontFace", "font")
		emit("chrome", {
			name = "Chrome text — accent",
			selector = `.{S}accent > .{liftTag}`,
			props = { TextColor3 = "$OnAccentChrome" },
		})
		emit("chrome", {
			name = "Chrome text — destructive",
			selector = `.facet-role-destructive > .{liftTag}`,
			props = { TextColor3 = "$OnDangerChrome" },
		})
		--[[ ...and the label-only role's lifted twin (stabilization B'1). A skinned
			text-bearing slot moves the label into a managed child, so every
			parent-role colour needs one of these or the lift paints plain $Content —
			which is exactly the defect the unlifted rule closes, one node down.

			NOTHING IN THE TREE REACHES IT TODAY, and that is stated rather than left
			for a reader to assume from the family it sits in. The only consumer of
			`onIndicator` is the segmented Picker's covered option, which is always
			`surface = "plain"` — and `chrome_slots.classify` returns NO SLOT for
			`plain` ("AN EXPLICIT `plain` PAINTS NOTHING — including chrome",
			`chrome_slots.luau`), so that option gets no decoration and no
			`FacetChromeText` child under ANY package. Verified headless on
			`glossy_touch` and `fantasy_ornate`: no lift instance is created, and the
			label reaches the screen through the UNLIFTED rule above in every package,
			exactly as it does on a flat theme.

			It is emitted anyway, for the reason every sibling in this family is: the
			set is generated per role, and a role missing its twin is the defect
			`Chrome text — accent` and `— selected` were both added to fix. It becomes
			live the day a control pairs a `decorationHint` (which outranks `plain`)
			with this role. So: proved to COMPILE, not proved to paint. ]]
		emit("chrome", {
			name = "Chrome text — indicator",
			selector = `.{ON_INDICATOR_TAG} > .{liftTag}`,
			props = { TextColor3 = "$OnAccent" },
		})
		emit("chrome", {
			name = "Chrome text — cancel",
			selector = `.facet-role-cancel > .{liftTag}`,
			props = { TextColor3 = "$OnCancelChrome" },
		})
		emit("chrome", {
			name = "Chrome text — secondary",
			selector = `.{liftTag}.facet-role-secondary`,
			props = { TextColor3 = "$OnFieldChromeSecondary" },
		})
		-- The two role tags the RENDERER puts on the PARENT (classifyTags:
		-- `strong` for heading-and-above text, `roleSecondary` for the secondary
		-- role). Their unlifted counterparts — "Strong text"/"Secondary text" —
		-- match the parent node, whose own text is hidden under the decoration, so
		-- without these the lifted label ignored the role entirely and every
		-- skinned heading painted plain $Content.
		emit("chrome", {
			name = "Chrome text — strong",
			selector = `.facet-role-strong > .{liftTag}`,
			props = { TextColor3 = "$OnControlChromeStrong" },
		})
		emit("chrome", {
			name = "Chrome text — parent secondary",
			selector = `.facet-role-secondary > .{liftTag}`,
			props = { TextColor3 = "$OnControlChromeSecondary" },
		})
		emit("chrome", {
			name = "Chrome text — disabled button",
			selector = `TextButton:NonInteractable > .{liftTag}`,
			props = { TextTransparency = num(baseExtra.disabledContentOpacity) },
		})
		emit("chrome", {
			name = "Chrome text — disabled field",
			selector = `TextBox:NonInteractable > .{liftTag}`,
			props = { TextTransparency = num(baseExtra.disabledContentOpacity) },
		})
	end
	if ninePlans.field ~= nil then
		-- a TextBox YIELDS its chrome while editing: the engine caret is drawn
		-- at the parent layer and must be visible, so the decoration flattens to
		-- the native fill (same shape as the asset-failure fallback) while the
		-- adapter's editing tag is present
		-- FULL yield, not a repaint. The decoration is a CHILD, and under `Sibling`
		-- z-behavior any opaque child draws over its parent's engine text and
		-- caret — so painting the native fill here (BackgroundTransparency 0) hid
		-- exactly what the yield exists to reveal. The decoration goes completely
		-- transparent instead and the TextBox's own sheet-owned fill
		-- ("Control fill" / "Field — outline") is what shows while editing.
		emit("chrome", {
			name = "Chrome — field editing",
			selector = `.{ninePlans.field.tag}.{chrome_slots.TAGS.editing}`,
			props = {
				ImageTransparency = num(1),
				BackgroundTransparency = num(1),
			},
		})
	end
	-- ...AND THE NODE UNDERNEATH HAS TO PAINT AGAIN (director round 10, found
	-- live 2026-07-26 on a phone: "when I tap the filter field there's no
	-- background").
	--
	-- The yield above and `emitSlotSuppression` were each right and together
	-- wrong. Suppression turns the native plate OFF whenever art covers a node,
	-- because the art is meant to BE the surface. The yield turns the art off
	-- while the engine draws its caret at the parent layer. Both fire at once on
	-- a focused skinned field, and the comment above — "the TextBox's own
	-- sheet-owned fill is what shows while editing" — described a fill that
	-- `.facet-skinned-field` had already switched off. Nothing painted: bare text
	-- on the page, no field at all, self-healing on blur, which is exactly what
	-- the device capture shows.
	--
	-- Two rules, keyed on BOTH tags, so they can only ever match a skinned field
	-- that is currently yielding — and emitted only when the package actually
	-- skins `field`, because a flat package must emit NO chrome rules at all.
	-- Emitted last, and the cascade is Priority-then-insertion-order with no
	-- specificity (native-stylesheets), so being last is what makes them win over
	-- the suppression they are undoing.
	if ninePlans.field ~= nil or stacks.field ~= nil then
		emit("chrome", {
			name = "Chrome — field editing, own fill",
			selector = `.{chrome_slots.TAGS.stackYield}.{chrome_slots.skinnedTagFor("field")}`,
			props = { BackgroundColor3 = "$Control", BackgroundTransparency = num(0) },
		})
		emit("chrome", {
			name = "Chrome — field editing, own corner",
			selector = `.{chrome_slots.TAGS.stackYield}.{chrome_slots.skinnedTagFor("field")}::UICorner`,
			props = { CornerRadius = udim(0, metrics.radii.control) },
		})
		fromMetric("radii.control", "Chrome — field editing, own corner", "CornerRadius", "udimOffset")
	end
	-- author-supplied rules ride the chrome group, after everything this
	-- compiler emits, so an author can override a generated decision
	for _, rule in o.rules or {} do
		emit("chrome", {
			name = rule.name,
			selector = rule.selector,
			props = rule.props,
			transitions = rule.transitions,
		})
	end

	-- hover (compound-gated on the pointer-live tag: a touch paradigm must
	-- never match, and :Hover alone carries no paradigm gate)
	emit("hover", {
		name = "Control — hover",
		selector = `TextButton.{T.interactive}.{T.pointerLive}:Hover`,
		props = { BackgroundColor3 = "$ControlHover" },
		transitions = { BackgroundColor3 = "fast" },
	})
	emit("hover", {
		name = "Selected — hover",
		selector = `TextButton.{T.selected}.{T.interactive}.{T.pointerLive}:Hover`,
		props = { BackgroundColor3 = "$ControlSelectedHover" },
		transitions = { BackgroundColor3 = "fast" },
	})
	emit("hover", {
		name = "Primary — hover",
		selector = `TextButton.{S}accent.{T.pointerLive}:Hover`,
		props = { BackgroundColor3 = "$AccentHover" },
		transitions = { BackgroundColor3 = "fast" },
	})
	emit("hover", {
		name = "Destructive — hover",
		selector = `TextButton.facet-role-destructive.{T.pointerLive}:Hover`,
		props = { BackgroundColor3 = "$DangerHover" },
		transitions = { BackgroundColor3 = "fast" },
	})
	emit("press", {
		name = "Control — pressed",
		selector = `TextButton.{T.interactive}:Press`,
		props = { BackgroundColor3 = "$ControlPressed" },
	})
	emit("press", {
		name = "Primary — pressed",
		selector = `TextButton.{S}accent:Press`,
		props = { BackgroundColor3 = "$AccentPressed" },
	})
	emit("press", {
		name = "Destructive — pressed",
		selector = "TextButton.facet-role-destructive:Press",
		props = { BackgroundColor3 = "$DangerPressed" },
	})
	-- ...and the emphasis words', from the SAME emitter the base seed uses and at
	-- the same position relative to the generic control ramp (see
	-- emitVocabularyStates for why the two halves cannot share one call site)
	emitVocabularyStates(function(rule: Rule)
		emit("hover", rule)
	end, function(rule: Rule)
		emit("press", rule)
	end, T.pointerLive)
	for _, rule in markHover do
		emit("hover", rule)
	end
	-- Chrome interaction states. The decoration child is Active=false and can
	-- never report a GuiState of its own, so the state is read from its PARENT
	-- and reaches the child through the child combinator. One base image, four
	-- tints — never four assets.
	for _, slot in chrome_slots.SLOTS do
		-- one decoration, or every layer of a stack: the whole ladder responds as
		-- one control, which is what a player sees. rs-m2 proved a compound tag
		-- can single one layer out when a package wants that instead.
		local selectedTag = SLOT_SELECTED_TAG[slot] or T.selected
		local tags: { { name: string, tag: string } } = {}
		if ninePlans[slot] ~= nil then
			table.insert(tags, { name = `Chrome — {slot}`, tag = chrome_slots.tagFor(slot) })
		end
		if stacks[slot] ~= nil then
			for _, layer in stacks[slot].layers do
				table.insert(tags, { name = `Chrome — {slot} L{layer.index} {layer.kind}`, tag = layer.tag })
			end
		end
		for _, entry in tags do
			emit("hover", {
				name = `{entry.name} hover`,
				selector = `.{T.interactive}.{T.pointerLive}:Hover > .{entry.tag}`,
				props = { ImageColor3 = "$ChromeTintHover" },
				transitions = { ImageColor3 = "fast" },
			})
			-- after the plain hover it must beat (the selected tint is a chrome rule,
			-- which every hover rule outranks by group)
			emit("hover", {
				name = `{entry.name} selected hover`,
				selector = `.{selectedTag}.{T.interactive}.{T.pointerLive}:Hover > .{entry.tag}`,
				props = { ImageColor3 = "$ChromeTintSelectedHover" },
				transitions = { ImageColor3 = "fast" },
			})
			emit("press", {
				name = `{entry.name} pressed`,
				selector = `.{T.interactive}:Press > .{entry.tag}`,
				props = { ImageColor3 = "$ChromeTintPressed" },
			})
			emit("press", {
				name = `{entry.name} selected pressed`,
				selector = `.{selectedTag}.{T.interactive}:Press > .{entry.tag}`,
				props = { ImageColor3 = "$ChromeTintSelectedPressed" },
			})
			emit("disabled", {
				name = `{entry.name} disabled`,
				selector = `:NonInteractable > .{entry.tag}`,
				props = { ImageTransparency = num(baseExtra.disabledContentOpacity) },
			})
			-- RS-DIR6-F1 (director round 6, live-found): A BROKEN ASSET STAYS
			-- HIDDEN IN EVERY STATE.
			--
			-- `Chrome — <slot> fallback hide` hides the art of a fallen-back
			-- slot (`ImageTransparency = 1`) while `Chrome — <slot> fallback`
			-- repaints the declared native fill underneath — one rule until
			-- the rich-skinning v2 decision split the hide onto its own tag. Both ride the CHROME
			-- group, and the disabled rule
			-- immediately above rides the DISABLED group — and the cascade is
			-- Priority first, then insertion order, with NO selector specificity
			-- (priority is pinned by this generator, so group order IS
			-- the answer). So on a node that was BOTH disabled and in fallback the
			-- 0.4 dim won on the same property and re-revealed exactly the broken
			-- art the fallback existed to hide, at 60% opacity, over the native
			-- fill and rounded phantom corner that had replaced it.
			--
			-- Fixed by PRIORITY, not by scoping the disabled rule off fallback
			-- nodes: a StyleSheet selector has no negation, so "everything except
			-- a fallback node" is not expressible — and re-asserting the hide
			-- above the state rules is the same shape the fallback rule already
			-- uses to beat the resting art. It carries the HIDE and nothing else,
			-- so it moved onto the mute tag with it (rich-skinning v2): art whose OWN asset
			-- failed is not hidden, and a disabled node must not re-reveal art that a
			-- healthy-sibling mute is hiding;
			-- the fill and the corner are the chrome-group rule's and nothing
			-- contests those. Emitted per entry, so one slot's protection can
			-- never be undercut by a later slot's disabled rule (different tag,
			-- different instance).
			emit("disabled", {
				name = `{entry.name} fallback over states`,
				selector = `.{entry.tag}.{chrome_slots.TAGS.mute}`,
				props = { ImageTransparency = num(1) },
			})
		end
	end
	-- ROLE-AWARE chrome states (the same finding V14 that produced the flat
	-- role hover/press rules, one level down). The generic `Chrome — control
	-- hover/pressed` rules key on the interactive tag, NOT on the role, so
	-- without these a hovered destructive slab repainted itself neutral grey and
	-- the role visually vanished at the moment of the click. Emitted AFTER the
	-- loop above so insertion order puts them on top of it.
	-- Every role that tints the art keeps its tint through the states (readability
	-- round 2026-09-23: a hovered emphasis button went grey under its white label),
	-- in the resting rules' order.
	if ninePlans.control ~= nil then
		local controlTag = ninePlans.control.tag
		for _, entry in
			{
				{ "emphasis", `.{T.appearancePrefix}emphasis`, "ChromeTintAccent" },
				{ "soft", `.{T.appearancePrefix}soft`, "ChromeTintSelected" },
				{ "destructive", ".facet-role-destructive", "ChromeTintDanger" },
				{ "cancel", ".facet-role-cancel", "ChromeTintCancel" },
				{ "accent", `.{S}accent`, "ChromeTintAccent" },
			}
		do
			emit("hover", {
				name = `Chrome role — {entry[1]} hover`,
				selector = `{entry[2]}.{T.pointerLive}:Hover > .{controlTag}`,
				props = { ImageColor3 = `${entry[3]}Hover` },
				transitions = { ImageColor3 = "fast" },
			})
			emit("press", {
				name = `Chrome role — {entry[1]} pressed`,
				selector = `{entry[2]}:Press > .{controlTag}`,
				props = { ImageColor3 = `${entry[3]}Pressed` },
			})
		end
	end
	-- ----- SEMANTIC ICON PAINT -------------------------------
	--
	-- The authority split, stated once: the ADAPTER picks WHICH picture (a content
	-- id per node is not something a rule can decide) and HOW BIG (from the
	-- snapshot's `iconSizes`, so a metric package resizes icons); the SHEET owns
	-- the two paint properties, so an icon re-tints on a theme change inside one
	-- package with no Luau at all, and a pixel package's icons are nearest-
	-- neighbour by the same counted rule every other image is.
	--
	-- One rule per icon name that RESOLVES TO ART, emitted only when it has
	-- something to say.
	--
	-- IT ASKS `resolveIcon`, IT DOES NOT READ THE AUTHORED MAP (found live in
	-- Studio, 2026-07-27). This loop used to iterate `package.icons`, which was
	-- correct while a package's own map was the only place art could come from.
	-- The compact-label stage added a rung below it — the framework's own icon set
	-- — so a package that declares NO icons now still draws pictures, and this
	-- emitter skipped every one of them: measured in the running showcase, Studio
	-- Neutral produced 70 rules and ZERO icon rules while `resolveIcon` happily
	-- returned `source = "asset"` with `tintRole = "content"` for the same names.
	-- `ImageColor3` is sheet-owned in native mode and the adapter may not write
	-- it, so those icons painted pure WHITE — invisible on the five light theme
	-- variants, and only a real engine could show it.
	--
	-- So the vocabulary is the union of what the package declared (which may
	-- include namespaced `ns:name` art) and what the framework itself knows, and
	-- the ANSWER for each comes from the one resolution ruling every other
	-- consumer asks. A package that declines the framework set gets a glyph back
	-- and is skipped below, exactly as an undeclared name always was.
	do
		local iconNames: { string } = {}
		local seenName: { [string]: boolean } = {}
		local function addName(name: string)
			if not seenName[name] then
				seenName[name] = true
				table.insert(iconNames, name)
			end
		end
		if type(package.icons) == "table" then
			for name in package.icons do
				addName(tostring(name))
			end
		end
		for name in themePackage.ICON_FALLBACK_GLYPHS :: any do
			addName(tostring(name))
		end
		table.sort(iconNames)
		for _, name in iconNames do
			local resolved = themePackage.resolveIcon(package, name)
			if type(resolved) ~= "table" or resolved.source ~= "asset" then
				continue -- a glyph answer paints no picture, so it needs no rule
			end
			local props: { [string]: RuleProp } = {}
			if type(resolved.tintRole) == "string" then
				local token = TINT_ROLE_TOKEN[resolved.tintRole]
				assert(
					token ~= nil,
					`sheet_model.buildPackage: icon '{name}' names tintRole '{resolved.tintRole}', which is not `
						.. "a palette role — a tint that resolves to nothing paints the art unchanged and is "
						.. "invisible until a device shows it"
				)
				props.ImageColor3 = token
			end
			if props.ImageColor3 == nil and pixelUnit == nil then
				continue -- nothing to own: no tint role and no pixel stamp
			end
			emit("chrome", {
				name = `Icon — {name}`,
				selector = "." .. chrome_slots.iconTagFor(name),
				props = imageProps(props),
			})
		end
	end
	-- an icon picture on art wears the label's colour for that art: over another
	-- node's plate, or on its own skinned node — a stepper's +/- art too, whose
	-- label is the control's (and its pressed plate's own, see the text rule)
	if ninePlans.stepperPlate ~= nil or stacks.stepperPlate ~= nil then
		local skinned = `.{chrome_slots.skinnedTagFor("stepperPlate")}`
		emit("chrome", {
			name = "On plate — stepper icon",
			selector = `{skinned} > .{chrome_slots.ICON_PICTURE_TAG}`,
			props = { ImageColor3 = "$OnControlChrome" },
		})
		emit("chrome", {
			name = "On plate — stepper icon pressed",
			selector = `{skinned}:Press > .{chrome_slots.ICON_PICTURE_TAG}`,
			props = { ImageColor3 = "$OnStepperChromePressed" },
		})
	end
	for _, entry in onArtRoles do
		for _, prefix in { chrome_slots.TAGS.onArtPrefix, chrome_slots.TAGS.skinnedPrefix } do
			emit("chrome", {
				name = `On plate — {entry[1]} icon ({prefix})`,
				selector = `.{prefix}{entry[1]} > .{chrome_slots.ICON_PICTURE_TAG}`,
				props = { ImageColor3 = entry[2] },
			})
		end
	end

	emit("disabled", {
		name = "Disabled button",
		selector = "TextButton:NonInteractable",
		props = { TextTransparency = num(baseExtra.disabledContentOpacity) },
	})
	emit("disabled", {
		name = "Disabled field",
		selector = "TextBox:NonInteractable",
		props = { TextTransparency = num(baseExtra.disabledContentOpacity) },
	})
	if baseExtra.dimDisabledPlates == true then
		emitDisabledPlates(function(rule: Rule)
			emit("disabled", rule)
		end, authoredSelection(package.style.themes))
	end
	-- ...and the SUBTREE a disabled container turned off — see the legacy builder's
	-- note beside the same two rules. Emitted by every package, so a swap can never
	-- leave a disabled panel's labels reading at full contrast.
	emit("disabled", {
		name = "Disabled subtree text",
		selector = `TextLabel.{chrome_slots.TAGS.stateDisabled}`,
		props = { TextTransparency = num(baseExtra.disabledContentOpacity) },
	})
	-- SEMANTIC ICON ART, emitted by EVERY package — including a
	-- package that declares no icons at all, because the tag only ever lands on a
	-- node whose icon actually resolved to art. Emitting it unconditionally is
	-- what keeps the suppression working across a swap: a package with icons and
	-- one without must not disagree about whether the rule exists.
	emit("disabled", {
		name = "Semantic icon replaces the glyph",
		selector = `.{chrome_slots.TAGS.iconArt}`,
		props = { TextTransparency = num(1) },
	})

	-- THE HELD SOURCE EMPTIES (director round five) — emitted by every package
	-- for the same swap-consistency reason as the icon rule above
	emit("disabled", {
		name = "Held drag source empties its label",
		selector = `.{chrome_slots.TAGS.dragHeld}`,
		props = { TextTransparency = num(1) },
	})

	-- ----- flatten, gate, and pin the cascade ------------------------------
	local rules: { Rule } = {}
	for _, group in sheet_model.RULE_GROUPS do
		for _, rule in groups[group] do
			sheet_model.checkSelector(rule.selector, rule.name)
			local pseudo = string.match(rule.selector, "::([%w_]+)$")
			if pseudo ~= nil then
				local allowed = (sheet_model.PHANTOM_PROPS :: any)[pseudo]
				for prop in rule.props do
					assert(
						allowed[prop] == true,
						`sheet_model.buildPackage: rule '{rule.name}' writes '{prop}', which ::{pseudo} does not have`
					)
				end
			else
				-- The chrome scope is what unlocks the six image properties, and it
				-- is earned by the SELECTOR, never by the group. Author-supplied
				-- rules ride the chrome group (that is where they must land in the
				-- cascade), so keying on the group handed every author rule the
				-- image-chrome allowance — a rule selecting `.facet-surface-raised`
				-- could set `Image` and compile clean, on a node that has no
				-- decoration to carry it. Every rule this compiler emits into the
				-- chrome group names the slot prefix in its selector, so the
				-- narrower test costs the generated rules nothing.
				local isChrome = string.find(rule.selector, chrome_slots.TAGS.slotPrefix, 1, true) ~= nil
				for prop, value in rule.props do
					local ok, reason = themePackage.lintProperty(prop, if isChrome then "chrome" else "rule")
					assert(ok, `sheet_model.buildPackage: rule '{rule.name}' — {tostring(reason)}`)
					sheet_model.checkContentValue(rule.name, prop, value)
				end
			end
			table.insert(rules, rule)
			rule.priority = #rules * 10
		end
	end

	projectContentRules(rules)
	-- a stepper's pressed plate may be different art, and its label is picked there;
	-- after the generated lifts, which out-rank every hand chrome rule
	if ninePlans.stepperPlate ~= nil then
		local selector = `.{chrome_slots.skinnedTagFor("stepperPlate")}:Press > .{chrome_slots.TAGS.text}`
		sheet_model.checkSelector(selector, "Chrome text — stepper pressed")
		table.insert(rules, {
			name = "Chrome text — stepper pressed",
			selector = selector,
			props = { TextColor3 = "$OnStepperChromePressed" },
			priority = (#rules + 1) * 10,
		})
	end
	-- Explicit partner lettering wins over both name tint and generated-owner color.
	emitStatusIconTint(function(rule: Rule)
		rule.priority = (#rules + 1) * 10
		table.insert(rules, rule)
	end)

	-- ----- mirrors: what the Style Editor SHOWS about this package ---------
	local mirrors: { { name: string, value: number } } = {}
	for _, step in themePackage.REQUIRED_SPACE_STEPS do
		table.insert(mirrors, { name = "Space" .. pascal(step), value = metrics.space[step] })
	end
	for _, role in themePackage.REQUIRED_TYPE_ROLES do
		table.insert(mirrors, { name = "Type" .. pascal(role), value = metrics.typography[role].size })
	end
	for _, radius in themePackage.REQUIRED_RADII do
		table.insert(mirrors, { name = "Radius" .. pascal(radius), value = metrics.radii[radius] })
	end
	table.insert(mirrors, { name = "TargetMinimum", value = metrics.targetSizes.minimum })
	table.insert(mirrors, { name = "MotionFast", value = metrics.motion.fast })
	table.insert(mirrors, { name = "MotionNormal", value = metrics.motion.normal })

	-- ----- the content stamp ----------------------------------------------
	-- Includes the package's own stamp, so a package edit ALWAYS migrates the
	-- sheet even if two different packages happened to compile to the same
	-- rules; and the chrome kinds, via chrome_props.describe.
	local parts: { string } = { `package={package.identity.id}@{package.identity.version}#{package.stamp}` }
	-- the ten-foot sheet is a DIFFERENT sheet and says so, so a re-ensure at a
	-- new display class regenerates its rules instead of preserving corners cut
	-- for another distance
	if themeSnapshot.metricScale(o.displaySize) ~= 1 then
		table.insert(parts, `paintScale={themeSnapshot.metricScale(o.displaySize)}`)
	end
	for _, theme in themes do
		local names = {}
		for k in theme.tokens do
			table.insert(names, k)
		end
		table.sort(names)
		for _, k in names do
			local v = theme.tokens[k]
			local described = chrome_props.describe(v)
			if described ~= nil then
				table.insert(parts, `{theme.name}.{k}={described}`)
			elseif v.kind == "number" then
				table.insert(parts, string.format("%s.%s=%.4f", theme.name, k, v.value))
			else
				table.insert(parts, string.format("%s.%s=%.4f,%.4f,%.4f", theme.name, k, v.r, v.g, v.b))
			end
		end
	end
	for _, rule in rules do
		table.insert(parts, `{rule.priority}:{rule.selector}`)
		local pnames = {}
		for k in rule.props do
			table.insert(pnames, k)
		end
		table.sort(pnames)
		for _, k in pnames do
			local v = rule.props[k]
			local described = if type(v) == "table" then chrome_props.describe(v) else nil
			table.insert(
				parts,
				k
					.. "="
					.. (
						if type(v) == "string"
							then v
							elseif described ~= nil then described
							else tostring(v.kind) .. tostring(v.value or v.offset or v.family or v.item or "")
					)
			)
		end
	end
	for _, m in mirrors do
		table.insert(parts, `{m.name}={m.value}`)
	end

	return {
		schema = "facet-native-sheet/1",
		stamp = stampOf(parts),
		defaultTheme = defaultTheme,
		themes = themes,
		rules = rules,
		mirrors = mirrors,
		motion = { fast = metrics.motion.fast, normal = metrics.motion.normal },
		-- live-edit repaint map (see fromMetric above): which rule props a
		-- Radii_*/Strokes_* sheet edit must refresh, consumed by the controller
		metricRuleProps = metricRuleProps,
		-- what this skin costs, counted at compile (see the census locals)
		census = census,
	}
end

return sheet_model
