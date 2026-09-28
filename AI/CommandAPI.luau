--[[
	VisualFX.AI.CommandAPI

	The structured command interface for AI agents:

	  local result = VisualFX:Execute({
	      Action = "CreateWeather",
	      Type = "Thunderstorm",
	      Configuration = { RainIntensity = 0.9, Fog = 0.4, Wind = 35, Lightning = true },
	  })

	Every command:
	  * is checked against the action's field schema (unknown actions and
	    malformed fields produce errors with suggestions, never exceptions);
	  * runs through the standard validation pipeline (schema, compatibility,
	    conflicts, performance) before touching the scene;
	  * returns a structured result:
	      { Success, Action, Created, Modified, Removed, Changed, Changes,
	        Warnings, Errors, Data? }

	Mutating actions accept DryRun = true (report the diff, change nothing).
	"Batch" runs several commands and, when Atomic (default), reverts all of
	them if any fails. Commands are data only; code is never executed.
]]

local Root = script.Parent.Parent
local Util = require(Root.Core.Util)

local CommandAPI = {}
CommandAPI.__index = CommandAPI

local function field(kind: string, description: string, required: boolean?)
	return { Kind = kind, Description = description, Required = required == true }
end

local CONFIG = field("table", "configuration table (see CONFIG_SCHEMA.md)")
local DRY_RUN = field("boolean", "only report what would change")

