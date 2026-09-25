--!strict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function interactive(
	id: string,
	contracts: { string },
	setup: (any) -> any,
	steps: { [string]: (any, any) -> () }
)
	table.insert(cases, { id = id, contracts = contracts, setup = setup, steps = steps })
end

local SHIPPED = {
	"Neutral",
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}

local OFFSETS = { 0, 4, 10, 14 }

local PSEUDO = "Şéţţíñĝş áñð áúðíó óþţíóñş ·········"
local PSEUDO_ACTION = "Şáṽé çĥáñĝéş ····"
local PSEUDO_SECONDARY = "Ñóţ ñóŵ ··"
local CJK = "速度制限標識と設定画面"
local EMOJI = "e\u{0301} 😀 👨\u{200D}👩\u{200D}👧"
local MIXED = `{CJK} {EMOJI} {PSEUDO_ACTION}`

local function shipped(t: any): { { name: string, package: any } }
	local out = {}
	for _, name in SHIPPED do
		for _, entry in t.themes do
			if entry.name == name then
				table.insert(out, entry)
			end
		end
	end
	return out
end

local function themeNamed(t: any, name: string): any
	for _, entry in t.themes do
		if entry.name == name then
			return entry.package
		end
	end
	return nil
end

local function grown(t: any, base: any, offset: number): any
	if offset == 0 then
		return base
	end
	local typography = {}
	for _, role in t.Facet.themes.TYPE_ROLES do
		local entry = base.metrics.typography[role]
		if entry then
			typography[role] = { size = entry.size + offset, font = entry.font, lineHeight = entry.lineHeight }
		end
	end
	local package, report = t.Facet.themes.define({
		base = base,
		identity = { id = `{base.identity.id}-plus-{offset}` },
		metrics = { typography = typography },
	})
	assert(package, report and report.errors and report.errors[1] and report.errors[1].message)
	return package
end

local function selectedName(): string
	local selected = GuiService.SelectedObject
	return if selected then selected.Name else "nil"
end

local function within(node: Instance?, name: string): boolean
	local at = node
	while at do
		if at.Name == name then
			return true
		end
		at = at.Parent
	end
	return false
end

local function watchSelection(value: any)
	value.visited = {}
	value.connection = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local selected = GuiService.SelectedObject
		table.insert(value.visited, selected or false)
	end)
end

local function visitedNames(value: any): { string }
	local names = {}
	for _, node in value.visited do
		table.insert(names, if node then node.Name else "nil")
	end
	return names
end

local function traversals(): { Instance }
	local out = {}
	for _, node in Players.LocalPlayer.PlayerGui:GetChildren() do
		if node:IsA("InputContext") and node.Name == "FacetTraversal" then
			table.insert(out, node)
		end
	end
	return out
end

local function newTraversal(before: { Instance }): any
	for _, node in traversals() do
		if not table.find(before, node) then
			return node:FindFirstChild("Traverse")
		end
	end
	return nil
end

local function tab(t: any, action: any)
	action:Fire(true)
	action:Fire(false)
	t.settle(3)
end

local function ordered(parent: Instance): { Instance }
	local children = parent:GetChildren()
	local sorted = false
	for _, child in children do
		if child:IsA("UIGridStyleLayout") and child.SortOrder == Enum.SortOrder.LayoutOrder then
			sorted = true
		end
	end
	if not sorted then
		return children
	end
	local index = {}
	for position, child in children do
		index[child] = position
	end
	table.sort(children, function(a, b)
		local left = if a:IsA("GuiObject") then a.LayoutOrder else 0
		local right = if b:IsA("GuiObject") then b.LayoutOrder else 0
		if left ~= right then
			return left < right
		end
		return index[a] < index[b]
	end)
	return children
end

local function stops(root: Instance, into: { string }, rects: boolean)
	if root:IsA("GuiObject") then
		if not root.Visible or not root.Interactable then
			return
		end
		if root.Selectable then
			local a, s = root.AbsolutePosition, root.AbsoluteSize
			table.insert(
				into,
				if rects then string.format("%s@%d,%d,%dx%d", root.Name, a.X, a.Y, s.X, s.Y) else root.Name
			)
		end
	end
	for _, child in ordered(root) do
		stops(child, into, rects)
	end
end

local function bindings(root: Instance): string
	local contexts, actions, keys = 0, 0, {}
	for _, node in root:GetDescendants() do
		if node:IsA("InputContext") and node.Enabled then
			contexts += 1
		elseif node:IsA("InputAction") and node.Enabled then
			actions += 1
		elseif node:IsA("InputBinding") then
			table.insert(keys, node.KeyCode.Name)
		end
	end
	table.sort(keys)
	return `contexts={contexts} actions={actions} keys={table.concat(keys, ",")} traversal={#traversals()}`
end

local function scenario(t: any, name: string, size: any, options: { [string]: any }?): (any, any)
	local built
	local config = options or {}
	local stage = t.mount(function(UI, Host, Compose, env)
		built = t.scenario(name).build(t.context(UI, Host, Compose, env))
		return if type(built) == "function" then built() else built.screen()
	end, { size = size, theme = config.theme, frames = config.frames or 20 })
	return stage, built
end

local function button(UI: any, name: string, label: string?): any
	return UI.Button(name)({ label = label or name })
end

