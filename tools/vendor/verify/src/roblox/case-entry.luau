--!strict

local Core = require "../core"

export type Host = "simulator" | "studio" | "player" | "open-cloud"
export type Entry = {
	cases: { Core.NamedCase },
	options: Core.RunOptions,
	now: () -> number,
}
export type Factory = (Host) -> Entry

local function run(factory: Factory, host: Host, ids: { string }?): Core.Report
	local entry = factory(host)
	return Core.runCases(entry.cases, entry.options, entry.now, ids)
end

return { run = run }
