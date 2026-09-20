--!strict
--[[ THE LIST WORLD — a `ForEach` of rows inside a stack, which is the population
	Plan D's D6a makes coordinate-space hosts (a row is one rect write on a list
	shift instead of one per box).

	IT EXISTS FOR ONE ORACLE. `nameplates_scene` is the C1 world: plates whose
	PLACEMENT is reactive, under an `Anchor`, hosted by the first trigger. Nothing in
	it is a list row, so `host_space_oracle`'s five arms had no way to see the fifth
	trigger at all — the blind spot D6a's fix round found the hard way, through six
	incremental-vs-full oracles going red on a `When`-branch drop. This scene is that
	shape at oracle size, with the same `snapshot`/`publicSnapshot` columns so the
	same five arms can drive it unchanged.

	`hosts` IS A THREAD, NOT A SECOND WORLD, exactly as it is there: it goes straight
	to `renderer.attach`'s `translateHosts`, so arm `e` is the SAME tree with no
	coordinate spaces in it, driven through the IDENTICAL step list.

	THE ROW HAS FOUR CHILDREN because the fifth trigger is about a container the
	engine can carry a subtree for, and a one-child row would be one write hosted or
	not. The `Button` is there so the surface declares an input sink (the hit-rect
	walk runs, and its rects compose through the host chain); the `Box` is a plain
	painted leaf; the two `Text`s are what a row write moves. ]]
local Compose = require("../../src/vendor/compose/core")
local scene_root = require("./scene_root")
local environment = require("../../src/env/environment")
local renderer = require("../../src/render/renderer")
local fake_target = require("./fake_target")

local row_host_scene = {}

row_host_scene.ROWS = 12

export type Opts = {
	viewport: { x: number, y: number, w: number, h: number }?,
	rows: number?,
	incremental: boolean?,
	measureReuse: boolean?,
	commitScope: boolean?,
	hosts: boolean?,
}

local function px(n: number): any
	return { type = "fixed", px = n }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

local function fmtRect(r: any): string
	return if r == nil then "-" else `{r.x},{r.y},{r.w},{r.h}`
end

local function ser(v: any): string
	if type(v) ~= "table" then
		return tostring(v)
	end
	local parts: { string } = {}
	for k, inner in v :: any do
		table.insert(parts, `{tostring(k)}={tostring(inner)}`)
	end
	table.sort(parts)
	return `\{{table.concat(parts, ",")}\}`
end

