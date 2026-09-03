--!strict
-- ScreenChrome — the DECORATION / CHROME subsystem of the client ScreenTarget,
-- extracted verbatim 2026-07-25 (rich-skinning-v2 close-out) because
-- `screen_target.luau` had reached 199_613 bytes and Studio's `Source`
-- assignment (tools/studio/inject.luau) refuses anything at or above 200_000.
-- The cut follows the seam that was already there: everything that
-- MATERIALIZES a theme package's art — decoration slots, semantic icons, the
-- chrome text lift, slot shadows, layer stacks, the bar assembly, toggle art
-- and the rung-2 per-view override — lives here; everything else stays in
-- `screen_target`.
--
-- IT IS A PURE MOVE. No behaviour, no public API and no rule authority changed
-- with it; the function bodies below are byte-for-byte what `screen_target.new`
-- used to close over. What was an implicit closure over the target's locals is
-- now an explicit `Context`, and the two seams that could not be an upvalue —
-- the committed theme snapshot (reassigned by `setThemePackage`) and
-- `adapter.setFocusVisual` (defined further down the target) — arrive as
-- callbacks.
--
-- DEPENDENCY DIRECTION:
-- `screen_target` requires `screen_chrome`, NEVER the reverse. Everything both
-- sides need is either a lower dep-free module (`chrome_slots`, `styling`,
-- `themes/package`) or a Context field.

local CollectionService = game:GetService("CollectionService")

local chrome_slots = require("../tokens/chrome_slots")
-- the PURE package library: `resolveIcon` is the one icon-resolution ruling and
-- this file is its application site
local themePackage = require("../themes/package")
local styling = require("../tokens/styling")
-- the recycle-safe reconnect helpers (task CONN, review-fix234 Finding 1): see
-- handle_conn.luau for why a shared helper replaces a hand-repeated
-- disconnect-if-present guard at every `handle.*Conn` reconnect site
local handle_conn = require("./handle_conn")
local reconnect = handle_conn.reconnect
local reconnectOnChange = handle_conn.reconnectOnChange

local screen_chrome = {}

-- local copy of the target's 3-line colour coercion: a leaf helper is cheaper
-- to repeat than to widen the Context with
local function toColor3(c: any): Color3
	return Color3.new(c.r, c.g, c.b)
end

-- Everything this subsystem needs from the target that owns it. Values that
-- never change for the life of a target are passed by value; the two that do
-- are functions.
export type Context = {
	style: any,
	nativeMode: boolean,
	hasUIShadow: boolean,
	-- the pure chrome_slots state (recipes, census, asset-failure ledger)
	chromeState: any,
	-- the target's two live registries, shared BY REFERENCE: a decoration is
	-- addressable by path and a bar fill finds its track through handlesByPath
	instancesByPath: { [string]: Instance },
	handlesByPath: { [string]: any },
	-- the live focus set, read by the syncChrome wrapper that re-places a focus
	-- visual when a node's art appears or disappears
	focusedHandles: { [any]: string? },
	-- the target's resolved palette (`COLOR`), for the one fallback fill that has
	-- no entry in chromeFillOf
	palette: { [string]: Color3 },
	-- the target's CENTRAL native-authority gate and its tag synchronizer
	assertBespokePaint: (engineProp: string) -> (),
	syncTags: (handle: any) -> (),
	-- the COMMITTED theme snapshot: reassigned inside setThemePackage's swap
	-- transaction, so it is read through a function rather than captured
	snapshot: () -> any,
	-- adapter.setFocusVisual, which is defined below this subsystem in the target
	setFocusVisual: (handle: any, on: boolean, profile: string?) -> (),
}

