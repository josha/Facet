--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	type Use = Facet.Use
	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")
	local Types = require("../src/ui/types")

	verifyHarness:suite("collection media preparation", function()
		verifyHarness:case("keeps a surface placeholder until media is ready and fades through the theme token", {
			id = "native_stage_presence::collection media preparation::keeps a surface placeholder until media is ready and fades through the theme token",
			run = function()
				local asset = Compose.cell("rbxassetid://1")
				local attributes: Types.Attributes = { FacetCollectionRow = true }
				local w = overlay.new(function(UI, Host, engine)
					return Host.Frame "Cell" {
						BackgroundColor3 = engine.types.Color3.new(0.2, 0.3, 0.4),
						Attributes = attributes,
						UI.Image "Picture" {
							image = asset,
							BackgroundColor3 = engine.types.Color3.new(0.7, 0.2, 0.1),
						},
						UI.Stage "Scene" {
							content = function(_runtime: Facet.Runtime, world: WorldModel): (() -> ())?
								local part = Host.Part "Complete" {}
								assert(typeof(part) == "Instance")
								part.Parent = world
								return nil
							end,
						},
					}
				end, { motionLevel = "normal" })
				local image, stage = w.find("Picture"), w.find("Scene")
				w.engine.environment.poke(image, "IsLoaded", false)
				Verify.expect(image.ImageTransparency):toBe(1)
				Verify.expect(image.BackgroundTransparency):toBe(0)
				Verify.expect(image.BackgroundColor3):toBe(w.engine.types.Color3.new(0.2, 0.3, 0.4))
				Verify.expect(stage.ImageTransparency):toBe(1)
				Verify.expect(stage.BackgroundTransparency):toBe(0)
				w.size(image, 120, 80)
				w.size(stage, 120, 80)
				w.advance(0.05, 3)
				Verify.expect(image.ImageTransparency):toBe(1)
				w.engine.environment.poke(image, "IsLoaded", true)
				local intermediate = false
				local last = image.ImageTransparency
				for _ = 1, 30 do
					w.advance(1 / 60)
					Verify.expect(image.ImageTransparency <= last):toBe(true)
					if image.ImageTransparency > 0 then
						Verify.expect(image.BackgroundColor3):toBe(w.engine.types.Color3.new(0.2, 0.3, 0.4))
					end
					intermediate = intermediate or (image.ImageTransparency > 0 and image.ImageTransparency < 1)
					last = image.ImageTransparency
				end
				Verify.expect(intermediate):toBe(true)
				Verify.expect(last):toBe(0)
				Verify.expect(image.BackgroundColor3):toBe(w.engine.types.Color3.new(0.7, 0.2, 0.1))
				Verify.expect(stage.ImageTransparency):toBe(0)
				asset:set("rbxassetid://2")
				Verify.expect(image.ImageTransparency):toBe(1)
				Verify.expect(image.BackgroundTransparency):toBe(0)
				w.engine.environment.poke(image, "IsLoaded", false)
				asset:set("")
				w.advance(0.4, 24)
				Verify.expect(image:GetAttribute("FacetMediaReady")):toBe(true)
				Verify.expect(image.ImageTransparency):toBe(0)
				w.stop()
			end,
		})
	end)

	local function scene(options: { lazy: boolean?, count: number? }?): any
		local o: { lazy: boolean?, count: number? } = options or {}
		local log: { builds: number, writes: number, lives: { Facet.ReadOnlyValue<boolean> } } =
			{ builds = 0, writes = 0, lives = {} }
		local w = overlay.new(function(UI: FacetControls, Host)
			local stages: { Facet.Child } = {}
			for index = 1, o.count or 1 do
				table.insert(
					stages,
					UI.Stage {
						Name = "Stage" .. index,
						lazy = o.lazy,
						content = function(
							runtime: Compose.Runtime,
							world: WorldModel,
							live: Compose.ReadOnlyValue<boolean>
						): (() -> ())?
							log.builds += 1
							table.insert(log.lives, live)
							local clock = runtime.timeline({ duration = 4, repeats = math.huge, autoplay = false })
							Compose.watch(function(use: Use)
								if use(live) then
									clock:play()
								else
									clock:pause()
								end
							end)
							local part = Host.Part {
								Name = "Spinner",
								Transparency = function(use: Use)
									return use(clock.progress)
								end,
							}
							part:GetPropertyChangedSignal("Transparency"):Connect(function()
								log.writes += 1
							end)
							part.Parent = world
							return nil
						end,
					}
				)
			end
			return Host.ScrollingFrame { Name = "Feed", table.unpack(stages) }
		end)
		local V = w.Vector2
		local feed = w.find("Feed")
		w.engine.environment.poke(feed, "AbsolutePosition", V.new(0, 0))
		w.engine.environment.poke(feed, "AbsoluteWindowSize", V.new(400, 300))
		for index = 1, o.count or 1 do
			local stage = w.find("Stage" .. index)
			w.engine.environment.poke(stage, "AbsoluteSize", V.new(200, 100))
			w.engine.environment.poke(stage, "AbsolutePosition", V.new(0, (index - 1) * 110))
		end
		w.log = log
		return w
	end

	verifyHarness:suite("native Stage presence", function()
		verifyHarness:case("releases the camera while an ancestor is hidden and restores the retained scene", {
			id = "native_stage_presence::native Stage presence::releases the camera while an ancestor is hidden and restores the retained scene",
			run = function()
				local w = scene({ lazy = true })
				local stage, feed = w.find("Stage1"), w.find("Feed")
				local camera = stage.CurrentCamera
				feed.Visible = false
				w.advance(0.3, 18)
				Verify.expect(stage.CurrentCamera):toBe(nil)
				Verify.expect(stage:GetAttribute("FacetLive")):toBe(false)
				Verify.expect(w.log.builds):toBe(0)
				feed.Visible = true
				w.advance(0.3, 18)
				Verify.expect(stage.CurrentCamera):toBe(camera)
				Verify.expect(w.log.builds):toBe(1)
				local part = w.find("Spinner")
				local screen = feed.Parent
				local hidden = w.engine.new("Frame")
				hidden.Visible = false
				hidden.Parent = screen
				stage.Parent = hidden
				Verify.expect(stage.CurrentCamera):toBe(nil)
				Verify.expect(stage:GetAttribute("FacetLive")):toBe(false)
				stage.Parent = feed
				Verify.expect(stage.CurrentCamera):toBe(camera)
				hidden.Visible = true
				hidden.Visible = false
				Verify.expect(stage:GetAttribute("FacetLive")):toBe(true)
				for _ = 1, 2 do
					screen.Enabled = false
					local writes = w.log.writes
					w.advance(0.3, 18)
					Verify.expect(stage.CurrentCamera):toBe(nil)
					Verify.expect(stage:GetAttribute("FacetLive")):toBe(false)
					Verify.expect(w.log.writes):toBe(writes)
					screen.Enabled = true
					w.advance(0.3, 18)
					Verify.expect(stage.CurrentCamera):toBe(camera)
					Verify.expect(stage:GetAttribute("FacetLive")):toBe(true)
					Verify.expect(w.find("Spinner")):toBe(part)
					Verify.expect(w.log.builds):toBe(1)
				end
				w.stop()
			end,
		})
		verifyHarness:case("lights the subject from the camera side unless the author sets the light", {
			id = "native_stage_presence::native Stage presence::lights the subject from the camera side unless the author sets the light",
			run = function()
				local w = overlay.new(function(UI, Host, engine)
					local T = engine.types
					return Host.Frame "Holder" {
						UI.Stage "Front" { camera = T.CFrame.lookAt(T.Vector3.new(11, 6, -13), T.Vector3.zero) },
						UI.Stage "Authored" { LightDirection = T.Vector3.new(1, 0, 0) },
					}
				end)
				local front, authored = w.find("Front"), w.find("Authored")
				local look = front.CurrentCamera.CFrame.LookVector
				Verify.expect(front.LightDirection:Dot(look) > 0.7):toBe(true)
				Verify.expect(front.LightDirection.Y < 0):toBe(true)
				Verify.expect(authored.LightDirection.X):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case("restores the authored external camera without taking ownership of it", {
			id = "native_stage_presence::native Stage presence::restores the authored external camera without taking ownership of it",
			run = function()
				local w = overlay.new(function(UI, Host, engine)
					local camera = engine.new("Camera")
					camera.Name = "ExternalCamera"
					return Host.Frame "Holder" { camera, UI.Stage "ExternalStage" { camera = camera } }
				end)
				local stage, camera = w.find("ExternalStage"), w.find("ExternalCamera")
				local holder = w.find("Holder")
				holder.Visible = false
				Verify.expect(stage.CurrentCamera):toBe(nil)
				Verify.expect(camera.Parent):toBe(holder)
				holder.Visible = true
				Verify.expect(stage.CurrentCamera):toBe(camera)
				Verify.expect(camera.Parent):toBe(holder)
				w.stop()
			end,
		})
		verifyHarness:case("preserves native camera overrides and reads their latest value on return", {
			id = "native_stage_presence::native Stage presence::preserves native camera overrides and reads their latest value on return",
			run = function()
				local selected = Compose.cell(nil :: Camera?)
				local w = overlay.new(function(UI, Host, engine)
					local camera = engine.new("Camera")
					camera.Name = "NativeCamera"
					selected:set(camera)
					local properties: Types.FrameNativeProps = {
						camera,
						UI.Stage "BoundCamera" { CurrentCamera = selected },
						UI.Stage "StaticCamera" { CurrentCamera = Compose.static(camera) },
					}
					return Host.Frame "Holder"(properties)
				end)
				local holder, camera = w.find("Holder"), w.find("NativeCamera")
				local bound, static = w.find("BoundCamera"), w.find("StaticCamera")
				Verify.expect(bound.CurrentCamera):toBe(camera)
				Verify.expect(static.CurrentCamera):toBe(camera)
				holder.Visible = false
				selected:set(nil)
				selected:set(camera)
				Verify.expect(bound.CurrentCamera):toBe(nil)
				selected:set(nil)
				holder.Visible = true
				Verify.expect(bound.CurrentCamera):toBe(nil)
				Verify.expect(static.CurrentCamera):toBe(camera)
				selected:set(camera)
				Verify.expect(bound.CurrentCamera):toBe(camera)
				w.stop()
			end,
		})

		verifyHarness:case("cancels retired lazy scenes before the replacement uses the next frame budget", {
			id = "native_stage_presence::native Stage presence::cancels retired lazy scenes before the replacement uses the next frame budget",
			run = function()
				local original = Compose.cell(true)
				local retired, replacement = 0, 0
				local w = overlay.new(function(UI, Host)
					return Host.Frame {
						Compose.show(original, function()
							local stages: { Facet.Child } = {}
							for index = 1, 8 do
								table.insert(
									stages,
									UI.Stage {
										Name = "Retired" .. index,
										lazy = true,
										content = function()
											retired += 1
											return nil
										end,
									}
								)
							end
							return Host.Frame { table.unpack(stages) }
						end),
						Compose.show(function(use: Use)
							return not use(original)
						end, function()
							return UI.Stage "Replacement" {
								lazy = true,
								content = function()
									replacement += 1
									return nil
								end,
							}
						end),
					}
				end)
				original:set(false)
				Verify.expect(retired):toBe(0)
				Verify.expect(replacement):toBe(0)
				w.advance(1 / 60)
				Verify.expect(retired):toBe(0)
				Verify.expect(replacement):toBe(1)
				Verify.expect(w.find("Replacement"):GetAttribute("FacetBuilt")):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("is not live while less than half of it shows in the scroll window", {
			id = "native_stage_presence::native Stage presence::is not live while less than half of it shows in the scroll window",
			run = function()
				local w = scene()
				local stage = w.find("Stage1")
				w.engine.environment.poke(stage, "AbsolutePosition", w.Vector2.new(0, 260))
				Verify.expect((w.log.lives[1]:peek())):toBe(false)
				w.engine.environment.poke(stage, "AbsolutePosition", w.Vector2.new(0, 220))
				Verify.expect((w.log.lives[1]:peek())):toBe(true)
				w.engine.environment.poke(stage, "AbsolutePosition", w.Vector2.new(0, 400))
				Verify.expect((w.log.lives[1]:peek())):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("pauses scene animation while scrolling and off screen, so no frame writes the scene", {
			id = "native_stage_presence::native Stage presence::pauses scene animation while scrolling and off screen, so no frame writes the scene",
			run = function()
				local w = scene()
				w.advance(0.5, 30)
				local playing = w.log.writes
				Verify.expect(playing > 20):toBe(true)
				local feed = w.find("Feed")
				local before = w.log.writes
				for frame = 1, 30 do
					feed.CanvasPosition = w.Vector2.new(0, frame * 4)
					w.advance(1 / 60)
				end
				Verify.expect(w.log.writes - before <= 1):toBe(true)
				w.advance(0.3, 18)
				local rested = w.log.writes
				Verify.expect(rested > before + 1):toBe(true)
				w.engine.environment.poke(w.find("Stage1"), "AbsolutePosition", w.Vector2.new(0, 500))
				local hidden = w.log.writes
				w.advance(0.5, 30)
				Verify.expect(w.log.writes - hidden <= 1):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("builds lazy content ahead of the scroll window so a card never scrolls in blank", {
			id = "native_stage_presence::native Stage presence::builds lazy content ahead of the scroll window so a card never scrolls in blank",
			run = function()
				local w = scene({ lazy = true })
				w.engine.environment.poke(w.find("Stage1"), "AbsolutePosition", w.Vector2.new(0, 360))
				w.advance(1 / 60)
				Verify.expect(w.log.builds):toBe(1)
				Verify.expect((w.find("Stage1"):GetAttribute("FacetLive"))):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("does not build lazy content that stays out of the scroll window", {
			id = "native_stage_presence::native Stage presence::does not build lazy content that stays out of the scroll window",
			run = function()
				local w = scene({ lazy = true })
				w.engine.environment.poke(w.find("Stage1"), "AbsolutePosition", w.Vector2.new(0, 500))
				w.advance(0.3, 18)
				Verify.expect(w.log.builds):toBe(0)
				w.engine.environment.poke(w.find("Stage1"), "AbsolutePosition", w.Vector2.new(0, 100))
				w.advance(1 / 60)
				Verify.expect(w.log.builds):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case("drops a queued lazy build when its stage is removed before the frame runs", {
			id = "native_stage_presence::native Stage presence::drops a queued lazy build when its stage is removed before the frame runs",
			run = function()
				local gate = Compose.cell(true)
				local builds = 0
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.ScrollingFrame {
						Name = "Feed",
						Compose.show(gate, function()
							local stages: { Facet.Child } = {}
							for index = 1, 3 do
								table.insert(
									stages,
									UI.Stage {
										Name = "Stage" .. index,
										lazy = true,
										content = function(): (() -> ())?
											builds += 1
											return nil
										end,
									}
								)
							end
							return Host.Frame { Name = "Cards", table.unpack(stages) }
						end),
					}
				end)
				local V = w.Vector2
				local feed = w.find("Feed")
				w.engine.environment.poke(feed, "AbsolutePosition", V.new(0, 0))
				w.engine.environment.poke(feed, "AbsoluteWindowSize", V.new(400, 300))
				for index = 1, 3 do
					local stage = w.find("Stage" .. index)
					w.engine.environment.poke(stage, "AbsoluteSize", V.new(200, 100))
					w.engine.environment.poke(stage, "AbsolutePosition", V.new(0, (index - 1) * 110))
				end
				gate:set(false)
				local ok, problem = pcall(function()
					w.advance(1 / 60, 4)
				end)
				Verify.expect(problem):toBe(nil)
				Verify.expect(ok):toBe(true)
				Verify.expect(builds):toBe(0)
				w.stop()
			end,
		})
	end)

	return nil
end
