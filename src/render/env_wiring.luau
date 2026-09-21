--!strict
--[[ THE ENVIRONMENT-FACT WIRING, lifted out of `render/renderer.luau` on
	2026-09-20 to give that module headroom under Roblox's 200,000-character
	Source cap (it stood 1,541 characters short of the cap, above which a script
	SILENTLY fails to load).

	FOUR LIVE FACTS REACH THE TARGET FROM HERE, and they are one seam because
	they share one shape: the fact is published by the environment, the adapter
	takes it through a feature-detected verb, and it must land BOTH at attach and
	on every later change — a mid-session dock, a player flipping a setting — with
	no remount. Two of them (hover, disclosure engagement) additionally CARRY:
	an interaction class arriving mid-session retrofits already-mounted nodes,
	not only nodes created after the flip.

	ONE-WAY OVER ITS ARGUMENTS. This module reads no mutable state of the
	renderer. `handles` and `root` travel by reference and are only read; the
	three scalars the carries keep (`hoverLive`, `lastPointer`, `lastTouch`) are
	declared here and read nowhere else. Nothing in the renderer calls back into
	this module: `install` runs once, at attach, and everything after that is an
	observation the attach scope owns.
]]
local observeChange = require("../core/on_change")

local env_wiring = {}

-- The classes that take a hover state. Read here to enable hover on a pointer
-- arriving mid-session, and by the renderer when it creates a node.
env_wiring.HOVERABLE = { Button = true, Toggle = true } :: { [string]: boolean }

local HOVERABLE = env_wiring.HOVERABLE

export type Deps = {
	env: any,
	adapter: any,
	attachScope: any,
	handles: any,
	root: any,
	opts: any,
}

--[[ Wire every environment fact this seam owns onto the adapter. Called once,
	at attach, after the handle map exists. ]]
