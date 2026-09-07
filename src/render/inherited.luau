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

--[[ Does this node owe an `enabled` write its own props cannot produce? True for
	exactly the node that inherited a disable and declared no `enabled` of its own —
	the case the creation-time props loop cannot see, because it iterates the props
	the author wrote.

	A NODE WITH NO `props` TABLE IS A STRUCTURAL REGION (`When`/`ForEach`/
	`ErrorBoundary`). The cascade resolves those too, because the re-walk has to pass
	through them, but they materialize nothing and have no property to write — so the
	table's presence is the test for "is there an instance behind this". ]]
function inherited.needsEnabledWrite(node: any): boolean
	return node.disabled == true and node.props ~= nil and node.props.enabled == nil
end

--[[ Does this node have a tint to write at creation — its own, or one it
	inherited? The caller still asks `prop_channels.emitsBinding` first: a container
	may carry a `tint` prop and has no channel to paint it into. ]]
function inherited.hasTint(node: any): boolean
	return node.inheritedTint ~= nil or (node.props ~= nil and node.props.tint ~= nil)
end

return inherited
