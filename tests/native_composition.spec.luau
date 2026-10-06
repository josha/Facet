--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	local function make(options: { [string]: any }?): (any, any, any, any)
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local T = engine.types
		gui.GetGuiInset = function()
			return T.Vector2.new(0, 58), T.Vector2.zero
		end
		gui.TopbarInset = T.Rect.new(0, 0, 0, 0)
		local config: { [string]: any } = { types = T, guiService = gui, services = { GuiService = gui } }
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		return engine, runtime, Facet.controls(runtime, config :: any), gui
	end

	local function sized(engine: any, node: any, width: number, height: number)
		node.AbsoluteSize = engine.types.Vector2.new(width, height)
	end

	local function form(Host: any, name: string): any
		return Host.Frame { Name = name }
	end

	local NAMES = { "Rounds", "Tasks", "Health", "Clock", "Strip", "Rail", "Readout", "Actions" }

	local function hud(UI: any, Host: any, forms: any, topbar: any?)
		local function region(name: string, spec: { [any]: any }): any
			spec.form = forms[name]
			return UI.Region(name)(spec)
		end
		return UI.Composition "Hud" {
			gap = 8,
			padding = 0,
			topbar = topbar,
			region("Rounds", { zone = "topLeft", rank = 1, form(Host, "RoundsFull") }) :: unknown,
			region("Tasks", {
				zone = "left",
				rank = 7,
				mayDrop = true,
				form(Host, "TasksFull"),
				form(Host, "TasksChip"),
			}),
			region("Health", { zone = "bottomLeft", rank = 5, form(Host, "HealthFull"), form(Host, "HealthChip") }),
			region("Clock", { zone = "top", rank = 2, form(Host, "ClockFull"), form(Host, "ClockChip") }),
			region("Strip", { zone = "topbar", rank = 6, form(Host, "Objective") }),
			region("Rail", { zone = "topRight", rank = 4, form(Host, "RailFull"), form(Host, "RailChip") }),
			region("Readout", { zone = "topRight", rank = 9, mayDrop = true, form(Host, "ReadoutText") }),
			region("Actions", { zone = "bottomRight", rank = 3, form(Host, "ActionsFull") }),
		}
	end

	local SIZES: { [string]: { number } } = {
		RoundsFull = { 120, 44 },
		TasksFull = { 240, 130 },
		TasksChip = { 90, 44 },
		HealthFull = { 150, 40 },
		HealthChip = { 60, 44 },
		ClockFull = { 170, 60 },
		ClockChip = { 80, 44 },
		Objective = { 130, 32 },
		RailFull = { 130, 132 },
		RailChip = { 80, 44 },
		ReadoutText = { 110, 16 },
		ActionsFull = { 44, 148 },
	}

	local function mount(options: { [string]: any }?, topbar: any?): (any, any, any, any, () -> ())
		local engine, runtime, UI, gui = make(options)
		local cells = {}
		for _, name in NAMES do
			cells[name] = Compose.cell(1)
		end
		local forms = {
			cells = cells,
			peek = function()
				local chosen = {}
				for name, cell in cells do
					chosen[name] = cell:peek()
				end
				return chosen
			end,
		}
		local layer = engine.new("ScreenGui")
		layer.Parent = engine.new("Folder")
		local root: any
		runtime.mount(function()
			root = hud(UI, runtime.constructors, cells, topbar)
			return root
		end, layer)
		for name, size in SIZES do
			sized(engine, root:FindFirstChild(name, true), size[1], size[2])
		end
		for _, node in root:GetDescendants() do
			if node.Name == "Reveal" then
				sized(engine, node, 28, 20)
			end
		end
		return root, engine, forms, gui, function()
			runtime:dispose()
		end
	end

	verifyHarness:suite("Composition", function()
		verifyHarness:case("anchors each region's zone to its screen edge or corner, in declaration order", {
			id = "native_composition::Composition::anchors each region's zone to its screen edge or corner, in declaration order",
			run = function()
				local root: any, engine, _, _, stop = mount()
				local T = engine.types
				local zones = root:FindFirstChild("Zones")
				for name, anchor in
					{
						TopLeft = { 0, 0 },
						Left = { 0, 0.5 },
						BottomLeft = { 0, 1 },
						Top = { 0.5, 0 },
						TopRight = { 1, 0 },
						BottomRight = { 1, 1 },
					} :: { [string]: { number } }
				do
					local zone: any = zones:FindFirstChild(name)
					Verify.expect(zone.AnchorPoint):toBe(T.Vector2.new(anchor[1], anchor[2]))
					Verify.expect(zone.Position):toBe(T.UDim2.fromScale(anchor[1], anchor[2]))
					Verify.expect(zone.AutomaticSize):toBe(T.Enum.AutomaticSize.XY)
				end
				local right = zones:FindFirstChild("TopRight")
				Verify.expect(right:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment)
					:toBe(T.Enum.HorizontalAlignment.Right)
				Verify.expect(right:FindFirstChild("Rail").LayoutOrder < right:FindFirstChild("Readout").LayoutOrder)
					:toBe(true)
				Verify.expect(zones:FindFirstChild("Top"):FindFirstChild("Topbar"):FindFirstChild("Strip") ~= nil)
					:toBe(true)
				stop()
			end,
		})

		verifyHarness:case("shows every region in full while each lane fits its third of the screen", {
			id = "native_composition::Composition::shows every region in full while each lane fits its third of the screen",
			run = function()
				local root: any, engine, forms, _, stop = mount()
				sized(engine, root:FindFirstChild("Zones"), 844, 330)
				Verify.expect((forms.peek())):toEqual({
					Rounds = 1,
					Tasks = 1,
					Health = 1,
					Clock = 1,
					Strip = 1,
					Rail = 1,
					Readout = 1,
					Actions = 1,
				})
				Verify.expect(root:FindFirstChild("TasksFull", true).Parent.Visible):toBe(true)
				Verify.expect(root:FindFirstChild("TasksChip", true).Parent.Visible):toBe(false)
				Verify.expect((root:FindFirstChild("Tasks", true):GetAttribute("FacetForm"))):toBe(1)
				stop()
			end,
		})

		verifyHarness:case("steps the least important region of the lane that runs out down first, then drops it", {
			id = "native_composition::Composition::steps the least important region of the lane that runs out down first, then drops it",
			run = function()
				local root: any, engine, forms, _, stop = mount()
				local box = root:FindFirstChild("Zones")
				sized(engine, box, 844, 300)
				Verify.expect(forms.peek().Readout):toBe(0)
				Verify.expect(forms.peek().Rail):toBe(1)
				Verify.expect(forms.peek().Tasks):toBe(1)
				sized(engine, box, 844, 230)
				Verify.expect(forms.peek().Rail):toBe(2)
				Verify.expect(forms.peek().Actions):toBe(1)
				Verify.expect(forms.peek().Tasks):toBe(2)
				Verify.expect(forms.peek().Health):toBe(1)
				Verify.expect(root:FindFirstChild("Readout", true).Visible):toBe(false)
				stop()
			end,
		})

		verifyHarness:case("keeps each lane to a third of the width, stepping only a region wider than its lane", {
			id = "native_composition::Composition::keeps each lane to a third of the width, stepping only a region wider than its lane",
			run = function()
				local root: any, engine, forms, _, stop = mount()
				sized(engine, root:FindFirstChild("Zones"), 390, 780)
				local chosen = forms.peek()
				Verify.expect(chosen.Tasks):toBe(2)
				Verify.expect(chosen.Clock):toBe(2)
				Verify.expect(chosen.Rail):toBe(2)
				Verify.expect(chosen.Rounds):toBe(1)
				Verify.expect(chosen.Health):toBe(2)
				Verify.expect(chosen.Readout):toBe(1)
				stop()
			end,
		})

		verifyHarness:case("returns to the same forms as a fresh mount after rotations", {
			id = "native_composition::Composition::returns to the same forms as a fresh mount after rotations",
			run = function()
				local root: any, engine, forms, _, stop = mount()
				local box = root:FindFirstChild("Zones")
				local expected = {}
				for _, size in { { 844, 330 }, { 390, 780 }, { 844, 250 } } do
					local fresh, freshEngine, freshForms, _, stopFresh = mount()
					sized(freshEngine, fresh:FindFirstChild("Zones"), size[1], size[2])
					expected[size] = freshForms.peek()
					stopFresh()
				end
				for _ = 1, 2 do
					for size, want in expected do
						sized(engine, box, size[1], size[2])
						Verify.expect((forms.peek())):toEqual(want)
					end
				end
				stop()
			end,
		})

		verifyHarness:case(
			"rides the free strip of the top bar in a TopbarSafeInsets ScreenGui, or leads the top zone",
			{
				id = "native_composition::Composition::rides the free strip of the top bar in a TopbarSafeInsets ScreenGui, or leads the top zone",
				run = function()
					local ride = Compose.cell(true)
					local root: any, engine, forms, gui, stop = mount(nil, ride)
					local T = engine.types
					local topbar = root:FindFirstChild("Topbar", true)
					Verify.expect(topbar.Parent.Name):toBe("Top")
					gui.TopbarInset = T.Rect.new(164, 0, 844, 58)
					local strip = topbar.Parent
					Verify.expect(strip.ClassName):toBe("ScreenGui")
					Verify.expect(strip.ScreenInsets):toBe(T.Enum.ScreenInsets.TopbarSafeInsets)
					Verify.expect(strip.Parent):toBe(root:FindFirstAncestorWhichIsA("ScreenGui").Parent)
					Verify.expect(topbar.Size):toBe(T.UDim2.fromScale(1, 1))
					sized(engine, strip, 680, 58)
					sized(engine, root:FindFirstChild("Zones"), 844, 330)
					Verify.expect(forms.peek().Strip):toBe(1)
					ride:set(false)
					Verify.expect(topbar.Parent.Name):toBe("Top")
					Verify.expect(topbar.LayoutOrder):toBe(0)
					Verify.expect(strip.Parent):toBe(nil)
					stop()
					Verify.expect(strip.Parent):toBe(nil)
				end,
			}
		)

		verifyHarness:case("pops an arriving form unless motion is reduced, and holds its measurement while it pops", {
			id = "native_composition::Composition::pops an arriving form unless motion is reduced, and holds its measurement while it pops",
			run = function()
				for _, reduced in { false, true } do
					local root: any, engine, forms, _, stop =
						mount({ motionLevel = if reduced then "none" else "normal" })
					local box = root:FindFirstChild("Zones")
					sized(engine, box, 844, 330)
					local rail = root:FindFirstChild("Rail", true)
					local pop = rail:FindFirstChildWhichIsA("UIScale")
					Verify.expect(pop.Scale):toBe(1)
					sized(engine, box, 844, 250)
					Verify.expect(forms.peek().Rail):toBe(2)
					Verify.expect(pop.Scale < 1):toBe(not reduced)
					sized(engine, root:FindFirstChild("RailFull", true), 110, 40)
					Verify.expect(forms.peek().Rail):toBe(if reduced then 1 else 2)
					stop()
				end
			end,
		})

		verifyHarness:case("discloses a stepped-down region's richest content in context, anchored at the region", {
			id = "native_composition::Composition::discloses a stepped-down region's richest content in context, anchored at the region",
			run = function()
				local overlay = require("./lib/overlay_world")
				local form = Compose.cell(1)
				local w: any = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Composition "Hud" {
						gap = 8,
						padding = 0,
						topbar = false,
						UI.Region "Rounds" {
							zone = "topLeft" :: "topLeft",
							rank = 1,
							Host.Frame { Name = "RoundsFull" },
						} :: unknown,
						UI.Region "Tasks" {
							zone = "left" :: "left",
							rank = 2,
							form = form,
							expand = function(): Instance
								return Host.TextLabel "TasksRich" { Text = "Win a round" }
							end,
							Host.Frame { Name = "TasksFull" } :: unknown,
							Host.Frame { Name = "TasksChip" },
						},
					}
				end)
				for name, size in
					{ RoundsFull = { 120, 44 }, TasksFull = { 240, 130 }, TasksChip = { 90, 30 } } :: { [string]: { number } }
				do
					w.size(w.find(name), size[1], size[2])
				end
				local zones = w.find("Zones")
				w.size(zones, 800, 400)
				local cover = w.find("Tasks"):FindFirstChild("Expand")
				Verify.expect((form:peek())):toBe(1)
				Verify.expect(cover.Visible):toBe(false)
				w.size(zones, 800, 150)
				Verify.expect((form:peek())):toBe(2)
				Verify.expect(cover.Visible):toBe(true)
				Verify.expect(cover.ZIndex < 0):toBe(true)
				Verify.expect(cover.Size.Y.Offset):toBe(14)
				cover.Activated.fire()
				Verify.expect(w.find("TasksRich") ~= nil):toBe(true)
				Verify.expect((w.find("ExpandModal"):GetAttribute("FacetRoute"))):toBe("popover")
				w.size(zones, 800, 400)
				Verify.expect((form:peek())):toBe(1)
				Verify.expect((w.find("TasksRich"))):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case(
			"leaves a Show hidden disc in place of a dropped region that can reveal, unless reveal is off",
			{
				id = "native_composition::Composition::leaves a Show hidden disc in place of a dropped region that can reveal, unless reveal is off",
				run = function()
					local overlay = require("./lib/overlay_world")
					for _, reveal in { true, false } do
						local form = Compose.cell(1)
						local w: any = overlay.new(function(UI: FacetControls, Host: RobloxHost)
							return UI.Composition "Hud" {
								gap = 8,
								padding = 0,
								topbar = false,
								UI.Region "Rounds" {
									zone = "topLeft" :: "topLeft",
									rank = 1,
									Host.Frame { Name = "RoundsFull" },
								} :: unknown,
								UI.Region "Feed" {
									zone = "left" :: "left",
									rank = 2,
									mayDrop = true,
									reveal = if reveal then nil else false,
									form = form,
									expand = function(): Instance
										return Host.TextLabel "FeedRich" { Text = "Ravi eliminated Mo" }
									end,
									Host.Frame { Name = "FeedFull" },
								},
							}
						end)
						w.size(w.find("RoundsFull"), 120, 44)
						w.size(w.find("FeedFull"), 240, 130)
						local disc = w.find("Reveal")
						Verify.expect(disc ~= nil):toBe(reveal)
						if disc then
							w.size(disc, 28, 20)
						end
						local zones = w.find("Zones")
						w.size(zones, 800, 400)
						Verify.expect((form:peek())):toBe(1)
						w.size(zones, 800, 200)
						Verify.expect((form:peek())):toBe(if reveal then 2 else 0)
						if disc then
							Verify.expect(disc.Parent.Visible):toBe(true)
							Verify.expect(w.find("Feed"):FindFirstChild("Expand").Visible):toBe(true)
							w.find("Feed"):FindFirstChild("Expand").Activated.fire()
							Verify.expect(w.find("FeedRich") ~= nil):toBe(true)
							w.size(zones, 800, 400)
							Verify.expect((w.find("FeedRich"))):toBeNil()
						end
						w.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"reveals a dropped region's own content in place when it has no expand, and puts the same node back",
			{
				id = "native_composition::Composition::reveals a dropped region's own content in place when it has no expand, and puts the same node back",
				run = function()
					local overlay = require("./lib/overlay_world")
					local form = Compose.cell(1)
					local w: any = overlay.new(function(UI: FacetControls, Host: RobloxHost)
						return UI.Composition "Hud" {
							gap = 8,
							padding = 0,
							topbar = false,
							UI.Region "Rounds" {
								zone = "topLeft" :: "topLeft",
								rank = 1,
								Host.Frame { Name = "RoundsFull" },
							} :: unknown,
							UI.Region "Feed" {
								zone = "left" :: "left",
								rank = 2,
								mayDrop = true,
								form = form,
								Host.Frame { Name = "FeedFull" },
							},
						}
					end)
					local feed = w.find("FeedFull")
					local home = feed.Parent
					w.size(w.find("RoundsFull"), 120, 44)
					w.size(feed, 240, 130)
					w.size(w.find("Reveal"), 28, 20)
					local zones = w.find("Zones")
					w.size(zones, 800, 400)
					w.size(zones, 800, 200)
					Verify.expect((form:peek())):toBe(2)
					local target = w.find("Feed"):FindFirstChild("Expand")
					Verify.expect(target.Visible):toBe(true)
					target.Activated.fire()
					Verify.expect(w.find("ExpandModal") ~= nil):toBe(true)
					Verify.expect(feed.Parent.Name):toBe("Hosted")
					Verify.expect((feed:IsDescendantOf(w.find("ExpandModal")))):toBe(true)
					w.size(feed, 200, 100)
					w.size(zones, 800, 400)
					Verify.expect((form:peek())):toBe(1)
					Verify.expect(feed.Parent):toBe(home)
					Verify.expect(feed.Parent ~= nil and home.Visible):toBe(true)
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"gathers a zone's dropped regions behind one hit-floor badge beside the zone, outside its flow",
			{
				id = "native_composition::Composition::gathers a zone's dropped regions behind one hit-floor badge beside the zone, outside its flow",
				run = function()
					local overlay = require("./lib/overlay_world")
					for _, reveal in { true, false } do
						local feedForm, stayForm = Compose.cell(1), Compose.cell(1)
						local w: any = overlay.new(function(UI: FacetControls, Host: RobloxHost)
							return UI.Composition "Hud" {
								gap = 8,
								padding = 0,
								topbar = false,
								UI.Region "Stay" {
									zone = "left" :: "left",
									rank = 1,
									form = stayForm,
									Host.Frame { Name = "StayFull" },
								} :: unknown,
								UI.Region "Feed" {
									zone = "left" :: "left",
									rank = 2,
									mayDrop = true,
									reveal = if reveal then nil else false,
									form = feedForm,
									Host.Frame { Name = "FeedFull" },
								},
							}
						end)
						local feed = w.find("FeedFull")
						local home = feed.Parent
						w.size(w.find("StayFull"), 100, 60)
						w.size(feed, 120, 60)
						local badge = w.find("Reveal")
						if badge then
							w.size(badge, 28, 60)
						end
						local zones = w.find("Zones")
						w.size(zones, 800, 400)
						local target = w.find("ZoneRevealLeft")
						Verify.expect(target ~= nil):toBe(reveal)
						w.size(zones, 800, 100)
						Verify.expect((feedForm:peek())):toBe(0)
						if target then
							local left = w.find("Left")
							w.size(left, 100, 60)
							Verify.expect(target.Visible):toBe(true)
							Verify.expect(target.Parent):toBe(zones)
							Verify.expect(target.Size.X.Offset >= 44 and target.Size.Y.Offset >= 44):toBe(true)
							Verify.expect(target.Position.X.Offset >= 100):toBe(true)
							Verify.expect(target.AnchorPoint.X):toBe(0)
							target.Activated.fire()
							Verify.expect((feed:IsDescendantOf(w.find("HiddenFeed")))):toBe(true)
							w.size(zones, 800, 400)
							Verify.expect((feedForm:peek())):toBe(1)
							Verify.expect(feed.Parent):toBe(home)
							Verify.expect(target.Visible):toBe(false)
						end
						w.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"keeps the zone's hidden popover open while another region in the zone steps a visible form",
			{
				id = "native_composition::Composition::keeps the zone's hidden popover open while another region in the zone steps a visible form",
				run = function()
					local overlay = require("./lib/overlay_world")
					local feedForm, otherForm = Compose.cell(1), Compose.cell(1)
					local w: any = overlay.new(function(UI: FacetControls, Host: RobloxHost)
						return UI.Composition "Hud" {
							gap = 8,
							padding = 0,
							topbar = false,
							UI.Region "Other" {
								zone = "left" :: "left",
								rank = 1,
								mayDrop = true,
								form = otherForm,
								Host.Frame { Name = "OtherFull" } :: unknown,
								Host.Frame { Name = "OtherChip" },
							} :: unknown,
							UI.Region "Feed" {
								zone = "left" :: "left",
								rank = 2,
								mayDrop = true,
								form = feedForm,
								Host.Frame { Name = "FeedFull" },
							},
						}
					end)
					w.size(w.find("OtherFull"), 100, 60)
					w.size(w.find("OtherChip"), 40, 40)
					w.size(w.find("FeedFull"), 120, 60)
					for _, badge in
						{
							w.find("Other"):FindFirstChild("Reveal", true),
							w.find("Feed"):FindFirstChild("Reveal", true),
						}
					do
						w.size(badge, 28, 28)
					end
					local zones = w.find("Zones")
					w.size(zones, 800, 400)
					w.size(zones, 800, 90)
					Verify.expect(`{otherForm:peek()} {feedForm:peek()}`):toBe("1 0")
					w.size(w.find("Left"), 100, 60)
					w.find("ZoneRevealLeft").Activated.fire()
					Verify.expect((w.find("FeedFull"):IsDescendantOf(w.find("HiddenFeed")))):toBe(true)
					w.size(zones, 800, 50)
					Verify.expect(`{otherForm:peek()} {feedForm:peek()}`):toBe("2 0")
					Verify.expect((w.find("FeedFull"):IsDescendantOf(w.find("HiddenFeed")))):toBe(true)
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"refuses an unknown anchor, a rank that is not a whole number, and a child that is not a Region",
			{
				id = "native_composition::Composition::refuses an unknown anchor, a rank that is not a whole number, and a child that is not a Region",
				run = function()
					local function refusal(body: (any, any) -> any): string
						local engine, runtime, UI = make()
						local ok, message = pcall(function()
							runtime.mount(function()
								return body(UI, runtime.constructors)
							end, engine.new("ScreenGui"))
						end)
						runtime:dispose()
						return if ok then "" else tostring(message)
					end
					Verify.expect(string.find(
						refusal(function(UI: FacetControls, Host: RobloxHost)
							return UI.Region { zone = "middle" :: any, rank = 1, Host.Frame {} }
						end),
						"zone",
						1,
						true
					) ~= nil):toBe(true)
					Verify.expect(string.find(
						refusal(function(UI: FacetControls, Host: RobloxHost)
							return UI.Region { zone = "top" :: "top", rank = 1.5, Host.Frame {} }
						end),
						"rank",
						1,
						true
					) ~= nil):toBe(true)
					Verify.expect(string.find(
						refusal(function(UI: FacetControls, Host: RobloxHost)
							return UI.Composition { Host.Frame {} }
						end),
						"UI.Region",
						1,
						true
					) ~= nil):toBe(true)
					Verify.expect(string.find(
						refusal(function(UI: FacetControls)
							return UI.Region { zone = "top" :: "top", rank = 1 }
						end),
						"form",
						1,
						true
					) ~= nil):toBe(true)
					Verify.expect((refusal(function(UI: FacetControls)
						return UI.Composition { UI.fill() }
					end))):toBe("")
				end,
			}
		)
	end)
end
