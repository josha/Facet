--!strict
-- The performance lab's LAUNCHER / STATUS OVERLAY (roadmap Step 9, PL-10).
--
-- It is a development control surface, not a demo: selectors, run controls, the
-- live counter set, and the on-screen build/scenario/device labels the execution
-- contract requires a review build to carry (§8).
--
-- IT MUST BE ABLE TO LEAVE COMPLETELY. "Clean capture mode" does not hide the
-- overlay behind a transparency — it DISMISSES the surface, because a hidden
-- ScreenGui is still a mounted tree the workload's instance census would count
-- and the frame would still pay for. `perf_lab` owns the dismiss; this module
-- owns only the blueprint and the signals it reads.
--
-- ENGINE-FREE: `Facet` and `core` arrive as arguments, every value is a signal
-- the scenario writes, and no engine type appears anywhere in the file.

local overlay = {}

export type Model = {
	-- identity labels (contract §8: an on-screen build/fixture/device label)
	buildLine: any, -- Readable<string>
	scenarioLine: any, -- Readable<string>
	deviceLine: any, -- Readable<string>
	-- state
	statusLine: any, -- Readable<string> — ready / warming / capturing / stopped
	countdown: any, -- Readable<string>
	counterLines: any, -- Readable<{string}>
	-- actions, supplied by perf_lab
	actions: { { id: string, label: string, run: () -> () } },
	scenarioNames: { string },
	onSelectScenario: (name: string) -> (),
	currentScenario: any, -- Readable<string>
	-- step through the workload list without hunting for a chip. `delta` is +1 or -1
	-- and wraps at both ends
	onCycleScenario: (delta: number) -> (),
	scenarioPosition: any, -- Readable<string> — "3/9"
	-- run every workload back to back, then stop so a single MicroProfiler dump
	-- covers the whole sweep
	onRunAll: () -> (),
	-- true when the installed theme charges enough across that "Run all" no longer
	-- fits beside the cycler and takes its own line (L-26). Supplied by perf_lab from
	-- the live snapshot; false — and so structurally invisible — on every flat package.
	splitAction: boolean?,
}

