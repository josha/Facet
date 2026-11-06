--!strict
local Types = require("./types")

type Generation = { [string]: true }
type Memo = { current: Generation, previous: Generation, count: number }

local LIMIT = 256
local memos: { [unknown]: Memo } = setmetatable({}, { __mode = "k" })

local function keyOf(ctx: Types.Context): unknown
	local services = ctx.config.services
	local provider = if services then services.ContentProvider else nil
	return if provider then provider else ctx.runtime
end

local function remember(ctx: Types.Context, id: string)
	if id == "" then
		return
	end
	local key = keyOf(ctx)
	local found = memos[key]
	if found == nil then
		local created: Memo = { current = {}, previous = {}, count = 0 }
		found = created
		memos[key] = created
	end
	local memo = found
	if memo.current[id] then
		return
	end
	if memo.count >= LIMIT then
		memo.previous = memo.current
		memo.current = {}
		memo.count = 0
	end
	memo.current[id] = true
	memo.count += 1
end

local function forget(ctx: Types.Context, id: string)
	local memo = memos[keyOf(ctx)]
	if memo == nil then
		return
	end
	if memo.current[id] then
		memo.current[id] = nil
		memo.count -= 1
	end
	memo.previous[id] = nil
end

local function knows(ctx: Types.Context, id: string): boolean
	local memo = memos[keyOf(ctx)]
	if memo == nil or id == "" then
		return false
	end
	if memo.current[id] then
		return true
	end
	if memo.previous[id] then
		remember(ctx, id)
		return true
	end
	return false
end

local function settle(ctx: Types.Context, id: string, status: Enum.AssetFetchStatus)
	if status == ctx.types.Enum.AssetFetchStatus.Success then
		remember(ctx, id)
	else
		forget(ctx, id)
	end
end

local function probe(ctx: Types.Context, id: string): boolean
	local services = ctx.config.services
	local provider = if services then services.ContentProvider else nil
	if provider == nil or id == "" then
		return false
	end
	local ok, status = pcall(provider.GetAssetFetchStatus, provider, id)
	if not ok then
		return false
	end
	local statuses = ctx.types.Enum.AssetFetchStatus
	if status == statuses.Success then
		remember(ctx, id)
		return true
	end
	if status == statuses.Failure or status == statuses.TimedOut then
		forget(ctx, id)
	end
	return false
end

return table.freeze {
	knows = knows,
	remember = remember,
	forget = forget,
	settle = settle,
	probe = probe,
}
