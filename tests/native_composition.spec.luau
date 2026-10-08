--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
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
				cover.Activated:Fire()
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
							w.find("Feed"):FindFirstChild("Expand").Activated:Fire()
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
					target.Activated:Fire()
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
							target.Activated:Fire()
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
					w.find("ZoneRevealLeft").Activated:Fire()
					Verify.expect((w.find("FeedFull"):IsDescendantOf(w.find("HiddenFeed")))):toBe(true)
					w.size(zones, 800, 50)
					Verify.expect(`{otherForm:peek()} {feedForm:peek()}`):toBe("2 0")
					Verify.expect((w.find("FeedFull"):IsDescendantOf(w.find("HiddenFeed")))):toBe(true)
					w.stop()
				end,
			}
		)

		verifyHarness:case("keeps borrowed region content in its popover until the exit finishes", {
			id = "native_composition::Composition::keeps borrowed region content in its popover until the exit finishes",
			run = function()
				local overlay = require("./lib/overlay_world")
				local w: any = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Composition "Hud" {
						gap = 8,
						padding = 0,
						topbar = false,
						UI.Region "Tasks" {
							zone = "left" :: "left",
							rank = 1,
							Host.Frame { Name = "TasksFull" },
							Host.Frame { Name = "TasksChip" },
						},
					}
				end, { motionLevel = "normal", runService = true })
				local full = w.find("TasksFull")
				local home = full.Parent
				w.size(full, 240, 130)
				w.size(w.find("TasksChip"), 90, 30)
				w.size(w.find("Zones"), 200, 100)
				w.find("Expand").Activated:Fire()
				w.advance(1, 60)
				local modal = w.find("ExpandModal")
				Verify.expect((full:IsDescendantOf(modal))):toBe(true)
				w.find("DismissOutside").Activated:Fire()
				Verify.expect((full:IsDescendantOf(modal))):toBe(true)
				w.advance(1 / 60)
				Verify.expect((full:IsDescendantOf(modal))):toBe(true)
				w.advance(1, 60)
				Verify.expect(full.Parent):toBe(home)
				Verify.expect((w.find("ExpandModal"))):toBeNil()
				w.stop()
			end,
		})

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
