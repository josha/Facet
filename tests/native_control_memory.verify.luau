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
	harness:case("collection rows reveal painted rows without a binding unless arrival motion is declared", {
		id = "native_control_memory::collection-row-reveal",
		run = function()
			type Row = { id: string }
			for _, arrival in { "absent", "rise" } do
				local function mount(count: number)
					local state = nativeApp()
					local Compose, V2, environment = state.Compose, state.types.Vector2, state.engine.environment
					local initial: { Row } = {}
					for index = 1, count do
						table.insert(initial, { id = tostring(index) })
					end
					local rows = Compose.cell(initial)
					Compose.inspect.start({ maxOwners = math.huge, maxNodes = math.huge })
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
							reducedMotion = false,
							arrival = if arrival == "rise" then "rise" else nil,
							selection = Compose.cell({}),
							render = function(current: Facet.ReadOnlyValue<Row>): GuiObject
								return state.Host.TextLabel "Caption" { Text = current:peek().id }
							end,
						}
						return root
					end, state.target)
					local snapshot = Compose.inspect.snapshot()
					local watches = 0
					for _, owner in snapshot.mounts do
						watches += owner.totalWatches
					end
					Compose.inspect.stop()
					local items = assert(root:FindFirstChild("Items", true))
					local function content(name: string): CanvasGroup
						local found = assert(assert(items:FindFirstChild(name)):FindFirstChild("Content"))
						assert(found:IsA("CanvasGroup"))
						return found
					end
					local function paint(name: string, frames: number)
						for _, node in assert(items:FindFirstChild(name)):GetDescendants() do
							if node:IsA("GuiObject") then
								environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", V2.new(100, 44))
								if node:IsA("TextLabel") then
									environment.poke(VerifyRoblox.assertInstance(node), "TextBounds", V2.new(60, 20))
								end
							end
						end
						for _ = 1, frames do
							state.frame()
						end
					end
					return {
						state = state,
						rows = rows,
						stop = stop,
						watches = watches,
						content = content,
						paint = paint,
					}
				end
				local one, two = mount(1), mount(2)
				Verify.expect(two.watches - one.watches):toBe(if arrival == "rise" then 3 else 2)
				two.stop()
				two.state.dispose()
				local first = one.content("1")
				Verify.expect(first.GroupTransparency):toBe(1)
				Verify.expect(first:GetAttribute("FacetCollectionReady")):toBe(false)
				one.paint("1", 4)
				Verify.expect(first.GroupTransparency):toBe(0)
				Verify.expect(first:GetAttribute("FacetCollectionReady")):toBe(true)
				one.rows:set({ { id = "1" }, { id = "2" } })
				local second = one.content("2")
				Verify.expect(second.GroupTransparency):toBe(1)
				Verify.expect(second:GetAttribute("FacetCollectionReady")):toBe(false)
				one.paint("2", 2)
				Verify.expect(second:GetAttribute("FacetCollectionReady")):toBe(true)
				if arrival == "rise" then
					Verify.expect(second.GroupTransparency > 0 and second.GroupTransparency < 1):toBe(true)
					one.paint("2", 120)
				end
				Verify.expect(second.GroupTransparency):toBe(0)
				Verify.expect(first.GroupTransparency):toBe(0)
				one.rows:set({ { id = "1" }, { id = "2" }, { id = "3" } })
				local third = one.content("3")
				local holder = assert(third.Parent)
				local environment, V2 = one.state.engine.environment, one.state.types.Vector2
				for _, node in holder:GetDescendants() do
					if node:IsA("GuiObject") then
						environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", V2.new(100, 44))
					end
				end
				for _ = 1, 60 do
					one.state.frame()
				end
				Verify.expect(third:GetAttribute("FacetCollectionReady")):toBe(false)
				for _ = 1, 80 do
					one.state.frame()
				end
				Verify.expect(third:GetAttribute("FacetCollectionReady")):toBe(true)
				one.stop()
				one.state.dispose()
				Verify.expect(one.state.engine.census().connections):toBe(0)
			end
		end,
	})
	harness:case("collection rows share selection painting and connect only the row hit events they use", {
		id = "native_control_memory::collection-row-selection",
		run = function()
			type Row = { id: string }
			local activation = require("../src/ui/activation")
			local function mount(count: number)
				local state = nativeApp()
				local Compose = state.Compose
				local initial: { Row } = {}
				for index = 1, count do
					table.insert(initial, { id = tostring(index) })
				end
				local rows = Compose.cell(initial)
				local selection = Compose.cell({} :: { [string]: boolean })
				local focus: Facet.FocusControls<string> = {}
				local activated: { string } = {}
				Compose.inspect.start({ maxOwners = math.huge, maxNodes = math.huge })
				local before = state.engine.census().connections
				local root: GuiObject
				local stop = state.runtime.mount(function()
					root = state.UI.VirtualGrid {
						from = rows,
						key = "id",
						mode = "all",
						columns = 2,
						itemSize = 44,
						measure = false,
						selection = selection,
						focus = focus,
						onActivate = function(_row: Row, key: string)
							table.insert(activated, key)
						end,
						render = function(current: Facet.ReadOnlyValue<Row>): GuiObject
							return state.Host.TextLabel "Caption" { Text = current:peek().id }
						end,
					}
					return root
				end, state.target)
				local snapshot = Compose.inspect.snapshot()
				local watches, cleanups = 0, 0
				for _, owner in snapshot.mounts do
					watches += owner.totalWatches
					cleanups += owner.totalCleanups
				end
				Compose.inspect.stop()
				return {
					state = state,
					rows = rows,
					selection = selection,
					focus = focus,
					activated = activated,
					stop = stop,
					items = assert(root:FindFirstChild("Items", true)),
					watches = watches,
					cleanups = cleanups,
					connections = state.engine.census().connections - before,
				}
			end
			local one, two = mount(1), mount(2)
			Verify.expect(two.watches - one.watches):toBe(2)
			Verify.expect(two.cleanups - one.cleanups):toBe(3)
			Verify.expect(two.connections - one.connections):toBe(4)
			one.stop()
			one.state.dispose()
			local items, environment = two.items, two.state.engine.environment
			local function hit(name: string): TextButton
				local found = assert(assert(items:FindFirstChild(name)):FindFirstChild("RowHit", true))
				assert(found:IsA("TextButton"))
				return found
			end
			local function content(name: string): Instance
				return assert(assert(items:FindFirstChild(name)):FindFirstChild("Content"))
			end
			local function shown(name: string): (boolean, boolean)
				return hit(name):GetAttribute("FacetSelected") == true, content(name):HasTag("facet-selected")
			end
			Verify.expect(environment.connectionsOfInstance(VerifyRoblox.assertInstance(hit("1")))):toBe(2)
			Verify.expect(hit("1"):GetAttribute("FacetSelected")):toBe(false)
			Verify.expect(hit("1"):GetAttribute("FacetOnlySelected")):toBe(nil)
			local mouse = { UserInputType = two.state.types.Enum.UserInputType.MouseButton1 }
			environment.fire(VerifyRoblox.assertInstance(hit("2")), "Activated", mouse, 1)
			Verify.expect(two.selection:peek()):toEqual({ ["2"] = true })
			Verify.expect({ shown("2") }):toEqual({ true, true })
			Verify.expect({ shown("1") }):toEqual({ false, false })
			environment.fire(VerifyRoblox.assertInstance(hit("1")), "Activated", mouse, 2)
			Verify.expect(two.activated):toEqual({ "1" })
			Verify.expect(activation.trigger(hit("2"), nil, nil)):toBe(true)
			Verify.expect(two.selection:peek()):toEqual({ ["2"] = true })
			Verify.expect(two.activated):toEqual({ "1", "2" })
			Verify.expect({ shown("1") }):toEqual({ false, false })
			environment.fire(VerifyRoblox.assertInstance(hit("1")), "SelectionGained")
			Verify.expect(assert(two.focus.current):peek()):toBe("1")
			local gone = hit("2")
			two.rows:set({ { id = "1" } })
			two.selection:set({ ["2"] = true, ["1"] = true })
			Verify.expect({ shown("1") }):toEqual({ true, true })
			two.stop()
			Verify.expect(activation.trigger(gone, nil, nil)):toBe(false)
			two.state.dispose()
			Verify.expect(two.state.engine.census().connections):toBe(0)
		end,
	})
end
