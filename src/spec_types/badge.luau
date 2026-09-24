--!strict
local bp = require("../blueprint")
local status = require("./status_indicator")
export type Spec = {
	ref: ((record: { api: any, dump: () -> any }) -> ())?,
	id: string?,
	label: bp.Bound<string | nil>?,
	icon: string?,
	iconPosition: ("leading" | "trailing")?,
	status: bp.Bound<status.Status | nil>?,
	appearance: ("standard" | "status" | "utility")?,
	corners: ("pill" | "square")?,
	controlSize: bp.Bound<"xsmall" | "compact" | "regular" | "large" | nil>?,
	over: "media"?,
	name: string?,
}
return nil
