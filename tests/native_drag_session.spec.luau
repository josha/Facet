--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
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
		world.CurrentCamera = engine.new("Camera")
		world.CurrentCamera.ScreenPointToRay = function(_, x, y)
			table.insert(rays, { x, y })
			return { Origin = engine.types.Vector3.zero, Direction = engine.types.Vector3.new(0, 0, -1) }
		end
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

	verifyHarness:suite("shared drop sessions", function()
		verifyHarness:case("anchors stacked previews to the picked card rather than the whole collection or stack", {
			id = "native_drag_session::shared drop sessions::anchors stacked previews to the picked card rather than the whole collection or stack",
			run = function()
				for _, frontSize in { { 100, 80 }, { 700, 40 }, { 40, 700 } } do
					for _, scale in { 0.5, 1, 2 } do
						local w = fixture()
						local V2, D2 = w.engine.types.Vector2, w.engine.types.UDim2
						local row, body, image =
							w.engine.new("Frame"), w.engine.new("ScrollingFrame"), w.engine.new("Frame")
						body.Parent, row.Parent = w.screen, body
						local unit = w.engine.new("Frame")
						unit.Name, unit.Parent, unit.AbsoluteSize = "LayoutUnit", body, V2.new(scale, scale)
						row.AbsolutePosition, row.AbsoluteSize =
							V2.new(20, 50), V2.new(frontSize[1], frontSize[2]) * scale
						local pickup = row.AbsolutePosition + V2.new(frontSize[1] * 0.1, frontSize[2] * 0.75) * scale
						w.session.begin(
							body,
							{ payload = "files" },
							"pointer",
							nil,
							false,
							{ position = pickup, source = row }
						)
						image.Size = D2.fromOffset(frontSize[1] + 12, frontSize[2] + 12)
						w.session.preview(image, body, D2.fromOffset(frontSize[1], frontSize[2]))
						local ghost = w.screen:FindFirstChild("DragGhost")
						local function topLeft()
							return V2.new(ghost.Position.X.Offset, ghost.Position.Y.Offset)
								- ghost.AnchorPoint * V2.new(ghost.Size.X.Offset, ghost.Size.Y.Offset) * scale
						end
						Verify.expect((topLeft() - row.AbsolutePosition).Magnitude < 1):toBe(true)
						w.session.update(pickup + V2.new(75, 90))
						Verify.expect((topLeft() - row.AbsolutePosition - V2.new(75, 90)).Magnitude < 1):toBe(true)
						w.stop()
					end
				end
			end,
		})

		verifyHarness:case("keeps drag status above custom previews and layered collection cards", {
			id = "native_drag_session::shared drop sessions::keeps drag status above custom previews and layered collection cards",
			run = function()
				local w = fixture()
				local paint = w.engine.new("Frame")
				paint.ZIndex, paint.Parent = 3000, w.source
				w.session.begin(w.source, { payload = "card" }, "pointer", nil, nil)
				local panel = w.screen:FindFirstChild("DragStatus")
				local label = panel:FindFirstChild("DragStatusText")
				Verify.expect(panel.ZIndex > paint.ZIndex):toBe(true)
				Verify.expect(label.ZIndex > panel.ZIndex):toBe(true)
				local body, image = w.engine.new("ScrollingFrame"), w.engine.new("Frame")
				body.Parent = w.screen
				image.Size = w.engine.types.UDim2.fromOffset(120, 160)
				local stack = w.engine.new("Frame")
				stack.ZIndex, stack.Parent = 5000, image
				local icon = w.engine.new("Path2D")
				icon.ZIndex, icon.Parent = 5010, stack
				w.session.preview(image, body)
				Verify.expect(panel.ZIndex > icon.ZIndex):toBe(true)
				Verify.expect(label.ZIndex > panel.ZIndex):toBe(true)
				w.session.finish(false)
				Verify.expect((w.screen:FindFirstChild("DragStatus"))):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case(
			"keeps an armed preview visible and updates controller hints from owned native input observations",
			{
				id = "native_drag_session::shared drop sessions::keeps an armed preview visible and updates controller hints from owned native input observations",
				run = function()
					local w = fixture()
					w.input.PreferredInput = w.engine.types.Enum.PreferredInput.Gamepad
					w.source.AbsoluteSize = w.engine.types.Vector2.new(120, 80)
					w.session.begin(w.source, { payload = "card" }, "armed", nil, nil)
					local ghost = w.screen:FindFirstChild("DragGhost")
					local text = w.screen:FindFirstChild("DragStatusText", true)
					Verify.expect(ghost ~= nil):toBe(true)
					Verify.expect(ghost.Interactable):toBe(false)
					Verify.expect(string.find(text.Text, "A: drop", 1, true) ~= nil):toBe(true)
					Verify.expect(text.Parent.Visible):toBe(true)
					w.input.PreferredInput = w.engine.types.Enum.PreferredInput.KeyboardAndMouse
					w.engine.heartbeat.fire(1 / 60)
					Verify.expect(string.find(text.Text, "Enter: drop", 1, true) ~= nil):toBe(true)
					w.session.finish(false)
					Verify.expect((w.screen:FindFirstChild("DragGhost"))):toBeNil()
					Verify.expect((w.source:GetAttribute("FacetDragHeld"))):toBeNil()
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"shows the negotiated operation, rejection reason and pending state without accepting another drop",
			{
				id = "native_drag_session::shared drop sessions::shows the negotiated operation, rejection reason and pending state without accepting another drop",
				run = function()
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
						Verify.expect(label.Text):toBe(string.upper(string.sub(kind, 1, 1)) .. string.sub(kind, 2))
						Verify.expect(label.Parent.Visible):toBe(kind ~= "move")
					end
					legal = false
					w.move(20, 30)
					Verify.expect(label.Text):toBe("This item is locked")
					Verify.expect(label.Parent.Visible):toBe(true)
					Verify.expect(w.target:FindFirstChild("FacetDropOutline").Enabled):toBe(false)
					legal = true
					operation:set("move")
					w.move(20, 30)
					w.session.commit(nil)
					Verify.expect(label.Text):toBe("Waiting for confirmation…")
					Verify.expect(label.Parent.Visible):toBe(true)
					Verify.expect(w.session.state:peek().pending):toBe(true)
					w.session.commit(nil)
					Verify.expect(count):toBe(1)
					w.session.finish(false, "Cancelled")
					Verify.expect((completion(true))):toBe(false)
					Verify.expect((w.screen:FindFirstChild("DragStatus"))):toBeNil()
					w.stop()
				end,
			}
		)

		verifyHarness:case("can hide status labels without changing validation or armed input instructions", {
			id = "native_drag_session::shared drop sessions::can hide status labels without changing validation or armed input instructions",
			run = function()
				local w = fixture()
				local legal, completion = true, nil
				w.register(w.target, {
					operation = "apply",
					label = "Canvas",
					accepts = function()
						return legal, "Wrong kind"
					end,
					onDrop = function(_, info)
						completion = info.complete
						return "pending"
					end,
				})
				w.hits({ w.target })
				w.begin({ payload = "card", statusLabels = false })
				local label = w.screen:FindFirstChild("DragStatusText", true)
				w.move(20, 30)
				Verify.expect(label.Parent.Visible):toBe(false)
				Verify.expect(w.session.state:peek().accepted):toBe(true)
				Verify.expect(w.target:FindFirstChild("FacetDropOutline").Enabled):toBe(true)
				legal = false
				w.move(20, 30)
				Verify.expect(label.Parent.Visible):toBe(false)
				Verify.expect(w.session.state:peek().accepted):toBe(false)
				Verify.expect(w.target:FindFirstChild("FacetDropOutline").Enabled):toBe(false)
				legal = true
				w.move(20, 30)
				w.session.commit(nil)
				Verify.expect(label.Parent.Visible):toBe(false)
				Verify.expect(w.session.state:peek().pending):toBe(true)
				Verify.expect((completion(true))):toBe(true)
				w.input.PreferredInput = w.engine.types.Enum.PreferredInput.Gamepad
				w.session.begin(w.source, { payload = "card", statusLabels = false }, "armed", nil, false)
				label = w.screen:FindFirstChild("DragStatusText", true)
				Verify.expect(label.Parent.Visible):toBe(true)
				Verify.expect(label.Text):toBe("A: drop · B: cancel")
				w.session.finish(false)
				w.stop()
			end,
		})

		verifyHarness:case("validates on hover and again at release without mutating on a rejected proposal", {
			id = "native_drag_session::shared drop sessions::validates on hover and again at release without mutating on a rejected proposal",
			run = function()
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
				Verify.expect((w.target:GetAttribute("FacetDropState"))):toBe("accepted")
				legal = false
				w.session.commit(nil)
				Verify.expect(commits):toBe(0)
				Verify.expect(reason):toBe("Locked")
				Verify.expect((w.session.state:peek())):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case("completes a pending command once and revalidates before the model can change", {
			id = "native_drag_session::shared drop sessions::completes a pending command once and revalidates before the model can change",
			run = function()
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
				Verify.expect(proposals):toBe(1)
				Verify.expect((w.target:GetAttribute("FacetDropState"))):toBe("pending")
				Verify.expect((completion(true))):toBe(true)
				Verify.expect((completion(true))):toBe(false)
				Verify.expect(accepted):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("rejects late async replies after source invalidation or target removal", {
			id = "native_drag_session::shared drop sessions::rejects late async replies after source invalidation or target removal",
			run = function()
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
					Verify.expect((completion(true))):toBe(false)
					Verify.expect((w.session.state:peek())):toBeNil()
					w.stop()
				end
			end,
		})

		verifyHarness:case("uses native visual order and blocks world drops behind visible UI even if the UI rejects", {
			id = "native_drag_session::shared drop sessions::uses native visual order and blocks world drops behind visible UI even if the UI rejects",
			run = function()
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
				Verify.expect(w.target:FindFirstChild("FacetDropOutline").Enabled):toBe(false)
				w.session.commit(nil)
				Verify.expect(worldDrops + uiDrops):toBe(0)
				Verify.expect(#w.rays):toBe(0)
				local blocker = w.engine.new("TextButton")
				blocker.Parent = w.screen
				w.hits({ blocker })
				w.begin({ payload = "color" })
				w.move(90, 110)
				w.session.commit(nil)
				Verify.expect(#w.rays):toBe(0)
				w.hits({})
				w.begin({ payload = "color", operations = { "apply" } })
				w.move(90, 110)
				w.session.commit(nil)
				Verify.expect(worldDrops):toBe(1)
				Verify.expect(w.rays[1]):toEqual({ 90, 110 })
				w.stop()
			end,
		})

		verifyHarness:case("uses themed transparency when deciding whether layout frames block world drops", {
			id = "native_drag_session::shared drop sessions::uses themed transparency when deciding whether layout frames block world drops",
			run = function()
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
				Verify.expect(count):toBe(1)
				transparency = 0
				w.begin({ payload = "color", operations = { "apply" } })
				w.move(10, 20)
				w.session.commit(nil)
				Verify.expect(count):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case(
			"refreshes world ray hits while the camera moves and never looks through an unregistered occluder",
			{
				id = "native_drag_session::shared drop sessions::refreshes world ray hits while the camera moves and never looks through an unregistered occluder",
				run = function()
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
					Verify.expect((first:GetAttribute("FacetDropState"))):toBe("accepted")
					w.ray({ Instance = wall })
					w.engine.heartbeat.fire(1 / 60)
					Verify.expect((first:GetAttribute("FacetDropState"))):toBeNil()
					w.ray({ Instance = second })
					w.engine.heartbeat.fire(1 / 60)
					w.session.commit(nil)
					Verify.expect(dropped):toBe(second)
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"routes explicit payload pass-through to the containing collection but keeps rejected item applications local",
			{
				id = "native_drag_session::shared drop sessions::routes explicit payload pass-through to the containing collection but keeps rejected item applications local",
				run = function()
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
					Verify.expect(inserted):toBe(1)
					w.begin({ payload = "color" })
					w.move(0, 0)
					w.session.commit(nil)
					Verify.expect(inserted):toBe(1)
					Verify.expect(applied):toBe(0)
					w.stop()
				end,
			}
		)
	end)
end
