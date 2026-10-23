# Adaptive manipulation

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

Define the operation first: move, copy, apply, reorder, resize or adjust.
Keep identity, eligibility and accepted result common across inputs. Let touch,
pointer and gamepad use appropriate targeting and feedback.

Use the owning Facet behavior rather than adding a second drag system.
Collections provide drag, drop and rowDrop. Use a separate dropTarget only
for a distinct subtarget. Custom adjusters can use adjustable; spatial command
navigation can use commandScope. Read their API nodes before implementation.

## Avoid competing gestures

Touch pickup must coexist with scrolling. Choose a handle, long press or
deliberate manipulation mode when intentions conflict. Keep the held object
visible above the finger. Pointer movement should track directly, not ease
behind the cursor.

Give gamepad an explicit pickup, destination, commit and cancel path or an
equivalent command. Collection onActivate can take precedence over pickup
outside Edit mode; adding drag alone does not make one activation do both.

Inspection input belongs to its preview. A press that opens or buys an object
must not also zoom or rotate its camera.
Keep spatial bounds and scale stable as content appears. Reveal an offscreen
selection only as needed; do not recenter the view on every selection.

## Validate the destination

Show source identity, candidate destination and rejection reasons. accepts
checks eligibility during targeting and release; it must not mutate records
or spend resources. A rejected visible target should not silently pass a
destructive action to something behind it. World targets need a reachable
focusTarget for non-pointer placement.

For pending drops, call info.complete(true) before changing the presentation
model, and apply that change only if it returns true. Complete refusal with
info.complete(false, reason). Canceled or late completion cannot commit the
same UI operation twice. Reconcile durable server results independently.

The built-in drag feedback uses Travel. Preserve a return destination where
needed instead of creating unrelated copies of the carried object.

Test valid, invalid, occupied and disappearing targets; scrolling and recycling;
cancel; pending acceptance and rejection; and the alternative command route.
Dragging must not also activate the source.
