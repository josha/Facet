--!strict
local Facet = require("../src")
export type Context = {
	Compose: Facet.ComposeModule,
	UI: Facet.Controls,
	Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host),
	runtime: Facet.Runtime,
	types: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).types),
	[string]: any,
}
return function(ctx: Context): Context
	return ctx
end
