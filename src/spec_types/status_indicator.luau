--!strict
local bp = require("../blueprint")
export type Form = "dot" | "ring" | "square" | "dash"
export type Status = "neutral" | "info" | "success" | "warning" | "error" | "accent"
export type Spec = {
	ref: ((record: { api: any, dump: () -> any }) -> ())?,
	id: string?,
	form: bp.Bound<Form | nil>?,
	status: bp.Bound<Status | nil>?,
	count: bp.Bound<number>?,
	max: number?,
	cutout: boolean?,
	name: string?,
	controlSize: bp.Bound<"compact" | "regular" | "large" | nil>?,
	width: bp.Bound<bp.Dim>?,
	height: bp.Bound<bp.Dim>?,
}
return nil
