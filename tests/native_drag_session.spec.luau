--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local context = require("../src/ui/context")
local sessionOf = require("../src/ui/drag_session")
local engineLib = require("./lib/native_engine")
local C = Facet.Compose

local function fixture()
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local input, gui = engine.new("UserInputService"), engine.new("GuiService")
	local playerGui, screen = engine.new("PlayerGui"), engine.new("ScreenGui")
	screen.Parent = playerGui
	local world = engine.new("Workspace")
	local hits, rayHit, rays = {}, nil, {}
	playerGui.GetGuiObjectsAtPosition = function()
		return hits
	end
	world.CurrentCamera = {
		ScreenPointToRay = function(_, x, y)
			table.insert(rays, { x, y })
			return { Origin = engine.types.Vector3.zero, Direction = engine.types.Vector3.new(0, 0, -1) }
		end,
	}
	world.Raycast = function()
		return rayHit
	end
	local ctx = context(
		C,
		runtime,
		{
			types = engine.types,
			userInputService = input,
			guiService = gui,
			services = {
				Workspace = world,
				Players = {
					LocalPlayer = {
						FindFirstChildWhichIsA = function()
							return playerGui
						end,
					},
				},
			},
		} :: any
	)
	local session = sessionOf(ctx)
	local source, target = engine.new("TextButton"), engine.new("Frame")
	source.Parent, target.Parent = screen, screen
	local owner = C.createRootOwner(function() end, runtime.reactor)
	return {
		engine = engine,
		input = input,
		runtime = runtime,
		source = source,
		target = target,
		session = session,
		screen = screen,
		world = world,
		rays = rays,
		hits = function(value)
			hits = value
		end,
		ray = function(value)
			rayHit = value
		end,
		register = function(node, spec)
			C.withOwner(owner.owner, function()
				session.register(node, spec)
			end)
		end,
		begin = function(spec)
			session.begin(source, spec, "pointer", nil, false)
		end,
		move = function(x, y)
			session.update(engine.types.Vector2.new(x, y))
		end,
		stop = function()
			session.finish(false)
			owner.dispose()
			runtime:dispose()
		end,
	}
end

