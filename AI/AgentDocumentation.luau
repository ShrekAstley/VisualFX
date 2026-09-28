--[[
	VisualFX.AI.AgentDocumentation

	The agent guide, available at runtime so an agent that can only call
	Luau (for example through a Studio MCP bridge) can discover how to use
	VisualFX without reading files:

	  local guide = VisualFX:GetDocumentation()
	  print(guide.Markdown)
]]

local Root = script.Parent.Parent
local Util = require(Root.Core.Util)

local AgentDocumentation = {}

AgentDocumentation.Workflow = {
	{ Step = "Inspect", Command = { Action = "InspectScene" }, Why = "Learn what exists: managed effects, developer effects, conflicts, quality." },
	{ Step = "Describe or configure", Command = { Action = "ValidateConfiguration", Configuration = { Weather = { Type = "LightRain" } } }, Why = "Build a configuration (or a description for the Visual Director) and validate it." },
	{ Step = "Detect conflicts", Command = { Action = "DetectConflicts" }, Why = "Duplicate atmospheres, stacked bloom, stale managed effects." },
	{ Step = "Preview the diff", Command = { Action = "DiffScene", Configuration = { Lighting = { ClockTime = 18 } }, Merge = true }, Why = "See exactly what will be created, modified and removed." },
	{ Step = "Apply", Command = { Action = "UpdateScene", Configuration = { Lighting = { ClockTime = 18 } } }, Why = "Apply; only differences are written; nothing is duplicated." },
	{ Step = "Transition", Command = { Action = "TransitionScene", Duration = 5, Configuration = { Weather = { Type = "HeavyRain", Intensity = 0.9 } } }, Why = "Smoothly move to a new state." },
	{ Step = "Inspect the result", Command = { Action = "InspectScene" }, Why = "Confirm the new state." },
	{ Step = "Optimize", Command = { Action = "SetQuality", Level = "Medium" }, Why = "Apply particle budgets and update frequencies." },
	{ Step = "Export", Command = { Action = "ExportConfiguration", Format = "json" }, Why = "Deterministic, diffable configuration." },
	{ Step = "Generate code", Command = { Action = "GenerateCode" }, Why = "Readable Luau that reproduces the scene in a published game." },
}

AgentDocumentation.Rules = {
	"Always InspectScene before changing a scene you did not create.",
	"Prefer UpdateScene (merge) for edits; CreateScene/ApplyPreset replace the managed scene.",
	"Never create instances manually for effects VisualFX manages; use commands so identity and duplicate prevention apply.",
	"Use DryRun = true or DiffScene for large changes and show the diff before applying.",
	"Treat Warnings as advice and Errors as blockers; fix Errors using the Path and Expected/Received fields.",
	"Use \"$remove\" in UpdateScene to delete a key or section; use RemoveParticleSystem/RemoveWeather/RemoveZone for effects.",
	"VisualFX never deletes developer-created or unknown instances; ResetManagedEffects only removes managed ones and restores originals.",
	"Configurations are data only. Never put code in a configuration; VisualFX will not execute it.",
	"Roblox values in JSON use tagged encodings ({\"$type\":\"Color3\",\"rgb\":[r,g,b]}) or shorthands (\"#RRGGBB\", [x,y,z]).",
	"Performance budgets are applied automatically; check GetPerformanceStats after large particle changes.",
}

AgentDocumentation.Topics = {
	InspectScene = "VisualFX:InspectScene() returns Lighting, Atmosphere, Sky, Clouds, PostProcessing, Water, Weather, Particles, Environment, ManagedEffects, Conflicts, Quality, Configuration, Unknown and Summary. Each instance has a Classification: Managed, Adopted, RobloxDefault, Developer or Unknown.",
	Modify = "Use Set* commands (merge) or UpdateScene. Section setters accept Replace = true to replace a whole section.",
	CreateEffects = "CreateParticleSystem (Template + overrides), CreateWeather (Type + Intensity/Wind/Fog/Lightning), CreateZone (Effect, Position, Size, Intensity), SetPostProcessing.",
	AvoidDuplicates = "Every managed instance has VisualFX_ID; applying the same configuration twice is a no-op. Existing Atmosphere/Sky/Clouds/Bloom/SunRays/DepthOfField are adopted rather than duplicated.",
	Validate = "ValidateConfiguration returns Errors (blocking) and Warnings with Path, Code and Message. Every mutating command validates automatically.",
	Presets = "ApplyPreset, SavePreset (Inherits supported for composition), DeletePreset, ListPresets, GetPreset.",
	GenerateCode = "GenerateCode returns Luau using a reusable configuration table and VisualFX:CreateScene. Options: Template = Script | LocalScript | Module | Transition.",
	Transitions = "TransitionScene with Duration, Easing and Configuration or Preset. New effects fade in, removed effects fade out.",
	Conflicts = "DetectConflicts reports multiple atmospheres/skies, stacked post effects, duplicate managed IDs, ignored fog, stale managed effects and developer particle load.",
	Optimize = "SetQuality(Low|Medium|High|Ultra|Custom). Budgets: ParticleRateScale, MaxParticleRate, MaxParticleSystems, UpdateFrequency, ActivationDistance, SpatialCulling.",
}

function AgentDocumentation.Build(engine)
	local catalog = engine.Commands:Catalog()
	local guide = {
		Version = engine.Version,
		ConfigVersion = engine.ConfigVersion,
		Workflow = Util.deepCopy(AgentDocumentation.Workflow),
		Rules = table.clone(AgentDocumentation.Rules),
		Topics = table.clone(AgentDocumentation.Topics),
		Actions = catalog,
		WeatherTypes = engine.Registry:ListWeather(),
		ParticleTemplates = engine.Registry:ListParticleTemplates(),
		Presets = {},
		DirectorVocabulary = engine.Director:Vocabulary(),
	}
	for _, preset in ipairs(engine:ListPresets()) do
		table.insert(guide.Presets, preset.Name)
	end
	guide.Markdown = AgentDocumentation.ToMarkdown(guide)
	return guide
end

function AgentDocumentation.ToMarkdown(guide): string
	local lines = {
		"# VisualFX Agent Guide (runtime)",
		"",
		"## Workflow",
	}
	for index, step in ipairs(guide.Workflow) do
		table.insert(lines, string.format("%d. **%s** — `%s`: %s", index, step.Step, step.Command.Action, step.Why))
	end
	table.insert(lines, "")
	table.insert(lines, "## Rules")
	for _, rule in ipairs(guide.Rules) do
		table.insert(lines, "- " .. rule)
	end
	table.insert(lines, "")
	table.insert(lines, "## Actions")
	for _, name in ipairs(Util.sortedKeys(guide.Actions)) do
		local action = guide.Actions[name]
		local fields = {}
		for _, fieldName in ipairs(Util.sortedKeys(action.Fields)) do
			local definition = action.Fields[fieldName]
			table.insert(fields, fieldName .. (if definition.Required then "*" else "") .. ": " .. definition.Kind)
		end
		table.insert(lines, string.format("- `%s` %s (%s)", name, action.Description, table.concat(fields, ", ")))
	end
	table.insert(lines, "")
	table.insert(lines, "Weather types: " .. table.concat(guide.WeatherTypes, ", "))
	table.insert(lines, "Particle templates: " .. table.concat(guide.ParticleTemplates, ", "))
	table.insert(lines, "Presets: " .. table.concat(guide.Presets, ", "))
	return table.concat(lines, "\n")
end

return AgentDocumentation
