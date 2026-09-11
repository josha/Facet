--!strict
local t = require("./lib/testkit")
local UI = require("../src/blueprint")
local world = require("./lib/world")
local framing = require("../src/render/image_framing")
local describe, it, expect = t.describe, t.it, t.expect

describe("Image framing", function()
	it("crops around the source focus point and clamps at image edges", function()
		local p = framing.resolve({ width = 1000, height = 500, focusX = 0.8 }, 200, 200)
		expect(p.source.x).toBe(500)
		expect(p.source.w).toBe(500)
		expect(p.destination.w).toBe(200)
		p = framing.resolve({ width = 1000, height = 500, focusX = 0 }, 200, 200)
		expect(p.source.x).toBe(0)
	end)
	it("keeps natural pixels, crops on shrink and exposes space on growth", function()
		local spec = { width = 1000, height = 500, mode = "none", focusX = 0.8 }
		local p = framing.resolve(spec, 200, 200)
		expect(p.source.x).toBe(700)
		expect(p.source.w).toBe(200)
		p = framing.resolve(spec, 1200, 600)
		expect(p.destination.w).toBe(1000)
		expect(p.destination.x).toBe(100)
		expect(p.destination.h).toBe(500)
	end)
	it("contains or stretches deliberately and supports explicit image scale", function()
		local p = framing.resolve({ width = 1000, height = 500, mode = "fit" }, 200, 200)
		expect(p.destination.h).toBe(100)
		expect(p.destination.y).toBe(50)
		p = framing.resolve({ width = 1000, height = 500, mode = "stretch" }, 200, 200)
		expect(p.source.w).toBe(1000)
		expect(p.destination.h).toBe(200)
		p = framing.resolve({ width = 1000, height = 500, mode = "none", scale = 2 }, 200, 200)
		expect(p.source.w).toBe(100)
	end)
	it("rejects malformed framing instead of silently misplacing art", function()
		for _, spec in
			{
				{ width = 0, height = 2 },
				{ width = 2, height = 2, focusX = 2 },
				{ width = 2, height = 2, mode = "tile" },
				{ width = 2, height = 2, scale = 0 },
				{ width = 2, height = 2, focusY = 0 / 0 },
				{ width = 2, height = 2, typo = 1 },
			}
		do
			expect(pcall(function()
				UI.Image({ imageFraming = spec })
			end)).toBe(false)
		end
	end)
	it("reframes a reactive background without solving or adding focus targets", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 300 } })
		local spec = w.core:signal({ width = 1000, height = 500, focusX = 0 })
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.background(
					UI.VStack({
						id = "Content",
						width = UI.fill(),
						height = UI.fill(),
						children = { UI.Button({ id = "Play", label = "Play" }) },
					}),
					UI.Image({ id = "Art", image = "rbxassetid://1", imageFraming = spec })
				),
			},
		}))
		w.settle(3)
		local target = "/S/Content+background/Content/Play"
		w.pres.focus.focusOn(target)
		w.settle(2)
		local before = w.controller.stats()
		spec:set({ width = 1000, height = 500, focusX = 1 })
		w.settle(3)
		expect(w.controller.stats().solves).toBe(before.solves)
		expect(w.controller.stats().creates).toBe(before.creates)
		expect(w.pres.focus.focused:get()).toBe(target)
		expect(w.adapter.node("/S/Content+background/Art").imagePlan.source.x > 0).toBe(true)
		w.env:set("viewportRect", { x = 0, y = 0, w = 200, h = 400 })
		w.settle(3)
		expect(w.adapter.node("/S/Content+background/Art").imagePlan.destination.w).toBe(200)
		spec:set(nil)
		w.settle(2)
		expect(w.adapter.node("/S/Content+background/Art").imagePlan).toBeNil()
		w.pres.dismiss(w.handle)
	end)
	it("keeps every source crop and painted destination inside its bounds", function()
		for _, mode in { "crop", "fill", "fit", "stretch", "none" } do
			for _, size in { { 390, 844 }, { 844, 390 }, { 1000, 800 }, { 1280, 720 }, { 1920, 1080 }, { 0, 0 } } do
				for _, focus in { 0, 0.25, 0.5, 1 } do
					local p = framing.resolve(
						{ width = 420, height = 300, mode = mode, focusX = focus, focusY = 1 - focus },
						size[1],
						size[2]
					)
					expect(p.source.x >= -0.0001 and p.source.x + p.source.w <= 420.0001).toBe(true)
					expect(p.source.y >= -0.0001 and p.source.y + p.source.h <= 300.0001).toBe(true)
					expect(p.destination.x >= -0.0001 and p.destination.x + p.destination.w <= size[1] + 0.0001).toBe(
						true
					)
					expect(p.destination.y >= -0.0001 and p.destination.y + p.destination.h <= size[2] + 0.0001).toBe(
						true
					)
				end
			end
		end
	end)
	it("drives the native framing module without new instances on crop changes and releases its observers", function()
		-- Native API fixture: executes the real adapter module; does not claim GPU evidence.
		local fs, luau = require("@lune/fs"), require("@lune/luau")
		local made, live = {}, 0
		local function instance(class)
			local obj = {
				ClassName = class,
				Image = "",
				ImageColor3 = "white",
				ImageTransparency = 0,
				ResampleMode = "Default",
				ZIndex = 1,
			}
			function obj:IsA(wanted)
				return wanted == self.ClassName
			end
			function obj:FindFirstChildOfClass(wanted)
				for _, child in made do
					if child.Parent == self and not child.dead and child.ClassName == wanted then
						return child
					end
				end
				return nil
			end
			function obj:GetPropertyChangedSignal(_property)
				return {
					Connect = function(_, callback)
						live += 1
						return {
							callback = callback,
							Disconnect = function()
								live -= 1
							end,
						}
					end,
				}
			end
			function obj:Clone()
				local copy = instance(self.ClassName)
				for key, value in self do
					if type(value) ~= "function" and key ~= "Parent" then
						copy[key] = value
					end
				end
				return copy
			end
			function obj:Destroy()
				self.dead = true
			end
			table.insert(made, obj)
			return obj
		end
		local module = luau.load(fs.readFile("src/client/screen_image.luau"), {
			injectGlobals = true,
			environment = {
				require = function()
					return framing
				end,
				Instance = { new = instance },
				Enum = { ScaleType = { Stretch = "Stretch" } },
				Vector2 = {
					new = function(x, y)
						return { X = x, Y = y }
					end,
				},
				UDim2 = {
					fromOffset = function(x, y)
						return { X = x, Y = y }
					end,
				},
			},
		})()
		local host = instance("ImageLabel")
		local styledSignals = {}
		local styledColor = "theme-red"
		local styledReads = 0
		function host:GetStyled(property)
			styledReads += 1
			if property == "ImageColor3" then
				return styledColor
			end
			if property == "ImageTransparency" then
				return 0.3
			end
			return self[property]
		end
		function host:GetStyledPropertyChangedSignal(property)
			return {
				Connect = function(_, callback)
					live += 1
					styledSignals[property] = callback
					return {
						Disconnect = function()
							live -= 1
						end,
					}
				end,
			}
		end
		local handle = {
			instance = host,
			imageContent = "art",
			windowRect = { w = 200, h = 200 },
			imageFraming = {
				width = 1000,
				height = 500,
			},
		}
		module.sync(handle)
		local picture = handle.framedImage.image
		expect(picture.Image).toBe("art")
		expect(picture.ImageColor3).toBe("theme-red")
		expect(picture.ImageTransparency).toBe(0.3)
		expect(type(styledSignals.ImageColor3)).toBe("function")
		styledColor = "theme-blue"
		styledSignals.ImageColor3()
		expect(picture.ImageColor3).toBe("theme-blue")
		expect(host.Image).toBe("")
		expect(picture.ImageRectOffset.X).toBe(250)
		expect(live).toBe(4)
		-- Moving/resizing art updates crop geometry without re-reading native paint.
		local reads = styledReads
		local oldPosition = picture.Position
		handle.windowRect = { x = 30, y = 40, w = 200, h = 200 }
		module.syncRect(handle)
		expect(picture.Position).toBe(oldPosition)
		handle.windowRect = { w = 400, h = 200 }
		module.syncRect(handle)
		expect(picture.ImageRectOffset.X).toBe(0)
		expect(picture.Size.X).toBe(400)
		expect(styledReads).toBe(reads)
		styledColor = "theme-green"
		styledSignals.ImageColor3()
		expect(picture.ImageColor3).toBe("theme-green")
		handle.imageContent = "replacement"
		handle.imageFraming = { width = 1000, height = 500, mode = "none", focusX = 1 }
		module.sync(handle)
		expect(picture.Image).toBe("replacement")
		expect(picture.ImageRectOffset.X).toBe(600)
		for i = 1, 120 do
			handle.imageFraming = { width = 1000, height = 500, focusX = i / 120 }
			module.sync(handle)
		end
		expect(#made).toBe(2)
		expect(handle.framedImage.image).toBe(picture)
		local corner = instance("UICorner")
		corner.Parent, corner.CornerRadius = host, 12
		module.syncModifiers(handle)
		local mirrored = picture:FindFirstChildOfClass("UICorner")
		expect(mirrored.CornerRadius).toBe(12)
		corner.CornerRadius = 24
		module.syncModifiers(handle)
		expect(picture:FindFirstChildOfClass("UICorner")).toBe(mirrored)
		expect(mirrored.CornerRadius).toBe(24)
		corner:Destroy()
		module.syncModifiers(handle)
		expect(picture:FindFirstChildOfClass("UICorner")).toBeNil()
		handle.imageFraming = nil
		module.sync(handle)
		expect(live).toBe(0)
		expect(picture.dead).toBe(true)
		expect(host.Image).toBe("replacement")
		module.clear(handle)
		expect(live).toBe(0)
		local fallback = {
			instance = instance("ImageLabel"),
			imageContent = "plain",
			windowRect = { w = 20, h = 20 },
			imageFraming = { width = 20, height = 20 },
		}
		module.sync(fallback)
		expect(fallback.framedImage.image.ImageColor3).toBe("white")
		module.clear(fallback)
		expect(live).toBe(0)
	end)
end)