--[[
	Action catalogue. Handler(engine, command) returns a result table.
]]
CommandAPI.Actions = {
	InspectScene = {
		Description = "Structured description of the current visual state, managed effects and conflicts.",
		Fields = { Options = field("table", "{ MaxParticles = number }") },
		Handler = function(engine, command)
			local scene = engine:InspectScene(command.Options)
			return { Success = true, Data = scene, Summary = scene.Summary }
		end,
	},
	SetAtmosphere = {
		Description = "Set Atmosphere properties (merge; Replace = true to replace).",
		Mutating = true,
		Fields = { Configuration = CONFIG, Replace = field("boolean", "replace the section instead of merging"), DryRun = DRY_RUN },
		Required = { "Configuration" },
		Section = "Atmosphere",
	},
	SetLighting = {
		Description = "Set Lighting service properties (merge; Replace = true to replace).",
		Mutating = true,
		Fields = { Configuration = CONFIG, Replace = field("boolean", "replace the section"), DryRun = DRY_RUN },
		Required = { "Configuration" },
		Section = "Lighting",
	},
	SetWater = {
		Description = "Set terrain water properties (merge; Replace = true to replace).",
		Mutating = true,
		Fields = { Configuration = CONFIG, Replace = field("boolean", "replace the section"), DryRun = DRY_RUN },
		Required = { "Configuration" },
		Section = "Water",
	},
	SetSky = {
		Description = "Set Sky properties.",
		Mutating = true,
		Fields = { Configuration = CONFIG, Replace = field("boolean", "replace the section"), DryRun = DRY_RUN },
		Required = { "Configuration" },
		Section = "Sky",
	},
	SetClouds = {
		Description = "Set Clouds properties.",
		Mutating = true,
		Fields = { Configuration = CONFIG, Replace = field("boolean", "replace the section"), DryRun = DRY_RUN },
		Required = { "Configuration" },
		Section = "Clouds",
	},
	SetPostProcessing = {
		Description = "Set post-processing effects { Bloom, ColorCorrection, DepthOfField, SunRays, Blur }.",
		Mutating = true,
		Fields = { Configuration = CONFIG, Replace = field("boolean", "replace the section"), DryRun = DRY_RUN },
		Required = { "Configuration" },
		Section = "PostProcessing",
	},
	SetEnvironment = {
		Description = "Set Environment { Wind, DayNight, Zones }.",
		Mutating = true,
		Fields = { Configuration = CONFIG, Replace = field("boolean", "replace the section"), DryRun = DRY_RUN },
		Required = { "Configuration" },
		Section = "Environment",
	},
	CreateParticleSystem = {
		Description = "Create or replace a named particle system.",
		Mutating = true,
		Fields = { Name = field("string", "system name", true), Template = field("string", "particle template"), Configuration = CONFIG, DryRun = DRY_RUN },
		Handler = function(engine, command)
			local config = Util.deepCopy(command.Configuration or {})
			if command.Template then
				config.Template = command.Template
			end
			if command.DryRun then
				return engine:DiffScene({ Particles = { [command.Name] = config } }, { Merge = true })
			end
			return engine:CreateParticleSystem(command.Name, config)
		end,
	},
	UpdateParticleSystem = {
		Description = "Merge changes into an existing particle system.",
		Mutating = true,
		Fields = { Name = field("string", "system name", true), Configuration = field("table", "partial configuration", true), DryRun = DRY_RUN },
		Handler = function(engine, command)
			if command.DryRun then
				return engine:DiffScene({ Particles = { [command.Name] = command.Configuration } }, { Merge = true })
			end
			return engine:UpdateParticleSystem(command.Name, command.Configuration)
		end,
	},
	RemoveParticleSystem = {
		Description = "Remove a named particle system.",
		Mutating = true,
		Fields = { Name = field("string", "system name", true) },
		Handler = function(engine, command)
			return engine:RemoveParticleSystem(command.Name)
		end,
	},
	CreateWeather = {
		Description = "Set the weather. Type is a weather type; Configuration holds Intensity, Wind, Fog, Lightning, RainIntensity, ...",
		Mutating = true,
		Fields = { Type = field("string", "weather type", true), Configuration = CONFIG, Duration = field("number", "transition duration in seconds"), DryRun = DRY_RUN },
		Handler = function(engine, command)
			local config = Util.deepCopy(command.Configuration or {})
			config.Type = command.Type
			if command.DryRun then
				return engine:DiffScene({ Weather = config }, { Merge = true })
			end
			if command.Duration and command.Duration > 0 then
				-- Replace only the Weather section, keeping the rest of the scene.
				local candidate = engine:GetConfiguration()
				candidate.Weather = config
				return engine:TransitionTo({ Duration = command.Duration, Configuration = candidate, Replace = true })
			end
			return engine:CreateWeather(command.Type, command.Configuration)
		end,
	},
	UpdateWeather = {
		Description = "Merge changes into the current weather (e.g. Intensity).",
		Mutating = true,
		Fields = { Configuration = field("table", "partial weather configuration", true), DryRun = DRY_RUN },
		Handler = function(engine, command)
			if command.DryRun then
				return engine:DiffScene({ Weather = command.Configuration }, { Merge = true })
			end
			return engine:UpdateWeather(command.Configuration)
		end,
	},
	RemoveWeather = {
		Description = "Remove the weather and everything it created.",
		Mutating = true,
		Fields = {},
		Handler = function(engine)
			return engine:RemoveWeather()
		end,
	},
	CreateZone = {
		Description = "Create or replace a spatial effect zone (Environment.Zones).",
		Mutating = true,
		Fields = { Name = field("string", "zone name", true), Configuration = field("table", "{ Effect, Position, Size, Intensity, ... }", true), DryRun = DRY_RUN },
		Handler = function(engine, command)
			if command.DryRun then
				return engine:DiffScene({ Environment = { Zones = { [command.Name] = command.Configuration } } }, { Merge = true })
			end
			return engine:CreateZone(command.Name, command.Configuration)
		end,
	},
	RemoveZone = {
		Description = "Remove a spatial effect zone.",
		Mutating = true,
		Fields = { Name = field("string", "zone name", true) },
		Handler = function(engine, command)
			return engine:RemoveZone(command.Name)
		end,
	},
	ApplyPreset = {
		Description = "Apply a preset (replaces the scene unless Merge = true).",
		Mutating = true,
		Fields = {
			Name = field("string", "preset name", true),
			Merge = field("boolean", "merge into the current scene"),
			Overrides = field("table", "configuration merged on top of the preset"),
			Duration = field("number", "transition duration in seconds"),
			Easing = field("string", "easing style"),
			DryRun = DRY_RUN,
		},
		Aliases = { Preset = "Name" },
		Handler = function(engine, command)
			local transition = nil
			if command.Duration and command.Duration > 0 then
				transition = { Duration = command.Duration, Easing = command.Easing }
			end
			return engine:ApplyPreset(command.Name, {
				Merge = command.Merge,
				Overrides = command.Overrides,
				Transition = transition,
				DryRun = command.DryRun,
			})
		end,
	},
	SavePreset = {
		Description = "Save a configuration (default: the current one) as a user preset.",
		Mutating = false,
		Fields = { Name = field("string", "preset name", true), Configuration = CONFIG, Overwrite = field("boolean", "replace an existing user preset") },
		Handler = function(engine, command)
			return engine:SavePreset(command.Name, command.Configuration, { Overwrite = command.Overwrite })
		end,
	},
	DeletePreset = {
		Description = "Delete a user preset (built-in presets are protected).",
		Fields = { Name = field("string", "preset name", true) },
		Handler = function(engine, command)
			return engine:DeletePreset(command.Name)
		end,
	},
	ListPresets = {
		Description = "List presets. Filter: { Category, Source, Search }.",
		Fields = { Filter = field("table", "{ Category, Source, Search }") },
		Handler = function(engine, command)
			return { Success = true, Data = engine:ListPresets(command.Filter) }
		end,
	},
	GetPreset = {
		Description = "Return a preset's resolved configuration (inheritance expanded).",
		Fields = { Name = field("string", "preset name", true) },
		Handler = function(engine, command)
			local preset, problem = engine:GetPreset(command.Name)
			if not preset then
				return { Success = false, Errors = { problem } }
			end
			return { Success = true, Data = preset, Configuration = preset }
		end,
	},
	CreateScene = {
		Description = "Create a complete scene from a configuration or a description { Mood, Time, Weather, Environment, Fog, LightingStyle, WaterStyle }.",
		Mutating = true,
		Fields = { Configuration = field("table", "configuration or description", true), Duration = field("number", "transition duration"), DryRun = DRY_RUN },
		Handler = function(engine, command)
			local transition = if command.Duration and command.Duration > 0 then { Duration = command.Duration } else nil
			return engine:CreateScene(command.Configuration, { DryRun = command.DryRun, Transition = transition })
		end,
	},
	UpdateScene = {
		Description = "Merge changes into the current scene. Use \"$remove\" to delete keys.",
		Mutating = true,
		Fields = { Configuration = field("table", "partial configuration", true), Duration = field("number", "transition duration"), DryRun = DRY_RUN },
		Handler = function(engine, command)
			local transition = if command.Duration and command.Duration > 0 then { Duration = command.Duration } else nil
			return engine:UpdateScene(command.Configuration, { DryRun = command.DryRun, Transition = transition })
		end,
	},
	TransitionScene = {
		Description = "Smoothly transition to a configuration (merged) or preset over Duration seconds.",
		Mutating = true,
		Fields = {
			Configuration = CONFIG,
			Preset = field("string", "preset to transition to"),
			Duration = field("number", "seconds (default 1)"),
			Easing = field("string", "Linear | Smooth | Sine | Quad | Cubic | Quart | Quint | Expo | Circular | Back"),
			EasingDirection = field("string", "In | Out | InOut"),
			Replace = field("boolean", "treat Configuration as a complete scene"),
		},
		Handler = function(engine, command)
			if not command.Configuration and not command.Preset then
				return { Success = false, Errors = { "TransitionScene requires Configuration or Preset" } }
			end
			return engine:TransitionTo({
				Duration = command.Duration or 1,
				Easing = command.Easing,
				EasingDirection = command.EasingDirection,
				Configuration = command.Configuration,
				Preset = command.Preset,
				Replace = command.Replace,
			})
		end,
	},
	DiffScene = {
		Description = "Compare a configuration with the live scene without changing anything.",
		Fields = { Configuration = CONFIG, Merge = field("boolean", "diff the result of merging instead of replacing") },
		Handler = function(engine, command)
			return engine:DiffScene(command.Configuration, { Merge = command.Merge })
		end,
	},
	PreviewScene = {
		Description = "Apply a configuration as a revertible preview (merge unless Replace).",
		Mutating = true,
		Fields = { Configuration = field("table", "configuration", true), Replace = field("boolean", "replace instead of merge") },
		Handler = function(engine, command)
			return engine:Preview(command.Configuration, { Replace = command.Replace })
		end,
	},
	CommitPreview = {
		Description = "Keep the current preview.",
		Fields = {},
		Handler = function(engine)
			return engine:CommitPreview()
		end,
	},
	RevertPreview = {
		Description = "Undo the current preview exactly (developer edits made meanwhile are kept).",
		Fields = {},
		Handler = function(engine)
			return engine:RevertPreview()
		end,
	},
	ExportConfiguration = {
		Description = "Export the current configuration. Format: table | json | document.",
		Fields = { Format = field("string", "table | json | document"), Resolved = field("boolean", "export the resolved configuration") },
		Handler = function(engine, command)
			local exported = engine:ExportConfiguration({ Format = command.Format, Resolved = command.Resolved })
			return { Success = true, Data = exported, Configuration = if typeof(exported) == "table" and not exported.Format then exported else nil }
		end,
	},
	ImportConfiguration = {
		Description = "Validate and apply a configuration (table, VisualFXConfig document or JSON text).",
		Mutating = true,
		Fields = { Data = field("any", "table or JSON string"), Configuration = CONFIG, Merge = field("boolean", "merge instead of replace"), Apply = field("boolean", "apply after validation (default true)"), DryRun = DRY_RUN },
		Handler = function(engine, command)
			local data = command.Data or command.Configuration
			if data == nil then
				return { Success = false, Errors = { "ImportConfiguration requires Data or Configuration" } }
			end
			return engine:ImportConfiguration(data, { Merge = command.Merge, Apply = command.Apply, DryRun = command.DryRun })
		end,
	},
	GenerateCode = {
		Description = "Generate readable Luau for a configuration (default: current).",
		Fields = { Configuration = CONFIG, Options = field("table", "{ Template = Script | LocalScript | Module | Transition, RequirePath, Comments }") },
		Handler = function(engine, command)
			local ok, code = pcall(engine.GenerateCode, engine, command.Configuration, command.Options)
			if not ok then
				return { Success = false, Errors = { tostring(code) } }
			end
			return { Success = true, Code = code, Data = code }
		end,
	},
	ValidateConfiguration = {
		Description = "Validate a configuration (default: current) without applying it.",
		Fields = { Configuration = CONFIG, Partial = field("boolean", "allow missing required fields") },
		Handler = function(engine, command)
			local report = engine:Validate(command.Configuration, { Partial = command.Partial })
			local errors, warnings = {}, {}
			for _, entry in ipairs(report.Errors) do
				table.insert(errors, entry.Message)
			end
			for _, entry in ipairs(report.Warnings) do
				table.insert(warnings, entry.Message)
			end
			return {
				Success = report.Success,
				Errors = errors,
				Warnings = warnings,
				ValidationErrors = report.Errors,
				ValidationWarnings = report.Warnings,
				Notes = report.Notes,
				Configuration = report.Normalized,
			}
		end,
	},
	DetectConflicts = {
		Description = "Detect conflicts in the live scene (duplicates, stacked effects, ignored fog, ...).",
		Fields = {},
		Handler = function(engine)
			local conflicts = engine:DetectConflicts()
			return { Success = true, Data = conflicts, Conflicts = conflicts }
		end,
	},
	ResetManagedEffects = {
		Description = "Remove all VisualFX-managed effects and restore original values. Developer content is untouched.",
		Mutating = true,
		Fields = {},
		Handler = function(engine)
			return engine:ResetManagedEffects()
		end,
	},
	SetQuality = {
		Description = "Set the quality level (Low | Medium | High | Ultra | Custom) with optional overrides.",
		Mutating = true,
		Fields = { Level = field("string", "quality level", true), Overrides = field("table", "profile overrides") },
		Handler = function(engine, command)
			return engine:SetQuality(command.Level, command.Overrides)
		end,
	},
	GetPerformanceStats = {
		Description = "Workload estimates (particle systems, particle rate, managed instances, update frequency).",
		Fields = {},
		Handler = function(engine)
			return { Success = true, Data = engine:GetPerformanceStats() }
		end,
	},
	GetSchema = {
		Description = "Machine-readable schema of sections, fields, weather types, templates, presets and commands.",
		Fields = { Format = field("string", "table (default) | jsonschema") },
		Handler = function(engine, command)
			if command.Format == "jsonschema" then
				local Schema = require(Root.AI.Schema)
				return { Success = true, Data = Schema.ToJSONSchema(engine) }
			end
			return { Success = true, Data = engine:GetSchema() }
		end,
	},
	GetDocumentation = {
		Description = "Structured agent guide (workflow, rules, actions, examples).",
		Fields = {},
		Handler = function(engine)
			return { Success = true, Data = engine:GetDocumentation() }
		end,
	},
	ListActions = {
		Description = "List every action with its fields.",
		Fields = {},
		Handler = function(engine)
			return { Success = true, Data = engine.Commands:Catalog() }
		end,
	},
	Batch = {
		Description = "Run several commands in order. Atomic (default true) reverts everything if any command fails.",
		Mutating = true,
		Fields = { Commands = field("table", "array of commands", true), Atomic = field("boolean", "revert all on failure (default true)") },
	},
}

