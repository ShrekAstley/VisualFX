--[[
	VisualFX.Runtime.Weather

	High-level weather built by composing lower-level systems. A weather type
	is pure data describing how it influences each system:

	  Thunderstorm
	  ├── Atmosphere        (targets blended by Intensity)
	  ├── Lighting          (targets blended by Intensity)
	  ├── Clouds            (targets blended by Intensity)
	  ├── PostProcessing    (targets blended by Intensity)
	  ├── Rain              (particle component, rate scaled by Intensity)
	  ├── Wind              (Workspace.GlobalWind + particle drift)
	  ├── Fog               (atmosphere density/haze boost, optional mist)
	  ├── Lightning         (flash controller + LightningStrike event)
	  └── AmbientAudioHooks (AudioHook events; no audio is played by VisualFX)

	Resolution is deterministic: the same configuration always produces the
	same concrete Atmosphere/Lighting/Particles values. Weather blends from
	the scene's own values (or Roblox defaults when a section is not set)
	toward the weather's targets by Intensity.
]]

local Core = script.Parent.Parent.Core
local Util = require(Core.Util)
local Values = require(Core.Values)
local Config = require(Core.Config)
local Particles = require(script.Parent.Particles)

local Weather = {}

Weather.DEFAULT_WIND_DIRECTION = Vector3.new(1, 0, 0.35).Unit

local rgb = Color3.fromRGB

