# VisualFX API Reference

```lua
local VisualFX = require(game:GetService("ReplicatedStorage").VisualFX)
```

The module returns a **default engine** (created on first use) and also exposes
`VisualFX.new(options)` for isolated engines. Every method below can be called
on either with `:` syntax.

```lua
local engine = VisualFX.new({
    AutoStart = true,          -- connect the scheduler to RunService.Heartbeat
    RuntimeControllers = nil,  -- default: true while the game is running
    CameraEffects = nil,       -- default: running on a client
    AdoptExisting = true,      -- adopt developer Atmosphere/Sky/Clouds/Bloom/SunRays/DepthOfField
    Quality = "High",
})
```

## Result objects

Every mutating call returns a structured result and never throws for invalid input:

```lua
{
    Success = true,
    Action = "ApplyPreset",
    Created = { "Rain", "Atmosphere" },   -- effect types created
    Modified = { "Lighting" },            -- effect types changed
    Removed = {},                         -- effect types removed
    Changed = { "Lighting.ClockTime" },   -- "Type.Property" strings
    Changes = { { ID, Type, Property, From, To, Restore?, Create? } },
    Warnings = { "..." },                 -- advice; never blocks execution
    Errors = { "..." },                   -- blocking problems (nothing was applied)
    ValidationErrors = { { Path, Code, Message, Expected?, Received? } },
    Notes = { "migrated configuration from version 0 to 1" },
    Configuration = { ... },              -- the authored configuration after the call
}
```

## Scenes

| Method | Description |
| --- | --- |
| `CreateScene(input, options?)` | Replace the managed scene. `input` is a configuration **or** a description (`Mood`, `Time`, `Weather`, `Environment`, `Fog`, `LightingStyle`, `WaterStyle`, `Intensity`) interpreted by the Visual Director. Options: `DryRun`, `Transition = { Duration, Easing }`. |
| `UpdateScene(overlay, options?)` | Merge into the current scene (`"$remove"` deletes keys). Same options. |
| `ApplyPreset(name, options?)` | Apply a preset. Options: `Merge`, `Overrides`, `Transition`, `DryRun`. Names are case/format-insensitive. |
| `TransitionTo({ Duration, Easing?, EasingDirection?, Configuration?, Preset?, Replace? })` | Smooth transition. Alias `TransitionScene`. |
| `CancelTransition(complete?)`, `IsTransitioning()` | Stop (freeze) or finish a transition. |
| `DiffScene(config?, { Merge? })` | Compare with the live scene without changing it → `{ Added, Modified, Removed, Unchanged, Warnings, Summary }`. |
| `InspectScene(options?)` | Structured inspection (see below). |
| `DetectConflicts()` | Live-scene conflicts: `{ Code, Severity, Message, Paths, Suggestion }`. |
| `Validate(config?, { Partial?, AllowRemove? })` | Validation report (default: current configuration). Alias `ValidateConfiguration`. |
| `ResetManagedEffects()` | Remove every managed instance, release adopted ones, restore originals. |

## Sections

All setters **merge** by default; pass `{ Replace = true }` to replace the section.

| Method | Section |
| --- | --- |
| `SetLighting(config, options?)` | `Lighting` |
| `SetAtmosphere(config, options?)` | `Atmosphere` |
| `SetSky(config, options?)` | `Sky` |
| `SetClouds(config, options?)` | `Clouds` |
| `SetPostProcessing(config, options?)` | `PostProcessing` (`Bloom`, `ColorCorrection`, `DepthOfField`, `SunRays`, `Blur`) |
| `SetWater(config, options?)` | `Water` |
| `SetEnvironment(config, options?)` | `Environment` |
| `SetWind({ Direction, Speed })` | `Environment.Wind` |
| `SetDayNightCycle({ Enabled, DayLength, StartTime, Paused, DriveLighting })` | `Environment.DayNight` |

## Particles, weather, zones

| Method | Description |
| --- | --- |
| `CreateParticleSystem(name, config)` | Create/replace a named system. `Template` defaults to the name when it matches a template (Rain, Snow, Dust, Fog, Mist, Smoke, Embers, Sparks, Fireflies, Leaves, Magic, Custom). |
| `UpdateParticleSystem(name, partial)` / `RemoveParticleSystem(name)` | Merge / remove. |
| `GetParticleSystem(name)` / `ListParticleSystems()` | Live values / names. |
| `CreateWeather(type, config?)` | Alias `SetWeather`. Config: `Intensity`, `Wind`, `WindDirection`, `Fog`, `Lightning`, `LightningFrequency`, `RainIntensity`, `SnowIntensity`, `DustIntensity`, `Attach`, `Position`, `Area`, `Seed`, `Particles`. |
| `UpdateWeather(partial)` / `RemoveWeather()` / `GetWeather()` | |
| `CreateZone(name, { Effect, Position, Size, Intensity, CullDistance?, BlendDistance?, Atmosphere?, Overrides? })` | Spatial effect zone. |
| `UpdateZone(name, partial)` / `RemoveZone(name)` | |

