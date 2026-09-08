--!strict
-- Native caret observation is read-only. The renderer owns scrolling; Roblox
-- owns editing. Each wiring owns its asynchronous measurements and connections.
local reconnect = require("./handle_conn").reconnect
local screen_caret = {}

function screen_caret.wire(handle: any, handlers: any)
	local instance = handle.instance
	handle.textHandlers = handlers
	for _, property in
		{ "CursorPosition", "Text", "AbsoluteSize", "TextSize", "LineHeight", "FontFace", "Padding", "Window" }
	do
		reconnect(handle, "caret" .. property .. "Conn", function()
			return nil
		end)
	end
	-- Wrapped TextBoxes stop native caret scrolling at their own bounds.
	-- Report the native cursor's line to the existing scroll authority; never
	-- write CursorPosition, selection, text, or CanvasPosition here.
	if handlers.onCaretRect then
		local revision = 0
		local function revealCaret()
			revision += 1
			local ticket = revision
			task.defer(function()
				if
					handle.textHandlers ~= handlers
					or ticket ~= revision
					or instance.Parent == nil
					or not instance:IsFocused()
					or not instance.MultiLine
				then
					return
				end
				local cursor = instance.CursorPosition
				if cursor < 1 then
					return
				end
				local text = instance.Text
				-- Include the remainder of the word, so its wrap agrees with the
				-- complete document when the cursor sits inside that word.
				local wordEnd = string.find(text, "%s", cursor) or (#text + 1)
				local before = string.sub(text, 1, cursor - 1)
				local wordStart = string.find(before, "%S+$") or cursor
				local pad = instance:FindFirstChildOfClass("UIPadding")
				local size = instance:GetStyled("TextSize")
				local face = instance:GetStyled("FontFace")
				local lineHeight = size * instance:GetStyled("LineHeight")
				local left = if pad then pad.PaddingLeft.Offset else 0
				local right = if pad then pad.PaddingRight.Offset else 0
				local top = if pad then pad.PaddingTop.Offset else 0
				local width = math.max(1, instance.AbsoluteSize.X - left - right)
				local params = Instance.new("GetTextBoundsParams")
				params.Font = face
				params.Size = size
				local ok, bounds = pcall(function()
					local service = game:GetService("TextService")
					params.Text = string.sub(text, wordStart, wordEnd - 1)
					params.Width = 1000000
					local word = service:GetTextBoundsAsync(params)
					-- A word wider than the viewport breaks inside itself; only
					-- measure through the cursor in that case, not its final line.
					params.Text = (if word.X > width then before else string.sub(text, 1, wordEnd - 1)) .. "\u{200B}"
					params.Width = width
					return service:GetTextBoundsAsync(params)
				end)
				params:Destroy()
				if
					not ok
					or handle.textHandlers ~= handlers
					or ticket ~= revision
					or instance.Parent == nil
					or not instance:IsFocused()
				then
					return
				end
				if
					instance.Text ~= text
					or instance.CursorPosition ~= cursor
					or instance:GetStyled("FontFace") ~= face
					or instance:GetStyled("TextSize") ~= size
					or size * instance:GetStyled("LineHeight") ~= lineHeight
					or math.max(
						1,
						instance.AbsoluteSize.X - (if pad then pad.PaddingLeft.Offset + pad.PaddingRight.Offset else 0)
					) ~= width
					or (if pad then pad.PaddingTop.Offset else 0) ~= top
				then
					revealCaret()
					return
				end
				local line = math.max(1, math.round(bounds.Y / size))
				handlers.onCaretRect({ x = 0, y = top + (line - 1) * lineHeight, w = 1, h = lineHeight })
			end)
		end
		for _, property in { "CursorPosition", "Text", "AbsoluteSize", "TextSize", "LineHeight" } do
			reconnect(handle, "caret" .. property .. "Conn", function()
				return instance:GetPropertyChangedSignal(property):Connect(revealCaret)
			end)
		end
		reconnect(handle, "caretFontFaceConn", function()
			return instance:GetStyledPropertyChangedSignal("FontFace"):Connect(revealCaret)
		end)
		local pad = instance:FindFirstChildOfClass("UIPadding")
		reconnect(handle, "caretPaddingConn", function()
			return if pad then pad.Changed:Connect(revealCaret) else nil
		end)
		local viewport = instance:FindFirstAncestorWhichIsA("ScrollingFrame")
		reconnect(handle, "caretWindowConn", function()
			return if viewport
				then viewport:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(revealCaret)
				else nil
		end)
	end
end

return screen_caret
