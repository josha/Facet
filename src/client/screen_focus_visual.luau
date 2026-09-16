--!strict
-- ScreenFocusVisual — the focus RING, the focus GLOW and the ten-foot LIFT of
-- the ScreenTarget adapter (`adapter.setFocusVisual`), extracted from
-- src/client/screen_target.luau for Studio's 200_000-character `Source` WRITE
-- cap. Over that cap a module silently stops live-syncing into an open Studio
-- session, so every live check against it tests the built place rather than the
-- edits on disk.
--
-- WHY THIS IS THE SEAM, AND WHY THE ROW'S OWN ESTIMATE OF ITS COST WAS WRONG.
-- `tools/lune/verify/data/source-cap-ledger.md`'s row for `screen_target.luau`
-- named this block as the next candidate after `setProp` and priced it as the
-- expensive one: it "READS all three of the host locals the theme install
-- reassigns — `focusTreatment`, `activeTheme` and the theme snapshot — so it
-- arrives needing screen_paint's three accessors plus `focusedHandles`,
-- `chromeState`, `focusArtHost`, `hasUIShadow`, the palette and the paint-claim
-- ledger. That is a paint-sized bundle for less code." Re-run mechanically
-- against the live file rather than re-read, that prediction is half right and
-- half generalised from `setProp`'s neighbours the way the row's own earlier
-- correction was: this block reads `focusTreatment` and the SNAPSHOT (two
-- accessors, not three — `activeTheme` it never touches), and it reads the
-- palette NOWHERE, `claimPaint`/`restorePaint`/`assertBespokePaint` NOWHERE and
-- `instancesByPath`/`handlesByPath` NOWHERE. The whole ctx is twelve names, of
-- which ten are values.
--
-- THE ONE-WAY TEST, MECHANISED over `screen_target.new`'s 123 closure locals
-- (15 of them reassigned): this block WRITES zero of them. Everything it
-- mutates it reaches through its own `handle`/`instance` parameters or through
-- `focusedHandles`/`chromeState`, two tables that are declared once and never
-- rebound — so they go back to the host AS THEMSELVES and every read on either
-- side stays byte-identical. Only two of the names it reads are reassigned
-- anywhere (`focusTreatment` by `setActiveTheme`, `activeThemeSnapshot` by
-- `setThemePackage`), and both arrive as accessors for exactly the reason
-- `screen_paint.luau` already takes them that way: a captured value would
-- freeze at construction and a live theme swap would repaint everything except
-- the ring.
--
-- WHAT DELIBERATELY DID NOT COME WITH IT. `aimFocusScale` (the lift's tween)
-- and `stopFocusScaleTweens` (its cancel) are a PAIR — the first calls the
-- second — and the second has three other callers in the host
-- (`adapter.park`, `adapter.remove`, `adapter.destroyRoot`). Moving the pair
-- would pull a teardown helper three unrelated paths depend on across the seam;
-- moving only `aimFocusScale` would split a two-line pair across two files.
-- So `aimFocusScale` stays in the host and arrives here as one ctx function,
-- which is one name cheaper than either alternative.
--
-- ctx:
--   style, nativeMode, hasUIShadow
--                        construction-time facts, by value (none reassigned
--                        after `screen_target.new` builds them)
--   focusedHandles       the live focus set, by reference — the host's
--                        `setActiveTheme` walks it to repaint, `remove` and
--                        `destroyRoot` clear from it, and this module is the
--                        one writer that adds to it
--   chromeState          the chrome census record, by reference (the focus-glow
--                        counter both sides note into)
--   syncTags             the host's tag reconciler, for native-mode Grip focus
--   focusColor           from `screen_paint` — the live accent
--   focusArtHost         from `screen_chrome` — WHICH instance the visual hangs
--                        on when a node carries drawn art
--   aimFocusScale        the host's lift tween (see above)
--   hostOriginOf         from `screen_presentation` — the float ring is
--                        positioned in its clip host's own space
--   focusTreatment(), snapshot()
--                        ACCESSORS, not values: the host reassigns both (the
--                        theme install and `setThemePackage`), so a captured
--                        value would freeze at construction
--
-- `styling` and `chrome_slots` are NOT on `ctx` — they are module requires the
-- host takes for itself, so threading them through would be a copy of an
-- address this module can already take.
--
-- `new(ctx)` returns `{ setFocusVisual }`; `screen_target.new` binds it straight
-- onto `adapter`, so the method the render layer calls is the same function it
-- always was. `tests/screen_focus_visual_seam.spec.luau` mechanises the
-- property: READ == DECLARED == PASSED as three set comparisons over the live
-- sources, the shared WRITE surface pinned to the two by-reference tables that
-- are allowed to be on it, the one construction site and the one-way require.

local styling = require("../tokens/styling")
local chrome_slots = require("../tokens/chrome_slots")

local screen_focus_visual = {}

export type Ctx = {
	style: any,
	nativeMode: boolean,
	hasUIShadow: boolean,
	focusedHandles: { [any]: string? },
	chromeState: any,
	syncTags: (any) -> (),
	focusColor: () -> Color3,
	focusArtHost: (any) -> GuiObject?,
	aimFocusScale: (any, number) -> (),
	hostOriginOf: (any) -> (number, number),
	focusTreatment: () -> any,
	snapshot: () -> any,
}

function screen_focus_visual.new(ctx: Ctx)
	local style = ctx.style
	local nativeMode = ctx.nativeMode
	local hasUIShadow = ctx.hasUIShadow
	local focusedHandles = ctx.focusedHandles
	local chromeState = ctx.chromeState
	local syncTags = ctx.syncTags
	local focusColor = ctx.focusColor
	local focusArtHost = ctx.focusArtHost
	local aimFocusScale = ctx.aimFocusScale
	local hostOriginOf = ctx.hostOriginOf
	local focusTreatment = ctx.focusTreatment
	local snapshot = ctx.snapshot

	-- focus ring (design §8.4: focus is never color-only — ring + hover fill).
	-- profile is the env distanceProfile (UI-PARADIGM-003, matrix D.4): on a
	-- "ten-foot" (Large) display the ring thickens AND the control scales up so
	-- focus is unmistakable across a room; "near" (or nil) keeps the hairline
	-- ring with no scale — byte-identical to the pre-expansion behavior.
	local function setFocusVisual(handle: any, on: boolean, profile: string?)
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return
		end
		local strong = profile == "ten-foot"
		-- remembered so a live theme swap can repaint whatever is focused right
		-- now (refreshFocusVisuals). Cleared on blur, so the set is exactly the
		-- live focus visuals and never a growing list of everything ever focused.
		if on then
			focusedHandles[handle] = profile or ""
		else
			focusedHandles[handle] = nil
		end
		-- grips are thin slivers: a ring alone is nearly invisible, which read
		-- as "focus went nowhere" in the director's hand test (2026-07-20) —
		-- focused grips fill with accent
		if handle.class == "Grip" then
			if nativeMode then
				-- native: the explicit write would permanently defeat the
				-- "Frame default" rule (arch verifier 2026-07-24) — the accent
				-- fill rides the "Grip focus" tag rule instead (theme-aware)
				handle.nativeGripFocus = on
				syncTags(handle)
			else
				instance.BackgroundTransparency = if on then 0 else 1
				instance.BackgroundColor3 = focusColor()
			end
		end
		-- WHERE THE VISUAL HANGS (director fix round 2026-07-25). Not the node —
		-- the DRAWN ART, when there is any. See `focusArtHost`: a Button carries a
		-- UIPadding so its engine label clears the edges, that padding insets the
		-- decoration because a decoration is a child, and a ring on the node
		-- therefore left a band of empty air on each side of the plate it was
		-- outlining (measured live: a 53px stepper button, a 29px plate).
		-- Hit geometry is untouched — it was never this instance's Size.
		local host: GuiObject = if on then focusArtHost(handle) or instance else instance
		-- a glow whose host was destroyed under it (a swap that removed the art)
		-- is GONE: a Destroy()'d instance cannot be re-parented, and its census
		-- entry would otherwise never fall
		if handle.focusGlow ~= nil and handle.focusGlow.Parent == nil then
			handle.focusGlow = nil
			chromeState.noteFocusGlow(false)
		end
		local previous: GuiObject? = handle.focusVisualHost
		if previous ~= nil and previous ~= host then
			-- the art appeared, moved or was destroyed under a focused node: clear
			-- the old host before deciding, or a swap leaves two rings
			local stale = previous:FindFirstChild("FocusRing")
			if stale ~= nil then
				stale:Destroy()
			end

			if handle.focusGlow ~= nil and handle.focusGlow.Parent == previous then
				handle.focusGlow:Destroy()
				handle.focusGlow = nil
				chromeState.noteFocusGlow(false)
			end
		end
		handle.focusVisualHost = if on then host else nil
		local ringFloat: Frame? = handle.focusRingFloat
		if ringFloat ~= nil and ringFloat.Parent == nil then
			handle.focusRingFloat = nil
			handle.focusFloatGeom = nil -- review N8: the geometry dies with the float
			ringFloat = nil
		end
		local ring = host:FindFirstChild("FocusRing")
			or (if ringFloat ~= nil then ringFloat:FindFirstChild("FocusRing") else nil)
		local glow = handle.focusGlow
		-- WHICH TREATMENT. `glow` needs the engine to have UIShadow at all; on an
		-- engine (or a headless target) without it the package's glow degrades to
		-- the ring rather than to nothing, because §8.4 says focus is never
		-- optional. Switching treatments tears the other one down first, so a
		-- swap from ring to glow while a control is focused cannot leave both.
		local wantGlow = on and focusTreatment().kind == "glow" and hasUIShadow
		local focusShadow: any = nil
		if wantGlow then
			local ok, normalized =
				pcall(styling.normalizeShadow, chrome_slots.focusShadowSpec(focusTreatment().recipe, strong), style)
			if ok then
				focusShadow = normalized
				local g: any = normalized
				-- Centered pixel-radius halos fit every actual clipping ancestor,
				-- including one beyond a non-clipping transform/animation host.
				if
					g.blurRadius.scale == 0
					and g.offset.x.scale == 0
					and g.offset.x.offset == 0
					and g.offset.y.scale == 0
					and g.offset.y.offset == 0
					and g.spread.x.scale == 0
					and g.spread.x.offset == 0
					and g.spread.y.scale == 0
					and g.spread.y.offset == 0
				then
					local pos, size = host.AbsolutePosition, host.AbsoluteSize
					local ancestor = host.Parent
					while ancestor do
						if ancestor:IsA("GuiObject") and (ancestor.ClipsDescendants or ancestor:IsA("CanvasGroup")) then
							local cp = ancestor.AbsolutePosition
							local cs = if ancestor:IsA("ScrollingFrame")
								then ancestor.AbsoluteWindowSize
								else ancestor.AbsoluteSize
							g.blurRadius.offset = chrome_slots.focusBlurWithin(
								g.blurRadius.offset,
								{ x = pos.X, y = pos.Y, w = size.X, h = size.Y },
								{ x = cp.X, y = cp.Y, w = cs.X, h = cs.Y }
							)
						end
						ancestor = ancestor.Parent
					end
					-- A flush edge cannot display a halo. Keep focus visible with
					-- the same ring fallback used when UIShadow is unavailable.
					wantGlow = g.blurRadius.offset > 0
				end
			else
				wantGlow = false
			end
		end
		if ring ~= nil and (not on or wantGlow) then
			ring:Destroy()
			ring = nil
		end
		if ringFloat ~= nil and (not on or wantGlow) then
			ringFloat:Destroy()
			handle.focusRingFloat = nil
			handle.focusFloatGeom = nil -- review N8: the geometry dies with the float
			ringFloat = nil
		end
		if glow ~= nil and (not on or not wantGlow) then
			glow:Destroy()
			handle.focusGlow = nil
			glow = nil
			chromeState.noteFocusGlow(false)
		end
		if on and wantGlow then
			if glow == nil then
				glow = Instance.new("UIShadow" :: any)
				glow.Name = "FocusGlow"
				handle.focusGlow = glow
				chromeState.noteFocusGlow(true)
			end
			local g = focusShadow
			glow.BlurRadius = UDim.new(g.blurRadius.scale, g.blurRadius.offset)
			glow.Color = focusColor()
			glow.Transparency = g.transparency
			glow.Offset = UDim2.new(g.offset.x.scale, g.offset.x.offset, g.offset.y.scale, g.offset.y.offset)
			glow.Spread = UDim2.new(g.spread.x.scale, g.spread.x.offset, g.spread.y.scale, g.spread.y.offset)
			glow.ZIndex = g.zIndex
			glow.Enabled = true
			glow.Parent = host
		end
		if on then
			--[[ THE LIFT, COMPUTED BEFORE THE RING (device bug fix, director 2026-08-23:
				"the button's right edge draws past the ring"). This used to run AFTER
				the float block below, which sized the float from the PRE-LIFT rect:
				`FocusScale` (a top-left-anchored UIScale) grows the focused instance by
				`tenFootFocusScale` post-hoc and the float's manual position/size math
				never read it. Measured live (demo picker, console-ten-foot, a scrolled
				row): button 146x69 base -> 153x72 lifted; float stuck at 138x61 (base
				minus the ring's own thickness) — a gap on the right/bottom, the two
				edges a top-left anchor grows into. The ORDINARY (non-float) ring never
				showed this: it is a literal UIStroke child of the SAME instance the
				UIScale scales, so the engine scales it for free — only the float, built
				by hand because a clipping host would cut an outward stroke, needs the
				factor spelled out. ]]
			local lift = false
			-- A label over a separate indicator must stay aligned with that plate.
			if strong and handle.buttonRole ~= chrome_slots.ON_INDICATOR_ROLE then
				local screenGui = instance:FindFirstAncestorWhichIsA("ScreenGui")
				if screenGui ~= nil then
					-- bounds = the solved ROOT node's frame (the SAFE content rect,
					-- inside the overscan margins), not the raw canvas: a TV clips
					-- the margin, so a lift poking into it can vanish on real
					-- hardware. Matches the fake_target mirror exactly (its screen
					-- bounds are the root node's solved rect). Rendering is FLAT
					-- (siblings named by path), so the root is looked up by the
					-- path's first segment, never by ancestry.
					local rootSegment = string.match(handle.path or "", "^(/[^/]+)")
					local rootFrame = if rootSegment ~= nil then screenGui:FindFirstChild(rootSegment) else nil
					local boundsSource: GuiObject = if rootFrame ~= nil and rootFrame:IsA("GuiObject")
						then rootFrame
						else screenGui :: any
					local scale = style.extra.tenFootFocusScale
					local pos = instance.AbsolutePosition
					local size = instance.AbsoluteSize
					local boundsPos = boundsSource.AbsolutePosition
					local bounds = boundsSource.AbsoluteSize
					lift = pos.X + size.X * scale <= boundsPos.X + bounds.X
						and pos.Y + size.Y * scale <= boundsPos.Y + bounds.Y
					-- ALSO CAP AGAINST THE NEAREST SCROLL/CLIP HOST'S WINDOW (task CONN
					-- round 2, item 5; MISC's live repro: 306.6x40.95 vs a 292px
					-- `AbsoluteWindowSize` — the pop overflowed a ScrollingFrame's
					-- scrollbar reserve while still fitting the far-larger root
					-- above). `AbsoluteWindowSize` is ScrollingFrame-only; a plain
					-- clip host falls back to `AbsoluteSize`.
					if
						lift
						and handle.instanceHost ~= nil
						and handle.instanceHost.crops
						and handle.instanceHost.instance ~= nil
					then
						local hostInst = handle.instanceHost.instance
						local hostPos = hostInst.AbsolutePosition
						local hostWindow = if hostInst:IsA("ScrollingFrame")
							then (hostInst :: ScrollingFrame).AbsoluteWindowSize
							else hostInst.AbsoluteSize
						lift = pos.X + size.X * scale <= hostPos.X + hostWindow.X
							and pos.Y + size.Y * scale <= hostPos.Y + hostWindow.Y
					end
				end
			end
			local liftScale = if strong and lift then style.extra.tenFootFocusScale else 1
			local thickness = if strong then style.extra.tenFootFocusRingThickness else style.extra.focusRingThickness
			if not wantGlow then
				-- THE FLOAT RING (director round three, ROOT CAUSE). The instance
				-- tree is FLAT with ZIndexBehavior=Sibling, so on a stacked row:
				-- an OUTWARD Border ring paints in the neighbors' territory (the
				-- next row covers its bottom, the canvas clips its sides, only the
				-- top arc survived) and any ring parented UNDER the hit is covered
				-- by every higher-z sibling regardless of its own ZIndex. The one
				-- placement that works is a SIBLING of the row's instances: a
				-- transparent frame parented to the CLIP HOST itself, topmost-z,
				-- positioned over the focused rect and inset by the ring's own
				-- thickness so no scroll edge can cut it. It scrolls with the
				-- canvas because it lives in it; applyRect re-aims it when the
				-- row itself moves. Unclipped nodes keep the outward ring.
				local strokeParent: GuiObject = host
				-- ...AND ONLY UNDER A HOST THAT CROPS. The float exists
				-- because a ring drawn under a clipping or buffered parent gets cut;
				-- a plain move-boundary host cuts nothing, so a node inside one keeps
				-- the ordinary outward ring rather than growing a second instance to
				-- solve a problem it does not have.
				-- A layout/motion host can sit between the button and its clip.
				-- Keep the ring inside the button under any cropping ancestor.
				local cropped = false
				local ancestor = host.Parent
				while ancestor do
					if ancestor:IsA("GuiObject") and (ancestor.ClipsDescendants or ancestor:IsA("CanvasGroup")) then
						cropped = true
						break
					end
					ancestor = ancestor.Parent
				end
				if handle.instanceHost ~= nil and cropped and handle.instanceHost.instance ~= nil then
					local float = ringFloat
					if float == nil then
						float = Instance.new("Frame")
						float.Name = "FocusRingFloat"
						float.BackgroundTransparency = 1
						float.Parent = handle.instanceHost.instance
						handle.focusRingFloat = float
					end
					--[[ THE CORNER IS RE-SYNCED ON EVERY CALL, NOT ONLY AT FLOAT CREATION
						(fix, task THEME2, director item: "the selection ring is rounded vs
						matching the theme", i1.png). `refreshFocusVisuals` re-enters this
						function for every STILL-FOCUSED handle on a live theme swap —
						`setActiveTheme`'s own documented job is "repaint whatever is
						showing one right now" — but this block used to build the float's
						corner only `if float == nil`, so a control that stayed focused
						across a swap (exactly what driving a theme picker's live swap
						does) kept the PREVIOUS theme's ring corner forever: Studio
						Neutral's 8px, Glossy Mobile's 16px, whatever was live when the
						float was first built, even though the control's own paint and
						palette repainted in the very same commit. A blur-then-refocus
						cycle was never affected (blur destroys the float below), which is
						why this only shows on a control that survives a swap while it
						still holds focus. Idempotent by construction: re-run with no
						theme change re-derives the SAME radius and only overwrites a
						`CornerRadius` field, never adds a second corner instance. ]]
					do
						local realCorner = host:FindFirstChildOfClass("UICorner")
						local floatCorner = float:FindFirstChildOfClass("UICorner")
						if realCorner ~= nil then
							if floatCorner == nil then
								floatCorner = realCorner:Clone()
								floatCorner.Parent = float
							else
								-- CornerRadius is only the uniform alias. Copying it over a
								-- per-corner segment resets square inner corners to a capsule.
								local copied = pcall(function()
									for _, key in
										{ "TopLeftRadius", "TopRightRadius", "BottomLeftRadius", "BottomRightRadius" }
									do
										(floatCorner :: any)[key] = (realCorner :: any)[key]
									end
								end)
								if not copied then
									(floatCorner :: UICorner).CornerRadius = realCorner.CornerRadius
								end
							end
						else
							--[[ NATIVE MODE'S CORNER IS A PHANTOM (device bug fix, director
								2026-08-23: "the ring is sharp-cornered, the button is round").
								Under native paint (B-15's default) a control's `::UICorner` is
								a StyleSheet pseudo-element the engine materializes at render
								time (`native_style.luau`: "a real modifier instance here would
								silently defeat those rules") — never a real child, so the clone
								above always finds nothing on a native-styled host. Measured
								live: the demo picker's row buttons (plain `UI.Button`, native
								`control` surface) painted round and rang square. The float is
								the framework's OWN unstyled instance — a real UICorner on IT
								defeats no sheet rule — so this mirrors the role -> radius
								mapping `applySurface`'s bespoke `corner()` already makes
								(`screen_paint.luau`), rather than re-guessing it here. ]]
							--[[ THE LIVE PACKAGE'S RADII, NOT THE FROZEN CONSTRUCTION-TIME
								ONE (fix, task THEME2, director item: "the selection ring is
								rounded vs matching the theme", i1.png). `style` is a
								CONSTRUCTION-TIME fact by this file's own contract
								(`screen_paint.luau`'s header: "style, nativeMode, palette —
								construction-time facts, by value") and is never reassigned —
								grepped across this whole file, the only writes are `style =
								style` at three OTHER subsystems' construction calls. A live
								package install/swap instead reassigns `activeThemeSnapshot`
								(`setThemePackage`'s whole job), so for the ENTIRE lifetime of a
								target that ever installs a non-neutral package, `style.radii`
								answers "what radius did this target boot with", never "what
								radius is live right now" — measured: Pixel Quest's `control`
								radius is 4px, Facet Neutral's (this showcase's boot style) is
								8px, and every fallback ring stayed at 8px under every package
								until this fix, on the FIRST focus after a swap, not only one
								that survived it. `activeThemeSnapshot` is the SAME
								`themeSnapshot`-shaped table `style` itself is (both carry
								`.radii.{control,panel,pill}` — `themes/snapshot.luau`'s
								`paintForDisplay` and its general resolve path agree on the
								shape), so reading it where present is a value swap, not a new
								contract; nil (no package installed) keeps today's answer
								exactly. ]]
							local activeThemeSnapshot = snapshot()
							local liveRadii = if type(activeThemeSnapshot) == "table"
									and type((activeThemeSnapshot :: any).radii) == "table"
								then (activeThemeSnapshot :: any).radii
								else style.radii
							local surfaceRole = handle.nativeSurface or handle.declaredSurface
							local radius: UDim? = nil
							if handle.shape == "circle" then
								radius = UDim.new(0.5, 0)
							elseif host ~= instance then
								radius = UDim.new(0, liveRadii.selection or liveRadii.control)
							elseif surfaceRole == "raised" then
								radius = UDim.new(0, liveRadii.panel)
							elseif surfaceRole == "control" or surfaceRole == "chip" then
								radius = UDim.new(0, liveRadii.control)
							elseif surfaceRole == "badge" then
								radius = UDim.new(0.5, 0)
							end
							if radius ~= nil then
								if floatCorner == nil then
									floatCorner = Instance.new("UICorner")
									floatCorner.Parent = float
								end
								(floatCorner :: UICorner).CornerRadius = radius
							elseif floatCorner ~= nil then
								-- the role stopped mapping to any radius (e.g. a live
								-- swap changed the classified surface) — a stale corner
								-- left behind is worse than none
								floatCorner:Destroy()
							end
						end
					end
					local f = float :: Frame
					local rect = handle.windowRect
					local ox, oy = hostOriginOf(handle)
					if rect ~= nil then
						-- POSITION is unaffected: the lift's UIScale anchors at the
						-- instance's own top-left, so that corner never moves. SIZE
						-- grows by the same factor the lift applies, or the ring stays
						-- sized for the rect the control no longer paints at.
						f.Position = UDim2.fromOffset(rect.x - ox + thickness, rect.y - oy + thickness)
						-- ...and it starts WHERE THE LIFT IS, not where it is going
						-- (task 7 item 7): `aimFocusScale` below travels it to
						-- `liftScale` on the lift's own TweenInfo, from the geometry
						-- recorded here. A destination written on the frame the lift
						-- merely STARTS is a ring hanging 5 % outside its control for
						-- the whole 0.2 s.
						handle.focusFloatGeom = { w = rect.w, h = rect.h, t = thickness }
						local at = if handle.focusScale ~= nil then handle.focusScale.Scale else 1
						f.Size = UDim2.fromOffset(rect.w * at - 2 * thickness, rect.h * at - 2 * thickness)
					end
					f.ZIndex = 9999
					strokeParent = f
				end
				if ring == nil then
					local stroke = Instance.new("UIStroke")
					stroke.Name = "FocusRing"
					-- THEMED, not the constant this used to capture: a package's
					-- own accent, live, so a parchment ring is ink-and-gold rather
					-- than Facet Neutral's blue
					stroke.Color = focusColor()
					stroke.Thickness = thickness
					stroke.Transparency = 0
					stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					stroke.Parent = strokeParent
				else
					(ring :: UIStroke).Thickness = thickness;
					(ring :: UIStroke).Color = focusColor()
				end
			end
			-- ten-foot: a dedicated UIScale lifts the focused control (kept
			-- separate from the pressed-dip uiScale so the two never fight). A
			-- near display never creates it, so resting geometry is untouched.
			-- LIFT CAP (director live find, Xbox emulator 2026-07-21): the lift
			-- is a CARD idiom — it applies only when the lifted bounds still fit
			-- the screen. A near-full-width surface (the playlist filter field:
			-- 1888 x 1.05 = 1982 > 1920) keeps the strong ring with NO scale,
			-- or it overflows the viewport. UIScale grows about the anchor
			-- (top-left in this stack), so the check is right/bottom edges.
			-- Measured pre-lift: FocusScale is 1 whenever this branch runs on a
			-- fresh focus — the blur below aims it back to 1, and `adapter.park`
			-- WRITES it back to 1 for the recycling path, where the blur's tween
			-- is cancelled mid-travel rather than allowed to land.
			-- `lift`/`liftScale`: computed above now, beside the ring geometry —
			-- and AIMED with here, so the float ring's own travel (which reads
			-- the same number through `aimFocusScale`) can never be computed from
			-- a second expression that agrees today.
			if strong and lift and handle.focusScale == nil then
				local focusScale = Instance.new("UIScale")
				focusScale.Name = "FocusScale"
				focusScale.Parent = instance
				handle.focusScale = focusScale
				-- The ring follows the actual lift, including geometry changes
				-- mid-flight. A second size tween can retain an obsolete rect.
				focusScale:GetPropertyChangedSignal("Scale"):Connect(function()
					local float, geom = handle.focusRingFloat, handle.focusFloatGeom
					if float ~= nil and float.Parent ~= nil and geom ~= nil then
						float.Size = UDim2.fromOffset(
							geom.w * focusScale.Scale - 2 * geom.t,
							geom.h * focusScale.Scale - 2 * geom.t
						)
					end
				end)
			end
			-- ONE aim, for both halves of the lift: the UIScale when there is one,
			-- and the float ring's Size whether or not there is (a control whose
			-- lift was REFUSED still has a float to size, at liftScale = 1)
			if handle.focusScale ~= nil or handle.focusRingFloat ~= nil then
				aimFocusScale(handle, liftScale)
			end
		else
			if handle.focusScale ~= nil then
				aimFocusScale(handle, 1)
			end
		end
	end

	return {
		setFocusVisual = setFocusVisual,
	}
end

return screen_focus_visual
