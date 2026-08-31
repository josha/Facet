#!/usr/bin/env bash
# Reference-proof place builder (reference-app-validation): emits one
# ready-to-open .rbxl per clean-room reference proof. Each place maps the full
# gallery surface (src, scenarios, reference modules, themes, bootstrap) and
# pre-sets the Workspace attribute Facet_Scenario so the place boots straight
# into its proof through the shared scenario runner.
# Usage: tools/build_reference_places.sh          (from the library root)
# Output: examples/places/Facet-Ref-*.rbxl
set -euo pipefail
cd "$(dirname "$0")/.."
# ROKIT'S rojo, NOT whatever is first on PATH. A stale /usr/local/bin/rojo
# (7.7.0-rc.1, Nov 2025) shadowed the rokit-managed 7.7.0 for months; its
# reflection database does not know `Workspace.PlayerScriptsUseInputActionSystem`,
# so a project declaring it FAILED THE BUILD with "Unknown property" while the
# pinned toolchain built it fine. Measured 2026-08-15.
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p examples/places

# FOUR, NOT FIVE, SINCE 2026-08-30: `ref_wardrobe|Facet-Ref-Wardrobe` was
# removed with the Wardrobe retirement (docs/plans/example-games-and-standalones.md,
# "Retire Wardrobe; complete Sipworks and Glade"). A publishable place is exactly
# what a retired example must not still have, so `examples/places/Facet-Ref-Wardrobe.rbxl`
# was deleted with it. The app survives only as test evidence for the closed
# reference-app-validation gate, at tests/fixtures/retired/p5_wardrobe.
PROOFS=(
  "ref_glade|Facet-Ref-Glade"
  "ref_cartwheel|Facet-Ref-Cartwheel"
  "ref_sipworks|Facet-Ref-Sipworks"
  "ref_foyer|Facet-Ref-Foyer"
)

for entry in "${PROOFS[@]}"; do
  IFS="|" read -r scenario name <<<"$entry"
  project="examples/.reference_place_build.project.json"
  cat >"$project" <<JSON
{
  "name": "$name",
  "emitLegacyScripts": false,
  "globIgnorePaths": ["**/*.spec.luau"],
  "tree": {
    "\$className": "DataModel",
    "Lighting": {
      "\$properties": {
        "Technology": "Unified",
        "LightingStyle": "Soft",
        "PrioritizeLightingQuality": false
      }
    },
    "Workspace": {
      "\$attributes": { "Facet_Scenario": "$scenario" },
      "\$properties": {
        "FilteringEnabled": true,
        "PlayerScriptsUseInputActionSystem": "Enabled"
      },
      "Baseplate": {
        "\$className": "Part",
        "\$properties": {
          "Anchored": true,
          "Locked": true,
          "Size": [512, 20, 512],
          "Position": [0, -10, 0],
          "Color": [0.35, 0.37, 0.39],
          "TopSurface": "Smooth",
          "BottomSurface": "Smooth"
        }
      },
      "SpawnLocation": {
        "\$className": "SpawnLocation",
        "\$properties": {
          "Anchored": true,
          "Size": [12, 1, 12],
          "Position": [0, 0.5, 0],
          "Duration": 0,
          "Neutral": true
        }
      }
    },
    "Players": {
      "\$properties": { "CharacterAutoLoads": false }
    },
    "ReplicatedStorage": {
      "Facet": { "\$path": "../src" },
      "FacetExamples": { "\$path": "gallery/examples" },
      "FacetScenarios": { "\$path": "gallery/scenarios" },
      "FacetReference": { "\$path": "reference" },
      "FacetThemes": { "\$path": "themes" }
    },
    "StarterGui": {
      "\$properties": { "ScreenOrientation": "Sensor" }
    },
    "StarterPlayer": {
      "StarterPlayerScripts": {
        "Gallery": { "\$path": "gallery/client" }
      }
    }
  }
}
JSON
  rojo build "$project" -o "examples/places/$name.rbxl"
  rm "$project"
  echo "built examples/places/$name.rbxl ($scenario)"
done
