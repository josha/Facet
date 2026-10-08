# Travel lifetime

Player task: move an item between cells while a collection replaces or removes
its cells. A removed item must stop drawing and must release its frame work.

Keep the public Travel slot API. The lifetime ends when its Compose owner,
content, anchor or current destination ends. A destroyed destination cancels
Travel. A later slot request cannot restart a destroyed carrier. The consumer
keeps a slot mounted for an item that must remain available.

Roblox Instance.Destroying reports destruction. Deferred signals can run after
destruction; Parent can already be nil. GuiObject.Parent has no destroyed flag,
and assigning Parent after Destroy fails. Check the carrier before each frame.
Compose Owner.createChild, withOwner, cleanup and runtime.connect supply the
lifetime and connection ownership. Use one child owner for each Travel. The
shared motion engine releases dead leases before it reads or paints them.

Proof: replace two VirtualGrid target keys, retarget, then remove the cells
while motion is active. Also destroy a carrier directly. Sample later frames:
no callback paints it, no Parent assignment occurs, and disposal releases the
clock. Run the same actions in the Lab with native immediate and deferred
signals. Keep the old error as the negative native result.
