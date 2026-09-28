--[[
	VisualFX.Runtime.Environment

	Environment-wide and spatial effects:

	  Wind      Workspace.GlobalWind (affects terrain grass, clouds and
	            particles with WindAffectsDrag) from Direction + Speed.
	  DayNight  day/night cycle advancing Lighting.ClockTime at runtime,
	            optionally driving ambient colors through sunrise/sunset keyframes.
	  Zones     spatial effects: a box volume emitting fog/mist/dust/leaves/...
	            particles, optionally blending the Atmosphere while the camera is
	            inside (fog banks). Zones are culled by distance on clients.

	Volumetric fog is approximated with large, soft, slow particles
	(Roblox has no volumetric fog primitive) combined with Atmosphere blending.
]]

local Core = script.Parent.Parent.Core
local Util = require(Core.Util)
local Values = require(Core.Values)
local Particles = require(script.Parent.Particles)
local Atmosphere = require(script.Parent.Atmosphere)

local Environment = {}

Environment.TimesOfDay = {
	Midnight = 0,
	Night = 22,
	Dawn = 5.6,
	Sunrise = 6.3,
	Morning = 8.5,
	Noon = 12,
	Afternoon = 15,
	GoldenHour = 17.2,
	Sunset = 17.9,
	Dusk = 18.6,
	Evening = 19.6,
}

local rgb = Color3.fromRGB

--[[
	Keyframes used when DayNight.DriveLighting is enabled. Values are
	interpolated by ClockTime (wrapping at 24).
]]
Environment.DayNightKeyframes = {
	{ Time = 0, Brightness = 0.4, OutdoorAmbient = rgb(45, 50, 75), Ambient = rgb(20, 22, 35), ColorShiftTop = rgb(0, 0, 0), AtmosphereColor = rgb(70, 80, 110), AtmosphereDecay = rgb(20, 25, 45) },
	{ Time = 5.2, Brightness = 0.5, OutdoorAmbient = rgb(60, 60, 90), Ambient = rgb(25, 25, 40), ColorShiftTop = rgb(0, 0, 0), AtmosphereColor = rgb(100, 100, 140), AtmosphereDecay = rgb(40, 40, 70) },
	{ Time = 6.3, Brightness = 1.4, OutdoorAmbient = rgb(150, 120, 110), Ambient = rgb(60, 45, 45), ColorShiftTop = rgb(255, 170, 110), AtmosphereColor = rgb(230, 170, 140), AtmosphereDecay = rgb(120, 90, 110) },
	{ Time = 8, Brightness = 2, OutdoorAmbient = rgb(140, 140, 145), Ambient = rgb(70, 70, 75), ColorShiftTop = rgb(255, 225, 190), AtmosphereColor = rgb(200, 205, 215), AtmosphereDecay = rgb(110, 120, 135) },
	{ Time = 12, Brightness = 2.4, OutdoorAmbient = rgb(150, 150, 150), Ambient = rgb(80, 80, 80), ColorShiftTop = rgb(255, 245, 230), AtmosphereColor = rgb(199, 205, 215), AtmosphereDecay = rgb(106, 112, 125) },
	{ Time = 16.5, Brightness = 2.1, OutdoorAmbient = rgb(145, 140, 135), Ambient = rgb(75, 70, 65), ColorShiftTop = rgb(255, 225, 185), AtmosphereColor = rgb(210, 200, 190), AtmosphereDecay = rgb(120, 110, 110) },
	{ Time = 17.9, Brightness = 1.3, OutdoorAmbient = rgb(160, 110, 95), Ambient = rgb(70, 45, 45), ColorShiftTop = rgb(255, 140, 80), AtmosphereColor = rgb(245, 160, 120), AtmosphereDecay = rgb(130, 70, 90) },
	{ Time = 19, Brightness = 0.6, OutdoorAmbient = rgb(80, 70, 100), Ambient = rgb(35, 30, 50), ColorShiftTop = rgb(120, 70, 90), AtmosphereColor = rgb(120, 100, 140), AtmosphereDecay = rgb(50, 40, 70) },
	{ Time = 24, Brightness = 0.4, OutdoorAmbient = rgb(45, 50, 75), Ambient = rgb(20, 22, 35), ColorShiftTop = rgb(0, 0, 0), AtmosphereColor = rgb(70, 80, 110), AtmosphereDecay = rgb(20, 25, 45) },
}

