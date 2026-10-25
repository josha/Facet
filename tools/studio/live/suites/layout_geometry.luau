--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Destination = typeof(require("@repo/tools/typecheck/aliases").Destination)
type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
type Tab = typeof(require("@repo/tools/typecheck/aliases").Tab)
type AlertAction = typeof(require("@repo/tools/typecheck/aliases").AlertAction)
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
local storage = game:GetService("ReplicatedStorage")
local VerifyRoblox = (require :: (Instance) -> typeof(require("@repo/tools/vendor/verify/src/roblox")))(
	storage:WaitForChild("FacetVerify"):WaitForChild("roblox")
)
local HudView = (require :: (Instance) -> typeof(require("../hud_view")))(
	storage:WaitForChild("FacetLive"):WaitForChild("hud_view")
)
type Case = {
	id: string,
	contracts: { string },
	run: ((any) -> ())?,
	setup: ((any) -> any)?,
	steps: { [string]: (any, any) -> () }?,
	keepGallery: boolean?,
}
local cases: { Case } = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function anchored(UI: any, Host: any, Compose: any, at: UDim2, edge: string?, pivot: Vector2)
	local anchor = UI.Button "Anchor" { label = "Anchor", Position = at, AnchorPoint = pivot }
	return Host.Frame "Surface" {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		anchor :: unknown,
		UI.Callout({
			anchor = anchor,
			edge = edge,
			isPresented = Compose.cell(true),
			onRetire = function() end,
			content = function()
				return UI.Text({ text = "Start from a prompt, then edit it before you send." })
			end,
		}),
	}
end

local SPOTS: {
	{
		name: string,
		at: typeof(UDim2.fromScale(0.5, 0.6))
			| typeof(UDim2.new(0, 8, 0.6, 0))
			| typeof(UDim2.new(1, -8, 0.6, 0))
			| typeof(UDim2.fromOffset(8, 12))
			| typeof(UDim2.new(1, -8, 1, -8)),
		edge: "top" | nil,
		pivot: typeof(Vector2.new(0.5, 0.5))
			| typeof(Vector2.new(0, 0.5))
			| typeof(Vector2.new(1, 0.5))
			| typeof(Vector2.zero)
			| typeof(Vector2.one),
	}
} =
	{
		{ name = "centre", at = UDim2.fromScale(0.5, 0.6), edge = "top" :: "top", pivot = Vector2.new(0.5, 0.5) },
		{ name = "left", at = UDim2.new(0, 8, 0.6, 0), edge = "top" :: "top", pivot = Vector2.new(0, 0.5) },
		{ name = "right", at = UDim2.new(1, -8, 0.6, 0), edge = "top" :: "top", pivot = Vector2.new(1, 0.5) },
		{ name = "top-left", at = UDim2.fromOffset(8, 12), edge = "top" :: "top", pivot = Vector2.zero },
		{ name = "bottom-right", at = UDim2.new(1, -8, 1, -8), edge = nil, pivot = Vector2.one },
	}

add("callout-edge-gap-shift-clamp", {}, function(t)
	for _, spot in SPOTS do
		local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
			return anchored(UI, Host, Compose, spot.at, spot.edge, spot.pivot)
		end)
		local anchor, panel = t.find(stage, "Anchor"), t.find(stage.Parent, "CalloutPanel")
		if not panel then
			t.check(spot.name .. " panel mounted", false)
			t.cleanup()
			continue
		end
		local screen = stage.Parent
		local a, p, s = t.rect(anchor), t.rect(panel), t.rect(screen)
		local above = p.b <= a.y + 0.5
		local gap = if above then a.y - p.b else p.y - a.b
		local arrow = t.find(screen, "Arrow")
		local reach = if arrow then arrow.AbsoluteSize.Y * math.sqrt(2) / 2 else 0
		t.near(spot.name .. " gap off the anchor edge", gap - reach, 8, 1)
		t.check(spot.name .. " panel does not cover the anchor", p.b <= a.y + 0.5 or p.y >= a.b - 0.5, {
			panel = { p.y, p.b },
			anchor = { a.y, a.b },
		})
		if spot.name == "top-left" then
			t.check("top-left flips below when the top edge has no room", p.y >= a.b - 0.5, { panel = p.y })
		end
		t.inside(spot.name .. " panel inside the safe box with 8px gutter", p, {
			x = s.x + 8,
			y = s.y + 8,
			r = s.r - 8,
			b = s.b - 8,
			w = 0,
			h = 0,
		}, 1)
		local centred = a.x + a.w / 2 - p.w / 2
		t.note(spot.name .. " shift", p.x - centred)
		if spot.name == "centre" then
			t.near("centre panel centred on the anchor", p.x + p.w / 2, a.x + a.w / 2, 1)
		end
		t.cleanup()
	end
end)

add("callout-tail-centre-border-corners", {}, function(t)
	for _, spot in SPOTS do
		local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
			return anchored(UI, Host, Compose, spot.at, spot.edge, spot.pivot)
		end)
		local screen = stage.Parent
		local anchor, panel, arrow = t.find(stage, "Anchor"), t.find(screen, "CalloutPanel"), t.find(screen, "Arrow")
		if not (panel and arrow) then
			t.check(spot.name .. " tail mounted", false)
			t.cleanup()
			continue
		end
		local a, p = t.rect(anchor), t.rect(panel)
		local centreX = arrow.AbsolutePosition.X + arrow.AbsoluteSize.X / 2
		local centreY = arrow.AbsolutePosition.Y + arrow.AbsoluteSize.Y / 2
		local border = if p.b <= a.y + 0.5 then p.b else p.y
		t.near(spot.name .. " tail rides the shared border", centreY, border, 1.5)
		t.check(
			spot.name .. " tail clears the panel corners",
			centreX >= p.x + 12 - 1 and centreX <= p.r - 12 + 1,
			{ centre = centreX, left = p.x, right = p.r }
		)
		local source = a.x + a.w / 2
		if source >= p.x + 12 and source <= p.r - 12 then
			t.near(spot.name .. " tail centres on the source", centreX, source, 1.5)
		end
		t.check(spot.name .. " tail paints behind the panel", arrow.ZIndex < panel.ZIndex, {
			arrow = arrow.ZIndex,
			panel = panel.ZIndex,
		})
		t.cleanup()
	end
