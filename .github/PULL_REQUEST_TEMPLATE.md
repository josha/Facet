# What changed

<!-- One or two sentences. What does this do, and why is it the right change? -->

## Verification

<!-- Which tier did you run, and what did it say? Paste the result line. An
     affected or fast run is not full evidence; say which one you ran. -->

- Tier run: <!-- affected | fast | full -->
- Result line:

```
```

- [ ] `stylua --check src tests tools bench examples` passes
- [ ] A covering spec was written first, and was seen to fail before the fix

## Documentation

- [ ] New or changed public properties are in `docs/reference/api.md`
- [ ] A new capability is in the catalog in `docs/guide/README.md`
- [ ] A change to what the library promises has a `CHANGELOG.md` entry saying what was chosen and what was rejected
- [ ] Not applicable

## Consumer impact

<!-- Does this change behavior a game already depends on? Name it here, in the
     words a consumer would use. If a public surface is retiring, say which
     entry in `Facet.DEPRECATIONS` covers it. -->

- [ ] No behavior change for existing consumers
- [ ] Behavior changes; described above
- [ ] Both install routes still work: a Rojo checkout, and the model or Package
      inserted into Studio with no toolchain
