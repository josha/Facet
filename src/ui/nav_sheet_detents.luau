--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local Overlay = require("./overlay_types")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local freeze = require("./freeze")
local NavigationProps = require("./navigation_props")

export type Detent = { id: string, fraction: number?, height: number?, hug: boolean, index: number }
export type Prepared = { detents: { Detent }, byId: { [string]: Detent }, cancel: Overlay.Action? }
export type Detents = {
	prepare: (NavigationProps.SheetSpec) -> Prepared,
	word: (string) -> string,
	writableDetent: (NavigationProps.SheetSpec, Prepared) -> ComposeTypes.Value<string>,
}

local PLACEMENTS: { [string]: boolean } =
	freeze({ automatic = true, adaptive = true, bottom = true, side = true, center = true })

return function(ctx: Types.Context): Detents
	local function prepare(spec: NavigationProps.SheetSpec): Prepared
		assert(
			spec.detent == nil or type(spec.detent) == "string" or (type(spec.detent) == "table" and spec.detent.set),
			"Sheet.detent requires a detent id or a writable Compose cell"
		)
		local placement = spec.placement or "automatic"
		assert(PLACEMENTS[placement], "Sheet.placement must be automatic, adaptive, bottom, side or center")
		assert(
			spec.edge == nil
				or ((placement == "side" or placement == "adaptive") and (spec.edge == "left" or spec.edge == "right")),
			"Sheet.edge is left or right, and only with placement side or adaptive"
		)
		parts.checkPreset(ctx, "Sheet", "width", spec.width, parts.WIDTH_PRESETS)
		assert(
			spec.closeButton == nil
				or type(spec.closeButton) == "boolean"
				or parts.bound(ctx, spec.closeButton, "string"),
			"Sheet.closeButton must be a boolean or a label"
		)
		local header = spec.header
		assert(
			header == nil or header == false or parts.instance(header) or type(header) == "function",
			"Sheet.header must be an Instance, a content factory or false"
		)
		assert(
			spec.contentInset == nil or spec.contentInset == "standard" or spec.contentInset == "none",
			"Sheet.contentInset must be standard or none"
		)
		assert(
			spec.actionLayout == nil
				or spec.actionLayout == "automatic"
				or spec.actionLayout == "row"
				or spec.actionLayout == "stacked",
			"Sheet.actionLayout must be automatic, row or stacked"
		)
		assert(
			spec.scrollPolicy == nil or spec.scrollPolicy == "always" or spec.scrollPolicy == "atLargestDetent",
			"Sheet.scrollPolicy must be always or atLargestDetent"
		)
		assert(
			spec.dragIndicator == nil
				or spec.dragIndicator == "automatic"
				or spec.dragIndicator == "visible"
				or spec.dragIndicator == "hidden",
			"Sheet.dragIndicator must be automatic, visible or hidden"
		)
		parts.checkHero("UI.Sheet", spec.hero)
		parts.checkActions(ctx, "UI.Sheet", spec.actions, math.huge)
		local cancel: Overlay.Action? = nil
		local listed: { Overlay.Action } = spec.actions or {}
		for _, action in listed do
			if action.role == "cancel" then
				cancel = action
			end
		end
		local detents: { Detent } = {}
		local byId: { [string]: Detent } = {}
		local entries: { Nav.SheetDetent } = spec.detents or { "medium", "large" }
		assert(#entries > 0, "Invalid Sheet detent")
		for index, entry in entries do
			local d: Detent = { id = "", fraction = nil, height = nil, hug = false, index = index }
			if entry == "medium" then
				d.id, d.fraction = "medium", 0.5
			elseif entry == "large" then
				d.id, d.fraction = "large", 0.95
			elseif entry == "hug" then
				d.id, d.hug = "hug", true
			else
				assert(type(entry) == "table", "Invalid Sheet detent")
				local custom = entry
				for key in custom do
					assert(key == "id" or key == "fraction" or key == "height", "Invalid Sheet detent")
				end
				assert(type(custom.id) == "string" and custom.id ~= "", "Invalid Sheet detent")
				assert(
					(custom.fraction == nil) ~= (custom.height == nil),
					"Sheet detent requires exactly one of fraction or height"
				)
				local fraction, height = custom.fraction, custom.height
				assert(
					if fraction ~= nil
						then type(fraction) == "number" and fraction > 0 and fraction <= 1
						else type(height) == "number" and height > 0 and height < math.huge,
					"Invalid Sheet detent extent"
				)
				d.id = custom.id
				d.fraction = fraction
				d.height = height
			end
			assert(not byId[d.id], "Sheet detents require unique ids")
			byId[d.id] = d
			table.insert(detents, d)
		end
		return { detents = detents, byId = byId, cancel = cancel }
	end

	local function word(id: string): string
		if id == "hug" then
			return "Fit"
		end
		return string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2)
	end

	local function writableDetent(spec: NavigationProps.SheetSpec, prepared: Prepared): ComposeTypes.Value<string>
		local authored = spec.detent
		if type(authored) == "table" then
			return authored
		end
		local initial = if type(authored) == "string" and prepared.byId[authored]
			then authored
			else prepared.detents[1].id
		return ctx.Compose.cell(initial)
	end
	return { prepare = prepare, word = word, writableDetent = writableDetent }
end
