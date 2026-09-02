--!strict
--[[ THE DRAG BRIDGE'S REGISTRY HALF — how a surface acquires a drag session.

	`src/input/drag_registry.luau` is the pure model: sources, targets, promotion,
	the arm->navigate->commit verbs. This module is the RENDERER's half of the
	bridge to it — the lazy construction that wires the model to a live surface's
	geometry, and the native `UIDragDetector` acquisition that runs beside it. Two
	functions, one lazily-built instance, and the instance's lifetime.

	WHY IT IS A MODULE, and it is the second half of a split the ledger named. Roblox
	refuses a `Script.Source` assignment at 200,000 characters and every LIVE path is
	a write, so a module over the cap silently stops syncing into an open Studio
	session and a live check then tests the code baked into the place rather than the
	edits on disk. `tools/lune/verify/data/source-cap-ledger.md` has named "the drag
	bridge" as `renderer.luau`'s next extraction since 2026-08-18. Its AUTOSCROLL half
	left on 2026-09-01 as `render/autoscroll_bridge.luau`, and the row's own words
	about this half were: "the REGISTRY half (`dragRegistry`/`attachDetector`, ~5 KB)
	is NOT taken and is the next named seam: `dragRegistryInstance` is read from eleven
	places in this file — the tap-echo guard, the structural refresh, three public
	controller methods and `dispose` — so it needs the shared-record move
	`controls/table.luau` proved, which is a different commit from a verbatim move."

	THE SHARED RECORD IS THIS MODULE, and that is the whole difference from the
	autoscroll half. `dragRegistryInstance` is a REASSIGNED scalar — nil until a
	source is registered, an object afterwards, nil again at dispose — so it fails the
	ledger's one-way test by construction: a callee handed the value keeps the OLD
	one and the two halves silently disagree. The move `controls/table.luau` proved is
	to give the scalar an OWNER and hand out accessors instead, which is what
	`registry()`/`peek()`/`dispose()` are. The renderer keeps no copy of it, so there
	is exactly one writer and eleven readers rather than two writers of the same name.

	`registry()` BUILDS ON FIRST ASK and `peek()` NEVER DOES, and the difference is
	load-bearing at four of those eleven sites: "is a drag session live" and "does
	this tap arm instead of activating" must not CREATE a registry as a side effect of
	being asked, because the registry existing is itself the signal that a declaring
	source is mounted. `registry()` is the wiring path (a source or a target
	registering, the public `controller.dragRegistry`); `peek()` is every read.

	EVERYTHING IT TAKES is read-only to it or a by-reference table the renderer
	declares once and never rebinds, which is the same seam test
	`render/rect_pass.luau`, `render/commit_walks.luau` and
	`render/autoscroll_bridge.luau` each passed, and
	`tests/drag_bridge_seam.spec.luau` runs it over the live sources rather than
	asserting it here.
]]

local authority = require("./authority")
local dragRegistryLib = require("../input/drag_registry")

local drag_bridge = {}

--[[ THE CONTRACT, AS A TYPE RATHER THAN A PARAGRAPH. Every field is read-only to
	this module or a by-reference table the renderer declares ONCE and never
	rebinds — which is the whole seam test, because a reassigned local cannot be
	shared by reference at all. ]]
export type DragBridgeCtx = {
	core: any, -- the reactive core, for the held-source observer
	adapter: any, -- the render target
	attachScope: any, -- the surface's scope; the observer dies with it
	handles: any, -- path -> adapter handle, by reference
	findNode: any, -- path -> the mounted node, for the write's authority class
	screenRectOf: any, -- the live painted rect of a path, in window space
	isPathLive: any, -- is this path outside every retiring subtree
	lastZ: any, -- path -> the z the sync walk last assigned, by reference
	dragSourceEnabled: any, -- path -> the source's live `enabled` read, by reference
	dragCollaborators: any, -- the injectable clock/feedback/proxy set, by reference
}

