# Reserved collection slots

A player places a rack tile on the board. The rack must keep its empty slot.
Recall must land at that slot. Play can release the slot and reflow the rack.
The consumer owns the item list and the ordered slot keys. No blank item is
needed in that list.

Add slots to VirtualList and VirtualGrid. It is an optional readable array of
unique item keys. A missing key is a reserved recess. An item with that key
uses that slot even when it returns at the end of from. Items not in slots
follow the reserved slots in source order. Remove a key from slots to release
its reservation. The ordinary API and compact layout remain the default.

UIGridLayout and UIListLayout arrange native children but do not reserve a
missing key. Compose.OrderedCollection already owns keyed retention, placement,
windowing and extent. Feed it Facet slot records and use Compose.show to mount
real item content or a recess. Do not change Compose or create a layout engine.
Use the shared travel engine and theme travel spring for reflow. The collection
drop target supplies a landing rectangle for a carried reserved key. It uses
LayoutUnit and CanvasPosition so zoom and scroll use drawn screen geometry.

Keep the existing pointer, touch and armed transfer session. A reserved recess
is not selectable. Returning the same key uses its reservation. Other drops
keep insertion policy. First fail a case that removes a middle item and keeps
the next item at its slot. Then check recall, release, windowed extent, sampled
reflow and travel landing. Extend the board-and-rack Lab and native live suite.
