# Third-party notices — DRAFT

> ## SUPERSEDED IN PART — read this first
>
> This draft was written against the audit baseline `27c0afd`, where the repository had **no**
> root `LICENSE` and **no** `THIRD_PARTY_NOTICES.md`. While the audit was running, the owner
> committed both locally (unpushed, `27c0afd..17ae422`):
>
> - `LICENSE` — MIT, `Copyright (c) 2026 Josh Anon`
> - `THIRD_PARTY_NOTICES.md` — 15,410 bytes, with sections for Facet's own art, SCOWL, and the
>   toolchain. **Its SCOWL section already carries the full verbatim `Copyright` block, UKACD
>   clause included** — verified. §2 of this draft is therefore already satisfied and needs no action.
>
> **What is still worth taking from this draft:**
>
> | Section | Status against the shipped `THIRD_PARTY_NOTICES.md` |
> |---|---|
> | §1 Fusion | **Missing from the shipped file, deliberately.** The shipped file has no Fusion section and `vendor/Fusion/` is deleted in the working tree. That is consistent and correct — *provided the deletion actually lands in the published commit*. If `vendor/Fusion/` ships after all, §1 below is the exact text required |
> | §2 SCOWL | **Already done**, verbatim. No action |
> | §3 Roblox engine fonts | Not in the shipped file; not required (nothing is redistributed). Optional completeness |
> | §4 Quoted documentation | Not in the shipped file. Optional, and less relevant now that `docs/reference/react-lua-comparison.md` and `fusion-comparison.md` are deleted in the working tree |
>
> The rest of this file is preserved as written, as the record of what the audit determined was required.

---

> **This is a draft.** Review, then publish as `THIRD_PARTY_NOTICES.md` at the repository root
> alongside a root `LICENSE` (which the repository does not currently have — see
> `provenance-ledger.md` item 24).
>
> Two sections are conditional:
> - **§1 (Fusion)** is required only if `vendor/Fusion/` ships. If `vendor/` is dropped from the
>   public tree per the existing distribution plan, delete §1.
> - **§2 (SCOWL)** is required as long as `examples/gallery/examples/words/` ships. It almost
>   certainly does — it is the data behind two shipped examples.
>
> Sections §3 and §4 require no licence text and are included so the record is complete.

Facet is distributed under the licence in `LICENSE`. It includes or derives from the third-party
material below, each under its own terms.

---

## 1. Fusion

**Applies to:** `vendor/Fusion/`
**Upstream:** https://github.com/dphfox/Fusion, tag `v0.3-beta`
**Modifications:** `src/` copied verbatim, then patched mechanically — `require(Package.X)` rewritten
to the Luau string-require form `require("../X")` across 54 files, plus one scheduler guard in
`init.luau` so callbacks run synchronously under Lune. No logic was changed. Details in
`vendor/Fusion/VENDOR.md`.

The following is the complete, unmodified contents of `vendor/Fusion/LICENSE`:

```
MIT License

Copyright (c) 2024 Daniel P H Fox

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 2. SCOWL — Spell Checker Oriented Word Lists

**Applies to:** the generated English word data in `examples/gallery/examples/words/`
(`len2.luau` … `len7.luau`, `solutions.luau`, `manifest.luau`), used by the word game and the
crossword tile game.

**Source:** SCOWL 2020.12.07 — http://wordlist.aspell.net/
**Archive:** `https://downloads.sourceforge.net/project/wordlist/SCOWL/2020.12.07/scowl-2020.12.07.tar.gz`
**Archive SHA-256:** `5587667caa20c4891390c2d42dbb4d5c4c3f41bee77af1457ece3ba23fb859cc`
**Relationship:** the archive is not redistributed. `tools/build_word_lists.py` downloads it on
demand, verifies it against the pinned SHA-256, and generates the word tables that ship. SCOWL's
licence expressly permits distributing "the output created from the scripts" provided these
notices accompany the copies.

### The required notice

