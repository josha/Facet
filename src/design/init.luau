--!strict

local Library = require("@self/library")
local Motion = require("@self/motion")
local Types = require("@self/types")

export type ControlSpec = Types.ControlSpec
export type FieldSpec = Types.FieldSpec
export type Seed = Types.Seed
export type Context = Library.Context
export type Motion = Types.Motion

return {
	library = Library.create,
	controls = Library.controls,
	seeds = Library.seeds,
	motion = Motion.motion,
}
