# VisualFX Command Reference

All AI-facing operations go through one entry point:

```lua
local result = VisualFX:Execute({ Action = "<Action>", ...fields })
```

* Commands are plain data. Functions or code strings are never executed.
* Unknown actions, missing required fields and wrong field types return
  `Success = false` with messages (and suggestions for typos). `Execute` never throws.
* Unknown fields produce a warning and are ignored.
* Mutating actions run the full pipeline: schema validation → compatibility
  validation → conflict detection → performance validation → plan → execute.
* Optional common fields: `Id` (echoed back in the result), `Comment`.
* `ListActions` returns this catalogue at runtime (`{ Description, Mutating, Fields }`).

## Result

```lua
{
    Success, Action, Id?,
    Created = {}, Modified = {}, Removed = {}, Changed = {}, Changes = {},
    Warnings = {}, Errors = {}, ValidationErrors = {},
    Data = ...,            -- query results
    Configuration = ...,   -- configuration after the command
    DryRun = true?, Diff = { Added, Modified, Removed, Unchanged, Summary }?,
}
```

## Inspection

| Action | Fields | Returns |
| --- | --- | --- |
| `InspectScene` | `Options?` `{ MaxParticles }` | `Data` = inspection, `Summary` |
| `DetectConflicts` | — | `Data`/`Conflicts` |
| `DiffScene` | `Configuration?`, `Merge?` | `Added`, `Modified`, `Removed`, `Unchanged`, `Summary` |
| `ValidateConfiguration` | `Configuration?` (default: current), `Partial?` | `Errors`, `Warnings`, `ValidationErrors`, `ValidationWarnings`, `Configuration` (normalized) |
| `GetPerformanceStats` | — | `Data` |
| `GetSchema` | `Format?` = `"table"` \| `"jsonschema"` | `Data` |
| `GetDocumentation` | — | `Data` (includes `Markdown`) |
| `ListActions` | — | `Data` |

## Sections (merge unless `Replace = true`; all accept `DryRun`)

| Action | Fields |
| --- | --- |
| `SetLighting` | `Configuration`*, `Replace?`, `DryRun?` |
| `SetAtmosphere` | same |
| `SetWater` | same |
| `SetSky` | same |
| `SetClouds` | same |
| `SetPostProcessing` | same |
| `SetEnvironment` | same |

## Effects

| Action | Fields |
| --- | --- |
| `CreateParticleSystem` | `Name`*, `Template?`, `Configuration?`, `DryRun?` |
| `UpdateParticleSystem` | `Name`*, `Configuration`*, `DryRun?` |
| `RemoveParticleSystem` | `Name`* |
| `CreateWeather` | `Type`*, `Configuration?`, `Duration?` (transition), `DryRun?` |
| `UpdateWeather` | `Configuration`*, `DryRun?` |
| `RemoveWeather` | — |
| `CreateZone` | `Name`*, `Configuration`* (`Effect`, `Position`, `Size`, `Intensity`, …), `DryRun?` |
| `RemoveZone` | `Name`* |

## Scenes and presets

| Action | Fields |
| --- | --- |
| `CreateScene` | `Configuration`* (configuration or description), `Duration?`, `DryRun?` |
| `UpdateScene` | `Configuration`* (overlay; `"$remove"` deletes), `Duration?`, `DryRun?` |
| `TransitionScene` | `Configuration?` or `Preset?`, `Duration?` (default 1), `Easing?`, `EasingDirection?`, `Replace?` |
| `ApplyPreset` | `Name`* (alias `Preset`), `Merge?`, `Overrides?`, `Duration?`, `Easing?`, `DryRun?` |
| `SavePreset` | `Name`*, `Configuration?` (default: current), `Overwrite?` |
| `DeletePreset` | `Name`* |
| `ListPresets` | `Filter?` `{ Category, Source, Search }` |
| `GetPreset` | `Name`* |
| `PreviewScene` | `Configuration`*, `Replace?` |
| `CommitPreview` / `RevertPreview` | — |
| `ResetManagedEffects` | — |
| `SetQuality` | `Level`*, `Overrides?` |

## Data

| Action | Fields |
| --- | --- |
| `ExportConfiguration` | `Format?` (`table`, `json`, `document`), `Resolved?` |
| `ImportConfiguration` | `Data` (table or JSON) or `Configuration`, `Merge?`, `Apply?` (default true), `DryRun?` |
| `GenerateCode` | `Configuration?`, `Options?` `{ Template, RequirePath, ConfigName, Comments, OmitTemplateDefaults, Quality, Duration, Easing }` → `Code` |

## Batch

```lua
VisualFX:Execute({
    Action = "Batch",
    Atomic = true,  -- default: revert every command if one fails
    Commands = {
        { Action = "SetLighting", Configuration = { ClockTime = 18 } },
        { Action = "CreateWeather", Type = "LightRain" },
    },
})
-- { Success, Results = { ...per-command results }, Reverted = true?, Created, Modified, Removed, Warnings, Errors }
```

Nested batches are rejected. Atomic batches use the preview journal, so a
failed batch leaves the scene exactly as it was.

## Examples

```lua
VisualFX:Execute({
    Action = "CreateWeather",
    Type = "Thunderstorm",
    Configuration = { RainIntensity = 0.9, Fog = 0.4, Wind = 35, Lightning = true },
})

VisualFX:Execute({
    Action = "TransitionScene",
    Configuration = { Weather = { Type = "HeavyRain", Intensity = 0.9 }, Lighting = { ClockTime = 19.2 } },
    Duration = 5,
})

VisualFX:Execute({ Action = "ValidateConfiguration" })
VisualFX:Execute({ Action = "GenerateCode", Options = { Template = "LocalScript" } })
```

## Error format

Type errors use a fixed, parseable format (also available structured in
`ValidationErrors[i]` with `Path`, `Code`, `Expected`, `Received`):

```text
Invalid property:
Lighting.ExposureCompensation

Expected:
number

Received:
string
```

Error codes: `InvalidType`, `OutOfRange`, `NotFinite`, `InvalidValue`,
`InvalidEnum`, `Required`, `InvalidKey`, `UnexpectedRemove`, `UnknownWeather`,
`UnknownTemplate`, `UnknownEffect`, `UnknownPreset`, `InvalidInheritance`,
`Migration`, `ValidatorFailure`, `EffectValidator`.

Warning codes: `UnknownProperty`, `UnknownSection`, `DuplicateAlias`,
`AboveRecommended`, `BelowRecommended`, `UnsupportedProperty`,
`UnsupportedEnum`, `SecurityRestricted`, `WeatherConflict`, `FogIgnored`,
`ClockTimeConflict`, `MultipleAtmospheres`, `PerformanceBudget`, `DecodeWarning`.
