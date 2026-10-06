--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local requireDynamic = require :: (any) -> any

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local gallery = require("../examples/gallery/client/screen")
	local C = Facet.Compose

	local function mount(
		name: string,
		run: (any, any, any, engineLib.Engine) -> (),
		prepare: ((any, engineLib.Engine) -> ())?
	)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local target = engine.new("ScreenGui")
		local ctx = {
			Facet = Facet,
			Compose = C,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			types = engine.types,
			viewport = C.cell({ width = 1280, height = 720 }),
			inputTarget = target,
			worldTarget = engine.new("Folder"),
			runService = { Heartbeat = engine.heartbeat },
		}
		ctx.UI = Facet.controls(runtime, { types = ctx.types, viewport = ctx.viewport })
		if prepare then
			prepare(ctx, engine)
		end
		local built
		local stop, root: any = runtime.mount(function()
			gallery.configure(ctx)
			built = requireDynamic("../examples/gallery/examples/" .. name).build(ctx)
			return built.screen()
		end, target)
		run(built, root, ctx, engine)
		stop()
		Verify.expect(#target:GetChildren()):toBe(0)
		Verify.expect(#ctx.worldTarget:GetChildren()):toBe(0)
		runtime:dispose()
	end

	verifyHarness:suite("showcase demos", function()
		verifyHarness:case("keeps saved cars through page changes and restores their appearance", {
			id = "native_showcase_demos::showcase demos::keeps saved cars through page changes and restores their appearance",
			run = function()
				mount("08_garage", function(built, root, ctx)
					built.model.vehicle:set("rover")
					built.model.wheel:set("rally")
					built.save()
					Verify.expect(built.report().presets):toBe(1)
					built.model.vehicle:set("sprint")
					built.model.savedOpen:set(true)
					ctx.inputTarget:FindFirstChild("LoadPreset1", true).Activated.fire()
					Verify.expect(built.report().vehicle):toBe("rover")
					Verify.expect(built.report().wheels):toBe("rally")
					built.model.savedOpen:set(false)
					Verify.expect(built.report().presets):toBe(1)
					built.reset()
					Verify.expect(built.report().presets):toBe(0)
				end)
			end,
		})
		verifyHarness:case("names cars in an anchored popover and reveals saved cars inline", {
			id = "native_showcase_demos::showcase demos::names cars in an anchored popover and reveals saved cars inline",
			run = function()
				mount("08_garage", function(built, root, ctx)
					root:FindFirstChild("SavePreset", true).Activated.fire()
					Verify.expect(ctx.inputTarget:FindFirstChild("PresetName", true) ~= nil):toBe(true)
					ctx.inputTarget:FindFirstChild("ConfirmSave", true).Activated.fire()
					Verify.expect(built.report().presets):toBe(1)
					built.model.savedOpen:set(true)
					Verify.expect(root:FindFirstChild("LoadPreset1", true) ~= nil):toBe(true)
				end)
			end,
		})

		verifyHarness:case("equips a warm outfit, filters equipment and swaps hotbar slots without duplication", {
			id = "native_showcase_demos::showcase demos::equips a warm outfit, filters equipment and swaps hotbar slots without duplication",
			run = function()
				mount("09_adventurers_pack", function(built)
					Verify.expect(built.report().warmth):toBe(2)
					built.equip("frostcoat")
					built.equip("snowboots")
					Verify.expect(built.report().warmth):toBe(10)
					built.model.query:set("frost")
					Verify.expect(#built.model.filtered:peek()):toBe(1)
					built.model.loadoutOpen:set(true)
					built.model.loadoutOpen:set(false)
					Verify.expect((built.assign("lantern", 1))):toBe(true)
					Verify.expect(built.report().hotbar[1]):toBe("lantern")
					Verify.expect(built.report().hotbar[2]):toBe("sword")
					Verify.expect((built.assign("frostcoat", 1))):toBe(false)

					built.model.path:set({ { id = "item", value = "lantern" } })
					Verify.expect(built.report().warmth):toBe(10)
					built.reset()
					Verify.expect(built.report().warmth):toBe(2)
				end)
			end,
		})
		verifyHarness:case("rejects the wrong batch and pays exactly once for each of three orders", {
			id = "native_showcase_demos::showcase demos::rejects the wrong batch and pays exactly once for each of three orders",
			run = function()
				mount("10_potion_shop", function(built)
					Verify.expect((built.brew())):toBe(false)
					for _, order in
						{ { id = "sun", order = 2 }, { id = "moon", order = 1 }, { id = "moss", order = 3 } }
					do
						for _ = 1, order.order do
							Verify.expect((built.addIngredient(order.id))):toBe(true)
						end
						Verify.expect((built.addIngredient(if order.id == "sun" then "moon" else "sun"))):toBe(false)
						Verify.expect((built.brew())):toBe(true)
						Verify.expect((built.serve())):toBe(false)
						built.advance(3)
						Verify.expect((built.serve())):toBe(true)
						Verify.expect((built.serve())):toBe(false)
					end
					Verify.expect(built.report().coins):toBe(86)
					Verify.expect(built.report().sales):toBe(3)
					Verify.expect((built.brew())):toBe(false)
					built.model.bookOpen:set(true)
					built.model.bookOpen:set(false)
					built.model.ledgerOpen:set(true)
					built.reset()
					Verify.expect(built.report().coins):toBe(0)
				end)
			end,
		})
		verifyHarness:case("requires water and collects three distinct nectar visitors", {
			id = "native_showcase_demos::showcase demos::requires water and collects three distinct nectar visitors",
			run = function()
				mount("11_glade", function(built)
					Verify.expect((built.invite())):toBe(false)
					built.refill()
					for _, nectar in { "bramble", "clover", "meadow" } do
						built.model.nectar:set(nectar)
						Verify.expect((built.invite())):toBe(true)
					end
					Verify.expect(built.report().discovered):toBe(3)
					built.invite()
					Verify.expect(built.report().discovered):toBe(3)
					built.model.guideOpen:set(true)
					built.model.guideOpen:set(false)
					built.model.journalOpen:set(true)
					Verify.expect(built.report().visits):toBe(4)
					built.reset()
					Verify.expect(built.report().discovered):toBe(0)
				end)
			end,
		})
		verifyHarness:case("rejects excess power and tears down its world surface", {
			id = "native_showcase_demos::showcase demos::rejects excess power and tears down its world surface",
			run = function()
				mount("12_outpost", function(built)
					built.model.draft.door:set(3)
					built.model.draft.beacon:set(2)
					built.model.draft.workshop:set(4)
					Verify.expect((built.apply())):toBe(false)
					Verify.expect(built.report().running):toBe(1)
					built.model.draft.door:set(2)
					built.model.draft.beacon:set(1)
					built.model.draft.workshop:set(2)
					Verify.expect((built.apply())):toBe(true)
					Verify.expect(built.report().running):toBe(3)
					built.model.worldMode:set(true)
					Verify.expect(built.report().world):toBe(true)
					built.model.worldMode:set(false)
					built.reset()
					Verify.expect(built.report().running):toBe(1)
				end)
			end,
		})
		verifyHarness:case(
			"fits the world terminal to its native page bounds through rotation and restores the camera",
			{
				id = "native_showcase_demos::showcase demos::fits the world terminal to its native page bounds through rotation and restores the camera",
				run = function()
					local camera: any, previous: any
					mount("12_outpost", function(built, root, ctx, engine)
						local V2, V3 = engine.types.Vector2, engine.types.Vector3
						built.model.worldMode:set(true)
						local bounds = root:FindFirstChild("WorldTerminalBounds", true)
						local console = ctx.worldTarget:FindFirstChild("ShowcaseConsole")
						local surface = ctx.inputTarget:FindFirstChild("OutpostSurface")
						for _, size in { V2.new(390, 844), V2.new(844, 390), V2.new(1280, 720), V2.new(390, 844) } do
							camera.ViewportSize = size
							bounds.AbsolutePosition = V2.new(16, 180)
							bounds.AbsoluteSize = V2.new(size.X - 32, size.Y - 250)
							Verify.expect(surface.CanvasSize.X):toBe(math.min(720, bounds.AbsoluteSize.X))
							Verify.expect(surface.CanvasSize.Y):toBe(math.min(520, bounds.AbsoluteSize.Y))
							for _, x in { -1, 1 } do
								for _, y in { -1, 1 } do
									local point = console.CFrame.Position
										+ V3.new(x * console.Size.X / 2, y * console.Size.Y / 2, -console.Size.Z / 2)
									local localPoint = camera.CFrame:PointToObjectSpace(point)
									local unit = size.Y
										/ (-2 * localPoint.Z * math.tan(math.rad(camera.FieldOfView / 2)))
									local projected =
										V2.new(size.X / 2 + localPoint.X * unit, size.Y / 2 - localPoint.Y * unit)
									local relative = projected - V2.new(0, 58) - bounds.AbsolutePosition
									Verify.expect(relative.X >= -0.001 and relative.X <= bounds.AbsoluteSize.X + 0.001)
										:toBe(true)
									Verify.expect(relative.Y >= -0.001 and relative.Y <= bounds.AbsoluteSize.Y + 0.001)
										:toBe(true)
								end
							end
							Verify.expect((surface:FindFirstChild("TerminalControls", true):IsA("ScrollingFrame")))
								:toBe(true)
						end
						built.model.worldMode:set(false)
						Verify.expect(camera.CFrame):toBe(previous.frame)
						Verify.expect(camera.CameraType):toBe(previous.kind)
						Verify.expect(camera.FieldOfView):toBe(previous.fov)
						Verify.expect(camera.FieldOfViewMode):toBe(previous.mode)
						Verify.expect(camera.Focus):toBe(previous.focus)
						Verify.expect(#ctx.worldTarget:GetChildren()):toBe(1)
						camera:Destroy()
					end, function(ctx, engine)
						ctx.worldTarget = engine.new("Workspace")
						camera = engine.new("Camera")
						camera.Parent = ctx.worldTarget
						ctx.worldTarget.CurrentCamera = camera
						camera.ViewportSize = engine.types.Vector2.new(1280, 720)
						camera.ScreenPointToRay = function(self: any, x: number, y: number)
							local size = self.ViewportSize
							local tangent = math.tan(math.rad(self.FieldOfView / 2))
							local direction = engine.types.Vector3.new(
								(x - size.X / 2) * 2 * tangent / size.Y,
								(size.Y / 2 - y - 58) * 2 * tangent / size.Y,
								-1
							)
							return { Direction = self.CFrame:VectorToWorldSpace(direction.Unit) }
						end
						previous = {
							frame = camera.CFrame,
							kind = camera.CameraType,
							fov = camera.FieldOfView,
							mode = camera.FieldOfViewMode,
							focus = camera.Focus,
						}
					end)
				end,
			}
		)
		verifyHarness:case("opens every arcade game from the retained navigation", {
			id = "native_showcase_demos::showcase demos::opens every arcade game from the retained navigation",
			run = function()
				mount("13_arcade", function(built)
					for _, page in { "word", "crossword", "match3", "outpost", "word" } do
						Verify.expect((built.select(page))):toBe(true)
						Verify.expect(built.report().active):toBe(page)
					end
				end)
			end,
		})
		verifyHarness:case("keeps recipe history and ingredient checks while following related blends", {
			id = "native_showcase_demos::showcase demos::keeps recipe history and ingredient checks while following related blends",
			run = function()
				mount("14_sipworks", function(built)
					built.open("amber-harvest")
					built.model.servings:set(3)
					built.model.gathered["amber-harvest/cinnamon"]:set(true)
					built.push("ingredient", "cinnamon")
					built.push("recipe", "copper-chai")
					Verify.expect(#built.report().path):toBe(3)
					built.back()
					Verify.expect(built.report().path[2].value):toBe("cinnamon")
					built.back()
					Verify.expect(built.report().path[1].value):toBe("amber-harvest")
					Verify.expect(built.report().servings):toBe(3)
					Verify.expect((built.model.gathered["amber-harvest/cinnamon"]:peek())):toBe(true)
					Verify.expect((built.select("saved"))):toBe(true)
					Verify.expect((built.select("all"))):toBe(true)
				end)
			end,
		})
		verifyHarness:case("clears the recipe search and uses stack Back in the wide detail pane", {
			id = "native_showcase_demos::showcase demos::clears the recipe search and uses stack Back in the wide detail pane",
			run = function()
				mount("14_sipworks", function(built, root, ctx, engine)
					local navigation = root:FindFirstChild("RecipeNavigation", true)
					Verify.expect(navigation ~= nil):toBe(true)
					local back = navigation:FindFirstChild("Back", true)
					Verify.expect(back == nil or not back.Visible):toBe(true)
					built.model.query:set("cinnamon")
					root:FindFirstChild("FindRecipe", true):FindFirstChild("Clear", true).Activated.fire()
					Verify.expect((built.model.query:peek())):toBe("")
					built.open("amber-harvest")
					for _ = 1, 90 do
						engine.heartbeat.fire(1 / 60)
					end
					built.push("ingredient", "cinnamon")
					for _ = 1, 90 do
						engine.heartbeat.fire(1 / 60)
					end
					navigation:FindFirstChild("ingredient"):FindFirstChild("Back", true).Activated.fire()
					Verify.expect(#built.report().path):toBe(1)
					for _ = 1, 90 do
						engine.heartbeat.fire(1 / 60)
					end
					navigation:FindFirstChild("recipe"):FindFirstChild("Back", true).Activated.fire()
					Verify.expect(#built.report().path):toBe(0)
				end)
			end,
		})
		verifyHarness:case("puts Cartwheel Close on the action ring and inspects the order inline", {
			id = "native_showcase_demos::showcase demos::puts Cartwheel Close on the action ring and inspects the order inline",
			run = function()
				mount("15_cartwheel", function(built, root, ctx)
					root:FindFirstChild("Actions_101", true):FindFirstChild("Launcher").Activated.fire()
					local close = ctx.inputTarget:FindFirstChild("$navigation", true)
					Verify.expect(close ~= nil):toBe(true)
					close.Activated.fire()
					built.inspect(101)
					Verify.expect(root:FindFirstChild("Order_101", true):FindFirstChild("Potion", true) ~= nil)
						:toBe(true)
				end)
			end,
		})

		verifyHarness:case("runs market orders through confirmation brewing and collection", {
			id = "native_showcase_demos::showcase demos::runs market orders through confirmation brewing and collection",
			run = function()
				mount("15_cartwheel", function(built)
					built.steps.start(101)
					built.steps.advance(2)
					Verify.expect((built.model.orders.statusOf(101))):toBe("brewing")
					built.steps.advance(61)
					Verify.expect((built.model.orders.statusOf(101))):toBe("ready")
					built.steps.collect(101)
					built.steps.advance(2)
					Verify.expect((built.model.orders.statusOf(101))):toBe("done")
				end)
			end,
		})
	end)
end
