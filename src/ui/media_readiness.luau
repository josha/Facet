--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")
local rest = require("./rest")
local motion = require("./motion")

return function(ctx: Types.Context, node: ImageLabel | ViewportFrame, authored: Types.Value<number>?)
	local Compose = ctx.Compose
	local owner = assert(Compose.currentOwner())
	local scope: ComposeTypes.Owner? = nil
	local held: Instance? = nil
	local background = node.BackgroundTransparency
	local backgroundColor = node.BackgroundColor3
	local function locate()
		local parent: Instance? = node.Parent
		local row: Instance? = nil
		local surface: GuiObject? = nil
		while parent do
			if parent:IsA("GuiObject") and parent:HasTag("facet-panel") and surface == nil then
				surface = parent
			end
			if parent:GetAttribute("FacetCollectionRow") then
				row = parent
				break
			end
			parent = parent.Parent
		end
		if row == held or owner.isDisposed() then
			return
		end
		if scope then
			scope.dispose()
			scope = nil
		end
		held = row
		if not row then
			(node :: ImageLabel).ImageTransparency = ctx.read(authored) or 0
			local native = node :: GuiObject
			if not node:IsA("ViewportFrame") then
				native.BackgroundTransparency = background
				native.BackgroundColor3 = backgroundColor
			end
			node:SetAttribute("FacetMediaReady", nil)
			return
		end
		local nextScope = owner.createChild()
		scope = nextScope
		Compose.withOwner(nextScope, function()
			local size = ctx.observe.AbsoluteSize(node)
			local observed = (ctx.observe :: unknown) :: { [string]: (Instance) -> ComposeTypes.Cell<unknown> }
			local loaded = if node:IsA("ImageLabel") then observed.IsLoaded(node) else nil
			local image = if node:IsA("ImageLabel") then observed.Image(node) else nil
			local assetOwner: ComposeTypes.Owner? = nil
			Compose.watch(function(use: ComposeTypes.Use)
				if image then
					use(image)
				end
				if assetOwner then
					assetOwner.dispose()
				end
				local asset = nextScope.createChild()
				assetOwner = asset
				Compose.withOwner(asset, function()
					node:SetAttribute("FacetMediaReady", false)
					local ready = rest(ctx, function(): (string, boolean, boolean?)
						local box = size:peek()
						local filled = box.X > 0
							and box.Y > 0
							and node:GetAttribute("FacetBuilt") ~= false
							and (loaded == nil or (image ~= nil and image:peek() == "") or loaded:peek() == true)
						return tostring(box), filled, filled
					end, function(use: ComposeTypes.Use): string
						return if image then tostring(use(image)) else tostring(use(size))
					end, true)
					Compose.watch(function(read: ComposeTypes.Use)
						node:SetAttribute("FacetMediaReady", read(ready))
					end)
					local amount = ctx.runtime.tween(function(use: ComposeTypes.Use): number
						return if use(ready) then 1 else 0
					end, {
						seconds = function(use: ComposeTypes.Use): number
							return ctx.motionTiming("reveal", use).enter
						end,
						ease = ctx.motionEase("fade"),
						reducedMotion = motion.reduced(ctx),
					})
					local color = ctx.observeStyled.BackgroundColor3(surface or (row :: GuiObject))
					ctx.runtime.decorate(node, {
						ImageTransparency = function(use: ComposeTypes.Use): number
							return 1 - (1 - (ctx.read(authored, use) or 0)) * use(amount)
						end,
						BackgroundTransparency = if node:IsA("ViewportFrame")
							then nil
							else function(use: ComposeTypes.Use): number
								return background * use(amount)
							end,
						BackgroundColor3 = if node:IsA("ViewportFrame")
							then nil
							else function(use: ComposeTypes.Use): Color3
								local progress = use(amount)
								local target = backgroundColor
								local placeholder = use(color)
								if background >= 1 then
									return if progress < 1 then placeholder else target
								end
								return placeholder:Lerp(target, progress)
							end,
					})
				end)
			end)
		end)
	end
	ctx.runtime.connect(node, "AncestryChanged", locate)
	locate()
end
