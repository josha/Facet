# Tasks.purchase

Keep purchase requests pending until the server accepts or rejects them.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local app = Facet.app({})
local UI = app.UI
type PurchaseResult = { accepted: boolean, message: string }
local buy = assert(game.ReplicatedStorage:FindFirstChild("Purchase")) :: RemoteFunction
app.mount(function()
  local active = true
  C.cleanup(function() active = false end)
  local pending, owned, result = C.cell(false), C.cell(false), C.cell("")
  return UI.VStack "Purchase" {
    UI.Text { text = result, wrap = true },
    UI.Button "Buy" { label = "Buy",
      enabled = function(use: Facet.Use) return not use(pending) and not use(owned) end,
      onActivate = function()
        if pending:peek() or owned:peek() then return end
        pending:set(true)
        result:set("Purchasing…")
        local ok, reply = pcall(function(): PurchaseResult return buy:InvokeServer("item-id") end)
        if not active then return end
        pending:set(false)
        if ok then
          owned:set(reply.accepted)
          result:set(reply.message)
        else
          result:set("Purchase failed. Try again.")
        end
      end },
  }
end)
```

The game supplies `Purchase`. The server validates the item, current price,
balance and ownership, then returns `PurchaseResult`. `message` is localized
by the game and explains acceptance or the rejection reason. Use the item's stable
ID. Show its price and missing funds beside Buy. Keep Buy enabled when the
displayed balance is low; let the server return the result. Do not spend local
coins or grant ownership before acceptance. Update the wallet from server state.

Use this action policy in [Tasks.collection-detail](Tasks.collection-detail.md). Keep pending and accepted
state in the item model, outside recycled rows. Block duplicate requests for
the same item. Localize labels and transport failures. The game owns the request;
the disposed mount ignores its response.
