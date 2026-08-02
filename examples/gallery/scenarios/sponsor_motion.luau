--!strict
-- Scenario 'sponsor_motion' (ledger rows SF-M1, SF-M2, SF-M3, SF-M5, SF-M7,
-- SF-M8; ui-designer-spec §8.1): the MOTION-CLASS LAB — every class visible,
-- interruptible, seedable, and every one of them stepped by the PRESENTER'S
-- clock so `presenter.tick(dt)` drives the whole fixture (live: the client's
-- motion driver; headless: a scripted dt).
--
-- Nothing here owns a clock, a frame connection or a tween. The scenario asks
-- the framework for named motion (`clock:spring` / `clock:chase` /
-- `clock:timeline`), reads the values, and writes them through the ONE motion
-- write surface — the presentation channel (`setPresentationTransform`), which
-- composes onto the solver's rect and therefore never re-solves and never
-- contests native-sheet paint (SF-M7).
--
-- The stage's slots are ZStack children: SlotB MOVES mid-flight by re-aligning
-- (a real re-solve), and the puck's chase re-reads its rect every frame, so
-- `retargetMidFlight` proves SF-M2 against a target that genuinely moved rather
-- than a scripted number.

return {
	title = "Motion lab (SF-M1/M2/M3/M5/M7/M8)",
	ledgerRows = { "SF-M1", "SF-M2", "SF-M3", "SF-M5", "SF-M7", "SF-M8", "SF-F1", "SF-C1", "SF-C2", "SF-C3" },
	build = function(ctx: any)
		local LuauUI = ctx.LuauUI
		local UI = LuauUI.UI
		local core = ctx.core
		local env = ctx.env
		local pres = ctx.presenter
		local scope = core:scope("sponsor-motion")
		local clock = pres.motionClock

		local SCREEN = "/MotionLab"
		local STAGE = SCREEN .. "/Main/StageColumn/Stage"
		local PUCK = STAGE .. "/Puck"
		local SLOT_A = STAGE .. "/SlotA"
		local SLOT_B = STAGE .. "/SlotB"
		local CHIP = STAGE .. "/RewardChip"
		local WASH = SCREEN .. "/Main/StageColumn/WashRow/WashFill"

		-- ===== the scenario trace (SF-F1's E3) ==============================
		-- Every §7 semantic event the presenter publishes, plus the fixture's own
		-- step marks, in ONE ordered log with the frame time each landed on. The
		-- runner has no trace collector of its own; this is the smallest one that
		-- answers "which frame did it fire on", which is the whole acceptance.
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

		-- ===== state ========================================================
		local panelOpen = scope:own(core:signal(false))
		local stressOn = scope:own(core:signal(false))
		-- SlotB's own placement, so `retargetMidFlight` moves a real box through a
		-- real re-solve rather than by editing the number the chase reads
		local slotBAlignV = scope:own(core:signal("end"))

		-- the four classes, one subject each. `scope:own` takes them because a
		-- MotionValue is scope-owned (`value:dispose()`), and SF-C1 is the row
		-- that fails if any of them survives a reset.
		local puckX = scope:own(clock:spring(0, "object"))
		local puckY = scope:own(clock:spring(0, "object"))
		local rewardScale = scope:own(clock:spring(1, "reward"))
		-- the decay class: attack is a CUT (snap), decay is the spring
		local energy = scope:own(clock:spring(0, "decay"))

		local chase: any = nil
		local arrivals: { any } = {}
		local stressScope: any = nil
		local stressTimeline: any = nil
		local cloneValues: { any } = {}

		local wash = scope:own(core:memo(function(use)
			-- SF-P1's value blend in its simplest form: control -> accent driven by
			-- a scalar a `decay` spring owns. A role blend, never a raw colour, so
			-- the theme still owns both ends.
			return { role = "accent", from = "control", blend = math.clamp(use(energy), 0, 1) }
		end))

		-- ===== the scripted schedule ========================================
		-- Steps that mean "do this, then that, a few frames later" (an interrupt
		-- INSIDE a settle) cannot fire on one frame without ceasing to be the
		-- thing they test. They arm entries here and the presenter's own tick
		-- runs them at their due time — the same path live and headless, and no
		-- second clock anywhere.
		local plan: { { at: number, run: () -> () } } = {}
		local function schedule(delay: number, run: () -> ())
			table.insert(plan, { at = elapsed + delay, run = run })
		end
		local function runDue()
			if #plan == 0 then
				return
			end
			local remaining: { { at: number, run: () -> () } } = {}
			-- collect first, then run: an entry that schedules another must not
			-- have its successor swallowed by this pass
			local due: { () -> () } = {}
			for _, entry in plan do
				if entry.at <= elapsed then
					table.insert(due, entry.run)
				else
					table.insert(remaining, entry)
				end
			end
			plan = remaining
			for _, run in due do
				run()
			end
		end

		-- ===== the presentation writes ======================================
		local result: any = {}
		local function controller(): any
			local handle = result.handle
			return if handle ~= nil then handle.controller else nil
		end

		scope:own(pres.onTick(function(dt: number)
			elapsed += dt
			runDue()
			local ctrl = controller()
			if ctrl == nil then
				return
			end
			ctrl.setPresentationTransform(PUCK, { x = puckX:get(), y = puckY:get() })
			ctrl.setPresentationTransform(CHIP, { x = 0, y = 0, scale = rewardScale:get() })
			for _, clone in cloneValues do
				ctrl.setPresentationTransform(clone.path, { x = clone.x:get(), y = clone.y:get() })
			end
		end))

		-- centre-to-centre delta from the puck's SOLVED rect to a slot's, which is
		-- what the presentation transform composes onto. `rectOf` answers the
		-- solver's rect and never the transformed one, so this cannot chase itself.
		local function deltaTo(targetPath: string): (number?, number?)
			local ctrl = controller()
			if ctrl == nil then
				return nil, nil
			end
			local puck = ctrl.rectOf(PUCK)
			local slot = ctrl.rectOf(targetPath)
			if puck == nil or slot == nil then
				return nil, nil
			end
			return (slot.x + slot.w / 2) - (puck.x + puck.w / 2), (slot.y + slot.h / 2) - (puck.y + puck.h / 2)
		end

		local function endChase()
			if chase ~= nil then
				chase:cancel()
				chase = nil
			end
		end

		local tossedTo = "SlotA" -- where the last flight aimed (SFH-1 rally state)
		local function flyTo(targetPath: string, label: string)
			endChase()
			tossedTo = label
			note("fly:start", { target = label })
			chase = clock:chase({
				x = puckX,
				y = puckY,
				target = function()
					return deltaTo(targetPath)
				end,
				onArrive = function(info: any)
					note("fly:arrive", { target = label, how = info.how, targetLost = info.targetLost })
					table.insert(
						arrivals,
						{ target = label, how = info.how, targetLost = info.targetLost, at = elapsed }
					)
					-- `arrive` is the MOTION verb (disposition F4); a chase a fixture
					-- created publishes its own arrival on the shared bus, which is
					-- what makes the trace one timeline instead of two.
					pres.emitFeedback({ type = "arrive", path = PUCK, context = { target = label, how = info.how } })
					chase = nil
				end,
			})
		end

		-- ===== the stage ====================================================
		local conditions = LuauUI.adaptive.conditions(core, env, { scope = scope }) -- RR-8: six memos die with the fixture
		local SLOT: any = { type = "fixed", px = "targetSizes.minimum" }

		local function slot(id: string, alignH: string, alignV: any)
			return UI.corners(
				UI.Box({ id = id, surface = "control", alignH = alignH, alignV = alignV, width = SLOT, height = SLOT }),
				"control"
			)
		end

		local clones = {}
		for i = 1, 20 do
			table.insert(
				clones,
				UI.corners(
					UI.Box({
						id = `Clone{i}`,
						surface = "accent",
						alignH = "center",
						alignV = "center",
						width = { type = "fixed", px = "iconSizes.small" },
						height = { type = "fixed", px = "iconSizes.small" },
					}),
					"pill"
				)
			)
		end

		local stage = UI.ZStack({
			id = "Stage",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = {
				UI.Box({
					id = "StageSurface",
					surface = "base",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
				}),
				slot("SlotA", "start", "start"),
				slot("SlotB", "end", slotBAlignV),
				UI.corners(
					UI.Box({
						id = "Puck",
						surface = "accent",
						alignH = "start",
						alignV = "start",
						width = SLOT,
						height = SLOT,
					}),
					"pill"
				),
				-- THE CONTAINER CLASS, on a structural region. `materialize` is a
				-- fading form, so its child is the declared fade group — that is the
				-- framework's rule, and a plain Box here is an authoring error.
				UI.When({
					id = "PanelRegion",
					condition = panelOpen,
					transition = { enter = "materialize", class = "container" },
					thenView = function()
						return UI.shadow(
							UI.corners(
								UI.Box({
									id = "Panel",
									surface = "raised",
									canvasGroup = true,
									alignH = "center",
									alignV = "center",
									width = { type = "percent", fraction = 0.7 },
									height = { type = "percent", fraction = 0.6 },
								}),
								"panel"
							),
							"overlay"
						)
					end,
				}),
				UI.corners(
					UI.Box({
						id = "RewardChip",
						surface = "control",
						alignH = "center",
						alignV = "end",
						width = { type = "fixed", px = "controlSizes.regular.height" },
						height = { type = "fixed", px = "controlSizes.compact.height" },
					}),
					"control"
				),
				-- SF-M8's dense scene: ≥20 concurrent springs, mounted only while the
				-- stress step is on so the resting cost of the lab stays honest
				UI.When({
					id = "CloneRegion",
					condition = stressOn,
					thenView = function()
						return UI.ZStack({
							id = "Clones",
							width = { type = "fill", weight = 1 },
							height = { type = "fill", weight = 1 },
							children = clones,
						})
					end,
				}),
			},
		})

		local function control(id: string, label: string, onActivate: () -> ())
			return UI.Button({
				id = id,
				label = label,
				height = { type = "minMax", min = "targetSizes.minimum" },
				onActivate = onActivate,
			})
		end

		-- ===== the verbs (buttons and steps call the SAME functions) =========
		local function openPanel()
			panelOpen:set(true)
			note("panel", { open = true })
		end
		local function closePanel()
			panelOpen:set(false)
			note("panel", { open = false })
		end
		local function pop()
			-- the one earned overshoot: place at the pressed scale, aim at rest
			rewardScale:snap(0.86)
			rewardScale:setTarget(1)
			note("reward:pop")
			pres.emitFeedback({ type = "celebrate", path = CHIP })
		end
		local function hit()
			-- ATTACK IS A CUT, DECAY IS THE SPRING. `snap` sets value+target+zero
			-- velocity and fires no settle event, so a re-hit mid-decay re-sets
			-- rather than ratcheting the second hit down.
			energy:snap(1)
			energy:setTarget(0)
			note("wash:hit", { energy = energy:get() })
		end
		-- TOSS ALTERNATES (director SFH-1: "the Ball doesn't reset, so I have no
		-- idea what it's doing"). Every press is a visible flight: the puck tosses
		-- to SlotB, and the NEXT press tosses it home to SlotA with the seed
		-- mirrored — mashing Toss reads as a rally instead of a dead button.
		local function toss()
			-- the gesture -> animation handoff (SF-D2's tracker, read here as a
			-- MOTION seed): scripted samples through the public velocity tracker,
			-- so the number that seeds the flight is one the framework computed.
			local goingHome = tossedTo == "SlotB"
			local dir = if goingHome then -1 else 1
			local tracker = LuauUI.newDragVelocity()
			for i = 0, 4 do
				tracker:push(i * 30 * dir, i * 12 * dir, elapsed + i * 0.016)
			end
			local vx, vy = tracker:velocity()
			if goingHome then
				flyTo(SLOT_A, "SlotA")
			else
				flyTo(SLOT_B, "SlotB")
			end
			puckX:setVelocity(vx)
			puckY:setVelocity(vy)
			note("fly:seed", { vx = vx, vy = vy, target = tossedTo })
			return { vx = vx, vy = vy, target = tossedTo }
		end

		local screen = UI.Screen({
			id = "MotionLab",
			padding = "m",
			gap = "m",
			children = {
				UI.Text({ id = "Title", text = "Motion lab", textSize = "heading" }),
				-- ONE tree, two intents: portrait stacks the stage over the controls,
				-- landscape puts the controls in a trailing column. The Grid derives
				-- its own column count, which is how the control row "wraps into two
				-- rows" on a compact viewport without a device branch.
				UI.AdaptiveStack({
					id = "Main",
					axis = conditions.axis,
					gap = "m",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.VStack({
							id = "StageColumn",
							gap = "s",
							width = { type = "fill", weight = 1 },
							height = { type = "fill", weight = 1 },
							children = {
								stage,
								-- the decay-wash subject, LABELED (director SFH-2: "decay
								-- wash doesn't seem to do anything" — it worked, but an
								-- anonymous strip gave the eye nothing to find). The label
								-- names the button that drives it.
								UI.ZStack({
									id = "WashRow",
									width = { type = "fill", weight = 1 },
									height = { type = "fixed", px = "targetSizes.minimum" },
									children = {
										UI.Box({
											id = "WashFill",
											surface = "control",
											tint = wash,
											width = { type = "fill", weight = 1 },
											height = { type = "fill", weight = 1 },
										}),
										UI.Text({
											id = "WashLabel",
											text = "energy wash — press Hit",
											role = "secondary",
											alignH = "center",
											alignV = "center",
										}),
									},
								}),
							},
						}),
						UI.Grid({
							id = "Controls",
							minColumnWidth = 96,
							gap = "s",
							rowGap = "s",
							width = { type = "fill", weight = 1 },
							children = {
								control("BtnPanel", "Panel", function()
									if panelOpen:get() then
										closePanel()
									else
										openPanel()
									end
								end),
								control("BtnFly", "Fly", function()
									flyTo(SLOT_B, "SlotB")
								end),
								control("BtnToss", "Toss", function()
									toss()
								end),
								control("BtnPop", "Pop", pop),
								control("BtnHit", "Hit", hit),
								control("BtnStress", "Stress", function()
									stressOn:set(not stressOn:get())
								end),
							},
						}),
					},
				}),
			},
		})

		local function startStress()
			if stressScope ~= nil then
				return #cloneValues
			end
			stressOn:set(true)
			stressScope = core:scope("sponsor-motion-stress")
			cloneValues = {}
			for i = 1, 20 do
				local x = stressScope:own(clock:spring(0, "object"))
				local y = stressScope:own(clock:spring(0, "object"))
				x:setTarget(math.cos(i) * 90)
				y:setTarget(math.sin(i) * 60)
				table.insert(cloneValues, { path = `{STAGE}/CloneRegion/Clones/Clone{i}`, x = x, y = y })
			end
			-- ...and a running timeline beside them (SF-M8 names both)
			stressTimeline = clock:timeline({
				beats = {
					{
						at = 0,
						run = function()
							note("stress:beat", { beat = 1 })
						end,
						terminal = function() end,
					},
					{
						at = 0.4,
						run = function()
							for _, clone in cloneValues do
								clone.x:setTarget(-clone.x:getTarget())
							end
						end,
						terminal = function() end,
					},
					{
						at = 0.8,
						run = function()
							for _, clone in cloneValues do
								clone.y:setTarget(-clone.y:getTarget())
							end
						end,
						terminal = function() end,
					},
				},
			})
			note("stress:on", { clones = #cloneValues })
			return #cloneValues
		end

		local function stopStress()
			if stressTimeline ~= nil then
				stressTimeline:interrupt()
				stressTimeline = nil
			end
			local ctrl = controller()
			if ctrl ~= nil then
				for _, clone in cloneValues do
					ctrl.setPresentationTransform(clone.path, nil)
				end
			end
			cloneValues = {}
			if stressScope ~= nil then
				stressScope:dispose()
				stressScope = nil
			end
			stressOn:set(false)
			note("stress:off")
		end

		result.screen = screen
		result.present = {}
		result.steps = {
			openPanel = function()
				openPanel()
				return { open = panelOpen:get() }
			end,
			closePanel = function()
				closePanel()
				return { open = panelOpen:get() }
			end,
			-- open -> close -> open INSIDE one settle. The two later flips are
			-- scheduled on the presenter's clock (0.08s apart, well inside the
			-- container class's 0.35s response), which is the only way the region
			-- can be re-entered mid-exit at all.
			interruptToggle = function()
				note("interrupt:begin")
				openPanel()
				schedule(0.08, closePanel)
				schedule(0.16, function()
					openPanel()
					note("interrupt:end")
				end)
				return { scheduled = 2, form = "materialize" }
			end,
			flyToSlot = function()
				puckX:snap(0)
				puckY:snap(0)
				slotBAlignV:set("end")
				flyTo(SLOT_B, "SlotB")
				return { seeded = false, target = "SlotB" }
			end,
			-- SF-M2: the target MOVES mid-flight (a real re-align, a real re-solve)
			-- and the puck lands on where SlotB ended up, not on the pixel it was
			-- aimed at when it left.
			retargetMidFlight = function()
				puckX:snap(0)
				puckY:snap(0)
				slotBAlignV:set("end")
				flyTo(SLOT_B, "SlotB")
				schedule(0.12, function()
					slotBAlignV:set("center")
					note("retarget:slotMoved", { alignV = "center" })
				end)
				return { scheduled = 1 }
			end,
			seedVelocityFly = function()
				puckX:snap(0)
				puckY:snap(0)
				return toss()
			end,
			rewardPop = function()
				pop()
				return { scale = rewardScale:get(), target = rewardScale:getTarget() }
			end,
			-- two hits, the second INSIDE the first's decay: the re-set must reach 1
			-- again, not the remainder of the first (WRONG: a dimmer second hit)
			hitDecay = function()
				hit()
				local first = energy:get()
				schedule(0.1, function()
					hit()
					note("wash:second", { energy = energy:get() })
				end)
				return { first = first, scheduled = 1 }
			end,
			stress = function()
				if stressOn:get() then
					stopStress()
					return { on = false, clones = 0, active = clock:activeCount() }
				end
				local n = startStress()
				return { on = true, clones = n, active = clock:activeCount() }
			end,
			-- the SF-M8 read a bench row pairs with: what is still being stepped,
			-- and what a settled lab costs (the answer must be zero)
			motionStats = function()
				return { active = clock:activeCount(), stats = clock:stats() }
			end,
		}
		result.report = function()
			local ctrl = controller()
			local styled: any = nil
			if ctx.nativeStyle ~= nil and ctx.nativeStyle.styledOf ~= nil then
				-- SF-M7/SF-P1: the wash node's claim is DECLARED, so the audit reads
				-- a hand-off rather than an accident. `styled` is the resolved winner;
				-- the claim attribute travels in the runner's own instance dump.
				styled = {
					washBackground = ctx.nativeStyle.styledOf(WASH, "BackgroundColor3"),
					washNode = if ctx.nativeStyle.dumpNode ~= nil then ctx.nativeStyle.dumpNode(WASH) else nil,
				}
			end
			return {
				ledger = "SF-M1/SF-M2/SF-M3/SF-M5/SF-M7/SF-M8",
				elapsed = elapsed,
				trace = trace,
				arrivals = arrivals,
				panelOpen = panelOpen:get(),
				energy = energy:get(),
				energySettled = energy:isSettled(),
				puck = {
					x = puckX:get(),
					y = puckY:get(),
					targetX = puckX:getTarget(),
					targetY = puckY:getTarget(),
					velocityX = puckX:getVelocity(),
					velocityY = puckY:getVelocity(),
					settled = puckX:isSettled() and puckY:isSettled(),
					chasing = chase ~= nil,
				},
				reward = { scale = rewardScale:get(), settled = rewardScale:isSettled() },
				reducedMotion = env:get("reducedMotion"):get(),
				motionPolicy = env:get("motionPolicy"):get(),
				reducedForm = { puck = puckX:reducedForm(), energyKind = energy:motionKind() },
				motion = { active = clock:activeCount(), stats = clock:stats() },
				stress = { on = stressOn:get(), clones = #cloneValues },
				geometry = if ctrl ~= nil
					then { puck = ctrl.rectOf(PUCK), slotA = ctrl.rectOf(SLOT_A), slotB = ctrl.rectOf(SLOT_B) }
					else nil,
				authority = styled,
				counters = core:counters(),
				coreError = core:lastError(),
			}
		end
		result.dispose = function()
			endChase()
			stopStress()
			scope:dispose()
		end
		return result
	end,
}
