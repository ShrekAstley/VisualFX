# VisualFX Studio

An AI-native visual-effects framework for Roblox: a runtime Luau library and a
Studio plugin for building, inspecting, previewing, serializing and reproducing
lighting, atmosphere, sky, clouds, post-processing, water, particles, weather
and spatial environment effects.

Humans work in the Studio plugin. AI agents work through a structured command
API. Both produce the same deterministic, versioned configuration data, which
can be turned into Luau code and applied in a published game.

```lua
local VisualFX = require(game:GetService("ReplicatedStorage").VisualFX)

VisualFX:ApplyPreset("CinematicSunset")

VisualFX:CreateScene({
    Mood = "mysterious",
    Time = "sunset",
    Weather = "light_rain",
    Environment = "dense_forest",
    Fog = "medium",
    LightingStyle = "cinematic",
})

VisualFX:TransitionTo({
    Duration = 8,
    Configuration = { Weather = { Type = "HeavyRain", Intensity = 0.9 }, Lighting = { ClockTime = 19.2 } },
})
```

## What's in the box

| Area | Location | Highlights |
| --- | --- | --- |
| Core | `Core/` | Registry, canonical config + merge rules + schema migration, validator, deterministic JSON serialization, compatibility detection, managed-identity instance manager with preview journal, events |
| Runtime | `Runtime/` | Lighting + post-processing, Atmosphere/Sky/Clouds, Water (+ underwater approximation), particle framework with 12 templates, composable weather (15 types), environment (wind, day/night, spatial zones), transitions, quality budgets, cleanup, reconciler |
| AI | `AI/` | `Execute` command API (35+ actions, batches, dry runs), scene inspector, Visual Director, machine-readable schema, runtime agent guide |
| Presets | `Presets/` | 26 built-in presets (inheritance/composition supported), user presets |
| Codegen | `Codegen/` | Deterministic Luau generator with Script/LocalScript/Module/Transition templates |
| Plugin | `Plugin/` | Dockable Studio UI with 13 pages, schema-generated property editors, live preview, Apply/Revert, AI Director panel, code export, runtime packaging |
| Docs | `Documentation/` | API, commands, config schema (+ JSON Schema), presets, examples, performance, AI agent guide |
| Tests | `Tests/`, `tools/` | 140+ specs and a headless plugin smoke test that run under a strict Roblox mock with the Luau CLI; the same specs run inside Studio |

## Installing

The project uses [Rojo](https://rojo.space) project files; nothing else is required.

```sh
# Runtime library only (place it in ReplicatedStorage)
rojo build default.project.json -o VisualFX.rbxm

# Studio plugin (bundles its own copy of the runtime)
rojo build plugin.project.json -o VisualFXStudio.rbxmx
# then copy VisualFXStudio.rbxmx into your Studio Plugins folder
# (Studio: Plugins tab -> Plugins Folder)

# Test place (runs the suite in Play mode)
rojo build test.project.json -o VisualFXTests.rbxlx
```

Without Rojo you can install the plugin build once and use **Settings → Install /
update in ReplicatedStorage** to copy the runtime package into any place.

### Runtime packaging workflow

```text
Studio plugin -> configure environment -> export configuration / code
  -> install runtime package (ReplicatedStorage.VisualFX)
  -> require(game.ReplicatedStorage.VisualFX) in your game
```

The runtime never requires the plugin. User presets saved in the plugin are
written into `VisualFX.Presets.User` as ModuleScripts, so
`VisualFX:ApplyPreset("MyPreset")` works in the published game.

Where to run it:

* **Server Script**: lighting, atmosphere, post-processing, water and world
  particles replicate to every player.
* **LocalScript** (recommended for weather): camera-following rain/snow, zone
  culling, zone fog-bank blending, lightning and the underwater look need the
  local camera. Runtime controllers start automatically when the game is running.

## Running the tests

The suite runs outside Roblox with the standalone [Luau CLI](https://github.com/luau-lang/luau/releases)
against `tools/mock/Roblox.luau`, a strict engine mock (unknown properties
error, numbers are stored as float32, `Parent` locks after `Destroy`, attributes
and tags are validated).

```sh
LUAU=/path/to/luau sh tools/test.sh          # all specs + plugin smoke test
LUAU=/path/to/luau sh tools/test.sh Weather  # only specs whose name contains "Weather"
```

In Studio, build `test.project.json`, open it and press Play: the server script
runs every spec and restores Lighting/Terrain/Workspace after each test.

`tools/test.sh` also runs `tools/run_plugin_smoke.luau`, which loads the whole
plugin headlessly, opens the widget, visits every page and drives the main
flows (preset apply/preview/revert, live property edit + Apply, search, AI
Director, code export, runtime package install).

### Regenerating schemas and reference docs

`Documentation/schema/*.json`, `CONFIG_SCHEMA.md` and `PRESETS.md` are generated
from the live registries so they cannot drift from the code:

```sh
LUAU=/path/to/luau sh tools/gen_docs.sh
```

### Layout note

The plugin entry point is `Plugin/PluginMain.server.luau`: the `.server`
suffix tells Rojo to build it as a `Script`, which plugins require.

## Design principles

* **Configuration is data.** Every effect is expressed in a canonical,
  versioned table (see `Documentation/CONFIG_SCHEMA.md`). Code is never executed
  from configurations.
* **One pipeline.** Input → schema validation → compatibility validation →
  conflict detection → performance validation → plan → execute → structured result.
* **Reconciliation, not creation.** Sections declare the instances and
  properties they want; the reconciler locates existing instances by managed
  identity (`VisualFX_ID` attribute + `VisualFX` tag), adopts compatible
  developer instances, writes only differences and removes only managed
  instances. Re-applying a configuration is a no-op.
* **Non-destructive.** Original values of every property VisualFX touches are
  recorded (in attributes, so they survive save/reopen) and restored on
  removal/reset. Previews are journaled and revert exactly, without overwriting
  edits a developer made in the meantime.
* **Adapt to the engine.** Property support is detected at runtime by reading
  real instances; unsupported properties are reported and skipped.

## Known limitations

These are Roblox engine constraints; VisualFX implements the closest robust
approximation and says so.

* **No volumetric fog primitive.** Fog banks use large, soft smoke-texture
  particles plus Atmosphere blending while the camera is inside a zone.
* **No underwater fog property.** The underwater look is a client-side
  ColorCorrection/Blur enabled when `Terrain:ReadVoxels` reports water at the camera.
* **Particle textures.** Templates use textures that ship with the client
  (`rbxasset://textures/particles/*.dds`). Rain streaks and leaves are
  approximations; set `Texture` to your own assets for production visuals.
* **Lighting.Technology** is typically writable only from Studio. At runtime
  the write is rejected by the engine; VisualFX reports it and continues.
* **Legacy fog** (`Lighting.Fog*`) has no visible effect while an Atmosphere
  exists; the validator warns about this combination.
* **Audio** is not played by VisualFX. Weather exposes `AudioHook` events
  (`Rain`, `Wind`, `Thunder`, …) for your audio system.
* **Clipboard.** Studio plugins cannot write to the system clipboard. The Code
  page's *Copy* button selects the code so you can press Ctrl+C, and *Export*
  writes the code into a script in the place.
* **Performance numbers are estimates** of workload (emission rate, estimated
  live particles). VisualFX never predicts FPS.
* **Server-side weather.** There is no camera on the server, so camera-attached
  weather particles stay at their configured position; apply weather from a
  LocalScript for per-player weather.