end)

add("callout-themed-arrows-follow-edges-and-clamps", {}, function(t)
	for _, key in { "fantasy_ornate", "fantasy_parchment", "pixel_quest" } do
		local package
		for _, entry in t.themes do
			if entry.name == key then
				package = entry.package
			end
		end
		assert(package, key .. " must be installed")
		for _, size in { Vector2.new(1024, 768), Vector2.new(390, 844), Vector2.new(844, 390) } do
			local edge, position
			local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
				edge, position =
					Compose.cell("bottom" :: "top" | "bottom" | "leading" | "trailing"),
					Compose.cell(UDim2.fromScale(0.5, 0.5))
				local anchor =
					UI.Button "Anchor" { label = "Anchor", Position = position, AnchorPoint = Vector2.new(0.5, 0.5) }
				return Host.Frame {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					anchor :: unknown,
					UI.Callout {
						anchor = anchor,
						edge = edge,
						isPresented = true,
						title = "A themed arrow",
						onRetire = function() end,
					},
				}
			end, { theme = package, size = size, frames = 20 })
			local panel, arrow = t.find(stage.Parent, "CalloutPanel"), t.find(stage.Parent, "Arrow")
			assert(panel and arrow, "callout must mount")
			local artwork = t.find(panel, "ArrowArtwork")
			assert(artwork, "arrow artwork must belong to the panel")
			local image = artwork:FindFirstChildWhichIsA("ImageLabel", true)
			assert(image, "arrow artwork must mount")
			game:GetService("ContentProvider"):PreloadAsync({ image })
			t.check(key .. " arrow image loads", image.IsLoaded)
			for _, side in { "bottom", "top", "leading", "trailing" } do
				edge:set(side :: "top" | "bottom" | "leading" | "trailing")
				for _, fraction in { 0.1, 0.5, 0.9 } do
					position:set(UDim2.fromScale(fraction, fraction))
					t.settle(8)
					local p, a = t.rect(panel), t.rect(arrow)
					local cx, cy = a.x + a.w / 2, a.y + a.h / 2
					local painted = t.rect(image)
					t.near("arrow image stays centred in its rotated bounds on X", painted.x + painted.w / 2, cx, 1)
					t.near("arrow image stays centred in its rotated bounds on Y", painted.y + painted.h / 2, cy, 1)
					local recipe = package.chrome.panelTail
					local inward = recipe.size.h / 2 - recipe.overhang
					local label = `{key} {size} {side} {fraction}`
					local rotation = arrow.Rotation
					local vertical = rotation == 0 or rotation == 180
					local actual = if vertical then cy else cx
					local expected = if rotation == 0
						then p.y + inward
						elseif rotation == 180 then p.b - inward
						elseif rotation == 90 then p.r - inward
						else p.x + inward
					t.near(label .. " artwork overlaps its frame at the join", actual, expected, 1)
					local along, first, last =
						if vertical then cx else cy, if vertical then p.x else p.y, if vertical then p.r else p.b
					t.check(
						label .. " artwork clears both corners",
						along - a.w / 2 >= first + recipe.margin - 1 and along + a.w / 2 <= last - recipe.margin + 1
					)
					t.check(
						label .. " artwork stays beneath content",
						artwork.ZIndex == 0 and artwork:IsDescendantOf(panel)
					)
					for _, node in stage.Parent:GetDescendants() do
						if node:IsA("Path2D") and node.Name == "Outline" then
							t.check(label .. " has no extra native border", not node.Visible)
						end
					end
				end
			end
			t.cleanup()
		end
	end
end)

add("popover-themed-arrows-keep-the-frame-unclipped", {}, function(t)
	for _, theme in t.themes do
		if not table.find({ "fantasy_ornate", "fantasy_parchment", "pixel_quest" }, theme.name) then
			continue
		end
		for _, side in { "top", "bottom", "leading", "trailing" } do
			local stage = t.mount(function(UI: FacetControls)
				return UI.Popover {
					isPresented = true,
					edge = side :: "top" | "bottom" | "leading" | "trailing",
					maxWidth = 280,
					trigger = UI.Button "Anchor" { label = "About", Position = UDim2.fromScale(0.5, 0.5) },
					content = function()
						return UI.Text { text = "Anchored content with a tail.", wrap = true }
					end,
				}
			end, { theme = theme.package, size = Vector2.new(1024, 768), motionLevel = "normal", frames = 50 })
			local panel, arrow = t.find(stage.Parent, "Panel"), t.find(stage.Parent, "Tail")
			t.check(theme.name .. " " .. side .. " panel mounts", panel ~= nil)
			if panel then
				t.check("the settled frame has no clipping fade container", panel:FindFirstChild("Fade") == nil)
				local skin = panel:FindFirstChild("SkinBoundary", true)
				t.check("the complete panel artwork remains mounted", skin ~= nil and t.visible(skin))
				local join = panel:FindFirstChild("TailChromeBoundary")
				local body = panel:FindFirstChild("Body", true)
				t.check(
					"the arrow join paints above the frame and below text",
					skin ~= nil
						and join ~= nil
						and body ~= nil
						and skin.ZIndex < join.ZIndex
						and join.ZIndex < body.ZIndex
				)
			end
			t.check("the themed arrow remains mounted", arrow ~= nil and t.visible(arrow))
			t.cleanup()
		end
	end
end)