interactive("chrome-strips-dpad", { "apps-151" }, function(t)
	local value = {}
	local stage = t.mount(function(UI)
		return UI.Screen "Page" {
			gap = "m",
			UI.HStack "Bar" { gap = "s", button(UI, "Left"), button(UI, "Right") },
			button(UI, "A", "Content A"),
			button(UI, "B", "Content B"),
			UI.HStack "Foot" { gap = "s", button(UI, "FootLeft", "Left"), button(UI, "FootRight", "Right") },
		}
	end, { size = Vector2.new(900, 600), frames = 12 })
	value.stage = stage
	GuiService.SelectedObject = t.find(stage, "A")
	t.settle(2)
	t.check("content A holds the selection at the start", selectedName() == "A", selectedName())
	return value
end, {
	afterUp = function(t)
		t.check("Up from the first content row lands on the top strip", selectedName() == "Left", selectedName())
	end,
	afterRight = function(t)
		t.check("Right walks along the strip", selectedName() == "Right", selectedName())
	end,
	afterLeft = function(t)
		t.check("Left walks back along the strip", selectedName() == "Left", selectedName())
	end,
	afterDown = function(t)
		t.check("Down from the first chip leaves the strip for the content", selectedName() == "A", selectedName())
	end,
	afterDown2 = function(t)
		t.check("Down walks the content", selectedName() == "B", selectedName())
	end,
	afterDown3 = function(t)
		t.check(
			"Down off the end of the content reaches the bottom strip",
			selectedName() == "FootLeft",
			selectedName()
		)
	end,
	afterRight2 = function(t)
		t.check("Right walks along the bottom strip", selectedName() == "FootRight", selectedName())
		GuiService.SelectedObject = nil
	end,
})

