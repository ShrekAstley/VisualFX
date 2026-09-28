--[[
	VisualFX — AI-native visual effects framework for Roblox.

	  local VisualFX = require(game.ReplicatedStorage.VisualFX)
	  VisualFX:ApplyPreset("CinematicSunset")

	The module returns a default engine instance (created lazily on first
	use). Isolated engines can be created with VisualFX.new(options).

	Every mutation follows the same safe pipeline:

	  Input
	   -> schema validation (types, ranges, aliases, migration)
	   -> compatibility validation (engine property support)
	   -> conflict detection (configuration and live scene)
	   -> performance validation (quality budgets)
	   -> planning (identity lookup, adoption, property diff)
	   -> execution (only differences are written)
	   -> structured result

	Configuration is data only. VisualFX never executes code contained in a
	configuration.
]]

local Root = script.Parent.Parent
local Core = Root.Core
local Runtime = script.Parent

local Util = require(Core.Util)
local Config = require(Core.Config)
local Registry = require(Core.Registry)
local Validation = require(Core.Validation)
local Serialization = require(Core.Serialization)
local Compatibility = require(Core.Compatibility)
local InstanceManager = require(Core.InstanceManager)
local Events = require(Core.Events)

local Lighting = require(Runtime.Lighting)
local Atmosphere = require(Runtime.Atmosphere)
local Water = require(Runtime.Water)
local Particles = require(Runtime.Particles)
local Weather = require(Runtime.Weather)
local Environment = require(Runtime.Environment)
local CustomEffects = require(Runtime.CustomEffects)
local Quality = require(Runtime.Quality)
local Scene = require(Runtime.Scene)
local Transitions = require(Runtime.Transitions)
local Cleanup = require(Runtime.Cleanup)
local EffectAPI = require(Runtime.EffectAPI)

local PresetRegistry = require(Root.Presets.Registry)
local SceneInspector = require(Root.AI.SceneInspector)
local VisualDirector = require(Root.AI.VisualDirector)
local CommandAPI = require(Root.AI.CommandAPI)
local Schema = require(Root.AI.Schema)
local AgentDocumentation = require(Root.AI.AgentDocumentation)
local LuauGenerator = require(Root.Codegen.LuauGenerator)

local VisualFX = {}
VisualFX.__index = VisualFX

VisualFX.Version = "1.0.0"
VisualFX.ConfigVersion = Config.CURRENT_VERSION
VisualFX.REMOVE = Config.REMOVE

local function isRunning(): boolean
	local ok, running = pcall(function()
		return game:GetService("RunService"):IsRunning()
	end)
	return ok and running
end

local function isClient(): boolean
	local ok, client = pcall(function()
		return game:GetService("RunService"):IsClient()
	end)
	return ok and client
end

--[[
	options:
	  AutoStart          connect the scheduler to RunService.Heartbeat (default true)
	  RuntimeControllers run camera-follow, lightning, day/night, zones, underwater
	                     (default: true while the game is running)
	  CameraEffects      camera-dependent controllers (default: running on a client)
	  AdoptExisting      adopt developer-created Atmosphere/Sky/Clouds/Bloom/... (default true)
	  Quality            initial quality level (default "High")
]]
function VisualFX.new(options: { [string]: any }?)
	local opts = options or {}
	local self = setmetatable({}, VisualFX)

	self.Settings = {
		AdoptExisting = if opts.AdoptExisting == nil then true else opts.AdoptExisting,
		RuntimeControllers = if opts.RuntimeControllers == nil then isRunning() else opts.RuntimeControllers,
		CameraEffects = if opts.CameraEffects == nil then (isRunning() and isClient()) else opts.CameraEffects,
	}

	self.Compatibility = Compatibility.new()
	self.Registry = Registry.new()
	self.Registry:RegisterSection({
		Name = "Quality",
		Order = 0,
		Description = "Quality level and performance budget overrides.",
		Fields = Quality.Fields,
	})
	Lighting.Register(self.Registry)
	Atmosphere.Register(self.Registry)
	Water.Register(self.Registry)
	Particles.Register(self.Registry)
	Weather.Register(self.Registry)
	Environment.Register(self.Registry)
	CustomEffects.Register(self.Registry)

	self.Validator = Validation.new(self.Registry, self.Compatibility)
	self.InstanceManager = InstanceManager.new(self.Compatibility)
	self.Events = Events.newBus()
	self.Quality = Quality.new()
	if opts.Quality then
		self.Quality:Set(opts.Quality)
	end
	self.Presets = PresetRegistry.new()

	self.Context = {
		Engine = self,
		Lighting = game:GetService("Lighting"),
		Workspace = workspace,
		Terrain = workspace.Terrain,
		Registry = self.Registry,
		Compatibility = self.Compatibility,
		InstanceManager = self.InstanceManager,
		Settings = self.Settings,
	}

	self.Scene = Scene.new(self)
	self.Transitions = Transitions.new(self)
	self.Inspector = SceneInspector.new(self)
	self.Director = VisualDirector.new(self)
	self.Commands = CommandAPI.new(self)
	self.Codegen = LuauGenerator

	self.Controllers = {
		Particles.CreateController(self),
		Weather.CreateController(self),
		Environment.CreateController(self),
		Water.CreateController(self),
	}

	self._authored = { Version = Config.CURRENT_VERSION }
	self._resolved = { Version = Config.CURRENT_VERSION }
	self._activeSpecs = {}
	self._preview = nil
	self._maid = Cleanup.Maid.new()
	self._stats = { LastStepCost = 0, Steps = 0 }
	self._audioHandler = nil

	EffectAPI.Install(self)

	if opts.AutoStart ~= false then
		self:Start()
	end
	return self
