--!strict
local harness = require("./harness")
-- A mounted Compose scene root for renderer-level fixtures that attach a
-- renderer by hand: `renderer.attach(core, root, env, adapter, opts)`.
-- Presenter-level specs use `tests/lib/world.luau` instead.
local Compose = require("../../src/vendor/compose/core")
local composeCore = harness.coreFactory
local composeScene = require("../../src/render/compose_scene")
local composeControls = require("../../src/render/compose_controls")

local scene_root = {}

export type Mounted = {
	core: any,
	UI: any,
	runtime: any,
	-- the renderer's root: `root.node`, `root.dispose()`, `root.takeDirty()`
	root: any,
}

-- `component(UI)` returns the screen node. `core` defaults to a fresh one.
function scene_root.mount(component: (UI: any) -> any, core: any?): Mounted
	local ownCore = core or composeCore.new()
	local scene = composeScene.new()
	local UI = composeControls.new(scene.runtime, ownCore, nil)
	local target = scene.target()
	local stop = scene.runtime.mount(function()
		return component(UI)
	end, target)
	local root = scene.root(target, function()
		stop()
		scene.runtime:dispose()
	end)
	return { core = ownCore, UI = UI, runtime = scene.runtime, root = root }
end

-- A keyed region whose rows may share one name: each row's path carries its key,
-- `/<id>/[<key>]/<row>`. `spec` is `{ items = cell, key = fn, row = fn(item) }`,
-- where `item` is the readable of the current record.
function scene_root.keyed(UI: any, id: string, spec: any): any
	return UI.ForEach(id)({
		Compose.keyed({
			from = spec.items,
			key = spec.key,
			render = function(item: any, _: any, key: any)
				local node = spec.row(item)
				node.collectionKey = `[{key}]`
				return node
			end,
		}),
	})
end

return scene_root
