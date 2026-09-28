# VisualFX AI Agent Guide

This guide is for AI coding agents that build or modify Roblox environments
with VisualFX. Everything here works programmatically, without the Studio UI.

**Where you can call VisualFX**

* In a game or test place: `local VisualFX = require(game.ReplicatedStorage.VisualFX)`.
* In Studio with the plugin loaded: `_G.VisualFXStudio.Execute({...})` uses
  the plugin's engine and its preview/undo integration, from code that shares
  the plugin's `_G`. From other contexts (e.g. the Command Bar, if `_G` is not
  shared with it), require the installed runtime package instead — the
  `Execute` API is identical.
* The same guide is available at runtime: `VisualFX:GetDocumentation()`
  (structured, plus `.Markdown`) and `VisualFX:GetSchema()`.
  Static machine-readable files: `Documentation/schema/*.json`.

**Golden rules**

1. Inspect before you change anything you did not create.
2. Use commands; never create Atmosphere/ParticleEmitter/post effects by hand
   for effects VisualFX manages (you would lose identity and duplicate
   prevention).
3. Validate or diff before large changes; show the diff to the user.
4. Warnings are advice; Errors block execution and nothing is applied.
5. Configurations are data. Never embed code — it is rejected, never executed.

---

## 1. Inspect a scene

```lua
local scene = VisualFX:Execute({ Action = "InspectScene" }).Data
print(table.concat(scene.Summary, "\n"))
```

Key fields:

* `scene.Lighting.Properties`, `scene.Water.Properties` — live values;
  `ManagedProperties` lists what VisualFX currently controls.
* `scene.Atmosphere`, `Sky`, `Clouds`, `PostProcessing`, `Particles.Managed`,
  `Particles.Developer` — instances with `Classification`:
  `Managed` (VisualFX created), `Adopted` (developer instance VisualFX took
  over; originals recorded), `RobloxDefault` (unmodified), `Developer`,
  `Unknown`.
* `scene.Weather` — `{ Active, Type, Intensity, Components, AudioHooks }`.
* `scene.ManagedEffects` — every managed instance with its `ID`.
* `scene.Conflicts`, `scene.Quality`, `scene.Configuration` (authored config).

## 2. Modify a scene

Prefer **merge** operations:

```lua
VisualFX:Execute({ Action = "SetLighting", Configuration = { ClockTime = 18.5, ExposureCompensation = 0.2 } })
VisualFX:Execute({ Action = "UpdateScene", Configuration = { Atmosphere = { Haze = 2 }, Water = { WaveSize = 0.3 } } })
```

* To remove a key or section use `"$remove"`:
  `{ Action = "UpdateScene", Configuration = { Weather = "$remove", Lighting = { FogEnd = "$remove" } } }`.
  Removed service properties return to their original values.
* To replace the whole managed scene use `CreateScene` or `ApplyPreset`.
* Aliases are accepted (`WaveStrength` → `WaveSize`, `EmissionRate` → `Rate`, …)
  and reported in `Notes`.

## 3. Create effects

```lua
-- From a description (deterministic Visual Director)
VisualFX:Execute({ Action = "CreateScene", Configuration = {
    Mood = "mysterious", Time = "sunset", Weather = "light_rain",
    Environment = "dense_forest", Fog = "medium", LightingStyle = "cinematic", WaterStyle = "calm_reflective",
} })

-- Weather composed of atmosphere, lighting, clouds, rain, wind, fog, lightning, audio hooks
VisualFX:Execute({ Action = "CreateWeather", Type = "Thunderstorm",
    Configuration = { RainIntensity = 0.9, Fog = 0.4, Wind = 35, Lightning = true } })

-- Particle systems from templates
VisualFX:Execute({ Action = "CreateParticleSystem", Name = "Embers", Template = "Embers",
    Configuration = { Attach = "World", Position = { 0, 2, 0 }, Rate = 40 } })

-- Spatial zone (fog bank that thickens the atmosphere while the camera is inside)
VisualFX:Execute({ Action = "CreateZone", Name = "ForestFog", Configuration = {
    Effect = "Fog", Position = { 0, 30, 0 }, Size = { 500, 100, 500 }, Intensity = 0.7,
    Atmosphere = { Density = 0.6, Haze = 3 } } })

-- Post-processing
VisualFX:Execute({ Action = "SetPostProcessing", Configuration = {
    Bloom = { Intensity = 0.8, Size = 28, Threshold = 1.6 },
    ColorCorrection = { Contrast = 0.1, Saturation = 0.1, TintColor = "#FFEBDC" } } })
```

