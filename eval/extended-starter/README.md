# Extended game contract

This directory holds only the extended contract additions. Run `lute run tools/facet facetbench prepare` to derive `artifacts/facetbench/extended-starter` from the racing-hub starter, these two modules, and `admin.patch`. The patch adds the `extended` branch to the existing server admin hook. The full derived contract lets the existing contract check compare the server and shared trees. The livery turn applies it over the completed scoreboard workspace. It contains no client interface.

Both arms receive the same files. The headline starter is unchanged. Later turns inherit this overlay. The model uses the base Ledger wallet. It validates livery ranges and decal choices, vote deadlines, chat presets and cooldowns, upgrade costs and levels, and invite eligibility. State changes use RemoteEvents. The fake friend replies are fixed game data.

The public client is `require(ReplicatedStorage.Shared.Extended).client()`. It supplies `get()`, `request(action, value)`, `onChanged(callback)`, and `now()`. Each result is `{ ok, reason?, state }`. Each turn's brief describes its fields and requests. The existing admin hook accepts `extended` with `{ command, args? }`. Commands are `state`, `reset`, `ballot`, `votes`, and `finish`. These commands are for hidden checks. They are not player actions.
