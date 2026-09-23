--!strict
--[[ Vote — up, down or none, over the caller's value (phase6 P6b, D7; owner
	ruling 2026-09-18: a thin wrapper over Picker).

	CONTROLLED. `value` is the caller's; a press proposes `onChange(next)` and only
	the caller's next value repaints. Pressing the chosen side proposes "none".
	The strip is Picker's own segmented, icon-only strip, reached through its
	PRIVATE submission seam: it borrows the derived selection (none -> nil) and
	hands an accepted choice to `onChange` at its one write/notify boundary, so a
	refused proposal never paints and a swap is one transition. Picker's
	`selection_model.choose` stays the one policy (enabled, equality, clearing).

	READ-ONLY is informational, not disabled: the same icons with the caller's
	choice plated by the shared selection indicator, and no Buttons at all, so
	there is no focus stop and no press affordance. `enabled = false` is ordinary
	inherited disabled paint on the interactive strip.

	`summary` is the caller's aggregate ("99% liked"), one line with the full
	value disclosed; nothing here counts votes. ]]
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local ownedFormula = require("../core/owned_formula")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local vocabulary = require("./control_vocabulary")
local selectionIndicator = require("./selection_indicator")

local vote = {}

local specTypes = require("../spec_types/vote")
export type Spec = specTypes.Spec

local KEYS = guard.keySet({ "controlSize", "enabled", "env", "id", "onChange", "readOnly", "summary", "value" })
local VALUES = { up = true, down = true, none = true }
local DUMP_SCHEMA = "facet-vote-dump/1"
local OPTIONS = {
	{ value = "up", label = "Upvote", icon = "vote.up" },
	{ value = "down", label = "Downvote", icon = "vote.down" },
}

local function build(Facet: any, core: any, spec: Spec, owner: any)
	guard.assertKnownKeys("UI.Vote", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Vote"
	local where = `UI.Vote('{id}')`
	if VALUES[selection.read(spec.value)] ~= true then
		error(`Facet {where}: \`value\` is required — "up" | "down" | "none", or a bound one.`, 0)
	end
	local readOnlyNow = selection.read(spec.readOnly)
	if readOnlyNow ~= nil and type(readOnlyNow) ~= "boolean" then
		error(`Facet {where}: \`readOnly\` is a boolean or a bound boolean.`, 0)
	end
	if spec.onChange ~= nil and type(spec.onChange) ~= "function" then
		error(`Facet {where}: \`onChange(next)\` is a function.`, 0)
	end
	if spec.onChange == nil and readOnlyNow ~= true then
		error(`Facet {where}: an interactive Vote needs \`onChange(next)\`; only a readOnly one may omit it.`, 0)
	end
	local summaryNow = selection.read(spec.summary)
	if summaryNow ~= nil and type(summaryNow) ~= "string" then
		error(`Facet {where}: \`summary\` is a string or a bound string.`, 0)
	end
	local enabledNow = selection.read(spec.enabled)
	if enabledNow ~= nil and type(enabledNow) ~= "boolean" then
		error(`Facet {where}: \`enabled\` is a boolean or a bound boolean.`, 0)
	end
	vocabulary.assertSize("UI.Vote", spec.controlSize)
	local onChange: any = spec.onChange

	-- ===== legal values only ==================================================
	local diagnostics: { string } = {}
	local function legal(key: string, source: any, ok: (any) -> boolean, what: string): any
		local last = selection.read(source)
		local refused = false
		return ownedFormula(owner, function(use)
			local v = selection.read(source, use)
			if ok(v) then
				last, refused = v, false
			elseif not refused then
				refused = true
				local line = `Facet {where}: \`{key}\` {what} — keeping the last legal value`
				selection.note(diagnostics, line)
			end
			return last
		end)
	end
	local value = legal("value", spec.value, function(v)
		return VALUES[v] == true
	end, 'is "up" | "down" | "none"')
	-- an interactive Vote without onChange is refused; it stays read-only
	local readOnly = legal("readOnly", spec.readOnly, function(v)
		return (v == nil or type(v) == "boolean") and (v == true or onChange ~= nil)
	end, "cannot turn off without onChange")
	local summary = legal("summary", spec.summary, function(v)
		return v == nil or type(v) == "string"
	end, "is a string")
	local enabled = ownedFormula(owner, function(use)
		return selection.read(spec.enabled, use) ~= false
	end)
	-- the borrowed selection: none reads as no selected option
	local selected = ownedFormula(owner, function(use)
		local v = use(value)
		return if v == "none" then nil else v
	end)

	local disposed = false
	local function submit(next: any)
		if disposed or not enabled:peek() or readOnly:peek() == true then
			return
		end
		onChange(if next == nil then "none" else next)
	end

	local function interactive(): any
		local strip = require("./picker").build(Facet, core, {
			id = "Choice",
			options = OPTIONS,
			selected = selected,
			required = false,
			style = "segmented",
			iconOnly = true,
			sizing = "hug",
			controlSize = spec.controlSize,
			enabled = enabled,
			env = spec.env,
		}, nil, submit)
		Compose.cleanup(function()
			strip.dispose()
		end)
		return strip.blueprint
	end

	-- the same icons, the caller's choice plated, and nothing to press
	local function informational(): any
		local marks: { any } = {}
		for i, option in OPTIONS do
			table.insert(
				marks,
				-- the strip's own segment ids, so both forms read alike
				UI.ZStack({
					id = `Opt{i}`,
					width = { type = "minMax", min = "targetSizes.minimum" },
					height = { type = "minMax", min = "targetSizes.minimum" },
					alignH = "center",
					alignV = "center",
					children = {
						UI.Image({
							id = "Icon",
							image = option.icon,
							width = { type = "fixed", px = "iconSizes.medium" },
							height = { type = "fixed", px = "iconSizes.medium" },
						}),
					},
				})
			)
		end
		local indicator = selectionIndicator.build(Facet, core, {
			id = "Plate",
			content = UI.HStack({ id = "Marks", gap = 0, children = marks }),
			segments = {
				{ id = "Opt1", value = "up" },
				{ id = "Opt2", value = "down" },
			},
			selected = selected,
			skin = "pill",
			env = spec.env,
		})
		Compose.cleanup(function()
			indicator.dispose()
		end)
		return indicator.blueprint
	end

	-- the summary gives up width first (truncating, disclosed); the strip never does
	local root = UI.HStack({
		id = id,
		gap = "s",
		align = "center",
		children = {
			UI.When({
				id = "Mode",
				condition = ownedFormula(owner, function(use)
					return use(readOnly) ~= true
				end),
				thenView = interactive,
				elseView = informational,
			}),
			UI.Text({
				id = "Summary",
				text = function(use)
					return use(summary) or ""
				end,
				hidden = function(use)
					return (use(summary) or "") == ""
				end,
				lineLimit = 1,
				disclose = true,
				shrinkWeight = 1,
			}),
		},
	})
	owner.own(function()
		disposed = true
	end)

	local function dump()
		return {
			schema = DUMP_SCHEMA,
			id = id,
			value = value:peek(),
			readOnly = readOnly:peek() == true,
			summary = summary:peek(),
			diagnostics = table.clone(diagnostics),
		}
	end

	return {
		blueprint = root,
		api = {
			diagnostics = function(): { string }
				return table.clone(diagnostics)
			end,
		},
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	}
end

function vote.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end

return vote