Weather.Types = {
	Clear = {
		Description = "Clear skies, crisp air.",
		Category = "Fair",
		Defaults = { Intensity = 1, Wind = 4, Fog = 0 },
		Targets = {
			Atmosphere = { Density = 0.28, Haze = 0.5, Glare = 0.2 },
			Clouds = { Cover = 0.15, Density = 0.4 },
		},
		Audio = { "Birds" },
	},
	Cloudy = {
		Description = "Partly cloudy.",
		Category = "Fair",
		Defaults = { Intensity = 0.6, Wind = 8, Fog = 0 },
		Targets = {
			Atmosphere = { Density = 0.33, Haze = 1 },
			Clouds = { Cover = 0.7, Density = 0.6 },
			Lighting = { Brightness = 1.8 },
		},
		Audio = { "Wind" },
	},
	Overcast = {
		Description = "Fully overcast, flat grey light.",
		Category = "Fair",
		Defaults = { Intensity = 0.8, Wind = 10, Fog = 0.15 },
		Targets = {
			Atmosphere = { Density = 0.4, Haze = 2, Glare = 0, Color = rgb(180, 185, 190), Decay = rgb(120, 125, 130) },
			Clouds = { Cover = 0.95, Density = 0.75, Color = rgb(200, 202, 205) },
			Lighting = { Brightness = 1.2, ExposureCompensation = -0.1 },
			PostProcessing = { ColorCorrection = { Saturation = -0.15 } },
		},
		Audio = { "Wind" },
	},
	LightRain = {
		Description = "Light, steady rain.",
		Category = "Rain",
		Defaults = { Intensity = 0.45, Wind = 8, Fog = 0.2 },
		Targets = {
			Atmosphere = { Density = 0.42, Haze = 1.8, Glare = 0, Color = rgb(170, 180, 190), Decay = rgb(100, 110, 120) },
			Clouds = { Cover = 0.85, Density = 0.7, Color = rgb(190, 195, 200) },
			Lighting = { Brightness = 1.4, ExposureCompensation = -0.1 },
			PostProcessing = { ColorCorrection = { Saturation = -0.1 } },
		},
		Particles = { Rain = { Template = "Rain", Rate = 700, WindFactor = 0.6 } },
		Audio = { "Rain" },
	},
	HeavyRain = {
		Description = "Heavy downpour with low visibility.",
		Category = "Rain",
		Defaults = { Intensity = 0.8, Wind = 20, Fog = 0.35 },
		Targets = {
			Atmosphere = { Density = 0.52, Haze = 2.4, Glare = 0, Color = rgb(150, 160, 170), Decay = rgb(90, 95, 105) },
			Clouds = { Cover = 0.95, Density = 0.85, Color = rgb(160, 165, 172) },
			Lighting = { Brightness = 1.1, ExposureCompensation = -0.25 },
			PostProcessing = { ColorCorrection = { Saturation = -0.2, Contrast = 0.05 } },
		},
		Particles = { Rain = { Template = "Rain", Rate = 1100, WindFactor = 0.8, Speed = NumberRange.new(110, 140) } },
		Audio = { "Rain", "Wind" },
	},
	Thunderstorm = {
		Description = "Dark storm with heavy rain, wind and lightning.",
		Category = "Rain",
		Defaults = { Intensity = 0.9, Wind = 30, Fog = 0.4, Lightning = true },
		Targets = {
			Atmosphere = { Density = 0.58, Haze = 2.8, Glare = 0, Color = rgb(120, 130, 145), Decay = rgb(70, 75, 90) },
			Clouds = { Cover = 1, Density = 0.95, Color = rgb(110, 115, 125) },
			Lighting = { Brightness = 0.8, ExposureCompensation = -0.4, OutdoorAmbient = rgb(90, 95, 110) },
			PostProcessing = { ColorCorrection = { Saturation = -0.3, Contrast = 0.1, TintColor = rgb(225, 232, 255) } },
		},
		Particles = { Rain = { Template = "Rain", Rate = 1300, WindFactor = 1, Speed = NumberRange.new(120, 150) } },
		Lightning = { Frequency = 6 },
		Audio = { "Rain", "Wind", "Thunder" },
	},
	Snow = {
		Description = "Gentle snowfall.",
		Category = "Snow",
		Defaults = { Intensity = 0.6, Wind = 6, Fog = 0.25 },
		Targets = {
			Atmosphere = { Density = 0.45, Haze = 2, Glare = 0.1, Color = rgb(215, 225, 235), Decay = rgb(160, 170, 185) },
			Clouds = { Cover = 0.85, Density = 0.7, Color = rgb(235, 238, 242) },
			Lighting = { Brightness = 1.6, OutdoorAmbient = rgb(170, 175, 190) },
			PostProcessing = { ColorCorrection = { Saturation = -0.1, TintColor = rgb(240, 245, 255) } },
		},
		Particles = { Snow = { Template = "Snow", Rate = 350, WindFactor = 0.3 } },
		Audio = { "Wind" },
	},
	Blizzard = {
		Description = "Violent snowstorm with near-zero visibility.",
		Category = "Snow",
		Defaults = { Intensity = 0.9, Wind = 45, Fog = 0.7 },
		Targets = {
			Atmosphere = { Density = 0.7, Haze = 4, Glare = 0, Color = rgb(215, 222, 232), Decay = rgb(175, 185, 200) },
			Clouds = { Cover = 1, Density = 1, Color = rgb(220, 224, 230) },
			Lighting = { Brightness = 1.2, OutdoorAmbient = rgb(180, 185, 200), ExposureCompensation = 0.1 },
			PostProcessing = { ColorCorrection = { Saturation = -0.25, TintColor = rgb(235, 242, 255) } },
		},
		Particles = { Snow = { Template = "Snow", Rate = 900, WindFactor = 0.8, Speed = NumberRange.new(10, 18) } },
		Audio = { "Wind", "Blizzard" },
	},
	Fog = {
		Description = "Dense, still fog.",
		Category = "Fog",
		Defaults = { Intensity = 0.7, Wind = 2, Fog = 0.8 },
		Targets = {
			Atmosphere = { Density = 0.6, Offset = 0, Haze = 3, Glare = 0, Color = rgb(190, 195, 200), Decay = rgb(150, 155, 162) },
			Clouds = { Cover = 0.9, Density = 0.6 },
			Lighting = { Brightness = 1.3 },
			PostProcessing = { ColorCorrection = { Saturation = -0.15, Contrast = -0.05 } },
		},
		Particles = { Fog = { Template = "Fog", Rate = 10 } },
		Audio = {},
	},
	DustStorm = {
		Description = "Brown haze with blowing dust.",
		Category = "Dust",
		Defaults = { Intensity = 0.7, Wind = 30, Fog = 0.5 },
		Targets = {
			Atmosphere = { Density = 0.6, Haze = 5, Glare = 0.4, Color = rgb(200, 165, 120), Decay = rgb(150, 110, 70) },
			Clouds = { Cover = 0.6, Density = 0.5, Color = rgb(210, 180, 140) },
			Lighting = { Brightness = 1.6, OutdoorAmbient = rgb(160, 130, 100) },
			PostProcessing = { ColorCorrection = { Saturation = -0.05, TintColor = rgb(255, 235, 205) } },
		},
		Particles = { Dust = { Template = "Dust", Rate = 300, WindFactor = 0.5, Speed = NumberRange.new(4, 10) } },
		Audio = { "Wind", "Dust" },
	},
	Sandstorm = {
		Description = "Thick orange sandstorm.",
		Category = "Dust",
		Defaults = { Intensity = 0.85, Wind = 50, Fog = 0.75 },
		Targets = {
			Atmosphere = { Density = 0.75, Haze = 7, Glare = 0.6, Color = rgb(230, 170, 100), Decay = rgb(170, 100, 50) },
			Clouds = { Cover = 0.4, Density = 0.4, Color = rgb(230, 190, 140) },
			Lighting = { Brightness = 1.8, OutdoorAmbient = rgb(180, 140, 95), ExposureCompensation = 0.1 },
			PostProcessing = { ColorCorrection = { Saturation = 0.05, TintColor = rgb(255, 225, 185) } },
		},
		Particles = {
			Sand = {
				Template = "Dust",
				Rate = 700,
				WindFactor = 1,
				Color = ColorSequence.new(rgb(215, 170, 110)),
				Speed = NumberRange.new(8, 16),
			},
		},
		Audio = { "Wind", "Sand" },
	},
	Windy = {
		Description = "Strong wind with drifting debris.",
		Category = "Fair",
		Defaults = { Intensity = 0.6, Wind = 40, Fog = 0.05 },
		Targets = {
			Atmosphere = { Density = 0.32, Haze = 1.2 },
			Clouds = { Cover = 0.6, Density = 0.55 },
		},
		Particles = { Debris = { Template = "Dust", Rate = 60, WindFactor = 1, Speed = NumberRange.new(6, 12) } },
		Audio = { "Wind" },
	},
	Autumn = {
		Description = "Warm autumn light with falling leaves.",
		Category = "Seasonal",
		Defaults = { Intensity = 0.6, Wind = 10, Fog = 0.1 },
		Targets = {
			Atmosphere = { Density = 0.36, Haze = 1.5, Color = rgb(220, 190, 160), Decay = rgb(150, 100, 70) },
			Lighting = { ColorShiftTop = rgb(255, 210, 160) },
			PostProcessing = { ColorCorrection = { Saturation = 0.1, TintColor = rgb(255, 240, 220) } },
		},
		Particles = { Leaves = { Template = "Leaves", Rate = 16, WindFactor = 0.4 } },
		Audio = { "Wind", "Leaves" },
	},
	MagicalStorm = {
		Description = "Otherworldly storm with glowing particles and violet lightning.",
		Category = "Fantasy",
		Defaults = { Intensity = 0.8, Wind = 25, Fog = 0.4, Lightning = true },
		Targets = {
			Atmosphere = { Density = 0.5, Haze = 3, Glare = 1.5, Color = rgb(150, 110, 200), Decay = rgb(70, 40, 120) },
			Clouds = { Cover = 0.95, Density = 0.9, Color = rgb(120, 90, 170) },
			Lighting = { Brightness = 1, OutdoorAmbient = rgb(110, 80, 150), ExposureCompensation = -0.2 },
			PostProcessing = {
				ColorCorrection = { Saturation = 0.25, Contrast = 0.1, TintColor = rgb(235, 215, 255) },
				Bloom = { Intensity = 1.2, Size = 30, Threshold = 1.2 },
			},
		},
		Particles = {
			Magic = {
				Template = "Magic",
				Rate = 120,
				Attach = "Camera",
				Area = Vector3.new(120, 40, 120),
				Offset = Vector3.new(0, 10, 0),
				WindFactor = 0.3,
			},
		},
		Lightning = { Frequency = 8, Color = rgb(200, 150, 255) },
		Audio = { "Wind", "Thunder", "Magic" },
	},
	Custom = {
		Description = "No built-in influence; compose it with Weather.Particles and the other Weather fields.",
		Category = "Custom",
		Defaults = { Intensity = 1, Wind = 0, Fog = 0 },
		Targets = {},
		Audio = {},
	},
}

