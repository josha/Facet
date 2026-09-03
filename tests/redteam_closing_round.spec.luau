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
end)

-- ===== 2. a composition is never a translated descendant ===================

local function compositionWorld(): any
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
								UI.Composition({
									id = "Comp",
									arrangements = { "column" },
									laneGap = 12,
									groupGap = 8,
									width = px(400),
									height = px(300),
									-- THE FIELD THAT MAKES THE RESOLUTION POSITION-DEPENDENT:
									-- author exclusions are window-space and are converted
									-- into the box, so moving the box moves which lanes they
									-- take out.
									exclusions = { { x = 0, y = 0, w = 200, h = 200 } },
									groups = {
										{ id = "main", lane = "main", sizing = "fill", minWidth = 120 },
									},
									children = {
										UI.Region({
											id = "R1",
											group = "main",
											rank = 1,
											children = { UI.Box({ id = "r1a", width = px(100), height = px(40) }) },
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
		local body = section(paintSource, "if cornersData == nil then", 1200)
		expect(contains(body, "for _, child in instance:GetChildren() do")).toBe(true)
		expect(contains(body, 'if child:IsA("UICorner") then')).toBe(true)
		-- the single-child form is what was wrong; the RESTORE path below it still
		-- reuses one instance on purpose (same identity, new radius), so the pin is
		-- on the teardown branch only
		expect(contains(body, 'local existing = instance:FindFirstChildOfClass("UICorner")')).toBe(false)
	end)

	it("every eraser on this instance sweeps GetChildren, and there are three of them", function()
		local sweeps = 0
		for _ in string.gmatch(paintSource, "for _, child in instance:GetChildren%(%) do") do
			sweeps += 1
		end
		-- applySurface plain, applySurface scrim, applyCorners' teardown
		expect(sweeps >= 3).toBe(true)
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
