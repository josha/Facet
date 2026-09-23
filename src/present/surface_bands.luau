--!strict
--[[ THE FIVE-LAYER SURFACE ORDER (ui-designer spec §6.3). BANDS, not one
	running counter: a toast has to sit above every base screen and below every
	modal regardless of the order they were presented in, which a single
	monotonic counter cannot express. Within a band, creation order still
	decides (each surface takes the next +100 step), so ~100 live surfaces per
	band before two would tie — far past anything real.

	THE SNACKBAR STRIP is the toast band's first step: above every base screen
	and every passive toast. A NON-MODAL OVERLAY that explains or points at base
	content (a Callout, a passive Popover, a help, disclosure or reveal plate)
	must read over that strip, so its base-band order is carried, step for
	step, to just above it; modals keep their own band above all of these. ]]
local surface_bands = {}

surface_bands.LAYER = table.freeze({
	base = 10000,
	toast = 20000,
	dragProxy = 30000,
	modal = 40000,
})
local LAYER = surface_bands.LAYER

surface_bands.SNACKBAR = LAYER.toast + 100

-- a base-band display order, moved above the snackbar strip; any other band is
-- already where it belongs
function surface_bands.overlay(order: number): number
	if order >= LAYER.base and order < LAYER.toast then
		return order - LAYER.base + surface_bands.SNACKBAR
	end
	return order
end

return surface_bands
