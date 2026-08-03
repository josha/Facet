# Baseline — `traversal-document-order`

- `test-before.json` — the library suite at stage start: **3079 passed**.
- `prior-gates-step8.txt` — Step 8's own in-tree prior-gates roll-up, copied verbatim.
- `prior-gates-before.txt` — the baseline this stage's `prior-gates-unregressed`
  check compares against: Step 8's roll-up (16 PASS) **plus `desktop-keyboard-navigation`
  itself**, which is a prior for this stage and which was measured at the
  unmodified pre-change source.

**It is recorded as FAIL, because that is what it did.** Running
`tools/gate.sh desktop-keyboard-navigation` before touching anything returned
`FAIL_RECOVERABLE` on two checks — one grepping a test that had been renamed, one
running a game test that asserted a pre-Step-8 world. Both are diagnosed in
`../decisions.md` TDN-5 and fixed in `../step8-debt.md`. Writing `PASS` here
because the stage is *recorded* as having passed would have made the
regression comparison compare against a fiction.
