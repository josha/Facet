# Guide links to paste — `docs/guide/14-choosing-a-ui-library.md`

Workstream E2 owns the new chapter and does **not** edit `README.md` or
`docs/guide/README.md`. The two lines below are the exact markdown another agent
pastes into those two files. Paste them verbatim; both were written in the table
style each file already uses, and both were checked against
`python3 tools/check_doc_style.py` in the shape they will land in.

## 1. `docs/guide/README.md`

Add as the last row of the **Reading order** table, directly after the
`13-theme-catalog.md` row:

```
| [`14-choosing-a-ui-library.md`](14-choosing-a-ui-library.md) | Optional: how Facet compares with React Luau, Fusion and Vide, and how to choose between them. |
```

## 2. `README.md` (repository root)

Add as a row of the **Where the documentation is** table, directly after the
`docs/guide/README.md` row:

```
| [`docs/guide/14-choosing-a-ui-library.md`](docs/guide/14-choosing-a-ui-library.md) | Optional: a comparison of Facet with React Luau, Fusion and Vide, for a creator choosing a UI library. |
```

## Notes for the agent who pastes them

- The guide-index row belongs in the reading-order table, not in the capability
  catalog: the chapter ships no capability.
- Both descriptions start with "Optional" on purpose. The chapter is advisory,
  and its own opening paragraph says so.
- Neither line adds an acronym that needs expanding: `UI` is in the doc-style
  checker's `COMMON` set.
- After pasting, run `python3 tools/check_doc_style.py`; both files are in its
  scanned set.
