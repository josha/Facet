--!strict
--[[ ACTIVATE DISPATCH, lifted out of `present/presenter.luau` on 2026-09-20 to
	give that module headroom under Roblox's 200,000-character Source cap (a
	script at or over it SILENTLY fails to load).

	WHAT THIS DECIDES: what one press MEANS. A consumer override, a node's own
	`onActivate`, a Toggle whose value flips, the longest-prefix contribution
	that consumes it, or nothing — plus the activation gate that can refuse the
	press outright, and the echo collapse that keeps one physical press from
	dispatching twice when both the pointer path and the action system see it.

	PURE OVER ITS ARGUMENTS. It lived above `presenter.new` already and closed
	over no surface state: everything it needs — `activateEcho`, `now`,
	`emitFeedback`, `contributions`, `controller`, `onActivate`, `root` — rides
	on the `handle` it is given, which is why the presenter's own comment beside
	the handle record says the handle carries them. It writes only
	`handle.activateEcho[path]`, through that argument. Three call sites in the
	presenter reach it; nothing here reaches back.
]]
local Compose = require("../vendor/compose/core")
local feedbackLib = require("./feedback")
local focusMap = require("./focus_map")

local contributionsForPath = focusMap.contributionsForPath
local isDisabled = focusMap.isDisabled
local isPathPrefix = focusMap.isPathPrefix
local nodeAt = focusMap.nodeAt

local activate_dispatch = {}

-- Activate dispatch when the consumer passed NO opts.onActivate: (1) a
-- props.onActivate on the node; (2) a Toggle whose value is a settable signal
-- flips; (3) the longest-prefix contribution whose handleActivate consumes it;
-- (4) no-op. When opts.onActivate IS present it wins outright (override).
local function activateEffect(handle: any, node: any, path: string?, meta: any?)
	if handle.onActivate ~= nil then
		handle.onActivate(path, meta) -- consumer override
		return
	end
	if path == nil then
		return
	end
	-- (1) a leaf that declares its own effect
	if node ~= nil and node.props ~= nil and type(node.props.onActivate) == "function" then
		node.props.onActivate(path, meta)
		return
	end
	-- (2) Toggle auto-flip (contract.luau §Toggle: "Activate flips value")
	if node ~= nil and node.class == "Toggle" and node.dynamicProps ~= nil then
		local value = node.dynamicProps.value
		if Compose.isReadable(value) and type((value :: any).set) == "function" then
			value:set(not value:peek())
			return
		end
	end
	-- (3) longest-prefix contribution dispatch
	for _, c in contributionsForPath(handle.contributions, path) do
		if c.bundle.handleActivate ~= nil and c.bundle.handleActivate(path, meta) then
			return
		end
	end
	--[[ (4) THE PUBLIC DRAG VERB'S PICKUP (the adaptation wave's generic-verb
		row). An action-source Activate
		that nobody above wanted, on a mounted `UI.draggable`, ARMS it — and the
		next one commits it at the aim the focus ring has been feeding. The rule is
		`UI.VirtualList`'s own ("a source with no consumer Activate arms on
		Activate"), hoisted to the public verb, and it is asked LAST so that
		"nobody wanted it" is structural rather than predicted: a node's own
		`onActivate`, a Toggle's flip and every control contribution have already
		declined. Before this, the whole arm->navigate->commit path existed, was
		tested, and was bound to nothing on a pad or a keyboard. ]]
	if handle.controller ~= nil and handle.controller.activateArms ~= nil then
		if handle.controller.activateArms(path, meta) then
			return
		end
	end
	-- (5) no-op
end

-- Activate dispatch + the semantic `activate` event, which fires on the CAUSAL
-- FRAME (this one) and exactly once per press, AFTER the effect — so a subscriber
-- that reads the resulting state sees the state the press produced.
--
-- DISABLED FIRST (B-BTN4; verifier finding V12). This gate used to sit AFTER the
-- consumer override, so a screen presented with `opts.onActivate` — the gallery
-- client's own integration and the common game pattern — still activated a
-- disabled control. `enabled = false` has to mean disabled on every path,
-- including the one that overrides everything else, and a disabled control emits
-- no event either: nothing happened.
--
-- `source` names which of the two paths saw the press: "action" (the IAS
-- Activate action — Return, Space, ButtonA) or "tap" (a native tap/Activated
-- routed through the renderer). One press can be seen by BOTH exactly when this
-- surface mirrors Facet focus onto `GuiService.SelectedObject`: the engine then
-- fires the selected `GuiButton`'s own `Activated` for the same key press that
-- IAS delivered as Activate. That must still be ONE activation (roadmap Step 8,
-- the one-Activate-per-press rule), so a cross-source pair inside
-- ACTIVATE_ECHO_WINDOW collapses.
--
-- IDENTIFIED BY INPUT CLASS, NOT BY TIME ALONE. A time-only window would eat a
-- real mouse click that happened to land beside a key press — which is a thing
-- players do, and it broke the "one event per press" feedback pin the moment it
-- was tried. The engine's selection activation is distinguishable: its
-- `InputObject.UserInputType` is Keyboard or a Gamepad, never Mouse or Touch. So
-- only an {IAS Activate, non-pointer native Activated} pair collapses. Two
-- pointer taps, two key presses, or a tap next to a key press are all two
-- presses. The renderer's own detector echo guard draws the same line for the
-- same reason: deduplicate only what genuinely has two signals per press.
local ACTIVATE_ECHO_WINDOW = 0.05 -- s; far below any human double-press
local function isEngineSelectionTap(source: string?, meta: any?): boolean
	if source ~= "tap" or type(meta) ~= "table" then
		return false
	end
	return meta.pointer == "keyboard" or meta.pointer == "gamepad"
