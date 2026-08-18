--!strict
-- Scenario 'sponsor_drop' (ledger rows SF-D1..SF-D5, SF-L2, SF-P4, SF-M2;
-- ui-designer-spec §8.4): the WHOLE DRAG STORY on one surface — promotion,
-- proxy, live verdicts, reject-and-return, edge autoscroll, the non-pointer
-- arm→navigate→commit path, and the ghost's layer.
--
-- THE FIXTURE WIRES NOTHING IT SHOULD NOT. The presenter auto-wires the drag
-- registry's collaborators (feedback bus, motion clock, ghost layer, clock time),
-- so this file declares `UI.draggable` / `UI.dropTarget` and drives the PUBLIC
-- registry seams. The only wiring here is the consumer's own half of the
-- non-pointer path (Activate arms / commits, Cancel cancels) and the once-per-
-- frame `stepAutoscroll` call the list documents.
--
-- INJECTED POINTER INPUT IS LABELED. `pressUnderThreshold` and friends drive
-- `registry.pointerDown/Move/Up` — the same seam the engine's detector funnels
-- into — and RECORD the aim rects plus the expected outcome, so the Studio phase
-- can replay the identical gesture with VirtualInput and compare against the
-- same block. No step claims a physical press happened.
--
-- THE §5.5 NON-POINTER PRESENTATION IS DRIVEN OFF THE FEEDBACK BUS (review
-- R2-F4). Arming a card is a state a player must be able to SEE: the source
-- takes the native selected state, focus moves to the first eligible row, and
-- the commit/cancel returns it to the card it came from. All of it hangs off
-- `pres.onFeedback` — `select`/`commit`/`cancel` with the session's own mode —
-- so every cancel path (the action, a modal, an illegal commit) restores the
-- surface without the fixture hooking each call site.

