--[[
	VisualFX.AI.VisualDirector

	Converts high-level scene descriptions into concrete, deterministic
	configurations. No external AI provider is involved: the vocabulary below
	is a fixed, inspectable mapping, so the same description always yields
	the same configuration. External agents can use it as-is or generate
	configurations themselves and call the API directly.

	  VisualFX:CreateScene({
	      Mood = "mysterious",
	      Time = "sunset",
	      Weather = "light_rain",
	      Environment = "dense_forest",
	      Fog = "medium",
	      LightingStyle = "cinematic",
	      WaterStyle = "calm_reflective",
	  })

	Composition order (later layers adjust earlier ones):
	  Time -> Environment -> Weather -> Fog -> Mood -> LightingStyle ->
	  WaterStyle -> explicit configuration sections in the description.

	CreateScene then: inspects the scene, plans against existing managed and
	adoptable instances (reuse/modify/create/remove), applies, and returns
	{ Success, Created, Modified, Removed, Warnings, Configuration, Interpretation }.
]]

local Root = script.Parent.Parent
local Util = require(Root.Core.Util)
local Values = require(Root.Core.Values)
local Config = require(Root.Core.Config)
local Environment = require(Root.Runtime.Environment)

local VisualDirector = {}
VisualDirector.__index = VisualDirector

local rgb = Color3.fromRGB

VisualDirector.DescriptionKeys = {
	Mood = true,
	Time = true,
	TimeOfDay = true,
	LightingStyle = true,
	WaterStyle = true,
	Style = true,
	Season = true,
	Intensity = true,
	WeatherIntensity = true,
}

---------------------------------------------------------------------------
-- Vocabulary
---------------------------------------------------------------------------

-- Adjustments are applied with these operators:
--   Set  = replace value        Add = add to number (then clamp)
--   Tint = multiply a Color3    (component-wise)

