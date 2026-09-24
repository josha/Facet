--!strict
local bp = require("../blueprint")
export type Spec = {
	ref: ((record: { api: any, dump: () -> any }) -> ())?,
	id: string?,
	form: "box" | "line" | "circle",
	width: bp.Bound<bp.Dim>?,
	height: bp.Bound<bp.Dim>?,
	lines: number?,
	corners: ("pill" | "square")?,
	controlSize: bp.Bound<"xsmall" | "compact" | "regular" | "large" | nil>?,
}
return nil