-- ===== DECORATION SLOTS ================================
-- One non-interactive ImageLabel per slotted node, and only where the
-- installed package's recipe for that slot is `nineSlice`. Everything
-- decidable without an engine — which slot a node belongs to, what the
-- recipe asks for, the census, the asset-failure ledger — lives in the pure
-- src/tokens/chrome_slots; this is the materializer and nothing else.
--
-- IN NATIVE MODE NO IMAGE PROPERTY IS WRITTEN HERE. The package's rules own
-- all six (feasibility m2), and an explicit write would permanently defeat
-- them (spike m10) — the same discipline every other surface follows. In
-- fallback mode the identical values are explicit-written from the SAME
-- plan, so the two paths cannot drift.
--
-- RENDER ORDER. TP-M8 is the theme feasibility probe that measured this on
-- 2026-07-25: under `Sibling` a descendant
-- renders above its ancestor at ANY ZIndex — an opaque decoration child
-- covers a TextButton/TextBox's OWN engine-drawn text and caret. Slot
-- parentage stays load-bearing (the per-state tint rules read GuiState from
-- the PARENT via the child combinator), so the resolution is the CHROME TEXT
-- LIFT: a text-bearing node with an active decoration gets one managed
-- `FacetChromeText` TextLabel above the chrome that mirrors the parent's
-- text (the parent keeps `Text` for semantics/measure; its paint is hidden
-- under the chrome either way). Paint on the lifted label is sheet-owned in
-- native mode (`.facet-chrome-text` rules + parent-tag child combinators);
-- fallback mode mirrors the parent's explicit paint. A TextBox additionally
-- YIELDS its chrome while editing (`facet-chrome-editing` tag; the engine
-- caret is parent-drawn and non-negotiable), the lifted label hiding so the
-- real text shows exactly once. Flat themes create none of this.
--
-- MIRRORED: Text, TextSize, the two alignments, TextWrapped, TextTruncate,
-- RichText and LineHeight — everything that decides what the glyphs ARE.
-- NOT SUPPORTED UNDER CHROME: `TextScaled`. It sizes text from the box the
-- label happens to occupy, and the lifted label's box is the decoration's,
-- not the parent's content rect — so a scaled mirror would disagree with
-- both the parent and the solver. Facet sizes text through the solver
-- (textSize + typographyScale) and never sets TextScaled anywhere; a host
-- that sets it by hand gets an unmirrored label under a skinned node.
function screen_chrome.new(ctx: Context)
	local style = ctx.style
	local nativeMode = ctx.nativeMode
	local hasUIShadow = ctx.hasUIShadow
	local chromeState = ctx.chromeState
	local instancesByPath = ctx.instancesByPath
	local handlesByPath = ctx.handlesByPath
	local focusedHandles = ctx.focusedHandles
	local COLOR = ctx.palette
	local assertBespokePaint = ctx.assertBespokePaint
	local syncTags = ctx.syncTags

	-- How long a decoration image may stay unloaded before this target calls it
	-- a failure on its own. The authoritative answer comes from the app's
	-- resource provider through `setChromeAssetLoaded`; this is the floor for a
	-- target nobody wired one to, so a bad content ID still reaches the
	-- fallback rules instead of painting nothing forever.
	local CHROME_ASSET_GRACE_SECONDS = 5
	-- taken from `style` rather than the COLOR table below, which is declared
	-- further down; the values are identical (COLOR is toColor3 of these)
	local chromeFillOf: { [string]: Color3 } = {
		panel = toColor3(style.colors.surfaceStrong),
		control = toColor3(style.extra.control),
		field = toColor3(style.extra.control),
		selection = toColor3(style.extra.controlSelected),
		divider = toColor3(style.extra.hairline),
		scrollbar = toColor3(style.extra.control),
		-- the value-control family's OWN paint, mirroring sheet_model's
		-- SLOT_FILL_TOKEN so the two paths cannot disagree about a flat thumb
		sliderTrack = toColor3(style.extra.control),
		sliderThumb = toColor3(style.colors.surfaceStrong),
		badge = toColor3(style.colors.surfaceStrong),
		-- v2 value displays, mirroring sheet_model's SLOT_FILL_TOKEN
		-- so a flat bar looks the same on both paint paths
		barTrack = toColor3(style.extra.control),
		barFill = toColor3(style.colors.accent),
		barCap = toColor3(style.colors.accent),
		barCenter = toColor3(style.colors.accent),
		stepperPlate = toColor3(style.extra.control),
		toggleTrack = toColor3(style.extra.control),
		toggleKnob = toColor3(style.colors.surfaceStrong),
		spinner = toColor3(style.colors.accent),
	}
	-- slots whose flat shape is a CIRCLE (mirrors sheet_model's SLOT_ROUND)
	local SLOT_ROUND_FALLBACK: { [string]: boolean } =
		{ sliderThumb = true, badge = true, toggleKnob = true, spinner = true }

	-- A VALUE CONTROL'S OWN NATIVE PAINT, explicit-write half (fallback mode
	-- only). Native mode does exactly this through the package's `Slot — <slot>`
	-- rules; on a target with no StyleSheets the adapter writes the same fill,
	-- corner and hairline itself, or a thumb that no longer borrows
	-- `surface = "raised"` would simply be invisible there.
	--
	-- SOLID, in both paths, on purpose — that is the entire fix: the thumb used
	-- to take the PANEL treatment, and Glossy Mobile's panel gradient carries
	-- alpha, so the accent fill behind the thumb read straight through it.
	--
	-- Written out rather than calling `corner()`/`hairline()`: those are declared
	-- further down this closure and a later-declared local is not an upvalue here
	-- (the same shape the hoisted `hasUIShadow` probe exists for).
	local function applySlotNativePaint(instance: GuiObject, slot: string, handle: any)
		if nativeMode or not chrome_slots.hasOwnPaint(slot) then
			return -- the rules own it; an explicit write here would defeat them
		end
		if handle.slotPainted == slot then
			return -- idempotent: syncChrome runs on every classification change
		end
		handle.slotPainted = slot
		instance.BackgroundTransparency = 0
		instance.BackgroundColor3 = chromeFillOf[slot] or toColor3(style.colors.surfaceStrong)
		local uiCorner = instance:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
		-- RECORDED ON THE HANDLE (T8 R3, Important 3): this is the node's OWN
		-- UICorner, shared with a reactive `corners` prop, and `screen_paint`'s
		-- `applyCorners` restores this exact value when that prop crosses to nil
		-- instead of deleting a slot radius nothing would ever repaint (this
		-- function is idempotent through `handle.slotPainted`). Unreachable in
		-- native mode — the early return above is what keeps the record honest
		-- there, so the sheet's own `Slot — <slot>` rules stay the only owner.
		local slotRadius = if SLOT_ROUND_FALLBACK[slot] then UDim.new(0.5, 0) else UDim.new(0, style.radii.control)
		uiCorner.CornerRadius = slotRadius
		uiCorner.Parent = instance
		handle.chromeCornerRadius = slotRadius
		if instance:FindFirstChild("Hairline") == nil then
			local stroke = Instance.new("UIStroke")
			stroke.Name = "Hairline"
			stroke.Color = toColor3(style.extra.hairline)
			stroke.Transparency = style.extra.hairlineOpacity
			stroke.Thickness = style.strokes.hairline
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = instance
		end
	end

	local function chromeSlotOf(handle: any): string?
		local slot = chrome_slots.classify({
			class = handle.class,
			surface = handle.declaredSurface,
			hasSelection = handle.hasSelectionBinding == true,
			-- a composite control's own declaration (Slider's rail/thumb) beats
			-- every generic hint; it arrives on the blueprint's internal meta
			-- channel and never through the public prop bag
			hint = if type(handle.decorationHint) == "table" then handle.decorationHint.slot else nil,
		})
		-- ...and a slot the INSTALLED PACKAGE has nothing to say about falls back
		-- to the one it used to borrow: a stepper's +/- is a Button,
		-- so a package published before `stepperPlate` existed must keep skinning
		-- it through its `control` recipe rather than losing its art to a v2 slot.
		return chrome_slots.resolveSlot(chromeState.package(), slot)
	end

	-- the rung-2 per-view override carried on the same hint (nil when absent)
	local function chromeOverrideOf(handle: any): any
		local hint = handle.decorationHint
		if type(hint) ~= "table" then
			return nil
		end
		local hasImage = type(hint.image) == "string" and hint.image ~= ""
		-- a per-state map with no bare string is still an override (its `default`
		-- is the resting picture)
		local hasVariants = type(hint.imageVariants) == "table"
		if not hasImage and not hasVariants then
			return nil
		end
		return { image = if hasImage then hint.image else nil, imageVariants = hint.imageVariants }
	end

	-- explicit-write half of the fallback flip (fallback mode only). `muted` is a
	-- SECOND axis, not a synonym for `on` (rich-skinning v2): the art of the asset that
	-- was condemned keeps drawing over the declared native fill, so its `IsLoaded`
	-- can still report a recovery. It draws nothing while the asset really is
	-- broken, which is why that costs no pixels.
	local function applyChromeFallbackWrites(deco: ImageLabel, slot: string, on: boolean, muted: boolean, plan: any)
		deco.ImageTransparency = if muted then 1 else plan.transparency
		if on then
			deco.BackgroundColor3 = chromeFillOf[slot] or COLOR.control
			deco.BackgroundTransparency = 0
		else
			deco.BackgroundTransparency = 1
		end
	end

	-- applyFullBleed(host, deco): make a decoration cover the host's OWN box.
	--
	-- A scale size resolves against the parent's CONTENT box, so a `UIPadding` on
	-- the host silently shrinks any child sized `fromScale(1, 1)` — including the
	-- plate that is supposed to BE the node's surface. The compensation is the
	-- padding pushed back out: start at minus the leading inset and grow by both.
	--
	-- Offsets only. A scale-valued UIPadding would need the host's resolved size
	-- to invert and nothing in this library authors one — `commit_walks.padding` and the
	-- Button create branch both write pure offsets — so a scale component is left
	-- alone rather than half-handled.
	local function applyFullBleed(host: GuiObject, deco: GuiObject)
		local pad = host:FindFirstChildOfClass("UIPadding")
		local l = if pad ~= nil then pad.PaddingLeft.Offset else 0
		local r = if pad ~= nil then pad.PaddingRight.Offset else 0
		local t = if pad ~= nil then pad.PaddingTop.Offset else 0
		local b = if pad ~= nil then pad.PaddingBottom.Offset else 0
		-- the arithmetic lives in `chrome_slots` so it can be tested headlessly:
		-- this file cannot load under Lune, and an off-by-the-padding rule needs a
		-- spec with real numbers rather than a source-text assertion
		local box = chrome_slots.fullBleedBox(l, r, t, b)
		local position = UDim2.new(0, box.x, 0, box.y)
		local size = UDim2.new(1, box.w, 1, box.h)
		if deco.Position ~= position then
			deco.Position = position
		end
		if deco.Size ~= size then
			deco.Size = size
		end
	end

	--[[ refitFullBleed(handle): recompute every full-bleed compensation this node
		owns, because the number they all cancel just CHANGED.

		`applyFullBleed` above cancels the host's `UIPadding` — it reads that padding
		once, at the moment it runs. `screen_target`'s `create` gives a Button (and a
		TextBox) a default `UIPadding` of `style.space.s + 4` and then calls
		`syncChrome`, so a decoration is born compensated for the CLASS DEFAULT; the
		authored `padding` prop arrives afterwards, through `applyProp`, rewrites that
		`UIPadding`, and used to re-run nothing. The compensation was then stale by the
		difference — and a stale full-bleed does not shrink the decoration, it MOVES
		and GROWS it, because the decoration is laid out inside the host's padded
		content box and pushed back out by the older, larger number.

		MEASURED LIVE (Studio, Compact Pointer, `row-actions` Table surface, viewport
		413x735): every Button on that screen keeps the default padding 12 and has
		`Position.X = -12` and ZERO overhang; the swipe tray's `Mark Read` plate — the
		one button carrying an authored `padding` of 8 — kept `-12` and painted
		[6.0 .. 97.0] for a plate at [10.0 .. 93.0]: 4px outside its own box on every
		side. Its left edge sits exactly on the Table body's clip edge (10.0), so the
		left 4px (border and both corners) was cut away and the right 4px landed in the
		6px `rowGutter` and survived — the director's `cutoff.png`, exactly.

		SO THE PADDING WRITE OWNS THE REFIT. It is the one authority for a host's
		`UIPadding`, which makes it the one place that can know a compensation derived
		from that padding has gone stale — the same shape as `refitIconArt`, which
		exists because a rect can arrive after the icon it sizes. Idempotent (both
		writes are guarded by an inequality), and a no-op on a node with no chrome. ]]
	local function refitFullBleed(handle: any)
		local instance = handle.instance
		if instance == nil then
			return
		end
		if handle.chrome ~= nil then
			applyFullBleed(instance, handle.chrome)
		end
		-- ...and the LAYER ladder, which is full-bled once at build and never by
		-- the per-sync path the single decoration takes, so a layered package was
		-- the same defect with no second chance at all
		for _, entry in handle.chromeStack or {} do
			if entry.fullBleed == true and entry.instance ~= nil then
				applyFullBleed(instance, entry.instance)
			end
		end
	end

	-- THE IMAGE IS THE BUTTON, explicit-write half (fallback mode only). Native
	-- mode does exactly this through the package's `Skinned — <slot>` rules; on a
	-- target with no StyleSheets the adapter writes the same three suppressions
	-- itself, so a parchment button reads identically on both paths instead of
	-- sitting inside a leftover Studio-Neutral slab.
	local function applySkinnedSuppression(instance: GuiObject, on: boolean, handle: any?)
		if nativeMode then
			return -- the rules own it; an explicit write here would defeat them
		end
		if on then
			instance.BackgroundTransparency = 1
			for _, child in instance:GetChildren() do
				if child:IsA("UICorner") then
					(child :: UICorner).CornerRadius = UDim.new(0, 0)
				elseif child:IsA("UIStroke") and child.Name == "Hairline" then
					(child :: UIStroke).Thickness = 0
					(child :: UIStroke).Transparency = 1
				end
			end
			-- AN ERASER CLEARS THE RECORD (T8 R4), the same rule `applySurface`'s
			-- `plain`/`scrim` destroy loops follow. A suppressed node wears NO
			-- chrome radius — the loop above just zeroed whatever `corner()` or
			-- `applySlotNativePaint` painted — so a later nil `corners` must tear
			-- that zeroed child down, not restore the radius the art replaced.
			-- The handle is optional only so this stays callable from a site that
			-- has none; every caller today passes one.
			if handle ~= nil then
				handle.chromeCornerRadius = nil
			end
		end
	end

	-- ===== SEMANTIC ICONS ==================================
	--
	-- A control requests an icon by MEANING and draws the framework's ASCII
	-- fallback glyph as that node's own text. This function is the UPGRADE: when
	-- the installed package declares art for that name, one managed picture is
	-- parented over the node and the glyph underneath is turned off.
	--
	-- WHY THE CONTROL STILL DRAWS THE GLYPH. It is the only arrangement in which
	-- "no theme art" cannot render tofu: the character is in the tree from the
	-- moment the control is built, chosen from a table that is plain ASCII by
	-- construction, and no resolution has to succeed for it to be legible. The
	-- sci-fi caret was the opposite arrangement — a codepoint chosen by the
	-- control, present in some faces and absent in Michroma.
	--
	-- THREE AUTHORITIES, deliberately split:
	--   * `Image` / `Size` / `ResampleMode` are the ADAPTER's. They come from the
	--     resolution (which content id), the snapshot (which `iconSizes` role, so
	--     a metric package resizes icons) and the package's rendering mode; none
	--     of them is sheet-owned, and no rule could pick a content id per node.
	--   * `ImageColor3` is the SHEET's in native mode — one `.facet-icon-<name>`
	--     rule per tinted icon, emitted beside the package's other image rules —
	--     so a theme change inside one package re-tints icons with no Luau. The
	--     fallback path writes the same role from the target's own style, exactly
	--     as `chromeFillOf` does for slot fills.
	--   * `TextTransparency` on the HOST is the sheet's too (it is in
	--     authority.nativeSheetOwned), so the glyph suppression is a tag.
	local ICON_TINT_COLOR: { [string]: Color3 } = {
		surface = toColor3(style.colors.surface),
		surfaceStrong = toColor3(style.colors.surfaceStrong),
		content = toColor3(style.colors.content),
		contentStrong = toColor3(style.colors.contentStrong),
		contentSecondary = toColor3(style.extra.contentSecondary),
		accent = toColor3(style.colors.accent),
		control = toColor3(style.extra.control),
		controlSelected = toColor3(style.extra.controlSelected),
		danger = toColor3(style.colors.danger),
		hairline = toColor3(style.extra.hairline),
	}
	local iconArtCount = 0
	-- forward-declared: `destroyChromeText` is defined below and a later local is
	-- not an upvalue here (the shape this file keeps a hoisted `hasUIShadow` for)
	local destroyChromeText: (handle: any) -> ()

	local function destroyIconArt(handle: any)
		if handle.iconInstance ~= nil then
			instancesByPath[handle.path .. "/" .. chrome_slots.ICON_NAME] = nil
			handle.iconInstance:Destroy()
			handle.iconInstance = nil
			iconArtCount -= 1
		end
		handle.iconKey = nil
		if handle.iconArt == true then
			handle.iconArt = false
			if not nativeMode then
				-- fallback half of the glyph suppression: the tag rule does it in
				-- native mode, and the two must agree about the restored value
				assertBespokePaint("TextTransparency")
				pcall(function()
					(handle.instance :: any).TextTransparency = 0
				end)
			end
			syncTags(handle)
		end
	end

	local function syncIconArt(handle: any)
		local hint = handle.decorationHint
		local name = if type(hint) == "table" then hint.icon else nil
		if type(name) ~= "string" or name == "" then
			destroyIconArt(handle)
			return
		end
		local package = chromeState.package()
		local resolved = themePackage.resolveIcon(package, name)
		-- a glyph answer, or a name that means nothing, is the SAME instruction
		-- here: draw no picture and leave the control's own character showing
		if type(resolved) ~= "table" or resolved.source ~= "asset" then
			destroyIconArt(handle)
			return
		end
		local snap = ctx.snapshot()
		local role = (if type(hint) == "table" then hint.iconSize else nil) or "medium"
		local px = if type(snap) == "table" and type(snap.iconSizes) == "table" then snap.iconSizes[role] else nil
		if type(px) ~= "number" or px <= 0 then
			px = 20 -- the neutral `medium` rung; never a zero-size picture
		end
		local pixelUnit = if type(snap) == "table" then snap.pixelUnit else nil
		local tag = chrome_slots.iconTagFor(name)
		-- THE PICTURE NEVER PAINTS OUTSIDE ITS OWN NODE (director report
		-- 2026-07-28). `px` above is what the THEME wants; this is what the node
		-- can actually hold. The renderer reserves the rung wherever the axis is
		-- content-derived, so on a node free to grow these two agree and nothing
		-- moves — but an authored size wins over measure by design, and a node
		-- fixed smaller than the rung used to have the picture simply spill out of
		-- it. The arithmetic is `chrome_slots.iconBoxPx` so it can be asserted
		-- headlessly with real numbers.
		local rect = handle.windowRect
		local pad = handle.instance:FindFirstChildOfClass("UIPadding")
		local padX = if pad ~= nil then pad.PaddingLeft.Offset + pad.PaddingRight.Offset else 0
		local padY = if pad ~= nil then pad.PaddingTop.Offset + pad.PaddingBottom.Offset else 0
		local drawPx = chrome_slots.iconBoxPx(
			px,
			if type(rect) == "table" then rect.w else nil,
			if type(rect) == "table" then rect.h else nil,
			padX,
			padY
		)
		-- `drawPx` rides the cache key, not `px`: the rect can arrive AFTER the
		-- icon does (create, then the first solve), and a key that only knew the
		-- theme's number would treat the re-fit as a no-op and leave the first,
		-- unconstrained size on screen forever.
		local key = `{resolved.contentId}#{px}#{drawPx}#{tostring(resolved.tintRole)}#{tostring(pixelUnit)}`
		if handle.iconKey == key then
			return
		end
		local child = handle.iconInstance
		if child == nil then
			child = Instance.new("ImageLabel")
			child.Name = chrome_slots.ICON_NAME
			child.Active = false -- input-transparent (rs-m3): the node keeps its hit
			child.Selectable = false
			child.BorderSizePixel = 0
			child.BackgroundTransparency = 1
			child.AnchorPoint = Vector2.new(0.5, 0.5)
			child.Position = UDim2.fromScale(0.5, 0.5)
			-- above the whole decoration ladder AND above the chrome text lift, so
			-- a layered plate can never cover the picture it exists to carry
			child.ZIndex = chrome_slots.ICON_Z_INDEX
			-- TAG BEFORE PARENT (rs-m2, platform verifier F4): every other create
			-- path in this file already does it, and this one did not. A picture
			-- that joins the tree untagged is visible for the frame before the tag
			-- lands, painting whatever the untagged cascade says.
			CollectionService:AddTag(child, tag)
			child.Parent = handle.instance
			handle.iconInstance = child
			instancesByPath[handle.path .. "/" .. chrome_slots.ICON_NAME] = child
			iconArtCount += 1
		end
		local prefix = chrome_slots.ICON_TAG_PREFIX
		for _, existing in CollectionService:GetTags(child) do
			if string.sub(existing, 1, #prefix) == prefix and existing ~= tag then
				CollectionService:RemoveTag(child, existing)
			end
		end
		if not CollectionService:HasTag(child, tag) then
			CollectionService:AddTag(child, tag)
		end
		-- THE SANCTIONED `Image` EXCEPTION (authority.BESPOKE_INSTANCES). `Image`
		-- is sheet-owned for every node a rule can reach, but no rule can pick a
		-- content id PER NODE, and this picture is an adapter-owned instance with
		-- no rule that writes its Image (asserted: no emitted `Icon — <name>` rule
		-- carries Image). Declared, not accidental.
		child.Image = resolved.contentId
		child.Size = UDim2.fromOffset(drawPx, drawPx)
		if not nativeMode then
			-- fallback half. In native mode BOTH of these are the package's own
			-- `Icon — <name>` rule (rs-m2: an explicit write here would defeat it
			-- permanently), and the two halves are written from the same two
			-- facts so they cannot drift.
			child.ResampleMode = if pixelUnit ~= nil then Enum.ResamplerMode.Pixelated else Enum.ResamplerMode.Default
			local tint = if type(resolved.tintRole) == "string" then ICON_TINT_COLOR[resolved.tintRole] else nil
			child.ImageColor3 = tint or Color3.new(1, 1, 1)
		end
		handle.iconKey = key
		if handle.iconArt ~= true then
			handle.iconArt = true
			if not nativeMode then
				assertBespokePaint("TextTransparency")
				pcall(function()
					(handle.instance :: any).TextTransparency = 1
				end)
			end
			syncTags(handle)
		end
		-- the lifted label mirrors the node's text, so it has to go too, or the
		-- glyph reappears ABOVE the picture on every skinned node
		destroyChromeText(handle)
	end

	local syncChrome: (handle: any) -> ()
	local chromeTextLifts = 0

	-- the chrome text lift (see the header comment above): one managed label
	-- above the decoration, mirroring the parent's engine-drawn text. Mirrors
	-- via GetPropertyChangedSignal so no write site anywhere else needs to know
	-- the lift exists. In native mode ONLY layout/binding-authority props are
	-- mirrored (Text/TextSize/alignment) — the label's paint is sheet-owned and
	-- an explicit TextColor3 would permanently defeat its rules; fallback mode
	-- mirrors paint too, byte-equal with what the parent would have shown.
	function destroyChromeText(handle: any)
		if handle.chromeTextConns ~= nil then
			for _, conn in handle.chromeTextConns do
				conn:Disconnect()
			end
			handle.chromeTextConns = nil
		end
		if handle.chromeText ~= nil then
			instancesByPath[handle.path .. "/" .. chrome_slots.TEXT_LIFT_NAME] = nil
			handle.chromeText:Destroy()
			handle.chromeText = nil
			chromeTextLifts -= 1
		end
		handle.chromeTextPlan = nil
		handle.chromeTextPath = nil
	end

	-- the lifted label's BOX, inset by the recipe's own contentInsets (director
	-- fix round: values sat on the painted border because the lift was full-bleed
	-- while the SOLVER had already reserved the inset for the parent's content).
	-- The MATH is pure and lives in chrome_slots.liftGeometry, so it is asserted
	-- headlessly against the same `contentInsets` the snapshot composes; this is
	-- only the UDim2 materialization.
	--
	-- THE PLAQUE NAMEPLATE (the layer stack's `text` sub-slot; arch verifier F2).
	-- When the live stack declares a plaque that asks for text, the lift moves
	-- onto the PLAQUE rect instead of the node's content rect — one geometry
	-- substitution, so the mirror, the connections, the census and the teardown
	-- are all exactly the machinery that already existed.
	-- `handle` is what lets the recipe's inset be CHECKED rather than assumed
	-- (director report 2026-07-28, defect 3): a lift inset by more than the space
	-- it has solves to zero width and draws nothing, and this label is the only
	-- thing that redraws the node's text above the plate covering it. The space a
	-- scale-1 child resolves against is the node's rect minus its own UIPadding —
	-- the same content box `applyFullBleed` above has to compensate for.
	local function liftGeometry(plan: any, handle: any?): (UDim2, UDim2)
		local hostW, hostH = nil, nil
		local padL, padR, padT, padB = 0, 0, 0, 0
		local rect = if handle ~= nil then handle.windowRect else nil
		if type(rect) == "table" then
			local pad = handle.instance:FindFirstChildOfClass("UIPadding")
			if pad ~= nil then
				padL, padR = pad.PaddingLeft.Offset, pad.PaddingRight.Offset
				padT, padB = pad.PaddingTop.Offset, pad.PaddingBottom.Offset
			end
			-- THE HOST'S OWN BOX, not its padded content box. The lift is full-bleed
			-- FIRST and inset by the recipe SECOND; feeding the padded width in here
			-- made the fit check believe the label had 24px less room than it does.
			hostW, hostH = rect.w, rect.h
		end
		--[[ THE LABEL'S OWN LINE BOX, which is the floor the recipe's inset may not
			eat through (task THEME, 2026-08-27;
			`chrome_slots.liftGeometry`). It is read off the LIVE instance rather than
			plumbed here because the host IS the text node — `TextSize` is whatever the
			last paint wrote — and a host with no text property contributes no floor at
			all. The measure seam takes the identical number through
			`chrome_slots.spendInset`, which is what keeps the reservation and the
			drawn box agreeing about a control too small for its theme.

			THIS COMMENT USED TO SAY "the two can never drift", AND THAT IS NOT TRUE
			(review finding I5, traced 2026-08-28). The VALUE cannot drift; WHEN it is
			re-read can. This function runs from two places — the chrome reconcile
			(`syncChromeText`, on a theme swap or a plan change) and `refitIconArt`,
			which the adapter calls from `applyRect`. `render/rect_pass.luau` skips
			`adapter.setRect` for a rect equal to the last one written, so a node whose
			TEXT SIZE changed while its RECT did not — a `fixed`-px themed control at a
			new `preferredTextSize` step is exactly that shape — gets a new `TextSize`
			from `applyProps` and NO refit. The measure seam has already given the
			inset back (its floor rose with the text) while this seam is still holding
			the previous frame's box: the disagreement Decision 1b exists to prevent,
			in the one window it can still occur.

			FIXED 2026-08-28, the round after the source-cap extraction this drift was
			booked against landed: `screen_props.luau`'s `textSize` branch (the
			per-class chain moved there off `screen_target.luau`, source-cap-ledger)
			now calls `refitIconArt(handle)` beside the `syncTags` it already makes,
			so a `TextSize`-only write re-runs this arithmetic itself rather than
			waiting on the next `applyRect`. `tests/chrome_inset_yield.spec.luau`
			pins the wiring; the Studio capture (a themed fixed-px control at the
			largest text preference, measure and paint agreeing) is still owed.
			`TextScaled` is out of scope by declaration — see the head of this file —
			so that half of the risk is closed by design. ]]
		--[[ AN `IsA` TEST, NOT A `pcall` (review Minor 7, 2026-08-28). This ran a
			closure through `pcall` on EVERY call, and `refitIconArt` drives every call
			from `applyRect` — a per-rect-write allocation on the hot path, to answer a
			question the vocabulary already answers: `chrome_slots.LIFTED_TEXT_CLASSES`
			is the closed set of classes that HAVE a `TextSize`, and it is the same list
			`syncChromeText` gates the lift's existence on. A class outside it
			contributes no floor, which is what the failed `pcall` meant. ]]
		local lineBox = 0
		if handle ~= nil and handle.instance ~= nil then
			for _, className in chrome_slots.LIFTED_TEXT_CLASSES do
				if handle.instance:IsA(className) then
					local size = (handle.instance :: any).TextSize
					if type(size) == "number" then
						lineBox = size
					end
					break
				end
			end
		end
		local plaque = chrome_slots.plaqueTextBox(plan)
		local box = plaque or chrome_slots.liftGeometry(plan, hostW, hostH, lineBox, lineBox)
		local anchor = (box :: any).anchor
		local px, py = box.position.xOffset, box.position.yOffset
		local sx, sy = box.size.xOffset, box.size.yOffset
		if plaque == nil then
			-- COMPENSATE FOR THE HOST'S PADDING, exactly as `applyFullBleed` does for a
			-- decoration. A scale-1 child resolves against the PADDED content box, so
			-- the recipe's insets were being taken from an already-shrunken box: a 60px
			-- Open button with 12+12 padding gave the label 60-24-28 = **8px**, and it
			-- rendered nothing. Full-bleed first, then inset, gives 60-28 = 32px.
			local bleed = chrome_slots.fullBleedBox(padL, padR, padT, padB)
			px, py = px + bleed.x, py + bleed.y
			sx, sy = sx + bleed.w, sy + bleed.h
		end
		local pos = UDim2.new(box.position.xScale, px, box.position.yScale, py)
		local size = UDim2.new(box.size.xScale, sx, box.size.yScale, sy)
		return pos, size, if anchor ~= nil then Vector2.new(anchor.x, anchor.y) else Vector2.zero
	end

	-- the LAYERED editing yield. A stack has no single decoration
	-- to tag, so the yield rides the DECORATED NODE and the package's
	-- child-combinator rules (`.facet-chrome-yield > .facet-chrome-field-N`) blank
	-- the whole ladder in one flip. Routed through syncTags so the tag survives
	-- the desired-set diff — the fix round's lesson, applied at the seam.
	local setChromeYield: (handle: any, on: boolean) -> ()
	-- ...and the two stack helpers the yield's FALLBACK-mode half needs. All
	-- three are declared here rather than where they are defined because a local
	-- declared later is not an upvalue — the shape this file already keeps a
	-- hoisted `hasUIShadow` probe for.
	local yieldTargets: (handle: any, deco: ImageLabel?) -> { ImageLabel }
	local restoreChromeStackPaint: (handle: any) -> ()

	-- `deco` is nil for a LAYERED node: there is no single decoration, and the
	-- yield/fallback writes below key off that. `liftZ` puts the label above the
	-- whole ladder (rs-m2: a layer covers the parent's engine text at any ZIndex).
	local function syncChromeText(handle: any, deco: ImageLabel?, plan: any, liftZ: number)
		-- SEMANTIC ICON ART REPLACED THIS NODE'S GLYPH: the lift
		-- exists to raise the node's text above its decoration, and there is no
		-- longer any text that should draw. Without this a skinned stepper showed
		-- the ASCII "+" ON TOP of the plate art that replaced it.
		if handle.iconArt == true then
			destroyChromeText(handle)
			return
		end
		local instance = handle.instance
		local isButton = instance:IsA("TextButton")
		local isBox = instance:IsA("TextBox")
		-- A BADGE is a TextLabel, and its count is the whole point of the control
		-- (director review 2026-07-25: "values like '3' unreadable" — the number
		-- was painting UNDER the seal). Any text-bearing label under a decoration
		-- needs the lift for exactly the same reason a button does: under
		-- `Sibling` a child draws over its parent's engine text at any ZIndex.
		local lifts = false
		for _, className in chrome_slots.LIFTED_TEXT_CLASSES do
			lifts = lifts or instance:IsA(className)
		end
		if not lifts then
			return
		end
		-- FORCE A REBUILD ON RECYCLE (task CONN round 2, completeness sweep):
		-- `park`/`adopt` never touch `chromeText`/`chromeTextConns`, so a lift
		-- surviving under an UNCHANGED chrome key across a recycle kept its
		-- Focused/FocusLost closures' captured `deco` and its `centred` local,
		-- both fixed at THIS build call, silently stale for the new occupant.
		-- `destroyChromeText` clears everything so the fall-through below
		-- rebuilds fresh; `handle.chromeTextPath` is the same identity every
		-- other site in this sweep keys on.
		if handle.chromeText ~= nil and handle.chromeTextPath ~= handle.path then
			destroyChromeText(handle)
		end
		if handle.chromeText ~= nil then
			-- geometry follows the live recipe even when the label already exists
			-- (a theme swap can change the insets without changing the slot — or
			-- move the label onto a plaque the new package declares)
			local pos, size, anchor = liftGeometry(plan, handle)
			handle.chromeText.AnchorPoint = anchor
			handle.chromeText.Position = pos
			handle.chromeText.Size = size
			-- kept so a rect that lands AFTER the label can re-fit it without
			-- re-running the whole chrome reconcile (adapter.setRect → refitLift)
			handle.chromeTextPlan = plan
			-- ...and above whatever ladder is live NOW: a swap from a 2-layer
			-- package to a 6-layer one must not leave the label buried
			handle.chromeText.ZIndex = liftZ
			return
		end
		-- a badge's number reads centred on its seal, both axes, whatever the
		-- parent label's own alignment happens to be
		local centred = chrome_slots.centresLiftedText(handle.chromeSlot)
		local label = Instance.new("TextLabel")
		label.Name = chrome_slots.TEXT_LIFT_NAME
		label.Active = false
		label.Selectable = false
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		local pos, size, anchor = liftGeometry(plan, handle)
		label.AnchorPoint = anchor
		label.Position = pos
		label.Size = size
		handle.chromeTextPlan = plan
		-- above the ZIndex-0 nine-slice decoration, or above the whole 1..N layer
		-- ladder (rs-m2 measured the lift staying on top at depth 5)
		label.ZIndex = liftZ
		CollectionService:AddTag(label, chrome_slots.TAGS.text)

		local conns: { RBXScriptConnection } = {}
		local function mirror()
			local showingPlaceholder = false
			if isBox then
				local text = (instance :: TextBox).Text
				if text == "" and (instance :: TextBox).PlaceholderText ~= "" then
					text = (instance :: TextBox).PlaceholderText
					showingPlaceholder = true
				end
				label.Text = text
			else
				label.Text = (instance :: TextButton).Text
			end
			-- placeholder reads secondary, exactly as the parent would paint it;
			-- a tag flip restyles natively (never an explicit color write here)
			if CollectionService:HasTag(label, "facet-role-secondary") ~= showingPlaceholder then
				if showingPlaceholder then
					CollectionService:AddTag(label, "facet-role-secondary")
				else
					CollectionService:RemoveTag(label, "facet-role-secondary")
				end
			end
			label.TextSize = (instance :: any).TextSize
			label.TextXAlignment = if centred then Enum.TextXAlignment.Center else (instance :: any).TextXAlignment
			label.TextYAlignment = if centred then Enum.TextYAlignment.Center else (instance :: any).TextYAlignment
			label.TextWrapped = (instance :: any).TextWrapped
			label.TextTruncate = (instance :: any).TextTruncate
			-- RichText and LineHeight are TEXT SHAPE, not paint: a RichText
			-- consumer whose label was lifted got the raw markup rendered as
			-- literal tags, and a custom line height silently reverted to 1.
			label.RichText = (instance :: any).RichText
			label.LineHeight = (instance :: any).LineHeight
			if not nativeMode then
				label.TextColor3 = if isBox and showingPlaceholder
					then (instance :: TextBox).PlaceholderColor3
					else (instance :: any).TextColor3
				label.FontFace = (instance :: any).FontFace
				label.TextTransparency = (instance :: any).TextTransparency
			end
		end
		local WATCHED = {
			"Text",
			"TextSize",
			"TextXAlignment",
			"TextYAlignment",
			"TextWrapped",
			"TextTruncate",
			"RichText",
			"LineHeight",
		}
		local WATCHED_FALLBACK = { "TextColor3", "FontFace", "TextTransparency", "PlaceholderColor3" }
		for _, prop in WATCHED do
			table.insert(conns, instance:GetPropertyChangedSignal(prop):Connect(mirror))
		end
		if isBox then
			table.insert(conns, instance:GetPropertyChangedSignal("PlaceholderText"):Connect(mirror))
		end
		if not nativeMode then
			for _, prop in WATCHED_FALLBACK do
				if isBox or prop ~= "PlaceholderColor3" then
					table.insert(conns, instance:GetPropertyChangedSignal(prop):Connect(mirror))
				end
			end
		end
		if isBox then
			-- the engine caret is parent-drawn and non-negotiable: while editing,
			-- the chrome YIELDS (tag rule flattens it natively; fallback writes
			-- the same) and the lifted label hides so text paints exactly once
			table.insert(
				conns,
				(instance :: TextBox).Focused:Connect(function()
					-- the yield flag rides the NODE in both shapes now. A layered
					-- field always needed it (one tag blanks the whole ladder); a
					-- nine-slice one needs it too, because the rule that gives the
					-- field its own fill back while the art is hidden is keyed on
					-- the node, not on the decoration (see sheet_model's
					-- "field editing, own fill"). Without a background the caret
					-- was drawn on bare page.
					setChromeYield(handle, true)
					if deco ~= nil then
						CollectionService:AddTag(deco, chrome_slots.TAGS.editing)
					end
					label.Visible = false
					if not nativeMode then
						-- FULLY transparent, not repainted. The decoration is a CHILD,
						-- and under `Sibling` any opaque child draws over its parent's
						-- engine text and caret — so painting the native fill here hid
						-- exactly what the yield exists to reveal. The TextBox's own
						-- fill (applySurface at create) is what shows while editing.
						for _, child in yieldTargets(handle, deco) do
							child.ImageTransparency = 1
							child.BackgroundTransparency = 1
						end
					end
				end)
			)
			table.insert(
				conns,
				(instance :: TextBox).FocusLost:Connect(function()
					setChromeYield(handle, false)
					if deco ~= nil then
						CollectionService:RemoveTag(deco, chrome_slots.TAGS.editing)
					end
					label.Visible = true
					if not nativeMode then
						local plan = handle.chromeSlot ~= nil and chromeState.planFor(handle.chromeSlot) or nil
						if deco ~= nil and plan ~= nil then
							applyChromeFallbackWrites(
								deco,
								handle.chromeSlot,
								chromeState.isFallback(handle.chromeSlot),
								chromeState.isArtMuted(handle.chromeSlot, plan.assetName, deco.IsLoaded),
								plan
							)
						elseif deco == nil then
							-- a LAYERED field on a target with no StyleSheets: the same
							-- restore, one instance per rail
							restoreChromeStackPaint(handle)
						end
					end
				end)
			)
		end
		mirror()
		label.Parent = instance
		handle.chromeText = label
		handle.chromeTextConns = conns
		handle.chromeTextPath = handle.path
		instancesByPath[handle.path .. "/" .. chrome_slots.TEXT_LIFT_NAME] = label
		chromeTextLifts += 1
	end

	-- re-apply the fallback tags for every live decoration of `assetName`
	local function refreshChromeFallback()
		for _, handle in handlesByPath do
			-- a LAYERED node has no `handle.chrome` at all; without this half a
			-- broken layer would never reach its fallback rules. NOR DOES A BAR
			-- (rich-skinning v2): its art is the adapter-owned fill and ornaments, so a
			-- ledger change reached a bar's parts only if something else happened to
			-- re-sync that node — which is also the path a RECOVERY has to travel.
			if
				handle.chrome ~= nil
				or handle.chromeStack ~= nil
				or handle.barFill ~= nil
				or handle.barOrnaments ~= nil
			then
				syncChrome(handle)
			end
		end
	end

	local function setChromeAssetLoaded(assetName: string, ok: boolean)
		if chromeState.setAssetLoaded(assetName, ok) then
			refreshChromeFallback()
		end
	end

	-- THE TWO FALLBACK TAGS, in ONE place (rich-skinning v2). `fallback` says "this slot
	-- is drawing its declared native treatment" and carries the FILL; `mute` says
	-- "and this art instance must not draw over it" and carries the hide. They
	-- differ on exactly one instance: the art whose OWN asset was condemned keeps
	-- drawing, because a fully transparent image is never decoded and muting it
	-- destroys the only signal that could ever report its recovery. Every flip site
	-- — nine-slice, layer stack, bar part — asks this, so the three cannot drift.
	local function setChromeTag(child: Instance, tag: string, want: boolean): boolean
		if CollectionService:HasTag(child, tag) == want then
			return false
		end
		if want then
			CollectionService:AddTag(child, tag)
		else
			CollectionService:RemoveTag(child, tag)
		end
		return true
	end

	-- returns (fallback, muted, changed)
	local function syncChromeFallbackTags(
		child: ImageLabel,
		slot: string,
		assetName: string?,
		eligible: boolean
	): (boolean, boolean, boolean)
		local fallback = eligible and chromeState.isFallback(slot)
		-- `IsLoaded` is the narrowing fact: art the engine has already decoded is no
		-- instrument (its signal cannot change again), so it hides with the siblings
		local muted = eligible and chromeState.isArtMuted(slot, assetName, child.IsLoaded)
		local changed = setChromeTag(child, chrome_slots.TAGS.fallback, fallback)
		changed = setChromeTag(child, chrome_slots.TAGS.mute, muted) or changed
		return fallback, muted, changed
	end

	-- THE FACT-GATHERING HALF of "is this art evidence about loading?"
	-- (chrome_slots.judgeArt owns the decision and its five clauses; this reads
	-- the five facts off real Instances). ONE ancestor walk answers three of them
	-- at once — `Visible`, attachment, and the rect of every `ClipsDescendants`
	-- host between the art and its LayerCollector.
	--
	-- The transparency and the source are RULE-owned in native mode, where a plain
	-- read is blind, so `GetStyled` is the instrument and the plain read is the
	-- fallback-mode answer.
	local function chromeArtJudgement(deco: ImageLabel): chrome_slots.ArtJudgement
		local transparency = deco.ImageTransparency
		local okStyled, styled = pcall(function()
			return (deco :: any):GetStyled("ImageTransparency")
		end)
		if okStyled and type(styled) == "number" then
			transparency = styled
		end
		local resolved = deco.Image
		local okImage, styledImage = pcall(function()
			return (deco :: any):GetStyled("Image")
		end)
		if okImage and type(styledImage) == "string" then
			resolved = styledImage
		end
		local pos, box = deco.AbsolutePosition, deco.AbsoluteSize
		local clips: { chrome_slots.ArtRect } = {}
		local visible = true
		local node: Instance? = deco
		while node ~= nil and not node:IsA("LayerCollector") do
			if node:IsA("GuiObject") then
				local gui = node :: GuiObject
				if not gui.Visible then
					visible = false
				end
				-- the art's OWN ClipsDescendants clips its children, never itself
				if node ~= deco and gui.ClipsDescendants then
					local cp, cs = gui.AbsolutePosition, gui.AbsoluteSize
					table.insert(clips, { x = cp.X, y = cp.Y, w = cs.X, h = cs.Y })
				end
			end
			node = node.Parent
		end
		return chrome_slots.judgeArt({
			attached = node ~= nil,
			visible = visible,
			transparency = transparency,
			-- the fallback's own hide, told apart from the package's intent: same
			-- verdict, and the reason is what makes the ledger's telemetry honest
			mutedByFallback = CollectionService:HasTag(deco, chrome_slots.TAGS.mute),
			image = resolved,
			rect = { x = pos.X, y = pos.Y, w = box.X, h = box.Y },
			clips = clips,
		})
	end

	local function watchChromeAsset(deco: ImageLabel, assetName: string)
		-- IsLoaded is the engine's only per-image signal here: ImageLabel has no
		-- LoadingImageFailed (native-substrate spike). A SUCCESS therefore
		-- arrives as a property change; a FAILURE arrives as silence, which is
		-- why the grace timer exists.
		local conn: RBXScriptConnection? = nil
		conn = deco:GetPropertyChangedSignal("IsLoaded"):Connect(function()
			if deco.IsLoaded then
				setChromeAssetLoaded(assetName, true)
				if conn ~= nil then
					conn:Disconnect()
					conn = nil
				end
			end
		end)
		-- THE DEADLINE DEFERS, IT DOES NOT SKIP (rich-skinning v2). Art the engine was
		-- never asked to decode is not evidence about its asset — but it is not a
		-- verdict of "healthy" either. A ScrollView's off-window rows would
		-- otherwise never be judged at all, so a package whose art really is broken
		-- would leave the nodes it skins drawing NOTHING (the plate is suppressed
		-- under a skin) instead of falling back. So an unjudgeable decoration
		-- re-arms the same window and is judged the moment it becomes judgeable —
		-- scrolled into view, un-collapsed, laid out, sourced, un-muted.
		--
		-- The chain terminates: it stops when the decoration dies, when this
		-- deadline reaches a verdict, and when ANY decoration of the same asset has
		-- already reached one (the ledger is asked, not this instance). Only assets
		-- with no judgeable decoration anywhere keep a timer alive, and they are
		-- exactly the ones still owed an answer.
		local judge: () -> ()
		judge = function()
			if deco.Parent == nil then
				return
			end
			if deco.IsLoaded then
				-- RECOVERY (live-found, director round 6). The signal above is a
				-- CHANGE signal, and an image that is ALREADY resident never
				-- changes — so a decoration built after the texture arrived
				-- reported nothing, and an asset marked failed during a cold start
				-- stayed failed for the rest of the session. Measured live: every
				-- `panel`/`control` decoration in the value fixture still carried
				-- `facet-chrome-fallback` with `IsLoaded = true`, which is how a
				-- disabled row came to draw its art at 0.4 over the fallback's
				-- native fill. The grace deadline is the right place to read it:
				-- by then the rule that sets `Image` has applied, so a true here
				-- means the picture is really there rather than that there is no
				-- picture yet.
				setChromeAssetLoaded(assetName, true)
				return
			end
			if chromeState.everLoaded(assetName) or chromeState.isAssetFailed(assetName) then
				return -- this asset already has a verdict; nothing left to judge
			end
			if chromeArtJudgement(deco).judgeable then
				-- the TARGET'S OWN inference from silence, which the ledger refuses
				-- once the asset has been seen to decode (chrome_slots: the monotone
				-- unknown -> failed -> loaded lattice that makes a flip/unflip cycle
				-- unreachable)
				if chromeState.observeAssetFailed(assetName) then
					refreshChromeFallback()
				end
				return
			end
			task.delay(CHROME_ASSET_GRACE_SECONDS, judge)
		end
		task.delay(CHROME_ASSET_GRACE_SECONDS, judge)
	end

	-- THE JUDGEMENT, AS A DEV INSTRUMENT (rich-skinning v2). `chromeCensus` publishes
	-- which assets this target has CONDEMNED; this publishes whether the engine
	-- was ever asked to decode the art that condemned them, over every art
	-- instance the target owns — the exact population whose silence can reach the
	-- ledger. `undecodedJudgeable` is the number that matters: art the target is
	-- entitled to call broken. Off-window art must never be in it, which is the
	-- defect this exists to make visible, and the reason histogram says why the
	-- rest were spared.
	local function chromeArtCensus(): any
		local byReason: { [string]: number } = {}
		local images, judgeable, undecoded, undecodedJudgeable = 0, 0, 0, 0
		local samples: { any } = {}
		local function visit(art: any, assetName: string?)
			-- `handle.iconArt` is a BOOLEAN flag, not the picture (the icon instance
			-- lives under the node by name), so this is typeof-guarded rather than
			-- nil-guarded: a dev instrument must not be the thing that throws
			if typeof(art) ~= "Instance" or not art:IsA("ImageLabel") or art.Parent == nil then
				return
			end
			local deco = art :: ImageLabel
			images += 1
			local verdict = chromeArtJudgement(deco)
			local reason = verdict.reason or "judgeable"
			byReason[reason] = (byReason[reason] or 0) + 1
			if verdict.judgeable then
				judgeable += 1
			end
			if deco.IsLoaded then
				return
			end
			undecoded += 1
			if not verdict.judgeable then
				return
			end
			undecodedJudgeable += 1
			if #samples < 8 then
				table.insert(samples, {
					name = deco.Name,
					host = if deco.Parent ~= nil then deco.Parent.Name else "?",
					asset = assetName,
					x = deco.AbsolutePosition.X,
					y = deco.AbsolutePosition.Y,
					w = deco.AbsoluteSize.X,
					h = deco.AbsoluteSize.Y,
				})
			end
		end
		for _, handle in handlesByPath do
			local plan = if handle.chromeSlot ~= nil then chromeState.planFor(handle.chromeSlot) else nil
			visit(handle.chrome, if plan ~= nil then plan.assetName else nil)
			visit(handle.barFill, if plan ~= nil then plan.assetName else nil)
			visit(instancesByPath[handle.path .. "/" .. chrome_slots.ICON_NAME], nil)
			visit(handle.track, nil)
			visit(handle.knob, nil)
			for _, entry in handle.chromeStack or {} do
				visit(entry.instance, entry.layer.assetName)
			end
			for _, entry in handle.barOrnaments or {} do
				visit(entry.instance, if entry.plan ~= nil then entry.plan.assetName else nil)
			end
		end
		-- THE LIFTED LABEL HAS TO FIT THE CHROME THAT TOOK IT.
		--
		-- Found live on `fantasy_ornate` (2026-08-05): a 60x46 Open button whose OWN
		-- text reported `TextFits = true` at 36x18, while the label the chrome lifted
		-- into `FacetChromeText` was **8px wide** — a 36px decoration minus two 14px
		-- corner pieces. The button rendered with no readable label and the solver
		-- filed nothing, because the solver measured the BUTTON's box and the adapter
		-- then painted the label into a box derived from the ART.
		--
		-- That is the "painted at a size nobody measured for it" family this project
		-- already has a lesson about, reaching the one seam the layout audit cannot
		-- see. This does not repair it — the fix is a theme/layout contract change —
		-- but it stops it being INVISIBLE, which is what let it ship.
		local liftedTooSmall: { any } = {}
		local liftedChecked = 0
		for _, handle in handlesByPath do
			local lifted = handle.chromeText
			if typeof(lifted) == "Instance" and lifted:IsA("TextLabel") and lifted.Parent ~= nil then
				liftedChecked += 1
				-- `TextBounds` IS THE RENDERED WIDTH, NOT THE REQUIRED ONE. The first
				-- version of this check compared the box against `lifted.TextBounds` and
				-- flagged nothing: a label truncated to nothing reports **0**, so
				-- "box narrower than text" was never true for exactly the labels that
				-- had vanished. (Same family as `TextFits` reporting true for a
				-- truncating label.)
				--
				-- The requirement comes from the HOST instead — the control's own
				-- measured text, which the solver sized the control for. If the box the
				-- chrome handed the label is narrower than that, the theme has taken a
				-- label the layout made room for and put it somewhere it does not fit.
				local box = lifted.AbsoluteSize
				local host = lifted.Parent
				local want = 0
				if host ~= nil and (host:IsA("TextButton") or host:IsA("TextLabel")) then
					want = (host :: any).TextBounds.X
				end
				local vanished = lifted.Text ~= "" and lifted.TextBounds.X <= 0
				if lifted.Text ~= "" and (vanished or (want > 0 and box.X + 0.5 < want)) then
					if #liftedTooSmall < 8 then
						table.insert(liftedTooSmall, {
							host = if lifted.Parent ~= nil then lifted.Parent.Name else "?",
							text = lifted.Text,
							boxW = math.floor(box.X + 0.5),
							wantW = math.floor(want + 0.5),
							-- the label rendered NOTHING: the unambiguous case
							vanished = vanished,
						})
					end
				end
			end
		end

		-- THE DECORATION HAS TO COVER THE CONTROL IT FRAMES.
		--
		-- Found live on `fantasy_ornate` (2026-08-05, director report): a 336px row
		-- framed by 312px of art and a 60px button by 36px — short by exactly 24px on X
		-- and 0 on Y, on ten of seventeen decorated nodes. 24px is the host's own
		-- horizontal `UIPadding` (`space.s + 4` per side), and Y was clean only because
		-- these controls have no vertical padding.
		--
		-- Roblox's `UIPadding` shrinks a host's ENGINE children, so a decoration
		-- parented to a padded control is inset by that padding unless something adds
		-- it back. `applyFullBleed` does exactly that — and it has ONE call site, which
		-- the layered (`chromeStack`) path does not use. The content then sits outside
		-- the painted frame: the avatar, the labels and the value row all did.
		--
		-- This reports it rather than repairing it; the repair belongs with the stack
		-- placement code and its own verification. What it stops is the silence.
		local undersized: { any } = {}
		local decoratedNodes = 0
		for _, handle in handlesByPath do
			local host = handle.instance
			if typeof(host) == "Instance" and host:IsA("GuiObject") then
				-- the single-decoration path names it `FacetChrome`; a LAYERED package
				-- names its layers `FacetChromeL<N>` and never creates the former, so a
				-- check that only looked for `DECORATION_NAME` was blind to exactly the
				-- packages this defect lives in
				local primary = host:FindFirstChild(chrome_slots.DECORATION_NAME)
					or host:FindFirstChild(chrome_slots.LAYER_NAME_PREFIX .. "1")
				if primary ~= nil and primary:IsA("GuiObject") then
					decoratedNodes += 1
					local shortW = host.AbsoluteSize.X - primary.AbsoluteSize.X
					local shortH = host.AbsoluteSize.Y - primary.AbsoluteSize.Y
					if (shortW > 1 or shortH > 1) and #undersized < 8 then
						table.insert(undersized, {
							host = host.Name,
							hostW = math.floor(host.AbsoluteSize.X + 0.5),
							decoW = math.floor(primary.AbsoluteSize.X + 0.5),
							uncoveredX = math.floor(shortW + 0.5),
							uncoveredY = math.floor(shortH + 0.5),
						})
					end
				end
			end
		end

		return {
			decoratedNodes = decoratedNodes,
			undersizedDecorations = #undersized,
			undersizedSamples = undersized,
			images = images,
			judgeable = judgeable,
			undecoded = undecoded,
			undecodedJudgeable = undecodedJudgeable,
			byReason = byReason,
			undecodedJudgeableSamples = samples,
			-- chrome-lifted labels whose box cannot hold their own text
			liftedChecked = liftedChecked,
			liftedTooSmall = #liftedTooSmall,
			liftedTooSmallSamples = liftedTooSmall,
		}
	end

	-- SLOT SHADOWS (director fix round).
	--
	-- AUTHORITY NOTE, deliberately: this is adapter-owned paint on a node the
	-- SHEET does not shadow. `::UIShadow` rules are silently accepted and paint
	-- nothing on 0.731 (feasibility m7), and the package compiler REJECTS the
	-- selector for exactly that reason — so there is no rule to defeat here and
	-- no dual authority. The shadow rides the existing bespoke `UIShadow`
	-- machinery behind the same `hasUIShadow` capability probe, which is why a
	-- headless target and an old engine simply get none.
	--
	-- It is parented to WHATEVER PAINTS THE SLOT: the decoration when the recipe
	-- is nine-slice (the art is the shape that should cast the shadow, and the
	-- node's own plate is suppressed under it), the node itself when the recipe
	-- is native. One rule, no per-package special cases.
	-- dropChromeShadow: the ONE teardown path, so the census can always fall and a
	-- shadow can never outlive the instance it was parented to (destroying a
	-- decoration destroys its children, and a destroyed instance can never be
	-- re-parented — that combination is a hard error, not a leak)
	local function dropChromeShadow(handle: any)
		if handle.chromeShadow == nil then
			return
		end
		pcall(function()
			handle.chromeShadow:Destroy()
		end)
		handle.chromeShadow = nil
		if handle.chromeShadowSlot ~= nil then
			chromeState.noteShadow(handle.chromeShadowSlot, false)
			handle.chromeShadowSlot = nil
		end
	end

	-- `slot` is passed EXPLICITLY rather than read from handle.chromeSlot: a
	-- NATIVE recipe's shadow lands on a node with no decoration at all, so
	-- handle.chromeSlot is nil there and the census would be keyed on nothing.
	local function syncChromeShadow(handle: any, slot: string?, host: Instance?, spec: any)
		if spec == nil or host == nil or slot == nil or not hasUIShadow then
			dropChromeShadow(handle)
			return
		end
		local ok, normalized = pcall(styling.normalizeShadow, spec, style)
		if not ok then
			-- `themes.define` already gated this shape; a package that reached
			-- here with a bad one degrades to NO shadow rather than tearing down
			-- the surface mid-render
			dropChromeShadow(handle)
			return
		end
		-- a slot change (or a host change) rebuilds: the instance is a child of
		-- whatever paints the slot, and that may have just been replaced
		if handle.chromeShadow ~= nil and (handle.chromeShadowSlot ~= slot or handle.chromeShadow.Parent ~= host) then
			dropChromeShadow(handle)
		end
		local live = handle.chromeShadow
		if live == nil then
			live = Instance.new("UIShadow" :: any)
			handle.chromeShadow = live
			handle.chromeShadowSlot = slot
			chromeState.noteShadow(slot, true)
		end
		local shadow: any = normalized
		live.BlurRadius = UDim.new(shadow.blurRadius.scale, shadow.blurRadius.offset)
		live.Color = Color3.new(shadow.color.r, shadow.color.g, shadow.color.b)
		live.Transparency = shadow.transparency
		live.Offset =
			UDim2.new(shadow.offset.x.scale, shadow.offset.x.offset, shadow.offset.y.scale, shadow.offset.y.offset)
		live.Spread =
			UDim2.new(shadow.spread.x.scale, shadow.spread.x.offset, shadow.spread.y.scale, shadow.spread.y.offset)
		live.ZIndex = shadow.zIndex
		live.Enabled = shadow.enabled
		live.Parent = host
	end

	-- ===== LAYERED DECORATION STACKS (probes rs-m2 + rs-m3) =====
	--
	-- A layered recipe wants N ordered children instead of one. Everything
	-- decidable without an engine is already decided in `chrome_slots`: which
	-- boxes a layer needs, where each sits, which tags it carries, how deep the
	-- text lift goes. What is left here is Instance.new, AnchorPoint/Position/
	-- Size, ZIndex, the tags, and the teardown.
	--
	-- THEY ARE DIRECT CHILDREN OF THE DECORATED NODE, never wrapped in a
	-- container: every state rule the package emits is a CHILD COMBINATOR off
	-- the node (`.facet-state-selected > .facet-chrome-panel-3`), and one
	-- intervening Frame would break all of them at once.
	--
	-- NOT ONE PAINT PROPERTY IS WRITTEN HERE IN NATIVE MODE. rs-m2's defeat
	-- refinement is the reason and it is not a style preference: a value written
	-- before the node joins the styled tree, with no rule matching it yet,
	-- SURVIVES and permanently defeats the rule that starts matching later —
	-- which is exactly what a per-state art swap is.
	local function stackSignature(slot: string, stack: any): string
		local parts: { string } = { slot }
		for _, layer in stack.layers do
			local geometry: { string } = {}
			-- `inset` rides here for the same reason every other geometry field
			-- does: a package swap that changes ONLY an inset changes the boxes,
			-- and a signature that could not see it would leave the old ladder up
			for _, field in
				{ "size", "sides", "thickness", "margin", "tile", "tileSize", "edge", "overhang", "inset", "mask" }
			do
				local v = (layer.geometry :: any)[field]
				if type(v) == "table" then
					local inner: { string } = {}
					for k, value in v do
						table.insert(inner, `{tostring(k)}={tostring(value)}`)
					end
					table.sort(inner)
					table.insert(geometry, `{field}:\{{table.concat(inner, ",")}}`)
				elseif v ~= nil then
					table.insert(geometry, `{field}:{tostring(v)}`)
				end
			end
			local corners: { string } = {}
			for corner, variants in layer.cornerVariants do
				table.insert(corners, `{corner}={variants.default.contentId}`)
			end
			table.sort(corners)
			table.insert(
				parts,
				`{layer.index}:{layer.kind}:{layer.contentId}:{layer.scaleType}:`
					.. `{table.concat(geometry, ";")}:{table.concat(corners, ";")}`
			)
		end
		return table.concat(parts, "|")
	end

	-- FALLBACK MODE ONLY (a target with no StyleSheets). The identical values the
	-- package's layer rules carry, explicit-written from the SAME plan, so the two
	-- paths cannot drift. `cornerContentId` lets a per-corner override win here
	-- exactly as its later-inserted rule wins natively.
	local function applyChromeLayerPaint(child: ImageLabel, layer: any, cornerContentId: string?)
		child.BackgroundTransparency = 1
		child.Image = cornerContentId or layer.contentId
		if layer.scaleType == "Slice" then
			child.ScaleType = Enum.ScaleType.Slice
			if layer.sliceCenter ~= nil then
				child.SliceCenter =
					Rect.new(layer.sliceCenter.x0, layer.sliceCenter.y0, layer.sliceCenter.x1, layer.sliceCenter.y1)
			end
			child.SliceScale = layer.sliceScale
		elseif layer.scaleType == "Tile" then
			child.ScaleType = Enum.ScaleType.Tile
			local size = layer.geometry.tileSize
			local repeatPx = layer.geometry.tile
			local w = if type(size) == "table" then size.w else repeatPx
			local h = if type(size) == "table" then size.h else repeatPx
			child.TileSize = UDim2.new(0, w or 0, 0, h or 0)
		else
			child.ScaleType = Enum.ScaleType.Stretch
		end
		-- the SAME resting tint the nine-slice fallback path writes (an
		-- ImageColor3 only multiplies down from white, so rest sits under it to
		-- leave hover headroom — chrome_slots.TINT)
		local rest = chrome_slots.TINT.rest
		child.ImageColor3 = Color3.new(rest, rest, rest)
		child.ImageTransparency = 0
	end

	-- every layer instance of a stack, flat (the yield and the fallback flip both
	-- act on the whole ladder — one broken layer is a broken skin, not a degraded
	-- one, so the stack fails and recovers as a unit)
	local function stackInstances(handle: any): { ImageLabel }
		local out: { ImageLabel } = {}
		for _, entry in handle.chromeStack or {} do
			table.insert(out, entry.instance)
		end
		return out
	end

	function yieldTargets(handle: any, deco: ImageLabel?): { ImageLabel }
		if deco ~= nil then
			return { deco }
		end
		return stackInstances(handle)
	end

	function restoreChromeStackPaint(handle: any)
		for _, entry in handle.chromeStack or {} do
			applyChromeLayerPaint(entry.instance, entry.layer, entry.cornerContentId)
		end
	end

	function setChromeYield(handle: any, on: boolean)
		if (handle.chromeYield == true) == on then
			return
		end
		handle.chromeYield = on
		syncTags(handle)
	end

	local function destroyChromeStack(handle: any)
		if handle.chromeStack == nil then
			return
		end
		for _, entry in handle.chromeStack do
			instancesByPath[handle.path .. "/" .. entry.instance.Name] = nil
			entry.instance:Destroy()
			-- the mask wrapper falls with its art, and its census entry with it:
			-- a canvas that outlived its layer would be an invisible live cost
			if entry.mask ~= nil then
				instancesByPath[handle.path .. "/" .. entry.mask.Name] = nil
				entry.mask:Destroy()
				chromeState.noteCanvasMask(false)
			end
		end
		-- the census counts LAYERS (the authoring unit, so it compares directly
		-- with chrome_slots.censusOf); `actualLayerInstances` is the DataModel
		-- unit, counted independently in chromeCensus
		for _, kind in handle.chromeStackKinds or {} do
			chromeState.noteDestroyed(handle.chromeStackSlot, kind)
		end
		handle.chromeStack = nil
		handle.chromeStackKinds = nil
		handle.chromeStackSlot = nil
		handle.chromeStackSignature = nil
		-- THE LIFT BELONGS TO THE DECORATION (live-found, director round 7). The
		-- nine-slice rebuild path has always torn the lifted label down with the
		-- decoration; the ladder did not, so a swap from a layered package to a
		-- flat one left an orphan `FacetChromeText` still boxed by the OUTGOING
		-- recipe's contentInsets. Measured live: after ornate -> studio-neutral the
		-- toolbar's three buttons each kept a lift at `{1, -28}` inside a 36px box,
		-- i.e. -16 px wide. It draws nothing at that size, which is exactly why it
		-- survived — the node's own engine text was doing the drawing. A stack that
		-- is being rebuilt gets its lift back on the next line.
		destroyChromeText(handle)
	end

	local function buildChromeStack(handle: any, slot: string, stack: any)
		local instance = handle.instance
		local built: { any } = {}
		local kinds: { string } = {}
		-- the whole ladder lives in the DECORATION band (<= 0), below the node's own
		-- content — see `chrome_slots.layerZIndexFor` for why, and for the live A/B
		-- that found it
		local layerCount = #stack.layers
		for _, layer in stack.layers do
			table.insert(kinds, layer.kind)
			local first = true
			for _, spec in chrome_slots.layerBoxes(layer) do
				local cornerContentId: string? = nil
				if spec.corner ~= nil then
					local variants = layer.cornerVariants[spec.corner]
					cornerContentId = if variants ~= nil then variants.default.contentId else nil
				end
				-- THE MASK WRAPPER (the layer stack's `mask`, probe rs-m9). A masked layer
				-- puts its BOX on an adapter-owned CanvasGroup and its art full-bleed
				-- inside it, so UICorner clips the art along the silhouette. The
				-- wrapper is a SHAPE, never paint: untagged (no rule can reach it),
				-- Active = false, and every existing rule path — resting art, per-state
				-- variants, tint, fallback, suppression — still selects the same
				-- tagged ImageLabel it always did. rs-m9 Q2 is what makes that safe:
				-- rules reach a tagged child inside a canvas exactly as outside.
				local maskKind = chrome_slots.layerMaskOf(layer)
				local mask: CanvasGroup? = nil
				if maskKind ~= nil then
					local made = Instance.new("CanvasGroup")
					made.Name = spec.name .. chrome_slots.LAYER_MASK_SUFFIX
					made.Active = false
					made.Selectable = false
					made.BorderSizePixel = 0
					made.AnchorPoint = Vector2.new(spec.anchor.x, spec.anchor.y)
					made.Position = UDim2.new(
						spec.position.xScale,
						spec.position.xOffset,
						spec.position.yScale,
						spec.position.yOffset
					)
					made.Size = UDim2.new(spec.size.xScale, spec.size.xOffset, spec.size.yScale, spec.size.yOffset)
					made.ZIndex = chrome_slots.layerZIndexFor(layer.index, layerCount)
					local corner = Instance.new("UICorner")
					-- "pill": scale 0.5 is a half-height radius at every width, so the
					-- silhouette follows a stretched track instead of a fixed radius
					corner.CornerRadius = UDim.new(0.5, 0)
					corner.Parent = made
					made.Parent = instance
					mask = made
				end
				local child = Instance.new("ImageLabel")
				child.Name = spec.name
				child.Active = false -- input-transparent ornaments (rs-m3)
				child.Selectable = false
				child.BorderSizePixel = 0
				if mask ~= nil then
					child.AnchorPoint = Vector2.zero
					child.Position = UDim2.fromScale(0, 0)
					child.Size = UDim2.fromScale(1, 1)
					child.ZIndex = 1
				else
					child.AnchorPoint = Vector2.new(spec.anchor.x, spec.anchor.y)
					child.Position = UDim2.new(
						spec.position.xScale,
						spec.position.xOffset,
						spec.position.yScale,
						spec.position.yOffset
					)
					child.Size = UDim2.new(spec.size.xScale, spec.size.xOffset, spec.size.yScale, spec.size.yOffset)
					child.ZIndex = chrome_slots.layerZIndexFor(layer.index, layerCount) -- Z-ORDER IS ARRAY ORDER
				end
				-- TAG BEFORE PARENT: the rule is matching the instant it joins the
				-- styled tree, which is the only condition under which a later
				-- state rule can still win (rs-m2)
				CollectionService:AddTag(child, layer.tag)
				if spec.corner ~= nil then
					CollectionService:AddTag(child, chrome_slots.cornerTagFor(slot, layer.index, spec.corner))
				end
				if not nativeMode then
					applyChromeLayerPaint(child, layer, cornerContentId)
				end
				child.Parent = mask or instance
				-- FULL-BLEED THE LAYER, exactly as the single-decoration path does.
				--
				-- A `UIPadding` on the host shrinks every engine child, so a layer sized
				-- `fromScale(1, 1)` covers the host's PADDED content box, not the host.
				-- `applyFullBleed` exists for that and had ONE call site — the
				-- single-decoration path — so every LAYERED package drew its frame short
				-- by the host's padding. Measured live on `fantasy_ornate`: a 336px row
				-- framed by 312px of art and a 60px button by 36px, short by exactly the
				-- 12+12 padding, on X only because these controls have no vertical
				-- padding. The avatar, the labels and the value row all sat outside the
				-- border that was supposed to contain them.
				--
				-- Skipped when the layer sits inside a MASK: the mask is the full-bleed
				-- surface then, and the layer is deliberately positioned within it.
				local fullBleed = mask == nil and spec.size.xScale == 1 and spec.size.yScale == 1
				if fullBleed then
					applyFullBleed(instance, child)
				end
				instancesByPath[handle.path .. "/" .. spec.name] = child
				if mask ~= nil then
					instancesByPath[handle.path .. "/" .. mask.Name] = mask
					chromeState.noteCanvasMask(true)
				end
				table.insert(built, {
					instance = child,
					mask = mask,
					layer = layer,
					cornerContentId = cornerContentId,
					-- WHICH layers `refitFullBleed` owns, recorded where the decision is
					-- made rather than re-derived from `spec` it would have to keep: a
					-- masked or partial layer is positioned deliberately and must never
					-- be pushed back out by the host's padding
					fullBleed = fullBleed,
				})
				if first then
					-- ONE grace timer per LAYER, not per ornament: four corners of
					-- one asset would otherwise report the same failure four times
					watchChromeAsset(child, layer.assetName)
					first = false
				end
			end
			chromeState.noteCreated(slot, layer.kind)
		end
		handle.chromeStack = built
		handle.chromeStackKinds = kinds
		handle.chromeStackSlot = slot
		handle.chromeStackSignature = stackSignature(slot, stack)
	end

	-- the whole-stack fallback flip. Tag-driven natively (`.<layerTag>.fallback`
	-- rules hide every layer and repaint the BACK one with the declared native
	-- fill); explicit-written on a target with no sheet.
	local function syncChromeStackFallback(handle: any, slot: string)
		for _, entry in handle.chromeStack or {} do
			local child = entry.instance
			-- per LAYER, not per stack (rich-skinning v2): the broken layer keeps its art
			-- (it draws nothing and is the only instrument that can report its own
			-- recovery); every healthy sibling hides, which is what the mute is for
			local want, muted, changed = syncChromeFallbackTags(child, slot, entry.layer.assetName, true)
			if not changed or nativeMode then
				continue
			end
			applyChromeLayerPaint(child, entry.layer, entry.cornerContentId)
			if muted then
				child.ImageTransparency = 1
			end
			if want and entry.layer.index == 1 then
				child.BackgroundColor3 = chromeFillOf[slot] or toColor3(style.colors.surfaceStrong)
				child.BackgroundTransparency = 0
			end
		end
	end

	-- ===== IMAGE VALUE DISPLAYS: THE BAR ASSEMBLY (probe rs-m4) ==
	--
	-- rs-m4 measured two ways to clip an image fill to a percent and rejected the
	-- ImageRect crop outright: `ImageRect` and `ScaleType = Slice` both address the
	-- texture, so composing them re-derives the nine-patch from the CROPPED rect —
	-- mid-percent fills lose the rail detail and the end cap is cut out of the
	-- middle of the texture. The winner is a WINDOW.
	--
	-- WHAT THE ADAPTER BUILDS, and where each piece lives:
	--
	--   the FILL node (hint `barFill`)     the solver already sizes this node to
	--                                      the percent — it IS a flat bar's accent
	--                                      block — so it is the window's rect. The
	--                                      adapter parents a ClipsDescendants
	--                                      window over it and puts a FULL-TRACK
	--                                      -size ImageLabel inside. The art never
	--                                      changes size with the value, so the
	--                                      slice geometry and the texture are
	--                                      byte-stable from 1% to 100% and a value
	--                                      change costs ZERO extra writes.
	--   the TRACK node (hint `barTrack`)   the end-caps and the centrepiece. They
	--                                      have to survive EVERY percent (the
	--                                      fantasy 'jewelled cap' idiom), so they
	--                                      are anchored to the track and never
	--                                      inside the window — exactly what rs-m4's
	--                                      consequences say.
	--
	-- A FLAT bar builds NOTHING here: with no `barFill` recipe the fill node's own
	-- `facet-slot-barFill` rules paint it solid, which is what a progress bar is
	-- when no package skins it (R9's OWN_PAINT_SLOTS).
	--
	-- NOT ONE PAINT PROPERTY IS WRITTEN IN NATIVE MODE, for rs-m2's reason: a value
	-- written before the instance joins the styled tree survives and permanently
	-- defeats the rule that starts matching later. The window frame is deliberately
	-- untagged — it is a MASK, not paint — and the `Frame default` rule every
	-- package emits already holds it transparent.
	local function barPaintFor(child: ImageLabel, plan: any, contentId: string?)
		child.BackgroundTransparency = 1
		child.Image = contentId or plan.contentId
		if plan.sliced and plan.sliceCenter ~= nil then
			child.ScaleType = Enum.ScaleType.Slice
			child.SliceCenter =
				Rect.new(plan.sliceCenter.x0, plan.sliceCenter.y0, plan.sliceCenter.x1, plan.sliceCenter.y1)
			child.SliceScale = plan.sliceScale
		else
			child.ScaleType = Enum.ScaleType.Stretch
		end
		child.ImageColor3 = toColor3(plan.tint)
		child.ImageTransparency = plan.transparency
	end

	local function applyBox(instance: GuiObject, box: any)
		instance.AnchorPoint = Vector2.new(box.anchor.x, box.anchor.y)
		instance.Position =
			UDim2.new(box.position.xScale, box.position.xOffset, box.position.yScale, box.position.yOffset)
		instance.Size = UDim2.new(box.size.xScale, box.size.xOffset, box.size.yScale, box.size.yOffset)
	end

	-- THE TRACK THIS FILL BELONGS TO, found through the Facet PATH.
	--
	-- Live-found (2026-07-25, first drive): `instance.Parent` is NOT the track.
	-- This target renders a FLAT instance tree — every node is a direct child of
	-- its root with an absolute rect — so a node's DataModel parent says nothing
	-- about its layout parent. Reading AbsoluteSize off it returned the ScreenGui's
	-- size on one screen and 0 on another, and the art was sized from whichever it
	-- happened to be. The path IS the containment relation here, so the walk goes
	-- up it and stops at the node that DECLARED `barTrack` — which also means a
	-- control may nest its fill as deep as it likes.
	local function barTrackHandleOf(handle: any): any?
		local path = handle.path
		while true do
			local cut = string.match(path, "^(.*)/[^/]+$")
			if cut == nil or cut == "" then
				return nil
			end
			path = cut
			local candidate = handlesByPath[path]
			local hint = if candidate ~= nil and type(candidate.decorationHint) == "table"
				then candidate.decorationHint.slot
				else nil
			if hint == "barTrack" then
				return candidate
			end
		end
	end

	-- the whole TRACK's extent on the driven axis. The art inside the window is
	-- pinned to it, which is the property rs-m4 measured ("fill stays 300px wide
	-- at every pct") and the reason a percent change re-derives nothing.
	-- THE TRACK'S EXTENT IN THE SPACE THE ART IS WRITTEN IN (platform verifier F6).
	--
	-- The fill art is a FULL-TRACK image inside a clip window (rs-m4), so it is
	-- sized in OFFSET px — and an offset is interpreted in the node's own,
	-- possibly SCALED, coordinate space. `AbsoluteSize` is the opposite: already
	-- multiplied by every ancestor UIScale. Reading one and writing the other
	-- double-applies the scale, so under the pressed dip (0.985) or the ten-foot
	-- focus lift (1.05) — never mind an ancestor UIScale = 2 — the fill art was
	-- wider than the track it is supposed to be a full-width copy of.
	--
	-- The SOLVER's px is the right number and the framework already has it:
	-- `windowRect` is exactly what `setRect` wrote, in unscaled px, which is the
	-- same space the offsets are written in. AbsoluteSize stays as the fallback
	-- for the one case the solved rect cannot answer (a track the adapter did not
	-- lay out), and the AbsoluteSize watch stays because it is still the cheapest
	-- signal that the track changed at all.
	local function barTrackExtent(handle: any, vertical: boolean): number
		local track = barTrackHandleOf(handle)
		if track == nil or not track.instance:IsA("GuiObject") then
			return 0
		end
		local rect = track.windowRect
		if type(rect) == "table" then
			return if vertical then rect.h else rect.w
		end
		local size = (track.instance :: GuiObject).AbsoluteSize
		return if vertical then size.Y else size.X
	end

	local function destroyBarFill(handle: any)
		if handle.barWindow == nil then
			return
		end
		for _, key in { "barConn", "barWindowConn" } do
			if handle[key] ~= nil then
				handle[key]:Disconnect()
				handle[key] = nil
			end
		end
		-- the identity `reconnectOnChange` stamped `barConn` against (task CONN):
		-- clearing it with the connection it belongs to is not load-bearing (a nil
		-- `barConn` already short-circuits the comparison), but leaving a stale
		-- path on a handle that no longer has the connection it names is the kind
		-- of drift this file's own census exists to catch
		handle.barConnPath = nil
		handle.barFillExtent = nil
		instancesByPath[handle.path .. "/" .. chrome_slots.BAR_WINDOW_NAME] = nil
		instancesByPath[handle.path .. "/" .. chrome_slots.BAR_FILL_NAME] = nil
		handle.barWindow:Destroy() -- the art is its child and goes with it
		handle.barWindow, handle.barFill = nil, nil
		handle.barFillKey = nil
		chromeState.noteDestroyed("barFill")
	end

	-- resize the art to the live track. A RESIZE, never a value change: the guard
	-- below makes every call a no-op unless the TRACK's own extent moved, so a
	-- percent sweep costs zero writes here however often it fires.
	--
	-- LIVE-FOUND (2026-07-25, first drive): the chrome can be built BEFORE the
	-- node joins its track, so the parent lookup returned nothing, the art was
	-- sized 0 and — because the engine never decodes an image with no area — the
	-- grace timer then reported its asset as FAILED and the whole slot fell back.
	-- The watch is therefore attached here, on the first call that finds a parent,
	-- rather than once at build against an instance that may not exist yet.
	local function refreshBarFillExtent(handle: any)
		if handle.barFill == nil then
			return
		end
		-- RECONNECT ON IDENTITY CHANGE (task CONN, Finding 1). This function can
		-- run many times inside one life (every percent sweep re-enters it, "a
		-- percent sweep costs zero writes here however often it fires" below), so
		-- an unconditional disconnect-and-remake here would churn a connection on
		-- every call for no reason — the `== nil` guard this replaces existed for
		-- exactly that, but for that same reason it could never rewire when the
		-- watched TRACK actually changed underneath it (a park->adopt recycle:
		-- `handle.path` moves, `barTrackHandleOf` resolves a different sibling,
		-- and the stale connection keeps watching the PRIOR track's AbsoluteSize
		-- forever, missing the current one's resizes). `handle.path` is the
		-- identity: unchanged short-circuits to the guard's old behaviour
		-- (connect once, keep retrying every call until a track exists), changed
		-- disconnects the stale watch before wiring the current track's.
		reconnectOnChange(handle, "barConn", "barConnPath", handle.path, function()
			local track = barTrackHandleOf(handle)
			if track ~= nil and track.instance:IsA("GuiObject") then
				return (track.instance :: GuiObject):GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					refreshBarFillExtent(handle)
				end)
			end
			return nil
		end)
		local direction = chrome_slots.barDirectionOf(chromeState.package(), "barFill")
		local px = barTrackExtent(handle, chrome_slots.isVerticalBar(direction))
		if handle.barFillExtent == px then
			return
		end
		handle.barFillExtent = px
		applyBox(handle.barFill, chrome_slots.barFillBox(direction, px))
	end

	local function buildBarFill(handle: any, plan: any, key: string)
		local instance = handle.instance
		local window = Instance.new("Frame")
		window.Name = chrome_slots.BAR_WINDOW_NAME
		window.Active = false -- a mask is never a hit target
		window.Selectable = false
		window.BorderSizePixel = 0
		window.ClipsDescendants = true -- rs-m4's winner, and the whole mechanism
		window.AnchorPoint = Vector2.zero
		window.Position = UDim2.fromScale(0, 0)
		window.Size = UDim2.fromScale(1, 1) -- the solved percent rect IS the window
		window.ZIndex = 1
		if not nativeMode then
			-- native mode leaves it to the `Frame default` rule: an untagged mask
			-- must never carry a pre-join paint write (rs-m2)
			window.BackgroundTransparency = 1
		end
		local art = Instance.new("ImageLabel")
		art.Name = chrome_slots.BAR_FILL_NAME
		art.Active = false
		art.Selectable = false
		art.BorderSizePixel = 0
		art.ZIndex = 1
		-- TAG BEFORE PARENT (rs-m2): the rule has to be matching the instant the
		-- instance joins the styled tree or a later state rule can never win
		if plan.tag ~= nil then
			CollectionService:AddTag(art, plan.tag)
		end
		if not nativeMode then
			barPaintFor(art, plan)
		end
		art.Parent = window
		window.Parent = instance
		handle.barWindow, handle.barFill = window, art
		handle.barFillKey = key
		instancesByPath[handle.path .. "/" .. chrome_slots.BAR_WINDOW_NAME] = window
		instancesByPath[handle.path .. "/" .. chrome_slots.BAR_FILL_NAME] = art
		chromeState.noteCreated("barFill")
		-- the WINDOW's own resize is the reliable first signal: it is this node's
		-- solved rect, so it fires as soon as the tree is laid out — which is also
		-- the first moment the track exists to be measured. `destroyBarFill`
		-- always precedes this call when actually rebuilding (line below), so
		-- `barWindowConn` is already nil here — `reconnect` is defense-in-depth
		-- against a future caller that forgets that pairing (task CONN).
		reconnect(handle, "barWindowConn", function()
			return window:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				refreshBarFillExtent(handle)
			end)
		end)
		refreshBarFillExtent(handle)
		watchChromeAsset(art, plan.assetName)
	end

	-- the caps and the centrepiece, on the TRACK. Rebuilt rather than repainted
	-- when the recipe's SHAPE changes, for the same reason a layer ladder is: the
	-- tags are what the rules key on and the px boxes are what the geometry is.
	local function destroyBarOrnaments(handle: any)
		if handle.barOrnaments == nil then
			return
		end
		for _, entry in handle.barOrnaments do
			instancesByPath[handle.path .. "/" .. entry.instance.Name] = nil
			entry.instance:Destroy()
			chromeState.noteDestroyed(entry.slot)
		end
		handle.barOrnaments = nil
		handle.barOrnamentKey = nil
	end

	local function buildBarOrnaments(handle: any, key: string)
		local package = chromeState.package()
		local instance = handle.instance
		local direction = chrome_slots.barDirectionOf(package, "barFill")
		local built: { any } = {}
		local function add(slot: string, plan: any, box: any, contentId: string?, extraTag: string?)
			local child = Instance.new("ImageLabel")
			child.Name = box.name
			child.Active = false -- input-transparent ornaments (rs-m3)
			child.Selectable = false
			child.BorderSizePixel = 0
			child.ZIndex = 2 -- above the window, so a cap survives every percent
			applyBox(child, box)
			if plan.tag ~= nil then
				CollectionService:AddTag(child, plan.tag)
			end
			if extraTag ~= nil then
				CollectionService:AddTag(child, extraTag)
			end
			if not nativeMode then
				barPaintFor(child, plan, contentId)
			end
			child.Parent = instance
			instancesByPath[handle.path .. "/" .. box.name] = child
			table.insert(built, { instance = child, slot = slot, plan = plan, contentId = contentId })
			chromeState.noteCreated(slot)
		end
		local capPlan = chromeState.planFor("barCap")
		if capPlan ~= nil then
			local recipe = (package.chrome :: any).barCap
			local size = chrome_slots.barOrnamentSize(recipe)
			for _, which in chrome_slots.BAR_ENDS do
				local named = chrome_slots.barCapAssetOf(recipe, which)
				local own = if named ~= nil and named ~= capPlan.assetName
					then ((package.assets :: any)[named] or {}).contentId
					else nil
				add(
					"barCap",
					capPlan,
					chrome_slots.barCapBox(which, direction, size),
					own,
					-- the second tag exists only where that end declared its OWN
					-- art; a tag with no rule is a selector that says nothing
					if own ~= nil then chrome_slots.barCapTagFor(which) else nil
				)
			end
		end
		local centerPlan = chromeState.planFor("barCenter")
		if centerPlan ~= nil then
			add(
				"barCenter",
				centerPlan,
				chrome_slots.barCenterBox(chrome_slots.barOrnamentSize((package.chrome :: any).barCenter)),
				nil,
				nil
			)
		end
		handle.barOrnaments = if #built > 0 then built else nil
		handle.barOrnamentKey = if #built > 0 then key else nil
	end

	-- the bar's fallback flip, one instance at a time. Tag-driven natively (the
	-- `Chrome — <slot> fallback` rules a nine-slice plan already emits); explicit
	-- on a target with no sheet.
	local function syncBarFallback(handle: any)
		local function flip(child: ImageLabel, slot: string, plan: any, contentId: string?)
			local want, muted, changed = syncChromeFallbackTags(child, slot, plan.assetName, true)
			if not changed or nativeMode then
				return
			end
			barPaintFor(child, plan, contentId)
			if muted then
				child.ImageTransparency = 1
			end
			if want then
				child.BackgroundColor3 = chromeFillOf[slot] or toColor3(style.colors.accent)
				child.BackgroundTransparency = 0
			end
		end
		if handle.barFill ~= nil then
			local plan = chromeState.planFor("barFill")
			if plan ~= nil then
				flip(handle.barFill, "barFill", plan)
			end
		end
		for _, entry in handle.barOrnaments or {} do
			flip(entry.instance, entry.slot, entry.plan, entry.contentId)
		end
	end

	-- ===== TOGGLE IMAGE SLOTS =================================
	--
	-- The knob-and-track predates this stage and stays exactly where it was: the
	-- `togglePalette` contract is the flat truth, the knob's TRAVEL is solver-free
	-- adapter geometry that art never touches, and a package with no toggle slots
	-- renders today's palette-true switch byte for byte.
	--
	-- What v2 adds is ART ON THOSE TWO INSTANCES. Both are ImageLabels now (a
	-- Frame cannot show a picture and an ImageLabel with no Image is a Frame), and
	-- both are DIRECT CHILDREN of the Toggle button — the knob moved out of the
	-- track for exactly that reason. Every per-state rule the package emits is a
	-- child combinator off the interactive node (`:Hover > .facet-chrome-toggleKnob`),
	-- and a knob nested one level deeper could never be reached by one. Its
	-- absolute travel is unchanged: the track's left edge is `width - 56`, so the
	-- knob's two stops are `width - 54` and `width - 34` written against the
	-- button instead of against the track.
	-- THE TOGGLE'S REAL CHROME CHILDREN, ON AND OFF (director round 6, 2026-07-25).
	--
	-- THE DEFECT, measured live and not what it looked like. The glossy toggle
	-- track rendered as a cluster of circles and diamonds, which reads exactly
	-- like a nine-slice whose corner caps overlap — the track art is 72x32 with a
	-- 14px border and the switch paints it into 44x24, so 14 + 14 of cap in 24px
	-- of height. That diagnosis is FALSE, and the isolating probe says so: at
	-- 44x24, 44x8 and 20x8 the same art with SliceScale 1 renders as a clean
	-- capsule, identical to the same art at the exactly-fitting scale. **Roblox
	-- clamps overlapping slice caps itself.**
	--
	-- What produces the artifact is the one variable the probe changed next: a
	-- REAL `UICorner` child on a `ScaleType = Slice` ImageLabel. The engine
	-- rounds each of the NINE PATCHES independently, so the four corner patches
	-- become diamonds and the two middle patches become lenses — the picture the
	-- director reported, reproduced and removed by that one property.
	--
	-- WHY IT SURVIVED R9. "The image is the element" turns off a skinned node's
	-- fill, corner and hairline through PHANTOM `::UICorner` / `::UIStroke`
	-- rules — and a REAL child of that class SUPPRESSES the phantom (the recorded
	-- StyleSheet truth). The toggle is the one slot whose chrome is real children:
	-- `buildToggleVisual` gives the track and knob a `UICorner` and a `Hairline`
	-- so the PALETTE-TRUE switch has its pill and its edge. No rule can reach
	-- them, so the suppression that covers every other skinned slot could not
	-- cover this one.
	--
	-- So the adapter does it, in BOTH modes, because in native mode there is no
	-- rule that could. It is inside the sanctioned exception this manifest
	-- already declares (the toggle knob-track assembly's own real children), and
	-- it RESTORES on unskin: a package with no toggle recipe still gets today's
	-- palette-true switch, pill and hairline byte for byte.
	local function setTogglePartChrome(target: Instance, skinned: boolean)
		for _, child in target:GetChildren() do
			if child:IsA("UICorner") then
				(child :: UICorner).CornerRadius = if skinned then UDim.new(0, 0) else UDim.new(0, style.radii.pill)
			elseif child:IsA("UIStroke") and child.Name == "Hairline" then
				local stroke = child :: UIStroke
				stroke.Thickness = if skinned then 0 else style.strokes.hairline
				stroke.Transparency = if skinned then 1 else style.extra.hairlineOpacity
			end
		end
	end

	local function syncToggleArt(handle: any)
		local parts = { toggleTrack = handle.track, toggleKnob = handle.knob }
		for slot, target in parts do
			if target == nil then
				continue
			end
			local plan = chromeState.planFor(slot)
			-- the RESTING picture natively (the rules own every state); the
			-- VALUE-resolved one on a target with no sheet, where nothing else can
			-- swap it. One variant map, both paths — never two state machines.
			local contentId = if plan == nil
				then nil
				elseif nativeMode then plan.contentId
				else chrome_slots.variantContentFor(plan.variants, { selected = handle.toggleOn == true })
					or plan.contentId
			local live = (handle.toggleArt or {})[slot]
			if plan ~= nil and live == contentId then
				continue
			end
			handle.toggleArt = handle.toggleArt or {}
			handle.toggleArt[slot] = contentId
			local slotTag = chrome_slots.tagFor(slot)
			local skinTag = chrome_slots.skinnedTagFor(slot)
			if plan == nil then
				-- back to the palette-true switch: the tags go, the pill and the
				-- hairline come back, and so does any image the fallback path wrote
				CollectionService:RemoveTag(target, slotTag)
				CollectionService:RemoveTag(target, skinTag)
				setTogglePartChrome(target, false)
				if not nativeMode then
					(target :: any).Image = ""
				end
				continue
			end
			-- the ART is the element (R9): the same `facet-skinned-<slot>` tag every
			-- other skinned node carries, so ONE suppression rule set turns off the
			-- pill fill, its corner and its hairline under the picture
			if not CollectionService:HasTag(target, slotTag) then
				CollectionService:AddTag(target, slotTag)
			end
			if not CollectionService:HasTag(target, skinTag) then
				CollectionService:AddTag(target, skinTag)
			end
			-- ...and the half no rule can reach: the REAL pill and hairline this
			-- assembly was built with (see setTogglePartChrome)
			setTogglePartChrome(target, true)
			if not nativeMode then
				barPaintFor(target :: any, plan, contentId)
			end
			watchChromeAsset(target :: any, plan.assetName)
		end
	end

	-- what the ornament ladder currently DEPENDS on. Empty means "this package
	-- declares no caps and no centrepiece", which is what a flat bar is.
	local function barOrnamentKeyOf(): string
		local package = chromeState.package()
		local parts: { string } = { chrome_slots.barDirectionOf(package, "barFill") }
		for _, slot in { "barCap", "barCenter" } do
			local plan = chromeState.planFor(slot)
			if plan == nil then
				continue
			end
			local recipe = ((if type(package) == "table" then package.chrome else nil) or {})[slot]
			local size = chrome_slots.barOrnamentSize(recipe)
			table.insert(parts, `{slot}={plan.contentId}:{size.w}x{size.h}`)
			if slot == "barCap" then
				for _, which in chrome_slots.BAR_ENDS do
					table.insert(parts, `{which}={tostring(chrome_slots.barCapAssetOf(recipe, which))}`)
				end
			end
		end
		return if #parts > 1 then table.concat(parts, "|") else ""
	end

	-- ===== rung-2 PER-STATE ART ==================
	--
	-- Rung 1 swaps a slot's picture with RULES, because the decoration carries
	-- the package's tag. A rung-2 override is untagged ON PURPOSE — that is the
	-- opt-out rule made concrete, and it is also why no rule can reach it. So the
	-- adapter picks the state art itself, from the SAME normalized variant map
	-- `themes.normalizeVariant` writes for a recipe (one grammar, both rungs) and
	-- in the SAME precedence the emitted cascade produces
	-- (chrome_slots.VARIANT_PRECEDENCE), or an overridden control would behave
	-- unlike its themed neighbour in exactly the states this stage is about.
	local function overrideVariantFlags(handle: any): any
		local instance: any = handle.instance
		local guiState: string? = nil
		pcall(function()
			guiState = tostring(instance.GuiState)
		end)
		local interactable: any = nil
		pcall(function()
			interactable = instance.Interactable
		end)
		return {
			disabled = guiState == "Enum.GuiState.NonInteractable" or interactable == false,
			pressed = guiState == "Enum.GuiState.Press",
			hover = guiState == "Enum.GuiState.Hover",
			error = handle.errorState == true,
			selected = handle.isSelected == true,
		}
	end

	local function applyOverrideVariantArt(handle: any)
		local deco = handle.chrome
		local variants = handle.chromeOverrideVariants
		if deco == nil or variants == nil then
			return
		end
		local flags = overrideVariantFlags(handle)
		local contentId = chrome_slots.variantContentFor(variants, flags)
		if contentId ~= nil and deco.Image ~= contentId then
			-- an explicit write on an UNTAGGED instance: no rule matches it, so
			-- there is nothing here to defeat (rs-m2's condition), and the write
			-- is the documented opt-out rather than dual authority
			deco.Image = contentId
		end
		-- THE ACCESSIBILITY FLOOR (arch verifier F3). Rung 1 dims a
		-- disabled decoration through `:NonInteractable > .<tag>`; this decoration
		-- is untagged by construction, so that rule can never reach it and the
		-- adapter has to write the SAME number itself — otherwise a map that omits
		-- `disabled` renders at full opacity beside a themed sibling at 0.4.
		local resting = handle.chromeOverrideRest or 0
		local wanted = chrome_slots.variantOpacityFor(flags, resting, style.extra.disabledContentOpacity)
		if deco.ImageTransparency ~= wanted then
			deco.ImageTransparency = wanted
		end
	end

	local function syncOverrideVariants(handle: any, plan: any)
		local wanted = if plan ~= nil and plan.localOverride == true then plan.variants else nil
		if wanted == nil then
			if handle.chromeOverrideConn ~= nil then
				handle.chromeOverrideConn:Disconnect()
				handle.chromeOverrideConn = nil
			end
			handle.chromeOverrideVariants = nil
			handle.chromeOverrideRest = nil
			return
		end
		handle.chromeOverrideVariants = wanted
		-- the plan's RESTING transparency, kept beside the map so the disabled
		-- floor has something to return to (arch verifier F3)
		handle.chromeOverrideRest = plan.transparency or 0
		if handle.chromeOverrideConn == nil then
			-- GuiState is the engine's own read-only interaction state (m9), and
			-- it is what the rung-1 :Hover/:Press pseudos read too — so both rungs
			-- are keyed off one fact rather than two state machines
			local ok, conn = pcall(function()
				return (handle.instance :: any):GetPropertyChangedSignal("GuiState"):Connect(function()
					applyOverrideVariantArt(handle)
				end)
			end)
			handle.chromeOverrideConn = if ok then conn else nil
		end
		applyOverrideVariantArt(handle)
	end

	-- focusArtHost(handle) -> the instance that DRAWS this node's plate, or nil
	-- when nothing does. The focus ring and the focus glow hang off it instead of
	-- off the node (director fix round 2026-07-25) so they hug the art rather than
	-- the padded solved rect.
	--
	-- WHICH instance is a PURE decision (`chrome_slots.focusArtLayer`): the one
	-- nine-slice decoration, or the back-most FULL-BLEED layer of a stack — a
	-- corner ornament or an overhanging plaque is a detail ON the plate, and a
	-- ring around one of those would be worse than the defect.
	local function focusArtHost(handle: any): GuiObject?
		local deco = handle.chrome
		if deco ~= nil and deco.Parent ~= nil then
			return deco
		end
		local stack = handle.chromeStack
		if stack == nil then
			return nil
		end
		-- the entries are in creation order, which IS array order, so the layer
		-- list this builds is already the plan's order
		local layers: { any } = {}
		local seen: { [number]: boolean } = {}
		for _, entry in stack do
			if not seen[entry.layer.index] then
				seen[entry.layer.index] = true
				table.insert(layers, entry.layer)
			end
		end
		local index = chrome_slots.focusArtLayer({ slot = handle.chromeStackSlot, layers = layers })
		if index == nil then
			return nil
		end
		for _, entry in stack do
			if entry.layer.index == index and entry.instance.Parent ~= nil then
				-- a MASKED layer's drawn shape is the wrapper's, not the art's: the
				-- art is full-bleed inside it and a ring around that would trace the
				-- rectangle the mask exists to hide
				return entry.mask or entry.instance
			end
		end
		return nil
	end

	local syncChromeInner: (handle: any) -> ()

	-- THE FOCUS VISUAL FOLLOWS THE ART (director fix round 2026-07-25). The ring
	-- and the glow now hang off the instance that DRAWS the plate, so a package
	-- install that creates or destroys that instance under a focused node has to
	-- re-place them — otherwise a swap leaves the ring on a decoration that no
	-- longer exists, or on the node after art appeared. One wrapper rather than a
	-- hook at each of syncChrome's early returns.
	function syncChrome(handle: any)
		syncChromeInner(handle)
		if focusedHandles[handle] ~= nil then
			ctx.setFocusVisual(handle, true, focusedHandles[handle])
		end
	end

	function syncChromeInner(handle: any)
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return
		end
		local slot = chromeSlotOf(handle)
		local override = chromeOverrideOf(handle)
		local plan = if slot ~= nil then chromeState.planFor(slot, override) else nil
		-- A LAYERED recipe (planFor returns nil for one, which is what keeps every
		-- flat and nine-slice package byte-identical). A rung-2 override beats it:
		-- an explicit local value opts this node out of the theme, ladder included.
		local stack = if slot ~= nil and not (plan ~= nil and plan.localOverride)
			then chromeState.layerPlanFor(slot)
			else nil
		local deco: ImageLabel? = handle.chrome
		-- WHEN A DECORATION HAS TO BE REBUILT rather than repainted. Its TAG is
		-- what the rules key on, so anything that changes the tag is a rebuild: a
		-- slot that changed identity (a plain row that became selectable), or a
		-- per-view override appearing or disappearing (an overridden decoration
		-- carries no slot tag at all). A themed CONTENT ID change is NOT a
		-- rebuild in native mode — the package's `Image` rule repaints it in
		-- place, which is the whole point of tag-driven paint — but it is one on
		-- a path that explicit-wrote the image, or the stale ID would stand.
		local writesImage = (not nativeMode) or (plan ~= nil and plan.localOverride)
		local rebuild = plan == nil
			or handle.chromeSlot ~= slot
			or handle.chromeLocalOverride ~= plan.localOverride
			or (writesImage and handle.chromeContentId ~= plan.contentId)
		if deco ~= nil and rebuild then
			chromeState.noteDestroyed(handle.chromeSlot)
			instancesByPath[handle.path .. "/" .. chrome_slots.DECORATION_NAME] = nil
			destroyChromeText(handle)
			deco:Destroy()
			-- the slot shadow is a CHILD of the decoration when one exists, so it
			-- has already been destroyed with it; drop the reference (and the
			-- census entry) before anything tries to re-parent a dead instance
			dropChromeShadow(handle)
			deco, handle.chrome, handle.chromeSlot = nil, nil, nil
			handle.chromeContentId, handle.chromeLocalOverride = nil, nil
			syncTags(handle) -- the skinned tag goes with the decoration
		end
		-- A HINTED NODE'S OWN IDENTITY, both halves, BEFORE the decoration branch
		-- can return.
		--
		-- THE BUG THIS SHAPE EXISTS FOR (live capture 2026-07-25, glossy): a
		-- hinted node has NO public `surface` — that is the entire point, it must
		-- not borrow a surface's treatment — so `applySurface` never runs for it
		-- and never calls syncTags. And when the installed package declares no
		-- recipe for its slot, `plan` is nil and this function used to RETURN
		-- below before reaching the only other syncTags call (the one that rides
		-- decoration creation). Net effect: `facet-slot-sliderThumb` never landed,
		-- nothing matched, and the Frame fell to the `Frame default` transparency
		-- rule — an invisible thumb and rail, with the accent fill floating alone.
		--
		-- It worked under Parchment purely by accident: Parchment DOES declare
		-- slider recipes, so a decoration got created and dragged the tag sync in
		-- behind it. A tag whose application depends on whether some OTHER
		-- package feature is in use is not applied at all.
		--
		-- Order-independent by construction: the tag comes from the hint, which
		-- is set at create, so an install that happens after mount cannot miss it
		-- (and `setThemePackage` re-runs this for every handle anyway).
		local hintedSlot = if type(handle.decorationHint) == "table" then handle.decorationHint.slot else nil
		if hintedSlot ~= nil and hintedSlot ~= chrome_slots.NO_SLOT then
			-- native half: classifyTags decides which tag (if any) the slot earns
			syncTags(handle)
		end
		if slot ~= nil then
			-- fallback half: the explicit fill/corner/hairline. Never behind the
			-- decoration branch either, for exactly the same reason.
			applySlotNativePaint(instance, slot, handle)
		end
		-- SEMANTIC ICONS, ahead of every early return below for the
		-- same reason the value displays are: a node may request an icon and have
		-- no decoration recipe at all (a flat theme's stepper), and a picture whose
		-- application depended on some other package feature being in use would
		-- not be applied.
		syncIconArt(handle)
		-- ----- THE LAYER LADDER ------------------------------
		-- Rebuilt, never repainted in place, when the ladder's SHAPE changes:
		-- the tags are what the rules key on and the boxes are what the geometry
		-- keys on, so a different stack is a different set of children.
		if handle.chromeStack ~= nil then
			local staleSlot = handle.chromeStackSlot ~= slot
			local staleShape = stack == nil or handle.chromeStackSignature ~= stackSignature(slot :: string, stack)
			if staleSlot or staleShape then
				destroyChromeStack(handle)
				if stack == nil and handle.chrome == nil then
					handle.chromeSlot = nil
					syncTags(handle) -- the skinned tag goes with the ladder
				end
			end
		end
		-- ----- IMAGE VALUE DISPLAYS --------------------------
		-- Ahead of every early return below, because a value display's chrome is
		-- not a decoration on THIS node: a bar's caps hang off the track whether or
		-- not the track itself is skinned, and a toggle's art rides two instances
		-- the adapter has always built. The Step 3.5 fix round's lesson, applied at
		-- the seam: a tag whose application depends on some other package feature
		-- being in use is not applied at all.
		if handle.track ~= nil then
			syncToggleArt(handle)
		end
		if slot ~= "barFill" and handle.barWindow ~= nil then
			destroyBarFill(handle) -- the node stopped being a bar fill
		end
		if slot ~= "barTrack" and handle.barOrnaments ~= nil then
			destroyBarOrnaments(handle)
		end
		if slot == "barTrack" then
			local key = barOrnamentKeyOf()
			if handle.barOrnamentKey ~= key then
				destroyBarOrnaments(handle)
				if key ~= "" then
					buildBarOrnaments(handle, key)
				end
			end
			syncBarFallback(handle)
		elseif slot == "barFill" then
			-- THE FILL IS CLIPPED, NOT DECORATED (rs-m4): its art lives inside an
			-- adapter-owned window at FULL TRACK SIZE rather than as this node's
			-- own full-bleed decoration, so it takes this branch and never the
			-- nine-slice one below.
			local key = if plan ~= nil
				then `{plan.contentId}#{chrome_slots.barDirectionOf(chromeState.package(), "barFill")}`
				else ""
			if handle.barFillKey ~= key then
				destroyBarFill(handle)
				if plan ~= nil then
					buildBarFill(handle, plan, key)
				end
				-- the skinned tag rides the FILL NODE, exactly as it does for a
				-- nine-slice or a layered one, so the same suppression rule set
				-- turns off the solid accent block under the art
				handle.chromeSlot = if plan ~= nil then slot else nil
				syncTags(handle)
			end
			if plan ~= nil then
				applySkinnedSuppression(instance, true, handle)
				syncBarFallback(handle)
			end
			syncChromeShadow(
				handle,
				slot,
				if plan ~= nil then handle.barFill else instance,
				chromeState.shadowFor(slot)
			)
			return
		end
		if stack ~= nil then
			if handle.chromeStack == nil then
				buildChromeStack(handle, slot :: string, stack)
				-- THE IMAGE IS THE ELEMENT (R9): the same `facet-skinned-<slot>` tag
				-- a nine-slice node carries, so one suppression rule set covers both
				handle.chromeSlot = slot
				syncTags(handle)
			end
			applySkinnedSuppression(instance, true, handle)
			-- the lift rides above the WHOLE ladder; the stack's own contentInsets
			-- box it exactly as a nine-slice recipe's do
			syncChromeText(handle, nil, stack, chrome_slots.liftZIndexFor(stack))
			-- the shadow hangs off the NODE for a stack: the art is N children and
			-- the back layer is full-bleed over the same rect the node solved, so
			-- the node is the shape that should cast it (and a plaque's overhang
			-- must not drag the shadow outside the control)
			syncChromeShadow(handle, slot, instance, chromeState.shadowFor(slot :: string))
			syncChromeStackFallback(handle, slot :: string)
			return
		end
		if plan == nil then
			-- a NATIVE recipe still gets its slot shadow, on the node itself
			syncChromeShadow(handle, slot, instance, if slot ~= nil then chromeState.shadowFor(slot) else nil)
			return
		end
		if deco == nil then
			local made = Instance.new("ImageLabel")
			made.Name = chrome_slots.DECORATION_NAME
			made.Active = false -- never a hit target: hit geometry is the node's
			made.Selectable = false -- and never engine-selectable
			made.BorderSizePixel = 0
			made.AnchorPoint = Vector2.zero
			made.Position = UDim2.fromScale(0, 0)
			made.Size = UDim2.fromScale(1, 1) -- full bleed: the skin IS the node
			-- below anything the node's own content draws. The SAME band the layer
			-- ladder occupies (`chrome_slots.layerZIndexFor`) — named rather than
			-- restated, because a ruling that lives at one call site is the defect
			-- this constant exists to close.
			made.ZIndex = chrome_slots.DECORATION_Z_INDEX
			-- RUNG 2 OF THE LADDER (per-view override). A locally overridden
			-- decoration is deliberately NOT tagged, so the package's `Image`
			-- rule can never reach it, and the adapter explicit-writes the image
			-- properties instead — in BOTH modes. That is the standing opt-out
			-- rule made concrete: an explicit local value opts this node out of
			-- theme changes, visibly and on purpose. Everything else about the
			-- node (its geometry, its insets, its shadow) still follows the theme.
			local writeImage = writesImage
			if not nativeMode then
				assertBespokePaint("BackgroundTransparency")
				made.BackgroundTransparency = 1
			end
			if writeImage then
				made.Image = plan.contentId
				if plan.sliced and plan.sliceCenter ~= nil then
					made.ScaleType = Enum.ScaleType.Slice
					made.SliceCenter =
						Rect.new(plan.sliceCenter.x0, plan.sliceCenter.y0, plan.sliceCenter.x1, plan.sliceCenter.y1)
					made.SliceScale = plan.sliceScale
				else
					-- whole image: no slice geometry at all (a slice centre on a
					-- fixed-size token smears its centre pixel across the middle)
					made.ScaleType = Enum.ScaleType.Stretch
				end
				made.ImageColor3 = toColor3(plan.tint)
				made.ImageTransparency = plan.transparency
			end
			if plan.tag ~= nil then
				CollectionService:AddTag(made, plan.tag)
			end
			made.Parent = instance
			deco = made
			handle.chrome = made
			handle.chromeSlot = slot
			handle.chromeContentId = plan.contentId
			handle.chromeLocalOverride = plan.localOverride
			-- addressable by path, so the scenario's style-authority probe can
			-- ask GetStyled about a decoration the way it asks about any node
			instancesByPath[handle.path .. "/" .. chrome_slots.DECORATION_NAME] = made
			chromeState.noteCreated(slot :: string)
			if not plan.localOverride then
				watchChromeAsset(made, plan.assetName)
			end
			-- THE IMAGE IS THE BUTTON: the plate, the corner and the hairline stop
			-- drawing under the art. Native mode does it with the package's
			-- `Skinned — <slot>` rules (via the tag syncTags now emits); fallback
			-- mode writes the same three suppressions below.
			syncTags(handle)
		end
		-- FULL BLEED MEANS THE NODE'S BOX, NOT ITS CONTENT BOX (director report
		-- 2026-07-27, Compact Pointer: "text overflowing each row on the left").
		--
		-- The decoration is created at `Size = fromScale(1, 1)` with the comment
		-- "the skin IS the node" — but a scale size resolves against the parent's
		-- CONTENT box, and `UIPadding` silently shrinks that. Every skinned host
		-- that carries one therefore drew its plate INSIDE the padding while the
		-- solver laid the node's content out against the node's own rect, so the
		-- two disagreed by exactly the padding.
		--
		-- Measured live on a playlist row: the host is x=16 w=357 with a 12px
		-- UIPadding, so the plate landed at x=28 while the first cell's text sat at
		-- x=26 — the text hanging 2px off the left edge of its own plate, which is
		-- what the capture shows. It is the measure-versus-paint family again, with
		-- the paint side moved by an engine object the solver cannot see.
		--
		-- Re-applied on EVERY sync because the host's padding is rewritten per
		-- solve (`commit_walks.padding` re-derives a Button's inset from the live theme),
		-- so a theme swap changes the number this compensates for.
		applyFullBleed(instance, deco :: ImageLabel)
		-- run on EVERY sync, not only at creation: several construction paths
		-- (applySurface, the TextField branch's own hairline()) paint a plate
		-- after the decoration already exists, and a re-suppression is idempotent
		applySkinnedSuppression(instance, true, handle)
		syncChromeText(handle, deco :: ImageLabel, plan, 1)
		syncChromeShadow(handle, slot, deco, chromeState.shadowFor(slot :: string))
		-- rung-2 PER-STATE ART. An overridden
		-- decoration is deliberately untagged, so no rule can swap its picture:
		-- the adapter watches the node's own states and writes the art itself.
		syncOverrideVariants(handle, plan)
		local decoration = deco :: ImageLabel
		-- a rung-2 override is untagged by design (no rule may reach its picture),
		-- so it takes neither fallback tag
		local wantFallback, muted, changed =
			syncChromeFallbackTags(decoration, slot :: string, plan.assetName, not plan.localOverride)
		if changed and not nativeMode then
			applyChromeFallbackWrites(decoration, slot :: string, wantFallback, muted, plan)
		end
	end

	-- chromePathChildEntries(handle) -> { [childName]: Instance } — every chrome
	-- child this handle registered under `path .. "/" .. name` (L-28).
	--
	-- THE ONE RULING for park/adopt re-keying. The recurring defect shape in this
	-- area is a ruling that lives at one call site (applyFullBleed, the chrome
	-- z-ladder), so the enumeration that `park` releases and `adopt` re-keys is a
	-- single function covering ALL the registration families this module writes:
	-- the single decoration, the lifted label, the managed icon, the layer ladder
	-- (including a MASKED layer's CanvasGroup — its ImageLabel is parented to the
	-- mask and NOT to the host, which is why this walks the handle's own records
	-- rather than the instance's direct children), the bar window/fill and
	-- ornaments, and the toggle's Track/Knob. A registration family added here
	-- without being added here is exactly the leak the themed-park test sweeps for.
	local function chromePathChildEntries(handle: any): { [string]: Instance }
		local out: { [string]: Instance } = {}
		if handle.chrome ~= nil then
			out[chrome_slots.DECORATION_NAME] = handle.chrome
		end
		if handle.chromeText ~= nil then
			out[chrome_slots.TEXT_LIFT_NAME] = handle.chromeText
		end
		if handle.iconInstance ~= nil then
			out[chrome_slots.ICON_NAME] = handle.iconInstance
		end
		if handle.chromeStack ~= nil then
			for _, entry in handle.chromeStack do
				out[entry.instance.Name] = entry.instance
				if entry.mask ~= nil then
					out[entry.mask.Name] = entry.mask
				end
			end
		end
		if handle.barWindow ~= nil then
			out[chrome_slots.BAR_WINDOW_NAME] = handle.barWindow
		end
		if handle.barFill ~= nil then
			out[chrome_slots.BAR_FILL_NAME] = handle.barFill
		end
		if handle.barOrnaments ~= nil then
			for _, entry in handle.barOrnaments do
				out[entry.instance.Name] = entry.instance
			end
		end
		if handle.track ~= nil then
			out[chrome_slots.TOGGLE_PARTS.toggleTrack] = handle.track
		end
		if handle.knob ~= nil then
			out[chrome_slots.TOGGLE_PARTS.toggleKnob] = handle.knob
		end
		return out
	end

	return {
		-- the ONE entry point: reconcile every piece of chrome this node should
		-- carry against the installed package (called on create, on rect change,
		-- on state change and for every handle on a package swap)
		syncChrome = syncChrome,
		-- RE-FIT EVERY FULL-BLEED COMPENSATION TO THE HOST'S CURRENT `UIPadding`
		-- (director device round 2026-08-13, `cutoff.png`). Called by the ONE
		-- authority that writes that padding — see the function's own comment for
		-- the live measurement and why the padding write has to own this.
		refitFullBleed = refitFullBleed,
		-- every chrome child registered under `path .. "/" .. name`, for the
		-- park/adopt re-key (L-28); park releases this set, adopt re-keys it
		chromePathChildEntries = chromePathChildEntries,
		-- the asset-failure ledger's inbound edge (adapter.setChromeAssetLoaded)
		setChromeAssetLoaded = setChromeAssetLoaded,
		-- the decode judgement over every art instance this target owns
		-- (adapter.chromeArtJudgement), the live twin of the ledger's own census
		artCensus = chromeArtCensus,
		-- "the image is the element": turn a skinned node's own plate off
		applySkinnedSuppression = applySkinnedSuppression,
		-- the toggle's two art-bearing parts, resynced on build and on value change
		syncToggleArt = syncToggleArt,
		-- RE-FIT AN ICON TO A RECT THAT ARRIVED AFTER IT (director report
		-- 2026-07-28). The picture is clamped to the node's solved box, and on the
		-- create path the icon can be synced before the first `setRect` — so the
		-- adapter calls this from `applyRect`. Guarded on the handle actually
		-- carrying a picture, so every node without one pays a nil check.
		refitIconArt = function(handle: any)
			if handle.iconInstance ~= nil then
				syncIconArt(handle)
			end
			-- the lifted label is clamped to the same box for the same reason, and
			-- reaches it the same way: the plan is cached on the handle so this
			-- costs one geometry rewrite rather than a whole chrome reconcile.
			if handle.chromeText ~= nil and handle.chromeTextPlan ~= nil then
				local pos, size, anchor = liftGeometry(handle.chromeTextPlan, handle)
				handle.chromeText.AnchorPoint = anchor
				handle.chromeText.Position = pos
				handle.chromeText.Size = size
			end
		end,
		-- the rung-2 per-view override's state art + accessibility floor
		applyOverrideVariantArt = applyOverrideVariantArt,
		-- the instance that DRAWS this node's plate, which the focus ring/glow
		-- hangs off
		focusArtHost = focusArtHost,
		-- the six teardown paths adapter.remove / destroyRoot drive
		destroyChromeText = destroyChromeText,
		destroyIconArt = destroyIconArt,
		destroyChromeStack = destroyChromeStack,
		destroyBarFill = destroyBarFill,
		destroyBarOrnaments = destroyBarOrnaments,
		dropChromeShadow = dropChromeShadow,
		-- the chrome-text-lift census counter (census.textLifts)
		textLifts = function(): number
			return chromeTextLifts
		end,
	}
end

return screen_chrome
