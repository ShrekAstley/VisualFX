-- Overview: scene status at a glance and quick actions.
local Theme = require(script.Parent.Parent.Theme)

return function(context)
	local ui, controller, engine = context.UI, context.Controller, context.Engine
	local frame = ui:Stack(Theme.Spacing.Medium)
	local page = { Name = "Overview", Frame = frame }

	local status = ui:Section("Scene status", { LayoutOrder = 1 })
	status.Frame.Parent = frame
	local lines = ui:Stack(2)
	lines.Parent = status.Content

	local actions = ui:Section("Quick actions", { LayoutOrder = 2 })
	actions.Frame.Parent = frame
	local confirmReset = false
	local resetButton
	resetButton = ui:Button("Reset managed effects", function()
		if not confirmReset then
			confirmReset = true
			resetButton.Text = "Click again to confirm reset"
			return
		end
		confirmReset = false
		resetButton.Text = "Reset managed effects"
		controller:ResetManagedEffects()
	end, { Style = "Danger" })
	ui:ButtonBar({
		ui:Button("Inspect scene", function()
			context.Navigate("Inspector")
		end),
		ui:Button("Browse presets", function()
			context.Navigate("Presets")
		end),
		ui:Button("AI Director", function()
			context.Navigate("AI Director")
		end),
		resetButton,
	}).Parent = actions.Content

	local about = ui:Section("About", { LayoutOrder = 3, Collapsed = true })
	about.Frame.Parent = frame
	ui:Label(
		"VisualFX builds scenes from validated configuration data. Edits are previewed non-destructively: use Apply to keep them (one undo step) or Revert to restore the scene exactly. AI agents use the same API through VisualFX:Execute.",
		{ Dim = true }
	).Parent = about.Content

	function page:Refresh()
		for _, child in ipairs(lines:GetChildren()) do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local stats = engine:GetPerformanceStats()
		local conflicts = engine:DetectConflicts()
		local weather = engine:GetWeather()
		local config = engine:GetConfiguration()
		local entries = {
			string.format("Scene: %s", config.Metadata and config.Metadata.Name or "(unsaved)"),
			string.format("Weather: %s", if weather.Active then string.format("%s (%.2f)", weather.Type, weather.Intensity) else "none"),
			string.format("Quality: %s — %d particle systems, ~%d particles/s", stats.Quality, stats.ActiveParticleSystems, stats.EstimatedParticleRate),
			string.format("Managed instances: %d", stats.ManagedInstances),
			string.format("Preview: %s", if engine:IsPreviewing() then "active (Apply or Revert)" else "none"),
		}
		for index, text in ipairs(entries) do
			ui:Label(text, { LayoutOrder = index }).Parent = lines
		end
		local severity = "Success"
		for _, conflict in ipairs(conflicts) do
			if conflict.Severity == "Error" then
				severity = "Error"
			elseif conflict.Severity == "Warning" and severity ~= "Error" then
				severity = "Warning"
			end
		end
		ui:Message(
			if #conflicts == 0 then "No conflicts detected" else string.format("%d conflict(s) — see Inspector", #conflicts),
			severity,
			#entries + 1
		).Parent = lines
	end

	return page
end
