--!strict
--[[ THE OUTPOST POWER TERMINAL — the screen itself, declared once.

	ONE MODULE, TWO HOSTS. The showcase scenario
	(`examples/gallery/scenarios/outpost_terminal.luau`) and the standalone place
	both build THIS file and present it on a `SurfaceGui` through
	`Facet.client.surface_target`. There is no showcase fork and no "simplified"
	standalone copy: a demo whose two hosts disagree is two demos.

	WHAT IT IS NOT. It is not engine code. It creates no Instance, reaches no
	service, and knows nothing about a `ProximityPrompt`, a console part or a
	`RemoteEvent`. It is handed a `send` function and told when replies land —
	which is exactly the contract `docs/guide/06-client-server.md` describes, and
	the reason this same screen is testable headlessly with no server at all.

	── THE AUTHORITY LINE, drawn where it actually is ────────────────────────────

	The UI is this player's. THE OUTPOST IS NOT: opening the blast door changes
	something every player can see. So `Apply` does not change the world — it
	sends ONE domain intent and waits, through `Facet.replication.mutation`, which
	is the framework's own seam for exactly this (one request in flight, verdicts
	matched by request id, `"pending"` is not success).

	NO OPTIMISTIC PRESENTATION, DELIBERATELY, and `mutation` offers it. An
	optimistic apply paints the outcome the player asked for before the server has
	agreed — which is defensible for a volume slider and is wrong here, because
	three of the five things the server checks (session, rate, and the distance it
	measures itself) are facts THIS CLIENT CANNOT KNOW. Showing the door open and
	taking it back is a worse lie than a half-second of "sending…". So the screen
	carries two allocations at once and says which is which: the DRAFT the steppers
	edit, and the allocation the outpost is CONFIRMED to be running.

	── WHY EVERY VALUE CONTROL IS A STEPPER ─────────────────────────────────────

	Not a taste call — the render target made it. `surface_target` deletes
	`setPointerHandlers` and `setTouchGestureHandlers` because a drag needs a
	canvas-space pointer mapping and, on a `SurfaceGui`, the `ScreenGui` inset
	correction is not merely wrong but the wrong KIND of correction. So this
	terminal is built from controls that need only ACTIVATION — which a tap, an
	Enter and a gamepad A all deliver identically. Six whole units among three
	consumers is also the better game rule: a decision, not a dial.
]]

local rules = require("@self/rules")

local terminal = {}

terminal.rules = rules

--[[ THE CANVAS, STATED. `surface_target`'s policy is a fixed virtual-pixel
	rectangle invariant to the part (measured: one `CanvasSize` held while the
	console was resized 8x5 -> 4x2.5 -> 16x10 -> 8x2 studs), so the resolution is
	the module's to declare and the FIXTURE's job to match with a part of the same
	aspect. 4:3 against an 8 x 6 stud console. ]]
terminal.CANVAS = { w = 640, h = 480 }

terminal.TITLE = "OUTPOST 7 — POWER"

export type Opts = {
	--[[ THE WIRE, and the only one. The screen hands over an envelope
		(`{ requestId, payload, expectedRevision }`) and the host puts it on
		whatever transport it has. Absent means "no server reachable" and the
		terminal says so instead of pretending: see `sendIntent`. ]]
	send: ((envelope: any) -> ())?,
	-- the host resigns the surface and gives the player back to the game
	onExit: (() -> ())?,
	-- every phase/outcome change, for a host that mirrors the state elsewhere
	onState: ((state: any) -> ())?,
}

export type Intent = {
	kind: string,
	allocation: rules.Allocation,
}

--[[ `terminal.build(Facet, core, opts)` — the same `(Facet, core, deps)` shape
	every tutorial example and reference proof uses, so a host that can mount one
	can mount this. ]]
