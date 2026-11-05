--!strict

local Compose = require "../core"
local Design = require "../design"

export type RenderPreview = (
	document: Design.Document,
	library: Design.Library,
	use: Compose.Use
) -> (Design.Document, { [string]: Design.Resolved })

return {}
