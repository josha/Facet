--!strict
local ComposeTypes = require("../vendor/compose/core")

return setmetatable({} :: { [Instance]: ComposeTypes.Readable<boolean> }, { __mode = "k" })
