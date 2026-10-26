--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
type Value<T> =
	ReadOnlyValue<T>
	& { set: (Value<T>, T) -> (), update: (Value<T>, (T) -> T) -> (), dispose: (Value<T>) -> () }
type Use = <T>(ReadOnlyValue<T>) -> T

local seedData = require("../content/seed")

local supply = {}

export type Opts = {
	Compose: ComposeModule,
	rooted: <T>(() -> T) -> T,
	now: ReadOnlyValue<number>,
}
export type Stamps = { nectar: Value<number>, dew: Value<number> }
export type GladeSupply = {
	glade: string,
	nectar: string,
	nectarElapsed: number,
	dewElapsed: number,
	nectarState: string,
	dewState: string,
}

local KINDS = { "nectar", "dew" }
supply.KINDS = KINDS

function supply.new(opts: Opts)
	local Compose: ComposeModule = opts.Compose

	local rooted = opts.rooted
	local now = opts.now

	local stamps: { [string]: Stamps } = {}
	local assigned: { [string]: Value<string> } = {}
	for _, glade in seedData.GLADES do
		stamps[glade.id] = {
			nectar = Compose.cell(-glade.nectarAge),
			dew = Compose.cell(-glade.dewAge),
		}
		assigned[glade.id] = Compose.cell(glade.nectar)
	end

	local service = {}

	local levels: { [string]: ReadOnlyValue<number> } = {}
	local remainings: { [string]: ReadOnlyValue<number> } = {}
	local states: { [string]: ReadOnlyValue<string> } = {}

	local function stampOf(gladeId: string, kind: string): Value<number>
		local stamp = stamps[gladeId]
		return if kind == "dew" then stamp.dew else stamp.nectar
	end

	local function elapsedOf(gladeId: string, kind: string, at: number): number
		return at - stampOf(gladeId, kind):peek()
	end

	function service.remaining(gladeId: string, kind: string): ReadOnlyValue<number>
		local key = gladeId .. "/" .. kind
		local memo = remainings[key]
		if memo == nil then
			memo = rooted(function()
				return Compose.formula(function(use: Use)
					local at = use(now)
					local stamp = use(stampOf(gladeId, kind))
					local left = seedData.DRAIN[kind].empty - (at - stamp)
					return if left < 0 then 0 else left
				end)
			end)
			remainings[key] = memo
		end
		return memo
	end

	function service.level(gladeId: string, kind: string): ReadOnlyValue<number>
		local key = gladeId .. "/" .. kind
		local memo = levels[key]
		if memo == nil then
			memo = rooted(function()
				return Compose.formula(function(use: Use)
					local left = use(service.remaining(gladeId, kind))
					return left / seedData.DRAIN[kind].empty
				end)
			end)
			levels[key] = memo
		end
		return memo
	end

	function service.state(gladeId: string, kind: string): ReadOnlyValue<string>
		local key = gladeId .. "/" .. kind
		local memo = states[key]
		if memo == nil then
			memo = rooted(function()
				return Compose.formula(function(use: Use)
					local at = use(now)
					local stamp = use(stampOf(gladeId, kind))
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

	function service.nectarOf(gladeId: string): Value<string>
		return assigned[gladeId]
	end

	function service.refill(gladeId: string, kind: string)
		stampOf(gladeId, kind):set(now:peek())
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

	function service.dump(): { GladeSupply }
		local out: { GladeSupply } = {}
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
