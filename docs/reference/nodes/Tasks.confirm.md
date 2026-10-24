# Tasks.confirm

Confirm a purchase and keep the Dialog open until the server answers.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local app = Facet.app({})
local UI = app.UI
type Reply = { accepted: boolean, message: string }
local buy = assert(game.ReplicatedStorage:FindFirstChild("Purchase")) :: RemoteFunction
app.mount(function()
  local open, busy, refusal = C.cell(true), C.cell(false), C.cell("")
  local actions: { Facet.DialogAction } = {
    { id = "Cancel", label = "Cancel", role = "cancel", onActivate = function() end },
    { id = "Buy", label = "Buy for 4,800 Credits", role = "default", keepOpen = true, busy = busy,
      onActivate = function()
        busy:set(true)
        refusal:set("")
        local ok, reply = pcall(function(): Reply return buy:InvokeServer("ion-thruster") end)
        busy:set(false)
        if ok and reply.accepted then
          open:set(false)
        else
          refusal:set(if ok then reply.message else "Purchase failed. Try again.")
        end
      end },
  }
  return UI.Dialog "Confirm" {
    isPresented = open, title = "Buy Ion Thruster?", actions = actions,
    onPresentedChange = function(value) if not busy:peek() then open:set(value) end end,
    content = function()
      return UI.VStack "Terms" { gap = "s",
        UI.Text { text = "4,800 Credits", textRole = "numeral" },
        UI.Text { text = "Balance after: 7,650 Credits", role = "secondary" },
        C.show(function(use) return use(refusal) ~= "" end, function()
          return UI.Notice { message = refusal, severity = "error" }
        end),
      }
    end,
  }
end)
```

Show the price, the gain and the balance after. The `default` role gives Buy
the emphasis and Return. `keepOpen` and `busy` hold the Dialog until the server
answers; a refusal stays as an error Notice. Alert suits a choice with no server
reply. See [purchase state](Tasks.purchase.md).
