--!strict
-- Layout fuzz case (design §15.2; UI-LAYOUT-001/002): generates random node
-- trees over the full V1 sizing algebra and solves them at random viewports
-- (including degenerate 1x1 and huge), with random safe insets and root
-- policy. Invariants checked per case:
--   * solve() never throws;
--   * every generated node id receives a rect with finite coordinates and
--     non-negative finite width/height;
--   * determinism: solving the identical snapshot twice yields identical
--     rects and diagnostics;
--   * vstack/hstack children never overlap along the stack axis;
--   * adversarialCase: undefined dim combinations (percent on an unbounded
--     scroll axis; aspect on both axes) produce diagnostics, never crashes
--     or non-finite geometry.

local solver = require("../../../src/layout/solver")
local prng = require("../prng")

type Prng = prng.Prng
type Node = solver.Node

local layout_fuzzer = {}

local FONTS = { "BuilderSans", "GothamMedium" }
local TEXTS = {
	"OK",
	"Continue",
	"A longer label that will wrap somewhere",
	"Iñtërnâtiônàlizætiøn",
	"日本語のテキスト",
	"",
}

local nextId = 0

local function randomDim(rng: Prng, allowFill: boolean): solver.Dim?
	local roll = rng:range(1, 100)
	if roll <= 30 then
		return nil -- content (default)
	elseif roll <= 55 then
		return { type = "fixed", px = rng:range(1, 300) }
	elseif roll <= 70 and allowFill then
		return { type = "fill", weight = rng:range(1, 3) }
	elseif roll <= 85 then
		local d: solver.Dim = { type = "percent", fraction = rng:range(10, 100) / 100 }
		if rng:bool(0.3) then
			d.max = rng:range(50, 400)
		end
		if rng:bool(0.2) then
			d.offset = rng:range(-32, 32)
		end
		return d
	elseif roll <= 95 then
		local min = rng:range(0, 100)
		return { type = "minMax", min = min, max = min + rng:range(0, 200) }
	end
	return { type = "aspect", ratio = rng:range(5, 20) / 10 }
end

local function buildNode(rng: Prng, depth: number, forceAdversarial: boolean): Node
	nextId += 1
	local id = `n{nextId}`
	local leafKinds = { "text", "box", "spacer" }
	local containerKinds = { "vstack", "hstack", "zstack", "grid", "scroll", "anchor" }
	local kind: string
	if depth <= 0 then
		kind = rng:pick(leafKinds)
	elseif rng:bool(0.7) then
		kind = rng:pick(containerKinds)
	else
		kind = rng:pick(leafKinds)
	end

	local node: Node = { kind = kind, id = id }
	local width = randomDim(rng, true)
	local height = randomDim(rng, true)
	-- aspect on both axes is the ADVERSARIAL path; keep normal cases legal
	if not forceAdversarial and width and height and width.type == "aspect" and height.type == "aspect" then
		height = { type = "fixed", px = rng:range(10, 100) }
	end
	node.width = width
	node.height = height

	if rng:bool(0.4) then
		node.padding = rng:range(0, 16)
	end
	if rng:bool(0.3) then
		node.margin = if rng:bool(0.5)
			then rng:range(0, 20)
			else {
				top = rng:range(0, 20),
				right = rng:range(0, 20),
				bottom = rng:range(0, 20),
				left = rng:range(0, 20),
			}
	end

	if kind == "text" then
		node.text = rng:pick(TEXTS)
		node.font = rng:pick(FONTS)
		node.textSize = rng:range(8, 40)
		--[[ ...AND SOMETIMES THE SIZE IS THE SOLVER'S TO CHOOSE (`textSize = "fit"`,
			2026-08-22). This vocabulary spoke only NUMBERS, which is exactly why the
			differential oracle could not see the fit branch's stale-cache defect: a fit
			node's answer depends on the offered HEIGHT, and text nodes are exempt from
			the height key (`memoPlan`'s `PLAN_HEIGHT_FREE`, L-9's fact), so the first
			box's answer served the second. A fuzzer that cannot generate the shape
			cannot find the bug in it.

			`textFit` is the RESOLVED form the renderer hands the solver (cap and floor
			already through the typography scale, the paint offset beside them), because
			that is what the solver reads — generating the PROP would test the schema
			instead. One in four, so three quarters of the corpus stays the plain-size
			control the oracle has always compared against. ]]
		if rng:bool(0.25) then
			local cap = rng:range(10, 44)
			node.textFit = { cap = cap, floor = rng:range(6, math.max(6, cap)), offset = rng:pick({ 0, 0, 4, 14 }) }
		end
		return node
	end
	if kind == "box" or kind == "spacer" then
		return node
	end

	if kind == "vstack" or kind == "hstack" then
		node.gap = rng:range(0, 12)
		if rng:bool(0.4) then
			node.align = rng:pick({ "start", "center", "end", "stretch" })
		end
	elseif kind == "grid" then
		node.gap = rng:range(0, 12)
		if rng:bool(0.6) then
			node.columns = rng:range(1, 4)
		else
			node.minColumnWidth = rng:range(20, 160)
		end
	elseif kind == "scroll" then
		node.axis = rng:pick({ "y", "x" })
	end

	local children = {}
	for _ = 1, rng:range(1, 4) do
		local child = buildNode(rng, depth - 1, forceAdversarial)
		if kind == "anchor" then
			child.anchor = rng:pick({
				"topLeft",
				"top",
				"topRight",
				"left",
				"center",
				"right",
				"bottomLeft",
				"bottom",
				"bottomRight",
			})
			if rng:bool(0.3) then
				child.offsetX = rng:range(-40, 40)
				child.offsetY = rng:range(-40, 40)
			end
		end
		table.insert(children, child)
	end

	if forceAdversarial and kind == "scroll" then
		-- percent along the scroll axis measures against an unbounded limit
		nextId += 1
		local percentChild: Node = {
			kind = "box",
			id = `n{nextId}`,
			width = if node.axis == "x" then { type = "percent", fraction = 0.5 } else nil,
			height = if node.axis ~= "x" then { type = "percent", fraction = 0.5 } else nil,
		}
		table.insert(children, percentChild)
	end

	node.children = children
	return node
