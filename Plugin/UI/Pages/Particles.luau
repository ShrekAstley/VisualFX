-- Particles page: named particle systems built from templates.
local Theme = require(script.Parent.Parent.Theme)
local PropertyEditor = require(script.Parent.Parent.PropertyEditor)

return function(context)
	local ui, controller, engine = context.UI, context.Controller, context.Engine
	local frame = ui:Stack(Theme.Spacing.Medium)
	local page = { Name = "Particles", Frame = frame }
	local selected = nil
	local editor = nil

	local addSection = ui:Section("Add particle system", { LayoutOrder = 1 })
	addSection.Frame.Parent = frame
	local templates = engine.Registry:ListParticleTemplates()
	local templateChoice = "Rain"
	local nameInput = ui:TextInput("", nil, { Placeholder = "System name (defaults to the template)" })
	local templateDropdown = ui:Dropdown(templates, templateChoice, function(choice)
		templateChoice = choice
	end)
	ui:Row("Template", templateDropdown.Instance, { LayoutOrder = 1 }).Parent = addSection.Content
	ui:Row("Name", nameInput.Instance, { LayoutOrder = 2 }).Parent = addSection.Content
	local templateInfo = ui:Label("", { Dim = true, LayoutOrder = 3, TextSize = Theme.TextSize.Small })
	templateInfo.Parent = addSection.Content
	ui:ButtonBar({
		ui:Button("Add", function()
			local name = nameInput:Get()
			if name == "" then
				name = templateChoice
			end
			local result = controller:Edit({ Particles = { [name] = { Template = templateChoice } } })
			if result.Success then
				selected = name
				page:Refresh()
			end
		end, { Style = "Primary" }),
	}, 4).Parent = addSection.Content

	local listSection = ui:Section("Particle systems", { LayoutOrder = 2 })
	listSection.Frame.Parent = frame
	local list = ui:Stack(2)
	list.Parent = listSection.Content

	local editorHolder = ui:Stack(0, 3)
	editorHolder.Parent = frame

	local function rebuildEditor()
		if editor then
			editor.Frame:Destroy()
			editor = nil
		end
		if not selected then
			return
		end
		local fields = engine.Registry:GetSection("Particles").ItemFields
		editor = PropertyEditor.new(ui, controller, { "Particles", selected }, fields, {
			Title = "Edit: " .. selected,
			Live = function()
				return engine.Particles:Get(selected)
			end,
		})
		editor.Frame.Parent = editorHolder
	end

	function page:Refresh()
		local template = engine.Registry:GetParticleTemplate(templateChoice)
		templateInfo.Text = template and template.Description or ""
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("Frame") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local names = engine.Particles:List()
		if #names == 0 then
			ui:Label("No particle systems. Weather and zones manage their own particles.", { Dim = true }).Parent = list
		end
		if selected and not table.find(names, selected) then
			selected = nil
		end
		for index, name in ipairs(names) do
			local config = engine.Particles:GetConfiguration(name) or {}
			local row = ui:Create("Frame", {
				BackgroundColor3 = if name == selected then ui.Palette.Selected else ui.Palette.PanelAlt,
				Size = UDim2.new(1, 0, 0, Theme.RowHeight),
				LayoutOrder = index,
			}, { ui:Corner(3), ui:Padding(0, 6), ui:HorizontalList(6) })
			local label = ui:Label(string.format("%s  (%s)", name, config.Template or name), { Size = UDim2.new(1, -140, 1, 0), Wrap = false })
			label.LayoutOrder = 1
			label.Parent = row
			ui:Button("Edit", function()
				selected = name
				page:Refresh()
			end, { LayoutOrder = 2 }).Parent = row
			ui:Button("Remove", function()
				controller:Edit({ Particles = { [name] = "$remove" } })
				if selected == name then
					selected = nil
				end
				page:Refresh()
			end, { Style = "Danger", LayoutOrder = 3 }).Parent = row
			row.Parent = list
		end
		local wanted = selected
		if not editor or not wanted or not string.find(editor.Section.Title, wanted, 1, true) then
			rebuildEditor()
		elseif editor then
			editor:Refresh()
		end
	end

	return page
end
