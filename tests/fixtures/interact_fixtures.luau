--!strict
-- Interaction fixture registry (design §16.1 "interact", §9.2): headless
-- action/focus trace fixtures driving the same action pipeline as real input.
-- Engine-side scriptable-binding traces live in the Studio spike, not here.
-- Filled by the input adapter work; the interact command fails while empty.

local runner = require("../../tools/lune/registry_runner")

local fixtures: { runner.Fixture } = {}

return fixtures
