--!strict
-- The `page_view` control's types, apart from its implementation: reading a type must
-- not load the control.
local publicCore = require("../core/contract")
local publicBlueprint = require("../blueprint")
export type Page = { id: string, title: string, content: publicBlueprint.Blueprint }
export type StringCell = publicCore.Cell<string>
export type Spec<V = StringCell> = {
	id: string?,
	pages: { Page },
	selection: V,
	height: publicBlueprint.Bound<publicBlueprint.Dim>?,
	indicators: boolean?,
	-- The "Page 2 of 3" line and the Previous/Next buttons. Both default to shown.
	summary: boolean?,
	controls: boolean?,
}
return nil
