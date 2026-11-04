--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local worlds = require("./lib/content_world")

return function(harness: Verify.Harness)
	local Compose = Facet.Compose

	harness:case("keeps native children and input gates while a readable group fades under two themes", {
		id = "native_group::keeps native children and input gates while a readable group fades under two themes",
		run = function(test: Verify.Context)
			local transparency, enabled, visible = Compose.cell(0.4), Compose.cell(true), Compose.cell(true)
			local theme = Compose.cell(Facet.themes.neutralPackage())
			local calls = 0
			local world = worlds.new(function(UI)
				return UI.Group "Strip" {
					groupTransparency = transparency,
					width = 400,
					height = 80,
					Visible = visible,
					UI.HStack "Controls" {
						UI.Image "Icon" { image = "rbxassetid://1" },
						UI.Text "Label" { text = "Audio" },
						UI.Button "Apply" {
							label = "Apply",
							enabled = enabled,
							onActivate = function()
								calls += 1
							end,
						},
					},
				}
			end, { theme = theme, motionLevel = "none" })
			test:defer(world.stop)
			local group, button = world.find("Strip"), world.find("Apply")
			Verify.expect(group.ClassName):toBe("CanvasGroup")
			Verify.expect(group.GroupTransparency):toBe(0.4)
			Verify.expect(world.find("Icon"):IsDescendantOf(group)):toBe(true)
			Verify.expect(world.find("Label"):IsDescendantOf(group)):toBe(true)
			local parent, size = button.Parent, button.Size
			local definition: Facet.ThemeDefinition = {
				identity = { id = "alternate", displayName = "Alternate" },
				style = { defaultTheme = "Light" },
			}
			local alternate = assert((Facet.themes.define(definition)))
			for _, package in { Facet.themes.neutralPackage(), alternate } do
				theme:set(package)
				for _, alpha in { 0, 0.6, 1 } do
					transparency:set(alpha)
					Verify.expect(world.find("Strip")):toBe(group)
					Verify.expect(group.GroupTransparency):toBe(alpha)
					Verify.expect(button.Parent):toBe(parent)
					Verify.expect(button.Size):toBe(size)
					local before = calls
					button.Activated:Fire()
					Verify.expect(calls):toBe(before + 1)
					enabled:set(false)
					button.Activated:Fire()
					Verify.expect(calls):toBe(before + 1)
					enabled:set(true)
					visible:set(false)
					button.Activated:Fire()
					Verify.expect(calls):toBe(before + 1)
					visible:set(true)
				end
			end
		end,
	})

	harness:case("adds no instances connections or idle frame writes over a plain container", {
		id = "native_group::adds no instances connections or idle frame writes over a plain container",
		run = function()
			local function measure(grouped: boolean): { instances: number, connections: number, frameWrites: number }
				local world = worlds.new(function(UI, Host, engine)
					local children = {
						UI.Image { image = "rbxassetid://1" },
						UI.Text { text = "Audio" },
						UI.Button { label = "Apply" },
					}
					return if grouped
						then UI.Group {
							groupTransparency = Compose.cell(0.4),
							width = 400,
							height = 80,
							table.unpack(children),
						}
						else Host.Frame { Size = engine.types.UDim2.fromOffset(400, 80), table.unpack(children) }
				end, { motionLevel = "none" })
				local counts = world.engine.census()
				local writes = 0
				local stop = world.engine.onWrite(function()
					writes += 1
				end)
				for _ = 1, 120 do
					world.engine.heartbeat:Fire(1 / 60)
				end
				stop:Disconnect()
				world.stop()
				Verify.expect(world.engine.census().connections):toBe(0)
				return { instances = counts.live, connections = counts.connections, frameWrites = writes }
			end
			local plain, group = measure(false), measure(true)
			Verify.expect(group):toEqual(plain)
			Verify.expect(group.frameWrites):toBe(0)
			print(
				`Group costs: plain={plain.instances} instances/{plain.connections} connections/{plain.frameWrites} writes in 120 frames; group={group.instances}/{group.connections}/{group.frameWrites}`
			)
		end,
	})
end
