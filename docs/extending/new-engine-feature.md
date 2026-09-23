# Adopting an engine feature

Read the actual engine contract and identify who owns the feature. Native class construction, property bindings, events and observation use the Compose Roblox host. Facet adds only control-specific policy around those capabilities.

1. Build the smallest native use through Host constructors and Compose ownership.
2. Check that the existing control can expose the capability through ordinary native properties or a narrow behavioral option.
3. If host support is missing, reproduce it upstream in Compose; synchronize the pinned snapshot after the upstream change.
4. Add behavior and native-engine tests, then exercise the actual gallery screen in Studio.
5. Document the supported contract and hard limits. Rebuild/check the distributable.

Do not reproduce a newly available engine layout, text editor, scroll container, selection mechanism, input transport or drag detector in Luau. Delete replaced code and its unreachable wrappers as part of the change. Keep deterministic control policy tests, but replace obsolete implementation assertions with observable behavior.

The Compose snapshot is generated and read-only. Vendor integrity verification must pass unchanged after a Facet-only change.
