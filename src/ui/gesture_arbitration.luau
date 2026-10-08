--!strict
export type Kind = "pending" | "drag" | "pan" | "scroll" | "press" | "doubleTap" | "cancelled"
export type Options = {
	pickup: ("immediate" | "longPress")?,
	axis: ("X" | "Y" | "XY")?,
	scroll: boolean?,
	threshold: number?,
}
export type Decision = { owner: GuiObject, origin: Vector2, kind: Kind }
type Contact = Decision & { options: Options }
export type Arbiter = {
	begin: (InputObject, GuiObject, Vector2, Options) -> boolean,
	move: (InputObject, Vector2) -> Kind?,
	claim: (InputObject, GuiObject, Kind) -> boolean,
	get: (InputObject) -> Decision?,
	finish: (InputObject, GuiObject, boolean?) -> Kind?,
	cancelOwner: (GuiObject) -> (),
	capture: (GuiObject, () -> ()) -> (),
	claimCamera: (GuiObject) -> boolean,
}
export type Binding = {
	begin: (InputObject, Vector2, Options) -> boolean,
	move: (InputObject, Vector2) -> Kind?,
	claim: (InputObject, Kind) -> boolean,
	get: (InputObject) -> Decision?,
	finish: (InputObject, boolean?) -> Kind?,
}
local arbitration = {}

function arbitration.new(): Arbiter
	local contacts: { [InputObject]: Contact } = {}
	local arbiter = {} :: Arbiter
	local captureOwner: GuiObject? = nil
	local cameras: { [GuiObject]: boolean } = {}
	function arbiter.begin(pointer: InputObject, owner: GuiObject, origin: Vector2, options: Options): boolean
		if contacts[pointer] then
			return contacts[pointer].owner == owner
		end
		local threshold = options.threshold or 6
		assert(threshold > 0 and threshold < math.huge, "Facet gesture threshold must be finite and positive")
		contacts[pointer] = { owner = owner, origin = origin, kind = "pending" :: Kind, options = table.clone(options) }
		return true
	end
	function arbiter.move(pointer: InputObject, position: Vector2): Kind?
		local contact = contacts[pointer]
		if not contact then
			return nil
		end
		if contact.kind ~= "pending" then
			return contact.kind
		end
		local delta = position - contact.origin
		local options = contact.options
		if delta.Magnitude < (options.threshold or 6) then
			return "pending"
		end
		local along = (options.axis ~= "X" or math.abs(delta.X) >= math.abs(delta.Y))
			and (options.axis ~= "Y" or math.abs(delta.Y) >= math.abs(delta.X))
		contact.kind = if options.pickup == "immediate" and along
			then "drag"
			elseif options.scroll then "scroll"
			else "pan"
		return contact.kind
	end
	function arbiter.claim(pointer: InputObject, owner: GuiObject, kind: Kind): boolean
		local contact = contacts[pointer]
		if not contact or contact.owner ~= owner then
			return false
		end
		if contact.kind ~= "pending" then
			return contact.kind == kind
		end
		if kind == "drag" and contact.options.pickup == nil then
			return false
		end
		if kind == "pan" or kind == "scroll" then
			return false
		end
		contact.kind = kind
		return true
	end
	function arbiter.get(pointer: InputObject): Decision?
		local contact = contacts[pointer]
		return if contact then { owner = contact.owner, origin = contact.origin, kind = contact.kind } else nil
	end
	function arbiter.finish(pointer: InputObject, owner: GuiObject, cancelled: boolean?): Kind?
		local contact = contacts[pointer]
		if not contact or contact.owner ~= owner then
			return nil
		end
		contacts[pointer] = nil
		return if cancelled then "cancelled" elseif contact.kind == "pending" then "press" else contact.kind
	end
	function arbiter.capture(owner: GuiObject, callback: () -> ())
		assert(captureOwner == nil, "Facet capture callbacks cannot start another capture")
		captureOwner = owner
		table.clear(cameras)
		local ok, failure = pcall(function(): unknown
			callback()
			return nil
		end)
		captureOwner = nil
		table.clear(cameras)
		if not ok then
			error(failure, 0)
		end
	end
	function arbiter.claimCamera(surface: GuiObject): boolean
		local owner = captureOwner
		if not owner or cameras[surface] or (owner ~= surface and not owner:IsDescendantOf(surface)) then
			return false
		end
		cameras[surface] = true
		return true
	end
	function arbiter.cancelOwner(owner: GuiObject)
		for pointer, contact in contacts do
			if contact.owner == owner then
				contacts[pointer] = nil
			end
		end
	end
	return arbiter
end

return arbitration