Environment.ZoneFields = {
	{ Key = "Effect", Kind = "string", Required = true, Description = "Particle template for the zone (Fog, Mist, Dust, Leaves, Fireflies, Rain, Snow, ...)." },
	{ Key = "Enabled", Kind = "boolean", Default = true },
	{ Key = "Position", Kind = "Vector3", Required = true, Description = "Zone center." },
	{ Key = "Size", Kind = "Vector3", Required = true, Min = 0, Description = "Zone box size in studs." },
	{ Key = "Intensity", Kind = "number", Min = 0, Max = 1, Default = 0.5 },
	{ Key = "CullDistance", Kind = "number", Min = 0, Description = "Disable the zone beyond this camera distance (defaults to the quality profile)." },
	{ Key = "BlendDistance", Kind = "number", Min = 0, Default = 40, Description = "Distance over which Atmosphere overrides fade in around the zone." },
	{ Key = "Atmosphere", Kind = "object", Fields = Atmosphere.Fields, Description = "Atmosphere values blended in while the camera is inside." },
	{ Key = "Overrides", Kind = "object", Fields = Particles.EmitterFields, Description = "ParticleEmitter overrides for the zone's emitter." },
}

Environment.Fields = {
	{
		Key = "Wind",
		Kind = "object",
		Description = "Global wind (Workspace.GlobalWind).",
		Fields = {
			{ Key = "Direction", Kind = "Vector3", Default = Vector3.new(1, 0, 0) },
			{ Key = "Speed", Kind = "number", Min = 0, SoftMax = 150, Default = 0, Neutral = 0 },
		},
	},
	{
		Key = "DayNight",
		Kind = "object",
		Description = "Day/night cycle (runtime).",
		Fields = {
			{ Key = "Enabled", Kind = "boolean", Default = false },
			{ Key = "DayLength", Kind = "number", Min = 0.1, SoftMax = 240, Default = 12, Description = "Real-time minutes per 24 in-game hours." },
			{ Key = "StartTime", Kind = "number", Min = 0, Max = 24, Description = "ClockTime when the cycle starts." },
			{ Key = "Paused", Kind = "boolean", Default = false },
			{ Key = "DriveLighting", Kind = "boolean", Default = false, Description = "Interpolate brightness/ambient/atmosphere colors through built-in sunrise/sunset keyframes." },
		},
	},
	{ Key = "Zones", Kind = "map", ItemFields = Environment.ZoneFields, Description = "Spatial effect zones keyed by name." },
}

local REFERENCE_VOLUME = 200 * 12 * 200

-- Linear interpolation through the day/night keyframes.
function Environment.SampleDayNight(clockTime: number)
	local keyframes = Environment.DayNightKeyframes
	local time = clockTime % 24
	for index = 1, #keyframes - 1 do
		local a, b = keyframes[index], keyframes[index + 1]
		if time >= a.Time and time <= b.Time then
			local t = if b.Time > a.Time then (time - a.Time) / (b.Time - a.Time) else 0
			local sample = {}
			for key, value in pairs(a) do
				if key ~= "Time" then
					sample[key] = Values.lerp(value, b[key], t)
				end
			end
			return sample
		end
	end
	return keyframes[1]
end

-- Resolves a time-of-day name ("sunset", "golden_hour") or number to ClockTime.
function Environment.ResolveTime(value: any): number?
	if typeof(value) == "number" then
		return value % 24
	elseif typeof(value) == "string" then
		local normalized = Util.normalizeName(value)
		for name, time in pairs(Environment.TimesOfDay) do
			if Util.normalizeName(name) == normalized then
				return time
			end
		end
	end
	return nil
end