add("navigation-stack-root-box-and-back-chrome", {}, function(t)
	local path
	local stage = t.mount(function(UI: FacetControls, _, Compose: ComposeModule)
		path = Compose.cell({})
		return UI.NavigationStack({
			path = path,
			root = {
				content = function(): Instance
					return UI.Text "RootLabel" { text = "Root" }
				end,
			},
			destinations = {
				detail = {
					title = "Detail",
					content = function(): Instance
						return UI.Text "DetailLabel" { text = "Detail" }
					end,
				} :: Destination,
			},
		})
	end, { size = Vector2.new(480, 320) })
	local stack = t.find(stage, "NavigationStack")
	local rootDestination = t.find(t.find(stack, "@root") or stack, "Destination")
	local s, d = t.rect(stack), t.rect(rootDestination)
	t.near("untitled root keeps the full width", d.w, s.w, 0.5)
	t.near("untitled root keeps the full height", d.h, s.h, 0.5)
	t.near("untitled root starts at the top", d.y, s.y, 0.5)
	path:set({ { id = "detail" } })
	t.settle(12)
	local page = t.find(stack, "detail")
	local destination, back, bar = t.find(page, "Destination"), t.find(page, "Back"), t.find(page, "NavigationBar")
	local pd, pb = t.rect(destination), t.rect(back)
	t.near("destination box is reduced by the Back chrome", pd.h, s.h - t.rect(bar).h, 0.5)
	t.check("destination starts below the navigation bar", pd.y >= t.rect(bar).b - 0.5, { destination = pd.y })
	t.near("destination keeps the stack bottom", pd.b, s.b, 0.5)
	t.inside("Back sits inside the navigation bar", pb, bar, 1)
	t.check("Back is visible", t.visible(back))
	t.note("navigation bar height", t.rect(bar).h)
	local title = t.find(bar, "Title")
	t.check("title fits its bar", title.TextFits, { bounds = title.TextBounds, size = title.AbsoluteSize })
end)

add("vertical-segments-stack-share-width-floor", {}, function(t)
	local stage = t.mount(function(UI: FacetControls, _, Compose: ComposeModule)
		return UI.Picker "Rail" {
			style = "segmented" :: "segmented",
			axis = "y" :: "y",
			selected = Compose.cell("a"),
			options = {
				{ value = "a", label = "Alpha" } :: PickerOption,
				{ value = "b", label = "Beta with a longer label" } :: PickerOption,
				{ value = "c", label = "C" } :: PickerOption,
			},
		}
	end, { size = Vector2.new(480, 400) })
	local segments = {}
	for _, value in { "a", "b", "c" } do
		local node = t.find(stage, value)
		if node and node:IsA("GuiObject") then
			table.insert(segments, t.rect(node))
		end
	end
	t.check("three segments mounted", #segments == 3, #segments)
	for index, rect in segments do
		t.check(`segment {index} meets the 44px floor on X`, rect.w >= 44 - 0.5, rect.w)
		t.check(`segment {index} meets the 44px floor on Y`, rect.h >= 44 - 0.5, rect.h)
		if index > 1 then
			t.check(`segment {index} stacks below segment {index - 1}`, rect.y >= segments[index - 1].b - 0.5, {
				top = rect.y,
				previousBottom = segments[index - 1].b,
			})
			t.near(`segment {index} shares the rail width`, rect.w, segments[1].w, 0.5)
			t.near(`segment {index} shares the rail x`, rect.x, segments[1].x, 0.5)
		end
	end
end)

add("tab-head-accessory-above-rail", {}, function(t)
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
		return UI.TabView({
			selection = Compose.cell("one"),
			style = "sidebarAdaptable" :: "sidebarAdaptable",
			placement = "sidebar" :: "sidebar",
			tabs = {
				{
					id = "one",
					label = "One",
					content = function()
						return Host.Frame({ BackgroundTransparency = 1 })
					end,
				} :: Tab,
				{
					id = "two",
					label = "Two",
					content = function()
						return Host.Frame({ BackgroundTransparency = 1 })
					end,
				} :: Tab,
			},
			accessories = {
				head = function(): Instance?
					return UI.Text "HeadLabel" { text = "Profile header" }
				end,
				foot = function(): Instance?
					return UI.Button "FootButton" { label = "Settings" }
				end,
			},
		})
	end, { size = Vector2.new(1000, 600) })
	local head, tabs = t.find(stage, "Accessory-head"), t.find(stage, "Tabs")
	local foot = t.find(stage, "Accessory-foot")
	if not (head and tabs and foot) then
		t.check("rail slots mounted", false, { head = head ~= nil, tabs = tabs ~= nil, foot = foot ~= nil })
		return
	end
	local h, s, f, root = t.rect(head), t.rect(tabs), t.rect(foot), t.rect(stage)
	t.check("head sits above the strip", h.b <= s.y + 0.5, { head = h.b, strip = s.y })
	t.check("head height is measured", h.h > 0, h.h)
	local railWidth = t.rect(t.find(stage, "Content")).x - root.x
	t.near("head spans the rail width", h.w, railWidth, 0.5)
	t.near("head starts at the rail edge", h.x, root.x, 0.5)
	t.check(
		"the strip sits inside the rail",
		s.x >= root.x - 0.5 and s.r <= root.x + railWidth + 0.5,
		{ strip = s, railWidth = railWidth }
	)
	t.check("head inside the TabView", h.x >= root.x - 0.5 and h.y >= root.y - 0.5, h)
	t.near("foot is pinned to the rail bottom", f.b, root.b, 0.5)
	t.check("strip ends above the foot", s.b <= f.y + 0.5, { strip = s.b, foot = f.y })
	t.check("rail inside the TabView width", s.r <= root.r + 0.5, { strip = s.r, root = root.r })
end)

