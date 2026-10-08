# Collection touch pickup

A player must lift a rack tile after six pixels of finger movement when the
drag factory returns touchPickup immediate. A shorter contact remains a tap.
Long-press pickup remains the default. Movement across touchDragAxis belongs
to scrolling for the whole contact. One item and one policy stay captured.

Use GuiObject InputBegan, UserInputService InputChanged and InputEnded, and
GuiObject TouchLongPress. UIDragDetector owns mouse detection. The shared
Facet arbiter owns the final contact decision. Compose cleanup and the existing
ordered collection own recess, preview and insertion. No new input mechanism,
frame loop or public option is needed.

Prepare the returned DraggableSpec on touch-down and keep it for pickup.
Use its touchPickup and touchDragAxis in the arbiter. At the movement threshold,
start the existing collection transfer session and update its preview in the
same input callback. Early scrolling rejects a later long press. Long press
still starts the same session for the default policy.

First prove that eight pixels fail to start an immediate collection transfer.
Then prove threshold, frozen item, recess, slot reflow, external drop, axis
scrolling, cancellation and default long press. Include the policy in the Lab
rack and pointer live suite. Phone geometry and native detection need Studio.