add("tab-scrolls-host-to-selection", { "apps-161" }, function(t)
	local before = traversals()
	local stage = t.mount(function(UI)
		local rows = {}
		for index = 1, 12 do
			rows[index] = UI.Button({
				Name = "Btn" .. index,
				label = "Row " .. index,
				Size = UDim2.new(1, 0, 0, 40),
				AutomaticSize = Enum.AutomaticSize.None,
			})
		end
		return UI.Screen "S" {
			UI.ScrollView "List" { height = 160, width = 300, table.unpack(rows) },
		}
	end, { size = Vector2.new(400, 300), frames = 12 })
	local action = newTraversal(before)
	t.check("the mount owns a Tab traversal action", action ~= nil)
	if not action then
		return
	end
	local list = t.find(stage, "List")
	GuiService.SelectedObject = t.find(stage, "Btn1")
	t.settle(2)
	t.near("the list starts unscrolled", list.CanvasPosition.Y, 0, 0.5)
	local outside = {}
	for press = 1, 8 do
		tab(t, action)
		t.settle(4)
		local selected = GuiService.SelectedObject
		local expected = "Btn" .. (press + 1)
		t.check(`Tab {press} selects {expected}`, selectedName() == expected, selectedName())
		if selected then
			local s, w = t.rect(selected), t.rect(list)
			if s.y < w.y - 0.5 or s.b > w.b + 0.5 then
				table.insert(outside, { selected.Name, s.y, s.b, w.y, w.b })
			end
		end
	end
	t.check("every Tab stop lies fully inside the scroll window", #outside == 0, outside)
	t.check("the host scrolled to keep focus visible", list.CanvasPosition.Y > 0, list.CanvasPosition)
	t.note("canvas after eight Tabs", list.CanvasPosition)
	GuiService.SelectedObject = nil
end)

add("slider-selection-ring-on-track", { "apps-166" }, function(t)
	local stage = t.mount(function(UI, _, Compose)
		return UI.Screen "S" {
			UI.Button "Before" { label = "Before" },
			UI.Slider "Vol" {
				label = "Volume",
				value = Compose.cell(0.5),
				min = 0,
				max = 1,
				step = 0.1,
				Size = UDim2.fromOffset(360, 0),
			},
		}
	end, { size = Vector2.new(600, 300), frames = 12 })
	local track, thumb, before = t.find(stage, "Track"), t.find(stage, "Thumb"), t.find(stage, "Before")
	t.check("the slider has a track and a thumb", track ~= nil and thumb ~= nil)
	if not (track and thumb) then
		return
	end
	t.check("the track is the selection stop", track.Selectable == true)
	local extra = {}
	for _, node in t.find(stage, "Vol"):GetDescendants() do
		if node:IsA("GuiObject") and node.Selectable and node ~= track then
			table.insert(extra, node.Name)
		end
	end
	t.check("no other part of the slider is a stop", #extra == 0, extra)
	local custom = {}
	local at: Instance? = track
	while at do
		if at:IsA("GuiObject") and at.SelectionImageObject ~= nil then
			table.insert(custom, at.Name)
		end
		at = at.Parent
	end
	t.check("the track and its ancestors keep the engine selection ring", #custom == 0, custom)
	t.check(
		"the Button and the slider draw the same engine ring",
		before.SelectionImageObject == nil and track.SelectionImageObject == nil
	)
	GuiService.SelectedObject = before
	t.settle(2)
	GuiService.SelectedObject = track
	t.settle(4)
	t.check("the selection lands on the track", GuiService.SelectedObject == track, selectedName())
	local tr, th = t.rect(track), t.rect(thumb)
	t.check(
		"the ring around the track encloses the thumb vertically",
		th.y >= tr.y - 0.5 and th.b <= tr.b + 0.5,
		{ thumb = { th.y, th.b }, track = { tr.y, tr.b } }
	)
	t.check("the track is a full 44 px target", track.AbsoluteSize.Y >= 43.5, track.AbsoluteSize)
	t.check("the thumb is visible while the track holds the selection", t.visible(thumb))
	GuiService.SelectedObject = before
	t.settle(2)
	t.check("the selection leaves the track", GuiService.SelectedObject == before, selectedName())
	GuiService.SelectedObject = nil
end)

interactive("form-controls-reach-by-arrows", { "apps-192" }, function(t)
	local value = {}
	local stage = scenario(t, "selection_controls", Vector2.new(900, 700))
	value.stage = stage
	GuiService.SelectedObject = t.find(stage, "Reset")
	t.settle(2)
	t.check("Reset holds the selection at the start", selectedName() == "Reset", selectedName())
	watchSelection(value)
	return value
end, {
	afterDowns = function(t, value)
		value.connection:Disconnect()
		local checkbox, join = false, false
		for _, node in value.visited do
			if node then
				checkbox = checkbox or within(node, "Checkbox")
				join = join or within(node, "Join")
			end
		end
		t.note("Down visits", visitedNames(value))
		t.check("Down reaches the checkbox", checkbox, visitedNames(value))
		t.check("Down reaches the Join button", join, visitedNames(value))
		GuiService.SelectedObject = nil
	end,
})

interactive("slider-between-controls-by-arrows", { "apps-192" }, function(t)
	local value = {}
	local stage = t.mount(function(UI, _, Compose)
		return UI.Screen "S" {
			UI.HStack "VolumeRow" { gap = "s", button(UI, "Volume"), button(UI, "Mute") },
			UI.Slider "Brightness" {
				label = "Brightness",
				value = Compose.cell(40),
				min = 0,
				max = 100,
				Size = UDim2.fromOffset(400, 0),
			},
			UI.HStack "QualityRow" { gap = "s", button(UI, "Quality"), button(UI, "Apply") },
		}
	end, { size = Vector2.new(700, 400), frames = 12 })
	value.stage = stage
	local track, volume = t.find(stage, "Track"), t.find(stage, "Volume")
	t.note("track x range", { track.AbsolutePosition.X, track.AbsolutePosition.X + track.AbsoluteSize.X })
	t.note("Volume x range", { volume.AbsolutePosition.X, volume.AbsolutePosition.X + volume.AbsoluteSize.X })
	GuiService.SelectedObject = t.find(stage, "Mute")
	t.settle(2)
	return value
end, {
	afterDown = function(t, value)
		local selected = GuiService.SelectedObject
		t.check("Down from Mute reaches the Brightness track", within(selected, "Brightness"), selectedName())
		GuiService.SelectedObject = t.find(value.stage, "Apply")
		t.settle(2)
	end,
	afterUp = function(t, value)
		local selected = GuiService.SelectedObject
		t.check("Up from Apply reaches the Brightness track", within(selected, "Brightness"), selectedName())
		GuiService.SelectedObject = t.find(value.stage, "Volume")
		t.settle(2)
	end,
	afterVolumeDown = function(t)
		t.note("Down from Volume, left of the track column, selects", selectedName())
		GuiService.SelectedObject = nil
	end,
})

local LANDSCAPE, PORTRAIT = Vector2.new(844, 390), Vector2.new(390, 844)

add("hud-sequence-equals-fresh-mount", { "apps-211" }, function(t)
	local function census(stage: any, action: any): (string, string, string)
		local rects = {}
		stops(stage, rects, true)
		local ring = {}
		GuiService.SelectedObject = nil
		t.settle(2)
		local first
		for _ = 1, 60 do
			tab(t, action)
			local name = selectedName()
			if first == nil then
				first = name
			elseif name == first then
				break
			end
			table.insert(ring, name)
		end
		GuiService.SelectedObject = nil
		return table.concat(rects, " "), table.concat(ring, ","), bindings(stage:FindFirstAncestorWhichIsA("ScreenGui"))
	end
	local before = traversals()
	local fresh, freshBuilt = scenario(t, "hud", LANDSCAPE)
	local freshAction = newTraversal(before)
	t.check("the fresh mount owns a Tab traversal action", freshAction ~= nil)
	if not freshAction then
		return
	end
	t.stable(fresh)
	local wantRects, wantRing, wantBound = census(fresh, freshAction)
	t.check("the fresh ring has entries", #wantRing > 0, wantRing)
	t.note("fresh ring", wantRing)
	t.note("fresh bindings", wantBound)
	t.check("the fresh HUD reports landscape forms", freshBuilt.report().urlBar == false)
	t.cleanup()
	before = traversals()
	local size = t.Facet.Compose.cell(LANDSCAPE)
	local live, built = scenario(t, "hud", size)
	local action = newTraversal(before)
	t.stable(live)
	local startRects = {}
	stops(live, startRects, true)
	built.steps.openUrlBar()
	t.settle(6)
	size:set(PORTRAIT)
	t.stable(live)
	t.settle(10)
	local midRects = {}
	stops(live, midRects, true)
	t.near("the portrait leg is at the portrait width", live.AbsoluteSize.X, PORTRAIT.X, 0.5)
	t.check("the portrait leg differs from landscape", table.concat(midRects, " ") ~= table.concat(startRects, " "))
	built.steps.closeUrlBar()
	t.settle(6)
	size:set(LANDSCAPE)
	t.stable(live)
	t.settle(10)
	t.near("the restored leg is at the landscape width", live.AbsoluteSize.X, LANDSCAPE.X, 0.5)
	local gotRects, gotRing, gotBound = census(live, action)
	t.check("the selection stops and their rects equal the fresh mount", gotRects == wantRects, {
		got = gotRects,
		want = wantRects,
	})
	t.check("the Tab ring equals the fresh mount", gotRing == wantRing, { got = gotRing, want = wantRing })
	t.check("the input bindings equal the fresh mount", gotBound == wantBound, { got = gotBound, want = wantBound })
end)

local function hudDpad(size: Vector2)
	return function(t: any)
		local value = {}
		local stage, built = scenario(t, "hud", size)
		t.stable(stage)
		value.stage, value.built = stage, built
		value.health = built.report().health
		GuiService.SelectedObject = t.find(stage, "Tick")
		t.settle(2)
		t.check("Advance clock holds the selection at the start", selectedName() == "Tick", selectedName())
		watchSelection(value)
		return value
	end
end

local hudSteps = {
	afterWalk = function(t, value)
		local names = visitedNames(value)
		t.note("arrow visits", names)
		t.check("the arrows reach the HUD actions trigger", table.find(names, "HudActionsTrigger") ~= nil, names)
		t.check("the trigger holds the selection", selectedName() == "HudActionsTrigger", selectedName())
	end,
	afterOpen = function(t, value)
		local selected = GuiService.SelectedObject
		t.note("selected after Return", selectedName())
		t.check(
			"Return opens the menu with the selection on its first row",
			selected ~= nil and within(selected, "damage")
				or (selected ~= nil and string.find(selected.Name, "damage", 1, true) ~= nil),
			selectedName()
		)
	end,
	afterPick = function(t, value)
		value.connection:Disconnect()
		t.check(
			"Return on the first row takes damage",
			value.built.report().health < value.health,
			value.built.report().health
		)
		t.check("the selection returns to the trigger", selectedName() == "HudActionsTrigger", selectedName())
		GuiService.SelectedObject = nil
	end,
}

interactive("hud-dpad-reaches-actions-390", { "apps-222" }, hudDpad(Vector2.new(390, 844)), hudSteps)
interactive("hud-dpad-reaches-actions-1920", { "apps-222" }, hudDpad(Vector2.new(1920, 1080)), hudSteps)

local VIEWPORTS = { Vector2.new(390, 844), Vector2.new(667, 375) }

local function formScreen(UI: any, Compose: any): any
	return UI.Screen "S" {
		UI.ScrollView "Form" {
			gap = "s",
			UI.Label "Heading" { text = PSEUDO, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0) },
			UI.TextInput "Name" { value = Compose.cell(""), placeholder = PSEUDO, Size = UDim2.new(1, 0, 0, 44) },
			UI.Slider "Volume" { label = PSEUDO, value = Compose.cell(0.5), min = 0, max = 1, step = 0.1 },
			UI.TextInput "Email" {
				value = Compose.cell(""),
				placeholder = PSEUDO_SECONDARY,
				Size = UDim2.new(1, 0, 0, 44),
			},
			UI.Label "Note" { text = PSEUDO, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0) },
			UI.TextInput "City" {
				value = Compose.cell(""),
				placeholder = PSEUDO_SECONDARY,
				Size = UDim2.new(1, 0, 0, 44),
			},
			UI.TextInput "Team" {
				value = Compose.cell(""),
				placeholder = PSEUDO_SECONDARY,
				Size = UDim2.new(1, 0, 0, 44),
			},
			UI.Label "Terms" { text = PSEUDO, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0) },
			UI.Toggle "Sound" { label = PSEUDO, value = Compose.cell(true) },
			UI.HStack "Actions" {
				gap = "s",
				wrap = true,
				width = "fill",
				UI.Button "Save" { label = PSEUDO_ACTION, TextWrapped = true },
				UI.Button "Later" { label = PSEUDO_SECONDARY, TextWrapped = true },
			},
		},
	}
end

add("form-reflows-then-scrolls", { "apps-249" }, function(t)
	local scrolled = false
	for _, viewport in VIEWPORTS do
		for _, themeName in { "Neutral", "fantasy_parchment" } do
			local base = themeNamed(t, themeName)
			local previous, window = 0, nil
			for _, offset in OFFSETS do
				local where = `{viewport.X}x{viewport.Y} {themeName} +{offset}`
				local stage = t.mount(function(UI, _, Compose)
					return formScreen(UI, Compose)
				end, { size = viewport, theme = grown(t, base, offset), frames = 16 })
				local form = t.find(stage, "Form")
				t.stable(t.find(stage, "Later"))
				local found = t.offenders(stage, stage)
				t.check(`{where} no text is clipped`, #found.clipped == 0, found.clipped)
				t.check(`{where} nothing crosses a lateral edge`, #found.lateral == 0, found.lateral)
				for _, name in { "Save", "Later" } do
					local node = t.find(stage, name)
					t.check(`{where} {name} shows its whole label`, t.fits(node), {
						bounds = node.TextBounds,
						size = node.AbsoluteSize,
					})
					t.inside(`{where} {name} inside the form width`, {
						x = node.AbsolutePosition.X,
						y = 0,
						w = 0,
						h = 0,
						r = node.AbsolutePosition.X + node.AbsoluteSize.X,
						b = 0,
					}, {
						x = form.AbsolutePosition.X,
						y = 0,
						w = 0,
						h = 0,
						r = form.AbsolutePosition.X + form.AbsoluteWindowSize.X,
						b = 0,
					})
				end
				local content = form.AbsoluteCanvasSize.Y
				t.check(`{where} the content grows or holds`, content >= previous - 0.5, {
					previous = previous,
					now = content,
				})
				previous = content
				if window == nil then
					window = form.AbsoluteSize.Y
				else
					t.near(`{where} the form viewport keeps its height`, form.AbsoluteSize.Y, window, 0.5)
				end
				if content > form.AbsoluteWindowSize.Y + 0.5 then
					scrolled = true
				end
				t.cleanup()
			end
			t.check(`{viewport.X}x{viewport.Y} {themeName} the content grew`, previous > 0)
		end
	end
	t.check("at least one row needs to scroll, so the scroll rung is reached", scrolled)
end)

add("form-geometry-identical-under-reduced-motion", { "apps-249" }, function(t)
	for _, viewport in VIEWPORTS do
		for _, offset in { 0, 14 } do
			local package = grown(t, themeNamed(t, "Neutral"), offset)
			local shapes = {}
			for _, reduced in { false, true } do
				local stage = t.mount(function(UI, _, Compose)
					return formScreen(UI, Compose)
				end, { size = viewport, theme = package, reducedMotion = reduced, frames = 16 })
				t.stable(t.find(stage, "Later"))
				t.settle(30)
				local lines = {}
				for _, node in stage:GetDescendants() do
					if node:IsA("GuiObject") then
						table.insert(
							lines,
							string.format(
								"%s@%.1f,%.1f,%.1fx%.1f",
								node:GetFullName():sub(#stage:GetFullName() + 1),
								node.AbsolutePosition.X,
								node.AbsolutePosition.Y,
								node.AbsoluteSize.X,
								node.AbsoluteSize.Y
							)
						)
					end
				end
				table.sort(lines)
				table.insert(shapes, table.concat(lines, "\n"))
				t.cleanup()
			end
			t.check(
				`{viewport.X}x{viewport.Y} +{offset} every rect is identical with and without reduced motion`,
				shapes[1] == shapes[2] and #shapes[1] > 0
			)
		end
	end
end)

add("action-label-wraps-before-truncating", { "apps-255" }, function(t)
	local sawWrap = false
	for _, themeName in { "Neutral", "fantasy_parchment" } do
		local base = themeNamed(t, themeName)
		local last = 0
		for _, offset in OFFSETS do
			local where = `{themeName} +{offset}`
			local stage = t.mount(function(UI)
				return UI.Screen "S" {
					UI.Button "Go" {
						label = PSEUDO_ACTION,
						TextWrapped = true,
						Size = UDim2.fromOffset(150, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					},
				}
			end, { size = Vector2.new(390, 400), theme = grown(t, base, offset), frames = 12 })
			local go = t.find(stage, "Go")
			t.stable(go)
			t.near(`{where} the action keeps its 150 px width`, go.AbsoluteSize.X, 150, 0.5)
			t.check(`{where} the action shows its whole label`, go.TextFits and t.fits(go), {
				bounds = go.TextBounds,
				size = go.AbsoluteSize,
				fits = go.TextFits,
			})
			t.check(`{where} the box grows with the text`, go.AbsoluteSize.Y >= last - 0.5, {
				last = last,
				now = go.AbsoluteSize.Y,
			})
			local line = go.TextSize * 1.5
			if go.TextBounds.Y > line then
				sawWrap = true
			end
			last = go.AbsoluteSize.Y
			t.cleanup()
		end
	end
	t.check("the sweep reaches a wrapped action", sawWrap)
end)

add("fixed-px-action-draws-compact-form", { "apps-255" }, function(t)
	local base = themeNamed(t, "fantasy_parchment")
	local clipped = {}
	local once = false
	for _, offset in OFFSETS do
		local stage = t.mount(function(UI)
			return UI.Screen "S" {
				UI.Button "Save" {
					label = PSEUDO_ACTION,
					compactLabel = "OK",
					Size = UDim2.fromOffset(88, 44),
					AutomaticSize = Enum.AutomaticSize.None,
				},
			}
		end, { size = Vector2.new(390, 300), theme = grown(t, base, offset), frames = 12 })
		local save = t.find(stage, "Save")
		t.settle(6)
		t.check(`+{offset} the 88 px action draws the compact form`, save.ContentText == "OK", save.ContentText)
		local cut = not t.fits(save)
		t.check(`+{offset} a clip never recovers at a larger preference`, not (once and not cut), {
			bounds = save.TextBounds,
			size = save.AbsoluteSize,
		})
		once = once or cut
		if cut then
			table.insert(clipped, offset)
		end
		t.cleanup()
	end
	t.note("offsets where the fixed 88 px width clips the compact form", clipped)
end)

add("mixed-script-lines-grow-monotonically", { "apps-255" }, function(t)
	for _, themeName in { "Neutral", "fantasy_parchment" } do
		local base = themeNamed(t, themeName)
		local previous = {}
		for _, offset in OFFSETS do
			local where = `{themeName} +{offset}`
			local stage = t.mount(function(UI)
				local function line(name: string, text: string): any
					return UI.Label(name)({ text = text, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0) })
				end
				return UI.Screen "S" { line("Cjk", CJK), line("Emoji", EMOJI), line("Mixed", MIXED) }
			end, { size = Vector2.new(390, 844), theme = grown(t, base, offset), frames = 12 })
			t.settle(6)
			local found = t.offenders(stage, stage)
			t.check(`{where} no mixed-script line is clipped`, #found.clipped == 0, found.clipped)
			t.check(`{where} no mixed-script line crosses an edge`, #found.lateral == 0, found.lateral)
			local boxes = {}
			for _, name in { "Cjk", "Emoji", "Mixed" } do
				local node = t.find(stage, name)
				boxes[name] = t.rect(node)
				t.check(
					`{where} {name} fits its box`,
					t.fits(node),
					{ bounds = node.TextBounds, size = node.AbsoluteSize }
				)
				if previous[name] then
					t.check(`{where} {name} does not shrink`, node.AbsoluteSize.Y >= previous[name] - 0.5, {
						before = previous[name],
						now = node.AbsoluteSize.Y,
					})
				end
				previous[name] = node.AbsoluteSize.Y
			end
			t.check(
				`{where} the three lines do not overlap`,
				boxes.Cjk.b <= boxes.Emoji.y + 0.5 and boxes.Emoji.b <= boxes.Mixed.y + 0.5
			)
			t.cleanup()
		end
	end
	for _, themeName in { "Neutral", "fantasy_parchment" } do
		local heights = {}
		for _, offset in { 0, 14 } do
			local stage = t.mount(function(UI)
				return UI.Screen "S" {
					UI.Label "Line" { text = MIXED, TextWrapped = true, Size = UDim2.fromOffset(300, 0) },
				}
			end, { size = Vector2.new(390, 400), theme = grown(t, themeNamed(t, themeName), offset), frames = 12 })
			t.settle(4)
			table.insert(heights, t.find(stage, "Line").AbsoluteSize.Y)
			t.cleanup()
		end
		t.check(`{themeName} the largest offset reserves a strictly taller box`, heights[2] > heights[1], heights)
	end
end)

local function sheetRule(stage: any, selector: string): any
	local gui = stage:FindFirstAncestorWhichIsA("ScreenGui")
	local sheet = gui and gui:FindFirstChildWhichIsA("StyleSheet")
	if not sheet then
		return nil
	end
	local found
	for _, rule in sheet:GetChildren() do
		if rule:IsA("StyleRule") and rule.Selector == selector then
			found = rule
		end
	end
	return found
end

local function same(a: Color3?, b: Color3?): boolean
	return a ~= nil
		and b ~= nil
		and math.abs(a.R - b.R) < 0.002
		and math.abs(a.G - b.G) < 0.002
		and math.abs(a.B - b.B) < 0.002
end

add("role-fills-win-at-rest", { "inputs-31" }, function(t)
	for _, entry in shipped(t) do
		local stage = t.mount(function(UI)
			return UI.Screen "S" {
				UI.Button "Delete" { label = "Delete", role = "destructive" },
				UI.Button "Cancel" { label = "Cancel", role = "cancel" },
				UI.Button "Plain" { label = "Plain" },
			}
		end, { size = Vector2.new(400, 300), theme = entry.package, frames = 10 })
		local danger = sheetRule(stage, ".facet-role-destructive")
		local hover = sheetRule(stage, ".facet-role-destructive:Hover")
		local press = sheetRule(stage, ".facet-role-destructive:Press")
		local baseHover = sheetRule(stage, ".facet-button:Hover")
		t.check(
			`{entry.name} the sheet has the role and its own hover and press rules`,
			danger and hover and press ~= nil
		)
		if danger and hover and press and baseHover then
			local color = danger:GetProperty("BackgroundColor3")
			local fill = t.find(stage, "Delete"):GetStyled("BackgroundColor3")
			t.check(`{entry.name} the destructive button rests on the danger fill`, same(fill, color), {
				fill = tostring(fill),
				danger = tostring(color),
			})
			t.check(
				`{entry.name} the plain button does not take the danger fill`,
				not same(t.find(stage, "Plain"):GetStyled("BackgroundColor3"), color)
			)
			t.check(
				`{entry.name} the role hover rule paints danger`,
				same(hover:GetProperty("BackgroundColor3"), color)
			)
			t.check(
				`{entry.name} the role press rule paints danger`,
				same(press:GetProperty("BackgroundColor3"), color)
			)
			t.check(
				`{entry.name} the role rules come after the generic state rules`,
				danger.Priority > baseHover.Priority and hover.Priority > baseHover.Priority,
				{ danger = danger.Priority, hover = hover.Priority, base = baseHover.Priority }
			)
		end
		local cancel = sheetRule(stage, ".facet-role-cancel >> .facet-button-caption")
		t.check(`{entry.name} the cancel role has its own caption rule`, cancel ~= nil)
		t.cleanup()
	end
end)

add("circle-corner-wins-in-every-package", { "inputs-46" }, function(t)
	for _, entry in shipped(t) do
		local stage = t.mount(function(UI, _, Compose)
			return UI.Screen "S" {
				gap = "s",
				UI.Button "Plain" { label = "x", shape = "circle" },
				UI.Button "Danger" { label = "x", shape = "circle", role = "destructive" },
				UI.Button "Picked" { label = "x", shape = "circle", selected = Compose.cell(true) },
				UI.Button "Soft" { label = "x", shape = "circle", appearance = "soft" },
				UI.Button "Strong" { label = "x", shape = "circle", appearance = "emphasis" },
				UI.Button "Icon" { label = "Close", icon = "close", shape = "circle" },
				UI.Button "Rect" { label = "Save" },
			}
		end, { size = Vector2.new(400, 600), theme = entry.package, frames = 10 })
		for _, name in { "Plain", "Danger", "Picked", "Soft", "Strong", "Icon" } do
			local node = t.find(stage, name)
			local corners = {}
			for _, child in node:GetChildren() do
				if child:IsA("UICorner") then
					table.insert(corners, child)
				end
			end
			t.check(`{entry.name} {name} has the circle tag`, node:HasTag("facet-shape-circle"))
			t.check(`{entry.name} {name} has one corner modifier`, #corners == 1, #corners)
			if corners[1] then
				t.check(
					`{entry.name} {name} corner stays fully round`,
					corners[1]:GetStyled("CornerRadius") == UDim.new(1, 0),
					tostring(corners[1]:GetStyled("CornerRadius"))
				)
			end
			t.near(`{entry.name} {name} is a 1:1 box`, node.AbsoluteSize.X, node.AbsoluteSize.Y, 0.5)
		end
		t.check(`{entry.name} a rect button has no circle tag`, not t.find(stage, "Rect"):HasTag("facet-shape-circle"))
		t.cleanup()
	end
end)

add("compact-label-ladder-every-package", { "inputs-69" }, function(t)
	for _, entry in shipped(t) do
		local heights = {}
		for _, width in { 400, 44 } do
			local stage = t.mount(function(UI)
				return UI.Screen "S" {
					UI.Button "Edit" {
						label = "Edit item",
						compactLabel = "Ed",
						Size = UDim2.fromOffset(width, 44),
						AutomaticSize = Enum.AutomaticSize.None,
					},
				}
			end, { size = Vector2.new(600, 200), theme = entry.package, frames = 10 })
			local node = t.find(stage, "Edit")
			t.settle(6)
			local want = if width == 400 then "Edit item" else "Ed"
			t.check(`{entry.name} at {width} px the button draws {want}`, node.ContentText == want, node.ContentText)
			t.check(
				`{entry.name} at {width} px the drawn label fits one line`,
				t.fits(node) and node.TextBounds.Y <= node:GetStyled("TextSize") * 1.5,
				{
					bounds = node.TextBounds,
					size = node.AbsoluteSize,
				}
			)
			heights[width] = node.AbsoluteSize.Y
			t.cleanup()
		end
		t.near(`{entry.name} the compact form costs no second line`, heights[44], heights[400], 0.5)
	end
end)

add("level-picker-strip-target", { "inputs-116" }, function(t)
	for _, entry in shipped(t) do
		local stage = t.mount(function(UI, _, Compose)
			return UI.Screen "S" {
				UI.LevelPicker "Bars" { value = Compose.cell(3), count = 10 },
				UI.LevelPicker "Glyphs" { value = Compose.cell(2), count = 5, segment = "glyph" },
				UI.Rating "Stars" { value = Compose.cell(3) },
			}
		end, { size = Vector2.new(600, 400), theme = entry.package, frames = 10 })
		for _, name in { "Bars", "Glyphs", "Stars" } do
			local node = t.find(stage, name)
			t.check(`{entry.name} {name} strip is at least 44 px tall`, node.AbsoluteSize.Y >= 43.5, node.AbsoluteSize)
			local marks = 0
			for _, child in node:GetDescendants() do
				if child:IsA("GuiObject") and string.match(child.Name, "^Level%d+$") then
					marks += 1
					t.check(
						`{entry.name} {name} {child.Name} has area`,
						child.AbsoluteSize.X * child.AbsoluteSize.Y > 0,
						child.AbsoluteSize
					)
					t.inside(`{entry.name} {name} {child.Name} inside the strip`, child, node)
				end
			end
			t.check(`{entry.name} {name} has its marks`, marks > 0, marks)
		end
		t.cleanup()
	end
end)

local SHOWCASE = {
	Vector2.new(390, 844),
	Vector2.new(844, 390),
	Vector2.new(768, 1024),
	Vector2.new(1280, 720),
	Vector2.new(1920, 1080),
}

add("level-picker-showcase-marks-have-area", { "inputs-121" }, function(t)
	for _, size in SHOWCASE do
		local where = `{size.X}x{size.Y}`
		local stage = scenario(t, "level_picker", size)
		local blank, count = {}, {}
		for _, node in stage:GetDescendants() do
			if node:IsA("GuiObject") and string.match(node.Name, "^Level%d+$") then
				local picker = node.Parent and node.Parent.Parent
				local key = if picker then picker.Name else "?"
				count[key] = (count[key] or 0) + 1
				if node.AbsoluteSize.X * node.AbsoluteSize.Y <= 0 or not t.visible(node) then
					table.insert(blank, key .. "/" .. node.Name)
				end
			end
		end
		t.check(`{where} every mark paints a rectangle with area`, #blank == 0, blank)
		for picker, want in
			{ BalancedBars = 10, FidelityBars = 3, TintedBars = 10, DifficultyGlyphs = 5, TrophyIcons = 3 }
		do
			t.check(`{where} {picker} has all {want} marks`, count[picker] == want, count[picker])
		end
		t.cleanup()
	end
	local stage = t.mount(function(UI, _, Compose)
		local value = Compose.cell(2)
		return UI.Screen "S" {
			UI.HStack "Pair" {
				gap = 8,
				align = "center",
				width = "fill",
				UI.LevelPicker "Quality" { value = value, count = 10 },
				UI.Stepper "QualityStep" { value = value, min = 0, max = 10 },
			},
		}
	end, { size = Vector2.new(600, 300), frames = 12 })
	for index = 1, 10 do
		local mark = t.find(t.find(stage, "Quality"), "Level" .. index)
		t.check(`beside a stepper Level{index} has area`, mark and mark.AbsoluteSize.X * mark.AbsoluteSize.Y > 0)
	end
end)

add("rating-fits-a-table-cell", { "inputs-159" }, function(t)
	for _, entry in shipped(t) do
		local stage = t.mount(function(UI, Host, Compose)
			return UI.Screen "S" {
				Host.Frame "Cell" {
					Size = UDim2.fromOffset(132, 48),
					BackgroundTransparency = 1,
					UI.Rating "Fill" { value = Compose.cell(3), Size = UDim2.fromScale(1, 1) },
				},
				Host.Frame "Plain" {
					Size = UDim2.fromOffset(132, 48),
					BackgroundTransparency = 1,
					UI.Rating "Hug" { value = Compose.cell(3) },
				},
			}
		end, { size = Vector2.new(400, 300), theme = entry.package, frames = 10 })
		local cell = t.rect(t.find(stage, "Cell"))
		local fill = t.find(stage, "Fill")
		local s1, s2, s5 =
			t.rect(t.find(fill, "Level1")), t.rect(t.find(fill, "Level2")), t.rect(t.find(fill, "Level5"))
		t.check(`{entry.name} five stars fit the 132 px cell`, s5.r <= cell.r + 0.5 and s1.x >= cell.x - 0.5, {
			first = s1.x,
			last = s5.r,
			cell = { cell.x, cell.r },
		})
		local before, after = s1.x - cell.x, cell.r - s5.r
		t.check(`{entry.name} the leftover is on both sides`, before > 0 and after > 0, { before, after })
		t.near(`{entry.name} the run is centred in the cell`, before, after, 2)
		t.check(
			`{entry.name} the spacing follows the glyph`,
			(s2.x - s1.x - s1.w) / s1.w < 0.25,
			{ pitch = s2.x - s1.x, glyph = s1.w }
		)
		local hug = t.rect(t.find(stage, "Hug"))
		t.check(`{entry.name} a hugging rating fits the cell`, hug.w <= 132.5, hug.w)
		t.cleanup()
	end
end)

local function luminance(color: Color3): number
	local function channel(value: number): number
		return if value <= 0.03928 then value / 12.92 else ((value + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
end

local function contrast(a: Color3, b: Color3): number
	local x, y = luminance(a), luminance(b)
	return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end

add("shortcut-hint-key-cap-anatomy", { "inputs-175" }, function(t)
	local neutral = {}
	for _, entry in shipped(t) do
		for _, offset in { 0, 14 } do
			local where = `{entry.name} +{offset}`
			local stage = t.mount(function(UI)
				return UI.Screen "S" { UI.ShortcutHint "Hint" { keys = { { "K" } } } }
			end, { size = Vector2.new(400, 300), theme = grown(t, entry.package, offset), frames = 10 })
			local cap = t.find(stage, "Hint")
			t.settle(4)
			local size = cap.AbsoluteSize
			t.check(`{where} the cap shows its key`, t.fits(cap), { bounds = cap.TextBounds, size = size })
			t.check(`{where} the cap is painted`, cap:GetStyled("BackgroundTransparency") < 1)
			t.check(`{where} the cap is a key, not a button`, size.Y < 44 and not cap.Selectable, size)
			t.check(`{where} the cap is not narrower than tall`, size.X >= size.Y - 0.5, size)
			local ratio = contrast(cap:GetStyled("TextColor3"), cap:GetStyled("BackgroundColor3"))
			t.check(`{where} the key is readable on its cap`, ratio >= 4.5, ratio)
			if entry.name == "Neutral" then
				neutral[offset] = size
			elseif neutral[offset] then
				t.check(
					`{where} the cap stays within 1.6x of the neutral cap`,
					size.X <= neutral[offset].X * 1.6 and size.Y <= neutral[offset].Y * 1.6,
					{ size = size, neutral = neutral[offset] }
				)
			end
			if offset == 14 and neutral[0] and entry.name == "Neutral" then
				t.check(
					`{where} the cap grows with the text`,
					size.X * size.Y > neutral[0].X * neutral[0].Y and size.Y >= neutral[0].Y,
					{ now = size, before = neutral[0] }
				)
			end
			t.cleanup()
		end
	end
end)

add("clear-button-trailing-and-centred", { "inputs-187" }, function(t)
	for _, framed in { false, true } do
		local where = if framed then "field chrome" else "bare field"
		local stage = t.mount(function(UI, _, Compose)
			return UI.Screen "S" {
				UI.TextInput "Name" {
					value = Compose.cell("typed"),
					clearButton = true,
					label = if framed then "Name" else nil,
					Size = if framed then UDim2.fromOffset(300, 0) else UDim2.fromOffset(300, 44),
				},
			}
		end, { size = Vector2.new(400, 300), frames = 12 })
		local clear = t.find(stage, "Clear")
		local field = if framed then t.find(stage, "Input") else t.find(stage, "Name")
		t.check(`{where} the clear button shows`, clear ~= nil and t.visible(clear))
		if not (clear and field) then
			t.cleanup()
			continue
		end
		local c, f = t.rect(clear), t.rect(field)
		local inset = f.r - c.r
		t.check(`{where} the clear button is inside the trailing edge`, inset >= -0.5 and inset <= 12, inset)
		t.check(`{where} the clear button is in the trailing half`, c.x > f.x + f.w / 2, { clear = c.x, field = f })
		t.near(`{where} the clear button is vertically centred`, c.y + c.h / 2, f.y + f.h / 2, 1)
		t.check(`{where} the clear button is a 44 px target`, c.w >= 43.5 and c.h >= 43.5, { c.w, c.h })
		t.cleanup()
	end
end)

add("slider-rest-idle-resize-clearance", { "inputs-220" }, function(t)
	local width = t.Facet.Compose.cell(Vector2.new(360, 200))
	local value = t.Facet.Compose.cell(50)
	local stage = t.mount(function(UI)
		return UI.Screen "S" {
			padding = 0,
			UI.Slider "Vol" { label = "Vol", value = value, min = 0, max = 100, Size = UDim2.fromScale(1, 0) },
		}
	end, { size = width, frames = 12 })
	local track, fill, thumb = t.find(stage, "Track"), t.find(stage, "Fill"), t.find(stage, "Thumb")
	t.stable(thumb)
	local function atRest(where: string)
		local tr, fr, th = t.rect(track), t.rect(fill), t.rect(thumb)
		t.near(`{where} the fill shows half the track`, fr.w, tr.w * 0.5, 1)
		t.near(`{where} the fill starts at the track start`, fr.x, tr.x, 0.5)
		t.near(`{where} the thumb centre sits at half the track`, th.x + th.w / 2, tr.x + tr.w * 0.5, 1)
	end
	atRest("at rest")
	local writes = 0
	local connections = {}
	for _, node in { track, fill, thumb } do
		table.insert(
			connections,
			node.Changed:Connect(function(name)
				if name ~= "AbsolutePosition" and name ~= "AbsoluteSize" and name ~= "GuiState" then
					writes += 1
				end
			end)
		)
	end
	t.settle(30)
	for _, connection in connections do
		connection:Disconnect()
	end
	t.check("an idle slider writes no property in 30 frames", writes == 0, writes)
	local before = track.AbsoluteSize.X
	width:set(Vector2.new(560, 200))
	t.stable(track)
	t.settle(4)
	t.check("the track follows the resize", track.AbsoluteSize.X > before + 100, { before, track.AbsoluteSize.X })
	t.check("the value does not move", value:peek() == 50, value:peek())
	atRest("after the resize")
	value:set(0)
	t.settle(6)
	local label = t.find(t.find(stage, "Vol"), "Label")
	local glyphs = label.AbsolutePosition.X + label.TextBounds.X
	local gap = thumb.AbsolutePosition.X - glyphs
	t.check("the thumb at value 0 clears the label glyphs by 16 px", gap >= 15.5, {
		glyphs = glyphs,
		thumb = thumb.AbsolutePosition.X,
		gap = gap,
	})
	t.note("label to thumb gap at value 0", gap)
	t.cleanup()
	local steps = t.Facet.Compose.cell(9)
	local stepperStage = t.mount(function(UI)
		return UI.Screen "S" { UI.Stepper "Qty" { label = "Volume", value = steps, min = 0, max = 100, step = 1 } }
	end, { size = Vector2.new(400, 200), frames = 12 })
	local readout = t.find(t.find(stepperStage, "Qty"), "Value")
	local increase = t.find(stepperStage, "Increase")
	t.check(
		"the readout is centred",
		readout.TextXAlignment == Enum.TextXAlignment.Center,
		tostring(readout.TextXAlignment)
	)
	local incX, readW = increase.AbsolutePosition.X, readout.AbsoluteSize.X
	steps:set(10)
	t.settle(6)
	t.near("a wider number keeps the readout width", readout.AbsoluteSize.X, readW, 0.5)
	t.near("a wider number does not move the increase button", increase.AbsolutePosition.X, incX, 0.5)
	for _, name in { "Decrease", "Increase" } do
		local node = t.find(stepperStage, name)
		t.check(
			`{name} is 44 px on both axes`,
			node.AbsoluteSize.X >= 43.5 and node.AbsoluteSize.Y >= 43.5,
			node.AbsoluteSize
		)
	end
end)

return cases
