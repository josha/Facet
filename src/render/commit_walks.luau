--!strict
--[[ THE COMMIT WALKS — everything that turns a finished solve into adapter writes.

	One solve produces one `rects` map, and six separate walks of the live tree
	spend it: the two typography paint seams, the solver's own text verdicts, the
	visibility verdict, the hit-geometry floor, and the native scroll canvas. They
	are grouped here because they are the same KIND of thing — a depth-first walk
	that compares a solve output against a per-path record of what was last
	written and sends only the difference — and because every one of them is a
	MINIMAL-WRITE contract whose record lives outside it.

	THE RECORDS STAY WITH THE RENDERER, BY REFERENCE. `lastTextSize`,
	`lastTextFont`, `lastPadding`, `lastCompact`, `lastWrapped`, `lastVisible`,
	`lastHitRects`, `lastScrollRegions` are declared in `render/renderer.luau` and
	handed here as tables. That is not an accident of extraction: the renderer's
	removal sweep clears them when a path leaves, and its parked-props record
	carries five of them across an instance RECYCLE
	(`captureParkedProps`/`restoreParkedProps`), so the owner of the lifetime has
	to be the file that owns mounting. A table is already a reference, so sharing
	one costs nothing and creates no way back — which is the same seam test
	`render/rect_pass.luau` passed, and the reason this module reads not one
	reassigned local of its host.

	WHY IT IS A MODULE. Roblox refuses a `Script.Source` assignment at 200,000
	characters, and every LIVE path is a write, so a module over the cap silently
	stops syncing into an open Studio session and a live check then tests the code
	baked into the place rather than the edits on disk
	(`docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md`).
	`renderer.luau` reached 198,974 — 1,026 characters of headroom — and
	`docs/handoff/SOURCE_CAP_LEDGER.md` had this extraction OWED BEFORE the next
	change of any size. The prescription there was "rect_pass-shaped: lift the
	RECT WRITE half of solveAndApply"; the rect diff-and-write loop itself had
	already left in `rect_pass.luau` (2026-08-17, one day before that row was
	written), so what shipped is the rest of the same half — the five other write
	loops the commit span runs beside it.

	THE OLD NAMES, so prose elsewhere still resolves. Inside `renderer.luau` these
	six were `applyTextScale`, `applyPadding`, `applyTextVerdicts`, `pushVisible`,
	`pushHitRects` and `pushRegions`; a comment in another module naming one of
	those means the function of that shape here. `src/client/screen_target.luau`
	still spells two of them the old way on purpose — it is itself inside the
	source-cap band, and a rename there costs it characters it does not have.

	WHAT DELIBERATELY STAYED BEHIND. The commit span's ORDER is the renderer's:
	visibility before hit geometry before rects before canvases, with the
	text-measurement follow-up last, and each of those orderings has its own
	recorded reason at the call site. So does the overhang lift
	(`render/hit_lift.luau`) and the z walk it triggers — a lift is paint ORDER,
	not a rect, and `syncZOrder` is declared far below the walks that need it.
]]

local authority = require("./authority")
local layout_node = require("./layout_node")
local themeSnapshot = require("../themes/snapshot")
local solver = require("../layout/solver")

local commit_walks = {}

--[[ A TOUCH FLOOR THAT GROWS UNTIL IT MEETS SOMETHING PRESSABLE (DIR5 review H1,
	ADR-0041).

	`own` is the rect the node paints, `want` is the floor it would like, and
	`blockers` are the rects of every node OUTSIDE it that can sink a press. The
	answer is `want`, given back one side at a time, each side stopping at the first
	blocker in its way and never shrinking past `own`.

	WHY GROWTH RATHER THAN A BOX TO CLAMP INTO. R18's ruling splits by what is
	UNDERNEATH: the 44px floor is EXEMPT over PASSIVE content — it is the F1
	accessibility floor and the convention every platform ships — and BANNED over
	INTERACTIVE content, because two actionable targets for one gesture is an
	ambiguity the player cannot see. So the bound is other pressable things, not a
	container. A first version clamped a cover into its REGION instead, and the
	measurement refused it: on the shipped HUD demo three covers whose floors reach
	nothing at all lost the floor purely because their regions are 21-30px tall, and
	`overflow_sweep`'s "no dead-end compact" guard reported it on five viewports — a
	route the thumb cannot land on is a route on paper.

	ONE SIDE AT A TIME, AND THE ORDER IS DETERMINISTIC rather than optimal: each
	side is grown against the rect as it stands, so an earlier side's growth is
	visible to a later side's test. That is conservative in the right direction (it
	can only grant less, never overlap more) and it is why this needs no fixed
	point. In the fixture that commissioned the rule the two vertical gaps are 9.5px
	against a 10.5px ask, so a cover that used to take 26% of each of two
	neighbouring Buttons now grows 42px of its 44 and takes nothing.

	It is a free function because a rule with a rect, a wish and a list in it
	deserves a table of cases (`tests/hit_floor_region_clamp.spec.luau`). ]]