VisualDirector.Moods = {
	Mysterious = {
		Add = { ["Atmosphere.Density"] = 0.08, ["Atmosphere.Haze"] = 1, ["Lighting.ExposureCompensation"] = -0.1, ["PostProcessing.ColorCorrection.Saturation"] = -0.15, ["PostProcessing.ColorCorrection.Contrast"] = 0.08 },
		Set = { ["Atmosphere.Glare"] = 0, ["PostProcessing.ColorCorrection.TintColor"] = rgb(220, 230, 245) },
		Note = "cooler tint, lower saturation, denser haze",
	},
	Calm = {
		Add = { ["PostProcessing.ColorCorrection.Saturation"] = 0.05, ["PostProcessing.ColorCorrection.Contrast"] = -0.03 },
		Set = { ["PostProcessing.Bloom.Intensity"] = 0.5, ["PostProcessing.Bloom.Size"] = 26, ["PostProcessing.Bloom.Threshold"] = 1.8 },
		Note = "soft contrast and gentle bloom",
	},
	Cheerful = {
		Add = { ["PostProcessing.ColorCorrection.Saturation"] = 0.2, ["Lighting.ExposureCompensation"] = 0.15 },
		Set = { ["PostProcessing.ColorCorrection.TintColor"] = rgb(255, 250, 240), ["PostProcessing.Bloom.Intensity"] = 0.7, ["PostProcessing.Bloom.Size"] = 26, ["PostProcessing.Bloom.Threshold"] = 1.6 },
		Note = "bright, saturated and warm",
	},
	Eerie = {
		Add = { ["PostProcessing.ColorCorrection.Saturation"] = -0.45, ["PostProcessing.ColorCorrection.Contrast"] = 0.18, ["Lighting.ExposureCompensation"] = -0.3, ["Atmosphere.Density"] = 0.15, ["Atmosphere.Haze"] = 1.5 },
		Set = { ["PostProcessing.ColorCorrection.TintColor"] = rgb(215, 235, 215), ["Atmosphere.Glare"] = 0 },
		Note = "desaturated green-grey, heavy haze, dark exposure",
	},
	Epic = {
		Add = { ["PostProcessing.ColorCorrection.Contrast"] = 0.15, ["PostProcessing.ColorCorrection.Saturation"] = 0.1 },
		Set = { ["PostProcessing.SunRays.Intensity"] = 0.15, ["PostProcessing.SunRays.Spread"] = 0.8, ["PostProcessing.Bloom.Intensity"] = 0.9, ["PostProcessing.Bloom.Size"] = 30, ["PostProcessing.Bloom.Threshold"] = 1.5 },
		Note = "punchy contrast, sun rays and bloom",
	},
	Melancholic = {
		Add = { ["PostProcessing.ColorCorrection.Saturation"] = -0.3, ["Lighting.ExposureCompensation"] = -0.15 },
		Set = { ["PostProcessing.ColorCorrection.TintColor"] = rgb(220, 225, 235) },
		Note = "muted blue-grey",
	},
	Romantic = {
		Add = { ["PostProcessing.ColorCorrection.Saturation"] = 0.1 },
		Set = { ["PostProcessing.ColorCorrection.TintColor"] = rgb(255, 230, 215), ["PostProcessing.Bloom.Intensity"] = 0.8, ["PostProcessing.Bloom.Size"] = 32, ["PostProcessing.Bloom.Threshold"] = 1.4 },
		Note = "warm rose tint with soft bloom",
	},
	Tense = {
		Add = { ["PostProcessing.ColorCorrection.Contrast"] = 0.2, ["PostProcessing.ColorCorrection.Saturation"] = -0.15, ["Lighting.ExposureCompensation"] = -0.2 },
		Note = "hard contrast, darker exposure",
	},
	Dreamy = {
		Add = { ["PostProcessing.ColorCorrection.Saturation"] = 0.15, ["Atmosphere.Glare"] = 1 },
		Set = { ["PostProcessing.Bloom.Intensity"] = 1.3, ["PostProcessing.Bloom.Size"] = 36, ["PostProcessing.Bloom.Threshold"] = 1.1 },
		Note = "strong soft bloom and glare",
	},
	Serene = {
		Add = { ["PostProcessing.ColorCorrection.Contrast"] = -0.02, ["Atmosphere.Haze"] = 0.3 },
		Set = { ["PostProcessing.Bloom.Intensity"] = 0.5, ["PostProcessing.Bloom.Size"] = 24, ["PostProcessing.Bloom.Threshold"] = 1.8 },
		Note = "clean, open and quiet",
	},
	Ominous = {
		Add = { ["PostProcessing.ColorCorrection.Contrast"] = 0.15, ["PostProcessing.ColorCorrection.Saturation"] = -0.25, ["Lighting.ExposureCompensation"] = -0.35, ["Atmosphere.Density"] = 0.08 },
		Set = { ["PostProcessing.ColorCorrection.TintColor"] = rgb(225, 225, 240) },
		Note = "dark, heavy and cold",
	},
}
VisualDirector.MoodAliases = {
	Mystery = "Mysterious", Peaceful = "Calm", Happy = "Cheerful", Joyful = "Cheerful",
	Horror = "Eerie", Creepy = "Eerie", Scary = "Eerie", Spooky = "Eerie",
	Heroic = "Epic", Sad = "Melancholic", Gloomy = "Melancholic", Cozy = "Romantic", Warm = "Romantic",
	Dramatic = "Tense", Magical = "Dreamy", Tranquil = "Serene", Dark = "Ominous", Menacing = "Ominous",
}

