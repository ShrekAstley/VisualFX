-- Presets page: searchable preset cards, apply/preview, save and delete user presets.
local Theme = require(script.Parent.Parent.Theme)

return function(context)
	local ui, controller, engine = context.UI, context.Controller, context.Engine
	local frame = ui:Stack(Theme.Spacing.Medium)
	local page = { Name = "Presets", Frame = frame }
	local search = ""

	local saveSection = ui:Section("Save current scene as preset", { LayoutOrder = 1, Collapsed = true })
	saveSection.Frame.Parent = frame
	local nameInput = ui:TextInput("", nil, { Placeholder = "PresetName (letters, digits, _ and -)" })
	ui:Row("Name", nameInput.Instance, { LayoutOrder = 1 }).Parent = saveSection.Content
	local saveMessage = ui:Label("", { Dim = true, LayoutOrder = 3, TextSize = Theme.TextSize.Small })
	ui:ButtonBar({
		ui:Button("Save", function()
			local result = controller:Execute({ Action = "SavePreset", Name = nameInput:Get(), Overwrite = true })
			saveMessage.Text = if result.Success then "Saved " .. nameInput:Get() else table.concat(result.Errors, "\n")
			page:Refresh()
		end, { Style = "Primary" }),
	}, 2).Parent = saveSection.Content
	saveMessage.Parent = saveSection.Content

	local searchInput = ui:TextInput("", function(text)
		search = text
		page:Refresh()
	end, { Placeholder = "Filter presets (name, category, tag)…", LayoutOrder = 2 })
	searchInput.Instance.Parent = frame

	local grid = ui:Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
	}, {
		ui:Create("UIGridLayout", {
			CellSize = UDim2.new(0.5, -4, 0, 112),
			CellPadding = UDim2.new(0, 6, 0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	grid.Parent = frame

	local function card(preset, index)
		local current = engine:GetConfiguration().Metadata
		local active = current and current.Name == preset.DisplayName
		local body = ui:Create("Frame", {
			BackgroundColor3 = if active then ui.Palette.Selected else ui.Palette.Panel,
			LayoutOrder = index,
		}, { ui:Corner(6), ui:Padding(6), ui:VerticalList(2) })
		ui:Label(preset.DisplayName, { Font = Theme.Fonts.Strong, Wrap = false, LayoutOrder = 1 }).Parent = body
		ui:Label(preset.Category .. (if preset.Source ~= "BuiltIn" then "  •  " .. preset.Source else ""), { Dim = true, TextSize = Theme.TextSize.Small, LayoutOrder = 2 }).Parent = body
		local description = ui:Label(preset.Description, { Dim = true, TextSize = Theme.TextSize.Small, LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 30) })
		description.TextTruncate = Enum.TextTruncate.AtEnd
		description.Parent = body
		local buttons = {
			ui:Button("Preview", function()
				local config = engine:GetPreset(preset.Name)
				if config then
					controller:PreviewScene(config)
				end
			end),
			ui:Button("Apply", function()
				controller:ApplyNow({ Action = "ApplyPreset", Name = preset.Name })
			end, { Style = "Primary" }),
		}
		if preset.Source ~= "BuiltIn" then
			table.insert(buttons, ui:Button("✕", function()
				controller:Execute({ Action = "DeletePreset", Name = preset.Name })
				page:Refresh()
			end, { Style = "Danger" }))
		end
		ui:ButtonBar(buttons, 4).Parent = body
		return body
	end

	function page:Refresh()
		for _, child in ipairs(grid:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for index, preset in ipairs(engine:ListPresets({ Search = search })) do
			card(preset, index).Parent = grid
		end
	end

	return page
end
