-- Settings page: plugin behaviour, quality, runtime packaging and engine compatibility.
local Theme = require(script.Parent.Parent.Theme)

return function(context)
	local ui, controller, engine = context.UI, context.Controller, context.Engine
	local frame = ui:Stack(Theme.Spacing.Medium)
	local page = { Name = "Settings", Frame = frame }

	local behaviour = ui:Section("Editing", { LayoutOrder = 1 })
	behaviour.Frame.Parent = frame
	local live = ui:Toggle(controller.Settings.LivePreview, function(value)
		controller:SetSetting("LivePreview", value)
	end)
	ui:Row("Live preview", live.Instance, { LayoutOrder = 1 }).Parent = behaviour.Content
	local adopt = ui:Toggle(controller.Settings.AdoptExisting, function(value)
		controller:SetSetting("AdoptExisting", value)
	end)
	ui:Row("Adopt existing effects", adopt.Instance, { LayoutOrder = 2 }).Parent = behaviour.Content
	local runtime = ui:Toggle(controller.Settings.RuntimePreview, function(value)
		controller:SetSetting("RuntimePreview", value)
	end)
	ui:Row("Run runtime controllers in edit mode", runtime.Instance, { LayoutOrder = 3 }).Parent = behaviour.Content
	ui:Label(
		"Runtime controllers (camera-following weather, lightning, day/night, zone culling) normally run only in play mode. Enabling them in edit mode moves managed emitter volumes with the edit camera.",
		{ Dim = true, TextSize = Theme.TextSize.Small, LayoutOrder = 4 }
	).Parent = behaviour.Content

	local quality = ui:Section("Quality", { LayoutOrder = 2 })
	quality.Frame.Parent = frame
	local qualityDropdown = ui:Dropdown({ "Low", "Medium", "High", "Ultra" }, engine.Quality.Level, function(choice)
		controller:Edit({ Quality = { Level = choice } })
	end)
	ui:Row("Level", qualityDropdown.Instance, { LayoutOrder = 1 }).Parent = quality.Content
	local statsLabel = ui:Label("", { Dim = true, TextSize = Theme.TextSize.Small, LayoutOrder = 2 })
	statsLabel.Parent = quality.Content

	local packaging = ui:Section("Runtime package", { LayoutOrder = 3 })
	packaging.Frame.Parent = frame
	local packageLabel = ui:Label("", { LayoutOrder = 1 })
	packageLabel.Parent = packaging.Content
	local packageMessage = ui:Label("", { Dim = true, TextSize = Theme.TextSize.Small, LayoutOrder = 3 })
	ui:ButtonBar({
		ui:Button("Install / update in ReplicatedStorage", function()
			local result = controller:InstallRuntimePackage()
			packageMessage.Text = result.Message or ""
			page:Refresh()
		end, { Style = "Primary" }),
	}, 2).Parent = packaging.Content
	packageMessage.Parent = packaging.Content
	ui:Label(
		"Workflow: configure the scene -> export configuration or code -> install the runtime package -> require(game.ReplicatedStorage.VisualFX) in your game. The runtime does not need this plugin. Saved presets are included as ModuleScripts in VisualFX.Presets.User.",
		{ Dim = true, TextSize = Theme.TextSize.Small, LayoutOrder = 4 }
	).Parent = packaging.Content

	local compatibility = ui:Section("Engine compatibility", { LayoutOrder = 4, Collapsed = true })
	compatibility.Frame.Parent = frame
	local compatibilityList = ui:Stack(1)
	compatibilityList.Parent = compatibility.Content

	function page:Refresh()
		live:Set(controller.Settings.LivePreview)
		adopt:Set(controller.Settings.AdoptExisting)
		runtime:Set(controller.Settings.RuntimePreview)
		qualityDropdown:Set(engine.Quality.Level)
		local profile = engine.Quality:GetProfile()
		statsLabel.Text = string.format(
			"Particle rate scale %.2f • max %d particles/s • max %d systems • updates %d Hz • activation distance %d studs",
			profile.ParticleRateScale,
			profile.MaxParticleRate,
			profile.MaxParticleSystems,
			profile.UpdateFrequency,
			profile.ActivationDistance
		)
		local installed = controller:GetInstalledPackageVersion()
		packageLabel.Text = if installed
			then string.format("Installed version: %s (plugin: %s)", installed, engine.Version)
			else "Not installed in this place"
		for _, child in ipairs(compatibilityList:GetChildren()) do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local report = engine:GetCompatibilityReport()
		ui:Message(string.format("%d supported properties", #report.Supported), "Success", 0).Parent = compatibilityList
		for index, entry in ipairs(report.Unsupported) do
			ui:Message(entry.Path .. ": " .. tostring(entry.Reason), "Warning", index).Parent = compatibilityList
		end
	end

	return page
end