add("circle-button-authored-axes", {}, function(t)
	for _, rung in { "compact", "regular", "large" } :: { "compact" | "large" | "regular" } do
		local stage = t.mount(function(UI: FacetControls)
			return UI.Button "Circle" {
				label = "Close",
				icon = "close",
				shape = "circle" :: "circle",
				controlSize = rung :: "compact" | "large" | "regular",
			}
		end, { size = Vector2.new(300, 200) })
		local node = t.find(stage, "Circle")
		local r = t.rect(node)
		t.near(`{rung} circle is round`, r.w, r.h, 0.5)
		t.check(`{rung} circle is not empty`, r.w > 0, r.w)
		t.note(`{rung} diameter`, r.w)
		t.cleanup()
	end
	for _, axis in { "width", "height" } do
		local size = if axis == "width" then UDim2.fromOffset(32, 0) else UDim2.fromOffset(0, 72)
		local stage = t.mount(function(UI: FacetControls)
			return UI.Button "Circle" {
				label = "Close",
				icon = "close",
				shape = "circle" :: "circle",
				controlSize = "compact" :: "compact",
				Size = size,
			}
		end, { size = Vector2.new(300, 200) })
		local r = t.rect(t.find(stage, "Circle"))
		local expected = if axis == "width" then 32 else 72
		t.near(`authored {axis} circle keeps its authored {axis}`, if axis == "width" then r.w else r.h, expected, 0.5)
		t.near(`authored {axis} circle is round`, r.w, r.h, 0.5)
		t.cleanup()
	end
end)

local HUD_DEVICES: { { name: string, size: Vector2, environment: { [string]: string } } } = {
	{ name = "desktop", size = Vector2.new(1542, 1009), environment = { preferredInput = "KeyboardAndMouse" } },
	{ name = "phone-portrait", size = Vector2.new(389, 704), environment = { preferredInput = "Touch" } },
	{ name = "phone-landscape", size = Vector2.new(800, 360), environment = { preferredInput = "Touch" } },
	{ name = "tablet", size = Vector2.new(1024, 768), environment = { preferredInput = "Touch" } },
	{
		name = "console",
		size = Vector2.new(1920, 1080),
		environment = { preferredInput = "Gamepad", viewingDistance = "ten-foot" },
	},
}

local function goalsHud(UI: FacetControls, ordering: boolean)
	local env = UI.environment()
	local function bar(name: string, value: number, words: string, width: number)
		return UI.ProgressView(name) {
			value = value,
			endLabel = words,
			Size = function(use: Use)
				return UDim2.fromOffset(use(env.scaled(width)), 0)
			end,
		}
	end
	local function order(compact: boolean): Frame?
		if not ordering then
			return nil
		end
		return UI.HStack "Order" {
			gap = "s",
			align = "center",
			UI.Text "Title" { text = "Bear's Big Order", textRole = "strong" },
			if compact then UI.Text "Count" { text = "0/12" } else bar("Bales", 0, "0/12", 120),
			UI.Text "Clock" { text = "2:26", textRole = "label" },
		}
	end
	local edge = { top = "xs", bottom = "xs", left = "m", right = "m" }
	return UI.Composition "Hud" {
		topbar = false,
		UI.Region "Wallet" {
			zone = "topLeft",
			rank = 1,
			UI.VStack "WalletFull" {
				gap = "xs",
				align = "stretch",
				UI.HStack "Coins" {
					surface = "panel",
					padding = "s",
					gap = "m",
					UI.Text "Count" { text = "1,234,567", textRole = "numeral" },
					UI.Text "Unit" { text = "coins", textRole = "caption" },
				},
				UI.Button "Upgrades" { label = "Upgrades", controlSize = "compact" },
			},
		},
		UI.Region "Goals" {
			zone = "top",
			rank = 2,
			mayDrop = false,
			reveal = false,
			UI.HStack "GoalsWide" {
				surface = "panel",
				padding = edge,
				gap = "s",
				align = "center",
				UI.Text "Name" { text = "Green Meadows", textRole = "strong" },
				bar("Mowed", 0, "0%", 150),
				order(false),
			},
			UI.HStack "GoalsLine" {
				surface = "panel",
				padding = edge,
				gap = "s",
				align = "center",
				UI.Text "Name" { text = "Green Meadows", textRole = "strong" },
				UI.Text "Pct" { text = "0%" },
				order(true),
			},
			UI.VStack "GoalsTall" {
				surface = "panel",
				padding = edge,
				gap = "xs",
				UI.HStack "Meadow" {
					gap = "s",
					align = "center",
					UI.Text "Name" { text = "Green Meadows", textRole = "strong" },
					UI.Text "Pct" { text = "0%" },
				},
				order(true),
			},
		},
		UI.Region "Boost" {
			zone = "action",
			rank = 1,
			UI.Button "Boost" { label = "Boost", shape = "circle", target = "thumb", controlSize = "large" },
		},
	}
end

