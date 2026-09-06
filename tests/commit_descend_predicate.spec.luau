--!strict
--[[ ── THE DESCEND LIST AGAINST `skip` ITSELF ───────────────────────────────────

	THE INVARIANT, in `render/commit_walks`' own words (`commit_descend_cache`'s
	header): "a walk descends a child if and only if that child is in the list the
	walk selected, and that list is, element for element, the set `skip(child, <that
	walk's own flags>)` answers 'descend' for. THERE IS NO SECOND CHECK BEHIND IT."
	A walk passes `chosen = true` to every child its parent's list handed it, so a
	child dropped from a list is not re-examined anywhere — it is simply not
	visited, and whatever the walk would have written it keeps from the last commit.

	WHICH MAKES THE LIST BUILDER AND THE PREDICATE TWO IMPLEMENTATIONS OF ONE RULE,
	and this file is the differential between them. `buildDescend` sifts a parent's
	children into three lists in one pass, sharing one `entryVerdict` and aliasing
	the arrays until two shapes disagree; `skip` answers the same question one child
	at a time from the same inputs. Every other spec in this family drives the
	CONSUMERS (rects, props, counters) and can only see a divergence that reaches an
	adapter write. This one asks the two implementations the same question directly,
	which is the cheapest possible statement of the invariant and the only one that
	holds for a child whose walk happens to write nothing that tick.

	IT IS NOT A HYPOTHETICAL. The aliasing has a per-array COUNT, and a fork that
	copied a prefix using the wrong array's count stored a commit list short by
	every child kept since the alias began — for the four arrange-blind walks
	(`textScale`, `padding`, `textVerdicts`, `scrollRegions`), which is a stale
	engine `TextSize`, a stale padding, a stale compact/wrap verdict and a stale
	scroll canvas on a child that WAS in the commit-dirty set. It shipped green
	through 8,663 suite cases because no case compared a list to the predicate.
	`tests/commit_arrange_sibling.spec.luau` is the end-to-end half. ]]
local testkit = require("./lib/testkit")
local commit_walks = require("../src/render/commit_walks")
local describe, it, expect = testkit.describe, testkit.it, testkit.expect

local function newCtx(stats: any)
	local noop = function() end
	return {
		adapter = { setRect = noop },
		handles = {},
		stats = stats,
		rectsEqual = function(a: any, b: any)
			return a == b
		end,
		paintedRectIn = function()
			return nil
		end,
		pathEscapesClip = function()
			return false
		end,
		reculPathClips = noop,
		lastTextSize = {},
		lastTextFont = {},
		lastPadding = {},
		lastCompact = {},
		lastWrapped = {},
		lastVisible = {},
		lastHitRects = {},
		lastScrollRegions = {},
		scrollAutoscroll = {},
		pathClipObservers = {},
		solverHidden = {},
		paintHeld = {},
		pathNodes = {},
		inputSinks = {},
		originOf = function()
			return 0, 0
		end,
		noteWorn = noop,
		lastCommitEntry = {},
		hiddenRoots = {},
		lastCompositions = {},
		lastTextFacts = {},
		authoredHidden = {},
	}
end

local function newStats()
	return { lastCommitVisits = 0, lastCommitVisitsByWalk = {}, lastCommitScans = 0, lastCommitProbes = 0 }
end

local function ids(list: { any }): string
	local out = {}
	for _, n in list do
		table.insert(out, n.path)
	end
	return table.concat(out, ",")
end

