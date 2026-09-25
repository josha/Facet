--!strict
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local cases = {}

local function interactive(
	id: string,
	contracts: { string },
	plan: string,
	setup: (any) -> any,
	steps: { [string]: (any, any) -> () },
	keepGallery: boolean?
)
	table.insert(
		cases,
		{ id = id, contracts = contracts, plan = plan, setup = setup, steps = steps, keepGallery = keepGallery }
	)
end

local function at(node: any, fx: number?, fy: number?): { number }
	local position, size = node.AbsolutePosition, node.AbsoluteSize
	return {
		math.floor(position.X + size.X * (fx or 0.5) + 0.5),
		math.floor(position.Y + size.Y * (fy or 0.5) + 0.5),
	}
end

local function host(t: any)
	t.note("host", {
		preferredInput = tostring(UserInputService.PreferredInput),
		viewport = workspace.CurrentCamera.ViewportSize,
		guiInset = GuiService:GetGuiInset(),
		tenFoot = GuiService:IsTenFootInterface(),
		textSize = tostring(GuiService.PreferredTextSize),
	})
end

local function partOf(root: any, name: string): any
	if root == nil then
		return nil
	end
	return root:FindFirstChild(name) or root:FindFirstChild(name, true)
end

interactive(
	"range-slider-drag",
	{ "post-pickers-104", "post-pickers-105" },
	"dragGap: drag from gapLower to gapPast; dragPile: drag from pileUpper to pileLeft",
	function(t)
		host(t)
		local value: any = { commits = {} }
		local stage = t.mount(function(UI, Host, Compose)
			value.gap = Compose.cell({ lower = 20, upper = 60 })
			value.pile = Compose.cell({ lower = 20, upper = 60 })
			return Host.Frame "Column" {
				Size = UDim2.fromOffset(600, 420),
				Position = UDim2.fromOffset(100, 100),
				BackgroundTransparency = 1,
				Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 40) }),
				UI.Slider "Gap" {
					LayoutOrder = 1,
					Size = UDim2.fromOffset(420, 0),
					value = value.gap,
					min = 0,
					max = 100,
					step = 5,
					range = true,
					minGap = 10,
					onCommit = function(range: any, info: any)
						table.insert(value.commits, `{info.thumb}:{range.lower}-{range.upper}`)
					end,
				},
				UI.Slider "Pile" {
					LayoutOrder = 2,
					Size = UDim2.fromOffset(420, 0),
					value = value.pile,
					min = 0,
					max = 100,
					step = 5,
					range = true,
					minGap = 0,
				},
			}
		end, { frames = 20 })
		for _, name in { "Gap", "Pile" } do
			local track = partOf(t.find(stage, name), "Track")
			value[name] = {
				track = track,
				lower = partOf(track, "HandleLower"),
				upper = partOf(track, "HandleUpper"),
				fill = partOf(track, "Fill"),
			}
			t.stable(track)
		end
		local gap, pile = value.Gap, value.Pile
		t.check(
			"all three tracks and their handles were found",
			gap.lower and gap.upper and pile.upper and true or false
		)
		for _, handle in { gap.lower, gap.upper } do
			t.check(
				`{handle.Name} is at least 44x44 on screen`,
				handle.AbsoluteSize.X >= 43.5 and handle.AbsoluteSize.Y >= 43.5,
				handle.AbsoluteSize
			)
		end
		local tr = t.rect(gap.track)
		t.note("points", {
			gapLower = at(gap.lower),
			gapPast = { math.floor(tr.r + 60), at(gap.lower)[2] },
			pileUpper = at(pile.upper),
			pileLeft = { math.floor(t.rect(pile.track).x - 60), at(pile.upper)[2] },
		})
		return value
	end,
	{
		dragGap = function(t, value)
			t.settle(6)
			local band = value.gap:peek()
			t.check(
				"a real drag of the lower thumb past the upper stops a whole minGap short: 50/60",
				band.lower == 50 and band.upper == 60,
				band
			)
			t.check(
				"the drag committed once and names the lower thumb",
				#value.commits == 1 and value.commits[1] == "lower:50-60",
				value.commits
			)
			local f, lower, upper = t.rect(value.Gap.fill), value.Gap.lower, value.Gap.upper
			t.near("the fill starts at the lower handle centre", f.x, at(lower)[1], 1)
			t.near("the fill ends at the upper handle centre", f.r, at(upper)[1], 1)
		end,
		dragPile = function(t, value)
			t.settle(6)
			local band = value.pile:peek()
			t.check(
				"a real drag keeps the upper thumb it started with past the lower one: 20/20",
				band.lower == 20 and band.upper == 20,
				band
			)
		end,
	}
)