function commit_walks.growWithin(own: any, want: any, blockers: { any }): any
	local out = { x = own.x, y = own.y, w = own.w, h = own.h }
	local asks = {
		{ side = "top", ask = math.max(0, own.y - want.y) },
		{ side = "bottom", ask = math.max(0, (want.y + want.h) - (own.y + own.h)) },
		{ side = "left", ask = math.max(0, own.x - want.x) },
		{ side = "right", ask = math.max(0, (want.x + want.w) - (own.x + own.w)) },
	}
	for _, entry in asks do
		local granted = entry.ask
		if granted <= 0 then
			continue
		end
		for _, b in blockers do
			if b.w <= 0 or b.h <= 0 then
				continue
			end
			--[[ TWO SKIPS PER SIDE, and the second one is what a first draft got
				wrong. A blocker BESIDE this rect on the other axis is never in its way;
				and a blocker entirely on the FAR side of the edge being moved cannot be
				hit by moving that edge — a rect above the box does not block growth
				DOWNWARD. Without the second test its negative "room" clamped the
				opposite side to zero, which cost every boxed-in-on-one-side cover its
				whole floor. ]]
			local room: number
			if entry.side == "top" or entry.side == "bottom" then
				if b.x >= out.x + out.w or b.x + b.w <= out.x then
					continue
				end
				if entry.side == "top" then
					if b.y >= out.y then
						continue
					end
					room = out.y - (b.y + b.h)
				else
					if b.y + b.h <= out.y + out.h then
						continue
					end
					room = b.y - (out.y + out.h)
				end
			else
				if b.y >= out.y + out.h or b.y + b.h <= out.y then
					continue
				end
				if entry.side == "left" then
					if b.x >= out.x then
						continue
					end
					room = out.x - (b.x + b.w)
				else
					if b.x + b.w <= out.x + out.w then
						continue
					end
					room = b.x - (out.x + out.w)
				end
			end
			granted = math.min(granted, room)
		end
		--[[ ...AND A SIDE THAT WAS GRANTED NOTHING — OR LESS THAN NOTHING, which is
			what a blocker already level with or inside this rect computes — MOVES NOT
			AT ALL. This is the guard that makes the rule one-directional: a floor may
			never shrink a node past what it already paints. ]]
		if granted <= 0 then
			continue
		end
		if entry.side == "top" then
			out.y -= granted
			out.h += granted
		elseif entry.side == "bottom" then
			out.h += granted
		elseif entry.side == "left" then
			out.x -= granted
			out.w += granted
		else
			out.w += granted
		end
	end
	return out
end

--[[ THE CONTRACT, AS A TYPE RATHER THAN A PARAGRAPH. Every field is read-only to
	this module or a by-reference table the renderer declares ONCE and never
	rebinds — which is the whole seam test, because a reassigned local cannot be
	shared by reference at all. `tests/commit_walks_seam.spec.luau` compares this
	declaration against what the module READS and what the renderer PASSES, in
	both directions, over the live sources. ]]
