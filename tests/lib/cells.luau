--!strict
local Compose = require("../../src/vendor/compose/core")
local Nav = require("../../src/ui/navigation_types")
local cells = {}
function cells.optionalString(value: string?): Compose.Cell<string?>
	return Compose.cell(value)
end
function cells.axis(value: "x" | "y"): Compose.Cell<"x" | "y">
	return Compose.cell(value)
end
function cells.indicator(value: Nav.Indicator?): Compose.Cell<Nav.Indicator?>
	return Compose.cell(value)
end
function cells.placement(value: Nav.Placement): Compose.Cell<Nav.Placement>
	return Compose.cell(value)
end
function cells.sidebar(value: "automatic" | "sidebar" | "topBar"): Compose.Cell<"automatic" | "sidebar" | "topBar">
	return Compose.cell(value)
end
function cells.collectionStatus(): Compose.Cell<Compose.OrderedCollectionStatus>
	local value: Compose.OrderedCollectionStatus = {
		mode = "windowed",
		direction = "vertical",
		total = 0,
		retained = 0,
		first = 0,
		last = 0,
		firstRow = 0,
		lastRow = 0,
		rowCount = 0,
		extent = 0,
		following = false,
		measured = 0,
	}
	return Compose.cell(value)
end
function cells.overscan(
	value: ("none" | { top: number, left: number, bottom: number, right: number })?
): Compose.Cell<("none" | { top: number, left: number, bottom: number, right: number })?>
	return Compose.cell(value)
end
function cells.emptyCollectionStatus(): Compose.Cell<Compose.OrderedCollectionStatus?>
	local value: Compose.OrderedCollectionStatus? = nil
	return Compose.cell(value)
end
function cells.sort(
	value: { column: string, direction: "ascending" | "descending" }?
): Compose.Cell<{ column: string, direction: "ascending" | "descending" }?>
	return Compose.cell(value)
end
function cells.presence(
	value: ("away" | "busy" | "inExperience" | "offline" | "online")?
): Compose.Cell<("away" | "busy" | "inExperience" | "offline" | "online")?>
	return Compose.cell(value)
end
return cells
