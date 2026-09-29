--!strict

return function(lab: any, playerGui: PlayerGui, ids: { string }): string
	local out = {}
	local function visible(node: GuiObject): boolean
		local at: Instance? = node
		while at and at:IsA("GuiObject") do
			if not (at :: GuiObject).Visible then
				return false
			end
			at = at.Parent
		end
		return true
	end
	for _, id in ids do
		lab.open(id)
		task.wait(0.3)
		local root = playerGui:FindFirstChild("Facet_FoundationLab")
		local page = root and root:FindFirstChild(`Page_{id}`, true)
		if page == nil then
			table.insert(out, `{id}: page did not mount`)
			continue
		end
		local lines = {}
		for _, node in page:GetDescendants() do
			if (node:IsA("TextLabel") or node:IsA("TextButton")) and visible(node) then
				local label = node :: TextLabel
				if label.Text ~= "" and label.TextTransparency < 1 then
					if label.AbsoluteSize.X < 1 then
						table.insert(lines, `text zero-width: {label:GetFullName()}`)
					elseif
						not label.TextFits
						and (label.TextBounds.X > label.AbsoluteSize.X + 1 or label.TextBounds.Y > label.AbsoluteSize.Y + 1)
						and not label.TextWrapped
						and label.TextTruncate == Enum.TextTruncate.None
						and not label.TextScaled
					then
						table.insert(lines, `text clipped "{string.sub(label.Text, 1, 30)}": {label.Name}`)
					end

					local cell: Instance? = label.Parent
					local clipped = false
					while cell and not string.match(cell.Name, "^C%d+$") do
						clipped = clipped or (cell:IsA("GuiObject") and (cell :: GuiObject).ClipsDescendants)
						cell = cell.Parent
					end
					if clipped then
						cell = nil
					end
					if cell and cell:IsA("GuiObject") and cell.Parent and cell.Parent.Name == "Cells" then
						local right = label.AbsolutePosition.X + math.min(label.AbsoluteSize.X, label.TextBounds.X + 16)
						if right > cell.AbsolutePosition.X + cell.AbsoluteSize.X + 4 then
							table.insert(
								lines,
								`text past its cell "{string.sub(label.Text, 1, 30)}": {cell.Parent.Parent.Name}/{cell.Name}`
							)
						end
					end
				end
			end
			if
				node.Name == "Live"
				and node:IsA("GuiObject")
				and node.Parent
				and string.match(node.Parent.Name, "^C%d+$")
			then
				local cell = node.Parent :: GuiObject
				local a, b = node.AbsolutePosition, cell.AbsolutePosition
				if a.X + node.AbsoluteSize.X > b.X + cell.AbsoluteSize.X + 2 or a.X < b.X - 2 then
					table.insert(
						lines,
						`cell overflow: {cell.Parent and cell.Parent.Parent and cell.Parent.Parent.Name}/{cell.Name}`
					)
				end
			end
		end
		local errors = lab.report().errors
		for where, message in errors do
			table.insert(lines, `refused {where}: {string.sub(message, 1, 120)}`)
		end
		if #lines > 0 then
			table.sort(lines)
			local shown = {}
			for i = 1, math.min(#lines, 8) do
				table.insert(shown, lines[i])
			end
			table.insert(out, `{id} ({#lines}):\n  {table.concat(shown, "\n  ")}`)
		end
	end
	return if #out == 0 then "audit: clean" else table.concat(out, "\n")
end
