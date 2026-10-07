--!strict
type DialogAction = typeof(require("@repo/tools/typecheck/aliases").DialogAction)

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type AlertAction = typeof(require("@repo/tools/typecheck/aliases").AlertAction)
type OverlayAction = typeof(require("@repo/tools/typecheck/aliases").OverlayAction)
type MenuItem = typeof(require("@repo/tools/typecheck/aliases").MenuItem)
type SheetDetent = typeof(require("@repo/tools/typecheck/aliases").SheetDetent)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Case = {
	id: string,
	contracts: { string },
	run: ((any) -> ())?,
	setup: ((any) -> any)?,
	steps: { [string]: (any, any) -> () }?,
	keepGallery: boolean?,
}
local cases: { Case } = {}
local TEXT = "Your selected driver is ready."

local function visible(node: GuiObject, root: Instance): boolean
	local at: Instance? = node
	while at and at ~= root do
		if at:IsA("GuiObject") and not at.Visible then
			return false
		end
		at = at.Parent
	end
	return true
end

local function snapshot(root: Instance, fixed: boolean?): any
	local texts, scrolls = {}, {}
	for _, node in root:GetDescendants() do
		if
			(node:IsA("TextLabel") or node:IsA("TextButton"))
			and visible(node, root)
			and node.TextTransparency < 1
			and node.Text ~= ""
		then
			local position = node.AbsolutePosition
				- (if fixed then Vector2.zero else (root :: GuiObject).AbsolutePosition)
			texts[node] = {
				node.TextBounds.X,
				node.TextBounds.Y,
				node.AbsoluteSize.X,
				node.AbsoluteSize.Y,
				position.X,
				position.Y,
			}
		elseif node:IsA("ScrollingFrame") then
			scrolls[node] = node.ScrollingEnabled
				and node.ScrollBarThickness > 0
				and node.AbsoluteCanvasSize.Y > node.AbsoluteWindowSize.Y + 1
		end
	end
	return { texts = texts, scrolls = scrolls }
end