add("hud-goals-card-fits-every-device", {}, function(t)
	local studio = game:GetService("RunService"):IsStudio()
	for _, device in HUD_DEVICES do
		for _, ordering in { false, true } do
			local where = `{device.name}{if ordering then " with the order" else ""}`
			local stage = t.mount(function(UI: FacetControls)
				return goalsHud(UI, ordering)
			end, { size = device.size, environment = device.environment, frames = 30 })
			local audit = VerifyRoblox.uiAudit.analyze(VerifyRoblox.uiAudit.collect { roots = { stage } })
			local blocking = {}
			for _, violation in audit.violations do
				local measured = studio
					or string.match(violation.path, "%.EndLabel$") ~= nil
					or string.match(violation.path, "%.Value$") ~= nil
				if
					violation.rule == "text-truncated" and measured
					or violation.rule == "text-clipped"
					or violation.rule == "offscreen"
				then
					table.insert(blocking, violation)
				end
			end
			t.check(where .. ": the HUD text fits and stays on screen", #blocking == 0, blocking)
			local zones: { { path: string, rect: { x: number, y: number, width: number, height: number }, visible: boolean } } =
				{}
			for _, element in VerifyRoblox.uiAudit.collect({ roots = { stage } }).elements do
				table.insert(zones, { path = element.path, rect = element.rect, visible = element.visible })
			end
			local covered = HudView.problems(zones)
			t.check(where .. ": no HUD zone moves into the play view", #covered == 0, covered)
			local goals = t.find(stage, "Goals")
			t.check(where .. ": the goals card shows", goals ~= nil and t.visible(goals), goals and goals.AbsoluteSize)
			t.note(where .. " goals form", goals and goals:GetAttribute("FacetForm"))
			t.cleanup()
		end
	end
end)

add("progress-short-end-label-keeps-its-text", {}, function(t)
	for _, theme in t.themes do
		for _, width in { 150, 120 } do
			for _, words in { "0%", "100%", "0/12" } do
				local where = `{theme.name} {width} {words}`
				local stage = t.mount(function(UI: FacetControls)
					return UI.ProgressView "Bar" { value = 0.3, endLabel = words, Size = UDim2.fromOffset(width, 0) }
				end, { theme = theme.package, size = Vector2.new(300, 120) })
				local ending = t.find(stage, "EndLabel") :: TextLabel?
				local track = t.find(stage, "Track") :: Frame?
				if not (ending and track) then
					t.check(where .. " bar mounted", false)
					t.cleanup()
					continue
				end
				local limit = track:FindFirstChildWhichIsA("UISizeConstraint")
				local floor = if limit then limit.MinSize.X else 0
				local giving = track.AbsoluteSize.X > floor + 0.5
				t.check(
					where .. " the end label shows all its text while the track can give way",
					ending.TextFits or not giving,
					{
						text = ending.Text,
						bounds = ending.TextBounds,
						size = ending.AbsoluteSize,
						track = track.AbsoluteSize,
					}
				)
				t.check(where .. " the track gives way", track.AbsoluteSize.X >= 4, track.AbsoluteSize)
				t.check(
					where .. " the track and the label share the bar's width",
					ending.AbsolutePosition.X + ending.AbsoluteSize.X <= track.AbsolutePosition.X + width + 0.5,
					{ track = track.AbsoluteSize, ending = ending.AbsoluteSize }
				)
				t.cleanup()
			end
		end
	end
end)

add("circular-progress-stroke-inside-box", {}, function(t)
	for _, theme in t.themes do
		local stage = t.mount(function(UI: FacetControls)
			return UI.ProgressView "Ring" { presentation = "circular" :: "circular", value = 1 }
		end, { theme = theme.package, size = Vector2.new(200, 200) })
		local indicator = t.find(stage, "Indicator")
		local fill = indicator and indicator:FindFirstChild("RingFill")
		if not (indicator and fill) then
			t.check(theme.name .. " ring mounted", false)
			t.cleanup()
			continue
		end
		local box = indicator.AbsoluteSize
		local half = fill.Thickness / 2
		local worst = math.huge
		for _, point in fill:GetControlPoints() do
			local x = point.Position.X.Scale * box.X + point.Position.X.Offset
			local y = point.Position.Y.Scale * box.Y + point.Position.Y.Offset
			worst = math.min(worst, x - half, y - half, box.X - x - half, box.Y - y - half)
		end
		t.check(
			theme.name .. " stroke fits inside its own box",
			worst >= -0.5,
			{ margin = worst, thickness = fill.Thickness, box = box }
		)
		t.near(theme.name .. " ring box is square", box.X, box.Y, 0.5)
		t.cleanup()
	end
end)

local function paddingOf(node: Instance): (number, number, number, number)
	local padding = node:FindFirstChildWhichIsA("UIPadding")
	local size = (node :: any).AbsoluteSize
	local function px(name: string, extent: number): number
		local value = if padding then padding:GetStyled(name) else node:GetStyled(name, "::UIPadding")
		return value.Scale * extent + value.Offset
	end
	return px("PaddingLeft", size.X), px("PaddingRight", size.X), px("PaddingTop", size.Y), px("PaddingBottom", size.Y)
end

add("chrome-insets-reserve-native-padding", {}, function(t)
	for _, theme in t.themes do
		local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
			return Host.Frame "Column" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Host.UIListLayout({ Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }) :: unknown,
				UI.Button "Plain" { label = "Continue the long journey", LayoutOrder = 1 },
				UI.Toggle "Switch" { label = "Notifications", value = Compose.cell(true), LayoutOrder = 2 },
			}
		end, { theme = theme.package, size = Vector2.new(420, 300) })
		for _, name in { "Plain", "Switch" } do
			local node = t.find(stage, name)
			if not node then
				t.check(`{theme.name} {name} mounted`, false)
				continue
			end
			local left, right, top, bottom = paddingOf(node)
			local r = t.rect(node)
			local content = { x = r.x + left, y = r.y + top, r = r.r - right, b = r.b - bottom, w = 0, h = 0 }
			local label = node:IsA("TextButton") and node or node:FindFirstChildWhichIsA("TextLabel", true)
			local lifted = t.find(node, "LabelBounds")
			if lifted then
				t.inside(`{theme.name} {name} lifted label inside the recipe padding`, lifted, content, 1)
				local lb = t.rect(lifted)
				t.near(`{theme.name} {name} lifted label starts at the left inset`, lb.x, content.x, 1)
				t.near(`{theme.name} {name} lifted label ends at the right inset`, lb.r, content.r, 1)
			elseif label and label:IsA("GuiObject") and (label :: any).TextBounds then
				local bounds = (label :: any).TextBounds
				t.check(
					`{theme.name} {name} text fits inside the padded box`,
					bounds.X <= (content.r - content.x) + 1 and bounds.Y <= (content.b - content.y) + 1,
					{ text = bounds, box = { content.r - content.x, content.b - content.y } }
				)
			end
			t.note(`{theme.name} {name} padding`, { left, right, top, bottom })
			t.check(
				`{theme.name} {name} padded box is not negative`,
				content.r >= content.x and content.b >= content.y,
				{
					left = left,
					right = right,
					width = r.w,
				}
			)
		end
		t.cleanup()
	end
end)

