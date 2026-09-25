# Client and server

Keep domain authority on the server. The client shows replicated facts and
requests commands. At the server boundary, validate identity, authorization,
prices, inventory and rate limits. Do this for every request, independent of
the control that sent it.

## Pending requests

Keep these values separate:

- the confirmed value,
- the edit in progress,
- the command status.

A pending request is visible, but it has not succeeded. Match each response to
the request that caused it. Then a stale response cannot overwrite a newer edit.

```luau
local balance = Compose.cell(0)
local pending = Compose.cell(false)
local errorMessage = Compose.cell("")
local sequence = 0
local latest = 0

local function Purchase()
    runtime.connect(reply, "OnClientEvent", function(requestId, response)
        if requestId ~= latest then return end
        pending:set(false)
        if response.ok then
            balance:set(response.balance)
            errorMessage:set("")
        else
            errorMessage:set(response.message)
        end
    end)
    return UI.VStack {
        gap = "s",
        UI.Button {
            label = "Purchase",
            busy = pending,
            onActivate = function()
                sequence += 1
                latest = sequence
                pending:set(true)
                request:FireServer(latest, productId)
            end,
        },
        UI.Label { text = errorMessage },
    }
end
```

`request` and `reply` in this example are RemoteEvents that the game owns. The
server finds the product id in its own catalog.

Production code must also time out lost responses. If a request can survive
navigation, keep its durable pending state outside the screen.

## Optimistic edits

An optimistic edit needs a defined rejection path:

1. Keep the last confirmed model.
2. Show the pending state.
3. Reconcile the model from the server response.

Do not grant inventory or currency because a button animation completed.

## Reference applications

The reference applications show deterministic command state machines, seeded
catalogs and rejection fixtures. Their clocks and mock services stay in the
examples. They are not Facet infrastructure.
