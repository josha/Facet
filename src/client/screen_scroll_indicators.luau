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

	IT DOES NOT DECIDE THE LAYOUT RESERVE (director ruling 2026-08-12, REVERSING the
	ruling of 2026-08-09). The original ruling read "an overlay indicator lays claim
	to no layout space" and published a reserve of ZERO under "auto". Roblox has no
	overlay scrollbar: the engine shrinks the window by the instance's thickness
	regardless of how the bar is painted, so a zero reserve laid every touch
	scroller's content out to a box 8px wider than the box the player could see, and
	the engine clipped the difference. Measured live in Studio on the running
	showcase 2026-08-12: `AbsoluteSize` 703x203 against `AbsoluteWindowSize` 695x203,
	nine nodes painted past the invisible edge — a `…` overflow button sliced, and a
	value reading "0.35" clipped to "0.3" (bugs/IMG_3691.jpeg,
	docs/plans/device-bug-round-2026-08-12.md B7(a) option (a)).

	The director's reasoning, kept here so nobody "restores" the old behaviour
	thinking they found a regression: 8px of real content on every phone beats a
	cosmetic flash indicator, and Roblox offers no free overlay bar. Note also that a
	machine which merely CAN accept touch derives "auto" — the Studio session that
	measured this reported both `TouchEnabled` and `MouseEnabled` — so this was never
	a phone-only fault. ]]
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

	-- native scroll host seam (native-substrate NS-A2; spikes m1/m2): the
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

	--[[ the DECLARED optional policy seam the presenter drives from the
		environment's `scrollIndicatorPolicy` + `motionPolicy` facts. It decides the
		bar's PAINT — persistent, or hidden-at-rest with a flash and a fade.

		IT NO LONGER MOVES THE RESERVE (director ruling 2026-08-12, reversing
		2026-08-09; see SCROLL_BAR_THICKNESS in src/client/screen_target.luau for the
		measured defect and the reasoning). This used to publish 0 under "auto" on the reading
		that an overlay indicator claims no layout space — but the engine charges the
		window for the instance whatever the policy paints, which this file's own
		cross-axis canvas clamp in `setScrollRegion` below has always said. The two
		statements contradicted each other in one file, and the reserve was the one
		that was wrong. The write stays here, restating the one true value, so a
		reader of this function is never left wondering whether the policy changed it. ]]
	local function setScrollIndicatorPolicy(policy: string, reduced: boolean?)
		state.policy = if policy == "auto" then "auto" else "always"
		state.reduced = reduced == true
		adapter.scrollBarThickness = if forceScrollFallbackMode then 0 else SCROLL_BAR_THICKNESS
		for _, handle in handlesByPath do
			if handle.instance ~= nil and handle.instance:IsA("ScrollingFrame") then
				handle.indicatorFlashed = nil
				indicatorSync(handle)
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
		if region.axis == "x" then
			local willOverflow = contentW > hostW
			contentH = math.min(contentH, math.max(0, hostH - (if willOverflow then thickness else 0)))
		else
			local willOverflow = contentH > hostH
			contentW = math.min(contentW, math.max(0, hostW - (if willOverflow then thickness else 0)))
		end
		instance.CanvasSize = UDim2.fromOffset(contentW, contentH)
		-- per-host opt-out first (a carousel whose affordance is the peeking
		-- tile declares indicators = "none"): zero thickness IS the engine's
		-- own way to draw no bar, and the driver below never arms
		if region.indicators == "none" then
			handle.indicatorsOff = true
			instance.ScrollBarThickness = 0
			return
		end
		if handle.indicatorsOff == true then
			handle.indicatorsOff = nil
			instance.ScrollBarThickness = SCROLL_BAR_THICKNESS
		end
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