function drag_bridge.new(ctx: DragBridgeCtx)
	local core = ctx.core
	local adapter = ctx.adapter
	local attachScope = ctx.attachScope
	local handles = ctx.handles
	local findNode = ctx.findNode
	local screenRectOf = ctx.screenRectOf
	local isPathLive = ctx.isPathLive
	local lastZ = ctx.lastZ
	local dragSourceEnabled = ctx.dragSourceEnabled
	local dragCollaborators = ctx.dragCollaborators

	-- THE ONE REASSIGNED SCALAR, and it lives here so that it has exactly one
	-- writer. Nil until a source or a target registers; nil again after `dispose`.
	local instance: any = nil

	local function registry(): any
		if instance == nil then
			instance = dragRegistryLib.new({
				core = core,
				rectOf = screenRectOf,
				zOf = function(path: string): number?
					return lastZ[path]
				end,
				-- A RETIRING SUBTREE IS NOT A DRAG SURFACE — resolution-time
				-- exclusion, reversal-safe by construction
				isPathLive = isPathLive,
				-- P2-3: disabled sources acquire nothing, read live per acquisition
				isSourceEnabled = function(path: string): boolean
					local read = dragSourceEnabled[path]
					return read == nil or read()
				end,
				now = dragCollaborators.now,
				feedback = dragCollaborators.feedback,
				proxy = dragCollaborators.proxy,
				motionClock = dragCollaborators.motionClock,
			})
			-- THE HELD SOURCE IS A NODE STATE (director round five): the registry
			-- publishes which path a live session is carrying; the adapter's
			-- `dragHeld` state empties that node's label through the same tag+rule
			-- channel `selected` paints by. Framework guarantee — no consumer code.
			--[[ THROUGH THE MANIFEST, LIKE EVERY OTHER RENDERER WRITE — the architecture
				review's channel rule.
				These two were the only `adapter.setProp` calls in the renderer that
				skipped `authority.assertWrite`, which is the single sentence
				constitution §11 makes about it ("asserts every write").
				`dragHeld` has always been declared (`common`, presentation
				authority) — the assert was simply never made, so the one property
				whose whole point is that a consumer cannot author it was the one
				property nothing checked. `findNode` is an O(N) walk and this
				observer fires only when a drag session picks a source up or puts
				it down, which is a gesture boundary, not a frame. ]]
			local function setDragHeld(dragPath: string, held: boolean)
				local handle = handles[dragPath]
				if handle == nil then
					return
				end
				local node = findNode(dragPath)
				authority.assertWrite(if node ~= nil then node.class else "common", "dragHeld", "presentation")
				adapter.setProp(handle, "dragHeld", held, "presentation")
			end
			local heldPath: string? = nil
			attachScope:own(core:observe(instance.heldSource, function(path: string?)
				if heldPath ~= nil and heldPath ~= path then
					setDragHeld(heldPath, false)
				end
				heldPath = path
				if path ~= nil then
					setDragHeld(path, true)
				end
			end))
		end
		return instance
	end

	-- THE READ that must never build (see the header): the registry existing is
	-- itself the signal that a declaring source is mounted, so asking "is a session
	-- live" may not manufacture one.
	local function peek(): any
		return instance
	end

	-- native drag acquisition, shared by the renderer's mount-time wiring and the
	-- public `controller.attachDragDetector`. Nilable by contract: an adapter or
	-- an engine without `UIDragDetector` answers nil and the caller falls back
	-- to the framework's own pointer capture — the ONE thing that must never differ
	-- between the two paths is the promotion rule, which lives in the registry.
	local function attachDetector(path: string, handlers: any): (() -> ())?
		if adapter.setDragDetector == nil then
			return nil
		end
		local handle = handles[path]
		if handle == nil then
			return nil
		end
		return adapter.setDragDetector(handle, handlers)
	end

	-- the surface is going away, so the model goes with it. Clearing the scalar is
	-- the half a caller could not do for itself once the name lives here.
	local function dispose()
		if instance ~= nil then
			instance.dispose()
			instance = nil
		end
	end

	return { registry = registry, peek = peek, attachDetector = attachDetector, dispose = dispose }
end

return drag_bridge