end

local function collectIds(node: Node, out: { string })
	table.insert(out, node.id)
	for _, child in node.children or {} do
		collectIds(child, out)
	end
end

local function checkFinite(id: string, rect: { x: number, y: number, w: number, h: number })
	for _, key in { "x", "y", "w", "h" } do
		local v = (rect :: any)[key]
		if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
			error(`node {id} rect.{key} is not finite: {tostring(v)}`)
		end
	end
	if rect.w < 0 or rect.h < 0 then
		error(`node {id} has negative size: w={rect.w} h={rect.h}`)
	end
end

local function serializeRects(rects: { [string]: any }): string
	local ids = {}
	for id in rects do
		table.insert(ids, id)
	end
	table.sort(ids)
	local parts = {}
	for _, id in ids do
		local r = rects[id].rect
		table.insert(parts, `{id}:{r.x},{r.y},{r.w},{r.h}`)
	end
	return table.concat(parts, ";")
end

-- assert stack children do not overlap along the stack's main axis
local function checkStackNoOverlap(node: Node, rects: { [string]: any })
	if node.kind == "vstack" or node.kind == "hstack" then
		local isH = node.kind == "hstack"
		local prevEnd: number? = nil
		for _, child in node.children or {} do
			local entry = rects[child.id]
			if entry ~= nil then
				local r = entry.rect
				local start = if isH then r.x else r.y
				local size = if isH then r.w else r.h
				if prevEnd ~= nil and start < prevEnd - 0.5 then
					error(
						`{node.kind} {node.id}: child {child.id} overlaps previous (start {start} < prev end {prevEnd})`
					)
				end
				prevEnd = math.max(prevEnd or -math.huge, start + size)
			end
		end
	end
	for _, child in node.children or {} do
		checkStackNoOverlap(child, rects)
	end
end

local function runOne(rng: Prng, forceAdversarial: boolean)
	nextId = 0
	local root = buildNode(rng, rng:range(1, 3), forceAdversarial)
	local viewport = {
		w = rng:pick({ 1, 40, 320, 375, 768, 1200 }),
		h = rng:pick({ 1, 40, 320, 667, 800, 1080 }),
	}
	local opts = {
		safeInsets = if rng:bool(0.4)
			then {
				top = rng:range(0, 60),
				bottom = rng:range(0, 40),
				left = rng:range(0, 40),
				right = rng:range(0, 40),
			}
			else nil,
		rootPolicy = if rng:bool(0.2) then "edgeToEdge" else nil,
	}

	local ok, result = pcall(solver.solve, root, viewport, opts)
	if not ok then
		error(`solver threw: {tostring(result)}`)
	end

	local ids = {}
	collectIds(root, ids)
	for _, id in ids do
		local entry = result.rects[id]
		if entry == nil then
			error(`node {id} missing from rects`)
		end
		checkFinite(id, entry.rect)
	end

	checkStackNoOverlap(root, result.rects)

	-- determinism: identical snapshot solves identically
	local again = solver.solve(root, viewport, opts)
	if serializeRects(result.rects) ~= serializeRects(again.rects) then
		error("solver is nondeterministic for an identical snapshot")
	end
	if #result.diagnostics ~= #again.diagnostics then
		error("solver diagnostics differ across identical solves")
	end

	return result
end

function layout_fuzzer.case(rng: Prng)
	runOne(rng, false)
end

-- every tree contains at least one undefined combination; the solver must
-- diagnose (not crash) and still emit finite geometry
function layout_fuzzer.adversarialCase(rng: Prng)
	nextId = 0
	local root: Node = {
		kind = "vstack",
		id = "adv-root",
		children = {
			{
				kind = "box",
				id = "adv-aspect-both",
				width = { type = "aspect", ratio = 1.5 },
				height = { type = "aspect", ratio = 0.75 },
			},
			buildNode(rng, 2, true),
			{
				kind = "scroll",
				id = "adv-scroll",
				axis = "y",
				height = { type = "fixed", px = rng:range(20, 120) },
				children = {
					{
						kind = "box",
						id = "adv-percent-unbounded",
						height = { type = "percent", fraction = 0.5 },
					},
				},
			},
		},
	}
	local viewport = { w = rng:pick({ 60, 375, 1200 }), h = rng:pick({ 60, 667, 1080 }) }
	local ok, result = pcall(solver.solve, root, viewport)
	if not ok then
		error(`solver threw on adversarial tree: {tostring(result)}`)
	end
	if #result.diagnostics == 0 then
		error("adversarial tree produced no diagnostics (aspect-on-both and percent-on-unbounded must be flagged)")
	end
	local ids = {}
	collectIds(root, ids)
	for _, id in ids do
		local entry = result.rects[id]
		if entry == nil then
			error(`adversarial node {id} missing from rects`)
		end
		checkFinite(id, entry.rect)
	end
end

return layout_fuzzer
