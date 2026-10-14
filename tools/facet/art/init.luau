--!strict

local Common = require("@self/common")

export type Output = Common.Output
export type Target = Common.Target

local targets: { Target } = {
	require("@self/icons"),
	require("@self/compact_pointer"),
	require("@self/fantasy_ornate"),
	require("@self/glossy_touch"),
	require("@self/fantasy_parchment"),
	require("@self/ornate_gauge"),
	require("@self/pixel_quest"),
}

return table.freeze(targets)
