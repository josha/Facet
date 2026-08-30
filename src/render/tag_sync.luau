--!strict
--[[ THE CLASSIFICATION-TAG SEAM'S PURE RULING: who owns a tag, and what one
	sync has to add and remove.

	WHY IT IS ITS OWN MODULE, in the idiom `render/stage_content` and
	`render/foreign_content` already set: the decision is pure, BOTH targets have
	to reach the same answer, and the live one cannot be loaded headlessly
	(`screen_target` touches engine globals at module scope). A ruling that only
	the engine-side adapter can execute is a ruling no spec can drive, and this
	one went wrong for four days under 7,116 green cases precisely because
	nothing headless could see it.

	THE DEFECT THIS EXISTS TO MAKE UNREPEATABLE. The tag rename
	`luau-*` -> `facet-*` (`36d1883`, 2026-08-18) rewrote 395 literals and left
	every hand-counted LENGTH behind: the retired prefix is five characters and
	the new one is six, so `string.sub(tag, 1, 5) == "facet-"` compares a
	five-character string against a six-character literal and is CONSTANT. The
	removal half of the adapter's `syncTags` became dead code, `syncTags` became
	purely additive, and every classification tag a node ever wore stayed on it
	for the node's whole life — surface, selection, role, toggle, error, shape,
	typography and skinned slot. A picker segment declared `surface = "plain"`
	kept `facet-surface-control` and the sheet painted an opaque plate over the
	tab indicator behind it.

	So the length is READ OFF the literal and both live here, spelled once, in a
	module a spec can require. `tests/tag_sync.spec.luau` drives the behaviour;
	`tests/prefix_tests.spec.luau` scans the repository for the shape.

	depends on: nothing. Deliberately — a pure ruling with no requires is a
	ruling any harness can load.
]]

local tag_sync = {}

-- Every tag `tokens/sheet_model.classifyTags` mints begins with this. The
-- adapter owns exactly these on an instance and diffs the rest away; anything
-- else on the node belongs to the game and is never touched.
tag_sync.PREFIX = "facet-"

--[[ IS THIS TAG THE ADAPTER'S TO REMOVE?

	The length is `#tag_sync.PREFIX` rather than a number, which is the whole
	point: a future rename can change the string and cannot desynchronise the
	count. `screen_chrome`'s icon-tag loop was already using this idiom with
	`chrome_slots.ICON_TAG_PREFIX` one file over. ]]
function tag_sync.owns(tag: string): boolean
	return string.sub(tag, 1, #tag_sync.PREFIX) == tag_sync.PREFIX
end

export type Plan = {
	add: { string },
	remove: { string },
}

--[[ ONE SYNC, AS TWO LISTS.

	`current` is what the node wears right now (the engine's `GetTags`, or the
	headless twin's own list); `desired` is what `classifyTags` just said it
	should wear. A tag comes OFF when this seam owns it and the desired set does
	not carry it; a tag goes ON when the desired set carries it and the node does
	not already. Both lists are sorted, so a caller's write order is
	deterministic and two runs of the same state produce the same plan.

	IT NEVER TOUCHES A TAG IT DOES NOT OWN. A game may tag Facet's instances for
	its own reasons; that is why the removal side asks `owns` at all rather than
	removing everything absent from `desired`. ]]
function tag_sync.diff(current: { string }, desired: { [string]: boolean }): Plan
	local have: { [string]: boolean } = {}
	for _, tag in current do
		have[tag] = true
	end
	local remove: { string } = {}
	for _, tag in current do
		if tag_sync.owns(tag) and desired[tag] ~= true then
			table.insert(remove, tag)
		end
	end
	local add: { string } = {}
	for tag in desired do
		if not have[tag] then
			table.insert(add, tag)
		end
	end
	table.sort(remove)
	table.sort(add)
	return { add = add, remove = remove }
end

return tag_sync
