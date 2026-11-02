--!strict
local CatalogTypes = require("./catalog_types")
type Context = CatalogTypes.Context
type PageDefinition = CatalogTypes.PageDefinition
type Properties = CatalogTypes.Properties
type FacetControls = CatalogTypes.FacetControls
type Source = CatalogTypes.Source

return function(PAGE_DATA: { [string]: PageDefinition }, NONE: unknown, properties: (Properties) -> Source)
	local function hierarchyState(c: Context): Properties
		local rows = c.cell(
			"treeRows",
			{
				{
					id = "folder",
					name = "Championship",
					laps = 0,
					children = {
						{ id = "coast", name = "Coastal Circuit", laps = 3 },
						{
							id = "nested",
							name = "Time trials",
							laps = 0,
							children = {
								{ id = "harbour", name = "Harbour Sprint", laps = 6 },
							},
						},
					},
				},
				{ id = "empty", name = "Community races", laps = 0, children = {} },
				{ id = "readme", name = "Practice loop", laps = 1 },
			} :: { any }
		)
		local expanded = c.cell("expanded", {})
		return {
			from = rows,
			children = "children",
			expanded = expanded,
			indent = 24,
			onExpansionChange = function(value)
				expanded:set(value)
				c.log("onExpansionChange")(value)
			end,
			onActivate = NONE,
		}
	end

	local function outlineBase(c: Context): Properties
		local spec: Properties = assert(PAGE_DATA.VirtualList.base)(c)
		for key, value in hierarchyState(c) do
			spec[key] = if value == NONE then nil else value
		end
		spec.selection = c.cell("outlineSelection", {})
		return spec
	end
	local function expandedState(c: Context): Properties
		local expanded = c.cell("expandedExample", { folder = true, nested = true })
		return {
			expanded = expanded,
			onExpansionChange = function(value: { [string]: boolean })
				expanded:set(value)
				c.log("onExpansionChange")(value)
			end,
		}
	end
	local function folderDisabled(item: { id: string }): boolean
		return item.id == "folder"
	end

	local outline: PageDefinition = {
		demonstrates = { "slots", "slotControls" },
		family = "collections",
		alias = "Outline",
		cellWidth = 340,
		cellHeight = 280,
		purpose = "Expand nested groups, select rows, and edit items in one hierarchy.",
		note = "Expand a group with its arrow; Left/Right collapse or expand the focused row. Selection and expansion settings are below; events go to the log.",
		alternatives = "VirtualList for flat rows. Table with children for hierarchy with columns.",
		snippet = 'UI.Outline { from = roots, key = "id", children = "children", expanded = expanded, render = renderCell }',
		base = outlineBase,
		axes = { { key = "selectionMode", values = { "single", "multiple" }, matrix = false } },
		states = {
			{ name = "content clipped", props = properties { contentOverflow = "clip" } },
			{ name = "content visible", props = properties { contentOverflow = "visible" } },
			{ name = "expanded", props = expandedState },
			{ name = "large indentation", props = properties { indent = 48 } },
			{ name = "reduced motion", props = properties { reducedMotion = true } },
			{ name = "rebuilt rows", props = properties { recycle = false } },
			{ name = "disabled folder", props = properties { disabled = folderDisabled } },
		},
	}

	local rewardSequence: PageDefinition = {
		recipe = true,
		family = "media",
		purpose = "Order a reward with lock, sweep, flash, travel, count and refill.",
		alternatives = "Use Travel for one slot change.",
		snippet = "local reward = UI.sequence { steps = steps }; reward.play()",
		base = function(): Properties
			return { pulse = true }
		end,
		axes = { { key = "pulse", values = { true, false } } },
		states = {
			{ name = "reward sequence", props = properties {} },
			{ name = "sweep only", props = properties { pulse = false } },
		},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			return require("./reward_sequence_demo")(UI, c.Host, c.Compose, p.pulse ~= false)
		end,
	}

	for _, name in { "VirtualList", "Table" } do
		table.insert(
			assert(PAGE_DATA[name].states),
			{ name = "expandable hierarchy", props = hierarchyState, across = false }
		)
	end

	return { outline = outline, rewardSequence = rewardSequence }
end
