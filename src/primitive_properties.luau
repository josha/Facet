--!strict
-- Property rules shared by immutable descriptions and the native Compose host.
local policy = require("./motion/policy")
local properties = {}
local requiredBySchema = {}
properties.direct = table.freeze({
	Screen = true,
	Button = true,
	VStack = true,
	ZStack = true,
	HStack = true,
	Spacer = true,
	Box = true,
	Anchor = true,
	Grid = true,
	GridRow = true,
	Text = true,
	Image = true,
	Path = true,
	Foreign = true,
	Stage = true,
})
function properties.assertCircleSquare(className: string, props: { [string]: any })
	if props.shape ~= "circle" then
		return
	end
	if props.width ~= nil and props.height ~= nil then
		error(
			`Facet UI.{className}: shape = "circle" takes at most ONE of \`width\` / \`height\` — the solver `
				.. `enforces the 1:1 square, so the other axis follows and the author never does the math. `
				.. `Fix: drop one of them (or drop both to size the disc from the control metric).`,
			0
		)
	end
end

-- `bound` names the properties a readable drives: what a bound value holds at
-- mount implies nothing about a construction-only property.
function properties.normalize(class: string, props: any, known: any, bound: { [string]: any }?)
	if props.animation ~= nil then
		local ok, why = policy.check(props.animation)
		assert(ok, `Facet UI.{class}.animation: {why or "invalid policy"}`)
		for key in props.animation do
			assert(key == "layout" or known[key], `Facet UI.{class}: cannot animate unsupported property '{key}'`)
		end
		props.animation = table.freeze(table.clone(props.animation))
	end
	local required = requiredBySchema[known]
	if not required then
		required = {}
		for name, definition in known do
			if definition.required then
				table.insert(required, name)
			end
		end
		requiredBySchema[known] = required
	end
	for _, name in required do
		if props[name] == nil then
			error(`Facet UI.{class}.{name} is required ({known[name].doc})`, 0)
		end
	end
	properties.assertCombinations(class, props)
	if
		props.overflow == "clip"
		and props.clipChildren == nil
		and known.clipChildren ~= nil
		and not (bound and bound.overflow ~= nil)
	then
		props.clipChildren = true
	end
end

--[[ THE CROSS-PROPERTY REFUSALS, WHICH ARE CONSTRUCTION ERRORS.

	Each one reads TWO properties, so no per-property schema check can see it, and
	each one is a refusal rather than a normalization — nothing is written, so it
	is idempotent and safe to ask twice.

	IT IS ASKED AT CONSTRUCTION, NOT ONLY AT MOUNT. A Compose host assigns
	properties one at a time, so the pair only exists once the node is built —
	which is `render/compose_scene`'s own constructor wrapper, the first moment
	both values are on the node. Asking only at `insertChild` meant a stack
	authored wrong and never parented (a fixture, a detached recipe, an authoring
	mistake caught before the node reaches a tree) was accepted in silence; asking the whole of `normalize` there instead
	would have run the WRITING half — the clip default, the required-prop sweep,
	Button's content rule — before a binding had delivered anything. ]]
function properties.assertCombinations(class: string, props: any)
	if class == "ZStack" then
		properties.assertCircleSquare(class, props)
	end
	if props.wrap == true and props.align == "stretch" then
		error(
			`Facet UI.{class}: \`align = "stretch"\` has two readings on a wrapping stack — "each child `
				.. `fills its line" and "the lines fill the container" — so it is refused. Put `
				.. '`lineAlign = "stretch"` on the children that should fill their line, and use `align` '
				.. "(start|center|end) for where the block of lines sits.",
			0
		)
	end
end
return properties
