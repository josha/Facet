--!strict

local seedData = require("../content/seed")

local supply = {}

export type Opts = {
	Compose: any,
	rooted: (() -> any) -> any,
	now: any,
}

local KINDS = { "nectar", "dew" }
supply.KINDS = KINDS

function supply.new(opts: Opts): any
	local Compose = opts.Compose

	local rooted = opts.rooted
	local now = opts.now

	local stamps: { [string]: any } = {}
	local assigned: { [string]: any } = {}
	for _, glade in seedData.GLADES do
		stamps[glade.id] = {
			nectar = Compose.cell(-glade.nectarAge),
			dew = Compose.cell(-glade.dewAge),
		}
		assigned[glade.id] = Compose.cell(glade.nectar)
	end

	local service = {}

	local levels: { [string]: any } = {}
	local remainings: { [string]: any } = {}
	local states: { [string]: any } = {}

	local function elapsedOf(gladeId: string, kind: string, at: number): number
		local stamp = stamps[gladeId][kind]
		return at - stamp:peek()
	end

	function service.remaining(gladeId: string, kind: string): any
		local key = gladeId .. "/" .. kind
		local memo = remainings[key]
		if memo == nil then
			memo = rooted(function()
				return Compose.formula(function(use)
					local at = use(now)
					local stamp = use(stamps[gladeId][kind])
					local left = seedData.DRAIN[kind].empty - (at - stamp)
					return if left < 0 then 0 else left
				end)
			end)
			remainings[key] = memo
		end
		return memo
	end

	function service.level(gladeId: string, kind: string): any
		local key = gladeId .. "/" .. kind
		local memo = levels[key]
		if memo == nil then
			memo = rooted(function()
				return Compose.formula(function(use)
					local left = use(service.remaining(gladeId, kind))
					return left / seedData.DRAIN[kind].empty
				end)
			end)
			levels[key] = memo
		end
		return memo
	end

	function service.state(gladeId: string, kind: string): any
		local key = gladeId .. "/" .. kind
		local memo = states[key]
		if memo == nil then
			memo = rooted(function()
				return Compose.formula(function(use)
					local at = use(now)
					local stamp = use(stamps[gladeId][kind])
					local elapsed = at - stamp
					local drain = seedData.DRAIN[kind]
					if elapsed >= drain.empty then
						return "empty"
					elseif elapsed >= drain.low then
						return "low"
					end
					return "full"
				end)
			end)
			states[key] = memo
		end
		return memo
	end

	function service.nectarOf(gladeId: string): any
		return assigned[gladeId]
	end

	function service.refill(gladeId: string, kind: string)
		stamps[gladeId][kind]:set(now:peek())
	end

	function service.assign(gladeId: string, nectarId: string)
		assigned[gladeId]:set(nectarId)
		service.refill(gladeId, "nectar")
	end

	function service.reset()
		for _, glade in seedData.GLADES do
			stamps[glade.id].nectar:set(-glade.nectarAge)
			stamps[glade.id].dew:set(-glade.dewAge)
			assigned[glade.id]:set(glade.nectar)
		end
	end

	function service.dump(): any
		local out: { any } = {}
		for _, glade in seedData.GLADES do
			local at = now:peek()
			table.insert(out, {
				glade = glade.id,
				nectar = assigned[glade.id]:peek(),
				nectarElapsed = elapsedOf(glade.id, "nectar", at),
				dewElapsed = elapsedOf(glade.id, "dew", at),
				nectarState = service.state(glade.id, "nectar"):peek(),
				dewState = service.state(glade.id, "dew"):peek(),
			})
		end
		return out
	end

	return service
end

return supply