Weather.Fields = {
	{ Key = "Type", Kind = "string", Required = true, Description = "Weather type (see Weather.Types)." },
	{ Key = "Intensity", Kind = "number", Min = 0, Max = 1, Description = "0 = no influence, 1 = full weather." },
	{ Key = "Wind", Kind = "number", Min = 0, SoftMax = 150, Description = "Wind speed in studs/second (Workspace.GlobalWind)." },
	{ Key = "WindDirection", Kind = "Vector3", Description = "Wind direction (normalized; Y is ignored)." },
	{ Key = "Fog", Kind = "number", Min = 0, Max = 1, Description = "Extra fog on top of the weather type." },
	{ Key = "Lightning", Kind = "boolean", Description = "Enable lightning flashes." },
	{ Key = "LightningFrequency", Kind = "number", Min = 0, Max = 60, Description = "Average strikes per minute." },
	{ Key = "RainIntensity", Kind = "number", Min = 0, Max = 1, Description = "Overrides Intensity for the Rain component." },
	{ Key = "SnowIntensity", Kind = "number", Min = 0, Max = 1, Description = "Overrides Intensity for the Snow component." },
	{ Key = "DustIntensity", Kind = "number", Min = 0, Max = 1, Description = "Overrides Intensity for Dust/Sand/Debris components." },
	{ Key = "Attach", Kind = "string", Values = { "Camera", "World" }, Description = "Where weather particles are emitted." },
	{ Key = "Position", Kind = "Vector3", Description = "Center of weather particles when Attach = World." },
	{ Key = "Area", Kind = "Vector3", Min = 0, Description = "Emission volume size for weather particles." },
	{ Key = "Seed", Kind = "integer", Description = "Seed for deterministic lightning timing." },
	{ Key = "Particles", Kind = "map", ItemFields = Particles.ItemFields, Description = "Per-component particle overrides or extra components." },
}