end
--[[ THE FIRST ACTIVATION WAKES THE SURFACE (`UI.activationGate`). A surface that
	is not the active one — a monitor in a room of monitors, an inactive panel in
	a split — must take a press to BECOME active without also pressing whatever
	sat under the finger. Before this, an app covered the whole subtree with a
	full-size transparent Button, which works for a tap and for the focus ring but
	is a second focus stop, a second hit target and a second thing to keep sized.

	It lives here because this is the ONE funnel every source arrives through:
	`"tap"` is pointer and touch, `"action"` is the IAS Activate the keyboard and
	the gamepad raise. A gate declared once is therefore honoured by all four with
	no per-source code.

	The DEEPEST closed gate on the path wins, so a gated panel inside a gated
	screen wakes one level per press, innermost first — the same longest-prefix
	rule contribution dispatch already uses. ]]
-- a press is not a reactive read: a binding is sampled through a `use` that
-- peeks, so the gate answers for THIS press and subscribes to nothing
local function peekUse(source: any): any
	if type(source) == "table" and type(source.peek) == "function" then
		return source:peek()
	end
	if type(source) == "function" then
		return source(peekUse)
	end
	return source
end

local function readGateClosed(gate: any): boolean
	return peekUse(gate.closed) == true
end

local function closedGateOn(handle: any, path: string): any?
	local node = if handle.root ~= nil then handle.root.node else nil
	local found = nil
	while node ~= nil do
		local gate = if node.meta ~= nil then node.meta.activationGate else nil
		if gate ~= nil and readGateClosed(gate) then
			found = gate
		end
		if node.path == path then
			break
		end
		local descend = nil
		for _, child in node.children or {} do
			if child.path ~= nil and (child.path == path or isPathPrefix(child.path, path)) then
				descend = child
				break
			end
		end
		node = descend
	end
	return found
end

local function dispatchActivate(handle: any, path: string?, meta: any?, source: string?)
	local node = if path ~= nil then nodeAt(handle.root.node, path) else nil
	if isDisabled(node) then
		return true -- consumes the verb and does nothing
	end
	if path ~= nil then
		local gate = closedGateOn(handle, path)
		if gate ~= nil then
			if type(gate.onOpen) == "function" then
				gate.onOpen(path, meta)
			end
			return true -- the press spent itself waking the surface
		end
	end
	if path ~= nil and source ~= nil and handle.activateEcho ~= nil then
		local at = handle.now()
		local selectionTap = isEngineSelectionTap(source, meta)
		local previous = handle.activateEcho[path]
		local echoes = previous ~= nil
			and previous.source ~= source
			and (selectionTap or previous.selectionTap == true)
			and (at - previous.at) < ACTIVATE_ECHO_WINDOW
		if echoes then
			-- A PRESS IS A PAIR, AND THE PAIR IS NOW SPENT (architecture review
			-- finding on the echo window). Recording the collapsing signal instead would roll the
			-- window forward on every echo, so a genuinely fast third press —
			-- key, echo, key — would land inside a window opened by the echo and
			-- be eaten as well. Clearing means the next signal starts a new press.
			handle.activateEcho[path] = nil
			return true -- the same press echoing through the other path
		end
		handle.activateEcho[path] = { at = at, source = source, selectionTap = selectionTap }
	end
	activateEffect(handle, node, path, meta)
	if path ~= nil and handle.emitFeedback ~= nil then
		-- THE PER-CONTROL VERB (director request 2026-08-13). `activate` is the
		-- default, not the only answer: a control (or any ancestor of it) may have
		-- declared what its own press means through
		-- `UI.sensoryFeedback(node, { activation = … })`, which the scene host
		-- resolves down the tree onto this node. `"none"` is a control the author
		-- deliberately silenced, and it emits nothing at all rather than a verb a
		-- subscriber then has to know to ignore.
		--
		-- `reason` is stamped on EVERY control activation, including the default
		-- one, because a subscriber otherwise cannot tell "a player pressed a
		-- control" from "the game emitted `commit` for its own reason" — and the
		-- client haptics adapter has to: on a platform where the engine itself
		-- plays a button's press through the button's own press-effect property,
		-- a second play from the bus would be two pulses for one press. (The
		-- engine symbol is deliberately not named here — the boundary rule in
		-- tests/haptics.spec.luau keeps every haptics name out of src/present.)
		local verb = if node ~= nil then node.activationFeedback else nil
		if verb ~= feedbackLib.ACTIVATION_SILENT then
			handle.emitFeedback({
				type = verb or "activate",
				path = path,
				surface = handle,
				reason = "activation",
				context = meta,
			})
		end
	end
	return nil
end

activate_dispatch.ACTIVATE_ECHO_WINDOW = ACTIVATE_ECHO_WINDOW
activate_dispatch.activateEffect = activateEffect
activate_dispatch.closedGateOn = closedGateOn
activate_dispatch.dispatch = dispatchActivate

return activate_dispatch
