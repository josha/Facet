--!strict
local ComposeTypes = require("../vendor/compose/core")

local presence: { [Instance]: ComposeTypes.ReadOnlyValue<boolean> } = setmetatable({}, { __mode = "k" })
return presence