add("panel-insets-reserve-native-padding", {}, function(t)
	for _, theme in t.themes do
		local recipe = theme.package.chrome and theme.package.chrome.panel
		local inset = if recipe then recipe.contentInsets or {} else {}
		local spacing = theme.package.metrics.space.m
		local stage = t.mount(function(UI: FacetControls, _, Compose: ComposeModule)
			return UI.Alert({
				isPresented = Compose.cell(true),
				title = "Replace the save?",
				message = "Your changes to this slot are not saved yet.",
				actions = {
					{ id = "stay", label = "Stay", role = "cancel" :: "cancel" } :: AlertAction,
					{ id = "go", label = "Replace" } :: AlertAction,
				},
			})
		end, { theme = theme.package, size = Vector2.new(800, 600) })
		local panel
		for _, node in stage.Parent:GetDescendants() do
			if node.Name == "AlertPanel" and node:IsA("GuiObject") and t.visible(node) then
				panel = node
			end
		end
		if not panel then
			t.check(`{theme.name} alert panel shown`, false)
			t.cleanup()
			continue
		end
		t.stable(panel)
		local left, right, top, bottom = paddingOf(panel)
		t.check(`{theme.name} the panel wears the facet-panel tag`, panel:HasTag("facet-panel"), panel:GetTags())
		t.near(`{theme.name} panel left padding is the panel inset`, left, math.max(spacing, inset.left or 0), 0.5)
		t.near(`{theme.name} panel right padding is the panel inset`, right, math.max(spacing, inset.right or 0), 0.5)
		t.near(`{theme.name} panel top padding is the panel inset`, top, math.max(spacing, inset.top or 0), 0.5)
		t.near(
			`{theme.name} panel bottom padding is the panel inset`,
			bottom,
			math.max(spacing, inset.bottom or 0),
			0.5
		)
		local layout = panel:FindFirstChild("AlertLayout", true)
		if layout then
			local r = t.rect(panel)
			t.inside(
				`{theme.name} the alert content sits inside the panel padding`,
				layout,
				{ x = r.x + left, y = r.y + top, r = r.r - right, b = r.b - bottom, w = 0, h = 0 },
				1
			)
		else
			t.check(`{theme.name} alert layout found`, false)
		end
		t.cleanup()
	end
end)

add("chrome-zero-inset-full-bleed", {}, function(t)
	local tested = 0
	for _, theme in t.themes do
		local chrome = theme.package.chrome
		local control = chrome and chrome.control
		if not control or control.kind == "native" or control.kind == "none" then
			continue
		end
		local package = table.clone(theme.package)
		package.chrome = table.clone(chrome)
		local bare = table.clone(control)
		bare.contentInsets = { left = 0, right = 0, top = 0, bottom = 0 }
		package.chrome.control = bare
		local stage = t.mount(function(UI: FacetControls)
			return UI.Button "Plain" { label = "Continue", Size = UDim2.fromOffset(240, 44) }
		end, { theme = package, size = Vector2.new(420, 300) })
		local node = t.find(stage, "Plain")
		local lifted = node and t.find(node, "LabelBounds")
		if not lifted then
			t.check(`{theme.name} lifted label found`, false)
			t.cleanup()
			continue
		end
		tested += 1
		t.stable(lifted)
		local n, l = t.rect(node), t.rect(lifted)
		local left, right, top, bottom = paddingOf(node)
		t.note(`{theme.name} zero inset: button padding`, { left, right, top, bottom })
		t.near(`{theme.name} zero inset: no top padding`, top, 0, 0.5)
		t.near(`{theme.name} zero inset: no bottom padding`, bottom, 0, 0.5)
		t.near(`{theme.name} zero inset: the lifted label spans the button height`, l.h, n.h, 1)
		t.near(`{theme.name} zero inset: the lifted label starts at the text padding floor`, l.x, n.x + left, 1)
		t.near(`{theme.name} zero inset: the lifted label ends at the text padding floor`, l.r, n.r - right, 1)
		t.cleanup()
	end
	t.check("at least one skinned control package was tested", tested > 0, tested)
end)