VisualDirector.Environments = {
	DenseForest = {
		Set = { ["Atmosphere.Color"] = rgb(170, 190, 170), ["Atmosphere.Decay"] = rgb(80, 100, 80) },
		Add = { ["Atmosphere.Density"] = 0.06, ["Atmosphere.Haze"] = 0.5 },
		Tint = { ["Lighting.OutdoorAmbient"] = rgb(215, 235, 205) },
		Particles = { Day = { Mist = { Template = "Mist", Rate = 10 }, Dust = { Template = "Dust", Rate = 12, Color = rgb(235, 235, 200) } }, Night = { Mist = { Template = "Mist", Rate = 10 }, Fireflies = { Template = "Fireflies", Rate = 8 } } },
		Water = { Color = rgb(45, 75, 60), Transparency = 0.2, Reflectance = 0.7 },
		Note = "green canopy light, low mist; fireflies at night",
	},
	Forest = {
		Set = { ["Atmosphere.Color"] = rgb(185, 200, 185), ["Atmosphere.Decay"] = rgb(95, 115, 95) },
		Add = { ["Atmosphere.Haze"] = 0.3 },
		Tint = { ["Lighting.OutdoorAmbient"] = rgb(225, 240, 215) },
		Particles = { Day = { Dust = { Template = "Dust", Rate = 10, Color = rgb(235, 235, 200) } }, Night = { Fireflies = { Template = "Fireflies", Rate = 5 } } },
		Note = "light green ambient",
	},
	Desert = {
		Set = { ["Atmosphere.Color"] = rgb(230, 200, 160), ["Atmosphere.Decay"] = rgb(170, 120, 80) },
		Add = { ["Atmosphere.Glare"] = 0.5, ["Atmosphere.Haze"] = 1 },
		Tint = { ["Lighting.OutdoorAmbient"] = rgb(255, 235, 205) },
		Particles = { Day = { Dust = { Template = "Dust", Rate = 25 } } },
		Note = "warm haze, heat glare and dust",
	},
	Arctic = {
		Set = { ["Atmosphere.Color"] = rgb(215, 228, 240), ["Atmosphere.Decay"] = rgb(150, 170, 200) },
		Tint = { ["Lighting.OutdoorAmbient"] = rgb(225, 235, 255) },
		Water = { Color = rgb(60, 100, 130), Transparency = 0.3, WaveSize = 0.05, WaveSpeed = 4 },
		Note = "cold blue-white air",
	},
	Ocean = {
		Set = { ["Atmosphere.Offset"] = 0.3, ["Atmosphere.Color"] = rgb(190, 215, 235), ["Atmosphere.Decay"] = rgb(100, 130, 165) },
		Water = { Color = rgb(20, 70, 110), Transparency = 0.35, Reflectance = 1, WaveSize = 0.35, WaveSpeed = 14 },
		Wind = 14,
		Note = "open horizon, deep blue water, sea breeze",
	},
	Tropical = {
		Add = { ["PostProcessing.ColorCorrection.Saturation"] = 0.1 },
		Set = { ["Atmosphere.Color"] = rgb(185, 225, 245) },
		Water = { Color = rgb(30, 170, 190), Transparency = 0.75, Reflectance = 0.6, WaveSize = 0.1, WaveSpeed = 9 },
		Note = "saturated, turquoise water",
	},
	City = {
		Set = { ["Atmosphere.Color"] = rgb(190, 190, 185), ["Atmosphere.Decay"] = rgb(120, 115, 110) },
		Add = { ["Atmosphere.Haze"] = 1, ["Atmosphere.Density"] = 0.04 },
		Note = "light smog haze",
	},
	Mountains = {
		Set = { ["Atmosphere.Offset"] = 0.35 },
		Add = { ["Atmosphere.Density"] = -0.05 },
		Wind = 12,
		Note = "clear air with distant silhouettes",
	},
	Swamp = {
		Set = { ["Atmosphere.Color"] = rgb(150, 160, 120), ["Atmosphere.Decay"] = rgb(80, 90, 60) },
		Add = { ["Atmosphere.Density"] = 0.12, ["Atmosphere.Haze"] = 1.2 },
		Particles = { Day = { Mist = { Template = "Mist", Rate = 14 } }, Night = { Mist = { Template = "Mist", Rate = 14 }, Fireflies = { Template = "Fireflies", Rate = 10 } } },
		Water = { Color = rgb(60, 70, 40), Transparency = 0.05, Reflectance = 0.3, WaveSize = 0.02, WaveSpeed = 2 },
		Note = "murky water, thick humid haze",
	},
	Plains = {
		Set = { ["Atmosphere.Offset"] = 0.25 },
		Wind = 8,
		Note = "open and airy",
	},
	Volcanic = {
		Set = { ["Atmosphere.Color"] = rgb(200, 120, 90), ["Atmosphere.Decay"] = rgb(90, 40, 30) },
		Add = { ["Atmosphere.Haze"] = 2, ["Atmosphere.Density"] = 0.1 },
		Tint = { ["Lighting.OutdoorAmbient"] = rgb(255, 200, 180) },
		Particles = { Day = { Embers = { Template = "Embers", Attach = "Camera", Area = Vector3.new(100, 30, 100), Offset = Vector3.new(0, 0, 0), Rate = 40 } }, Night = { Embers = { Template = "Embers", Attach = "Camera", Area = Vector3.new(100, 30, 100), Offset = Vector3.new(0, 0, 0), Rate = 40 } } },
		Note = "ash-red haze and drifting embers",
	},
}
VisualDirector.EnvironmentAliases = {
	Jungle = "DenseForest", Woods = "Forest", Woodland = "Forest", Sea = "Ocean", Coast = "Ocean", Beach = "Tropical",
	Island = "Tropical", Tundra = "Arctic", Snow = "Arctic", Urban = "City", Town = "City", Marsh = "Swamp",
	Grassland = "Plains", Meadow = "Plains", Mountain = "Mountains", Volcano = "Volcanic",
}

