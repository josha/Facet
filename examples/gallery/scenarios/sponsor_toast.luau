--!strict
-- Scenario 'sponsor_toast' (ledger rows SF-T1, SF-T2, SF-T3, SF-M6;
-- ui-designer-spec §8.5): the TRANSIENT SURFACE and the structural-transition
-- contract — an input-transparent, self-retiring layer that never touches focus,
-- a scheduler with a read floor and a cap, and a region that can be re-entered
-- mid-exit.
--
-- EVERY ASSERTION HERE IS ABOUT SOMETHING A TOAST MUST NOT DO: not take input,
-- not move focus, not join the navigation ring, not truncate a sentence somebody
-- is reading, not drop a queued message under reduced motion, and not defer its
-- own disposal past the flat 500 ms cap.
--
-- The pointer half of `inputPassthrough` is a LIVE-DRIVE row: this file records
-- the aim rect (a point inside both the toast and the button beneath it) and the
-- expected outcome, and drives the state-level equivalent — the surface's own
-- Activate action on the focused button — so the headless run and the Studio
-- VirtualInput run compare against the same block.

local newLifetime = require("./lifetime")

return {
	title = "Toasts",
	ledgerRows = { "SF-T1", "SF-T2", "SF-T3", "SF-M6", "SF-F1", "SF-C1", "SF-C2", "SF-C3" },
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI, Compose = ctx.UI, ctx.Compose
		local core = ctx.core
		local env = ctx.env
		local pres = ctx.presenter
		local lifetime = newLifetime(Compose)
		local own = lifetime.own

		local SCREEN = "/ToastLab"
		local BENEATH = SCREEN .. "/Stage/Beneath"

		local trace: { any } = {}
		local elapsed = 0
		local dismissals: { any } = {}
		local supersedes: { any } = {}
		local function note(kind: string, info: any?)
			table.insert(trace, { at = elapsed, kind = kind, info = info })
		end
		own(pres.onFeedback(function(event: any)
			table.insert(trace, {
				at = elapsed,
				kind = "feedback:" .. tostring(event.type),
				info = { path = event.path, reason = event.reason, context = event.context },
			})
			if event.type == "dismiss" then
				table.insert(dismissals, { at = elapsed, reason = event.reason, context = event.context })
			elseif event.type == "supersede" then
				table.insert(supersedes, { at = elapsed, context = event.context })
			end
		end))

		local beneathPresses = Compose.cell(0)
		local position = Compose.cell("top")
		local widthMode = Compose.cell("fill")

		-- the schedule trace: every change in what the layer is showing/queuing,
		-- sampled on the presenter's own tick (SF-T2's evidence)
		local scheduleTrace: { any } = {}
		local lastCounts: any = nil
		local aim: { any } = {}
		local expectations: { any } = {}
		local handles: { any } = {}
		local counterBaseline: any = nil
		local counterAfter: any = nil

		local result: any = {}
		local function controller(): any
			local handle = result.handle
			return if handle ~= nil then handle.controller else nil
		end

		own(pres.onTick(function(dt: number)
			elapsed += dt
			local counts = pres.toastCounts()
			if
				lastCounts == nil
				or counts.visible ~= lastCounts.visible
				or counts.queued ~= lastCounts.queued
				or counts.sequence ~= lastCounts.sequence
			then
				lastCounts = counts
				if #scheduleTrace < 400 then
					table.insert(scheduleTrace, {
						at = elapsed,
						visible = counts.visible,
						queued = counts.queued,
						sequence = counts.sequence,
					})
				end
			end
		end))

		local function ToastBody(props: any)
			local contentWidth = if props.fit then UI.hug() else UI.fill()
			return UI.ZStack("Plate")({
				width = contentWidth,
				height = UI.hug(),
				UI.shadow(
					UI.corners(
						UI.Box("PlateFill")({
							surface = "raised",
							width = UI.fill(),
							height = UI.fill(),
						}),
						"control"
					),
					"overlay"
				),
				UI.HStack("Body")({
					padding = "m",
					gap = "s",
					width = contentWidth,
					UI.corners(
						UI.Box("Glyph")({
							surface = "chip",
							width = { type = "fixed", px = "iconSizes.medium" },
							height = { type = "fixed", px = "iconSizes.medium" },
						}),
						"pill"
					),
					UI.VStack("Lines")({
						gap = "xs",
						width = contentWidth,
						UI.Text("Title")({ text = props.title, textSize = "body", width = contentWidth }),
						UI.Text("Detail")({
							text = props.detail,
							textSize = "body",
							role = "secondary",
							width = contentWidth,
						}),
					}),
				}),
			})
		end

		-- `subject` IS THE OPTION'S NAME HERE (review R2-F10). §3.1 calls the
		-- same-message identity a SUBJECT — "the message updated where it stands" —
		-- and `key` reads like a collection row key to anyone who has just written a
		-- ForEach. The presenter's wire name is still `key`, so this is the one place
		-- the translation happens: the fixture reads like the spec, the API is
		-- untouched, and nothing downstream has two names for one thing.
		local function show(title: string, detail: string, opts: any?): any
			local options: any = if opts ~= nil then table.clone(opts) else {}
			if options.subject ~= nil then
				options.key = options.subject
				options.subject = nil
			end
			options.position = options.position or position:peek()
			options.width = options.width or (if widthMode:peek() == "hug" then UI.hug({ max = 560 }) else UI.fill())
			-- the toast owns its body: the component runs inside the toast
			local fit = options.width.type == "hug"
			local handle = pres.presentToast(function()
				return ToastBody({ title = title, detail = detail, fit = fit })
			end, options)
			table.insert(handles, { id = handle.id, title = title, opts = opts, at = elapsed, handle = handle })
			note("toast:present", { title = title, opts = opts })
			return handle
		end

		-- ===== the screen ===================================================
		local function control(id: string, label: string, onActivate: () -> ())
			return UI.Button(id)({
				label = label,
				height = { type = "minMax", min = "targetSizes.minimum" },
				onActivate = onActivate,
			})
		end

		local burstIndex = 0
		local function ToastLab()
			return UI.Screen("ToastLab")({
				padding = "m",
				gap = "m",

				-- the toast strip owns the TOP lane (director SFH-3: the title used
				-- to sit exactly under the first toast row); the lab's own chrome
				-- lives below the stage
				UI.ZStack("Stage")({
					width = UI.fill(),
					height = UI.fill(),

					UI.alignment(
						UI.Button("Beneath")({
							label = function(use)
								return `Test input: {use(beneathPresses)}`
							end,
							height = { type = "minMax", min = "targetSizes.minimum" },
							onActivate = function()
								-- the control UNDER the toast: it must activate normally
								-- while a toast is showing over it (SF-T1)
								beneathPresses:set(beneathPresses:peek() + 1)
								note("beneath:activate", { presses = beneathPresses:peek() })
							end,
						}),
						"center",
						"center"
					),
				}),
				--[[ THE CHROME SCROLLS, THE STAGE DOES NOT (O-21, measured 2026-08-15).
					Both lanes were `fill` against a page that was not, so on a 640x320
					landscape at +10 the heading, the status line and a four-button grid
					took the whole canvas: the stage collapsed under its own button's
					44px target floor and `Press me` — the control this fixture exists to
					prove stays pressable UNDER a toast — sat 5px below the fold with
					nothing to scroll it back. Splitting the leftover between two fills
					gives the stage a lane that can always seat one target, and hands the
					chrome a window it can scroll inside instead of pushing the page. ]]
				UI.ScrollView("Chrome")({
					axis = "y",
					gap = "m",
					width = UI.fill(),
					height = UI.fill(),

					UI.Text("Title")({ text = "Toasts", textSize = "heading" }),
					UI.Text("Status")({
						text = "Show a toast, then try Test input. Its count increases while the toast stays visible; notifications leave your controls usable.",
						textSize = "body",
						role = "secondary",
						width = UI.fill(),
					}),
					UI.Picker("Position")({
						label = "Edge for new stacks",
						style = "segmented",
						selected = position,
						options = { { value = "top", label = "Top" }, { value = "bottom", label = "Bottom" } },
					}),
					UI.Picker("Width")({
						label = "Toast width",
						style = "segmented",
						selected = widthMode,
						options = {
							{ value = "fill", label = "Wide" },
							{ value = "hug", label = "Fit content" },
						},
					}),
					UI.Grid("Controls")({
						-- A PACKING FLOOR, NOT A FONT GUESS, and it was measured on 2026-08-21 before
						-- being left alone. `minColumnWidth = "intrinsic"` (the default since that day)
						-- lets the WIDEST verb decide every column, so one long label costs this lab a
						-- whole column on a 320px phone: the control grid doubles in height and the
						-- `fill` stage column above it collapses to zero. This number asks the other
						-- question — how many controls fit a row — and lets a long label compact.
						minColumnWidth = 104,
						gap = "s",
						rowGap = "s",
						width = UI.fill(),

						control("BtnOne", "Show toast", function()
							show("Notice", "A single transient message")
						end),
						control("BtnPair", "Show pair", function()
							show(
								"First message",
								"The other toast slides into this space",
								{ duration = 3, readFloor = 0 }
							)
							show(
								"Second message",
								"Still here after the first message leaves",
								{ duration = 8, readFloor = 0 }
							)
						end),
						control("BtnBurst", "Burst", function()
							for i = 1, 12 do
								burstIndex += 1
								show(`Burst {burstIndex}`, "Queued behind the visible three", {
									priority = i % 3,
									duration = 1.2,
									readFloor = 0.4,
								})
							end
						end),
						control("BtnPriority", "Priority", function()
							show("Urgent", "Arrived during another toast's read floor", { priority = 5 })
						end),
						control("BtnSupersede", "Supersede", function()
							show("Subject", "Same subject, replaced in place", { subject = "lap-time" })
						end),
					}),
				}),
			})
		end
		local screen = ToastLab

		local function focusBeneath(): boolean
			return pres.focus.focusOn(BENEATH)
		end

		local function fireActivate(): boolean
			local handle = result.handle
			if handle == nil then
				return false
			end
			local binding = handle.actions.activate.bind({ scriptable = true })
			binding.fire(true)
			binding.fire(false)
			binding.remove()
			return true
		end

		local function rectOf(path: string): any
			local ctrl = controller()
			if ctrl == nil then
				return nil
			end
			return if ctrl.screenRectOf ~= nil then ctrl.screenRectOf(path) else ctrl.rectOf(path)
		end

		result.screen = screen
		result.present = {}
		result.steps = {
			showOne = function()
				local handle = show("Notice", "A single transient message")
				local counts = pres.toastCounts()
				return { id = handle.id, counts = counts, focus = pres.focus.focused:peek(), depth = pres.depth() }
			end,
			-- SF-T1: the layer is structurally incapable of taking input. The focus
			-- graph reads identically before, during and after, the presenter stack
			-- never grew, and the button underneath still activates.
			inputPassthrough = function()
				focusBeneath()
				local focusBefore = pres.focus.focused:peek()
				local depthBefore = pres.depth()
				local pressesBefore = beneathPresses:peek()
				show("Over the button", "Tap through me", { duration = 6 })
				pres.refresh()
				local focusDuring = pres.focus.focused:peek()
				local beneathRect = rectOf(BENEATH)
				fireActivate()
				local entry = {
					label = "inputPassthrough",
					rects = { [BENEATH] = beneathRect },
					synthetic = true,
					note = "the pointer half is a live VirtualInput row: click the recorded rect while the toast "
						.. "covers it and the press count must rise by exactly one",
				}
				table.insert(aim, entry)
				local expectation = {
					step = "inputPassthrough",
					expectFocusUnchanged = true,
					expectDepthUnchanged = true,
					expectPressDelta = 1,
					focusBefore = focusBefore,
					focusDuring = focusDuring,
					depthBefore = depthBefore,
					depthDuring = pres.depth(),
					pressDelta = beneathPresses:peek() - pressesBefore,
				}
				table.insert(expectations, expectation)
				entry.expected = expectation
				note("inputPassthrough", expectation)
				return expectation
			end,
			-- SF-T2: eight at once — three visible, priority-ordered, the queue capped
			-- at eight and every drop traceable
			burst = function()
				scheduleTrace = {}
				dismissals = {}
				-- TWELVE, not eight: three show, eight wait, and the twelfth is what
				-- makes the queue cap a real event rather than a documented number
				for i = 1, 12 do
					burstIndex += 1
					show(`Burst {burstIndex}`, "Queued behind the visible three", {
						priority = i % 3,
						duration = 1.2,
						readFloor = 0.4,
					})
				end
				local counts = pres.toastCounts()
				note("burst", counts)
				return { counts = counts, presented = 12 }
			end,
			-- SF-T2/finding F2: priority orders the QUEUE and never truncates the
			-- showing toast's read floor
			priorityMidFloor = function()
				scheduleTrace = {}
				show("Reading", "This one owns its read floor", { duration = 3, readFloor = 1.5 })
				local at = elapsed
				show("Urgent", "Arrived mid-floor", { priority = 9, duration = 2, readFloor = 0.5 })
				note("priorityMidFloor", { presentedAt = at })
				return { counts = pres.toastCounts(), readFloor = 1.5 }
			end,
			-- same subject replaces in place: one `supersede`, no exit/enter churn
			supersede = function()
				supersedes = {}
				show("Subject v1", "The first version", { subject = "lap-time", duration = 4, readFloor = 0 })
				show("Subject v2", "Replaced in place", { subject = "lap-time", duration = 4, readFloor = 0 })
				note("supersede", { counts = pres.toastCounts() })
				return { counts = pres.toastCounts(), supersedes = #supersedes }
			end,
			-- SF-M6: re-present the same subject while its exit is still playing —
			-- the same mounted subtree reverses instead of finishing and re-entering
			exitInterrupt = function()
				local handle = show("Reversible", "Dismissed then re-presented", { subject = "reverse", readFloor = 0 })
				handle.dismiss()
				local afterDismiss = pres.toastCounts()
				-- mid-exit, on the very next call: the region is still mounted
				show("Reversible", "Re-entered mid-exit", { subject = "reverse", readFloor = 0 })
				note("exitInterrupt", { afterDismiss = afterDismiss, now = pres.toastCounts() })
				return { afterDismiss = afterDismiss, afterReenter = pres.toastCounts() }
			end,
			-- the flat 500 ms cap: no exit may defer disposal past it, and the
			-- fixture's own counters must return to where they started
			unmountCap = function()
				counterBaseline = core.owner.size()
				local capped: { any } = {}
				for i = 1, 3 do
					table.insert(capped, show(`Capped {i}`, "Dismissed immediately", { readFloor = 0, duration = 4 }))
				end
				-- dismissed on the SAME frame they were presented: every one is now in
				-- its exit, and the flat cap owns how long that may defer disposal
				for _, handle in capped do
					handle.dismiss()
				end
				note("unmountCap:presented", { counters = counterBaseline })
				return { baseline = counterBaseline, dismissed = #capped, capSeconds = 0.5 }
			end,
			-- read after ticking past the cap: the layer is gone and the counters are
			-- back (the caller ticks; the runner refreshes between steps)
			unmountCapRead = function()
				counterAfter = core.owner.size()
				return {
					baseline = counterBaseline,
					after = counterAfter,
					counts = pres.toastCounts(),
				}
			end,
			-- §3.1's OTHER EDGE (review R2-F10): the layer docks where the FIRST
			-- toast says, for its lifetime — one strip, one stacking direction, so a
			-- burst can never make it hop mid-read. Which is why this step clears the
			-- layer first: a bottom-docked toast is only a bottom-docked toast if no
			-- top layer is still alive. Stacking grows upward from the safe-area inset
			-- there; the geometry itself is pinned headlessly in toast_presentation.
			bottomEdge = function()
				-- so the evidence can never claim an edge it did not get: the option
				-- only decides the dock when the layer is BUILT, and a driver that
				-- forgot to retire the previous one would otherwise record "bottom"
				-- over a top-docked strip
				local before = pres.toastCounts()
				local layerWasEmpty = before.visible == 0 and before.queued == 0
				local handle = show("Docked low", "Bottom edge, growing upward", {
					position = "bottom",
					duration = 4,
					readFloor = 0,
				})
				note("bottomEdge", { before = before, layerWasEmpty = layerWasEmpty })
				return {
					position = "bottom",
					layerWasEmpty = layerWasEmpty,
					id = handle.id,
					counts = pres.toastCounts(),
					focus = pres.focus.focused:peek(),
					depth = pres.depth(),
				}
			end,
			dismissAll = function()
				local n = 0
				for _, entry in handles do
					if entry.handle ~= nil and entry.handle.dismiss() then
						n += 1
					end
				end
				handles = {}
				return { cleared = n, counts = pres.toastCounts() }
			end,
		}
		result.report = function()
			return {
				ledger = "SF-T1/SF-T2/SF-T3/SF-M6",
				elapsed = elapsed,
				trace = trace,
				scheduleTrace = scheduleTrace,
				dismissals = dismissals,
				supersedes = supersedes,
				counts = pres.toastCounts(),
				presented = (function()
					local out: { any } = {}
					for _, entry in handles do
						table.insert(out, { id = entry.id, title = entry.title, at = entry.at, opts = entry.opts })
					end
					return out
				end)(),
				aim = aim,
				expectations = expectations,
				beneathPresses = beneathPresses:peek(),
				position = position:peek(),
				width = widthMode:peek(),
				beneathRect = rectOf(BENEATH),
				focusPath = pres.focus.focused:peek(),
				depth = pres.depth(),
				surfaceDisplayOrder = if result.handle ~= nil then result.handle.displayOrder else nil,
				counterBaseline = counterBaseline,
				counterAfter = counterAfter,
				reducedMotion = env:get("reducedMotion"):peek(),
				motionPolicy = env:get("motionPolicy"):peek(),
				counters = core.owner.size(),
				coreError = core.lastError(),
			}
		end
		result.dispose = function()
			for _, entry in handles do
				entry.handle.dismiss()
			end
			lifetime.dispose()
		end
		return result
	end,
}