local COMPONENT_INTENSITY_KEYS = {
	Rain = "RainIntensity",
	Snow = "SnowIntensity",
	Dust = "DustIntensity",
	Sand = "DustIntensity",
	Debris = "DustIntensity",
}

function Weather.RegisterTypes(registry)
	for _, name in ipairs(Util.sortedKeys(Weather.Types)) do
		local definition = Util.shallowCopy(Weather.Types[name])
		definition.Name = name
		registry:RegisterWeather(definition)
	end
end

-- Lists the lower-level systems a weather type is composed of.
function Weather.DescribeComposition(definition): { string }
	local parts = {}
	for _, section in ipairs(Util.sortedKeys(definition.Targets or {})) do
		table.insert(parts, section)
	end
	for _, component in ipairs(Util.sortedKeys(definition.Particles or {})) do
		table.insert(parts, component)
	end
	if (definition.Defaults and (definition.Defaults.Wind or 0) > 0) then
		table.insert(parts, "Wind")
	end
	if definition.Defaults and (definition.Defaults.Fog or 0) > 0 then
		table.insert(parts, "Fog")
	end
	if definition.Lightning then
		table.insert(parts, "Lightning")
	end
	if definition.Audio and #definition.Audio > 0 then
		table.insert(parts, "AmbientAudioHooks")
	end
	return parts
end

local function fieldDefault(registry, sectionName: string, key: string, nested: string?)
	local section = registry:GetSection(sectionName)
	if not section then
		return nil
	end
	local fields = section.Fields
	if nested then
		local owner = section.FieldIndex[nested]
		if not owner then
			return nil
		end
		for _, field in ipairs(owner.Fields) do
			if field.Key == key then
				return if field.Neutral ~= nil then field.Neutral else field.Default
			end
		end
		return nil
	end
	local field = section.FieldIndex[key]
	return field and field.Default
end

