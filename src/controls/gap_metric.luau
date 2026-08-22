--!strict
--[[ A GAP THAT MAY BE A THEME TOKEN — one vocabulary, one refusal, one live read,
	shared by every collection that spends a gutter in Luau arithmetic.

	WHY IT EXISTS. `newTable.rowGap` has taken a theme metric name since 2026-08-06,
	for a reason its own comment states plainly: the gap "is used in ARITHMETIC", so
	a name that reached `cum += height + rowGap` used to throw. `newVirtualList` and
	`newVirtualGrid` did the arithmetic too and took only a number (and, on
	`VirtualGrid.gap`, not even a `Readable`), so a consumer who wanted a
	theme-tracking gutter on a virtualized collection had exactly one legal route:
	hand-write a memo that reads the live snapshot and hands back pixels. That memo
	existed — `controls/row_actions.luau`'s `vlistGap()` — and it is the reason this
	module does: the framework required the boilerplate the precedent was about.

	THE THREE FORMS, and they are the same three on every field that uses this:

	  · a NUMBER — pixels, exactly as before;
	  · a STRING — a theme metric name: a space step ("xs".."xl") or a dotted path
	    ("controls.table.rowGap"), resolved against the live snapshot on every read,
	    so a theme swap moves the gutter with no rebuild;
	  · a `Readable` — the consumer's own live number (or name), read reactively.

	AN UNRESOLVABLE NAME IS REFUSED BY NAME, WHICH IS WHERE THIS DIVERGES FROM
	`newTable` AND DELIBERATELY SO. `table.luau` resolves a string and falls back to
	`0`, so `rowGap = "6"` — a number somebody quoted — is silently no gutter at
	all. Constitution §4's rule for a spec field is the opposite: an unknown value
	is an authoring mistake, never a silent no-op, and this is a field whose wrong
	answer is invisible (a gutter of zero looks exactly like a gutter nobody asked
	for). So the name is resolved ONCE at construction, against the snapshot the
	control can actually see, and a name that answers nothing names itself in the
	refusal. Every spelling `newTable` accepts and MEANS still works here; the only
	thing refused is the spelling that meant nothing there either.

	THE LIVE READ CANNOT REFUSE, and does not pretend to: a package swapped at
	runtime may drop a key the construction-time snapshot had. That read falls back
	to the default rather than throwing inside a memo, because a theme swap must not
	be able to tear down a mounted surface. The construction check is what makes
	that fallback rare rather than routine.

	Public interface: `gap_metric.reader(ctx) -> Reader`.
]]

local themeSnapshot = require("../themes/snapshot")

local gap_metric = {}

export type Ctx = {
	-- the environment whose `themeMetrics` a name resolves against; nil is a
	-- headless mount and resolves against the neutral package
	env: any,
	-- what to call this field in a refusal, e.g. "VirtualList.rowGap"
	label: string,
	-- the spec's own value (nil takes the default)
	value: any,
	-- the answer when the field is absent, and the floor a live read falls back to
	default: number,
	-- one sentence saying what this gutter IS, appended to every refusal about it
	what: string,
}

export type Reader = {
	-- inside a memo (subscribes to the live theme and to a Readable value)
	In: (use: any) -> number,
	-- outside one (reads the current value)
	Now: () -> number,
	-- is the answer capable of moving without a rebuild (a name or a Readable)
	live: boolean,
}

-- a garbage `themeMetrics` fact falls back to neutral rather than erroring — the
-- same §8.2 guard `table.luau` and `row_actions_metrics.luau` each keep, for the
-- same reason: a broken adapter fact must never leak past the seam that read it.
local function metricsOr(raw: any): any
	return if type(raw) == "table" and type(raw.controls) == "table" then raw else themeSnapshot.neutral()
end

function gap_metric.reader(ctx: Ctx): Reader
	local value = ctx.value
	local default = ctx.default
	local env = ctx.env

	if value == nil then
		return {
			In = function(): number
				return default
			end,
			Now = function(): number
				return default
			end,
			live = false,
		}
	end

	local isLive = type(value) == "table" and type((value :: any).get) == "function"
	assert(
		isLive or type(value) == "number" or type(value) == "string",
		`{ctx.label} must be a non-negative number, a theme metric name ("xs".."xl" or a dotted path such as `
			.. `"controls.table.rowGap"), or a Readable of either: {ctx.what}`
	)
	if type(value) == "number" then
		-- `value == value` is the NaN test: arithmetic on a NaN gutter propagates
		-- silently into every offset the index computes
		assert(
			value == value and value >= 0,
			`{ctx.label} must be a non-negative number when it is a number: {ctx.what}`
		)
	end

	local function snapshotIn(use: any?): any
		if env == nil then
			return themeSnapshot.neutral()
		end
		local key = env:get("themeMetrics")
		return metricsOr(if use ~= nil then use(key) else key:get())
	end

	if type(value) == "string" then
		--[[ RESOLVED ONCE, HERE, so a name that answers nothing is an authoring
			mistake with a message rather than a gutter of zero nobody ordered. It is
			checked against the snapshot this control can see right now, which is the
			installed package on a mounted surface and neutral on a headless one — the
			same snapshot the live read below will ask first. ]]
		local resolved = themeSnapshot.resolveNumber(snapshotIn(nil), value)
		assert(
			resolved ~= nil,
			`{ctx.label} = "{value}" is not a theme metric this package carries. Use a space step ("xs".."xl"), a `
				.. `dotted path into the metrics ("controls.table.rowGap"), or a plain number of pixels: {ctx.what}`
		)
		assert(
			(resolved :: number) >= 0,
			`{ctx.label} = "{value}" resolves to {resolved}, and a gutter may not be negative: {ctx.what}`
		)
	end

	--[[ ONE READ PATH FOR ALL THREE FORMS. A `Readable` is unwrapped first, then
		whatever it carried goes through the same resolver a literal would — so a
		consumer whose signal holds a metric NAME (a themed gutter the consumer is
		also switching) works without a second contract. `resolveNumber` returns a
		number unchanged, so the number case costs one type test. ]]
	local function read(use: any?): number
		local raw: any = if isLive then (if use ~= nil then use(value) else (value :: any):get()) else value
		if type(raw) == "number" then
			return if raw == raw and raw >= 0 then raw else default
		end
		return themeSnapshot.resolveNumber(snapshotIn(use), raw) or default
	end

	return {
		In = function(use: any): number
			return read(use)
		end,
		Now = function(): number
			return read(nil)
		end,
		-- a plain number is the one form that can never move on its own
		live = isLive or type(value) == "string",
	}
end

return gap_metric
