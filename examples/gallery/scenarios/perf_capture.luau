--!strict
-- Scenario 'perf_capture' (roadmap Step 4, ledger rows XP-B2..XP-B6, XP-C1/C2).
--
-- The production-shaped fixture the five-view device matrix drives AND the one
-- the Studio performance capture measures. One fixture, because they are the
-- same question asked two ways: does this screen lay out correctly on that
-- device, and what does it cost there.
--
-- SHAPE, not mechanism. A dense live HUD (eight readouts, a progress bar, a
-- keyed marker row), a 200-row virtualized roster with a real row shape, and a
-- pinned action bar — the composition a race HUD or a garage actually has. It
-- must fit a 359x718 phone and a 1920x1080 television from one semantic tree,
-- so there is no device-name branch anywhere in it.
--
-- THE TWO FAULTS are first-class steps, not a debugging afterthought. A driver
-- that has never been seen to fail proves nothing, so this fixture can break
-- its own layout (`faultLayout`) and its own input effect (`faultInput`) on
-- demand, and the matrix driver runs both to show its assertions bite.
--
-- Engine-free: every engine fact arrives through the runner's ctx seams
-- (ctx.telemetry, ctx.geometry, ctx.themePackages).

-- THE ROSTER ROW, in one place: the design floor, its padding, and the two text
-- sizes its cell paints. The declared extent below is derived from exactly these,
-- so the row and the slot it is windowed into cannot drift apart.
local ROSTER_ROW_FLOOR = 44
local ROSTER_ROW_PADDING = 4
local ROSTER_NAME_SIZE = 14
local ROSTER_DETAIL_SIZE = 12

