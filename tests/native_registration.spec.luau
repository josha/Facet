--!strict
local t = require("./lib/testkit")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local scaffold = require("../tools/lune/scaffold")
local function registrations(path, found)
	for _, name in fs.readDir(path) do
		local full = path .. "/" .. name
		if fs.isDir(full) then
			registrations(full, found)
		elseif string.match(name, "%.luau$") then
			for constructor in string.gmatch(fs.readFile(full), "UI%.([%a_][%w_]*)%s*=") do
				assert(not found[constructor], "Duplicate control registration: " .. constructor)
				found[constructor] = full
			end
		end
	end
end

t.describe("native registration and package contract", function()
	t.it("registers every authored control and documents every public constructor", function()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, { types = engine.types })
		local found = {}
		registrations("src/ui", found)
		local reference = fs.readFile("docs/reference/api.md")
		for name in found do
			t.expect(type(UI[name])).toBe("function")
			t.expect(string.find(reference, name, 1, true) ~= nil).toBe(true)
		end
		for name, constructor in UI do
			t.expect(found[name] ~= nil).toBe(true)
			t.expect(type(constructor)).toBe("function")
		end
		t.expect(table.isfrozen(UI)).toBe(true)
		t.expect(string.match(Facet.VERSION, "^%d+%.%d+%.%d+$") ~= nil).toBe(true)
		t.expect(Facet.Compose).toBe(require("../src/vendor/compose/core"))
		t.expect(Facet.Roblox).toBe(require("../src/vendor/compose/roblox"))
		runtime:dispose()
	end)
	t.it("scaffolds a typed native control with idempotent runtime and public type registration", function()
		local plan = scaffold.plan("control", "proof_control")
		t.expect(#plan.files).toBe(1)
		t.expect(#plan.edits).toBe(3)
		t.expect(plan.files[1].path).toBe("src/ui/proof_control.luau")
		local edited = {}
		for _, edit in plan.edits do
			edited[edit.path] = scaffold.applyEdit(fs.readFile(edit.path), edit)
			t.expect(scaffold.applyEdit(edited[edit.path], edit)).toBe(edited[edit.path])
			luau.compile(edited[edit.path])
		end
		local generated = luau.load(plan.files[1].content, {
			environment = {
				require = function(path)
					t.expect(path).toBe("@self/types")
					return require("../src/ui/types")
				end,
			},
		})()
		local createControls = luau.load(edited["src/ui/init.luau"], {
			environment = {
				require = function(path)
					return if path == "@self/proof_control"
						then generated
						else require("../src/ui/" .. string.sub(path, 7))
				end,
			},
		})()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local UI = createControls(Facet.Compose, runtime, { types = engine.types })
		t.expect(table.isfrozen(UI)).toBe(true)
		local stop, node = runtime.mount(function()
			return UI.ProofControl "Proof" { Size = engine.types.UDim2.fromOffset(60, 40) }
		end, engine.new("Folder"))
		t.expect(node.ClassName).toBe("Frame")
		t.expect(node.Name).toBe("Proof")
		t.expect(node.Size.X.Offset).toBe(60)
		local stopNamed, named = runtime.mount(function()
			return UI.ProofControl("Named")({ Size = engine.types.UDim2.fromOffset(20, 30) })
		end, engine.new("Folder"))
		t.expect(named.Name).toBe("Named")
		stopNamed()
		stop()
		t.expect(node.isDestroyed()).toBe(true)
		runtime:dispose()
		for _, kind in { "primitive", "target", "mode" } do
			t.expect(pcall(scaffold.plan, kind, "proof")).toBe(false)
		end
	end)
end)
