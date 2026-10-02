--!strict

local Facet = require("../src")
local Shared = require("../src/ui/types")
export type Context = {
	Compose: Facet.ComposeModule,
	UI: Facet.Controls,
	Host: Shared.Host,
	runtime: Facet.Runtime,
	types: Shared.RobloxTypes,
	[string]: any,
}
return (nil :: unknown) :: { Context: Context }
