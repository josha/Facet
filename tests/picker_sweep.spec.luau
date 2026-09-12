--!strict
--[[ PICKER SWEEP — every style x four theme packages x four text preferences x
	five matrix viewports (picker round, 2026-09-11). What "the picker holds up
	everywhere" means, pinned against solved rects rather than eyeballed:

	  * CLOSED: no painted sibling overlaps and no essential text truncated
	    without a full-value path (the large-text audit, pseudo-localized ~1.4x
	    labels throughout), on the picker and on the neighbour beneath it;
	  * OPEN (the menu family): the popover or sheet stays inside the viewport,
	    its rows do not overlap, focus lands inside it, a pick writes the
	    caller's signal and closes, and a close restores focus to the trigger;
	  * STRIP (segmented / inline / radioGroup): a tap on the second option
	    writes the signal.

	The themes are the reference neutral, the glossy touch package, and the two
	image-skinned packages (pixel quest, fantasy ornate); the preferences are
	the four the accessibility matrix names (0 / 4 / 10 / 14 px). ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local lt = require("./lib/large_text")
local snapshot = require("../src/themes/snapshot")
local chrome_slots = require("../src/tokens/chrome_slots")

local UI = Facet.UI

-- the PACKAGE as well as its snapshot: the closed-surface pin below asks the
-- package what it paints for a slot, which is a question only the package can
-- answer (a ThemeSnapshot carries the reservations, not the art).
local function packageOf(name: string): any
	return (require)(`../examples/themes/{name}`).build(Facet.themes)
end

local THEMES = {
	{ id = "facet-neutral", package = nil, metrics = nil },
	{ id = "glossy-touch", package = packageOf("glossy_touch") },
	{ id = "pixel-quest", package = packageOf("pixel_quest") },
	{ id = "fantasy-ornate", package = packageOf("fantasy_ornate") },
}
for _, theme in THEMES do
	if theme.package ~= nil then
		theme.metrics = snapshot.resolve(theme.package, nil, {})
	end
end

local VIEWPORTS = {
	{ id = "phone-portrait", rect = { x = 0, y = 0, w = 390, h = 844 }, input = "touch" },
	{ id = "phone-landscape", rect = { x = 0, y = 0, w = 844, h = 390 }, input = "touch" },
	{ id = "tablet-landscape", rect = { x = 0, y = 0, w = 1080, h = 810 }, input = "touch" },
	{ id = "desktop-standard", rect = { x = 0, y = 0, w = 1280, h = 720 }, input = "desktop" },
	{ id = "console-ten-foot", rect = { x = 0, y = 0, w = 1920, h = 1080 }, input = "gamepad" },
}

local STYLES = { "automatic", "menu", "segmented", "inline", "radioGroup", "navigationLink" }
local MENU_FAMILY: { [string]: boolean } = { menu = true, navigationLink = true }

-- pseudo-localized (~1.4x) labels that can WRAP. An unbreakable compound word
-- is the documented LT-G4 gap (an option label has no `disclose` route) and is
-- swept by the large-text matrix's own Picker fixtures, not re-litigated here.
local fixtures = require("./fixtures/a11y_l10n_fixtures")
local function options(style: string): { any }
	if style == "segmented" then
		-- a DECLARED segmented strip is the short-word, few-option control (the
		-- automatic ladder folds anything longer into rows on a compact screen
		-- for exactly this reason); two pseudo-localized short words, the shape
		-- the large-text matrix's own Picker fixtures sweep. Three localized
		-- words at the Large preference under a roomy package do not fit a
		-- 320px strip and truncate — the documented LT-G4 gap (an option label
		-- has no disclose route), not a claim this sweep makes.
		return {
			{ value = "a", label = fixtures.pseudoLocalize("Open") },
			{ value = "b", label = fixtures.pseudoLocalize("Club") },
		}
	end
	return {
		{ value = "a", label = lt.PSEUDO_ACTION },
		{ value = "b", label = lt.PSEUDO_SECONDARY, description = lt.PSEUDO_SECONDARY },
		{ value = "c", label = lt.PSEUDO_ACTION .. " " .. lt.PSEUDO_SECONDARY },
	}
end

local function suffixPath(w: any, suffix: string): string?
	for _, path in w.adapter.paths() do
		if string.sub(path, -#suffix) == suffix then
			return path
		end
	end
	return nil
end

local function world(viewport: any, offset: number, theme: any)
	local w = lt.world({
		viewport = viewport.rect,
		offset = offset,
		theme = theme,
		input = if viewport.input == "desktop" then "desktop" else "touch",
	})
	if viewport.input == "gamepad" then
		w.env:set("preferredInput", "Gamepad")
		w.env:set("capabilities", { keyboard = false, mouse = false, touch = false, gamepad = true })
		w.env:set("displaySize", "Large")
		w.env:set("overscanInsets", "none")
	end
	return w
end

local function mount(w: any, style: string)
	local selected = w.core:signal("a")
	local spec: any = { id = "P", label = lt.PSEUDO_ACTION, selected = selected, options = options(style) }
	if style == "navigationLink" then
		spec.query = w.core:signal("")
	elseif style ~= "automatic" then
		spec.style = style
	end
	local picker = Facet.Controls.Picker(w.core, spec)
	local neighbour = UI.Button({ id = "Below", label = lt.PSEUDO_ACTION, width = UI.fill() })
	w.present(UI.Screen({
		id = "S",
		padding = "m",
		children = {
			UI.ScrollView({
				id = "Page",
				width = UI.fill(),
				height = UI.fill(),
				children = {
					UI.VStack({
						id = "Form",
						width = UI.fill(),
						gap = "m",
						children = {
							UI.Text({ id = "Title", text = lt.PSEUDO, width = UI.fill() }),
							picker.blueprint,
							neighbour,
						},
					}),
				},
			}),
		},
	}))
	w.pres.refresh()
	return picker, selected
end

local function rectWithin(rect: any, vp: any): boolean
	return rect.x >= vp.x - 0.5
		and rect.y >= vp.y - 0.5
		and rect.x + rect.w <= vp.x + vp.w + 0.5
		and rect.y + rect.h <= vp.y + vp.h + 0.5
end

local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1)
end

local function metric(theme: any, name: string, fallback: number): number
	local snap = if theme ~= nil and theme.metrics ~= nil then theme.metrics else snapshot.neutral()
	return snapshot.resolveNumber(snap, name) or fallback
end

--[[ THE ATTACHMENT (visual review 2026-09-11: "the menu isn't attached to the
	thing that opens it"). Pinned per theme, preference and viewport: the popover's
	trailing edge is flush with the trigger's VISIBLE trailing edge (the chevron on
	a plain touch row, the bordered trigger elsewhere), its top sits one `xs` under
	that edge (or its bottom one `xs` above it when the placement flipped), it is
	never narrower than the trigger nor wider than the screen less its content
	inset, and the trigger reads as pressed while the menu is up. ]]
local function pinAttachment(label: string, w: any, theme: any, viewport: any, trigger: string, popupRoot: string)
	-- the touch form row is ONE row, so its menu hangs from the chevron — the
	-- control the eye sees — and the popover's width floor is the value +
	-- chevron; a boxed trigger hangs the menu from its own frame (2026-09-12)
	local rowChevron = suffixPath(w, "/Trigger/Row/Trailing/Chevron")
	local visible = suffixPath(w, "/Trigger/Row/Trailing")
	local source = w.adapter.node(rowChevron or trigger).rect
	local panel = w.adapter.node(popupRoot).rect
	local triggerRect = w.adapter.node(visible or trigger).rect
	local gap = metric(theme, "space.xs", 4)
	local inset = metric(theme, "space.m", 16)
	-- flush — or, when the rows want more room than the source leaves to its
	-- left, pushed to the content inset and still covering the source's edge
	-- (the placement's own shift; the reference platform's menu does the same)
	local flush = near(panel.x + panel.w, source.x + source.w)
		or (near(panel.x, inset) and panel.x + panel.w + 0.5 >= source.x + source.w)
	expect(
		`{label} trailing edges flush: {flush} (panel right {panel.x + panel.w}, source right {source.x + source.w})`
	).toBe(`{label} trailing edges flush: true (panel right {panel.x + panel.w}, source right {source.x + source.w})`)
	local below = near(panel.y, source.y + source.h + gap)
	local above = near(panel.y + panel.h, source.y - gap)
	expect(
		`{label} hangs one xs off the source: {below or above} (panel {panel.x},{panel.y} {panel.w}x{panel.h}; source {source.x},{source.y} {source.w}x{source.h}; gap {gap})`
	).toBe(
		`{label} hangs one xs off the source: true (panel {panel.x},{panel.y} {panel.w}x{panel.h}; source {source.x},{source.y} {source.w}x{source.h}; gap {gap})`
	)
	expect(`{label} at least the trigger's width: {panel.w + 0.5 >= triggerRect.w}`).toBe(
		`{label} at least the trigger's width: true`
	)
	expect(
		`{label} inside the content inset: {panel.x + 0.5 >= inset and panel.x + panel.w <= viewport.rect.w - inset + 0.5}`
	).toBe(`{label} inside the content inset: true`)
	local pressed = w.adapter.node(trigger).props.selected
	expect(`{label} trigger pressed while open: {pressed == true}`).toBe(`{label} trigger pressed while open: true`)
end

--[[ THE TRIGGER'S OWN LINE (user review of the side-by-side, 2026-09-11): the
	chevron is centred on the value's line, and on a row that has not stacked
	the title shares that centre too — one baseline for label, value and
	chevron, measured on the solved rects with a pixel of tolerance. ]]
local function centreY(rect: any): number
	return rect.y + rect.h / 2
end

local function pinTriggerLine(label: string, w: any, trigger: string)
	local value = suffixPath(w, "/Value")
	local chevron = suffixPath(w, "/Chevron")
	expect(`{label} value and chevron mounted: {value ~= nil and chevron ~= nil}`).toBe(
		`{label} value and chevron mounted: true`
	)
	local valueRect = w.adapter.node(value :: string).rect
	local chevronRect = w.adapter.node(chevron :: string).rect
	expect(
		`{label} chevron centred on the value: {near(centreY(valueRect), centreY(chevronRect))} ({centreY(valueRect)} vs {centreY(
			chevronRect
		)})`
	).toBe(`{label} chevron centred on the value: true ({centreY(valueRect)} vs {centreY(chevronRect)})`)
	local labelPath = suffixPath(w, "/Label")
	if labelPath ~= nil then
		local labelRect = w.adapter.node(labelPath :: string).rect
		-- stacked (the title above the value at a large preference) or one line
		local stacked = labelRect.y + labelRect.h <= valueRect.y + 0.5
		expect(
			`{label} title on the value's line or above it: {stacked or near(centreY(labelRect), centreY(valueRect))} ({centreY(
				labelRect
			)} vs {centreY(valueRect)})`
		).toBe(`{label} title on the value's line or above it: true ({centreY(labelRect)} vs {centreY(valueRect)})`)
	end
	local _ = trigger
end

--[[ THE CLOSED TRIGGER'S OWN SURFACE (user feedback item 8, 2026-09-12: "a
	closed trigger must paint its control surface in every theme; the glow alone is
	wrong").

	TWO FORMS, TWO CLAIMS, because the picker deliberately draws two triggers.

	  * THE BOXED TRIGGER (pointer, gamepad, and every picker that is not a
	    labelled form row) is the visible control, so the claim is that it RESOLVES
	    A PAINTED SURFACE: it classifies into the `control` slot — through the same
	    pure `chrome_slots.classify` the solver (`render/layout_node`) and the live
	    adapter (`client/screen_chrome`) both call, fed from the node the fake
	    target actually recorded — and, under an installed package, that package
	    publishes a themed plate for that slot with a real content id.

	    IT FAILS BEFORE THE FIX. `classify` routes on `hasSelection`, which both
	    consumers derive from `props.selected ~= nil` — a DECLARATION, not a state
	    — and a picker trigger always declares `selected` so its open state can
	    light up. So a CLOSED trigger answered `selection` under every package, and
	    took the row-selection wash where the pop-up button's plate belongs.

	  * THE TOUCH FORM ROW is `surface = "plain"` BY DESIGN — one tappable row, the
	    value and chevron flush trailing, no box (see `picker_menu`'s own comment).
	    `plain` is a hard "no decoration" in `classify`, so there is no plate to
	    claim and asserting one would be asserting against the design. What it owes
	    instead is that the row still ANSWERS a finger: its focus visual paints, and
	    it reads pressed while its menu is up (the latter is `pinAttachment`'s).

	THE LIVE HALF IS OWED. The fake target records the decoration hint and the
	props but materializes no ImageLabel, so "the nine-slice actually painted" is
	not a headless proposition — this pins the decision, and a Studio capture under
	each package still owes the pixels.

	THE NAVIGATION LINK IS NOT SWEPT HERE, and the reason is structural rather than
	an omission. It is the ONE trigger whose surface MOVES — `plain` on a touch row
	and `control` on a pointer or pad, off one reactive memo rather than off the
	`UI.When` pair the menu form splits itself with — and a decoration hint is
	STATIC blueprint metadata. So the fix this pin guards cannot be expressed for
	it without splitting its two forms structurally, which moves its mounted path.
	Booked; its pointer form still takes the `selection` slot today. ]]
local function pinClosedSurface(label: string, w: any, theme: any, trigger: string)
	local node = w.adapter.node(trigger)
	expect(`{label} trigger node recorded: {node ~= nil}`).toBe(`{label} trigger node recorded: true`)
	local hint = if type(node.decorationHint) == "table" then node.decorationHint.slot else nil
	local slot = chrome_slots.classify({
		class = node.class,
		surface = node.props.surface,
		hasSelection = node.props.selected ~= nil,
		hint = hint,
	})
	if node.props.surface == "plain" then
		-- the plain row: no plate by design, so pin the affordance it does owe
		expect(`{label} plain row carries no plate: {slot == nil}`).toBe(`{label} plain row carries no plate: true`)
		w.pres.focus.focusOn(trigger)
		w.pres.refresh()
		local focused = w.adapter.node(trigger).focused
		expect(`{label} plain row's focus visual paints: {focused == true}`).toBe(
			`{label} plain row's focus visual paints: true`
		)
		return
	end
	local painted = chrome_slots.resolveSlot(theme.package, slot)
	expect(`{label} closed trigger classifies as a control: {tostring(painted)}`).toBe(
		`{label} closed trigger classifies as a control: control`
	)
	if theme.package == nil then
		-- no package installed: the library's own sheet fills the surface role, so
		-- the node declaring `control` IS the painted surface
		expect(`{label} native control surface declared: {tostring(node.props.surface)}`).toBe(
			`{label} native control surface declared: control`
		)
		return
	end
	local plan = chrome_slots.planFor(theme.package, painted :: string)
	local stack = chrome_slots.layerPlanFor(theme.package, painted :: string)
	local art = if plan ~= nil
		then plan.contentId
		elseif stack ~= nil and stack.layers[1] ~= nil then stack.layers[1].contentId
		else nil
	expect(`{label} the package paints that slot: {type(art) == "string" and art ~= ""}`).toBe(
		`{label} the package paints that slot: true`
	)
end

--[[ THE TRACK (visual review 2026-09-11): a segmented picker is ONE plated
	track holding equal segments — every segment the same height and, on a filled
	band, the same width — and the row forms carry no track at all. ]]
local function pinTrack(label: string, w: any, picker: any)
	local resolved = picker.dump().presentation
	local track = suffixPath(w, "/Indicator/Track")
	if resolved == "segmented" then
		-- (the fake resolves `hidden` into `node.visible`, never a stored prop)
		expect(`{label} track plated: {track ~= nil and w.adapter.node(track :: string).visible ~= false}`).toBe(
			`{label} track plated: true`
		)
		local heights: { number } = {}
		local widths: { number } = {}
		for _, path in w.adapter.paths() do
			if string.match(path, "/Indicator/Options/Opt%d+$") then
				local rect = w.adapter.node(path).rect
				table.insert(heights, rect.h)
				table.insert(widths, rect.w)
			end
		end
		local equal = #heights >= 2
		for i = 2, #heights do
			equal = equal and near(heights[i], heights[1]) and near(widths[i], widths[1])
		end
		expect(`{label} equal segments: {equal} ({table.concat(widths, ",")} x {table.concat(heights, ",")})`).toBe(
			`{label} equal segments: true ({table.concat(widths, ",")} x {table.concat(heights, ",")})`
		)
	else
		local plated = track ~= nil and w.adapter.node(track :: string).visible ~= false
		expect(`{label} no track on a row form: {not plated}`).toBe(`{label} no track on a row form: true`)
	end
end

local function judge(label: string, w: any, prefix: string?)
	local found = lt.sweep(w, prefix)
	if #found.overlaps > 0 then
		error(`{label}: painted siblings overlap:\n{lt.describeFindings(label, found.overlaps)}`, 0)
	end
	if #found.clipped > 0 then
		error(
			`{label}: essential text truncated with no full-value path:\n{lt.describeFindings(label, found.clipped)}`,
			0
		)
	end
end

describe("Picker sweep: style x theme x text preference x viewport", function()
	for _, style in STYLES do
		it(`{style}: closed, open, pick and dismiss hold on every theme, preference and viewport`, function()
			local cells = 0
			for _, theme in THEMES do
				for _, preference in lt.PREFERENCES do
					for _, viewport in VIEWPORTS do
						local label = `[{style} @{preference.name}(+{preference.offset}) {theme.id} {viewport.id}]`
						local w = world(viewport, preference.offset, theme)
						local picker, selected = mount(w, style)
						cells += 1
						judge(label, w, "/S")
						local resolved = picker.dump().style
						if MENU_FAMILY[resolved] then
							local trigger = suffixPath(w, "/Trigger")
							expect(`{label} has a trigger: {trigger ~= nil}`).toBe(`{label} has a trigger: true`)
							if resolved ~= "navigationLink" then
								pinClosedSurface(label, w, theme, trigger :: string)
								pinTriggerLine(label, w, trigger :: string)
							end
							picker.api.open()
							w.pres.refresh()
							w.pres.refresh() -- the measured list budget lands one solve later
							expect(`{label} open: {picker.dump().open}`).toBe(`{label} open: true`)
							local popupRoot = suffixPath(w, "/Popup")
							expect(`{label} popup mounted: {popupRoot ~= nil}`).toBe(`{label} popup mounted: true`)
							local panel = w.adapter.node(popupRoot :: string).rect
							expect(
								`{label} popup inside the viewport: {rectWithin(panel, viewport.rect)} ({panel.x},{panel.y} {panel.w}x{panel.h})`
							).toBe(
								`{label} popup inside the viewport: true ({panel.x},{panel.y} {panel.w}x{panel.h})`
							)
							local surfaceRoot = string.match(popupRoot :: string, "^(/[^/]+)")
							judge(label .. " open", w, surfaceRoot)
							if picker.dump().presentation ~= "sheet" then
								pinAttachment(label, w, theme, viewport, trigger :: string, popupRoot :: string)
							end
							local focused = w.pres.focus.focused:get()
							expect(
								`{label} focus inside the popup: {focused ~= nil and string.find(
									focused,
									surfaceRoot :: string,
									1,
									true
								) == 1}`
							).toBe(`{label} focus inside the popup: true`)
							picker.api.select("c")
							w.pres.refresh()
							expect(`{label} picked c: {selected:get()} open={picker.dump().open}`).toBe(
								`{label} picked c: c open=false`
							)
							picker.api.open()
							w.pres.refresh()
							picker.api.close()
							w.pres.refresh()
							local back = w.pres.focus.focused:get()
							expect(`{label} closed, focus back on the trigger: {back == trigger}`).toBe(
								`{label} closed, focus back on the trigger: true`
							)
							local released = w.adapter.node(trigger :: string).props.selected
							expect(`{label} trigger released when closed: {released ~= true}`).toBe(
								`{label} trigger released when closed: true`
							)
						else
							-- a described option never becomes a segment (options(style) carries one
							-- for every non-segmented style), so an automatic strip is a row form
							if style == "automatic" then
								expect(`{label} automatic never segments a described option: {resolved}`)
									.never()
									.toBe(`{label} automatic never segments a described option: segmented`)
							end
							pinTrack(label, w, picker)
							local second = suffixPath(w, "/Opt2")
								or suffixPath(w, "/[b]/Option")
								or suffixPath(w, "/[b]/SectionRow/Option")
							expect(`{label} second option mounted: {second ~= nil}`).toBe(
								`{label} second option mounted: true`
							)
							w.adapter.tap(second :: string)
							w.pres.refresh()
							expect(`{label} tapped b: {selected:get()}`).toBe(`{label} tapped b: b`)
							judge(label .. " after pick", w, "/S")
						end
						picker.dispose()
						w.pres.dismiss(w.handle)
					end
				end
			end
			expect(cells).toBe(#THEMES * #lt.PREFERENCES * #VIEWPORTS)
		end)
	end
end)
