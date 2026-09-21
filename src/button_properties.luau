--!strict
-- Button content rules shared by immutable descriptions and the Compose host.
local primitiveProperties = require("./primitive_properties")
local themePackage = require("./themes/package")
local Compose = require("./vendor/compose/core")
type Blueprint = any
local isReadable = Compose.isReadable
local isWritable = require("./selection_model").isWritable
local CONTENT_FOCUSABLE = { Button = true, Toggle = true, TextField = true }
local function assertNoFocusableContent(children: { Blueprint }?)
	if children == nil then
		return
	end
	local function walk(node: Blueprint)
		local source = if node.dynamicProps then node.dynamicProps.value else node.props.value
		local inertToggle = node.class == "Toggle"
			and node.meta
			and node.meta.displayOnly == true
			and node.props.focusable == false
			and Compose.isReadable(source)
			and not isWritable(source)
		if
			(CONTENT_FOCUSABLE[node.class] and not inertToggle)
			or (node.class == "Grip" and node.props.focusable == true)
		then
			error(
				`Facet UI.Button: custom content must stay inside one activation surface, but it `
					.. `contains a focusable UI.{node.class} ('{node.id or "unnamed"}'). Put the control `
					.. `beside the Button, not inside it.`,
				0
			)
		end
		for _, child in node.children or {} do
			walk(child)
		end
	end
	for _, child in children do
		walk(child)
	end
end

-- A circular button shows one icon or a short label.
local CIRCLE_MAX_CHARS = 3

local function circleDrawnLabel(props: { [string]: any }, children: { Blueprint }?): (string | number)?
	-- With custom content or an icon, the label is only an accessible name.
	if props.icon ~= nil or (children ~= nil and #children > 0) then
		return nil
	end
	local label = props.label
	if isReadable(label) then
		return nil -- a bound label is checked when it is read, like every reactive prop
	end
	return label
end

local function assertShape(props: { [string]: any }, children: { Blueprint }?)
	local shape = props.shape
	if props.icon ~= nil and shape ~= "circle" then
		error(
			`Facet UI.Button.icon is only supported with shape = "circle" (got shape = `
				.. `{if shape == nil then "nil" else `'{tostring(shape)}'`}). A circle's content is ONE mark, `
				.. `which is what a semantic icon name describes. Fix: add shape = "circle", or put an icon `
				.. `BESIDE a title with UI.Label inside the button's children.`,
			0
		)
	end
	if props.icon ~= nil and not themePackage.isIconName(props.icon) then
		local known: { string } = {}
		for name in themePackage.ICON_FALLBACK_GLYPHS :: any do
			table.insert(known, name)
		end
		table.sort(known)
		error(
			`Facet UI.Button.icon: '{tostring(props.icon)}' names no semantic icon. It must be a framework `
				.. `name ({table.concat(known, ", ")}) or a namespaced one a package contributes ("ns:name"). `
				.. `Fix: use a framework name, or namespace your own and declare it in the package's `
				.. `\`icons\` map.`,
			0
		)
	end
	if shape ~= "circle" then
		return
	end
	primitiveProperties.assertCircleSquare("Button", props)
	local drawn = circleDrawnLabel(props, children)
	if drawn == nil then
		return
	end
	local text = tostring(drawn)
	if string.find(text, "%s") ~= nil or utf8.len(text) == nil or (utf8.len(text) :: number) > CIRCLE_MAX_CHARS then
		error(
			`Facet UI.Button.label: '{text}' cannot be the drawn content of shape = "circle" — a disc holds `
				.. `ONE icon or up to {CIRCLE_MAX_CHARS} characters with no spaces, and a longer label has `
				.. `nowhere to go inside a 1:1 target. Fix: pass icon = "<semantic name>" (e.g. "more", `
				.. `"close", "menu") and keep this label as the semantic name, shorten the label, or drop `
				.. `shape = "circle" for the default rectangular Button.`,
			0
		)
	end
end

-- The schema checks shape; these rules check icon names and text meaning.
local function assertCompactLabel(props: { [string]: any }, children: { Blueprint }?)
	local compact = props.compactLabel
	if compact == nil then
		return
	end
	-- Custom content replaces drawn text, so a compact label would have no effect.
	if children ~= nil and #children > 0 then
		error(
			`Facet UI.Button.compactLabel is not supported on a CONTENT button — a button with children `
				.. `draws no text of its own (its label is semantics only), so there is nothing to shorten. `
				.. `Fix: drop compactLabel, or make the content itself adapt with UI.ViewThatFits.`,
			0
		)
	end
	local text = if type(compact) == "string"
		then compact
		else (if type(compact) == "table" then (compact :: any).text else nil)
	-- Compact labels must not introduce a word-wrap opportunity.
	if type(text) == "string" and string.find(text, "%s") ~= nil then
		error(
			`Facet UI.Button.compactLabel: '{text}' contains whitespace, and a compact label must be ONE `
				.. `word. It is drawn only when the full label did not fit, and a phrase has a legal break `
				.. `point — so the engine would wrap it and the button would be as tall as the case the `
				.. `compact form exists to avoid. Fix: use a single word, or icon = "<semantic name>".`,
			0
		)
	end
	local icon = if type(compact) == "table" then (compact :: any).icon else nil
	if icon ~= nil and not themePackage.isIconName(icon) then
		local known: { string } = {}
		for name in themePackage.ICON_FALLBACK_GLYPHS :: any do
			table.insert(known, name)
		end
		table.sort(known)
		error(
			`Facet UI.Button.compactLabel.icon: '{tostring(icon)}' names no semantic icon. It must be a `
				.. `framework name ({table.concat(known, ", ")}) or a namespaced one a package contributes `
				.. `("ns:name"). Fix: use a framework name, or namespace your own and declare it in the `
				.. `package's \`icons\` map.`,
			0
		)
	end
end

return function(props: any, children: any)
	assertNoFocusableContent(children)
	assertShape(props, children)
	assertCompactLabel(props, children)
end