local function checkFrames(t: any, name: string, frames: { any })
	t.check(name .. " sampled visible frames", #frames >= 3, #frames)
	if #frames < 3 then
		return
	end
	local final = frames[#frames]
	local largest, shift, flash, count, missing = 0, 0, false, 0, false
	local example, boundsExample
	for _ in final.texts do
		count += 1
	end
	for at, frame in frames do
		for node, before in frame.texts do
			local after = final.texts[node]
			if after then
				for index = 5, 6 do
					local delta = math.abs(before[index] - after[index])
					if delta > shift then
						shift = delta
						example = { node = node.Name, before = before, after = after, frame = at, shown = frame.shown }
					end
				end
				for index = 1, 4 do
					local delta = math.abs(before[index] - after[index])
					if delta > largest then
						largest = delta
						boundsExample =
							{ node = node.Name, before = before, after = after, frame = at, shown = frame.shown }
					end
				end
			else
				missing = true
			end
		end
		for node in final.texts do
			missing = missing or frame.texts[node] == nil
		end
		for node, scrolling in frame.scrolls do
			flash = flash or (scrolling and final.scrolls[node] == false)
		end
	end
	t.check(name .. " visible text was sampled throughout", count > 0 and not missing, count)
	t.check(name .. " text keeps final bounds while visible", largest <= 1, largest)
	t.check(name .. " text keeps final position while visible", shift <= 0.5, shift)
	t.check(name .. " no temporary vertical scrollbar", not flash)
	t.note(name .. " frames", #frames)
	local samples = {}
	for _, frame in frames do
		local sample = { panel = frame.panel, shown = frame.shown, texts = {} }
		for node, bounds in frame.texts do
			sample.texts[node.Name] = bounds
		end
		table.insert(samples, sample)
	end
	t.note(name .. " frame samples", samples)
	if largest > 1 then
		t.note(name .. " bounds", boundsExample)
	end
	if shift > 0.5 then
		t.note(name .. " shift", example)
	end
	if largest > 1 or shift > 0.5 then
		local trace = {}
		for at = 1, math.min(#frames, 16) do
			trace[at] = frames[at].panel
		end
		t.note(name .. " panel trace", trace)
	end
end

table.insert(cases, {
	id = "continuity-checker-rejects-text-pop-shift-and-scrollbar-flash",
	contracts = {},
	run = function(t)
		local factor, extent, label
		local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
			factor, extent = Compose.cell(0.94), Compose.cell(80)
			label = UI.Text { text = TEXT, TextSize = 24 }
			return Host.Frame "Fault" {
				Size = UDim2.fromOffset(300, 100),
				Host.UIScale { Scale = factor } :: unknown,
				label,
				Host.ScrollingFrame {
					Size = UDim2.fromOffset(300, 40),
					CanvasSize = function(use: Use)
						return UDim2.fromOffset(0, use(extent))
					end,
					ScrollBarThickness = 12,
				},
			}
		end)
		local frames = { snapshot(stage), snapshot(stage) }
		factor:set(1)
		extent:set(0)
		t.settle(4)
		table.insert(frames, snapshot(stage))
		local rejected = {}
		checkFrames({
			check = function(name, ok)
				rejected[name] = not ok
			end,
			note = function() end,
		}, "injected", frames)
		t.check("detects an injected native text-scale pop", rejected["injected text keeps final bounds while visible"])
		t.check("detects an injected temporary scrollbar", rejected["injected no temporary vertical scrollbar"])
		label.Position = UDim2.fromOffset(1, 1)
		t.settle(2)
		local shifted = { snapshot(stage), snapshot(stage) }
		label.Position = UDim2.fromOffset(0, 0)
		t.settle(2)
		table.insert(shifted, snapshot(stage))
		checkFrames({
			check = function(name, ok)
				rejected[name] = not ok
			end,
			note = function() end,
		}, "shifted", shifted)
		t.check("detects a one-pixel position shift", rejected["shifted text keeps final position while visible"])
		t.check(
			"position control keeps text bounds stable",
			not rejected["shifted text keeps final bounds while visible"]
		)
		t.cleanup()
	end,
})

for _, kind in
	{ "Alert", "Dialog", "Menu", "Popover", "Callout", "Help", "Sheet", "CollapsibleView", "Toast" } :: { "Alert" | "Callout" | "CollapsibleView" | "Dialog" | "Help" | "Menu" | "Popover" | "Sheet" | "Toast" }
do
	table.insert(cases, {
		id = string.lower(kind) .. "-entrance-continuity",
		contracts = {},
		run = function(t: any)
			for _, motion in { "normal", "limited", "none" } do
				for _, shape in { Vector2.new(960, 720), Vector2.new(390, 720) } do
					for _, large in { false, true } do
						local copy = if large
							then TEXT .. " Please confirm the selected driver and race details before continuing."
							else TEXT
						local theme = t.themes[1]
						if large then
							for _, entry in t.themes do
								if entry.name == "scifi_hud" then
									theme = entry
								end
							end
						end
						local open, trigger
						local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
							open = Compose.cell(false)
							local function content(): Instance
								return UI.Text "Copy" {
									text = copy,
									TextSize = if large then 36 else 24,
									TextWrapped = true,
									Size = UDim2.new(1, 0, 0, 0),
									AutomaticSize = Enum.AutomaticSize.Y,
								}
							end
							local function change(value: boolean)
								open:set(value)
							end
							trigger = UI.Button "Trigger" {
								label = "Open",
								Position = UDim2.fromOffset(40, 100),
								help = if kind == "Help" then copy else nil,
							}
							local overlay: GuiObject?
							if kind == "Alert" then
								overlay = UI.Alert {
									isPresented = open,
									title = "Start this race?",
									message = copy,
									actions = {
										{
											id = "Cancel",
											label = "Cancel",
											role = "cancel" :: "cancel",
											onActivate = function()
												open:set(false)
											end,
										} :: AlertAction,
									},
								}
							elseif kind == "Dialog" then
								overlay = UI.Dialog {
									isPresented = open,
									onPresentedChange = change,
									title = "Start this race?",
									content = content,
									actions = {
										{
											id = "Cancel",
											label = "Cancel",
											role = "cancel" :: "cancel",
											onActivate = function()
												open:set(false)
											end,
										} :: DialogAction,
									},
								}
							elseif kind == "Menu" then
								overlay = UI.Menu {
									isPresented = open,
									label = "Options",
									Position = UDim2.fromOffset(40, shape.Y - 80),
									presentation = if shape.X < 600 then "sheet" :: "sheet" else "menu" :: "menu",
									items = {
										{ id = "Start", label = copy, onSelect = function() end } :: MenuItem,
									},
								}
							elseif kind == "Popover" then
								overlay = UI.Popover {
									isPresented = open,
									onPresentedChange = change,
									trigger = trigger :: GuiButton,
									content = content,
									maxWidth = 340,
								}
							elseif kind == "Callout" then
								overlay = UI.Callout {
									isPresented = open,
									anchor = trigger :: GuiObject,
									content = content,
									onRetire = function()
										open:set(false)
									end,
								}
							elseif kind == "Sheet" then
								overlay = UI.Sheet {
									isPresented = open,
									detent = Compose.cell("hug"),
									detents = { "hug" } :: { SheetDetent },
									content = content,
									title = "Details",
								}
							elseif kind == "CollapsibleView" then
								overlay = UI.CollapsibleView { label = copy, expanded = open, content = content }
							elseif kind == "Toast" then
								overlay = UI.Toast {
									isPresented = open,
									onPresentedChange = change,
									message = copy,
									duration = 10,
								}
							end
							return Host.Frame {
								Size = UDim2.fromScale(1, 1),
								BackgroundTransparency = 1,
								overlay or trigger :: unknown,
								if kind ~= "Popover" and overlay then trigger else nil :: unknown,
							}
						end, {
							size = shape,
							theme = theme.package,
							motionLevel = motion,
							environment = {
								preferredInput = "Gamepad",
								displaySize = "Large",
								preferredTextSize = if large then "Largest" else "Medium",
							},
						})
						local layer = stage:FindFirstAncestorWhichIsA("LayerCollector")
						if kind == "Help" then
							game:GetService("GuiService").SelectedObject = trigger
						else
							open:set(true)
						end
						local names = {
							Alert = "AlertPanel",
							Dialog = "Panel",
							Menu = "MenuPanel",
							Popover = "Panel",
							Callout = "CalloutPanel",
							Help = "Help",
							Sheet = "SheetPanel",
							CollapsibleView = "Expanded",
							Toast = "ToastRow",
						}
						local frames = {}
						local started = os.clock()
						while os.clock() - started < 1.2 do
							t.settle(1)
							local panel = t.find(layer, names[kind])
							if panel and panel:IsA("GuiObject") then
								local fade = panel:FindFirstChild("FadePaint")
									or panel:FindFirstChild("PresentationFade")
								local alpha = if fade then fade.Transparency.Keypoints[1].Value else 0
								if alpha < 0.95 then
									local frame = snapshot(
										panel,
										kind ~= "Sheet"
											and (kind ~= "Menu" or shape.X >= 600)
											and kind ~= "Toast"
											and kind ~= "CollapsibleView"
									)
									frame.shown = t.visible(panel)
									frame.panel = {
										panel.AbsolutePosition.X,
										panel.AbsolutePosition.Y,
										panel.AbsoluteSize.X,
										panel.AbsoluteSize.Y,
										alpha,
									}
									table.insert(frames, frame)
								end
							end
						end
						if kind == "Toast" then
							local row = t.find(layer, "ToastRow")
							local message = row and t.find(row, "Message")
							t.check(
								`Toast/{motion}/{shape.X}/{theme.name} fits its presentation width`,
								row and row.AbsoluteSize.X <= shape.X - 31,
								row and row.AbsoluteSize.X
							)
							t.check(`Toast/{motion}/{shape.X}/{theme.name} message fits`, message and message.TextFits)
						end
						checkFrames(
							t,
							`{kind}/{motion}/{shape.X}/{theme.name}/{if large then "large" else "standard"}`,
							frames
						)
						if large and motion == "normal" then
							if kind == "Help" then
								game:GetService("GuiService").SelectedObject = nil
							else
								open:set(false)
							end
							local lag, closing = 0, os.clock()
							while os.clock() - closing < 1 do
								t.settle(1)
								local panel = t.find(layer, names[kind])
								if panel == nil then
									break
								end
								local paint = panel:FindFirstChild("FadePaint")
								if paint then
									for _, child in panel:GetChildren() do
										if child:IsA("UIShadow") and child.Enabled then
											lag = math.max(
												lag,
												paint.Transparency.Keypoints[1].Value - child.Transparency
											)
										end
									end
								end
							end
							t.check(`{kind}/{shape.X} shadow fades with the panel`, lag <= 0.01, lag)
						end
						t.cleanup()
					end
				end
			end
		end,
	})
end
return cases
