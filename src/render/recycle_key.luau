--!strict
--[[ THE RECYCLE-KEY FAMILY, lifted out of `render/renderer.luau` on 2026-09-03
	(wicked-fast T8 R2's Phase 0): `recycleKey`, `propSignature`, `wornSignature`,
	the worn-set updater and the `recycleKeyPartsOf` bookkeeping. The ledger row's
	trigger named this the next seam the moment the scroll-into-view family left;
	this task's own fix round needed the room W1b's self-review round had already
	spent down to 733 characters, so it is taken FIRST, on its own, exactly as
	Phase 0 was.

	PURE OVER `prop_channels` + `chrome_slots.hintKey` — no `renderer.attach`
	upvalue at all. Every per-path record this module owns (`partsOf`, `wornOf`)
	is a fresh table built inside `recycle_key.new()`, so two attached surfaces
	share nothing and this module requires nothing back.

	NO BEHAVIOUR CHANGE. The signature this commit signs is still `STYLE_PROPS`
	only — the fix round's own broadening to `BINDING_PROPS ∪ STYLE_PROPS`
	(T8 review, Critical 1) is a SEPARATE commit on top of this one, because a
	seam extraction and a correctness fix are two different claims and this
	repository never ships them in the same diff. `tests/recycle_key_seam.spec.luau`
	mechanises the read/write sets and the mutations; the renderer's own suite
	(`instance_recycling*`, `recycle_prop_signature.spec.luau`) is the behaviour
	half, unmoved by the split. ]]

local prop_channels = require("./prop_channels")
local chrome_slots = require("../tokens/chrome_slots")

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
	-- WORN-SET MAINTENANCE: called from the ONE place(s) a tracked prop is ever
	-- written to the adapter. `value == nil` REMOVES the prop from `path`'s worn
	-- set; anything else ADDS it. Callers are trusted to call this only for a
	-- prop this module's namespace actually tracks — see the host file for which
	-- that is in this commit.
	noteWorn: (path: string, prop: string, value: any) -> (),
	-- the structural parts, recorded once at create/adopt
	declareParts: (path: string, class: string, hint: any, kind: string) -> (),
	-- the CREATE-TIME signature: the tracked names already present on `node.props`
	-- (used for the adoption lookup, before this path has a worn set of its own)
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
			if STYLE_PROPS[name] then
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
