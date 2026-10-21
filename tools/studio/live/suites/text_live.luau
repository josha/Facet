--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
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

add("button-labels-centred-in-every-package", {}, function(t: any)
	for _, theme in t.themes do
		local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame "Row" {
				Size = UDim2.fromOffset(600, 80),
				BackgroundTransparency = 1,
				Host.UIListLayout { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12) } :: unknown,
				UI.Button "Word" { label = "Play" },
				UI.Button "Marked" { label = "Next", icon = "chevron.down" },
			}
		end, { theme = theme.package, size = Vector2.new(600, 200) })
		t.settle(10)
		for name, text in { Word = "Play", Marked = "Next" } :: { [string]: string } do
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

add("described-toggle-fits-a-narrow-row", {}, function(t: any)
	local chosen = t.themes[1]
	for _, theme in t.themes do
		if theme.name == "classic_desktop" then
			chosen = theme
		end
	end
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
		return Host.Frame "Column" {
			Size = UDim2.fromOffset(320, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Host.UIListLayout {} :: unknown,
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
	t.cleanup()
	local sides: { "leading" | "trailing" } = { "leading", "trailing" }
	for _, side in sides do
		local copy = "Keep frames aligned with the display"
		local hinted = t.mount(function(UI: FacetControls)
			return UI.Toggle "Hinted" {
				label = "Vertical sync",
				hint = copy,
				value = t.Facet.Compose.cell(true),
				controlSize = "large",
				indicatorPosition = side :: "leading" | "trailing",
				Size = UDim2.fromOffset(280, 0),
			}
		end, {
			theme = chosen.package,
			size = Vector2.new(320, 400),
			environment = { preferredTextSize = "Largest" },
		})
		local label = assert(drawn(hinted, copy))
		local switch = assert(t.find(hinted, "Indicator"))
		local toggle = assert(t.find(hinted, "Hinted"))
		local bounds, text, indicator = t.rect(toggle), t.rect(label), t.rect(switch)
		t.check(`the {side} hinted toggle keeps its width`, math.abs(bounds.w - 280) <= 1, bounds)
		t.check(`the {side} hint draws all text`, label.TextFits, { label.TextBounds, label.AbsoluteSize })
		t.inside(`the {side} hint stays inside the toggle`, label, toggle, 1)
		t.check(
			`the {side} indicator stays beside the hint`,
			if side == "leading" then indicator.r <= text.x + 1 else text.r <= indicator.x + 1,
			{ text, indicator }
		)
		t.cleanup()
	end
end)

add("padded-text-draws-inside-its-inset", {}, function(t: any)
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
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

add("wrapped-region-readouts-use-the-offered-column-width", {}, function(t)
	local stage = t.mount(function(UI: FacetControls)
		return UI.Composition "HUD" {
			UI.Region "Wallet" {
				zone = "topLeft",
				rank = 1,
				UI.VStack "Readouts" {
					width = 260,
					padding = "m",
					gap = "s",
					UI.Text "Balance" { text = "2,400 coins / 100 gems", wrap = true },
					UI.Text "Status" { text = "Progress saved in this session", wrap = true },
				},
				UI.Text { text = "2,400" },
			},
		}
	end, { size = Vector2.new(800, 600) })
	t.settle(20)
	local wallet = t.find(stage, "Wallet") :: Frame
	local readouts = t.find(stage, "Readouts") :: Frame
	local balance = t.find(stage, "Balance") :: TextLabel
	local status = t.find(stage, "Status") :: TextLabel
	t.check("the rich form fits", wallet:GetAttribute("FacetForm") == 1, wallet:GetAttribute("FacetForm"))
	t.check("the column keeps its authored width", math.abs(readouts.AbsoluteSize.X - 260) <= 1, readouts.AbsoluteSize)
	for _, label in { balance, status } do
		t.check(`{label.Name} uses the column width`, label.AbsoluteSize.X > 200, label.AbsoluteSize)
		t.check(`{label.Name} avoids a character-wide column`, label.AbsoluteSize.Y < 60, label.AbsoluteSize)
		t.check(`{label.Name} fits`, label.TextFits, { label.TextBounds, label.AbsoluteSize })
	end
end)

add("wrapped-text-resizes-and-keeps-explicit-sizing", {}, function(t)
	local stage = t.mount(function(UI: FacetControls)
		return UI.VStack "Column" {
			width = 320,
			gap = "s",
			UI.Text "Paragraph" {
				text = "Choose a kart, compare its handling and acceleration, then enter the next race with your friends.",
				wrap = true,
			},
			UI.Text "Explicit" {
				text = "Ready",
				wrap = true,
				Size = UDim2.fromOffset(100, 40),
				AutomaticSize = Enum.AutomaticSize.None,
			},
			UI.Text "Unwrapped" { text = "Ready" },
			UI.Text "NativeOverride" { text = "Ready", wrap = true, TextWrapped = false },
		}
	end, { size = Vector2.new(400, 500) })
	t.settle(20)
	local column = t.find(stage, "Column") :: Frame
	local paragraph = t.find(stage, "Paragraph") :: TextLabel
	local explicit = t.find(stage, "Explicit") :: TextLabel
	local unwrapped = t.find(stage, "Unwrapped") :: TextLabel
	local override = t.find(stage, "NativeOverride") :: TextLabel
	local wideHeight = paragraph.AbsoluteSize.Y
	t.near("paragraph fills the wide column", paragraph.AbsoluteSize.X, 320, 1)
	t.check("the wide paragraph fits", paragraph.TextFits)
	column.Size = UDim2.fromOffset(180, 0)
	t.settle(20)
	t.near("paragraph follows the narrow column", paragraph.AbsoluteSize.X, 180, 1)
	t.check("the narrow paragraph grows vertically", paragraph.AbsoluteSize.Y > wideHeight)
	t.check("the narrow paragraph fits", paragraph.TextFits)
	t.check("explicit sizing remains exact", explicit.AbsoluteSize == Vector2.new(100, 40), explicit.AbsoluteSize)
	t.check("unwrapped text hugs its content", unwrapped.AbsoluteSize.X < 100, unwrapped.AbsoluteSize)
	t.check("native wrapping override keeps content sizing", not override.TextWrapped and override.AbsoluteSize.X < 100)
end)

add("styled-caption-does-not-hide-the-composition", {}, function(t)
	t.device({ device = "hd_1080" })
	local Facet: typeof(require("@repo/tools/typecheck/aliases").FacetModule) = t.Facet
	local theme, report = Facet.themes.define({
		base = Facet.themes.neutralPackage(),
		identity = { id = "caption-readiness", displayName = "Caption readiness" },
		style = { defaultTheme = "Caption", themes = { { name = "Caption", colors = {} } } },
	})
	assert(report.ok and theme)
	local notice = Facet.Compose.cell("Welcome to ION Circuit · session progress stays until you leave")
	local app = Facet.app({ name = "CaptionReadiness", theme = theme })
	local UI = app.UI
	local _, stage = app.mount(function()
		return UI.Composition "HUD" {
			UI.Region "Feedback" {
				zone = "top",
				rank = 1,
				UI.VStack "Panel" {
					surface = "panel",
					padding = "s",
					width = 360,
					UI.Text "Caption" {
						text = notice,
						textRole = "caption",
						wrap = true,
						AutoLocalize = false,
					},
				},
			},
		}
	end)
	t.settle(120)
	notice:set("Confirmed · session saved")
	t.settle(120)
	local hud = t.find(stage, "HUD") :: Frame
	local fade = t.find(hud, "Fade") :: CanvasGroup?
	local caption = t.find(hud, "Caption") :: TextLabel
	t.check("the HUD finishes preparation", hud:GetAttribute("FacetPreparing") ~= true)
	t.check("the HUD is drawn", fade == nil or fade.GroupTransparency == 0, if fade then fade.GroupTransparency else 0)
	t.check("the caption fits", caption.TextFits, { caption.TextBounds, caption.AbsoluteSize })
	app.dispose()
end)

return cases
