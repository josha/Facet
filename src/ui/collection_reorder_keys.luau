--!strict
local ComposeTypes = require("../vendor/compose/core")
local State = require("./collection_reorder_state")
return function<V, K>(shared: State.Reorder<V, K>, root: Frame, body: ScrollingFrame): ()
	local ctx, spec, gesture = shared.ctx, shared.spec, shared.gesture
	local E = ctx.types.Enum
	local moving, choosingDestination, drag, focus =
		shared.moving, shared.choosingDestination, shared.drag, shared.focus
	local rowNodes, gui, horizontal = shared.rowNodes, shared.gui, shared.horizontal
	local reorderable, deletable, begin, step = shared.reorderable, shared.deletable, shared.begin, shared.step
	local commit, chosen = shared.commit, shared.chosen
	local function keyboardActive(use: ComposeTypes.Use): boolean
		local move = use(moving)
		local node = use(focus)
		return (spec.onReorder ~= nil or spec.drop ~= nil)
			and move ~= nil
			and move.keyboard
			and not use(choosingDestination)
			and (node == nil or node == gesture.keyboardTarget or node:IsDescendantOf(body))
	end
	if spec.drag then
		local function focusedKey(use: ComposeTypes.Use?): K?
			local node = if use then use(focus) else focus:peek()
			if not node then
				return nil
			end
			for key, frame in rowNodes do
				if frame.Parent and node:IsDescendantOf(frame.Parent) then
					return key
				end
			end
			return nil
		end
		ctx.action(root, "CollectionPickUp", { E.KeyCode.Return, E.KeyCode.ButtonA }, function(use)
			return use(moving) == nil and use(drag.state) == nil and focusedKey(use) ~= nil
		end, function()
			local key = focusedKey(nil)
			if key ~= nil then
				begin(key)
			end
		end, { priority = 400 })
	end
	if spec.drag and (spec.onReorder or spec.drop) then
		ctx.action(root, "ChooseDropDestination", { E.KeyCode.ButtonY }, function(use)
			local move = use(moving)
			local session = use(drag.state)
			return move ~= nil and move.keyboard and session ~= nil and not session.pending
		end, function()
			choosingDestination:set(not choosingDestination:peek())
			if gui then
				local move = moving:peek()
				local row = move and rowNodes[move.key]
				local hit = row and row.Parent and row.Parent:FindFirstChild("RowHit")
				gui.SelectedObject = if choosingDestination:peek()
						and hit
						and hit:IsA("GuiObject")
					then hit
					else gesture.keyboardTarget
			end
			local session = drag.state:peek()
			if session then
				session.spec.navigationHint = if choosingDestination:peek()
					then "Y: reorder here"
					else "Y: choose destination"
				drag.hover(drag.targetOf(focus:peek()), nil)
			end
		end, { priority = 400 })
	end
	local earlier = if horizontal then { E.KeyCode.Left, E.KeyCode.DPadLeft } else { E.KeyCode.Up, E.KeyCode.DPadUp }
	local later = if horizontal
		then { E.KeyCode.Right, E.KeyCode.DPadRight }
		else { E.KeyCode.Down, E.KeyCode.DPadDown }
	ctx.action(root, "ReorderUp", earlier, keyboardActive, function()
		step(-1, true)
	end, { priority = 400, capture = true })
	ctx.action(root, "ReorderDown", later, keyboardActive, function()
		step(1, true)
	end, { priority = 400, capture = true })
	if shared.grid then
		ctx.action(
			root,
			"ReorderCrossEarlier",
			if horizontal then { E.KeyCode.Up, E.KeyCode.DPadUp } else { E.KeyCode.Left, E.KeyCode.DPadLeft },
			keyboardActive,
			function()
				step(-1)
			end,
			{ priority = 400, capture = true }
		)
		ctx.action(
			root,
			"ReorderCrossLater",
			if horizontal then { E.KeyCode.Down, E.KeyCode.DPadDown } else { E.KeyCode.Right, E.KeyCode.DPadRight },
			keyboardActive,
			function()
				step(1)
			end,
			{ priority = 400, capture = true }
		)
	end
	ctx.action(root, "ReorderCancel", { E.KeyCode.Escape, E.KeyCode.ButtonB }, function(use: ComposeTypes.Use)
		return use(moving) ~= nil
	end, shared.cancel, { priority = 400 })
	ctx.action(root, "ReorderDrop", { E.KeyCode.Return, E.KeyCode.ButtonA }, function(use)
		local move = use(moving)
		return move ~= nil
			and move.keyboard
			and not use(choosingDestination)
			and (spec.onReorder ~= nil or spec.drop ~= nil)
	end, commit, { priority = 400 })
	if reorderable then
		local function nudge(delta: number)
			local keys = chosen()
			if #keys > 0 then
				begin(keys[1], nil, true)
				step(delta)
				commit()
			end
		end
		local function ready(use: ComposeTypes.Use): boolean
			return use(moving) == nil and #chosen(use) > 0
		end
		ctx.action(root, "MoveRowsEarlier", { E.KeyCode.ButtonL1 }, ready, function()
			nudge(-1)
		end, { priority = 400 })
		ctx.action(root, "MoveRowsLater", { E.KeyCode.ButtonR1 }, ready, function()
			nudge(1)
		end, { priority = 400 })
	end
	if deletable then
		ctx.action(
			root,
			"DeleteRows",
			{ E.KeyCode.Delete, E.KeyCode.Backspace, E.KeyCode.ButtonX },
			shared.canDelete,
			function()
				shared.remove(false)
			end,
			{ priority = 400 }
		)
	end
end
