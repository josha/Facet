--!strict

local Compose = require "../core"
local Design = require "../design"

export type RenderPreview = (
	document: Design.Document,
	library: Design.Library,
	use: Compose.Use
) -> (Design.Document, { [string]: Design.Resolved })

local function bindings(
	document: Design.Document,
	supplied: { [string]: Design.Resolved }?,
	use: Compose.Use
): { [string]: Design.Resolved }?
	if supplied == nil then
		return nil
	end
	local resolved = table.clone(supplied)
	for _, input in document.contract.inputs do
		local binding = supplied[input.id]
		if input.kind == "value" and binding then
			if binding.readable then
				resolved[input.id] = { literal = use(binding.readable) }
			elseif binding.rows then
				local rows: Design.Row = {}
				for index, row in use(binding.rows) do
					rows[index] = row
				end
				resolved[input.id] = { literal = rows }
			end
		end
	end
	return resolved
end

return { bindings = bindings }