end

---------------------------------------------------------------------------
-- Scheduler
---------------------------------------------------------------------------

function VisualFX:Start()
	if self._heartbeat then
		return
	end
	local ok, runService = pcall(function()
		return game:GetService("RunService")
	end)
	if ok and runService then
		self._heartbeat = runService.Heartbeat:Connect(function(dt)
			self:Step(dt)
		end)
		self._maid:Give(self._heartbeat)
	end
end

function VisualFX:Stop()
	if self._heartbeat then
		self._heartbeat:Disconnect()
		self._heartbeat = nil
	end
end

--[[
	Advances transitions and runtime controllers by dt seconds. Called by the
	Heartbeat scheduler; call it manually when AutoStart is false.
]]
function VisualFX:Step(dt: number)
	local started = os.clock()
	self.Transitions:Step(dt)
	if self.Settings.RuntimeControllers then
		for _, controller in ipairs(self.Controllers) do
			local cameraDependent = controller.Name == "Particles" or controller.Name == "Underwater"
			if not cameraDependent or self.Settings.CameraEffects then
				local ok, problem = pcall(controller.Step, controller, dt)
				if not ok then
					self.Events.Warning:Fire(string.format("%s controller error: %s", controller.Name, tostring(problem)))
				end
			end
		end
	end
	self._stats.LastStepCost = os.clock() - started
	self._stats.Steps += 1
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------

local function newResult(action: string?)
	return {
		Success = true,
		Action = action,
		Created = {},
		Modified = {},
		Removed = {},
		Changed = {},
		Changes = {},
		Warnings = {},
		Errors = {},
		ValidationErrors = {},
		Notes = {},
	}
end

local function fail(result, message: string)
	result.Success = false
	table.insert(result.Errors, message)
	return result
end

local function absorbReport(result, report)
	for _, entry in ipairs(report.Errors) do
		table.insert(result.Errors, entry.Message)
		table.insert(result.ValidationErrors, entry)
	end
	for _, entry in ipairs(report.Warnings) do
		Util.addUnique(result.Warnings, entry.Message)
	end
	Util.append(result.Notes, report.Notes)
	if not report.Success then
		result.Success = false
	end
end

---------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------

function VisualFX:_ValidationChecks(options: { [string]: any }?)
	local checks = {
		function(normalized, report)
			self.Presets:CheckInheritance(normalized, report)
		end,
	}
	if not (options and options.SkipSceneChecks) then
		table.insert(checks, function(normalized, report)
			self.Inspector:CheckConfiguration(normalized, report)
		end)
		table.insert(checks, function(normalized, report)
			self.Quality:CheckConfiguration(self, normalized, report)
		end)
	end
	return checks
end

--[[
	Validates a configuration without applying it.
	options: { Partial = boolean, AllowRemove = boolean }
	Returns { Success, Errors = {...}, Warnings = {...}, Notes, Normalized }
]]
function VisualFX:Validate(configuration: any, options: { [string]: any }?)
	local opts = options or {}
	local config = configuration
	if config == nil then
		config = self._authored
	end
	if typeof(config) == "table" and config.Inherits and not opts.Partial then
		local expandReport = Validation.Report.new()
		self.Presets:CheckInheritance({ Inherits = if typeof(config.Inherits) == "string" then { config.Inherits } else config.Inherits }, expandReport)
		if not expandReport.Success then
			return expandReport:ToTable()
		end
		config = self.Presets:Expand(config)
	end
	local report = self.Validator:Validate(config, {
		Partial = opts.Partial,
		AllowRemove = opts.AllowRemove,
		Checks = self:_ValidationChecks(opts),
	})
	return report:ToTable()
end
VisualFX.ValidateConfiguration = VisualFX.Validate

---------------------------------------------------------------------------
-- Mutation pipeline
---------------------------------------------------------------------------

function VisualFX:_ScopeFor(resolved, replace: boolean?)
	if replace then
		return nil
	end
	local scope = {}
	for _, name in ipairs(Config.sections(self._resolved)) do
		scope[name] = true
	end
	for _, name in ipairs(Config.sections(resolved)) do
		scope[name] = true
	end
	return scope
end

