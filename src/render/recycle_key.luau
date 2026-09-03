--!strict
--[[ THE RECYCLE-KEY FAMILY, lifted out of `render/renderer.luau` on 2026-09-03
	(wicked-fast T8 R2's Phase 0): `recycleKey`, `propSignature`, `wornSignature`,
	the worn-set updater and the `recycleKeyPartsOf` bookkeeping. The ledger row's
	trigger named this the next seam the moment the scroll-into-view family left;
	this task's own fix round needed the room W1b's self-review round had already
	spent down to 733 characters, so it was taken first, on its own, exactly as
	Phase 0 was — the module's own git history carries that behaviour-neutral
	commit; this docstring describes the state AFTER the fix that landed on top
	of it.

	PURE OVER `prop_channels` + `chrome_slots.hintKey` — no `renderer.attach`
	upvalue at all. Every per-path record this module owns (`partsOf`, `wornOf`)
	is a fresh table built inside `recycle_key.new()`, so two attached surfaces
	share nothing and this module requires nothing back.

	THE NAMESPACE (T8 R2, review Critical 1): structural PARTS (class, hint,
	kind — frozen at create) plus the set of prop names in
	`BINDING_PROPS ∪ STYLE_PROPS` the instance CURRENTLY wears non-nil. NOT
	style-only — W1b's own narrowing of the create-time key to `STYLE_PROPS`
	let a row adopt an instance wearing a BINDING prop (`enabled`, `image`,
	`tint`, ...) it never itself declared, because `applyProps` iterates only
	`node.props` and never clears a prop the adopter did not name. Layout props
	are EXCLUDED, for one reason and no other: every layout write
	(`commit_walks.luau` textSize/textFont/padding/textWrapped, `renderer.luau`
	clipChildren) is value-diffed against caches `captureParkedProps`/
	`restoreParkedProps` carry across an adoption, and padding has its own
	explicit un-pad branch — neither has the "stale bespoke child" failure a
	tracked prop's ABSENCE creates, so putting them in the key would only
	narrow buckets for no safety bought. `signature()` (create) and `noteWorn`
	(park, live) sign the SAME two tables, so the two halves cannot drift apart
	in WHICH NAMES ARE SIGNABLE. They can still disagree about one name in ONE
	direction (RED-TEAM T9, finding 7): `signature` counts a declared prop,
	`noteWorn` records only what the adapter actually received, and two writers
	drop a prop in between — `emitsBinding` refuses a tracked name this class
	does not emit (`thickness` on anything but a `Path`), and `applyProp` can
	transform a value to nil (`drawnButtonText`) so `noteWorn` REMOVES a name
	`signature` counted. Both are the safe direction — the park key is exactly
	"what this instance is wearing", which is the truth adoption needs — so the
	cost is a MISSED reuse (two identical Dividers never share a bucket), never
	a wrong one. `tests/recycle_key_seam.spec.luau` mechanises the seam's
	own read/write set and one-way shape; `tests/recycle_prop_signature.spec.luau`
	drives the namespace claim, including the ragged-binding regression this
	round closed. ]]

local prop_channels = require("./prop_channels")
local chrome_slots = require("../tokens/chrome_slots")

local BINDING_PROPS = prop_channels.BINDING_PROPS
local STYLE_PROPS = prop_channels.STYLE_PROPS

local recycle_key = {}

-- the structural facts a path was CREATED/ADOPTED with — frozen once, because a
-- dying node's decoration hint is not available at remove time. The hint here
-- is the TABLE, not its hashed string: hints come off frozen blueprints
-- (`chrome_slots.readHint`), so holding the table is safe as long as nothing
-- ever mutates one in place, and `key()` below re-hashes it by CONTENT at the
-- moment it is actually needed rather than paying for it on every create.
export type Parts = { class: string, hint: any, kind: string }

export type RecycleKey = {
	-- WORN-SET MAINTENANCE: called from EVERY choke point that ever writes a
	-- BINDING or STYLE prop to the adapter — `applyProp`, `applyStyleProp`, and
	-- (via a passed-through dep, since their value is DERIVED and not simply
	-- `node.props[prop]`) the two compact-ladder writes in `commit_walks.luau`.
	-- `value == nil` REMOVES the prop from `path`'s worn set; anything else
	-- ADDS it. Callers are trusted to call this only for a prop in
	-- `BINDING_PROPS ∪ STYLE_PROPS` — every current call site already is, by
	-- construction (an `emitsBinding`/style-authority write, or a name this
	-- module itself asserts is tracked).
	noteWorn: (path: string, prop: string, value: any) -> (),
	-- the structural parts, recorded once at create/adopt
	declareParts: (path: string, class: string, hint: any, kind: string) -> (),
	-- the CREATE-TIME signature: the BINDING ∪ STYLE names already present on
	-- `node.props` (used for the adoption lookup, before this path has a worn
	-- set of its own) — the SAME namespace `noteWorn` maintains live, so the
	-- create key and the park key can never disagree about what counts.
	signature: (node: any) -> string,
	-- the key string, shared by the adoption lookup and the park-time build
	key: (class: string, hint: any, kind: string, sig: string) -> string,
	-- the PARK-TIME key, built from this path's frozen parts plus its CURRENT
	-- worn set — nil if this path never had parts recorded (recycling was off)
	parkKey: (path: string) -> string?,
	-- clears BOTH records for a departed path, so a path string reused by a
	-- structurally different node later starts from nothing
	forget: (path: string) -> (),
}

function recycle_key.new(): RecycleKey
	local partsOf: { [string]: Parts } = {}
	local wornOf: { [string]: { [string]: boolean } } = {}

	local function sortedJoin(names: { string }): string
		table.sort(names)
		return table.concat(names, ",")
	end

	local function noteWorn(path: string, prop: string, value: any)
		if value == nil then
			local worn = wornOf[path]
			if worn ~= nil then
				worn[prop] = nil
			end
		else
			local worn = wornOf[path]
			if worn == nil then
				worn = {}
				wornOf[path] = worn
			end
			worn[prop] = true
		end
	end

	local function declareParts(path: string, class: string, hint: any, kind: string)
		partsOf[path] = { class = class, hint = hint, kind = kind }
	end

	local function signature(node: any): string
		local props = node.props
		if props == nil then
			return ""
		end
		local names = {}
		for name in props do
			if BINDING_PROPS[name] or STYLE_PROPS[name] then
				table.insert(names, name)
			end
		end
		return sortedJoin(names)
	end

	local function key(class: string, hint: any, kind: string, sig: string): string
		return `{class}\0{chrome_slots.hintKey(hint)}\0{kind}\0{sig}`
	end

	local function wornSignature(path: string): string
		local worn = wornOf[path]
		if worn == nil then
			return ""
		end
		local names = {}
		for name in worn do
			table.insert(names, name)
		end
		return sortedJoin(names)
	end

	local function parkKey(path: string): string?
		local parted = partsOf[path]
		if parted == nil then
			return nil
		end
		return key(parted.class, parted.hint, parted.kind, wornSignature(path))
	end

	local function forget(path: string)
		partsOf[path] = nil
		wornOf[path] = nil
	end

	return {
		noteWorn = noteWorn,
		declareParts = declareParts,
		signature = signature,
		key = key,
		parkKey = parkKey,
		forget = forget,
	}
end

return recycle_key
