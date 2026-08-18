--!strict
--[[ THE PER-NODE PRESENTATION CHANNEL, as a factory.

	The renderer's motion write surface: `transform` and `transparency` are
	PRESENTATION properties (authority manifest §7.3), and this is the only thing
	in the library that writes them. A transform never touches solver geometry —
	no Size, no re-solve, no layout-affecting animation — and never writes a
	native-sheet-owned property, which is what lets a 60 Hz motion run beside sheet
	paint without contesting it.

	Three contributors, ONE write site (ADR-0026 Decision 3): the imperative
	channel (`setPresentationTransform` / `setPresentationTransparency`), the
	AUTHORED triple a blueprint declares (`opacity`/`scale`/`rotation`), and the
	`withAnimation` records that fly a commit's rect and paint deltas home on one
	spring. They compose; they never take turns at the adapter.

	`presentation_channel.new(deps) -> channel`, one per attached surface. `deps`:
	  core      the reactive core, for the progress spring's observation
	  root      the mounted root (the record walk is top-down over it)
	  adapter   the RenderTargetAdapter — the only thing this module writes to
	  handles   path -> adapter handle, BY REFERENCE (the renderer mutates it)
	  lastRects path -> last solved rect, BY REFERENCE (the record diff reads it)
	  findNode  path -> mounted node

	The four tables/functions above are shared BY REFERENCE and never reassigned on
	either side — `dispose` clears `handles`/`lastRects` in place for exactly that
	reason. That is what made this seam cheap: nothing here needs a callback to
	read a reassigned local.

	The channel's surface, all of it consumed by `render/renderer.luau`:
	  setPresentationTransform / setPresentationTransparency / armAnimation /
	  disarmAnimation / animationRecordCount   -- rebound onto `controller`, so
	                                              the public API did not move
	  presentationShift(path) -> dx, dy        -- the geometry half, for window-space rects
	  readAuthoredPresentation(node) -> moved  -- mount-time re-read
	  paintAuthored(path)                      -- the gated mount-time push
	  reactAuthored(paths)                     -- the dirty-commit re-read
	  installAnimationRecords(rects) / armed() -- the armed commit
	  forgetPath(path) / dropNodeCache()       -- the renderer's two cache sweeps
	  composedAlpha(path)                      -- what the overlap alarm reads
	  settleAll()                              -- teardown

	WHY IT IS ITS OWN FILE. Roblox refuses a `Script.Source` assignment at 200,000
	characters or more, and every LIVE path is a write — the Rojo plugin,
	`execute_luau`, any plugin — so a module over the cap silently stops syncing
	into an open Studio session and a live check against it then tests the code
	baked into the place rather than the edits on disk
	(docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md). `renderer.luau`
	was 242,943 characters; this seam was the one the last mission to raise it
	proposed, and taking it is what puts the file back under the cap.

	Depends on: render/presentation (the pure arithmetic — the composition rules,
	the authored triple's domain checks, the write memo's comparison) and
	render/authority (the per-property write assertion).
]]

local authority = require("./authority")
-- the presentation channel's arithmetic (ADR-0026): the composition rules, the
-- authored triple's domain checks, and the write memo's comparison. Pure.
local presentation = require("./presentation")

local presentation_channel = {}

