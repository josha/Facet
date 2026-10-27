# Composition.examples

Use different arrangements for entering a world and inspecting an object.

## Expedition base: the world is the subject

Use [Tasks.hub](Tasks.hub.md) at the root of [Tasks.pages](Tasks.pages.md).
Call both helpers inside `app.mount`. The example command must be bound by the
game. Read the current expedition and accepted equipment from the game model.

```luau
return pages(app, "Expedition tasks", function(openTasks)
  return hub(app, "North ridge", "Weather clear · Field pack equipped",
    "Begin expedition", beginAction, requestDeparture, openTasks)
end, tasks)
```

Frame the actual ridge, campsite and equipped character in the world camera.
Leave the center open. Use small opaque plates under text, not one opaque
full-screen plate. A command requests departure; the server accepts it before
travel begins. Put all other routes in the tasks destination. Do not turn each
route into an equally large button on the launch screen.

On a phone, the compact identity retains the location and accepted equipment;
the action moves into thumb reach. On controller, bind the same request to the
shown InputAction and use normal navigation focus for Tasks and settings.
Disable the game InputContext while a page or modal owns input.

## Specimen workbench: the selected object is the subject

Use [Tasks.inspect](Tasks.inspect.md) inside the task body. This composition
fills the available art pane. It does not reuse the lobby's corner arrangement.

```luau
return inspect(app, function()
  return UI.Stage "Specimen" {
    Size = UDim2.fromScale(1, 1),
    camera = CFrame.lookAt(Vector3.new(0, 2, 6), Vector3.new(0, 0, 0)),
    fieldOfView = 35,
    content = function(runtime, world)
      specimenModel(runtime, world, selected)
      return nil
    end,
  }
end, specimenFields, "Basalt specimen", "Record this specimen in your journal",
  "Record specimen", requestRecord)
```

This camera fits a roughly two-stud specimen centered at the origin. Fit it to
your subject and test the shortest art pane. `specimenModel` uses the same model
key and shape data as the world object. The helper binds Host-created parts to the readable selection and parents
them with `Facet.Compose.static(world)`. See [Stage](Stage.reference.md). Bind title,
facts and command to that same selected record. Do not show one object's art
beside another object's accepted equipment or price.

Art is first, identity and the decision are second, optional facts are third.
This inspector gives art twice the flexible space of facts. Only facts scroll;
the name, terms and action stay visible. Use this allocation while those fixed
regions fit. With large text or less room, let the complete decision scroll
instead of hiding content behind pinned controls. A bright paper surface and dark type
can suit a workbench; the palette is optional. [Theme](Tasks.theme.md) defines
paint and type, not the subject or layout. Use one Stage for the focal object;
use images or simple cards for the collection when live previews are not needed.

On a phone the panes stack without remounting the draft. On a short landscape
screen they share the remaining space after the action and terms. Controller
focus follows the fields and commitment, with Back returning to the opener.
Use [collection/detail](Tasks.collection-detail.md) when browsing needs its own
compact column. Keep selection and drafts outside the destination.

## Capture before reuse

Capture the same task wide, phone portrait, short landscape and controller with
large text. Check that the world or object is recognizable at first glance,
the next action is clear, and the name, terms and action fit. Open every route,
complete or reject an action, then return through normal input. Correct the
composition before applying it to another task. A missing or world-only capture
cannot validate a UI composition.
