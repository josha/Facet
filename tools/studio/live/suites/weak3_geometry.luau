--!strict
local GuiService = game:GetService("GuiService")

local cases: { any } = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function interactive(
	id: string,
	contracts: { string },
	plan: string,
	setup: (any) -> any,
	steps: { [string]: (any, any) -> () }
)
	table.insert(cases, { id = id, contracts = contracts, plan = plan, setup = setup, steps = steps })
end

local function selectedName(): string
	local selected = GuiService.SelectedObject
	return if selected then selected.Name else "nil"
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

local function overlap(a: any, b: any): boolean
	local w = math.min(a.r, b.r) - math.max(a.x, b.x)
	local h = math.min(a.b, b.b) - math.max(a.y, b.y)
	return w > 0.5 and h > 0.5
end

local function scenario(t: any, name: string, options: { [string]: any }?): (any, any)
	local config: { [string]: any } = options or {}
	local built: any
	local stage = t.mount(function(UI: any, Host: any, Compose: any, env: any)
		built = t.scenario(name).build(t.context(UI, Host, Compose, env))
		return if type(built) == "function" then built() else built.screen()
	end, {
		size = config.size,
		theme = config.theme,
		reducedMotion = config.reducedMotion,
		frames = config.frames or 20,
	})
	return stage, built
end

local ELLIPSIS = "\u{2026}"
local COASTAL = "Coastal circuit reverse night lap 14"

local function labelHolder(t: any, text: any, width: any, extra: { [string]: any }?, options: { [string]: any }?): any
	return t.mount(function(UI: any, Host: any, Compose: any)
		local spec: { [any]: any } = { Name = "Cut", text = text, truncate = "middle" }
		for key, value in extra or {} do
			spec[key] = value
		end
		return Host.Frame({
			Name = "Holder",
			BackgroundTransparency = 1,
			Size = function(use: any)
				local value = if Compose.isReadable(width) then use(width) else width
				return UDim2.fromOffset(value, 40)
			end,
			UI.Text(spec),
		})
	end, options or { size = Vector2.new(800, 400) })
end

add("label-middle-truncation-real-bounds", { "mech2-46" }, function(t)
	local Compose = t.Facet.Compose
	local width = Compose.cell(60)
	local stage = labelHolder(t, COASTAL, width)
	local label = t.find(stage, "Cut")
	t.check("the middle-cut label mounts as a TextLabel", label ~= nil and label:IsA("TextLabel"))
	if not label then
		return
	end
	for _, w in { 60, 120, 200 } do
		width:set(w)
		t.settle(6)
		local text = label.ContentText
		t.note(`{w} px painted`, { text, label.TextBounds, label.AbsoluteSize })
		t.check(`{w} px: the box is the offered width`, math.abs(label.AbsoluteSize.X - w) <= 0.5, label.AbsoluteSize)
		t.check(`{w} px: the painted line fits the width`, label.TextBounds.X <= w + 0.5, label.TextBounds)
		t.check(`{w} px: an ellipsis stands between head and tail`, string.find(text, ELLIPSIS, 1, true) ~= nil, text)
		t.check(`{w} px: the head is kept`, string.sub(text, 1, 1) == "C", text)
		t.check(`{w} px: the tail is kept`, string.sub(text, -2) == "14", text)
		t.check(`{w} px: one line`, label.TextBounds.Y <= label.AbsoluteSize.Y + 0.5 and not label.TextWrapped)
	end
	width:set(400)
	t.settle(6)
	t.check("the whole value paints when it fits", label.ContentText == COASTAL, label.ContentText)
	width:set(1)
	t.settle(6)
	t.check("only the ellipsis paints when nothing fits", label.ContentText == ELLIPSIS, label.ContentText)
	width:set(120)
	t.settle(6)
	local narrow = label.ContentText
	local changes = 0
	local connection = label:GetPropertyChangedSignal("Text"):Connect(function()
		changes += 1
	end)
	t.settle(20)
	t.check("nothing is re-measured while the width, text and size stay", changes == 0, changes)
	width:set(240)
	t.settle(6)
	connection:Disconnect()
	t.check("a width change re-measures the cut", changes > 0 and label.ContentText ~= narrow, {
		changes = changes,
		before = narrow,
		after = label.ContentText,
	})
	t.check("the wider cut still fits", label.TextBounds.X <= 240.5, label.TextBounds)
	t.cleanup()
	local back = Compose.cell(60)
	local restore = labelHolder(t, "Coastal circuit", back)
	local short = t.find(restore, "Cut")
	t.check(
		"a narrow box cuts the short value",
		short ~= nil and short.ContentText ~= "Coastal circuit",
		short and short.ContentText
	)
	back:set(560)
	t.settle(6)
	t.check(
		"the whole value is restored when the box grows back",
		short ~= nil and short.ContentText == "Coastal circuit",
		short and short.ContentText
	)
	t.cleanup()
	local accented = "Piloté circuit côtier — réservé"
	local multi = labelHolder(t, accented, 90)
	local cut = t.find(multi, "Cut")
	t.check(
		"a cut never splits a multi-byte character",
		cut ~= nil and utf8.len(cut.ContentText) ~= nil and string.find(cut.ContentText, ELLIPSIS, 1, true) ~= nil,
		cut and cut.ContentText
	)
	t.check("the accented cut fits 90 px", cut ~= nil and cut.TextBounds.X <= 90.5, cut and cut.TextBounds)
end)