function env_wiring.install(deps: Deps)
	local env, adapter, attachScope = deps.env, deps.adapter, deps.attachScope
	local handles, root, opts = deps.handles, deps.root, deps.opts

	-- verifier F3: hover is a hot-switch CARRY idiom — a pointer ARRIVING
	-- mid-session (dock adds a mouse) enables hover on nodes that already
	-- exist, not only on nodes created after the flip. enableHover is
	-- idempotent; there is no disable path (without a mouse the events
	-- simply never fire).
	do
		local hoverLive = env:get("interactionClasses"):peek().pointer == true
		observeChange(attachScope, env:get("interactionClasses"), function(classes)
			local live = classes.pointer == true
			if live and not hoverLive and adapter.enableHover ~= nil then
				local function enableWalk(node: any)
					if HOVERABLE[node.class] and handles[node.path] ~= nil then
						adapter.enableHover(handles[node.path])
					end
					for _, child in node.children do
						enableWalk(child)
					end
				end
				enableWalk(root.node)
			end
			hoverLive = live
		end)
	end

	-- ...and the SAME carry idiom for disclosure engagement zones (architecture
	-- review F-5): long-press is the ONLY full-value path on touch, so a touch
	-- class arriving mid-session (hybrid handheld docking, first tap on a
	-- touchscreen laptop) must retrofit zones onto already-mounted disclosed
	-- labels exactly as hover does. `enableDisclosure` merges per half, so a
	-- label wired for hover at mount gains the touch half here without
	-- disturbing the first.
	do
		local discloseHoverCb = opts and (opts :: any).onDiscloseHover
		local disclosePressCb = opts and (opts :: any).onDiscloseLongPress
		if (discloseHoverCb ~= nil or disclosePressCb ~= nil) and adapter.enableDisclosure ~= nil then
			local last = env:get("interactionClasses"):peek()
			local lastPointer, lastTouch = last.pointer == true, last.touch == true
			observeChange(attachScope, env:get("interactionClasses"), function(classes)
				local pointer, touch = classes.pointer == true, classes.touch == true
				if (pointer and not lastPointer) or (touch and not lastTouch) then
					local function wireWalk(node: any)
						local discloses = (node.props or {}).disclose == true or (node.props or {}).reveal ~= nil
						if (discloses or (node.props or {}).help ~= nil) and handles[node.path] ~= nil then
							local path = node.path
							adapter.enableDisclosure(handles[path], {
								hover = if discloseHoverCb ~= nil and pointer
									then function(over: boolean)
										discloseHoverCb(if over then path else nil)
									end
									else nil,
								-- the press half is the PLATE's, never help's (D3a)
								longPress = if disclosePressCb ~= nil
										and discloses
										and touch
									then function(held: boolean)
										disclosePressCb(if held then path else nil)
									end
									else nil,
							})
						end
						for _, child in node.children do
							wireWalk(child)
						end
					end
					wireWalk(root.node)
				end
				lastPointer, lastTouch = pointer, touch
			end)
		end
	end

	--[[ REDUCED MOTION IS A LIVE FACT, AND IT REACHES THE TARGET FROM HERE — both
		halves of a target's motion, through one observation of one env key.

		`setNativeTransitionsEnabled` is the SHEET half, from the native-stylesheet round:
		when the target runs sheet-owned paint, the adapter strips/restores the
		sheet's declared transitions on the fly (SetPropertyTransitions({}) — the
		proven instant path, spike m9).

		`setReducedMotion` is the BESPOKE half (C1, 2026-08-12), and it exists
		because the comment that used to stand here was false. It said bespoke
		targets "consult the reducedMotion policy per-play already" — they consult
		a `screen_target.new({ isReducedMotion = ... })` CLOSURE, and no production
		caller anywhere ever passed one (not the showcase, not RascalRally's four
		GUIs), so every bespoke tween ran at full motion for a player who had asked
		for less. A construction-time opt four call sites forgot is the defect; the
		repair is that the framework pushes the fact instead of hoping a consumer
		wires it. Both calls are feature-detected, so a target with neither degrades
		by name (target_contract) rather than crashing.

		Pushed once at attach and again on every change, so a mid-session flip of
		the player's setting lands without a remount. ]]
	if adapter.setNativeTransitionsEnabled ~= nil or adapter.setReducedMotion ~= nil then
		local function pushReducedMotion(reduced: boolean)
			if adapter.setNativeTransitionsEnabled ~= nil then
				adapter.setNativeTransitionsEnabled(reduced ~= true)
			end
			if adapter.setReducedMotion ~= nil then
				adapter.setReducedMotion(reduced == true)
			end
		end
		pushReducedMotion(env:get("reducedMotion"):peek() == true)
		observeChange(attachScope, env:get("reducedMotion"), function(reduced)
			pushReducedMotion(reduced == true)
		end)
	end

	--[[ THE PLAYER'S BACKGROUND TRANSPARENCY PREFERENCE (owed row O-26).

		The third accessibility fact to ride this seam, and it rides it for exactly
		the reason the second one had to: `setReducedMotion` above exists because the
		fact used to arrive only through a construction-time opt that all four
		production call sites forgot, so the preference silently did nothing. A
		preference the framework merely PUBLISHES is a preference no player feels;
		`effectiveTransparency` had been published and unread for four stages.

		The env memo is the clamp — a garbage or NaN platform reading becomes 1
		(paint what the theme said) before it ever reaches an adapter, so the seam
		carries a value already in its legal domain.

		UNLIKE `setReducedMotion`, THIS ONE REPAINTS. Reduced motion changes how the
		NEXT transition plays; a transparency preference changes what is on screen
		right now, so an adapter that takes it has to move the backdrop it has
		already painted, not merely remember the number. ]]
	if adapter.setPreferredTransparency ~= nil then
		local effective = env:get("effectiveTransparency")
		adapter.setPreferredTransparency(effective:peek())
		observeChange(attachScope, effective, function(value)
			adapter.setPreferredTransparency(value)
		end)
	end
end

return env_wiring