> **ACTION FOR WHOEVER PUBLISHES THIS FILE:** copy the fenced block from
> `examples/gallery/examples/words/PROVENANCE.md` — **lines 92 through 341, byte for byte** — into
> the space below. Do not retype it, do not reflow it, and do not abridge it. It is ~250 lines.
> It is already correct in the repository; the only job here is to mirror it so a reader who never
> opens the word-game example still sees it.
>
> ```sh
> sed -n '92,341p' examples/gallery/examples/words/PROVENANCE.md
> ```

<!-- PASTE THE FULL SCOWL COPYRIGHT BLOCK HERE, VERBATIM, lines 92-341 -->

The block opens with Kevin Atkinson's collective-work notice:

```
The collective work is Copyright 2000-2018 by Kevin Atkinson as well
as any of the copyrights mentioned below:

  Copyright 2000-2018 by Kevin Atkinson

  Permission to use, copy, modify, distribute and sell these word
  lists, the associated scripts, the output created from the scripts,
  and its documentation for any purpose is hereby granted without fee,
  provided that the above copyright notice appears in all copies and
  that both that copyright notice and this permission notice appear in
  supporting documentation. Kevin Atkinson makes no representations
  about the suitability of this array for any purpose. It is provided
  "as is" without express or implied warranty.
```

and it goes on to carry the notices of the component word lists: 12dicts and ENABLE (Alan Beale),
Moby (Grady Ward, public domain), Brian Kelk's wordlist (public domain), WordNet 1.6
(Princeton University), UKACD (J Ross Beresford) and VarCon (Kevin Atkinson, Benjamin Titze,
Geoff Kuenning).

**One component imposes a stricter condition than the rest, and it is the reason the block must
never be abridged:**

```
UKACD, by J Ross Beresford <ross@bryson.demon.co.uk>, is under the
following copyright:

  Copyright (c) J Ross Beresford 1993-1999. All Rights Reserved.

  The following restriction is placed on the use of this publication:
  if The UK Advanced Cryptics Dictionary is used in a software package
  or redistributed in any form, the copyright notice must be
  prominently displayed and the text of this document must be included
  verbatim.

  There are no other restrictions: I would like to see the list
  distributed as widely as possible.
```

---

## 3. Roblox engine fonts

**Applies to:** nothing distributed. Facet references fonts as
`rbxasset://fonts/families/{Fondamento,Michroma,Nunito,BuilderSans}.json`, which resolve inside the
Roblox client. No font file is included in this repository, so no font licence obligation attaches
to it. Fondamento, Michroma and Nunito are Google Fonts (SIL Open Font License) shipped by the
Roblox client; BuilderSans is Roblox's own. `[VERIFY]` — the per-family licensing above is stated
for the reader's benefit and was not verified against Roblox's font manifest during this audit; it
does not affect Facet's obligations, which are none.

---

## 4. Quoted documentation

**Applies to:** `docs/reference/swiftui-parity.md`, `docs/reference/react-lua-comparison.md`, and
related comparison documents.

These cite Apple's developer documentation, Human Interface Guidelines and WWDC sessions, and the
React-Lua / Roact / Vide documentation, in short attributed quotations with live links and access
dates, for the purpose of comparing Facet's behavior against them. No third-party source code is
reproduced. Apple, SwiftUI, WWDC, React and Roblox are trademarks of their respective owners, and
Facet is not affiliated with, endorsed by, or sponsored by any of them.

---

## Items deliberately not listed

- **`assets/icons/`** and all six theme packages under **`assets/themes/`** are original work,
  generated by scripts in this repository (`generate_icons.py`, `generate_art.py`) from recorded
  seeds. They carry no external claims and need no notice.
- **`examples/places/*.rbxl`** are built by `rojo build` from this repository's own source. `[VERIFY]`
  — if these ship, confirm by rebuild-diff that no third-party asset was added by hand in Studio;
  the `.rbxl` format is LZ4-chunk-compressed, so byte inspection cannot settle it.
- **Screen captures of the Roblox mobile app** under `docs/plans/reference-media/` are **not**
  listed here because they must not ship at all. There is no notice that permits redistributing
  another company's application UI. See `provenance-ledger.md` item 18.
