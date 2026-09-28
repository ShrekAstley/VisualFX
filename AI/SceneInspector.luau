--[[
	VisualFX.AI.SceneInspector

	Structured, serializable view of the current visual state for humans and
	AI agents:

	  VisualFX:InspectScene() -> {
	      Lighting, Atmosphere, Sky, Clouds, PostProcessing, Water, Weather,
	      Particles, Environment, ManagedEffects, Conflicts, Quality,
	      Configuration, Unknown, Summary
	  }

	Every visual instance is classified:
	  Managed        created by VisualFX (VisualFX_Managed attribute)
	  Adopted        developer instance VisualFX has taken over (originals recorded)
	  RobloxDefault  unmodified instance whose properties equal a fresh instance's
	  Developer      a visual instance created or edited by the developer
	  Unknown        an unrecognised instance inside a visual container

	The inspector only reads. VisualFX never deletes Developer or Unknown
	instances.
]]

local Root = script.Parent.Parent
local Util = require(Root.Core.Util)
local Values = require(Root.Core.Values)
local PropertyMap = require(Root.Core.PropertyMap)
local Lighting = require(Root.Runtime.Lighting)
local Atmosphere = require(Root.Runtime.Atmosphere)
local Water = require(Root.Runtime.Water)
local Particles = require(Root.Runtime.Particles)

local SceneInspector = {}
SceneInspector.__index = SceneInspector

SceneInspector.VisualClasses = {
	Atmosphere = Atmosphere.Fields,
	Sky = Atmosphere.SkyFields,
	Clouds = Atmosphere.CloudFields,
	ParticleEmitter = Particles.EmitterFields,
}
for _, effect in ipairs(Lighting.PostEffects) do
	SceneInspector.VisualClasses[effect.ClassName] = effect.Fields
end

-- Other visual classes that are recognised but not configured by VisualFX.
SceneInspector.OtherVisualClasses = {
	Beam = true, Trail = true, Fire = true, Smoke = true, Sparkles = true,
	PointLight = true, SpotLight = true, SurfaceLight = true, Highlight = true,
}

-- Instances that are expected in Lighting without being visual effects.
local LIGHTING_BENIGN = { Folder = true, Configuration = true }

function SceneInspector.new(engine)
	local self = setmetatable({}, SceneInspector)
	self.Engine = engine
	return self
end

local function describeValues(values: { [string]: any }?): { [string]: any }
	local result = {}
	for key, value in pairs(values or {}) do
		result[key] = value
	end
	return result
end

-- True when every schema property equals the value on a fresh instance.
function SceneInspector:IsRobloxDefault(instance: Instance): boolean
	local fields = SceneInspector.VisualClasses[instance.ClassName]
	if not fields then
		return false
	end
	local compatibility = self.Engine.Compatibility
	local compared = 0
	for _, field in ipairs(fields) do
		if field.Property then
			local info = compatibility:GetPropertySupport(instance.ClassName, field.Property)
			if info.Supported and info.Default ~= nil then
				local ok, value = compatibility:GetProperty(instance, field.Property)
				if ok then
					compared += 1
					if not Values.equal(value, info.Default) then
						return false
					end
				end
			end
		end
	end
	return compared > 0
end

function SceneInspector:Classify(instance: Instance): string
	local manager = self.Engine.InstanceManager
	if manager:IsManaged(instance) then
		return if manager:IsAdopted(instance) then "Adopted" else "Managed"
	end
	if SceneInspector.VisualClasses[instance.ClassName] then
		return if self:IsRobloxDefault(instance) then "RobloxDefault" else "Developer"
	end
	if SceneInspector.OtherVisualClasses[instance.ClassName] then
		return "Developer"
	end
	return "Unknown"
end

function SceneInspector:_DescribeInstance(instance: Instance, fields)
	local manager = self.Engine.InstanceManager
	local entry = {
		Name = instance.Name,
		ClassName = instance.ClassName,
		Path = instance:GetFullName(),
		Classification = self:Classify(instance),
	}
	local identity = manager:GetIdentity(instance)
	if identity then
		entry.ID = identity.ID
		entry.Type = identity.Type
		entry.Owner = identity.Owner ~= "" and identity.Owner or nil
	end
	if fields then
		entry.Properties = describeValues(PropertyMap.read(instance, fields, self.Engine.Compatibility))
	end
	return entry
end

function SceneInspector:_ChildrenOfClass(parent: Instance?, className: string)
	local list = {}
	if not parent then
		return list
	end
	for _, child in ipairs(parent:GetChildren()) do
		if child.ClassName == className then
			table.insert(list, self:_DescribeInstance(child, SceneInspector.VisualClasses[className]))
		end
	end
	table.sort(list, function(a, b)
		return a.Path < b.Path
	end)
	return list
