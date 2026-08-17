--!strict
-- ScreenPresentation — THE PRESENTATION CHANNEL (ADR-0022 Decision 2) of the
-- ScreenTarget adapter, plus the REAL-PARENT (instance host) record it composes
-- against, extracted from src/client/screen_target.luau for Studio's
-- 200_000-character `Source` WRITE cap. Over that cap a module silently stops
-- live-syncing into an open Studio session, so every live check against it
-- tests the built place rather than the edits on disk —
-- docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md. Strictly
-- one-way, like screen_chrome/screen_paint/screen_scroll_indicators: it never
-- requires back.
--
-- WHY THIS IS THE SEAM. It is the one region of the adapter that already had a
-- name: a presentation transform composes onto the solver's rect AT THE WRITE,
-- so `applyRect` is the single place a Position or Size is written and the
-- offset is added every time. Everything that follows from that rule lives
-- here — the flat-tree offset accumulation, the subtree index that makes a
-- 60 Hz leaf motion cost one node instead of the whole target, the hit
-- expander that must travel with the paint, and the scale/rotation half.
--
-- `new(ctx)` returns the region; screen_target rebinds each export to a local
-- of its ORIGINAL name, so every call site in that file reads exactly as it did
-- while this was inline. Public surface unmoved: all of this is internal to
-- screen_target.new, whose contract is the `adapter` table it returns.
--
-- ctx:
--   handlesByPath   BY REFERENCE — the same live-handle map screen_target
--                   holds; `subtreeOf` walks it
--   refitIconArt    screen_chrome's icon re-fit, called by `applyRect` (a rect
--                   that lands after the picture did has to re-clamp it)
--   ensureScale     screen_paint's lazy UIScale, called by
--                   `applyPresentationPaint`. ONE UIScale per object is an
--                   engine rule, so the motion scale and the press dip share
--                   the instance deliberately — see that function's header
--
-- `subtreeOf` and `applyPresentationPaint` are NOT exported: `setTransform` is
-- the only caller either ever had, and it came here with them.
--
-- SOME EXPORTS EXIST BECAUSE A NUMBER CANNOT BE SHARED BY REFERENCE.
-- `presentationTransforms` is a table and goes back to the host as itself, so
-- its reads are unchanged. (`instanceHosts` COULD have, and deliberately does
-- not — ADR-0032 step 1 made the registry private behind
-- `registerHost`/`unregisterHost`/`hostAt`/`hostFor`, because "which paths get
-- registered" is the one predicate that whole migration changes and it needs one
-- place to live.) `presentationCount` (the zero-cost
-- fast path every rect write consults) and `subtreeCache` are a number and a
-- rebound table, and the host has three sites that used to write them directly:
-- `setProp("transform")` is now `setTransform`, `remove`/`destroyRoot`'s
-- per-path teardown is `dropPath`, and every structural change calls
-- `invalidateSubtree`. One authority for the count, exactly as the paint-claim
-- ledger is one authority per render property.

local screen_presentation = {}