## Per-effect APIs

Every effect exposes the same nine operations: `Create`, `Get`, `Set`, `Update`,
`Remove`, `Reset`, `Serialize`, `Deserialize`, `Validate`.

```lua
VisualFX.Lighting, VisualFX.Atmosphere, VisualFX.Sky, VisualFX.Clouds, VisualFX.Water
VisualFX.PostProcessing.Bloom / .ColorCorrection / .DepthOfField / .SunRays / .Blur
VisualFX.Wind, VisualFX.DayNight
VisualFX.Weather            -- Create(type, config), Types()
VisualFX.Particles          -- keyed: Create(name, cfg), Get(name), Set(name, cfg), Update(name, partial), Remove(name), Reset(), List()
VisualFX.Zones, VisualFX.Effects   -- keyed like Particles
```

* `Set` replaces the effect's configuration exactly; properties that are no
  longer configured are restored to their original values.
* `Update` merges.
* `Get` reads live values from the scene; `GetConfiguration` returns the authored values.
* `Remove`/`Reset` delete the effect from the configuration: created instances
  are removed, adopted instances released, service properties restored.

## Presets

| Method | Description |
| --- | --- |
| `ApplyPreset(name, options?)` | See above. |
| `SavePreset(name, config?, { Overwrite? })` | Save (default: current configuration). `Inherits` is preserved for composed presets. Built-ins are protected. |
| `DeletePreset(name)` | User presets only. |
| `GetPreset(name)` | Resolved configuration (inheritance expanded) or `nil, error`. |
| `ListPresets({ Category?, Source?, Search? })` | `{ Name, DisplayName, Category, Description, Tags, Source, Inherits }`. |
| `ComposePresets(names, overrides?)` | Merge presets left to right. |
| `engine.Presets:SetStorage({ Load, Save })` | Persist user presets (the plugin uses `plugin:SetSetting`; games can use a DataStore). |

## Preview (non-destructive editing)

```lua
VisualFX:Preview(config, { Replace = false }) -- journal every change
VisualFX:IsPreviewing()
VisualFX:CommitPreview()                        -- keep
VisualFX:RevertPreview()                        -- restore exactly; developer edits made meanwhile are kept
```

## Import, export, code

| Method | Description |
| --- | --- |
| `GetConfiguration()` | Deep copy of the authored configuration. |
| `GetResolvedConfiguration()` | Configuration after inheritance, day/night and weather composition (internal `_Weather` data included). |
| `ExportConfiguration({ Format = "table" \| "json" \| "document", Resolved?, Metadata?, Pretty? })` | Deterministic export. |
| `ImportConfiguration(data, { Apply = true, Merge = false, DryRun = false })` | Table, `VisualFXConfig` document or JSON text; validated before anything is applied. |
| `GenerateCode(config?, options?)` | Luau source (see `Codegen/LuauGenerator.luau`). |

## Quality and diagnostics

| Method | Description |
| --- | --- |
| `SetQuality(level, overrides?)` | `Low`, `Medium`, `High`, `Ultra`, `Custom`; stored in the `Quality` section. |
| `GetQuality()` | `{ Level, Profile }`. |
| `GetPerformanceStats()` | `ActiveParticleSystems`, `CulledParticleSystems`, `EstimatedParticleRate`, `EstimatedLiveParticles`, `ParticleBudget`, `BudgetScale`, `RateScale`, `QualityDisabledSystems`, `ManagedInstances`, `PooledInstances`, `UpdateFrequency`, `TransitionFrequency`, `WeatherFrequency`, `ActiveTransition`, `RuntimeControllers`, `LastStepCostMs`. |
| `GetCompatibilityReport()` | Supported / unsupported schema properties on the running engine. |

## Extensibility

