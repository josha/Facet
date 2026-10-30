# Tasks.sheet

Open a task over play and return to its source. Keep the HUD mounted as a
sibling of the Sheet when it should stay visible behind the modal.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI
local open, captions = C.cell(false), C.cell(true)
app.mount(function()
  return UI.Screen "Root" {
    UI.Button { label = "Audio options", onActivate = function() open:set(true) end },
    UI.Sheet {
      title = "Audio options", isPresented = open,
      placement = "center", detents = { "hug" },
      content = function()
        return UI.VStack "Options" { width = "fill", gap = "s",
          UI.Text { text = "Show captions for spoken dialogue.", wrap = true },
          UI.Toggle { label = "Dialogue captions", value = captions },
        }
      end,
    },
  }
end)
script.Destroying:Connect(app.dispose)
```

The game applies the value. Close returns to the opener. Leave closeButton
absent so the exit follows placement. Test exit and focus return with each input.

Use [pages](Tasks.pages.md) when a destination intentionally replaces play,
[Popover](Popover.card.md) for an anchored choice, or DisclosureGroup for
optional inline facts. A short task hugs its content; a large collection needs
a bounded viewport. NavigationStack fills its viewport and cannot hug. For a task with child
steps, put the stack inside a bounded Sheet, with the opened task as root.
The root has Close and no Back. Push or replace in one path update; do not
pop to gameplay and defer opening the next step. See the
[game screen recipe](../../../skills/use-facet/references/game-screens.md).

Content runs at construction. Use [Compose branches](State.md) for changing
content. Apply [Sheet.dismissal](Sheet.dismissal.md) to every dirty exit.
Keep pending work open until acceptance; preserve rejected drafts.
Modals hide native touch controls and restore them on exit. The game owns
custom touch actions and gameplay input.
