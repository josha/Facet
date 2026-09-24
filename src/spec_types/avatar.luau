--!strict
local bp = require("../blueprint")
export type Presence = "online" | "away" | "busy" | "offline"
export type Spec = {
	ref: ((record: { api: any, dump: () -> any }) -> ())?,
	id: string?,
	name: string,
	image: bp.Bound<string>?,
	userId: number?,
	key: string?,
	provider: any?,
	controlSize: bp.Bound<"xsmall" | "compact" | "regular" | "large" | nil>?,
	diameter: (number | string)?,
	presence: bp.Bound<Presence | nil>?,
	presenceLabel: bp.Bound<string | nil>?,
	presenceMark: boolean?,
	frame: bp.Blueprint?, -- caller-owned content; activated frames obey Button content restrictions
	backplate: boolean?,
	form: ("standard" | "icon")?,
	over: "media"?,
	onActivate: (() -> ())?,
}
return nil