VisualDirector.FogLevels = { None = 0, Light = 0.2, Medium = 0.45, Heavy = 0.7, Dense = 0.9 }

VisualDirector.LightingStyles = {
	Realistic = {
		Set = { ["Lighting.EnvironmentDiffuseScale"] = 1, ["Lighting.EnvironmentSpecularScale"] = 1, ["Lighting.ShadowSoftness"] = 0.2, ["PostProcessing.Bloom.Intensity"] = 0.4, ["PostProcessing.Bloom.Size"] = 24, ["PostProcessing.Bloom.Threshold"] = 2.2 },
		Add = { ["PostProcessing.ColorCorrection.Contrast"] = 0.05 },
		Note = "sky-driven ambient and reflections",
	},
	Cinematic = {
		Set = {
			["Lighting.EnvironmentSpecularScale"] = 0.7, ["Lighting.ShadowSoftness"] = 0.35,
			["PostProcessing.Bloom.Intensity"] = 0.8, ["PostProcessing.Bloom.Size"] = 28, ["PostProcessing.Bloom.Threshold"] = 1.6,
			["PostProcessing.SunRays.Intensity"] = 0.1, ["PostProcessing.SunRays.Spread"] = 0.8,
			["PostProcessing.DepthOfField.FarIntensity"] = 0.12, ["PostProcessing.DepthOfField.FocusDistance"] = 60,
			["PostProcessing.DepthOfField.InFocusRadius"] = 40, ["PostProcessing.DepthOfField.NearIntensity"] = 0,
		},
		Add = { ["PostProcessing.ColorCorrection.Contrast"] = 0.12, ["PostProcessing.ColorCorrection.Saturation"] = 0.05, ["Lighting.ExposureCompensation"] = 0.05 },
		Note = "bloom, sun rays, shallow depth of field, graded contrast",
	},
	Stylized = {
		Set = { ["Lighting.ShadowSoftness"] = 0.6, ["Lighting.EnvironmentDiffuseScale"] = 0.2, ["PostProcessing.Bloom.Intensity"] = 1.1, ["PostProcessing.Bloom.Size"] = 30, ["PostProcessing.Bloom.Threshold"] = 1.3 },
		Add = { ["PostProcessing.ColorCorrection.Saturation"] = 0.25, ["PostProcessing.ColorCorrection.Contrast"] = 0.08 },
		Note = "soft shadows, saturated colors",
	},
	Dramatic = {
		Set = { ["Lighting.ShadowSoftness"] = 0.05 },
		Add = { ["PostProcessing.ColorCorrection.Contrast"] = 0.25, ["Lighting.ExposureCompensation"] = -0.1 },
		Note = "hard shadows, strong contrast",
	},
	Noir = {
		Set = { ["PostProcessing.ColorCorrection.Saturation"] = -1, ["Lighting.ShadowSoftness"] = 0.05 },
		Add = { ["PostProcessing.ColorCorrection.Contrast"] = 0.3 },
		Note = "black and white, hard contrast",
	},
	Soft = {
		Set = { ["Lighting.ShadowSoftness"] = 0.7, ["PostProcessing.Bloom.Intensity"] = 0.6, ["PostProcessing.Bloom.Size"] = 32, ["PostProcessing.Bloom.Threshold"] = 1.6 },
		Add = { ["PostProcessing.ColorCorrection.Contrast"] = -0.05 },
		Note = "diffuse light and gentle bloom",
	},
	Vibrant = {
		Add = { ["PostProcessing.ColorCorrection.Saturation"] = 0.35, ["PostProcessing.ColorCorrection.Contrast"] = 0.1 },
		Note = "high saturation",
	},
	Flat = {
		Set = { ["Lighting.ShadowSoftness"] = 1, ["Lighting.EnvironmentDiffuseScale"] = 0, ["Lighting.EnvironmentSpecularScale"] = 0 },
		Add = { ["PostProcessing.ColorCorrection.Contrast"] = -0.1 },
		Note = "minimal shading",
	},
	Moody = {
		Add = { ["Lighting.ExposureCompensation"] = -0.2, ["PostProcessing.ColorCorrection.Contrast"] = 0.15, ["PostProcessing.ColorCorrection.Saturation"] = -0.1 },
		Note = "dark and contrasty",
	},
}
VisualDirector.LightingStyleAliases = { Cartoon = "Stylized", Film = "Cinematic", Movie = "Cinematic", Photoreal = "Realistic", Natural = "Realistic" }