add("label-middle-truncation-follows-a-theme-text-change", { "mech2-46" }, function(t)
	local Compose = t.Facet.Compose
	local base = t.themes[1].package
	local themeCell: any
	local stage = t.mount(function(UI: any, Host: any, _: any, env: any)
		themeCell = env.theme
		return Host.Frame({
			Name = "Holder",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(160, 60),
			UI.Text({ Name = "Cut", text = COASTAL, truncate = "middle" }),
		})
	end, { size = Vector2.new(800, 400) })
	local label = t.find(stage, "Cut")
	t.check("the label mounts", label ~= nil)
	if not label then
		return
	end
	local before = { label.ContentText, label.TextBounds }
	t.check("the base cut fits 160 px", label.TextBounds.X <= 160.5, before)
	themeCell:set(grown(t, base, 14))
	t.settle(10)
	local after = { label.ContentText, label.TextBounds, label:GetStyled("TextSize") }
	t.note("cut before and after the +14 theme", { before = before, after = after })
	t.check("a grown theme text size re-derives the cut", label.ContentText ~= before[1], after)
	t.check("the grown cut still fits 160 px", label.TextBounds.X <= 160.5, after)
	t.check(
		"the grown cut keeps the head and the tail",
		string.sub(label.ContentText, 1, 1) == "C" and string.sub(label.ContentText, -2) == "14",
		after
	)
	themeCell:set(base)
	t.settle(10)
	t.check("the base theme restores the base cut", label.ContentText == before[1], { label.ContentText, before[1] })
	local _ = Compose
end)

local TextService = game:GetService("TextService")
local SPONSOR = "Sponsor a Race"

local function boundsAt(label: any, size: number): Vector2
	local params = Instance.new("GetTextBoundsParams")
	params.Text = label.ContentText
	params.Font = label:GetStyled("FontFace")
	params.Size = size
	params.Width = label.AbsoluteSize.X
	return TextService:GetTextBoundsAsync(params)
end

local function paintedSize(label: any): number
	local target = label.TextBounds
	local best, gap = 0, math.huge
	for size = 1, 100 do
		local b = boundsAt(label, size)
		local miss = math.abs(b.X - target.X) + math.abs(b.Y - target.Y)
		if miss < gap then
			best, gap = size, miss
		end
	end
	return best
end

local function fitsAt(label: any, size: number): boolean
	local b = boundsAt(label, size)
	return b.X <= label.AbsoluteSize.X + 0.5 and b.Y <= label.AbsoluteSize.Y + 0.5
end

local function fitBox(t: any, text: string, w: number, h: number, textSize: any, theme: any?): any
	local stage = t.mount(function(UI: any, Host: any)
		return Host.Frame({
			Name = "Box",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(w, h),
			UI.Text({ Name = "Cta", text = text, textSize = textSize }),
		})
	end, { size = Vector2.new(800, 400), theme = theme })
	return t.find(stage, "Cta")
end

