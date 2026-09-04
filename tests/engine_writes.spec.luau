--!strict
--[[ ENGINE WRITES ARE COUNTED AT THE WRITE, ON BOTH ADAPTERS (Plan C, T0).
	`stats.rectWrites` counts `adapter.setRect` CALLS; the engine's own bill is two
	levels down — the `Position`/`Size` assignment `applyRect` makes after its
	write-skip compare. Under a real instance parent the two diverge by design
	(a host move: N setRect calls, 1 Position write), so a counter that can only
	see the call proves nothing about the collapse this campaign is for. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")

describe("engineWrites: the adapter counts what the engine was told", function()
	it("the fake target counts one Position/Size write per changed rect, none for an equal one", function()
		local s = scene.new()
		s.tick(3, 2) -- warm: the first refresh is the cold solve
		local before = s.adapter.engineWrites()
		s.tick(3, 2)
		local st = s.stats()
		-- READ OFF THE RUN at HEAD before T3: every one of the 1,500 rect writes is a
		-- real engine write today, because the plate tree is FLAT.
		expect(`engineWrites delta={s.adapter.engineWrites() - before} solves={st.solves}`).toBe(
			`engineWrites delta={scene.PLATES * scene.NODES_PER_PLATE} solves={st.solves}`
		)
		expect(`stats.engineWrites={st.engineWrites}`).toBe(`stats.engineWrites={s.adapter.engineWrites()}`)
		-- an A/A re-apply costs nothing: the mirror compares before it writes
		local again = s.adapter.engineWrites()
		s.controller.refresh()
		expect(`A/A delta={s.adapter.engineWrites() - again}`).toBe("A/A delta=0")
		s.dispose()
	end)
end)