VisualDirector.WaterStyles = {
	CalmReflective = { Color = rgb(35, 90, 120), Transparency = 0.35, Reflectance = 1, WaveSize = 0.05, WaveSpeed = 5, Note = "glassy, mirror-like" },
	Stormy = { Color = rgb(40, 60, 70), Transparency = 0.2, Reflectance = 0.6, WaveSize = 0.6, WaveSpeed = 25, Note = "tall fast waves" },
	TropicalClear = { Color = rgb(30, 170, 190), Transparency = 0.8, Reflectance = 0.6, WaveSize = 0.1, WaveSpeed = 9, Note = "clear turquoise" },
	Murky = { Color = rgb(60, 70, 40), Transparency = 0.05, Reflectance = 0.3, WaveSize = 0.02, WaveSpeed = 2, Note = "opaque green-brown" },
	Icy = { Color = rgb(150, 190, 210), Transparency = 0.4, Reflectance = 0.9, WaveSize = 0.01, WaveSpeed = 1, Note = "still and pale" },
	DeepOcean = { Color = rgb(15, 50, 90), Transparency = 0.25, Reflectance = 1, WaveSize = 0.35, WaveSpeed = 14, Note = "deep blue swell" },
}
VisualDirector.WaterStyleAliases = { Calm = "CalmReflective", Reflective = "CalmReflective", Rough = "Stormy", Clear = "TropicalClear", Tropical = "TropicalClear", Swamp = "Murky", Frozen = "Icy", Ocean = "DeepOcean" }

VisualDirector.WeatherAliases = {
	Sunny = "Clear", Fair = "Clear", Rain = "LightRain", Rainy = "LightRain", Drizzle = "LightRain",
	Downpour = "HeavyRain", Storm = "Thunderstorm", Stormy = "Thunderstorm", Foggy = "Fog", Misty = "Fog",
	Snowy = "Snow", Snowing = "Snow", Dust = "DustStorm", Sand = "Sandstorm", Wind = "Windy", Fall = "Autumn",
	Magic = "MagicalStorm", Cloudless = "Clear", Grey = "Overcast", Gray = "Overcast",
}

local CLAMPS = {
	["Atmosphere.Density"] = { 0, 1 }, ["Atmosphere.Offset"] = { 0, 1 }, ["Atmosphere.Haze"] = { 0, 10 }, ["Atmosphere.Glare"] = { 0, 10 },
	["Lighting.ExposureCompensation"] = { -3, 3 }, ["Lighting.Brightness"] = { 0, 10 },
	["PostProcessing.ColorCorrection.Saturation"] = { -1, 1 }, ["PostProcessing.ColorCorrection.Contrast"] = { -1, 1 },
	["PostProcessing.ColorCorrection.Brightness"] = { -1, 1 },
}

-- Neutral starting values for keys that are adjusted additively.
local ADD_BASE = {
	["PostProcessing.ColorCorrection.Saturation"] = 0,
	["PostProcessing.ColorCorrection.Contrast"] = 0,
	["PostProcessing.ColorCorrection.Brightness"] = 0,
	["Lighting.ExposureCompensation"] = 0,
	["Atmosphere.Density"] = 0.35,
	["Atmosphere.Haze"] = 1,
	["Atmosphere.Glare"] = 0,
	["Atmosphere.Offset"] = 0.1,
}

---------------------------------------------------------------------------

function VisualDirector.new(engine)
	local self = setmetatable({}, VisualDirector)
	self.Engine = engine
	return self
end

