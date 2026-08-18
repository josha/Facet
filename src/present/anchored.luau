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

	AND THE WEDGE MUST BE SQUARE-CORNERED, WHICH IT WAS NOT (director, 2026-08-17:
	the stem read as *"a second shape below the main box"*). `surface = "raised"`
	brings the panel's phantom `::UICorner` with it — `radii.panel` is 12 under
	Studio Neutral against a `space.m` = 16px box, and the engine CLAMPS a corner
	radius to half the shorter side. 12 > 8, so the "wedge" was a CIRCLE, and what
	protruded past the panel was a semicircular bump wearing a hairline arc. The
	authored `corners = 0` below is what makes it a triangle; an instance property
	beats a StyleRule, so it overrides the phantom rule without touching the sheet.

	ONE SURFACE ROLE, NEVER A RECONSTRUCTED COLOUR (director, 2026-08-17: *"the
	triangle shouldn't have its own fill colour distinct from the tooltip… it
	should all be one colour"*).

	The wedge names `surface = "raised"` — the SAME sheet rule the panel names —
	so its fill is the panel's fill BY CONSTRUCTION rather than by agreement, and
	its two PROTRUDING edges carry the theme's hairline through the same phantom
	`::UIStroke` the panel's own border comes from. One vocabulary, correct under
	every package, no colour arithmetic anywhere in this file.

	AND THE PANEL'S BORDER MUST NOT CROSS THE ARROW'S BASE (director, 2026-08-17,
	from a zoomed device capture: *"can we eliminate the line at the bottom of the
	triangle?"*). It is the panel's own hairline, drawn straight through the join,
	and it is what keeps a correct wedge reading as a separate shape. `TailSeam` is
	the answer: a thin square unstroked band in the panel's fill, declared LAST so
	it paints OVER that border, exactly as wide as the wedge's base and centred on
	the shared edge.

	THE BAND'S FILL IS A SECOND AUTHORITY, AND IT IS GUARDED RATHER THAN AVOIDED.
	`surface = "base"` is the one native surface carrying neither a phantom corner
	nor a phantom stroke — which is exactly what a cover band needs — but its fill
	is `$Surface`, so the panel's colour has to be re-declared through
	`tint = { role = "surfaceStrong" }`. That reconstruction resolves through
	`sheet_model.paletteColor(paletteTheme(), …)` while `.facet-surface-raised`
	resolves `$SurfaceStrong` through the sheet's own emitted rule. The two agree,
	and `tests/anchored_surface.spec.luau` PINS them equal across every shipped
	package, because nothing else can: a live property read reports the UNSTYLED
	value (both plate and wedge read rgb(163,162,165) while painting rgb(28,31,40)
	— `GetStyled` is the only instrument that sees sheet paint), so a package that
	moved one authority and not the other would put a mismatched bar on the plate
	and every headless assertion in this repo would stay green.

	THE HONEST ALTERNATIVE, if that guard ever becomes a burden: give the panel and
	the wedge ONE stroked silhouette, so there is no border to cross and no colour
	to reconstruct. That needs a borderless panel surface the callers can name, and
	is a bigger change than this one buys.

	THE TAIL EATS ITS OWN GAP. A square of side `s` rotated 45° protrudes
	`s * sqrt(2) / 2` past its centre, so a tailed surface stands `gap +
	protrusion` off its source and the arrow's tip lands exactly `gap` short of
	it. Without that the wedge would be drawn over the very control it points at.
]]

local anchorPlacement = require("../layout/anchor_placement")
local blueprintLib = require("../blueprint")
local chrome_slots = require("../tokens/chrome_slots")
local mountLib = require("../mount")
local rendererLib = require("../render/renderer")
local specGuard = require("../spec_guard")
local themeSnapshot = require("../themes/snapshot")

local anchored = {}

-- Node ids inside the synthesized surface. Public in the sense that a test or a
-- bug report names them: `/<id>/Layer/Surface` is the panel, `/<id>/Layer/Tail`
-- the wedge.
local LAYER_ID = "Layer"
local SURFACE_ID = "Surface"
local TAIL_ID = "Tail"
-- the band that carries the panel's fill ACROSS the wedge's base (header)
local TAIL_SEAM_ID = "TailSeam"