--[[
	Applies a fully validated authored configuration.
	options: { Action, Replace, DryRun, Transition = { Duration, Easing, EasingDirection } }
]]
function VisualFX:_ApplyAuthored(authored: { [string]: any }, options: { [string]: any }, result)
	if self.Transitions:IsActive() and not (options.Transition or options.DryRun) then
		self.Transitions:Cancel(false)
	end
	if authored.Quality then
		self.Quality:ApplySection(authored.Quality)
	end
	local resolved = self.Scene:Resolve(authored)
	local scope = self:_ScopeFor(resolved, options.Replace)

	if options.DryRun then
		local plan = self.Scene:Plan(resolved, { Scope = scope })
		result.DryRun = true
		result.Diff = self:_PlanToDiff(plan)
		result.Configuration = Util.deepCopy(authored)
		Util.append(result.Warnings, plan.Warnings)
		for _, entry in ipairs(plan.Added) do
			Util.addUnique(result.Created, entry.Type)
		end
		result.Modified = table.clone(plan.Modified)
		for _, entry in ipairs(plan.Removed) do
			Util.addUnique(result.Removed, entry.Type)
		end
		return result
	end

	local previousWeather = self._resolved._Weather
	if options.Transition then
		local transition = self.Transitions:Start(resolved, {
			Duration = options.Transition.Duration,
			Easing = options.Transition.Easing,
			EasingDirection = options.Transition.EasingDirection,
			Scope = scope,
		})
		local plan = transition.Plan
		for _, entry in ipairs(plan.Added) do
			Util.addUnique(result.Created, entry.Type)
		end
		result.Modified = table.clone(plan.Modified)
		for _, entry in ipairs(plan.Removed) do
			Util.addUnique(result.Removed, entry.Type)
		end
		result.Changes = plan.Changes
		Util.append(result.Warnings, plan.Warnings)
		Util.append(result.Warnings, transition.Warnings)
		result.TransitionId = transition.Id
		result.Duration = transition.Duration
		self._activeSpecs = plan.Specs
	else
		local plan = self.Scene:Plan(resolved, { Scope = scope })
		local executed = self.Scene:Execute(plan)
		result.Created = executed.Created
		result.Modified = executed.Modified
		result.Removed = executed.Removed
		result.Changes = executed.Changes
		for _, warning in ipairs(executed.Warnings) do
			Util.addUnique(result.Warnings, warning)
		end
		self._activeSpecs = plan.Specs
	end

	self._authored = Util.deepCopy(authored)
	self._resolved = resolved

	for _, change in ipairs(result.Changes) do
		if change.Property then
			Util.addUnique(result.Changed, change.Type .. "." .. change.Property)
		end
	end
	result.Configuration = Util.deepCopy(authored)

	-- Weather notifications and optional audio hooks.
	local currentWeather = resolved._Weather
	local previousType = previousWeather and previousWeather.Type
	local currentType = currentWeather and currentWeather.Type
	if previousType ~= currentType or (previousWeather and currentWeather and previousWeather.Intensity ~= currentWeather.Intensity) then
		self.Events.WeatherChanged:Fire({
			Previous = previousType,
			Current = currentType,
			Intensity = currentWeather and currentWeather.Intensity or 0,
		})
	end
	for _, hook in ipairs(Weather.DiffAudio(previousWeather, currentWeather)) do
		self.Events.AudioHook:Fire(hook)
		if self._audioHandler then
			pcall(self._audioHandler, hook)
		end
	end

	self.Events.Changed:Fire(result)
	return result
end

--[[
	Validates `candidate` as a complete authored configuration and applies it.
]]
function VisualFX:_ApplyCandidate(candidate: { [string]: any }, options: { [string]: any }, result)
	local report = self.Validator:Validate(candidate, { Checks = self:_ValidationChecks(options) })
	absorbReport(result, report)
	if not report.Success then
		result.Configuration = nil
		return result
	end
	return self:_ApplyAuthored(report.Normalized, options, result)
end

-- Expands `Inherits` in an input configuration, recording problems in result.
function VisualFX:_ExpandInherits(input: { [string]: any }, result): { [string]: any }?
	if input.Inherits == nil then
		return input
	end
	local report = Validation.Report.new()
	local inherits = input.Inherits
	if typeof(inherits) == "string" then
		inherits = { inherits }
	end
	if typeof(inherits) ~= "table" then
		fail(result, "Inherits must be a preset name or a list of preset names")
		return nil
	end
	self.Presets:CheckInheritance({ Inherits = inherits }, report)
	if not report.Success then
		absorbReport(result, report)
		return nil
	end
	local expanded = self.Presets:Expand(input)
	return expanded
end

--[[
	Merges an overlay into the current configuration and applies it.
	The overlay may use "$remove" (VisualFX.REMOVE) to delete keys.
]]
function VisualFX:_MutateOverlay(overlay: any, options: { [string]: any }?)
	local opts = options or {}
	local result = newResult(opts.Action)
	if typeof(overlay) ~= "table" then
		return fail(result, "configuration must be a table, received " .. typeof(overlay))
	end
	local expanded = self:_ExpandInherits(overlay, result)
	if not expanded then
		return result
	end
	local report = self.Validator:Validate(expanded, { Partial = true, AllowRemove = true })
	absorbReport(result, report)
	if not report.Success then
		return result
	end
	local candidate = Config.merge(self._authored, report.Normalized)
	Config.stripRemovals(candidate)
	candidate.Version = Config.CURRENT_VERSION
	return self:_ApplyCandidate(candidate, opts, result)
end

