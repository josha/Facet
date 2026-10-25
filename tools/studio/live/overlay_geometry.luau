--!strict
type Checks = { check: (string, boolean, unknown?) -> () }

local function inside(node: GuiObject, low: Vector2, high: Vector2, tolerance: number): boolean
	local at, ending = node.AbsolutePosition, node.AbsolutePosition + node.AbsoluteSize
	return at.X >= low.X - tolerance
		and at.Y >= low.Y - tolerance
		and ending.X <= high.X + tolerance
		and ending.Y <= high.Y + tolerance
end

local function attachment(
	t: Checks,
	panel: GuiObject,
	anchor: GuiObject,
	safe: GuiBase2d,
	gap: number,
	tail: GuiObject?
)
	local p, a = panel.AbsolutePosition, anchor.AbsolutePosition
	local ps, az = panel.AbsoluteSize, anchor.AbsoluteSize
	local gaps: { [string]: number } =
		{ bottom = p.Y - a.Y - az.Y, top = a.Y - p.Y - ps.Y, right = p.X - a.X - az.X, left = a.X - p.X - ps.X }
	local edge, error = "bottom", math.huge
	for name, distance in gaps do
		if math.abs(distance - gap) < error then
			edge, error = name, math.abs(distance - gap)
		end
	end
	local vertical = edge == "bottom" or edge == "top"
	local span = if vertical
		then math.min(p.X + ps.X, a.X + az.X) - math.max(p.X, a.X)
		else math.min(p.Y + ps.Y, a.Y + az.Y) - math.max(p.Y, a.Y)
	t.check(
		"settled panel attaches to anchor with expected gap",
		error <= 0.5 and span >= -0.5,
		{ edge = edge, gaps = gaps, expected = gap, overlap = span }
	)
	t.check(
		"settled panel stays inside safe area",
		inside(panel, safe.AbsolutePosition, safe.AbsolutePosition + safe.AbsoluteSize, 0.5),
		{ position = { p.X, p.Y }, size = { ps.X, ps.Y } }
	)
	if tail then
		local center = tail.AbsolutePosition + tail.AbsoluteSize / 2
		local point, low, high =
			if vertical then center.X else center.Y,
			if vertical then a.X else a.Y,
			if vertical then a.X + az.X else a.Y + az.Y
		t.check(
			"settled tail points inside anchor span",
			point >= low - 0.5 and point <= high + 0.5,
			{ point = point, low = low, high = high }
		)
	end
end

local function scrim(
	t: Checks,
	catcher: GuiObject,
	viewport: GuiObject,
	safe: GuiObject,
	panel: GuiObject,
	plate: boolean?
)
	local low, high = catcher.AbsolutePosition, catcher.AbsolutePosition + catcher.AbsoluteSize
	local clipping: { { path: string, position: { number }, size: { number } } } = {}
	local at = catcher.Parent
	while at do
		if at:IsA("GuiObject") and (at.ClipsDescendants or at:IsA("CanvasGroup")) then
			table.insert(clipping, {
				path = at:GetFullName(),
				position = { at.AbsolutePosition.X, at.AbsolutePosition.Y },
				size = { at.AbsoluteSize.X, at.AbsoluteSize.Y },
			})
			low = Vector2.new(math.max(low.X, at.AbsolutePosition.X), math.max(low.Y, at.AbsolutePosition.Y))
			local ending = at.AbsolutePosition + at.AbsoluteSize
			high = Vector2.new(math.min(high.X, ending.X), math.min(high.Y, ending.Y))
		end
		at = at.Parent
	end
	local v, ending = viewport.AbsolutePosition, viewport.AbsolutePosition + viewport.AbsoluteSize
	local overflow = { low.X - v.X, low.Y - v.Y, ending.X - high.X, ending.Y - high.Y }
	t.check(
		"scrim covers complete viewport including unsafe areas",
		math.max(table.unpack(overflow)) <= 1,
		{ overflow = overflow, clipping = clipping }
	)
	local bottom = panel.AbsolutePosition.Y + panel.AbsoluteSize.Y
	if plate and bottom > safe.AbsolutePosition.Y + safe.AbsoluteSize.Y + 1 then
		t.check(
			"a bottom sheet plate reaches the bottom of the glass",
			bottom >= ending.Y - 1,
			{ bottom = panel.AbsolutePosition.Y + panel.AbsoluteSize.Y, glass = ending.Y }
		)
		return
	end
	t.check(
		"modal panel stays inside core and device safe insets",
		inside(panel, safe.AbsolutePosition, safe.AbsolutePosition + safe.AbsoluteSize, 1),
		{
			panel = { panel.AbsolutePosition.X, panel.AbsolutePosition.Y, panel.AbsoluteSize.X, panel.AbsoluteSize.Y },
			safe = { safe.AbsolutePosition.X, safe.AbsolutePosition.Y, safe.AbsoluteSize.X, safe.AbsoluteSize.Y },
		}
	)
end

return { attachment = attachment, scrim = scrim }
