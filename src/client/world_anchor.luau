--!strict
-- Screen-overlay projection only; no Instances, input, or frame driver created.
local guard = require("../spec_guard")
local worldAnchor = {}
local KEYS = guard.keySet({ "target", "padding", "camera" })
local function read(value: any): any
	return if type(value) == "table" and type(value.get) == "function" then value:get() else value
end
local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- host is client.host.new() or its {core, presenter} pair. services is a test seam.
function worldAnchor.new(host: any, opts: any, services: any?): any
	guard.assertKnownKeys("world_anchor.new", opts, KEYS, "opts")
	assert(type(opts) == "table" and opts.target ~= nil, "world_anchor.new: target is required")
	local padding = if opts.padding == nil then 0.15 else opts.padding
	assert(
		finite(padding) and padding >= 0 and padding <= 1,
		"world_anchor.new: padding must be a fraction from 0 to 1"
	)
	local scene = if services then services.workspace else workspace
	local function sample(): any
		local target, camera = read(opts.target), read(opts.camera) or scene.CurrentCamera
		if target == nil or camera == nil then
			return { visible = false }
		end
		assert(
			target:IsA("BasePart") or target:IsA("Model") or target:IsA("Player"),
			"world_anchor.new: target must be a BasePart, Model, or Player"
		)
		if target:IsA("Player") then
			target = target.Character
		end
		if target == nil or not target:IsDescendantOf(scene) then
			return { visible = false }
		end
		local cf, size
		if target:IsA("Model") then
			if not target:FindFirstChildWhichIsA("BasePart", true) then
				return { visible = false }
			end
			cf, size = target:GetBoundingBox()
		else
			cf, size = target.CFrame, target.Size
		end
		local points = {}
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					local point = cf.Position
						+ cf.RightVector * (size.X * x / 2)
						+ cf.UpVector * (size.Y * y / 2)
						+ cf.LookVector * (size.Z * z / 2)
					-- Facet solves in window space, including the top bar.
					local p = camera:WorldToViewportPoint(point)
					if not finite(p.X) or not finite(p.Y) or not finite(p.Z) or p.Z <= math.abs(camera.NearPlaneZ) then
						return { visible = false }
					end
					minX, minY, maxX, maxY =
						math.min(minX, p.X), math.min(minY, p.Y), math.max(maxX, p.X), math.max(maxY, p.Y)
					table.insert(points, p)
				end
			end
		end
		local x, y = (minX + maxX) / 2, (minY + maxY) / 2
		local view = camera.ViewportSize
		if x < 0 or y < 0 or x > view.X or y > view.Y then
			return { visible = false }
		end
		local radius = 0
		for _, p in points do
			radius = math.max(radius, math.sqrt((p.X - x) ^ 2 + (p.Y - y) ^ 2))
		end
		return { x = x, y = y, clearance = radius * (1 + padding), visible = true }
	end
	-- Validate and measure before allocating, so invalid authoring cannot leak.
	local first = sample()
	local scope = host.core:scope("world-anchor")
	local anchor = scope:own(host.core:signal(first))
	local disposed = false
	scope:own(host.presenter.onTick(function()
		-- Streaming/destruction can invalidate a target between reads. Never leave
		-- the last valid anchor interactive when a native read fails.
		local ok, nextValue = pcall(sample)
		if not ok then
			nextValue = { visible = false }
		end
		local old = anchor:get()
		if
			old.visible ~= nextValue.visible
			or old.x ~= nextValue.x
			or old.y ~= nextValue.y
			or old.clearance ~= nextValue.clearance
		then
			anchor:set(nextValue)
		end
	end))
	return table.freeze({
		anchor = anchor,
		dispose = function()
			if not disposed then
				disposed = true
				anchor:set({ visible = false })
				scope:dispose()
			end
		end,
	})
end
return worldAnchor
