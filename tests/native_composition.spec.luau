--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
local t = require("./lib/testkit")
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

t.describe("Composition", function()
	t.it("anchors each region's zone to its screen edge or corner, in declaration order", function()
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
			t.expect(zone.AnchorPoint).toBe(T.Vector2.new(anchor[1], anchor[2]))
			t.expect(zone.Position).toBe(T.UDim2.fromScale(anchor[1], anchor[2]))
			t.expect(zone.AutomaticSize).toBe(T.Enum.AutomaticSize.XY)
		end
		local right = zones:FindFirstChild("TopRight")
		t.expect(right:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment)
			.toBe(T.Enum.HorizontalAlignment.Right)
		t.expect(right:FindFirstChild("Rail").LayoutOrder < right:FindFirstChild("Readout").LayoutOrder).toBe(true)
		t.expect(zones:FindFirstChild("Top"):FindFirstChild("Topbar"):FindFirstChild("Strip") ~= nil).toBe(true)
		stop()
	end)

	t.it("shows every region in full while each lane fits its third of the screen", function()
		local root: any, engine, forms, _, stop = mount()
		sized(engine, root:FindFirstChild("Zones"), 844, 330)
		t.expect(forms.peek())
			.toEqual({ Rounds = 1, Tasks = 1, Health = 1, Clock = 1, Strip = 1, Rail = 1, Readout = 1, Actions = 1 })
		t.expect(root:FindFirstChild("TasksFull", true).Parent.Visible).toBe(true)
		t.expect(root:FindFirstChild("TasksChip", true).Parent.Visible).toBe(false)
		t.expect(root:FindFirstChild("Tasks", true):GetAttribute("FacetForm")).toBe(1)
		stop()
	end)

	t.it("steps the least important region of the lane that runs out down first, then drops it", function()
		local root: any, engine, forms, _, stop = mount()
		local box = root:FindFirstChild("Zones")
		sized(engine, box, 844, 300)
		t.expect(forms.peek().Readout).toBe(0)
		t.expect(forms.peek().Rail).toBe(1)
		t.expect(forms.peek().Tasks).toBe(1)
		sized(engine, box, 844, 230)
		t.expect(forms.peek().Rail).toBe(2)
		t.expect(forms.peek().Actions).toBe(1)
		t.expect(forms.peek().Tasks).toBe(2)
		t.expect(forms.peek().Health).toBe(1)
		t.expect(root:FindFirstChild("Readout", true).Visible).toBe(false)
		stop()
	end)

	t.it("keeps each lane to a third of the width, stepping only a region wider than its lane", function()
		local root: any, engine, forms, _, stop = mount()
		sized(engine, root:FindFirstChild("Zones"), 390, 780)
		local chosen = forms.peek()
		t.expect(chosen.Tasks).toBe(2)
		t.expect(chosen.Clock).toBe(2)
		t.expect(chosen.Rail).toBe(2)
		t.expect(chosen.Rounds).toBe(1)
		t.expect(chosen.Health).toBe(2)
		t.expect(chosen.Readout).toBe(1)
		stop()
	end)

	t.it("returns to the same forms as a fresh mount after rotations", function()
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
				t.expect(forms.peek()).toEqual(want)
			end
		end
		stop()
	end)

	t.it("rides the free strip of the top bar in a TopbarSafeInsets ScreenGui, or leads the top zone", function()
		local ride = Compose.cell(true)
		local root: any, engine, forms, gui, stop = mount(nil, ride)
		local T = engine.types
		local topbar = root:FindFirstChild("Topbar", true)
		t.expect(topbar.Parent.Name).toBe("Top")
		gui.TopbarInset = T.Rect.new(164, 0, 844, 58)
		local strip = topbar.Parent
		t.expect(strip.ClassName).toBe("ScreenGui")
		t.expect(strip.ScreenInsets).toBe(T.Enum.ScreenInsets.TopbarSafeInsets)
		t.expect(strip.Parent).toBe(root:FindFirstAncestorWhichIsA("ScreenGui").Parent)
		t.expect(topbar.Size).toBe(T.UDim2.fromScale(1, 1))
		sized(engine, strip, 680, 58)
		sized(engine, root:FindFirstChild("Zones"), 844, 330)
		t.expect(forms.peek().Strip).toBe(1)
		ride:set(false)
		t.expect(topbar.Parent.Name).toBe("Top")
		t.expect(topbar.LayoutOrder).toBe(0)
		t.expect(strip.Parent).toBe(nil)
		stop()
		t.expect(strip.Parent).toBe(nil)
	end)

	t.it("pops an arriving form unless motion is reduced, and holds its measurement while it pops", function()
		for _, reduced in { false, true } do
			local root: any, engine, forms, _, stop = mount({ motionLevel = if reduced then "none" else "normal" })
			local box = root:FindFirstChild("Zones")
			sized(engine, box, 844, 330)
			local rail = root:FindFirstChild("Rail", true)
			local pop = rail:FindFirstChildWhichIsA("UIScale")
			t.expect(pop.Scale).toBe(1)
			sized(engine, box, 844, 250)
			t.expect(forms.peek().Rail).toBe(2)
			t.expect(pop.Scale < 1).toBe(not reduced)
			sized(engine, root:FindFirstChild("RailFull", true), 110, 40)
			t.expect(forms.peek().Rail).toBe(if reduced then 1 else 2)
			stop()
		end
	end)

	t.it("discloses a stepped-down region's richest content in context, anchored at the region", function()
		local overlay = require("./lib/overlay_world")
		local form = Compose.cell(1)
		local w: any = overlay.new(function(UI: FacetControls, Host: RobloxHost)
			return UI.Composition "Hud" {
				gap = 8,
				padding = 0,
				topbar = false,
				UI.Region "Rounds" { zone = "topLeft" :: "topLeft", rank = 1, Host.Frame { Name = "RoundsFull" } } :: unknown,
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
		t.expect(form:peek()).toBe(1)
		t.expect(cover.Visible).toBe(false)
		w.size(zones, 800, 150)
		t.expect(form:peek()).toBe(2)
		t.expect(cover.Visible).toBe(true)
		t.expect(cover.ZIndex < 0).toBe(true)
		t.expect(cover.Size.Y.Offset).toBe(14)
		cover.Activated.fire()
		t.expect(w.find("TasksRich") ~= nil).toBe(true)
		t.expect(w.find("ExpandModal"):GetAttribute("FacetRoute")).toBe("popover")
		w.size(zones, 800, 400)
		t.expect(form:peek()).toBe(1)
		t.expect(w.find("TasksRich")).toBeNil()
		w.stop()
	end)

	t.it("leaves a Show hidden disc in place of a dropped region that can reveal, unless reveal is off", function()
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
			t.expect(disc ~= nil).toBe(reveal)
			if disc then
				w.size(disc, 28, 20)
			end
			local zones = w.find("Zones")
			w.size(zones, 800, 400)
			t.expect(form:peek()).toBe(1)
			w.size(zones, 800, 200)
			t.expect(form:peek()).toBe(if reveal then 2 else 0)
			if disc then
				t.expect(disc.Parent.Visible).toBe(true)
				t.expect(w.find("Feed"):FindFirstChild("Expand").Visible).toBe(true)
				w.find("Feed"):FindFirstChild("Expand").Activated.fire()
				t.expect(w.find("FeedRich") ~= nil).toBe(true)
				w.size(zones, 800, 400)
				t.expect(w.find("FeedRich")).toBeNil()
			end
			w.stop()
		end
	end)

	t.it(
		"reveals a dropped region's own content in place when it has no expand, and puts the same node back",
		function()
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
			t.expect(form:peek()).toBe(2)
			local target = w.find("Feed"):FindFirstChild("Expand")
			t.expect(target.Visible).toBe(true)
			target.Activated.fire()
			t.expect(w.find("ExpandModal") ~= nil).toBe(true)
			t.expect(feed.Parent.Name).toBe("Hosted")
			t.expect(feed:IsDescendantOf(w.find("ExpandModal"))).toBe(true)
			w.size(feed, 200, 100)
			w.size(zones, 800, 400)
			t.expect(form:peek()).toBe(1)
			t.expect(feed.Parent).toBe(home)
			t.expect(feed.Parent ~= nil and home.Visible).toBe(true)
			w.stop()
		end
	)

	t.it("gathers a zone's dropped regions behind one hit-floor badge beside the zone, outside its flow", function()
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
			t.expect(target ~= nil).toBe(reveal)
			w.size(zones, 800, 100)
			t.expect(feedForm:peek()).toBe(0)
			if target then
				local left = w.find("Left")
				w.size(left, 100, 60)
				t.expect(target.Visible).toBe(true)
				t.expect(target.Parent).toBe(zones)
				t.expect(target.Size.X.Offset >= 44 and target.Size.Y.Offset >= 44).toBe(true)
				t.expect(target.Position.X.Offset >= 100).toBe(true)
				t.expect(target.AnchorPoint.X).toBe(0)
				target.Activated.fire()
				t.expect(feed:IsDescendantOf(w.find("HiddenFeed"))).toBe(true)
				w.size(zones, 800, 400)
				t.expect(feedForm:peek()).toBe(1)
				t.expect(feed.Parent).toBe(home)
				t.expect(target.Visible).toBe(false)
			end
			w.stop()
		end
	end)

	t.it("keeps the zone's hidden popover open while another region in the zone steps a visible form", function()
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
			{ w.find("Other"):FindFirstChild("Reveal", true), w.find("Feed"):FindFirstChild("Reveal", true) }
		do
			w.size(badge, 28, 28)
		end
		local zones = w.find("Zones")
		w.size(zones, 800, 400)
		w.size(zones, 800, 90)
		t.expect(`{otherForm:peek()} {feedForm:peek()}`).toBe("1 0")
		w.size(w.find("Left"), 100, 60)
		w.find("ZoneRevealLeft").Activated.fire()
		t.expect(w.find("FeedFull"):IsDescendantOf(w.find("HiddenFeed"))).toBe(true)
		w.size(zones, 800, 50)
		t.expect(`{otherForm:peek()} {feedForm:peek()}`).toBe("2 0")
		t.expect(w.find("FeedFull"):IsDescendantOf(w.find("HiddenFeed"))).toBe(true)
		w.stop()
	end)

	t.it("keeps borrowed region content in its popover until the exit finishes", function()
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
		w.find("Expand").Activated.fire()
		w.advance(1, 60)
		local modal = w.find("ExpandModal")
		t.expect(full:IsDescendantOf(modal)).toBe(true)
		w.find("DismissOutside").Activated.fire()
		t.expect(full:IsDescendantOf(modal)).toBe(true)
		w.advance(1 / 60)
		t.expect(full:IsDescendantOf(modal)).toBe(true)
		w.advance(1, 60)
		t.expect(full.Parent).toBe(home)
		t.expect(w.find("ExpandModal")).toBeNil()
		w.stop()
	end)

	t.it("refuses an unknown anchor, a rank that is not a whole number, and a child that is not a Region", function()
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
		t.expect(string.find(
			refusal(function(UI: FacetControls, Host: RobloxHost)
				return UI.Region { zone = "middle" :: any, rank = 1, Host.Frame {} }
			end),
			"zone",
			1,
			true
		) ~= nil).toBe(true)
		t.expect(string.find(
			refusal(function(UI: FacetControls, Host: RobloxHost)
				return UI.Region { zone = "top" :: "top", rank = 1.5, Host.Frame {} }
			end),
			"rank",
			1,
			true
		) ~= nil).toBe(true)
		t.expect(string.find(
			refusal(function(UI: FacetControls, Host: RobloxHost)
				return UI.Composition { Host.Frame {} }
			end),
			"UI.Region",
			1,
			true
		) ~= nil).toBe(true)
		t.expect(string.find(
			refusal(function(UI: FacetControls)
				return UI.Region { zone = "top" :: "top", rank = 1 }
			end),
			"form",
			1,
			true
		) ~= nil).toBe(true)
		t.expect(refusal(function(UI: FacetControls)
			return UI.Composition { UI.fill() }
		end)).toBe("")
	end)
end)
