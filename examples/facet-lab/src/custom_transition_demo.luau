--!strict
local Catalog = require("./catalog_types")
local journal = require("./journal_demo")
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)

return {
	family = "navigation",
	recipe = true,
	cellWidth = 360,
	matrix = false,
	base = function()
		return {}
	end,
	alias = "Custom transitions",
	purpose = "Turn a journal page by dragging, or use Previous and Next.",
	alternatives = "Use default transitions unless the motion explains the screen.",
	snippet = 'transition = { motion = "pageTurn", fade = false, progress = dragProgress, apply = turnPage }',
	demonstrates = { "transition" },
	axes = {},
	states = {},
	make = function(UI: Controls, _: never, c: Catalog.Context): Instance
		return journal(UI, c.app.runtime, c.Compose, c.types, c.cell("journalSpread", "crossing"))
	end,
} :: Catalog.PageDefinition
