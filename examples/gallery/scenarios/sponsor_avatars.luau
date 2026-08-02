--!strict
-- Scenario 'sponsor_avatars' (ledger rows SF-A1..SF-A4, SF-P2;
-- ui-designer-spec §8.6): the ASYNC-IMAGE LIFECYCLE — a grid of eight avatar
-- composites that load, fail silently, retry on a scripted clock, survive churn
-- without a stale face popping into a recycled slot, warm through the preload
-- seam, and take the dim treatment through the authored tint channel.
--
-- THE TRANSPORT IS THE FIXTURE'S, THE POLICY IS THE FRAMEWORK'S. Headlessly the
-- scenario answers `provider.pendingRequests()` itself, which is what makes every
-- timing here deterministic; in Studio the `liveTransport` step binds the real
-- Roblox transport through the runner's seam and the same report block records
-- what a real `rbxthumb://` fetch did (SF-A4).
--
-- The provider's clock is INJECTED from the presenter's own tick, so a "1 second
-- apart" retry is one second of the same time everything else on this surface
-- runs on — never `os.clock`, never a `task.delay`.

return {
	title = "Avatar lab (SF-A1..A4/P2)",
	ledgerRows = { "SF-A1", "SF-A2", "SF-A3", "SF-A4", "SF-P2", "SF-C1", "SF-C2", "SF-C3" },
	build = function(ctx: any)
		local LuauUI = ctx.LuauUI
		local UI = LuauUI.UI
		local core = ctx.core
		local env = ctx.env
		local pres = ctx.presenter
		local scope = core:scope("sponsor-avatars")

		local SCREEN = "/AvatarLab"
		local GRID = SCREEN .. "/Avatars"

		local trace: { any } = {}
		local elapsed = 0
		local function note(kind: string, info: any?)
			table.insert(trace, { at = elapsed, kind = kind, info = info })
		end
		scope:own(pres.onFeedback(function(event: any)
			table.insert(
				trace,
				{ at = elapsed, kind = "feedback:" .. tostring(event.type), info = { path = event.path } }
			)
		end))

		-- ===== the provider ==================================================
		-- RETRY IS A CALL-SITE DECISION (§6.6): three attempts a second apart, then
		-- the key is given up for the session. The clock is the presenter's.
		local RETRY = { count = 3, delaySeconds = 1 }
		-- NOT scope-owned: a provider is not disposable (its handles are — each
		-- `acquire` registers its own release on the caller's scope), so owning
		-- it here only ever read as ownership.
		local provider = LuauUI.newResourceProvider(core, {
			maxConcurrent = 4,
			now = function()
				return elapsed
			end,
			retry = RETRY,
		})

		-- the scripted transport: which keys are allowed to succeed, and how many
		-- times each key has been asked
		local failing: { [string]: boolean } = {}
		local attempts: { any } = {}
		local completions: { any } = {}
		local staleCompletions: { any } = {}
		local churnOutcomes: { any } = {}
		local autoDrain = scope:own(core:signal(true))
		local transportBound = scope:own(core:signal(false))

		local function drain()
			if not autoDrain:get() then
				return
			end
			for _, request in provider.pendingRequests() do
				table.insert(attempts, { at = elapsed, key = request.key, attempt = request.attempt })
				if failing[request.key] then
					local outcome = provider.fail(request.key, request.generation, "demo-transport-failure")
					note("transport:fail", { key = request.key, attempt = request.attempt, outcome = outcome })
				else
					local outcome = provider.complete(request.key, request.generation, `demo://{request.key}`)
					table.insert(completions, { at = elapsed, key = request.key, outcome = outcome })
					if outcome == "stale" then
						table.insert(staleCompletions, { at = elapsed, key = request.key })
					end
					note("transport:complete", { key = request.key, outcome = outcome })
				end
			end
		end

		-- ===== the composites ===============================================
		local FACE: any = { type = "fixed", px = "targetSizes.minimum" }
		local dimmed = scope:own(core:signal(false))
		local states: { [string]: any } = {}

		-- A COMPOSITE'S ROW KEY CARRIES A GENERATION, its provider key does not.
		-- Re-fetching is a remount — `provider.invalidate` drops a cached value but
		-- an already-`ready` handle keeps its state — so a fixture that wants a key
		-- fetched AGAIN has to give the row a new identity while asking the provider
		-- for the same content. That is what a real reload does, too.
		local generation = 0
		local function makeSet(n: number, offset: number?): { any }
			local out = {}
			for i = 1, n do
				local index = i + (offset or 0)
				table.insert(out, {
					key = string.format("av-%02d", index),
					rowKey = string.format("av-%02d#%d", index, generation),
					initial = string.char(64 + ((index - 1) % 26 + 1)),
				})
			end
			return out
		end

		local function reload(current: { any }?): { any }
			generation += 1
			local out: { any } = {}
			for _, item in (current or {}) do
				table.insert(out, {
					key = item.key,
					rowKey = `{item.key}#{generation}`,
					initial = item.initial,
				})
			end
			return out
		end

		local avatars = scope:own(core:signal(makeSet(8)))

		local rimStroke = scope:own(core:memo(function(use)
			-- the dim treatment's companion (§6.5): the rim goes further back at the
			-- same moment the picture does, so "dimmed" is two channels, not a hue
			return UI.strokeData({ color = "hairline", transparency = if use(dimmed) then 0.35 else 0 })
		end))

		local function composite(item: any, itemScope: any): any
			local image = LuauUI.newAsyncImage(LuauUI, core, {
				id = "Face",
				scope = itemScope,
				provider = provider,
				key = item.key,
				width = FACE,
				height = FACE,
				retry = RETRY,
				dimmed = dimmed,
			})
			states[item.key] = image.state
			local notReady = itemScope:own(core:memo(function(use)
				return use(image.state) ~= "ready"
			end))
			return UI.ZStack({
				id = "Avatar",
				-- the keyed row declares a `fade` enter, and a fading form needs a
				-- fade GROUP: the composite is the group, so the whole avatar fades as
				-- one unit through a single GroupTransparency write
				canvasGroup = true,
				width = FACE,
				height = FACE,
				children = {
					-- the presentable placeholder: a complete composite, never a spinner
					UI.corners(UI.Box({ id = "Fallback", surface = "raised", width = FACE, height = FACE }), "pill"),
					image.blueprint,
					UI.When({
						id = "InitialRegion",
						condition = notReady,
						thenView = function()
							return UI.Text({
								id = "Initial",
								text = item.initial,
								textSize = "label",
								textAlign = "center",
								width = FACE,
								height = FACE,
							})
						end,
					}),
					-- the rim is a BOUND stroke prop (the reactive idiom): one memo of
					-- `UI.strokeData`, so the dim state moves the border's transparency
					-- without ever stacking a second border on the node
					UI.corners(
						UI.Box({ id = "Rim", surface = "plain", stroke = rimStroke, width = FACE, height = FACE }),
						"pill"
					),
				},
			})
		end

		local function control(id: string, label: string, onActivate: () -> ())
			return UI.Button({
				id = id,
				label = label,
				height = { type = "minMax", min = "targetSizes.minimum" },
				onActivate = onActivate,
			})
		end

		local result: any = {}

		local plan: { { at: number, run: () -> () } } = {}
		local function schedule(delay: number, run: () -> ())
			table.insert(plan, { at = elapsed + delay, run = run })
		end

		scope:own(pres.onTick(function(dt: number)
			elapsed += dt
			if #plan > 0 then
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
			-- cross the injected clock so a spaced retry becomes due, then answer
			-- whatever the window holds
			provider.tick()
			drain()
		end))

		local screen = UI.Screen({
			id = "AvatarLab",
			padding = "m",
			gap = "m",
			children = {
				UI.Text({ id = "Title", text = "Avatar lab", textSize = "heading" }),
				-- WRAPS TO FEWER COLUMNS rather than shrinking the circles below the
				-- face floor: the grid derives its column count from a minimum width
				UI.Grid({
					id = "Avatars",
					minColumnWidth = 56,
					gap = "s",
					rowGap = "s",
					width = { type = "fill", weight = 1 },
					children = {
						UI.ForEach({
							id = "Set",
							items = avatars,
							key = function(item: any)
								return item.rowKey
							end,
							row = composite,
							transition = { enter = "fade", class = "container" },
						}),
					},
				}),
				UI.Grid({
					id = "Controls",
					minColumnWidth = 104,
					gap = "s",
					rowGap = "s",
					width = { type = "fill", weight = 1 },
					children = {
						control("BtnLoad", "Load", function()
							autoDrain:set(true)
						end),
						control("BtnFail", "Fail", function()
							for index, item in avatars:get() :: { any } do
								if index % 2 == 0 then
									failing[item.key] = true
									provider.invalidate(item.key)
								end
							end
						end),
						control("BtnChurn", "Churn", function()
							avatars:set(makeSet(8, 8))
						end),
						control("BtnPreload", "Preload", function()
							provider.preload({ "av-97", "av-98" })
						end),
						control("BtnDim", "Dim", function()
							dimmed:set(not dimmed:get())
						end),
					},
				}),
			},
		})

		local function stateSnapshot(): { [string]: string }
			local out: { [string]: string } = {}
			for _, item in avatars:get() :: { any } do
				local state = states[item.key]
				out[item.key] = if state ~= nil then tostring(state:get()) else "unmounted"
			end
			return out
		end

		local function markMounted(): any
			-- SF-A1's evidence: is anything painted on a FAILED avatar beyond its
			-- placeholder? The runner answers geometry for mounted paths only, so a
			-- present rect means the node exists.
			if ctx.geometry == nil then
				return nil
			end
			local paths: { string } = {}
			for _, item in avatars:get() :: { any } do
				table.insert(paths, `{GRID}/Set/[{item.rowKey}]/Avatar/Face/Failure/then/Mark`)
				table.insert(paths, `{GRID}/Set/[{item.rowKey}]/Avatar/Face/Placeholder/then/Fill`)
			end
			local geometry = ctx.geometry(paths)
			local marks, placeholders = {}, {}
			for path, rect in geometry do
				if string.find(path, "/Failure/then/Mark", 1, true) ~= nil then
					table.insert(marks, path)
				else
					table.insert(placeholders, { path = path, rect = rect })
				end
			end
			table.sort(marks)
			return { failureMarks = marks, placeholders = #placeholders }
		end

		result.screen = screen
		result.present = {}
		result.steps = {
			-- staggered ready: the transport answers each key a beat apart, so the
			-- fade-ins are visibly staggered rather than one flash
			load = function()
				failing = {}
				autoDrain:set(false)
				local current = avatars:get() :: { any }
				avatars:set(reload(current))
				pres.refresh()
				local keys: { string } = {}
				for _, item in avatars:get() :: { any } do
					table.insert(keys, item.key)
				end
				for index, request in provider.pendingRequests() do
					local key, generation = request.key, request.generation
					schedule(0.15 * index, function()
						local outcome = provider.complete(key, generation, `demo://{key}`)
						table.insert(completions, { at = elapsed, key = key, outcome = outcome })
						note("load:complete", { key = key, outcome = outcome })
					end)
				end
				schedule(0.15 * (#keys + 1), function()
					autoDrain:set(true)
				end)
				return { keys = keys, staggerSeconds = 0.15, pending = #provider.pendingRequests() }
			end,
			-- SF-A1: half the set is forced to fail. The placeholder must persist and
			-- nothing may announce the failure on screen; the provider still reports
			-- `failed` for instrumentation.
			fail = function()
				local failed: { string } = {}
				local current = avatars:get() :: { any }
				for index, item in current do
					if index % 2 == 0 then
						failing[item.key] = true
						table.insert(failed, item.key)
						provider.invalidate(item.key)
					end
				end
				-- remount the grid so every key is fetched again: half the set now
				-- fails at the transport and must stay presentable anyway
				avatars:set(reload(current))
				pres.refresh()
				note("fail:forced", { keys = failed })
				return { forced = failed, states = stateSnapshot() }
			end,
			-- SF-A2: three attempts, a second apart, then given up for the session
			retrySchedule = function()
				attempts = {}
				local current = avatars:get() :: { any }
				local key = current[1].key
				failing[key] = true
				provider.invalidate(key)
				avatars:set(reload(current))
				pres.refresh()
				note("retry:begin", { key = key, policy = RETRY })
				return { key = key, policy = RETRY }
			end,
			retryRead = function()
				local key = (avatars:get() :: any)[1].key
				local mine: { any } = {}
				for _, attempt in attempts do
					if attempt.key == key then
						table.insert(mine, attempt)
					end
				end
				return {
					key = key,
					attempts = mine,
					gaveUp = provider.gaveUp(key),
					state = if states[key] ~= nil then states[key]:get() else nil,
				}
			end,
			-- SF-A2's churn clause: release and remount the set while fetches are in
			-- flight; a completion for a released generation must never paint
			churnStale = function()
				autoDrain:set(false)
				staleCompletions = {}
				churnOutcomes = {}
				local captured: { any } = {}
				for _, request in provider.pendingRequests() do
					table.insert(captured, { key = request.key, generation = request.generation })
				end
				-- the rows leave. A departing keyed row RETIRES rather than vanishing
				-- (the fade's mirrored exit), so its item scope — and the provider
				-- handle it owns — is still alive until the exit completes. The
				-- completions therefore land AFTER the exit, which is the only moment
				-- "the row is gone and the answer arrived anyway" is a real test.
				avatars:set(makeSet(8, 8))
				pres.refresh()
				schedule(0.6, function()
					for _, request in captured do
						local outcome = provider.complete(request.key, request.generation, `demo://{request.key}`)
						table.insert(churnOutcomes, { key = request.key, outcome = outcome })
						if outcome == "stale" then
							table.insert(staleCompletions, { at = elapsed, key = request.key })
						end
					end
					autoDrain:set(true)
					note("churnStale:completed", { outcomes = churnOutcomes, stale = #staleCompletions })
				end)
				note("churnStale:released", { released = #captured })
				return { released = #captured, pending = true, completeAfterSeconds = 0.6 }
			end,
			churnStaleRead = function()
				return { outcomes = churnOutcomes, stale = #staleCompletions, states = stateSnapshot() }
			end,
			-- SF-A3: a declared set warms, so a debuting composite skips the
			-- placeholder flash entirely
			preload = function()
				local keys = { "av-97", "av-98" }
				local warm = provider.preload(keys)
				for _, request in provider.pendingRequests() do
					if request.key == "av-97" or request.key == "av-98" then
						provider.complete(request.key, request.generation, `demo://{request.key}`)
					end
				end
				local set = avatars:get() :: { any }
				local next = table.clone(set)
				table.insert(next, { key = "av-97", rowKey = `av-97#{generation}`, initial = "Y" })
				table.insert(next, { key = "av-98", rowKey = `av-98#{generation}`, initial = "Z" })
				avatars:set(next)
				pres.refresh()
				local debut = if states["av-97"] ~= nil then states["av-97"]:get() else nil
				note("preload", { keys = warm.keys, debutState = debut })
				return { keys = warm.keys, debutState = debut, skippedPlaceholder = debut == "ready" }
			end,
			-- SF-P2: the dim treatment, on the authored tint channel plus the rim
			dim = function()
				dimmed:set(not dimmed:get())
				note("dim", { dimmed = dimmed:get() })
				return { dimmed = dimmed:get() }
			end,
			-- SF-A4: the real Roblox transport, Studio only. Headlessly the seam is
			-- absent and the step says so rather than pretending it ran.
			liveTransport = function()
				if ctx.bindResourceTransport == nil then
					return { bound = false, reason = "no engine transport seam (headless run)" }
				end
				autoDrain:set(false)
				local unbind = ctx.bindResourceTransport(provider)
				scope:own(unbind)
				transportBound:set(true)
				local live = {
					{
						key = "rbxthumb://type=AvatarHeadShot&id=1&w=48&h=48",
						rowKey = `live-head#{generation}`,
						initial = "R",
					},
					-- a content id that cannot resolve: the forced-failure half of SF-A4
					{ key = "rbxassetid://0", rowKey = `live-fail#{generation}`, initial = "F" },
				}
				local next = table.clone(avatars:get() :: { any })
				for _, entry in live do
					table.insert(next, entry)
				end
				avatars:set(next)
				note("liveTransport", { keys = { live[1].key, live[2].key } })
				return { bound = true, keys = { live[1].key, live[2].key } }
			end,
			states = function()
				return { states = stateSnapshot(), marks = markMounted() }
			end,
		}
		result.report = function()
			return {
				ledger = "SF-A1/SF-A2/SF-A3/SF-A4/SF-P2",
				elapsed = elapsed,
				trace = trace,
				states = stateSnapshot(),
				-- SF-A1's row reads this: a failed avatar must show NOTHING beyond its
				-- placeholder. `failureMarks` names every mark node the tree actually
				-- carries, so the claim is machine-checkable rather than eyeballed.
				marks = markMounted(),
				attempts = attempts,
				completions = completions,
				staleCompletions = staleCompletions,
				churnOutcomes = churnOutcomes,
				retryPolicy = RETRY,
				providerCounters = provider.counters(),
				gaveUp = (function()
					local out: { [string]: boolean } = {}
					for _, item in avatars:get() :: { any } do
						out[item.key] = provider.gaveUp(item.key)
					end
					return out
				end)(),
				dimmed = dimmed:get(),
				transportBound = transportBound:get(),
				keys = (function()
					local out: { string } = {}
					for _, item in avatars:get() :: { any } do
						table.insert(out, item.key)
					end
					return out
				end)(),
				reducedMotion = env:get("reducedMotion"):get(),
				counters = core:counters(),
				coreError = core:lastError(),
			}
		end
		result.dispose = function()
			scope:dispose()
		end
		return result
	end,
}