describe("buildDescend's three lists, against `skip`'s own answer", function()
	it("a commit-dirty child survives the arrange-blind sift", function()
		local stats = newStats()
		local ctx = newCtx(stats)
		local cw = commit_walks.new(ctx :: any)

		local A = { path = "/R/A", class = "Box", props = {}, children = {} }
		local B = { path = "/R/B", class = "Box", props = {}, children = {} }
		local C = { path = "/R/C", class = "Box", props = {}, children = {} }
		local root = { path = "/R", class = "Box", props = {}, children = { A, B, C } }

		local function e(x: number)
			return { rect = { x = x, y = 0, w = 10, h = 10 } }
		end
		local eR, eA, eB, eC = e(0), e(1), e(2), e(3)
		local rects = { ["/R"] = eR, ["/R/A"] = eA, ["/R/B"] = eB, ["/R/C"] = eC }

		-- what the LAST commit wrote: A and C settled (identity holds), B replaced
		ctx.lastCommitEntry["/R"] = e(99) -- root not settled, so the walk descends it
		ctx.lastCommitEntry["/R/A"] = eA
		ctx.lastCommitEntry["/R/B"] = e(98) -- B's entry is NEW this solve
		ctx.lastCommitEntry["/R/C"] = eC

		--  A  clean everywhere         -> every shape skips
		--  B  dirty in BOTH sets       -> every shape descends
		--  C  arrange-class dirt only  -> base/move descend, the COMMIT shape skips
		local nodeDirty = { ["/R"] = true, ["/R/B"] = true, ["/R/C"] = true }
		local commitDirty = { ["/R"] = true, ["/R/B"] = true }

		local metrics = {}
		-- the FIRST harvest sets the stamp; the prune only arms once the stamp holds
		cw.harvest(root, rects, true, nodeDirty, 1, metrics, 0, commitDirty)
		cw.harvest(root, rects, true, nodeDirty, 1, metrics, 0, commitDirty)
		expect(cw.scope.armed()).toBe(true)

		local base = cw.scope.descendOf(root)
		local move = cw.scope.descendOf(root, true)
		local commit = cw.scope.descendOf(root, true, true)

		-- ...and the ground truth: `skip` itself, asked child by child
		local truth = {}
		for _, child in root.children do
			if not cw.scope.skip(child, true, true) then
				table.insert(truth, child)
			end
		end
		print(`descend base=[{ids(base)}] move=[{ids(move)}] commit=[{ids(commit)}] skip-truth=[{ids(truth)}]`)
		expect(`commit=[{ids(commit)}]`).toBe(`commit=[{ids(truth)}]`)
	end)

	it("...for every ordering of every verdict class, on all three shapes", function()
		--[[ THE EXHAUSTIVE FORM, and the six classes are the whole verdict space of
			`buildDescend`'s branch read off `verdictOf`:

			  clean          settled, in no dirty set          — every shape skips
			  both           in `nodeDirty` and `commitDirty`  — every shape descends
			  arrange        `nodeDirty` only, settled entry   — the COMMIT fork
			  arrangeMoved   `nodeDirty` only, `moveOnly`      — the commit fork again,
			                                                     by the other route
			  moved          no dirt, `moveOnly` entry         — the MOVE fork
			  fresh          no dirt, no entry to probe        — every shape descends

			ORDER IS THE AXIS, not membership: the lists alias one array until two
			shapes disagree, so what a fork copies depends on which classes came BEFORE
			it. Four children over six classes is 1,296 orderings, which is every
			interleaving of two forks with a kept child between them, and the case that
			shipped broken (`clean`, `both`, `arrange`) is one of them. ]]
		local CLASSES = { "clean", "both", "arrange", "arrangeMoved", "moved", "fresh" }
		local WIDTH = 4
		local checked, forks = 0, 0
		local combo = table.create(WIDTH, 1)
		while true do
			local stats = newStats()
			local ctx = newCtx(stats)
			local cw = commit_walks.new(ctx :: any)
			local kids: { any } = {}
			local rects: any = { ["/R"] = { rect = { x = 0, y = 0, w = 1, h = 1 } } }
			local nodeDirty: { [string]: boolean } = { ["/R"] = true }
			local commitDirty: { [string]: boolean } = { ["/R"] = true }
			-- the root is dirty in both sets, so the walk reaches it and every child's
			-- verdict is the child's own
			ctx.lastCommitEntry["/R"] = { rect = { x = 9, y = 9, w = 9, h = 9 } }
			local label = {}
			for i = 1, WIDTH do
				local class = CLASSES[combo[i]]
				table.insert(label, class)
				local path = `/R/{i}`
				local child = { path = path, class = "Box", props = {}, children = {} }
				table.insert(kids, child)
				local entry = { rect = { x = i, y = 0, w = 10, h = 10 } }
				local prior = { rect = { x = i, y = 1, w = 10, h = 10 } }
				if class == "clean" then
					rects[path] = entry
					ctx.lastCommitEntry[path] = entry
				elseif class == "both" then
					rects[path] = entry
					ctx.lastCommitEntry[path] = prior
					nodeDirty[path] = true
					commitDirty[path] = true
				elseif class == "arrange" then
					rects[path] = entry
					ctx.lastCommitEntry[path] = entry
					nodeDirty[path] = true
				elseif class == "arrangeMoved" then
					rects[path] = { rect = entry.rect, moveOnly = true, prev = prior }
					ctx.lastCommitEntry[path] = prior
					nodeDirty[path] = true
				elseif class == "moved" then
					rects[path] = { rect = entry.rect, moveOnly = true, prev = prior }
					ctx.lastCommitEntry[path] = prior
				else
					-- `fresh`: no entry of its own and no single child to borrow one from
					ctx.lastCommitEntry[path] = prior
				end
			end
			local root = { path = "/R", class = "Box", props = {}, children = kids }
			local metrics = {}
			cw.harvest(root, rects, true, nodeDirty, 1, metrics, 0, commitDirty)
			cw.harvest(root, rects, true, nodeDirty, 1, metrics, 0, commitDirty)
			expect(cw.scope.armed()).toBe(true)

			local shapes = {
				{ name = "base", move = false, arrange = false },
				{ name = "move", move = true, arrange = false },
				{ name = "commit", move = true, arrange = true },
			}
			local seen = {}
			for _, shape in shapes do
				local list = cw.scope.descendOf(root, shape.move or nil, shape.arrange or nil)
				local truth = {}
				for _, child in kids do
					if not cw.scope.skip(child, shape.move or nil, shape.arrange or nil) then
						table.insert(truth, child)
					end
				end
				local key = table.concat(label, ">")
				expect(`{key} {shape.name}=[{ids(list)}]`).toBe(`{key} {shape.name}=[{ids(truth)}]`)
				seen[shape.name] = ids(list)
				checked += 1
			end
			if seen.commit ~= seen.base then
				forks += 1
			end

			-- ...odometer over the class table
			local at = WIDTH
			while at >= 1 and combo[at] == #CLASSES do
				combo[at] = 1
				at -= 1
			end
			if at < 1 then
				break
			end
			combo[at] += 1
		end
		--[[ NON-VACUITY, because a differential that never reaches the fork is a
			differential that cannot fail: the commit list has to actually PART COMPANY
			with the base list, and on most of these 1,296 orderings it does. ]]
		print(`descend sweep: {checked} list comparisons, {forks} orderings where commit ~= base`)
		expect(checked).toBe(1296 * 3)
		expect(forks > 600).toBe(true)
	end)
end)
