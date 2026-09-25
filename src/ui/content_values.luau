--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")

return function(ctx: Types.Context, control: string)
	local Compose, read = ctx.Compose, ctx.read
	local diagnostics: { string } = {}
	local function note(message: string)
		warn(message)
		table.insert(diagnostics, message)
		if #diagnostics > 16 then
			table.remove(diagnostics, 1)
		end
	end
	local function legal<T>(
		key: string,
		source: Types.Value<T>,
		ok: (unknown) -> boolean,
		what: string
	): ComposeTypes.Formula<T>
		local last: T = read(source)
		local refused = false
		return Compose.formula(function(use: ComposeTypes.Use): T
			local value: T = read(source, use)
			if ok(value) then
				last, refused = value, false
			elseif not refused then
				refused = true
				note(`Facet UI.{control}: {key} {what}; the last legal value stays`)
			end
			return last
		end)
	end
	return {
		attribute = function(value: unknown): Types.Value<Types.AttributeValue?>
			return value :: Types.Value<Types.AttributeValue?>
		end,
		note = note,
		list = function(): { string }
			return table.clone(diagnostics)
		end,
		legal = legal,
	}
end
