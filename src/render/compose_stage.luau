--!strict
-- Connect engine content to a native Stage's lifetime after its target exists.
local Compose = require("../vendor/compose/core")
local contribution = require("../input/contribution")
local stage = {}

function stage.new(construct)
	local function build(spec, name)
		local props = table.clone(spec)
		local content = props.content
		props.content = nil
		assert(content == nil or type(content) == "function", "Stage.content must be a function")
		local node = if name then construct(name)(props) else construct(props)
		if content == nil then
			return node
		end
		local owner = Compose.currentOwner().createChild()
		local controller, started = nil, false
		return contribution.attach(node, {
			bindController = function(value)
				controller = value
			end,
			syncGeometry = function(_, current)
				if started or controller == nil or owner.isDisposed() then
					return
				end
				local host = controller.stageHost(current.path)
				if host == nil then
					return
				end
				started = true
				local ok, result = pcall(Compose.withOwner, owner, function()
					local cleanup = content(host)
					assert(
						cleanup == nil or type(cleanup) == "function",
						"Stage.content must return a cleanup function or nil"
					)
					if cleanup then
						Compose.cleanup(cleanup)
					end
				end)
				if not ok then
					owner.dispose()
					error(result, 0)
				end
			end,
		})
	end
	return function(spec)
		if type(spec) == "string" then
			return function(props)
				return build(props, spec)
			end
		end
		return build(spec, nil)
	end
end
return stage
