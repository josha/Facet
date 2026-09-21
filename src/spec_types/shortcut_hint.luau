--!strict
local blueprint = require("../blueprint")
local environment = require("../env/environment")
export type Spec = {
	id: string?,
	action: string?,
	keys: { { string } }?,
	separator: blueprint.Bound<string>?,
	controlSize: blueprint.Bound<"compact" | "regular" | "large">?,
	over: "media"?,
	env: environment.Env?,
}
return nil
