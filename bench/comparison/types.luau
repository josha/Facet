--!strict

local NativeApp = require("../native_app")

export type World = NativeApp.State
export type Lane = "plain" | "facet"
export type Scene = {
	step: (number) -> (),
	snapshot: () -> string,
	stop: () -> (),
}
export type Workload = {
	id: string,
	iterations: number,
	what: string,
	prepare: (World, Lane) -> Scene,
}

return {}