function VisualDirector:IsDescription(input: { [string]: any }): boolean
	for key in pairs(input) do
		if VisualDirector.DescriptionKeys[key] then
			return true
		end
	end
	if typeof(input.Environment) == "string" or typeof(input.Fog) == "string" or typeof(input.Fog) == "number" then
		return true
	end
	return false
end

-- The vocabulary accepted in descriptions (for schemas and UIs).
function VisualDirector:Vocabulary()
	local function names(map, aliases)
		local list = Util.sortedKeys(map)
		if aliases then
			for _, alias in ipairs(Util.sortedKeys(aliases)) do
				table.insert(list, alias)
			end
		end
		return list
	end
	local times = Util.sortedKeys(Environment.TimesOfDay)
	return {
		Mood = names(VisualDirector.Moods, VisualDirector.MoodAliases),
		Time = times,
		Weather = names(self.Engine.Registry.WeatherTypes, VisualDirector.WeatherAliases),
		Environment = names(VisualDirector.Environments, VisualDirector.EnvironmentAliases),
		Fog = Util.sortedKeys(VisualDirector.FogLevels),
		LightingStyle = names(VisualDirector.LightingStyles, VisualDirector.LightingStyleAliases),
		WaterStyle = names(VisualDirector.WaterStyles, VisualDirector.WaterStyleAliases),
		Notes = {
			"Values are case/format-insensitive: \"light_rain\", \"Light Rain\" and \"LightRain\" are equivalent.",
			"Time also accepts a number (ClockTime 0-24). Fog also accepts a number 0-1.",
			"Intensity (0-1) scales weather; any configuration section (Lighting, Atmosphere, ...) may be included to override the result.",
		},
	}
end

local function lookup(value: any, map: { [string]: any }, aliases: { [string]: string }?): (string?, any)
	if typeof(value) ~= "string" then
		return nil, nil
	end
	local normalized = Util.normalizeName(value)
	for _, name in ipairs(Util.sortedKeys(map)) do
		if Util.normalizeName(name) == normalized then
			return name, map[name]
		end
	end
	if aliases then
		for alias, target in pairs(aliases) do
			if Util.normalizeName(alias) == normalized then
				return target, map[target]
			end
		end
	end
	return nil, nil
end

local function suggestion(value: any, map, aliases): string
	if typeof(value) ~= "string" then
		return ""
	end
	local candidates = Util.sortedKeys(map)
	for _, alias in ipairs(Util.sortedKeys(aliases or {})) do
		table.insert(candidates, alias)
	end
	local best = Util.suggest(value, candidates)
	return if best then string.format(" (did you mean '%s'?)", best) else ""
end

-- Applies Set/Add/Tint operators to a configuration table.
local function applyOperators(config, operators)
	for _, path in ipairs(Util.sortedKeys(operators.Set or {})) do
		Util.setPath(config, path, operators.Set[path])
	end
	for _, path in ipairs(Util.sortedKeys(operators.Add or {})) do
		local current = Util.getPath(config, path)
		if typeof(current) ~= "number" then
			current = ADD_BASE[path] or 0
		end
		local value = current + operators.Add[path]
		local clamp = CLAMPS[path]
		if clamp then
			value = Util.clamp(value, clamp[1], clamp[2])
		end
		Util.setPath(config, path, Util.round(value, 4))
	end
	for _, path in ipairs(Util.sortedKeys(operators.Tint or {})) do
		local current = Util.getPath(config, path)
		local tint = operators.Tint[path]
		if typeof(current) == "Color3" then
			Util.setPath(
				config,
				path,
				Color3.fromRGB(
					math.floor(current.R * tint.R * 255 + 0.5),
					math.floor(current.G * tint.G * 255 + 0.5),
					math.floor(current.B * tint.B * 255 + 0.5)
				)
			)
		end
	end
end