local function hex(color: Color3): string
	return color:ToHex()
end

interactive(
	"color-plane-drag",
	{ "post-pickers-179" },
	"hold: mouse down at down, move to to in steps, keep the button held; release: mouse up at to; corner: click at corner",
	function(t)
		host(t)
		local value: any = { commits = {}, changes = 0 }
		local stage = t.mount(function(UI, Host, Compose)
			value.cell = Compose.cell(Color3.fromHSV(0.5, 0.5, 0.5))
			return Host.Frame "Box" {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(100, 100),
				Size = UDim2.fromOffset(360, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				UI.ColorPicker "Accent" {
					label = "Accent",
					style = "inline",
					modes = { "spectrum" },
					value = value.cell,
					onChange = function(next: Color3)
						value.changes += 1
						value.cell:set(next)
					end,
					onCommit = function(committed: Color3)
						table.insert(value.commits, hex(committed))
					end,
				},
			}
		end, { frames = 20 })
		local plane = partOf(t.find(stage, "Accent"), "Plane")
		value.plane = plane
		value.surface = plane and plane:FindFirstChild("Surface")
		value.ring = plane and plane:FindFirstChild("Ring")
		t.check("the plane, its Surface and its Ring were found", value.surface ~= nil and value.ring ~= nil)
		if value.surface == nil then
			return value
		end
		t.stable(plane)
		t.note("points", {
			down = at(value.surface, 0.25, 0.5),
			to = at(value.surface, 0.75, 0.25),
			corner = at(value.surface, 0.999, 0.001),
		})
		return value
	end,
	{
		hold = function(t, value)
			t.settle(4)
			local h, s, v = value.cell:peek():ToHSV()
			t.near("mid-drag saturation tracks the pointer 1:1 at 75", math.floor(s * 100 + 0.5), 75, 1)
			t.near("mid-drag value tracks the pointer 1:1 at 75", math.floor(v * 100 + 0.5), 75, 1)
			t.near("the drag keeps the hue at 180", math.floor(h * 360 + 0.5), 180, 1)
			t.check("nothing is committed while the button is held", #value.commits == 0, value.commits)
			t.check("the value moved live during the drag", value.changes >= 1, value.changes)
		end,
		release = function(t, value)
			t.settle(4)
			t.check(
				"the release commits exactly once, with the dragged colour",
				#value.commits == 1 and value.commits[1] == hex(value.cell:peek()),
				{ commits = value.commits, now = hex(value.cell:peek()) }
			)
			local ring, surface = t.rect(value.ring), t.rect(value.surface)
			t.near("the ring sits where the colour is", ring.x + ring.w / 2, surface.x + surface.w * 0.75, 1)
		end,
		corner = function(t, value)
			t.settle(6)
			t.inside("at the top-right corner the whole ring stays on the plane", value.ring, value.surface, 0.5)
			t.check("the corner click committed once more", #value.commits == 2, value.commits)
		end,
	}
)

interactive(
	"underline-hover",
	{ "post-port26-008" },
	"hover: move the mouse onto the Link point; away: move the mouse to the away point",
	function(t)
		host(t)
		local value: any = {}
		local stage = t.mount(function(UI, Host)
			return Host.Frame "Column" {
				Position = UDim2.fromOffset(100, 100),
				Size = UDim2.fromOffset(400, 200),
				BackgroundTransparency = 1,
				Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 24) }),
				UI.Button "Link" { label = "Read more", underline = "hover", LayoutOrder = 1 },
				UI.Button "Always" { label = "Terms", underline = "always", LayoutOrder = 2 },
			}
		end, { frames = 12 })
		value.link = t.find(stage, "Link")
		value.always = t.find(stage, "Always")
		t.check(
			"at rest the hover link is not underlined",
			not string.find(value.link.Text, "<u>", 1, true),
			value.link.Text
		)
		t.check(
			"the always link is underlined at rest",
			string.find(value.always.Text, "<u>", 1, true) ~= nil,
			value.always.Text
		)
		t.note("points", { hover = at(value.link), away = { 900, 600 } })
		return value
	end,
	{
		hover = function(t, value)
			t.settle(4)
			t.check(
				"the real pointer hovers the link",
				value.link.GuiState == Enum.GuiState.Hover,
				tostring(value.link.GuiState)
			)
			t.check(
				"the hovered link is underlined",
				string.find(value.link.Text, "<u>", 1, true) ~= nil,
				value.link.Text
			)
		end,
		away = function(t, value)
			t.settle(4)
			t.check(
				"the pointer left the link",
				value.link.GuiState == Enum.GuiState.Idle,
				tostring(value.link.GuiState)
			)
			t.check(
				"the underline clears after the pointer leaves",
				not string.find(value.link.Text, "<u>", 1, true),
				value.link.Text
			)
			t.check(
				"the always link stays underlined",
				string.find(value.always.Text, "<u>", 1, true) ~= nil,
				value.always.Text
			)
		end,
	}
)