return {
	title = "Drop lab (SF-D1..D5/L2/P4/M2)",
	ledgerRows = {
		"SF-D1",
		"SF-D2",
		"SF-D3",
		"SF-D4",
		"SF-D5",
		"SF-L2",
		"SF-P4",
		"SF-M2",
		"SF-F1",
		"SF-C1",
		"SF-C2",
		"SF-C3",
	},
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local env = ctx.env
		local pres = ctx.presenter
		local scope = core:scope("sponsor-drop")
		local clock = pres.motionClock
		local conditions = Facet.adaptive.conditions(core, env, { scope = scope }) -- RR-8: six memos die with the fixture

		local SCREEN = "/DropLab"
		local LIST = SCREEN .. "/Main/ListZone/Rows"
		local HAND = SCREEN .. "/Main/Hand"
		local CHEV_TOP = SCREEN .. "/Main/ListZone/Chevrons/ChevTop"
		local CHEV_BOTTOM = SCREEN .. "/Main/ListZone/Chevrons/ChevBottom"
		local PROXY_LAYER = "/__dragproxy__/Layer"

		local trace: { any } = {}
		local elapsed = 0
		local rejects: { any } = {}
		local function note(kind: string, info: any?)
			table.insert(trace, { at = elapsed, kind = kind, info = info })
		end
		-- the ARMED SOURCE (§5.5): the path of the card an armed session is holding,
		-- nil while nothing is armed. Cards bind their `selected` state to it, and it
		-- is also where focus goes home to on the terminal.
		local armedSource = scope:own(core:signal(nil :: string?))
		-- the armed card's payload, for the rows to read: while it is set, a row
		-- that would REFUSE the card dims — which is also the visible answer to
		-- "why did the pickup land my focus on row 02" (director round: the
		-- skipped rows gave no cue that they had refused)
		local armedPayload = scope:own(core:signal(nil :: any))

		local armFocus: { any } = {}
		-- the focus exemption this fixture opened on arm (nil = none of ours)
		local armExemption: string? = nil
		-- declared before the bus handler, defined once the list exists
		local armPresent: (source: string, payload: any) -> ()
		local armRelease: (how: string) -> ()
		scope:own(pres.onFeedback(function(event: any)
			table.insert(trace, {
				at = elapsed,
				kind = "feedback:" .. tostring(event.type),
				info = { path = event.path, reason = event.reason, context = event.context },
			})
			if event.type == "reject" then
				-- SF-D5: exactly one per refusal, carrying the fixture's own code
				table.insert(rejects, { at = elapsed, path = event.path, reason = event.reason })
			end
			-- THE ARM PRESENTATION, ON THE SEMANTIC BUS. `select` carries the session's
			-- mode, so a pointer pickup (which presents itself — the proxy IS the
			-- feedback) is left alone and only the armed path takes the source state.
			local context: any = event.context
			if event.type == "select" and type(context) == "table" and context.mode == "armed" then
				armPresent(tostring(context.source), context.payload)
			elseif event.type == "commit" or event.type == "cancel" then
				armRelease(event.type)
			end
		end))

		-- the presented handle, the controller and the surface's ONE drag registry.
		-- Declared first: rows, cards and steps all reach for them, and the registry
		-- only exists once the surface is presented.
		local result: any = {}
		local function controller(): any
			local handle = result.handle
			return if handle ~= nil then handle.controller else nil
		end
		local function registry(): any
			local ctrl = controller()
			return if ctrl ~= nil then ctrl.dragRegistry() else nil
		end
		-- a signal MIRROR of the registry's published verdict, so a row cell (built
		-- before the surface exists) can bind to it. Kept in sync by an observer on
		-- the registry's own Readable, so a retarget reaches the paint on the frame
		-- it happened rather than on the next tick.
		local registryVerdict = scope:own(core:signal(nil :: any))

		-- ===== data =========================================================
		local FULL_COUNT, SHORT_COUNT = 12, 4
		local function makeRows(n: number): { any }
			local out = {}
			for i = 1, n do
				table.insert(out, { id = string.format("row-%02d", i), name = string.format("Row %02d", i) })
			end
			return out
		end
		local rows = scope:own(core:signal(makeRows(FULL_COUNT)))
		local verdictLine = scope:own(core:signal("verdict: (idle)"))
		-- THE LANDED WASH (director fix round, RR parity): a successful drop has no
		-- commit flight by default — the card vanishes at the drop point, and the
		-- ROW carries the confirmation as a decay-class tint wash, exactly the
		-- shipped Sponsor `celebration:rowWash` beat expressed through public API.
		local landedKey = scope:own(core:signal(nil :: string?))
		local landedWash = if clock ~= nil then clock:spring(0, "decay") else nil
		if landedWash ~= nil then
			scope:own(function()
				landedWash:dispose()
			end)
			landedWash:onSettle(function()
				if landedWash:get() < 0.01 then
					landedKey:set(nil)
				end
			end)
		end
		local function washRow(key: string)
			landedKey:set(key)
			if landedWash ~= nil then
				landedWash:snap(0.45)
				landedWash:setTarget(0)
			end
		end
		local activations = scope:own(core:signal(0))
		local returnedHome = scope:own(core:signal(0))

		local drops: { any } = {}
		local sessionIds: { string } = {}
		local autoscrollTrace: { any } = {}
		local aim: { any } = {}
		local expectations: { any } = {}

		local function indexOfKey(key: string): number
			return tonumber(string.match(key, "%d+") or "0") or 0
		end

		-- the list's own row-hit path for a key: the node the framework focuses,
		-- hit-tests and lands drops on
		local function rowHit(key: string): string
			return `{LIST}/Canvas/W/[{key}]/Row/Hit`
		end

		-- THE LEGALITY TABLE IS FIXTURE DATA, the mechanism is the framework's.
		-- Even rows take the A/B cards, odd rows take C — so every card has both a
		-- legal and an illegal target, and every refusal carries a reason code the
		-- `reject` event hands back.
		local function acceptsFor(key: string)
			local index = indexOfKey(key)
			return function(payload: any): (boolean, string?)
				if type(payload) ~= "table" or payload.kind ~= "sponsor-card" then
					return false, "demo-blocked-3"
				end
				local even = index % 2 == 0
				if payload.card == "C" then
					return not even, "demo-blocked-1"
				end
				return even, "demo-blocked-2"
			end
		end

		-- ===== the list =====================================================
		local rowHeight = scope:own(core:memo(function(use)
			--[[ THE LINE BOX COMES FROM THE FRAMEWORK (`Facet.text.facts` /
				`Facet.text.lineBox`, adopted 2026-08-15). The copy that was here read
				`typographyScale` alone; the measure seam reserves at
				`max(typographyScale, typographyPaintScale)`, so at a sub-1 accessibility
				preference this reserved less than the engine drew.
				docs/plans/variable-item-extents.md. ]]
			local facts = Facet.text.facts({ env = env, use = use })
			local metrics: any = facts.metrics
			if type(metrics) ~= "table" or type(metrics.type) ~= "table" then
				return 56
			end
			local lineBox = Facet.text.lineBox({ facts = facts, size = "body", lines = 1 })
			return math.max(metrics.targetSizes.minimum or 44, lineBox + 2 * (metrics.space.s or 8))
		end))

		-- THE WINDOW IS A LIVE NUMBER (review R2-F7). `newVirtualList` takes a
		-- Readable viewport height, so the window is a memo over the environment's
		-- own viewport rect: a rotation or a split-screen resize re-derives it in
		-- place, and the painted box and the windowing arithmetic read the same
		-- number. A build-time pixel was the fixed-px-vs-live-facts defect class one
		-- level up from the row height.
		local viewportHeight = scope:own(core:memo(function(use)
			local vp: any = use(env:get("viewportRect"))
			local h = if type(vp) == "table" and type(vp.h) == "number" then vp.h else 760
			return math.clamp(math.floor(h * 0.5), 160, 420)
		end))

		local list: any = nil
		local ICON: any = { type = "fixed", px = "iconSizes.medium" }
		-- the affordance glyph is the SMALL icon role (§4.5); the row's verdict slot
		-- stays medium so this lab's row and the collection lab's measure the same
		-- A FLOOR, NOT A CAP (O-21, 2026-08-15). This plate holds a TEXT glyph, and
		-- a `fixed` box against a line height that grows with the player's text
		-- preference is the fixed-px-vs-text class: at +10/+14 the caption line box
		-- is 27/32px in a 16px plate, so the glyph overflowed its own zstack by 23px
		-- and the solver reported it CUT. `minMax` keeps the affordance at icon size
		-- wherever it fits and lets it grow with the one thing inside it.
		local CHEV_ICON: any = { type = "minMax", min = "iconSizes.small" }

		local function cell(item: any, cellCtx: any): any
			local itemScope = cellCtx.scope
			local key = item.id
			-- THE PREDICTED VERDICT, read from the registry's own publication. It
			-- carries `overId` and the refusal `reason` as well as the legal target,
			-- which is what lets a row paint "you are over me and I am refusing you"
			-- with the game's own code.
			local verdict = itemScope:own(core:memo(function(use)
				local v: any = use(registryVerdict)
				if v == nil or v.overId == nil then
					return nil
				end
				if string.find(v.overId, `[{key}]`, 1, true) == nil then
					return nil
				end
				return if v.legal then "legal" else "illegal"
			end))
			-- THE VERDICT WASH RIDES THE ROLE-BLEND CHANNEL (review R2-F6). It used to
			-- paint `raised` — an ELEVATION role carrying an interaction state, which
			-- is the one-meaning-per-channel erosion I-5 exists to stop. `tint` blends
			-- between two THEME roles, so the verdict stays themable and elevation
			-- keeps meaning elevation. It sits on its own Box because a tint claims
			-- the fill of the node it is written to, and the card's fill belongs to
			-- the theme's `control` surface; at rest the blend is 0, which IS that
			-- surface, so a row with no verdict is byte-identical to an untinted one.
			local verdictTint = itemScope:own(core:memo(function(use)
				local state = use(verdict)
				if state == "legal" then
					return { role = "accent", from = "control", blend = 0.35 }
				elseif state == "illegal" then
					return { role = "danger", from = "control", blend = 0.35 }
				end
				-- ARMED-INELIGIBLE DIM (director round): while a card is up, a row
				-- that would refuse it steps toward the base surface — the eye can
				-- see at a glance which rows are live for THIS card, and why the
				-- arm skipped the ones it skipped
				local payload = use(armedPayload)
				if payload ~= nil then
					local ok = acceptsFor(key)(payload)
					if not ok then
						return { role = "surface", from = "control", blend = 0.5 }
					end
				end
				-- the landed wash: the drop's confirmation decays on the row itself
				-- (a MotionValue IS a core signal, so the blend rides it directly)
				if landedWash ~= nil and use(landedKey) == key then
					local w = use(landedWash)
					if w > 0.01 then
						return { role = "accent", from = "control", blend = w }
					end
				end
				return { role = "accent", from = "control", blend = 0 }
			end))
			-- the wash node exists ONLY while it has something to say (director
			-- round three): an always-mounted tint paints its `from` colour at
			-- blend 0, which covered the row's own plate — and the native
			-- `controlSelected` state under it — with a second slab of "control"
			local washOn = itemScope:own(core:memo(function(use)
				if use(verdict) ~= nil then
					return true
				end
				if landedWash ~= nil and use(landedKey) == key and use(landedWash) > 0.01 then
					return true
				end
				local payload = use(armedPayload)
				if payload ~= nil and not acceptsFor(key)(payload) then
					return true
				end
				return false
			end))
			local strokeData = itemScope:own(core:memo(function(use)
				local state = use(verdict)
				if state == "legal" then
					return UI.strokeData({ thickness = 2, color = "accent" })
				elseif state == "illegal" then
					return UI.strokeData({ thickness = 2, color = "danger" })
				end
				return nil
			end))
			-- the §4.2 VERDICT GLYPH SLOT: a second channel, never colour alone. The
			-- refusal reads as a blocked mark rather than a slash (review R2-F16).
			local glyph = itemScope:own(core:memo(function(use)
				local state = use(verdict)
				return if state == "legal" then "+" elseif state == "illegal" then "×" else ""
			end))

			-- ONE PLATE PER ROW (director round three): the full-row hit Button IS
			-- the row's surface — a second `control` plate here, inset by a margin,
			-- was the "text on a darker band over a lighter row" artifact, and it
			-- painted over the hit's native selected state
			return UI.ZStack({
				id = "Card",
				stroke = strokeData,
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.When({
						id = "WashWhen",
						condition = washOn,
						thenView = function()
							return UI.Box({
								id = "Wash",
								tint = verdictTint,
								width = { type = "fill", weight = 1 },
								height = { type = "fill", weight = 1 },
							})
						end,
					}),
					UI.HStack({
						id = "Row",
						padding = "s",
						gap = "s",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.Text({ id = "Name", text = item.name, textSize = "body" }),
							UI.Spacer({ id = "Gap" }),
							UI.Text({
								id = "VerdictGlyph",
								text = glyph,
								textSize = "body",
								textAlign = "center",
								width = ICON,
								height = ICON,
							}),
						},
					}),
				},
			})
		end

		list = Facet.Controls.VirtualList(core, {
			id = "Rows",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = rowHeight,
			viewportHeight = viewportHeight,
			overscan = 2,
			selection = "single",
			rowDropTarget = function(item: any)
				local key = item.id
				return {
					accepts = acceptsFor(key),
					onDrop = function(payload: any, info: any)
						table.insert(drops, { key = key, card = payload.card, index = info.index })
						verdictLine:set(`verdict: {payload.card} landed on {key}`)
						washRow(key)
						note("drop", { key = key, card = payload.card })
					end,
				}
			end,
			onActivate = function(item: any, _meta: any)
				-- THE NON-POINTER COMMIT (§5.5): Activate on a target aims the live
				-- session at it and commits — the same session, the same legality.
				local reg = registry()
				if reg ~= nil and reg.isActive() then
					reg.armTo(rowHit(item.id))
					reg.commit()
					note("nonpointer:commit", { key = item.id })
				end
			end,
			cell = cell,
		})

		-- ===== the §5.5 arm presentation ====================================
		-- THE FOCUS HANDOFF, THROUGH PUBLIC SEAMS ONLY. Arming with a gamepad has to
		-- put the player where the decision is — on the first row that would ACCEPT
		-- the card — or the affordance is a proxy floating over a focus ring that
		-- never moved. `list.focusKey` scrolls the row into the window (keep-visible)
		-- and `pres.focus.focusOn` moves the surface's own focus; both are asked
		-- because they are two jobs. `beginInteraction` is the SF-L3 exemption: the
		-- row the live session is aiming at keeps its focusability even if the game's
		-- predicate turns against it mid-gesture.
		local function firstEligibleRow(payload: any): string?
			for _, item in rows:get() :: { any } do
				local ok = acceptsFor(item.id)(payload)
				if ok then
					return item.id
				end
			end
			return nil
		end

		function armPresent(source: string, payload: any)
			armedSource:set(source)
			armedPayload:set(payload)
			local key = firstEligibleRow(payload)
			local focusBefore = pres.focus.focused:get()
			local landed: string? = nil
			if key ~= nil then
				list.focusKey(key)
				local path = rowHit(key)
				if pres.focus.focusOn(path) then
					landed = path
					pres.focus.beginInteraction(path)
					armExemption = path
				end
			end
			table.insert(
				armFocus,
				{ at = elapsed, how = "arm", source = source, before = focusBefore, focused = landed }
			)
			note("nonpointer:armPresented", { source = source, target = landed, firstEligible = key })
		end

		function armRelease(how: string)
			if armedSource:get() == nil then
				return
			end
			local source = armedSource:get()
			armedSource:set(nil)
			armedPayload:set(nil)
			if armExemption ~= nil then
				-- close only what this fixture opened: `endInteraction` holds ONE
				-- exemption for the whole graph, and clearing someone else's would be
				-- the fixture reaching past its own gesture
				pres.focus.endInteraction()
				armExemption = nil
			end
			-- focus goes home to the card it came from: a terminal that leaves the
			-- ring inside a list the player is no longer acting on is a lost player
			local returned = if source ~= nil and pres.focus.focusOn(source) then source else nil
			table.insert(armFocus, { at = elapsed, how = how, source = source, focused = returned })
			note("nonpointer:armReleased", { how = how, source = source, focused = returned })
		end

		-- ===== the hand =====================================================
		-- COMMIT STYLE (director fix round, RR parity): the shipped Sponsor feel is
		-- NO commit flight — the card vanishes at the drop point and the ROW washes
		-- (RascalRally SponsorGesture:_endDrag + celebration:rowWash). That is the
		-- default here. Card B alone keeps `flyToTarget`, because the live-target
		-- commit chase is its own acceptance row (SF-M2) and stays demonstrable.
		local function card(id: string, letter: string, label: string, commitStyle: string?)
			local path = `{HAND}/{id}`
			-- THE ARMED SOURCE STATE (§5.5, review R2-F4) on the framework's own
			-- selection channel: `selected` rides a style tag the theme paints, so a
			-- gamepad player can see which card is up without the fixture inventing a
			-- fill. Multi-channel by construction — the proxy is the second channel.
			local armed = scope:own(core:memo(function(use)
				return use(armedSource) == path
			end))
			return UI.draggable(
				UI.corners(
					UI.Button({
						id = id,
						-- the slot EMPTIES while its card is held — that is the
						-- framework's `dragHeld` guarantee (registry -> renderer ->
						-- `facet-drag-held` rule), NOT fixture code: proof by absence
						label = label,
						compactLabel = letter,
						selected = armed,
						width = { type = "fill", weight = 1 },
						height = { type = "minMax", min = "targetSizes.minimum" },
						onActivate = function(_path: string, meta: any?)
							activations:set(activations:get() + 1)
							local reg = registry()
							if reg == nil then
								return
							end
							if reg.isActive() then
								-- A on the hand while a card is armed = PUT IT BACK
								-- (RR: drag-back-onto-the-hand semantics): aim at the
								-- hand and commit — the hand target's onDrop returns it
								if reg.mode() == "armed" then
									reg.armTo(path)
									reg.commit()
									note("nonpointer:putBack", { card = letter })
								end
								return
							end
							-- ARM ON ACTIVATE IS THE NON-POINTER PATH ONLY (§5.5). A tap
							-- under the promotion gate must stay a plain tap — arming on
							-- every activation would turn the "taps are never eaten"
							-- proof into a session, which is the opposite of SF-D3.
							if meta == nil or meta.source ~= "action" then
								return
							end
							reg.arm(`{HAND}/{id}`)
							note("nonpointer:arm", { card = letter })
						end,
					}),
					"control"
				),
				{
					payload = { kind = "sponsor-card", card = letter },
					dragMotion = "object",
					onCommitProxy = commitStyle,
					-- TAP IS THE PICKUP (director round six): tap a card, scroll the
					-- list freely with a pan (a swipe is past the tap threshold so it
					-- can never read as a drop), tap a row to place it — the armed
					-- paradigm on touch. Drag still works: press-and-slide promotes.
					armOnTap = true,
					-- THE GHOST IS THE CARD (director round two: the default
					-- anonymous plate read as "a drop target appeared", not as
					-- "Card C is in my hand"). A display composite — the card's
					-- own label on the same raised plate a real game ghost wears.
					proxy = function()
						return UI.ZStack({
							id = "GhostCard",
							width = { type = "fill", weight = 1 },
							height = { type = "fill", weight = 1 },
							children = {
								UI.shadow(
									UI.corners(
										UI.Box({
											id = "GhostPlate",
											surface = "raised",
											width = { type = "fill", weight = 1 },
											height = { type = "fill", weight = 1 },
										}),
										"control"
									),
									"overlay"
								),
								UI.Text({
									id = "GhostLabel",
									text = label,
									alignH = "center",
									alignV = "center",
								}),
							},
						})
					end,
				}
			)
		end

		local hand = UI.dropTarget(
			UI.corners(
				UI.HStack({
					id = "Hand",
					surface = "raised",
					gap = "s",
					padding = "s",
					width = { type = "fill", weight = 1 },
					children = {
						card("CardA", "A", "Card A"),
						card("CardB", "B", "Card B", "flyToTarget"),
						card("CardC", "C", "Card C"),
					},
				}),
				"panel"
			),
			{
				-- TOUCH HAS NO CANCEL KEY (I-7): the hand itself always reads as a
				-- legal "put it back" target while a card is up, which is the visible
				-- cancel affordance for a finger.
				accepts = function(payload: any): (boolean, string?)
					return type(payload) == "table" and payload.kind == "sponsor-card", "demo-blocked-3"
				end,
				onDrop = function(payload: any, _info: any)
					returnedHome:set(returnedHome:get() + 1)
					verdictLine:set(`verdict: {payload.card} returned to the hand`)
					note("returned", { card = payload.card })
				end,
			}
		)

		-- ===== chevrons (the autoscroll affordance, neutral channel only) =====
		-- A DECLARED FADE GROUP, because the affordance's whole vocabulary is
		-- opacity (hidden / 40% armed / 100% active + pulse) and the presentation
		-- channel fades a group, never a node's own paint.
		local function chevron(id: string, anchor: string, glyph: string)
			return UI.ZStack({
				id = id,
				canvasGroup = true,
				anchor = anchor,
				offsetX = 0,
				offsetY = if anchor == "top" then 4 else -4,
				width = CHEV_ICON,
				height = CHEV_ICON,
				children = {
					UI.Text({
						id = "Glyph",
						text = glyph,
						textSize = "caption",
						textAlign = "center",
						role = "secondary",
						width = { type = "fill", weight = 1 },
					}),
				},
			})
		end

		local screen = UI.Screen({
			id = "DropLab",
			padding = "m",
			gap = "s",
			children = {
				UI.Text({ id = "Title", text = "Drop lab", textSize = "heading" }),
				UI.Text({ id = "VerdictLine", text = verdictLine, textSize = "caption", role = "secondary" }),
				-- ONE tree, two intents: portrait docks the hand under the list (thumb
				-- zone), landscape puts it in a side column. It is one child ORDER
				-- either way, because a structural swap would remount both halves.
				UI.AdaptiveStack({
					id = "Main",
					axis = conditions.axis,
					gap = "s",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.ZStack({
							id = "ListZone",
							width = { type = "fill", weight = 1 },
							children = {
								list.blueprint,
								UI.Anchor({
									id = "Chevrons",
									width = { type = "fill", weight = 1 },
									height = { type = "fill", weight = 1 },
									children = {
										chevron("ChevTop", "top", "^"),
										chevron("ChevBottom", "bottom", "v"),
									},
								}),
							},
						}),
						hand,
					},
				}),
			},
		})

		-- ===== registry plumbing ============================================
		local unbindScroll: any = nil
		local unbindCancel: any = nil
		local unbindVerdict: any = nil
		local autoscrollDefaults = Facet.newAutoscroll():options()

		local function ensureWired()
			local ctrl = controller()
			if ctrl == nil then
				return
			end
			if unbindScroll == nil then
				unbindScroll = list.bindNativeScroll(ctrl)
			end
			if unbindVerdict == nil then
				local reg = ctrl.dragRegistry()
				registryVerdict:set(reg.verdict:get())
				unbindVerdict = core:observe(reg.verdict, function(v: any)
					registryVerdict:set(v)
				end)
			end
			if unbindCancel == nil and result.handle ~= nil and result.handle.actions ~= nil then
				-- THE CANCEL AFFORDANCE for keyboard and gamepad (§5.5): the presenter
				-- offers Cancel to the surface, and a surface that owns a live drag
				-- session cancels it. Consumer wiring, one line, public seam.
				unbindCancel = result.handle.actions.cancel.onPressed(function()
					local reg = registry()
					if reg ~= nil and reg.isActive() then
						reg.cancel("cancel-action")
						note("cancel:action")
					end
				end)
			end
		end

		-- the chevrons' PRESENTED transparency, ramped toward the state's target so
		-- the affordance crossfades instead of hard-cutting (§4.5's 120 ms). Both
		-- start hidden, which is what an idle list owes the player.
		local CHEV_FADE_S = 0.12
		local chevFade: { [string]: number } = { top = 1, bottom = 1 }

		local function sessionMark()
			local reg = registry()
			if reg == nil then
				return
			end
			local session = reg.session()
			if session ~= nil then
				local id = tostring(session)
				if sessionIds[#sessionIds] ~= id then
					table.insert(sessionIds, id)
				end
			end
		end

		scope:own(pres.onTick(function(dt: number)
			elapsed += dt
			ensureWired()
			local ctrl = controller()
			if ctrl == nil then
				return
			end
			-- EDGE AUTOSCROLL is wired but not self-driving: one call per frame, on
			-- the presenter's own tick, exactly as the list documents. It applies the
			-- scroll and re-runs the drop hit-test in the SAME frame.
			local step = list.stepAutoscroll(elapsed)
			local reg = registry()
			if step ~= nil and reg ~= nil and #autoscrollTrace < 600 then
				local v: any = reg.verdict:get()
				table.insert(autoscrollTrace, {
					at = elapsed,
					state = step.state,
					band = list.autoscroll:get().band,
					delta = step.delta,
					justArmed = step.justArmed,
					scrollTop = list.scrollTop:get(),
					overId = if v ~= nil then v.overId else nil,
					legal = if v ~= nil then v.legal else nil,
					reason = if v ~= nil then v.reason else nil,
				})
			end
			-- the affordance: hidden / armed (40%) / active (100% + a slow pulse),
			-- through the presentation channel's transparency — the neutral channel
			-- only, never a verdict hue.
			--
			-- HIDDEN AT A CLAMPED END (review R2-F8). The model deliberately stays
			-- ARMED when the canvas has nowhere left to go — correct for the scroll
			-- mechanism, because the player is still pushing — so the affordance,
			-- which is the fixture's to own, asks the question the affordance is
			-- actually about: can this edge still move? A chevron pulsing at 100 %
			-- against an edge that cannot scroll is the honest-affordance rule
			-- inverted at exactly the moment it matters. The range comes off the
			-- list's own dump (position vs the canvas end), never a private field.
			local dump = list.dump()
			local maxScroll = math.max(0, dump.totalRows * dump.rowHeight - dump.viewportHeight)
			local atEnd = { top = dump.scrollTop <= 0.5, bottom = dump.scrollTop >= maxScroll - 0.5 }
			local state = list.autoscroll:get()
			local reduced = env:get("motionPolicy"):get() == "reduced"
			local function targetFor(edge: string): number
				if state.band ~= edge or atEnd[edge] then
					return 1 -- hidden
				end
				if state.state == "active" then
					return if reduced then 0 else 0.15 * (0.5 + 0.5 * math.sin(elapsed * 2 * math.pi * 0.8))
				elseif state.state == "dwelling" or state.state == "exiting" then
					return 0.6 -- armed
				end
				return 1
			end
			-- ...AND IT FADES (review R2-F8): 120 ms between states, ramped on the
			-- presenter's own tick. A duration is not a spring, so this is not a
			-- motion class — the classes are all springs and none of them is "exactly
			-- 120 ms" — but it IS motion, so reduced motion takes the cut instead.
			local function fadeTo(edge: string, target: number): number
				local current = chevFade[edge]
				if reduced then
					chevFade[edge] = target
					return target
				end
				local most = dt / CHEV_FADE_S
				chevFade[edge] = current + math.clamp(target - current, -most, most)
				return chevFade[edge]
			end
			ctrl.setPresentationTransparency(CHEV_TOP, fadeTo("top", targetFor("top")))
			ctrl.setPresentationTransparency(CHEV_BOTTOM, fadeTo("bottom", targetFor("bottom")))
		end))

		-- ===== synthetic pointer helpers (labeled) ==========================
		local function centerOf(path: string): (number?, number?)
			local ctrl = controller()
			if ctrl == nil then
				return nil, nil
			end
			local rect = if ctrl.screenRectOf ~= nil then ctrl.screenRectOf(path) else ctrl.rectOf(path)
			if rect == nil then
				return nil, nil
			end
			return rect.x + rect.w / 2, rect.y + rect.h / 2
		end

		local function recordAim(label: string, paths: { string })
			local ctrl = controller()
			local entry: any = { label = label, rects = {}, synthetic = true }
			if ctrl ~= nil then
				for _, path in paths do
					local rect = if ctrl.screenRectOf ~= nil then ctrl.screenRectOf(path) else ctrl.rectOf(path)
					entry.rects[path] = rect
				end
			end
			table.insert(aim, entry)
			return entry
		end

		local function pressCard(cardPath: string, pointerType: string): (number, number)
			local x, y = centerOf(cardPath)
			local reg = registry()
			if reg ~= nil and x ~= nil and y ~= nil then
				reg.pointerDown(cardPath, { x = x, y = y, pointerType = pointerType })
			end
			return x or 0, y or 0
		end

		local function moveCard(cardPath: string, x: number, y: number, pointerType: string)
			local reg = registry()
			if reg ~= nil then
				reg.pointerMove(cardPath, { x = x, y = y, pointerType = pointerType })
				sessionMark()
			end
		end

		local function releaseCard(cardPath: string, x: number, y: number, pointerType: string)
			local reg = registry()
			if reg ~= nil then
				reg.pointerUp(cardPath, { x = x, y = y, pointerType = pointerType })
			end
		end

		local function verdictNow(): any
			local reg = registry()
			if reg == nil then
				return nil
			end
			local v: any = reg.verdict:get()
			return if v == nil
				then nil
				else { targetId = v.targetId, overId = v.overId, legal = v.legal, reason = v.reason, mode = v.mode }
		end

		local function dragTo(cardPath: string, targetPath: string, pointerType: string): any
			ensureWired()
			pressCard(cardPath, pointerType)
			local tx, ty = centerOf(targetPath)
			-- one over-threshold move promotes, the second lands the pointer on the
			-- target (the promotion frame is its own event, and a fixture that jumped
			-- straight to the target would never see it)
			local sx, sy = centerOf(cardPath)
			moveCard(cardPath, (sx or 0) + 20, (sy or 0) + 20, pointerType)
			moveCard(cardPath, tx or 0, ty or 0, pointerType)
			return { x = tx, y = ty }
		end

		-- ===== the churn schedule ===========================================
		local plan: { { at: number, run: () -> () } } = {}
		local function schedule(delay: number, run: () -> ())
			table.insert(plan, { at = elapsed + delay, run = run })
		end
		scope:own(pres.onTick(function(_dt: number)
			if #plan == 0 then
				return
			end
			local remaining: { any } = {}
			local due: { () -> () } = {}
			for _, entry in plan do
				if entry.at <= elapsed then
					table.insert(due, entry.run)
				else
					table.insert(remaining, entry)
				end
			end
			plan = remaining
			for _, fn in due do
				fn()
			end
		end))

		local function churnOnce()
			local current = rows:get() :: { any }
			local next: { any } = {}
			for i = 2, #current do
				table.insert(next, current[i])
			end
			table.insert(next, current[1])
			rows:set(next)
		end

		result.screen = screen
		result.present = {}
		result.steps = {
			-- SF-D3: a release under the promotion gate is a TAP. The aim rects and
			-- the expectation are recorded for the live VirtualInput replay; the
			-- state-level equivalent runs here through the same registry seam the
			-- engine's detector funnels into.
			pressUnderThreshold = function()
				ensureWired()
				local cardPath = `{HAND}/CardA`
				local entry = recordAim("pressUnderThreshold", { cardPath })
				local x, y = pressCard(cardPath, "mouse")
				moveCard(cardPath, x + 4, y + 2, "mouse") -- 4.47 px < the 6 px pointer gate
				local activeMidGesture = registry() ~= nil and registry().isActive()
				releaseCard(cardPath, x + 4, y + 2, "mouse")
				local expectation = {
					step = "pressUnderThreshold",
					travelPx = 4.47,
					gatePx = Facet.interactionTokens.dragPromotionPx.pointer,
					expectSession = false,
					expectActivate = 1,
					observedSession = activeMidGesture,
					note = "synthetic pointer at the registry seam; the live VirtualInput drive replays the same rects",
				}
				table.insert(expectations, expectation)
				entry.expected = expectation
				note("pressUnderThreshold", expectation)
				return expectation
			end,
			-- SF-D1/SF-P4: promotion, the pickup event, and the proxy above every
			-- transient (a toast is summoned mid-drag on purpose)
			promoteAndHover = function()
				ensureWired()
				local cardPath = `{HAND}/CardA`
				local target = rowHit("row-02")
				recordAim("promoteAndHover", { cardPath, target })
				dragTo(cardPath, target, "mouse")
				pres.presentToast(
					UI.VStack({
						id = "Body",
						children = { UI.Text({ id = "Line", text = "Toast during drag", textSize = "body" }) },
					}),
					{ key = "drag-layer", duration = 6 }
				)
				local reg = registry()
				return {
					active = reg ~= nil and reg.isActive(),
					mode = if reg ~= nil then reg.mode() else nil,
					verdict = verdictNow(),
					-- WHAT A CONSUMER CAN ACTUALLY READ about layering: this surface's
					-- own display order, and the proxy layer's path. The framework's
					-- band table is presenter-module-private (package finding P5-F3), so
					-- the ordering itself is asserted from the render target's display
					-- orders rather than from a number the fixture cannot see.
					surfaceDisplayOrder = result.handle.displayOrder,
					proxyLayerPath = PROXY_LAYER,
					proxyMounted = if ctx.instanceAt ~= nil then ctx.instanceAt(PROXY_LAYER) ~= nil else nil,
				}
			end,
			-- SF-D1 + SF-M2: a legal drop commits on the causal frame and the proxy
			-- flies to the LIVE row — Card B is the fixture's flyToTarget card
			legalDrop = function()
				ensureWired()
				local cardPath = `{HAND}/CardB`
				local target = rowHit("row-02")
				recordAim("legalDrop", { cardPath, target })
				local pos = dragTo(cardPath, target, "mouse")
				local before = verdictNow()
				releaseCard(cardPath, pos.x or 0, pos.y or 0, "mouse")
				note("legalDrop", { verdict = before })
				return { verdictWhileHovering = before, drops = #drops, active = registry().isActive() }
			end,
			-- RR-DEFAULT COMMIT (director fix round): Card A has NO commit flight —
			-- the ghost vanishes on the release frame, `land` fires immediately, and
			-- the landed row carries a decay-class wash (the shipped rowWash beat)
			legalDropInstant = function()
				ensureWired()
				local cardPath = `{HAND}/CardA`
				local target = rowHit("row-02")
				recordAim("legalDropInstant", { cardPath, target })
				local pos = dragTo(cardPath, target, "mouse")
				local before = verdictNow()
				releaseCard(cardPath, pos.x or 0, pos.y or 0, "mouse")
				note("legalDropInstant", { verdict = before })
				return {
					verdictWhileHovering = before,
					drops = #drops,
					active = registry().isActive(),
					landedKey = landedKey:get(),
					washNow = if landedWash ~= nil then landedWash:get() else nil,
				}
			end,
			-- SF-D5: an illegal drop rejects exactly once with the fixture's reason
			-- code, and the return flight is velocity-seeded because the gesture was
			illegalDrop = function()
				ensureWired()
				local cardPath = `{HAND}/CardC`
				local target = rowHit("row-02") -- even row: refuses C with demo-blocked-1
				recordAim("illegalDrop", { cardPath, target })
				local pos = dragTo(cardPath, target, "mouse")
				local before = verdictNow()
				-- a real toss: the last samples carry speed into the return flight
				moveCard(cardPath, (pos.x or 0) + 24, (pos.y or 0) + 12, "mouse")
				releaseCard(cardPath, (pos.x or 0) + 24, (pos.y or 0) + 12, "mouse")
				note("illegalDrop", { verdict = before })
				return { verdictWhileHovering = before, rejects = #rejects }
			end,
			-- SF-L2: drive the pointer into each band and hold. Dwell, ramp, clamp
			-- and the per-frame verdict all land in `autoscrollTrace`.
			autoscrollDrive = function()
				ensureWired()
				autoscrollTrace = {}
				local cardPath = `{HAND}/CardA`
				local ctrl = controller()
				local host = if ctrl ~= nil then ctrl.screenRectOf(LIST) else nil
				recordAim("autoscrollDrive", { cardPath, LIST })
				if host == nil then
					return { skipped = "list not mounted" }
				end
				pressCard(cardPath, "mouse")
				local sx, sy = centerOf(cardPath)
				moveCard(cardPath, (sx or 0) + 20, (sy or 0) + 20, "mouse")
				-- into the BOTTOM band (the pointer point, never the proxy's bounds)
				moveCard(cardPath, host.x + host.w / 2, host.y + host.h - 8, "mouse")
				note("autoscroll:bottomBand")
				-- ...then the top band, then release, on the presenter's own clock
				schedule(1.2, function()
					moveCard(cardPath, host.x + host.w / 2, host.y + 8, "mouse")
					note("autoscroll:topBand")
				end)
				schedule(2.4, function()
					local reg = registry()
					if reg ~= nil and reg.isActive() then
						reg.cancel("autoscroll-end")
					end
					note("autoscroll:end", { samples = #autoscrollTrace })
				end)
				return { pending = true, host = host, bands = autoscrollDefaults }
			end,
			-- the honest affordance: short content cannot scroll, so nothing arms
			-- and no chevron shows
			shortContent = function()
				ensureWired()
				rows:set(makeRows(SHORT_COUNT))
				pres.refresh()
				autoscrollTrace = {}
				local cardPath = `{HAND}/CardA`
				local ctrl = controller()
				local host = if ctrl ~= nil then ctrl.screenRectOf(LIST) else nil
				if host == nil then
					return { skipped = "list not mounted" }
				end
				pressCard(cardPath, "mouse")
				local sx, sy = centerOf(cardPath)
				moveCard(cardPath, (sx or 0) + 20, (sy or 0) + 20, "mouse")
				moveCard(cardPath, host.x + host.w / 2, host.y + host.h - 8, "mouse")
				schedule(1.0, function()
					local reg = registry()
					if reg ~= nil and reg.isActive() then
						reg.cancel("short-content-end")
					end
					note("shortContent:end", { samples = #autoscrollTrace, state = list.autoscroll:get() })
				end)
				return { rows = SHORT_COUNT, pending = true }
			end,
			restoreRows = function()
				rows:set(makeRows(FULL_COUNT))
				return { rows = FULL_COUNT }
			end,
			-- SF-L1/SF-L3 under a live session: a 250 ms re-sort must retarget the
			-- hover verdict on the same frame and leave the hovered row focusable
			churnWhileDragging = function()
				ensureWired()
				local cardPath = `{HAND}/CardA`
				local target = rowHit("row-04")
				recordAim("churnWhileDragging", { cardPath, target })
				dragTo(cardPath, target, "mouse")
				local before = verdictNow()
				churnOnce()
				pres.refresh()
				local reg = registry()
				if reg ~= nil then
					reg.refreshTargets()
				end
				local after = verdictNow()
				note("churnWhileDragging", { before = before, after = after })
				return { before = before, after = after, sameFrame = true, order = (rows:get() :: any)[1].id }
			end,
			-- SF-D4: arm -> navigate -> commit, and arm -> navigate -> cancel, both
			-- through ONE session object and one legality model
			nonPointerFlow = function()
				ensureWired()
				local reg = registry()
				if reg == nil then
					return { skipped = "no registry" }
				end
				sessionIds = {}
				armFocus = {}
				local cardPath = `{HAND}/CardA`
				-- the §5.5 PRESENTATION is what this evidence is about: where focus
				-- was before the arm, where the arm put it, and where the terminal
				-- returned it (review R2-F4)
				pres.focus.focusOn(cardPath)
				local focusBefore = pres.focus.focused:get()
				reg.arm(cardPath)
				sessionMark()
				local armedSession = tostring(reg.session())
				local focusDuring = pres.focus.focused:get()
				local armedSourceDuring = armedSource:get()
				reg.armTo(rowHit("row-02")) -- legal for A
				local hovering = verdictNow()
				reg.armTo(rowHit("row-03")) -- odd: refuses A
				local illegalHover = verdictNow()
				reg.armTo(rowHit("row-02"))
				local committed = reg.commit()
				local dropsAfterCommit = #drops
				local focusAfterCommit = pres.focus.focused:get()
				local armedSourceAfterCommit = armedSource:get()

				reg.arm(cardPath)
				sessionMark()
				local secondSession = tostring(reg.session())
				local focusDuringSecond = pres.focus.focused:get()
				reg.armTo(rowHit("row-04"))
				local cancelled = reg.cancel("nonpointer-cancel")
				local focusAfterCancel = pres.focus.focused:get()
				note("nonPointerFlow", { hovering = hovering, illegalHover = illegalHover })
				return {
					armedSession = armedSession,
					secondSession = secondSession,
					sameSessionThroughFlow = sessionIds,
					hovering = hovering,
					illegalHover = illegalHover,
					committed = committed,
					cancelled = cancelled,
					dropsAfterCommit = dropsAfterCommit,
					-- the presentation half (§5.5): armed source + focus handoff
					focusBefore = focusBefore,
					focusDuring = focusDuring,
					focusDuringSecond = focusDuringSecond,
					focusAfter = focusAfterCommit,
					focusAfterCancel = focusAfterCancel,
					armedSourceDuring = armedSourceDuring,
					armedSourceAfter = armedSourceAfterCommit,
					armFocus = armFocus,
					synthetic = "navigation is the registry's armTo; physical gamepad stays pending",
				}
			end,
			-- I-7: three cancel affordances, one trace shape
			cancelPaths = function()
				ensureWired()
				local cardPath = `{HAND}/CardA`
				local ctrl = controller()
				local out: { any } = {}

				-- (1) pointer release over free area
				local screenRect = if ctrl ~= nil then ctrl.screenRectOf(SCREEN) else nil
				local freeX = if screenRect ~= nil then screenRect.x + screenRect.w - 2 else 0
				local freeY = if screenRect ~= nil then screenRect.y + 2 else 0
				pressCard(cardPath, "mouse")
				local sx, sy = centerOf(cardPath)
				moveCard(cardPath, (sx or 0) + 20, (sy or 0) + 20, "mouse")
				moveCard(cardPath, freeX, freeY, "mouse")
				releaseCard(cardPath, freeX, freeY, "mouse")
				table.insert(out, { path = "pointer-free-area", active = registry().isActive() })

				-- (2) touch release over the source (the hand's "put it back" target)
				pressCard(cardPath, "touch")
				local tx, ty = centerOf(cardPath)
				moveCard(cardPath, (tx or 0) + 30, (ty or 0) + 30, "touch") -- past the 14 px touch gate
				local handX, handY = centerOf(HAND)
				moveCard(cardPath, handX or 0, handY or 0, "touch")
				releaseCard(cardPath, handX or 0, handY or 0, "touch")
				table.insert(out, {
					path = "touch-release-over-source",
					active = registry().isActive(),
					returned = returnedHome:get(),
				})

				-- (3) the Cancel action, through the presenter's own action
				pressCard(cardPath, "mouse")
				local cx, cy = centerOf(cardPath)
				moveCard(cardPath, (cx or 0) + 20, (cy or 0) + 20, "mouse")
				local handle = result.handle
				local binding = handle.actions.cancel.bind({ scriptable = true })
				binding.fire(true)
				binding.fire(false)
				binding.remove()
				table.insert(out, { path = "cancel-action", active = registry().isActive() })
				note("cancelPaths", out)
				return { paths = out }
			end,
			-- finding F7, end to end: a modal presenting mid-session cancels it
			modalCancelsDrag = function()
				ensureWired()
				local cardPath = `{HAND}/CardA`
				pressCard(cardPath, "mouse")
				local sx, sy = centerOf(cardPath)
				moveCard(cardPath, (sx or 0) + 20, (sy or 0) + 20, "mouse")
				local activeBefore = registry().isActive()
				local modal = pres.presentModal(UI.Screen({
					id = "MidDragModal",
					children = { UI.Button({ id = "Ok", label = "Ok", onActivate = function() end }) },
				}))
				local activeAfter = registry().isActive()
				pres.dismiss(modal)
				note("modalCancelsDrag", { before = activeBefore, after = activeAfter })
				return { activeBefore = activeBefore, activeAfter = activeAfter }
			end,
		}
		result.report = function()
			local reg = registry()
			local window: { string } = {}
			for key in list.debugWindow() do
				table.insert(window, key)
			end
			table.sort(window)
			return {
				ledger = "SF-D1/D2/D3/D4/D5, SF-L2, SF-P4, SF-M2",
				elapsed = elapsed,
				trace = trace,
				aim = aim,
				expectations = expectations,
				autoscrollTrace = autoscrollTrace,
				autoscroll = list.autoscroll:get(),
				autoscrollOptions = autoscrollDefaults,
				promotionTokens = Facet.interactionTokens.dragPromotionPx,
				promotionRange = Facet.interactionTokens.dragPromotionRangePx,
				drops = drops,
				rejects = rejects,
				sessionIds = sessionIds,
				returnedHome = returnedHome:get(),
				activations = activations:get(),
				verdict = verdictNow(),
				registry = if reg ~= nil then reg.dump() else nil,
				surfaceDisplayOrder = if result.handle ~= nil then result.handle.displayOrder else nil,
				proxyLayerPath = PROXY_LAYER,
				window = window,
				rowHeight = rowHeight:get(),
				viewportHeight = viewportHeight:get(),
				armedSource = armedSource:get(),
				armFocus = armFocus,
				chevronFade = { top = chevFade.top, bottom = chevFade.bottom, seconds = CHEV_FADE_S },
				scrollTop = list.scrollTop:get(),
				scrollPath = list.scrollPath(),
				order = (function()
					local out: { string } = {}
					for _, item in rows:get() :: { any } do
						table.insert(out, item.id)
					end
					return out
				end)(),
				focusPath = pres.focus.focused:get(),
				reducedMotion = env:get("reducedMotion"):get(),
				motion = { active = clock:activeCount(), stats = clock:stats() },
				counters = core:counters(),
				coreError = core:lastError(),
			}
		end
		result.dispose = function()
			local reg = registry()
			if reg ~= nil and reg.isActive() then
				reg.cancel("dispose")
			end
			if unbindVerdict ~= nil then
				unbindVerdict()
				unbindVerdict = nil
			end
			if unbindCancel ~= nil then
				unbindCancel()
				unbindCancel = nil
			end
			if unbindScroll ~= nil then
				unbindScroll()
				unbindScroll = nil
			end
			list.dispose()
			scope:dispose()
		end
		return result
	end,
}