```lua
VisualFX:RegisterEffect({
    Name = "Fireflies",
    Category = "Particles",
    Schema = { Rate = { Kind = "number", Min = 0, Default = 10 }, Position = { Kind = "Vector3", Required = true } },
    Create = function(config, context) ... return instance end,
    Update = function(instance, config, context) ... end,   -- optional
    Remove = function(instance, context) ... end,           -- optional (default: removed by VisualFX)
    Validate = function(config, report) ... end,            -- optional extra checks
})
VisualFX:CreateEffect("Grove", { Effect = "Fireflies", Position = Vector3.new(0, 3, 0) })
VisualFX:RemoveEffect("Grove")

VisualFX:RegisterWeather({ Name = "Pollen", Defaults = {...}, Targets = {...}, Particles = {...}, Audio = {...} })
VisualFX:RegisterParticleTemplate("Bubbles", { Description = "...", Defaults = {...} })
```

Custom effects get identity, duplicate prevention, diffing, previews and
cleanup for free. `Update` is only called when the effect's configuration
fingerprint changes.

## Events

`VisualFX.Events.<Name>:Connect(fn)`:

| Event | Payload |
| --- | --- |
| `Changed` | the result of any mutation |
| `EffectCreated` / `EffectRemoved` | `{ ID, Type, Instance? }` |
| `TransitionStarted` / `TransitionCompleted` | `{ Id, Duration }` / `{ Id, Cancelled, Result }` |
| `WeatherChanged` | `{ Previous, Current, Intensity }` |
| `LightningStrike` | `{ Intensity, Time, ThunderDelay }` |
| `AudioHook` | `{ Hook, Action = "Start" \| "Stop" \| "Update" \| "Trigger", Volume, Delay? }` |
| `QualityChanged` | `{ Level, Profile }` |
| `Warning` | message |

`VisualFX:SetAudioHandler(fn)` is a convenience for wiring audio hooks.

## Lifecycle

`Start()`, `Stop()`, `Step(dt)` (drive manually when `AutoStart = false`), `Destroy()`.

## Inspection format

```lua
{
    Lighting = { Properties = {...}, ManagedProperties = { "Brightness", ... } },
    Atmosphere = { { Name, ClassName, Path, Classification, ID?, Properties } },
    Sky = {...}, Clouds = {...}, PostProcessing = {...},
    Water = { Properties = {...}, ManagedProperties = {...} },
    Weather = { Active, Type, Intensity, Wind, Lightning, AudioHooks, Components, Particles },
    Particles = { Managed = {...}, Developer = {...}, Truncated? },
    Environment = { GlobalWind, DayNight, Zones },
    ManagedEffects = { { ID, Type, Section, Owner, ClassName, Path, Adopted } },
    Conflicts = { { Code, Severity, Message, Paths, Suggestion } },
    Quality = { Level, Profile, Stats },
    Configuration = {...},
    Unknown = { { Path, ClassName } },
    Transition = nil | { Id, Duration, Elapsed, Progress, Tracks },
    Previewing = false,
    Summary = { "Lighting: ClockTime 17.9, ...", ... },
}
```

Classifications: `Managed`, `Adopted`, `RobloxDefault` (all properties equal a
fresh instance's, determined by inspecting the engine), `Developer`, `Unknown`.

## Compatibility layer

```lua
local Compatibility = require(VisualFX.Core.Compatibility) -- or engine.Compatibility
Compatibility.Default:IsSupported("Lighting.EnvironmentDiffuseScale")
Compatibility.Default:GetPropertySupport("Lighting", "EnvironmentDiffuseScale")
-- { ClassName, Property, Supported, Readable, Reason, ValueType, Default }
```

## Managed identity

| Attribute | Example |
| --- | --- |
| `VisualFX_Managed` | `true` |
| `VisualFX_ID` | `"weather.rain.primary"` |
| `VisualFX_Type` | `"Rain"` |
| `VisualFX_Section` | `"Weather"` |
| `VisualFX_Owner` | `"Weather"`, `"Particles"`, `"Zone"`, `"Effects"` |
| `VisualFX_Adopted` | `true` for adopted developer instances |
| `VisualFX_Orig_<Property>` | original value recorded before VisualFX changed it |

Plus the CollectionService tag `VisualFX`. (Roblox attribute names cannot
contain `.`, so `VisualFX.Managed` is spelled `VisualFX_Managed`.)

ID scheme: `lighting`, `water`, `environment.wind`, `atmosphere.primary`,
`sky.primary`, `clouds.primary`, `postprocessing.<effect>`,
`particles.<name>` (+ `.host`), `weather.<component>.primary`,
`weather.lightning.flash`, `zone.<name>`, `effect.<id>`,
`water.underwater.colorcorrection`, `water.underwater.blur`, `root`
(the `Workspace.VisualFX` folder).