-- Replaces the value at a configuration path (after normalizing it) and applies.
function VisualFX:_ReplacePath(path: { string }, value: any, options: { [string]: any }?)
	local opts = options or {}
	local result = newResult(opts.Action)
	local wrapped = {}
	local node = wrapped
	for index = 1, #path - 1 do
		node[path[index]] = {}
		node = node[path[index]]
	end
	node[path[#path]] = value
	local report = self.Validator:Validate(wrapped, { Partial = true })
	absorbReport(result, report)
	if not report.Success then
		return result
	end
	local normalizedValue = Util.getPath(report.Normalized, table.concat(path, "."))
	local candidate = Util.deepCopy(self._authored)
	Util.setPath(candidate, table.concat(path, "."), normalizedValue)
	return self:_ApplyCandidate(candidate, opts, result)
end

-- Applies a complete configuration, replacing the current scene.
function VisualFX:_ReplaceScene(configuration: any, options: { [string]: any }?)
	local opts = table.clone(options or {})
	opts.Replace = true
	local result = newResult(opts.Action)
	if typeof(configuration) ~= "table" then
		return fail(result, "configuration must be a table, received " .. typeof(configuration))
	end
	local expanded = self:_ExpandInherits(configuration, result)
	if not expanded then
		return result
	end
	local candidate = Util.deepCopy(expanded)
	candidate.Inherits = nil
	return self:_ApplyCandidate(candidate, opts, result)
end

---------------------------------------------------------------------------
-- Section setters
---------------------------------------------------------------------------

local function setter(section: string)
	return function(self, configuration: { [string]: any }, options: { [string]: any }?)
		if options and options.Replace then
			return self:_ReplacePath({ section }, configuration, { Action = "Set" .. section })
		end
		return self:_MutateOverlay({ [section] = configuration }, { Action = "Set" .. section })
	end
end

-- Merge semantics: listed properties change, others keep their values.
-- Pass { Replace = true } to replace the section exactly.
VisualFX.SetAtmosphere = setter("Atmosphere")
VisualFX.SetLighting = setter("Lighting")
VisualFX.SetWater = setter("Water")
VisualFX.SetSky = setter("Sky")
VisualFX.SetClouds = setter("Clouds")
VisualFX.SetPostProcessing = setter("PostProcessing")
VisualFX.SetEnvironment = setter("Environment")

function VisualFX:SetWind(configuration: { [string]: any })
	return self:_MutateOverlay({ Environment = { Wind = configuration } }, { Action = "SetWind" })
end

function VisualFX:SetDayNightCycle(configuration: { [string]: any })
	return self:_MutateOverlay({ Environment = { DayNight = configuration } }, { Action = "SetDayNightCycle" })
end

---------------------------------------------------------------------------
-- Particles, weather, zones, custom effects
---------------------------------------------------------------------------

function VisualFX:CreateParticleSystem(name: string, configuration: { [string]: any }?)
	if typeof(name) ~= "string" or name == "" then
		return fail(newResult("CreateParticleSystem"), "CreateParticleSystem requires a name")
	end
	return self:_ReplacePath({ "Particles", name }, configuration or {}, { Action = "CreateParticleSystem" })
end

function VisualFX:UpdateParticleSystem(name: string, configuration: { [string]: any })
	return self:_MutateOverlay({ Particles = { [name] = configuration } }, { Action = "UpdateParticleSystem" })
end

function VisualFX:RemoveParticleSystem(name: string)
	local result = newResult("RemoveParticleSystem")
	if not (self._authored.Particles and self._authored.Particles[name]) then
		return fail(result, string.format("no particle system named '%s'", tostring(name)))
	end
	return self:_MutateOverlay({ Particles = { [name] = Config.REMOVE } }, { Action = "RemoveParticleSystem" })
end

function VisualFX:GetParticleSystem(name: string)
	return self.Particles:Get(name)
end

function VisualFX:ListParticleSystems(): { string }
	return self.Particles:List()
end

function VisualFX:CreateWeather(weatherType: string, configuration: { [string]: any }?)
	local value = Util.deepCopy(configuration or {})
	value.Type = weatherType
	return self:_ReplacePath({ "Weather" }, value, { Action = "CreateWeather" })
end
VisualFX.SetWeather = VisualFX.CreateWeather

function VisualFX:UpdateWeather(configuration: { [string]: any })
	return self:_MutateOverlay({ Weather = configuration }, { Action = "UpdateWeather" })
end

function VisualFX:RemoveWeather()
	return self:_MutateOverlay({ Weather = Config.REMOVE }, { Action = "RemoveWeather" })
end

function VisualFX:GetWeather()
	return self.Weather:Get()
end

function VisualFX:CreateZone(name: string, configuration: { [string]: any })
	return self:_ReplacePath({ "Environment", "Zones", name }, configuration, { Action = "CreateZone" })
end

function VisualFX:UpdateZone(name: string, configuration: { [string]: any })
	return self:_MutateOverlay({ Environment = { Zones = { [name] = configuration } } }, { Action = "UpdateZone" })
end

function VisualFX:RemoveZone(name: string)
	return self:_MutateOverlay({ Environment = { Zones = { [name] = Config.REMOVE } } }, { Action = "RemoveZone" })
end

--[[
	Registers a custom effect type (see Core/Registry.luau). Instances are
	then declared with VisualFX:CreateEffect(id, { Effect = name, ... }) or in
	the Effects section of a configuration.
]]
function VisualFX:RegisterEffect(definition)
	local result = newResult("RegisterEffect")
	local ok, problem = pcall(self.Registry.RegisterEffect, self.Registry, definition)
	if not ok then
		return fail(result, tostring(problem))
	end
	return result
end

function VisualFX:CreateEffect(id: string, configuration: { [string]: any })
	return self:_ReplacePath({ "Effects", id }, configuration, { Action = "CreateEffect" })
end

function VisualFX:RemoveEffect(id: string)
	return self:_MutateOverlay({ Effects = { [id] = Config.REMOVE } }, { Action = "RemoveEffect" })
end

function VisualFX:RegisterWeather(definition)
	self.Registry:RegisterWeather(definition)
end

function VisualFX:RegisterParticleTemplate(name: string, template)
	self.Registry:RegisterParticleTemplate(name, template)
end

---------------------------------------------------------------------------
-- Scenes and presets
---------------------------------------------------------------------------

--[[
	Creates a scene from either a configuration table or a high-level
	description ({ Mood, Time, Weather, Environment, Fog, LightingStyle, ... }),
	replacing the current managed scene.
	options: { DryRun, Transition = { Duration, Easing } }
]]
function VisualFX:CreateScene(input: any, options: { [string]: any }?)
	local opts = table.clone(options or {})
	opts.Action = opts.Action or "CreateScene"
	if typeof(input) == "table" and self.Director:IsDescription(input) then
		return self.Director:CreateScene(input, opts)
	end
	return self:_ReplaceScene(input, opts)
end

-- Merges changes into the current scene (use "$remove" to delete keys).
function VisualFX:UpdateScene(input: any, options: { [string]: any }?)
	local opts = table.clone(options or {})
	opts.Action = opts.Action or "UpdateScene"
	if typeof(input) == "table" and self.Director:IsDescription(input) then
		opts.Merge = true
		return self.Director:CreateScene(input, opts)
	end
	return self:_MutateOverlay(input, opts)
end

--[[
	Applies a preset by name. options:
	  Merge       merge into the current scene instead of replacing it
	  Overrides   configuration merged on top of the preset
	  Transition  { Duration, Easing } for a smooth change
	  DryRun      only report what would change
]]
function VisualFX:ApplyPreset(name: string, options: { [string]: any }?)
	local opts = table.clone(options or {})
	opts.Action = "ApplyPreset"
	local result = newResult("ApplyPreset")
	local preset, problem = self.Presets:Resolve(name)
	if not preset then
		local suggestion = Util.suggest(tostring(name), Util.sortedKeys(self:_PresetNames()))
		return fail(result, (problem or "unknown preset") .. if suggestion then " (did you mean '" .. suggestion .. "'?)" else "")
	end
	if opts.Overrides then
		preset = Config.merge(preset, opts.Overrides)
		Config.stripRemovals(preset)
	end
	local applied
	if opts.Merge then
		applied = self:_MutateOverlay(preset, opts)
	else
		applied = self:_ReplaceScene(preset, opts)
	end
	applied.Preset = self.Presets:FindName(name)
	return applied
end

function VisualFX:_PresetNames()
	local names = {}
	for _, item in ipairs(self.Presets:List()) do
		names[item.Name] = true
	end
	return names
end

function VisualFX:SavePreset(name: string, configuration: { [string]: any }?, options: { [string]: any }?)
	local result = newResult("SavePreset")
	local config = configuration or self:ExportConfiguration()
	local report = self.Validator:Validate(self.Presets:Expand(config), {
		Checks = { function(normalized, r)
			self.Presets:CheckInheritance(normalized, r)
		end },
	})
	absorbReport(result, report)
	if not report.Success then
		return result
	end
	-- Keep Inherits so composed presets stay composed; values are normalized.
	local toSave = Util.deepCopy(config)
	local normalizedOwn = self.Validator:Validate(config, { Partial = true })
	if normalizedOwn.Success then
		local inherits = config.Inherits
		toSave = normalizedOwn.Normalized
		toSave.Inherits = if typeof(inherits) == "string" then { inherits } else inherits
	end
	local ok, problem = self.Presets:Save(name, toSave, options)
	if not ok then
		return fail(result, problem or "could not save preset")
	end
	result.Preset = name
	result.Configuration = toSave
	return result
end

function VisualFX:DeletePreset(name: string)
	local result = newResult("DeletePreset")
	local ok, problem = self.Presets:Delete(name)
	if not ok then
		return fail(result, problem or "could not delete preset")
	end
	result.Preset = name
	return result
end

function VisualFX:GetPreset(name: string)
	return self.Presets:Resolve(name)
end

function VisualFX:ListPresets(filter: { [string]: any }?)
	return self.Presets:List(filter)
end

function VisualFX:ComposePresets(names: { string }, overrides: { [string]: any }?)
	return self.Presets:Compose(names, overrides)
end

---------------------------------------------------------------------------
-- Transitions
---------------------------------------------------------------------------

--[[
	Smoothly transitions to a configuration.
	  VisualFX:TransitionTo({ Duration = 8, Easing = "Smooth", Configuration = {...} })
	  VisualFX:TransitionTo({ Duration = 5, Preset = "Night" })
	Configuration is merged into the current scene unless Replace = true.
]]
function VisualFX:TransitionTo(options: { [string]: any })
	local result = newResult("TransitionTo")
	if typeof(options) ~= "table" then
		return fail(result, "TransitionTo expects { Duration, Configuration | Preset }")
	end
	local configuration = options.Configuration
	local replace = options.Replace == true
	if options.Preset then
		local preset, problem = self.Presets:Resolve(options.Preset)
		if not preset then
			return fail(result, problem or "unknown preset")
		end
		configuration = if configuration then Config.merge(preset, configuration) else preset
		replace = options.Replace ~= false
	end
	if typeof(configuration) ~= "table" then
		return fail(result, "TransitionTo requires Configuration or Preset")
	end
	local duration = options.Duration or 1
	if typeof(duration) ~= "number" or duration < 0 then
		return fail(result, "Duration must be a non-negative number")
	end
	local transition = { Duration = duration, Easing = options.Easing, EasingDirection = options.EasingDirection }
	if replace then
		return self:_ReplaceScene(configuration, { Action = "TransitionTo", Transition = transition })
	end
	return self:_MutateOverlay(configuration, { Action = "TransitionTo", Transition = transition })
end
VisualFX.TransitionScene = VisualFX.TransitionTo

function VisualFX:CancelTransition(complete: boolean?)
	return self.Transitions:Cancel(complete)
end

function VisualFX:IsTransitioning(): boolean
	return self.Transitions:IsActive()
end

---------------------------------------------------------------------------
-- Preview (non-destructive editing)
---------------------------------------------------------------------------

--[[
	Applies a configuration as a preview. Every change is journaled until
	CommitPreview() keeps it or RevertPreview() restores the previous state.
	Calling Preview again while previewing continues the same session.
	options: { Replace = boolean }
]]
function VisualFX:Preview(configuration: any, options: { [string]: any }?)
	local opts = options or {}
	if not self._preview then
		self.InstanceManager:BeginJournal("Preview")
		self._preview = {
			Authored = Util.deepCopy(self._authored),
			Resolved = Util.deepCopy(self._resolved),
			ActiveSpecs = self._activeSpecs,
			Runtime = Util.deepCopy(self.Scene._runtimeApplied),
			Quality = { Level = self.Quality.Level, Overrides = Util.deepCopy(self.Quality.Overrides) },
		}
	end
	local result
	if opts.Replace then
		result = self:_ReplaceScene(configuration, { Action = "Preview" })
	else
		result = self:_MutateOverlay(configuration, { Action = "Preview" })
	end
	result.Previewing = true
	return result
end

function VisualFX:IsPreviewing(): boolean
	return self._preview ~= nil
end

function VisualFX:CommitPreview()
	local result = newResult("CommitPreview")
	if not self._preview then
		return fail(result, "no preview in progress")
	end
	if self.Transitions:IsActive() then
		self.Transitions:Cancel(true)
	end
	result.Committed = self.InstanceManager:CommitJournal()
	self._preview = nil
	result.Configuration = Util.deepCopy(self._authored)
	return result
end

function VisualFX:RevertPreview()
	local result = newResult("RevertPreview")
	if not self._preview then
		return fail(result, "no preview in progress")
	end
	if self.Transitions:IsActive() then
		self.Transitions:Cancel(false)
	end
	local reverted = self.InstanceManager:RevertJournal()
	local snapshot = self._preview
	self._preview = nil
	self._authored = snapshot.Authored
	self._resolved = snapshot.Resolved
	self._activeSpecs = snapshot.ActiveSpecs
	self.Scene._runtimeApplied = snapshot.Runtime
	self.Quality:Set(snapshot.Quality.Level, snapshot.Quality.Overrides)
	result.Restored = reverted.Restored
	Util.append(result.Warnings, reverted.Skipped)
	result.Configuration = Util.deepCopy(self._authored)
	self.Events.Changed:Fire(result)
	return result
end

---------------------------------------------------------------------------
-- Inspection, diff and conflicts
---------------------------------------------------------------------------

function VisualFX:InspectScene(options: { [string]: any }?)
	return self.Inspector:Inspect(options)
end

function VisualFX:DetectConflicts()
	return self.Inspector:DetectConflicts()
end

function VisualFX:_PlanToDiff(plan)
	local modified = {}
	for _, change in ipairs(plan.Changes) do
		if not change.Create and change.Property then
			table.insert(modified, {
				ID = change.ID,
				Type = change.Type,
				Property = change.Property,
				From = change.From,
				To = change.To,
				Restore = change.Restore,
			})
		end
	end
	return {
		Added = plan.Added,
		Modified = modified,
		Removed = plan.Removed,
		Unchanged = plan.Unchanged,
		Warnings = plan.Warnings,
		Summary = Scene.FormatDiff(plan),
	}
end

--[[
	Compares a configuration with the live scene without changing anything.
	options.Merge = true compares the result of merging into the current scene;
	otherwise the configuration is treated as a complete scene.
	Returns { Success, Added, Modified, Removed, Unchanged, Warnings, Summary, Errors }
]]
function VisualFX:DiffScene(configuration: any, options: { [string]: any }?)
	local opts = options or {}
	local result = newResult("DiffScene")
	if configuration == nil then
		configuration = self._authored
	end
	if typeof(configuration) == "table" and self.Director:IsDescription(configuration) then
		local interpreted = self.Director:Interpret(configuration)
		configuration = interpreted.Configuration
		Util.append(result.Warnings, interpreted.Warnings)
	end
	local diffResult
	if opts.Merge then
		diffResult = self:_MutateOverlay(configuration, { Action = "DiffScene", DryRun = true })
	else
		diffResult = self:_ReplaceScene(configuration, { Action = "DiffScene", DryRun = true })
	end
	local diff = diffResult.Diff or { Added = {}, Modified = {}, Removed = {}, Unchanged = {}, Warnings = {}, Summary = {} }
	return {
		Success = diffResult.Success,
		Action = "DiffScene",
		Added = diff.Added,
		Modified = diff.Modified,
		Removed = diff.Removed,
		Unchanged = diff.Unchanged,
		Warnings = Util.append(result.Warnings, diffResult.Warnings),
		Errors = diffResult.Errors,
		Summary = diff.Summary,
		Configuration = diffResult.Configuration,
	}
end

---------------------------------------------------------------------------
-- Import / export / code generation
---------------------------------------------------------------------------

function VisualFX:GetConfiguration()
	return Util.deepCopy(self._authored)
end

function VisualFX:GetResolvedConfiguration()
	return self._resolved
end

function VisualFX:GetActiveSpecs()
	return self._activeSpecs
end

--[[
	Exports the current configuration.
	options.Format: "table" (default) | "json" | "document"
	options.Resolved: export the fully resolved configuration (weather expanded)
	options.Metadata: metadata to attach
]]
function VisualFX:ExportConfiguration(options: { [string]: any }?)
	local opts = options or {}
	local config
	if opts.Resolved then
		config = Util.deepCopy(self._resolved)
		for key in pairs(config) do
			if string.sub(key, 1, 1) == "_" then
				config[key] = nil
			end
		end
	else
		config = Util.deepCopy(self._authored)
	end
	config.Version = Config.CURRENT_VERSION
	if opts.Metadata then
		config.Metadata = Config.merge(config.Metadata or {}, opts.Metadata)
	end
	if opts.Format == "json" then
		return Serialization:Export(config, opts.Pretty)
	elseif opts.Format == "document" then
		return Serialization:Serialize(config)
	end
	return config
end

--[[
	Imports a configuration (table, VisualFXConfig document, or JSON text).
	It is validated before anything is applied.
	options: { Apply = true (default), Merge = false, DryRun = false }
]]
function VisualFX:ImportConfiguration(data: any, options: { [string]: any }?)
	local opts = options or {}
	local result = newResult("ImportConfiguration")
	local config, warnings, problem = Serialization:Deserialize(data)
	Util.append(result.Warnings, warnings)
	if not config then
		return fail(result, problem or "could not read configuration")
	end
	local validation = self:Validate(config)
	for _, entry in ipairs(validation.Errors) do
		table.insert(result.Errors, entry.Message)
		table.insert(result.ValidationErrors, entry)
	end
	for _, entry in ipairs(validation.Warnings) do
		Util.addUnique(result.Warnings, entry.Message)
	end
	if not validation.Success then
		result.Success = false
		return result
	end
	if opts.Apply == false then
		result.Configuration = validation.Normalized
		return result
	end
	local applied
	if opts.Merge then
		applied = self:_MutateOverlay(config, { Action = "ImportConfiguration", DryRun = opts.DryRun })
	else
		applied = self:_ReplaceScene(config, { Action = "ImportConfiguration", DryRun = opts.DryRun })
	end
	Util.append(applied.Warnings, result.Warnings)
	return applied
end

--[[
	Generates readable, deterministic Luau for a configuration (default: the
	current configuration). options: see Codegen/LuauGenerator.luau.
]]
function VisualFX:GenerateCode(configuration: { [string]: any }?, options: { [string]: any }?)
	return LuauGenerator.Generate(configuration or self._authored, options, self.Registry)
end

---------------------------------------------------------------------------
-- Quality and diagnostics
---------------------------------------------------------------------------

function VisualFX:SetQuality(level: string, overrides: { [string]: any }?)
	local result = newResult("SetQuality")
	if not table.find(Quality.Levels, level) then
		local suggestion = Util.suggest(tostring(level), Quality.Levels)
		return fail(
			result,
			string.format(
				"unknown quality level '%s'%s. Available: %s",
				tostring(level),
				if suggestion then " (did you mean '" .. suggestion .. "'?)" else "",
				table.concat(Quality.Levels, ", ")
			)
		)
	end
	local section = Util.deepCopy(overrides or {})
	section.Level = level
	local applied = self:_ReplacePath({ "Quality" }, section, { Action = "SetQuality" })
	if applied.Success then
		self.Events.QualityChanged:Fire({ Level = level, Profile = self.Quality:GetProfile() })
		applied.Profile = Util.deepCopy(self.Quality:GetProfile())
	end
	return applied
end

function VisualFX:GetQuality()
	return { Level = self.Quality.Level, Profile = Util.deepCopy(self.Quality:GetProfile()) }
end

--[[
	Workload estimates. Never an FPS prediction.
]]
function VisualFX:GetPerformanceStats()
	local profile = self.Quality:GetProfile()
	local activeSystems, totalRate, estimatedParticles = 0, 0, 0
	for _, spec in ipairs(self._activeSpecs) do
		if spec.Particle and spec.Properties.Enabled ~= false then
			activeSystems += 1
			totalRate += spec.Properties.Rate or 0
			estimatedParticles += Particles.EstimateCount(spec)
		end
	end
	local culled = 0
	for _, controller in ipairs(self.Controllers) do
		if controller.Name == "Particles" then
			culled = controller.Culled or 0
		end
	end
	return {
		Quality = profile.Level,
		ActiveParticleSystems = activeSystems,
		CulledParticleSystems = culled,
		EstimatedParticleRate = math.floor(totalRate + 0.5),
		EstimatedLiveParticles = math.floor(estimatedParticles + 0.5),
		ParticleBudget = profile.MaxParticleRate,
		BudgetScale = self.Quality.LastBudget.BudgetScale,
		RateScale = self.Quality.LastBudget.RateScale,
		QualityDisabledSystems = table.clone(self.Quality.LastBudget.Disabled),
		ManagedInstances = #self.InstanceManager:GetManaged(true),
		PooledInstances = self.InstanceManager:GetPoolSize(),
		UpdateFrequency = profile.UpdateFrequency,
		TransitionFrequency = profile.TransitionFrequency,
		WeatherFrequency = profile.WeatherFrequency,
		ActiveTransition = self.Transitions:GetActive(),
		RuntimeControllers = self.Settings.RuntimeControllers,
		LastStepCostMs = math.floor(self._stats.LastStepCost * 100000 + 0.5) / 100,
	}
end

---------------------------------------------------------------------------
-- Reset / lifecycle
---------------------------------------------------------------------------

--[[
	Removes every VisualFX-managed instance, releases adopted instances and
	restores original property values. Developer-created content is untouched.
]]
function VisualFX:ResetManagedEffects()
	local result = newResult("ResetManagedEffects")
	if self.Transitions:IsActive() then
		self.Transitions:Cancel(false)
	end
	local reset = Cleanup.ResetManagedEffects(self)
	result.Removed = reset.Removed
	result.Restored = reset.Restored
	Util.append(result.Warnings, reset.Warnings)
	local previousWeather = self._resolved._Weather
	self._authored = { Version = Config.CURRENT_VERSION }
	self._resolved = { Version = Config.CURRENT_VERSION }
	self._activeSpecs = {}
	self.Scene._runtimeApplied = {}
	self.Quality:Set("High")
	for _, hook in ipairs(Weather.DiffAudio(previousWeather, nil)) do
		self.Events.AudioHook:Fire(hook)
	end
	self.Events.Changed:Fire(result)
	return result
end

-- Optional audio integration: handler({ Hook, Action, Volume, Delay? }).
function VisualFX:SetAudioHandler(handler: ((hook: { [string]: any }) -> ())?)
	self._audioHandler = handler
	if handler then
		self._maid:Give(self.Events.AudioHook:Connect(function(hook)
			if hook.Action == "Trigger" and self._audioHandler then
				pcall(self._audioHandler, hook)
			end
		end))
	end
end

function VisualFX:Destroy()
	self:Stop()
	self.Transitions:Cancel(false)
	self._maid:Clean()
	self.InstanceManager:ClearPool()
	Events.destroyBus(self.Events)
end

---------------------------------------------------------------------------
-- AI integration
---------------------------------------------------------------------------

--[[
	Central structured command interface for AI agents:
	  VisualFX:Execute({ Action = "CreateWeather", Type = "Thunderstorm", Configuration = {...} })
	See Documentation/COMMANDS.md.
]]
function VisualFX:Execute(command: any)
	return self.Commands:Execute(command)
end

function VisualFX:GetSchema(options: { [string]: any }?)
	return Schema.Build(self, options)
end

function VisualFX:GetDocumentation()
	return AgentDocumentation.Build(self)
end

function VisualFX:GetCompatibilityReport()
	return self.Compatibility:BuildReport(self.Registry:CollectPropertyFields())
end

---------------------------------------------------------------------------
-- Module export: a lazily created default engine that also exposes the class.
---------------------------------------------------------------------------

local defaultEngine = nil

local Module = {
	new = VisualFX.new,
	Class = VisualFX,
	Version = VisualFX.Version,
	ConfigVersion = VisualFX.ConfigVersion,
	REMOVE = VisualFX.REMOVE,
}

function Module.GetDefault()
	if not defaultEngine then
		defaultEngine = VisualFX.new()
	end
	return defaultEngine
end

setmetatable(Module, {
	__index = function(_, key)
		local engine = Module.GetDefault()
		local value = engine[key]
		if typeof(value) == "function" then
			return function(selfArg, ...)
				if selfArg == Module then
					selfArg = engine
				end
				return value(selfArg, ...)
			end
		end
		return value
	end,
})

return Module
