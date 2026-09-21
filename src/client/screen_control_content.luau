--!strict
-- Internal ownership for generated primary text/icons. Only tags cross the link;
-- native rules remain the sole color writer. Clear before pooling or removal.
local sheet = require("../tokens/sheet_model")
local content = {}
function content.new(collection: any, handles: { [string]: any }): any
	local api = {}
	local function tagsFor(handle: any): { [string]: boolean }
		local owner = handle.contentOwner
		if owner == nil then
			return {}
		end
		local state = ""
		pcall(function()
			state = string.match(tostring(owner.instance.GuiState), "([%w]+)$") or ""
		end)
		return sheet.contentTags(collection:GetTags(owner.instance), state)
	end
	local function apply(instance: any, desired: { [string]: boolean })
		if instance == nil then
			return
		end
		for _, tag in collection:GetTags(instance) do
			if
				(
					string.sub(tag, 1, #sheet.CONTENT_OWNER_PREFIX) == sheet.CONTENT_OWNER_PREFIX
					or tag == sheet.CONTENT_TEXT_TAG
					or tag == sheet.CONTENT_ICON_TAG
					or tag == sheet.CONTENT_ART_TAG
				) and not desired[tag]
			then
				collection:RemoveTag(instance, tag)
			end
		end
		for tag in desired do
			if not collection:HasTag(instance, tag) then
				collection:AddTag(instance, tag)
			end
		end
	end
	local function refresh(handle: any)
		local desired = {}
		if handle.contentOwner and handle.contentOwner ~= handle then
			desired = tagsFor(handle)
			desired[sheet.CONTENT_TEXT_TAG] = true
		end
		apply(handle.instance, desired)
		local image = {}
		if handle.contentOwner then
			image = tagsFor(handle)
			image[sheet.CONTENT_ART_TAG] = true
			image[sheet.CONTENT_ICON_TAG] = if handle.iconContentPaint then true else nil
		end
		apply(handle.iconInstance, image)
	end
	function api.augment(handle: any, desired: { [string]: boolean })
		if handle.contentOwner and handle.contentOwner ~= handle then
			for tag in tagsFor(handle) do
				desired[tag] = true
			end
			desired[sheet.CONTENT_TEXT_TAG] = true
		end
	end
	function api.changed(handle: any)
		if handle.contentOwner then
			refresh(handle)
		end
		if handle.contentFollowers then
			for follower in handle.contentFollowers do
				refresh(follower)
			end
		end
	end
	function api.clear(handle: any)
		if handle == nil then
			return
		end
		local owner = handle.contentOwner
		handle.contentOwner = nil
		if owner then
			owner.contentFollowers[handle] = nil
			if next(owner.contentFollowers) == nil then
				if owner.contentStateConn then
					owner.contentStateConn:Disconnect()
					owner.contentStateConn = nil
				end
				owner.contentFollowers = nil
			end
			refresh(handle)
		end
		if handle.contentFollowers then
			for follower in table.clone(handle.contentFollowers) do
				api.clear(follower)
			end
		end
	end
	function api.bind(handle: any)
		api.clear(handle)
		local depth = handle.decorationHint and handle.decorationHint.contentOwnerDepth
		if depth == nil then
			return
		end
		local path = handle.path
		for _ = 1, depth do
			path = string.match(path, "^(.*)/[^/]+$") or ""
		end
		local owner = handles[path]
		assert(
			owner and owner.class == "Button" and owner.rootHandle == handle.rootHandle,
			"Facet generated content must name its Button or an ancestor Button on the same surface"
		)
		handle.contentOwner = owner
		if owner.contentFollowers == nil then
			owner.contentFollowers = {}
			owner.contentStateConn = owner.instance:GetPropertyChangedSignal("GuiState"):Connect(function()
				api.changed(owner)
			end)
		end
		owner.contentFollowers[handle] = true
		refresh(handle)
	end
	return api
end
return content
