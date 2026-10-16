# Outline.onActivate

Table puts disclosure and indentation in its first column and sorts each set
of siblings independently. Expansion does not change other column alignment.

`onActivate` handles opening a folder or a file. Desktop uses double-click;
touch and gamepad use activation outside Edit mode. Without `onActivate`, an
Outline activation toggles a folder. Use NavigationStack for entering a folder
with Back; that navigation is separate from expanding rows in place.
Native button activation supplies the click count. When a UIDragDetector captures
a frame cell, Facet recognizes a second tap on the same cell within half a second
and six pixels; dragging or cancelling resets that sequence.

For hierarchy reordering, `onReorder(keys, siblingSlot, parentKey)` reports a
zero-based slot among remaining siblings and their parent (`nil` at the root).
Only keys with the same parent can reorder together. Invalid insertion points
are rejected. To move into another folder, compose `UI.dropTarget` on that
folder's cell. The model validates cycles, permissions and descendant changes.
