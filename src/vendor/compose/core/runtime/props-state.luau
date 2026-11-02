--!strict

local Weak = require "../weak"
local Types = require "../reactive/types"
type Mapping = { source: Types.ReadOnlyValue<unknown>, transform: (unknown) -> unknown }
local mapped: { [unknown]: Mapping } = {}
Weak.keys(mapped)
local applying: { key: string? } = { key = nil }
return { mapped = mapped, applying = applying, unwritten = newproxy(false) }
