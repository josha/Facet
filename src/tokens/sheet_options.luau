--!strict
-- The theme-optional paint both sheet builders add: the authored selection ink's
-- marks, the whole-control disabled dim, the inverse pair and the strong divider.
-- Every value here is what a theme AUTHORS or what its consumers painted before;
-- a theme that authors nothing gets byte-identical paint. Pure: tags come in.
local options = {}

local function color(c: any): any
	return { kind = "color", r = c.r, g = c.g, b = c.b }
end
local function lerp(a: any, b: any, t: number): any
	return { kind = "color", r = a.r + (b.r - a.r) * t, g = a.g + (b.g - a.g) * t, b = a.b + (b.b - a.b) * t }
end
local function num(v: number): any
	return { kind = "number", value = v }
end

-- the rules below key on `selection` being AUTHORED somewhere in the package
function options.authoredSelection(themes: { any }): boolean
	for _, theme in themes do
		if type(theme) == "table" and type(theme.extra) == "table" and theme.extra.selection ~= nil then
			return true
		end
	end
	return false
end

-- a strong divider's transparency: authored, or three times as visible as the hairline
function options.strongHairlineOpacity(x: any): number
	return x.strongHairlineOpacity or math.max(0, 1 - (1 - x.hairlineOpacity) * 3)
end

-- the optional tokens; `danger` is the effective danger plate
function options.tokens(c: any, x: any, danger: any): { [string]: any }
	local selection, inverse, onInverse =
		x.selection or c.accent, x.inverseSurface or c.contentStrong, x.onInverse or c.surface
	local dim = x.disabledContentOpacity or 0.4
	return {
		Selection = color(selection),
		OnSelection = color(x.onSelection or c.onAccent),
		Scrim = color(x.scrim or c.surface),
		InverseSurface = color(inverse),
		OnInverse = color(onInverse),
		InverseHover = lerp(inverse, onInverse, 0.12),
		InversePressed = lerp(inverse, onInverse, 0.2),
		-- each plate at the disabled content opacity over the page
		ControlDisabled = lerp(x.control, c.surface, dim),
		ControlSelectedDisabled = lerp(x.controlSelected, c.surface, dim),
		AccentDisabled = lerp(c.accent, c.surface, dim),
		DangerDisabled = lerp(danger, c.surface, dim),
		InverseDisabled = lerp(inverse, c.surface, dim),
		SelectionDisabled = lerp(selection, c.surface, dim),
	}
end

-- A selected chip, a checkbox's fill and tick, and a chosen link row wear the
-- authored ink; the hover rule keeps a hovered chosen chip chosen.
function options.emitSelectionMark(emitRest: (any) -> (), emitHover: (any) -> (), T: any)
	local chosen = `TextButton.{T.selected}.{T.selectionMark}`
	emitRest({
		name = "Selection mark — chosen",
		selector = chosen,
		props = { BackgroundColor3 = "$Selection", TextColor3 = "$OnSelection" },
	})
	emitRest({
		name = "Selection mark — fill",
		selector = `Frame.{T.selectionMark}`,
		props = { BackgroundColor3 = "$Selection", BackgroundTransparency = num(0) },
	})
	emitRest({
		name = "Selection mark — ink",
		selector = `TextLabel.{T.selectionMark}`,
		props = { TextColor3 = "$OnSelection" },
	})
	emitRest({
		name = "Selected link",
		selector = `TextButton.{T.selected}.{T.appearancePrefix}link`,
		props = { TextColor3 = "$Selection" },
	})
	emitHover({
		name = "Selection mark — chosen hover",
		selector = `{chosen}.{T.pointerLive}:Hover`,
		props = { BackgroundColor3 = "$Selection", TextColor3 = "$OnSelection" },
	})
end

-- the tick's icon art, after every icon and on-plate tint it has to beat
function options.markIconRule(T: any, iconTag: string): any
	return {
		name = "Selection mark — icon",
		selector = `.{T.selectionMark} > .{iconTag}`,
		props = { ImageColor3 = "$OnSelection" },
	}
end

-- `extra.dimDisabledPlates`: each plate blends toward the page with its label, on
-- the label dim's own engine state; a quiet word keeps its plate under a role.
function options.emitDisabledPlates(emit: (any) -> (), selectionMarks: boolean, T: any, disabledTag: string)
	local A = T.appearancePrefix
	local function plate(name: string, selector: string, token: string)
		emit({ name = `Disabled plate — {name}`, selector = selector, props = { BackgroundColor3 = token } })
	end
	plate("control", "TextButton:NonInteractable", "$ControlDisabled")
	plate("selected", `TextButton.{T.selected}:NonInteractable`, "$ControlSelectedDisabled")
	plate("accent", `TextButton.{T.surfacePrefix}accent:NonInteractable`, "$AccentDisabled")
	plate("emphasis", `TextButton.{A}emphasis:NonInteractable`, "$AccentDisabled")
	plate("inverse", `TextButton.{A}inverse:NonInteractable`, "$InverseDisabled")
	plate("soft", `TextButton.{A}soft:NonInteractable`, "$ControlSelectedDisabled")
	plate("utility", `TextButton.{A}utility:NonInteractable`, "$Surface")
	plate("destructive", "TextButton.facet-role-destructive:NonInteractable", "$DangerDisabled")
	plate("destructive soft", `TextButton.facet-role-destructive.{A}soft:NonInteractable`, "$ControlSelectedDisabled")
	plate("destructive utility", `TextButton.facet-role-destructive.{A}utility:NonInteractable`, "$Surface")
	plate("chip box", `Frame.{T.surfacePrefix}chip.{disabledTag}`, "$ControlDisabled")
	if selectionMarks then
		plate("chosen", `TextButton.{T.selected}.{T.selectionMark}:NonInteractable`, "$SelectionDisabled")
		plate("mark fill", `Frame.{T.selectionMark}.{disabledTag}`, "$SelectionDisabled")
	end
end

return options
