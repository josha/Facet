# Tasks.state

Bind HUD readouts to an initial server snapshot and later updates.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
type State = { coins: number, xp: number }
type Client = {
  getState: () -> State,
  onStateChanged: ((State) -> ()) -> (() -> ()),
}
local function mountWallet(client: Client)
  local app = Facet.app({ name = "Game" })
  local UI = app.UI
  app.mount(function()
    local env = UI.environment()
    local width = env.scaled(160)
    local state = C.cell(client.getState())
    C.cleanup(client.onStateChanged(function(nextState: State) state:set(nextState) end))
    state:set(client.getState())
    return UI.VStack "Wallet" { surface = "panel", padding = "s",
      UI.Text { text = function(use: Facet.Use) return `{use(state).coins} Coins` end },
      UI.ProgressView { label = "XP", max = 100,
        value = function(use: Facet.Use) return use(state).xp end,
        Size = function(use: Facet.Use): UDim2 return UDim2.fromOffset(use(width), 0) end },
    }
  end)
  return app
end
local snapshot: Facet.Value<State> = C.cell({ coins = 300, xp = 40 })
mountWallet({
  getState = function() return snapshot:peek() end,
  onStateChanged = function(changed)
    return C.watch(function(use) changed(use(snapshot)) end)
  end,
})
```

The cell demonstrates the client adapter. `getState()` returns the current
server snapshot without yielding. `onStateChanged()` reports each new snapshot
in a new table and returns a disconnect function. For a native connection, return
`function() connection:Disconnect() end`; do not give `C.cleanup` an
`RBXScriptConnection`. Subscribe before reading the snapshot again so mounting
does not miss an update. Compose disconnects when the mount ends.
The game owns the XP limit and all other game rules. Apply this state pattern
to the readouts in [Tasks.hud](Tasks.hud.md); keep one HUD Composition.
Localize the sample labels with the game's translator.