Vocabulary for descriptions: `VisualFX.Director:Vocabulary()` or
`GetSchema().DirectorVocabulary`. Unknown words become warnings with suggestions.

## 4. Avoid duplicates

You do not need to check before creating: every managed instance has an
identity (`VisualFX_ID`), and the reconciler always looks it up first.

* Applying the same configuration twice creates nothing and modifies nothing.
* Existing developer `Atmosphere`, `Sky`, `Clouds`, `BloomEffect`,
  `SunRaysEffect` and `DepthOfFieldEffect` in Lighting/Terrain are **adopted**
  instead of duplicated. Their original values are recorded and restored when
  the effect is removed.
* Duplicate managed copies (e.g. from copy/paste) are collapsed automatically
  on the next apply and reported as warnings.
* Changing weather replaces weather-owned particles; nothing accumulates.

## 5. Validate configurations

```lua
local report = VisualFX:Execute({ Action = "ValidateConfiguration", Configuration = candidate })
if not report.Success then
    for _, entry in ipairs(report.ValidationErrors) do
        -- entry.Path, entry.Code, entry.Expected, entry.Received, entry.Message
    end
end
```

`report.Configuration` is the normalized form (aliases resolved, `"#RRGGBB"`
→ Color3, arrays → Vector3/NumberRange, enum names → EnumItems). Mutating
commands validate automatically; you only need this to check candidates.

## 6. Create presets

```lua
VisualFX:Execute({ Action = "SavePreset", Name = "StormyHarbor" })   -- current scene
VisualFX:Execute({ Action = "SavePreset", Name = "AutumnDusk", Configuration = {
    Inherits = { "Sunset", "Autumn" }, Lighting = { ClockTime = 18.2 } } })
VisualFX:Execute({ Action = "ApplyPreset", Name = "AutumnDusk", Duration = 4 })
```

Built-ins cannot be overwritten or deleted. `ListPresets` with
`Filter = { Search = "rain" }` finds presets; `GetPreset` returns the
resolved configuration.

## 7. Generate code

```lua
local code = VisualFX:Execute({ Action = "GenerateCode", Options = { Template = "LocalScript" } }).Code
```

Templates: `Script` (server), `LocalScript` (client weather), `Module`
(configuration table), `Transition`. Output is deterministic, commented,
omits particle values equal to template defaults, and reproduces the scene
exactly when run. Pair it with `ExportConfiguration` (`Format = "json"`) for
a diffable data file.

## 8. Transition scenes

```lua
VisualFX:Execute({ Action = "TransitionScene", Duration = 5, Easing = "Smooth",
    Configuration = { Weather = { Type = "HeavyRain", Intensity = 0.9 }, Lighting = { ClockTime = 19.2 } } })
VisualFX:Execute({ Action = "TransitionScene", Preset = "Night", Duration = 8 })
```

New effects fade in from neutral (particle `Rate` 0, bloom intensity 0, …);
removed effects fade out and are then removed; `ClockTime` takes the short way
around midnight; the end state is exactly what an instant apply produces.
Transitions advance on Heartbeat (or `VisualFX:Step(dt)` if you drive time
yourself). `VisualFX:CancelTransition(true)` jumps to the end.

## 9. Diagnose conflicts

