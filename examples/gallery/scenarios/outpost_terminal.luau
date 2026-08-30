--!strict
--[[ Scenario 'outpost_terminal': FLAT FACET ON A WORLD SURFACE — a console the
	player walks up to and uses (ADR-0063; design
	artifacts/example-games-and-standalones/design/outpost-power-terminal.md).

	TWO HALVES, THE SAME SPLIT EVERY WORLD FIXTURE IN THIS FOLDER USES. The
	terminal's screen is a blueprint declared by
	`ReplicatedStorage.FacetExamples.outpost_terminal` — the SAME module the
	standalone place mounts, verbatim, with no showcase fork. Painting it on a
	`SurfaceGui` over a console part, loading a character to walk with, and
	putting an intent on a `RemoteEvent` are all engine work, so they go through
	the runner's `ctx.surface` seam exactly as the billboard's world anchor goes
	through `ctx.billboard`. This file stays engine-free.

	ON A HOST WITH NO ENGINE the seam is absent, and every step here says so
	instead of pretending it ran — which is what lets the headless sweep mount
	this surface at nine viewports under five packages and get an honest answer.

	WHAT THE COMPANION SCREEN IS FOR. The terminal itself is on the console, in
	the world; this ScreenGui is the LAB around it — what the fixture is doing,
	which of the eight exits fired last, whether the chosen face actually points
	at the player, and the buttons that drive each path once. It is not the demo.
	The demo is the thing on the wall.

	THE FACE. `Back` is the +Z face of an unrotated part, and the console is
	unrotated at z = -24 with the player spawning at z = -8 — so `Back`'s world
	normal points straight at where a player stands. `Front` would have been the
	-Z face, painting the terminal on the side facing away, where it renders
	perfectly, measures perfectly, and can never be clicked. `faceCheck` asserts
	it rather than trusting the arithmetic. ]]

local CANVAS = { w = 640, h = 480 }

--[[ THE CONTENT MODULE, RESOLVED LAZILY AND NEVER AT MODULE SCOPE. Lune resolves
	a relative require by FILE-SYSTEM path and live Rojo/Studio resolves the
	identical string by INSTANCE-TREE depth, and the two disagree the moment a
	module reaches out of its own mount — `FacetScenarios` and `FacetExamples` are
	SIBLINGS in the built place, not nested. So: engine route first (the real one),
	file route second (Lune only, where `game` does not exist at all), both
	pcall-guarded, inside a function. `tools/lune/check_scenario_requires` exists
	because three modules shipped without this shape. ]]
local function resolveTerminal(): (any?, string?)
	local reasons: { string } = {}
	local engineOk, engineResult = pcall(function(): any
		return require((game :: any):GetService("ReplicatedStorage").FacetExamples.outpost_terminal)
	end)
	if engineOk and engineResult ~= nil then
		return engineResult, nil
	end
	table.insert(reasons, `engine route: {tostring(engineResult)}`)
	local fileOk, fileResult = pcall(function(): any
		return require("../examples/outpost_terminal")
	end)
	if fileOk and fileResult ~= nil then
		return fileResult, nil
	end
	table.insert(reasons, `file route: {tostring(fileResult)}`)
	return nil, table.concat(reasons, " | ")
end

