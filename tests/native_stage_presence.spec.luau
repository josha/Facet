--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")

	verifyHarness:suite("collection media preparation", function()
		verifyHarness:case("keeps a surface placeholder until media is ready and fades through the theme token", {
			id = "native_stage_presence::collection media preparation::keeps a surface placeholder until media is ready and fades through the theme token",
			run = function()
				local asset = Compose.cell("rbxassetid://1")
				local w = overlay.new(function(UI, Host, engine)
					return Host.Frame "Cell" {
						BackgroundColor3 = engine.types.Color3.new(0.2, 0.3, 0.4),
						Attributes = { FacetCollectionRow = true },
						UI.Image "Picture" { image = asset, BackgroundColor3 = engine.types.Color3.new(0.7, 0.2, 0.1) },
						UI.Stage "Scene" {
							content = function(runtime, world)
								local part = runtime.constructors.Part "Complete" {}
								part.Parent = world
							end,
						},
					}
				end, { motionLevel = "normal" })
				local image, stage = w.find("Picture"), w.find("Scene")
				image.IsLoaded = false
				Verify.expect(image.ImageTransparency):toBe(1)
				Verify.expect(image.BackgroundTransparency):toBe(0)
				Verify.expect(image.BackgroundColor3):toBe(w.engine.types.Color3.new(0.2, 0.3, 0.4))
				Verify.expect(stage.ImageTransparency):toBe(1)
				Verify.expect(stage.BackgroundTransparency):toBe(0)
				w.size(image, 120, 80)
				w.size(stage, 120, 80)
				w.advance(0.05, 3)
				Verify.expect(image.ImageTransparency):toBe(1)
				image.IsLoaded = true
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
				image.IsLoaded = false
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
		local log = { builds = 0, writes = 0, lives = {} :: { any } }
		local w = overlay.new(function(UI: FacetControls, Host)
			local stages = {}
			for index = 1, o.count or 1 do
				table.insert(
					stages,
					UI.Stage({
						Name = "Stage" .. index,
						lazy = o.lazy,
						content = function(
							runtime: Compose.Runtime,
							world: WorldModel,
							live: Compose.Readable<boolean>
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
							local part = Host.Part({
								Name = "Spinner",
								Transparency = function(use: Use)
									return use(clock.progress)
								end,
							})
							part:GetPropertyChangedSignal("Transparency"):Connect(function()
								log.writes += 1
							end)
							part.Parent = world
							return nil
						end,
					})
				)
			end
			return Host.ScrollingFrame({ Name = "Feed", table.unpack((stages :: unknown) :: { unknown }) })
		end)
		local V = w.Vector2
		local feed = w.find("Feed")
		feed.AbsolutePosition = V.new(0, 0)
		feed.AbsoluteWindowSize = V.new(400, 300)
		for index = 1, o.count or 1 do
			local stage = w.find("Stage" .. index)
			stage.AbsoluteSize = V.new(200, 100)
			stage.AbsolutePosition = V.new(0, (index - 1) * 110)
		end
		w.log = log
		return w
	end

	verifyHarness:suite("native Stage presence", function()
		verifyHarness:case("is not live while less than half of it shows in the scroll window", {
			id = "native_stage_presence::native Stage presence::is not live while less than half of it shows in the scroll window",
			run = function()
				local w = scene()
				local stage = w.find("Stage1")
				stage.AbsolutePosition = w.Vector2.new(0, 260)
				Verify.expect((w.log.lives[1]:peek())):toBe(false)
				stage.AbsolutePosition = w.Vector2.new(0, 220)
				Verify.expect((w.log.lives[1]:peek())):toBe(true)
				stage.AbsolutePosition = w.Vector2.new(0, 400)
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
				w.find("Stage1").AbsolutePosition = w.Vector2.new(0, 500)
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
				w.find("Stage1").AbsolutePosition = w.Vector2.new(0, 360)
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
				w.find("Stage1").AbsolutePosition = w.Vector2.new(0, 500)
				w.advance(0.3, 18)
				Verify.expect(w.log.builds):toBe(0)
				w.find("Stage1").AbsolutePosition = w.Vector2.new(0, 100)
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
					return Host.ScrollingFrame({
						Name = "Feed",
						Compose.show(gate, function()
							local stages = {}
							for index = 1, 3 do
								table.insert(
									stages,
									UI.Stage({
										Name = "Stage" .. index,
										lazy = true,
										content = function(): (() -> ())?
											builds += 1
											return nil
										end,
									})
								)
							end
							return Host.Frame({ Name = "Cards", table.unpack((stages :: unknown) :: { unknown }) })
						end),
					})
				end)
				local V = w.Vector2
				local feed = w.find("Feed")
				feed.AbsolutePosition = V.new(0, 0)
				feed.AbsoluteWindowSize = V.new(400, 300)
				for index = 1, 3 do
					local stage = w.find("Stage" .. index)
					stage.AbsoluteSize = V.new(200, 100)
					stage.AbsolutePosition = V.new(0, (index - 1) * 110)
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
