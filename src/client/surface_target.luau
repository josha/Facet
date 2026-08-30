--!strict
--[[ SurfaceTarget (ADR-0063; CLIENT-ONLY): the RenderTargetAdapter for flat UI on
	a world surface — a console a player walks up to and uses.

	A thin root swap over ScreenTarget, exactly as `billboard_target` is:
	everything below the root (style, bindings, states, z-order, recycling) is the
	same flat instance renderer, so the two targets cannot drift.

	WHAT THIS IS NOT. It is ordinary two-dimensional Facet, rendered by a
	`SurfaceGui`. It is not the declarative Part/Model layout Step 12 considered,
	and it is not VR, ray, hand, or gaze support.

	════════════════════════════════════════════════════════════════════════════
	PLATFORM TRUTHS, EVERY ONE OF THEM MEASURED
	(Studio 0.736.0.7361346, Play mode, 2026-08-29 —
	 artifacts/example-games-and-standalones/spike/world-surface.md)

	1. THE CANVAS IS A FIXED VIRTUAL-PIXEL RECTANGLE, INVARIANT TO THE PART.
	   With `SizingMode = FixedSize`, one `CanvasSize` held while the part was
	   resized 8x5 -> 4x2.5 -> 16x10 -> 8x2 studs reported `AbsoluteSize = 400,250`
	   every time, and every descendant's `AbsolutePosition`/`AbsoluteSize` read in
	   the same canvas pixels a ScreenGui would report. So the solver is handed ONE
	   exact rectangle, every layout decision behaves as it does on a screen, and a
	   designer resizing the console costs no re-solve. The trade-off is aspect
	   ratio, which is the fixture's problem: state the resolution and match the
	   part to it. `PixelsPerStud` is deliberately NOT offered — it makes the
	   canvas a function of the part, so resizing a console silently re-lays-out
	   the UI.

	2. `face` IS REQUIRED AND HAS NO DEFAULT, and this is not fussiness.
	   For an unrotated part `Enum.NormalId.Front` is the **-Z** face, so a camera
	   looking along -Z sees `Back`. The spike lost two rounds to exactly that: two
	   surfaces painted on the side facing away from the camera, rendering
	   perfectly, measuring perfectly, and unclickable — which is indistinguishable
	   from "the engine does not support this". A default here would ship that
	   confusion to every consumer.

	3. THE PART MUST STAY QUERYABLE. With `CanQuery = false` the surface still
	   renders at full size and receives nothing: activation went 1 -> 0 -> 1 as
	   the flag was cleared and restored. A non-queryable adornee produces a
	   terminal that looks completely correct and cannot be touched, with no error
	   anywhere, so this adapter asserts it at construction rather than letting a
	   consumer discover it on a device.

	4. `AlwaysOnTop` IS PINNED FALSE AND IS NOT AN OPTION. With it true, a wall
	   between the camera and the console did not stop a click: activation read 0
	   with a wall and `false`, 1 with a wall and `true`, 1 with the wall removed.
	   A player would not merely SEE the terminal through geometry, they would
	   OPERATE it. If a consumer ever needs the other value it is an ADR with its
	   own evidence, not a flag.

	5. A LIVE SURFACE SINKS THE WORLD INPUT UNDER IT. A `ClickDetector` on the same
	   part fired while the surfaces were inert and fired ZERO times once they were
	   live at the same coordinates. A walk-up prompt and a live terminal cannot
	   both listen in the same region — that is a fixture constraint, recorded here
	   because it is this adapter that causes it.

	6. A DESTROYED ADORNEE IS INVISIBLE THROUGH `.Adornee`. After the part was
	   destroyed the `SurfaceGui` still reported `Adornee = <the destroyed part>`
	   and its canvas size unchanged. The reference outlives the instance, so this
	   adapter watches the instance's own lifetime and TELLS the consumer;
	   see `onAdorneeLost`.

	7. PLAYERGUI PARENTING IS AN OWNERSHIP RULE, NOT AN INPUT RULE — and the
	   framework's own contract had this wrong. `target_contract.FUTURE.surface`
	   said a SurfaceGui parented INTO the part "is display-only" and could never
	   be clicked. Measured: BOTH topologies take input (activated=1, inputBegan=2
	   on each). The rule stands anyway, for the better reason: a `SurfaceGui`
	   inside a Workspace part is REPLICATED TO EVERY PLAYER and server-owned, and
	   shared UI is precisely what Facet must never build. So `parent` is required
	   and is meant to be this client's `PlayerGui`.

	Clipping, the native scroll host's canvas writes, and `TextService` text bounds
	all behaved exactly as they do on a screen. The StyleSheet cascade is NOT yet
	proved — see `nativeStyle` below.
]]

