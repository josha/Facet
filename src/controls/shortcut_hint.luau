--!strict
-- Passive keycaps borrow live actions and own only their derived display state.
-- The plate has no decoration slot: theme tint, authored corner and hairline
-- cannot acquire panel insets or badge art. Rungs spend icon sizes, not hit floors.
local hint = require("../input/hint")
local keyNames = require("../input/key_names")
local specGuard = require("../spec_guard")
local selection = require("../selection_model")
local surfaceEnv = require("../env/surface_env")
local vocabulary = require("./control_vocabulary")

local shortcut_hint = {}

local Compose = require("../vendor/compose/core")
local contribution = require("../input/contribution")
local specTypes = require("../spec_types/shortcut_hint")
export type Spec = specTypes.Spec

local HINT_KEYS = specGuard.keySet({
	"action",
	"controlSize",
	"env",
	"id",
	"keys",
	"over",
	"separator",
})

local DEFAULT_SEPARATOR = "or"
local CAP_GAP = "controls.shortcutHint.capGap"
local DEFAULT_RUNG = "regular"
type Key = { text: string, glyph: string? }
local EMPTY_KEY: Key = table.freeze({ text = "", glyph = nil })
local function assertChords(id: string, keys: any)
	local function refuse(why: string): ()
		error(
			`Facet ShortcutHint('{id}'): \`keys\` is a list of alternatives, each a list of key `
				.. 'names — { { "Ctrl", "K" }, { "F1" } }. '
				.. why,
			0
		)
	end
	if type(keys) ~= "table" or #keys == 0 then
		refuse("It was empty or not a list.")
	end
	for _, chord in keys do
		if type(chord) ~= "table" or #chord == 0 then
			refuse("One alternative was empty or not a list.")
		end
		for _, key in chord do
			if type(key) ~= "string" or key == "" then
				refuse("One key was empty or not a string.")
			end
		end
	end
end

