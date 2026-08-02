--!strict
-- Touch gesture normalization + composition (corrections addendum §2: "Touch
-- gestures start with GuiObject events"). The ENGINE recognizes gestures —
-- GuiObject fires TouchTap, TouchLongPress, TouchPan, TouchPinch, TouchRotate,
-- TouchSwipe — so we NEVER re-recognize from raw samples. This module does the
-- two jobs Roblox does not: (1) normalize the engine's positional callback
-- arguments into stable, headlessly-comparable value objects, and (2) arbitrate
-- which gesture stream OWNS the interaction when several fire together (the
-- engine happily fires pan alongside pinch).
--
-- Robustness rule: normalize must accept the engine's documented argument shapes
-- and NEVER yield or error on a missing optional field — a partial callback
-- (e.g. a swipe with only a direction) still yields a well-formed Gesture.

local touch_gestures = {}

export type Vec = { x: number, y: number }

export type Gesture = {
	kind: string, -- "tap" | "longPress" | "pan" | "pinch" | "rotate" | "swipe"
	state: string, -- "began" | "changed" | "ended" | "none"
	positions: { Vec }, -- normalized touch points (empty when the event carries none)
	totalTranslation: Vec?, -- pan
	velocity: (Vec | number)?, -- pan: Vector2; pinch/rotate: number
	scale: number?, -- pinch
	rotation: number?, -- rotate
	direction: string?, -- swipe: Enum.SwipeDirection name
}

-- engine callback names AND already-short kinds both resolve to the short kind.
local KIND_MAP: { [string]: string } = {
	TouchTap = "tap",
	TouchLongPress = "longPress",
	TouchPan = "pan",
	TouchPinch = "pinch",
	TouchRotate = "rotate",
	TouchSwipe = "swipe",
	tap = "tap",
	longPress = "longPress",
	pan = "pan",
	pinch = "pinch",
	rotate = "rotate",
	swipe = "swipe",
}

-- Enum.UserInputState name -> normalized lifecycle state. Anything else (None,
-- Cancel, nil) collapses to "none".
local STATE_MAP: { [string]: string } = {
	Begin = "began",
	Change = "changed",
	End = "ended",
}

-- extract a name from an Enum-like value: a raw string, an { Name = ... } table
-- (our test fakes), or a real `EnumItem` — which, like `Vector2`, is USERDATA
-- rather than a table (SEAM-3). Read through the same guarded door: anything
-- without a string `.Name` is simply nameless. nil-tolerant.
local function nameOf(v: any): string?
	local kind = type(v)
	if kind == "string" then
		return v
	end
	if kind == "table" then
		return if type(v.Name) == "string" then v.Name else nil
	end
	if v == nil or kind == "number" or kind == "boolean" or kind == "function" then
		return nil
	end
	local ok, name = pcall(function()
		return (v :: any).Name
	end)
	return if ok and type(name) == "string" then name else nil
end

local function mapState(v: any): string
	return STATE_MAP[nameOf(v) or ""] or "none"
end

-- normalize a Vector2-like: engine {X=,Y=}, our test {x=,y=}, or a real Vector2.
-- Missing components read as 0; a nil input returns nil (optional field absent).
--
-- A REAL `Vector2` IS USERDATA, not a table (SEAM-3). A table-only reader was
-- green against every headless `{X=,Y=}` fixture and returned an empty positions
-- list for every touch a device actually delivered — the "headless shape is not
-- the engine shape" defect class. So a non-table value object is read through the
-- same X/Y door, pcall-guarded: an opaque userdata that has no numeric X/Y is
-- still not a position, and nothing is invented for it.
local function vec(v: any): Vec?
	local kind = type(v)
	if kind == "table" then
		local x = v.x or v.X or 0
		local y = v.y or v.Y or 0
		return { x = x, y = y }
	end
	if v == nil or kind == "number" or kind == "string" or kind == "boolean" or kind == "function" then
		return nil
	end
	local ok, x, y = pcall(function()
		return (v :: any).X, (v :: any).Y
	end)
	if ok and type(x) == "number" and type(y) == "number" then
		return { x = x, y = y }
	end
	return nil
end

local function vecList(list: any): { Vec }
	local out: { Vec } = {}
	if type(list) == "table" then
		for _, v in list do
			local point = vec(v)
			if point ~= nil then
				table.insert(out, point)
			end
		end
	end
	return out
end

local function num(v: any): number?
	if type(v) == "number" then
		return v
	end
	return nil
end

-- normalize(kind, args): `args` is the engine callback's positional arguments as
-- an array, matching the GuiObject signatures:
--   TouchTap(positions)                                    -> args = { positions }
--   TouchLongPress(positions, state)                       -> args = { positions, state }
--   TouchPan(positions, totalTranslation, velocity, state) -> args = { positions, trans, vel, state }
--   TouchPinch(positions, scale, velocity, state)          -> args = { positions, scale, vel, state }
--   TouchRotate(positions, rotation, velocity, state)      -> args = { positions, rotation, vel, state }
--   TouchSwipe(direction, numberOfTouches)                 -> args = { direction, count }
function touch_gestures.normalize(kind: string, args: { any }?): Gesture
	local short = KIND_MAP[kind] or kind
	local a = args or {}

	if short == "tap" then
		-- taps are instantaneous: no lifecycle state.
		return { kind = "tap", state = "none", positions = vecList(a[1]) }
	elseif short == "longPress" then
		return { kind = "longPress", state = mapState(a[2]), positions = vecList(a[1]) }
	elseif short == "pan" then
		return {
			kind = "pan",
			state = mapState(a[4]),
			positions = vecList(a[1]),
			totalTranslation = vec(a[2]),
			velocity = vec(a[3]), -- pan velocity is a Vector2
		}
	elseif short == "pinch" then
		return {
			kind = "pinch",
			state = mapState(a[4]),
			positions = vecList(a[1]),
			scale = num(a[2]),
			velocity = num(a[3]), -- pinch velocity is a scalar
		}
	elseif short == "rotate" then
		return {
			kind = "rotate",
			state = mapState(a[4]),
			positions = vecList(a[1]),
			rotation = num(a[2]),
			velocity = num(a[3]), -- rotate velocity is a scalar
		}
	end

	-- swipe (and any unknown kind falls through here defensively): instantaneous,
	-- carries a direction name and no touch positions.
	return { kind = "swipe", state = "none", positions = {}, direction = nameOf(a[1]) }
end

-- ── arbitration ──────────────────────────────────────────────────────────────
-- When several gesture streams fire at once, one OWNS the interaction. Policy:
--   * pinch/rotate (two-finger) PREEMPT pan (one-finger) — the higher-rank
--     two-finger intent wins the moment it begins;
--   * a began longPress PREEMPTS tap;
--   * swipe and tap are instantaneous: they never take ownership, and are
--     "preempted" (suppressed) while a higher-rank continuous gesture owns.
-- Ownership is acquired on began/changed and RELEASES when the owning kind
-- reports state "ended".
local RANK: { [string]: number } = {
	pinch = 3,
	rotate = 3,
	pan = 2,
	longPress = 1,
	tap = 0,
	swipe = 0,
}

local function isInstant(kind: string): boolean
	return kind == "tap" or kind == "swipe"
end

export type Arbiter = {
	feed: (self: Arbiter, gesture: Gesture) -> string, -- "own" | "preempted" | "pass"
	owner: (self: Arbiter) -> string?,
	reset: (self: Arbiter) -> (),
}

-- `opts` is RESERVED: the arbitration policy (RANK above) is fixed, and there is
-- no option today that changes it. An accepted-and-ignored table is the silent
-- failure class (SEAM-4) — an author biasing pinch over pan with
-- `newArbiter({ rank = ... })` would get exactly the default behaviour and no
-- word about it. So the parameter stays in the signature (the shape is where a
-- future option lands) and a NON-EMPTY table is refused at construction, naming
-- the keys it was given. nil and `{}` remain legal.
function touch_gestures.newArbiter(opts: { [string]: any }?): Arbiter
	if opts ~= nil then
		if type(opts) ~= "table" then
			error(`LuauUI touchGestures.newArbiter: opts must be a table (got {type(opts)})`, 0)
		end
		local keys: { string } = {}
		for key in opts :: any do
			table.insert(keys, tostring(key))
		end
		if #keys > 0 then
			table.sort(keys)
			error(
				`LuauUI touchGestures.newArbiter: options are reserved and none exist yet — got `
					.. `\{ {table.concat(keys, ", ")} \}. The arbitration policy (pinch/rotate preempt pan; a began `
					.. "longPress preempts tap; tap and swipe never own) is fixed; pass nil or {} until an option is "
					.. "declared, or arbitrate yourself with the gesture stream.",
				0
			)
		end
	end

	local owner: string? = nil

	local arbiter = {}

	function arbiter.feed(_: any, gesture: Gesture): string
		local kind = gesture.kind
		local state = gesture.state

		-- terminal frame: the owning kind releases the interaction.
		if state == "ended" then
			if owner == kind then
				owner = nil
				return "own" -- final owned frame; ownership is now free
			end
			return "pass"
		end

		-- instantaneous gestures never own; they are suppressed under an owner.
		if isInstant(kind) then
			if owner ~= nil and RANK[owner] > RANK[kind] then
				return "preempted"
			end
			return "pass"
		end

		-- continuous gesture (began / changed).
		if owner == nil or owner == kind then
			owner = kind
			return "own"
		end
		if (RANK[kind] or 0) > (RANK[owner] or 0) then
			owner = kind -- higher-rank intent takes over (pinch/rotate over pan)
			return "own"
		end
		return "preempted" -- yields to the incumbent higher/equal-rank owner
	end

	function arbiter.owner(_: any): string?
		return owner
	end

	function arbiter.reset(_: any)
		owner = nil
	end

	return arbiter :: any
end

return touch_gestures