add("label-text-size-fit-real-engine", { "mech3-83" }, function(t)
	local base = t.themes[1].package
	local body = base.metrics.typography.body.size
	local caption = base.metrics.typography.caption.size
	local title = base.metrics.typography.title.size
	t.note("theme role sizes", { body = body, caption = caption, title = title })
	local go = fitBox(t, "Go", 240, 52, "fit")
	t.check("a fitting label mounts with TextScaled", go ~= nil and go.TextScaled == true)
	if go then
		local painted = paintedSize(go)
		t.note("Go painted", { painted, go.TextBounds, go.AbsoluteSize, go.TextFits })
		t.near("a label that fits paints the cap (body)", painted, body, 0)
	end
	t.cleanup()
	local long = fitBox(t, SPONSOR, 80, 24, "fit")
	if long then
		local painted = paintedSize(long)
		t.note("Sponsor painted in 80x24", { painted, long.TextBounds, long.AbsoluteSize, long.TextFits })
		t.check("the size comes down from the cap", painted < body, { painted = painted, cap = body })
		t.check("the painted size fits the 80x24 box", fitsAt(long, painted) and long.TextFits, long.TextBounds)
		t.check("one size larger would not fit, so it is the largest that fits", not fitsAt(long, painted + 1), painted)
		t.check("the painted size never goes under the caption floor", painted >= caption, painted)
		t.inside("the reserved box holds the painted line", {
			x = long.AbsolutePosition.X,
			y = long.AbsolutePosition.Y,
			w = long.TextBounds.X,
			h = long.TextBounds.Y,
			r = long.AbsolutePosition.X + long.TextBounds.X,
			b = long.AbsolutePosition.Y + long.TextBounds.Y,
		}, long)
	end
	t.cleanup()
	local floored = fitBox(t, "Sponsorship", 40, 52, { fit = { cap = "title", floor = 12 } })
	if floored then
		local painted = paintedSize(floored)
		t.note("floored painted", { painted, floored.TextBounds, floored.AbsoluteSize, floored.TextFits })
		t.note("explicit floor 12 estimated painted size", painted)
		local band = floored:FindFirstChildOfClass("UITextSizeConstraint")
		t.check(
			"the explicit band reaches the engine as 12..title",
			band ~= nil and band.MinTextSize == 12 and band.MaxTextSize == title,
			band and { band.MinTextSize, band.MaxTextSize }
		)
	end
	t.cleanup()
	local capped = fitBox(t, "Go", 240, 52, { fit = { cap = "caption" } })
	if capped then
		t.near("a cap named by role paints that role's size", paintedSize(capped), caption, 0)
	end
	t.cleanup()
	local tiny = fitBox(t, "Sponsorship", 20, 52, "fit")
	if tiny then
		t.note("default floor estimated painted size", { paintedSize(tiny), tiny.TextBounds, tiny.TextFits })
		local band = tiny:FindFirstChildOfClass("UITextSizeConstraint")
		t.check(
			"the default floor reaches the engine as the caption role",
			band ~= nil and band.MinTextSize == caption,
			band and band.MinTextSize
		)
	end
	t.cleanup()
	local offset = 14
	local raised = grown(t, base, offset)
	local raisedGo = fitBox(t, "Go", 240, 52, "fit", raised)
	if raisedGo then
		t.near("under the +14 theme a fitting label paints the grown cap", paintedSize(raisedGo), body + offset, 0)
	end
	t.cleanup()
	local plain = fitBox(t, SPONSOR, 160, 52, "fit")
	local plainSize = if plain then paintedSize(plain) else 0
	t.cleanup()
	local raisedLong = fitBox(t, SPONSOR, 160, 52, "fit", raised)
	if raisedLong then
		local painted = paintedSize(raisedLong)
		t.note(
			"Sponsor at 160 px plain and +14",
			{ plain = plainSize, raised = painted, bounds = raisedLong.TextBounds }
		)
		t.check("the +14 theme grows the painted size above the plain one", painted > plainSize, { plainSize, painted })
		t.check(
			"the +14 theme steps down below its grown cap when 160 px cannot hold it",
			painted < body + offset,
			painted
		)
		t.check(
			"the grown painted text still fits its 160x52 box",
			raisedLong.TextFits and fitsAt(raisedLong, painted),
			raisedLong.TextBounds
		)
	end
end)

add("uicorner-per-corner-probe", { "post-recipes-09" }, function(t)
	local corner = Instance.new("UICorner")
	local found = {}
	for _, name in
		{
			"CornerRadius",
			"TopLeftRadius",
			"TopRightRadius",
			"BottomLeftRadius",
			"BottomRightRadius",
			"TopLeft",
			"TopRight",
			"BottomLeft",
			"BottomRight",
		}
	do
		local ok, value = pcall(function()
			return (corner :: any)[name]
		end)
		found[name] = if ok then tostring(value) else false
	end
	corner:Destroy()
	t.note("UICorner properties", found)
	local perCorner = found.TopLeftRadius ~= false or found.TopLeft ~= false
	t.note("per-corner radii available", perCorner)
	t.check("the UICorner property probe ran and CornerRadius exists", found.CornerRadius ~= false, found)
end)

local _ = scenario
local _ = interactive
local _ = selectedName
local _ = overlap

return cases