--[[
	Resolve step: StartTime seeds Lighting.ClockTime when the scene does not
	set it; DriveLighting samples the keyframes for the initial state.
]]
function Environment.Resolve(resolved: { [string]: any })
	local environment = resolved.Environment
	if not environment then
		return
	end
	local dayNight = environment.DayNight
	if dayNight and dayNight.Enabled then
		resolved.Lighting = resolved.Lighting or {}
		if dayNight.StartTime and resolved.Lighting.ClockTime == nil then
			resolved.Lighting.ClockTime = dayNight.StartTime
		end
		if dayNight.DriveLighting then
			local sample = Environment.SampleDayNight(resolved.Lighting.ClockTime or 14)
			resolved.Lighting.Brightness = sample.Brightness
			resolved.Lighting.OutdoorAmbient = sample.OutdoorAmbient
			resolved.Lighting.Ambient = sample.Ambient
			resolved.Lighting.ColorShiftTop = sample.ColorShiftTop
			resolved.Atmosphere = resolved.Atmosphere or {}
			resolved.Atmosphere.Color = sample.AtmosphereColor
			resolved.Atmosphere.Decay = sample.AtmosphereDecay
		end
	end
end

function Environment.Register(registry)
	registry:RegisterSection({
		Name = "Environment",
		Order = 80,
		Description = "Wind, day/night cycle and spatial effect zones.",
		Fields = Environment.Fields,
		Targets = function(context)
			return { { ID = "environment.wind", Instance = context.Workspace } }
		end,
		Validate = function(section, report)
			for name, zone in pairs(section.Zones or {}) do
				if typeof(zone) == "table" and zone.Effect and not registry:FindParticleTemplate(zone.Effect) then
					local suggestion = Util.suggest(zone.Effect, registry:ListParticleTemplates())
					report:Error(
						"Environment.Zones." .. name .. ".Effect",
						"UnknownEffect",
						string.format(
							"unknown zone effect '%s'%s",
							zone.Effect,
							if suggestion then " (did you mean '" .. suggestion .. "'?)" else ""
						)
					)
				end
			end
		end,
		Desired = function(section, context)
			local specs = {}
			if section.Wind then
				local direction = section.Wind.Direction or Vector3.new(1, 0, 0)
				if direction.Magnitude > 1e-3 then
					direction = direction.Unit
				end
				table.insert(specs, {
					ID = "environment.wind",
					Type = "Wind",
					Target = context.Workspace,
					Properties = { GlobalWind = direction * (section.Wind.Speed or 0) },
				})
			end
			for _, name in ipairs(Util.sortedKeys(section.Zones or {})) do
				local zone = section.Zones[name]
				local merged = Particles.Merge(registry, name, { Template = zone.Effect })
				for key, value in pairs(zone.Overrides or {}) do
					merged[key] = value
				end
				local size = zone.Size or Vector3.new(50, 20, 50)
				local volumeFactor = Util.clamp((size.X * size.Y * size.Z) / REFERENCE_VOLUME, 0.25, 4)
				local intensity = zone.Intensity or 0.5
				if not (zone.Overrides and zone.Overrides.Rate) then
					merged.Rate = (merged.Rate or 0) * intensity * 2 * volumeFactor
				end
				merged.Attach = "World"
				merged.Area = size
				merged.Position = zone.Position
				merged.CullDistance = zone.CullDistance
				merged.Enabled = zone.Enabled ~= false
				local host, emitter = Particles.BuildSpecs(merged, context, {
					ID = "zone." .. name,
					Type = name,
					Owner = "Zone",
					Priority = 4,
				})
				table.insert(specs, host)
				table.insert(specs, emitter)
			end
			return specs
		end,
		Inspect = function(context)
			local environment = context.Engine:GetResolvedConfiguration().Environment or {}
			local zones = {}
			for name, zone in pairs(environment.Zones or {}) do
				zones[name] = { Effect = zone.Effect, Position = zone.Position, Size = zone.Size, Intensity = zone.Intensity }
			end
			local okWind, wind = pcall(function()
				return context.Workspace.GlobalWind
			end)
			return {
				GlobalWind = if okWind then wind else nil,
				DayNight = environment.DayNight,
				Zones = zones,
			}
		end,
	})
end