```lua
for _, conflict in ipairs(VisualFX:Execute({ Action = "DetectConflicts" }).Data) do
    print(conflict.Severity, conflict.Code, conflict.Message, conflict.Suggestion)
end
```

| Code | Meaning | Fix |
| --- | --- | --- |
| `MultipleAtmosphere` / `MultipleSky` / `MultipleClouds` | Roblox renders only one | Remove extras; VisualFX adopts one |
| `StackedBloomEffect` / `StackedSunRaysEffect` / `StackedDepthOfFieldEffect` | Enabled effects stack | Disable extras |
| `DuplicateManagedID` | Copies of a managed instance | Re-apply (auto-collapse) or `ResetManagedEffects` |
| `FogIgnored` | Legacy fog set while an Atmosphere exists | Use `Atmosphere.Density/Haze` |
| `StaleManagedEffects` | Managed instances not in the current configuration | `CreateScene`/`ApplyPreset` or `ResetManagedEffects` |
| `DeveloperParticleLoad` | Unmanaged emitters exceed the budget | Lower their rates or quality |

Configuration-level conflicts (rain particles with `Clear` weather, fog with an
atmosphere, `ClockTime` vs `DayNight.StartTime`) appear as validation warnings.

## 10. Optimize effects

```lua
local stats = VisualFX:Execute({ Action = "GetPerformanceStats" }).Data
if stats.EstimatedParticleRate > 3000 then
    VisualFX:Execute({ Action = "SetQuality", Level = "Medium" })
end
```

Levers: `SetQuality` (budgets), lower `Rate`/`Lifetime`, `CullDistance` on
zones, fewer systems (see PERFORMANCE.md). Never promise FPS numbers — stats
are workload estimates.

---

## Complete workflow (definition of done)

```lua
local VisualFX = require(game.ReplicatedStorage.VisualFX)

-- Inspect
local scene = VisualFX:Execute({ Action = "InspectScene" })

-- Create (structured description -> configuration)
local created = VisualFX:Execute({ Action = "CreateScene", DryRun = true, Configuration = {
    Mood = "mysterious", Time = "sunset", Weather = "light_rain",
    Environment = "dense_forest", Fog = "medium", LightingStyle = "cinematic" } })
-- created.Diff.Summary -> show to the user

-- Validate + conflicts
local validation = VisualFX:Execute({ Action = "ValidateConfiguration", Configuration = created.Configuration })
local conflicts = VisualFX:Execute({ Action = "DetectConflicts" })

-- Preview, then apply
VisualFX:Execute({ Action = "PreviewScene", Configuration = created.Configuration, Replace = true })
VisualFX:Execute({ Action = "CommitPreview" })   -- or RevertPreview

-- Transition
VisualFX:Execute({ Action = "TransitionScene", Duration = 5, Configuration = {
    Weather = { Type = "HeavyRain", Intensity = 0.9 }, Lighting = { ClockTime = 19.2 } } })

-- Inspect the result, optimize
local after = VisualFX:Execute({ Action = "InspectScene" })
VisualFX:Execute({ Action = "SetQuality", Level = "High" })

-- Export and generate reusable Luau
local json = VisualFX:Execute({ Action = "ExportConfiguration", Format = "json" }).Data
local code = VisualFX:Execute({ Action = "GenerateCode" }).Code
```

`Tests/Commands.spec.luau` and `Examples/AgentWorkflow.luau` (exercised by
`Tests/Examples.spec.luau`) run this workflow end to end.

## Failure handling

```lua
local result = VisualFX:Execute(command)
if not result.Success then
    -- result.Errors: human-readable; result.ValidationErrors: { Path, Code, Expected, Received }
    -- Nothing was applied. Fix the Path and retry.
end
for _, warning in ipairs(result.Warnings) do
    -- e.g. "Lighting.Technology: ... skipped", "Unknown property Atmosphere.Densty ... (did you mean 'Density'?)"
end
```

For multi-step edits that must all succeed, wrap them in
`{ Action = "Batch", Commands = {...} }` — a failure reverts the whole batch.
