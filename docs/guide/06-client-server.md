# Client and server

Keep domain authority on the server. The client presents replicated facts and requests commands. Validate identity, authorization, prices, inventory and rate limits at the server boundary regardless of which control sent the request.

Separate the confirmed value from an in-progress edit and command status. A pending request is visible but has not succeeded. Correlate each response to the request that produced it so a stale response cannot overwrite a newer edit.

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
    return Host.Frame {
        Host.UIListLayout { Padding = UDim.new(0, 8) },
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
        UI.Label { label = errorMessage },
    }
end
```

`request` and `reply` above are game-owned RemoteEvents; the server resolves the product id from its own catalog. Production code should also time out lost responses and keep durable pending state outside a screen when requests may survive navigation.

Optimistic editing needs a defined rejection path. Retain the last confirmed model, display pending state, and reconcile from the server response. Do not grant inventory or currency because a button animation completed.

The reference applications demonstrate deterministic command state machines, seeded catalogs and rejection fixtures. Their clocks and mock services stay in the examples; they are not Facet infrastructure.
