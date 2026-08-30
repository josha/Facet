--!strict
-- BillboardTarget (CLIENT-ONLY): the RenderTargetAdapter for
-- world-anchored UI. A thin root swap over ScreenTarget — everything below
-- the root (style, bindings, states, z-order, pointer capture) is the same
-- flat instance renderer, so the two targets cannot drift.
--
-- Platform truths this encodes (research + memory 2026-07-19):
--   * a BillboardGui pixel canvas is OFFSET Size ONLY — scale units mean
--     STUDS on billboards, so the canvas is fixed at construction and the
--     solver's viewport is set to exactly that canvas;
--   * INPUT reaches a billboard only when it is PlayerGui-PARENTED with
--     `Adornee` set AND `Active = true` (part-parented billboards drop input
--     silently) — new() takes the PlayerGui-ish parent + adornee explicitly;
--   * `ClipsDescendants` defaults true on billboards TODAY — set explicitly
--     so a platform default change can never alter our clipping contract;
--   * there is NO cross-billboard ZIndex — paint order between billboards is
--     engine-managed (depth); in-canvas z-order still applies (setZOrder).

local screen_target = require("./screen_target")

local billboard_target = {}

export type Opts = {
	parent: Instance, -- PlayerGui (input) or any host (display-only)
	adornee: Instance,
	canvas: { w: number, h: number }, -- pixel canvas (offset Size)
	studsOffset: Vector3?,
	alwaysOnTop: boolean?,
	maxDistance: number?,
	style: any?,
	--[[ THE DISPLAY CLASS, FORWARDED VERBATIM like `style` (paint-family lockstep,
		the ten-foot ladder's paint half). A billboard is a WORLD surface and the viewer's
		distance to it is a world distance, not a screen class — but its solver
		reads the same environment-wide `themeMetrics` every other surface on this
		client reads, so a billboard that painted near while its own layout measured
		far would re-open the measure/paint disagreement the ladder exists to close.
		The consumer passes the environment's fact; absent is near, the identity. ]]
	displaySize: string?,
	-- DEPRECATED, and forwarded verbatim to `screen_target.new` — see its own `Opts`
	-- for why it survives at all. Registered in `Facet.DEPRECATIONS` as
	-- `screen_target.new(opts.isReducedMotion)`, which this field retires with:
	-- reduced motion arrives on its own through `adapter.setReducedMotion`, and a
	-- closure passed here can only force it ON, never off.
	isReducedMotion: (() -> boolean)?,
}

function billboard_target.new(opts: Opts)
	assert(opts.parent ~= nil, "billboard_target: parent is required (PlayerGui for input)")
	assert(opts.adornee ~= nil, "billboard_target: adornee is required")
	assert(opts.canvas and opts.canvas.w and opts.canvas.h, "billboard_target: canvas {w,h} is required")
	local adapter = screen_target.new({
		parent = opts.parent,
		style = opts.style,
		displaySize = opts.displaySize,
		-- deprecated on both sides; forwarded, never interpreted here
		isReducedMotion = opts.isReducedMotion,
		-- native ScrollingFrame hosts stay OFF billboards until their canvas
		-- coordinate mapping and input are proven on a live billboard drive
		-- (native-substrate corrections §13 / the native-substrate ledger); the clip-only
		-- fallback is the billboard contract for now
		forceScrollFallback = true,
		-- native PAINT on billboards is probe-viable (promotion-readiness.json:
		-- StyleLink under BillboardGui resolves rules + phantom chrome) but the
		-- billboard contract stays conservative: explicit false so the library
		-- default flip (native_style.DEFAULT_ENABLED) never sweeps billboards
		-- before a full billboard Facet drive proves the integrated adapter path
		nativeStyle = false,
		-- same rule for native drag acquisition (verifier F1 2026-07-23):
		-- UIDragDetector positions on a billboard arrive in the camera-
		-- projected canvas space — the exact unproven mapping above — so the
		-- detector seam must return nil here (corrections §1: billboards keep
		-- a non-native path until proven)
		forceDragFallback = true,
		rootFactory = function(screenId: string)
			local gui = Instance.new("BillboardGui")
			gui.Name = `Facet_BB_{screenId}`
			-- Instance.new LayerCollectors keep the LEGACY Global behavior;
			-- nested control internals (toggle track/knob/label) sort behind
			-- their opaque parents under Global — Sibling is the framework's
			-- z-order model on every target (WS3 verifier F1; the same trap
			-- the game hit on ScreenGuis, memory 2026-07-17)
			gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			gui.Size = UDim2.fromOffset(opts.canvas.w, opts.canvas.h) -- offset px ONLY
			gui.Adornee = opts.adornee
			gui.Active = true
			-- ClipsDescendants/LightInfluence match today's engine defaults —
			-- these writes PIN the contract against future default changes,
			-- they do not change current behavior
			gui.ClipsDescendants = true
			gui.AlwaysOnTop = opts.alwaysOnTop == true
			gui.ResetOnSpawn = false
			gui.LightInfluence = 0
			if opts.studsOffset ~= nil then
				gui.StudsOffset = opts.studsOffset :: Vector3
			end
			if opts.maxDistance ~= nil then
				gui.MaxDistance = opts.maxDistance :: number
			end
			gui.Parent = opts.parent
			return { gui = gui }
		end,
	})
	-- pointer CAPTURE is not offered on billboards (WS3 verifier F2): the
	-- shared drag math compares screen-space InputChanged positions (plus the
	-- ScreenGui inset correction) against solver rects, but a billboard's
	-- rects live in its own camera-projected CANVAS space — capture would be
	-- silently wrong. Removing the optional method makes the renderer degrade
	-- honestly (no grip/drag wiring); taps/Activated still work. Canvas-space
	-- pointer mapping is a future decision when a consumer needs draggable
	-- billboard UI.
	adapter.setPointerHandlers = nil
	-- native touch-gesture positions share the same unproven canvas-space
	-- mapping (verifier F1): strip the seam so consumers degrade honestly
	-- instead of receiving camera-space coordinates
	adapter.setTouchGestureHandlers = nil
	-- the engine-content seam (UI.Stage) is NOT offered on billboards either: a
	-- ViewportFrame renders its own scene inside a canvas that is itself a
	-- camera-projected world surface, and nothing has measured what that composition
	-- costs or looks like at distance. Removing the optional method makes
	-- `controller.stageHost` answer nil — the documented degrade (an empty reserved
	-- box, or the author's own fallback plate) — instead of shipping an unproven
	-- render. A billboard drive is what would promote it.
	adapter.stageHost = nil
	-- ...and the FOREIGN-content seam (UI.Foreign) is withheld for the
	-- same unmeasured reason: a caller's own GuiObject inside a camera-projected
	-- canvas is a composition nobody has looked at, and a `SurfaceGui` has its own
	-- pixel-space rules. `controller.foreignHost` answers nil — the documented
	-- degrade (an empty reserved box, or the author's fallback plate). A billboard
	-- drive is what would promote it, exactly as for the stage.
	adapter.foreignHost = nil
	return adapter
end

-- the environment viewport a billboard canvas needs (the solver's world IS
-- the canvas): env:set("viewportRect", billboard_target.canvasRect(canvas))
function billboard_target.canvasRect(canvas: { w: number, h: number }): { x: number, y: number, w: number, h: number }
	return { x = 0, y = 0, w = canvas.w, h = canvas.h }
end

return billboard_target
