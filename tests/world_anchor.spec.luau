--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local rbx = require("@lune/roblox")
local worldAnchor = require("../src/client/world_anchor")
local function fixture()
	local scene = {}
	local camera = { NearPlaneZ = -0.5, ViewportSize = { X = 800, Y = 600 } }
	function camera:WorldToViewportPoint(p)
		return { X = 400 + p.X * 100 / -p.Z, Y = 300 - p.Y * 100 / -p.Z, Z = -p.Z }
	end
	scene.CurrentCamera = camera
	local part = { CFrame = rbx.CFrame.new(0, 0, -10), Size = rbx.Vector3.new(4, 2, 2), live = true }
	function part:IsA(name)
		return name == "BasePart"
	end
	function part:IsDescendantOf(root)
		return root == scene and self.live
	end
	local tick, connected = nil, false
	local host = {
		core = Facet.newCore(),
		presenter = {
			onTick = function(fn)
				tick, connected = fn, true
				return function()
					connected = false
				end
			end,
		},
	}
	return host,
		scene,
		part,
		function()
			if connected then
				tick(1 / 60)
			end
		end,
		function()
			return connected
		end
end
t.describe("world anchor", function()
	t.it("encloses projected corners with padding and updates on the host frame", function()
		local host, scene, part, tick = fixture()
		local binding = worldAnchor.new(host, { target = part, padding = 0.15 }, { workspace = scene })
		local a = binding.anchor:get()
		t.expect(a.visible).toBe(true)
		t.expect(a.x).toBe(400)
		t.expect(a.y).toBe(300)
		t.expect(math.abs(a.clearance - (math.sqrt(20 * 20 + 10 * 10) / 0.9 * 1.15)) < 0.001).toBe(true)
		part.CFrame = rbx.CFrame.new(2, 0, -5) * rbx.CFrame.Angles(0, 0.5, 0.3)
		tick()
		t.expect(binding.anchor:get().x > a.x).toBe(true)
		t.expect(binding.anchor:get().clearance > a.clearance).toBe(true)
		binding.dispose()
	end)
	t.it("uses relative padding at every distance and defaults to fifteen percent", function()
		for _, padding in { false, 0, 0.15, 0.5, 1 } do
			local host, scene, part, tick = fixture()
			local options = { target = part }
			if padding ~= false then
				options.padding = padding
			end
			local binding = worldAnchor.new(host, options, { workspace = scene })
			for _, distance in { 5, 10, 20 } do
				part.CFrame = rbx.CFrame.new(0, 0, -distance)
				tick()
				local radius = math.sqrt(200 ^ 2 + 100 ^ 2) / (distance - 1)
				local fraction = if padding == false then 0.15 else padding
				t.expect(math.abs(binding.anchor:get().clearance / radius - (1 + fraction)) < 0.00001).toBe(true)
			end
			binding.dispose()
		end
	end)
	t.it("tracks models, avatar respawns, camera replacement and unavailable targets", function()
		local host, scene, part, tick, connected = fixture()
		local model = { live = true }
		function model:IsA(name)
			return name == "Model"
		end
		function model:IsDescendantOf(root)
			return self.live and root == scene
		end
		function model:FindFirstChildWhichIsA()
			return part
		end
		function model:GetBoundingBox()
			return part.CFrame, part.Size
		end
		local player = { Character = model }
		function player:IsA(name)
			return name == "Player"
		end
		local target = host.core:signal(player)
		local binding = worldAnchor.new(host, { target = target }, { workspace = scene })
		t.expect(binding.anchor:get().clearance > 0).toBe(true)
		player.Character = nil
		tick()
		t.expect(binding.anchor:get().visible).toBe(false)
		player.Character = model
		tick()
		t.expect(binding.anchor:get().visible).toBe(true)
		scene.CurrentCamera = nil
		tick()
		t.expect(binding.anchor:get().visible).toBe(false)
		binding.dispose()
		binding.dispose()
		t.expect(connected()).toBe(false)
	end)
	t.it("rejects near-plane intersections and offscreen or removed objects", function()
		local host, scene, part, tick = fixture()
		local binding = worldAnchor.new(host, { target = part }, { workspace = scene })
		for _, cf in { rbx.CFrame.new(0, 0, -1), rbx.CFrame.new(0, 0, 10), rbx.CFrame.new(100, 0, -10) } do
			part.CFrame = cf
			tick()
			t.expect(binding.anchor:get().visible).toBe(false)
		end
		part.CFrame = rbx.CFrame.new(0, 0, -10)
		part.live = false
		tick()
		t.expect(binding.anchor:get().visible).toBe(false)
		binding.dispose()
	end)
	t.it("validates options before allocating a frame hook", function()
		local host, scene, part, _, connected = fixture()
		for _, options in
			{
				{ target = part, paddding = 1 },
				{ target = part, padding = -1 },
				{ target = part, padding = 1.01 },
				{ target = part, padding = math.huge },
				{ target = part, minimumRadius = 70 },
			}
		do
			t.expect(pcall(function()
				worldAnchor.new(host, options, { workspace = scene })
			end)).toBe(false)
		end
		t.expect(connected()).toBe(false)
	end)
end)