--[[ THE SCREEN TARGET IS RESOLVED INSIDE `new`, NOT AT MODULE SCOPE.

	`screen_target` reaches the engine, so requiring it up here would make this
	whole module engine-only — and then its pure half (`canvasRect`, and every
	argument assertion below, which all fire before a single Instance is made)
	could not be tested at all. `src/client/host.luau` established this shape for
	exactly that reason and says so in its own header: "resolves `screen_target` /
	`roblox_input` / `roblox_env` inside `new`, each behind its own seam — which is
	the only reason this contract can be proved headlessly".

	`billboard_target` still requires at module scope, which is why it has no spec
	of its own. This one does. ]]
local surface_target = {}

export type Opts = {
	--[[ This client's PlayerGui. Required, and required to be PlayerGui-ish: see
		platform truth 7 — the reason is ownership, and a surface parented anywhere
		replicated is shared UI. ]]
	parent: Instance,
	-- the replicated part the canvas is painted on. Must have `CanQuery = true`.
	adornee: Instance,
	-- WHICH FACE. No default; see platform truth 2.
	face: Enum.NormalId,
	-- the fixed virtual-pixel canvas. The solver's world IS this rectangle.
	canvas: { w: number, h: number },
	-- how far a player can be and still see it. Absent leaves the engine default.
	maxDistance: number?,
	--[[ Called once if the adornee leaves the world — destroyed, streamed out, or
		re-parented away — because `.Adornee` cannot report it (platform truth 6).
		The consumer resigns the surface; this adapter only tells it. ]]
	onAdorneeLost: (() -> ())?,
	style: any?,
	-- the display class, forwarded verbatim like `style` (paint-family lockstep,
	-- ADR-0039 Decision 3a), for the same reason billboards forward it: a surface
	-- that painted near while its own layout measured far would re-open the
	-- measure/paint disagreement the ladder exists to close.
	displaySize: string?,
	-- DEPRECATED on both sides (ADR-0011); forwarded, never interpreted here.
	isReducedMotion: (() -> boolean)?,
}

