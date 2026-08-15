--!strict
-- THE FOREIGN-CONTENT SEAM'S RULINGS (UI.Foreign; ADR-0034).
--
-- PURE and engine-free, so BOTH adapters go through it: the live ScreenTarget
-- (which builds the description below from a real Instance and then makes the
-- ONE write it is allowed to make) and the headless recording twin the suite
-- drives. A refusal ladder each adapter wrote for itself would be two rulings on
-- one contract, which is how "headless green, device wrong" ships (the SF-M9
-- lesson; `stage_content.luau` exists for exactly the same reason and this
-- module is deliberately its shape).
--
-- WHAT IS PURE HERE AND WHAT IS NOT. The ADMISSION LADDER is pure: given a
-- description of a candidate — is there one at all, what class is it, is it a
-- GuiObject, is it a LayerCollector, is it still alive — the verdict and the
-- sentence are the same on every target. What is NOT pure is producing that
-- description, because only an engine can answer `IsA` and only an engine can
-- tell a live instance from a destroyed one. So the live adapter builds the
-- description and the fake target states one directly, and the ladder they run
-- is one function with one set of words.
--
-- THE REFUSALS NAME THE ALTERNATIVE (constitution §4; the ADR-0029 pattern). A
-- caller who reaches `UI.Foreign` with a `Part` has not made a typo — they have
-- the 3-D case, which is a different record's question (ADR-0024), and the
-- error says so rather than reporting a type mismatch.

local foreign_content = {}

-- What an adapter must be able to say about a candidate instance. Every field is
-- an ENGINE fact; nothing here computes them.
export type Candidate = {
	-- false when the caller passed nil (or a non-Instance) at all
	present: boolean,
	-- the engine ClassName, for the message; "" when unknown
	className: string,
	-- Instance:IsA("GuiObject")
	isGuiObject: boolean,
	-- Instance:IsA("LayerCollector") — a ScreenGui/BillboardGui cannot be a child
	-- of a GuiObject, so it is refused with its own sentence rather than through
	-- the generic "not a GuiObject" one (it IS one, in the loose sense a caller
	-- means, and the generic sentence would read as a lie)
	isLayerCollector: boolean,
	-- false when the engine has already destroyed it. The live adapter cannot ask
	-- this directly — there is no `IsDestroyed` — so it discovers it the only way
	-- the engine offers: a non-nil Parent write on a destroyed instance throws
	-- ("Parent property is locked"), which is the same detection `screen_target`'s
	-- recycling `adopt` already relies on (architecture review F9).
	alive: boolean,
}

-- the refusal a handle whose node has died answers, spelled once so both adapters
-- say the same thing (and a caller can match on it)
function foreign_content.disposedError(path: string): string
	return `LuauUI foreignHost: the Foreign node '{path}' has been disposed — its handle is dead. `
		.. "Ask controller.foreignHost(path) again after the node remounts."
end

--[[ assertAdmissible(path, candidate) — the whole ladder, in the order a caller
	hits it. Every rung errors; there is no "returns false" form, because a
	silently-ignored adoption is the accepted-and-ignored failure this framework
	keeps closing (a caller would see an empty box and have nothing to grep).

	It runs BEFORE any write, so a refusal leaves the container exactly as it was.
]]
function foreign_content.assertAdmissible(path: string, candidate: Candidate)
	if not candidate.present then
		error(
			`LuauUI foreignHost.adopt on '{path}': no instance was passed. `
				.. "Pass the GuiObject you created — LuauUI reserves the box and never creates the content.",
			0
		)
	end
	if candidate.isLayerCollector then
		error(
			`LuauUI foreignHost.adopt on '{path}': a {candidate.className} is a LayerCollector and cannot be a `
				.. "child of a GuiObject, so it can never render inside this box. Adopt the GuiObject from "
				.. "INSIDE it instead, or mount your own LuauUI surface for it.",
			0
		)
	end
	if not candidate.isGuiObject then
		error(
			`LuauUI foreignHost.adopt on '{path}': a {candidate.className} is not a GuiObject, so this box — `
				.. "which is 2-D layout — can never draw it. For a Part/Model/Beam (the 3-D case) use "
				.. "UI.Stage and controller.stageHost(path).contentRoot(); see ADR-0024.",
			0
		)
	end
	if not candidate.alive then
		error(
			`LuauUI foreignHost.adopt on '{path}': that {candidate.className} has already been destroyed. `
				.. "The content is yours to own and to keep alive; LuauUI never resurrects an instance.",
			0
		)
	end
end

--[[ THE ONE ENGINE PROPERTY LUAUUI EVER WRITES ON AN INSTANCE IT DOES NOT OWN.

	Named here rather than spelled at the write site so the authority manifest,
	the adapter and the tests all read the same constant — the same anti-drift
	rule `authority.INSTANCE_NAMES` follows one module up.
]]
foreign_content.CLAIMED_PROPERTY = "Parent"

return table.freeze(foreign_content)
