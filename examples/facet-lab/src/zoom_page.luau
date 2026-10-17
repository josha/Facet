--!strict
local CatalogTypes = require("./catalog_types")
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Context = {
	Host: typeof(require("@repo/tools/typecheck/aliases").RobloxHost),
	Compose: typeof(require("@repo/tools/typecheck/aliases").ComposeModule),
}
type Properties = { maxZoom: number?, enabled: boolean?, captureCamera: boolean?, collectionCapture: boolean? }

local page: CatalogTypes.PageDefinition = {
	family = "layout",
	purpose = "Inspect a large board and keep the pointed cell fixed while zooming.",
	alternatives = "Use ScrollView for content that only scrolls.",
	snippet = "UI.ZoomView { contentSize = Vector2.new(780, 780), zoom = zoom, content = Board }",
	base = function()
		return { maxZoom = 4, enabled = true, captureCamera = false, collectionCapture = false }
	end,
	axes = {
		{ key = "captureCamera", values = { false, true } },
		{ key = "collectionCapture", values = { false, true } },
		{ key = "maxZoom", values = { 1, 2, 4 } },
		{ key = "enabled", values = { true, false } },
	},
	states = {
		{ name = "zoom at capture", props = { captureCamera = true } },
		{ name = "collection pickup camera", props = { collectionCapture = true } },
		{ name = "disabled", props = { enabled = false } },
		{ name = "fit limit", props = { maxZoom = 1 } },
	},
	make = function(UI: FacetControls, p: Properties, c: Context): Instance
		if p.collectionCapture then
			return require("./zoom_collection_demo")(UI, c.Host, c.Compose)
		end
		return require("./zoom_travel_demo").zoom(
			UI,
			c.Host,
			c.Compose,
			p.maxZoom or 4,
			p.enabled ~= false,
			p.captureCamera == true
		)
	end,
}
return page