interactive(
	"skinned-part-press-state",
	{ "themes-P4-51" },
	"pressToggle: mouse down on toggle and hold; releaseToggle: mouse up; pressStepper: mouse down on stepper and hold; releaseStepper: mouse up",
	function(t)
		host(t)
		local value: any = {}
		local stage = t.mount(function(UI, Host, Compose)
			value.toggle = Compose.cell(false)
			return Host.Frame "Column" {
				Position = UDim2.fromOffset(100, 100),
				Size = UDim2.fromOffset(360, 300),
				BackgroundTransparency = 1,
				Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }),
				UI.Toggle "Toggle" { value = value.toggle, label = "On", LayoutOrder = 1 },
				UI.Stepper "Stepper" { value = Compose.cell(2), min = 0, max = 5, LayoutOrder = 2 },
			}
		end, { frames = 10 })
		value.indicator = t.find(t.find(stage, "Toggle"), "Indicator")
		value.stepper = t.find(t.find(stage, "Stepper"), "Increase")
		t.check(
			"the Toggle Indicator and the Stepper Increase part were found",
			value.indicator ~= nil and value.stepper ~= nil
		)
		t.note("points", { toggle = at(value.indicator), stepper = at(value.stepper) })
		return value
	end,
	{
		pressToggle = function(t, value)
			t.settle(3)
			t.check(
				"the held mouse puts the Toggle Indicator in GuiState Press",
				value.indicator.GuiState == Enum.GuiState.Press,
				tostring(value.indicator.GuiState)
			)
		end,
		releaseToggle = function(t, value)
			t.settle(4)
			t.check(
				"after release the Indicator leaves Press",
				value.indicator.GuiState ~= Enum.GuiState.Press,
				tostring(value.indicator.GuiState)
			)
			t.check("the release flipped the toggle once", value.toggle:peek() == true, value.toggle:peek())
		end,
		pressStepper = function(t, value)
			t.settle(3)
			t.check(
				"the held mouse puts the Stepper Increase part in GuiState Press",
				value.stepper.GuiState == Enum.GuiState.Press,
				tostring(value.stepper.GuiState)
			)
		end,
		releaseStepper = function(t, value)
			t.settle(4)
			t.check(
				"after release the Stepper Increase part leaves Press",
				value.stepper.GuiState ~= Enum.GuiState.Press,
				tostring(value.stepper.GuiState)
			)
		end,
	}
)

return cases