local DUMP_SCHEMA = "facet-anchored-dump/1"

-- THEME METRICS (ADR-0019 §2), never bare pixels. The gap is the small spacing
-- step; the tail is one medium step square, which is 16px under Studio Neutral
-- and therefore an 11.3px protrusion — the size Apple's own popover arrow is.
-- The corner keep-out is the panel radius, so a tail can never grow out of a
-- rounded corner however the theme rounds them.
local DEFAULT_GAP = "s"
local DEFAULT_TAIL_SIZE = "m"
local TAIL_CORNER_METRIC = "radii.panel"
-- the seam band's thickness, read off the theme's own border vocabulary: a
-- package that thickens its hairlines needs a wider band to cover one.
-- `ApplyStrokeMode = Border` puts the panel's stroke on the OUTSIDE of its rect,
-- so the band STRADDLES the edge — twice the thickness, plus one pixel so a
-- fractional layout position cannot leave a lit sliver.
local SEAM_METRIC = "strokes.hairline"
local SEAM_OVERDRAW = 1

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
	local env = ctx.env
	local adapter = ctx.adapter
	local stack = ctx.stack
	local presenter = ctx.presenter
	local metricsNow = ctx.metricsNow
	local safeBox = ctx.safeBox
	local handleByPath = ctx.handleByPath
	local baseDisplayOrder = ctx.baseDisplayOrder

	local optsKeys: { [string]: boolean } = {}
	for key in ctx.presentOptsKeys do
		optsKeys[key] = true
	end
	optsKeys.anchor = true
	optsKeys.chrome = true
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
			local tailCentreX = placement.tailX or placement.x
			local tailCentreY = placement.tailY or placement.y
			local tx = tailCentreX - tailPx / 2
			local ty = tailCentreY - tailPx / 2
			moved = moved or record.tx:get() ~= tx or record.ty:get() ~= ty
			record.tx:set(tx)
			record.ty:set(ty)

			--[[ THE SEAM BAND (header). Its LENGTH is the wedge's base — a square of
				side `s` rotated 45 degrees presents a diagonal of `s * sqrt(2)` to the
				edge it straddles — and its THICKNESS straddles that edge. Which axis is
				which follows the RESOLVED edge, so a safe-area flip re-orients it in the
				same pass that moves the wedge. ]]
			local base = tailPx * ROOT_TWO
			local band = resolveMetric(SEAM_METRIC, 1) * 2 + SEAM_OVERDRAW
			local vertical = placement.edge == "top" or placement.edge == "bottom"
			local seamW = if vertical then base else band
			local seamH = if vertical then band else base
			local sx = tailCentreX - seamW / 2
			local sy = tailCentreY - seamH / 2
			-- COMPARED BY VALUE, never by table identity: a fresh `{}` every frame
			-- would redirty the band's measure on a settled surface
			moved = moved
				or record.sx:get() ~= sx
				or record.sy:get() ~= sy
				or record.sw:get().px ~= seamW
				or record.sh:get().px ~= seamH
			record.sx:set(sx)
			record.sy:set(sy)
			if record.sw:get().px ~= seamW then
				record.sw:set({ type = "fixed", px = seamW })
			end
			if record.sh:get().px ~= seamH then
				record.sh:set({ type = "fixed", px = seamH })
			end

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
				"Facet presenter.presentAnchored: `anchor` is required — { source = { path = … } | { rect = … }, "
					.. "edge?, align?, gap?, tail?, overflow? }. An anchored surface with no source is just present().",
				0
			)
		end
		specGuard.assertKnownKeys("presenter.presentAnchored", raw, ANCHOR_KEYS, "opts.anchor")
		local source = raw.source
		if type(source) ~= "table" then
			error('Facet presenter.presentAnchored: `anchor.source` must be { path = "…" } or { rect = … }.', 0)
		end
		specGuard.assertKnownKeys("presenter.presentAnchored", source, SOURCE_KEYS, "opts.anchor.source")
		local hasPath = type(source.path) == "string"
		local hasRect = type(source.rect) == "table"
		if hasPath == hasRect then
			error(
				"Facet presenter.presentAnchored: `anchor.source` names EXACTLY one of `path` (a mounted node, "
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
				`Facet presenter.presentAnchored: \`anchor.tail\` is true/false or a table `
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
				"Facet presenter.presentAnchored: the first argument is the PANEL blueprint — any node, not a "
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
				`Facet presenter.presentAnchored: rootPolicy must be "edgeToEdge" (got '{tostring(rootPolicy)}'). `
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
		-- the seam band's window-space box, solved per placement (see `place`). The
		-- two DIMENSIONS are whole reactive dims rather than reactive numbers: a `px`
		-- field inside a dim is read ONCE at construction, so publishing a number
		-- there sizes the band at mount and never again (measured: 0x0 forever).
		local sx = scope:own(core:signal(0))
		local sy = scope:own(core:signal(0))
		local sw = scope:own(core:signal({ type = "fixed", px = 0 }))
		local sh = scope:own(core:signal({ type = "fixed", px = 0 }))
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
			--[[ A ROTATED NODE TAKES THE PANEL'S FILL AND REFUSES ITS FRAME (device
				review 2026-08-16, F5). Director, under Fantasy Ornate: the tail painted
				as *"a long diagonal slab with the package's gold border running down
				both of its long edges"* — a rotated nine-slice, not a wedge.

				THE RULE THIS ENCODES, and it is general rather than a patch for one
				package: A ROTATED NODE MUST NOT WEAR A SKIN WHOSE DECORATION IS
				ORIENTATION-DEPENDENT. A nine-slice frame, a directional gradient and
				corner ornaments are all wrong at 45°, and every image-driven package
				ships at least one of them. `surface = "raised"` was chosen so a theme
				swap moved the wedge with the panel, which is right — but `raised`
				classifies into the `panel` chrome slot, and `panel` under an ornate
				package is six layers including a frame and four corner ornaments, not
				a fill. The flat default materializes no decoration at all, which is
				exactly why this shipped.

				SO THE SURFACE STAYS AND THE SLOT GOES. `NO_SLOT` is the shipped way to
				say "this is not a decoration surface" (`chrome_slots.NO_SLOT`, the same
				declaration the synthesized catchers carry after the twin defect in
				`popup_catcher_paint.spec` — a node that never said what it was, dressed
				by a package that had no way to know better). What remains is the NATIVE
				sheet paint of `.facet-surface-raised`, which every package restyles with
				its own `surfaceStrong`: the wedge keeps following the theme, in the
				panel's own colour, and can no longer inherit its geometry. ]]
			table.insert(
				children,
				chrome_slots.attachHint(
					blueprintLib.corners(
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
							-- colour that a theme swap could desynchronize — AND so its two
							-- protruding edges carry the theme's own hairline (header)
							surface = tailSpec.surface or "raised",
							hidden = tailHidden,
						}),
						-- A WEDGE, NOT A BLOB. Without this the panel's phantom
						-- `::UICorner` rounds a 16px box by `radii.panel` = 12, the engine
						-- clamps that to half the side, and the arrow is a circle (header).
						0
					),
					{ slot = chrome_slots.NO_SLOT }
				)
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
		if wantsTail then
			--[[ DECLARED LAST, SO IT PAINTS OVER THE PANEL'S BORDER — the mirror of the
				wedge's "declared first, so it paints behind". This is the seam fix: the
				panel's hairline stops being drawn across the arrow's base, so the plate
				and the arrow read as ONE shape (director, 2026-08-17: *"can we eliminate
				the line at the bottom of the triangle?"*).

				`surface = "base"` is the ONE native surface with neither a phantom corner
				NOR a phantom stroke, so the band can never round its ends or grow a
				border; the tint puts it in the panel's own colour. That tint is a SECOND
				AUTHORITY over a value `.facet-surface-raised` already owns, and the two
				resolve through different paths — so `sheet_seam_authority.spec.luau` pins
				them equal across every shipped package. Without that guard this is a
				defect only a live `GetStyled` could ever see. ]]
			table.insert(
				children,
				chrome_slots.attachHint(
					blueprintLib.corners(
						blueprintLib.Box({
							id = TAIL_SEAM_ID,
							anchor = "topLeft",
							offsetX = sx,
							offsetY = sy,
							width = sw,
							height = sh,
							surface = "base",
							tint = { role = "surfaceStrong", blend = 1 },
							-- one suppression rule, not two: a plate the clamp carried off
							-- its source drops the wedge, and the band goes with it
							hidden = tailHidden,
						}),
						0
					),
					{ slot = chrome_slots.NO_SLOT }
				)
			)
		end

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

		local chrome = opts ~= nil and opts.chrome == true
		if chrome and opts ~= nil and opts.modal == true then
			error(
				"Facet presenter.presentAnchored: `chrome` and `modal` are opposites. A chrome layer takes no "
					.. "input and pushes no focus scope; a modal exists to trap both.",
				0
			)
		end
		local handle
		if chrome then
			--[[ CHROME MODE (D3a): A LAYER, NOT A SURFACE.

				A presented surface is the right shape for a Menu or a Callout — it
				pushes a focus scope, creates an input context and joins the stack, and
				all three are things those constructs need. It is exactly the wrong
				shape for a HELP PLATE, which must be provably incapable of taking
				anything: a scope with no focusables of its own is still the TOP scope,
				so the next arrow press after one appeared had nowhere to go. Measured,
				before this mode existed.

				So a chrome surface is mounted the way the two shipped chrome layers
				already are — the full-value disclosure plate and the toast strip both
				hand-mount their own controller and never enter the stack — and this is
				the THIRD copy of that, written once. It still gets everything D1
				actually owns: the same solver, the same tail, the same safe box, the
				same moving-source cadence. What it gives up is the presenter's stack,
				scope, context and catcher, which is the entire point.

				`rootPolicy = "edgeToEdge"` for the same reason the delegating path
				pins it: the offsets are window space. The display order sits just
				above whichever surface owns the source, so a plate over a modal's
				control is above THAT modal rather than behind it. ]]
			local mounted = mountLib.mount(core, screen, { scope = scope:child("mount") })
			local controller = rendererLib.attach(core, mounted, env, adapter, { rootPolicy = "edgeToEdge" })
			controller.initialRender()
			if controller.setDisplayOrder ~= nil then
				local owner = if anchor.source.path ~= nil then handleByPath(anchor.source.path :: string) else nil
				local base = if owner ~= nil and type(owner.displayOrder) == "number"
					then owner.displayOrder
					else baseDisplayOrder
				controller.setDisplayOrder(base + 25)
			end
			handle = {
				chrome = true,
				id = id,
				blueprint = screen,
				root = mounted,
				controller = controller,
			}
		else
			handle = if opts ~= nil and opts.modal == true
				then presenter.presentModal(screen, passthrough)
				else presenter.present(screen, passthrough)
		end

		local record = {
			id = id,
			handle = handle,
			chrome = chrome,
			scope = scope,
			anchor = anchor,
			surfacePath = `/{id}/{LAYER_ID}/{SURFACE_ID}`,
			tailPath = `/{id}/{LAYER_ID}/{TAIL_ID}`,
			tailSeamPath = `/{id}/{LAYER_ID}/{TAIL_SEAM_ID}`,
			wantsTail = wantsTail,
			tailMetric = tailMetric,
			tailInsetMetric = tailInsetMetric,
			ox = ox,
			oy = oy,
			tx = tx,
			ty = ty,
			sx = sx,
			sy = sy,
			sw = sw,
			sh = sh,
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
			-- a CHROME record is not in the stack and never was, so the stack is not
			-- the question for it: it lives until `dismissChrome` takes it down
			if not record.chrome and table.find(stack, record.handle) == nil then
				table.remove(live, i)
				record.scope:dispose()
			end
		end
	end

	--[[ TAKE A CHROME LAYER DOWN. `presenter.dismiss` cannot: its first act is to
		remove the handle from the stack, and a chrome handle was never in it. So the
		presenter routes a chrome handle here instead, and the teardown is the same
		one the disclosure plate does — controller disposed, scope disposed, record
		gone on the same call rather than a frame later. ]]
	local function dismissChrome(handle: any)
		for i = #live, 1, -1 do
			local record = live[i]
			if record.handle == handle then
				table.remove(live, i)
				record.handle.controller.dispose()
				record.scope:dispose()
				return true
			end
		end
		return false
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
		dismissChrome = dismissChrome,
	}
end

return anchored
