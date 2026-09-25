--!strict
local Players = game:GetService("Players")

local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function visibleNamed(t: any, root: Instance, name: string): any
	for _, node in root:GetDescendants() do
		if node.Name == name and node:IsA("GuiObject") and t.visible(node) then
			return node
		end
	end
	return nil
end

local function overlap(a: any, b: any): boolean
	local w = math.min(a.r, b.r) - math.max(a.x, b.x)
	local h = math.min(a.b, b.b) - math.max(a.y, b.y)
	return w > 0.5 and h > 0.5
end

local function scenario(t: any, name: string, size: Vector2?): (any, any)
	local built
	local stage = t.mount(function(UI, Host, Compose, env)
		built = t.scenario(name).build(t.context(UI, Host, Compose, env))
		return if type(built) == "function" then built() else built.screen()
	end, { size = size, frames = 16 })
	return stage, built
end

local function alertCase(t: any, where: string, size: Vector2, message: string, actions: { any }, theme: any?)
	local stage = t.mount(function(UI, _, Compose)
		return UI.Alert({
			isPresented = Compose.cell(true),
			title = "Replace the save?",
			message = message,
			actions = actions,
		})
	end, { size = size, theme = theme, frames = 4 })
	local panel = visibleNamed(t, stage, "AlertPanel")
	if not panel then
		t.check(where .. " alert shown", false)
		return nil
	end
	t.stable(panel)
	local p = t.rect(panel)
	t.inside(where .. " card inside the screen", p, stage, 1)
	local buttons = {}
	for _, node in panel:GetDescendants() do
		if node:IsA("GuiButton") and t.visible(node) and node.Name ~= "AlertMessage" then
			local scroller = node:FindFirstAncestorWhichIsA("ScrollingFrame")
			local r = t.rect(node)
			if scroller and scroller:IsDescendantOf(panel) then
				t.check(
					`{where} {node.Name} inside the card or its scroll region`,
					r.x >= p.x - 1 and r.r <= p.r + 1,
					r
				)
			else
				t.inside(`{where} {node.Name} inside the card`, r, p, 1)
			end
			table.insert(buttons, r)
		end
	end
	for i = 1, #buttons do
		for j = i + 1, #buttons do
			t.check(
				`{where} actions {i} and {j} do not overlap`,
				not overlap(buttons[i], buttons[j]),
				{ buttons[i], buttons[j] }
			)
		end
	end
	return panel
end

add("alert-actions-inside-card", { "navigation-1-18" }, function(t)
	local long = string.rep("Your changes to this slot are not saved yet. ", 40)
	local panel = alertCase(t, "640x320 long", Vector2.new(640, 320), long, {
		{ id = "cancel", label = "Cancel", role = "cancel" },
		{ id = "continue", label = "Continue" },
	})
	local message = panel and t.find(panel, "AlertMessage")
	if message and message:IsA("ScrollingFrame") then
		t.check("long message scrolls", message.AbsoluteCanvasSize.Y > message.AbsoluteWindowSize.Y, {
			canvas = message.AbsoluteCanvasSize,
			window = message.AbsoluteWindowSize,
		})
	end
	t.cleanup()
	panel = alertCase(t, "749x235 short", Vector2.new(749, 235), "The older save is lost.", {
		{ id = "keep", label = "Keep previous", role = "cancel" },
		{ id = "replace", label = "Replace save", role = "destructive" },
	})
	message = panel and t.find(panel, "AlertMessage")
	if message and message:IsA("ScrollingFrame") then
		t.check("short message does not scroll", message.AbsoluteCanvasSize.Y <= message.AbsoluteWindowSize.Y + 0.5, {
			canvas = message.AbsoluteCanvasSize,
			window = message.AbsoluteWindowSize,
		})
	end
end)

add("alert-themes-and-viewports", { "navigation-1-17" }, function(t)
	for _, theme in t.themes do
		for _, size in { Vector2.new(375, 667), Vector2.new(667, 375), Vector2.new(1280, 720) } do
			alertCase(t, `{theme.name} {size.X}x{size.Y}`, size, string.rep("Leave the match now? ", 6), {
				{ id = "stay", label = "Stay", role = "cancel" },
				{ id = "save", label = "Save and leave" },
				{ id = "leave", label = "Leave without saving", role = "destructive" },
			}, theme.package)
			t.cleanup()
		end
	end
	t.note("preferred text size", t.environment.preferredTextSize)
end)

