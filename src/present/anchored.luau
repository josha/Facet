--!strict
--[[ ANCHORED SURFACES — a presented surface positioned against a SOURCE VIEW'S
	screen rect rather than a parent corner (navigation-and-menus brief §2 D1).
	The substrate for the Menu (D2), `help` (D3a) and the Callout (D3b).

	`presenter.presentAnchored(panel, opts)` takes a PANEL — any blueprint, not a
	`Screen` — and this module supplies the surface around it: the Screen root, the
	full-viewport `Anchor` layer, the window-space offsets the placement solver
	computes, and the optional arrow tail. Everything else it does NOT supply, on
	purpose:

	  * the STACK, the focus scope, the input context, the layering band and the
	    dismissal outcome are the presenter's, reached by delegating straight to
	    `present`/`presentModal`. Every `PresentOpts` key therefore works here
	    unchanged — `scrim`, `cancelPolicy`, `outsideTapCancel`, `initialFocus`,
	    `transition`, `navigationGroups`, all of it;
	  * the TAP-AWAY CATCHER is `presenter.syncPopupCatcher`'s, reached the same
	    way every other transient surface reaches it (a contribution's
	    `outsideDismiss`, whose `consume = false` mode is what a non-blocking
	    callout needs);
	  * the PLACEMENT ARITHMETIC is `src/layout/anchor_placement.luau`'s, which is
	    pure and shared with the two hand-rolled precedents this seam unified.

	FOLLOWING A MOVING SOURCE COSTS NO WATCHER. `sync()` is called from the
	presenter's `refreshBody` (the cadence a real scroll already drives — the same
	one `row_actions`' menu re-aims on, "asking nothing new of any caller") and
	from `tickBody` (the cadence the disclosure plate's clamp already rides, which
	is what catches a text measure that lands after mount). Both are existing
	frame work; a surface that has not moved costs two rect reads and zero writes.

	WHY THE TAIL IS A ROTATED BOX AND NOT A `UI.Path`. `UI.Path` materializes as a
	Roblox `Path2D`, and `Path2D` STROKES ONLY — there is no fill, and
	`path_shapes` exports `arc`/`ring`/`needle`, no triangle. A stroked outline
	cannot read as the solid, panel-coloured wedge the reference plate has. A
	45°-rotated square painted BEHIND the panel does, exactly, and for free: the
	half that overlaps the panel is covered by it (the renderer walks children in
	document order assigning increasing z, so the `Tail` declared first paints
	below the `Surface` declared second), and the half that protrudes is the
	triangle. `rotation` is a shipped, paint-only prop on every rendered class
	(ADR-0026) — it moves no layout, no hit geometry and no focus, which is
	exactly right for a decoration. The alternative, an `UI.Image` nine-slice,
	would need an uploaded asset per theme fill; this needs none.

	THE TAIL EATS ITS OWN GAP. A square of side `s` rotated 45° protrudes
	`s * sqrt(2) / 2` past its centre, so a tailed surface stands `gap +
	protrusion` off its source and the arrow's tip lands exactly `gap` short of
	it. Without that the wedge would be drawn over the very control it points at.
]]

local anchorPlacement = require("../layout/anchor_placement")
local blueprintLib = require("../blueprint")
local specGuard = require("../spec_guard")
local themeSnapshot = require("../themes/snapshot")

local anchored = {}

-- Node ids inside the synthesized surface. Public in the sense that a test or a
-- bug report names them: `/<id>/Layer/Surface` is the panel, `/<id>/Layer/Tail`
-- the wedge.
local LAYER_ID = "Layer"
local SURFACE_ID = "Surface"
local TAIL_ID = "Tail"

local DUMP_SCHEMA = "luauui-anchored-dump/1"

-- THEME METRICS (ADR-0019 §2), never bare pixels. The gap is the small spacing
-- step; the tail is one medium step square, which is 16px under Studio Neutral
-- and therefore an 11.3px protrusion — the size Apple's own popover arrow is.
-- The corner keep-out is the panel radius, so a tail can never grow out of a
-- rounded corner however the theme rounds them.
local DEFAULT_GAP = "s"
local DEFAULT_TAIL_SIZE = "m"
local TAIL_CORNER_METRIC = "radii.panel"