function terminal.build(Facet: any, core: any, opts: Opts?)
	local o: Opts = opts or {}
	local UI = Facet.UI
	local scope = core:scope("outpost-terminal")

	-- ===== state ============================================================

	--[[ THE OUTPOST'S OWN ALLOCATION, as the server last reported it. A
		`replication.snapshot` rather than a plain signal because that is what it
		is: authoritative state arriving with a revision, where a late or duplicate
		message must not overwrite a newer one. ]]
	local outpost = Facet.replication.snapshot(core, 0, rules.copy(rules.START))
	scope:own(outpost.binding)

	--[[ THE DRAFT — one Signal per consumer, because that is what a Stepper owns
		and reads. Seeded from the outpost so the player starts from where the
		outpost actually is rather than from a blank form. ]]
	local draft: { [string]: any } = {}
	for _, consumer in rules.CONSUMERS do
		draft[consumer.id] = scope:own(core:signal(rules.START[consumer.id]))
	end

	local function draftAllocation(): rules.Allocation
		local out: rules.Allocation = {}
		for _, consumer in rules.CONSUMERS do
			out[consumer.id] = draft[consumer.id]:get()
		end
		return out
	end

	local function seedDraft(from: rules.Allocation)
		core:transaction(function()
			for _, consumer in rules.CONSUMERS do
				draft[consumer.id]:set(from[consumer.id] or 0)
			end
		end)
	end

	--[[ THE SESSION PHASE. `idle` is a terminal nobody is standing at; `engaged`
		is one this player holds; `sending` is the half-second the server owns; and
		`exited` is the terminal after every exit path, of which there are eight and
		all of them land here. ]]
	local phase = scope:own(core:signal("idle"))
	-- the last thing the outpost said back: `{ ok, code?, message }` or nil
	local outcome = scope:own(core:signal(nil :: any))
	local exitReason = scope:own(core:signal(nil :: any))

	local mutation = Facet.replication.mutation(core)
	scope:own(mutation.status)
	scope:own(mutation.lastResult)

	local sent = 0
	local refusedLocally = 0
	local applied = 0

	local function publishState()
		if o.onState == nil then
			return
		end
		local out = outcome:get()
		o.onState({
			phase = phase:get(),
			status = mutation.status:get(),
			draft = draftAllocation(),
			outpost = rules.copy(outpost.binding:get()),
			complete = rules.allRunning(outpost.binding:get()),
			outcome = out,
			exitReason = exitReason:get(),
		})
	end

	-- ===== the readouts, all derived =======================================

	local budgetLine = scope:own(core:memo(function(use)
		local spent = 0
		for _, consumer in rules.CONSUMERS do
			spent += use(draft[consumer.id])
		end
		local spare = rules.TOTAL - spent
		if spare < 0 then
			return `{spent} of {rules.TOTAL} units allocated — {-spare} over budget`
		elseif spare == 0 then
			return `{spent} of {rules.TOTAL} units allocated — nothing spare`
		end
		return `{spent} of {rules.TOTAL} units allocated — {spare} spare`
	end))

	--[[ THE LIVE VERDICT ON THE DRAFT, which is what makes this terminal answer
		before it spends a round trip. It is the SAME `rules.validate` the server
		runs; the difference is that the server's answer is the one that counts. ]]
	local draftVerdict = scope:own(core:memo(function(use)
		local allocation: rules.Allocation = {}
		for _, consumer in rules.CONSUMERS do
			allocation[consumer.id] = use(draft[consumer.id])
		end
		return rules.validate(allocation)
	end))

	local canApply = scope:own(core:memo(function(use)
		return use(phase) == "engaged" and use(draftVerdict).ok and use(mutation.status) ~= "pending"
	end))

	--[[ THE ONE LINE THE PLAYER READS FOR "WHAT JUST HAPPENED". It answers, in
		priority order: an in-flight request, the outpost's own refusal or report,
		this terminal's own objection to the draft, and finally the objective. ]]
	local messageLine = scope:own(core:memo(function(use)
		if use(mutation.status) == "pending" then
			return "Sending to the outpost…"
		end
		local said = use(outcome)
		if said ~= nil then
			return said.message
		end
		local verdict = use(draftVerdict)
		if not verdict.ok then
			return verdict.message
		end
		return rules.OBJECTIVE
	end))

	--[[ STATE COLOUR IS SEMANTIC, never a literal, and it is a TINT rather than a
		`Text.role`: `role` is a two-value closed set (`content | secondary`) and
		`danger`/`accent` are TINT roles. A bound value outside a closed set paints
		nothing, which the renderer says out loud. ]]
	local messageTint = scope:own(core:memo(function(use)
		if use(mutation.status) == "pending" then
			return { role = "contentSecondary", blend = 1 }
		end
		local said = use(outcome)
		if said ~= nil then
			return { role = if said.ok then "accent" else "danger", blend = 1 }
		end
		return if use(draftVerdict).ok then { role = "contentSecondary", blend = 1 } else { role = "danger", blend = 1 }
	end))

	local outpostLine = scope:own(core:memo(function(use)
		local allocation = use(outpost.binding)
		local running = rules.runningCount(allocation)
		if rules.allRunning(allocation) then
			return `Outpost: all {running} consumers running.`
		end
		return `Outpost: {running} of {#rules.CONSUMERS} consumers running.`
	end))

	-- ===== the intent =======================================================

	local function sendIntent(kind: string, allocation: rules.Allocation): any
		if phase:get() == "exited" then
			return { sent = false, reason = "exited" }
		end
		if mutation.status:get() == "pending" then
			--[[ THE FRAMEWORK'S OWN RULE, HONOURED RATHER THAN TRIPPED OVER:
				`mutation.send` ERRORS on a second in-flight request. Example 03
				learned on a device what that reads like when it is allowed to throw
				("I can toggle music on but not off"), so this asks first. ]]
			return { sent = false, reason = "pending" }
		end
		local verdict = rules.validate(allocation)
		if not verdict.ok then
			--[[ REFUSED HERE, AND STILL REFUSED THERE. Not sending an allocation
				this terminal can already see is illegal is a courtesy to the player,
				never a substitute for the server's check — the server re-runs the
				identical `rules.validate` on arrival, because a client's verdict is
				a suggestion. ]]
			refusedLocally += 1
			outcome:set({ ok = false, code = verdict.code, message = verdict.message })
			publishState()
			return { sent = false, reason = verdict.code, message = verdict.message }
		end
		local envelope = mutation.send({ kind = kind, allocation = rules.copy(allocation) }, outpost.revision())
		sent += 1
		outcome:set(nil)
		if o.send == nil then
			--[[ NO TRANSPORT IS A STATE, NOT A CRASH. It is what a headless mount
				and a place with no server both look like, and the terminal says so in
				the same place it says everything else. ]]
			local refusal = { ok = false, code = "session", message = rules.refusal("session") }
			mutation.reject(envelope.requestId, refusal)
			outcome:set(refusal)
			publishState()
			return { sent = false, reason = "no-transport", requestId = envelope.requestId }
		end
		o.send(envelope)
		publishState()
		return { sent = true, requestId = envelope.requestId, allocation = envelope.payload.allocation }
	end

	-- ===== the drive surface (the same calls the buttons make) ==============

	local api: any = {}

	--[[ ENGAGE. The host calls this when the walk-up prompt is triggered; the
		screen has no opinion about how that happened. `allocation` is what the
		outpost is currently running, if the host knows it. ]]
	function api.engage(allocation: rules.Allocation?): any
		if allocation ~= nil then
			outpost.ingest(outpost.revision() + 1, rules.copy(allocation))
		end
		core:transaction(function()
			phase:set("engaged")
			outcome:set(nil)
			exitReason:set(nil)
		end)
		seedDraft(outpost.binding:get())
		mutation.reset()
		publishState()
		return api.snapshot()
	end

	function api.setValue(id: string, value: number): any
		local consumer = rules.consumer(id)
		if consumer == nil then
			return { ok = false, message = rules.refusal("unknown", { id = id }) }
		end
		--[[ AN EDIT RETIRES THE LAST OUTCOME. The message line is one line and it
			has one job: say the most recent true thing. A success sentence left
			standing over a draft the player has since made illegal is the terminal
			lying about state it can see. ]]
		core:transaction(function()
			outcome:set(nil)
			draft[id]:set(math.clamp(math.floor(value), 0, consumer.capacity))
		end)
		publishState()
		return { ok = true, id = id, value = draft[id]:get() }
	end

	function api.adjust(id: string, delta: number): any
		local consumer = rules.consumer(id)
		if consumer == nil then
			return { ok = false, message = rules.refusal("unknown", { id = id }) }
		end
		return api.setValue(id, draft[id]:get() + delta)
	end

	function api.apply(): any
		return sendIntent("set", draftAllocation())
	end

	--[[ RESET IS A SERVER INTENT, not a local undo. "Reset puts the outpost back
		to its starting allocation" is a change to shared world state, so it takes
		the same road, the same validation and the same refusals as any other. ]]
	function api.reset(): any
		seedDraft(rules.START)
		return sendIntent("set", rules.copy(rules.START))
	end

	--[[ EXIT. The terminal's own control, and also where EVERY other exit path
		lands: cancel, out of range, out of line of sight, character removal, a
		streamed-out adornee, a scenario switch and teardown all call this with
		their own reason before the host resigns the surface. ]]
	function api.exit(reason: string?): any
		local was = phase:get()
		--[[ IDEMPOTENT, AND THE REASON IS A REAL LOOP. The Exit control calls this,
			this calls the host's `onExit`, and the host's release calls this again —
			because every OTHER exit originates on the host side and has to reach the
			screen. Returning early on an already-exited terminal is what makes the two
			directions one door instead of a cycle. ]]
		if was == "exited" then
			return { exited = true, from = was, reason = exitReason:get(), already = true }
		end
		core:transaction(function()
			phase:set("exited")
			exitReason:set(reason or "exit-control")
		end)
		--[[ IN-FLIGHT INPUT IS CANCELLED, not left hanging: `mutation.reset` is
			the documented escape from a request the server never answered, and
			without it the next engage would meet a terminal that refuses to send. ]]
		mutation.reset()
		publishState()
		if o.onExit ~= nil then
			o.onExit()
		end
		return { exited = true, from = was, reason = exitReason:get() }
	end

	-- ── what the host feeds back in ────────────────────────────────────────

	function api.confirm(requestId: number, result: any): any
		local before = rules.copy(outpost.binding:get())
		if result ~= nil and result.allocation ~= nil then
			outpost.ingest(result.revision or outpost.revision() + 1, rules.copy(result.allocation))
		end
		mutation.confirm(requestId, result)
		local after = rules.copy(outpost.binding:get())
		applied += 1
		outcome:set({ ok = true, code = "applied", message = rules.outcomeLine(before, after) })
		publishState()
		return api.snapshot()
	end

	function api.reject(requestId: number, reason: any): any
		mutation.reject(requestId, reason)
		local code = if type(reason) == "table" then reason.code else nil
		local message = if type(reason) == "table" and reason.message ~= nil
			then reason.message
			else rules.refusal("session")
		outcome:set({ ok = false, code = code, message = message })
		publishState()
		return api.snapshot()
	end

	-- an allocation change nobody on this client asked for (another player)
	function api.ingest(revision: number, allocation: rules.Allocation): any
		local verdict = outpost.ingest(revision, rules.copy(allocation))
		publishState()
		return { verdict = verdict, revision = outpost.revision() }
	end

	function api.snapshot(): any
		local out = outcome:get()
		return {
			phase = phase:get(),
			status = mutation.status:get(),
			draft = draftAllocation(),
			outpost = rules.copy(outpost.binding:get()),
			revision = outpost.revision(),
			verdict = draftVerdict:get(),
			canApply = canApply:get(),
			complete = rules.allRunning(outpost.binding:get()),
			message = messageLine:get(),
			messageTint = messageTint:get(),
			budget = budgetLine:get(),
			outcome = out,
			exitReason = exitReason:get(),
			counters = { sent = sent, refusedLocally = refusedLocally, applied = applied },
		}
	end

	-- ===== the screen =======================================================

	local controls: { any } = {}

	local function consumerRow(consumer: rules.Consumer): any
		local stepper = Facet.Controls.Stepper(core, {
			id = `{consumer.id}Step`,
			value = draft[consumer.id],
			min = 0,
			max = consumer.capacity,
			format = function(value: number): string
				return `{value}`
			end,
		})
		table.insert(controls, stepper)
		local state = scope:own(core:memo(function(use)
			local units = use(draft[consumer.id])
			local live = use(outpost.binding)
			local now = if units >= consumer.needs then consumer.running else consumer.idle
			local wasRunning = rules.isRunning(live, consumer.id)
			local willRun = units >= consumer.needs
			if wasRunning ~= willRun then
				return `{now} (on Apply)`
			end
			return now
		end))
		local stateTint = scope:own(core:memo(function(use)
			return if use(draft[consumer.id]) >= consumer.needs
				then { role = "accent", blend = 1 }
				else { role = "contentSecondary", blend = 1 }
		end))
		return UI.HStack({
			id = consumer.id,
			surface = "control",
			padding = "s",
			gap = "s",
			align = "center",
			width = UI.fill(),
			children = {
				UI.VStack({
					id = "Copy",
					gap = "tight",
					width = UI.fill(),
					children = {
						UI.Text({
							id = "Label",
							text = `{consumer.label} — needs {consumer.needs}`,
							textSize = "body",
						}),
						UI.Text({ id = "State", text = state, textSize = "caption", tint = stateTint }),
					},
				}),
				stepper.blueprint,
			},
		})
	end

	local rows: { any } = {}
	for _, consumer in rules.CONSUMERS do
		table.insert(rows, consumerRow(consumer))
	end

	local function action(id: string, label: string, role: string?, enabled: any?, onActivate: () -> ()): any
		return UI.Button({
			id = id,
			label = label,
			role = role,
			enabled = enabled,
			height = { type = "minMax", min = "targetSizes.minimum" },
			width = UI.fill(),
			onActivate = onActivate,
		})
	end

	local screen = UI.Screen({
		id = "OutpostTerminal",
		padding = "m",
		gap = "s",
		children = {
			UI.VStack({
				id = "Head",
				gap = "tight",
				width = UI.fill(),
				children = {
					UI.Text({ id = "Title", text = terminal.TITLE, textSize = "heading" }),
					UI.Text({ id = "Budget", text = budgetLine, textSize = "body", role = "secondary" }),
					UI.Text({ id = "Outpost", text = outpostLine, textSize = "caption", role = "secondary" }),
				},
			}),
			UI.VStack({
				id = "Consumers",
				gap = "s",
				width = UI.fill(),
				children = rows,
			}),
			UI.Text({
				id = "Message",
				text = messageLine,
				textSize = "body",
				tint = messageTint,
				width = UI.fill(),
			}),
			UI.HStack({
				id = "Actions",
				gap = "s",
				width = UI.fill(),
				children = {
					action("Apply", "Apply", nil, canApply, function()
						api.apply()
					end),
					action("Reset", "Reset", nil, nil, function()
						api.reset()
					end),
					action("Exit", "Exit", "cancel", nil, function()
						api.exit("exit-control")
					end),
				},
			}),
		},
	})

	--[[ THE PRESENT OPTIONS THIS SCREEN NEEDS, declared BY the screen rather than
		re-derived by each host — the walk-up contract in one place.

		`responder = "passive"` is the whole engagement story: the surface mounts
		inert (priority 3000, created disabled, sinking nothing) and only
		`handle.engage()` turns it into the one surface that receives Navigate,
		Activate and Cancel. That is what "triggering the prompt engages exactly ONE
		Facet responder and focus scope" means mechanically, and it is also what
		puts the terminal above the host screen's base band while it is live and
		back below it the instant it resigns.

		CANCEL IS DELIBERATELY LEFT AT ITS DEFAULT, which on a passive surface is
		not "dismiss" at all: the presenter RESIGNS an engaged-from-passive surface
		back to passive and disables its context (ADR-0014). That is precisely the
		Cancel exit this terminal wants — the mounted surface survives, so the
		player can walk up and press the prompt again — and it means the platform
		back action, the gamepad B button and the terminal's own Exit control all
		land in the same place instead of in three. A host learns it happened by
		observing `handle.responder`. ]]
	local present = {
		responder = "passive",
		keyboardNavigation = true,
		initialFocus = "first",
	}

	publishState()

	return {
		screen = screen,
		present = present,
		canvas = terminal.CANVAS,
		rules = rules,
		steps = api,
		outpost = outpost,
		mutation = mutation,
		draft = draft,
		phase = phase,
		report = api.snapshot,
		dispose = function()
			for _, control in controls do
				if control.dispose ~= nil then
					control.dispose()
				end
			end
			table.clear(controls)
			scope:dispose()
		end,
	}
end

return terminal
