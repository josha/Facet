# Facet name-collision / rights evidence check

Date: 2026-08-17
Scope: rename evidence gathering only. No judgment on whether to rename, no alternative names proposed.
Rename in question: `github.com/josha/LuauUI` → `github.com/josha/Facet` (Roblox/Luau UI framework).

---

## 1. GitHub

**Target availability**
- Query: `curl -I https://github.com/josha/Facet` (HTTP status check)
- Result: **404 — does not exist.** Target path is available.
- URL: https://github.com/josha/Facet
- Conflict relevance: none — target is free.

**Owner account sanity check**
- Query: `GET https://api.github.com/users/josha`
- Result: account `josha` exists, 3 public repos (none named LuauUI/Facet/RascalRally in the public listing — likely private or differently named).
- URL: https://github.com/josha
- Conflict relevance: n/a, informational only.

**Top ~5 prominent GitHub projects named exactly `facet`/`Facet`**
Query: GitHub Search API `q=facet in:name`, sorted by stars, filtered to exact-name matches (excludes `facets`, `myfacet`, etc.).

| Repo | Stars | Language | Purpose |
|---|---|---|---|
| [facet-rs/facet](https://github.com/facet-rs/facet) | 2,565 | Rust | Reflection / serialization / deserialization / pretty-printing framework ("the last proc macro you should need") |
| [Tim-Maes/Facet](https://github.com/Tim-Maes/Facet) | 1,205 | C# | Generates DTOs, mappings, constructors, LINQ projections from domain models |
| [BCG-X-Official/facet](https://github.com/BCG-X-Official/facet) | 533 | Jupyter/Python | Human-explainable AI toolkit |
| [kgscialdone/facet](https://github.com/kgscialdone/facet) | 452 | JavaScript | Declarative web components |
| [ncoevoet/facet](https://github.com/ncoevoet/facet) | 200 | Python | Local AI photo scoring/culling/gallery tool |

Conflict relevance: all different ecosystems (Rust, C#, Python, generic JS web components) — none are Roblox/Luau, none are UI frameworks for game engines. **Low relevance.**

**Roblox/Luau-specific GitHub search**
- Query: GitHub Search API `q=facet+roblox` and `q=facet+luau`
- Result: **[emdomanus/facet](https://github.com/emdomanus/facet)** — Luau language, description "Camera-aware 3D UI surface primitives for Roblox" (README: "turns screen-space UI regions into camera-aware 3D `SurfaceGui` planes"). 0 stars, 0 forks, 6 commits, created 2026-05-20, last pushed 2026-05-20, last repo-metadata update 2026-06-02, 0 open issues. Uses Wally + Rojo.
- URL: https://github.com/emdomanus/facet
- Conflict relevance: **exact-name, same-ecosystem (Roblox/Luau) UI-adjacent package — owner should review.** Narrow scope (world-space/3D `SurfaceGui` UI surfaces specifically, not a general 2D UI framework like LuauUI/Facet), and effectively zero adoption (0 stars/forks/issues, single-week commit history, no evidence of ongoing activity since June 2026).

---

## 2. Roblox ecosystem (DevForum, Creator Store, Wally)

**Wally package registry (wally.run / UpliftGames/wally-index)**
- Query: authenticated GitHub code search `repo:UpliftGames/wally-index facet`, cross-checked with a direct content fetch of the matched path.
- Result: **exactly one match — package `emdomanus/facet`**, same project as the GitHub repo above. `wally.toml` description: "Client-side 3D UI surface primitives for Roblox." MIT license, author `emdomanus`, versions 0.1.0–0.1.2+, no `homepage`/`repository` metadata set, `private: false` (publicly installable via `wally install emdomanus/facet`).
- URL: https://github.com/UpliftGames/wally-index/blob/main/emdomanus/facet
- Conflict relevance: **exact-name Roblox package, installable today via Wally — owner should review.** Same caveat as above: niche 3D-surface-UI primitive package, not a competing general-purpose UI framework, with no visible community adoption.

**Roblox DevForum**
- Query: `https://devforum.roblox.com/search.json?q=facet` (site search API)
- Result: no topic, library announcement, or resource is titled/named "Facet." All hits are the common English word ("facets of the platform," "faceted geometry," "Facet Suggestions" search-UI copy) — no product.
- URL: https://devforum.roblox.com/search?q=facet
- Conflict relevance: none found — **low relevance.**

**Roblox Creator Store**
- Query: web search `Roblox Creator Store "Facet"` and manual review of Creator Store category pages.
- Result: no plugin, UI library, or asset pack found named "Facet." Only hit is Roblox's own internal marketplace-search feature called "Facet Suggestions" (a generic UX term for faceted search, unrelated to any product).
- URL: https://create.roblox.com/store/category/plugins
- Conflict relevance: none found — **low relevance.**

---

## 3. Other major code hosts / package registries (informational — different ecosystems)

| Registry | Exact name "facet" | Notes | URL |
|---|---|---|---|
| npm | Yes — package `facet` exists | "Configuration mixin for constructors," last published v0.5.0 in **2014**, appears abandoned (no updates since) | https://www.npmjs.com/package/facet |
| crates.io | Yes — package `facet` exists | Rust reflection/serialization crate (same project as facet-rs/facet above), **very active**, 50+ published versions, most recent update 2026-06-28 | https://crates.io/crates/facet |
| PyPI | Yes — package `facet` exists | "Service manager for asyncio," current version 0.10.1 | https://pypi.org/project/facet/ |

Conflict relevance: all three — **different ecosystem (JS/Rust/Python general-purpose, not Roblox/Luau/game UI), low relevance.**

---

## 4. Trademark (USPTO)

- Query attempted directly against USPTO TESS/TSDR (`tsdr.uspto.gov`) and the mirrors `trademarks.justia.com/search?q=facet` and `trademarkia.com`.
- Result: **all three blocked automated access** — TSDR returned 503, and both Justia and Trademarkia returned Cloudflare "403 Forbidden" bot-challenge pages, so no authoritative live-mark list could be pulled directly for this check.
- Fallback: web search for known live "FACET"-branded software/tech entities, which surfaces evidence of existing marks without a full USPTO-verified status table:
  - **Facet Computing, Inc.** — trademark owner record found via Justia's indexed listing (page itself blocked, but the entity/listing title is indexed): "FACET" mark used for business consulting in decentralized applications, downloadable software for blockchain-based platforms, and crypto-related financial services. URL: https://trademarks.justia.com/owners/facet-computing-inc-5932033 — plausible class 9/42 coverage (downloadable software), **different application domain (blockchain/fintech), not a UI dev library.**
  - **Facet** (formerly "Facet Wealth") — financial planning / wealth-management company, consumer fintech brand, not a software dev tool. https://www.cbinsights.com/company/facet-5
  - **FacetWP** — commercial WordPress plugin ("Advanced Filtering / Faceted Search for WordPress"), active product, https://facetwp.com/ — closer to "software" but is an end-user WP plugin, not a UI framework/SDK, and not Roblox-adjacent.
  - **Facet Digital**, **Facet Interactive**, **Facet Technology** — several small software/IT consulting agencies use "Facet" in their company name (service marks, not clearly product trademarks for a UI library). https://facetdigital.com/ , https://facetinteractive.com/ , https://facet.technology/
- Conflict relevance: **"FACET" is a moderately crowded word-mark space in software/tech generally (fintech, WordPress plugin, consulting brands, a blockchain-software mark), but no live mark surfaced that squarely covers a UI development framework/SDK/library.** No authoritative TESS status could be confirmed due to blocked automated access — a manual/paid trademark-clearance search would be needed for a legal determination.

---

## Summary

**Blocking conflicts found: NO** (by the stated bar — no active, same-ecosystem Roblox/Luau UI *product* is named "Facet," and no live trademark squarely covers a UI development library).

**Relevant, non-blocking findings for owner review:**
- `github.com/josha/Facet` is available (404 today).
- One exact-name, same-ecosystem hit: **`emdomanus/facet`**, a Wally-published Roblox/Luau package ("client-side 3D UI surface primitives for Roblox") — real, installable, but effectively zero adoption (0 stars/forks/issues, ~2 weeks of commits in May 2026, no activity since June 2026). This is the closest thing to a same-space naming collision found and is worth a human look before finalizing.
- No "Facet" hits on Roblox DevForum or Creator Store.
- `facet` exact-name packages exist on npm (abandoned since 2014), crates.io (active Rust reflection library, 2,500+ GitHub stars), and PyPI (asyncio service manager) — all different ecosystems, low relevance.
- Trademark surfaces a moderately crowded "FACET" word-mark landscape in software/tech broadly (fintech, WordPress plugin, blockchain/consulting brands), but nothing squarely on a UI dev framework. USPTO TESS/TSDR and mirror sites (Justia, Trademarkia) blocked automated access (403/503), so this section is search-surfaced evidence only, not a verified legal clearance.
