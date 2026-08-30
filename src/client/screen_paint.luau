--!strict
-- ScreenPaint — the BESPOKE (non-native) paint vocabulary of the ScreenTarget
-- adapter, extracted from src/client/screen_target.luau for Studio's
-- 200_000-character `Source` WRITE cap. Over that cap a module silently stops
-- live-syncing into an open Studio session, so every live check against it
-- tests the built place rather than the edits on disk, once it is over the
-- 200,000-char Source WRITE cap.
--
-- THE NATURAL SIBLING OF src/client/screen_chrome. Chrome is the PACKAGE-ART
-- path (slots, decorations, layers); this is the BESPOKE path (surfaces, radii,
-- hairlines, strokes, shadows, gradients, tints, interactive states, the toggle
-- visual). The two already shared the paint-claim ledger, which stays in
-- screen_target and is handed to both. Strictly one-way, like screen_chrome: it
-- never requires back.
--
-- `new(ctx)` returns eighteen functions; screen_target rebinds each to a local
-- of its ORIGINAL name, so every call site in that file — and the source
-- contracts that anchor on them — read exactly as they did while this was
-- inline. Public surface unmoved: all of this is internal to screen_target.new,
-- whose contract is the `adapter` table it returns.
--
-- ctx:
--   style, nativeMode, palette (`COLOR`), hasUIShadow, hasPerCornerRadii
--                        construction-time facts, by value
--   instancesByPath, handlesByPath, chrome
--                        BY REFERENCE — the same tables/subsystem screen_target
--                        and screen_chrome hold
--   claimPaint, restorePaint, assertBespokePaint
--                        THE PAINT-CLAIM LEDGER, one authority per render
--                        property. It stays in the host and is passed down, the
--                        same way screen_chrome already receives
--                        `assertBespokePaint`
--   syncTags, isReducedMotion, toColor3
--                        host helpers
--   focusTreatment(), activeTheme(), snapshot()
--                        ACCESSORS, not values: these three host locals are
--                        REASSIGNED by `setActiveTheme` and the theme install,
--                        so a captured value would freeze at construction. Read
--                        through the call, exactly as screen_chrome reads its
--                        own `snapshot`.
--
-- `refreshToggleVisuals` and `refreshThemedPaint` are exported rather than
-- bound: screen_target forward-declares both above `setActiveTheme` (which calls
-- them) and assigns them from here — a local declared later is not an upvalue.
--
-- THE THREE THINGS A THEME COMMIT REPAINTS, all of them adapter-owned because no
-- StyleSheet rule can express them: `refreshFocusVisuals` (the host's, the ring's
-- colour), `refreshToggleVisuals` (the switch's palette) and `refreshThemedPaint`
-- (the `tint` channel and a `UI.Path`'s stroke role). Anything else here that
-- learns to read the palette joins the third.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local sheet_model = require("../tokens/sheet_model")
-- the paint-time half of the paint family: an authored radius/stroke TOKEN is
-- re-derived here against this target's own (display-adapted) style
local styling = require("../tokens/styling")
local chrome_slots = require("../tokens/chrome_slots")
local themeSnapshot = require("../themes/snapshot")
local authority = require("../render/authority")

local screen_paint = {}

function screen_paint.new(ctx: any)
	local style = ctx.style
	local nativeMode: boolean = ctx.nativeMode
	local COLOR = ctx.palette
	local hasUIShadow: boolean = ctx.hasUIShadow
	local hasPerCornerRadii: boolean = ctx.hasPerCornerRadii
	local instancesByPath = ctx.instancesByPath
	local handlesByPath = ctx.handlesByPath
	local toColor3 = ctx.toColor3
	local isReducedMotion = ctx.isReducedMotion
	-- the player's Background Transparency preference. An ACCESSOR,
	-- not a value, for the same reason `focusTreatment`/`activeTheme` below are:
	-- the renderer pushes a new number mid-session and a captured value would
	-- freeze at construction, which is precisely the "published but unread"
	-- failure this row exists to end
	local preferredTransparency = ctx.preferredTransparency
	-- the paint-claim ledger, owned by screen_target
	local claimPaint = ctx.claimPaint
	local restorePaint = ctx.restorePaint
	local assertBespokePaint = ctx.assertBespokePaint
	local syncTags = ctx.syncTags
	-- the chrome subsystem, bound to the names its call sites here already use
	local chrome = ctx.chrome
	local syncChrome = chrome.syncChrome
	local syncToggleArt = chrome.syncToggleArt
	local applySkinnedSuppression = chrome.applySkinnedSuppression
	-- reassigned by the host, so read through the call and never captured
	local focusTreatment = ctx.focusTreatment
	local activeTheme = ctx.activeTheme
	local snapshot = ctx.snapshot

	-- the colour a focus visual paints, in ONE place so the ring and the glow can
	-- never disagree about which accent is live. DECLARED BELOW `COLOR` on
	-- purpose: a local declared later is NOT an upvalue — placed above the
	-- table, this function captured a nil GLOBAL `COLOR` and crashed the first
	-- real boot (docs/lessons; the fake adapter never runs this file, so only a
	-- Studio session can catch it).
	local function focusColor(): Color3
		return focusTreatment().color or COLOR.accent
	end

	-- THE TOGGLE PALETTE, resolved live. Same shape and same reason as
	-- `focusColor` above, and DECLARED IN THE SAME PLACE for the same reason: it
	-- captures `COLOR`, so it must sit below the table.
	--
	-- The toggle's knob-and-track is value-driven paint, and a StyleSheet rule
	-- cannot see a value — so these two colours stay bespoke writes in BOTH modes
	-- (the `Toggle chrome` rule owns only their opacity). That is precisely why
	-- they were still painting from constants captured at construction, and why a
	-- parchment toggle rendered a Studio-Neutral blue pill.
	--
	-- WITH NO PACKAGE INSTALLED this returns exactly today's COLOR.* values, so
	-- every existing game and every existing test is byte-identical. The mapping
	-- itself lives in the pure `sheet_model.togglePalette` (which states why each
	-- role was chosen) so the adapter and the specs cannot disagree about it.
	local function togglePalette(): { trackOn: Color3, trackOff: Color3, knobOn: Color3, knobOff: Color3 }
		if activeTheme() == nil then
			return { trackOn = COLOR.accent, trackOff = COLOR.surface, knobOn = COLOR.content, knobOff = COLOR.content }
		end
		local p = sheet_model.togglePalette(activeTheme())
		return {
			trackOn = toColor3(p.trackOn),
			trackOff = toColor3(p.trackOff),
			knobOn = toColor3(p.knobOn),
			knobOff = toColor3(p.knobOff),
		}
	end

	-- THE PALETTE A CONTINUOUS VALUE RESOLVES AGAINST: the installed package theme,
	-- or the style this target was constructed with — the same two-step
	-- `togglePalette` above uses, so a tint resolves identically whether or not a
	-- package is installed, and a target with none is byte-identical to before.
	local function paletteTheme(): any
		return activeTheme() or { colors = style.colors, extra = style.extra }
	end

	-- forward-declared for `applyTint`'s bare-circle corner fix below (a local
	-- declared later is not an upvalue but a nil global); assigned at their
	-- ordinary position, unchanged, so every
	-- other call site reads exactly as it did before this fix
	local cornerRadiusFor: (any, number) -> UDim
	local corner: (Instance, number, boolean?, any?) -> ()

	-- THE CONTINUOUS-COLOUR WRITE.
	--
	-- One engine property per class — the one paint channel that class owns — and
	-- each is claimed before it is written (see claimPaint): the sheet cannot express
	-- a value, so the node takes the property and the dump says it did.
	--
	-- `Box` claims its TRANSPARENCY as well as its colour, and that is a decision
	-- rather than an oversight: a Frame is transparent until a surface says
	-- otherwise (the class-default rule in native mode, an explicit write in
	-- fallback), so a tint that only set BackgroundColor3 would paint an invisible
	-- fill — accepted and ignored, the failure class this framework keeps closing.
	-- A tinted Box paints. Text and Image claim only their colour, leaving
	-- TextTransparency to the disabled state and ImageTransparency to a dim
	-- treatment.
	--
	-- The resolution itself is PURE (`sheet_model.tintColor`) and shared with the
	-- headless FakeTarget, so the two adapters cannot disagree about the colour.
	--
	-- A `ViewportFrame` (UI.Stage) joins the ImageLabel branch on purpose: a stage's
	-- "picture" IS the scene it renders, and the engine multiplies it by the same
	-- ImageColor3/ImageTransparency pair (research 2026-08-08). Tinting the
	-- BACKGROUND instead — which the GuiObject fall-through would do — would paint
	-- the plate and leave the content untouched.
	local function applyTint(handle: any)
		local tint = handle.tint
		local instance = handle.instance
		if tint == nil then
			return
		end
		local color = toColor3(sheet_model.tintColor(paletteTheme(), tint, handle.class))
		-- THE TINT'S OWN ALPHA (2026-07-31). Absent it resolves to 0, which is what
		-- every branch below already wrote (Box) or left alone (Text/Image), so a
		-- tint that does not declare one is byte-identical. Declared, it claims the
		-- matching transparency property beside the colour — one channel, one claim
		-- pair, never a second opacity authority.
		local alpha = sheet_model.tintTransparency(tint, handle.class)
		local hasAlpha = (tint :: any).transparency ~= nil
		if handle.path2d ~= nil then
			-- a Path2D is not a GuiObject and no rule can select one: no claim needed.
			-- Its pre-tint colour is recorded here rather than through claimPaint,
			-- which reads GuiObject properties, so a release restores the role's stroke
			-- instead of guessing at the default.
			if handle.tintPathRestore == nil then
				handle.tintPathRestore = handle.path2d.Color3
			end
			handle.path2d.Color3 = color
			return
		end
		if instance:IsA("ImageLabel") or instance:IsA("ViewportFrame") then
			claimPaint(handle, "ImageColor3")
			assertBespokePaint("ImageColor3", handle)
			instance.ImageColor3 = color
			if hasAlpha then
				claimPaint(handle, "ImageTransparency")
				assertBespokePaint("ImageTransparency", handle)
				instance.ImageTransparency = alpha
			end
		elseif instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			claimPaint(handle, "TextColor3")
			assertBespokePaint("TextColor3", handle)
			instance.TextColor3 = color
			if hasAlpha then
				claimPaint(handle, "TextTransparency")
				assertBespokePaint("TextTransparency", handle)
				instance.TextTransparency = alpha
				if handle.labelInstance ~= nil then
					handle.labelInstance.TextTransparency = alpha
				end
			end
			-- ...AND THE LIFTED LABEL, which is the instance that actually draws the
			-- glyphs on a skinned node (the node's own text is suppressed under the
			-- art). Same reason the `textSize` write below reaches both: a tint on the
			-- node and an untinted label is measure-versus-paint one layer down.
			if handle.labelInstance ~= nil then
				handle.labelInstance.TextColor3 = color
			end
		elseif instance:IsA("GuiObject") then
			claimPaint(handle, "BackgroundColor3")
			claimPaint(handle, "BackgroundTransparency")
			assertBespokePaint("BackgroundColor3", handle)
			assertBespokePaint("BackgroundTransparency", handle)
			instance.BackgroundColor3 = color
			instance.BackgroundTransparency = alpha
			--[[ ...AND THE FILL ITSELF IS A TAG, because the write above could not
				take it (director report 2026-08-15, the `canvas-group` demo whose
				three plates were never painted at all).

				`BackgroundTransparency` is native-sheet-owned and the class-default
				rule paints an un-surfaced node INVISIBLE. The tint's default alpha is
				0 — which is `Frame.BackgroundTransparency`'s class default — and the
				engine decides "explicit" BY VALUE, so that write marks nothing
				explicit and the rule goes on winning. Measured live on the plate:
				raw 0 / GetStyled 1; write 0.001 -> GetStyled 0.001; write 0 again ->
				GetStyled 1.

				The COLOUR still has to be the claim above — a rule cannot carry
				per-node data — so the two halves of one tint travel different roads
				on purpose. In bespoke mode `syncTags` returns immediately and the
				explicit write is the whole story, exactly as before. ]]
			handle.tintFill = true
			syncTags(handle)
			--[[ A BARE `shape = "circle"` NODE NEVER REACHES `applySurface` (task EXTRACT, closing task PAINT's disclosed boundary). `applySurface`
				is the only fallback-mode writer that materialises a real UICorner
				(`corner()`, below); a node that never carries a `surface` prop at all
				never calls it, so the fallback `shape` write (screen_props.luau) has
				nothing to re-radius and `shape = "circle"` is accepted-and-ignored —
				until THIS write paints a square fill directly onto it. Gated on
				`declaredSurface == nil` (set unconditionally, both modes, the moment a
				surface IS ever authored — screen_paint's `applySurface`) so a node that
				carries a real surface is untouched: that node's UICorner life cycle
				belongs to `applySurface` alone, and creating a second one here would be
				exactly the "two paint decisions that can drift" this file's `corner()`
				comment already warns about. Native mode is excluded because the
				phantom `.facet-shape-circle::UICorner` sheet rule already rounds it
				for free (screen_chrome). Residual, disclosed rather than silently
				accepted: a node that starts bare and is GIVEN a surface later (after
				this write already ran) still collides with `applySurface`'s own
				`corner()` call, because neither checks for an existing sibling — the
				same latent double-instantiation CLASS every non-"plain" surface
				TRANSITION already carries, one file up. THE CLASS IS OLD; THIS ENTRY
				PATH IS NOT (review Minor-1, task EXTRACT fix round 1): before this
				write existed, a bare tinted circle created NO UICorner at all, so
				this specific route into the class was unreachable — this fix is what
				opens it. Closing the class for every caller is the "audit
				`applySurface`'s full call graph" work this task's own report named as
				bigger than this round owes. ]]
			if not nativeMode and handle.shape == "circle" and handle.declaredSurface == nil then
				if instance:FindFirstChildOfClass("UICorner") == nil then
					corner(instance, style.radii.control, nil, handle)
				end
			end
		end
	end

	-- releasing a tint restores what the property held when the claim was taken.
	-- The claim itself does not come back to the sheet — the engine has no such
	-- operation (see the claims block above), which the reference states.
	local function releaseTint(handle: any)
		handle.tint = nil
		-- the fill tag goes with it, or a node whose tint was cleared keeps a fill
		-- nothing asked for — the "tag added outside the desired set" defect class,
		-- inverted (screen_target's syncTags says why the set is diffed at all)
		handle.tintFill = nil
		syncTags(handle)
		if handle.path2d ~= nil then
			if handle.tintPathRestore ~= nil then
				handle.path2d.Color3 = handle.tintPathRestore
				handle.tintPathRestore = nil
			end
			return
		end
		for _, prop in
			{
				"ImageColor3",
				"ImageTransparency",
				"TextColor3",
				"TextTransparency",
				"BackgroundColor3",
				"BackgroundTransparency",
			}
		do
			restorePaint(handle, prop)
		end
		if handle.labelInstance ~= nil and handle.paintRestore ~= nil and handle.paintRestore.TextColor3 ~= nil then
			handle.labelInstance.TextColor3 = handle.paintRestore.TextColor3
		end
	end

	-- ===== A `UI.Path`'S STROKE ROLE (director report 2026-08-14) ==========
	--
	-- *"when i changed to the parchment theme, the spinner stayed blue."*
	--
	-- A Path2D is NOT a GuiObject and no StyleSheet rule can select one (see
	-- applyTint's Path branch), so its colour is adapter-owned paint in every
	-- mode — exactly like the focus ring and the toggle palette above it. It used
	-- to resolve against `COLOR`, the palette this target was CONSTRUCTED with, so
	-- a stroked path wore Studio Neutral under every package that was ever
	-- installed. That is the same theme-blindness the focus ring carried before
	-- the 2026-07-25 director round (screen_target's focus-treatment block, defect
	-- (1)) — one seam over, and never fixed because a path has no interactive
	-- state to make it obvious. The circular ProgressView is a Path, which is why
	-- its accent arc was blue on a parchment screen.
	--
	-- WITH NO PACKAGE INSTALLED `paletteTheme()` is the constructed style, so
	-- every existing game and every existing test is byte-identical.
	local PATH_ROLE_TOKEN: { [string]: string } = { accent = "accent", secondary = "contentSecondary" }
	local function applyPathRole(handle: any)
		if handle.path2d == nil then
			return
		end
		local color =
			toColor3(sheet_model.paletteColor(paletteTheme(), PATH_ROLE_TOKEN[tostring(handle.pathRole)] or "content"))
		-- A LIVE TINT OWNS `Path2D.Color3` — applyTint records the pre-tint colour
		-- in `tintPathRestore` and paints over it — so while one is claimed the
		-- role's colour is what a RELEASE returns to, not what is painted now.
		-- Writing the instance here would silently overwrite the claim.
		if handle.tintPathRestore ~= nil then
			handle.tintPathRestore = color
		else
			handle.path2d.Color3 = color
		end
	end

	-- ===== EVERY ADAPTER-OWNED PAINT THAT READS THE PALETTE, RE-RESOLVED =====
	--
	-- A theme commit is a RE-SOLVE and never a rebuild — which is
	-- what keeps mount identity, focus and scroll alive across a swap, and is
	-- exactly why a PAINT-only property could be missed. `themeMetrics` is one of
	-- the renderer's coalesced GEOMETRY keys, so a swap re-derives everything the
	-- SOLVER reads and nothing the ADAPTER paints; a node whose layout did not
	-- change is never re-visited, and a `tint` is paint, not geometry.
	--
	-- The focus ring and the toggle each got their own refresh at the moment a
	-- director found them stale. The `tint` channel and the Path role never did:
	-- measured live 2026-08-14, installing Fantasy Parchment (accent
	-- rgb(122,72,26)) over a mounted surface left a tinted Box and both of a
	-- circular ProgressView's paths reading rgb(44,98,210). A tint whose value is
	-- REACTIVE self-heals on its next write (the dot spinner recolours on the next
	-- animation tick), which is why this presented as "only some things are
	-- stale"; a STATIC tint is stale for the rest of its life.
	--
	-- ONE sweep, beside refreshFocusVisuals/refreshToggleVisuals, so the next
	-- adapter-owned palette consumer has an obvious place to join rather than
	-- becoming a fourth seam that a director finds.
	local function refreshThemedPaint()
		for _, handle in handlesByPath do
			applyPathRole(handle) -- no-op unless the node is a Path
			if handle.tint ~= nil then
				-- LAST, for the standing reason: the tint is the final word on the
				-- property it claimed.
				applyTint(handle)
			end
		end
	end

	--[[ THE BACKDROP REPAINT. A theme commit is not the only thing that
		can stale an adapter-owned paint: so can a PREFERENCE. When the player moves
		Background Transparency the modal in front of them is already on screen, so
		the new number has to reach the backdrop that is painted, not only the next
		one to be created.

		BESPOKE ONLY, and the early return is load-bearing: in native mode the
		`Scrim backdrop` rule is the single writer of this property, and an explicit
		write here would not lose a frame — it would make the rule's value unreadable
		for good (measured). The native side moves the RULE
		instead (`screen_target.setPreferredTransparency`). ]]
	local function refreshBackdropPaint()
		if nativeMode then
			return
		end
		for _, handle in handlesByPath do
			if handle.declaredSurface == "scrim" then
				local instance = instancesByPath[handle.path]
				if instance ~= nil and instance:IsA("GuiObject") then
					instance.BackgroundTransparency =
						sheet_model.backdropTransparency(style.extra.scrimOpacity, preferredTransparency())
				end
			end
		end
	end

	-- normalized UI.stroke data -> ONE bespoke UIStroke under the node (style
	-- authority). Named from the manifest's own constant, reused rather than
	-- re-created (a reactive pulse must never stack two borders), and destroyed when
	-- the declaration goes away.
	--
	-- NO `assertBespokePaint`: an authored stroke is a DECLARED override, the same
	-- standing UI.corners/UI.shadow have. It coexists with a theme's phantom
	-- ::UIStroke rule — the engine renders both — so it never
	-- suppresses theme chrome and never has to fight for it.
	local function applyStroke(instance: Instance, stroke: any, handle: any)
		if not instance:IsA("GuiObject") then
			return
		end
		if stroke == nil then
			if handle.strokeInstance ~= nil then
				handle.strokeInstance:Destroy()
				handle.strokeInstance = nil
			end
			return
		end
		local live = handle.strokeInstance
		if live == nil then
			live = Instance.new("UIStroke")
			live.Name = authority.INSTANCE_NAMES.stroke
			handle.strokeInstance = live
		end
		-- …and the same door for an authored stroke's thickness
		local painted = styling.paintStroke(stroke, style)
		live.Color = toColor3(painted.color)
		live.Transparency = painted.transparency
		live.Thickness = painted.thickness
		-- Border, ALWAYS: ApplyStrokeMode defaults to Contextual, which on a text
		-- node strokes the GLYPHS instead of the box (the same engine truth the
		-- phantom stroke rules carry)
		live.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		live.Parent = instance
	end

	local function motionInfo(duration: number): TweenInfo
		return TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end

	-- THE PRESS DIP'S UIScale, CREATED ON FIRST PRESS AND NOT BEFORE.
	--
	-- Measured on the performance lab: a 5-row window held 249 instances, and **all 25
	-- UIScale objects sat at Scale = 1.0** — one per interactive control, created at
	-- construction for a dip that had not happened and on most controls never will.
	-- That is 10% of every instance on the surface doing nothing, and it is paid by
	-- every Facet consumer with buttons on screen, not just this fixture.
	--
	-- ONE SCALE, SHARED WITH THE MOTION CHANNEL. The engine honours a single UIScale
	-- per instance, so the press dip and a running motion must not each own one — the
	-- existing "the motion scale SHARES the press dip's UIScale" contract. This
	-- accessor is the single place either path gets one, so laziness cannot
	-- accidentally produce two.
	local function ensureScale(instance: Instance, handle: any): UIScale
		local existing = handle.motionScale or handle.uiScale
		if existing ~= nil then
			return existing
		end
		local scale = Instance.new("UIScale")
		scale.Name = authority.INSTANCE_NAMES.motionScale
		scale.Parent = instance
		handle.uiScale = scale
		return scale
	end

	--[[ WHAT THE DIP MUST COME BACK TO (fixed 2026-08-14).

		The engine honours ONE `UIScale` per object, so an authored `scale` and the
		press dip write the same instance. The dip used to tween to
		`style.extra.pressedScale` and recover to an absolute **`1`** — so the first
		release of a Button carrying an authored scale destroyed it permanently, and
		nothing re-asserted it (the renderer's write is memoized on the composed
		value, which had not changed).

		`handle.restingScale` is that composed value, recorded by
		`applyPresentationPaint` at the moment it writes it. The dip is now a
		RELATIVE gesture — `resting x pressedScale` down, `resting` back — which is
		what it always meant: a 1.5x badge dips to 1.4775x and returns to 1.5x, and
		a control with no authored scale is byte-identical to before (resting = 1).

		One function rather than four literals, because the version with four
		literals is exactly how three of them stayed at `1`. ]]
	local function restingScale(handle: any): number
		return handle.restingScale or 1
	end

	-- pressed-dip presentation for native mode: the fills belong to the sheet
	-- (:Press rules), but the quick UIScale dip is value-driven presentation
	-- and stays bespoke (plan §6.5) — wired WITHOUT any fill writes.
	local function wireNativePressDip(button: TextButton, handle: any)
		local function recover()
			-- nothing to recover if no dip ever happened, and nothing to create either
			local scale = handle.motionScale or handle.uiScale
			if scale == nil then
				return
			end
			local resting = restingScale(handle)
			if not isReducedMotion() and not handle.suppressStates then
				TweenService:Create(scale, motionInfo(style.motion.fast), { Scale = resting }):Play()
			else
				scale.Scale = resting
			end
		end
		button.MouseButton1Down:Connect(function()
			if not isReducedMotion() and not handle.suppressStates then
				TweenService:Create(
					ensureScale(button, handle),
					motionInfo(style.motion.fast),
					{ Scale = restingScale(handle) * style.extra.pressedScale }
				):Play()
			end
		end)
		button.MouseButton1Up:Connect(recover)
		button.MouseLeave:Connect(recover)
	end

	-- THE DISC'S RADIUS, FALLBACK HALF (feature round 2026-07-26). In native mode
	-- the pill is the sheet's phantom `.facet-shape-circle::UICorner` rule; on the
	-- bespoke path the adapter owns the real UICorner, so the SAME fact has to
	-- reach it here. One function, so "a circle is UDim(0.5, 0)" is one decision
	-- across both paint paths rather than two that drift.
	cornerRadiusFor = function(handle: any, radius: number): UDim
		if type(handle) == "table" and handle.shape == "circle" then
			return UDim.new(0.5, 0)
		end
		return UDim.new(0, radius)
	end

	-- sanctionedOverride: the toggle knob-track assembly's declared real-child
	-- chrome (authority.luau native-owned notes) — the ONLY callers allowed to
	-- materialize modifier instances in native mode
	corner = function(instance: Instance, radius: number, sanctionedOverride: boolean?, handle: any?)
		if not sanctionedOverride then
			assertBespokePaint("CornerRadius")
		end
		local uiCorner = Instance.new("UICorner")
		uiCorner.CornerRadius = cornerRadiusFor(handle, radius)
		uiCorner.Parent = instance
	end

	-- normalized UI.shadow data -> a UIShadow instance under the node (style
	-- authority; purely visual — never enters layout). No-capability engines
	-- keep the declaration as data only (headless fallback).
	local function applyShadow(instance: Instance, shadow: any, handle: any)
		if not hasUIShadow or not instance:IsA("GuiObject") then
			return
		end
		local shadowInstance = handle.shadowInstance
		if shadowInstance == nil then
			shadowInstance = Instance.new("UIShadow" :: any)
			handle.shadowInstance = shadowInstance
		end
		shadowInstance.BlurRadius = UDim.new(shadow.blurRadius.scale, shadow.blurRadius.offset)
		shadowInstance.Color = Color3.new(shadow.color.r, shadow.color.g, shadow.color.b)
		shadowInstance.Transparency = shadow.transparency
		shadowInstance.Offset =
			UDim2.new(shadow.offset.x.scale, shadow.offset.x.offset, shadow.offset.y.scale, shadow.offset.y.offset)
		shadowInstance.Spread =
			UDim2.new(shadow.spread.x.scale, shadow.spread.x.offset, shadow.spread.y.scale, shadow.spread.y.offset)
		shadowInstance.ZIndex = shadow.zIndex
		shadowInstance.Enabled = shadow.enabled
		shadowInstance.Parent = instance
	end

	-- normalized UI.gradient data -> ONE UIGradient under the node (style
	-- authority; purely visual — never enters layout).
	--
	-- WHY AN INSTANCE AND NOT A RULE (the whole rung-2 argument). A theme's
	-- gradients are phantom `::UIGradient` MODIFIER rules with zero children: a
	-- rule matches a CLASS of nodes, which is exactly right for a theme and
	-- exactly wrong for "this one card". So the per-view modifier follows
	-- `UI.shadow`'s architecture — a bespoke adapter-owned child — and the real
	-- child is what makes the view win on this node (measured live).
	--
	-- Named so it is identifiable in a live tree, and REUSED rather than
	-- re-created, so a reactive gradient (or a theme swap that re-applies style
	-- props) can never leave two ramps stacked on one node.
	local function applyGradient(instance: Instance, gradient: any, handle: any)
		if not instance:IsA("GuiObject") then
			return
		end
		local live = handle.gradientInstance
		if live == nil then
			live = Instance.new("UIGradient")
			live.Name = "FacetGradient"
			handle.gradientInstance = live
		end
		local keypoints: { ColorSequenceKeypoint } = {}
		for _, stop in gradient.colors do
			table.insert(keypoints, ColorSequenceKeypoint.new(stop.t, Color3.new(stop.r, stop.g, stop.b)))
		end
		live.Color = ColorSequence.new(keypoints)
		if gradient.transparency ~= nil then
			local alpha: { NumberSequenceKeypoint } = {}
			for _, stop in gradient.transparency do
				table.insert(alpha, NumberSequenceKeypoint.new(stop.t, stop.v))
			end
			live.Transparency = NumberSequence.new(alpha)
		else
			live.Transparency = NumberSequence.new(0)
		end
		live.Rotation = gradient.rotation
		live.Enabled = gradient.enabled
		live.Parent = instance
	end

	-- normalized UI.corners data -> ONE UICorner in exactly ONE form
	-- (uniform alias or four per-corner radii — never both; engine hazard)
	local function applyCorners(instance: Instance, cornersData: any)
		if not instance:IsA("GuiObject") then
			return
		end
		-- the AUTHORED token re-derived for this target's distance (fix round 2)
		local corners = styling.paintCorners(cornersData, style)
		local uiCorner = instance:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
		if corners.form == "uniform" then
			uiCorner.CornerRadius = UDim.new(0, corners.radius)
		elseif hasPerCornerRadii then
			(uiCorner :: any).TopLeftRadius = UDim.new(0, corners.topLeft);
			(uiCorner :: any).TopRightRadius = UDim.new(0, corners.topRight);
			(uiCorner :: any).BottomLeftRadius = UDim.new(0, corners.bottomLeft);
			(uiCorner :: any).BottomRightRadius = UDim.new(0, corners.bottomRight)
		else
			-- old-engine fallback: alias with the largest declared radius
			local top = math.max(corners.topLeft, corners.topRight, corners.bottomLeft, corners.bottomRight)
			uiCorner.CornerRadius = UDim.new(0, top)
		end
		uiCorner.Parent = instance
	end

	-- A STROKE NOBODY CAN SEE IS NOT WORTH AN INSTANCE. A theme package may set
	-- `strokes.hairline = 0` or a fully transparent hairline; both shipped themes
	-- keep it visible, so this saves nothing on them — but a theme that turns
	-- hairlines off would otherwise pay 30 invisible `UIStroke` objects per five
	-- rows (measured shape: 30 strokes on a 137-GuiObject surface). The guard is one
	-- comparison at construction and cannot change what is on screen: if it declines
	-- to build the stroke, the stroke would have drawn nothing.
	local function hairlineWouldShow(): boolean
		local thickness = style.strokes.hairline
		local opacity = style.extra.hairlineOpacity
		if type(thickness) == "number" and thickness <= 0 then
			return false
		end
		if type(opacity) == "number" and opacity >= 1 then
			return false
		end
		return true
	end

	local function hairline(instance: Instance, sanctionedOverride: boolean?)
		if not hairlineWouldShow() then
			return
		end
		if not sanctionedOverride then
			assertBespokePaint("StrokeColor")
		end
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Hairline"
		stroke.Color = COLOR.hairline
		stroke.Transparency = style.extra.hairlineOpacity
		stroke.Thickness = style.strokes.hairline
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = instance
	end

	-- surface roles for containers/rows (style authority; opted in via the
	-- blueprint `surface` prop): raised | control | scrim
	--
	-- NATIVE MODE: the surface hint becomes a tag, never a write —
	-- the sheet's surface rules own fills/transparency and its ::UICorner/
	-- ::UIStroke rules CREATE the phantom chrome (spike m2: materializing a
	-- real modifier instance here would silently defeat those rules).
	--[[ `plain` AND `scrim` PART WAYS ON `suppressStates` (task PAINT fix round
		1, RED-TEAM finding 1, 2026-08-28). Both stay chrome-less — `nativeSurface`
		is nil either way, so neither ever earns a `facet-surface-*` tag and
		`classifyTags`'s own `suppressed` check (`sheet_model.luau`) independently
		refuses BOTH the `facet-interactive` and `facet-selected` tags for
		either one, regardless of `nativeInteractive` below — that part of the
		contract is unchanged and is exactly why `nativeInteractive` staying
		`false` for `plain` costs nothing: no tag exists for it to gate.

		`suppressStates` is a DIFFERENT gate, read by exactly two consumers,
		neither of them tag-based: `wireNativePressDip`'s press/release tween
		(`not handle.suppressStates`) and this file's fallback-mode
		`wireInteractiveStates`. It is presentation-only — a `UIScale` dip on
		press, nothing to do with fill, corner or hairline — so an activation
		surface that opts out of decorative chrome (`plain`) has no reason to
		also opt out of feeling pressed. A `scrim` is not a control the player
		activates for its own sake (a backdrop dismiss-catcher), so it keeps
		BOTH flags suppressed, unchanged. Found live: `examples/reference/
		p1_glade`'s `gladeCard` went `surface = "plain"` to fix a corner-radius
		mismatch (item 11) and silently lost all pointer/touch tap feedback
		with it — the two concerns had never been asked to separate before. ]]
	local function applySurfaceNative(instance: GuiObject, surface: string, handle: any)
		handle.nativeSurface = if surface == "plain" then nil else surface
		if surface == "scrim" then
			handle.suppressStates = true
			handle.nativeInteractive = false
		else
			handle.suppressStates = false
			-- `plain` is chrome-less but still every bit the control its class
			-- says it is (a Button/Toggle) -- see the header above for why this
			-- is safe: classifyTags' own `suppressed` check keeps the tag from
			-- ever reaching the sheet either way.
			handle.nativeInteractive = handle.class == "Button" or handle.class == "Toggle"
			if surface == "accent" and instance:IsA("TextButton") then
				-- primary-action treatment: sheet rules carry accent fill + label
				handle.surfaceKind = "accent"
			end
		end
		if surface == "badge" and instance:IsA("ImageLabel") then
			instance.ScaleType = Enum.ScaleType.Crop -- not a styled property
		end
		syncTags(handle)
	end

	local function applySurface(instance: GuiObject, surface: string, handle: any?)
		if handle ~= nil then
			-- recorded in BOTH modes: decoration-slot classification is a
			-- semantic decision and must not depend on whether paint is native
			handle.declaredSurface = surface
			syncChrome(handle)
		end
		if nativeMode and handle ~= nil then
			applySurfaceNative(instance, surface, handle)
			return
		end
		assertBespokePaint("BackgroundColor3")
		if surface == "base" then
			instance.BackgroundTransparency = 0
			instance.BackgroundColor3 = COLOR.surface
		elseif surface == "raised" then
			instance.BackgroundTransparency = 0
			instance.BackgroundColor3 = COLOR.surfaceStrong
			corner(instance, style.radii.panel, nil, handle)
			hairline(instance)
		elseif surface == "control" then
			instance.BackgroundTransparency = 0
			instance.BackgroundColor3 = COLOR.control
			corner(instance, style.radii.control, nil, handle)
		elseif surface == "badge" then
			-- circular identity badges (racer headshots / initial chips):
			-- surface-raised fill behind a cropped circle — matches the game's
			-- avatar-badge convention (fallback fill visible until art loads)
			instance.BackgroundTransparency = 0
			instance.BackgroundColor3 = COLOR.surfaceStrong
			local circle = Instance.new("UICorner")
			circle.CornerRadius = UDim.new(0.5, 0)
			circle.Parent = instance
			if instance:IsA("ImageLabel") then
				instance.ScaleType = Enum.ScaleType.Crop
			end
		elseif surface == "chip" then
			-- floating drag chips: control fill + a hairline OUTLINE so a
			-- stacked group reads as distinct cards (director 2026-07-20)
			instance.BackgroundTransparency = 0
			instance.BackgroundColor3 = COLOR.control
			corner(instance, style.radii.control, nil, handle)
			hairline(instance)
		elseif surface == "plain" then
			-- chrome-less control: ONLY the content shows (in-cell glyph
			-- buttons like a segmented picker's options, a match3 tile's full-
			-- bleed hit target, a region's cover). No fill, no corner, no
			-- hairline; the focus ring still applies for gamepad reachability.
			--
			-- STILL LIVE INTERACTION FEEDBACK (task PAINT fix round 1, RED-TEAM
			-- finding 1, 2026-08-28): `suppressStates` deliberately stays
			-- false/unset here now, so `wireInteractiveStates`'s press-dip
			-- (`ensureScale`/`TweenService`, pure presentation, no fill/corner
			-- read or write) still plays on press and release. The hover/press
			-- FILL tween below also stays live, but it costs nothing to leave
			-- on: `setFill` only ever writes `BackgroundColor3`, never touches
			-- `BackgroundTransparency`, which this branch just forced to `1` and
			-- nothing downstream reverts -- so the colour changes underneath an
			-- invisible background, harmlessly. See `applySurfaceNative` above
			-- for the identical split on the native path.
			instance.BackgroundTransparency = 1
			local chrome = instance:FindFirstChild("Hairline")
			if chrome then
				chrome:Destroy()
			end
			for _, child in instance:GetChildren() do
				if child:IsA("UICorner") then
					child:Destroy()
				end
			end
			-- explicit, not merely "left unset": `surface` is reactively
			-- authorable, and a Button that ever wore `scrim` (which DOES set
			-- this true, below) before flipping to `plain` must not inherit
			-- that suppression by omission.
			if handle ~= nil then
				handle.suppressStates = false
			end
		elseif surface == "accent" then
			-- on a Button this is the PRIMARY-ACTION treatment: accent fill,
			-- high-contrast label, hover/pressed states in accent space
			-- (director report 2026-07-20: the neutral control fill did not
			-- read as a button). On plain frames it stays the flat indicator
			-- fill (table resize preview, drop indicator).
			instance.BackgroundTransparency = 0
			instance.BackgroundColor3 = COLOR.accent
			if handle ~= nil and instance:IsA("TextButton") then
				handle.surfaceKind = "accent"
				instance.TextColor3 = COLOR.onAccent
				if handle.applyRestingFill ~= nil then
					handle.applyRestingFill()
				end
			end
		elseif surface == "scrim" then
			-- a scrim is a backdrop, not a control: dimmed fill, no chrome,
			-- and no hover/pressed feedback even when it is a Button
			--
			-- ...and it is the ONE background in this whole vocabulary that is
			-- neither 0 nor 1, which is why it is the one that reads the player's
			-- Background Transparency preference. The composition is
			-- shared with the native sheet's own patch of the same value, so the
			-- two paint modes cannot drift apart about what the player asked for.
			instance.BackgroundTransparency =
				sheet_model.backdropTransparency(style.extra.scrimOpacity, preferredTransparency())
			instance.BackgroundColor3 = toColor3(style.colors.surface)
			local chrome = instance:FindFirstChild("Hairline")
			if chrome then
				chrome:Destroy()
			end
			for _, child in instance:GetChildren() do
				if child:IsA("UICorner") then
					child:Destroy()
				end
			end
			if handle ~= nil then
				handle.suppressStates = true
			end
		end
		-- THE IMAGE IS THE BUTTON, again: every branch above just painted a
		-- plate, a corner and possibly a hairline, and on a skinned node all
		-- three sit UNDER the art. Re-suppress here rather than branching inside
		-- each case, so no future surface can quietly reintroduce the border the
		-- director asked us to remove.
		if handle ~= nil and handle.chrome ~= nil then
			applySkinnedSuppression(instance, true)
		end
	end

	-- interactive state feedback for Buttons and Toggle rows: rest/hover/
	-- pressed fills + a quick pressed dip (UIScale), reduced-motion aware
	local function wireInteractiveStates(button: TextButton, handle: any)
		assertBespokePaint("BackgroundColor3")
		button.BackgroundTransparency = 0
		button.BackgroundColor3 = COLOR.control
		corner(button, style.radii.control, nil, handle)
		hairline(button)
		-- resting fill honors selection: hover-leave on a selected row must
		-- restore controlSelected, never strip the tint (live-found 2026-07-19)
		local function restingFill(): Color3
			if handle.surfaceKind == "accent" then
				return COLOR.accent
			end
			return if handle.isSelected then COLOR.controlSelected else COLOR.control
		end
		local function hoverFill(): Color3
			if handle.surfaceKind == "accent" then
				return COLOR.accent:Lerp(Color3.new(1, 1, 1), 0.12)
			end
			return COLOR.controlHover
		end
		local function pressedFill(): Color3
			if handle.surfaceKind == "accent" then
				return COLOR.accent:Lerp(Color3.new(0, 0, 0), 0.18)
			end
			return COLOR.controlPressed
		end
		local function setFill(color: Color3, instant: boolean?, chromeState_: string?)
			if handle.suppressStates then
				return
			end
			-- THE IMAGE IS THE BUTTON (fallback mode). A skinned node's plate is
			-- suppressed, so painting a fill on it would either do nothing or
			-- punch a coloured rectangle out from behind the art. The interaction
			-- feedback is the decoration's TINT instead — the same ladder the
			-- native `Chrome — <slot> hover/pressed` rules apply.
			if handle.chrome ~= nil then
				if chromeState_ ~= nil then
					local tint = (chrome_slots.TINT :: any)[chromeState_]
					if tint ~= nil then
						handle.chrome.ImageColor3 = Color3.new(tint, tint, tint)
					end
				end
				return
			end
			if instant or isReducedMotion() then
				button.BackgroundColor3 = color
			else
				TweenService:Create(button, motionInfo(style.motion.fast), { BackgroundColor3 = color }):Play()
			end
		end
		handle.applyRestingFill = function()
			setFill(restingFill(), true, "rest")
		end
		-- the hover FILL is exposed for enableHover (UI-PARADIGM-001): the renderer
		-- wires MouseEnter to it ONLY when the pointer class is live, so a
		-- pure-touch device allocates no hover wiring. Pressed + the leave-recovery
		-- below stay unconditional (touch presses fire MouseButton1Down/Up too).
		handle.applyHoverFill = function()
			if button.Active ~= false then
				setFill(hoverFill(), nil, "hover")
			end
		end
		-- RECOVERING THE PRESSED DIP IS ONE DECISION, NOT TWO (found live 2026-08-06,
		-- playing the tutorial gallery: every click emitted
		-- `TweenService:Create failed because Instance is null` from the
		-- MouseButton1Up handler below).
		--
		-- The dip is created LAZILY -- `ensureScale` makes the UIScale on the first
		-- press, and the inert-container elision means most buttons carry none until
		-- then. MouseLeave already read `handle.motionScale or handle.uiScale` and
		-- nil-guarded it; MouseButton1Up referenced a bare `scale`, which is declared
		-- nowhere in this scope and therefore resolved to a nil GLOBAL. So the release
		-- path threw on EVERY press and the dip never recovered on release -- only
		-- when the pointer happened to leave the button afterwards.
		--
		-- The native path (`wireNativePressDip`) already had exactly this function.
		-- Two copies of one rule is how the second copy went stale, so there is one
		-- here now and both connections use it.
		local function recoverPressDip()
			-- `uiScale` ONLY, never `motionScale` (architecture review M-3).
			-- `handle.motionScale` belongs to the PRESENTATION authority — it is
			-- created by `applyPresentationPaint` for `setPresentationTransform`, and
			-- `parkEligible` refuses to recycle a handle that has one. Restoring it
			-- to 1 from the interaction path is two authorities writing one engine
			-- property with the lower-priority one winning last: a button released
			-- while a pop or an enter transition is live would have its presentation
			-- scale snapped to 1, and nothing re-asserts it. The old `MouseLeave`
			-- handler had this; extending it to every mouse RELEASE would have made
			-- a rare exposure a common one.
			--
			-- nothing to recover if no dip ever happened, and nothing to create either
			local scale = handle.uiScale
			if scale == nil then
				return
			end
			-- ...and it comes back to the AUTHORED resting scale, not to 1 (see
			-- `restingScale` above): an absolute target is what destroyed an
			-- authored `scale` on the first release
			local resting = restingScale(handle)
			if not isReducedMotion() and not handle.suppressStates then
				TweenService:Create(scale, motionInfo(style.motion.fast), { Scale = resting }):Play()
			else
				scale.Scale = resting
			end
		end
		button.MouseLeave:Connect(function()
			setFill(restingFill(), nil, "rest")
			-- the pressed dip must ALWAYS recover: MouseButton1Up never fires
			-- when the button is released off-target (or the row is dragged
			-- away), which left rows visibly shrunken (director hand-test
			-- 2026-07-20: "one row is narrower than the others")
			recoverPressDip()
		end)
		button.MouseButton1Down:Connect(function()
			setFill(pressedFill(), true, "pressed")
			if not isReducedMotion() and not handle.suppressStates then
				TweenService:Create(
					ensureScale(button, handle),
					motionInfo(style.motion.fast),
					{ Scale = restingScale(handle) * style.extra.pressedScale }
				):Play()
			end
		end)
		button.MouseButton1Up:Connect(function()
			-- verifier F4: the release fill is hover ONLY where hover is wired
			-- (pointer live). Touch taps fire MouseButton1Down/Up too, and a
			-- pure-touch device has no MouseLeave to recover a leaked hover
			-- tint — release must return to RESTING there.
			if handle.hoverStateConn ~= nil then
				setFill(hoverFill(), nil, "hover")
			else
				setFill(restingFill(), nil, "rest")
			end
			recoverPressDip()
		end)
	end

	-- THE KNOB'S TWO STOPS, written against the BUTTON (see buildToggleVisual).
	-- The track is 44 wide with its right edge at `width - 12`, so its left edge is
	-- `width - 56` and the knob's old `+2`/`+22` offsets inside it are these two
	-- numbers. Named constants because "travel is byte-identical, skinned or flat"
	-- is an assertion this stage makes, and a magic number in two places is how a
	-- travel assertion quietly stops being about the same geometry.
	local TOGGLE_KNOB_OFF = UDim2.new(1, -54, 0.5, 0)
	local TOGGLE_KNOB_ON = UDim2.new(1, -34, 0.5, 0)

	-- THE LABEL COLUMN IS THE COLUMN THE SOLVER RESERVED (director round 9,
	-- found live 2026-07-26). It used to be built from `style.space.*` — the
	-- style captured when this ScreenTarget was CONSTRUCTED — while the measure
	-- seam reserved it from the LIVE snapshot. Under Studio Neutral the two
	-- agree to the byte (space.s + 4 = 12 = trackInset, space.m = 16), which is
	-- why it survived four stages; under classic-desktop the solver reserved 28
	-- px and this drew 20, and the label read "Mu".
	--
	-- One description, two consumers: `themeSnapshot.toggleRowPadding` is what
	-- the renderer's measure seam uses. Falling back to the boot style when no
	-- package is installed keeps the flat default byte-identical, because that
	-- fallback IS the neutral snapshot's answer.
	local function toggleLabelBox(): (UDim2, UDim2)
		local snap = snapshot()
		if type(snap) ~= "table" then
			snap = { controls = { toggle = { trackWidth = 44, trackInset = 12 } }, space = style.space }
		end
		local pad = themeSnapshot.toggleRowPadding(snap)
		return UDim2.fromOffset(pad.left, 0), UDim2.new(1, -(pad.left + pad.right), 1, 0)
	end

	-- re-applied on a theme swap: the label column moves with the metrics that
	-- reserved it, and a Toggle built under one package must not keep another's
	local function applyToggleLabelBox(handle: any)
		local label = handle.labelInstance
		if label == nil or handle.class ~= "Toggle" then
			return
		end
		local pos, size = toggleLabelBox()
		label.Position = pos
		label.Size = size
	end

	-- Toggle rows get a real knob-track (pill track right-aligned, animated
	-- knob, accent fill when on). The label lives in a DEDICATED child
	-- TextLabel sized to clear the track — the button's own text region does
	-- not reliably honor UIPadding, which let labels run under the track
	-- (director report 2026-07-19).
	local function buildToggleVisual(button: TextButton, handle: any)
		button.Text = ""
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		local labelPos, labelSize = toggleLabelBox()
		label.Position = labelPos
		label.Size = labelSize
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center
		-- ONE LINE, NEVER A BROKEN WORD (director finding 13, measured live
		-- 2026-07-26). The reserved label column is `ceil(the engine's own
		-- measurement)` and the engine draws exactly that, so under four of the
		-- nine reference packages the column and the drawn bounds are EQUAL to
		-- the pixel (Studio Neutral 35/35, classic-desktop 28/28, and the
		-- ValueProbe's "Candlelight" at 67/67 and 73/73). With `TextWrapped` a
		-- one-pixel shortfall does not clip a pixel — it BREAKS THE WORD:
		-- perturbing the live Music row by −1 px collapsed `TextBounds` from
		-- 35x16 to 28x16, which is "Musi" over "c", the second line clipped by a
		-- 28 px row. That is the director's "Musi c" exactly, and the row IS
		-- perturbed on every flip, because the press affordance scales the whole
		-- control by `extra.pressedScale` (0.985 — measured live at 104 -> 102.44
		-- -> 104 under classic-desktop).
		--
		-- Single-line with an end ellipsis is the same floor a Button's label
		-- gets: the measured width is a floor the row grows to where it can, and
		-- where it cannot the label ellipsizes instead of breaking. The SOLVER
		-- measures one line too (`singleLine` on the layout node), so the two
		-- seams cannot disagree about how many lines this is.
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.TextSize = 16
		if not nativeMode then
			-- native: the "Text default" class rule owns label paint (a write
			-- here would pin the label's color across theme swaps)
			assertBespokePaint("TextColor3")
			-- the pre-paint floor; the Toggle's role face reaches this lifted label
			-- through the `textFont` write, exactly as its `textSize` does
			label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json")
			label.TextColor3 = COLOR.content
		end
		label.Parent = button
		handle.labelInstance = label
		-- AN IMAGELABEL, NOT A FRAME. With no `Image` it is a
		-- Frame in every observable way — same background, same UICorner, same
		-- UIStroke — and it is what lets a package's `toggleTrack` recipe paint the
		-- switch as ART without the adapter creating a second instance to hold it.
		local track = Instance.new("ImageLabel")
		track.Name = "Track"
		track.AnchorPoint = Vector2.new(1, 0.5)
		track.Position = UDim2.new(1, -12, 0.5, 0)
		track.Size = UDim2.fromOffset(44, 24)
		track.ZIndex = 1
		track.BackgroundColor3 = togglePalette().trackOff
		-- opacity: bespoke keeps the plain write; native mode CANNOT — writes
		-- made before the instance joins the styled tree are STOMPED when
		-- styling first applies (director live find 2026-07-24, spike
		-- addendum: defeat is order-sensitive), so the "Toggle chrome" tag
		-- rule owns transparency there. The value-driven COLOR writes happen
		-- after styling with no competing rule and stay bespoke in both modes.
		track.BackgroundTransparency = 0
		if nativeMode then
			CollectionService:AddTag(track, "facet-toggle-chrome")
		end
		track.BorderSizePixel = 0
		corner(track, style.radii.pill, true)
		hairline(track, true)
		-- THE KNOB IS A SIBLING OF THE TRACK, not its child.
		-- Every per-state rule a package emits is a CHILD COMBINATOR off the
		-- interactive node (`.facet-interactive:Press > .facet-chrome-toggleKnob`),
		-- and a knob one level deeper could not be reached by one — so per-state
		-- knob art would have been emitted and never applied, which is exactly the
		-- defect class this stage exists to remove.
		--
		-- TRAVEL IS BYTE-IDENTICAL. The track's right edge is `width - 12` and it is
		-- 44 wide, so its left edge is `width - 56`; the knob's two stops were
		-- `+2` and `+22` inside it, i.e. `width - 54` and `width - 34` here. Art
		-- never moves geometry — the same two absolute positions, written against
		-- the button.
		local knob = Instance.new("ImageLabel")
		knob.Name = "Knob"
		knob.AnchorPoint = Vector2.new(0, 0.5)
		knob.Position = TOGGLE_KNOB_OFF
		knob.Size = UDim2.fromOffset(20, 20)
		knob.ZIndex = 2 -- above the track it used to be parented inside
		-- the resolver, not a captured constant: a toggle built while a package is
		-- installed must be born in that package's palette, not repainted into it
		-- on its first value change
		knob.BackgroundColor3 = togglePalette().knobOff
		knob.BackgroundTransparency = 0 -- bespoke path; native rides the tag rule
		if nativeMode then
			CollectionService:AddTag(knob, "facet-toggle-chrome")
		end
		knob.BorderSizePixel = 0
		corner(knob, style.radii.pill, true)
		track.Parent = button
		knob.Parent = button
		handle.track = track
		handle.knob = knob
		-- addressable by PATH, like every other managed child: the knob's travel and
		-- the track's resolved art are what "art never moves geometry" is asserted
		-- from, and a probe that has to walk the tree to find them is a probe that
		-- silently stops finding them
		for name, part in { Track = track, Knob = knob } do
			instancesByPath[handle.path .. "/" .. name] = part
		end
		-- the package's toggle recipes, applied the moment the assembly exists —
		-- not only on the next classification pass, or a toggle built while a
		-- skinned package is installed would be born palette-true and stay that way
		syncToggleArt(handle)
	end

	-- applyToggleValue(handle, on): the ONE value-driven paint site for a toggle,
	-- and now the one that reads the live palette rather than constants captured
	-- when the adapter was built.
	--
	-- MID-TWEEN RECOLOUR. A theme swap can land while the ON/OFF tween is still
	-- running toward the OLD colour. A Tween keeps writing its own target until
	-- it completes, so simply setting the new colour would be overwritten a frame
	-- later and the pill would settle on the outgoing theme's accent. The colour
	-- tween is therefore CANCELLED before a new one is issued, and a recolour
	-- (`retheme = true`) SNAPS rather than animating: the value did not change,
	-- so there is nothing to animate — a theme swap that visibly slides its
	-- colours reads as a state change that never happened.
	local function applyToggleValue(handle: any, on: boolean, retheme: boolean?)
		local track: Frame? = handle.track
		local knob: Frame? = handle.knob
		if track == nil or knob == nil then
			return
		end
		-- remembered so a live retheme can repaint the CURRENT state without the
		-- caller having to know it (and without touching the value)
		handle.toggleOn = on
		-- ON/OFF IS A VALUE, AND ART READS IT AS A TAG. No
		-- engine GuiState reports a value — which is exactly why `togglePalette`
		-- stayed a bespoke colour write — so the package's `selected` variant rules
		-- key on `facet-toggle-on`, flipped at the same site and from the same fact
		-- the colours are. It goes through syncTags (and therefore through
		-- classifyTags' desired set) because every `facet-*` tag on this instance is
		-- diffed away otherwise — the Step 3.5 fix round's exact lesson.
		syncTags(handle)
		-- the FALLBACK-mode half: with no sheet there is no rule to swap the
		-- picture, so the same variant map is resolved here
		syncToggleArt(handle)
		local palette = togglePalette()
		local trackColor = if on then palette.trackOn else palette.trackOff
		local knobColor = if on then palette.knobOn else palette.knobOff
		local knobPos = if on then TOGGLE_KNOB_ON else TOGGLE_KNOB_OFF
		if handle.toggleTrackTween ~= nil then
			handle.toggleTrackTween:Cancel()
			handle.toggleTrackTween = nil
		end
		if retheme == true or isReducedMotion() then
			track.BackgroundColor3 = trackColor
			knob.BackgroundColor3 = knobColor
			if retheme ~= true then
				knob.Position = knobPos
			end
		else
			local tween = TweenService:Create(track, motionInfo(style.motion.normal), { BackgroundColor3 = trackColor })
			handle.toggleTrackTween = tween
			tween:Play()
			-- the KNOB's colour snaps while its position slides: the two states'
			-- knob colours are a contrast pair, and interpolating between them
			-- passes through the middle, where it is readable against neither
			knob.BackgroundColor3 = knobColor
			TweenService:Create(knob, motionInfo(style.motion.normal), { Position = knobPos }):Play()
		end
	end

	-- ASSIGNED HERE, not beside its declaration: it calls `applyToggleValue`
	-- above, and a local declared later is not an upvalue.
	local function refreshToggleVisuals()
		for _, handle in handlesByPath do
			if handle.track ~= nil and handle.knob ~= nil then
				applyToggleValue(handle, handle.toggleOn == true, true)
			end
		end
	end

	return {
		applyCorners = applyCorners,
		applyGradient = applyGradient,
		applyPathRole = applyPathRole,
		applyShadow = applyShadow,
		applyStroke = applyStroke,
		applySurface = applySurface,
		applyTint = applyTint,
		applyToggleLabelBox = applyToggleLabelBox,
		applyToggleValue = applyToggleValue,
		buildToggleVisual = buildToggleVisual,
		corner = corner,
		cornerRadiusFor = cornerRadiusFor,
		ensureScale = ensureScale,
		focusColor = focusColor,
		hairline = hairline,
		refreshBackdropPaint = refreshBackdropPaint,
		refreshThemedPaint = refreshThemedPaint,
		refreshToggleVisuals = refreshToggleVisuals,
		releaseTint = releaseTint,
		wireInteractiveStates = wireInteractiveStates,
		wireNativePressDip = wireNativePressDip,
	}
end

return screen_paint
