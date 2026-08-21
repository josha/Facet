# Clear technical writing — the automated half

**What this file records:** the checker `tools/check_doc_style.py`, what it
enforces and what it deliberately only warns about, its negative control, and the
violations it found and closed on the live tree.

The plan's writing standard is ASD-STE100-inspired. This is a clarity standard,
not a claim of formal certification, and most of it is a human judgement. This
checker owns the parts that are mechanical.

## Scope

`docs/guide/**.md` and `docs/extending/**.md` — 21 documents, every one a Roblox
developer is expected to read.

Before any rule looks at a line, fenced code blocks become empty, inline code
spans become one token, `<kbd>` keys become one token, a link becomes its label,
a bare URL becomes one token, an HTML comment is dropped, and emphasis markers
are removed. That is why no rule can reject an API name, a Roblox class name, a
path, a command or a table of them.

## What FAILS

| Rule | What it catches |
|---|---|
| One instruction per step | a numbered step over 20 words is carrying more than one |
| No unexplained acronym | an acronym in `NEEDS_EXPANSION` used before the document expands it |
| No internal shorthand | a bare artifact row, phase or finding code (`TP-A12`, `SF-D3`, `M8`) |

The acronym glossary is maintained in the checker, in two halves. `COMMON` is
ordinary technical English for a Roblox developer and needs no expansion.
`NEEDS_EXPANSION` is what this repository uses that a new reader will not know,
each mapped to the words it stands for; the checker accepts either
`Words (ACRONYM)` or `ACRONYM (Words)`, matched across line breaks so a correctly
wrapped sentence is not failed for its width.

`SHORTHAND_ALLOW` names the tokens that look like a row id and are not — gamepad
shoulder buttons and triggers, keyboard function keys, a display-resolution class
in the device matrix, `ADR`. Each entry carries its reason; an entry without one
would be a hole rather than an allowlist.

## What only WARNS

A sentence over 25 words, and a likely passive construction. Both misjudge real
technical prose often enough that failing on them would teach people to route
around the checker. They print with `--warnings` and never change the exit code.
The live tree reports 381 of them, which is a backlog for a human editing pass
and not a gate.

## The negative control

`python3 tools/check_doc_style.py --selftest` writes a scratch document into
`docs/guide/`, once per FAIL rule, requires each violation to be reported by
name, deletes it, and then requires the restored tree to be clean.

```
check_doc_style: SELFTEST PASS — an over-long numbered step, an unexpanded
acronym and a bare artifact row id were each reported; the restored tree is clean
(381 warnings, which never fail)
```

## What it found, and what closing it changed

The first run on the live tree reported **36 violations across 12 documents**.
All 36 are closed.

| Class | Count | How it was closed |
|---|---|---|
| bare artifact row id | 21 | replaced by the fact, or by the artifact path alone |
| unexpanded acronym | 9 | expanded at first use (IAS, CAS, MCP, VM, REPL, CDN, GA) |
| over-long numbered step | 0 | the guide already kept steps short |

Examples of the rewrite: `E1`/`E3`/`E4` in the evidence-class table became
`headless`, `Studio` and `device`, which is what those codes meant;
`(artifacts/…/review-packet.md, TP-P1–TP-P4)` became the path alone, because the
path is what a reader can open and the row ids are private; "closes PL-P1/PL-P2"
became "closes the two open device rows in the lab's review packet".

```
check_doc_style: PASS — 21 documents; no over-long instruction step, no
unexpanded acronym, no internal shorthand (381 warnings, reported with
--warnings and never fatal)
```

## What this does NOT prove

The plan also requires a fresh Roblox author and a fresh agent to each complete a
small task from the public documents alone, and to explain the relevant concept.
Neither exercise ran in this wave. Acceptance row **RC-17 stays PENDING** and is
owned by the fresh-reader wave; nothing in this file may be read as closing it.