-- Actions accept these extra keys without warnings.
local COMMON_FIELDS = { Action = true, Id = true, Comment = true }

function CommandAPI.new(engine)
	local self = setmetatable({}, CommandAPI)
	self.Engine = engine
	self.History = {}
	self.HistoryLimit = 50
	return self
end

function CommandAPI:Catalog()
	local catalog = {}
	for _, name in ipairs(Util.sortedKeys(CommandAPI.Actions)) do
		local action = CommandAPI.Actions[name]
		local fields = {}
		for _, fieldName in ipairs(Util.sortedKeys(action.Fields or {})) do
			local definition = action.Fields[fieldName]
			local required = definition.Required or (action.Required ~= nil and table.find(action.Required, fieldName) ~= nil)
			fields[fieldName] = { Kind = definition.Kind, Description = definition.Description, Required = required }
		end
		catalog[name] = { Description = action.Description, Mutating = action.Mutating == true, Fields = fields }
	end
	return catalog
end

local function normalizeResult(result, actionName: string)
	if typeof(result) ~= "table" then
		result = { Success = result ~= nil, Data = result }
	end
	result.Action = actionName
	result.Success = result.Success ~= false and (result.Errors == nil or #result.Errors == 0)
	result.Warnings = result.Warnings or {}
	result.Errors = result.Errors or {}
	result.Created = result.Created or {}
	result.Modified = result.Modified or {}
	result.Removed = result.Removed or {}
	result.Changed = result.Changed or {}
	return result
end

local function failure(actionName: string?, message: string, extra: { [string]: any }?)
	local result = normalizeResult({ Success = false, Errors = { message } }, actionName or "Unknown")
	if extra then
		for key, value in pairs(extra) do
			result[key] = value
		end
	end
	result.Success = false
	return result
end

-- Checks a command against its action's field schema.
function CommandAPI:ValidateCommand(command: any): (boolean, { string }, { string }, any)
	local errors, warnings = {}, {}
	if typeof(command) ~= "table" then
		table.insert(errors, "command must be a table, received " .. typeof(command))
		return false, errors, warnings, nil
	end
	local actionName = command.Action
	if typeof(actionName) ~= "string" then
		table.insert(errors, "command.Action must be a string naming an action (see ListActions)")
		return false, errors, warnings, nil
	end
	local action = CommandAPI.Actions[actionName]
	if not action then
		local suggestion = Util.suggest(actionName, Util.sortedKeys(CommandAPI.Actions))
		table.insert(
			errors,
			string.format("unknown action '%s'%s", actionName, if suggestion then " (did you mean '" .. suggestion .. "'?)" else "")
		)
		return false, errors, warnings, nil
	end
	local fields = action.Fields or {}
	for key, value in pairs(command) do
		if typeof(key) ~= "string" then
			table.insert(errors, "command keys must be strings")
		elseif not COMMON_FIELDS[key] and not fields[key] and not (action.Aliases and action.Aliases[key]) then
			local suggestion = Util.suggest(key, Util.sortedKeys(fields))
			table.insert(
				warnings,
				string.format("%s: unknown field '%s' ignored%s", actionName, key, if suggestion then " (did you mean '" .. suggestion .. "'?)" else "")
			)
		end
		local definition = fields[key]
		if definition and definition.Kind ~= "any" and value ~= nil and typeof(value) ~= definition.Kind then
			table.insert(
				errors,
				string.format("Invalid property:\n%s.%s\n\nExpected:\n%s\n\nReceived:\n%s", actionName, key, definition.Kind, typeof(value))
			)
		end
	end
	for alias, target in pairs(action.Aliases or {}) do
		if command[target] == nil and command[alias] ~= nil then
			command[target] = command[alias]
		end
	end
	for fieldName, definition in pairs(fields) do
		local required = definition.Required or (action.Required and table.find(action.Required, fieldName))
		if required and command[fieldName] == nil then
			table.insert(errors, string.format("%s requires field '%s' (%s)", actionName, fieldName, definition.Description))
		end
	end
	return #errors == 0, errors, warnings, action
end

function CommandAPI:_RunSection(action, command)
	local engine = self.Engine
	local section = action.Section
	if command.DryRun then
		local overlay = { [section] = command.Configuration }
		if command.Replace then
			local candidate = engine:GetConfiguration()
			candidate[section] = command.Configuration
			return engine:DiffScene(candidate)
		end
		return engine:DiffScene(overlay, { Merge = true })
	end
	return engine["Set" .. section](engine, command.Configuration, { Replace = command.Replace })
end

function CommandAPI:_RunBatch(command)
	local engine = self.Engine
	local commands = command.Commands
	if not Util.isArray(commands) then
		return failure("Batch", "Batch.Commands must be a non-empty array of commands")
	end
	local atomic = command.Atomic ~= false
	local ownsPreview = atomic and not engine:IsPreviewing()
	if ownsPreview then
		engine.InstanceManager:BeginJournal("Batch")
		engine._preview = {
			Authored = Util.deepCopy(engine._authored),
			Resolved = Util.deepCopy(engine._resolved),
			ActiveSpecs = engine._activeSpecs,
			Runtime = Util.deepCopy(engine.Scene._runtimeApplied),
			Quality = { Level = engine.Quality.Level, Overrides = Util.deepCopy(engine.Quality.Overrides) },
		}
	end
	local results = {}
	local batch = normalizeResult({ Success = true }, "Batch")
	for index, child in ipairs(commands) do
		if typeof(child) == "table" and child.Action == "Batch" then
			table.insert(results, failure("Batch", "nested Batch commands are not supported"))
		else
			table.insert(results, self:Execute(child))
		end
		local last = results[#results]
		for _, typeName in ipairs(last.Created) do
			Util.addUnique(batch.Created, typeName)
		end
		for _, typeName in ipairs(last.Modified) do
			Util.addUnique(batch.Modified, typeName)
		end
		for _, typeName in ipairs(last.Removed) do
			Util.addUnique(batch.Removed, typeName)
		end
		for _, warning in ipairs(last.Warnings) do
			table.insert(batch.Warnings, string.format("[%d %s] %s", index, tostring(last.Action), warning))
		end
		if not last.Success then
			for _, problem in ipairs(last.Errors) do
				table.insert(batch.Errors, string.format("[%d %s] %s", index, tostring(last.Action), problem))
			end
			batch.Success = false
			if atomic then
				break
			end
		end
	end
	if ownsPreview then
		if batch.Success then
			engine:CommitPreview()
		else
			engine:RevertPreview()
			batch.Reverted = true
		end
	end
	batch.Results = results
	batch.Configuration = engine:GetConfiguration()
	return batch
end

--[[
	Executes one command and returns a structured result. Never throws.
]]
function CommandAPI:Execute(command: any)
	local ok, errors, warnings, action = self:ValidateCommand(command)
	local actionName = if typeof(command) == "table" and typeof(command.Action) == "string" then command.Action else "Unknown"
	if not ok then
		return failure(actionName, table.concat(errors, "\n"), { Errors = errors, Warnings = warnings })
	end
	local runOk, result = pcall(function()
		if actionName == "Batch" then
			return self:_RunBatch(command)
		elseif action.Section then
			return self:_RunSection(action, command)
		end
		return action.Handler(self.Engine, command)
	end)
	if not runOk then
		result = failure(actionName, "internal error: " .. tostring(result))
	end
	result = normalizeResult(result, actionName)
	for _, warning in ipairs(warnings) do
		table.insert(result.Warnings, warning)
	end
	if command.Id ~= nil then
		result.Id = command.Id
	end
	table.insert(self.History, { Action = actionName, Success = result.Success, Time = os.clock() })
	if #self.History > self.HistoryLimit then
		table.remove(self.History, 1)
	end
	return result
end

return CommandAPI
