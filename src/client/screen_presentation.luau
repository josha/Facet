--!strict
-- ScreenPresentation — THE PRESENTATION CHANNEL of the
-- ScreenTarget adapter, plus the REAL-PARENT (instance host) record it composes
-- against, extracted from src/client/screen_target.luau for Studio's
-- 200_000-character `Source` WRITE cap. Over that cap a module silently stops
-- live-syncing into an open Studio session, so every live check against it
-- tests the built place rather than the edits on disk, once it is over the
-- 200,000-char Source WRITE cap. Strictly
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
-- not — the nested-tree migration made the registry private behind
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

-- Path2D control-point application (the native substrate; spike m5-path2d.json): normalized
-- points (unit box, tangents relative to the point) scale into the CURRENT
-- solved rect. Engine truths: max 100 control points; no Transparency
-- property; left tangent = incoming handle, right = outgoing.
--
--[[ THE POINTS RIDE `Scale`, NOT `Offset` (2026-08-29, the director's Pixel Quest
	HUD: "the circular progress bar is also not circular ... the green does not
	totally cover the yellow part").

	`UDim.Offset` IS AN INT32 — measured live in this session on a Path2D round
	trip: `UDim2.new(0, 25.05, 0, 6.95)` reads back as `(25, 6)`, and the same
	pair written as `Scale` survives to six decimal places. So the previous form,
	`UDim2.fromOffset(p.x * w, p.y * h)`, TRUNCATED every control point to a whole
	pixel, and a circle is the shape that reports it loudest:

	  * the truncation is ASYMMETRIC — on the shipped 32px ring (radius 0.8 of the
	    half-extent = 12.8px) the 3 o'clock and 6 o'clock extremes lost 0.8px while
	    12 o'clock and 9 o'clock lost 0.2, so a circle came out an off-centre egg;
	  * a CLOSED ring's last point is its first — `arc(0, 360)` — and
	    `sin(2*pi)` is a hair BELOW zero, so `16 - 1e-15` floored to **15** while
	    the identical first point floored to 16. The track therefore closed one
	    pixel left of where it opened and painted a notch of bare track past the
	    arc's own start: the "green does not cover the yellow" seam, at the exact
	    12 o'clock the fixture's ring starts from.

	`Scale` needs no `w`/`h` at all, because the points are ALREADY normalized to
	the unit box and the engine resolves scale against the parent's own size. That
	parent is this handle's instance, whose `Size` `applyRect` writes as exactly
	the painted box (`rect + presentationSize`) — so the "re-scales with a box that
	is travelling" promise below is now kept by the engine rather than re-derived
	here, and a shape can no longer be a frame behind its own node. ]]
--[[ ...AND THE UPLOAD IS VALUE-DIFFED, like every other channel this adapter
	owns (2026-09-07).

	`SetControlPoints` is not a property assignment. It hands the engine a whole
	new vector geometry and the engine does not diff it, so it is the most
	expensive single call this target can make on a `Path` node. `applyRect`
	calls it on EVERY rect write — and, since the points moved to `Scale`, for
	numbers that are the same every time. The paragraph above says so out loud:
	"these are the same numbers every time". So a ring re-uploaded its geometry on
	every solve that moved its box, and a rotation moves every box.

	MEASURED on the shipped `hud` fixture, live: with this diff the two ring nodes
	upload ONCE for the life of the surface instead of once per rect write.

	BY VALUE AND NOT BY IDENTITY, because the `points` prop arrives as a fresh
	table on every rebuild of the blueprint — an identity check would never fire.
	The applied set is COPIED rather than aliased: the caller's table is not this
	adapter's to hold, and a caller that mutates its own array in place would
	otherwise make this record agree with a geometry the engine never got.

	THE RULE THIS RESTORES: a render target may not re-issue a write it already
	owns with the value it already wrote. `render/commit_walks.luau` holds every
	other channel to it; this one was the exception. It is NOT a fix for the
	chrome-rotation paint loss — measured, it does not move that defect — and it
	is not offered as one. ]]
local function samePathPoints(applied: { any }?, points: { any }): boolean
	if applied == nil or #applied ~= #points then
		return false
	end
	for i = 1, #points do
		local a, p = applied[i], points[i]
		if a.x ~= p.x or a.y ~= p.y or a.inX ~= p.inX or a.inY ~= p.inY or a.outX ~= p.outX or a.outY ~= p.outY then
			return false
		end
	end
	return true
end

local function applyPathPoints(handle: any)
	local path2d = handle.path2d
	local points = handle.normPoints
	if path2d == nil or points == nil then
		return
	end
	if samePathPoints(handle.appliedPathPoints, points) then
		return
	end
	local cps = table.create(#points)
	local applied = table.create(#points)
	for _, p in points do
		table.insert(
			cps,
			Path2DControlPoint.new(
				UDim2.fromScale(p.x, p.y),
				UDim2.fromScale(p.inX, p.inY),
				UDim2.fromScale(p.outX, p.outY)
			)
		)
		table.insert(applied, { x = p.x, y = p.y, inX = p.inX, inY = p.inY, outX = p.outX, outY = p.outY })
	end
	path2d:SetControlPoints(cps)
	handle.appliedPathPoints = applied
end

function screen_presentation.new(ctx: any)
	local handlesByPath = ctx.handlesByPath
	local refitIconArt = ctx.refitIconArt
	local ensureScale = ctx.ensureScale

	--[[ THE INSTANCE-HOST REGISTRY — THE ONE RECORD THAT MAKES A NODE A REAL PARENT.
		(Named `clipHosts` until the nested-tree migration, after the first of its
		three triggers.)

		A registered node's descendants parent UNDER it in the engine hierarchy,
		with positions relative to it; everything else stays flat under the root.
		Three declarations register one today — a `ScrollView` (by construction),
		an authored `clipChildren`, and a fade group — and only the first of the
		three is about clipping, which is why the name moved. `path` is on the
		entry for the presentation channel: an offset
		accumulating down a subtree stops at the nearest REAL PARENT, whose own
		move already carries its children, and this is how a child knows where
		that is.

		THE TABLE IS PRIVATE, AND THAT IS THE POINT OF THIS STEP. Nesting is a
		REGISTRATION POLICY, not a renderer rewrite — "switching to nested is a
		change to one predicate: which paths get registered". A policy needs one
		place to live, so the record is born in `registerHost` and dies in
		`unregisterHost`, and the host reads it through `hostAt`/`hostFor` rather
		than indexing a shared table at four call sites. The invariant is
		structural now instead of a convention a fifth call site can miss.
	]]
	local instanceHosts: {
		[string]: { instance: Instance, rect: any?, children: { any }, path: string, hostSpace: boolean? },
	} =
		{}

	--[[ CREATE-OR-REUSE, and both halves are load-bearing.

		REUSE: a node may declare itself a real parent TWICE — a fade group
		registers while `create` is still choosing its engine class, and an authored
		`clipChildren` registers again at the prop write. Replacing the entry would
		strand every child already re-based against it, so the first registration
		wins and the second hands back the same table.

		`crops` ACCUMULATES rather than being overwritten, and it is not a synonym
		for `clipChildren`. The question the framework actually asks a host is "can
		something drawn OUTSIDE a child's own box survive here" — which is what the
		focus ring's float placement turns on, since a ring is a stroke that extends
		past the rect it marks. A `ClipsDescendants` host answers no. A `CanvasGroup`
		answers no as well despite never setting that property, because it renders
		its subtree into a buffer its own size. A plain move-boundary host — the kind
		a later step registers so the engine can carry a subtree — answers YES, and
		it must, or a ring that only ever needed to float inside a scroll canvas
		would start floating under every container that merely moves.
	]]
	--[[ `hostSpace` ACCUMULATES THROUGH THE REUSE PATH THE WAY `crops` DOES, and it
		has to (Plan C): a path can be registered TWICE — once by this file's own
		ScrollView/`clipChildren` triggers and again from `createOpts.instanceHost` —
		and if the second call dropped the flag, `applyRect` would subtract the host
		rect from children whose rects are ALREADY relative to it, landing every one
		of them at `rect - host`. ]]
	local function registerHost(path: string, instance: Instance, rect: any?, crops: boolean, hostSpace: boolean?): any
		local existing = instanceHosts[path]
		if existing ~= nil then
			existing.crops = existing.crops or crops
			existing.hostSpace = existing.hostSpace or hostSpace
			return existing
		end
		local entry =
			{ instance = instance, rect = rect, children = {}, path = path, crops = crops, hostSpace = hostSpace }
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
	-- free. The nested-tree migration's entire content is "register more hosts", so that loop
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
	-- origin arrives or moves. rich-skinning v2-D1b (found live 2026-07-26): the renderer pushes
	-- hit rects BEFORE the commit that writes rects, so on a fresh build an instance host's
	-- rect is not yet current when the expander is first placed, and the renderer's
	-- own cache (which stores only the WANTED rect) never asks again. Measured after a
	-- scenario `reset()`: an expander 74px below the button it belongs to. Placing it
	-- here, in the one function that re-bases a node, is what makes the two unable to
	-- disagree.
	-- ===== THE PRESENTATION CHANNEL =================
	--
	-- A presentation transform composes onto the solver's rect at the WRITE, so a
	-- motion never touches solver geometry and a re-solve never loses the motion:
	-- `applyRect` is the one place a Position is written, and it adds the offset
	-- every time.
	--
	-- THE INSTANCE TREE IS MOSTLY FLAT, and
	-- that is the load-bearing fact here. Every node parents under the root gui
	-- unless a REAL PARENT claimed it (an instance host: a clip host, a scroll host, a
	-- fade group, a scaled/rotated container, or a COORDINATE-SPACE host), so
	-- moving a container's own instance moves nothing but that container — the
	-- keyboard keep-visible shift on the root node would have moved one transparent
	-- frame and nothing the player can see. So the offset ACCUMULATES down the
	-- subtree: a node pays its own transform plus every ancestor's, stopping at its
	-- real parent, whose own move already carries it. One rule, and the root case
	-- (the whole surface shifts) falls out of it.
	--
	-- ...AND ONE KIND OF HOST BREAKS THE OTHER HALF OF "FLAT" (Plan C): beneath a
	-- COORDINATE-SPACE host the solver stores rects RELATIVE to the host rather than
	-- in window space, so it is the one host whose children's rects are not window
	-- coordinates and the one whose origin `applyRect` must NOT subtract — the
	-- subtraction has already happened, in the solver. `hostOriginOf` below is the
	-- single place that distinction lives.
	local presentationTransforms: { [string]: any } = {}
	local presentationCount = 0
	-- THE ENGINE-WRITE COUNTER (Plan C, T0): `applyRect` is the ONLY writer of
	-- this instance's Position/Size (see its header), so this is the true bill
	-- the engine was handed — not the `setRect` CALL count `stats.rectWrites`
	-- already tracks two levels up, but the write that survives the
	-- write-skip compare below. Hit expanders and decorations are NOT
	-- counted: they are a different instance, written unconditionally, and
	-- not the collapse this campaign measures.
	local engineWriteCount = 0
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
		-- UDim offsets truncate to whole pixels. A spring approaching from below
		-- otherwise stays one pixel short until its transform clears, then pops.
		-- Round the composed delta once so the node, hit expander and focus ring
		-- reach their resting pixels together, without changing the solver's rect.
		handle.presentationOffsetX = math.round(ox)
		handle.presentationOffsetY = math.round(oy)
		-- THE SIZE HALF, AND IT READS THIS NODE'S OWN TRANSFORM ONLY (withAnimation
		-- size, 2026-08-14). The loop above accumulates because a container's MOVE
		-- carries nothing inside it in a flat tree. A container's painted GROWTH
		-- carries nothing inside it either — and there that same fact means the
		-- opposite: every child holds an absolute rect, so it must keep its own solved
		-- size while its parent's box travels. So: no ancestor walk, one lookup.
		local ownT = presentationTransforms[handle.path]
		handle.presentationSizeW = if ownT ~= nil and type(ownT.w) == "number" then math.round(ownT.w) else 0
		handle.presentationSizeH = if ownT ~= nil and type(ownT.h) == "number" then math.round(ownT.h) else 0
	end

	--[[ THE ORIGIN A NODE'S ENGINE `Position` IS RELATIVE TO — its real instance
		parent, or (0, 0) when it has none. ZERO UNDER A COORDINATE-SPACE HOST (Plan
		C): the solver already stored that subtree's rects relative to the host, so
		there is nothing left to subtract. Three sites read it (the rect, the hit
		expander, the focus-ring float) and they must not be able to disagree. ]]
	local function hostOriginOf(handle: any): (number, number)
		local host = handle.instanceHost
		if host == nil or host.rect == nil or host.hostSpace == true then
			return 0, 0
		end
		return host.rect.x, host.rect.y
	end

	local function applyHitExpander(handle: any)
		local expander = handle.hitExpander
		local rect = handle.hitRectWant
		if expander == nil or rect == nil then
			return
		end
		local ox, oy = hostOriginOf(handle)
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
		local ox, oy = hostOriginOf(handle)
		-- THE PAINTED SIZE (withAnimation size, 2026-08-14): the solved extent plus
		-- this node's own presentation delta. Zero for every node that is not
		-- mid-flight, which is every node almost all of the time.
		--
		-- ...AND THE "auto" SCROLL BAR'S OVERLAY DELTA (director ruling 2026-08-28,
		-- `screen_scroll_indicators.applyBarOverlayWiden`): zero for every node
		-- that is not an overflowing auto-policy scroll host, which is every node
		-- and almost every scroll host almost all of the time. Riding the SAME
		-- additive seam as the animation delta rather than a second writer, for
		-- the reason the paragraph below this one states about `applyRect` itself.
		local pw = rect.w + (handle.presentationSizeW or 0) + (handle.barOverlayWidenW or 0)
		local ph = rect.h + (handle.presentationSizeH or 0) + (handle.barOverlayWidenH or 0)
		local px = rect.x - ox + (handle.presentationOffsetX or 0)
		local py = rect.y - oy + (handle.presentationOffsetY or 0)
		if handle.motionAnchorCentered then
			-- a live motion scale re-anchored this instance to its pivot so the
			-- UIScale pivots there (director fix round: pops and the drag ghost grew
			-- down-right from the top-left; centred by default, a named corner for
			-- an anchored popover) — same rect, written at its pivot.
			-- The PAINTED extent's fraction, so the two branches place the same box: a
			-- growing node extends down-right from its solved origin either way.
			px += pw * (handle.motionPivotX or 0.5)
			py += ph * (handle.motionPivotY or 0.5)
		end
		--[[ THE WRITE A HOST MAKES UNNECESSARY (the arrange half).

			A `GuiObject.Position` is PARENT-RELATIVE, and `ox, oy` above is exactly
			the parent it is relative to. So when a HOST moves, every descendant's
			`rect` and the host's origin change by the same delta and `px, py` come
			out identical — measured on a 20-row list: the container moves, 120 of
			120 absolute positions change, and 0 of 120 change relative to the host.
			The shipped code wrote all 120 anyway. That is the 120-write bill,
			and every one of those writes stored the number already there.

			SO THE MECHANISM IS NOT "WRITE LESS", IT IS "KNOW WHAT YOU WROTE". This
			function already computed the pair; it simply never compared it to the
			pair it wrote last time. Under a host that moved, the compare matches and
			the bill collapses to the host's own single write. With no host above the
			node the compare almost always differs — its absolute position really did
			change — and it costs two number compares, which is why this is a general
			rule rather than a nesting special case.

			WHY THE CACHE CANNOT GO STALE. `applyRect` is the ONLY writer of this
			instance's `Position`/`Size` — checked across the whole adapter; every
			other `.Position =` in `src/client/` targets a decoration CHILD (a label,
			a track, a knob, an ornament, the float ring below), and the one
			`TweenService` animation of a Position drives a toggle's knob, not a
			node's own instance. THE ENGINE DOES NOT WRITE IT EITHER, and that is not
			luck: `setDragDetector` attaches its `UIDragDetector` in `CustomOffset`
			mode precisely so the detector never writes Position — the default
			`Offset` mode "would fight it, measured in the spike" — so the renderer
			already holds sole authority over this property and this cache is a
			record of an authority that was established for other reasons.
			`park` sets `Parent = nil` and leaves the geometry
			alone, so a pooled instance's real position still matches its cache when
			`adopt` re-parents it; the cache lives on the handle, and a handle that
			loses its instance loses the cache with it. The AnchorPoint flip needs no
			invalidation of its own because it MOVES `px`/`py` by half the extent,
			so the compare misses exactly when the anchor changes meaning.
		]]
		if handle.lastWriteX ~= px or handle.lastWriteY ~= py then
			handle.instance.Position = UDim2.fromOffset(px, py)
			handle.lastWriteX, handle.lastWriteY = px, py
			engineWriteCount += 1
		end
		if handle.lastWriteW ~= pw or handle.lastWriteH ~= ph then
			handle.instance.Size = UDim2.fromOffset(pw, ph)
			handle.lastWriteW, handle.lastWriteH = pw, ph
			engineWriteCount += 1
		end
		applyHitExpander(handle)
		if handle.focusRingFloat ~= nil and handle.focusRingFloat.Parent ~= nil then
			-- the float ring rides the focused rect (it lives in the cropping host,
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
			-- The points are `Scale` now, so the ENGINE re-scales them with the box
			-- this function just wrote and these are the same numbers every time.
			-- Kept as the belt: `normPoints` is applied by its own prop setter, and
			-- this is the only other place that knows a path node has a box at all.
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
	-- the named pivot as AnchorPoint fractions (schema.TRANSITION_PIVOTS); the
	-- centre when nothing is named, which is every motion before the picker round
	local PIVOT_FRACTIONS: { [string]: { number } } = {
		center = { 0.5, 0.5 },
		topLeft = { 0, 0 },
		topRight = { 1, 0 },
		bottomLeft = { 0, 1 },
		bottomRight = { 1, 1 },
	}
	local function pivotFractions(pivot: any): (number, number)
		local pair = if type(pivot) == "string" then PIVOT_FRACTIONS[pivot] else nil
		if pair == nil then
			return 0.5, 0.5
		end
		return pair[1], pair[2]
	end

	local function applyPresentationPaint(handle: any, t: any)
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return
		end
		local scale = if type(t) == "table" and type(t.scale) == "number" then t.scale else nil
		local existing = handle.motionScale or handle.uiScale
		-- THE PRESS DIP'S RESTING TARGET (fixed 2026-08-14).
		-- The composed scale this authority is writing IS what a dip must come back
		-- to, and this is the one moment it is known. Recorded even when the
		-- instance is shared with the dip — especially then, since that sharing is
		-- what made an absolute recovery destroy an authored scale. Cleared, not set
		-- to 1, when nothing is scaling: `screen_paint.restingScale` reads it with
		-- `or 1`, so an unscaled control never grows a field.
		handle.restingScale = if scale ~= nil and scale ~= 1 then scale else nil
		-- Keep an explicit settled scale on the same engine pivot. Removing UIScale
		-- at exactly 1 changes Roblox's pixel rounding and jumps a radial segment
		-- by a pixel on its final frame. Clearing the transform still releases it.
		if scale ~= nil and (scale ~= 1 or handle.motionAnchorCentered) then
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
			local fx, fy = pivotFractions(if type(t) == "table" then t.pivot else nil)
			if not handle.motionAnchorCentered or handle.motionPivotX ~= fx or handle.motionPivotY ~= fy then
				handle.motionAnchorCentered = true
				handle.motionPivotX, handle.motionPivotY = fx, fy
				instance.AnchorPoint = Vector2.new(fx, fy)
			end
		elseif existing ~= nil then
			existing.Scale = 1
			if handle.motionScale ~= nil then
				--[[ BOTH REFERENCES DIE, OR THE NEXT SCALE WRITES TO A CORPSE.

					`screen_paint.ensureScale` records the instance it makes on
					`handle.uiScale`; the branch above then records the SAME instance on
					`handle.motionScale`. Two fields, one object, and only one of them
					used to be cleared here.

					The read at the top of this function is
					`handle.motionScale or handle.uiScale`, so a surviving `uiScale`
					means the next non-1 scale finds a DESTROYED instance, concludes one
					already exists, and writes `Scale` to it. That write SUCCEEDS — a
					destroyed instance accepts every write except a non-nil Parent, which
					is the same engine fact `parkEligible`'s corpse gate is built on — so
					the node silently stops scaling while its rotation, a direct property,
					keeps working.

					FOUND ON A PHYSICAL DEVICE (director, 2026-08-17): turn the
					nested-compositing demo on, off, and on again, and the second turn
					rotates without scaling. Reproduced in Studio through the real
					presenter — `Carried` at TURN2 read `Abs=100x70 AbsRot=30.0
					UIScale=none`. It reaches any authored `scale` that is ever animated
					to 1 and back, which since nesting includes a container whose
					whole subtree rides the term.

					Guarded on identity rather than cleared unconditionally: when the
					scale instance is the PRESS DIP's rather than the motion's, this
					branch does not destroy it at all (see the `motionScale ~= nil` test
					it sits under), and clearing `uiScale` there would strand the dip. ]]
				if handle.uiScale == handle.motionScale then
					handle.uiScale = nil
				end
				handle.motionScale:Destroy()
				handle.motionScale = nil
			end
			if handle.motionAnchorCentered then
				handle.motionAnchorCentered = nil
				handle.motionPivotX, handle.motionPivotY = nil, nil
				instance.AnchorPoint = Vector2.new(0, 0)
			end
		end
		-- Rotation is paint-only in Roblox (it never moves layout or hit geometry),
		-- and no rule writes it, so it needs no claim
		local rotation = if type(t) == "table" and type(t.rotation) == "number" then t.rotation else 0
		instance.Rotation = rotation
	end

	-- THE `transform` PROP, whole (fixes the headless-green/device-wrong class — this branch
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
		-- policy nesting changes has exactly one place to live (see the
		-- registry's own header).
		presentationTransforms = presentationTransforms,
		registerHost = registerHost,
		unregisterHost = unregisterHost,
		hostAt = hostAt,
		hostFor = hostFor,
		hostOriginOf = hostOriginOf,
		recomputePresentationOffset = recomputePresentationOffset,
		applyHitExpander = applyHitExpander,
		dropHitExpander = dropHitExpander,
		applyRect = applyRect,
		applyPathPoints = applyPathPoints,
		setTransform = setTransform,
		dropPath = dropPath,
		invalidateSubtree = invalidateSubtree,
		engineWrites = function()
			return engineWriteCount
		end,
	}
end

return screen_presentation