function surface_target.new(opts: Opts)
	assert(opts.parent ~= nil, "surface_target: parent is required (this client's PlayerGui)")
	assert(opts.adornee ~= nil, "surface_target: adornee is required (the part the canvas is painted on)")
	assert(
		typeof(opts.face) == "EnumItem" and opts.face.EnumType == Enum.NormalId,
		"surface_target: face is required and takes an Enum.NormalId — there is no default, because "
			.. "`Front` is the -Z face and a camera looking along -Z sees `Back`. A surface on the wrong "
			.. "face renders and measures perfectly and can never be clicked."
	)
	assert(
		opts.canvas and opts.canvas.w and opts.canvas.h,
		"surface_target: canvas {w,h} is required — the solver is handed exactly this rectangle"
	)
	-- Platform truth 3, asserted at construction rather than discovered on a
	-- device: a non-queryable adornee renders at full size and receives nothing.
	local queryable = (opts.adornee :: any).CanQuery
	assert(
		queryable ~= false,
		"surface_target: the adornee has CanQuery = false, so its surface will render perfectly and "
			.. "receive no input at all. Set CanQuery = true on the part."
	)

	local adornee = opts.adornee
	local lostConnections: { RBXScriptConnection } = {}

	local screen_target = require("./screen_target")
	local adapter = screen_target.new({
		parent = opts.parent,
		style = opts.style,
		displaySize = opts.displaySize,
		isReducedMotion = opts.isReducedMotion,
		--[[ The native scroll host stays OFF until a live surface drive proves a
			user-driven scroll, not merely a scripted one. The spike wrote
			`CanvasPosition` on a ScrollingFrame over a surface and it took
			(0,120 on a 200x600 canvas in a 200x100 window) — but a scripted write
			is not a wheel, a drag or a touch flick, and those are what a consumer
			would actually get. Clip-only until measured, same as the billboard. ]]
		forceScrollFallback = true,
		--[[ Native paint is UNPROVEN on a world surface and this is the one open
			question the spike could not close. Two attempts to apply a hand-built
			StyleRule through a StyleLink failed to apply on the SCREEN control as
			well, so the setup was wrong and a shared null proves nothing about the
			cascade. `false` keeps the library's default flip from sweeping surfaces
			before `native_style` itself has been driven on one. ]]
		nativeStyle = false,
		--[[ Native drag acquisition needs a canvas-space pointer mapping. The spike
			proved ACTIVATION reaches a surface control; it did not prove what
			coordinates a capture would carry, and on a SurfaceGui the ScreenGui
			inset correction is not merely wrong, it is the wrong KIND of
			correction — the position is screen space and the solver's rects are
			canvas space. Fallback until a mapping is measured. ]]
		forceDragFallback = true,
		rootFactory = function(screenId: string)
			local gui = Instance.new("SurfaceGui")
			gui.Name = `Facet_Surface_{screenId}`
			-- Instance.new LayerCollectors keep the LEGACY Global behaviour, under
			-- which nested control internals sort behind their opaque parents.
			-- Sibling is the framework's z-order model on every target.
			gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
			gui.CanvasSize = Vector2.new(opts.canvas.w, opts.canvas.h)
			gui.Face = opts.face
			gui.Adornee = adornee
			-- SurfaceGui.Active already defaults true (unlike BillboardGui, which is
			-- why billboard_target sets it) — written anyway so a platform default
			-- change cannot silently make every surface inert.
			gui.Active = true
			gui.ClipsDescendants = true
			-- Platform truth 4. Not an option; a terminal usable through a wall is
			-- not a terminal.
			gui.AlwaysOnTop = false
			gui.ResetOnSpawn = false
			gui.LightInfluence = 0
			if opts.maxDistance ~= nil then
				gui.MaxDistance = opts.maxDistance :: number
			end
			gui.Parent = opts.parent
			return { gui = gui }
		end,
	})

	--[[ THE ADORNEE'S LIFETIME, WATCHED DIRECTLY (platform truth 6).

		`.Adornee` still names a destroyed part, so polling it can never notice.
		`AncestryChanged` fires for a destroy, a stream-out and a re-parent alike —
		all three mean the same thing to a surface: the thing it is painted on is
		no longer in the world. The consumer is told once; resigning the surface is
		its decision, not this adapter's. ]]
	if opts.onAdorneeLost ~= nil then
		local notified = false
		local function checkGone()
			if notified then
				return
			end
			if not (adornee :: any):IsDescendantOf(game) then
				notified = true
				(opts.onAdorneeLost :: () -> ())()
			end
		end
		table.insert(lostConnections, (adornee :: any).AncestryChanged:Connect(checkGone))
		table.insert(
			lostConnections,
			(adornee :: any).Destroying:Connect(function()
				if not notified then
					notified = true
					(opts.onAdorneeLost :: () -> ())()
				end
			end)
		)
	end

	--[[ Teardown owns the watch. `destroyRoot` is the renderer's one call for
		"this surface is finished", so the connections leave with it rather than
		outliving the adapter that made them. ]]
	local innerDestroyRoot = adapter.destroyRoot
	adapter.destroyRoot = function(rootHandle: any)
		for _, connection in lostConnections do
			connection:Disconnect()
		end
		table.clear(lostConnections)
		return innerDestroyRoot(rootHandle)
	end

	--[[ Capabilities REMOVED, each with its named degradation. Deleting the method
		is the sanctioned move: `target_contract.check` then reports it absent and
		the renderer degrades by name, instead of a screen-space capability
		appearing to work while its coordinate space is wrong. ]]
	-- pointer capture and native gestures: canvas-space mapping unproven (above)
	adapter.setPointerHandlers = nil
	adapter.setTouchGestureHandlers = nil
	-- a ViewportFrame rendering its own scene inside a canvas that is itself a
	-- world surface is a composition nobody has measured, at any distance
	adapter.stageHost = nil
	-- ...and a caller's own GuiObject inside that canvas is the same unmeasured
	-- question (ADR-0034). `controller.foreignHost` answers nil — the documented
	-- degrade, an empty reserved box or the author's own fallback plate.
	adapter.foreignHost = nil

	return adapter
end

--[[ The environment viewport a surface canvas needs — the solver's world IS the
	canvas: `env:set("viewportRect", surface_target.canvasRect(canvas))`.

	The consumer also sets `env:set("presentationSpace", "world")`, which this
	target is the first thing in the repository to make true. ]]
function surface_target.canvasRect(canvas: { w: number, h: number }): { x: number, y: number, w: number, h: number }
	return { x = 0, y = 0, w = canvas.w, h = canvas.h }
end

return surface_target
