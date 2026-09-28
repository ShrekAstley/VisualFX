# Examples

Runnable scripts live in `Examples/`. Snippets assume
`local VisualFX = require(game:GetService("ReplicatedStorage").VisualFX)`.

## Apply a preset from the server

```lua
VisualFX:ApplyPreset("CinematicSunset")
```

## Build a scene piece by piece

```lua
VisualFX:SetAtmosphere({
    Density = 0.35,
    Haze = 2,
    Glare = 0.15,
    Color = Color3.fromRGB(190, 205, 220),
    Decay = Color3.fromRGB(80, 100, 120),
})

VisualFX:SetLighting({ ClockTime = 18.5, Brightness = 2, ExposureCompensation = 0.2 })

VisualFX:SetWater({
    Color = Color3.fromRGB(35, 90, 120),
    Transparency = 0.25,
    Reflectance = 0.7,
    WaveStrength = 0.35, -- alias of WaveSize
    WaveSpeed = 10,
})

VisualFX:CreateParticleSystem("Rain", {
    Rate = 600,
    Lifetime = NumberRange.new(1, 2),
    Speed = NumberRange.new(80, 120),
    Size = NumberSequence.new(0.08),
    Color = ColorSequence.new(Color3.fromRGB(180, 200, 255)),
    Transparency = NumberSequence.new(0.35),
})

VisualFX:CreateWeather("HeavyRain", { Intensity = 0.8, Wind = 25, Fog = 0.3, Lightning = true })

VisualFX:CreateZone("ForestFog", {
    Position = Vector3.new(0, 30, 0),
    Size = Vector3.new(500, 100, 500),
    Effect = "Fog",
    Intensity = 0.7,
})
```

## Describe a scene

```lua
local result = VisualFX:CreateScene({
    Mood = "mysterious",
    Time = "sunset",
    Weather = "light_rain",
    Environment = "dense_forest",
    Fog = "medium",
    LightingStyle = "cinematic",
    WaterStyle = "calm_reflective",
})
print(result.Created, result.Modified, result.Removed, result.Warnings)
for _, line in ipairs(result.Interpretation) do
    print(line)
end
```

## Weather that changes over time (client)

```lua
-- StarterPlayerScripts/Weather.client.luau
VisualFX:ApplyPreset("Forest")
task.wait(30)
VisualFX:TransitionTo({ Duration = 10, Configuration = { Weather = { Type = "LightRain", Intensity = 0.4 } } })
task.wait(30)
VisualFX:TransitionTo({ Duration = 8, Configuration = { Weather = { Type = "Thunderstorm", Intensity = 0.9 } } })
```

## Day/night cycle

```lua
VisualFX:SetDayNightCycle({ Enabled = true, DayLength = 20, StartTime = 6, DriveLighting = true })
```

## Hooking weather audio

```lua
local sounds = { Rain = workspace.Sounds.Rain, Wind = workspace.Sounds.Wind, Thunder = workspace.Sounds.Thunder }
VisualFX.Events.AudioHook:Connect(function(hook)
    local sound = sounds[hook.Hook]
    if not sound then
        return
    end
    if hook.Action == "Start" or hook.Action == "Update" then
        sound.Volume = hook.Volume
        sound:Play()
    elseif hook.Action == "Stop" then
        sound:Stop()
    elseif hook.Action == "Trigger" then
        task.delay(hook.Delay or 0, function()
            sound:Play()
        end)
    end
end)
```

## Custom effect type

```lua
VisualFX:RegisterEffect({
    Name = "Beacon",
    Category = "Lights",
    Schema = {
        Position = { Kind = "Vector3", Required = true },
        Color = { Kind = "Color3", Default = Color3.fromRGB(255, 200, 120) },
        Range = { Kind = "number", Min = 0, Max = 60, Default = 20 },
    },
    Create = function(config)
        local part = Instance.new("Part")
        part.Anchored, part.CanCollide, part.Transparency = true, false, 1
        part.Position = config.Position
        local light = Instance.new("PointLight")
        light.Color = config.Color or Color3.fromRGB(255, 200, 120)
        light.Range = config.Range or 20
        light.Parent = part
        return part
    end,
    Update = function(part, config)
        part.Position = config.Position
        local light = part:FindFirstChildOfClass("PointLight")
        light.Color = config.Color or light.Color
        light.Range = config.Range or light.Range
    end,
})

VisualFX:CreateEffect("HarborBeacon", { Effect = "Beacon", Position = Vector3.new(40, 12, -30), Range = 30 })
```

## Preview, compare, apply

```lua
local diff = VisualFX:DiffScene({ Weather = { Type = "Blizzard" } }, { Merge = true })
for _, line in ipairs(diff.Summary) do
    print(line) -- "+ Snow (weather.snow.primary)", "~ Atmosphere.Density: 0.35 -> 0.6", ...
end

VisualFX:Preview({ Weather = { Type = "Blizzard" } })
-- look at it...
VisualFX:RevertPreview() -- or VisualFX:CommitPreview()
```

## Export, import and code generation

```lua
local json = VisualFX:ExportConfiguration({ Format = "json" })
local result = VisualFX:ImportConfiguration(json)   -- validated before applying
print(VisualFX:GenerateCode(nil, { Template = "Module" }))
```

## AI agent workflow

See `Examples/AgentWorkflow.luau` and `Documentation/AI_AGENT_GUIDE.md`.
