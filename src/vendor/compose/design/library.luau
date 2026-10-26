--!strict

local Types = require "./types"

export type Extension = {
	kinds: { [string]: Types.Kind },
	prelude: { string }?,
}

local function extend(base: Types.Library, extension: Extension): Types.Library
	local kinds: { [string]: Types.Kind } = table.clone(base.kinds)
	for name, kind in extension.kinds do
		assert(kinds[name] == nil, `{base.name} already has a kind named {name}`)
		kinds[name] = kind
	end
	local prelude = table.clone(base.prelude)
	local added: { string } = extension.prelude or {}
	for _, line in added do
		if table.find(prelude, line) == nil then
			table.insert(prelude, line)
		end
	end
	local extended = table.clone(base)
	extended.kinds = kinds
	extended.prelude = prelude
	return extended
end

return {
	extend = extend,
}
