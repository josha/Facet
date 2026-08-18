# D0.2 — every manifest suite grep replayed against a live green transcript

Produced by `tools/check_manifest_integrity.py --transcript`. Anchoring is a
syntactic property; this is the semantic one. A renamed spec case leaves its grep
perfectly anchored and matching nothing, which is how two consecutive stages found
a rename by hand instead of in the commit that caused it.

- suite greps discovered: **1485** (facet 1378, rascalrally 107)
- matched a line in a green transcript: **1485**
- negated (`grep -v`), not match-checked: **0**
- matching ZERO lines: **0**

Patterns are routed to the transcript their own capture came from, positionally —
a check may capture `$out` from the Facet suite and only then `cd` into Rascal
Rally. Mis-routing all 65 Rascal Rally patterns to the Facet transcript reports 63
false positives, which is the measurement error the round's brief itself made.