add("layers-hang-outside-layout", {}, function(t)
	for _, theme in t.themes do
		t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
			return UI.Sheet({
				isPresented = Compose.cell(true),
				detent = Compose.cell("medium"),
				title = "Loadout",
				content = function(): Instance
					return UI.Text "SheetBody" {
						text = "Choose a loadout for the next round.",
						TextWrapped = true,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					}
				end,
			})
		end, { theme = theme.package })
		local gui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
		local panel
		for _, node in gui:GetDescendants() do
			if node.Name == "SheetPanel" and node:IsA("GuiObject") and t.visible(node) then
				panel = node
			end
		end
		local body = panel and t.find(panel, "SheetBody")
		if not (panel and body) then
			t.check(theme.name .. " sheet mounted", false)
			t.cleanup()
			continue
		end
		local p, b = t.rect(panel), t.rect(body)
		local offset = b.y - p.y
		t.inside(theme.name .. " content inside the decorated panel", body, panel, 1)
		local boundary
		for _, node in panel:GetDescendants() do
			if node.Name == "SkinBoundary" and node.Parent and node.Parent.Parent == panel then
				boundary = node
			end
		end
		local skin = boundary and boundary:FindFirstChild("Skin", true)
		if skin then
			local art = t.rect(skin)
			t.near(theme.name .. " art covers the panel width", art.w, p.w, 1.5)
			t.near(theme.name .. " art covers the panel height", art.h, p.h, 1.5)
			t.near(theme.name .. " art starts at the panel origin", art.x, p.x, 1.5)
			local host = assert(assert(boundary).Parent)
			local outer = host.Parent
			t.check(
				theme.name .. " art boundary is not a layout item",
				host:FindFirstChildWhichIsA("UIGridStyleLayout") == nil
					and (
						not host:IsA("GuiObject")
						or outer == nil
						or outer:FindFirstChildWhichIsA("UIGridStyleLayout") == nil
					),
				host.ClassName
			)
		end
		t.note(theme.name .. " content offset", { offset = offset, skinned = skin ~= nil })
		t.cleanup()
	end
end)

add("grid-cell-width-arithmetic", {}, function(t)
	for _, columns in { 2, 3, 4 } do
		local rows = {}
		for index = 1, 12 do
			rows[index] = { id = tostring(index) }
		end
		local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
			return UI.VirtualGrid "Grid" {
				from = rows,
				key = function(item)
					return item.id
				end,
				columns = columns,
				itemSize = 60,
				gap = 8,
				crossGap = 10,
				Size = UDim2.fromOffset(400, 300),
				render = function(current): GuiObject
					return Host.Frame({
						Name = "Cell" .. current:peek().id,
						Size = UDim2.fromScale(1, 1),
					})
				end,
			}
		end, { size = Vector2.new(400, 300) })
		local grid = t.find(stage, "Grid")
		local window = grid.AbsoluteWindowSize.X
		local edge = math.ceil(10 / 2)
		local expected = (window - 2 * edge - (columns - 1) * 10) / columns
		local first, second = t.find(grid, "Cell1"), t.find(grid, "Cell2")
		if not (first and second) then
			t.check(`{columns} columns cells mounted`, false)
			t.cleanup()
			continue
		end
		local a, b = t.rect(first), t.rect(second)
		t.near(`{columns} columns cell width`, a.w, expected, 1)
		t.near(`{columns} columns first cell keeps half a gap at the edge`, a.x - grid.AbsolutePosition.X, edge, 1)
		t.near(`{columns} columns cross gap`, b.x - a.r, 10, 1)
		t.near(`{columns} columns cell height`, a.h, 60, 1)
		local below = t.find(grid, "Cell" .. tostring(columns + 1))
		if below then
			t.near(`{columns} columns line gap`, t.rect(below).y - a.b, 8, 1)
			t.near(`{columns} columns next line starts at the first column`, t.rect(below).x, a.x, 1)
		end
		t.cleanup()
	end
end)

add("image-button-caption-clear-of-artwork", {}, function(t)
	for _, theme in t.themes do
		for _, width in { 180, 240, 320 } do
			local stage = t.mount(function(UI: FacetControls)
				return UI.Button "Card" {
					label = "A driver with a descriptive title",
					subtitle = "A longer description that must wrap inside the card.",
					image = "rbxasset://textures/ui/GuiImagePlaceholder.png",
					imageAspectRatio = 2,
					Size = UDim2.fromOffset(width, 300),
				}
			end, { theme = theme.package, size = Vector2.new(400, 400) })
			local card = t.find(stage, "Card")
			local image, title = t.find(card, "Image"), t.find(card, "Title")
			local description = t.find(card, "Description")
			local where = `{theme.name} {width}px`
			if not (image and title) then
				t.check(where .. " card parts mounted", false)
				t.cleanup()
				continue
			end
			local i, ti = t.rect(image), t.rect(title)
			t.check(where .. " title below the artwork", ti.y >= i.b - 0.5, { image = i.b, title = ti.y })
			t.inside(where .. " artwork inside the card", i, card, 1)
			t.inside(where .. " title inside the card", ti, card, 1)
			if description then
				local d = t.rect(description)
				t.check(where .. " description below the title", d.y >= ti.b - 0.5, { title = ti.b, description = d.y })
				t.check(
					where .. " description clear of the artwork",
					d.y >= i.b - 0.5,
					{ image = i.b, description = d.y }
				)
				t.note(where .. " description overflow below the card", math.max(0, d.b - t.rect(card).b))
			end
			local selectable = 0
			for _, node in card:GetDescendants() do
				if node:IsA("GuiObject") and node.Selectable and t.visible(node) then
					selectable += 1
				end
			end
			t.check(where .. " one focus target", card.Selectable and selectable == 0, { descendants = selectable })
			t.cleanup()
		end
	end
end)

