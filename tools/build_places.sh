#!/usr/bin/env bash








set -euo pipefail
cd "$(dirname "$0")/.."





export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p examples/places


















BUILD_STAMP="content $( { find src examples/gallery examples/reference examples/themes -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 shasum -a 256 2>/dev/null; } | shasum -a 256 | cut -c1-12 )"

EXAMPLES=(
  "0|Facet-SettingsDemo|00_settings_demo"
  "1|Facet-Ex01-TemperatureConverter|01_temperature_converter"
  "2|Facet-Ex02-PlaylistTable|02_playlist_table"
  "3|Facet-Ex03-SettingsSync|03_settings_sync"
  "4|Facet-Ex04-ConfirmDialog|04_confirm_dialog"
  "5|Facet-Ex05-WordGame|05_word_game"
  "6|Facet-Ex06-TileGame|06_tile_game"
  "7|Facet-Ex07-Match3|07_match3"
)

for entry in "${EXAMPLES[@]}"; do
  IFS="|" read -r index name file <<<"$entry"
  project="examples/.place_build.project.json"
  if [ "$index" = "0" ]; then
    attributes=""
  else
    attributes="\"\$attributes\": { \"Facet_Example\": $index },"
  fi

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
      $attributes
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
      "FacetExamples": { "\$path": "gallery/examples" }
    },
    "StarterGui": {
      "\$properties": { "ScreenOrientation": "Sensor" }
    },
    "StarterPlayer": {}
  }
}
JSON
  rojo build "$project" -o "examples/places/$file.rbxl"
  rm "$project"
  echo "built examples/places/$file.rbxl ($name)"
done






project="examples/.place_build.project.json"
cat >"$project" <<'JSON'
{
  "name": "Facet-Showcase",
  "emitLegacyScripts": false,
  "globIgnorePaths": ["**/*.spec.luau"],
  "tree": {
    "$className": "DataModel",
    "Lighting": {
      "$properties": {
        "Technology": "Unified",
        "LightingStyle": "Soft",
        "PrioritizeLightingQuality": false
      }
    },
    "Workspace": {
      "$attributes": {
        "Facet_Showcase": true,
        "Facet_NativeStyle": true,
        "Facet_Build": "@@BUILD_STAMP@@"
      },
      "$properties": {
        "FilteringEnabled": true,
        "PlayerScriptsUseInputActionSystem": "Enabled"
      },
      "Baseplate": {
        "$className": "Part",
        "$properties": {
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
        "$className": "SpawnLocation",
        "$properties": {
          "Anchored": true,
          "Size": [12, 1, 12],
          "Position": [0, 0.5, 0],
          "Duration": 0,
          "Neutral": true
        }
      }
    },
    "Players": {
      "$properties": { "CharacterAutoLoads": false }
    },
    "ReplicatedStorage": {
      "Gallery": { "$path": "gallery/client" },
      "Facet": { "$path": "../src" },
      "FacetExamples": { "$path": "gallery/examples" },
      "FacetScenarios": { "$path": "gallery/scenarios" },
      "FacetThemes": { "$path": "themes" }
    },
    "StarterGui": {
      "$properties": { "ScreenOrientation": "Sensor" }
    },
    "StarterPlayer": {},
    "ServerScriptService": {
      "Outpost": { "$path": "gallery/server" }
    }
  }
}
JSON


perl -pi -e "s|\\@\\@BUILD_STAMP\\@\\@|$BUILD_STAMP|" "$project"
rojo build "$project" -o "examples/places/Facet-Showcase.rbxl"
rm "$project"
echo "built examples/places/Facet-Showcase.rbxl (Facet-Showcase — in-game demo + theme switching)"












rojo build examples/performance.project.json -o "examples/places/Facet-PerformanceLab.rbxl"
echo "built examples/places/Facet-PerformanceLab.rbxl (Facet-PerformanceLab — Step 9 performance lab)"



lune run tools/lune/check_place_bootstrap.luau examples/places/0*.rbxl examples/places/Facet-Showcase.rbxl

echo "done: $(ls examples/places/*.rbxl | wc -l | tr -d ' ') place files in examples/places/"
