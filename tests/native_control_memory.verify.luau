--!strict

local Verify = require("../tools/vendor/verify/src/core")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
local nativeApp = require("../bench/native_app")
local context = require("../src/ui/context")
local Facet = require("../src")
local InputTypes = require("../src/ui/input_types")

return function(harness: Verify.Harness)
	harness:case("hidden guides build the latest entries on first use and retain them through hiding", {
		id = "native_control_memory::guide-lifetime",
		run = function()
			local state = nativeApp()
			local Compose = state.Compose
			local input: UserInputService = state.engine.new("UserInputService")
			state.runtime:watch(function()
				state.runtime.adopt(input)
			end)
			local UI = state.Facet.controls(state.runtime, {
				types = state.types,
				services = { UserInputService = input },
			})
			local label = Compose.cell("Buy")
			local visible = Compose.cell(true)
			local entries: { InputTypes.ButtonGuideEntry } = { { keys = { { "E" } }, label = label } }
			local guide: Frame
			local stop = state.runtime.mount(function()
				guide = UI.ButtonGuide { entries = entries, Visible = visible }
				return guide
			end, state.target)
			Verify.expect(guide:FindFirstChild("Entries")):toBe(nil)
			label:set("Sell")
			state.engine.environment.poke(
				VerifyRoblox.assertInstance(input),
				"PreferredInput",
				state.types.Enum.PreferredInput.Gamepad
			)
			local entries = assert(guide:FindFirstChild("Entries"))
			local caption = assert(entries:FindFirstChild("Label", true))
			assert(caption:IsA("TextLabel"))
			Verify.expect(caption.Text):toBe("Sell")
			Verify.expect(guide.Visible):toBe(true)
			visible:set(false)
			Verify.expect(guide.Visible):toBe(false)
			Verify.expect(guide:FindFirstChild("Entries")):toBe(entries)
			visible:set(true)
			Verify.expect(guide.Visible):toBe(true)
			state.engine.environment.poke(
				VerifyRoblox.assertInstance(input),
				"PreferredInput",
				state.types.Enum.PreferredInput.Touch
			)
			Verify.expect(guide.Visible):toBe(false)
			stop()
			state.dispose()
			Verify.expect(state.engine.census().connections):toBe(0)
		end,
	})
	harness:case("field messages start empty and preserve their first shown row for later validation", {
		id = "native_control_memory::field-message-lifetime",
		run = function()
			local state = nativeApp()
			local hint, failure = state.Compose.cell(""), state.Compose.cell("")
			local field: Instance
			local stop = state.runtime.mount(function()
				field = state.UI.TextInput {
					value = state.Compose.cell("Ada"),
					label = "Driver",
					hint = hint,
					errorText = failure,
				}
				return field
			end, state.target)
			Verify.expect(field:FindFirstChild("Message")):toBe(nil)
			hint:set("Shown to players")
			local message = assert(field:FindFirstChild("Message"))
			local caption = assert(message:FindFirstChild("Validation"))
			assert(caption:IsA("TextLabel"))
			Verify.expect(caption.Text):toBe("Shown to players")
			failure:set("Choose another driver")
			Verify.expect(caption.Text):toBe("Choose another driver")
			Verify.expect(caption:HasTag("facet-validation")):toBe(true)
			failure:set("")
			hint:set("")
			Verify.expect(field:FindFirstChild("Message")):toBe(message)
			assert(message:IsA("Frame"))
			Verify.expect(message.Visible):toBe(false)
			stop()
			state.dispose()
			Verify.expect(state.engine.census().connections):toBe(0)
		end,
	})
	harness:case("media skins first appear when required and keep following the theme after a sibling leaves", {
		id = "native_control_memory::media-skin-lifetime",
		run = function()
			local state = nativeApp()
			local plain = state.Facet.themes.neutralPackage()
			local theme = state.Compose.cell(plain)
			local UI = state.Facet.controls(state.runtime, { types = state.types, theme = theme })
			local first: GuiObject
			local second: GuiObject
			local stopFirst = state.runtime.mount(function()
				first = UI.Badge { label = "First", status = "success" }
				return first
			end, state.target)
			local stopSecond = state.runtime.mount(function()
				second = UI.Badge { label = "Second" }
				return second
			end, state.target)
			Verify.expect(first:FindFirstChild("Skin", true)):toBe(nil)
			Verify.expect(second:FindFirstChild("Skin", true)):toBe(nil)
			stopFirst()
			local art = state.Facet.themes.neutralPackage()
			art.assets = { fill = { contentId = "rbxassetid://1" } }
			art.chrome = { badge = { kind = "nineSlice", asset = "fill" } }
			theme:set(art)
			local skin = assert(second:FindFirstChild("Skin", true))
			Verify.expect(second:HasTag("facet-skinned")):toBe(true)
			theme:set(plain)
			Verify.expect(second:FindFirstChild("Skin", true)):toBe(skin)
			Verify.expect(second:HasTag("facet-skinned")):toBe(false)
			stopSecond()
			state.dispose()
			Verify.expect(state.engine.census().connections):toBe(0)
		end,
	})
	harness:case("environment readers share runtime observations and follow input changes outside a mount", {
		id = "native_control_memory::environment-lifetime",
		run = function()
			local state = nativeApp()
			local input: UserInputService = state.engine.new("UserInputService")
			state.runtime:watch(function()
				state.runtime.adopt(input)
			end)
			local ctx =
				context(state.Compose, state.runtime, { types = state.types, services = { UserInputService = input } })
			local effective = ctx.effectiveInput()
			Verify.expect(ctx.effectiveInput()):toBe(effective)
			Verify.expect(ctx.pointerOnly()):toBe(ctx.pointerOnly())
			Verify.expect(ctx.hitFloor()):toBe(ctx.hitFloor())
			Verify.expect(ctx.touchFloor()):toBe(ctx.touchFloor())
			Verify.expect(ctx.tenFoot()):toBe(ctx.tenFoot())
			state.engine.environment.poke(
				VerifyRoblox.assertInstance(input),
				"PreferredInput",
				state.types.Enum.PreferredInput.Touch
			)
			Verify.expect(effective()):toBe("Touch")
			state.dispose()
			Verify.expect(state.engine.census().connections):toBe(0)
		end,
	})
	harness:case(
		"collection rows park a replaced row until its replacement paints and hold row hooks only while needed",
		{
			id = "native_control_memory::collection-row-hooks",
			run = function()
				type Row = { id: string, title: string }
				for _, ending in { "paint", "unparent", "destroy" } do
					local state = nativeApp()
					local Host, V2, environment = state.Host, state.types.Vector2, state.engine.environment
					local rows = state.Compose.cell({ { id = "A", title = "Alpha" } :: Row })
					local root: GuiObject
					local stop = state.runtime.mount(function()
						root = state.UI.VirtualGrid {
							from = rows,
							key = "id",
							mode = "all",
							columns = 2,
							itemSize = 44,
							measure = false,
							recycle = false,
							render = function(current: Facet.ReadOnlyValue<Row>): GuiObject
								return Host.TextLabel "Caption" { Text = current:peek().title }
							end,
						}
						return root
					end, state.target)
					local items = assert(root:FindFirstChild("Items", true))
					local function connections(node: Instance): number
						return environment.connectionsOfInstance(VerifyRoblox.assertInstance(node))
					end
					local function content(row: Instance): CanvasGroup
						local found = assert(row:FindFirstChild("Content"))
						assert(found:IsA("CanvasGroup"))
						return found
					end
					local function paint(name: string)
						for _, node in assert(items:FindFirstChild(name)):GetDescendants() do
							if node:IsA("GuiObject") then
								environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", V2.new(100, 44))
								if node:IsA("TextLabel") then
									environment.poke(VerifyRoblox.assertInstance(node), "TextBounds", V2.new(60, 20))
								end
							end
						end
						for _ = 1, 4 do
							state.frame()
						end
					end
					local old = assert(items:FindFirstChild("A"))
					Verify.expect(connections(old)):toBe(1)
					Verify.expect(connections(content(old))):toBe(1)
					paint("A")
					Verify.expect(content(old).GroupTransparency):toBe(0)
					Verify.expect(connections(old)):toBe(1)
					Verify.expect(connections(content(old))):toBe(0)
					environment.poke(VerifyRoblox.assertInstance(content(old)), "AbsoluteSize", V2.new(0, 0))
					Verify.expect(content(old).GroupTransparency):toBe(0)
					rows:set({ { id = "B", title = "Beta" } :: Row })
					local fresh = assert(items:FindFirstChild("B"))
					Verify.expect(old.Parent):toBe(items)
					Verify.expect(connections(old)):toBe(2)
					Verify.expect(content(fresh).GroupTransparency):toBe(1)
					if ending == "unparent" then
						old.Parent = nil
						Verify.expect(old.Parent):toBe(items)
					elseif ending == "destroy" then
						old:Destroy()
						Verify.expect(old.Parent):toBe(nil)
					end
					paint("B")
					Verify.expect(content(fresh).GroupTransparency):toBe(0)
					Verify.expect(old.Parent):toBe(nil)
					Verify.expect(connections(old)):toBe(0)
					stop()
					state.dispose()
					Verify.expect(state.engine.census().connections):toBe(0)
				end
			end,
		}
	)
end
