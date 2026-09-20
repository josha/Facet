--!strict
-- Scenario 'sponsor_billboard' (ledger row SF-W1; ui-designer-spec §8.8): the
-- DISPLAY-ONLY WORLD-ANCHORED surface — a depleting ring over a fixture part,
-- driven by the same motion clock and torn down registry-neutral.
--
-- TWO HALVES, ON PURPOSE. The billboard content is a blueprint this file
-- declares; mounting it over a world part is engine work, so it goes through the
-- runner's `ctx.billboard` seam (the same shape as the resource transport). On a
-- host with no engine the seam is absent and every step says so instead of
-- pretending it ran — the pure halves (the depleting timer, the render-vs-record
-- predicate, the blueprint) still run and are still asserted.
--
-- THE SCOPING PREDICATE IS PURE (SF-W1's E1 half). `shouldRender(state)` decides
-- whether the omen is PAINTED; whether it is RECORDED is a different question and
-- the answer stays yes either way — the timer keeps depleting to the same
-- wall-clock terminus while the ring is unmounted, which is what "render vs
-- record" has to mean for the data not to lie.

local newLifetime = require("./lifetime")

return {
	title = "Billboard lab (SF-W1)",
	ledgerRows = { "SF-W1", "SF-M5", "SF-C1", "SF-C3" },
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI, Compose = ctx.UI, ctx.Compose
		local core = ctx.core
		local env = ctx.env
		local pres = ctx.presenter
		local shapes = Facet.pathShapes
		local lifetime = newLifetime(Compose)
		local own = lifetime.own
		local clock = pres.motionClock

		local CANVAS = { w = 320, h = 220 }
		local DEPLETE_SECONDS = 5

		local trace: { any } = {}
		local elapsed = 0
		local function note(kind: string, info: any?)
			table.insert(trace, { at = elapsed, kind = kind, info = info })
		end

		-- ===== state ========================================================
		-- the omen's remaining fraction. A TIMER, not a spring: it owes a
		-- wall-clock terminus, and under reduced motion the `informational` kind
		-- quantizes its writes to 250 ms steps and still lands at zero at the same
		-- moment (finding F10's stepped policy).
		local fraction = Compose.cell(1)
		local timer: any = nil
		local timerDone = Compose.cell(false)
		local recording = Compose.cell(true)
		local rendering = Compose.cell(true)
		local depleteRuns = 0

		-- THE PURE PREDICATE (E1). Render is a presentation decision; recording is
		-- a data decision. They are separate answers and only one of them may ever
		-- be false at a time on this fixture.
		local function shouldRender(state: { recording: boolean, inScope: boolean }): boolean
			return state.recording and state.inScope
		end

		local renderScope = Compose.formula(function(use)
			return shouldRender({ recording = use(recording), inScope = use(rendering) })
		end)

		local ringPoints = Compose.formula(function(use)
			local value = math.clamp(use(fraction), 0, 1)
			return shapes.arc(0, 360 * value, { segments = 8, radius = 0.86 })
		end)
		local caption = Compose.formula(function(use)
			return string.format("omen %d%%", math.floor(use(fraction) * 100 + 0.5))
		end)

		-- ===== the billboard blueprint ======================================
		-- display-only: no focusables, no pointer capture (the billboard riders stay
		-- out of scope), so nothing here is a Button and nothing is `focusable`
		local RING: any = { type = "fixed", px = 160 }
		-- Built with the billboard application's own controls: the omen lives in
		-- that application, not in the lab screen's.
		local function billboardBlueprint(UI: any)
			return UI.ZStack("Omen")({
				width = UI.fill(),
				height = UI.fill(),

				UI.When("RenderScope")({
					Compose.show(renderScope, function()
						return UI.ZStack("Composite")({
							canvasGroup = true,
							width = UI.fill(),
							height = UI.fill(),

							UI.Path("Track")({
								points = shapes.ring({ radius = 0.86 }),
								thickness = 4,
								role = "secondary",
								alignH = "center",
								alignV = "center",
								width = RING,
								height = RING,
							}),
							UI.Path("Arc")({
								points = ringPoints,
								thickness = 10,
								role = "accent",
								alignH = "center",
								alignV = "center",
								width = RING,
								height = RING,
							}),
							UI.corners(
								UI.Box("IconSlot")({
									surface = "accent",
									alignH = "center",
									alignV = "center",
									width = { type = "fixed", px = "controlSizes.regular.height" },
									height = { type = "fixed", px = "controlSizes.regular.height" },
								}),
								"pill"
							),
							UI.Text("Caption")({
								text = caption,
								textSize = "caption",
								textAlign = "center",
								alignH = "center",
								alignV = "end",
								width = UI.fill(),
							}),
						})
					end),
				}),
			})
		end

		-- ===== the companion screen =========================================
		local statusLine = Compose.formula(function(use)
			return string.format(
				"omen %d%% — render:%s record:%s",
				math.floor(use(fraction) * 100 + 0.5),
				tostring(use(renderScope)),
				tostring(use(recording))
			)
		end)

		local billboardState = Compose.cell("not mounted")

		local function seam(): any
			return ctx.billboard
		end

		local function mountBillboard(): any
			local api = seam()
			if api == nil then
				billboardState:set("seam absent")
				return { mounted = false, reason = "no billboard seam on this host (headless run)" }
			end
			local dump = api.mount({ screen = billboardBlueprint, canvas = CANVAS })
			billboardState:set(if dump.mounted then "mounted" else "failed")
			note("billboard:mount", dump)
			return dump
		end

		local function tearDownBillboard(): any
			local api = seam()
			if api == nil then
				billboardState:set("seam absent")
				return { torn = false, reason = "no billboard seam on this host (headless run)" }
			end
			local dump = api.teardown()
			billboardState:set("torn down")
			note("billboard:teardown", dump)
			return dump
		end

		local function startDeplete(): any
			if timer ~= nil then
				timer:dispose()
				timer = nil
			end
			timerDone:set(false)
			depleteRuns += 1
			fraction:set(1)
			timer = own(clock:timer({ from = 1, to = 0, duration = DEPLETE_SECONDS }))
			-- the timer is a Readable; mirroring it into the fixture's own signal is
			-- what lets the ring and the caption read one value
			local running = timer
			lifetime.watch(function(use)
				if timer ~= running then
					return
				end
				local value = use(running)
				fraction:set(value)
				if value <= 0 then
					timerDone:set(true)
				end
			end)
			note("deplete:start", { duration = DEPLETE_SECONDS, kind = timer:motionKind() })
			return { duration = DEPLETE_SECONDS, kind = timer:motionKind(), run = depleteRuns }
		end

		local result: any = {}

		own(pres.onTick(function(dt: number)
			elapsed += dt
			local api = seam()
			if api ~= nil then
				-- the billboard is its own render target: a paint-only binding lands
				-- on its own, and this keeps its layout honest across a canvas change
				api.refresh()
			end
		end))

		local function control(id: string, label: string, onActivate: () -> ())
			return UI.Button(id)({
				label = label,
				height = { type = "minMax", min = "targetSizes.minimum" },
				onActivate = onActivate,
			})
		end

		local function screen()
			return UI.Screen("BillboardLab")({
				padding = "m",
				gap = "m",

				--[[ THE READOUTS SCROLL, AND THAT IS WHAT PUSHES THE CONTROLS DOWN
					(O-21, measured 2026-08-15). This was a `Spacer` on `fill`, which is
					a lane that gives its pixels back to nobody: on a 640x320 landscape
					at +4 the three readouts plus a four-button grid ran 64px past the
					canvas and every one of the four labelled controls — `Mount`,
					`Deplete`, `Move`, `Teardown`, i.e. the whole surface — was below the
					fold with no page scroller to reach it. A `fill` ScrollView does the
					Spacer's job (it takes the leftover, so the control grid still sits
					on the bottom edge) and its window is a place the readouts can be
					read from rather than a place they overflow. ]]
				UI.ScrollView("Readouts")({
					axis = "y",
					gap = "m",
					width = UI.fill(),
					height = UI.fill(),

					UI.Text("Title")({ text = "Billboard lab", textSize = "heading" }),
					UI.Text("Status")({ text = statusLine, textSize = "caption", role = "secondary" }),
					UI.Text("BillboardState")({
						text = billboardState,
						textSize = "caption",
						role = "secondary",
					}),
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

					control("BtnMount", "Mount", function()
						mountBillboard()
					end),
					control("BtnDeplete", "Deplete", function()
						startDeplete()
					end),
					control("BtnMove", "Move", function()
						local api = seam()
						if api ~= nil then
							api.moveAnchor(3, 0, 0)
						end
					end),
					control("BtnTeardown", "Teardown", function()
						tearDownBillboard()
					end),
				}),
			})
		end

		result.screen = screen
		result.present = {}
		result.steps = {
			mount = function()
				return mountBillboard()
			end,
			-- the arc empties on the clock; under reduced motion the stepped policy
			-- applies and the ring still reaches empty at the same wall-clock moment
			deplete = function()
				return startDeplete()
			end,
			depleteRead = function()
				return {
					fraction = fraction:peek(),
					done = timerDone:peek(),
					arcPoints = #(ringPoints:peek() :: any),
					kind = if timer ~= nil then timer:motionKind() else nil,
					reducedForm = if timer ~= nil then timer:reducedForm() else nil,
					motionPolicy = env:get("motionPolicy"):peek(),
				}
			end,
			-- the world anchor moves and the billboard tracks it (engine-owned; the
			-- seam answers the anchor's position so the capture has a number beside it)
			movePart = function()
				local api = seam()
				if api == nil then
					return { moved = false, reason = "no billboard seam on this host (headless run)" }
				end
				local moved = api.moveAnchor(3, 0, 0)
				note("billboard:move", moved)
				return moved
			end,
			-- SF-W1's pure half: the render-vs-record predicate. Recording never
			-- stops; only the painting does, and the ring's value keeps its terminus.
			scopePredicate = function()
				local before = { fraction = fraction:peek(), rendering = renderScope:peek() }
				rendering:set(false)
				local outOfScope = { rendering = renderScope:peek(), recording = recording:peek() }
				rendering:set(true)
				local restored = { rendering = renderScope:peek(), fraction = fraction:peek() }
				note("scopePredicate", { before = before, outOfScope = outOfScope, restored = restored })
				return {
					before = before,
					outOfScope = outOfScope,
					restored = restored,
					-- the predicate itself, exercised as a pure function over its inputs
					truthTable = {
						recordingInScope = shouldRender({ recording = true, inScope = true }),
						recordingOutOfScope = shouldRender({ recording = true, inScope = false }),
						notRecordingInScope = shouldRender({ recording = false, inScope = true }),
						neither = shouldRender({ recording = false, inScope = false }),
					},
				}
			end,
			setRecording = function(_built: any, payload: string?)
				recording:set(payload ~= "false")
				return { recording = recording:peek(), rendering = renderScope:peek() }
			end,
			teardown = function()
				return tearDownBillboard()
			end,
			-- the ≥20-cycle row (SF-C1's billboard half): mount and tear down N times
			-- and read the engine census at the end
			cycle = function(_built: any, payload: string?)
				local times = tonumber(payload or "20") or 20
				local api = seam()
				if api == nil then
					return { cycles = 0, reason = "no billboard seam on this host (headless run)" }
				end
				for _ = 1, times do
					api.mount({ screen = billboardBlueprint, canvas = CANVAS })
					api.teardown()
				end
				local after = api.dump()
				note("billboard:cycle", { cycles = times, after = after })
				return { cycles = times, after = after }
			end,
		}
		result.report = function()
			local api = seam()
			return {
				ledger = "SF-W1",
				elapsed = elapsed,
				trace = trace,
				fraction = fraction:peek(),
				depleteRuns = depleteRuns,
				timerDone = timerDone:peek(),
				timerKind = if timer ~= nil then timer:motionKind() else nil,
				renderScope = renderScope:peek(),
				recording = recording:peek(),
				canvas = CANVAS,
				billboard = if api ~= nil then api.dump() else { mounted = false, seam = "absent" },
				billboardState = billboardState:peek(),
				arcPoints = #(ringPoints:peek() :: any),
				caption = caption:peek(),
				focusPath = pres.focus.focused:peek(),
				-- SF-W1/F12: the billboard itself carries no focusables, so its matrix
				-- rows assert geometry and lifecycle and mark focus-visibility N/A
				billboardFocusables = 0,
				reducedMotion = env:get("reducedMotion"):peek(),
				motionPolicy = env:get("motionPolicy"):peek(),
				motion = { active = clock:activeCount(), stats = clock:stats() },
				counters = core.owner.size(),
				coreError = core.lastError(),
			}
		end
		result.dispose = function()
			tearDownBillboard()
			if timer ~= nil then
				timer:dispose()
				timer = nil
			end
			lifetime.dispose()
		end
		return result
	end,
}