local function blendSection(registry, resolved, sectionName: string, targets, t: number, nested: string?)
	resolved[sectionName] = resolved[sectionName] or {}
	local container = resolved[sectionName]
	if nested then
		container[nested] = container[nested] or {}
		container = container[nested]
	end
	for _, key in ipairs(Util.sortedKeys(targets)) do
		local target = targets[key]
		local base = container[key]
		if base == nil then
			base = fieldDefault(registry, sectionName, key, nested)
		end
		if base == nil or typeof(base) ~= typeof(target) then
			container[key] = if t >= 0.5 then target else base
		else
			container[key] = Values.lerp(base, target, t)
		end
	end
end

--[[
	Expands resolved.Weather into concrete section values. Mutates `resolved`
	and records internal data under resolved._Weather:
	  { Type, Intensity, Particles = { [component] = mergedConfig }, Lightning, Audio, Wind }
]]
function Weather.Resolve(registry, resolved: { [string]: any }, authored: { [string]: any })
	local config = resolved.Weather
	if not config then
		return
	end
	local definition, typeName = registry:FindWeather(config.Type)
	if not definition then
		return
	end
	local defaults = definition.Defaults or {}
	local intensity = config.Intensity or defaults.Intensity or 1

	-- 1. Blend section targets.
	for _, sectionName in ipairs(Util.sortedKeys(definition.Targets or {})) do
		local targets = definition.Targets[sectionName]
		local weight = intensity * (definition.Weight or 1)
		if sectionName == "PostProcessing" then
			for _, effect in ipairs(Util.sortedKeys(targets)) do
				blendSection(registry, resolved, "PostProcessing", targets[effect], weight, effect)
			end
		else
			blendSection(registry, resolved, sectionName, targets, weight)
		end
	end

	-- 2. Fog boost.
	local fog = config.Fog
	if fog == nil then
		fog = (defaults.Fog or 0) * intensity
	end
	if fog > 0 then
		resolved.Atmosphere = resolved.Atmosphere or {}
		local atmosphere = resolved.Atmosphere
		local density = atmosphere.Density or fieldDefault(registry, "Atmosphere", "Density") or 0.395
		local haze = atmosphere.Haze or 0
		atmosphere.Density = Util.clamp(density + fog * 0.3, 0, 1)
		atmosphere.Haze = Util.clamp(haze + fog * 2.5, 0, 10)
	end

	-- 3. Wind.
	local windSpeed = config.Wind
	if windSpeed == nil then
		windSpeed = (defaults.Wind or 0) * math.max(intensity, 0.25)
	end
	local direction = config.WindDirection or Weather.DEFAULT_WIND_DIRECTION
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 1e-3 then
		direction = Weather.DEFAULT_WIND_DIRECTION
	end
	direction = direction.Unit
	local authoredWind = authored.Environment and authored.Environment.Wind
	if not authoredWind then
		resolved.Environment = resolved.Environment or {}
		resolved.Environment.Wind = { Direction = direction, Speed = windSpeed }
	end

	-- 4. Particle components.
	local components = {}
	local overrides = config.Particles or {}
	local definitionParticles = definition.Particles or {}
	local names = Util.sortedKeys(definitionParticles)
	for _, extra in ipairs(Util.sortedKeys(overrides)) do
		Util.addUnique(names, extra)
	end
	if fog >= 0.45 and not definitionParticles.Fog and not overrides.Fog then
		table.insert(names, "Mist")
	end
	for _, component in ipairs(names) do
		local base = definitionParticles[component]
		local override = overrides[component]
		if override == Config.REMOVE then
			continue
		end
		local declared = Util.deepCopy(base or {})
		if component == "Mist" and not base then
			declared = { Template = "Mist", Rate = 14 * fog }
		end
		local windFactor = declared.WindFactor or 0
		declared.WindFactor = nil
		if override then
			for key, value in pairs(override) do
				declared[key] = value
			end
		end
		local merged = Particles.Merge(registry, component, declared)
		local intensityKey = COMPONENT_INTENSITY_KEYS[component]
		local componentIntensity = (intensityKey and config[intensityKey]) or intensity
		if override and override.Rate then
			merged.Rate = override.Rate
		else
			merged.Rate = (merged.Rate or 0) * componentIntensity
		end
		if windFactor > 0 and windSpeed > 0 then
			merged.Acceleration = (merged.Acceleration or Vector3.new(0, 0, 0)) + direction * windSpeed * windFactor
		end
		if config.Attach then
			merged.Attach = config.Attach
		end
		if config.Position then
			merged.Position = config.Position
		end
		if config.Area then
			merged.Area = config.Area
		end
		if merged.Rate > 0 then
			components[component] = merged
		end
	end

	-- 5. Lightning.
	local lightningEnabled = config.Lightning
	if lightningEnabled == nil then
		lightningEnabled = defaults.Lightning == true
	end
	local lightning = nil
	if lightningEnabled then
		local base = definition.Lightning or {}
		lightning = {
			Frequency = config.LightningFrequency or (base.Frequency or 4) * math.max(intensity, 0.2),
			Color = base.Color or Color3.fromRGB(220, 230, 255),
			Intensity = intensity,
			Seed = config.Seed or 1,
		}
	end

	-- 6. Audio hooks.
	local audio = {}
	for _, hook in ipairs(definition.Audio or {}) do
		Util.addUnique(audio, hook)
	end
	if lightning then
		Util.addUnique(audio, "Thunder")
	end
	table.sort(audio)

	resolved._Weather = {
		Type = typeName,
		Intensity = intensity,
		Particles = components,
		Lightning = lightning,
		Audio = audio,
		Wind = direction * windSpeed,
		Composition = Weather.DescribeComposition(definition),
	}
