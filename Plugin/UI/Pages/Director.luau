--[[
	AI Director page:
	  Input -> Interpreted Configuration -> Changes -> Warnings -> Preview -> Apply
	The director is deterministic and runs locally; external AI agents can
	produce the same JSON input (or full configurations) and call the API.
]]
local Theme = require(script.Parent.Parent.Theme)

local EXAMPLE = [[{
  "Mood": "mysterious",
  "Time": "sunset",
  "Weather": "light_rain",
  "Environment": "dense_forest",
  "Fog": "medium",
  "LightingStyle": "cinematic"
}]]

return function(context)
	local ui, controller, engine = context.UI, context.Controller, context.Engine
	local Serialization = require(context.Library.Core.Serialization)
	local frame = ui:Stack(Theme.Spacing.Medium)
	local page = { Name = "AI Director", Frame = frame }
	local interpreted = nil

	local inputSection = ui:Section("1. Input (JSON description)", { LayoutOrder = 1 })
	inputSection.Frame.Parent = frame
	local input = ui:CodeBox(EXAMPLE, { Height = 150 })
	input.Instance.Parent = inputSection.Content
	local vocabulary = engine.Director:Vocabulary()
	ui:Label(
		"Mood: " .. table.concat(vocabulary.Mood, ", ") .. "\nEnvironment: " .. table.concat(vocabulary.Environment, ", ") .. "\nLightingStyle: " .. table.concat(vocabulary.LightingStyle, ", ") .. "\nWaterStyle: " .. table.concat(vocabulary.WaterStyle, ", "),
		{ Dim = true, TextSize = Theme.TextSize.Small, LayoutOrder = 2 }
	).Parent = inputSection.Content

	local configSection = ui:Section("2. Interpreted configuration", { LayoutOrder = 2 })
	configSection.Frame.Parent = frame
	local configView = ui:CodeBox("", { Height = 180, Editable = false })
	configView.Instance.Parent = configSection.Content

	local changesSection = ui:Section("3. Changes and warnings", { LayoutOrder = 3 })
	changesSection.Frame.Parent = frame
	local changes = ui:Stack(2)
	changes.Parent = changesSection.Content

	local function showLines(lines)
		for _, child in ipairs(changes:GetChildren()) do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		for index, line in ipairs(lines) do
			ui:Message(line[1], line[2], index).Parent = changes
		end
	end

	local function interpret()
		local ok, description = pcall(function()
			return Serialization:FromJSON(input:Get())
		end)
		if not ok or typeof(description) ~= "table" then
			showLines({ { "Input is not valid JSON: " .. tostring(description), "Error" } })
			return nil
		end
		interpreted = engine.Director:Interpret(description)
		configView:Set(Serialization:Export(interpreted.Configuration))
		local diff = engine:DiffScene(interpreted.Configuration)
		local lines = {}
		for _, line in ipairs(interpreted.Interpretation) do
			table.insert(lines, { line, "Info" })
		end
		for _, line in ipairs(diff.Summary) do
			table.insert(lines, { line, if string.sub(line, 1, 1) == "!" then "Warning" else "Info" })
		end
		for _, warning in ipairs(interpreted.Warnings) do
			table.insert(lines, { warning, "Warning" })
		end
		for _, problem in ipairs(diff.Errors or {}) do
			table.insert(lines, { problem, "Error" })
		end
		showLines(lines)
		return interpreted
	end

	local actions = ui:Section("4. Preview / Apply", { LayoutOrder = 4 })
	actions.Frame.Parent = frame
	ui:ButtonBar({
		ui:Button("Interpret", interpret),
		ui:Button("Preview", function()
			local result = interpret()
			if result then
				controller:PreviewScene(result.Configuration)
			end
		end),
		ui:Button("Apply", function()
			if not engine:IsPreviewing() then
				local result = interpret()
				if result then
					controller:PreviewScene(result.Configuration)
				end
			end
			controller:Apply()
		end, { Style = "Primary" }),
		ui:Button("Revert", function()
			controller:Revert()
		end, { Style = "Danger" }),
	}).Parent = actions.Content

	function page:Refresh() end

	return page
end
