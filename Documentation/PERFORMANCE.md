# Performance

VisualFX keeps performance controllable through **quality profiles**,
**deterministic budgets** and **write-only-on-change** runtime updates. It
reports workload estimates; it never claims FPS numbers, because frame cost
depends on the device, the rest of the game and the engine.

## Quality profiles

```lua
VisualFX:SetQuality("Medium")
VisualFX:SetQuality("Custom", { MaxParticleRate = 2500, UpdateFrequency = 20 })
```

| Setting | Low | Medium | High | Ultra | Meaning |
| --- | --- | --- | --- | --- | --- |
| `ParticleRateScale` | 0.3 | 0.6 | 1 | 1 | Multiplier on every particle system's `Rate` |
| `MaxParticleRate` | 800 | 2000 | 4000 | 8000 | Total emitted particles/second across managed systems |
| `MaxParticleSystems` | 4 | 8 | 16 | 32 | Active managed particle systems |
| `UpdateFrequency` (Hz) | 10 | 15 | 30 | 60 | Camera-follow, culling, day/night, zone blending |
| `TransitionFrequency` (Hz) | 15 | 20 | 30 | 60 | Transition property updates |
| `WeatherFrequency` (Hz) | 5 | 10 | 15 | 30 | Lightning simulation |
| `ActivationDistance` (studs) | 250 | 400 | 700 | 1200 | Default cull distance for world-attached systems and zones |
| `SpatialCulling` | on | on | on | on | Disable distant world systems on clients |
| Post-processing | ColorCorrection only | + Bloom, Blur | + SunRays, DepthOfField | all | Effects disallowed by the level are kept but disabled |

The level is part of the configuration (`Quality` section), so exported scenes
carry their performance settings. `Custom` starts from `High` and applies overrides.

## Budgets (applied when the scene is planned)

1. Every system's configured `Rate` × `ParticleRateScale`.
2. If more than `MaxParticleSystems` systems are enabled, the lowest
   `Priority` systems are disabled (ties broken by ID, so the result is
   deterministic). Weather particles have priority 10, user systems 5, zones 4.
3. If the total rate still exceeds `MaxParticleRate`, all rates are scaled down
   proportionally.

The validator adds `PerformanceBudget` warnings when a configuration will be
throttled, and `GetPerformanceStats()` reports what was applied.

## Runtime costs and how they are bounded

| Mechanism | Cost control |
| --- | --- |
| Single scheduler | One Heartbeat connection per engine; controllers self-throttle to their frequency |
| Write-on-change | Transitions and controllers compare with tolerance (float32-aware) before writing a property |
| Camera-attached weather | Emission volume moves only when the camera moved more than one stud |
| Spatial culling | Distant world systems/zones are disabled on clients (`CullDistance` or `ActivationDistance`) |
| Pooling | Removed emitter parts are reused for new systems (up to 16 pooled instances) |
| Object reuse | Instances are found by managed identity and updated in place; re-applying a scene is a no-op |
| Automatic cleanup | Weather/zone changes remove what they no longer need; `ResetManagedEffects` removes everything |
| Bounded scans | Identity lookups use CollectionService tags plus scans of Lighting, Terrain, `Workspace.VisualFX` and the camera only |
| Server vs client | Run weather from a LocalScript: particle simulation and camera logic stay on the client that sees them |

## Diagnostics

```lua
local stats = VisualFX:GetPerformanceStats()
-- {
--   Quality = "High",
--   ActiveParticleSystems = 4,
--   CulledParticleSystems = 1,
--   EstimatedParticleRate = 1180,       -- particles emitted per second
--   EstimatedLiveParticles = 1520,      -- rate × average lifetime
--   ParticleBudget = 4000,
--   BudgetScale = 1,                    -- < 1 when the budget throttled rates
--   RateScale = 1,
--   QualityDisabledSystems = {},
--   ManagedInstances = 14,
--   PooledInstances = 0,
--   UpdateFrequency = 30, TransitionFrequency = 30, WeatherFrequency = 15,
--   ActiveTransition = nil,
--   RuntimeControllers = true,
--   LastStepCostMs = 0.04,              -- CPU time of the last VisualFX step
-- }
```

`DetectConflicts()` also reports `DeveloperParticleLoad` when unmanaged
emitters exceed the profile's budget (VisualFX cannot throttle those).

## Guidelines

* Prefer a few large emitters with moderate rates over many small ones.
* Keep `Lifetime` short for fast particles (rain): live particles ≈ rate × lifetime.
* Fog banks: large `Size`, low `Rate`, long `Lifetime`, high `Transparency`.
* Use zones with `CullDistance` for local effects instead of camera-attached systems.
* Transition durations do not change cost per frame; `TransitionFrequency` does.
* On mobile-heavy games start from `Medium` and raise it with a settings menu.