function presentation_channel.new(deps: {
	core: any,
	root: any,
	adapter: any,
	handles: { [string]: any },
	lastRects: { [string]: any },
	findNode: (path: string) -> any,
}): any
	local core = deps.core
	local root = deps.root
	local adapter = deps.adapter
	-- BY REFERENCE, both of them: the renderer creates and retires handles and
	-- rewrites rects every solve, and this module must see those edits. Neither
	-- side may ever rebind the name (`dispose` clears in place).
	local handles = deps.handles
	local lastRects = deps.lastRects
	local findNode = deps.findNode

	local channel = {}

	-- the presentation transform currently pushed per path (ADR-0022 Decision 2).
	-- The renderer's `screenRectOf` reads it through `presentationShift` below,
	-- because a rect compared against a POINTER has to answer where the node is
	-- PAINTED, and while a presentation offset is live that is not where the solver
	-- put it. It must
	-- also be forgotten when a path is removed: a re-created node starts at rest,
	-- and a cached value would suppress the write that puts it there (the same
	-- verdict-inheritance defect the visible and hit-rect caches were bitten by —
	-- verifier finding V10). `presentationLive` counts the non-nil entries so a
	-- surface with no motion running pays one integer compare per hit-test.
	local lastTransform: { [string]: any } = {}
	local presentationLive = 0
	-- AUTHORED PRESENTATION (ADR-0026, and render/presentation.luau's header): the
	-- blueprint's `opacity`/`scale`/`rotation` are a second TERM in this channel,
	-- never a second writer. `authoredN` is the off-path gate — zero means the
	-- composition is skipped entirely.
	local authored: { [string]: any } = {}
	local authoredN = 0
	local lastTransparency: { [string]: number } = {}
	-- what was last WRITTEN, per engine property: the memo must live on the COMPOSED
	-- value, or one contributor moving alone is swallowed by the other's cache
	local lastComposedTransform: { [string]: any } = {}
	local lastComposedAlpha: { [string]: number } = {}
	-- ===== `withAnimation` RECORDS (docs/plans/swiftui-parity-round2.md §Phase 1,
	-- "Blocker 3") ===========================================================
	-- A record is the RELATIVE delta a path is currently flying, installed only at
	-- an animation ROOT. Both halves of the presentation channel already accumulate
	-- ancestor offsets (see the accumulation rule below), so a per-node ABSOLUTE
	-- delta would paint a sliding panel's children at double the distance.
	--
	-- The record belongs to the PATH; the spring is merely the driver it is
	-- attached to right now. That is what keeps two calls off one `lastTransform`
	-- slot: a later call re-bases the path and re-attaches it, and the older
	-- spring's settle clears only what it still owns.
	--
	-- They live on the CHANNEL, which is per-surface (one `new()` per
	-- `renderer.attach`), because they are surface-scoped state that must be
	-- cleared per path at removal — see `channel.forgetPath`, which the renderer's
	-- retire sweep calls beside every other per-path cache it drops.
	local animationSession: any = nil -- non-nil only for the duration of an ARMED commit
	local animationBaseline: { [string]: boolean }? = nil
	local animationRecords: { [string]: any } = {}
	local animationSets: { any } = {}
	local animationRecordN = 0
	-- per-path `{ o, s, r }` deltas parked by an ARMED commit and consumed by the
	-- walk below (ADR-0026 Decision 7) — the authored value is already at its
	-- destination by then, the same reason the rect half needs `lastRects`
	local animationPaintDelta: { [string]: any } = {}
	-- FORWARD-DECLARED, and they must stay that way: each is assigned below with
	-- `function <name>(...)`, which without this line would define a GLOBAL, and
	-- each is also called from a closure defined above its assignment
	-- (docs/lessons/later-locals-are-not-upvalues.md)
	local installAnimationRecords: (rects: any) -> ()
	local animationClear: (path: string, write: boolean) -> ()
	-- the ONE presentation write site (ADR-0026 Decision 3) and the authored-triple
	-- re-read, forward-declared: mount and the commit both reach them from above
	local pushPresentationPaint: (path: string) -> ()
	local readAuthoredPresentation: (node: any) -> boolean
	-- PLAT-4 (platform verifier, 2026-07-27): the paint half of the presentation
	-- channel was sound and the geometry half was not — `screenRectOf` composed
	-- scroll offsets only, so while the keyboard keep-visible shift sat on the root
	-- (the whole time the OS keyboard is up) or an enter/exit slide sat on a region,
	-- Facet's own drop verdicts disagreed with what the player was looking at by
	-- exactly the offset.
	--
	-- THE ACCUMULATION RULE, IN WINDOW SPACE. The adapter stops its own
	-- accumulation at the nearest REAL PARENT (a clip host / fade group), because
	-- that parent's instance move already carries its children
	-- (screen_target.recomputePresentationOffset). In ABSOLUTE window space that
	-- stop cancels out — the parent re-adds its own shift by moving — so the
	-- painted rect of a node is its solved rect plus its own transform plus EVERY
	-- ancestor's, with no stop. One rule, and the root case (the whole surface
	-- shifts) falls out of it, exactly as it does on the paint side.
	--
	-- OFFSETS ONLY. A transform's `scale`/`rotation` reach only the node's own
	-- instance (and whatever is really parented under it) and would turn a hit rect
	-- into a quad; hit geometry stays axis-aligned this round and a scaled node
	-- hit-tests at its solved size (documented in docs/reference/api.md).
	local function presentationShift(path: string): (number, number)
		if presentationLive == 0 then
			return 0, 0
		end
		local dx, dy = 0, 0
		local own = lastTransform[path]
		if own ~= nil then
			dx += own.x or 0
			dy += own.y or 0
		end
		local i = #path
		while i > 1 do
			if string.sub(path, i, i) == "/" then
				local t = lastTransform[string.sub(path, 1, i - 1)]
				if t ~= nil then
					dx += t.x or 0
					dy += t.y or 0
				end
			end
			i -= 1
		end
		return dx, dy
	end
	-- path -> mounted node, memoized for the write sites below (see nodeAt). It is
	-- dropped wholesale by `channel.dropNodeCache`, which the renderer calls from
	-- `structuralSync`: mounted identity is stable except across a structural
	-- change, and that is the only place it can move.
	local presentationNodes: { [string]: any } = {}

	-- ===== THE PER-NODE PRESENTATION CHANNEL (ADR-0022 Decision 2) ==========
	--
	-- The authority manifest has declared `transform` and `transparency` as
	-- PRESENTATION properties since §7.3; before this channel the only writer was
	-- the keep-visible offset (`controller.setPresentationOffset`, still in the
	-- renderer), and it wrote them at the ROOT only. These two
	-- methods are the whole motion write surface: a transform never touches solver
	-- geometry (no Size, no re-solve, no layout-affecting animation) and never
	-- writes a native-sheet-owned property, which is what lets a 60 Hz motion run
	-- beside sheet paint without contesting it.
	--
	-- `nil` clears. Values are compared before writing, so a settled motion that
	-- keeps re-asserting its rest value costs nothing (minimal-write contract).
	local transformsEqual = presentation.transformsEqual

	-- the mounted node behind a path, memoized. A motion writes EVERY FRAME while it
	-- runs and each write needs the node's class (for the authority assertion), so
	-- walking the tree per write would put a tree walk on the frame budget. Mounted
	-- identity is stable except across a structural sync, which is where the cache is
	-- dropped (`channel.dropNodeCache`, called from the renderer's structuralSync).
	local function nodeAt(path: string): any
		local hit = presentationNodes[path]
		if hit ~= nil then
			return hit
		end
		local node = findNode(path)
		presentationNodes[path] = node
		return node
	end

	-- ===== THE ONE PRESENTATION WRITE SITE (ADR-0026 Decision 3) ==============
	-- Every contributor routes through here and NOTHING else in this file calls
	-- `adapter.setProp` for `transform` or `transparency` — which is what makes
	-- "one authority per engine property" a fact in the code rather than a claim in
	-- a comment (`tests/authored_presentation.spec.luau` counts the sites in the
	-- source). The arithmetic and its reasoning live in `render/presentation.luau`;
	-- what is here is the STATE and the write.
	--
	-- The memo is on the COMPOSED value, never on a contributor's: it was correct
	-- on the channel value while there was one contributor and would go stale the
	-- instant there were two.
	function pushPresentationPaint(path: string)
		local handle = handles[path]
		if handle == nil then
			return
		end
		local t = lastTransform[path]
		-- THE OFF-PATH GATE (Decision 9). Nothing on this surface authored one of the
		-- three, so there is nothing to compose and `composeTransform` returns the
		-- channel value by identity.
		local o, s, r = nil, nil, nil
		if authoredN > 0 then
			local rec = animationRecords[path]
			o, s, r = presentation.effective(authored[path], rec, if rec ~= nil then rec.set.spring:get() else 0)
		end
		local node: any = nil

		local composed = presentation.composeTransform(t, s, r)
		if not transformsEqual(lastComposedTransform[path], composed) then
			node = nodeAt(path)
			if node ~= nil then
				lastComposedTransform[path] = composed
				authority.assertWrite(node.class, "transform", "presentation")
				adapter.setProp(handle, "transform", composed, "presentation")
			end
		end

		local alpha = presentation.composeAlpha(lastTransparency[path], o)
		if lastComposedAlpha[path] ~= alpha then
			if node == nil then
				node = nodeAt(path)
			end
			if node ~= nil then
				lastComposedAlpha[path] = alpha
				authority.assertWrite(node.class, "transparency", "presentation")
				adapter.setProp(handle, "transparency", alpha, "presentation")
			end
		end
	end

	--[[ A FADE IS A FADE-GROUP FACT, and the node must have said so — either
		`canvasGroup = true`, or an authored `opacity`, which IS that declaration
		(ADR-0026 Decision 4). The alternative — writing BackgroundTransparency /
		TextTransparency per node — is exactly the write that permanently defeats a
		native sheet rule (spike m10), and it fades one node's own paint rather than
		the group the caller means. So the refusal is loud and names the fix instead
		of fading something nobody asked for. ]]
	local function isFadeGroup(node: any): boolean
		return node.props ~= nil and (node.props.canvasGroup == true or node.props.opacity ~= nil)
	end

	-- `w`/`h` are a PAINTED SIZE DELTA in pixels, added to the solved rect at the
	-- adapter's one Size write (withAnimation size, 2026-08-14). Unlike `x`/`y`
	-- they do NOT accumulate down the subtree: every rect is absolute, so a
	-- container's painted growth carries nothing inside it and must not.
	function channel.setPresentationTransform(
		path: string,
		t: {
			x: number,
			y: number,
			w: number?,
			h: number?,
			scale: number?,
			rotation: number?,
		}?
	)
		local handle = handles[path]
		if handle == nil then
			return
		end
		if transformsEqual(lastTransform[path], t) then
			return
		end
		local node = nodeAt(path)
		if node == nil then
			return
		end
		if (lastTransform[path] == nil) ~= (t == nil) then
			presentationLive += if t ~= nil then 1 else -1
		end
		lastTransform[path] = t
		pushPresentationPaint(path)
	end

	function channel.setPresentationTransparency(path: string, alpha: number?)
		local handle = handles[path]
		if handle == nil then
			return
		end
		local node = nodeAt(path)
		if node == nil then
			return
		end
		if not isFadeGroup(node) then
			error(
				`Facet presentation: {path} cannot be faded — presentation transparency needs a fade GROUP. `
					.. "Wrap the subtree in UI.Box{ canvasGroup = true } (or declare an authored `opacity`, "
					.. "which implies one) and fade that: GroupTransparency is one engine property no style "
					.. "rule owns, while per-node transparency would contest native-sheet paint and fade only "
					.. "that node's own glyphs or fill.",
				0
			)
		end
		if lastTransparency[path] == alpha then
			return
		end
		lastTransparency[path] = alpha
		pushPresentationPaint(path)
	end

	-- THE AUTHORED TRIPLE, re-read off the LIVE tree (ADR-0026). The reading and
	-- its domain checks are `presentation.readAuthored`; what is here is the
	-- bookkeeping — the map, and `authoredN`, which is the off-path gate above.
	-- Returns true when the stored triple moved, so a caller can skip a write.
	function readAuthoredPresentation(node: any): boolean
		local path = node.path
		local next = presentation.readAuthored(node.props, node.class, path)
		local prev = authored[path]
		if presentation.sameAuthored(prev, next) then
			return false
		end
		if (prev == nil) ~= (next == nil) then
			authoredN += if next ~= nil then 1 else -1
		end
		authored[path] = next
		return true
	end

	-- ===== `withAnimation`: arming, roots, and the one progress spring ========
	-- The verb is `presenter.withAnimation` (design §"Where it lives"); this is the
	-- half that has to be controller-scoped, because a record is per-path state
	-- that dies with its path.

	function animationClear(path: string, write: boolean)
		local rec = animationRecords[path]
		if rec == nil then
			return
		end
		animationRecords[path] = nil
		animationRecordN -= 1
		rec.set.paths[path] = nil
		if write then
			-- No paint-half recompose here, deliberately, and it was checked rather
			-- than assumed: the spring SNAPS to its target before `onSettle` runs
			-- (motion/motion.luau `sp:snap(sp:getTarget())`, and the clock's commit
			-- phase precedes its post phase), so `animationWrite` has already painted
			-- the record at p = 0 — which is the authored destination exactly. A push
			-- here reddened nothing when deliberately removed, and a line no check can
			-- fail is decoration.
			channel.setPresentationTransform(path, nil)
		end
	end

	-- ONE progress spring drives a whole call: 1 = at the old place, 0 = at the
	-- solved place, so every record's absolute offset is `(its delta) x p` for a
	-- single `p` — a uniform interpolation that provably cannot TEAR a subtree.
	-- `transitions.luau`'s ratified shape (its header, "one spring per transition").
	local function animationWrite(set: any)
		local p = set.spring:get()
		for path in set.paths do
			local rec = animationRecords[path]
			if rec ~= nil and rec.set == set then
				-- one `p` for position AND size, which is what makes a panel's growth
				-- and the displacement of everything below it arrive on the same frame
				-- ...and, since ADR-0026, for opacity/scale/rotation too, which is what
				-- makes a card that slides, grows and fades land on ONE frame.
				if rec.moves then
					channel.setPresentationTransform(
						path,
						{ x = rec.x * p, y = rec.y * p, w = rec.w * p, h = rec.h * p }
					)
				end
				if rec.paints then
					pushPresentationPaint(path)
				end
			end
		end
	end

	local function animationSettle(set: any)
		if set.done then
			return
		end
		set.done = true
		-- ONLY the paths it STILL owns: a later call may have re-based some of them
		-- onto its own spring, and clearing those would snap a live animation
		local owned: { string } = {}
		for path in set.paths do
			table.insert(owned, path)
		end
		for _, path in owned do
			animationClear(path, true)
		end
		if set.unobserve ~= nil then
			set.unobserve()
			set.unobserve = nil
		end
		set.spring:dispose()
		local at = table.find(animationSets, set)
		if at ~= nil then
			table.remove(animationSets, at)
		end
	end

	function installAnimationRecords(rects: any)
		local session = animationSession
		local baseline = animationBaseline
		if session == nil or baseline == nil then
			return
		end
		local set: any = nil
		-- the INTERRUPTION carry (design §Interruption). One spring serves the whole
		-- call, so the velocity that survives is the DOMINANT record's: painted speed
		-- is `rel * dp/dt`, so holding `relOld_max * vOld == relNew_max * vNew` keeps
		-- the biggest motion's speed continuous and puts a small kink on the rest.
		local carryMagOld, carryVelocity, carryMagNew = 0, 0, 0
		-- `relX`/`relY` are RELATIVE to the ancestors' composed delta (the offset half
		-- accumulates); `dw`/`dh` are the node's OWN absolute size delta, because the
		-- size half does not accumulate. See the walk below.
		-- `dOp`/`dSc`/`dRo` are the AUTHORED presentation deltas (ADR-0026 Decision 7):
		-- `old - new`, painted as `destination + delta x p` on the SAME spring as the
		-- four rect numbers. Per-node like the size half, never accumulated: a fade
		-- group's children are really inside its buffer and would fade twice.
		local function claim(
			path: string,
			relX: number,
			relY: number,
			dw: number,
			dh: number,
			dOp: number,
			dSc: number,
			dRo: number
		)
			if set == nil then
				-- `carriesVelocity = false` marks a CURVE-driven session (ADR-0033):
				-- a curve's speed is its shape, so there is no velocity to seed and
				-- the carry below must not try — `setVelocity` raises on a tween
				-- value, and raising here would abort an armed commit mid-install.
				-- Absent (an older session shape) means a spring, which carries.
				set = {
					spring = session.newSpring(),
					paths = {},
					done = false,
					carriesVelocity = session.carriesVelocity ~= false,
				}
				-- the write rides the VALUE, not the clock step, exactly as a
				-- transition's does, so an instantly-placed value lands the same way
				set.unobserve = core:observe(set.spring, function()
					animationWrite(set)
				end)
				set.spring:onSettle(function()
					animationSettle(set)
				end)
				table.insert(animationSets, set)
			end
			local prev = animationRecords[path]
			if prev ~= nil then
				-- INTERRUPTION (design §Interruption): carry the offset this path is
				-- painted at right now into the new record, so a path claimed by two
				-- calls re-targets instead of jumping, and hand it to the new spring
				local p = prev.set.spring:get()
				-- all four components are PIXELS on the same progress spring, so the
				-- dominant magnitude is the largest of the four, not the largest offset
				local mag = math.max(math.abs(prev.x), math.abs(prev.y), math.abs(prev.w), math.abs(prev.h))
				if mag > carryMagOld then
					carryMagOld = mag
					carryVelocity = prev.set.spring:getVelocity()
				end
				relX += prev.x * p
				relY += prev.y * p
				-- the size half re-bases on exactly the same rule: carry the delta this
				-- path is PAINTED at right now, so a panel interrupted half-grown
				-- continues from the height on screen instead of snapping to its start
				dw += prev.w * p
				dh += prev.h * p
				-- ...and the paint half re-bases identically: a panel interrupted
				-- half-faded continues from the alpha on screen. The CARRY MAGNITUDE
				-- above stays on the four PIXEL numbers on purpose — a `math.max` over
				-- a ratio, a factor, an angle and pixels is a number with no meaning —
				-- so a pure-paint record re-targets from rest, which is the same small
				-- kink the dominant-record rule already accepts.
				dOp += prev.o * p
				dSc += prev.s * p
				dRo += prev.r * p
				animationClear(path, false)
			end
			carryMagNew = math.max(carryMagNew, math.abs(relX), math.abs(relY), math.abs(dw), math.abs(dh))
			local moves = relX ~= 0 or relY ~= 0 or dw ~= 0 or dh ~= 0
			local paints = dOp ~= 0 or dSc ~= 0 or dRo ~= 0
			animationRecords[path] = {
				x = relX,
				y = relY,
				w = dw,
				h = dh,
				o = dOp,
				s = dSc,
				r = dRo,
				moves = moves,
				paints = paints,
				set = set,
			}
			animationRecordN += 1
			set.paths[path] = true
			-- SEED SYNCHRONOUSLY, before the first step (transitions.luau's seed at
			-- `writeEntry(entry)` before `setTarget`): `tick` runs on PreRender and
			-- `refresh` on Heartbeat, so a record written a frame late paints one frame
			-- at the destination and then jumps back.
			--
			-- A PURE-PAINT RECORD WRITES NO TRANSFORM AT ALL: a zero transform is not
			-- free (it counts into `presentationLive` and makes the adapter recompose
			-- the subtree's offsets) and a fade has no offset to declare.
			channel.setPresentationTransform(path, if moves then { x = relX, y = relY, w = dw, h = dh } else nil)
			if paints then
				pushPresentationPaint(path)
			end
		end
		-- TOP-DOWN, because a node cannot be classified before its ancestors.
		-- `inh` is the composed ABSOLUTE delta this path inherits from the records
		-- installed above it — never an ancestor's stored RELATIVE, and never a live
		-- record from an EARLIER call (which is not this diff's business).
		local function walk(node: any, inhX: number, inhY: number)
			local path = node.path
			-- PRECEDENCE (design §Composition), SCOPED TO THE NODE — RED-TEAM
			-- Milestone 1, blocker 1 (tests/animation_precedence.spec.luau).
			--
			-- There is one `lastTransform` slot per path and no contributor stack,
			-- so a path another writer already owns — a structural transition,
			-- keep-visible — must stay out of this diff: two writers alternating on
			-- one slot is the contention this rule exists to prevent.
			--
			-- THAT IS A STATEMENT ABOUT THE SLOT, AND A SLOT BELONGS TO ONE PATH.
			-- Taking the owned path's whole SUBTREE out of the diff protects
			-- nothing (a child has its own slot, uncontended) and costs everything
			-- when the owned path is the ROOT: every `UI.TextInput` declares a
			-- `keepVisibleOffset`, and `presenter.present` wires it eagerly, so
			-- `setPresentationOffset(0)` writes a zero transform onto the root at
			-- boot on any surface holding a text field. `withAnimation` on that
			-- surface then installed zero records and snapped, with no error and no
			-- diagnostic.
			--
			-- So the owned node is EXCLUDED and the walk CONTINUES with `inh`
			-- UNCHANGED. `inh` is the composed delta of records installed in THIS
			-- diff, and a foreign writer's shift is not one of them: both halves of
			-- the presentation channel accumulate every ancestor's transform
			-- independently (`presentationShift`, the adapter's compose), so the
			-- keep-visible shift is already added on top of whatever a descendant's
			-- own record paints. Passing it through unchanged is what makes the
			-- painted sum come out right; folding it into `inh` would subtract it
			-- from the descendant twice.
			local owned = lastTransform[path] ~= nil and animationRecords[path] == nil
			if not owned then
				local dx, dy, dw, dh = 0, 0, 0, 0
				-- LIVENESS IS NOT `lastRects[path] ~= nil`: `restoreParkedProps` carries
				-- `lastRects` across paths for a recycled instance, so a brand-new row
				-- would fly in from the position of whatever dead row it adopted.
				local live = baseline[path] == true
				if live then
					local last = lastRects[path]
					local entry = rects[path]
					if last ~= nil and entry ~= nil then
						dx = last.x - entry.rect.x
						dy = last.y - entry.rect.y
						-- THE SIZE DELTA IS ABSOLUTE, not relative, and that asymmetry is
						-- the whole design (docs/plans/with-animation-size.md). A position
						-- offset accumulates down the subtree because the instance tree is
						-- FLAT — a container's move carries nothing inside it, so every
						-- descendant re-adds its ancestors' offsets. A size change carries
						-- nothing inside it EITHER, and there the same fact means the
						-- opposite: a child's rect is absolute, so the parent's painted
						-- growth must not reach it. Hence no `inh` for w/h, and no
						-- compensating record for a child that did not resize.
						dw = last.w - entry.rect.w
						dh = last.h - entry.rect.h
					end
				end
				local relX, relY = dx - inhX, dy - inhY
				-- THE AUTHORED PAINT DELTAS (ADR-0026), parked by the commit phase —
				-- exactly the role `lastRects` plays for the rect numbers, and for the
				-- same reason: `authored[path]` already holds the destination here.
				local dOp, dSc, dRo = 0, 0, 0
				local pd = if live then animationPaintDelta[path] else nil
				if pd ~= nil then
					dOp, dSc, dRo = pd.o, pd.s, pd.r
				end
				-- a path already carrying a record must be re-based even when its relative
				-- delta is zero this time, or it keeps flying to a place it no longer sits
				local claimed = relX ~= 0
					or relY ~= 0
					or dw ~= 0
					or dh ~= 0
					or dOp ~= 0
					or dSc ~= 0
					or dRo ~= 0
					or animationRecords[path] ~= nil
				if live and claimed and handles[path] ~= nil then
					claim(path, relX, relY, dw, dh, dOp, dSc, dRo)
					-- what the children inherit is this path's composed ABSOLUTE POSITION
					-- delta. Size is deliberately absent: see the comment above.
					inhX, inhY = dx, dy
				end
			end
			for _, child in node.children do
				walk(child, inhX, inhY)
			end
		end
		walk(root.node, 0, 0)
		-- the parked deltas belong to THIS armed commit only: a path the walk declined
		-- (not live, no handle) must not be flown by the next call
		animationPaintDelta = {}
		if set ~= nil then
			set.spring:setTarget(0)
			-- after the aim, so the seed is what integrates from here
			if set.carriesVelocity and carryMagOld > 0 and carryMagNew > 0 then
				set.spring:setVelocity(carryVelocity * (carryMagOld / carryMagNew))
			end
		end
	end

	-- Armed by `presenter.withAnimation` for exactly one commit, which it forces
	-- itself after draining the queue UNARMED — so the frame-coalesced refresh,
	-- virtual-list windowing, replication reverts and async landings never install
	-- records. `session.newSpring()` is called lazily, so a call that moves nothing
	-- builds no spring.
	function channel.armAnimation(session: any)
		animationSession = session
		-- the paths alive at the PREVIOUS (unarmed) commit — see `live` above for
		-- why this cannot be `lastRects`
		local alive: { [string]: boolean } = {}
		for path in handles do
			alive[path] = true
		end
		animationBaseline = alive
	end

	function channel.disarmAnimation()
		animationSession = nil
		animationBaseline = nil
	end

	-- DIAGNOSTIC (design §Proof), not a feature: how many paths currently carry a
	-- `withAnimation` record. The suite reads it to prove roots-only recording.
	function channel.animationRecordCount(): number
		return animationRecordN
	end

	-- ===== WHAT THE RENDERER REACHES IN =====================================
	-- Each of these was an inline block in `renderer.luau` that touched this
	-- module's state directly. They are methods rather than exported tables for
	-- the reason the state is private at all: `presentationLive`, `authoredN` and
	-- `animationRecordN` are COUNTERS kept in step with their maps, and a caller
	-- that could clear a map without them would corrupt the off-path gates.

	channel.presentationShift = presentationShift
	channel.readAuthoredPresentation = readAuthoredPresentation
	channel.installAnimationRecords = installAnimationRecords

	-- ...and the authored triple, now that a handle exists. Gated, so a node
	-- declaring none of the three pays one hash lookup at mount and no more.
	function channel.paintAuthored(path: string)
		if authoredN > 0 and authored[path] ~= nil then
			pushPresentationPaint(path)
		end
	end

	-- is an ARMED commit in flight? Two callers: the solve, which must install
	-- records before `lastRects` is overwritten, and `refresh`, which forces a
	-- solve for a commit that only dirtied paint (ADR-0026 Decision 7).
	function channel.armed(): boolean
		return animationSession ~= nil
	end

	-- THE AUTHORED TRIPLE, re-read from the live tree (ADR-0026) for the paths a
	-- commit dirtied. Called after the structural sync and before the solve —
	-- because the read must see this frame's value, and because on an ARMED commit
	-- the OLD value has to be captured before it is overwritten: that difference is
	-- what `withAnimation` flies.
	function channel.reactAuthored(paths: { string })
		local seen: { [string]: boolean } = {}
		for _, path in paths do
			if not seen[path] then
				seen[path] = true
				local node = findNode(path)
				if node ~= nil then
					local before = authored[path]
					if readAuthoredPresentation(node) and handles[path] ~= nil then
						if animationSession ~= nil then
							local now = authored[path]
							local function was(key: string, identity: number): number
								return (before ~= nil and before[key]) or identity
							end
							local function isNow(key: string, identity: number): number
								return (now ~= nil and now[key]) or identity
							end
							animationPaintDelta[path] = {
								o = was("opacity", 1) - isNow("opacity", 1),
								s = was("scale", 1) - isNow("scale", 1),
								r = was("rotation", 0) - isNow("rotation", 0),
							}
						end
						pushPresentationPaint(path)
					end
				end
			end
		end
	end

	-- EVERY per-path presentation cache, forgotten together, called from the
	-- renderer's retire sweep. It must be all of them at once: a re-created node
	-- starts at rest and a cached value would suppress the write that puts it
	-- there (the same verdict-inheritance defect the visible and hit-rect caches
	-- were bitten by — verifier finding V10), a stale composed memo would answer
	-- for a path a recycled instance adopts, and a leaked `authored` entry would
	-- make an idle surface pay forever (ADR-0026).
	function channel.forgetPath(path: string)
		if lastTransform[path] ~= nil then
			lastTransform[path] = nil
			presentationLive -= 1
		end
		lastTransparency[path] = nil
		lastComposedTransform[path] = nil
		lastComposedAlpha[path] = nil
		animationPaintDelta[path] = nil
		if authored[path] ~= nil then
			authored[path] = nil
			authoredN -= 1
		end
		-- ...and the `withAnimation` record for this path, HERE rather than by
		-- blanket-dropping every record in structuralSync: structural syncs are
		-- frequent (virtual-list windowing, `When` branches) and a blanket drop
		-- would snap unrelated in-flight animations. The write is skipped — the
		-- handle is already gone (V10's per-path clear, at the renderer's call site).
		if animationRecords[path] ~= nil then
			animationClear(path, false)
		end
	end

	-- mounted identity may have changed under any path (a When branch, a ForEach
	-- row, a re-created ViewThatFits candidate), so the node memo is dropped
	-- wholesale rather than patched per path. The renderer calls this from
	-- `structuralSync`, which is the only place identity can move.
	function channel.dropNodeCache()
		presentationNodes = {}
	end

	-- what the cross-surface overlap alarm reads (ADR-0028): the COMPOSED alpha
	-- last written for a path, which is where an authored `opacity = 0` shows up
	-- as `T = 1`. nil means nothing has been written.
	function channel.composedAlpha(path: string): number?
		return lastComposedAlpha[path]
	end

	-- a `withAnimation` spring is built on the presenter's clock, which OUTLIVES
	-- the surface, so the springs die with the surface that started them
	function channel.settleAll()
		for i = #animationSets, 1, -1 do
			animationSettle(animationSets[i])
		end
	end

	return channel
end

return presentation_channel
