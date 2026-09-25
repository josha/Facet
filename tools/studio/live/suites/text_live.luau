--!strict
local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function drawn(root: Instance, text: string): TextLabel?
	local best: any = nil
	for _, node in root:GetDescendants() do
		if
			(node:IsA("TextLabel") or node:IsA("TextButton"))
			and node.Text == text
			and node.AbsoluteSize.X > 0
			and node:GetStyled("TextTransparency") < 1
		then
			best = node
		end
	end
	return best
end

local function glyphCentre(label: any): number
	local top = label.AbsolutePosition.Y
	local padding = label:FindFirstChildWhichIsA("UIPadding")
	local inner = label.AbsoluteSize.Y
	if padding then
		local t, b = padding:GetStyled("PaddingTop"), padding:GetStyled("PaddingBottom")
		top += t.Offset + t.Scale * inner
		inner -= t.Offset + t.Scale * label.AbsoluteSize.Y + b.Offset + b.Scale * label.AbsoluteSize.Y
	end
	local alignment = label:GetStyled("TextYAlignment")
	if alignment == Enum.TextYAlignment.Top then
		return top + label.TextBounds.Y / 2
	elseif alignment == Enum.TextYAlignment.Bottom then
		return top + inner - label.TextBounds.Y / 2
	end
	return top + inner / 2
end

add("button-labels-centred-in-every-package", { "inputs-50" }, function(t: any)
	for _, theme in t.themes do
		local stage = t.mount(function(UI, Host)
			return Host.Frame "Row" {
				Size = UDim2.fromOffset(600, 80),
				BackgroundTransparency = 1,
				Host.UIListLayout { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12) },
				UI.Button "Word" { label = "Play" },
				UI.Button "Marked" { label = "Next", icon = "chevron.down" },
			}
		end, { theme = theme.package, size = Vector2.new(600, 200) })
		t.settle(10)
		for name, text in { Word = "Play", Marked = "Next" } do
			local button = t.find(stage, name)
			local label = button and drawn(button.Parent, text)
			if not (button and label) then
				t.check(`{theme.name} {name} label drawn`, false)
				continue
			end
			local box = button.AbsolutePosition.Y + button.AbsoluteSize.Y / 2
			t.near(`{theme.name} {name} label is centred on its button`, glyphCentre(label), box, 1.5)
		end
		t.cleanup()
	end
end)

add("described-toggle-fits-a-narrow-row", { "apps-130" }, function(t: any)
	local chosen = t.themes[1]
	for _, theme in t.themes do
		if theme.name == "classic_desktop" then
			chosen = theme
		end
	end
	local stage = t.mount(function(UI, Host)
		return Host.Frame "Column" {
			Size = UDim2.fromOffset(320, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Host.UIListLayout {},
			UI.Toggle "Hints" {
				row = {
					title = "Show hints",
					description = "Adds a short line of help under each control in this panel",
					icon = "settings",
				},
				value = t.Facet.Compose.cell(true),
			},
		}
	end, { theme = chosen.package, size = Vector2.new(320, 400) })
	t.settle(15)
	local root = t.find(stage, "Hints")
	local hint = root and drawn(root, "Adds a short line of help under each control in this panel")
	local indicator = root and t.find(root, "Indicator")
	t.check(`{chosen.name} described toggle mounted`, hint ~= nil and indicator ~= nil)
	if not (root and hint and indicator) then
		return
	end
	local box, words, mark = t.rect(root), t.rect(hint), t.rect(indicator)
	t.check("the row keeps its 320 px width", math.abs(box.w - 320) <= 1, box.w)
	t.check(
		"the description stays inside the row",
		words.b <= box.b + 1 and words.x >= box.x - 1 and words.r <= box.r + 1,
		{ words, box }
	)
	t.check("the description ends before the trailing switch", words.r <= mark.x + 1, { words.r, mark.x })
	t.check("the label column is more than twice the switch", words.w > mark.w * 2, { words.w, mark.w })
end)

add("padded-text-draws-inside-its-inset", { "mech3-76" }, function(t: any)
	local stage = t.mount(function(UI, Host)
		return UI.Text "Padded" {
			text = "A padded paragraph that wraps across several lines inside its box",
			Size = UDim2.fromOffset(200, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			Host.UIPadding {
				PaddingLeft = UDim.new(0, 20),
				PaddingRight = UDim.new(0, 20),
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
			},
		}
	end, { size = Vector2.new(400, 400) })
	t.settle(10)
	local label = t.find(stage, "Padded")
	t.check("the padded text mounted", label ~= nil)
	if label == nil then
		return
	end
	t.check("the glyphs fit the padded width", label.TextBounds.X <= label.AbsoluteSize.X - 40 + 1, {
		bounds = label.TextBounds.X,
		box = label.AbsoluteSize.X,
	})
	t.check("the box grows to hold the padded lines", label.AbsoluteSize.Y >= label.TextBounds.Y + 16 - 1, {
		bounds = label.TextBounds.Y,
		box = label.AbsoluteSize.Y,
	})
	t.check("the text wraps to more than one line", label.TextBounds.Y > label.TextSize * 1.5, label.TextBounds.Y)
end)

return cases
