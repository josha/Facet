--!strict

local Facet = require("../src")
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
export type Context = {
	Compose: Facet.ComposeModule,
	UI: Facet.Controls,
	Host: RobloxHost,
	runtime: Facet.Runtime,
	types: RobloxTypes,
	[string]: any,
}
return (nil :: unknown) :: { Context: Context }