--[[
	Runtime controller:
	  * advances ClockTime for the day/night cycle (DriveLighting samples keyframes)
	  * blends zone Atmosphere overrides while the camera is inside a zone
	Writes only when a value actually changes.
]]
function Environment.CreateController(engine)
	local controller = { Name = "Environment", _accumulated = 0, _zoneWeight = {}, ActiveZones = {} }

	local function setIfChanged(instance: Instance, property: string, value: any, epsilon: number?)
		local ok, current = engine.Compatibility:GetProperty(instance, property)
		if ok and not Values.equal(current, value, epsilon) then
			engine.Compatibility:SetProperty(instance, property, value)
		end
	end

	function controller:Step(dt: number)
		local resolved = engine:GetResolvedConfiguration()
		local environment = resolved.Environment
		if not environment then
			return
		end
		local profile = engine.Quality:GetProfile()
		self._accumulated += dt
		local interval = 1 / math.max(1, profile.UpdateFrequency)
		if self._accumulated < interval then
			return
		end
		local elapsed = self._accumulated
		self._accumulated = 0
		local lighting = engine.Context.Lighting

		local dayNight = environment.DayNight
		if dayNight and dayNight.Enabled and not dayNight.Paused and not engine.Transitions:IsActive() then
			local hoursPerSecond = 24 / ((dayNight.DayLength or 12) * 60)
			local clock = (lighting.ClockTime + elapsed * hoursPerSecond) % 24
			engine.Compatibility:SetProperty(lighting, "ClockTime", clock)
			if dayNight.DriveLighting then
				local sample = Environment.SampleDayNight(clock)
				setIfChanged(lighting, "Brightness", sample.Brightness, 1e-3)
				setIfChanged(lighting, "OutdoorAmbient", sample.OutdoorAmbient, 2e-3)
				setIfChanged(lighting, "Ambient", sample.Ambient, 2e-3)
				setIfChanged(lighting, "ColorShift_Top", sample.ColorShiftTop, 2e-3)
				local atmosphere = engine.InstanceManager:Find("atmosphere.primary")
				if atmosphere then
					setIfChanged(atmosphere, "Color", sample.AtmosphereColor, 2e-3)
					setIfChanged(atmosphere, "Decay", sample.AtmosphereDecay, 2e-3)
				end
			end
		end

		-- Zone atmosphere blending follows the local camera (clients only).
		local zones = environment.Zones
		local camera = workspace.CurrentCamera
		if not zones or not camera or not engine.Settings.CameraEffects then
			return
		end
		local cameraPosition = camera.CFrame.Position
		local blendTarget, blendWeight = nil, 0
		table.clear(self.ActiveZones)
		for _, name in ipairs(Util.sortedKeys(zones)) do
			local zone = zones[name]
			if zone.Atmosphere and zone.Enabled ~= false then
				local half = zone.Size / 2
				local offset = cameraPosition - zone.Position
				local outside = Vector3.new(
					math.max(0, math.abs(offset.X) - half.X),
					math.max(0, math.abs(offset.Y) - half.Y),
					math.max(0, math.abs(offset.Z) - half.Z)
				).Magnitude
				local blend = zone.BlendDistance or 40
				local weight = if outside <= 0 then 1 elseif blend > 0 then math.max(0, 1 - outside / blend) else 0
				weight *= zone.Intensity or 0.5
				if weight > 0 then
					table.insert(self.ActiveZones, name)
				end
				if weight > blendWeight then
					blendTarget, blendWeight = zone.Atmosphere, weight
				end
			end
		end
		local atmosphere = engine.InstanceManager:Find("atmosphere.primary")
		if not atmosphere then
			return
		end
		local base = resolved.Atmosphere or {}
		local keys = { "Density", "Haze", "Glare", "Offset", "Color", "Decay" }
		local properties = {}
		for _, key in ipairs(keys) do
			if (blendTarget and blendTarget[key] ~= nil) or self._zoneWeight[key] then
				properties[key] = true
			end
		end
		for key in pairs(properties) do
			local baseValue = base[key]
			if baseValue == nil then
				local ok, live = engine.Compatibility:GetProperty(atmosphere, key)
				baseValue = if ok then live else nil
			end
			if baseValue ~= nil then
				local target = if blendTarget and blendTarget[key] ~= nil then blendTarget[key] else baseValue
				setIfChanged(atmosphere, key, Values.lerp(baseValue, target, blendWeight), 1e-3)
			end
			self._zoneWeight[key] = if blendWeight > 0 then true else nil
		end
	end

	return controller
end

return Environment
