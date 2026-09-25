# Adopting an engine feature

Read the actual engine contract. Identify who owns the feature. Native class
construction, property bindings, events and observation use the Compose Roblox
host. Facet adds only control-specific policy around those capabilities.

1. Build the smallest native use with Host constructors and Compose ownership.
2. Check whether the existing control can expose the capability through
   ordinary native properties or a narrow behavioral option.
3. If the host support is missing, reproduce the problem upstream in Compose.
   After the upstream change, synchronize the pinned snapshot.
4. Add behavior tests and native-engine tests. Then exercise the actual gallery
   screen in Studio.
5. Document the supported contract and the hard limits. Rebuild and check the
   distributable.

Do not reproduce a new engine layout, text editor, scroll container, selection
mechanism, input transport or drag detector in Luau. In the same change, delete
the replaced code and its unreachable wrappers. Keep the deterministic control
policy tests. Replace obsolete implementation assertions with observable
behavior.

The Compose snapshot is generated and read-only. After a change to Facet only,
the vendor integrity verification must pass without changes.
