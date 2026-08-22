# D0.1 — the sweep suite cache, with every guard broken on purpose

Produced by `tools/suite_cache_selftest.sh`. A cache is exactly the shape that
turns a real check into one that cannot fail, so each guard below is asserted by
breaking it: the assertions are run against synthetic caches whose transcript is
red, failing, truncated, empty, fast-tier, or mutated after the fact.

- assertions passed: **28**
- assertions failed: **0**

Every refusal asserts BOTH a non-zero exit (which reddens FORM A's `&&` chain)
and empty stdout (which reddens a FORM B pipeline, whose exit status is grep's
and not the helper's).
