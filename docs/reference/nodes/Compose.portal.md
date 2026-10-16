# Compose.portal

Mount children into another native container while keeping their Compose owner.

`Compose.portal(target, function() return { children } end)` is a child
directive. Return a list from the builder. The target is borrowed: disposal
removes the portal's children and leaves the target standing. Use
`local Host = runtime.constructors` to create native containers.

Sheet, Dialog and Popover already own their overlay placement and modal
selection. Mount them beside the HUD Composition in Screen. Use a portal for
game-owned layers that need another parent. Do not move a control's private
backdrop or make a second modal selection scope.

Open:

- [Tasks.sheet](Tasks.sheet.md)
- [Mounting](Mounting.md)