add("image-button-wrapped-cells-reserve-full-height", {}, function(t)
	for _, ratio in { 1, 16 / 9 } do
		for _, scale in { 0.75, 1, 1.5 } do
			local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
				local cells: { unknown } = {}
				for i, appearance in { "standard", "emphasis", "soft", "utility", "link", "inverse" } do
					cells[i] = UI.VStack({
						Name = `Cell{i}`,
						gap = "xs",
						UI.Text { text = appearance, textRole = "caption" :: "caption" },
						UI.ErrorBoundary {
							view = function()
								return UI.Button {
									label = "Button",
									subtitle = "12 playing",
									appearance = appearance,
									image = "rbxasset://textures/ui/GuiImagePlaceholder.png",
									imageAspectRatio = ratio,
								}
							end,
							fallback = function(message)
								error(message)
							end,
						},
					})
				end
				local row = UI.HStack "Cards" { width = "fill" :: "fill", wrap = true, gap = "m", table.unpack(cells) }
				return UI.ScrollView {
					UI.VStack "Page" {
						width = "fill" :: "fill",
						gap = "m",
						row :: unknown,
						UI.Text "NextSection" { text = "Settings row" },
					} :: unknown,
					Host.UIScale { Scale = scale } :: unknown,
				}
			end, { size = Vector2.new(1100, 800) })
			local row = t.find(stage, "Cards")
			for _, width in { 1040, 280, 520 } do
				row.Size = UDim2.fromOffset(width, 0)
				t.settle(15)
				local where = `{ratio} ratio {scale} scale {width}px`
				for i = 1, 6 do
					local cell = t.find(row, `Cell{i}`)
					local button = cell:FindFirstChildWhichIsA("TextButton", true)
					local media = t.find(button, "Media")
					t.near(where .. ` image {i} aspect`, media.AbsoluteSize.X / media.AbsoluteSize.Y, ratio, 0.02)
					t.inside(where .. ` button {i} inside its cell`, t.rect(button), cell, 1)
					t.inside(where .. ` cell {i} inside its row`, t.rect(cell), row, 1)
					if i > 1 then
						local previous = t.rect(t.find(row, `Cell{i - 1}`))
						local current = t.rect(cell)
						t.check(
							where .. ` cell {i} clear of previous`,
							current.x >= previous.r or current.y >= previous.b - 1
						)
					end
				end
				t.check(where .. " next section below row", t.rect(t.find(stage, "NextSection")).y >= t.rect(row).b)
			end
			t.cleanup()
		end
	end
end)

add("travel-scroll-keeps-the-current-destination", { "UI.Travel" }, function(t)
	for _, clipped in { false, true } do
		for _, motion in { "ease", "spring" } do
			local destination: typeof(require("@repo/tools/typecheck/aliases").ZoomDestinationCell)
			local source: Frame
			local target: Frame
			local carrier: Frame
			local anchor: Frame
			local starts, lands = 0, 0
			local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, C: ComposeModule)
				source = Host.Frame {
					Position = UDim2.fromOffset(20, 140),
					Size = UDim2.fromOffset(48, 48),
					ClipsDescendants = clipped,
				}
				target = Host.Frame {
					Position = UDim2.fromOffset(260, 300),
					Size = UDim2.fromOffset(60, 60),
					ClipsDescendants = clipped,
				}
				destination = C.cell(source :: GuiObject)
				anchor = UI.Travel {
					destination = destination,
					path = "arc" :: "arc",
					motion = motion :: "ease" | "spring",
					lift = true,
					onStarted = function()
						starts += 1
					end,
					onLanded = function()
						lands += 1
					end,
					content = function(): GuiObject
						carrier = Host.Frame {}
						return carrier
					end,
				}
				return Host.ScrollingFrame {
					Name = "TravelScroll",
					Size = UDim2.fromOffset(400, 320),
					CanvasSize = UDim2.fromOffset(400, 900),
					BorderSizePixel = 0,
					source :: unknown,
					target,
					anchor,
					Host.UIScale { Scale = 1.25 },
				}
			end, { motionLevel = "normal", frames = 15 })
			local scroll = t.find(stage, "TravelScroll") :: ScrollingFrame
			local where = `{motion} clipped={clipped}`
			local function resting(slot: Frame)
				t.check(
					where .. " carrier stays at its slot",
					(carrier.AbsolutePosition - slot.AbsolutePosition).Magnitude <= 1
				)
				t.check(where .. " carrier keeps slot size", (carrier.AbsoluteSize - slot.AbsoluteSize).Magnitude <= 1)
				t.check(where .. " no resting flight", anchor:GetAttribute("FacetTravelMoving") == false)
				t.near(where .. " no resting lift", (carrier:FindFirstChild("TravelLift") :: UIScale).Scale, 1, 0.001)
			end
			for _, offset in { 40, 80, 20 } do
				scroll.CanvasPosition = Vector2.new(0, offset)
				t.settle(3)
				resting(source)
			end
			source.Position = UDim2.fromOffset(40, 160)
			source.Size = UDim2.fromOffset(64, 56)
			t.settle(3)
			resting(source)
			t.check(
				where .. " resting geometry starts no trips",
				starts == 0 and lands == 1,
				{ starts = starts, lands = lands }
			)
			destination:set(target)
			for offset = 21, 60 do
				scroll.CanvasPosition = Vector2.new(0, offset)
				t.settle(1)
			end
			t.settle(90)
			resting(target)
			t.check(
				where .. " scrolling does not restart the trip",
				starts == 1 and lands == 2,
				{ starts = starts, lands = lands }
			)
			destination:set(source)
			t.settle(3)
			destination:set(target)
			t.settle(90)
			resting(target)
			t.check(
				where .. " explicit interruption still starts a trip",
				starts == 3 and lands == 3,
				{ starts = starts, lands = lands }
			)
			t.cleanup()
		end
	end
end)

return cases
