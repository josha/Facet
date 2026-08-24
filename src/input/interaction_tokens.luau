--!strict
-- Shared interaction tokens (ADR-0022 Decision 5). ONE place where
-- the numbers that decide "was that a tap or a drag?" live, keyed by INPUT
-- CLASS rather than by consumer.
--
-- WHY A TOKEN MODULE AND NOT A CONSTANT PER CONTROL: a press→drag threshold is
-- a device fact, not a control fact. A finger's resting jitter is ~10 px on a
-- phone and a mouse's is ~1 px, so one number cannot serve both; and when each
-- control carries its own copy, a device round that retunes touch has to find
-- every copy. Table shipped a private `DRAG_THRESHOLD = 6` for exactly this
-- reason and it was correct for mice and wrong for fingers. It now reads the
-- token, and so does every acquisition path added since.
--
-- The ratified values (Sponsor motion spec, cited as framework defaults):
--   pointer 6 px  [4–8]     mouse/pen: precise devices, a small gate
--   touch  14 px  [10–18]   fingers: the gate has to clear resting jitter
-- Non-pointer classes carry 0: a keyboard or gamepad drag is ARMED by an
-- explicit verb (Activate-hold / a grab action), so there is no travel to
-- measure. The slot exists so the shape stays per-class as new classes land.
--
-- Nothing here reads the environment. A promotion decision is made against the
-- pointer type of the EVENT in hand — a hybrid device delivers mouse and touch
-- events to the same node, and the live class SET cannot say which one this
-- press was.

local interaction_tokens = {}

-- input class -> press→drag promotion distance in Facet px
local DRAG_PROMOTION_PX: { [string]: number } = {
	pointer = 6,
	touch = 14,
	-- non-gestural acquisition: armed by verb, never by travel
	keyboard = 0,
	gamepad = 0,
}
interaction_tokens.dragPromotionPx = table.freeze(DRAG_PROMOTION_PX)

-- the ratified tuning ranges, published so a review round can check a game's
-- override against the band it was ratified inside rather than against taste
interaction_tokens.dragPromotionRangePx = table.freeze({
	pointer = table.freeze({ min = 4, max = 8 }),
	touch = table.freeze({ min = 10, max = 18 }),
})

-- engine/adapter pointerType -> interaction class. `pen` is precise like a
-- mouse; an unknown or absent type is treated as pointer, because the ONE
-- adapter that omits it (the headless fake's default) is a mouse.
local POINTER_TYPE_CLASS: { [string]: string } = {
	mouse = "pointer",
	pen = "pointer",
	pointer = "pointer",
	touch = "touch",
}

function interaction_tokens.classForPointerType(pointerType: string?): string
	if pointerType == nil then
		return "pointer"
	end
	return POINTER_TYPE_CLASS[pointerType] or "pointer"
end

-- promotion distance for an interaction class. An unknown class falls back to
-- the pointer gate rather than to zero: a gate that is too small still asks the
-- player to move, while a zero gate would eat every tap on that device.
function interaction_tokens.promotionPx(inputClass: string?, overrides: { [string]: number }?): number
	local class = inputClass or "pointer"
	if overrides ~= nil and type(overrides[class]) == "number" then
		return overrides[class]
	end
	local px = DRAG_PROMOTION_PX[class]
	return if px ~= nil then px else DRAG_PROMOTION_PX.pointer
end

function interaction_tokens.promotionForPointerType(pointerType: string?, overrides: { [string]: number }?): number
	return interaction_tokens.promotionPx(interaction_tokens.classForPointerType(pointerType), overrides)
end

--[[ THE RESPONDER PRIORITY BANDS (framework-gaps-phase2 item 41; ADR-0014;
	`src/present/presenter.luau`'s own responder-priority section is the live
	authority these numbers mirror). A consumer arbitrating its OWN input
	contexts against a Facet-presented surface's — the exact shape
	`games/RascalRally/code/src/shared/InputActions.luau` is — has to know
	where Facet's own bands sit, and until now the only place that was written
	down was a comment inside `presenter.luau` and inside this framework's own
	controls (`src/input/contribution.luau`, `src/controls/row_actions.luau`)
	that named it in prose rather than pointing at a value. Published here so
	"know it only by comment" stops being the only way to find out.

	  baseScreen   every presented Facet screen (`kind = "screen"`) sinks here.
	  engagedBase  an engaged-from-passive or modal surface's floor — strictly
	               above `baseScreen`, so an engaged surface can never be
	               starved by a base screen sharing its band.
	  modalStep    each modal stacks this far above the previous one
	               (`engagedBase + modalStep * depth`), so nested modals never
	               collide on one priority.

	A NUMBER A GAME MUST STAY BELOW, NOT ONE IT MAY REUSE: a context sitting AT
	or above `baseScreen` can sink a Facet screen it does not own (measured
	live, a RascalRally device finding rebuilt one layer up — see `InputActions.luau`'s own
	account of the failure mode this exists to prevent). ]]
interaction_tokens.contextPriority = table.freeze({
	baseScreen = 1500,
	engagedBase = 3000,
	modalStep = 500,
})

-- has this press travelled far enough to become a drag? MAGNITUDE, not
-- per-axis: a 5 px diagonal on a mouse is 7 px of travel and reads as a drag to
-- the player, while two independent axis tests would still call it a tap.
function interaction_tokens.promoted(
	dx: number,
	dy: number,
	pointerType: string?,
	overrides: { [string]: number }?
): boolean
	local gate = interaction_tokens.promotionForPointerType(pointerType, overrides)
	if gate <= 0 then
		return true
	end
	return (dx * dx + dy * dy) >= gate * gate
end

return interaction_tokens