end

--[[
	options:
	  IncludeProperties  include property tables for particle emitters (default true)
	  MaxParticles       cap on scanned emitters (default 200)
]]
function SceneInspector:Inspect(options: { [string]: any }?)
	local opts = options or {}
	local engine = self.Engine
	local context = engine.Context
	local manager = engine.InstanceManager
	local compatibility = engine.Compatibility

	local lightingService = context.Lighting
	local terrain = context.Terrain

	local lightingManaged = manager:GetManagedProperties(lightingService)
	local waterManaged = manager:GetManagedProperties(terrain)

	local postProcessing = {}
	for _, effect in ipairs(Lighting.PostEffects) do
		Util.append(postProcessing, self:_ChildrenOfClass(lightingService, effect.ClassName))
		Util.append(postProcessing, self:_ChildrenOfClass(context.Workspace.CurrentCamera, effect.ClassName))
	end

	-- Particle emitters anywhere in Workspace (bounded scan).
	local particles = { Managed = {}, Developer = {} }
	local maxParticles = opts.MaxParticles or 200
	local ok, descendants = pcall(context.Workspace.GetDescendants, context.Workspace)
	if ok then
		local count = 0
		for _, instance in ipairs(descendants) do
			if instance.ClassName == "ParticleEmitter" then
				count += 1
				if count > maxParticles then
					particles.Truncated = true
					break
				end
				local entry = self:_DescribeInstance(instance, if opts.IncludeProperties == false then nil else Particles.EmitterFields)
				entry.Enabled = instance.Enabled
				entry.Rate = instance.Rate
				if entry.Classification == "Managed" or entry.Classification == "Adopted" then
					table.insert(particles.Managed, entry)
				else
					table.insert(particles.Developer, entry)
				end
			end
		end
	end
	table.sort(particles.Managed, function(a, b)
		return a.Path < b.Path
	end)
	table.sort(particles.Developer, function(a, b)
		return a.Path < b.Path
	end)

	-- Managed effects.
	local managedEffects = {}
	for _, instance in ipairs(manager:GetManaged(true)) do
		local identity = manager:GetIdentity(instance)
		table.insert(managedEffects, {
			ID = identity.ID,
			Type = identity.Type,
			Section = identity.Section,
			Owner = identity.Owner ~= "" and identity.Owner or nil,
			ClassName = instance.ClassName,
			Path = instance:GetFullName(),
			Adopted = identity.Adopted,
		})
	end

	-- Unknown instances inside visual containers.
	local unknown = {}
	for _, child in ipairs(lightingService:GetChildren()) do
		local classification = self:Classify(child)
		if classification == "Unknown" and not LIGHTING_BENIGN[child.ClassName] then
			table.insert(unknown, { Path = child:GetFullName(), ClassName = child.ClassName })
		end
	end
	table.sort(unknown, function(a, b)
		return a.Path < b.Path
	end)

	local weatherSection = engine.Registry:GetSection("Weather")
	local environmentSection = engine.Registry:GetSection("Environment")
	local inspectContext = setmetatable({ Engine = engine }, { __index = context })

	local conflicts = self:DetectConflicts()
	local stats = engine:GetPerformanceStats()

	local scene = {
		Lighting = {
			Properties = describeValues(PropertyMap.read(lightingService, Lighting.Fields, compatibility)),
			ManagedProperties = lightingManaged,
			Classification = if #lightingManaged > 0 then "Managed" else "Service",
		},
		Atmosphere = self:_ChildrenOfClass(lightingService, "Atmosphere"),
		Sky = self:_ChildrenOfClass(lightingService, "Sky"),
		Clouds = self:_ChildrenOfClass(terrain, "Clouds"),
		PostProcessing = postProcessing,
		Water = {
			Properties = describeValues(PropertyMap.read(terrain, Water.Fields, compatibility)),
			ManagedProperties = waterManaged,
		},
		Weather = weatherSection.Inspect(inspectContext),
		Particles = particles,
		Environment = environmentSection.Inspect(inspectContext),
		ManagedEffects = managedEffects,
		Conflicts = conflicts,
		Quality = {
			Level = engine.Quality.Level,
			Profile = Util.deepCopy(engine.Quality:GetProfile()),
			Stats = stats,
		},
		Configuration = engine:GetConfiguration(),
		Unknown = unknown,
		Transition = engine.Transitions:GetActive(),
		Previewing = engine:IsPreviewing(),
	}
	scene.Summary = self:Summarize(scene)
	return scene