--[[
	Interprets a description into a configuration. Pure and deterministic.
	Returns { Configuration, Interpretation = { lines }, Warnings, Input }.
]]
function VisualDirector:Interpret(description: { [string]: any })
	local engine = self.Engine
	local config = { Version = Config.CURRENT_VERSION }
	local interpretation, warnings = {}, {}

	-- 1. Time of day
	local timeValue = description.Time or description.TimeOfDay or 12
	local clock = Environment.ResolveTime(timeValue)
	if not clock then
		table.insert(warnings, string.format("Unknown Time '%s'%s; using noon", tostring(timeValue), suggestion(timeValue, Environment.TimesOfDay)))
		clock = 12
	end
	local sample = Environment.SampleDayNight(clock)
	config.Lighting = {
		ClockTime = clock,
		Brightness = Util.round(sample.Brightness, 3),
		Ambient = sample.Ambient,
		OutdoorAmbient = sample.OutdoorAmbient,
		ColorShiftTop = sample.ColorShiftTop,
		ExposureCompensation = 0,
		GlobalShadows = true,
	}
	config.Atmosphere = {
		Density = 0.35,
		Offset = 0.1,
		Haze = 1,
		Glare = if clock > 6 and clock < 18.5 then 0.3 else 0,
		Color = sample.AtmosphereColor,
		Decay = sample.AtmosphereDecay,
	}
	table.insert(interpretation, string.format("Time: ClockTime %s (%s)", Util.formatNumber(clock), tostring(timeValue)))
	local isNight = clock >= 19 or clock < 5.5

	-- 2. Environment
	if description.Environment ~= nil then
		local name, environment = lookup(description.Environment, VisualDirector.Environments, VisualDirector.EnvironmentAliases)
		if environment then
			applyOperators(config, environment)
			local particles = environment.Particles and (if isNight then environment.Particles.Night else environment.Particles.Day)
			if particles then
				config.Particles = Config.merge(config.Particles or {}, particles)
			end
			if environment.Water then
				config.Water = Config.merge(config.Water or {}, environment.Water)
			end
			if environment.Wind then
				config.Environment = { Wind = { Direction = Vector3.new(1, 0, 0.35), Speed = environment.Wind } }
			end
			table.insert(interpretation, string.format("Environment: %s — %s", name, environment.Note))
		else
			table.insert(warnings, string.format("Unknown Environment '%s'%s; ignored", tostring(description.Environment), suggestion(description.Environment, VisualDirector.Environments, VisualDirector.EnvironmentAliases)))
		end
	end

	-- 3. Weather
	local weatherValue = description.Weather
	if typeof(weatherValue) == "table" then
		config.Weather = Util.deepCopy(weatherValue)
		table.insert(interpretation, "Weather: explicit configuration")
	elseif weatherValue ~= nil then
		local definition, typeName = engine.Registry:FindWeather(weatherValue)
		if not definition then
			local alias = lookup(weatherValue, engine.Registry.WeatherTypes, VisualDirector.WeatherAliases)
			if alias then
				definition, typeName = engine.Registry:FindWeather(alias)
			end
		end
		if definition then
			config.Weather = { Type = typeName }
			local intensity = description.WeatherIntensity or description.Intensity
			if typeof(intensity) == "number" then
				config.Weather.Intensity = Util.clamp(intensity, 0, 1)
			end
			table.insert(interpretation, string.format("Weather: %s — %s", typeName, definition.Description or ""))
		else
			table.insert(warnings, string.format("Unknown Weather '%s'%s; ignored", tostring(weatherValue), suggestion(weatherValue, engine.Registry.WeatherTypes, VisualDirector.WeatherAliases)))
		end
	end

	-- 4. Fog
	if description.Fog ~= nil then
		local amount = nil
		if typeof(description.Fog) == "number" then
			amount = Util.clamp(description.Fog, 0, 1)
		else
			local _, level = lookup(description.Fog, VisualDirector.FogLevels)
			amount = level
		end
		if amount == nil then
			table.insert(warnings, string.format("Unknown Fog '%s'%s; ignored", tostring(description.Fog), suggestion(description.Fog, VisualDirector.FogLevels)))
		elseif config.Weather then
			config.Weather.Fog = amount
			table.insert(interpretation, string.format("Fog: %s (applied through the weather system)", Util.formatNumber(amount)))
		else
			applyOperators(config, { Add = { ["Atmosphere.Density"] = amount * 0.3, ["Atmosphere.Haze"] = amount * 2.5 } })
			if amount >= 0.45 then
				config.Particles = config.Particles or {}
				config.Particles.Mist = { Template = "Mist", Rate = Util.round(14 * amount, 2) }
			end
			table.insert(interpretation, string.format("Fog: %s (atmosphere density and haze%s)", Util.formatNumber(amount), if amount >= 0.45 then ", ground mist" else ""))
		end
	end

	-- 5. Mood
	if description.Mood ~= nil then
		local name, mood = lookup(description.Mood, VisualDirector.Moods, VisualDirector.MoodAliases)
		if mood then
			applyOperators(config, mood)
			table.insert(interpretation, string.format("Mood: %s — %s", name, mood.Note))
		else
			table.insert(warnings, string.format("Unknown Mood '%s'%s; ignored", tostring(description.Mood), suggestion(description.Mood, VisualDirector.Moods, VisualDirector.MoodAliases)))
		end
	end

	-- 6. Lighting style
	local styleValue = description.LightingStyle or description.Style
	if styleValue ~= nil then
		local name, style = lookup(styleValue, VisualDirector.LightingStyles, VisualDirector.LightingStyleAliases)
		if style then
			applyOperators(config, style)
			table.insert(interpretation, string.format("LightingStyle: %s — %s", name, style.Note))
		else
			table.insert(warnings, string.format("Unknown LightingStyle '%s'%s; ignored", tostring(styleValue), suggestion(styleValue, VisualDirector.LightingStyles, VisualDirector.LightingStyleAliases)))
		end
	end

	-- 7. Water style
	if description.WaterStyle ~= nil then
		local name, water = lookup(description.WaterStyle, VisualDirector.WaterStyles, VisualDirector.WaterStyleAliases)
		if water then
			local copy = Util.shallowCopy(water)
			copy.Note = nil
			config.Water = Config.merge(config.Water or {}, copy)
			table.insert(interpretation, string.format("WaterStyle: %s — %s", name, water.Note))
		else
			table.insert(warnings, string.format("Unknown WaterStyle '%s'%s; ignored", tostring(description.WaterStyle), suggestion(description.WaterStyle, VisualDirector.WaterStyles, VisualDirector.WaterStyleAliases)))
		end
	end

	-- Post-processing entries created by operators need their required pieces.
	if config.PostProcessing then
		for effect, values in pairs(config.PostProcessing) do
			if typeof(values) == "table" and values.Enabled == nil then
				values.Enabled = true
			end
			if effect == "Bloom" then
				values.Size = values.Size or 24
				values.Threshold = values.Threshold or 2
			end
		end
	end

	-- 8. Explicit sections in the description override everything.
	for _, key in ipairs(Util.sortedKeys(description)) do
		if engine.Registry:GetSection(key) and typeof(description[key]) == "table" and key ~= "Weather" then
			config[key] = Config.merge(config[key] or {}, description[key])
			table.insert(interpretation, string.format("%s: explicit overrides applied", key))
		end
	end

	config.Metadata = {
		Name = "Director Scene",
		Description = table.concat(interpretation, "; "),
		Author = "VisualFX Director",
	}

	return {
		Configuration = config,
		Interpretation = interpretation,
		Warnings = warnings,
		Input = Util.deepCopy(description),
	}