local ROOT_TWO = math.sqrt(2)

local ANCHOR_KEYS = specGuard.keySet({ "align", "edge", "gap", "overflow", "source", "tail" })
local SOURCE_KEYS = specGuard.keySet({ "path", "rect" })
local TAIL_KEYS = specGuard.keySet({ "cornerInset", "size", "surface" })

export type Source = { path: string?, rect: { x: number, y: number, w: number, h: number }? }
export type Tail = { size: (string | number)?, surface: string?, cornerInset: (string | number)? }
export type Anchor = {
	source: Source,
	edge: string?,
	align: string?,
	gap: (string | number)?,
	overflow: string?,
	tail: (boolean | Tail)?,
}

--[[ ctx — the same by-reference shape `catchers.new` takes, and for the same
	reason: everything here reads the presenter's live state and nothing here owns
	any of it.
	  core, env        the injected reactive/fact seam
	  stack            the presented handles, read live (a dismissed surface stops
	                   being anchored because it stops being in the stack)
	  presenter        so `present`/`presentModal`/`dismiss` are the ONLY way a
	                   surface is created — this module never mounts a surface
	  metricsNow()     the LIVE metric authority, read per use
	  safeBox()        the presenter's own safe box (viewport less the per-edge
	                   MAX of the two inset facts). Reused, never re-derived.
	  handleByPath(p)  which presented surface owns a path, so a source path is
	                   resolved through ITS controller's `screenRectOf`
	  presentOptsKeys  the presenter's own closed key set, so the anchored opts
	                   are that set plus this module's three and can never drift
]]
function anchored.new(ctx: any)
	local core = ctx.core
	local stack = ctx.stack
	local presenter = ctx.presenter
	local metricsNow = ctx.metricsNow
	local safeBox = ctx.safeBox
	local handleByPath = ctx.handleByPath

	local optsKeys: { [string]: boolean } = {}
	for key in ctx.presentOptsKeys do
		optsKeys[key] = true
	end
	optsKeys.anchor = true
	optsKeys.id = true
	optsKeys.modal = true
	table.freeze(optsKeys)

	-- live anchored surfaces, creation-ordered. Small by construction: these are
	-- transient surfaces, and the round's own rule is at most one callout.
	local live: { any } = {}

	local function resolveMetric(value: any, fallback: number): number
		if value == nil then
			return fallback
		end
		return themeSnapshot.resolveNumber(metricsNow(), value) or fallback
	end

	-- the source's rect in WINDOW space. A literal rect answers for itself; a path
	-- answers through the controller of whichever surface owns it, and
	-- `screenRectOf` is the one that corrects for accumulated nested-scroll offset
	-- AND for a live presentation shift (`rectOf` does neither).
	local function sourceRectOf(record: any): any
		local source = record.anchor.source
		if source.rect ~= nil then
			return source.rect
		end
		local path = source.path :: string
		local owner = handleByPath(path)
		if owner == nil then
			return nil
		end
		local ctrl = owner.controller
		return if ctrl.screenRectOf ~= nil then ctrl.screenRectOf(path) else ctrl.rectOf(path)
	end

	--[[ PLACE ONE SURFACE. Two passes by necessity, exactly as the disclosure
		plate's clamp is: the surface's SIZE is a solve output, so it is mounted
		first and moved second — through the anchor offsets, which are `dirty =
		arrange` and therefore a re-solve, never a remount. The signals no-op on an
		unchanged value, so a settled surface costs reads and no writes. ]]
	local function place(record: any)
		local sourceRect = sourceRectOf(record)
		local surfaceRect = record.handle.controller.rectOf(record.surfacePath)
		if type(sourceRect) ~= "table" or type(surfaceRect) ~= "table" then
			-- a source that is not mounted (yet, or any more) leaves the surface
			-- exactly where it is rather than throwing or teleporting it to 0,0 —
			-- the same degrade `computeMenuAnchor` chose for the same case
			return
		end
		local anchor = record.anchor
		local gapPx = resolveMetric(anchor.gap, resolveMetric(DEFAULT_GAP, 0))
		-- RESOLVED PER PLACEMENT, from the LIVE metric authority — never cached at
		-- present time. The tail's box declares the same metric NAME, so a theme
		-- commit retunes the wedge and the distance it stands off the source in the
		-- same frame it retunes everything else (ADR-0019 §2).
		local tailPx = if record.wantsTail then resolveMetric(record.tailMetric, 0) else 0
		-- a 45° square protrudes half its DIAGONAL past its centre
		local protrusion = tailPx * ROOT_TWO / 2
		local placement = anchorPlacement.solve({
			source = sourceRect,
			size = { w = surfaceRect.w, h = surfaceRect.h },
			safe = safeBox(),
			edge = anchor.edge,
			align = anchor.align,
			gap = gapPx + protrusion,
			tail = tailPx * ROOT_TWO,
			-- the CORNER RADIUS only: the solver adds half the tail's own width to
			-- this itself, so adding it here too would keep the wedge a full tail
			-- width away from a corner it only has to clear by half of one
			tailInset = resolveMetric(record.tailInsetMetric, 0),
			overflow = anchor.overflow,
		})
		record.placement = placement
		record.placed = true

		local moved = record.ox:get() ~= placement.x or record.oy:get() ~= placement.y
		record.ox:set(placement.x)
		record.oy:set(placement.y)
		if tailPx > 0 then
			-- the wedge's layout box is `tailPx` square and `rotation` turns it about
			-- its own centre, so the offsets place that centre on the shared border
			local tx = (placement.tailX or placement.x) - tailPx / 2
			local ty = (placement.tailY or placement.y) - tailPx / 2
			moved = moved or record.tx:get() ~= tx or record.ty:get() ~= ty
			record.tx:set(tx)
			record.ty:set(ty)
			local hide = placement.tailSuppressed
			moved = moved or record.tailHidden:get() ~= hide
			record.tailHidden:set(hide)
		end
		if moved then
			record.handle.controller.refresh()
		end
	end

	local function normalizeAnchor(raw: any): any
		if type(raw) ~= "table" then
			error(
				"LuauUI presenter.presentAnchored: `anchor` is required — { source = { path = … } | { rect = … }, "
					.. "edge?, align?, gap?, tail?, overflow? }. An anchored surface with no source is just present().",
				0
			)
		end
		specGuard.assertKnownKeys("presenter.presentAnchored", raw, ANCHOR_KEYS, "opts.anchor")
		local source = raw.source
		if type(source) ~= "table" then
			error('LuauUI presenter.presentAnchored: `anchor.source` must be { path = "…" } or { rect = … }.', 0)
		end
		specGuard.assertKnownKeys("presenter.presentAnchored", source, SOURCE_KEYS, "opts.anchor.source")
		local hasPath = type(source.path) == "string"
		local hasRect = type(source.rect) == "table"
		if hasPath == hasRect then
			error(
				"LuauUI presenter.presentAnchored: `anchor.source` names EXACTLY one of `path` (a mounted node, "
					.. "followed as it moves) or `rect` (a fixed window-space box).",
				0
			)
		end
		anchorPlacement.assertEdge(raw.edge, "presenter.presentAnchored")
		anchorPlacement.assertAlign(raw.align, "presenter.presentAnchored")
		anchorPlacement.assertOverflow(raw.overflow, "presenter.presentAnchored")
		local tail = raw.tail
		if type(tail) == "table" then
			specGuard.assertKnownKeys("presenter.presentAnchored", tail, TAIL_KEYS, "opts.anchor.tail")
		elseif tail ~= nil and type(tail) ~= "boolean" then
			error(
				`LuauUI presenter.presentAnchored: \`anchor.tail\` is true/false or a table `
					.. `\{ size?, surface?, cornerInset? } (got {typeof(tail)}).`,
				0
			)
		end
		return {
			source = { path = source.path, rect = source.rect },
			edge = raw.edge or "bottom",
			align = raw.align or "center",
			gap = raw.gap,
			overflow = raw.overflow,
			tail = tail,
		}
	end

	local function present(panel: any, opts: any): any
		specGuard.assertKnownKeys("presenter.presentAnchored", opts, optsKeys, "opts")
		if type(panel) ~= "table" then
			error(
				"LuauUI presenter.presentAnchored: the first argument is the PANEL blueprint — any node, not a "
					.. "`UI.Screen`. The surface around it is synthesized here.",
				0
			)
		end
		local anchor = normalizeAnchor(if opts ~= nil then opts.anchor else nil)
		local id = (opts and opts.id) or "Anchored"
		--[[ WINDOW SPACE OR NOTHING. The offsets below are the same coordinates
			`screenRectOf` and `safeBox` answer in, which is what gives the whole
			placement one frame of reference. A root policy that insets the root
			would silently shift every one of them by the safe-area inset, so an
			explicit different policy is refused rather than quietly re-based. ]]
		local rootPolicy = if opts ~= nil then opts.rootPolicy else nil
		if rootPolicy ~= nil and rootPolicy ~= "edgeToEdge" then
			error(
				`LuauUI presenter.presentAnchored: rootPolicy must be "edgeToEdge" (got '{tostring(rootPolicy)}'). `
					.. "An anchored surface is placed in WINDOW space, the coordinates screenRectOf answers in; "
					.. "an inset root would re-base every offset by the safe-area inset. The safe area is honoured "
					.. "by the placement itself.",
				0
			)
		end

		local scope = core:scope(`present-anchored-{id}`)
		local ox = scope:own(core:signal(0))
		local oy = scope:own(core:signal(0))
		local tx = scope:own(core:signal(0))
		local ty = scope:own(core:signal(0))
		local tailHidden = scope:own(core:signal(true))

		local tailSpec: any = if type(anchor.tail) == "table" then anchor.tail else {}
		local wantsTail = anchor.tail ~= nil and anchor.tail ~= false
		-- the METRIC NAMES, not the numbers they resolve to today: the box below
		-- declares them straight into its dimension (a `px` field takes a metric
		-- name, `snapshot.resolveDim`), and `place` resolves the same names off the
		-- live authority. One theme commit moves both.
		local tailMetric = tailSpec.size or DEFAULT_TAIL_SIZE
		local tailInsetMetric = tailSpec.cornerInset or TAIL_CORNER_METRIC

		local children: { any } = {}
		if wantsTail then
			-- DECLARED FIRST, SO IT PAINTS BEHIND (renderer `syncZOrder`: document
			-- order becomes increasing z). The half of the wedge that overlaps the
			-- panel is covered by it; the half that protrudes is the arrow.
			table.insert(
				children,
				blueprintLib.Box({
					id = TAIL_ID,
					anchor = "topLeft",
					offsetX = tx,
					offsetY = ty,
					width = { type = "fixed", px = tailMetric },
					height = { type = "fixed", px = tailMetric },
					rotation = 45,
					-- the SAME surface role the panel wears, so the wedge is the
					-- panel's own fill continuing past its edge rather than a second
					-- colour that a theme swap could desynchronize
					surface = tailSpec.surface or "raised",
					hidden = tailHidden,
				})
			)
		end
		table.insert(
			children,
			blueprintLib.VStack({
				id = SURFACE_ID,
				anchor = "topLeft",
				offsetX = ox,
				offsetY = oy,
				width = { type = "hug" },
				height = { type = "hug" },
				children = { panel },
			})
		)

		local screen = blueprintLib.Screen({
			id = id,
			children = {
				blueprintLib.Anchor({
					id = LAYER_ID,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = children,
				}),
			},
		})

		local passthrough: any = {}
		if opts ~= nil then
			for key, value in opts do
				if key ~= "anchor" and key ~= "id" and key ~= "modal" then
					passthrough[key] = value
				end
			end
		end
		passthrough.rootPolicy = "edgeToEdge"

		local handle = if opts ~= nil and opts.modal == true
			then presenter.presentModal(screen, passthrough)
			else presenter.present(screen, passthrough)

		local record = {
			id = id,
			handle = handle,
			scope = scope,
			anchor = anchor,
			surfacePath = `/{id}/{LAYER_ID}/{SURFACE_ID}`,
			tailPath = `/{id}/{LAYER_ID}/{TAIL_ID}`,
			wantsTail = wantsTail,
			tailMetric = tailMetric,
			tailInsetMetric = tailInsetMetric,
			ox = ox,
			oy = oy,
			tx = tx,
			ty = ty,
			tailHidden = tailHidden,
			placed = false,
			placement = nil,
		}
		table.insert(live, record)
		place(record)
		return handle
	end

	--[[ A SURFACE STOPS BEING ANCHORED THE MOMENT IT LEAVES THE STACK, not a frame
		later. `presenter.dismiss` removes the handle from `stack` as its first act
		(a surface on its way out must never still take input) and calls this
		immediately after, so the record and the signals it owns die on the same
		call — never a dump reporting a surface that is already gone, and never a
		scope waiting on the next frame to be disposed. ]]
	local function prune()
		for i = #live, 1, -1 do
			local record = live[i]
			if table.find(stack, record.handle) == nil then
				table.remove(live, i)
				record.scope:dispose()
			end
		end
	end

	--[[ ONE PASS OVER THE LIVE SURFACES, on cadences that already exist. Called
		from `refreshBody` (after every handle has re-rendered and re-fed its
		geometry, so the source rect read here is this frame's) and from `tickBody`
		(so a size that lands asynchronously — a late text measure — re-places the
		surface on the next frame rather than never). ]]
	local function sync()
		prune()
		for _, record in live do
			place(record)
		end
	end

	local function dump(): any
		local surfaces: { any } = {}
		local lines: { string } = {}
		for _, record in live do
			local p = record.placement
			local anchor = record.anchor
			local sourceText = if anchor.source.path ~= nil
				then anchor.source.path
				else `rect({anchor.source.rect.x},{anchor.source.rect.y})`
			local entry = {
				id = record.id,
				source = sourceText,
				requestedEdge = anchor.edge,
				align = anchor.align,
				placed = record.placed,
				edge = if p ~= nil then p.edge else nil,
				flipped = if p ~= nil then p.flipped else nil,
				shift = if p ~= nil then p.shift else nil,
				fits = if p ~= nil then p.fits else nil,
				x = if p ~= nil then p.x else nil,
				y = if p ~= nil then p.y else nil,
				w = if p ~= nil then p.w else nil,
				h = if p ~= nil then p.h else nil,
				tail = record.wantsTail,
				tailSuppressed = if p ~= nil then p.tailSuppressed else nil,
				tailX = if p ~= nil then p.tailX else nil,
				tailY = if p ~= nil then p.tailY else nil,
			}
			table.insert(surfaces, entry)
			local tailText = if not entry.tail
				then "no tail"
				elseif entry.tailSuppressed == true then "tail SUPPRESSED (shifted off the source)"
				else `tail at {entry.tailX},{entry.tailY}`
			table.insert(
				lines,
				`{record.id}: anchored {anchor.edge}/{anchor.align} of {sourceText} -> `
					.. `{tostring(entry.edge)}{if entry.flipped == true then " (FLIPPED)" else ""} `
					.. `at {tostring(entry.x)},{tostring(entry.y)} shift {tostring(entry.shift)}, {tailText}`
			)
		end
		return {
			schema = DUMP_SCHEMA,
			count = #live,
			surfaces = surfaces,
			text = if #lines == 0 then "no anchored surface" else table.concat(lines, "\n"),
		}
	end

	return {
		present = present,
		prune = prune,
		sync = sync,
		dump = dump,
	}
end

return anchored