-- Path2D control-point application (NS-A7; spike m5-path2d.json): normalized
-- points (unit box, tangents relative to the point) scale into the CURRENT
-- solved rect. Engine truths: max 100 control points; no Transparency
-- property; left tangent = incoming handle, right = outgoing.
local function applyPathPoints(handle: any)
	local path2d = handle.path2d
	local rect = handle.windowRect
	local points = handle.normPoints
	if path2d == nil or rect == nil or points == nil then
		return
	end
	-- normalized against the PAINTED box, so a shape inside a node whose size is
	-- travelling re-scales with it instead of sitting at its destination size
	-- inside a smaller box (withAnimation size, 2026-08-14)
	local w = math.max(rect.w + (handle.presentationSizeW or 0), 1)
	local h = math.max(rect.h + (handle.presentationSizeH or 0), 1)
	local cps = table.create(#points)
	for _, p in points do
		table.insert(
			cps,
			Path2DControlPoint.new(
				UDim2.fromOffset(p.x * w, p.y * h),
				UDim2.fromOffset(p.inX * w, p.inY * h),
				UDim2.fromOffset(p.outX * w, p.outY * h)
			)
		)
	end
	path2d:SetControlPoints(cps)
end

function screen_presentation.new(ctx: any)
	local handlesByPath = ctx.handlesByPath
	local refitIconArt = ctx.refitIconArt
	local ensureScale = ctx.ensureScale

	--[[ THE INSTANCE-HOST REGISTRY — THE ONE RECORD THAT MAKES A NODE A REAL PARENT.
		(ADR-0032 Decision 1. Named `clipHosts` until then, after the first of its
		three triggers.)

		A registered node's descendants parent UNDER it in the engine hierarchy,
		with positions relative to it; everything else stays flat under the root.
		Three declarations register one today — a `ScrollView` (by construction),
		an authored `clipChildren`, and a fade group — and only the first of the
		three is about clipping, which is why the name moved. `path` is on the
		entry for the presentation channel (ADR-0022 Decision 2): an offset
		accumulating down a subtree stops at the nearest REAL PARENT, whose own
		move already carries its children, and this is how a child knows where
		that is.

		THE TABLE IS PRIVATE, AND THAT IS THE POINT OF THIS STEP. ADR-0032 is a
		REGISTRATION POLICY, not a renderer rewrite — "switching to nested is a
		change to one predicate: which paths get registered". A policy needs one
		place to live, so the record is born in `registerHost` and dies in
		`unregisterHost`, and the host reads it through `hostAt`/`hostFor` rather
		than indexing a shared table at four call sites. The invariant is
		structural now instead of a convention a fifth call site can miss.
	]]
	local instanceHosts: { [string]: { instance: Instance, rect: any?, children: { any }, path: string } } = {}

	-- CREATE-OR-REUSE, and the reuse half is load-bearing: a node may declare
	-- itself a real parent TWICE — a fade group registers while `create` is still
	-- choosing its engine class, and an authored `clipChildren` registers again at
	-- the prop write. Replacing the entry would strand every child already
	-- re-based against it, so the first registration wins and the second is a
	-- no-op that hands back the same table.
	local function registerHost(path: string, instance: Instance, rect: any?): any
		local existing = instanceHosts[path]
		if existing ~= nil then
			return existing
		end
		local entry = { instance = instance, rect = rect, children = {}, path = path }
		instanceHosts[path] = entry
		return entry
	end

	local function unregisterHost(path: string)
		instanceHosts[path] = nil
	end

	-- EXACT: is THIS path a host? (the rect re-base on a host's own move, and
	-- the park refusal, both ask about the node itself rather than its ancestry)
	local function hostAt(path: string): any
		return instanceHosts[path]
	end

	-- NEAREST REGISTERED ANCESTOR — a longest-path-prefix match, and it walks the
	-- CANDIDATE's separators rather than scanning the registry.
	--
	-- WHY THAT DISTINCTION IS THE WHOLE STEP. The scan it replaces was
	-- `for hostPath, entry in instanceHosts do` — every registered host examined
	-- on every `create` and every `adopt`. At the three hosts a flat tree has,
	-- free. ADR-0032's entire content is "register more hosts", so that loop
	-- becomes O(nodes x hosts) exactly as the migration proceeds: the cost would
	-- have arrived with the feature and been blamed on nesting. Walking the
	-- path's own separators from the deepest inward is bounded by the path's
	-- LENGTH and is independent of how many hosts exist — the same walk
	-- `recomputePresentationOffset` already does two functions below, which is
	-- the honest sign it is this file's idiom rather than a new one.
	--
	-- Deepest-first, so the first hit IS the longest prefix and there is nothing
	-- to compare lengths against. A node is never its own host: the walk only
	-- reads prefixes that END before a separator.
	local function hostFor(path: string): any
		local i = #path
		while i > 1 do
			if string.sub(path, i, i) == "/" then
				local entry = instanceHosts[string.sub(path, 1, i - 1)]
				if entry ~= nil then
					return entry
				end
			end
			i -= 1
		end
		return nil
	end
	-- the effective-target expander (B-BTN3) lives beside its control, so it must be
	-- re-based from the SAME clip-host origin — and re-based AGAIN whenever that
	-- origin arrives or moves. RS-A16-D1b (found live 2026-07-26): the renderer pushes
	-- hit rects BEFORE the commit that writes rects, so on a fresh build an instance host's
	-- rect is not yet current when the expander is first placed, and the renderer's
	-- own cache (which stores only the WANTED rect) never asks again. Measured after a
	-- scenario `reset()`: an expander 74px below the button it belongs to. Placing it
	-- here, in the one function that re-bases a node, is what makes the two unable to
	-- disagree.
	-- ===== THE PRESENTATION CHANNEL (ADR-0022 Decision 2) =================
	--
	-- A presentation transform composes onto the solver's rect at the WRITE, so a
	-- motion never touches solver geometry and a re-solve never loses the motion:
	-- `applyRect` is the one place a Position is written, and it adds the offset
	-- every time.
	--
	-- THE INSTANCE TREE IS FLAT (docs/lessons/screen-target-tree-is-flat.md), and
	-- that is the load-bearing fact here. Every node parents under the root gui
	-- unless a REAL PARENT claimed it (an instance host: a clip host, a scroll host, or a fade group), so
	-- moving a container's own instance moves nothing but that container — the
	-- keyboard keep-visible shift on the root node would have moved one transparent
	-- frame and nothing the player can see. So the offset ACCUMULATES down the
	-- subtree: a node pays its own transform plus every ancestor's, stopping at its
	-- real parent, whose own move already carries it. One rule, and the root case
	-- (the whole surface shifts) falls out of it.
	local presentationTransforms: { [string]: any } = {}
	local presentationCount = 0
	-- path -> the handles a transform on that path composes into (itself first).
	-- A motion writes EVERY FRAME while it runs, and scanning every handle on the
	-- target per write would make a leaf's 60 Hz motion cost the whole tree. Built
	-- once per animated path and dropped wholesale on any structural change, which is
	-- rare next to a frame.
	local subtreeCache: { [string]: { any } } = {}
	local function subtreeOf(path: string): { any }
		local hit = subtreeCache[path]
		if hit ~= nil then
			return hit
		end
		local prefix = path .. "/"
		local out: { any } = {}
		for otherPath, other in handlesByPath do
			if otherPath == path or string.sub(otherPath, 1, #prefix) == prefix then
				table.insert(out, other)
			end
		end
		subtreeCache[path] = out
		return out
	end

	-- cached on the handle so `applyRect` — the hot path — adds two numbers instead
	-- of walking a path. Recomputed for the affected subtree when a transform moves,
	-- and once at creation for a node born under a live one.
	local function recomputePresentationOffset(handle: any)
		local ox, oy = 0, 0
		if presentationCount > 0 then
			local own = presentationTransforms[handle.path]
			if own ~= nil then
				ox += own.x or 0
				oy += own.y or 0
			end
			-- ancestors, down to (and excluding) the real parent
			local stop = if handle.instanceHost ~= nil then #handle.instanceHost.path else 0
			local path = handle.path
			local i = #path
			while i > 1 do
				if string.sub(path, i, i) == "/" then
					local ancestor = string.sub(path, 1, i - 1)
					if #ancestor <= stop then
						break
					end
					local t = presentationTransforms[ancestor]
					if t ~= nil then
						ox += t.x or 0
						oy += t.y or 0
					end
				end
				i -= 1
			end
		end
		handle.presentationOffsetX = ox
		handle.presentationOffsetY = oy
		-- THE SIZE HALF, AND IT READS THIS NODE'S OWN TRANSFORM ONLY (withAnimation
		-- size, 2026-08-14). The loop above accumulates because a container's MOVE
		-- carries nothing inside it in a flat tree. A container's painted GROWTH
		-- carries nothing inside it either — and there that same fact means the
		-- opposite: every child holds an absolute rect, so it must keep its own solved
		-- size while its parent's box travels. So: no ancestor walk, one lookup.
		local ownT = presentationTransforms[handle.path]
		handle.presentationSizeW = if ownT ~= nil and type(ownT.w) == "number" then ownT.w else 0
		handle.presentationSizeH = if ownT ~= nil and type(ownT.h) == "number" then ownT.h else 0
	end

	local function applyHitExpander(handle: any)
		local expander = handle.hitExpander
		local rect = handle.hitRectWant
		if expander == nil or rect == nil then
			return
		end
		local ox, oy = 0, 0
		if handle.instanceHost ~= nil and handle.instanceHost.rect ~= nil then
			ox, oy = handle.instanceHost.rect.x, handle.instanceHost.rect.y
		end
		-- the expander is this control's HIT surface, so it travels with the paint:
		-- a shifted control whose target stayed behind would be a control you can see
		-- and cannot press
		expander.Position = UDim2.fromOffset(
			rect.x - ox + (handle.presentationOffsetX or 0),
			rect.y - oy + (handle.presentationOffsetY or 0)
		)
		expander.Size = UDim2.fromOffset(rect.w, rect.h)
		expander.ZIndex = handle.instance.ZIndex - 1
	end

	-- ONE teardown for the expander and everything wired onto it. Destroying the
	-- instance disconnects its own signals, but the handle slot has to go dead too
	-- or `setPointerHandlers` would see a stale `hitExpanderPointerConn` and refuse
	-- to wire the NEXT expander this handle grows (a recycled node's hit rect
	-- arriving after its handlers — see that function's order note).
	local function dropHitExpander(handle: any)
		if handle.hitExpanderPointerConn ~= nil then
			handle.hitExpanderPointerConn:Disconnect()
			handle.hitExpanderPointerConn = nil
		end
		if handle.hitExpander ~= nil then
			handle.hitExpander:Destroy()
			handle.hitExpander = nil
		end
	end

	local function applyRect(handle: any)
		local rect = handle.windowRect
		if rect == nil then
			return
		end
		local ox, oy = 0, 0
		if handle.instanceHost ~= nil and handle.instanceHost.rect ~= nil then
			ox, oy = handle.instanceHost.rect.x, handle.instanceHost.rect.y
		end
		-- THE PAINTED SIZE (withAnimation size, 2026-08-14): the solved extent plus
		-- this node's own presentation delta. Zero for every node that is not
		-- mid-flight, which is every node almost all of the time.
		local pw = rect.w + (handle.presentationSizeW or 0)
		local ph = rect.h + (handle.presentationSizeH or 0)
		if handle.motionAnchorCentered then
			-- a live motion scale re-anchored this instance to its center so the
			-- UIScale pivots there (director fix round: pops and the drag ghost grew
			-- down-right from the top-left) — same rect, written as its center.
			-- Half the PAINTED extent, so the two branches place the same box: a
			-- growing node extends down-right from its solved origin either way.
			handle.instance.Position = UDim2.fromOffset(
				rect.x - ox + (handle.presentationOffsetX or 0) + pw / 2,
				rect.y - oy + (handle.presentationOffsetY or 0) + ph / 2
			)
		else
			handle.instance.Position = UDim2.fromOffset(
				rect.x - ox + (handle.presentationOffsetX or 0),
				rect.y - oy + (handle.presentationOffsetY or 0)
			)
		end
		handle.instance.Size = UDim2.fromOffset(pw, ph)
		applyHitExpander(handle)
		if handle.focusRingFloat ~= nil and handle.focusRingFloat.Parent ~= nil then
			-- the float ring rides the focused rect (it lives in the host,
			-- so a row that re-arranges must carry its ring along)
			local t = handle.focusRingFloat:FindFirstChild("FocusRing")
			local thickness = if t ~= nil and t:IsA("UIStroke") then t.Thickness else 2
			handle.focusRingFloat.Position = UDim2.fromOffset(
				rect.x - ox + thickness + (handle.presentationOffsetX or 0),
				rect.y - oy + thickness + (handle.presentationOffsetY or 0)
			)
			-- the ring traces the PAINTED box: a ring left at the solved size while its
			-- node's box travels would visibly detach from the control it marks
			handle.focusRingFloat.Size = UDim2.fromOffset(pw - 2 * thickness, ph - 2 * thickness)
		end
		-- a semantic icon is clamped to the box this node actually has, so a rect
		-- that lands after the picture did has to re-fit it (director report
		-- 2026-07-28). No-op for every node carrying no icon art.
		refitIconArt(handle)
		if handle.path2d ~= nil then
			-- normalized control points re-scale with the solved rect (NS-A7)
			applyPathPoints(handle)
		end
	end

	-- the paint half of a transform: SCALE and ROTATION reach only the node's own
	-- instance (and whatever is really parented under it), which is why the
	-- reference points a subtree-scaling caller at a `canvasGroup` node.
	--
	-- `UIScale` IS SHARED WITH THE PRESS DIP. The engine honours ONE UIScale per
	-- object, so a second instance would make the winner unpredictable — a
	-- pressable control's motion scale therefore writes the dip's own instance, and
	-- the last writer wins by design rather than by accident.
	local function applyPresentationPaint(handle: any, t: any)
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return
		end
		local scale = if type(t) == "table" and type(t.scale) == "number" then t.scale else nil
		local existing = handle.motionScale or handle.uiScale
		-- THE PRESS DIP'S RESTING TARGET (ADR-0026 Consequences, fixed 2026-08-14).
		-- The composed scale this authority is writing IS what a dip must come back
		-- to, and this is the one moment it is known. Recorded even when the
		-- instance is shared with the dip — especially then, since that sharing is
		-- what made an absolute recovery destroy an authored scale. Cleared, not set
		-- to 1, when nothing is scaling: `screen_paint.restingScale` reads it with
		-- `or 1`, so an unscaled control never grows a field.
		handle.restingScale = if scale ~= nil and scale ~= 1 then scale else nil
		if scale ~= nil and scale ~= 1 then
			local live = existing
			if live == nil then
				live = ensureScale(instance, handle)
				handle.motionScale = live
			end
			live.Scale = scale
			-- CENTERED PIVOT (director fix round, RR parity): UIScale scales around
			-- the AnchorPoint, and the flat tree anchors top-left, so every pop and
			-- the drag ghost's pickup grow crawled down-right. While a motion scale
			-- is live the instance is re-anchored to its center; applyRect writes
			-- the same rect as its center point, so nothing else moves.
			if not handle.motionAnchorCentered then
				handle.motionAnchorCentered = true
				instance.AnchorPoint = Vector2.new(0.5, 0.5)
			end
		elseif existing ~= nil then
			existing.Scale = 1
			if handle.motionScale ~= nil then
				handle.motionScale:Destroy()
				handle.motionScale = nil
			end
			if handle.motionAnchorCentered then
				handle.motionAnchorCentered = nil
				instance.AnchorPoint = Vector2.new(0, 0)
			end
		end
		-- Rotation is paint-only in Roblox (it never moves layout or hit geometry),
		-- and no rule writes it, so it needs no claim
		local rotation = if type(t) == "table" and type(t.rotation) == "number" then t.rotation else 0
		instance.Rotation = rotation
	end

	-- THE `transform` PROP, whole (ADR-0022 Decision 2; fixes SF-M9 — this branch
	-- simply did not exist, so every keep-visible shift was a headless green that
	-- never moved a device). It lives here rather than in the host's setProp because
	-- it is the ONE writer of `presentationCount`, which a number cannot share by
	-- reference. Offset composes onto the solver's rect for this node AND its
	-- subtree (the tree is flat — see recomputePresentationOffset); scale and
	-- rotation are paint on its own instance. `nil` clears.
	local function setTransform(handle: any, value: any)
		local previous = presentationTransforms[handle.path]
		if value == nil then
			if previous ~= nil then
				presentationCount -= 1
			end
			presentationTransforms[handle.path] = nil
		else
			if previous == nil then
				presentationCount += 1
			end
			presentationTransforms[handle.path] = value
		end
		applyPresentationPaint(handle, value)
		for _, other in subtreeOf(handle.path) do
			recomputePresentationOffset(other)
			applyRect(other)
		end
	end

	-- ONE PATH'S TWO CHANNEL RECORDS DIE TOGETHER, called by `remove` (one node)
	-- and by `destroyRoot` (every node under the root — a target hosts several
	-- roots at once, so neither can be a blanket reset).
	--
	-- The PRESENTATION record dies with the node, or a re-created path inherits a
	-- transform nothing is driving any more (and `presentationCount` — the
	-- zero-cost fast path every rect write consults — would never fall back to 0).
	-- ...and so does its REAL-PARENT record. A stale entry keeps re-parenting new
	-- nodes into a destroyed instance, which is the one way a flat tree can lose a
	-- whole subtree silently.
	local function dropPath(path: string)
		if presentationTransforms[path] ~= nil then
			presentationTransforms[path] = nil
			presentationCount -= 1
		end
		unregisterHost(path)
	end

	-- the subtree index is DERIVED from `handlesByPath`, so it dies with any
	-- structural change rather than being patched at the five sites that cause one
	-- (create, park, adopt, remove, destroyRoot). A rebind, not a `table.clear`,
	-- because `subtreeOf` hands its inner arrays out to callers mid-iteration.
	local function invalidateSubtree()
		subtreeCache = {}
	end

	return {
		-- `presentationTransforms` goes back BY REFERENCE — the host reads
		-- `presentationTransforms[path]` directly. `instanceHosts` does NOT: it is
		-- reached only through the four functions below, so the registration
		-- policy ADR-0032 changes has exactly one place to live (see the
		-- registry's own header).
		presentationTransforms = presentationTransforms,
		registerHost = registerHost,
		unregisterHost = unregisterHost,
		hostAt = hostAt,
		hostFor = hostFor,
		recomputePresentationOffset = recomputePresentationOffset,
		applyHitExpander = applyHitExpander,
		dropHitExpander = dropHitExpander,
		applyRect = applyRect,
		applyPathPoints = applyPathPoints,
		setTransform = setTransform,
		dropPath = dropPath,
		invalidateSubtree = invalidateSubtree,
	}
end

return screen_presentation
