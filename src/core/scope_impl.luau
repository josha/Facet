--!strict
-- Compose owns cleanup storage and early-child removal; Facet keeps its API.
local Compose = require("../vendor/compose")
local impl = {}
function impl.factory(counts: any, report: any, givenReactor: any?)
	local reactor = givenReactor or Compose.reactor()
	local Scope = {}
	Scope.__index = Scope
	local function newScope(label: string?, native: any?): any
		counts.scopes += 1
		local self =
			setmetatable({ label = label, native = native or Compose.createOwner(reactor), disposed = false }, Scope)
		self.native.own(function()
			self.disposed = true
			counts.scopes -= 1
		end)
		return self
	end
	function Scope.own(self: any, resource: any): any
		assert(not self:isDisposed(), "cannot own into a disposed scope")
		if type(resource) == "function" then
			self.native.own(resource)
		elseif type(resource) == "table" then
			if resource.dispose == nil then
				error(
					`Facet scope: own() on scope '{self.label or "?"}' was handed a table with no dispose() — own its release FUNCTION instead`,
					0
				)
			end
			self.native.own(function()
				if getmetatable(resource) ~= Scope or not resource:isDisposed() then
					resource:dispose()
				end
			end)
		end
		return resource
	end
	function Scope.use(_self: any, resource: any): any
		return resource
	end
	function Scope.child(self: any, label: string?): any
		assert(not self:isDisposed(), "cannot create a child of a disposed scope")
		return newScope(label, self.native.createChild())
	end
	function Scope.isDisposed(self: any): boolean
		return self.disposed or self.native.isDisposed()
	end
	function Scope.dispose(self: any)
		if self:isDisposed() then
			if report then
				report(`Facet: double disposal of scope '{self.label or "?"}' detected`)
			end
			return
		end
		local ok, err = pcall(self.native.dispose)
		if not ok and report then
			report(`Facet: scope cleanup error in '{self.label or "?"}': {tostring(err)}`)
		end
	end
	return newScope
end
return impl