end

--[[
	Full director workflow: inspect -> interpret -> plan (reuse/modify/create/
	remove) -> apply -> structured result.
	options: { DryRun, Merge, Transition = { Duration, Easing } }
]]
function VisualDirector:CreateScene(description: { [string]: any }, options: { [string]: any }?)
	local opts = options or {}
	local engine = self.Engine
	local inspection = engine.Inspector:Inspect({ IncludeProperties = false, MaxParticles = 50 })
	local interpreted = self:Interpret(description)
	local applyOptions = { Action = opts.Action or "CreateScene", DryRun = opts.DryRun, Transition = opts.Transition }
	local result
	if opts.Merge then
		result = engine:_MutateOverlay(interpreted.Configuration, applyOptions)
	else
		result = engine:_ReplaceScene(interpreted.Configuration, applyOptions)
	end
	for _, warning in ipairs(interpreted.Warnings) do
		Util.addUnique(result.Warnings, warning)
	end
	result.Interpretation = interpreted.Interpretation
	result.Input = interpreted.Input
	result.Inspection = {
		Summary = inspection.Summary,
		ExistingManagedEffects = #inspection.ManagedEffects,
		Conflicts = #inspection.Conflicts,
	}
	result.Configuration = result.Configuration or interpreted.Configuration
	return result
end

return VisualDirector
