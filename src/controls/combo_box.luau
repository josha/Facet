--!strict
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
function combo.build(Facet, core, spec)
	guard.assertKnownKeys("Controls.ComboBox", spec, KEYS, "spec")
	for _, name in { "value", "text" } do
		assert(
			type(spec[name]) == "table" and spec[name].kind == "signal" and type(spec[name]:get()) == "string",
			`ComboBox: {name} must be a caller-owned Signal<string>`
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
	local scope = core:scope("combo-box")
	local disposed = false
	local node
	scope:own(function()
		disposed = true
	end)
	local validationError = scope:own(core:signal(""))
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
		spec.text:set(label(spec.value:get()))
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
		if proposed ~= spec.value:get() then
			spec.value:set(proposed)
			changed(proposed)
		else
			validationError:set("")
		end
	end
	local editor = Facet.Controls.TextInput(core, {
		id = "Editor",
		value = spec.text,
		enabled = spec.enabled,
		placeholder = spec.placeholder,
		env = spec.env,
		onCommit = commit,
		onCancel = cancel,
	})
	scope:own(editor)
	local suggestions = Facet.Controls.PopupButton(core, {
		id = "Suggestions",
		options = spec.options,
		value = spec.value,
		query = spec.text,
		enabled = spec.enabled,
		onChange = changed,
		env = spec.env,
		placeholder = "Suggestions",
	})
	scope:own(suggestions)
	local hidden = scope:own(core:memo(function(use)
		return use(validationError) == ""
	end))
	local blueprint = contribution.attach(
		UI.VStack({
			id = spec.id or "ComboBox",
			width = { type = "fill", weight = 1 },
			gap = "xs",
			children = {
				editor.blueprint,
				suggestions.blueprint,
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
			value = spec.value:get(),
			text = spec.text:get(),
			validationError = validationError:get(),
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
				scope:dispose()
			end
		end,
	}
end
return combo
