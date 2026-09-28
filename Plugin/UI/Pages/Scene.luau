--[[
	Scene: the current configuration as deterministic JSON. Validate, diff,
	preview and import edited JSON; export the current scene.
]]
local Theme = require(script.Parent.Parent.Theme)

return function(context)
	local ui, controller, engine = context.UI, context.Controller, context.Engine
	local frame = ui:Stack(Theme.Spacing.Medium)
	local page = { Name = "Scene", Frame = frame }

	local editorSection = ui:Section("Configuration (VisualFXConfig JSON)", { LayoutOrder = 1 })
	editorSection.Frame.Parent = frame
	local editor = ui:CodeBox("", { Height = 280, LayoutOrder = 1 })
	editor.Instance.Parent = editorSection.Content

	local output = ui:Stack(2, 3)
	local function show(lines: { { string } })
		for _, child in ipairs(output:GetChildren()) do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		for index, line in ipairs(lines) do
			ui:Message(line[1], line[2], index).Parent = output
		end
	end

	local function report(result, successText)
		local lines = {}
		if result.Success then
			table.insert(lines, { successText, "Success" })
		end
		for _, problem in ipairs(result.Errors or {}) do
			table.insert(lines, { problem, "Error" })
		end
		for _, warning in ipairs(result.Warnings or {}) do
			table.insert(lines, { warning, "Warning" })
		end
		show(lines)
	end

	ui:ButtonBar({
		ui:Button("Reload", function()
			page:Refresh(true)
		end),
		ui:Button("Validate", function()
			local config, _, problem = require(context.Library.Core.Serialization):Deserialize(editor:Get())
			if not config then
				show({ { problem or "invalid document", "Error" } })
				return
			end
			local validation = engine:Validate(config)
			local messages = {}
			for _, entry in ipairs(validation.Errors) do
				table.insert(messages, entry.Message)
			end
			local warnings = {}
			for _, entry in ipairs(validation.Warnings) do
				table.insert(warnings, entry.Message)
			end
			report({ Success = validation.Success, Errors = messages, Warnings = warnings }, "Configuration is valid")
		end),
		ui:Button("Diff", function()
			local diff = controller:Execute({ Action = "ImportConfiguration", Data = editor:Get(), DryRun = true })
			local lines = {}
			if diff.Diff then
				for _, line in ipairs(diff.Diff.Summary) do
					table.insert(lines, { line, if string.sub(line, 1, 1) == "!" then "Warning" else "Info" })
				end
			end
			for _, problem in ipairs(diff.Errors) do
				table.insert(lines, { problem, "Error" })
			end
			if #lines == 0 then
				table.insert(lines, { "No differences", "Success" })
			end
			show(lines)
		end),
		ui:Button("Preview", function()
			local config, _, problem = require(context.Library.Core.Serialization):Deserialize(editor:Get())
			if not config then
				show({ { problem or "invalid document", "Error" } })
				return
			end
			report(controller:PreviewScene(config), "Previewing — Apply or Revert in the status bar")
		end, { Style = "Primary" }),
	}, 2).Parent = editorSection.Content
	output.Parent = editorSection.Content

	function page:Refresh(force: boolean?)
		if force or not editor.TextBox:IsFocused() then
			editor:Set(engine:ExportConfiguration({ Format = "json" }))
		end
	end

	return page
end
