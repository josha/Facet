--!strict
--[[ THE WICKED-FAST CLOSING RED-TEAM'S THREE ADJUDICATED FINDINGS, one case each.

	The campaign's final adversarial pass read the whole `2d9f90cf..HEAD` diff and
	returned nine findings. Three were HIGH/MEDIUM and are fixed; this file is the
	demonstrator for those three, plus a source pin for the one that lives in a
	module no headless suite can execute.

	1. THE ANCHOR ARM SERVED A CHILD WITHOUT PUBLISHING ITS VERDICTS (HIGH).
	   `solver.luau`'s anchor reuse arm (T6) takes `w, h` from the previous entry
	   and skips `measure` — and `ctx.textStates`/`compact`/`textFacts` are fresh
	   per solve with `measure` as their ONLY writer. The arm already knew this
	   for a fourth channel (`ctx.offers`, re-recorded with a comment saying
	   exactly why); the other three were missed. It is only OBSERVABLE when the
	   served child then rebuilds a fresh entry literal instead of skipping or
	   translating, which is what the case below arranges: a `fill`-width anchor
	   child whose own reactive `offsetX` moves, so `offsetFill` hands it a
	   different width, `pr.w ~= rect.w`, and `arrange` writes a new literal with
	   `textFacts = ctx.textFacts[id]` — nil. Downstream that is a compact Button
	   silently un-compacting and a `textScale` fit write that never happens.

	   THE ASSERTION IS THE ENTRY, NOT A RECT. Every rect in the case is correct
	   before and after the fix, which is precisely why no existing differential
	   caught it: the geometry oracle in `anchor_arrange.spec.luau` compares rects
	   and would have stayed green forever.

	1b-1d. ...AND THE FOURTH CHANNEL WAS `ctx.diagnostics` (T9 task review,
	   Important 1). The three cases above the source pins are the long form the
	   solver's own comment points at.

	   WHY THE ARM CANNOT REPUBLISH IT. The other three channels are per-NODE
	   verdicts and `prev` carries each one, so the arm re-states them. A finding is
	   filed about any node in the served SUBTREE and the entry carries none, so
	   there is nothing to replay from. Nor can `solve`'s end-of-solve replay cover
	   it: it re-files a previous finding only when its filer is absent from
	   `walkedIds`, and the arm's own `arrange` call walks the whole served subtree.

	   WHY THE MEASURE STORE ALMOST HIDES IT, AND THE TWO SHAPES THAT REACH IT. A
	   measure-time finding normally rides P1's slate — `measure` captures every
	   finding an uncached call produced onto the entry and re-files them on an
	   adopted hit — so ANY enclosing ancestor whose measure descends or adopts puts
	   the finding back, and most trees are covered by the root's own measure. The
	   loss needs an anchor whose OWN measure never descends to the child, which is
	   an anchor with a definite size on both axes: `resolveAxis` answers `fixed`
	   without calling `contentFn`, so such a child is measured ONLY by the anchor
	   arrange branch — the exact call the arm skips. Case 1b is that shape with the
	   finding on the served child; case 1c nests two of them so the finding sits on
	   a WALKED DESCENDANT of a served child. Both were run RED first: the finding is
	   filed on the full solve and is absent from `controller.diagnostics()` from the
	   first reuse solve onward, forever.

	   THE FIX IS A FOURTH GATE, NOT A FOURTH REPUBLISH. The arm does not fire at all
	   on a solve whose predecessor filed a MEASURE-time finding (`ctx.measureQuiet`,
	   computed once per solve). It was chosen over the review's two candidates
	   because it is the only one exact in BOTH directions: re-filing the previous
	   solve's findings for the served subtree needs a subtree index no entry carries,
	   and keeping the served child out of `walkedIds` — the translate root's answer,
	   and sound there because a translate root's body never runs — would resurrect
	   the ARRANGE-time findings whose cause this very solve removed. Case 1d is that
	   negative control: a reactive `anchor` that goes bad and is then fixed, where
	   the arm must stay ARMED (an arrange-time finding is not a measure one) and the
	   stale finding must NOT come back. Telling the two apart is what the `measured`
	   stamp on the four measure-time filers is for; it is written in their literals
	   because `measure` has two early returns that never reach its capture block,
	   which a first draft of this fix stamped at and which the probe caught.

	   THE COST IS SCOPED TO A TREE THAT IS ALREADY MALFORMED. All four `measured`-
	   stamped filers report authoring defects (percent or containerRelative on an
	   unbounded axis, aspect on both, a scroll region on an unbounded axis) and none
	   is ever `designed`, so a well-formed surface never disarms the arm. A fifth
	   measure-time filer, `composition_resolve.luau`'s missing-`UI.Region` finding,
	   carries no stamp and needs none: the anchor arm never runs `measure` for the
	   served subtree, so `arrange`'s own composition resolve re-derives and re-files
	   it unconditionally wherever it is reached.

	   KNOWN AND PRE-EXISTING, NOT INTRODUCED HERE: a node measured uncached at N
	   distinct offers files N copies of the same measure-time finding, at HEAD and
	   before it. The fixtures below are single-copy shapes so the count pins mean
	   what they say; the duplicate class is booked, not fixed, in the T9 fix-round
	   report.

	2. A COMPOSITION WAS TRANSLATED AS A DESCENDANT (MEDIUM).
	   `literalIsWholeEntry` refuses a `composition` as a translate ROOT;
	   `translateDescendants` recursed with no kind check at all. A composition's
	   resolution is a function of its ORIGIN (author exclusions are converted from
	   window space into the box, and the platform-band reservation compares the
	   placed y against the root rect), so a `table.clone` + shifted rect carries
	   lanes computed at a position the box no longer occupies. `scroll` really is
	   translation-invariant in every field it stamps; this one is not.

	3. THE `applyCorners` NIL BRANCH ERASED ONE UICORNER WHERE ITS SIBLINGS ERASE
	   ALL (MEDIUM), plus the pre-seeded `handle: any?` -> `any`. Both live in
	   `src/client/`, which needs an engine, so both are pinned as source shape —
	   the same instrument `paint_extensions.spec.luau` uses for the live adapter's
	   own contracts, and the same instrument the T8 rounds used for these exact
	   branches. The live behaviour is covered by T9's Studio canary (five corner
	   cases, transcript in the FacetBench after-doc). ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local solver = require("../src/layout/solver")
local fake_target = require("./lib/fake_target")

local function contains(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
end

local function section(source: string, from: string, length: number): string
	local at = string.find(source, from, 1, true)
	expect(at ~= nil).toBe(true)
	return string.sub(source, at :: number, (at :: number) + length)
end

-- Slice-to-boundary form (final review, M-5): anchors the END on a distinctive
-- string that follows the branch rather than a fixed character count, so a
-- comment added inside the branch cannot push a later pin out of the window.
local function sectionUntil(source: string, from: string, upTo: string): string
	local at = string.find(source, from, 1, true)
	expect(at ~= nil).toBe(true)
	local stop = string.find(source, upTo, (at :: number) + 1, true)
	expect(stop ~= nil).toBe(true)
	return string.sub(source, at :: number, (stop :: number) - 1)
end

--[[ CAPTURE THE SOLVE THE RENDERER ACTUALLY DROVE. `renderer.luau` calls
	`solver.solve(...)` as a field lookup, so swapping the field is the documented
	seam (`translate_arm.spec.luau` states it) and the only way to read the entry
	map a real refresh produced — the controller does not publish it. Restored in
	the same call so a failure cannot leak the wrapper into another case. ]]
local function withSolveCapture<T>(fn: (() -> any) -> T): T
	local real = solver.solve
	local last: any = nil
	solver.solve = function(root: any, vp: any, opts: any): any
		local result = real(root, vp, opts)
		last = result
		return result
	end
	local ok, out = pcall(fn, function(): any
		return last
	end)
	solver.solve = real
	if not ok then
		error(out, 0)
	end
	return out :: T
end

local function px(n: number): any
	return { type = "fixed", px = n }
end
local FILL = { type = "fill", weight = 1 }
local ASPECT = { type = "aspect", ratio = 1 }
local ASPECT_ISSUE = "aspect on both axes is undefined; treating both as content"

-- the four fields these cases read off one refresh, in one place: how many
-- findings the surface reports, how many of them are the measure-time one under
-- test, and the two counters that say whether the anchor arm fired
local function readback(controller: any, lastSolve: () -> any, issue: string): any
	local diags = controller.diagnostics()
	local hits = 0
	for _, d in diags do
		if d.issue == issue then
			hits += 1
		end
	end
	local work = lastSolve().work or {}
	return {
		findings = #diags,
		hits = hits,
		solves = controller.stats().solves,
		reused = work.anchorReused,
		offered = work.anchorOffered,
	}
end

local function attach(core: any, root: any, env: any): any
	return renderer.attach(core, root, env, fake_target.new(), {
		rootPolicy = "edgeToEdge",
		incrementalLayout = true,
		measureReuse = true,
		layoutNodeReuse = true,
		commitScope = true,
	})
end

-- ===== 1. the anchor arm's verdict channels ================================

describe("RED-TEAM 1: an anchor child served by the reuse arm keeps its measure verdicts", function()
	it("a fill-width anchor child whose own offsetX moves rebuilds its entry WITH textFacts", function()
		withSolveCapture(function(lastSolve)
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
			env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
			local nudge = core:signal(0)
			local root = mountLib.mount(
				core,
				UI.Screen({
					id = "S",
					children = {
						UI.Anchor({
							id = "A",
							width = FILL,
							height = FILL,
							children = {
								-- THE ONE SHAPE THAT REACHES IT: `fill` width, so the final
								-- rect is `offsetFill(innerW, ox, ...)` rather than the
								-- measured width the arm serves; and the reactive prop is
								-- ARRANGE-classed, so `measureContains` stays clean and the
								-- arm fires.
								UI.Text({
									id = "T",
									text = "a label long enough that its measurement has something to say about itself",
									anchor = "topLeft",
									width = FILL,
									offsetX = nudge,
									offsetY = 4,
								}),
							},
						}),
					},
				})
			)
			local adapter = fake_target.new()
			local controller = renderer.attach(core, root, env, adapter, {
				rootPolicy = "edgeToEdge",
				incrementalLayout = true,
				measureReuse = true,
				layoutNodeReuse = true,
				commitScope = true,
			})
			controller.initialRender()
			-- one settling drive, so the next one is a genuine reuse solve
			nudge:set(1)
			controller.refresh()
			local before = lastSolve().rects["/S/A/T"]
			expect(before ~= nil).toBe(true)
			expect(type(before.textFacts)).toBe("table")

			nudge:set(40)
			controller.refresh()
			local after = lastSolve().rects["/S/A/T"]
			expect(after ~= nil).toBe(true)
			-- the entry really was REBUILT rather than skipped or translated — the
			-- fill width moved with the offset — so this is the case that bites
			expect(after.rect.w ~= before.rect.w).toBe(true)
			expect(after ~= before).toBe(true)
			-- ...and the verdict channel survived the rebuild. `nil` here is the
			-- defect: a commit reading it decides "not truncated" and "not compact"
			-- about a box whose width just changed.
			expect(type(after.textFacts)).toBe("table")
			expect(after.textFacts.text).toBe(before.textFacts.text)

			controller.dispose()
			root.dispose()
			return true
		end)
	end)

	it("...and a measure-time FINDING on that child survives the arm, exactly once", function()
		withSolveCapture(function(lastSolve)
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
			env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
			local nudge = core:signal(0)
			local root = mountLib.mount(
				core,
				UI.Screen({
					id = "S",
					children = {
						-- DEFINITE ON BOTH AXES, which is what keeps the measure pass out
						-- of this subtree: `resolveAxis` answers `fixed` without calling
						-- `contentFn`, so `C` is measured by the anchor ARRANGE branch and
						-- by nothing else — and that is the call the arm skips.
						UI.Anchor({
							id = "A",
							width = px(400),
							height = px(300),
							children = {
								UI.ZStack({
									id = "C",
									anchor = "topLeft",
									width = ASPECT,
									height = ASPECT,
									children = {
										-- the dirt is the GRANDCHILD's, and it is
										-- arrange-classed: `C` is measure-clean (so the arm
										-- serves it) and contains a dirty node (so it is
										-- walked rather than skipped or translated)
										UI.Box({ id = "E", width = px(60), height = px(40), offsetY = nudge }),
									},
								}),
							},
						}),
					},
				})
			)
			local controller = attach(core, root, env)
			controller.initialRender()
			local first = readback(controller, lastSolve, ASPECT_ISSUE)
			expect(first.solves).toBe(1)
			expect(first.hits).toBe(1)

			nudge:set(1)
			controller.refresh()
			local second = readback(controller, lastSolve, ASPECT_ISSUE)
			expect(second.solves).toBe(2)
			-- THE ASSERTION. Pre-fix this is 0: the arm served `C`, `measure` never
			-- ran on it, and `solve`'s replay refuses a finding whose filer is in
			-- `walkedIds` — which the arm's own `arrange` call put `C` into.
			expect(second.hits).toBe(1)
			-- ...and nothing was double-filed: the aspect finding plus the ZStack's
			-- own arrange-time report about `E`'s inert `offsetY`, and no third row
			expect(second.findings).toBe(2)
			-- the mechanism: the arm REFUSED to fire, so the child was offered
			expect(second.reused).toBe(0)
			expect(second.offered).toBe(1)

			-- and it does not decay on the next tick either (the pre-fix loss is
			-- permanent — the finding leaves `previous.diagnostics` and never returns)
			nudge:set(40)
			controller.refresh()
			local third = readback(controller, lastSolve, ASPECT_ISSUE)
			expect(third.solves).toBe(3)
			expect(third.hits).toBe(1)
			expect(third.findings).toBe(2)
			expect(third.reused).toBe(0)

			controller.dispose()
			root.dispose()
			return true
		end)
	end)

	it("...including one filed inside a WALKED DESCENDANT of a served child", function()
		withSolveCapture(function(lastSolve)
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
			env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
			local nudge = core:signal(0)
			local root = mountLib.mount(
				core,
				UI.Screen({
					id = "S",
					children = {
						UI.Anchor({
							id = "A",
							width = px(400),
							height = px(300),
							children = {
								-- two definite anchors, so BOTH arms fire: `A` serves `C`
								-- and `C` serves `D`. The finding is `D`'s and `D` is a
								-- walked descendant of the child `A` served.
								UI.Anchor({
									id = "C",
									anchor = "topLeft",
									width = px(200),
									height = px(150),
									children = {
										UI.ZStack({
											id = "D",
											anchor = "topLeft",
											width = ASPECT,
											height = ASPECT,
											children = {
												UI.Box({
													id = "E",
													width = px(60),
													height = px(40),
													offsetY = nudge,
												}),
											},
										}),
									},
								}),
							},
						}),
					},
				})
			)
			local controller = attach(core, root, env)
			controller.initialRender()
			expect(readback(controller, lastSolve, ASPECT_ISSUE).hits).toBe(1)

			nudge:set(1)
			controller.refresh()
			local second = readback(controller, lastSolve, ASPECT_ISSUE)
			expect(second.solves).toBe(2)
			expect(second.hits).toBe(1)
			expect(second.findings).toBe(2)
			-- both arms refused, and the count says both: two anchors, two offers
			expect(second.reused).toBe(0)
			expect(second.offered).toBe(2)

			controller.dispose()
			root.dispose()
			return true
		end)
	end)

	it("an ARRANGE-time finding neither disarms the arm nor survives its own repair", function()
		withSolveCapture(function(lastSolve)
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
			env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
			local anch = core:signal("topLeft")
			local root = mountLib.mount(
				core,
				UI.Screen({
					id = "S",
					children = {
						UI.Anchor({
							id = "A",
							width = px(400),
							height = px(300),
							children = { UI.Box({ id = "C", anchor = anch, width = px(60), height = px(40) }) },
						}),
					},
				})
			)
			local controller = attach(core, root, env)
			controller.initialRender()
			local BAD = "unknown anchor 'nope'"
			expect(readback(controller, lastSolve, BAD).findings).toBe(0)

			-- `anchor` is arrange-classed, so the arm serves `C` and the anchor branch
			-- files about it in the same solve. THE ARM MUST STAY ARMED: this finding
			-- is not a measure-time one, and disarming on it would cost the arm on
			-- every surface that ever reports anything.
			anch:set("nope")
			controller.refresh()
			local bad = readback(controller, lastSolve, BAD)
			expect(bad.solves).toBe(2)
			expect(bad.hits).toBe(1)
			expect(bad.findings).toBe(1)
			expect(bad.reused).toBe(1)
			expect(bad.offered).toBe(0)

			-- ...and the repair CLEARS it. This is the direction the `walkedIds`
			-- alternative would have broken: `C` is walked, files nothing this solve,
			-- and the replay must refuse to re-file a finding whose cause is gone.
			anch:set("topRight")
			controller.refresh()
			local fixed = readback(controller, lastSolve, BAD)
			expect(fixed.solves).toBe(3)
			expect(fixed.hits).toBe(0)
			expect(fixed.findings).toBe(0)
			expect(fixed.reused).toBe(1)

			controller.dispose()
			root.dispose()
			return true
		end)
	end)
end)

-- ===== 2. a composition is never a translated descendant ===================

--[[ ONE FIXTURE, TWO INNER NODES — the composition under test, and the `Box` that
	is its SIBLING POSITIVE CONTROL (T9 task review, Minor 4). `#translatedPaths == 0`
	is trivially true of a fixture where the arm never armed at all, so the case below
	runs the identical tree with `inner = "box"` and shows the same `Wrap` DOES take a
	translate run — which is what makes the zero an argued refusal rather than an
	absence. Everything else about the two trees is character-identical. ]]
local function compositionWorld(inner: string?): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local slide = core:signal(0)
	local root = mountLib.mount(
		core,
		UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "A",
					width = FILL,
					height = FILL,
					children = {
						-- the TRANSLATE ROOT: a plain box whose only dirt is its own
						-- offset, which is what makes the subtree below it translatable
						UI.ZStack({
							id = "Wrap",
							anchor = "topLeft",
							offsetX = 0,
							offsetY = slide,
							width = px(400),
							height = px(300),
							children = {
								if inner == "box"
									then UI.Box({ id = "Comp", width = px(400), height = px(300) })
									else UI.Composition({
										id = "Comp",
										arrangements = { "column" },
										laneGap = 12,
										groupGap = 8,
										width = px(400),
										height = px(300),
										-- THE FIELD THAT MAKES THE RESOLUTION POSITION-DEPENDENT:
										-- author exclusions are window-space and are converted
										-- into the box, so moving the box moves which lanes
										-- they take out.
										exclusions = { { x = 0, y = 0, w = 200, h = 200 } },
										groups = {
											{ id = "main", lane = "main", sizing = "fill", minWidth = 120 },
										},
										children = {
											UI.Region({
												id = "R1",
												group = "main",
												rank = 1,
												children = {
													UI.Box({ id = "r1a", width = px(100), height = px(40) }),
												},
											}),
										},
									}),
							},
						}),
					},
				}),
			},
		})
	)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = true,
		measureReuse = true,
		layoutNodeReuse = true,
		commitScope = true,
	})
	controller.initialRender()
	return {
		controller = controller,
		slide = function(v: number)
			slide:set(v)
			controller.refresh()
		end,
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

describe("RED-TEAM 2: the translate arm refuses a composition as a descendant", function()
	it("moving a box that holds an exclusion-carrying composition takes NO translate run", function()
		withSolveCapture(function(lastSolve)
			local w = compositionWorld()
			w.slide(7)
			w.slide(23)
			local result = lastSolve()
			local work = result.work or {}
			for _, path in work.translatedPaths or {} do
				-- the whole run is refused, so the composition cannot appear — and
				-- neither can its parent, since the root's own literal is only written
				-- once every descendant has been re-based
				expect(path ~= "/S/A/Wrap/Comp").toBe(true)
			end
			expect(#(work.translatedPaths or {})).toBe(0)
			-- ...and the entry is a real arrange, so the composition dump beside it was
			-- computed at the position the box now occupies
			local entry = result.rects["/S/A/Wrap/Comp"]
			expect(entry ~= nil).toBe(true)
			expect(entry.moveOnly).toBe(nil)
			expect(entry.rect.y).toBe(23)
			w.dispose()
			return true
		end)
	end)

	it("SIBLING POSITIVE CONTROL: the same fixture with a Box in its place DOES translate", function()
		withSolveCapture(function(lastSolve)
			local w = compositionWorld("box")
			w.slide(7)
			w.slide(23)
			local result = lastSolve()
			local work = result.work or {}
			-- the arm really is armed on this tree, and it really did re-base this
			-- subtree — so the zero above is a refusal, not an arm that never fired
			expect(#(work.translatedPaths or {}) >= 1).toBe(true)
			local entry = result.rects["/S/A/Wrap/Comp"]
			expect(entry ~= nil).toBe(true)
			expect(entry.moveOnly).toBe(true)
			expect(entry.rect.y).toBe(23)
			-- ...and the run reached the box itself, by path
			local found = false
			for _, path in work.translatedPaths or {} do
				if path == "/S/A/Wrap/Comp" then
					found = true
				end
			end
			expect(found).toBe(true)
			w.dispose()
			return true
		end)
	end)

	it("the refusal is a KIND check in translateDescendants, beside the root's own", function()
		local source = fs.readFile("src/layout/solver.luau")
		local body = section(source, "local function translateDescendants(", 2400)
		expect(contains(body, 'if child.kind == "composition" then')).toBe(true)
		-- the root-side refusal it mirrors, still present
		expect(contains(source, 'return kind ~= "scroll" and kind ~= "composition"')).toBe(true)
	end)
end)

-- ===== 3. the live-adapter source contracts ================================

describe("RED-TEAM 3: the paint erasers agree with each other", function()
	local paintSource = fs.readFile("src/client/screen_paint.luau")
	local chromeSource = fs.readFile("src/client/screen_chrome.luau")

	it("applyCorners' nil-with-no-record branch destroys EVERY UICorner, like its siblings", function()
		local body = sectionUntil(paintSource, "if cornersData == nil then", "the AUTHORED token re-derived")
		expect(contains(body, "for _, child in instance:GetChildren() do")).toBe(true)
		expect(contains(body, 'if child:IsA("UICorner") then')).toBe(true)
		-- the single-child form is what was wrong; the RESTORE path below it still
		-- reuses one instance on purpose (same identity, new radius), so the pin is
		-- on the teardown branch only — sliced to it, so the single-child CALL
		-- bites (the first pin named a variable the file never had: vacuous; the
		-- bare method name is in that branch's own comment, so pin the call shape)
		local teardown =
			sectionUntil(body, "if restored == nil then", "local uiCorner = instance:FindFirstChildOfClass")
		expect(contains(teardown, "for _, child in instance:GetChildren() do")).toBe(true)
		expect(contains(teardown, 'instance:FindFirstChildOfClass("UICorner")')).toBe(false)
	end)

	it("every eraser on this instance sweeps GetChildren, and there are three of them", function()
		local sweeps = 0
		for _ in string.gmatch(paintSource, "for _, child in instance:GetChildren%(%) do") do
			sweeps += 1
		end
		-- applySurface plain, applySurface scrim, applyCorners' teardown — EXACTLY
		-- three, so a fourth eraser arriving without a case here fails this line
		-- rather than sliding under a `>=` (T9 task review, Minor 4)
		expect(sweeps).toBe(3)
		expect(contains(chromeSource, "for _, child in instance:GetChildren() do")).toBe(true)
	end)

	it("applySkinnedSuppression takes a REQUIRED handle (pre-seeded finding)", function()
		expect(
			contains(
				chromeSource,
				"local function applySkinnedSuppression(instance: GuiObject, on: boolean, handle: any)"
			)
		).toBe(true)
		-- ...and the optional form is gone from THIS signature (the file has other
		-- functions that legitimately take an optional handle, so the pin is on the
		-- one signature the finding names, not on the token)
		expect(contains(chromeSource, "applySkinnedSuppression(instance: GuiObject, on: boolean, handle: any?)")).toBe(
			false
		)
		-- and the dead alias in the target is gone
		local targetSource = fs.readFile("src/client/screen_target.luau")
		expect(contains(targetSource, "local applySkinnedSuppression = chrome.applySkinnedSuppression")).toBe(false)
	end)
end)
