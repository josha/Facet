--!strict

export type Row = { checkpoint: string, viewport: string, kind: string? }
export type Ordered<R = Row> = { driven: { R }, undriven: { R } }

local function order<R>(
	checkpoints: { string },
	viewports: { string },
	rows: { R },
	collectAll: boolean?
): (Ordered<R>?, string?)
	if type(checkpoints) ~= "table" or type(viewports) ~= "table" or type(rows) ~= "table" then
		return nil, "checkpoint_plan_invalid"
	end
	local names: { [string]: boolean } = {}
	local views: { [string]: boolean } = {}
	for _, name in checkpoints do
		if type(name) ~= "string" or name == "" or names[name] then
			return nil, "checkpoint_plan_invalid"
		end
		names[name] = true
	end
	for _, view in viewports do
		if type(view) ~= "string" or view == "" or views[view] then
			return nil, "checkpoint_plan_invalid"
		end
		views[view] = true
	end
	local selected: { [string]: R } = {}
	local undriven = {}
	for _, original in rows do
		local row = original :: unknown
		local fields = row :: { [string]: unknown }
		if type(row) ~= "table" or type(fields.checkpoint) ~= "string" or type(fields.viewport) ~= "string" then
			return nil, "checkpoint_row_invalid"
		end
		if fields.kind == "checkpoint" then
			local key = fields.viewport .. "\0" .. fields.checkpoint
			if selected[key] ~= nil then
				return nil, "checkpoint_row_duplicate: " .. fields.checkpoint .. " on " .. fields.viewport
			end
			selected[key] = original
		else
			table.insert(undriven, original)
		end
	end
	if collectAll == true then
		return { driven = {}, undriven = {} }, nil
	end
	local driven = {}
	for _, checkpoint in checkpoints do
		for _, viewport in viewports do
			local row = selected[viewport .. "\0" .. checkpoint]
			if row == nil then
				return nil, "checkpoint_row_missing: " .. checkpoint .. " on " .. viewport
			end
			table.insert(driven, row)
		end
	end
	return { driven = driven, undriven = undriven }, nil
end

return { order = order }
