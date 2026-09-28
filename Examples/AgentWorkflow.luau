--[[
	Example: the complete AI-agent workflow, programmatically.

	  Inspect -> understand -> build a configuration -> validate -> detect
	  conflicts -> preview the diff -> apply -> transition -> inspect ->
	  optimize -> export -> generate Luau

	Usage (e.g. from a Script or the Command Bar):
	  local report = require(path.To.AgentWorkflow)(require(game.ReplicatedStorage.VisualFX))

	Returns a report table describing every step. Pass `step` to advance time
	yourself (e.g. in tests); otherwise the transition runs on Heartbeat.
]]

return function(VisualFX, step: ((number) -> ())?)
	local report = { Steps = {} }
	local function record(name, result)
		table.insert(report.Steps, {
			Step = name,
			Success = result.Success ~= false,
			Created = result.Created,
			Modified = result.Modified,
			Removed = result.Removed,
			Warnings = result.Warnings,
			Errors = result.Errors,
		})
		return result
	end

	-- 1. Inspect and understand the current visual state.
	local scene = record("InspectScene", VisualFX:Execute({ Action = "InspectScene" }))
	report.Before = scene.Data.Summary

	-- 2. Build a structured configuration from a description (dry run = no changes).
	local description = {
		Mood = "mysterious",
		Time = "sunset",
		Weather = "light_rain",
		Environment = "dense_forest",
		Fog = "medium",
		LightingStyle = "cinematic",
	}
	local planned = record("CreateScene (dry run)", VisualFX:Execute({
		Action = "CreateScene",
		Configuration = description,
		DryRun = true,
	}))
	report.Diff = planned.Diff and planned.Diff.Summary
	local configuration = planned.Configuration

	-- 3. Validate and detect conflicts.
	local validation = record("ValidateConfiguration", VisualFX:Execute({
		Action = "ValidateConfiguration",
		Configuration = configuration,
	}))
	if not validation.Success then
		report.Aborted = "validation failed"
		return report
	end
	report.Conflicts = record("DetectConflicts", VisualFX:Execute({ Action = "DetectConflicts" })).Data

	-- 4. Preview, then apply.
	record("PreviewScene", VisualFX:Execute({ Action = "PreviewScene", Configuration = configuration, Replace = true }))
	record("CommitPreview", VisualFX:Execute({ Action = "CommitPreview" }))

	-- 5. Transition to heavier weather at dusk.
	record("TransitionScene", VisualFX:Execute({
		Action = "TransitionScene",
		Duration = 5,
		Configuration = {
			Weather = { Type = "HeavyRain", Intensity = 0.9 },
			Lighting = { ClockTime = 19.2 },
		},
	}))
	if step then
		for _ = 1, 60 do
			step(0.1)
		end
	end

	-- 6. Inspect the result and optimize.
	report.After = record("InspectScene", VisualFX:Execute({ Action = "InspectScene" })).Data.Summary
	local stats = VisualFX:Execute({ Action = "GetPerformanceStats" }).Data
	if stats.EstimatedParticleRate > 3000 then
		record("SetQuality", VisualFX:Execute({ Action = "SetQuality", Level = "Medium" }))
	end
	report.Stats = VisualFX:Execute({ Action = "GetPerformanceStats" }).Data

	-- 7. Export and generate reusable Luau.
	report.Json = record("ExportConfiguration", VisualFX:Execute({ Action = "ExportConfiguration", Format = "json" })).Data
	report.Code = record("GenerateCode", VisualFX:Execute({ Action = "GenerateCode", Options = { Template = "LocalScript" } })).Code

	report.Success = true
	for _, entry in ipairs(report.Steps) do
		if not entry.Success then
			report.Success = false
		end
	end
	return report
end
