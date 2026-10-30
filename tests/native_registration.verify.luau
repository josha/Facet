--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	local requireDynamic = require :: (any) -> any

	local fs = require("@std/fs")
	local Lute = require("../tools/vendor/verify/src/lute")
	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local scaffold = require("../tools/facet/lib/scaffold")
	type ProofControls = { ProofControl: (string) -> ({ Size: UDim2 }) -> Instance }

	verifyHarness:suite("native registration and package contract", function()
		verifyHarness:case("scaffolds a typed native control with idempotent runtime and public type registration", {
			id = "native_registration::native registration and package contract::scaffolds a typed native control with idempotent runtime and public type registration",
			run = function()
				local plan = scaffold.plan("control", "proof_control")
				Verify.expect(#plan.files):toBe(1)
				Verify.expect(#plan.edits):toBe(3)
				Verify.expect(plan.files[1].path):toBe("src/ui/proof_control.luau")
				local edited = {}
				for _, edit in plan.edits do
					edited[edit.path] = scaffold.applyEdit(fs.readFileToString(edit.path), edit)
					Verify.expect((scaffold.applyEdit(edited[edit.path], edit))):toBe(edited[edit.path])
					assert(Lute.chunk.check(edited[edit.path], edit.path))
				end
				local typesEnvironment: { [string]: unknown } = {
					require = function(path: string): unknown
						Verify.expect(path):toBe("@self/types")
						return require("../src/ui/types")
					end,
				}
				local generated = Lute.chunk.load(
					plan.files[1].content,
					{ name = plan.files[1].path, environment = typesEnvironment }
				)()
				local controlsEnvironment: { [string]: unknown } = {
					require = function(path: string): unknown
						return if path == "@self/proof_control"
							then generated
							else requireDynamic("../src/ui/" .. string.sub(path, 7))
					end,
				}
				local createControls = Lute.chunk.load(
					edited["src/ui/init.luau"],
					{ name = "src/ui/init.luau", environment = controlsEnvironment }
				)() :: (unknown, unknown, unknown) -> ProofControls
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local UI = createControls(Facet.Compose, runtime, { types = engine.types })
				Verify.expect((table.isfrozen(UI))):toBe(true)
				local stop, node: any = runtime.mount(function()
					return UI.ProofControl "Proof" { Size = engine.types.UDim2.fromOffset(60, 40) }
				end, engine.new("Folder"))
				Verify.expect(node.ClassName):toBe("Frame")
				Verify.expect(node.Name):toBe("Proof")
				Verify.expect(node.Size.X.Offset):toBe(60)
				local stopNamed, named: any = runtime.mount(function()
					return UI.ProofControl("Named")({ Size = engine.types.UDim2.fromOffset(20, 30) })
				end, engine.new("Folder"))
				Verify.expect(named.Name):toBe("Named")
				stopNamed()
				stop()
				Verify.expect((node:isDestroyed())):toBe(true)
				runtime:dispose()
				for _, kind in { "primitive", "target", "mode" } :: { "mode" | "primitive" | "target" } do
					Verify.expect((pcall(scaffold.plan, kind, "proof"))):toBe(false)
				end
			end,
		})

		verifyHarness:case("installs each control family on its first read and keeps the full member set", {
			id = "native_registration::native registration and package contract::installs each control family on its first read and keeps the full member set",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local function fresh(): { [string]: unknown }
					return (Facet.controls(runtime, { types = engine.types }) :: unknown) :: { [string]: unknown }
				end
				local complete = fresh()
				local names: { string } = {}
				for name, value in complete do
					Verify.expect(type(name)):toBe("string")
					Verify.expect(value ~= nil):toBe(true)
					table.insert(names, name)
				end
				Verify.expect(#names > 90):toBe(true)
				for _, name in names do
					local controls = fresh()
					Verify.expect(type(controls[name])):toBe(type(complete[name]))
				end
				local lazy = fresh()
				local metatableOf = (getmetatable :: unknown) :: (unknown) -> { __index: { [string]: unknown } }
				local members = metatableOf(lazy).__index
				Verify.expect(rawget(members, "Button")):toBe(nil)
				Verify.expect(type(lazy.Button)):toBe("function")
				Verify.expect(type(rawget(members, "Button"))):toBe("function")
				Verify.expect(rawget(members, "Table")):toBe(nil)
				Verify.expect(rawget(members, "Text")):toBe(nil)
				Verify.expect(lazy.Missing):toBe(nil)
				Verify.expect((table.isfrozen(lazy))):toBe(true)
				Verify.expect((pcall(function()
					lazy.Button = nil
				end))):toBe(false)
				runtime:dispose()
			end,
		})

		verifyHarness:case("a family first read inside a mount stays usable after that mount stops", {
			id = "native_registration::native registration and package contract::a family first read inside a mount stays usable after that mount stops",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local UI = Facet.controls(runtime, { types = engine.types })
				local stopFirst, firstNode = runtime.mount(function()
					return UI.Button "First" { label = "First" }
				end, engine.new("Folder"))
				Verify.expect((firstNode :: Instance).Name):toBe("First")
				stopFirst()
				local stopSecond, secondNode = runtime.mount(function()
					return UI.Button "Second" { label = "Second" }
				end, engine.new("Folder"))
				Verify.expect((secondNode :: Instance).Name):toBe("Second")
				stopSecond()
				runtime:dispose()
			end,
		})
	end)
end