end

function Weather.Register(registry)
	Weather.RegisterTypes(registry)
	registry:RegisterSection({
		Name = "Weather",
		Order = 70,
		Description = "High-level weather composed of atmosphere, lighting, clouds, particles, wind, fog, lightning and audio hooks.",
		Fields = Weather.Fields,
		Coerce = function(value)
			if typeof(value) == "string" then
				return { Type = value }
			end
			return value
		end,
		Validate = function(section, report)
			if section.Type and not registry:FindWeather(section.Type) then
				local suggestion = Util.suggest(section.Type, registry:ListWeather())
				report:Error(
					"Weather.Type",
					"UnknownWeather",
					string.format(
						"Weather.Type: unknown weather type '%s'%s. Available: %s",
						section.Type,
						if suggestion then " (did you mean '" .. suggestion .. "'?)" else "",
						table.concat(registry:ListWeather(), ", ")
					)
				)
			elseif section.Type then
				local _, canonical = registry:FindWeather(section.Type)
				section.Type = canonical
			end
			for name, item in pairs(section.Particles or {}) do
				if typeof(item) == "table" and item.Template and not registry:FindParticleTemplate(item.Template) then
					report:Error(
						"Weather.Particles." .. name .. ".Template",
						"UnknownTemplate",
						string.format("unknown particle template '%s'", tostring(item.Template))
					)
				end
			end
		end,
		Desired = function(_section, context, resolved)
			local weather = resolved._Weather
			local specs = {}
			if not weather then
				return specs
			end
			for _, component in ipairs(Util.sortedKeys(weather.Particles)) do
				local host, emitter = Particles.BuildSpecs(weather.Particles[component], context, {
					ID = "weather." .. string.lower(component) .. ".primary",
					Type = component,
					Owner = "Weather",
					Priority = 10,
				})
				table.insert(specs, host)
				table.insert(specs, emitter)
			end
			if weather.Lightning then
				table.insert(specs, {
					ID = "weather.lightning.flash",
					Type = "Lightning",
					ClassName = "ColorCorrectionEffect",
					Name = "VisualFX_LightningFlash",
					Parent = context.Lighting,
					Owner = "Weather",
					Properties = { Enabled = true, Brightness = 0, Contrast = 0, Saturation = 0, TintColor = weather.Lightning.Color },
					RuntimeProperties = { Brightness = true, Contrast = true },
				})
			end
			return specs
		end,
		Inspect = function(context)
			local resolved = context.Engine:GetResolvedConfiguration()
			local weather = resolved._Weather
			if not weather then
				return { Active = false }
			end
			local particles = {}
			for name, config in pairs(weather.Particles) do
				particles[name] = { Template = config.Template, Rate = config.Rate }
			end
			return {
				Active = true,
				Type = weather.Type,
				Intensity = weather.Intensity,
				Wind = weather.Wind,
				Lightning = weather.Lightning ~= nil,
				AudioHooks = weather.Audio,
				Components = weather.Composition,
				Particles = particles,
			}
		end,
	})
