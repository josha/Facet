#!/usr/bin/env bash
# LuauUI example place builder: emits one ready-to-open .rbxl per tutorial
# example (docs/guide/04-tutorial-examples.md) plus the plain settings demo.
# Each place maps src -> ReplicatedStorage.LuauUI, the example modules ->
# ReplicatedStorage.LuauUIExamples, the gallery bootstrap ->
# StarterPlayerScripts, adds a baseplate + spawn, and pre-sets the Workspace
# attribute LuauUI_Example so the place boots straight into its example.
# Usage: tools/build_places.sh          (from the library root)
# Output: examples/places/*.rbxl
set -euo pipefail
cd "$(dirname "$0")/.."
# ROKIT'S rojo, NOT whatever is first on PATH. A stale /usr/local/bin/rojo
# (7.7.0-rc.1, Nov 2025) shadowed the rokit-managed 7.7.0 for months; its
# reflection database does not know `Workspace.PlayerScriptsUseInputActionSystem`,
# so a project declaring it FAILED THE BUILD with "Unknown property" while the
# pinned toolchain built it fine. Measured 2026-08-15.
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p examples/places

EXAMPLES=(
  "0|LuauUI-SettingsDemo|00_settings_demo"
  "1|LuauUI-Ex01-TemperatureConverter|01_temperature_converter"
  "2|LuauUI-Ex02-PlaylistTable|02_playlist_table"
  "3|LuauUI-Ex03-SettingsSync|03_settings_sync"
  "4|LuauUI-Ex04-ConfirmDialog|04_confirm_dialog"
  "5|LuauUI-Ex05-WordGame|05_word_game"
  "6|LuauUI-Ex06-TileGame|06_tile_game"
  "7|LuauUI-Ex07-Match3|07_match3"
)

for entry in "${EXAMPLES[@]}"; do
  IFS="|" read -r index name file <<<"$entry"
  project="examples/.place_build.project.json"
  if [ "$index" = "0" ]; then
    attributes=""
  else
    attributes="\"\$attributes\": { \"LuauUI_Example\": $index },"
  fi
  cat >"$project" <<JSON
{
  "name": "$name",
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
      "\$properties": { "FilteringEnabled": true },
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
      "LuauUI": { "\$path": "../src" },
      "LuauUIExamples": { "\$path": "gallery/examples" }
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
  rojo build "$project" -o "examples/places/$file.rbxl"
  rm "$project"
  echo "built examples/places/$file.rbxl ($name)"
done
# ===== THE SHOWCASE PLACE ===================================================
# One place to publish and open on a phone, a tablet, a desktop and a console.
# Everything the eight single-example places need an attribute + a republish to
# change, this place changes in-game: the demo AND the theme. It therefore maps
# the scenarios (for the all-controls fixture) and the theme packages too, and
# sets LuauUI_Showcase so the bootstrap takes its showcase branch.
project="examples/.place_build.project.json"
cat >"$project" <<'JSON'
{
  "name": "LuauUI-Showcase",
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
        "LuauUI_Showcase": true,
        "LuauUI_NativeStyle": true
      },
      "$properties": { "FilteringEnabled": true },
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
      "LuauUI": { "$path": "../src" },
      "LuauUIExamples": { "$path": "gallery/examples" },
      "LuauUIScenarios": { "$path": "gallery/scenarios" },
      "LuauUIThemes": { "$path": "themes" }
    },
    "StarterGui": {
      "$properties": { "ScreenOrientation": "Sensor" }
    },
    "StarterPlayer": {
      "StarterPlayerScripts": {
        "Gallery": { "$path": "gallery/client" }
      }
    }
  }
}
JSON
rojo build "$project" -o "examples/places/LuauUI-Showcase.rbxl"
rm "$project"
echo "built examples/places/LuauUI-Showcase.rbxl (LuauUI-Showcase — in-game demo + theme switching)"

# ===== THE PERFORMANCE LAB ==================================================
# Roadmap Step 9 (docs/plans/performance-stress-places.md). Unlike every place
# above, this one is built from a CHECKED-IN Rojo project file rather than a
# heredoc: the plan requires the place's sources and its project to be
# reviewable artifacts, and a project that exists only inside a shell script
# cannot be diffed, opened in Rojo, or reused by the place doctor.
#
# The emitted file must open and run with no Rojo session, no filesystem path,
# no private asset, no secret, no universe id and no plugin — it is safe for the
# user to open and choose "Publish to Roblox" manually. THIS SCRIPT NEVER
# PUBLISHES: `rojo build` writes a local file and nothing else.
rojo build examples/performance.project.json -o "examples/places/LuauUI-PerformanceLab.rbxl"
echo "built examples/places/LuauUI-PerformanceLab.rbxl (LuauUI-PerformanceLab — Step 9 performance lab)"

echo "done: $(ls examples/places/*.rbxl | wc -l | tr -d ' ') place files in examples/places/"
