--!strict
-- Scenario 'sponsor_list' (ledger rows SF-L1, SF-L3, SF-P1, SF-P3;
-- ui-designer-spec §8.3): the UNIFIED COLLECTION under churn — one construct
-- that windows, selects, reorders and skips ineligible rows, with the continuous
-- wash (SF-P1) and the authored stroke pulse (SF-P3) riding real rows.
--
-- THE ROW HEIGHT IS DERIVED, NEVER TYPED. It comes from the theme snapshot and
-- the live text facts (typography scale + preferred-text offset), which is the
-- lesson a px height fixed against unfixed content taught: the detail line is
-- `lineLimit`-capped at 2 so growth stays uniform per list (finding F13), and the
-- height re-derives on a theme swap because `itemExtent` accepts a Readable. The
-- derivation reads every token the `Card`/`Labels` arrangement itself spends
-- (the label VStack's inter-line gap, the card's own padding AND its own
-- margin) rather than a second, approximate copy of them — the overflow sweep
-- caught the row 11px short on every mounted row because the old formula
-- counted the padding but not the gap or the margin: the arrangement and the
-- height are ONE decision, and the solver already said so.
--
-- THE SCREEN BODY SCROLLS. Title + controls + the (already viewport-sized)
-- list + the inspect line can still sum taller than a short landscape phone
-- offers, so they live inside a `UI.ScrollView` (`Body`) rather than directly
-- under the screen — the same BodyScroll shape `adaptive_controls.luau` uses.
--
-- STATE FILL AND CONTINUOUS WASH ARE DIFFERENT NODES ON PURPOSE. A tinted Box
-- claims its fill for the instance's lifetime, so painting the row's card with
-- `tint` would take the state channel away from the theme. The card carries the
-- state (surface + stroke + content role + the leading edge bar), and the wash is
-- its own trailing bar — which is exactly the row hierarchy §8.3 declares.
--
-- SELECTION IS THE LIST'S OWN NATIVE STATE (review R2-F6). The construct declares
-- `selected` on the row hit under the card, so the theme paints the chosen row
-- (`controlSelected`); this fixture adds the FORM channels a player reads at a
-- glance — the accent edge bar and the hairline stroke — and never spends an
-- ELEVATION role on an interaction state.

