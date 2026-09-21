--!strict
local bp = require("../blueprint")
local avatar = require("./avatar")
export type Member = {
	id: string,
	name: string,
	image: bp.Bound<string>?,
	userId: number?,
	key: string?,
	presence: bp.Bound<avatar.Presence | nil>?,
	presenceLabel: bp.Bound<string | nil>?,
}
export type Spec = {
	ref: ((record: { api: any, dump: () -> any }) -> ())?,
	id: string?,
	items: bp.Bound<{ Member }>,
	layout: ("stacked" | "spread")?,
	max: number?,
	overflow: ("count" | "ellipsis")?,
	form: ("standard" | "icon")?,
	controlSize: bp.Bound<"compact" | "regular" | "large" | nil>?,
	over: "media"?,
	onOverflow: (() -> ())?,
	overflowLabel: bp.Bound<string | nil>?,
	provider: any?,
}
return nil
