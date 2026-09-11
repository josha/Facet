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

local UI = Facet.UI

local function packageMetrics(name: string): any
	local pkg = (require)(`../examples/themes/{name}`).build(Facet.themes)
	return snapshot.resolve(pkg, nil, {})
end

local THEMES = {
	{ id = "facet-neutral", metrics = nil },
	{ id = "glossy-touch", metrics = packageMetrics("glossy_touch") },
	{ id = "pixel-quest", metrics = packageMetrics("pixel_quest") },
	{ id = "fantasy-ornate", metrics = packageMetrics("fantasy_ornate") },
}

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
						else
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