function overlay.build(Facet: any, core: any, model: Model): any
	local UI = Facet.UI

	local chips = {}
	for _, name in model.scenarioNames do
		table.insert(
			chips,
			UI.Button({
				id = `S_{string.gsub(name, "%-", "_")}`,
				label = name,
				onActivate = function()
					model.onSelectScenario(name)
				end,
			})
		)
	end

	-- THE ACTION ROW WRAPS. Five buttons in one HStack need ~420px; on a 360px phone
	-- the last one ("Clean capture") was clipped at the screen edge and the row painted
	-- over the list behind it. An HStack does not compress on its main axis — it paints
	-- past its own box — so the fix is to stop asking it to.
	--
	-- `UI.Grid` wraps into as many rows as it needs and reports its real height, which
	-- is what the panel's reservation is measured from, so the workload lays out below
	-- whatever the buttons actually occupy.
	local actionButtons = {}
	for _, action in model.actions do
		table.insert(
			actionButtons,
			UI.Button({
				id = action.id,
				label = action.label,
				onActivate = action.run,
			})
		)
	end
	--
	-- THE COLUMN COUNT IS THE SOLVER'S, NOT THE CALLER'S. The first fix passed a
	-- count computed from `viewportRect` at build time — and a blueprint is built
	-- ONCE, so after a landscape-to-portrait rotation the panel still carried
	-- landscape's five columns and clipped exactly as before. Same split brain as
	-- the row height (docs/lessons/the-solver-already-told-you.md): a viewport
	-- number read once is a number that is wrong on the second screen.
	--
	-- `minColumnWidth = "intrinsic"` asks the solver for the width it already
	-- measured for the widest button and fits as many as the real box allows, on
	-- every solve. No viewport read, no rebuild, nothing to keep in sync.
	local actionRow = UI.Grid({
		id = "Actions",
		minColumnWidth = "intrinsic",
		gap = 6,
		width = { type = "fill", weight = 1 },
		children = actionButtons,
	})

	-- ONE TEXT NODE PER LINE, not one node holding newlines (found live 2026-08-04;
	-- docs/lessons/embedded-newlines-measure-as-one-line.md). The first version
	-- joined the counter lines with `\n` to keep a development overlay from
	-- re-solving six nodes per update — and the solver measures an embedded newline
	-- as ONE line, so the block reserved a 29px box, drew six lines into it, and
	-- reported `truncated = false`. Four counters were simply invisible.
	--
	-- A fixed number of rows keeps the node count bounded; lines beyond it would be
	-- the same defect in a different shape, so the model's line count is asserted
	-- rather than assumed.
	-- THE SCENARIO CYCLER — the first thing in the panel, and the reason this row
	-- exists at all. The picker below is a nine-chip ScrollView, and on a phone the
	-- panel is capped at about a third of the screen, so every chip sat below the fold:
	-- the lab had a full scenario list that a person looking at the screen could not
	-- find. A prev/next pair with the current name between them needs one row, is
	-- reachable without scrolling anything, and answers "which one am I on?" at the
	-- same time. The chip list stays for jumping straight to a workload.
	-- RUN ALL LIVES IN THE CYCLER ROW, not in the action grid below it. The panel is
	-- capped at a third of the screen and on a 338px-tall landscape phone that is one
	-- row — the action grid was below the fold, so the one button a profiling session
	-- actually presses was invisible on exactly the device the session is for. The
	-- cycler row is the only row guaranteed to be on screen, so the primary action
	-- belongs in it.
	--
	-- ...ON ITS OWN LINE UNDER A THEME (L-26, 2026-08-05). Every control in this row
	-- pays the installed package's `chromeInsets` — 14 per side under fantasy-ornate —
	-- and the panel itself pays its own, so measured at 360px the five items needed
	-- 415px of the 310 left to them: the row overflowed by 105 and the scenario name
	-- between the arrows compressed to ZERO. An HStack does not compress on its main
	-- axis, so the fix is the one the action grid above already uses — stop asking it
	-- to. `compactLabel` cannot help here and was tried: the solver's compact swap
	-- fires when a button is HANDED a narrow box, and an overflowing HStack narrows
	-- nobody.
	--
	-- The condition is the theme's own charge rather than a remembered width, so it is
	-- exactly 0 on every flat package and this whole branch is unreachable there — the
	-- flat overlay is byte-identical, which is what keeps every recorded capture valid.
	-- Both lines are still above the picker, so the guarantee the paragraph above is
	-- about survives.
	local splitAction = model.splitAction == true
	local runAll = UI.Button({
		id = "RunAllTop",
		label = "▶ Run all",
		onActivate = function()
			model.onRunAll()
		end,
	})
	local cycleChildren = {
		UI.Button({
			id = "Prev",
			label = "◀",
			onActivate = function()
				model.onCycleScenario(-1)
			end,
		}),
		UI.Text({
			id = "Current",
			text = model.currentScenario,
			textSize = 15,
			textAlign = "center",
			-- one line, ellipsised: the longest workload name is wider than the
			-- space between two buttons on a 360px screen, and a name that wraps
			-- would grow this row past the height the panel reserved for it
			lineLimit = 1,
			width = { type = "fill", weight = 1 },
		}),
		UI.Text({ id = "Position", text = model.scenarioPosition, textSize = 12 }),
		UI.Button({
			id = "Next",
			label = "▶",
			onActivate = function()
				model.onCycleScenario(1)
			end,
		}),
	}
	if not splitAction then
		table.insert(cycleChildren, runAll)
	end
	local cycleRow = UI.HStack({
		id = "Cycle",
		gap = 6,
		width = { type = "fill", weight = 1 },
		children = cycleChildren,
	})
	-- The primary action's own line, inserted directly under the cycler so it is
	-- still above the fold the paragraph above is about. Appended to a LIST rather
	-- than written as a conditional element of the stack's literal: `{a, nil, b}`
	-- leaves an array whose length is a border, and the element that would vanish is
	-- the status line.
	local actionLine = if splitAction
		then UI.HStack({
			id = "PrimaryAction",
			gap = 6,
			width = { type = "fill", weight = 1 },
			children = { runAll },
		})
		else nil

	local COUNTER_LINES = 6
	local counterTexts = {}
	for i = 1, COUNTER_LINES do
		local line = core:memo(function(use)
			local lines = use(model.counterLines)
			return lines[i] or ""
		end)
		table.insert(counterTexts, UI.Text({ id = `C{i}`, text = line, textSize = 12 }))
	end

	-- ORDER IS REACHABILITY. The panel is bounded and scrolls, so whatever sits below
	-- the fold needs a gesture to reach — and on a 339px-tall landscape phone the fold
	-- lands about 140px in. So the top of the panel is exactly the three things a
	-- session needs and nothing else: WHICH workload (and the controls to change it),
	-- WHAT it is doing right now, and the identity labels the execution contract
	-- requires on screen (§8). Everything else is a scroll away and that is fine.
	--
	-- `Status` is second because it is where "DONE 9/9 — dump now: Ctrl/Cmd+F6"
	-- appears. A finished sweep that announces itself below the fold has not announced
	-- itself.
	local stackChildren = { cycleRow }
	if actionLine ~= nil then
		table.insert(stackChildren, actionLine)
	end
	table.insert(
		stackChildren,
		UI.HStack({
			id = "Status",
			gap = 8,
			-- FILL, or the `fill` child below collapses. A `fill` child asks its
			-- parent for the leftover main-axis space, and a HUGGING parent has
			-- none to give — it sizes itself to its content, so the child resolves
			-- to ~zero and the status renders as a single character. Measured, not
			-- reasoned: the first attempt set the child to fill and left this row
			-- hugging, and the device showed "F".
			width = { type = "fill", weight = 1 },
			children = {
				--[[ FILL, SO IT WRAPS INSTEAD OF RUNNING OFF THE EDGE.

					Device report, 2026-08-13: the mount-refusal message was cut off
					on a phone — twice, once before it was shortened and again after.
					The message was not the whole problem. This Text had no width, so
					in an HStack it takes its natural single-line extent and simply
					overflows the overlay; anything past the panel edge is unreadable
					no matter how short the string gets.

					A `fill` width makes it wrap to as many lines as it needs, which
					is what a diagnostic has to do — a status line that can only ever
					show its first sixty characters cannot carry a node path AND what
					went wrong. ]]
				UI.Text({
					id = "State",
					text = model.statusLine,
					textSize = 15,
					width = { type = "fill", weight = 1 },
				}),
				UI.Text({ id = "Countdown", text = model.countdown, textSize = 15 }),
			},
		})
	)
	table.insert(
		stackChildren,
		UI.VStack({
			id = "Head",
			gap = 2,
			children = {
				UI.Text({ id = "Build", text = model.buildLine, textSize = 13 }),
				UI.Text({ id = "Scenario", text = model.scenarioLine, textSize = 13 }),
				UI.Text({ id = "Device", text = model.deviceLine, textSize = 13 }),
			},
		})
	)
	table.insert(stackChildren, actionRow)
	table.insert(
		stackChildren,
		UI.ScrollView({
			id = "Picker",
			axis = "y",
			-- FIXED, deliberately: a `percent` here is measured against the panel's own
			-- scroll axis, which has no bound, and the solver rightly refused it (caught
			-- by the overlay layout audit on its first run). The panel scrolls, so a
			-- fixed picker cannot trap a control off-screen.
			height = { type = "fixed", px = 110 },
			width = { type = "fill", weight = 1 },
			children = { UI.VStack({ id = "Chips", gap = 4, children = chips }) },
		})
	)
	table.insert(stackChildren, UI.VStack({ id = "Counters", gap = 0, children = counterTexts }))

	-- ANCHORED TO THE BOTTOM, NOT FLOATING OVER THE WORKLOAD (found in the first
	-- live capture, 2026-08-04). Two `present()` surfaces stack in present order and
	-- the workload is presented after the overlay, so an un-anchored overlay ended
	-- up UNDER the list with its header text painted through the list's own — every
	-- selector and counter unreachable. The workload occupies the top of the screen
	-- (a 420px viewport plus its header), so the control surface takes the bottom.
	-- `perf_lab` additionally re-presents this surface after every mount so z-order
	-- follows, exactly as the showcase bootstrap raises its chrome.
	-- THE PANEL IS BOUNDED AND SCROLLS. A control surface that grows with its content
	-- will always, on some real screen, be taller than the screen — and on a 390px-tall
	-- landscape phone it left no room for the list at all. Capping it at a fraction of
	-- the viewport (the caller measures it) keeps every control reachable by scrolling
	-- while guaranteeing the workload always gets the majority of the screen.
	return UI.Screen({
		id = "PerfLabOverlay",
		padding = 8,
		children = {
			UI.Anchor({
				id = "Dock",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.ScrollView({
						id = "Panel",
						axis = "y",
						anchor = "bottomLeft",
						-- OPAQUE. Two presented surfaces do not composite into one
						-- layout, so a panel with no plate lets the workload read
						-- straight through its own labels — which is what a phone
						-- screenshot showed: counter text woven into list rows.
						surface = "raised",
						padding = 8,
						width = { type = "fill", weight = 1 },
						-- A FRACTION OF THE SCREEN, RESOLVED EVERY SOLVE. A fixed px
						-- computed by the caller was a snapshot of one orientation;
						-- `percent` with a clamp is the same intent stated to the
						-- solver, so rotation just re-solves it.
						height = { type = "percent", fraction = 0.34, min = 96, max = 260 },
						children = {
							UI.VStack({
								id = "Stack",
								width = { type = "fill", weight = 1 },
								gap = 6,
								children = stackChildren,
							}),
						},
					}),
				},
			}),
		},
	})
end

return overlay