function row_host_scene.new(opts: Opts?)
	local o: Opts = opts or {}
	local n = o.rows or row_host_scene.ROWS
	local items: { any } = {}
	local byKey: { [string]: any } = {}
	for i = 1, n do
		local item = { key = `r{i}`, label = Compose.cell(`Row {i}`), n = Compose.cell(i) }
		items[i] = item
		byKey[item.key] = item
	end
	local rows = Compose.cell(items)
	local branchOn = Compose.cell(true)
	local nextKey = n + 1

	-- The banner is a sibling of the list, not a row in it: dropping it leaves the
	-- list clean and only moved, so the list is the translate root and every row a
	-- coordinate-space descendant of one. Both containers are fixed-height so a
	-- content-height canvas never enters the comparison.
	local mounted = scene_root.mount(function(UI)
		return UI.Screen("S")({
			UI.VStack("Body")({
				padding = 4,
				gap = 2,
				width = fill(),
				height = px(2000),
				UI.When("Head")({
					Compose.show(branchOn, function()
						return UI.Box("Banner")({ width = fill(), height = px(60) })
					end),
				}),
				UI.VStack("List")({
					padding = 0,
					gap = 2,
					width = fill(),
					height = px(1200),
					scene_root.keyed(UI, "Rows", {
						items = rows,
						key = function(item: any): string
							return item.key
						end,
						row = function(entry: any): any
							local item = entry:peek()
							return UI.HStack("Row")({
								padding = 0,
								gap = 4,
								width = fill(),
								height = px(28),
								UI.Text("V")({
									textSize = 14,
									text = function(use: any): string
										return tostring(use(item.n))
									end,
								}),
								UI.Text("L")({ textSize = 12, text = item.label }),
								UI.Button("B")({
									label = "go",
									width = px(64),
									height = px(44),
									onActivate = function() end,
								}),
								UI.Box("P")({ width = px(30), height = px(10) }),
							})
						end,
					}),
				}),
			}),
		})
	end)
	local core, root = mounted.core, mounted.root
	local env = environment.new(core)
	env:set("viewportRect", o.viewport or { x = 0, y = 0, w = 400, h = 600 })

	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = o.incremental ~= false,
		measureReuse = o.measureReuse ~= false,
		layoutNodeReuse = true,
		commitScope = o.commitScope ~= false,
		translateHosts = o.hosts ~= false,
	})
	controller.initialRender()

	local scene: any = { core = core, env = env, adapter = adapter, controller = controller, items = items }

	local function publish()
		local out: { any } = {}
		for _, item in items do
			table.insert(out, item)
		end
		rows:set(out)
		controller.refresh()
	end

	function scene.reorder(i: number, j: number)
		if items[i] ~= nil and items[j] ~= nil then
			items[i], items[j] = items[j], items[i]
		end
		publish()
	end

	function scene.insert(at: number)
		local key = `r{nextKey}`
		nextKey += 1
		local item = { key = key, label = Compose.cell(`Row {key}`), n = Compose.cell(nextKey) }
		byKey[key] = item
		table.insert(items, math.clamp(at, 1, #items + 1), item)
		publish()
	end

	function scene.remove(at: number)
		if items[at] ~= nil then
			byKey[items[at].key] = nil
			table.remove(items, at)
		end
		publish()
	end

	function scene.write(at: number, text: string)
		if items[at] ~= nil then
			items[at].label:set(text)
		end
		controller.refresh()
	end

	function scene.bump(at: number, v: number)
		if items[at] ~= nil then
			items[at].n:set(v)
		end
		controller.refresh()
	end

	function scene.branch(on: boolean)
		branchOn:set(on)
		controller.refresh()
	end

	function scene.viewport(w: number, h: number)
		env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
		controller.refresh()
	end

	function scene.stats(): any
		return controller.stats()
	end

	-- the same columns `nameplates_scene.snapshot` publishes, for the same reason:
	-- an adapter-only comparison is blind to most of what a solve publishes
	function scene.snapshot(): string
		local out: { string } = {}
		local diagKeys: { string } = {}
		for _, finding in controller.diagnostics() do
			table.insert(diagKeys, `{tostring(finding.node)}:{tostring(finding.issue)}`)
		end
		table.sort(diagKeys)
		for path, node in adapter.liveNodes() do
			local props: { string } = {}
			for k, v in node.props or {} do
				table.insert(props, `{k}={ser(v)}`)
			end
			table.sort(props)
			local pp, ps = node.presentedPosition, node.presentedSize
			local sro = controller.screenRectOf(path)
			local posOk = pp == nil or sro == nil or (pp.x == sro.x and pp.y == sro.y)
			table.insert(
				out,
				`{path}|{fmtRect(node.storedRect)}|{table.concat(props, ",")}`
					.. `|vis={tostring(node.visible)}`
					.. `|hit={fmtRect(node.hitRect)}`
					.. `|canvas={if node.scrollRegion
						then `{node.scrollRegion.contentW},{node.scrollRegion.contentH}`
						else "-"}`
					.. `|pos={if pp then `{pp.x},{pp.y}` else "-"}`
					.. `|psize={if ps then `{ps.w},{ps.h}` else "-"}`
					.. `|focus={tostring(node.focused)},{tostring(node.focusProfile)},{tostring(node.focusLift)}`
					.. `|ro={fmtRect(controller.rectOf(path))}`
					.. `|sro={fmtRect(sro)}`
					.. (if posOk then "" else "|POSMISMATCH")
			)
		end
		table.sort(out)
		table.insert(out, `diagKey={table.concat(diagKeys, ";")}`)
		return table.concat(out, "\n")
	end

	-- ...minus the STORED rect column, which arm `e` is EXPECTED to differ on
	function scene.publicSnapshot(): string
		local out: { string } = {}
		for _, line in string.split(scene.snapshot(), "\n") do
			local head, tail = string.match(line, "^([^|]*)|[^|]*|(.*)$")
			table.insert(out, if head == nil then line else `{head}|{tail}`)
		end
		return table.concat(out, "\n")
	end

	function scene.dispose()
		controller.dispose()
		root.dispose()
	end

	return scene
end

return row_host_scene
