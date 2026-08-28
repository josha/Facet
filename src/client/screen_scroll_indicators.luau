--!strict
-- ScrollIndicators — the native scroll host's REGION/POSITION writes and the
-- scroll-indicator paint driver, extracted from src/client/screen_target.luau
-- for Studio's 200_000-character `Source` write cap (a module over it silently
-- stops live-syncing into an open session, so a live check against it tests the
-- built place rather than your edits —
-- docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md). Strictly
-- one-way, exactly like src/client/screen_chrome: it never requires back.
--
-- `new(ctx)` returns the three adapter methods, which screen_target rebinds onto
-- its adapter under their original names so no call site moved:
--   setScrollIndicatorPolicy(policy, reduced?) / setScrollRegion(handle, region)
--   / setScrollPosition(handle, pos)
--
-- ctx (screen_target passes the first three BY REFERENCE):
--   adapter          the adapter table — `setScrollIndicatorPolicy` republishes
--                    `adapter.scrollBarThickness`, which the renderer feeds to
--                    the solver
--   handlesByPath    every live handle, walked on a policy change
--   indicatorState   { policy: "always"|"auto", reduced: boolean } — SHARED,
--                    because screen_target's create path reads `.policy` at
--                    instance birth to decide whether a new ScrollingFrame is
--                    born with its bar hidden
--   scrollBarThickness / forceScrollFallback   the host's two scroll constants
--
-- Everything else is per-host state living ON THE HANDLE (`indicatorFlashed`,
-- `indicatorConn`, `indicatorsOff`), so it dies with the instance's Destroy and
-- a recycled instance's new identity re-announces itself.

local TweenService = game:GetService("TweenService")

--[[ scroll indicator policy — WHAT IT DECIDES, AND WHAT IT DOES NOT.

	"always" = the desktop convention: a persistent bar. "auto" = the touch/gamepad
	convention: the bar's image is hidden at rest, FLASHES once when a scrollable
	region first mounts (so a page that continues below never reads as cut off),
	shows while scrolling, and fades when idle. Reduced motion never fades: "auto"
	degrades to visible-whenever-scrollable, so the affordance never depends on
	movement.

	IT DECIDES THE LAYOUT RESERVE ONCE MORE, BUT ONLY FOR "auto" (director ruling
	2026-08-28, PARTIALLY REVERSING 2026-08-12, which itself reversed 2026-08-09):
	"if the scrollbar is set to persistently visible, we hold space for it, but if
	it's auto visible, we let it overlap — a framework thing that just works with
	our layouts." "always" keeps the FULL 2026-08-12 behaviour unchanged (a
	persistent bar earns a permanent gutter). "auto" now reserves ZERO again — but
	NOT by simply repeating 2026-08-09's mistake.

	2026-08-12's own measurement is still true and still the reason a bare
	reserve-zero is wrong: Roblox has no overlay scrollbar — `AbsoluteWindowSize`
	is narrower than the frame's own `AbsoluteSize` by `ScrollBarThickness`
	whenever the scroll axis overflows, UNCONDITIONALLY on paint policy (measured
	directly in this round: even `ScrollBarImageTransparency = 1`, fully invisible,
	does not stop the engine narrowing the window — `291,200` against `300,200`,
	thickness untouched). A zero reserve alone reproduces 2026-08-09's exact
	defect (`bugs/IMG_3691.jpeg`): content measured to the full width, then
	clipped by the engine's own narrower window.

	So "auto" pairs the zero reserve with `applyBarOverlayWiden` below: the FRAME
	ITSELF is widened by `SCROLL_BAR_THICKNESS` on the cross axis whenever its
	scroll axis overflows, which widens the engine's own internal window by the
	same amount and exactly cancels the narrowing — content measured to the full
	(unreserved) width lands on a window of that same full width. The extra
	`SCROLL_BAR_THICKNESS` px the frame now occupies sits BEYOND the box the
	solver gave it (typically the padding/gap that already follows a scroller),
	which is where the bar ends up: genuinely overlapping whatever is there
	instead of a permanently reserved, usually-empty gutter — measured live,
	`.superpowers/sdd/framework-gaps-phase2-followups/task-scroll2-report.md`.
	Known, disclosed limit: a scroller authored with LESS than
	`SCROLL_BAR_THICKNESS` of trailing room has nothing safe to widen into and
	may encroach on whatever follows it — no viewport-bounds clamp exists yet
	(booked as a follow-up).

	The director's ORIGINAL reasoning for reserving nothing under "auto" still
	stands and is worth keeping in mind reading the above: 8px of real content on
	every phone beats a cosmetic flash indicator. What changed is not that
	reasoning — it is HOW to get there without the clip Roblox's own engine
	otherwise charges for it. Note also that a machine which merely CAN accept
	touch derives "auto" — the Studio session that measured the original defect
	reported both `TouchEnabled` and `MouseEnabled` — so this was never a
	phone-only fault. ]]
