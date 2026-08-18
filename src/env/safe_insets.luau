--!strict
--[[ SAFE-AREA INSET DERIVATION — the pure half of the platform adapter's
	`GuiService:GetInsetArea` handling (PLAT-3, 2026-08-17).

	`src/client/roblox_env.luau` is the one file allowed to read the engine's
	inset services, and until this module existed the arithmetic that turns an
	engine rect into four edge insets lived inside it — which meant the two
	things most worth proving about that arithmetic (the space conversion, and
	whether the answer can be trusted at all) could only be proved on a device.
	Nothing here touches an engine type: the caller unpacks the `Rect` and the
	`Vector2` at the seam, and this decides what they mean.

	THE SPACE CONVERSION. `GetInsetArea` answers in the SAME inset-subtracted
	space `AbsolutePosition` uses — measured on desktop, the `CoreUISafeInsets`
	rect reads (0,0)->(w, h-58) while the window is h tall — so window-space edge
	distances come from adding the legacy `GetGuiInset()` top offset back before
	subtracting.

	THE BELT. `Camera.ViewportSize` and `GetInsetArea` update on DIFFERENT
	frames, so one pass can convert an inset measured against the OLD viewport
	using the NEW one. Measured (`src/env/environment.luau:354`, the shipped
	repro): a topbar-safe area of y 0..58 on an 852-tall portrait window stores
	`bottom = 794`; read against a 393-tall landscape window that inset alone is
	twice the screen. `describesViewport` is that test — an edge pair that cannot
	fit inside the viewport it is being published beside did not come from that
	viewport — and the caller discards rather than publishes, so the last good
	value stands until the next platform event.
]]

local safe_insets = {}

export type Insets = { top: number, bottom: number, left: number, right: number }
export type Area = { minX: number, minY: number, maxX: number, maxY: number }
export type Viewport = { w: number, h: number }
export type GuiInset = { x: number, y: number }

-- engine area (inset-subtracted space) -> window-space edge insets
function safe_insets.fromArea(area: Area, guiInset: GuiInset, viewport: Viewport): Insets
	local ox, oy = guiInset.x, guiInset.y
	return {
		top = math.max(0, area.minY + oy),
		left = math.max(0, area.minX + ox),
		right = math.max(0, viewport.w - (area.maxX + ox)),
		bottom = math.max(0, viewport.h - (area.maxY + oy)),
	}
end

-- could this inset have been measured on THIS viewport? Opposite edges that
-- together meet or exceed the viewport describe no content box at all.
function safe_insets.describesViewport(inset: Insets, viewport: Viewport): boolean
	return inset.top + inset.bottom < viewport.h and inset.left + inset.right < viewport.w
end

return safe_insets
