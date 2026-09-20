--!strict
-- Scenario 'sponsor_celebration' (ledger row SF-M4; ui-designer-spec §8.2): the
-- TIMELINE contract — a four-beat choreographed sequence that can be interrupted
-- at every boundary and mid-beat, and that resolves to a clean terminal state
-- rather than a half-painted stage.
--
-- Every beat declares BOTH halves: `run` (its content) and `terminal` (where the
-- stage must stand if the sequence never gets to play it). `handle:interrupt()`
-- runs every remaining beat's terminal, in order, on the interrupt frame — which
-- is the only reason "no half-flown box, no half-faded wash" can be an assertion
-- instead of a hope.
--
-- The stage is itself the skip affordance (§8.2: Activate on the stage while
-- running = Skip). It is a content Button — one activation surface, no text of
-- its own, `focusable = false` so the four control buttons remain the whole focus
-- order the spec declares.

local newLifetime = require("./lifetime")

return {
	title = "Sequence lab (SF-M4)",
	ledgerRows = { "SF-M4", "SF-M5", "SF-F1", "SF-C1", "SF-C2", "SF-C3" },
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI, Compose = ctx.UI, ctx.Compose
		local core = ctx.core
		local env = ctx.env
		local pres = ctx.presenter
		local lifetime = newLifetime(Compose)
		local own = lifetime.own
		local clock = pres.motionClock

		local SCREEN = "/CelebrationLab"
		local STAGE = SCREEN .. "/Stage/StageInner"
		local BOX_B = STAGE .. "/Beats/Row/Beat2/BoxB"
		local BOX_C = STAGE .. "/Beats/Row/Beat3/BoxC"

		local trace: { any } = {}
		local elapsed = 0
		local function note(kind: string, info: any?)
			table.insert(trace, { at = elapsed, kind = kind, info = info })
		end
		own(pres.onFeedback(function(event: any)
			table.insert(trace, {
				at = elapsed,
				kind = "feedback:" .. tostring(event.type),
				info = { path = event.path, reason = event.reason, context = event.context },
			})
		end))

		-- the four subjects, one per beat
		local boxAOpen = Compose.cell(false)
		local boxBX = own(clock:spring(0, "object"))
		local chipScale = own(clock:spring(1, "reward"))
		local washEnergy = own(clock:spring(0, "decay"))
		local washTint = Compose.formula(function(use)
			return { role = "accent", from = "surface", blend = math.clamp(use(washEnergy), 0, 1) }
		end)

		local FLY_FROM = -160
		local BEAT_AT = { 0, 0.5, 1.0, 1.5 }

		local timeline: any = nil
		local runs = 0
		local doneReasons: { string } = {}
		local boundaryResults: { any } = {}
		local pending: string? = nil

		local plan: { { at: number, run: () -> () } } = {}
		local function schedule(delay: number, run: () -> ())
			table.insert(plan, { at = elapsed + delay, run = run })
		end
		local function runDue()
			if #plan == 0 then
				return
			end
			local remaining: { { at: number, run: () -> () } } = {}
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

		local result: any = {}
		local function controller(): any
			local handle = result.handle
			return if handle ~= nil then handle.controller else nil
		end

		own(pres.onTick(function(dt: number)
			elapsed += dt
			runDue()
			local ctrl = controller()
			if ctrl == nil then
				return
			end
			ctrl.setPresentationTransform(BOX_B, { x = boxBX:peek(), y = 0 })
			ctrl.setPresentationTransform(BOX_C, { x = 0, y = 0, scale = chipScale:peek() })
		end))

		-- the STAGE STATE a terminal assertion reads: every subject's value, and
		-- whether it stands at the beat's declared terminal
		local function stageState(): any
			return {
				boxAOpen = boxAOpen:peek(),
				boxBX = boxBX:peek(),
				boxBSettled = boxBX:isSettled(),
				chipScale = chipScale:peek(),
				chipSettled = chipScale:isSettled(),
				wash = washEnergy:peek(),
				washSettled = washEnergy:isSettled(),
				-- PERCEPTUAL, not exact: a spring's settle epsilon is 1e-3 and a
				-- terminal stage is one nobody can see a difference in, so the
				-- predicate is half a pixel and half a percent. The raw values ride
				-- beside it so a reader can always check the arithmetic.
				terminal = boxAOpen:peek()
					and math.abs(boxBX:peek()) < 0.5
					and math.abs(chipScale:peek() - 1) < 0.005
					and math.abs(washEnergy:peek()) < 0.005,
			}
		end

		local function resetStage()
			boxAOpen:set(false)
			boxBX:snap(FLY_FROM)
			chipScale:snap(1)
			washEnergy:snap(0)
		end

		local function endTimeline()
			if timeline ~= nil and not timeline:isDone() then
				timeline:interrupt()
			end
			timeline = nil
		end

		local function startRun(label: string)
			endTimeline()
			resetStage()
			runs += 1
			note("run:start", { label = label, run = runs })
			timeline = clock:timeline({
				beats = {
					{
						at = BEAT_AT[1],
						run = function()
							note("beat:1", { subject = "BoxA", form = "materialize" })
							boxAOpen:set(true)
						end,
						terminal = function()
							boxAOpen:set(true)
						end,
					},
					{
						at = BEAT_AT[2],
						run = function()
							note("beat:2", { subject = "BoxB", class = "object" })
							boxBX:setTarget(0)
						end,
						terminal = function()
							boxBX:snap(0)
						end,
					},
					{
						at = BEAT_AT[3],
						run = function()
							note("beat:3", { subject = "BoxC", class = "reward" })
							chipScale:snap(0.82)
							chipScale:setTarget(1)
						end,
						terminal = function()
							chipScale:snap(1)
						end,
					},
					{
						at = BEAT_AT[4],
						run = function()
							note("beat:4", { subject = "Wash", class = "decay" })
							washEnergy:snap(1)
							washEnergy:setTarget(0)
						end,
						terminal = function()
							washEnergy:snap(0)
						end,
					},
				},
				onDone = function(reason: string)
					table.insert(doneReasons, reason)
					note("run:done", { reason = reason, state = stageState() })
					pres.emitFeedback({ type = "celebrate", path = SCREEN .. "/Stage", reason = reason })
					timeline = nil
					pending = nil
				end,
			})
		end

		local function skipRun()
			if timeline ~= nil and not timeline:isDone() then
				note("skip")
				timeline:skip()
				return true
			end
			return false
		end

		-- ===== the stage ====================================================
		local function beat(index: number, caption: string, boxView: any)
			return UI.VStack(`Beat{index}`)({
				gap = "xs",
				width = UI.fill(),

				boxView,
				-- captions WRAP (they are the preferred-text participant here);
				-- the beat box grows with its caption because the column sizes to
				-- its content, and the stage scrolls rather than clipping
				UI.Text(`Cap{index}`)({ text = caption, textSize = "caption", role = "secondary" }),
			})
		end

		local BEAT_BOX: any = { type = "fixed", px = "controlSizes.large.height" }

		local function stageInner()
			return UI.ZStack("StageInner")({
				width = UI.fill(),
				height = UI.fill(),

				-- the beat-4 wash, BEHIND the beats: a tinted Box claims both colour
				-- and opacity, so a wash painted over the content would hide it
				UI.Box("Wash")({
					surface = "base",
					tint = washTint,
					width = UI.fill(),
					height = UI.fill(),
				}),
				UI.ScrollView("Beats")({
					axis = "y",
					width = UI.fill(),
					height = UI.fill(),

					UI.HStack("Row")({
						gap = "s",
						align = "start",
						width = UI.fill(),

						beat(
							1,
							"materialize",
							UI.When("BoxARegion")({
								transition = { enter = "materialize", class = "container" },
								Compose.show(boxAOpen, function()
									return UI.corners(
										UI.Box("BoxA")({
											surface = "control",
											canvasGroup = true,
											width = UI.fill(),
											height = BEAT_BOX,
										}),
										"control"
									)
								end),
							})
						),
						beat(
							2,
							"fly in (object)",
							UI.corners(
								UI.Box("BoxB")({
									surface = "control",
									width = UI.fill(),
									height = BEAT_BOX,
								}),
								"control"
							)
						),
						beat(
							3,
							"reward pop",
							UI.corners(
								UI.Box("BoxC")({
									surface = "control",
									width = UI.fill(),
									height = BEAT_BOX,
								}),
								"control"
							)
						),
						beat(
							4,
							"decay wash",
							UI.corners(
								UI.Box("BoxD")({
									surface = "control",
									width = UI.fill(),
									height = BEAT_BOX,
								}),
								"control"
							)
						),
					}),
				}),
			})
		end

		local function control(id: string, label: string, onActivate: () -> ())
			return UI.Button(id)({
				label = label,
				height = { type = "minMax", min = "targetSizes.minimum" },
				onActivate = onActivate,
			})
		end

		local function screen()
			return UI.Screen("CelebrationLab")({
				padding = "m",
				gap = "m",

				UI.Text("Title")({ text = "Sequence lab", textSize = "heading" }),
				-- THE STAGE IS THE SKIP AFFORDANCE. A content Button paints no text of
				-- its own and refuses focusables inside it, so this is one activation
				-- surface over inert content — and `focusable = false` keeps the focus
				-- order exactly the four controls below.
				UI.Button("Stage")({
					label = "Skip sequence",
					focusable = false,
					surface = "base",
					width = UI.fill(),
					height = UI.fill(),
					onActivate = function()
						skipRun()
					end,
					stageInner(),
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

					control("BtnRun", "Run", function()
						startRun("button")
					end),
					control("BtnInterrupt", "Interrupt", function()
						endTimeline()
					end),
					control("BtnSkip", "Skip", function()
						skipRun()
					end),
					control("BtnReplay", "Replay", function()
						startRun("replay")
					end),
				}),
			})
		end

		result.screen = screen
		result.present = {}
		result.steps = {
			run = function()
				startRun("step")
				return { run = runs, beats = #BEAT_AT }
			end,
			-- THE THREE BOUNDARIES, one sub-invocation each. Each sub-run plays up to
			-- the frame BEFORE the next beat fires, interrupts there, and records the
			-- stage on the interrupt frame and again once the clock has run on — so a
			-- half-painted beat shows up as a snapshot rather than as a screenshot
			-- somebody has to squint at.
			interruptAtBoundary = function()
				boundaryResults = {}
				pending = "interruptAtBoundary"
				local function sub(index: number)
					startRun(`boundary-{index}`)
					-- a frame BEFORE the next beat: at the boundary, beat `index` has
					-- fired and beats index+1.. have not, which is what makes this a
					-- boundary rather than "just after the next beat"
					schedule(BEAT_AT[index + 1] - 0.02, function()
						local before = stageState()
						endTimeline()
						local after = stageState()
						local entry: any = {
							boundary = index,
							at = BEAT_AT[index + 1],
							before = before,
							interruptFrame = after,
						}
						table.insert(boundaryResults, entry)
						note("boundary:interrupted", { boundary = index, terminal = after.terminal })
						schedule(1.0, function()
							entry.settled = stageState()
							if index < 3 then
								sub(index + 1)
							else
								pending = nil
							end
						end)
					end)
				end
				sub(1)
				return { subInvocations = 3, pending = true }
			end,
			-- MID-BEAT-2. Two snapshots on purpose: `interruptFrame` is what the
			-- contract lands on the interrupt frame, and `settled` is where the
			-- flights came to rest. THE PLAYING BEAT IS TERMINALIZED TOO (§1.6 as
			-- ruled in review R2-F6's sibling finding): "skip" means jump to the end
			-- state, never half-painted, so an interrupt lands every beat's terminal —
			-- the one already playing included — on the interrupt frame (spec finding
			-- F6, endorsed as the contract wording by the UI-designer review). The
			-- rows below prove it rather than the fixture snapping its own boxes.
			interruptMidBeat = function()
				boundaryResults = {}
				pending = "interruptMidBeat"
				startRun("mid-beat")
				schedule(BEAT_AT[2] + 0.15, function()
					local before = stageState()
					endTimeline()
					local after = stageState()
					local entry: any = { boundary = "mid-2", before = before, interruptFrame = after }
					table.insert(boundaryResults, entry)
					note("midbeat:interrupted", { terminal = after.terminal })
					schedule(1.0, function()
						entry.settled = stageState()
						note("midbeat:settled", { terminal = entry.settled.terminal })
						pending = nil
					end)
				end)
				return { pending = true, interruptAt = BEAT_AT[2] + 0.15 }
			end,
			skipToEnd = function()
				pending = "skipToEnd"
				startRun("skip")
				schedule(0.3, function()
					local skipped = skipRun()
					note("skip:result", { skipped = skipped, state = stageState() })
					pending = nil
				end)
				return { pending = true }
			end,
			-- terminal -> clean restart: no orphan state from the run before it
			replay = function()
				local before = stageState()
				startRun("replay")
				return { before = before, after = stageState(), run = runs }
			end,
			state = function()
				return stageState()
			end,
		}
		result.report = function()
			return {
				ledger = "SF-M4",
				elapsed = elapsed,
				trace = trace,
				runs = runs,
				doneReasons = doneReasons,
				boundaryResults = boundaryResults,
				pending = pending,
				running = timeline ~= nil,
				stage = stageState(),
				beats = BEAT_AT,
				reducedMotion = env:get("reducedMotion"):peek(),
				motionPolicy = env:get("motionPolicy"):peek(),
				motion = { active = clock:activeCount(), stats = clock:stats() },
				counters = core.owner.size(),
				coreError = core.lastError(),
			}
		end
		result.dispose = function()
			endTimeline()
			lifetime.dispose()
		end
		return result
	end,
}