local INDICATOR_IDLE_FADE_SECONDS = 1.1
local INDICATOR_FLASH_HOLD_SECONDS = 1.6
local INDICATOR_FADE_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local screen_scroll_indicators = {}

function screen_scroll_indicators.new(ctx: any)
	local adapter = ctx.adapter
	local handlesByPath = ctx.handlesByPath
	local state = ctx.indicatorState
	local SCROLL_BAR_THICKNESS: number = ctx.scrollBarThickness
	local forceScrollFallbackMode: boolean = ctx.forceScrollFallback == true
	-- fade generation per host: a newer show/fade supersedes an in-flight one
	local indicatorFadeToken = {} :: { [any]: number }

	-- native scroll host seam (the native substrate; spikes m1/m2): the
	-- solver's content extent becomes the engine canvas; the ENGINE owns the
	-- live offset (wheel, touch momentum, elastic, bars); observeScroll reports
	-- engine-driven CanvasPosition changes back to the framework (windowing);
	-- setScrollPosition is the framework's programmatic keep-visible write.
	-- On the fallback path (forceScrollFallback / non-ScrollingFrame instance)
	-- these degrade to no-ops and the node stays a proven clip-only host.
	-- ===== the indicator driver (director ruling 2026-08-09) ==============
	-- Policy state lives in the shared `indicatorState` record; per-host state
	-- lives ON THE HANDLE (the connection dies with the instance's Destroy, and
	-- screen_target's `adopt` resets the flash so a recycled instance's NEW
	-- identity announces itself again).
	local function indicatorShow(handle: any)
		local instance = handle.instance
		if instance == nil or not instance:IsA("ScrollingFrame") then
			return
		end
		indicatorFadeToken[handle] = (indicatorFadeToken[handle] or 0) + 1
		instance.ScrollBarImageTransparency = 0
	end

	local function indicatorFadeLater(handle: any, delaySeconds: number)
		if state.reduced then
			return -- reduced motion: never fade — the affordance stays put
		end
		local token = (indicatorFadeToken[handle] or 0) + 1
		indicatorFadeToken[handle] = token
		task.delay(delaySeconds, function()
			if indicatorFadeToken[handle] ~= token then
				return -- a newer show/fade superseded this one
			end
			local instance = handle.instance
			if instance ~= nil and instance:IsA("ScrollingFrame") and instance.Parent ~= nil then
				TweenService:Create(instance, INDICATOR_FADE_TWEEN, { ScrollBarImageTransparency = 1 }):Play()
			end
		end)
	end

	local function indicatorOverflowing(handle: any): boolean
		local instance = handle.instance
		if instance == nil or not instance:IsA("ScrollingFrame") then
			return false
		end
		local canvas = instance.AbsoluteCanvasSize
		local window = instance.AbsoluteWindowSize
		return canvas.Y > window.Y + 1 or canvas.X > window.X + 1
	end

	local function indicatorSync(handle: any)
		local instance = handle.instance
		if instance == nil or not instance:IsA("ScrollingFrame") then
			return
		end
		if state.policy == "always" then
			indicatorShow(handle)
			return
		end
		-- auto: reduced motion pins the indicator whenever there is anything to
		-- indicate; full motion flashes a NEWLY scrollable host once and then
		-- lets the scroll driver own it
		if not indicatorOverflowing(handle) then
			indicatorFadeToken[handle] = (indicatorFadeToken[handle] or 0) + 1
			instance.ScrollBarImageTransparency = 1
			handle.indicatorFlashed = nil
			return
		end
		if state.reduced then
			indicatorShow(handle)
			return
		end
		if handle.indicatorFlashed ~= true then
			handle.indicatorFlashed = true
			indicatorShow(handle)
			indicatorFadeLater(handle, INDICATOR_FLASH_HOLD_SECONDS)
		end
		if handle.indicatorConn == nil then
			handle.indicatorConn = instance:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
				if state.policy ~= "auto" or state.reduced then
					return
				end
				indicatorShow(handle)
				indicatorFadeLater(handle, INDICATOR_IDLE_FADE_SECONDS)
			end)
		end
	end

	--[[ THE FRAME-WIDENING HALF OF THE "auto" RULING (see the header). `axis` /
		`overflowing` are the SAME facts `setScrollRegion` already derives for the
		cross-axis canvas clamp — this just remembers them on the handle so a bare
		POLICY change (no new region event) can re-derive the widen without one.
		`indicatorsOff` mirrors a per-region `indicators = "none"` opt-out: that
		host already draws no bar at all (`instance.ScrollBarThickness = 0`), so it
		has nothing to compensate for and must never widen.

		Consumed by `screen_presentation.luau`'s `applyRect`, riding the SAME
		additive-delta seam `presentationSizeW/H` already uses for a mid-animation
		size delta (`pw = rect.w + presentationSizeW + barOverlayWidenW`) — no new
		writer of `Position`/`Size` needed, which is the invariant that function's
		own header states `applyRect` is checked to be the only one of. ]]
	local function applyBarOverlayWiden(handle: any, axis: string?, overflowing: boolean, indicatorsOff: boolean)
		handle.barOverlayAxis = axis
		handle.barOverlayOverflowing = overflowing
		local widen = if axis ~= nil
				and overflowing
				and not indicatorsOff
				and state.policy == "auto"
				and not forceScrollFallbackMode
			then SCROLL_BAR_THICKNESS
			else 0
		if axis == "x" then
			handle.barOverlayWidenH = if widen > 0 then widen else nil
			handle.barOverlayWidenW = nil
		else
			handle.barOverlayWidenW = if widen > 0 then widen else nil
			handle.barOverlayWidenH = nil
		end
	end

	--[[ the DECLARED optional policy seam the presenter drives from the
		environment's `scrollIndicatorPolicy` + `motionPolicy` facts. It decides the
		bar's PAINT — persistent, or hidden-at-rest with a flash and a fade.

		THE RESERVE IS POLICY-DRIVEN AGAIN, BUT ONLY HALF OF IT MOVED (director
		ruling 2026-08-28; see the file header). "always" keeps the 2026-08-12
		reserve unchanged; "auto" now publishes zero — paired with
		`applyBarOverlayWiden` re-run below for every live handle, so a policy flip
		alone (no new region event) immediately re-derives each host's widen from
		its own last-known axis/overflow rather than leaving it stale until the
		next region write. ]]
	local function setScrollIndicatorPolicy(policy: string, reduced: boolean?)
		state.policy = if policy == "auto" then "auto" else "always"
		state.reduced = reduced == true
		adapter.scrollBarThickness = if forceScrollFallbackMode or state.policy == "auto"
			then 0
			else SCROLL_BAR_THICKNESS
		for _, handle in handlesByPath do
			if handle.instance ~= nil and handle.instance:IsA("ScrollingFrame") then
				handle.indicatorFlashed = nil
				indicatorSync(handle)
				applyBarOverlayWiden(
					handle,
					handle.barOverlayAxis,
					handle.barOverlayOverflowing == true,
					handle.indicatorsOff == true
				)
			end
		end
	end

	local function setScrollRegion(handle: any, region: any)
		local instance = handle.instance
		if instance == nil or not instance:IsA("ScrollingFrame") then
			return
		end
		if region == nil then
			instance.CanvasSize = UDim2.new()
			applyBarOverlayWiden(handle, nil, false, handle.indicatorsOff == true)
			return
		end
		instance.ScrollingDirection = if region.axis == "x"
			then Enum.ScrollingDirection.X
			else Enum.ScrollingDirection.Y
		-- THE CROSS AXIS IS CLAMPED TO THE ENGINE'S OWN WINDOW (director live
		-- report 2026-08-09): the solver already clamps its measure, but the
		-- engine's window is thinner than the frame by the BAR THICKNESS even
		-- with ScrollBarInset.None — a fact only the engine can answer — and a
		-- canvas one bar wider than the window makes it draw a cross-axis bar
		-- nobody can scroll. Ask the instance, not arithmetic.
		local window = instance.AbsoluteWindowSize
		local contentW = region.contentW
		local contentH = region.contentH
		-- DETERMINISTIC, from the region's own published host box (the live
		-- window geometry races the layout mid-churn): when the main axis will
		-- overflow, the engine shrinks its window by the BAR THICKNESS even at
		-- ScrollBarInset.None, so the cross clamp subtracts it up front.
		local thickness = instance.ScrollBarThickness
		local hostW = if type(region.hostW) == "number" then region.hostW else window.X
		local hostH = if type(region.hostH) == "number" then region.hostH else window.Y
		-- SHARED with `applyBarOverlayWiden` below (director ruling 2026-08-28):
		-- the same "does the scroll axis overflow" fact that decides the
		-- cross-axis clamp ALSO decides whether an "auto" host needs widening.
		local willOverflow: boolean
		if region.axis == "x" then
			willOverflow = contentW > hostW
			contentH = math.min(contentH, math.max(0, hostH - (if willOverflow then thickness else 0)))
		else
			willOverflow = contentH > hostH
			contentW = math.min(contentW, math.max(0, hostW - (if willOverflow then thickness else 0)))
		end
		instance.CanvasSize = UDim2.fromOffset(contentW, contentH)
		-- per-host opt-out first (a carousel whose affordance is the peeking
		-- tile declares indicators = "none"): zero thickness IS the engine's
		-- own way to draw no bar, and the driver below never arms
		if region.indicators == "none" then
			handle.indicatorsOff = true
			instance.ScrollBarThickness = 0
			applyBarOverlayWiden(handle, region.axis, willOverflow, true)
			return
		end
		if handle.indicatorsOff == true then
			handle.indicatorsOff = nil
			instance.ScrollBarThickness = SCROLL_BAR_THICKNESS
		end
		applyBarOverlayWiden(handle, region.axis, willOverflow, false)
		-- the region write is where a host LEARNS it overflows — the auto
		-- policy's mount flash rides it (and a region that stops overflowing
		-- hides its indicator and re-arms the flash)
		indicatorSync(handle)
	end

	local function setScrollPosition(handle: any, pos: { x: number, y: number })
		local instance = handle.instance
		if instance ~= nil and instance:IsA("ScrollingFrame") then
			instance.CanvasPosition = Vector2.new(pos.x, pos.y)
		end
	end

	return {
		setScrollIndicatorPolicy = setScrollIndicatorPolicy,
		setScrollRegion = setScrollRegion,
		setScrollPosition = setScrollPosition,
	}
end

return screen_scroll_indicators