add("disclosure-description-header", { "navigation-2-17" }, function(t)
	local description
	local stage = t.mount(function(UI, Host, Compose)
		description = Compose.cell("Configure the current race")
		return Host.Frame "Column" {
			Size = UDim2.fromOffset(390, 400),
			BackgroundTransparency = 1,
			Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
			UI.DisclosureGroup "With" {
				LayoutOrder = 1,
				label = "Details",
				description = description,
				chevronPosition = "trailing",
				appearance = "contained",
				expanded = Compose.cell(false),
				content = function()
					return UI.Text({ text = "Body" })
				end,
			},
			UI.DisclosureGroup "Without" {
				LayoutOrder = 2,
				label = "Details",
				chevronPosition = "trailing",
				appearance = "contained",
				expanded = Compose.cell(false),
				content = function()
					return UI.Text({ text = "Body" })
				end,
			},
		}
	end, { size = Vector2.new(390, 400) })
	local with, without = t.find(stage, "With"), t.find(stage, "Without")
	local hw, hn = t.find(with, "Header"), t.find(without, "Header")
	t.check("header with a description is taller", hw.AbsoluteSize.Y > hn.AbsoluteSize.Y, {
		with = hw.AbsoluteSize.Y,
		without = hn.AbsoluteSize.Y,
	})
	t.note("header without description", hn.AbsoluteSize.Y)
	local function inside(where: string)
		for _, name in { "Title", "Description" } do
			local node = t.find(hw, name)
			if node then
				t.inside(`{where} {name} inside the header`, node, hw, 1)
			else
				t.check(`{where} {name} found`, false)
			end
		end
	end
	inside("short")
	description:set("Configure the current race, the weather and the number of laps for every driver")
	t.settle(8)
	inside("long")
end)

add("toggle-sizes-around-label", { "mech3-14" }, function(t)
	for _, theme in t.themes do
		for _, presentation in { "switch", "checkbox" } do
			for _, position in { "leading", "trailing" } do
				local label
				local stage = t.mount(function(UI, _, Compose)
					label = Compose.cell("Rain")
					return UI.Toggle "Toggle" {
						label = label,
						value = Compose.cell(true),
						presentation = presentation,
						indicatorPosition = position,
					}
				end, { theme = theme.package, size = Vector2.new(600, 200) })
				local where = `{theme.name} {presentation} {position}`
				local toggle = t.find(stage, "Toggle")
				local indicator = t.find(toggle, "Indicator")
				t.stable(toggle)
				local before, bounds = toggle.AbsoluteSize.X, toggle.TextBounds.X
				if indicator then
					local i, g = t.rect(indicator), t.rect(toggle)
					t.inside(where .. " indicator inside the toggle", i, g, 1)
					t.check(where .. " toggle wider than label and indicator", g.w >= bounds + i.w + 8 - 1, {
						toggle = g.w,
						text = bounds,
						indicator = i.w,
					})
				else
					t.check(where .. " indicator found", false)
				end
				label:set("Night vision assistance")
				t.stable(toggle)
				local grown = t.rect(toggle)
				local mark = if indicator then t.rect(indicator) else nil
				t.check(
					where .. " toggle grows with the longer label",
					grown.w > before,
					{ before = before, after = grown.w }
				)
				if mark then
					t.inside(where .. " indicator inside the grown toggle", mark, grown, 1)
					t.check(
						where .. " grown toggle holds the label and the indicator",
						grown.w >= toggle.TextBounds.X + mark.w + 8 - 1,
						{ toggle = grown.w, text = toggle.TextBounds.X, indicator = mark.w }
					)
				end
				t.check(where .. " longer label fits", t.fits(toggle), toggle.TextBounds)
				t.cleanup()
			end
		end
	end
end)

add("step-and-clear-targets", { "mech1-88" }, function(t)
	for _, theme in t.themes do
		local stage = t.mount(function(UI, Host, Compose)
			return Host.Frame "Column" {
				Size = UDim2.fromOffset(360, 300),
				BackgroundTransparency = 1,
				Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
				UI.Stepper "Stepper" { value = Compose.cell(2), max = 5, LayoutOrder = 1 },
				UI.TextInput "Search" {
					value = Compose.cell("racers"),
					clearButton = true,
					clearButtonMode = "always",
					LayoutOrder = 2,
				},
			}
		end, { theme = theme.package, size = Vector2.new(360, 300) })
		for _, name in { "Decrease", "Increase", "Clear" } do
			local node = visibleNamed(t, stage, name)
			if node then
				t.check(`{theme.name} {name} at least 44 px high`, node.AbsoluteSize.Y >= 43.5, node.AbsoluteSize)
			else
				t.check(`{theme.name} {name} found`, false)
			end
		end
		t.cleanup()
	end
end)