export type CommitCtx = {
	adapter: any, -- the render target
	handles: any, -- path -> adapter handle
	stats: any, -- the renderer's counters
	rectsEqual: any, -- the pure rect comparison
	paintedRectIn: any, -- a solve's rect for a path, as painted
	pathEscapesClip: any, -- is this stroked path outside its clip host
	reculPathClips: any, -- re-cull the paths against the live scroll offsets
	--[[ the eight minimal-write records, one per verdict the walks below send.
		They belong to the renderer because it owns the LIFETIME: its removal sweep
		clears each of them per path, and its parked-props record carries five
		across an instance recycle. ]]
	lastTextSize: any,
	lastTextFont: any,
	lastPadding: any,
	lastCompact: any,
	lastWrapped: any,
	lastVisible: any,
	lastHitRects: any,
	lastScrollRegions: any,
	scrollAutoscroll: any, -- per scroll host: its autoscroll declaration
	pathClipObservers: any, -- per scroll host: the live-offset subscription
	solverHidden: any, -- path -> the solver's hidden verdict this pass
	paintHeld: any, -- path -> the presenter's paint hold
	pathNodes: any, -- the stroked-path node set
	inputSinks: any, -- path -> can this node SINK a press (the overhang lift's census)
}

function commit_walks.new(ctx: CommitCtx)
	local adapter = ctx.adapter
	local handles = ctx.handles
	local stats = ctx.stats
	local rectsEqual = ctx.rectsEqual
	local paintedRectIn = ctx.paintedRectIn
	local pathEscapesClip = ctx.pathEscapesClip
	local reculPathClips = ctx.reculPathClips
	local lastTextSize = ctx.lastTextSize
	local lastTextFont = ctx.lastTextFont
	local lastPadding = ctx.lastPadding
	local lastCompact = ctx.lastCompact
	local lastWrapped = ctx.lastWrapped
	local lastVisible = ctx.lastVisible
	local lastHitRects = ctx.lastHitRects
	local lastScrollRegions = ctx.lastScrollRegions
	local scrollAutoscroll = ctx.scrollAutoscroll
	local pathClipObservers = ctx.pathClipObservers
	local solverHidden = ctx.solverHidden
	local paintHeld = ctx.paintHeld
	local pathNodes = ctx.pathNodes
	local inputSinks = ctx.inputSinks

	-- paint seam for scaled text (input-paradigms expansion, matrix D.1): write
	-- props.textSize * typographyScale, tracking the last value per path so a
	-- steady scale is a no-op (minimal-write contract) but a displaySize flip
	-- rewrites every scaled size. Runs inside solveAndApply so paint and the
	-- re-solved layout always agree.
	--
	-- ...and the INTRINSIC size paints too (director fix round 2026-07-25). It
	-- used not to: an absent `textSize` left the adapter's hardcoded TextSize 16,
	-- while the measure seam above reserved the class's typography ROLE from the
	-- snapshot. A package that moved that role — compact-pointer draws its control
	-- text at 13 — was therefore reserved for at one size and drawn at another,
	-- and a single-line button label wrapped ("Pla"/"y") inside a box the solver
	-- had sized correctly for the size it measured. Same argument as `padding`
	-- below, same seam, same guarantee: written inside the solve, against THAT
	-- solve's metrics, so the size the engine draws with and the size the solver
	-- reserved can never disagree.
	--
	-- `textScale` multiplies AUTHORED sizes only, exactly as the measure seam does
	-- (an intrinsic default is not scaled there either), and the preferred-text
	-- offset stays out of paint because the engine applies its own at draw time.
	-- THE FACE, beside the size, from the SAME role (F2, 2026-08-02). The
	-- typography role has always carried a font descriptor and the MEASURE seam
	-- has always keyed `text_metrics` on it (`toLayoutNode` -> `layoutNode.font`);
	-- paint did not, so every text node was drawn in whatever face the adapter
	-- hardcoded at creation. That is `Text.font`'s deprecation read backwards —
	-- there, the author's face reached measurement and never paint; here, the
	-- THEME's face reached measurement and never paint — and it is why a weight
	-- channel had to be a role rather than a prop.
	--
	-- Both seams resolve through `themeSnapshot.effectiveTypeRole`, so the
	-- descriptor the solver measured with IS the descriptor the engine draws with.
	-- Written inside the solve, against THAT solve's metrics, exactly as the size
	-- and the Button padding beside it are. Minimal-write: the descriptor key is
	-- cached per path, so a steady theme costs zero writes and every screen whose
	-- roles all resolve to the family's Regular face is byte-identical.
	local function textScale(rootNode: any, scale: number, metrics: any)
		local function walk(node: any)
			-- an AUTHORED size paints; a role name is just as authored as a number
			-- (it resolves through the same snapshot the measure seam used), while
			-- an absent prop falls back to the class's own typography role
			local raw = themeSnapshot.resolveSize(metrics, node.props and node.props.textSize)
			if raw == nil and not (node.class == "Button" and #node.children > 0) then
				raw = themeSnapshot.intrinsicTextSize(metrics, node.class)
			end
			if raw ~= nil and handles[node.path] ~= nil then
				--[[ ONE LADDER, AUTHORED OR NOT — the ten-foot adaptation round, 2026-08-18.
					This read
					`if authored then raw * scale else raw`, and the measure seam said the
					same thing, so the two agreed and nothing clipped — which is precisely
					why nobody saw that `UI.Text{ text }` painted 16px on a television
					while `UI.Text{ textSize = "body" }` painted 24. The ten-foot floor is
					a property of the ROLE ("body text must clear ~29pt at 3m", D.1), and
					an unauthored node wears a role too (`INTRINSIC_TEXT_ROLE`), so it
					takes the same multiplier. Scaling here alone would draw 27px inside a
					box reserved for 18: `layout_node.textOf` moves in the same commit,
					and measure/paint agreement is the property that had to survive. ]]
				local scaled = raw * scale
				if lastTextSize[node.path] ~= scaled then
					authority.assertWrite(node.class, "textSize", "layout")
					adapter.setProp(handles[node.path], "textSize", scaled, "layout")
					lastTextSize[node.path] = scaled
					stats.propWrites += 1
				end
				-- a CONTENT Button draws no text of its own, so it has no face to
				-- write either (`raw` is already nil for one, above)
				local roleName, role =
					themeSnapshot.effectiveTypeRole(metrics, node.class, node.props and node.props.textSize)
				if role ~= nil then
					if lastTextFont[node.path] ~= role.fontKey then
						authority.assertWrite(node.class, "textFont", "layout")
						adapter.setProp(handles[node.path], "textFont", {
							role = roleName,
							fontKey = role.fontKey,
							family = role.font.family,
							weight = role.font.weight,
							style = role.font.style,
						}, "layout")
						lastTextFont[node.path] = role.fontKey
						stats.propWrites += 1
					end
				end
			end
			for _, child in node.children do
				walk(child)
			end
		end
		walk(rootNode)
	end

	-- PAINT SEAM FOR PADDING, exactly the shape `textScale` has. A Button's
	-- engine text inset is theme geometry: it resolves through the snapshot, so a
	-- theme swap or a designer's live metric edit moves it — and it is written
	-- here, inside the solve, against THAT solve's metrics, so the inset the
	-- engine draws with and the padding the solver reserved can never disagree.
	-- Minimal-write: the effective four sides are cached per path, so a steady
	-- theme costs zero writes.
	--
	-- ...AND A PADDED `Text` GOES OUT THE SAME SEAM (device report 2026-08-12,
	-- IMG_3691 — the S1..S12 stat tiles). `UI.padding` is legal on a Text because
	-- the solver's text measure ADDS it to the reserved box
	-- (`blueprint_schema` Text.padding: "it lets UI.padding apply without
	-- wrapping"), and nothing painted it: the plate came out label+12 wide and the
	-- glyphs were drawn from the box's leading edge, so every tile's label sat
	-- against — and over — its own rounded corner. Measured at a size nobody
	-- painted, which is `docs/lessons/measure-the-requirement-not-the-render.md`
	-- read backwards. A container spends its padding in `arrange` (children are
	-- placed at rect + padding) and a Button already had this write, so a text LEAF
	-- was the one shape where the two passes could disagree.
	--
	-- Guarded on an AUTHORED value: an unpadded Text — every Text on every shipped
	-- screen but these — raises no write and materializes no engine modifier.
	local function padding(rootNode: any, metrics: any)
		local function walk(node: any)
			local pad: any = nil
			if node.class == "Button" then
				pad = themeSnapshot.buttonPadding(metrics, node.props)
			elseif node.class == "Text" then
				if node.props ~= nil and node.props.padding ~= nil then
					pad = themeSnapshot.resolveSides(metrics, node.props.padding)
				elseif lastPadding[node.path] ~= nil then
					-- ...AND AN ADOPTED INSTANCE MUST BE UN-PADDED EXPLICITLY. The
					-- recycler carries `padding` across an adoption
					-- (`captureParkedProps`/`restoreParkedProps` below), so a padded
					-- label recycled into an unpadded one would keep the previous row's
					-- inset on a modifier this seam had stopped visiting. Zeroing is a
					-- write; skipping is a stale glyph box.
					pad = { top = 0, right = 0, bottom = 0, left = 0 }
				end
			end
			if pad ~= nil and handles[node.path] ~= nil then
				local top, right, bottom, left = solver.sides(pad)
				local key = `{top},{right},{bottom},{left}`
				if lastPadding[node.path] ~= key then
					authority.assertWrite(node.class, "padding", "layout")
					adapter.setProp(handles[node.path], "padding", pad, "layout")
					lastPadding[node.path] = key
					stats.propWrites += 1
				end
			end
			for _, child in node.children do
				walk(child)
			end
		end
		walk(rootNode)
	end

	-- PAINT SEAM FOR THE COMPACT LADDER, the same shape `textScale` and
	-- `padding` have (director, 2026-07-27).
	--
	-- The verdict is the SOLVER's — only it knows the width this node ended up
	-- with — and it reaches paint through the rects it produced, so the string the
	-- box was reserved for is the string the engine draws. That is the whole
	-- reason this is a post-solve seam and not a prop the author toggles.
	--
	-- The label ITSELF still goes out on the ordinary binding write, so there is
	-- exactly one writer for `Text` and `screen_target`'s TextWrapped rule
	-- re-decides from the string it is handed, exactly as it does for a reactive
	-- label. An icon form additionally raises an icon REQUEST, which is the same
	-- upgrade-not-dependency arrangement `props.icon` already uses: the ASCII
	-- glyph is already drawn, and theme art paints over it if any resolves.
	-- Minimal-write: the verdict is cached per path, so a steady layout costs zero
	-- writes and a node with no compact form is never visited twice.
	-- ...and the WRAP verdict, on the same seam and for the same reason (director
	-- ruling 5, 2026-08-13). `screen_target`'s TextWrapped rule sees the string and
	-- not the box, so it cannot answer "does this phrase's longest word fit"; the
	-- solver can, and does (`textFacts.wraps`). Unlike `lastCompact` this IS a value
	-- the instance holds, so it rides the parked-props record across a recycle
	-- exactly as `lastTextSize` does — a recycled instance carrying `TextWrapped =
	-- false` with a cleared cache would silently keep it.
	--
	-- `nil` means "never written", which is the adapter's own default (wrap on
	-- whitespace) — so the overwhelmingly common `wraps = true` node costs ZERO
	-- writes, on the first solve and every one after it.
	-- ONE WALK, TWO VERDICTS. Both are the solver's answers about text, both reach
	-- paint through the rects that produced them, and both are cached per path — so
	-- they share the traversal rather than paying for a second one on every solve.
	local function textVerdicts(rootNode: any, rects: any)
		local function walk(node: any)
			local handle = handles[node.path]
			local labelDriven = node.class == "Text" or (node.class == "Button" and #node.children == 0)
			if labelDriven and handle ~= nil then
				local entry = rects[node.path]
				if node.class == "Button" then
					local isCompact = entry ~= nil and entry.compact == true
					local form = layout_node.compactForm(node.props)
					if form ~= nil and lastCompact[node.path] ~= isCompact then
						authority.assertWrite("Button", "text", "binding")
						adapter.setProp(handle, "label", layout_node.drawnButtonText(node.props, isCompact), "binding")
						stats.propWrites += 1
						if form.kind == "icon" then
							authority.assertWrite("Button", "icon", "style")
							adapter.setProp(handle, "icon", if isCompact then form.icon else nil, "style")
							stats.propWrites += 1
						elseif form.kind == "image" then
							authority.assertWrite("Button", "compactLabel", "style")
							adapter.setProp(handle, "compactLabel", if isCompact then form else nil, "style")
							stats.propWrites += 1
						end
						lastCompact[node.path] = isCompact
					end
				end
				-- THE WRAP VERDICT (ruling 5). A node the solve did not reach (hidden,
				-- not yet solved) keeps whatever it has: absent facts are not a verdict.
				local facts = if entry ~= nil then entry.textFacts else nil
				if facts ~= nil then
					local wraps = facts.wraps == true
					local previous = lastWrapped[node.path]
					if (if previous == nil then true else previous) ~= wraps then
						authority.assertWrite(node.class, "textWrapped", "layout")
						adapter.setProp(handle, "textWrapped", wraps, "layout")
						lastWrapped[node.path] = wraps
						stats.propWrites += 1
					end
				end
			end
			for _, child in node.children do
				walk(child)
			end
		end
		walk(rootNode)
	end

	--[[ THE VISIBILITY VERDICT. A hidden candidate must not PAINT: a zero rect was
		not enough, because text still wrapped and drew inside a 0px box (found live
		in the `adaptive_controls` capture, where the losing action column's labels
		ran down the screen edge). The solver marks the candidate ROOT only, so
		hiddenness is carried DOWN the walk. Feature-detected: an adapter with no
		`setVisible` keeps today's behaviour, and — deliberately — writes no
		`solverHidden` verdict either, exactly as before this was a module. ]]
	local function visible(rootNode: any, rects: any, nextHidden: any)
		if adapter.setVisible == nil then
			return
		end
		local function rectFor(path: string): any
			return paintedRectIn(rects, path)
		end
		local function pushVisible(node: any, hidden: boolean)
			local isHidden = hidden or nextHidden[node.path] == true
			solverHidden[node.path] = isHidden
			-- RS-PATHCLIP: a stroked path outside its clip host is culled. It is
			-- decided per NODE and never inherited (a Path is a leaf, and the
			-- solver's own verdict is what descends), so the walk keeps carrying
			-- `isHidden` down and this only widens the write for the path itself.
			-- ...and a presenter PAINT HOLD (auto reveal) is a per-node veto the
			-- same way: never inherited, never contradicting the solver.
			local wantHidden = isHidden or paintHeld[node.path] == true
			if not wantHidden and pathNodes[node.path] == true and pathEscapesClip(node.path, rectFor) then
				wantHidden = true
			end
			local handle = handles[node.path]
			if handle ~= nil and lastVisible[node.path] ~= not wantHidden then
				adapter.setVisible(handle, not wantHidden)
				lastVisible[node.path] = not wantHidden
			end
			for _, child in node.children do
				pushVisible(child, isHidden)
			end
		end
		pushVisible(rootNode, false)
	end

	--[[ B-BTN3: enforce the effective target floor in HIT geometry. The visual rect
		is deliberately untouched — flooring the painted size would silently rewrite
		shipped design (a 22px icon button would double) — so the framework separates
		what the player SEES from what the player can HIT. ]]
	local function hitRects(rootNode: any, rects: any, nextHidden: any, metrics: any)
		if adapter.setHitRect == nil then
			return
		end
		-- A HIDDEN CANDIDATE ASKS FOR NOTHING — found live by the rich-skinning
		-- device matrix, under the flat default, with real injected clicks. This
		-- walk used to ignore the
		-- `nextHidden` set the visibility walk just built. A hidden candidate
		-- solves to zero width, so every control inside it fell under the floor
		-- and the renderer ASKED for an expanded hit rect — a live activation
		-- surface for a control the player cannot see, which in the real adapter
		-- sits at the ScreenGui root and out-ranked the VISIBLE winner's buttons.
		-- Hiddenness is carried down the walk (the solver marks the candidate
		-- ROOT only) exactly as `pushVisible` carries it, and a hidden node takes
		-- the SAME diff path with `want = nil`, so a node that BECOMES hidden has
		-- its expander retracted rather than merely left un-refreshed.
		--[[ ...AND THE ONE FLOOR THAT IS BOUNDED (DIR5 review H1, ADR-0041). A
			region's expand affordance in the "cover" role IS the region's whole box,
			so inflating it to the touch floor necessarily leaves the region on the
			axis it is short on — measured at 390x150 as 960 px2 of one neighbouring
			Button and 828 of another, 26% of each, delivered to the plate instead of
			to the button the player aimed at.

			THE BOUND IS R18 AS IT WAS RULED, AND THE REGION BOX IS NOT IT. The ruling
			splits by what is UNDERNEATH: the 44px floor is EXEMPT over PASSIVE content
			— it is the F1 accessibility floor and the convention every platform ships
			— and BANNED over INTERACTIVE content, because two actionable targets for
			one gesture is the ambiguity the player cannot see. So a cover keeps its
			whole floor unless that floor would reach an interactive node OUTSIDE its
			own region, and only then falls back to the region's box.

			CLAMPING TO THE REGION UNCONDITIONALLY WAS TRIED FIRST AND MEASURED WRONG.
			On the shipped HUD demo the un-clamped floors of all five covers take
			NOTHING from any interactive node — the regions have room around them — and
			the unconditional clamp took the accessibility floor off three of them
			purely because their regions are 21-30px tall. `overflow_sweep`'s
			"no dead-end compact" guard reported it on five viewports: a route the
			thumb cannot land on is a route on paper. The guard was right and the
			first rule was over-applied.

			WHY NOT A NODE-AWARE `effectiveHitFloor`. `syncZOrder` calls that same
			function to reserve the expander's z slot, and NM-H4a made that reservation
			a function of the CLASS rather than of the current state after a whole-band
			paint defect on a real device. A floor that returned nil for a cover would
			move every z below every cover and put the reservation back on history.
			This decision reads THIS SOLVE's rects and the structural sink census, and
			never `lastHitRects` — it is a function of the frame, not of its history. ]]
		local function isCover(node: any): boolean
			local props = node.props
			local target = if props ~= nil then props.expandTarget else nil
			return type(target) == "table" and target.role == "cover"
		end
		--[[ EVERY RECT A PRESS COULD LAND ON. `inputSinks` is the same structural
			census the overhang lift resolves against — which paths can actually SINK a
			press — collected on the live-path walk, so this costs one pass over that
			set per STANDING COVER and nothing at all on every other node.

			IT NEEDS NO "NOT MY OWN REGION" FILTER, and one was written and then
			removed because no mutation could redden it (2026-08-21). R18 exempts the
			floor inside its own region, and the geometry already delivers that: every
			side's test skips a blocker on the far side of the edge it is moving, so a
			blocker CONTAINED in the node's own rect — which is what a region's own
			standing form is, and what the cover itself is — skips on all four sides by
			construction. A filter that restates a fact the arithmetic already
			guarantees is a filter the next reader trusts instead of the arithmetic.

			A HIDDEN NODE CANNOT BE PRESSED, and `solverHidden` was written by the
			visibility walk that runs immediately before this one. ]]
		local function pressableRects(): { any }
			local out: { any } = {}
			for path in inputSinks do
				if solverHidden[path] == true then
					continue
				end
				local other = rects[path]
				local r = if other ~= nil then other.rect else nil
				if r ~= nil and r.w > 0 and r.h > 0 then
					table.insert(out, r)
				end
			end
			return out
		end
		local function pushHitRects(node: any, hidden: boolean)
			local isHidden = hidden or nextHidden[node.path] == true
			local entry = rects[node.path]
			-- the same reading the solve was handed as `hitFloor` (see
			-- `effectiveHitFloor`): the contract declares the floor exists, the
			-- theme owns its value, and it clamps up only
			local floor = layout_node.effectiveHitFloor(node.class, metrics)
			if floor ~= nil then
				local handle = handles[node.path]
				if entry ~= nil and handle ~= nil then
					local r = entry.rect
					local want: any = nil
					if not isHidden and (r.w < floor or r.h < floor) then
						local w = math.max(r.w, floor)
						local h = math.max(r.h, floor)
						want = {
							x = r.x - math.floor((w - r.w) / 2),
							y = r.y - math.floor((h - r.h) / 2),
							w = w,
							h = h,
						}
						if isCover(node) then
							want = commit_walks.growWithin(r, want, pressableRects())
							-- grown back to the box it already paints, there is
							-- nothing to advertise: the Button's own rect IS the
							-- region, so an expander here would be a transparent
							-- duplicate of it
							if want.w <= r.w and want.h <= r.h then
								want = nil
							end
						end
					end
					local last = lastHitRects[node.path]
					if not rectsEqual(last, want) then
						adapter.setHitRect(handle, want)
						lastHitRects[node.path] = want
					end
				end
			end
			-- the box a child's floor may not leave. A node the solve did not reach
			-- passes its own ancestor's down rather than nil, which widens the bound
			-- rather than removing it.
			for _, child in node.children do
				pushHitRects(child, isHidden)
			end
		end
		pushHitRects(rootNode, false)
	end

	--[[ NATIVE SCROLL REGIONS — the native-substrate round's scroll seam, and the
		one place a canvas is published. A scroll node's SOLVED
		content extent (plus its own padding — children arrange inside the padded
		area, so the canvas must include it) maps to the adapter's canvas. The
		adapter/engine owns the live offset; the solver keeps owning every content
		rect. Feature-detected: a scroll-less adapter (billboard until proven, old
		fake) keeps the clip-only fallback. ]]
	local function scrollRegions(rootNode: any, rects: any, metrics: any)
		if adapter.setScrollRegion == nil then
			return
		end
		local function pushRegions(node: any)
			if node.class == "ScrollView" then
				local entry = rects[node.path]
				local handle = handles[node.path]
				if entry ~= nil and entry.contentSize ~= nil and handle ~= nil then
					-- THE PADDING THE SOLVER ACTUALLY SPENT, not the padding the
					-- author wrote (found 2026-07-27 while chasing a landscape
					-- scroll cut-off). `toLayoutNode` adds a slot's `chromeInsets`
					-- to this node's padding before the solve, and a ScrollView
					-- always classifies into the `scrollbar` slot — so recomputing
					-- from `props.padding` here would under-report the canvas by
					-- exactly the theme's reservation, and the tail of the content
					-- would be unreachable. Inert today (every shipped package
					-- declares `chrome.scrollbar = { kind = "native" }`, reserving
					-- zero) and wrong the moment one does not.
					local props = node.props or {}
					local layoutPadding = if entry.padding ~= nil
						then entry.padding
						else themeSnapshot.resolveSides(metrics, props.padding)
					local pt, pr, pb, pl = solver.sides(layoutPadding)
					-- ...PLUS THE THEME'S DECORATION BLEED (director round 11,
					-- root-caused 2026-07-27 from a landscape capture).
					--
					-- A canvas built from RECTS stops exactly at the last child's
					-- rect — I measured it doing so to the pixel in seven
					-- configurations. A `shadow` recipe paints OUTSIDE that rect,
					-- so under Sci-Fi HUD (a centred 24px glow on `panel`) the
					-- bottom of the last element was unreachable: scrollbar at the
					-- end of its track, content still cut off.
					--
					-- It is spent HERE and nowhere else, deliberately. Reserving it
					-- as layout margin would be the other way to fix it and it would
					-- be wrong — a glow is meant to overlap its neighbours, and
					-- reserving it would space every themed screen out by 24px in
					-- every direction. A canvas allowance is the scroll-inset shape every
					-- platform ships: the layout does not move, the paint becomes
					-- reachable.
					-- Zero for every package that declares no shadow.
					local bleed = if type(metrics.chromeBleed) == "number" then metrics.chromeBleed else 0
					local region = {
						axis = props.axis or "y",
						contentW = entry.contentSize.w + pl + pr + bleed,
						contentH = entry.contentSize.h + pt + pb + bleed,
						-- the host's ARRANGED box, so the adapter's cross-axis
						-- canvas clamp is deterministic instead of racing the
						-- engine's own window geometry mid-layout
						hostW = entry.w,
						hostH = entry.h,
						-- per-host indicator opt-out (director ruling 2026-08-09):
						-- carried on the region because the adapter learns a host
						-- overflows on exactly this walk — the same place its
						-- indicator lifecycle begins
						indicators = if props.indicators == "none" then "none" else "auto",
					}
					-- the host's own autoscroll declaration, recorded on the SAME
					-- walk that publishes its canvas: `false` opts out, a table
					-- tunes the model, absent means on-and-inert. Kept here so the
					-- per-frame stepper never needs a tree lookup.
					scrollAutoscroll[node.path] = if props.autoscroll == false
						then false
						else (if type(props.autoscroll) == "table" then props.autoscroll else true)
					local last = lastScrollRegions[node.path]
					if
						last == nil
						or last.axis ~= region.axis
						or last.contentW ~= region.contentW
						or last.contentH ~= region.contentH
						or last.indicators ~= region.indicators
						or last.hostW ~= region.hostW
						or last.hostH ~= region.hostH
					then
						authority.assertWrite("common", "canvasSize", "layout")
						adapter.setScrollRegion(handle, region)
						lastScrollRegions[node.path] = region
					end
					-- RS-PATHCLIP: the host's live offset is what a stroked path
					-- inside it has to be re-culled against. One subscription per
					-- scroll host, taken where the host is already in hand; the
					-- callback early-outs on a surface with no paths, so a list that
					-- draws none pays a comparison.
					if adapter.observeScroll ~= nil and pathClipObservers[node.path] == nil then
						pathClipObservers[node.path] = adapter.observeScroll(handle, function()
							reculPathClips()
						end)
					end
				end
			end
			for _, child in node.children do
				pushRegions(child)
			end
		end
		pushRegions(rootNode)
	end
	return {
		textScale = textScale,
		padding = padding,
		textVerdicts = textVerdicts,
		visible = visible,
		hitRects = hitRects,
		scrollRegions = scrollRegions,
	}
end

return commit_walks
