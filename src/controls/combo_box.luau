--!strict
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
-- Editable selection: durable committed value and editable text are distinct.
local guard = require("../spec_guard")
local selection = require("../selection_model")
local contract = require("../class_contract")
local contribution = require("../input/contribution")
local combo = {}
local KEYS = guard.keySet({
	"id",
	"value",
	"text",
	"options",
	"enabled",
	"acceptCustom",
	"onChange",
	"commitOnFocusLost",
	"placeholder",
	"env",
})
local function build(Facet, core, spec, owner)
	guard.assertKnownKeys("UI.ComboBox", spec, KEYS, "spec")
	for _, name in { "value", "text" } do
		assert(
			selection.isWritable(spec[name]) and type(selection.read(spec[name])) == "string",
			`ComboBox: {name} must be a writable Compose string cell`
		)
	end
	assert(type(spec.acceptCustom) == "function", "ComboBox: acceptCustom must explicitly validate custom text")
	local enabled = selection.read(spec.enabled)
	assert(enabled == nil or type(enabled) == "boolean", "ComboBox: enabled must be boolean or readable boolean")
	assert(spec.placeholder == nil or type(spec.placeholder) == "string", "ComboBox: placeholder must be a string")
	assert(spec.onChange == nil or type(spec.onChange) == "function", "ComboBox: onChange must be a function")
	assert(
		spec.commitOnFocusLost == nil or type(spec.commitOnFocusLost) == "boolean",
		"ComboBox: commitOnFocusLost must be boolean"
	)
	local UI = Facet.UI
	local disposed = false
	local node
	owner.own(function()
		disposed = true
	end)
	local validationError = Compose.cell("")
	local function available()
		return not disposed and contract.enabledNow(spec.enabled) and not contract.isDisabled(node)
	end
	local function label(value)
		local option = selection.find(selection.read(spec.options), value)
		return if option then selection.read(option.label) else value
	end
	local function cancel()
		if disposed then
			return
		end
		spec.text:set(label(spec.value:peek()))
		validationError:set("")
	end
	local function changed(value)
		if not available() then
			return
		end
		validationError:set("")
		spec.text:set(label(value))
		if spec.onChange then
			spec.onChange(value)
		end
	end
	local function commit(text, reason)
		if not available() or (reason == "focusLost" and spec.commitOnFocusLost ~= true) then
			return
		end
		local supplied
		for _, option in selection.read(spec.options) do
			if not option.divider and selection.read(option.label) == text then
				supplied = option
				break
			end
		end
		local proposed = text
		if supplied then
			if not selection.enabled(supplied) then
				validationError:set("This option is unavailable.")
				return
			end
			proposed = supplied.id
		else
			local ok, accepted, message = pcall(spec.acceptCustom, text)
			if not available() then
				return
			end
			if not ok or accepted ~= true then
				validationError:set(if type(message) == "string" then message else "This value is not accepted.")
				return
			end
		end
		if proposed ~= spec.value:peek() then
			spec.value:set(proposed)
			changed(proposed)
		else
			validationError:set("")
		end
	end
	local editor = require("./text_input").build(Facet, core, {
		id = "Editor",
		value = spec.text,
		enabled = spec.enabled,
		placeholder = spec.placeholder,
		env = spec.env,
		onCommit = commit,
		onCancel = cancel,
	})
	owner.own(editor.dispose)
	local suggestions = require("./picker_menu").build(Facet, core, {
		id = "Suggestions",
		options = spec.options,
		value = spec.value,
		query = spec.text,
		enabled = spec.enabled,
		onChange = changed,
		env = spec.env,
		placeholder = "Suggestions",
	}, true)
	owner.own(suggestions.dispose)
	local hidden = Compose.formula(function(use)
		return use(validationError) == ""
	end)
	local blueprint = contribution.attach(
		UI.VStack({
			id = spec.id or "ComboBox",
			width = { type = "fill", weight = 1 },
			gap = "xs",
			children = {
				-- The field and its suggestions opener share one row.
				UI.HStack({
					id = "Row",
					width = { type = "fill", weight = 1 },
					gap = "xs",
					children = {
						editor.blueprint,
						-- A FLOOR, NOT A CAP. 56px was a constant, and a constant cannot
						-- hold a themed trigger's own padding plus a chevron drawn at the
						-- player's text preference: at +14 the chevron was clipped with no
						-- full-value path, and under a roomy package the trigger painted
						-- 20px outside its row. The opener keeps its comfortable minimum
						-- and takes the width its content actually needs.
						UI.frame(suggestions.blueprint, { minWidth = 56 }),
					},
				}),
				UI.Text({
					id = "Validation",
					text = validationError,
					hidden = hidden,
					textSize = "caption",
					tint = { role = "danger", blend = 1 },
					width = { type = "fill", weight = 1 },
				}),
			},
		}),
		{
			syncGeometry = function(_, root)
				node = root
			end,
		}
	)
	local function dump()
		return {
			schema = "facet-combo_box-dump/1",
			editing = editor.dump().editing,
			value = spec.value:peek(),
			text = spec.text:peek(),
			validationError = validationError:peek(),
			open = suggestions.dump().open,
		}
	end
	return {
		blueprint = blueprint,
		api = {
			submit = editor.api.submit,
			cancel = function()
				editor.api.cancel()
				cancel()
				suggestions.api.close()
			end,
		},
		dump = dump,
		dispose = function()
			if not disposed then
				owner.dispose()
			end
		end,
	}
end
function combo.build(Facet, core, spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end
return combo