return {
	title = "Collection lab (SF-L1/L3/P1/P3)",
	ledgerRows = { "SF-L1", "SF-L3", "SF-P1", "SF-P3", "SF-F1", "SF-C1", "SF-C2", "SF-C3" },
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local env = ctx.env
		local pres = ctx.presenter
		local scope = core:scope("sponsor-list")
		local clock = pres.motionClock

		local SCREEN = "/ListLab"
		-- the screen body scrolls (below, `Body`) so `Rows` sits one level deeper
		-- than the screen itself
		local LIST = SCREEN .. "/Body/Rows"

		local trace: { any } = {}
		local elapsed = 0
		local function note(kind: string, info: any?)
			table.insert(trace, { at = elapsed, kind = kind, info = info })
		end
		scope:own(pres.onFeedback(function(event: any)
			table.insert(trace, {
				at = elapsed,
				kind = "feedback:" .. tostring(event.type),
				info = { path = event.path, reason = event.reason, context = event.context },
			})
		end))

		-- ===== data (placeholder-neutral, §8's content rule) =================
		local ROW_COUNT = 20
		local function makeRows(): { any }
			local rows = {}
			for i = 1, ROW_COUNT do
				local id = string.format("row-%02d", i)
				table.insert(rows, {
					id = id,
					name = string.format("Row %02d", i),
					detail = "Secondary line, long enough to wrap at the largest text offset",
				})
			end
			return rows
		end
		local rows = scope:own(core:signal(makeRows()))
		local churning = scope:own(core:signal(false))
		local mixedEligibility = scope:own(core:signal(false))
		-- rows the fixture has blocked BY HAND (the exemption step flips one while
		-- it is armed); separate from the every-third pattern so the two reasons a
		-- row can be ineligible never get confused in the trace
		local blocked = scope:own(core:signal({} :: { [string]: boolean }))
		local inspect = scope:own(core:signal("inspect: (nothing yet)"))
		local pulseKey = scope:own(core:signal(nil :: string?))

		local sweep = scope:own(clock:spring(0, "decay"))
		local pulse = scope:own(clock:spring(0, "decay"))

		local remountCounts: { [string]: number } = {}
		local navigationSweep: { any } = {}

		local function indexOfKey(key: string): number
			return tonumber(string.match(key, "%d+") or "0") or 0
		end

		local function isEligible(key: string): boolean
			if (blocked:get() :: any)[key] == true then
				return false
			end
			if not mixedEligibility:get() then
				return true
			end
			return indexOfKey(key) % 3 ~= 0
		end

		-- ===== the derived row height =======================================
		local itemExtent = scope:own(core:memo(function(use)
			--[[ THE LINE BOXES COME FROM THE FRAMEWORK (`Facet.text.facts` /
				`Facet.text.lineBox`, adopted 2026-08-15). This memo used to carry its own
				copy of the arithmetic, and the copy was wrong in the way six of the seven
				in-repo copies were: it read `typographyScale` alone, while the measure seam
				reserves at `max(typographyScale, typographyPaintScale)` — so at any sub-1
				accessibility preference it reserved less than the engine drew.
				docs/plans/variable-item-extents.md. ]]
			local facts = Facet.text.facts({ env = env, use = use })
			local metrics: any = facts.metrics
			if type(metrics) ~= "table" or type(metrics.type) ~= "table" then
				return 56
			end
			local function lineBox(role: string, lines: number): number
				return Facet.text.lineBox({ facts = facts, size = role, lines = lines })
			end
			-- THE ARRANGEMENT AND THE HEIGHT ARE ONE DECISION (the row-height lesson,
			-- restated here because this row is exactly its worked example). Every
			-- number this memo adds is a number the `Card`/`Labels` arrangement below
			-- ALSO spends, read from the same token so there is no second copy of the
			-- decision to drift out of sync:
			--   * one name line + the `Labels` VStack's own `gap = "xs"` between Name
			--     and Detail (found live: overflowing every row by 11px on the sweep —
			--     this gap was the row's own layout decision, uncounted here) + the
			--     capped two detail lines;
			--   * the `Card` HStack's own vertical `padding = "s"`;
			--   * the `Card`'s own vertical `margin = "xs"` (the hairline-ish inset
			--     that keeps the list's focus ring visible around the card) — the
			--     ZStack `Row` wrapper hands `Card` its box MINUS this margin, so it is
			--     room the row's content never gets either, exactly like the padding.
			local labelGap = metrics.space.xs or 4
			--[[ the two caption lines are ONE `lineBox` call, not two summed: the ceil
				lands once on the whole two-line product, which is what the solver's own
				measure does (several of the copies this replaced ceiled per line and
				over-reserved by up to `lines - 1` px). ]]
			local content = lineBox("body", 1) + labelGap + lineBox("caption", 2)
			local padV = 2 * (metrics.space.s or 8)
			local marginV = 2 * (metrics.space.xs or 4)
			return math.max(metrics.targetSizes.minimum or 44, content + padV + marginV)
		end))

		--[[ THE WINDOW IS A LIVE NUMBER (review R2-F7). `newVirtualList` takes a
			Readable viewport height, so this is a memo over the environment's own
			viewport rect and a rotation (or a split-screen resize) re-derives the
			window in place — no reset, and the painted box and the windowing
			arithmetic read the same number. A build-time pixel here was the same
			fixed-px-vs-live-facts defect the derived row height above exists to avoid,
			one level up.

			AND IT IS NOT `viewportExtent = "auto"`, WHICH IS A FACT ABOUT THIS
			FIXTURE'S TREE RATHER THAN AN OVERSIGHT (purity audit §4, 2026-08-22).
			`"auto"` takes `fill` along the scroll axis and measures what the solver
			gave it, and its one requirement is an ancestor that hands the list a
			DEFINITE extent there. This list sits inside `Body`, a y-scrolling page:
			its content box is unbounded on y by construction, so a `fill` child of it
			has nothing definite to fill. AND THE FAILURE WOULD BE THE LOUD-LOOKING ONE
			WEARING THE QUIET ONE'S CLOTHES: a `fill` inside a scroller's own scroll
			axis is offered an unbounded limit and answers with its CONTENT, and a
			scroll node's content measure sums its children — so this list would
			measure its whole canvas and window every row, with virtualization
			silently off and the layout looking perfect. `newVirtualList` reports that
			shape in `dump().diagnostics` now; it is still not a thing to declare on
			purpose. `scenarios/row_actions.luau` and `scenarios/card_rail.luau`
			migrated in the same round because their lists sit in panes with definite
			extents; `scenarios/sponsor_drop.luau` was migrated and REVERTED on
			measurement, for a different reason it carries at its own site. The clamp
			stays here, and the sentence above is why. ]]
		local viewportExtent = scope:own(core:memo(function(use)
			local vp: any = use(env:get("viewportRect"))
			local h = if type(vp) == "table" and type(vp.h) == "number" then vp.h else 760
			return math.clamp(math.floor(h - 220), 160, 460)
		end))

		-- ===== the row ======================================================
		-- declared before `cell` because a row reads the list's own selection
		-- signal; it is assigned the moment the construct is built, below
		local list: any = nil
		local SWATCH: any = { type = "fixed", px = "iconSizes.medium" }

		local function cell(item: any, cellCtx: any): any
			local itemScope = cellCtx.scope
			remountCounts[item.id] = (remountCounts[item.id] or 0) + 1
			local key = item.id
			local index = indexOfKey(key)

			local selected = itemScope:own(core:memo(function(use)
				return use(list.selectedKey) == key
			end))
			local eligible = itemScope:own(core:memo(function(use)
				if (use(blocked) :: any)[key] == true then
					return false
				end
				if not use(mixedEligibility) then
					return true
				end
				return index % 3 ~= 0
			end))
			-- SF-P1: a continuous value on the fill channel. One `decay` spring
			-- drives the whole list and each row spends it at its own phase, so the
			-- sweep is a real gradient across rows rather than 20 copies of one
			-- number.
			local energy = itemScope:own(core:memo(function(use)
				return math.clamp(use(sweep) * 1.8 - (index - 1) * 0.08, 0, 1)
			end))
			local washTint = itemScope:own(core:memo(function(use)
				return { role = "accent", from = "control", blend = use(energy) }
			end))
			-- THE CARD'S FILL IS ELEVATION, AND ONLY ELEVATION (review R2-F6). It used
			-- to switch to `raised` when the row was selected, which put an
			-- interaction state on the elevation channel — the one-meaning-per-channel
			-- erosion I-5 exists to stop. Selection is now the LIST's own native
			-- state: it declares `selected` on the row hit under this card, the theme
			-- paints that (`controlSelected`), and the card contributes the FORM
			-- channels instead — the accent edge bar and the hairline stroke.
			local cardSurface = itemScope:own(core:memo(function(use)
				return if use(eligible) then "control" else "base"
			end))
			-- the content channel of the row's state set: an ineligible row reads in
			-- the secondary role, an eligible one in the default. "secondary" is the
			-- only authored text role there is — anything else would be a string the
			-- schema accepts and the theme ignores.
			local nameRole = itemScope:own(core:memo(function(use)
				return if use(eligible) then nil else "secondary"
			end))
			-- ONE stroke prop, declared precedence: the pulse (SF-P3) outranks the
			-- selected hairline, and an unselected quiet row carries none
			local strokeData = itemScope:own(core:memo(function(use)
				if use(pulseKey) == key then
					return UI.strokeData({ thickness = 2, color = "accent", transparency = 1 - use(pulse) })
				end
				if use(selected) then
					return UI.strokeData({ color = "hairline" })
				end
				return nil
			end))
			local edgeBarWidth = itemScope:own(core:memo(function(use)
				return { type = "fixed", px = if use(selected) then 4 else 0 }
			end))

			return UI.HStack({
				id = "Card",
				surface = cardSurface,
				stroke = strokeData,
				padding = "s",
				gap = "s",
				-- INSET BY A HAIRLINE-ISH MARGIN so the row's own focus ring — drawn
				-- by the theme on the list's hit node, which this card paints over —
				-- stays visible around the card on every viewport
				margin = "xs",
				width = UI.fill(),
				height = UI.fill(),
				children = {
					-- the selected FORM channel (never hue alone, I-5)
					UI.Box({
						id = "EdgeBar",
						surface = "accent",
						width = edgeBarWidth,
						height = UI.fill(),
					}),
					UI.corners(UI.Box({ id = "Swatch", surface = "chip", width = SWATCH, height = SWATCH }), "pill"),
					UI.VStack({
						id = "Labels",
						gap = "xs",
						width = UI.fill(),
						children = {
							UI.Text({ id = "Name", text = item.name, textSize = "body", role = nameRole }),
							-- CAPPED AT TWO LINES (finding F13): the row height above
							-- reserves exactly this, so the largest text offset grows
							-- every row by the same amount and the windowing arithmetic
							-- stays index x height
							UI.Text({
								id = "Detail",
								text = item.detail,
								textSize = "caption",
								role = "secondary",
								lineLimit = 2,
								-- ...AND A WAY BACK OUT OF THE CAP (O-21, 2026-08-15). The
								-- cap is deliberate and stays: uniform growth per row is what
								-- keeps `index x height` windowing true. What was missing is
								-- the other half of §15.3 `policy = "truncate"` — on a
								-- 359x718 phone at +10 and +14 this line is CUT (measured:
								-- 101px of box for a 61-character string) and had nothing to
								-- open it, which is lost copy rather than a declared degrade.
								disclose = true,
								width = UI.fill(),
							}),
						},
					}),
					UI.Spacer({ id = "Gap" }),
					-- the §4.2 verdict glyph slot: empty in this lab (no drag session
					-- here), sized so the drop lab's row and this one measure the same
					UI.Box({ id = "VerdictSlot", surface = "plain", width = SWATCH, height = SWATCH }),
					-- SF-P1's continuous channel, on its own node so the card keeps its
					-- state fill (a tint claims the fill it is written to)
					UI.Box({
						id = "Wash",
						tint = washTint,
						width = { type = "fixed", px = 6 },
						height = UI.fill(),
					}),
				},
			})
		end

		local reorders: { any } = {}
		local selections: { string } = {}
		local activations: { any } = {}

		list = Facet.Controls.VirtualList(core, {
			id = "Rows",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			itemExtent = itemExtent,
			viewportExtent = viewportExtent,
			overscan = 2,
			selection = "single",
			onSelect = function(_item: any, key: string)
				table.insert(selections, key)
				note("select", { key = key })
			end,
			reorderable = true,
			reorderMotion = "object",
			motionClock = clock,
			onReorder = function(key: string, toIndex: number)
				table.insert(reorders, { key = key, toIndex = toIndex })
				local current = rows:get() :: { any }
				local next: { any } = {}
				local moved: any = nil
				for _, item in current do
					if item.id == key then
						moved = item
					else
						table.insert(next, item)
					end
				end
				table.insert(next, math.clamp(toIndex, 1, #next + 1), moved)
				rows:set(next)
				note("reorder", { key = key, toIndex = toIndex })
			end,
			rowFocusable = function(item: any)
				return isEligible(item.id)
			end,
			onActivate = function(item: any, _meta: any)
				-- I-9: an ineligible row is skipped for NAVIGATION and still answers
				-- "explain why" on Activate
				local eligible = isEligible(item.id)
				table.insert(activations, { key = item.id, eligible = eligible })
				inspect:set(
					if eligible
						then `inspect: {item.name} is eligible`
						else `inspect: {item.name} is ineligible (demo-pattern-3)`
				)
				note("activate", { key = item.id, eligible = eligible })
			end,
			cell = cell,
		})

		-- ===== the scripted schedule (churn) =================================
		local plan: { { at: number, run: () -> () } } = {}
		local function schedule(delay: number, run: () -> ())
			table.insert(plan, { at = elapsed + delay, run = run })
		end
		local function runDue()
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
		end

		local churnTicks = 0
		local function churnOnce()
			-- a re-sort that KEEPS every key: identity, selection, focus and the
			-- mounted rows must all survive it (SF-L1)
			local current = rows:get() :: { any }
			local next: { any } = {}
			for i = 2, #current do
				table.insert(next, current[i])
			end
			table.insert(next, current[1])
			rows:set(next)
			churnTicks += 1
		end
		local function scheduleChurn()
			if not churning:get() then
				return
			end
			schedule(0.25, function()
				if not churning:get() then
					return
				end
				churnOnce()
				scheduleChurn()
			end)
		end

		local result: any = {}
		local unbindScroll: any = nil
		local function controller(): any
			local handle = result.handle
			return if handle ~= nil then handle.controller else nil
		end

		-- THE CONSUMER WIRING the unified list documents: bind the engine scroll
		-- mirror once, as soon as the surface exists. It is idempotent and called
		-- from both entry points — the first frame AND the first step — because a
		-- driver may step the fixture before any frame has been ticked, and an
		-- unbound list has no drag registry, no keep-visible and no `focusKey`.
		local function ensureBound()
			if unbindScroll ~= nil then
				return
			end
			local ctrl = controller()
			if ctrl ~= nil then
				unbindScroll = list.bindNativeScroll(ctrl)
			end
		end

		scope:own(pres.onTick(function(dt: number)
			elapsed += dt
			ensureBound()
			runDue()
		end))

		-- THE BODY SCROLLS (the overflow-sweep fix, precedent BodyScroll in
		-- adaptive_controls.luau): the title, the controls row, the list and the
		-- inspect line are content-sized in total, and on a short landscape phone
		-- their SUM already exceeds the box the screen offers before the list even
		-- windows — found live by the overflow sweep at 705x338 and 640x320. A
		-- `UI.ScrollView` reads `gap`/`axis`/multiple children exactly like a
		-- VStack (solver's `scroll` measure sums the main axis, same as
		-- `vstack`/`hstack`), so it drops in as the screen's one child with no
		-- second wrapper node — `LIST` above already accounts for the one path
		-- segment (`Body`) this adds.
		local screen = UI.Screen({
			id = "ListLab",
			padding = "m",
			children = {
				UI.ScrollView({
					id = "Body",
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.Text({ id = "Title", text = "Collection lab", textSize = "heading" }),
						-- THE CONTROL ROW WRAPS (O-21, 2026-08-15). The buttons carry
						-- their own labels and nothing in the row is shrinkable, so on a
						-- 320px phone from +10 up it painted `Eligibility` 15px off the
						-- right screen edge — a control whose label cannot be read and
						-- whose target cannot be reached.
						UI.HStack({
							id = "Controls",
							wrap = true,
							gap = "s",
							width = UI.fill(),
							children = {
								UI.Button({
									id = "BtnChurn",
									label = "Churn",
									selected = churning,
									height = { type = "minMax", min = "targetSizes.minimum" },
									onActivate = function()
										churning:set(not churning:get())
										if churning:get() then
											scheduleChurn()
										end
									end,
								}),
								UI.Button({
									id = "BtnEligibility",
									label = "Eligibility",
									selected = mixedEligibility,
									height = { type = "minMax", min = "targetSizes.minimum" },
									onActivate = function()
										mixedEligibility:set(not mixedEligibility:get())
									end,
								}),
							},
						}),
						list.blueprint,
						UI.Text({ id = "InspectLine", text = inspect, textSize = "caption", role = "secondary" }),
					},
				}),
			},
		})

		-- ===== steps ========================================================
		-- `list.focusKey` is KEEP-VISIBLE plus the list's own focused key; moving the
		-- surface's focus is the focus graph's job, so both are asked. Two seams,
		-- two jobs — and calling only the first is why a sweep can start from the
		-- control row instead of the list.
		local function focusRow(key: string): string?
			ensureBound()
			list.focusKey(key)
			local path = `{LIST}/Canvas/W/[{key}]/Row/Hit`
			return if pres.focus.focusOn(path) then path else nil
		end

		local function focusSweep(steps: number): { any }
			-- SYNTHETIC NAVIGATION, honestly labeled: this drives the presenter's own
			-- Navigate action through a scriptable binding, which is the same action
			-- a D-pad drives — no hardware is being counterfeited and no focus is
			-- being placed by hand. The physical-gamepad row stays pending.
			local handle = result.handle
			local out: { any } = {}
			if handle == nil then
				return out
			end
			local binding = handle.actions.navigate.bind({ scriptable = true })
			for _ = 1, steps do
				binding.fire(1)
				binding.fire(0)
				-- a refresh between moves is the FRAME BOUNDARY the runner gives every
				-- step: without it the window cannot slide, so a sweep that walks past
				-- the mounted window would report the same row twice
				pres.refresh()
				table.insert(out, { focused = pres.focus.focused:get() })
			end
			binding.remove()
			return out
		end

		result.screen = screen
		result.present = {}
		result.steps = {
			select = function()
				list.select("row-03")
				return { selected = list.selectedKey:get(), selections = #selections }
			end,
			startChurn = function()
				churning:set(true)
				churnTicks = 0
				scheduleChurn()
				note("churn:start")
				return { churning = true, order = (rows:get() :: any)[1].id }
			end,
			stopChurn = function()
				churning:set(false)
				note("churn:stop", { ticks = churnTicks })
				return { churning = false, ticks = churnTicks }
			end,
			-- every third row ineligible + a synthetic Navigate sweep that shows the
			-- skips (the row the framework refuses to land on never appears here)
			mixedEligibility = function()
				ensureBound()
				mixedEligibility:set(true)
				local start = focusRow("row-01")
				navigationSweep = focusSweep(6)
				table.insert(navigationSweep, 1, { focused = start, seed = true })
				note("eligibility:mixed", { visited = #navigationSweep })
				return { mixed = true, visited = navigationSweep }
			end,
			-- SF-L3's exemption: arm a row, then flip ITS predicate false. The armed
			-- row must keep its focusability until the interaction ends.
			exemption = function()
				ensureBound()
				local key = "row-04"
				focusRow(key)
				list.toggleGrab(key)
				local armed = list.armedKey:get()
				local blockedNow = table.clone(blocked:get() :: any)
				blockedNow[key] = true
				blocked:set(blockedNow)
				pres.refresh()
				local hit = `{LIST}/Canvas/W/[{key}]/Row/Hit`
				local focusedWhileArmed = pres.focus.focused:get()
				local focusableWhileArmed = pres.focus.isFocusable(hit)
				local armedAfterFlip = list.armedKey:get()
				-- disarm: NOW the flip is allowed to take effect
				list.toggleGrab(key)
				pres.refresh()
				local focusedAfterDisarm = pres.focus.focused:get()
				local focusableAfterDisarm = pres.focus.isFocusable(hit)
				note("exemption", { key = key, armed = armed, armedAfterFlip = armedAfterFlip })
				return {
					key = key,
					armed = armed,
					armedAfterFlip = armedAfterFlip,
					focusedWhileArmed = focusedWhileArmed,
					focusableWhileArmed = focusableWhileArmed,
					focusedAfterDisarm = focusedAfterDisarm,
					focusableAfterDisarm = focusableAfterDisarm,
					eligibleNow = isEligible(key),
				}
			end,
			-- SF-P1: drive the continuous channel across every mounted row and hand
			-- the authority dump back with it
			washSweep = function()
				sweep:snap(1)
				sweep:setTarget(0)
				note("wash:sweep")
				return { sweep = sweep:get(), settled = sweep:isSettled() }
			end,
			-- SF-P3: one row's authored border pulses on a bound decay value
			strokePulse = function()
				pulseKey:set("row-05")
				pulse:snap(1)
				pulse:setTarget(0)
				note("stroke:pulse", { key = "row-05" })
				return { key = pulseKey:get(), value = pulse:get() }
			end,
			clearStrokePulse = function()
				pulseKey:set(nil)
				return { key = pulseKey:get() }
			end,
			inspectIneligible = function()
				mixedEligibility:set(true)
				local target = "row-03"
				local item: any = nil
				for _, row in rows:get() :: { any } do
					if row.id == target then
						item = row
					end
				end
				-- the Activate a tap delivers, at the list's own public seam
				if item ~= nil then
					list.select(target)
				end
				local eligible = isEligible(target)
				inspect:set(
					if eligible
						then `inspect: {target} is eligible`
						else `inspect: {target} is ineligible (demo-pattern-3)`
				)
				table.insert(activations, { key = target, eligible = eligible })
				note("inspect", { key = target, eligible = eligible })
				return { key = target, eligible = eligible, line = inspect:get() }
			end,
			-- identity evidence a churn row pairs with: how many times each key's
			-- cell factory has run since the fixture mounted (SF-L1's no-blink)
			remounts = function()
				local total = 0
				for _, n in remountCounts do
					total += n
				end
				return { keys = remountCounts, total = total }
			end,
		}
		result.report = function()
			local order: { string } = {}
			for _, item in rows:get() :: { any } do
				table.insert(order, item.id)
			end
			local window: { string } = {}
			for key in list.debugWindow() do
				table.insert(window, key)
			end
			table.sort(window)
			local styled: any = nil
			if ctx.nativeStyle ~= nil and ctx.nativeStyle.styledOf ~= nil then
				local first = window[1]
				if first ~= nil then
					local wash = `{LIST}/Canvas/W/[{first}]/Row/Card/Wash`
					styled = {
						path = wash,
						washBackground = ctx.nativeStyle.styledOf(wash, "BackgroundColor3"),
						node = if ctx.nativeStyle.dumpNode ~= nil then ctx.nativeStyle.dumpNode(wash) else nil,
					}
				end
			end
			return {
				ledger = "SF-L1/SF-L3/SF-P1/SF-P3",
				elapsed = elapsed,
				trace = trace,
				order = order,
				window = window,
				itemExtent = itemExtent:get(),
				viewportExtent = viewportExtent:get(),
				selectedKey = list.selectedKey:get(),
				armedKey = list.armedKey:get(),
				focusedKey = list.focusedKey:get(),
				focusPath = pres.focus.focused:get(),
				churning = churning:get(),
				churnTicks = churnTicks,
				mixedEligibility = mixedEligibility:get(),
				blocked = blocked:get(),
				inspect = inspect:get(),
				navigationSweep = navigationSweep,
				navigationSweepIsSynthetic = true,
				selections = selections,
				activations = activations,
				reorders = reorders,
				remounts = remountCounts,
				sweep = sweep:get(),
				pulse = { key = pulseKey:get(), value = pulse:get() },
				authority = styled,
				listDump = list.dump(),
				motion = { active = clock:activeCount(), stats = clock:stats() },
				reducedMotion = env:get("reducedMotion"):get(),
				preferredTextOffset = env:get("preferredTextOffset"):get(),
				counters = core:counters(),
				coreError = core:lastError(),
			}
		end
		result.dispose = function()
			churning:set(false)
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
