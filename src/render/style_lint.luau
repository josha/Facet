--!strict
-- Style lint (design §17 Phase 4 engine styling): walks a MOUNTED node tree
-- and flags engine-guidance violations as warnings (never hard errors —
-- these are quality/perf signals for the gate and the docs):
--   * "jagged-corner-shadow" — a node combining a shadow with a large corner
--     radius (engine release note: shadows may render jagged against large
--     corner radii). Threshold: any radius above LARGE_RADIUS px.
--   * "shadow-budget" — more than SHADOW_BUDGET shadowed nodes in one tree
--     (engine guidance: ~100 on-screen shadows; the perf runner measures the
--     write cost, the lint enforces the count).
-- lint(mountedNode) -> { { rule, path, detail } }

local style_lint = {}

style_lint.LARGE_RADIUS = 24
style_lint.SHADOW_BUDGET = 100

local CORNER_KEYS = { "topLeft", "topRight", "bottomLeft", "bottomRight" }

local function maxRadius(corners: any): number
	if corners == nil then
		return 0
	end
	if corners.form == "uniform" then
		return corners.radius or 0
	end
	local top = 0
	for _, key in CORNER_KEYS do
		top = math.max(top, corners[key] or 0)
	end
	return top
end

function style_lint.lint(mountedNode: any): { { rule: string, path: string, detail: string } }
	local warnings: { { rule: string, path: string, detail: string } } = {}
	local shadowCount = 0
	local function walk(node: any)
		local props = node.props
		if props ~= nil and props.shadow ~= nil then
			shadowCount += 1
			local radius = maxRadius(props.corners)
			if radius > style_lint.LARGE_RADIUS then
				table.insert(warnings, {
					rule = "jagged-corner-shadow",
					path = node.path,
					detail = `corner radius {radius}px > {style_lint.LARGE_RADIUS}px with a shadow may render jagged (engine caveat)`,
				})
			end
		end
		for _, child in node.children or {} do
			walk(child)
		end
	end
	walk(mountedNode)
	if shadowCount > style_lint.SHADOW_BUDGET then
		table.insert(warnings, {
			rule = "shadow-budget",
			path = mountedNode.path or "/",
			detail = `{shadowCount} shadowed nodes exceed the ~{style_lint.SHADOW_BUDGET} on-screen shadow guidance`,
		})
	end
	return warnings
end

return style_lint
