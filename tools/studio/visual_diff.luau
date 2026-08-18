--!strict
--[[
	VISUAL REGRESSION, AGAINST THE REAL ENGINE.

	Built for incremental layout (docs/plans/incremental-layout.md): the change makes
	the solver re-lay-out a subtree instead of the whole tree, so the only claim worth
	testing is that **the screen is identical**. The headless differential in
	`tests/` compares the fake adapter's virtual state, which is necessary and not
	sufficient — it cannot see engine rounding, native scroll offsets, clip-host
	re-parenting or ZIndex, and those are exactly the places a partial solve could go
	wrong.

	So this reads what the ENGINE actually resolved: `AbsolutePosition`,
	`AbsoluteSize`, `Visible`, `ZIndex` and text, for every GuiObject on the surface.
	Not the values Facet asked for — the values the engine ended up with.

	IT IS NOT A SCREENSHOT DIFF, deliberately. A screenshot compares pixels and tells
	you *that* something moved; this tells you *which node* moved and by how much,
	which is the difference between a finding and a hunt. Screenshots are still taken
	alongside it for human review — the two answer different questions.

	THE HARNESS MUST BE PROVEN STABLE BEFORE IT IS TRUSTED. `selfCheck` runs the same
	configuration twice and requires a zero diff. A comparison instrument that is not
	stable under no change reports every real comparison as a failure, and a green
	result from one that has never been checked means nothing.
]]

local visual_diff = {}

local Players = game:GetService("Players")

local function surfaces(): { Instance }
	local out = {}
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return out
	end
	for _, gui in pg:GetChildren() do
		if gui:IsA("ScreenGui") and gui.Enabled then
			table.insert(out, gui)
		end
	end
	return out
end

-- Every GuiObject on every live surface, keyed by its instance NAME — which for a
-- Facet node is its path, and therefore stable across a re-solve. Rounded to whole
-- pixels: the engine carries sub-pixel floats and comparing those would make the
-- instrument report noise as a defect.
function visual_diff.snapshot(filter: string?): { [string]: string }
	local out: { [string]: string } = {}
	for _, gui in surfaces() do
		if filter ~= nil and string.find(gui.Name, filter, 1, true) == nil then
			continue
		end
		for _, inst in gui:GetDescendants() do
			if inst:IsA("GuiObject") then
				local p, s = inst.AbsolutePosition, inst.AbsoluteSize
				local text = ""
				if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
					text = (inst :: any).Text
				end
				local image = ""
				if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
					image = (inst :: any).Image
				end
				-- THE KEY MUST BE UNIQUE. Facet node instances are named by path and are
				-- unique, but their adapter-owned CHROME children are not — every hit
				-- expander is called `FacetHitExpander`. Keying on name alone collapsed
				-- all of them onto one entry, and the survivor depended on
				-- `GetDescendants` order, so two runs of the SAME build reported a
				-- phantom difference. The key is the ancestry path plus the class.
				local key = inst.Name
				local parent = inst.Parent
				while parent ~= nil and not parent:IsA("ScreenGui") do
					key = parent.Name .. "/" .. key
					parent = parent.Parent
				end
				out[`{key}#{inst.ClassName}`] = string.format(
					"%d,%d %dx%d vis=%s z=%d clip=%s t=%s img=%s",
					math.floor(p.X + 0.5),
					math.floor(p.Y + 0.5),
					math.floor(s.X + 0.5),
					math.floor(s.Y + 0.5),
					tostring(inst.Visible),
					inst.ZIndex,
					tostring(inst.ClipsDescendants),
					text,
					image
				)
			end
		end
	end
	return out
end

-- a -> b. Reports MISSING, EXTRA and CHANGED separately, because they mean different
-- things: a missing node is a structural failure, a changed one is a geometry failure.
function visual_diff.diff(a: { [string]: string }, b: { [string]: string }, limit: number?): any
	local cap = limit or 12
	local missing, extra, changed = {}, {}, {}
	for k, v in a do
		local other = b[k]
		if other == nil then
			if #missing < cap then
				table.insert(missing, k)
			end
		elseif other ~= v then
			if #changed < cap then
				table.insert(changed, `{k}\n    A: {v}\n    B: {other}`)
			end
		end
	end
	for k in b do
		if a[k] == nil and #extra < cap then
			table.insert(extra, k)
		end
	end
	local function count(t: { [string]: string }): number
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end
	local total = 0
	for k, v in a do
		if b[k] ~= v then
			total += 1
		end
	end
	for k in b do
		if a[k] == nil then
			total += 1
		end
	end
	return {
		identical = total == 0,
		nodesA = count(a),
		nodesB = count(b),
		differences = total,
		missing = missing,
		extra = extra,
		changed = changed,
	}
end

-- PROVE THE INSTRUMENT BEFORE USING IT. `run` is called twice with nothing changed
-- in between; anything other than a zero diff means this harness cannot be used as
-- an oracle, and says so instead of quietly reporting a false positive later.
function visual_diff.selfCheck(run: () -> (), filter: string?): any
	run()
	local a = visual_diff.snapshot(filter)
	run()
	local b = visual_diff.snapshot(filter)
	local d = visual_diff.diff(a, b)
	return {
		stable = d.identical,
		nodes = d.nodesA,
		differences = d.differences,
		changed = d.changed,
		note = if d.identical
			then "the harness reproduces itself exactly; a difference in a real comparison is a real difference"
			else "UNSTABLE — this harness cannot be used as an oracle until the instability is explained",
	}
end

return visual_diff
