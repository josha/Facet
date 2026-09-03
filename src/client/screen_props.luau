--!strict
-- ScreenProps — the per-class PROPERTY-WRITE dispatch table of the ScreenTarget
-- adapter (`adapter.setProp`'s per-class chain), extracted from
-- src/client/screen_target.luau for Studio's 200_000-character `Source` WRITE
-- cap. Over that cap a module silently stops live-syncing into an open Studio
-- session, so every live check against it tests the built place rather than the
-- edits on disk, once it is over the 200,000-char Source WRITE cap.
--
-- WHY THIS IS THE SEAM. `tools/lune/verify/data/source-cap-ledger.md`'s row for this file
-- named it across six prior extractions: everything large inside
-- `screen_target.new`'s closure — `setProp` (25.8 KB), `syncTags`, `create` and
-- `setFocusVisual` — reads the same `style`/`nativeMode`/`instancesByPath`/
-- `assertBespokePaint`/handle-map upvalues, so none of them is one-way AS
-- WRITTEN. The row's own prescription: `setProp` "becomes one-way the moment the
-- paint/style context it reads is a parameter object rather than four upvalues"
-- — a REFACTOR of the adapter, not a plain move, which is why five smaller seams
-- left first. `new(ctx)` below is that parameter object; `screen_target` calls
-- `ensureInstance(handle)` itself (unchanged — it stays the host's one
-- materialisation authority, ahead of every prop write) and hands the whole
-- per-class chain to `setProp` here.
--
-- THE COST WAS ZERO RECORDS. Every name `ctx` carries is a value assigned once
-- at construction (a style/mode/palette fact) or a function bound once from a
-- sibling subsystem (`chrome`, `paint`, `presentation`) or a host-owned helper
-- (`syncTags`, `assertBespokePaint`, `mirrorToHitExpander`, `writeFieldText`) —
-- `setProp` reassigns not one of them and writes only through its own `handle`
-- and `instance` parameters, so unlike `table_rows.luau`'s `rowGesture` or
-- `virtual_list_hosted.luau`'s `hostedDelivery` there is no reassigned scalar to
-- wrap in a shared record. `tests/screen_props_seam.spec.luau` mechanises the
-- property: READ == DECLARED == PASSED as three set comparisons over the live
-- sources, the empty shared-write surface, the one construction site and the
-- one-way require.
--
-- `new(ctx)` returns `{ setProp }`; `screen_target.new` binds it to a local of
-- the same name so the one call site below reads exactly as it did while this
-- was inline. Public surface unmoved: all of this is internal to
-- `screen_target.new`, whose contract is the `adapter` table it returns.
--
-- ctx:
--   style, nativeMode, palette (`COLOR`), canSetTextInputType,
--   keyboardTypeEngineName
--                        construction-time facts, by value (none reassigned
--                        after `screen_target.new` builds them)
--   assertBespokePaint, claimPaint, restorePaint, syncTags
--                        THE PAINT-CLAIM LEDGER and the tag reconciler, the same
--                        host helpers `screen_chrome`/`screen_paint` already
--                        receive
--   syncChrome, applyOverrideVariantArt, refitFullBleed, refitIconArt
--                        from `screen_chrome` — the package-art path
--   applySurface, applyShadow, applyGradient, applyCorners, applyStroke,
--   applyTint, releaseTint, applyPathRole, cornerRadiusFor, applyToggleValue
--                        from `screen_paint` — the bespoke path
--   applyPathPoints, registerHost, setPresentationTransform
--                        from `screen_presentation`
--   writeFieldText, mirrorToHitExpander
--                        host helpers with no subsystem of their own (the
--                        IME-safe TextBox echo guard, and the hit-expander
--                        mirror that keeps a disabled/enabled control's tap band
--                        honest)
--
-- `TEXT_ALIGN_MAP`, `SCALE_MODE_ENGINE`, `TINT_REPAINTING_PROPS` and
-- `fontFaceFor` are NOT on `ctx` — they are `screen_vocabulary` module-scope
-- constants already reachable by a direct require, same as `screen_target`
-- reads them, so threading them through `ctx` would be a copy of an address
-- this module can already take for itself.

local screen_vocabulary = require("./screen_vocabulary")
local TEXT_ALIGN_MAP = screen_vocabulary.TEXT_ALIGN_MAP
local SCALE_MODE_ENGINE = screen_vocabulary.SCALE_MODE_ENGINE
local TINT_REPAINTING_PROPS = screen_vocabulary.TINT_REPAINTING_PROPS
local fontFaceFor = screen_vocabulary.fontFaceFor

local screen_props = {}

export type Ctx = {
	style: any,
	nativeMode: boolean,
	palette: any,
	canSetTextInputType: boolean,
	keyboardTypeEngineName: { [string]: string },
	assertBespokePaint: (string, any?) -> (),
	claimPaint: (any, string) -> (),
	restorePaint: (any, string) -> (),
	syncTags: (any) -> (),
	syncChrome: (any) -> (),
	applyOverrideVariantArt: (any) -> (),
	refitFullBleed: (any) -> (),
	refitIconArt: (any) -> (),
	applySurface: (Instance, string, any) -> (),
	applyShadow: (Instance, any, any) -> (),
	applyGradient: (Instance, any, any) -> (),
	applyCorners: (Instance, any, any?) -> (),
	applyStroke: (Instance, any, any) -> (),
	applyTint: (any) -> (),
	releaseTint: (any) -> (),
	applyPathRole: (any) -> (),
	cornerRadiusFor: (any, number) -> number,
	applyToggleValue: (any, boolean) -> (),
	applyPathPoints: (any) -> (),
	registerHost: (string, Instance, any, boolean?) -> (),
	setPresentationTransform: (any, any) -> (),
	writeFieldText: (any, string) -> (),
	mirrorToHitExpander: (any) -> (),
}

function screen_props.new(ctx: Ctx)
	local style = ctx.style
	local nativeMode = ctx.nativeMode
	local COLOR = ctx.palette
	local canSetTextInputType = ctx.canSetTextInputType
	local KEYBOARD_TYPE_ENGINE_NAME = ctx.keyboardTypeEngineName
	local assertBespokePaint = ctx.assertBespokePaint
	local claimPaint = ctx.claimPaint
	local restorePaint = ctx.restorePaint
	local syncTags = ctx.syncTags
	local syncChrome = ctx.syncChrome
	local applyOverrideVariantArt = ctx.applyOverrideVariantArt
	local refitFullBleed = ctx.refitFullBleed
	local refitIconArt = ctx.refitIconArt
	local applySurface = ctx.applySurface
	local applyShadow = ctx.applyShadow
	local applyGradient = ctx.applyGradient
	local applyCorners = ctx.applyCorners
	local applyStroke = ctx.applyStroke
	local applyTint = ctx.applyTint
	local releaseTint = ctx.releaseTint
	local applyPathRole = ctx.applyPathRole
	local cornerRadiusFor = ctx.cornerRadiusFor
	local applyToggleValue = ctx.applyToggleValue
	local applyPathPoints = ctx.applyPathPoints
	local registerHost = ctx.registerHost
	local setPresentationTransform = ctx.setPresentationTransform
	local writeFieldText = ctx.writeFieldText
	local mirrorToHitExpander = ctx.mirrorToHitExpander

	-- a property write needs a real object; the host materialises it
	-- (`ensureInstance(handle)`) before calling here, exactly as it did when this
	-- chain was inline
	local function setProp(handle: any, prop: string, value: any, _authority: string)
		local instance = handle.instance
		if prop == "surface" then
			if instance:IsA("GuiObject") then
				applySurface(instance, tostring(value), handle)
			end
		elseif prop == "role" then
			-- B-BTN2: on a BUTTON, `role` is the semantic role (default | cancel |
			-- destructive). Native mode emits a tag and the sheet's rule paints it;
			-- the fallback path writes the danger/cancel fill directly. Never a
			-- parallel paint-state system — the states below still own hover/press.
			if handle.class == "Button" then
				if nativeMode then
					handle.nativeButtonRole = if value == "default" then nil else value
					syncTags(handle)
				else
					local fill = if value == "destructive"
						then COLOR.danger
						elseif value == "cancel" then COLOR.surface
						else COLOR.control
					handle.roleFill = if value == "default" then nil else fill
					assertBespokePaint("BackgroundColor3")
					instance.BackgroundColor3 = fill
					if instance:IsA("TextButton") then
						assertBespokePaint("TextColor3")
						instance.TextColor3 = if value == "destructive"
							then COLOR.onDanger
							elseif value == "cancel" then COLOR.contentSecondary
							else COLOR.content
					end
				end
			elseif nativeMode and (instance:IsA("TextLabel") or instance:IsA("TextButton")) then
				-- native: the "Secondary text" tag rule owns the color
				handle.nativeRoleSecondary = value == "secondary"
				syncTags(handle)
			elseif instance:IsA("TextLabel") or instance:IsA("TextButton") then
				-- BOTH DIRECTIONS. `role` is a reactive prop, and the native path above
				-- already round-trips it through the tag; this fallback path used to
				-- write the receded colour and nothing else, so a label that flipped
				-- secondary -> content stayed grey for the rest of its life. A closed
				-- set whose paint is one-way is not a state, it is a latch.
				assertBespokePaint("TextColor3")
				instance.TextColor3 = if value == "secondary" then COLOR.contentSecondary else COLOR.content
			elseif handle.path2d ~= nil then
				-- Path stroke color rides the style role hint: never a raw
				-- color from screen code — and, since 2026-08-14, never the palette
				-- this target was CONSTRUCTED with either. A Path2D is adapter-owned
				-- paint in every mode (no rule can select one), so the role resolves
				-- against the LIVE theme; see screen_paint.applyPathRole.
				handle.pathRole = value
				applyPathRole(handle)
			end
		elseif prop == "points" then
			if handle.path2d ~= nil then
				handle.normPoints = value
				applyPathPoints(handle)
			end
		elseif prop == "thickness" then
			if handle.path2d ~= nil then
				handle.path2d.Thickness = value
			end
		elseif prop == "closed" then
			if handle.path2d ~= nil then
				handle.path2d.Closed = value == true
			end
		elseif prop == "clipChildren" then
			if value == true and instance:IsA("GuiObject") then
				instance.ClipsDescendants = true
				-- a node may ALREADY be a real parent (a fade group declares itself one
				-- at creation): `registerHost` is create-or-REUSE for exactly this
				-- order, because replacing the entry would strand every child already
				-- re-based against it
				registerHost(handle.path, instance, handle.windowRect, true)
			end
		elseif prop == "padding" then
			if handle.class == "Button" then
				local pad = instance:FindFirstChildOfClass("UIPadding")
				if pad ~= nil then
					-- PER-SIDE IS LEGAL AND ARRIVED AS A TABLE (found 2026-07-26 by the
					-- gallery picker's tight-vertical chip). `padding = { top = "xs" }`
					-- is an ordinary authored value on every container the schema
					-- declares, Button included, and this write passed it straight to
					-- `UDim.new`, which errors on a table — a crash on documented input.
					--
					-- The engine inset is HORIZONTAL by construction: the label centres
					-- inside the box the solver already reserved, so the vertical pair is
					-- spent on the node's SIZE and needs no instance. Sides that were not
					-- authored are 0, which is exactly what `solver.sides` measured them
					-- as — measure and paint cannot disagree about a side nobody wrote.
					local left, right = 0, 0
					if type(value) == "number" then
						left, right = value, value
					elseif type(value) == "table" then
						left = if type(value.left) == "number" then value.left else 0
						right = if type(value.right) == "number" then value.right else 0
					end
					pad.PaddingLeft = UDim.new(0, left)
					pad.PaddingRight = UDim.new(0, right)
					--[[ ...AND EVERY DECORATION THAT CANCELS THAT PADDING IS NOW STALE.
						A Button is CREATED with `style.space.s + 4` a side (below) and
						skinned at the end of `create`, so its decoration is full-bled for
						the class default; this write is where the authored number lands,
						and it used to leave the compensation pointing at the old one.

						MEASURED LIVE (Compact Pointer, the swipe tray's `Mark Read` plate,
						2026-08-13): default 12 vs authored 8 painted the decoration at
						[6.0 .. 97.0] for a plate at [10.0 .. 93.0] — 4px outside its own
						box a side — and the plate's left edge sits exactly on the Table
						body's clip edge, so the left border and both left corners were cut
						away. `refitFullBleed`'s own comment carries the full measurement. ]]
					refitFullBleed(handle)
				end
			elseif handle.class == "Text" and instance:IsA("TextLabel") then
				-- A PADDED `Text` LEAF (device report 2026-08-12, IMG_3691). The solver
				-- adds a Text's authored padding to its reserved box and then returns at
				-- the leaf without insetting anything — a container spends its padding
				-- by placing children at rect + padding, and a leaf has none — so the
				-- glyphs were drawn across the WHOLE padded box, flush against its
				-- leading edge. The showcase's stat tiles are the shape that shows it:
				-- a 27px plate holding a 15px label with 6px of padding a side, and the
				-- label sitting on the plate's own rounded corner.
				--
				-- ALL FOUR SIDES, unlike Button's horizontal-only pair: a Button centres
				-- its single line in the box the solver reserved, so its vertical
				-- padding is already spent on the node's size, while a Text can wrap,
				-- can be top/bottom aligned, and is the node whose own box this is. The
				-- padding written here is exactly the padding `contentSize` measured
				-- with, so measure and paint agree on every side.
				local pad = instance:FindFirstChildOfClass("UIPadding")
				local top, right, bottom, left = 0, 0, 0, 0
				if type(value) == "number" then
					top, right, bottom, left = value, value, value, value
				elseif type(value) == "table" then
					top = if type(value.top) == "number" then value.top else 0
					right = if type(value.right) == "number" then value.right else 0
					bottom = if type(value.bottom) == "number" then value.bottom else 0
					left = if type(value.left) == "number" then value.left else 0
				end
				-- an all-zero inset on a node that never had one materializes nothing:
				-- the instance budget stays exactly where it was for every unpadded
				-- label in the tree
				if pad == nil and (top ~= 0 or right ~= 0 or bottom ~= 0 or left ~= 0) then
					pad = Instance.new("UIPadding")
					pad.Parent = instance
				end
				if pad ~= nil then
					pad.PaddingTop = UDim.new(0, top)
					pad.PaddingRight = UDim.new(0, right)
					pad.PaddingBottom = UDim.new(0, bottom)
					pad.PaddingLeft = UDim.new(0, left)
					-- the same refit as the Button branch above, for the same reason: a
					-- `Text` can carry a surface and therefore a decoration, and this
					-- write can MATERIALISE a `UIPadding` where there was none, which
					-- turns a correct identity compensation into a stale zero
					refitFullBleed(handle)
				end
			end
		elseif prop == "shape" then
			-- THE CIRCLE BUTTON (feature round 2026-07-26). Applied FIRST of the
			-- style props (renderer STYLE_PROP_ORDER) so every chrome write after it
			-- sees the shape: `corner()` reads `handle.shape`, and the surface a
			-- Button declares arrives next.
			handle.shape = if value == "circle" then "circle" else nil
			if nativeMode then
				-- the pill and the rim are the sheet's phantom modifier rules — zero
				-- new instances on a flat theme, which is the whole reason the disc
				-- rides the radii machinery the slider thumb proved
				syncTags(handle)
			else
				-- fallback half: the real UICorner already exists (adapter.create
				-- wires a Button's interactive states before any prop arrives), so
				-- re-radius what is there rather than parenting a second modifier —
				-- the engine honours ONE UICorner and a second would be dead weight
				-- whose value nobody could predict.
				assertBespokePaint("CornerRadius")
				local reshaped = cornerRadiusFor(handle, style.radii.control)
				for _, child in instance:GetChildren() do
					if child:IsA("UICorner") then
						(child :: UICorner).CornerRadius = reshaped
					end
				end
				-- ...AND THE CHROME RECORD FOLLOWS THE PAINT (T8 R3, Important 3).
				-- This write does not MATERIALISE the corner, so it never creates a
				-- record — but when a chrome owner already made one, that record
				-- must keep describing what the instance actually wears, or a
				-- reactive `corners` crossing to nil would restore the square
				-- radius `wireInteractiveStates` wrote before the disc arrived.
				if handle.chromeCornerRadius ~= nil then
					handle.chromeCornerRadius = reshaped
				end
			end
		elseif prop == "icon" then
			-- SEMANTIC ICON CONTENT reached from a public prop. The
			-- control's own text is already the framework's ASCII glyph (the
			-- renderer's drawnButtonText), so this is an UPGRADE, not a dependency:
			-- it tells the chrome subsystem which semantic name to look for in the
			-- installed package, and a package with no art for it changes nothing.
			--
			-- The hint table may be FROZEN (chrome_slots.attachHint freezes it), so
			-- this composes a new one rather than writing through.
			local merged: { [string]: any } = {}
			if type(handle.decorationHint) == "table" then
				for k, v in handle.decorationHint do
					merged[k] = v
				end
			end
			merged.icon = if type(value) == "string" and value ~= "" then value else nil
			handle.decorationHint = merged
			-- syncChrome is the ONE reconcile entry point and drives syncIconArt
			syncChrome(handle)
		elseif prop == "compactLabel" then
			-- THE RAW-IMAGE COMPACT FORM (compact-label stage, 2026-07-27). Only the
			-- `image` form reaches here: the `text` form is just a shorter string on
			-- the ordinary label write, and the `icon` form is raised as an `icon`
			-- request so it goes through the R4 machinery above (theme art, tint
			-- role, the ASCII floor) rather than around it.
			--
			-- A raw content id has no semantic name, so nothing can resolve a tint
			-- role or a package override for it — which is exactly why the docs
			-- point authors at `icon` and call this the escape hatch. It is carried
			-- on the decoration hint as a per-view `image`, the rung-2 override the
			-- chrome subsystem already understands, so the picture is anchored and
			-- sized by the same code that draws every other managed image.
			--
			-- The renderer clears it (passes nil) the moment the full label fits
			-- again, so the picture never outlives the verdict that raised it.
			local merged: { [string]: any } = {}
			if type(handle.decorationHint) == "table" then
				for k, v in handle.decorationHint do
					merged[k] = v
				end
			end
			merged.image = if type(value) == "table" and type(value.image) == "string" then value.image else nil
			handle.decorationHint = merged
			syncChrome(handle)
		elseif prop == "shadow" then
			applyShadow(instance, value, handle)
		elseif prop == "gradient" then
			applyGradient(instance, value, handle)
		elseif prop == "corners" then
			applyCorners(instance, value, handle)
		elseif prop == "stroke" then
			applyStroke(instance, value, handle)
		elseif prop == "tint" then
			-- THE CONTINUOUS-COLOUR CHANNEL. The renderer applies this LAST at
			-- creation and re-applies it after any write that repaints what it claimed
			-- (see the tail of this function), so the tint is always the final word on
			-- the property it owns.
			if value == nil then
				releaseTint(handle)
			else
				handle.tint = value
				applyTint(handle)
			end
		elseif prop == "scaleMode" then
			-- HOW THE PICTURE FILLS ITS BOX. `ScaleType` is sheet-owned in native mode
			-- (a skinned slot's rule sets it), so an authored one CLAIMS it — the same
			-- mechanism the tint uses, for the same reason: no rule can carry a
			-- per-node authored value.
			if instance:IsA("ImageLabel") then
				if value == nil then
					restorePaint(handle, "ScaleType")
				else
					local mapped = SCALE_MODE_ENGINE[tostring(value)]
					if mapped ~= nil then
						claimPaint(handle, "ScaleType")
						assertBespokePaint("ScaleType", handle)
						instance.ScaleType = mapped
					end
				end
			end
		elseif prop == "transform" then
			-- THE PRESENTATION TRANSFORM (fixes the headless-green/device-wrong class — this
			-- branch simply did not exist, so every keep-visible shift was a headless
			-- green that never moved a device). The whole body is
			-- `screen_presentation.setTransform`, because it is the one writer of that
			-- module's `presentationCount`.
			setPresentationTransform(handle, value)
		elseif prop == "dragHeld" then
			-- THE HELD DRAG SOURCE (director round five). Native: the tag rides
			-- syncTags and the sheet's `.facet-drag-held` rule empties the label
			-- (TextTransparency is sheet-owned there — same channel as iconArt).
			-- Bespoke: the write is ours, so it is direct — with the node's own
			-- resting transparency restored on release.
			local held = value == true
			handle.dragHeld = held
			if nativeMode then
				syncTags(handle)
			elseif instance:IsA("TextButton") or instance:IsA("TextLabel") or instance:IsA("TextBox") then
				instance.TextTransparency = if held then 1 else 0
			end
		elseif prop == "transparency" then
			-- PRESENTATION TRANSPARENCY IS A GROUP FACT: one engine property, on a
			-- node that declared itself a fade group, that no style rule owns — so a
			-- subtree fade never contests native-sheet paint. The renderer refuses the
			-- write for an undeclared node, and this guard is the adapter's half of the
			-- same contract.
			if handle.canvasGroupInstance ~= nil then
				handle.canvasGroupInstance.GroupTransparency = if type(value) == "number"
					then math.clamp(value, 0, 1)
					else 0
			end
		elseif prop == "textAlign" then
			-- paint-only and reactive: an unset or unrecognised value falls back to
			-- Left, which is what this adapter hard-coded before the prop existed
			if instance:IsA("TextLabel") or instance:IsA("TextButton") then
				instance.TextXAlignment = TEXT_ALIGN_MAP[value] or Enum.TextXAlignment.Left
			end
		elseif prop == "textSize" then
			if instance:IsA("TextLabel") or instance:IsA("TextButton") then
				instance.TextSize = value -- layout authority in BOTH modes
				-- ...AND the Toggle's lifted label, which is the thing that
				-- actually draws that text (director round 9). It was pinned at 16
				-- from construction while the SOLVER measured the row at the
				-- theme's `body` size — classic-desktop measures "Music" at 13
				-- (28 px) and the engine drew it at 16 (35 px) into a 20 px box.
				-- Same accepted-and-ignored class as director defect 3, one
				-- control down.
				if handle.labelInstance ~= nil then
					handle.labelInstance.TextSize = value
				end
				-- THE TEXT-SIZE-ONLY DRIFT CASE (review finding I5, 2026-08-28;
				-- the themed-chrome amendment). `chrome_slots.liftGeometry`'s
				-- floor is the host's LIVE `TextSize`, re-read from two places: the
				-- chrome reconcile, and `refitIconArt`, which the adapter otherwise
				-- only drives from `applyRect`. `render/rect_pass.luau` skips
				-- `setRect` for a rect equal to the last one written, so a
				-- `fixed`-px themed control whose TEXT SIZE moves at a new
				-- `preferredTextSize` step while its RECT does not would take the
				-- new size here and get no refit — the paint seam holding the
				-- previous frame's lift box while the measure seam has already
				-- moved. This is the one other write that can know the floor just
				-- changed, so it re-runs the same no-op-guarded refit
				-- `applyRect`/the padding write already call (see
				-- `chrome_padding_refit.spec.luau`'s identical shape).
				refitIconArt(handle)
				if nativeMode then
					-- native: heading-scale emphasis rides the "Strong text" tag rule
					handle.nativeStrong = value >= style.type.heading
					syncTags(handle)
				elseif value >= style.type.heading then
					assertBespokePaint("TextColor3")
					instance.TextColor3 = COLOR.contentStrong
				end
			end
		elseif prop == "textFont" then
			-- THE TYPOGRAPHY ROLE'S FACE (F2, 2026-08-02). The renderer resolves the
			-- node's effective role against the SAME snapshot the solver measured with
			-- and hands the descriptor here, so the family/weight the engine draws is
			-- the family/weight the box was reserved for. Before this the adapter wrote
			-- one hardcoded face at creation and nothing ever moved it — which is why a
			-- `weight` PROP would have been the wrong shape: a face that reaches only
			-- one seam is exactly what `Text.font` was deprecated for.
			--
			-- NATIVE MODE MUST NOT WRITE IT. `FontFace` is sheet-owned
			-- (authority.nativeSheetOwned) and an explicit write permanently defeats the
			-- rule, so in native mode the role rides a `facet-type-<role>` TAG whose
			-- generated rule carries the same descriptor.
			local descriptor = if type(value) == "table" then value else nil
			if nativeMode then
				handle.typeRole = if descriptor ~= nil then descriptor.role else nil
				syncTags(handle)
			elseif descriptor ~= nil then
				local face = fontFaceFor(descriptor)
				if face ~= nil then
					if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
						assertBespokePaint("FontFace")
						instance.FontFace = face
					end
					-- ...and the Toggle's lifted label, for exactly the reason `textSize`
					-- reaches it: that instance is the thing that draws the text
					if handle.labelInstance ~= nil then
						assertBespokePaint("FontFace")
						handle.labelInstance.FontFace = face
					end
				end
			end
		elseif prop == "text" or prop == "label" then
			if handle.class == "TextField" and instance:IsA("TextBox") then
				writeFieldText(handle, tostring(value))
			elseif handle.labelInstance ~= nil then
				handle.labelInstance.Text = tostring(value)
			elseif instance:IsA("TextLabel") or instance:IsA("TextButton") then
				instance.Text = tostring(value)
			end
			-- ONE LINE FOR A WORD, WRAPPING FOR A PHRASE (director round 13,
			-- 2026-07-27: fantasy-parchment's Edit/Done toggle drew "Don" over
			-- "e"). A content-sized button is measured to EXACTLY its label, so a
			-- one-pixel disagreement with the engine's own measurement does not
			-- clip a pixel — it BREAKS THE WORD. A word has no legal break point,
			-- so an ellipsis is the honest degradation; a phrase has one, and the
			-- theme picker's "Classic Desktop" chips wrap to two lines on a narrow
			-- phone on purpose.
			--
			-- It rides the LABEL WRITE, not creation, because the label is a
			-- reactive binding: the table's own toggle flips Edit <-> Done, and
			-- both seams have to re-decide from the same string. The solver makes
			-- the identical call (renderer.luau `isSingleWord`).
			--
			-- GENERALISED TO EVERY TEXT NODE (director, 2026-07-27). This was
			-- gated on `handle.class == "Button"`, so a plain `UI.Text` — a table
			-- cell, a list row, any label — kept the creation default
			-- `TextWrapped = true` and had NO `TextTruncate` at all. The framework
			-- therefore had no opinion about how such a node degrades: with a box
			-- too small the engine was free to break a word or clip mid-character
			-- with no ellipsis, which is what the playlist's name column showed
			-- ("Neon Straightawa"). The rule was never Button-specific — breaking a
			-- WORD is damage wherever it happens — so the gate was the bug.
			--
			-- ...AND HALF THE RULE LIVES IN THE SOLVE (director ruling 5, 2026-08-13).
			-- "Has a legal break" is all this seam can see; whether the break can
			-- SUCCEED needs the drawable width, and a phrase wrapped into a column
			-- narrower than one of its own words is broken mid-word exactly as a
			-- single word would be. The solver measures that (`textFacts.wraps`) and
			-- the renderer carries the verdict here as `textWrapped`; `handle.wraps`
			-- is that verdict, `nil` until a solve has spoken. Both halves are ANDed,
			-- so whichever of the two writes lands last, the answer is the same one.
			if instance:IsA("TextLabel") or instance:IsA("TextButton") then
				instance.TextWrapped = handle.wraps ~= false and string.find(tostring(value), "%s") ~= nil
			end
		elseif prop == "textWrapped" then
			-- the other half of the same rule; re-applied against the string the
			-- instance is currently drawing, because the two writes are independent
			handle.wraps = value ~= false
			if instance:IsA("TextLabel") or instance:IsA("TextButton") then
				local drawn = if handle.labelInstance ~= nil then handle.labelInstance.Text else instance.Text
				instance.TextWrapped = handle.wraps and string.find(drawn, "%s") ~= nil
			end
		elseif prop == "placeholder" then
			if instance:IsA("TextBox") then
				instance.PlaceholderText = tostring(value)
			end
		elseif prop == "editing" then
			-- the editing binding is the CaptureFocus/ReleaseFocus channel (WP2
			-- seam): model enters edit -> capture; leaves -> release. Guarded by
			-- IsFocused so an engine-initiated focus (native tap / A-press, which
			-- already drove the model into editing via onFocusGained) does not
			-- redundantly re-capture, and a model-exit after the engine already
			-- released (Enter fired FocusLost first) is a harmless skip.
			if instance:IsA("TextBox") then
				if value == true then
					if not instance:IsFocused() then
						instance:CaptureFocus()
					end
				else
					if instance:IsFocused() then
						instance:ReleaseFocus(false)
					end
				end
			end
		elseif prop == "keyboardType" then
			-- best-effort engine hint: map numeric/email/phone -> the closest
			-- Enum.TextInputType; default/unknown -> Default. Degrades to the default
			-- keyboard when the security-locked TextInputType is unreachable (facts
			-- §1: RobloxScript-locked, so canSetTextInputType is false on shipping
			-- game/plugin scripts and this whole branch is skipped — forward-
			-- compatible when a future engine unlocks it). The declaration always
			-- stays valid data on the model side regardless.
			if instance:IsA("TextBox") and canSetTextInputType then
				local name = KEYBOARD_TYPE_ENGINE_NAME[tostring(value)] or "Default"
				pcall(function()
					(instance :: any).TextInputType = (Enum.TextInputType :: any)[name]
				end)
			end
		elseif prop == "maxLength" then
			-- no engine property enforces this; the value model clamps by Unicode
			-- scalar (WP2). Nothing to write to the TextBox — data-only.
		elseif prop == "selected" then
			-- a node that DECLARES a selection binding is a selection surface,
			-- whatever the current value is: the slot is the node's semantics
			-- and the value is the state a tint rule paints over one base image
			if handle.hasSelectionBinding ~= true then
				handle.hasSelectionBinding = true
				syncChrome(handle)
			end
			if instance:IsA("TextButton") then
				handle.isSelected = value == true
				-- a rung-2 map may declare `selected` art; nothing else repaints an
				-- untagged decoration
				applyOverrideVariantArt(handle)
				if nativeMode then
					-- native: the tag flip IS the state change — the
					-- "Selected row" rule paints it (and transitions animate it)
					syncTags(handle)
				elseif handle.applyRestingFill ~= nil then
					handle.applyRestingFill()
				else
					assertBespokePaint("BackgroundColor3")
					instance.BackgroundColor3 = if value == true then COLOR.controlSelected else COLOR.control
				end
			end
		elseif prop == "value" then
			applyToggleValue(handle, value == true)
		elseif prop == "enabled" then
			if instance:IsA("TextBox") then
				instance.TextEditable = value == true
				if nativeMode then
					-- native: Interactable drives GuiState.NonInteractable (spike
					-- m1 — Active does NOT); the :NonInteractable rule owns the
					-- disabled text transparency
					(instance :: any).Interactable = value == true
				else
					assertBespokePaint("TextTransparency")
					instance.TextTransparency = if value == true then 0 else style.extra.disabledContentOpacity
				end
			elseif instance:IsA("TextButton") then
				instance.Active = value == true
				if nativeMode then
					(instance :: any).Interactable = value == true
				else
					assertBespokePaint("TextTransparency")
					instance.TextTransparency = if value == true then 0 else style.extra.disabledContentOpacity
				end
			end
			--[[ THE BAND GOES WITH THE FACE (review F1, and its fix-1 residual): a
				disabled control whose 44px expander still advertises a press is a
				promise it does not keep, and the expander is a SIBLING so nothing
				about `enabled` reaches it by parentage.

				OUTSIDE THE CLASS CHAIN, deliberately. The chain above is about which
				engine PROPERTY says "disabled" for each instance class; the expander
				is a different question entirely — `setHitRect` builds one for whatever
				host asked for a hit rect, and four control classes declare a hit floor
				(Button and Toggle are TextButtons, TextField is a TextBox, Grip is
				neither). Gating this on `TextButton` left a disabled TextField's band
				carrying whatever it was born with. `mirrorToHitExpander` already
				guards on "does this handle have an expander", which is the same
				predicate `setHitRect` writes — so the condition is derived from that
				one guard rather than restated here as a class list that would drift
				the moment a fifth class declares a floor. ]]
			mirrorToHitExpander(handle)
		elseif prop == "active" then
			if instance:IsA("GuiObject") then
				instance.Active = value == true
			end
		elseif prop == "image" then
			if instance:IsA("ImageLabel") then
				instance.Image = tostring(value)
			end
		elseif prop == "cursorHint" then
			handle.cursorHint = tostring(value)
		end
		-- THE TINT IS THE LAST WORD ON THE PROPERTY IT CLAIMED. Everything in this
		-- set repaints a fill or a glyph colour on the bespoke path — a reactive
		-- `surface` swap, a role change, a selection flip, a disable — and a claimed
		-- property that gets quietly overwritten is a bound colour the author can see
		-- stop working. Declared as a set rather than a line inside each branch, so a
		-- new repainting write cannot forget it.
		if handle.tint ~= nil and TINT_REPAINTING_PROPS[prop] then
			applyTint(handle)
		end
	end

	return {
		setProp = setProp,
	}
end

return screen_props
