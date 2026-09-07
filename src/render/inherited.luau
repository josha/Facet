--!strict
--[[ THE RENDER SIDE OF THE TWO INHERITED CHANNELS (stabilization pass 2026-09-07,
	stream C; design note
	`docs/superpowers/specs/2026-09-07-inherited-tint-disabled.md`).

	`enabled` and `tint` may be declared on a layout container, where they apply to
	the container's whole SUBTREE. `src/mount.luau` owns the cascade — it is the one
	pass that sees a blueprint's ancestors and its mounted node at the same moment —
	and it publishes two derived fields on every node it resolves:

	    node.disabled        this node is inside (or is) a disabled subtree
	    node.inheritedTint   the tint it paints, when it declared none

	This module is the two lines of policy the renderer needs to turn those into
	adapter writes, and it lives HERE rather than in `renderer.luau` for the reason
	`prop_channels`, `layout_node` and `presentation_channel` do: the renderer is
	within a couple of thousand characters of the 200,000-char `Source` write cap,
	past which a module silently stops live-syncing into an open Studio session.
	Nothing below reads a `renderer.attach` upvalue, so the extraction is one-way by
	construction.

	WHY THESE RIDE THE PROPS THE FRAMEWORK ALREADY HAS, and not a new pair. A second
	prop name would be a second state channel for one fact, and the whole point of
	the cascade is that a node which INHERITED a disable is indistinguishable, from
	here on, from one that declared it: same property, same authority, same adapter
	branch, same theme rule. `enabled` carries the resolved disabled state (which is
	why `render/authority.luau` declares it on `common` — any class may wear it), and
	`tint` carries the resolved colour, restricted by `prop_channels`'
	`BINDING_PROP_CLASSES` to the five classes that have a channel to paint it into.
]]

local classContract = require("../class_contract")
local prop_channels = require("./prop_channels")

local inherited = {}

-- the mounted-node reading of `enabled`: own `false`, or any ancestor's.
-- Re-exported rather than re-implemented — `class_contract` owns the definition,
-- and `present/focus_map` reads the identical function.
inherited.isDisabled = classContract.isDisabled

--[[ The value the adapter should receive for `prop` on `node`, given what the
	author declared there. Everything except the two inherited channels is the
	declared value unchanged.

	The RESOLVED value, not the authored one, is what makes the cascade true at the
	engine: a Button that declared nothing but sits inside a disabled panel has to
	be non-interactable, and a Text that declared no tint has to paint the one its
	container declared. ]]
function inherited.resolve(node: any, prop: string, declared: any): any
	if prop == "enabled" then
		return not classContract.isDisabled(node)
	end
	if prop == "tint" and declared == nil then
		return node.inheritedTint
	end
	return declared
end

--[[ WHICH CLASSES CONSUME A RESOLVED `enabled` (RED-TEAM I3).

	The write used to go to every node in a disabled subtree — all 26 classes,
	`Screen`, `VStack`, `Spacer`, `Divider`, `Path` included. Two costs, and the
	first is permanent: the engine adapter ELIDES a container that draws nothing
	(`screen_target`'s `ELIDABLE_CLASSES`: VStack, HStack, ZStack, Grid, Anchor,
	Spacer) and materializes it the moment any property is written to it, with no
	re-elide. Switching a panel off therefore created a real `Frame` per elidable
	container for the life of the surface. What it bought was a
	`facet-state-disabled` tag that NOTHING SELECTS: the one rule the framework
	emits for that tag selects `TextLabel`.

	So the write goes where something reads it:
	  * `Button`, `Toggle`, `TextField` — the engine's own non-interactable state
	    (`Active`/`Interactable`), which is what makes an ancestor-disabled control
	    genuinely unpressable rather than merely skipped;
	  * `Text` — the `TextLabel` the themed `Disabled subtree text` rule paints.

	THE HONEST LIMIT, STATED. A theme package that wanted to key its own disabled
	rule on another class — a `Frame` background, say — would not find the tag
	there. That is a deliberate trade: a permanent instance per elidable container,
	on every screen that switches a panel off, against a rule nobody has written.
	Widening it is this one table plus the rule that justifies the widening, and
	`api.md`'s inheritance section says so in public. ]]
local ENABLED_CONSUMERS: { [string]: boolean } = {
	Button = true,
	Toggle = true,
	TextField = true,
	Text = true,
}

--[[ May this node emit this prop at all? `prop_channels.emitsBinding` answers the
	CLASS-vs-authority half (the `tint` allowlist, the `thickness` one); this adds the
	`enabled` half, which the authority manifest cannot express because `enabled` is
	declared on `common` so that a node of any class MAY carry a resolved value —
	"may carry" and "is worth writing" are different questions and this is the second.

	Both renderer write sites ask this one function, so the authored path and the
	inherited path cannot disagree about which containers get materialized. ]]
function inherited.emits(node: any, prop: string): boolean
	if not prop_channels.emitsBinding(node.class, prop) then
		return false
	end
	return prop ~= "enabled" or ENABLED_CONSUMERS[node.class] == true
end

--[[ Does this node owe an `enabled` write? True for a class that consumes one, when
	the author declared a value OR the cascade resolved a disable onto it. The second
	half is the case the creation-time props loop cannot see, because it iterates the
	props the author wrote.

	A NODE WITH NO `props` TABLE IS A STRUCTURAL REGION (`When`/`ForEach`/
	`ErrorBoundary`). The cascade resolves those too, because the re-walk has to pass
	through them, but they materialize nothing and have no property to write — so the
	table's presence is the test for "is there an instance behind this". ]]
function inherited.needsEnabledWrite(node: any): boolean
	local props = node.props
	if props == nil or ENABLED_CONSUMERS[node.class] ~= true then
		return false
	end
	return props.enabled ~= nil or node.disabled == true
end

--[[ Does this node have a tint to write at creation — its own, or one it
	inherited? The caller still asks `inherited.emits` first: a container may carry a
	`tint` prop and has no channel to paint it into. ]]
function inherited.hasTint(node: any): boolean
	return node.inheritedTint ~= nil or (node.props ~= nil and node.props.tint ~= nil)
end

return inherited