t.describe("shared drop sessions", function()
	t.it("anchors stacked previews to the picked card rather than the whole collection or stack", function()
		for _, frontSize in { { 100, 80 }, { 700, 40 }, { 40, 700 } } do
			for _, scale in { 0.5, 1, 2 } do
				local w = fixture()
				local V2, D2 = w.engine.types.Vector2, w.engine.types.UDim2
				local row, body, image = w.engine.new("Frame"), w.engine.new("ScrollingFrame"), w.engine.new("Frame")
				body.Parent, row.Parent = w.screen, body
				local unit = w.engine.new("Frame")
				unit.Name, unit.Parent, unit.AbsoluteSize = "LayoutUnit", body, V2.new(scale, scale)
				row.AbsolutePosition, row.AbsoluteSize = V2.new(20, 50), V2.new(frontSize[1], frontSize[2]) * scale
				local pickup = row.AbsolutePosition + V2.new(frontSize[1] * 0.1, frontSize[2] * 0.75) * scale
				w.session.begin(body, { payload = "files" }, "pointer", nil, false, { position = pickup, source = row })
				image.Size = D2.fromOffset(frontSize[1] + 12, frontSize[2] + 12)
				w.session.preview(image, body, D2.fromOffset(frontSize[1], frontSize[2]))
				local ghost = w.screen:FindFirstChild("DragGhost")
				local function topLeft()
					return V2.new(ghost.Position.X.Offset, ghost.Position.Y.Offset)
						- ghost.AnchorPoint * V2.new(ghost.Size.X.Offset, ghost.Size.Y.Offset) * scale
				end
				t.expect((topLeft() - row.AbsolutePosition).Magnitude < 1).toBe(true)
				w.session.update(pickup + V2.new(75, 90))
				t.expect((topLeft() - row.AbsolutePosition - V2.new(75, 90)).Magnitude < 1).toBe(true)
				w.stop()
			end
		end
	end)

	t.it("keeps drag status above custom previews and layered collection cards", function()
		local w = fixture()
		local paint = w.engine.new("Frame")
		paint.ZIndex, paint.Parent = 3000, w.source
		w.session.begin(w.source, { payload = "card" }, "pointer", nil, nil)
		local panel = w.screen:FindFirstChild("DragStatus")
		local label = panel:FindFirstChild("DragStatusText")
		t.expect(panel.ZIndex > paint.ZIndex).toBe(true)
		t.expect(label.ZIndex > panel.ZIndex).toBe(true)
		local body, image = w.engine.new("ScrollingFrame"), w.engine.new("Frame")
		body.Parent = w.screen
		image.Size = w.engine.types.UDim2.fromOffset(120, 160)
		local stack = w.engine.new("Frame")
		stack.ZIndex, stack.Parent = 5000, image
		local icon = w.engine.new("Path2D")
		icon.ZIndex, icon.Parent = 5010, stack
		w.session.preview(image, body)
		t.expect(panel.ZIndex > icon.ZIndex).toBe(true)
		t.expect(label.ZIndex > panel.ZIndex).toBe(true)
		w.session.finish(false)
		t.expect(w.screen:FindFirstChild("DragStatus")).toBeNil()
		w.stop()
	end)

	t.it("keeps an armed preview visible and updates controller hints from owned native input observations", function()
		local w = fixture()
		w.input.PreferredInput = w.engine.types.Enum.PreferredInput.Gamepad
		w.source.AbsoluteSize = w.engine.types.Vector2.new(120, 80)
		w.session.begin(w.source, { payload = "card" }, "armed", nil, nil)
		local ghost = w.screen:FindFirstChild("DragGhost")
		local text = w.screen:FindFirstChild("DragStatusText", true)
		t.expect(ghost ~= nil).toBe(true)
		t.expect(ghost.Interactable).toBe(false)
		t.expect(string.find(text.Text, "A: drop", 1, true) ~= nil).toBe(true)
		t.expect(text.Parent.Visible).toBe(true)
		w.input.PreferredInput = w.engine.types.Enum.PreferredInput.KeyboardAndMouse
		w.engine.heartbeat.fire(1 / 60)
		t.expect(string.find(text.Text, "Enter: drop", 1, true) ~= nil).toBe(true)
		w.session.finish(false)
		t.expect(w.screen:FindFirstChild("DragGhost")).toBeNil()
		t.expect(w.source:GetAttribute("FacetDragHeld")).toBeNil()
		w.stop()
	end)

	t.it("shows the negotiated operation, rejection reason and pending state without accepting another drop", function()
		local w = fixture()
		local operation, legal, completion, count = C.cell("copy"), true, nil, 0
		w.register(w.target, {
			operation = operation,
			accepts = function()
				return legal, "This item is locked"
			end,
			onDrop = function(_, info)
				completion = info.complete
				count += 1
				return "pending"
			end,
		})
		w.hits({ w.target })
		w.begin({ payload = 7, operations = { "copy", "move", "apply" } })
		local label = w.screen:FindFirstChild("DragStatusText", true)
		for _, kind in { "copy", "move", "apply" } do
			operation:set(kind)
			w.move(20, 30)
			t.expect(label.Text).toBe(string.upper(string.sub(kind, 1, 1)) .. string.sub(kind, 2))
			t.expect(label.Parent.Visible).toBe(kind ~= "move")
		end
		legal = false
		w.move(20, 30)
		t.expect(label.Text).toBe("This item is locked")
		t.expect(label.Parent.Visible).toBe(true)
		t.expect(w.target:FindFirstChild("FacetDropOutline").Enabled).toBe(false)
		legal = true
		operation:set("move")
		w.move(20, 30)
		w.session.commit(nil)
		t.expect(label.Text).toBe("Waiting for confirmation…")
		t.expect(label.Parent.Visible).toBe(true)
		t.expect(w.session.state:peek().pending).toBe(true)
		w.session.commit(nil)
		t.expect(count).toBe(1)
		w.session.finish(false, "Cancelled")
		t.expect(completion(true)).toBe(false)
		t.expect(w.screen:FindFirstChild("DragStatus")).toBeNil()
		w.stop()
	end)

	t.it("validates on hover and again at release without mutating on a rejected proposal", function()
		local w = fixture()
		local legal, commits, reason = true, 0, nil
		w.register(w.target, {
			accepts = function()
				return legal, "Locked"
			end,
			onDrop = function()
				commits += 1
			end,
			onReject = function(_, why)
				reason = why
			end,
		})
		w.hits({ w.target })
		w.begin({ payload = { kind = "file" } })
		w.move(20, 30)
		t.expect(w.target:GetAttribute("FacetDropState")).toBe("accepted")
		legal = false
		w.session.commit(nil)
		t.expect(commits).toBe(0)
		t.expect(reason).toBe("Locked")
		t.expect(w.session.state:peek()).toBeNil()
		w.stop()
	end)

	t.it("completes a pending command once and revalidates before the model can change", function()
		local w = fixture()
		local completion, proposals, accepted = nil, 0, nil
		w.register(w.target, {
			onDrop = function(_, info)
				completion = info.complete
				proposals += 1
				return "pending"
			end,
		})
		w.hits({ w.target })
		w.begin({
			payload = 7,
			onEnd = function(ok)
				accepted = ok
			end,
		})
		w.move(1, 2)
		w.session.commit(nil)
		w.session.commit(nil)
		t.expect(proposals).toBe(1)
		t.expect(w.target:GetAttribute("FacetDropState")).toBe("pending")
		t.expect(completion(true)).toBe(true)
		t.expect(completion(true)).toBe(false)
		t.expect(accepted).toBe(true)
		w.stop()
	end)

	t.it("rejects late async replies after source invalidation or target removal", function()
		for _, removeTarget in { false, true } do
			local w = fixture()
			local completion, valid = nil, true
			w.register(w.target, {
				onDrop = function(_, info)
					completion = info.complete
					return "pending"
				end,
			})
			w.hits({ w.target })
			w.begin({
				payload = 7,
				valid = function()
					return valid
				end,
			})
			w.move(1, 2)
			w.session.commit(nil)
			if removeTarget then
				w.target:Destroy()
			else
				valid = false
			end
			w.engine.heartbeat.fire(1 / 60)
			t.expect(completion(true)).toBe(false)
			t.expect(w.session.state:peek()).toBeNil()
			w.stop()
		end
	end)

	t.it("uses native visual order and blocks world drops behind visible UI even if the UI rejects", function()
		local w = fixture()
		local worldDrops, uiDrops = 0, 0
		local part = w.engine.new("Part")
		part.Parent = w.world
		w.register(part, {
			operation = "apply",
			onDrop = function()
				worldDrops += 1
			end,
		})
		w.register(w.target, {
			operation = "apply",
			accepts = function()
				return false, "Wrong kind"
			end,
			onDrop = function()
				uiDrops += 1
			end,
		})
		w.ray({ Instance = part })
		w.hits({ w.target })
		w.begin({ payload = "color", operations = { "apply" } })
		w.move(90, 110)
		t.expect(w.target:FindFirstChild("FacetDropOutline").Enabled).toBe(false)
		w.session.commit(nil)
		t.expect(worldDrops + uiDrops).toBe(0)
		t.expect(#w.rays).toBe(0)
		local blocker = w.engine.new("TextButton")
		blocker.Parent = w.screen
		w.hits({ blocker })
		w.begin({ payload = "color" })
		w.move(90, 110)
		w.session.commit(nil)
		t.expect(#w.rays).toBe(0)
		w.hits({})
		w.begin({ payload = "color", operations = { "apply" } })
		w.move(90, 110)
		w.session.commit(nil)
		t.expect(worldDrops).toBe(1)
		t.expect(w.rays[1]).toEqual({ 90, 110 })
		w.stop()
	end)

	t.it("uses themed transparency when deciding whether layout frames block world drops", function()
		local w = fixture()
		local frame, part = w.engine.new("Frame"), w.engine.new("Part")
		frame.Parent, part.Parent = w.screen, w.world
		frame.BackgroundTransparency = 0
		local transparency, count = 1, 0
		rawset(frame, "GetStyled", function(_, property)
			return if property == "BackgroundTransparency" then transparency else frame[property]
		end)
		w.register(part, {
			operation = "apply",
			onDrop = function()
				count += 1
			end,
		})
		w.hits({ frame })
		w.ray({ Instance = part })
		w.begin({ payload = "color", operations = { "apply" } })
		w.move(10, 20)
		w.session.commit(nil)
		t.expect(count).toBe(1)
		transparency = 0
		w.begin({ payload = "color", operations = { "apply" } })
		w.move(10, 20)
		w.session.commit(nil)
		t.expect(count).toBe(1)
		w.stop()
	end)

	t.it("refreshes world ray hits while the camera moves and never looks through an unregistered occluder", function()
		local w = fixture()
		local first, second, wall = w.engine.new("Part"), w.engine.new("Part"), w.engine.new("Part")
		first.Parent, second.Parent, wall.Parent = w.world, w.world, w.world
		local dropped
		for _, part in { first, second } do
			w.register(part, {
				onDrop = function(_, info)
					dropped = info.target
				end,
			})
		end
		w.ray({ Instance = first })
		w.begin({ payload = 1 })
		w.move(40, 50)
		t.expect(first:GetAttribute("FacetDropState")).toBe("accepted")
		w.ray({ Instance = wall })
		w.engine.heartbeat.fire(1 / 60)
		t.expect(first:GetAttribute("FacetDropState")).toBeNil()
		w.ray({ Instance = second })
		w.engine.heartbeat.fire(1 / 60)
		w.session.commit(nil)
		t.expect(dropped).toBe(second)
		w.stop()
	end)

	t.it(
		"routes explicit payload pass-through to the containing collection but keeps rejected item applications local",
		function()
			local w = fixture()
			local cell = w.engine.new("Frame")
			cell.Parent = w.target
			local applied, inserted = 0, 0
			w.register(w.target, {
				onDrop = function()
					inserted += 1
				end,
			})
			w.register(cell, {
				passThrough = function(payload)
					return payload == "files"
				end,
				accepts = function()
					return false, "Locked item"
				end,
				onDrop = function()
					applied += 1
				end,
			})
			w.hits({ cell, w.target })
			w.begin({ payload = "files" })
			w.move(0, 0)
			w.session.commit(nil)
			t.expect(inserted).toBe(1)
			w.begin({ payload = "color" })
			w.move(0, 0)
			w.session.commit(nil)
			t.expect(inserted).toBe(1)
			t.expect(applied).toBe(0)
			w.stop()
		end
	)
end)
