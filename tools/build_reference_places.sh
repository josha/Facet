#!/usr/bin/env bash







set -euo pipefail
cd "$(dirname "$0")/.."





export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p examples/places







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
      "Gallery": { "\$path": "gallery/client" },
      "Facet": { "\$path": "../src" },
      "FacetExamples": { "\$path": "gallery/examples" },
      "FacetScenarios": { "\$path": "gallery/scenarios" },
      "FacetReference": { "\$path": "reference" },
      "FacetThemes": { "\$path": "themes" }
    },
    "StarterGui": {
      "\$properties": { "ScreenOrientation": "Sensor" }
    },
    "StarterPlayer": {}
  }
}
JSON
  rojo build "$project" -o "examples/places/$name.rbxl"
  rm "$project"
  echo "built examples/places/$name.rbxl ($scenario)"
done