end

--[[
	Runtime controller for lightning. Strike timing uses a seeded Random so a
	given configuration produces the same sequence of strikes. Each strike
	briefly brightens the managed flash ColorCorrection, then fires
	Events.LightningStrike and an AudioHook "Thunder" trigger with a delay
	(sound travels slower than light), leaving playback to the game.
]]
function Weather.CreateController(engine)
	local controller = {
		Name = "Lightning",
		_accumulated = 0,
		_flash = 0,
		_flashDuration = 0.35,
		_random = nil,
		_seed = nil,
		Strikes = 0,
	}

	function controller:Strike(intensity: number?)
		local resolved = engine:GetResolvedConfiguration()
		local weather = resolved._Weather
		local strength = intensity or (weather and weather.Intensity) or 1
		self._flash = self._flashDuration
		self._strength = strength
		self.Strikes += 1
		local random = self._random or Random.new(1)
		local delaySeconds = random:NextNumber(0.4, 3)
		engine.Events.LightningStrike:Fire({ Intensity = strength, Time = os.clock(), ThunderDelay = delaySeconds })
		engine.Events.AudioHook:Fire({ Hook = "Thunder", Action = "Trigger", Volume = strength, Delay = delaySeconds })
	end

	function controller:Step(dt: number)
		local resolved = engine:GetResolvedConfiguration()
		local weather = resolved._Weather
		local lightning = weather and weather.Lightning
		local flash = engine.InstanceManager:Find("weather.lightning.flash")
		if not lightning or not flash then
			self._flash = 0
			return
		end
		if self._seed ~= lightning.Seed then
			self._seed = lightning.Seed
			self._random = Random.new(lightning.Seed)
		end
		if self._flash > 0 then
			self._flash = math.max(0, self._flash - dt)
			local alpha = self._flash / self._flashDuration
			-- Double flicker: bright, dip, bright, fade.
			local flicker = if alpha > 0.7 then 1 elseif alpha > 0.55 then 0.35 else alpha / 0.55
			local brightness = 0.45 * (self._strength or 1) * flicker
			engine.Compatibility:SetProperty(flash, "Brightness", brightness)
			engine.Compatibility:SetProperty(flash, "Contrast", 0.15 * flicker)
		elseif flash.Brightness ~= 0 then
			engine.Compatibility:SetProperty(flash, "Brightness", 0)
			engine.Compatibility:SetProperty(flash, "Contrast", 0)
		end
		local profile = engine.Quality:GetProfile()
		self._accumulated += dt
		local interval = 1 / math.max(1, profile.WeatherFrequency)
		if self._accumulated < interval then
			return
		end
		local elapsed = self._accumulated
		self._accumulated = 0
		local probability = (lightning.Frequency / 60) * elapsed
		if self._random:NextNumber() < probability then
			self:Strike(lightning.Intensity)
		end
	end

	return controller
end

--[[
	Computes AudioHook Start/Stop/Update events between two resolved states.
]]
function Weather.DiffAudio(previous, current): { { Hook: string, Action: string, Volume: number } }
	local events = {}
	local before = previous and previous.Audio or {}
	local after = current and current.Audio or {}
	local volume = current and current.Intensity or 0
	for _, hook in ipairs(before) do
		if not table.find(after, hook) then
			table.insert(events, { Hook = hook, Action = "Stop", Volume = 0 })
		end
	end
	for _, hook in ipairs(after) do
		if not table.find(before, hook) then
			table.insert(events, { Hook = hook, Action = "Start", Volume = volume })
		elseif previous and previous.Intensity ~= volume then
			table.insert(events, { Hook = hook, Action = "Update", Volume = volume })
		end
	end
	return events
end

return Weather
