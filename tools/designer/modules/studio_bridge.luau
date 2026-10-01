--!strict

local document = require("./document")
local sourceReader = require("./source")
local savedLibrary = require("./saved_library")

local bridge = {}

function bridge.new(pluginHost: any): any
	local json = game:GetService("HttpService")
	local encoding = game:GetService("EncodingService")
	local editor = game:GetService("ScriptEditorService")
	local undo = game:GetService("ChangeHistoryService")
	local storage = game:GetService("ReplicatedStorage")
	local selection = game:GetService("Selection")
	local key = "FacetDesign_Library_v1"
	local linked: ModuleScript?
	local lastSource = ""
	local writable = true
	local writing = false
	local callback: any
	local sourceConnection: RBXScriptConnection?
	local function refresh(target: ModuleScript)
		task.defer(function()
			if writing or linked ~= target or not callback then
				return
			end
			local raw = editor:GetEditorSource(target)
			if raw == lastSource then
				return
			end
			local ok, value = pcall(sourceReader.parse, raw, target.Name)
			lastSource, writable = raw, ok
			target:SetAttribute("FacetDesignSourceStatus", if ok then "synchronized" else "custom")
			if ok then
				target:SetAttribute("FacetDesignDocument", json:JSONEncode(value))
			end
			callback(if ok then value else nil, if ok then nil else value)
		end)
	end
	local function link(target: ModuleScript?, raw: string)
		if sourceConnection then
			sourceConnection:Disconnect()
			sourceConnection = nil
		end
		linked, lastSource, writable = target, raw, true
		if target then
			target:SetAttribute("FacetDesignSourceStatus", "synchronized")
		end
		if target then
			sourceConnection = target:GetPropertyChangedSignal("Source"):Connect(function()
				refresh(target)
			end)
		end
	end
	return {
		import = function()
			local selected = selection:Get()[1]
			assert(selected and selected:IsA("ModuleScript"), "Select a Facet component ModuleScript in Explorer")
			local raw = editor:GetEditorSource(selected)
			local value = sourceReader.parse(raw, selected.Name)
			link(selected, raw)
			return value
		end,
		updateSource = function(value, generated)
			if not linked or not linked.Parent or generated == lastSource then
				return
			end
			assert(
				writable,
				"Custom code cannot be rewritten visually. Restore supported source or unlink this component"
			)
			local target = linked
			local previous = lastSource
			assert(
				editor:GetEditorSource(target) == previous,
				"Source changed. Import the current component before editing visually"
			)
			local recording = assert(
				undo:TryBeginRecording("FacetDesign.Edit", "Edit Facet design"),
				"Finish the current Studio edit first"
			)
			local changed = false
			writing = true
			local ok, err = pcall(function()
				editor:UpdateSourceAsync(target, function(current)
					changed = current == previous
					return if changed then generated else current
				end)
				assert(changed, "Source changed during the visual edit; the source was retained")
				lastSource = generated
				target:SetAttribute("FacetDesignDocument", json:JSONEncode(value))
			end)
			writing = false
			undo:FinishRecording(
				recording,
				if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
			)
			if not ok then
				error(err, 0)
			end
		end,
		disconnectSource = function()
			link(nil, "")
		end,
		watchSource = function(onChange)
			callback = onChange
			local connection = editor.TextDocumentDidChange:Connect(function(editDocument: any)
				if linked and editDocument:GetScript() == linked then
					refresh(linked)
				end
			end)
			return {
				Disconnect = function()
					connection:Disconnect()
					callback = nil
					link(nil, "")
				end,
			}
		end,
		read = function()
			local ok, value = pcall(function()
				local raw = pluginHost:GetSetting(key)
				return if type(raw) == "string"
					then json:JSONDecode(buffer.tostring(encoding:Base64Decode(buffer.fromstring(raw))))
					else {}
			end)
			if not ok or type(value) ~= "table" then
				return {}
			end
			local clean = { designs = {}, archived = {} }
			if value.draft and pcall(document.validate, value.draft) then
				clean.draft = value.draft
			end
			for _, bucket in { "designs", "archived" } do
				if type(value[bucket]) == "table" then
					for name, design in value[bucket] do
						if type(name) == "string" and pcall(document.validate, design) then
							clean[bucket][name] = design
						end
					end
				end
			end
			return clean
		end,
		write = function(value)
			local raw = json:JSONEncode(savedLibrary.validate(value))
			assert(#raw <= 900000, "Design library exceeds 900 KB")
			local encoded = buffer.tostring(encoding:Base64Encode(buffer.fromstring(raw)))
			pluginHost:SetSetting(key, encoded)
			assert(pluginHost:GetSetting(key) == encoded, "Studio did not save the design library. Try Save again")
		end,
		export = function(value, source, preview)
			local recording = assert(
				undo:TryBeginRecording("FacetDesign.Export", "Export Facet design"),
				"Finish the current Studio edit before exporting"
			)
			local created = {}
			local ok, err = pcall(function()
				local folder = storage:FindFirstChild("FacetDesigns")
				if folder then
					assert(folder:IsA("Folder"), "ReplicatedStorage.FacetDesigns must be a Folder")
				else
					folder = Instance.new("Folder")
					folder.Name = "FacetDesigns"
					folder.Parent = storage
					table.insert(created, folder)
				end
				local base = string.gsub(value.name, "[^%w_]", "")
				if base == "" then
					base = "Design"
				end
				local name, number = base, 1
				while folder:FindFirstChild(name) or folder:FindFirstChild(name .. ".preview") do
					number += 1
					name = base .. tostring(number)
				end
				local component = Instance.new("ModuleScript")
				table.insert(created, component)
				component.Name = name
				component:SetAttribute("FacetDesignDocument", json:JSONEncode(value))
				editor:UpdateSourceAsync(component, function()
					return source
				end)
				component.Parent = folder
				local sample = Instance.new("ModuleScript")
				table.insert(created, sample)
				sample.Name = name .. ".preview"
				editor:UpdateSourceAsync(sample, function()
					return preview(name, value.name)
				end)
				sample.Parent = folder
				selection:Set({ component })
				link(component, source)
			end)
			if not ok then
				for index = #created, 1, -1 do
					created[index]:Destroy()
				end
			end
			undo:FinishRecording(
				recording,
				if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
			)
			if not ok then
				error(err, 0)
			end
		end,
	}
end

return bridge