return {
	title = "Production-shaped performance capture",
	ledgerRows = { "XP-B2", "XP-B3", "XP-B4", "XP-B5", "XP-B6", "XP-C1", "XP-C2" },
	build = function(ctx: any)
		local LuauUI = ctx.LuauUI
		local UI = LuauUI.UI
		local core = ctx.core
		local scope = core:scope("perf-capture")
		local conditions = LuauUI.adaptive.conditions(core, ctx.env, { scope = scope }) -- RR-8: six memos die with the fixture

		-- ---- owner-held state -------------------------------------------
		local readouts = {}
		for i = 1, 8 do
			readouts[i] = core:signal(0)
		end
		local lap = core:signal(0.35)
		local boosts = core:signal(0)
		local roster = core:signal({})
		local faults = { layout = false, input = false }
		-- the layout fault has to be REACTIVE to change a solved width without a
		-- remount, so it rides a signal rather than the plain flag table
		local faultsSignal = core:signal(false)
		-- M6's visible end: the text a player would see change
		local boostText = core:memo(function(use)
			return `Boost x{use(boosts)}`
		end)

		local items = table.create(200)
		for i = 1, 200 do
			items[i] = { id = `r{i}`, name = `Racer {i}`, detail = `Lap {(i % 5) + 1} · P{i}` }
		end
		roster:set(items)

		-- THE FAULT, expressed as geometry (XP-B5). It has to be a fault the
		-- solver genuinely cannot absorb, and the first attempt was not: an
		-- absurd fixed WIDTH on the action row came back clamped to the content
		-- width (1055px in a 1079px viewport), so the "broken" row passed every
		-- assertion. That is the solver behaving correctly on the cross axis.
		--
		-- The MAIN axis is where a stack does not compress: it paints past its
		-- own box. So the fault is an absurd fixed HEIGHT, which pushes the
		-- pinned action bar below the screen and out of reach — a defect a
		-- player would feel and a capture alone would not necessarily show.
		local actionHeight = core:memo(function(use)
			return if use(faultsSignal) then { type = "fixed", px = 2400 } else nil
		end)

		local progress = LuauUI.newProgressView(LuauUI, core, { id = "Lap", value = lap, label = "Lap" })

		--[[ THE ROSTER ROW'S HEIGHT — a design FLOOR that grows with the text
			(adopted 2026-08-15, docs/plans/variable-item-extents.md).

			WHAT IT WAS: `rowHeight = 44`, flat. 44 is a comfortable rhythm for a 14px
			name beside a 12px detail with 4px of padding, and it is generous at the
			default preference — which is why the lie only surfaced at the far end of
			the sweep: on a console-class display at `preferredTextOffset` +10 the row
			MEASURES 50 in a 44px slot (the ten-foot floor takes the 14px name to 21,
			and the engine adds 10 on top of that). The overflow sweep carried a
			lying-extent waiver for it.

			WHY IT STAYS DECLARED, and uniformly. This scenario is the perf harness's
			capture surface: it exists so a run measures the UNIFORM windowing
			arithmetic, and `itemExtent = "measured"` would change what it measures
			(and cost a wrapper node per row). It genuinely needs a CORRECT declaration
			rather than self-measurement — this is the case the ruling named when it
			said measured mode is not a complete answer.

			WHY IT IS A `max` AND NOT JUST THE LINE BOX. Dropping to the bare content
			height would be 25px at the default preference — a different-looking screen
			and a different mounted-row count, i.e. a silent perf-baseline change made
			while fixing an accessibility defect. The floor keeps the row byte-identical
			everywhere it was already honest, and the line box takes over exactly where
			it stopped being. ]]
		local rowHeight = core:memo(function(use)
			local facts = LuauUI.text.facts({ env = ctx.env, use = use })
			local content = math.max(
				LuauUI.text.lineBox({ facts = facts, size = ROSTER_NAME_SIZE, lines = 1 }),
				LuauUI.text.lineBox({ facts = facts, size = ROSTER_DETAIL_SIZE, lines = 1 })
			)
			return math.max(ROSTER_ROW_FLOOR, content + 2 * ROSTER_ROW_PADDING)
		end)

		local list = LuauUI.newVirtualList(LuauUI, core, {
			id = "Roster",
			rows = roster,
			key = function(item)
				return item.id
			end,
			rowHeight = rowHeight,
			viewportHeight = 220,
			cell = function(item)
				return UI.HStack({
					id = "Row",
					gap = 8,
					padding = ROSTER_ROW_PADDING,
					children = {
						UI.Text({ id = "Name", text = item.name, textSize = ROSTER_NAME_SIZE }),
						UI.Spacer({ id = "Gap" }),
						UI.Text({ id = "Detail", text = item.detail, textSize = ROSTER_DETAIL_SIZE }),
					},
				})
			end,
		})

		local readoutViews = {}
		for i = 1, 8 do
			local sig = readouts[i]
			local text = core:memo(function(use)
				return `{use(sig)}`
			end)
			table.insert(readoutViews, UI.Text({ id = `R{i}`, text = text, textSize = 14 }))
		end

		local screen = UI.Screen({
			id = "PerfCapture",
			padding = 12,
			gap = 8,
			children = {
				UI.HStack({ id = "Readouts", gap = 6, children = readoutViews }),
				progress.blueprint,
				UI.Text({ id = "BoostCount", text = boostText, textSize = 16 }),
				UI.ScrollView({
					id = "Body",
					axis = "y",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.AdaptiveStack({
							id = "Split",
							axis = conditions.axis,
							gap = 12,
							width = { type = "fill", weight = 1 },
							children = { list.blueprint },
						}),
					},
				}),
				UI.HStack({
					id = "Actions",
					gap = 8,
					height = actionHeight,
					children = {
						UI.Button({
							id = "Boost",
							label = "Boost",
							onActivate = function()
								-- faultInput suppresses only the EFFECT, not the
								-- activation: the press still happens, the screen
								-- just stops reflecting it. That is the failure a
								-- capture alone cannot see and a paired trace can.
								if not faults.input then
									boosts:set(boosts:get() + 1)
								end
							end,
						}),
						UI.Button({ id = "Reset", label = "Reset" }),
					},
				}),
			},
		})

		return {
			screen = screen,
			dispose = function()
				progress.dispose()
				list.dispose()
				scope:dispose()
			end,
			steps = {
				-- ---- the capture (XP-C1) --------------------------------
				-- Drives a fixed workload and records the metric ledger. Frame
				-- work is sampled around the workload, not instead of it, so the
				-- number describes a frame that was doing this screen's work.
				measure = function(_self, payload: string?)
					local frames = tonumber(payload or "") or 90
					local t = ctx.telemetry
					local before = t.memory()
					-- LuauUI's own update cost: 60 driven refreshes, timed
					local updates = table.create(60)
					for i = 1, 60 do
						for k = 1, 8 do
							readouts[k]:set(i * 10 + k)
						end
						lap:set((i % 100) / 100)
						local t0 = t.clock()
						ctx.presenter.refresh()
						updates[i] = (t.clock() - t0) * 1000
					end
					table.sort(updates)
					local function pct(p: number): number
						return updates[math.max(1, math.ceil(p * #updates))]
					end
					-- whole-frame work, sampled while the same screen is mounted
					local frameWork = t.frameWork(frames)
					local after = t.memory()
					return {
						updateMs = {
							measured = true,
							p50_ms = pct(0.5),
							p95_ms = pct(0.95),
							p99_ms = pct(0.99),
							samples = #updates,
							note = "wall time around presenter.refresh() after a live binding storm; LuauUI's share only",
						},
						frameWorkMs = frameWork,
						instances = t.instances(),
						connections = t.connections(),
						memoryKb = {
							measured = true,
							beforeLuaHeapKb = before.luaHeapKb,
							afterLuaHeapKb = after.luaHeapKb,
							deltaLuaHeapKb = after.luaHeapKb - before.luaHeapKb,
							totalMb = after.totalMb,
							totalMbNote = after.totalMbNote,
							-- the KEY the runner actually publishes. It was `guiInstanceMb`
							-- here and `guiMb` there, so the figure silently dropped out of
							-- every artifact — the same "fix the producer, miss the consumer"
							-- shape as the VirtualInput probe, one layer up.
							guiMb = after.guiMb,
							guiMbBefore = before.guiMb,
							-- the only attributable half: what the workload moved
							guiMbDelta = if type(after.guiMb) == "number" and type(before.guiMb) == "number"
								then after.guiMb - before.guiMb
								else nil,
							guiMbNote = after.guiMbNote,
							guiMbUnavailable = after.guiMbUnavailable,
							memoryTrackingEnabled = after.memoryTrackingEnabled,
						},
						workload = "60 driven refreshes over 8 live readouts + a progress binding, then " .. tostring(
							frames
						) .. " sampled frames",
					}
				end,

				-- ---- input-to-visible (M6) ------------------------------
				-- arm() starts the raw-input listener and hands back the LIVE
				-- geometry of the button, so the driver injects at a point it
				-- derived from the running tree rather than a remembered one.
				armInput = function()
					ctx.telemetry.rawInput.arm()
					-- both ends of M6 are timestamped inside engine callbacks: the
					-- raw event above, and the painted property below
					ctx.telemetry.paintWatch.arm(ctx.instanceAt("/PerfCapture/BoostCount"), "Text")
					local geo = ctx.geometry({ "/PerfCapture/Actions/Boost", "/PerfCapture/BoostCount" })
					local target = geo["/PerfCapture/Actions/Boost"]
					return {
						armed = true,
						boostsBefore = boosts:get(),
						boostTextBefore = boostText:get(),
						geometry = geo,
						-- the centre of the activation surface in the SAME space the
						-- geometry above is in. A caller injecting native input adds
						-- this session's measured injection offset (see the
						-- `calibrateInput` step) — the driver never guesses it.
						aimPoint = if target ~= nil
							then { x = target.x + target.w / 2, y = target.y + target.h / 2 }
							else nil,
					}
				end,
				-- INJECTION CALIBRATION (live finding 2026-07-26). Injected pointer
				-- coordinates and the coordinates the engine reports are offset from
				-- each other by a session-dependent amount, and a click aimed at a
				-- remembered constant silently lands somewhere else — the failure
				-- mode where "the screenshot looks aimed correctly even though routed
				-- input landed elsewhere". So the offset is MEASURED, once per
				-- session: inject anywhere, call this, and add the delta.
				calibrateInput = function(_self, payload: string?)
					local raw = ctx.telemetry.rawInput.last()
					local requested = if payload ~= nil then tonumber(payload) else nil
					return {
						rawEvent = raw,
						requestedY = requested,
						offsetY = if raw ~= nil and requested ~= nil then requested - raw.position.y else nil,
						note = "add offsetY to a window-space target Y before injecting; re-measure per session",
					}
				end,
				-- readInput() is called AFTER the injected press. It pairs the raw
				-- native event with the painted result and reports the interval
				-- between them. It is frame-quantized and excludes scan-out, so it
				-- is an upper bound on LuauUI's share, never display latency.
				readInput = function()
					local t = ctx.telemetry
					-- COMMIT, then let the engine draw. The activate handler sets a
					-- signal; the property write that a player sees happens on the
					-- presenter's commit. The runner refreshes AFTER a step returns,
					-- so a read taken here without committing first saw the model
					-- changed and the screen not yet written — and reported "the
					-- press reached the engine and never reached the screen" for a
					-- press that had worked. The commit is part of the chain being
					-- measured, so it belongs inside it.
					ctx.presenter.refresh()
					t.step()
					local pair = t.rawInput.pair()
					local raw = pair.began
					-- the activation completes on RELEASE, so the gesture's end is
					-- what the paint should be timed from; the press-to-release
					-- dwell belongs to whatever injected it, not to LuauUI
					local gestureEnd = pair.ended or pair.began
					local paint = t.paintWatch.read()
					local painted = ctx.geometry({ "/PerfCapture/BoostCount" })
					local latency: any
					if raw == nil then
						latency = { measured = false, reason = "no raw input event was observed after arming" }
					elseif paint.firstChangeAt == nil then
						latency = {
							measured = false,
							reason = "a raw input event arrived but no painted change followed it — the press "
								.. "reached the engine and never reached the screen",
						}
					else
						latency = {
							measured = true,
							quantity = "input -> committed property write",
							bound = "lower",
							ms = (paint.firstChangeAt - gestureEnd.at) * 1000,
							fromInputBeganMs = (paint.firstChangeAt - raw.at) * 1000,
							injectorDwellMs = pair.dwellMs,
							watching = paint.watching,
							commitDrivenBy = "the harness (presenter.refresh inside readInput); a game refreshes on its own schedule",
							note = "the raw native event that COMPLETED the gesture -> the property WRITE that will "
								.. "change what a player sees. Both timestamped inside engine callbacks. "
								.. "GetPropertyChangedSignal fires on the write, which strictly PRECEDES the frame "
								.. "that renders it, so this is a LOWER bound on input-to-visible — not an upper "
								.. "bound and not frame-quantized. fromInputBeganMs additionally contains the "
								.. "injector's own press-to-release dwell. No instrument here sees scan-out.",
						}
					end
					return {
						rawEvent = raw,
						rawPair = pair,
						paintWatch = paint,
						inputToVisibleMs = latency,
						boosts = boosts:get(),
						boostText = boostText:get(),
						effectVisible = painted,
					}
				end,

				-- ---- theme swaps as cost + invalidation (XP-A3's E3 half) ---
				themeSwap = function(_self, payload: string?)
					local name = payload or "flat"
					local t = ctx.telemetry
					local before = ctx.geometry({ "/PerfCapture/Actions/Boost", "/PerfCapture/BoostCount" })
					local instancesBefore = t.instances()
					-- ctx.themePackages hands over the MODULE, not the compiled
					-- package: a theme file exports `build(themes)`. Passing the
					-- module straight to setThemePackage returns false and produces
					-- an empty census, which reads as "the ornate skin costs
					-- nothing" — the exact shape of a misleading zero this stage
					-- exists to prevent (found live, 2026-07-26).
					local module = if name == "flat" then nil else ctx.themePackages[name]
					local pkg = if module ~= nil and type(module.build) == "function"
						then module.build(ctx.LuauUI.themes)
						else module
					local t0 = t.clock()
					local changed = ctx.themeChrome.setPackage(pkg)
					ctx.presenter.refresh()
					local swapMs = (t.clock() - t0) * 1000
					local after = ctx.geometry({ "/PerfCapture/Actions/Boost", "/PerfCapture/BoostCount" })
					local moved = 0
					for path, rect in before do
						local b = after[path]
						if b == nil or b.x ~= rect.x or b.y ~= rect.y or b.w ~= rect.w or b.h ~= rect.h then
							moved += 1
						end
					end
					return {
						package = name,
						packageFound = pkg ~= nil or name == "flat",
						packageCompiled = pkg ~= nil and pkg.identity ~= nil,
						chromeChanged = changed,
						swapMs = swapMs,
						movedRects = moved,
						probes = 2,
						census = ctx.themeChrome.census(),
						instancesBefore = instancesBefore.guiObjects,
						instancesAfter = t.instances().guiObjects,
					}
				end,

				-- ---- the intentional faults (XP-B5 / XP-B6) --------------
				faultLayout = function()
					faults.layout = true
					faultsSignal:set(true)
					ctx.presenter.refresh()
					return { fault = "layout", active = true }
				end,
				faultInput = function()
					faults.input = true
					return {
						fault = "input",
						active = true,
						note = "the press still fires; only its effect is suppressed",
					}
				end,
				clearFaults = function()
					faults.layout = false
					faults.input = false
					faultsSignal:set(false)
					ctx.presenter.refresh()
					return { fault = "none", active = false }
				end,

				snapshot = function()
					return {
						boosts = boosts:get(),
						lap = lap:get(),
						readouts = readouts[1]:get(),
						faults = { layout = faults.layout, input = faults.input },
					}
				end,
			},
			report = function()
				return {
					sizeClass = conditions.sizeClass:get(),
					axis = conditions.axis:get(),
					isTenFoot = conditions.isTenFoot:get(),
					contentWidth = conditions.contentWidth:get(),
					virtualRows = 200,
					windowedRows = (function()
						local n = 0
						for _ in list.debugWindow() do
							n += 1
						end
						return n
					end)(),
					boosts = boosts:get(),
					boostText = boostText:get(),
					faults = { layout = faults.layout, input = faults.input },
					progress = progress.dump(),
				}
			end,
		}
	end,
}
