--!strict
local Types = require("./catalog_types")
type Row = { id: string, name: string, laps: number }

return function(c: Types.Context, initial: { Row }): Types.Properties
	local rows = c.cell("transferRows", initial)
	local serial = 0
	return {
		from = rows,
		collectionId = rows,
		drag = function(items, keys)
			return { payload = { items = items, keys = keys, collection = rows }, operations = { "copy" } }
		end,
		drop = {
			operation = "copy",
			accepts = function(payload)
				return type(payload) == "table" and payload.items ~= nil
			end,
			onDrop = function(payload: any, info: any)
				local next = table.clone(rows:peek())
				for index, item in payload.items do
					serial += 1
					local copy = table.clone(item)
					copy.id, copy.name = "copy-" .. serial, item.name .. " copy"
					table.insert(next, info.insertion.slot + index, copy)
				end
				rows:set(next)
				c.log("onDrop")(info.operation, info.insertion.slot)
				return true
			end,
		},
	}
end