return {
	title = "Outpost power terminal (world surface)",
	ledgerRows = { "WORLD-1" },
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("outpost-terminal-scenario")

		local terminalModule, resolveError = resolveTerminal()
		local rules = if terminalModule ~= nil then terminalModule.rules else nil

		local trace: { any } = {}
		local function note(kind: string, info: any?)
			table.insert(trace, { at = os.clock(), kind = kind, info = info })
		end

		-- ===== what the lab knows ==========================================

		local surfaceState = scope:own(core:signal("not opened"))
		local lastExit = scope:own(core:signal("—"))
		local terminalState = scope:own(core:signal(nil :: any))
		local faceLine = scope:own(core:signal("face: not checked"))

		local function seam(): any
			return ctx.surface
		end

		local function absent(): any
			surfaceState:set("seam absent")
			return { ok = false, reason = "no surface seam on this host (headless run)" }
		end

		--[[ THE ONE CALLBACK SET THE RUNNER HANDS TO THE CONTENT MODULE. The
			scenario decides what a server reply MEANS to the terminal; the runner only
			carries it. `send`/`exit` come the other way — the terminal calls them, the
			runner puts them on the wire and resigns the surface. ]]
		local function buildTerminal(host: any): any
			local built = terminalModule.build(Facet, host.core, {
				send = host.send,
				onExit = function()
					host.exit("exit-control")
				end,
				onState = function(state: any)
					terminalState:set(state)
				end,
			})
			return {
				screen = built.screen,
				present = built.present,
				report = built.report,
				dispose = built.dispose,
				-- the prompt was triggered and the SERVER issued a session token
				onEngage = function(allocation: any)
					built.steps.engage(allocation)
				end,
				-- an exit, whichever of the eight it was
				onExit = function(reason: string)
					built.steps.exit(reason)
					lastExit:set(reason)
					note("exit", reason)
				end,
				-- the outpost changed under us (another player, or a reset)
				onState = function(payload: any)
					built.steps.ingest(payload.revision, payload.allocation)
				end,
				-- the verdict on one Apply
				onVerdict = function(payload: any)
					if payload.ok then
						built.steps.confirm(payload.requestId, payload)
					else
						built.steps.reject(payload.requestId, payload)
					end
					note("verdict", { ok = payload.ok, code = payload.code })
				end,
				steps = built.steps,
			}
		end

		local function open(): any
			local api = seam()
			if api == nil then
				return absent()
			end
			local dump = api.open({
				canvas = CANVAS,
				-- the face, named rather than defaulted: see the header
				face = "Back",
				range = if rules ~= nil then rules.RANGE else 10,
				maxDistance = 64,
				build = buildTerminal,
				onEngage = function(source: string?)
					surfaceState:set(`engaged ({source or "step"})`)
					note("engage", source)
				end,
				onRelease = function(reason: string)
					surfaceState:set(`released ({reason})`)
					lastExit:set(reason)
				end,
			})
			surfaceState:set(if dump.open then "open" else `failed: {tostring(dump.error)}`)
			if dump.faceCheck ~= nil and dump.faceCheck.checked then
				faceLine:set(
					`face {dump.faceCheck.face}: dot {string.format("%.2f", dump.faceCheck.dot)} `
						.. `({if dump.faceCheck.pointsAtViewer then "points at the player" else "POINTS AWAY"})`
				)
			end
			note("open", dump)
			return dump
		end

		-- ===== the lab's readouts ==========================================

		local statusLine = scope:own(core:memo(function(use)
			return `surface: {use(surfaceState)} — last exit: {use(lastExit)}`
		end))

		local terminalLine = scope:own(core:memo(function(use)
			local state = use(terminalState)
			if state == nil then
				return "terminal: not mounted"
			end
			local draft = state.draft or {}
			local live = state.outpost or {}
			return `terminal: {state.phase}/{state.status} — draft {draft.door or 0}/{draft.beacon or 0}/`
				.. `{draft.workshop or 0}, outpost {live.door or 0}/{live.beacon or 0}/{live.workshop or 0}`
				.. `{if state.complete then " — ALL RUNNING" else ""}`
		end))

		local outcomeLine = scope:own(core:memo(function(use)
			local state = use(terminalState)
			if state == nil or state.outcome == nil then
				return "outcome: —"
			end
			return `outcome: {state.outcome.message}`
		end))

		--[[ THE RULES, ON SCREEN. The lab prints the same table the terminal and the
			server both read, so a reviewer standing at the console can check the
			numbers against the thing enforcing them. ]]
		local rulesLine = if rules == nil
			then `rules unavailable: {tostring(resolveError)}`
			else (function(): string
				local parts: { string } = {}
				for _, consumer in rules.CONSUMERS do
					table.insert(parts, `{consumer.label} {consumer.needs}..{consumer.capacity}`)
				end
				return `{rules.TOTAL} units — ` .. table.concat(parts, ", ")
			end)()

		-- ===== the drive surface ===========================================

		local function withSeam(fn: (any) -> any): any
			local api = seam()
			if api == nil then
				return absent()
			end
			return fn(api)
		end

		--[[ A RAW COMMAND, DELIBERATELY UNVALIDATED ON THIS SIDE. The terminal
			refuses an illegal allocation before it spends a round trip, which is
			exactly what makes it useless for proving the SERVER refuses one. These
			steps go around the terminal and put the bad intent on the wire directly —
			which is also, precisely, what an unfriendly client would do. ]]
		local function rawApply(allocation: any, token: string?): any
			return withSeam(function(api)
				local payload: any = { requestId = -1, allocation = allocation }
				if token ~= nil then
					payload.token = token
				end
				local sent = api.command("apply", payload)
				note("rawApply", { allocation = allocation, token = token, sent = sent.sent })
				return { sent = sent, replies = api.replies() }
			end)
		end

		local steps: { [string]: (any, string?) -> any } = {}

		steps.open = function()
			return open()
		end
		steps.dump = function()
			return withSeam(function(api)
				return api.dump()
			end)
		end
		steps.replies = function()
			return withSeam(function(api)
				return api.replies()
			end)
		end
		steps.faceCheck = function()
			return withSeam(function(api)
				local check = api.faceCheck()
				note("faceCheck", check)
				return check
			end)
		end
		-- the walk-up, driven as STATE (the native prompt press is native-input
		-- territory and rides the MCP input tools in the live proof)
		steps.engage = function()
			return withSeam(function(api)
				return api.engage("step")
			end)
		end
		--[[ THE TERMINAL'S OWN VERBS. They live on the SURFACE host's core, which
			this module deliberately has no handle on — the seam is the one door, and
			`setValue` is the same call the stepper's + and - make. ]]
		steps.setValue = function(_built: any, payload: string?)
			local id, value = string.match(payload or "", "^(%a+):(%-?%d+)$")
			if id == nil then
				return { ok = false, reason = "payload is '<consumer>:<units>', e.g. door:2" }
			end
			return withSeam(function(api)
				return api.terminalStep("setValue", id, tonumber(value))
			end)
		end
		steps.apply = function()
			return withSeam(function(api)
				return api.terminalStep("apply")
			end)
		end
		steps.resetOutpost = function()
			return withSeam(function(api)
				return api.terminalStep("reset")
			end)
		end
		steps.solve = function()
			--[[ THE WINNING ALLOCATION, IN ONE STEP. 2 + 1 + 2 = 5 gets all three
				running with a unit spare; a matrix driver should not have to know the
				answer to take a screenshot of the success state. ]]
			return withSeam(function(api)
				api.terminalStep("setValue", "door", 2)
				api.terminalStep("setValue", "beacon", 1)
				api.terminalStep("setValue", "workshop", 2)
				return api.terminalStep("apply")
			end)
		end
		steps.terminal = function()
			return withSeam(function(api)
				return api.terminalStep("snapshot")
			end)
		end
		steps.rules = function()
			if rules == nil then
				return { available = false, reason = resolveError }
			end
			local out: { any } = {}
			for _, consumer in rules.CONSUMERS do
				table.insert(out, {
					id = consumer.id,
					label = consumer.label,
					needs = consumer.needs,
					capacity = consumer.capacity,
				})
			end
			return {
				available = true,
				total = rules.TOTAL,
				range = rules.RANGE,
				minInterval = rules.MIN_COMMAND_INTERVAL,
				start = rules.START,
				objective = rules.OBJECTIVE,
				consumers = out,
			}
		end
		-- ── the five server refusals, each driven once ──────────────────────
		steps.refuseRange = function()
			return rawApply({ door = 9, beacon = 0, workshop = 0 })
		end
		steps.refuseBudget = function()
			return rawApply({ door = 3, beacon = 2, workshop = 4 })
		end
		steps.refuseStale = function()
			return rawApply({ door = 2, beacon = 1, workshop = 2 }, "stale-token")
		end
		steps.refuseFast = function()
			local first = rawApply({ door = 2, beacon = 1, workshop = 2 })
			local second = rawApply({ door = 2, beacon = 1, workshop = 2 })
			return { first = first, second = second }
		end
		steps.refuseFar = function()
			return withSeam(function(api)
				local moved = api.placeCharacter(40)
				local sent = rawApply({ door = 2, beacon = 1, workshop = 2 })
				return { moved = moved, sent = sent }
			end)
		end
		steps.walkBack = function()
			return withSeam(function(api)
				return api.placeCharacter(6)
			end)
		end
		-- ── the eight exits, each driven once ───────────────────────────────
		local function exitStep(reason: string)
			return function()
				return withSeam(function(api)
					local before = api.dump()
					local released = api.release(reason)
					return { reason = reason, released = released, before = before, after = api.dump() }
				end)
			end
		end
		steps.exitCancel = exitStep("cancel")
		--[[ THE EXIT CONTROL IS THE TERMINAL'S OWN BUTTON, not a release call: it
			runs the screen's `exit`, which is what then asks the host to resign. Every
			other row here drives the host directly, because that is where those seven
			exits actually originate. ]]
		steps.exitControl = function()
			return withSeam(function(api)
				local stepped = api.terminalStep("exit", "exit-control")
				return { stepped = stepped, after = api.dump() }
			end)
		end
		steps.exitOutOfRange = exitStep("out-of-range")
		steps.exitLineOfSight = exitStep("line-of-sight")
		steps.exitCharacter = function()
			return withSeam(function(api)
				api.command("character", { action = "remove" })
				return { requested = "character-removed", after = api.dump() }
			end)
		end
		steps.exitAdornee = function()
			return withSeam(function(api)
				api.command("console", { action = "remove" })
				return { requested = "adornee-lost", after = api.dump() }
			end)
		end
		steps.restoreConsole = function()
			--[[ A DESTROYED ADORNEE CANNOT BE RE-ADOPTED — `surface_target` holds the
				part it was constructed with, and `.Adornee` still names the destroyed
				one (which is exactly why the adapter has to watch the instance's own
				lifetime rather than read that property). So restoring the console is a
				NEW fixture and a NEW surface, which is what a stream-IN is. ]]
			return withSeam(function(api)
				api.teardown()
				return open()
			end)
		end
		steps.teardown = function()
			return withSeam(function(api)
				local dump = api.teardown()
				surfaceState:set("torn down")
				note("teardown", dump)
				return dump
			end)
		end
		--[[ REPEATED TRIGGER-THEN-CANCEL, which the design requires to be safe. The
			surface stays MOUNTED across every cycle — engaging and resigning a
			responder is the cheap operation, and rebuilding a host per press is the
			expensive mistake this shape exists to avoid. ]]
		steps.cycle = function(_built: any, payload: string?)
			return withSeam(function(api)
				local times = tonumber(payload or "20") or 20
				for _ = 1, times do
					api.engage("cycle")
					api.release("cancel")
				end
				local after = api.dump()
				note("cycle", { cycles = times, after = after })
				return { cycles = times, after = after }
			end)
		end

		-- ===== the lab screen ==============================================

		local function control(id: string, label: string, onActivate: () -> ()): any
			return UI.Button({
				id = id,
				label = label,
				height = { type = "minMax", min = "targetSizes.minimum" },
				onActivate = onActivate,
			})
		end

		local screen = UI.Screen({
			id = "OutpostLab",
			padding = "m",
			gap = "m",
			children = {
				--[[ THE READOUTS SCROLL AND THE CONTROLS DO NOT, which is the packing
					the sibling world fixture (`sponsor_billboard`) learned the hard way: a
					`fill` Spacer gives its pixels back to nobody, so a narrow landscape
					phone put every labelled control below the fold with no page scroller
					to reach it. A `fill` ScrollView does the Spacer's job AND is a place
					the readouts can be read from. ]]
				UI.ScrollView({
					id = "Readouts",
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.Text({ id = "Title", text = "Outpost power terminal", textSize = "heading" }),
						UI.Text({
							id = "Lead",
							text = "The terminal is on the console in the world. Walk up and use it.",
							textSize = "caption",
							role = "secondary",
						}),
						UI.Text({ id = "Status", text = statusLine, textSize = "caption", role = "secondary" }),
						UI.Text({ id = "Terminal", text = terminalLine, textSize = "caption", role = "secondary" }),
						UI.Text({ id = "Outcome", text = outcomeLine, textSize = "caption", role = "secondary" }),
						UI.Text({ id = "Face", text = faceLine, textSize = "caption", role = "secondary" }),
						UI.Text({ id = "Rules", text = rulesLine, textSize = "caption", role = "secondary" }),
					},
				}),
				UI.Grid({
					id = "Controls",
					-- a packing floor rather than a font guess: this asks how many
					-- controls fit a row and lets a long label compact
					minColumnWidth = 104,
					gap = "s",
					rowGap = "s",
					width = UI.fill(),
					--[[ FIVE BUTTONS, AND THE COUNT IS A MEASUREMENT. At `minColumnWidth`
					104 a 640x320 landscape phone fits five columns, so five controls are
					one row and six are two — and the second row is 40px more than the
					leftover has at the largest text preference, measured, on exactly that
					viewport. The other twelve drives are steps: a matrix driver calls
					them by name, and a person at the console does not need them.
					`Solve` is here because a driver taking a screenshot of the success
					state should not have to know that 2 + 1 + 2 is the answer. ]]
					children = {
						control("BtnOpen", "Open", function()
							open()
						end),
						control("BtnEngage", "Engage", function()
							steps.engage(nil)
						end),
						control("BtnSolve", "Solve", function()
							steps.solve(nil)
						end),
						control("BtnCancel", "Cancel", function()
							steps.exitCancel(nil)
						end),
						control("BtnTeardown", "Teardown", function()
							steps.teardown(nil)
						end),
					},
				}),
			},
		})

		local result: any = {}
		result.screen = screen
		result.present = {}
		result.steps = steps
		result.report = function()
			local api = seam()
			return {
				ledger = "WORLD-1",
				canvas = CANVAS,
				face = "Back",
				surfaceState = surfaceState:get(),
				lastExit = lastExit:get(),
				terminal = terminalState:get(),
				rulesLine = rulesLine,
				resolveError = resolveError,
				trace = trace,
				surface = if api ~= nil then api.dump() else { open = false, seam = "absent" },
				focusPath = ctx.presenter.focus.focused:get(),
				counters = core:counters(),
				coreError = core:lastError(),
			}
		end
		result.dispose = function()
			local api = seam()
			if api ~= nil then
				api.teardown()
			end
			scope:dispose()
		end
		return result
	end,
}
