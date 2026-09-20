--!strict
-- UI inheritance policy shared by every domain-node construction path.
local schema = require("../blueprint_schema")
export type Inherit = { disabled: boolean, tint: any }

local TINT_STOPS: { [string]: boolean } = { Button = true, Toggle = true, TextField = true }

-- the two prop names whose change re-resolves a subtree (see `recascade`)

-- two records say the same thing when they answer the same two questions
local function sameRecord(a: Inherit?, b: Inherit?): boolean
	if a == b then
		return true
	end
	if a == nil or b == nil then
		return false
	end
	return a.disabled == b.disabled and a.tint == b.tint
end

--[[ Resolve one node against the record it was handed. Sets the two derived
	fields — `node.disabled` (this node is inside, or is, a disabled subtree) and
	`node.inheritedTint` (the tint it paints when it declared none) — records the
	incoming record for a later re-walk, and returns the record its children get,
	whether either derived field MOVED, and whether the outgoing record is the one
	this node handed down last time.

	The derived fields are deliberately NOT folded into `node.props`: props stays
	"what the author declared", which is what makes "does this node override?"
	answerable at all. ]]
local function applyInherited(node: any, inherited: Inherit?): (Inherit?, boolean, boolean, boolean)
	local props = node.props
	local ownEnabled = if props ~= nil then props.enabled else nil
	local ownTint = if props ~= nil then props.tint else nil
	--[[ THE OFF PATH, AND IT IS MOST OF EVERY MOUNT. A screen that
		declares neither channel — which is every screen shipped before this feature
		and most screens after it — has nothing above, nothing here, and nothing
		resolved on a previous pass, so there is no answer to compute and no field to
		write. Measured on the reviewer's 3,281-node tree, best of twelve: without
		this the body's four field writes and four returns cost 1.73-1.79 ms against
		a 1.13-1.20 ms baseline, ~50% of a mount, for a feature the tree does not use.

		`node.inheritOut ~= nil` IS the "nothing resolved before" test on its own —
		a disabled node always hands a record down, and an inherited tint always came
		from one — but the two derived fields are read as well, so the early-out is
		provably equivalent to the body rather than equivalent-by-invariant. Three
		nil reads is a price worth paying to keep that argument short. ]]
	if
		inherited == nil
		and ownTint == nil
		and ownEnabled ~= false
		and node.inheritOut == nil
		and node.disabled == nil
		and node.inheritedTint == nil
	then
		return nil, false, false, true
	end
	local inTint = if inherited ~= nil then inherited.tint else nil
	local disabled = (inherited ~= nil and inherited.disabled == true) or ownEnabled == false
	local inheritedTint = if ownTint == nil then inTint else nil

	local disabledMoved = (node.disabled == true) ~= disabled
	local tintMoved = node.inheritedTint ~= inheritedTint
	node.disabled = if disabled then true else nil
	node.inheritedTint = inheritedTint
	node.inheritFrom = inherited

	--[[ THE READ-SITE HALF OF THE `transparency` REFUSAL. The
		schema refuses an alpha on a container's `tint` at construction, but that prop
		is REACTIVE: a `Compose.cell({ …, transparency = 0.5 })` is a first-class
		authoring form the constructor never sees, and without this it walked straight
		through, claimed `TextTransparency` on every `Text` in the subtree, and — with a
		`UI.Path` down there — crashed the render with a message naming a class the
		author never wrote `transparency` on.

		HERE is the read site, because here is where a container's own tint stops being
		its own and becomes the thing it hands down. The predicate is the schema's own
		(`INHERITED_TINT_CLASSES`, derived from `channel = "inherit"`), and the sentence
		is the schema's own string, so the two halves of one ruling cannot drift.

		A LEAF is untouched: it paints its alpha on itself, which is the bounded,
		named decision the channel exists for. ]]
	if ownTint ~= nil and (ownTint :: any).transparency ~= nil and schema.INHERITED_TINT_CLASSES[node.class] then
		error(`Facet {node.class}.tint at {node.path}: {schema.INHERITED_TINT_ALPHA_REFUSAL}`, 0)
	end
	local childTint = if TINT_STOPS[node.class] then nil else (if ownTint ~= nil then ownTint else inTint)
	local previous: Inherit? = node.inheritOut
	local out: Inherit? = nil
	if disabled or childTint ~= nil then
		if inherited ~= nil and inherited.disabled == disabled and inherited.tint == childTint then
			out = inherited -- the same answer this node was handed: share the table
		elseif previous ~= nil and previous.disabled == disabled and previous.tint == childTint then
			out = previous -- unchanged: descendants keep the reference they hold
		else
			out = { disabled = disabled, tint = childTint } :: Inherit
		end
	end
	--[[ `outSame` IS THE STOP CONDITION FOR THE RE-WALK, and it is a different
		question from whether this node moved. A container that declares its OWN tint
		never moves when that tint changes — its `inheritedTint` is nil either way —
		while everything below it moves, which is exactly the bound-container case.
		So the walk descends on what this node HANDS DOWN, not on what it wears. ]]
	local outSame = sameRecord(out, previous)
	node.inheritOut = out
	return out, disabledMoved, tintMoved, outSame
end

return { apply = applyInherited }