end

-- Short human-readable lines describing a scene inspection.
function SceneInspector:Summarize(scene): { string }
	local lines = {}
	local lighting = scene.Lighting.Properties
	table.insert(
		lines,
		string.format(
			"Lighting: ClockTime %s, Brightness %s, Exposure %s (%d managed properties)",
			Values.describe(lighting.ClockTime),
			Values.describe(lighting.Brightness),
			Values.describe(lighting.ExposureCompensation),
			#scene.Lighting.ManagedProperties
		)
	)
	local function listLine(label, list)
		if #list == 0 then
			table.insert(lines, label .. ": none")
			return
		end
		local parts = {}
		for _, entry in ipairs(list) do
			table.insert(parts, string.format("%s [%s]", entry.Name, entry.Classification))
		end
		table.insert(lines, label .. ": " .. table.concat(parts, ", "))
	end
	listLine("Atmosphere", scene.Atmosphere)
	listLine("Sky", scene.Sky)
	listLine("Clouds", scene.Clouds)
	listLine("Post-processing", scene.PostProcessing)
	if scene.Weather.Active then
		table.insert(lines, string.format("Weather: %s at intensity %s", scene.Weather.Type, Values.describe(scene.Weather.Intensity)))
	else
		table.insert(lines, "Weather: none")
	end
	table.insert(
		lines,
		string.format(
			"Particles: %d managed, %d developer emitters",
			#scene.Particles.Managed,
			#scene.Particles.Developer
		)
	)
	table.insert(lines, string.format("Managed effects: %d", #scene.ManagedEffects))
	table.insert(lines, string.format("Conflicts: %d", #scene.Conflicts))
	table.insert(lines, string.format("Quality: %s", scene.Quality.Level))
	return lines
end

--[[
	Detects conflicts in the live scene. Each conflict:
	{ Code, Severity = "Error" | "Warning" | "Info", Message, Paths, Suggestion }
]]
function SceneInspector:DetectConflicts()
	local engine = self.Engine
	local context = engine.Context
	local manager = engine.InstanceManager
	local conflicts = {}

	local function add(code, severity, message, paths, suggestion)
		table.insert(conflicts, { Code = code, Severity = severity, Message = message, Paths = paths or {}, Suggestion = suggestion })
	end

	local function singleton(parent: Instance, className: string, label: string)
		local list = {}
		for _, child in ipairs(parent:GetChildren()) do
			if child.ClassName == className then
				table.insert(list, child:GetFullName())
			end
		end
		table.sort(list)
		if #list > 1 then
			add(
				"Multiple" .. className,
				"Warning",
				string.format("%d %s instances exist in %s; Roblox only renders one %s", #list, className, parent:GetFullName(), label),
				list,
				"Keep one. VisualFX adopts the first unmanaged instance; remove the others manually if they are unused."
			)
		end
	end
	singleton(context.Lighting, "Atmosphere", "atmosphere")
	singleton(context.Lighting, "Sky", "sky")
	singleton(context.Terrain, "Clouds", "cloud layer")

	for _, className in ipairs({ "BloomEffect", "SunRaysEffect", "DepthOfFieldEffect" }) do
		local list = {}
		for _, parent in ipairs({ context.Lighting, context.Workspace.CurrentCamera }) do
			if parent then
				for _, child in ipairs(parent:GetChildren()) do
					if child.ClassName == className and (child :: any).Enabled then
						table.insert(list, child:GetFullName())
					end
				end
			end
		end
		table.sort(list)
		if #list > 1 then
			add(
				"Stacked" .. className,
				"Warning",
				string.format("%d enabled %s effects stack; the combined result is usually stronger than intended", #list, className),
				list,
				"Disable or remove the extra effects, or let VisualFX adopt a single one."
			)
		end
	end

	for id, instances in pairs(manager:FindDuplicates()) do
		local paths = {}
		for _, instance in ipairs(instances) do
			table.insert(paths, instance:GetFullName())
		end
		table.sort(paths)
		add(
			"DuplicateManagedID",
			"Error",
			string.format("%d instances share the managed identity %s", #instances, id),
			paths,
			"Re-apply the configuration (VisualFX collapses duplicates automatically) or run ResetManagedEffects."
		)
	end

	local atmosphere = context.Lighting:FindFirstChildOfClass("Atmosphere")
	local okFog, fogEnd = pcall(function()
		return context.Lighting.FogEnd
	end)
	if atmosphere and okFog and fogEnd < 10000 then
		add(
			"FogIgnored",
			"Info",
			"Lighting.FogEnd is set, but an Atmosphere exists; Roblox ignores Lighting fog while an Atmosphere is present",
			{ context.Lighting:GetFullName() },
			"Use Atmosphere.Density/Haze for fog, or remove the Atmosphere to use legacy fog."
		)
	end

	-- Managed effects that the current configuration does not declare.
	local desired = {}
	for _, spec in ipairs(engine:GetActiveSpecs()) do
		desired[spec.ID] = true
	end
	local configured = next(engine:GetConfiguration(), nil) ~= nil and #engine:GetActiveSpecs() > 0
	if configured then
		local stale = {}
		for _, instance in ipairs(manager:GetManaged(true)) do
			local identity = manager:GetIdentity(instance)
			if identity and identity.ID and not desired[identity.ID] then
				table.insert(stale, instance:GetFullName())
			end
		end
		table.sort(stale)
		if #stale > 0 then
			add(
				"StaleManagedEffects",
				"Info",
				string.format("%d managed instances are not part of the current configuration (e.g. saved from an earlier session)", #stale),
				stale,
				"Apply a full scene (CreateScene/ApplyPreset) or ResetManagedEffects to clean them up."
			)
		end
	end

	-- Developer particle load versus the quality budget.
	local profile = engine.Quality:GetProfile()
	local ok, descendants = pcall(context.Workspace.GetDescendants, context.Workspace)
	if ok then
		local developerRate = 0
		for _, instance in ipairs(descendants) do
			if instance.ClassName == "ParticleEmitter" and not manager:IsManaged(instance) and (instance :: any).Enabled then
				developerRate += (instance :: any).Rate
			end
		end
		if developerRate > profile.MaxParticleRate then
			add(
				"DeveloperParticleLoad",
				"Warning",
				string.format(
					"Developer particle emitters emit %d particles/s, above the %s budget of %d/s; VisualFX cannot throttle unmanaged emitters",
					math.floor(developerRate),
					profile.Level,
					profile.MaxParticleRate
				),
				{},
				"Lower emitter rates or use a lower quality level."
			)
		end
	end

	table.sort(conflicts, function(a, b)
		local order = { Error = 1, Warning = 2, Info = 3 }
		if order[a.Severity] ~= order[b.Severity] then
			return order[a.Severity] < order[b.Severity]
		end
		return a.Code < b.Code
	end)
	return conflicts
end

--[[
	Conflict detection step of the validation pipeline: checks a candidate
	configuration against itself and against the live scene.
]]
function SceneInspector:CheckConfiguration(config: { [string]: any }, report)
	local engine = self.Engine
	local context = engine.Context

	local weather = config.Weather
	if weather and (weather.Type == "Clear" or weather.Type == "Cloudy") then
		for name, system in pairs(config.Particles or {}) do
			local template = system.Template or name
			if template == "Rain" or template == "Snow" then
				report:Warn(
					"Particles." .. name,
					"WeatherConflict",
					string.format("Particles.%s emits %s while Weather.Type is %s", name, template, weather.Type)
				)
			end
		end
	end

	local lighting = config.Lighting
	if lighting and (lighting.FogEnd or lighting.FogStart or lighting.FogColor) then
		local hasAtmosphere = config.Atmosphere ~= nil or config.Weather ~= nil or context.Lighting:FindFirstChildOfClass("Atmosphere") ~= nil
		if hasAtmosphere then
			report:Warn(
				"Lighting.FogEnd",
				"FogIgnored",
				"Lighting fog properties have no visible effect while an Atmosphere exists; use Atmosphere.Density/Haze"
			)
		end
	end

	local environment = config.Environment
	local dayNight = environment and environment.DayNight
	if dayNight and dayNight.Enabled and lighting and lighting.ClockTime and dayNight.StartTime then
		report:Warn(
			"Environment.DayNight.StartTime",
			"ClockTimeConflict",
			"Both Lighting.ClockTime and DayNight.StartTime are set; Lighting.ClockTime is used as the starting time"
		)
	end

	if config.Atmosphere then
		local count = 0
		for _, child in ipairs(context.Lighting:GetChildren()) do
			if child.ClassName == "Atmosphere" and not engine.InstanceManager:IsManaged(child) then
				count += 1
			end
		end
		if count > 1 then
			report:Warn(
				"Atmosphere",
				"MultipleAtmospheres",
				string.format("%d unmanaged Atmosphere instances exist in Lighting; VisualFX will adopt one and leave the others (Roblox renders only one)", count)
			)
		end
	end
end

return SceneInspector