function shortcut_hint.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("ShortcutHint", spec, HINT_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "ShortcutHint"

	if (spec.action == nil) == (spec.keys == nil) then
		error(
			`Facet ShortcutHint('{id}'): give it \`action\` (the semantic action whose LIVE key to show) `
				.. "or `keys` (explicit chords), and exactly one of the two.",
			0
		)
	end
	if spec.action ~= nil and (type(spec.action) ~= "string" or spec.action == "") then
		error(`Facet ShortcutHint('{id}'): \`action\` is a semantic action NAME, never a key code.`, 0)
	end
	if spec.separator ~= nil and spec.keys == nil then
		error(
			`Facet ShortcutHint('{id}'): \`separator\` joins the alternatives in \`keys\`; the live `
				.. "`action` form shows one binding and has nothing to separate.",
			0
		)
	end
	if spec.keys ~= nil then
		assertChords(id, spec.keys)
	end
	local separatorNow = selection.read(spec.separator)
	if spec.separator ~= nil and (type(separatorNow) ~= "string" or separatorNow == "") then
		error(`Facet ShortcutHint('{id}'): \`separator\` is the player-visible word between alternatives.`, 0)
	end
	vocabulary.assertSize("ShortcutHint", spec.controlSize)
	vocabulary.assertOver("ShortcutHint", spec.over)
	local env = if spec.action ~= nil then spec.env or surfaceEnv.find(core) else nil
	if spec.action ~= nil and env == nil then
		error(
			`Facet ShortcutHint('{id}'): the live action form needs the surface environment; pass env when ambiguous.`,
			0
		)
	end
	local separator = spec.separator or DEFAULT_SEPARATOR
	-- the cap's outline is the theme's `controls.shortcutHint.capStroke` (Neutral: the
	-- hairline); 0 draws a soft filled cap with no outline
	local metricsEnv = env or surfaceEnv.find(core)
	local capStroke = Compose.formula(function(use)
		local metrics = if metricsEnv ~= nil then use(metricsEnv:get("themeMetrics")) else nil
		local family = if type(metrics) == "table" and metrics.controls then metrics.controls.shortcutHint else nil
		local thickness = if family then family.capStroke else nil
		if thickness == 0 then
			return nil
		end
		return Facet.UI.strokeData({ color = "hairline", thickness = thickness })
	end)

	local rung = selection.read(spec.controlSize) or DEFAULT_RUNG
	local function capDim(currentRung: any): any
		local icon = vocabulary.iconSizeFor(currentRung) or vocabulary.iconSizeFor(DEFAULT_RUNG)
		return { type = "minMax", min = { icon, "space.xs" } }
	end
	local capBox = vocabulary.deriveSize("ShortcutHint", spec.controlSize, capDim) or capDim(rung)

	local function cap(capId: string, text: any, glyph: any): any
		local content: any
		if glyph ~= nil then
			content = UI.Image({ id = "Glyph", image = glyph, width = capBox, height = capBox })
		else
			content = UI.Text({
				id = "Label",
				text = text,
				textSize = "label",
				textAlign = "center",
				tint = { role = "contentStrong", blend = 1 },
			})
		end

		if glyph == nil then
			content = UI.padding(content, { left = "space.xs", right = "space.xs", top = 0, bottom = 0 })
		end
		local plate = UI.corners(
			UI.Box({
				id = "Plate",
				tint = { role = "surfaceStrong", blend = 1 },
				width = UI.fill(),
				height = UI.fill(),
				stroke = capStroke,
			}),
			"control"
		)
		return UI.ZStack({
			id = capId,
			alignH = "center",
			alignV = "center",
			width = capBox,
			height = capBox,
			children = { plate, content },
		})
	end

	local children: { any } = {}

	local liveKey: any = nil
	local liveLabel: any = nil
	local liveGlyph: any = nil
	local bundle: any = nil
	if spec.action ~= nil then
		local systemSignal = Compose.cell(nil :: any)

		local surfaceContext: any = nil

		local effectiveInput = env:get("effectiveInput")
		liveKey = Compose.formula(function(use): Key
			local preferred = use(effectiveInput)

			if preferred == "Touch" then
				return EMPTY_KEY
			end
			local system = use(systemSignal)
			if system == nil then
				return EMPTY_KEY
			end
			use(system.revision)
			local found = system.actionNamed(spec.action, if surfaceContext ~= nil then surfaceContext() else nil)
			local binding = if found ~= nil then found.preferredBinding(preferred) else nil
			local text = hint.labelOf(binding)
			if text == "" then
				return EMPTY_KEY
			end
			return { text = text, glyph = keyNames.image(if binding ~= nil then binding.keyCode else nil) }
		end)
		liveLabel = Compose.formula(function(use)
			return (use(liveKey) :: any).text
		end)
		bundle = {
			bindActionSystem = function(actionSystem: any, contextOf: any)
				surfaceContext = contextOf
				if systemSignal:peek() ~= actionSystem then
					systemSignal:set(actionSystem)
				end
			end,
		}
		liveGlyph = Compose.formula(function(use)
			return (use(liveKey) :: any).glyph
		end)

		local showsLetter = Compose.formula(function(use)
			local key = use(liveKey) :: any
			return key.text ~= "" and key.glyph == nil
		end)
		local showsGlyph = Compose.formula(function(use)
			return (use(liveKey) :: any).glyph ~= nil
		end)
		table.insert(
			children,

			UI.When({
				id = "Live",
				condition = showsLetter,
				thenView = function()
					return UI.HStack({
						id = "Chord1",
						gap = "xs",
						align = "center",
						children = { cap("Key1", liveLabel, nil) },
					})
				end,
			})
		)
		table.insert(
			children,
			UI.When({
				id = "LiveGlyph",
				condition = showsGlyph,
				thenView = function()
					return UI.HStack({
						id = "Chord1",
						gap = "xs",
						align = "center",
						children = { cap("Key1", liveLabel, liveGlyph) },
					})
				end,
			})
		)
	else
		for index, chord in spec.keys :: { { string } } do
			if index > 1 then
				table.insert(
					children,

					UI.Text({
						id = `Or{index}`,
						text = separator,
						textSize = "label",
						role = "secondary",
						over = spec.over,
					})
				)
			end
			local capsInChord: { any } = {}
			for position, key in chord do
				table.insert(capsInChord, cap(`Key{position}`, key, nil))
			end
			table.insert(
				children,
				UI.HStack({
					id = `Chord{index}`,
					gap = CAP_GAP,
					align = "center",
					wrap = true,
					children = capsInChord,
				})
			)
		end
	end

	local blueprint = UI.HStack({
		id = id,
		gap = "xs",
		align = "center",
		wrap = true,
		children = children,
	})
	if bundle ~= nil then
		blueprint = contribution.attach(blueprint, bundle)
	end

	local function dump()
		local alternatives: { { string } } = {}
		if spec.keys ~= nil then
			for _, chord in spec.keys do
				table.insert(alternatives, table.clone(chord))
			end
		elseif liveLabel ~= nil and liveLabel:peek() ~= "" then
			alternatives = { { liveLabel:peek() } }
		end
		local glyph = if liveGlyph ~= nil then liveGlyph:peek() else nil
		return {
			schema = "facet-shortcut-hint-dump/1",
			id = id,
			form = if spec.action ~= nil then "action" else "keys",
			action = spec.action,
			alternatives = alternatives,
			separator = if spec.keys ~= nil then selection.read(separator) else nil,
			visible = #alternatives > 0,
			glyph = glyph,
			controlSize = selection.read(spec.controlSize),
			over = spec.over,
		}
	end

	return {
		blueprint = blueprint,
		dump = dump,
	}
end

return shortcut_hint
