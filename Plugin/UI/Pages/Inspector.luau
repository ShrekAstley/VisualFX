-- Inspector page: structured scene inspection, classifications and conflicts.
local Theme = require(script.Parent.Parent.Theme)

return function(context)
	local ui, controller, engine = context.UI, context.Controller, context.Engine
	local frame = ui:Stack(Theme.Spacing.Medium)
	local page = { Name = "Inspector", Frame = frame }

	ui:ButtonBar({
		ui:Button("Refresh", function()
			page:Refresh(true)
		end, { Style = "Primary" }),
	}, 0).Parent = frame

	local summarySection = ui:Section("Summary", { LayoutOrder = 1 })
	summarySection.Frame.Parent = frame
	local conflictsSection = ui:Section("Conflicts", { LayoutOrder = 2 })
	conflictsSection.Frame.Parent = frame
	local objectsSection = ui:Section("Visual objects", { LayoutOrder = 3 })
	objectsSection.Frame.Parent = frame
	local managedSection = ui:Section("Managed effects", { LayoutOrder = 4, Collapsed = true })
	managedSection.Frame.Parent = frame

	local function clear(section)
		for _, child in ipairs(section.Content:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function objectRow(entry, index)
		local row = ui:Create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, Theme.RowHeight),
			LayoutOrder = index,
		}, { ui:HorizontalList(6) })
		local severity = ({ Managed = "Success", Adopted = "Info", RobloxDefault = "Info", Developer = "Warning", Unknown = "Error" })[entry.Classification] or "Info"
		ui:Badge(entry.Classification, severity, 1).Parent = row
		local label = ui:Label(entry.Path, { Wrap = false, Size = UDim2.new(1, -170, 1, 0) })
		label.LayoutOrder = 2
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = row
		ui:Button("Select", function()
			controller:Select(entry.Path)
		end, { Style = "Ghost", LayoutOrder = 3 }).Parent = row
		return row
	end

	function page:Refresh(force: boolean?)
		if not force and not frame.Parent then
			return
		end
		local scene = engine:InspectScene({ MaxParticles = 100 })
		clear(summarySection)
		for index, line in ipairs(scene.Summary) do
			ui:Label(line, { LayoutOrder = index }).Parent = summarySection.Content
		end

		clear(conflictsSection)
		if #scene.Conflicts == 0 then
			ui:Message("No conflicts", "Success").Parent = conflictsSection.Content
		end
		for index, conflict in ipairs(scene.Conflicts) do
			local block = ui:Stack(1, index)
			ui:Message(conflict.Message, conflict.Severity, 1).Parent = block
			if conflict.Suggestion then
				ui:Label("   " .. conflict.Suggestion, { Dim = true, TextSize = Theme.TextSize.Small, LayoutOrder = 2 }).Parent = block
			end
			block.Parent = conflictsSection.Content
		end

		clear(objectsSection)
		local index = 0
		for _, group in ipairs({ scene.Atmosphere, scene.Sky, scene.Clouds, scene.PostProcessing, scene.Particles.Managed, scene.Particles.Developer }) do
			for _, entry in ipairs(group) do
				index += 1
				objectRow(entry, index).Parent = objectsSection.Content
			end
		end
		for _, entry in ipairs(scene.Unknown) do
			index += 1
			objectRow({ Classification = "Unknown", Path = entry.Path }, index).Parent = objectsSection.Content
		end
		if index == 0 then
			ui:Label("No visual objects found.", { Dim = true }).Parent = objectsSection.Content
		end

		clear(managedSection)
		for position, effect in ipairs(scene.ManagedEffects) do
			ui:Label(string.format("%s  [%s]  %s", effect.ID, effect.Type, effect.Path), { TextSize = Theme.TextSize.Small, LayoutOrder = position }).Parent = managedSection.Content
		end
	end

	return page
end
