--!strict
local ComposeTypes = require("../vendor/compose/core")

return setmetatable({} :: { [Instance]: ComposeTypes.ReadOnlyValue<boolean> }, { __mode = "k" })