add("picker-long-labels", { "apps-237" }, function(t)
	local sets = {
		long = {
			{ value = "a", label = "Automatic transmission mode" },
			{ value = "b", label = "Manual transmission override" },
			{ value = "c", label = "Sequential paddle shift gear" },
			{ value = "d", label = "Assisted launch control mode" },
		},
		short = {
			{ value = "a", label = "Auto" },
			{ value = "b", label = "Manual" },
			{ value = "c", label = "Paddle" },
			{ value = "d", label = "Launch" },
		},
	}
	for name, options in sets do
		for _, width in { 360, 380, 400 } do
			local stage = t.mount(function(UI, _, Compose)
				return UI.Picker "Auto" {
					selected = Compose.cell("a"),
					Size = UDim2.fromOffset(width, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					options = options,
				}
			end, { size = Vector2.new(width, 300) })
			local picker = t.find(stage, "Auto")
			t.stable(picker)
			local presentation = picker:FindFirstChild("Presentation")
			local segmented = presentation ~= nil and presentation:HasTag("facet-segmented")
			local clipped, labels = 0, 0
			for _, node in picker:GetDescendants() do
				if (node:IsA("TextButton") or node:IsA("TextLabel")) and t.visible(node) and node.Text ~= "" then
					labels += 1
					if not t.fits(node) then
						clipped += 1
					end
				end
			end
			t.note(`{name} {width} segmented`, segmented)
			t.check(
				`{name} {width} no label clips`,
				clipped == 0 and labels > 0,
				{ clipped = clipped, labels = labels }
			)
			t.check(
				`{name} {width} presentation follows the label fit`,
				segmented == (name == "short"),
				{ segmented = segmented }
			)
			t.inside(`{name} {width} picker inside its width`, picker, stage, 1)
			t.cleanup()
		end
	end
end)

add("toast-wide-and-fit", { "apps2-247", "mech3-87" }, function(t)
	local stage, built = scenario(t, "sponsor_toast", Vector2.new(390, 700))
	built.width:set("fill")
	built.show("Supply drop", "A sponsor sent a crate to the garage.")
	t.settle(30)
	local toast = visibleNamed(t, stage, "Toast")
	if toast then
		local title = t.find(toast, "Title")
		t.check("wide toast is wider than 200 px", toast.AbsoluteSize.X > 200, toast.AbsoluteSize)
		t.check(
			"wide toast title is wider than 50 px",
			title ~= nil and title.AbsoluteSize.X > 50,
			title and title.AbsoluteSize
		)
	else
		t.check("wide toast shown", false)
	end
	built.dismiss()
	t.settle(30)
	built.width:set("hug")
	built.show("Saved", "")
	t.settle(30)
	local short = visibleNamed(t, stage, "Toast")
	local shortRect = short and t.rect(short)
	built.show("A very long sponsor message", string.rep("The crate holds tyres, fuel and a new livery. ", 4))
	t.settle(30)
	local strip = t.find(stage, "Messages")
	local toasts = {}
	for _, node in stage:GetDescendants() do
		if node.Name == "Toast" and node:IsA("GuiObject") and t.visible(node) then
			table.insert(toasts, t.rect(node))
		end
	end
	if strip and #toasts >= 2 then
		local s = t.rect(strip)
		for index, r in toasts do
			t.near(`fit toast {index} centred on the strip`, r.x + r.w / 2, s.x + s.w / 2, 1)
			t.check(`fit toast {index} at most 560 wide`, r.w <= 560.5, r.w)
		end
		table.sort(toasts, function(a, b)
			return a.w < b.w
		end)
		t.check(
			"long toast is taller than the short one",
			toasts[#toasts].h > toasts[1].h,
			{ toasts[1].h, toasts[#toasts].h }
		)
	else
		t.check("strip and two fit toasts found", false, { strip = strip ~= nil, toasts = #toasts, short = shortRect })
	end
end)

add("text-degrade-sort-label", { "apps2-63" }, function(t)
	local stage, built = scenario(t, "text_degrade", Vector2.new(600, 700))
	for _, stop in { "roomy", "snug", "tight", "impossible" } do
		built.steps.setStop(built, stop)
		t.settle(10)
		local sort = visibleNamed(t, stage, "Sort")
		if not sort then
			t.check(stop .. " Sort found", false)
			continue
		end
		local text = if sort:IsA("TextButton") then sort.ContentText else sort.Text
		t.note(
			stop .. " Sort",
			{ text = text, fits = sort.TextFits, size = sort.AbsoluteSize, bounds = sort.TextBounds }
		)
		t.check(
			stop .. " Sort text fits",
			t.fits(sort),
			{ text = text, bounds = sort.TextBounds, size = sort.AbsoluteSize }
		)
		if stop == "roomy" then
			t.check("roomy shows the full word", text == "Sorting", text)
		end
	end
end)

add("compact-label-single-line", { "inputs-63" }, function(t)
	local width
	local stage = t.mount(function(UI, Host, Compose)
		width = Compose.cell(300)
		return Host.Frame "Box" {
			Size = function(use)
				return UDim2.fromOffset(use(width), 60)
			end,
			BackgroundTransparency = 1,
			Host.UIListLayout({ FillDirection = Enum.FillDirection.Horizontal }),
			UI.Button "Go" {
				label = "Continue to checkout",
				compactLabel = "Continue",
				Host.UIFlexItem({ FlexMode = Enum.UIFlexMode.Fill }),
			},
		}
	end, { size = Vector2.new(400, 200) })
	local button = t.find(stage, "Go")
	local lineHeight: number? = nil
	local labels = {}
	for w = 300, 90, -15 do
		width:set(w)
		t.settle(2)
		local caption = if button:IsA("TextButton") then button else button:FindFirstChildWhichIsA("TextLabel", true)
		lineHeight = lineHeight or caption.TextBounds.Y
		labels[caption.ContentText] = true
		t.check(
			`{w} caption does not wrap`,
			(caption :: any):GetStyled("TextWrapped") == false,
			(caption :: any):GetStyled("TextWrapped")
		)
		t.near(`{w} caption is one line`, caption.TextBounds.Y, lineHeight :: number, 1)
	end
	t.check("the compact label appears", labels["Continue"] == true, labels)
end)

add("progress-skin-under-scale", { "themes-P5-38" }, function(t)
	local packages = {}
	for _, theme in t.themes do
		local chrome = theme.package.chrome
		if chrome and chrome.barFill then
			table.insert(packages, theme)
		end
	end
	t.note("packages with barFill art", #packages)
	for _, theme in packages do
		for _, factor in { 2, 0.5 } do
			local stage = t.mount(function(UI, Host)
				return Host.Frame "Scaled" {
					Size = UDim2.fromOffset(200, 60),
					BackgroundTransparency = 1,
					Host.UIScale({ Scale = factor }),
					UI.ProgressView "Bar" { value = 0.5, Size = UDim2.fromOffset(180, 12) },
				}
			end, { theme = theme.package, size = Vector2.new(500, 300) })
			local fill = t.find(stage, "Fill1")
			local boundary = fill and t.find(fill, "SkinBoundary")
			local where = `{theme.name} x{factor}`
			if not (fill and boundary) then
				t.check(where .. " fill art found", false)
				t.cleanup()
				continue
			end
			local bounds = t.find(boundary, "SkinBounds") or boundary:FindFirstChildWhichIsA("GuiObject", true)
			t.near(where .. " boundary is one scaled pixel", boundary.AbsoluteSize.X, factor, 0.05)
			if bounds then
				t.near(where .. " art covers the painted fill", bounds.AbsoluteSize.X, fill.AbsoluteSize.X, 1)
			end
			t.cleanup()
		end
	end
	t.check("at least one package has barFill art", #packages > 0, #packages)
end)

add("skinned-checkbox-stroke", { "themes-P2-22" }, function(t)
	local neutral = t.Facet.themes.neutralPackage()
	neutral.assets = neutral.assets or {}
	neutral.assets.boxArt = { content = "rbxasset://textures/ui/GuiImagePlaceholder.png" }
	neutral.chrome = neutral.chrome or {}
	neutral.chrome.toggleTrack = { kind = "nineSlice", asset = "boxArt" }
	neutral.chrome.panel = { kind = "nineSlice", asset = "boxArt" }
	local skinned = assert(t.Facet.themes.define(neutral))
	local function rules(stage: Instance): { [string]: StyleRule }
		local found = {}
		local gui = stage:FindFirstAncestorWhichIsA("LayerCollector")
		local sheet = gui and gui:FindFirstChildWhichIsA("StyleSheet")
		for _, node in if sheet then sheet:GetDescendants() else {} do
			if node:IsA("StyleRule") then
				found[node.Selector] = node
			end
		end
		return found
	end
	for _, entry in
		{
			{ name = "skinned", package = skinned, hidden = true },
			{ name = "plain", package = t.themes[1].package, hidden = false },
		}
	do
		local stage = t.mount(function(UI, Host, Compose)
			return Host.Frame {
				Size = UDim2.fromOffset(400, 300),
				BackgroundTransparency = 1,
				Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
				UI.Toggle "Box" { value = Compose.cell(true), label = "Box", presentation = "checkbox" },
				UI.Menu "Actions" {
					label = "Actions",
					isPresented = Compose.cell(true),
					items = { { id = "a", label = "Archive", onSelect = function() end } },
				},
			}
		end, { theme = entry.package, size = Vector2.new(400, 300), frames = 20 })
		local indicator = t.find(stage, "Indicator")
		local found = rules(stage)
		local base = found[".facet-toggle-checkbox::UIStroke"]
		local over = found[".facet-toggle-checkbox.facet-skinned::UIStroke"]
		local menuOver = found[".facet-menu.facet-skinned::UIStroke"]
		t.check(entry.name .. " checkbox indicator found", indicator ~= nil)
		t.check(
			entry.name .. " base stroke rule shows an outline",
			base ~= nil and (base:GetProperty("Transparency") :: number) < 1,
			base and base:GetProperties()
		)
		t.check(
			entry.name .. " skinned stroke rule hides the outline at a higher priority",
			base ~= nil and over ~= nil and over.Priority > base.Priority and over:GetProperty("Transparency") == 1,
			{ base = base and base.Priority, skinned = over and over.Priority }
		)
		t.check(
			entry.name .. " skinned menu stroke rule hides the hairline",
			menuOver ~= nil and menuOver:GetProperty("Transparency") == 1
		)
		if indicator then
			t.check(
				entry.name .. " indicator carries the checkbox tag",
				indicator:HasTag("facet-toggle-checkbox"),
				indicator:GetTags()
			)
			t.check(
				entry.name .. " indicator is skinned only with art",
				indicator:HasTag("facet-skinned") == entry.hidden,
				indicator:GetTags()
			)
		end
		local panel
		for _, node in stage:GetDescendants() do
			if node:IsA("GuiObject") and node:HasTag("facet-menu") and t.visible(node) then
				panel = node
			end
		end
		t.check(
			entry.name .. " open menu panel is skinned only with art",
			panel ~= nil and panel:HasTag("facet-skinned") == entry.hidden,
			panel and panel:GetTags()
		)
		t.cleanup()
	end
end)

add("playlist-and-grid-panes", { "apps2-231", "apps2-57" }, function(t)
	local stage, built = scenario(t, "virtual_grid", Vector2.new(1000, 700))
	local collection = t.find(stage, "Collection")
	if collection then
		t.near("grid window equals its pane", collection.AbsoluteWindowSize.Y, collection.AbsoluteSize.Y, 1)
		local before = built.report().status.first
		collection.CanvasPosition = Vector2.new(0, 1800)
		t.settle(10)
		local status = built.report().status
		t.check(
			"status.first changes after an 1800 px scroll",
			status.first ~= before,
			{ before = before, after = status.first }
		)
		t.check("retained stays under 100", status.retained < 100, status.retained)
	else
		t.check("grid found", false)
	end
	t.cleanup()
	local page, extents = scenario(t, "variable_extents", Vector2.new(320, 640))
	local list = t.find(page, "Collection")
	local function hosts()
		local out = {}
		for _, node in list:GetDescendants() do
			local key = string.match(node.Name, "^Post_(.+)$")
			if key and node:IsA("GuiObject") and t.visible(node) then
				table.insert(out, { post = node, host = node.Parent })
			end
		end
		return out
	end
	local variable = hosts()
	for index, entry in variable do
		t.check(
			`variable post {index} fits its row host`,
			entry.post.AbsoluteSize.Y <= entry.host.AbsoluteSize.Y + 0.5,
			{
				post = entry.post.AbsoluteSize.Y,
				host = entry.host.AbsoluteSize.Y,
			}
		)
	end
	table.sort(variable, function(a, b)
		return a.host.AbsolutePosition.Y < b.host.AbsolutePosition.Y
	end)
	for index = 2, #variable do
		local previous, current = variable[index - 1].host, variable[index].host
		t.check(
			`variable row hosts {index - 1} and {index} do not overlap`,
			previous.AbsolutePosition.Y + previous.AbsoluteSize.Y <= current.AbsolutePosition.Y + 0.5,
			index
		)
	end
	local report = extents.report()
	t.note("variable mode", report.variable)
	t.check("variable rows found", #variable > 0, #variable)
end)

return cases
