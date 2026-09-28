-- Weather page: pick a weather type and tune intensity, wind, fog and lightning.
local Theme = require(script.Parent.Parent.Theme)

return function(context)
	local ui, controller, engine = context.UI, context.Controller, context.Engine
	local frame = ui:Stack(Theme.Spacing.Medium)
	local page = { Name = "Weather", Frame = frame }

	local state = { Type = "Clear", Intensity = 0.6, Wind = 10, Fog = 0.2, Lightning = false }

	local section = ui:Section("Weather", { LayoutOrder = 1 })
	section.Frame.Parent = frame
	local function preview()
		controller:Edit({ Weather = {
			Type = state.Type,
			Intensity = state.Intensity,
			Wind = state.Wind,
			Fog = state.Fog,
			Lightning = state.Lightning,
		} })
	end

	local typeDropdown = ui:Dropdown(engine.Registry:ListWeather(), state.Type, function(choice)
		state.Type = choice
		local definition = engine.Registry.WeatherTypes[choice]
		if definition and definition.Defaults then
			state.Intensity = definition.Defaults.Intensity or state.Intensity
			state.Wind = definition.Defaults.Wind or state.Wind
			state.Fog = definition.Defaults.Fog or state.Fog
			state.Lightning = definition.Defaults.Lightning == true
		end
		page:Refresh(true)
		preview()
	end)
	ui:Row("Type", typeDropdown.Instance, { LayoutOrder = 1 }).Parent = section.Content

	local intensity = ui:Slider(state.Intensity, 0, 1, function(value, final)
		state.Intensity = value
		if final then
			preview()
		end
	end)
	ui:Row("Intensity", intensity.Instance, { LayoutOrder = 2 }).Parent = section.Content
	local wind = ui:Slider(state.Wind, 0, 80, function(value, final)
		state.Wind = value
		if final then
			preview()
		end
	end)
	ui:Row("Wind (studs/s)", wind.Instance, { LayoutOrder = 3 }).Parent = section.Content
	local fog = ui:Slider(state.Fog, 0, 1, function(value, final)
		state.Fog = value
		if final then
			preview()
		end
	end)
	ui:Row("Fog", fog.Instance, { LayoutOrder = 4 }).Parent = section.Content
	local lightning = ui:Toggle(state.Lightning, function(value)
		state.Lightning = value
		preview()
	end)
	ui:Row("Lightning", lightning.Instance, { LayoutOrder = 5 }).Parent = section.Content

	local description = ui:Label("", { Dim = true, LayoutOrder = 6, TextSize = Theme.TextSize.Small })
	description.Parent = section.Content
	ui:ButtonBar({
		ui:Button("Remove weather", function()
			controller:Edit({ Weather = "$remove" })
		end, { Style = "Danger" }),
	}, 7).Parent = section.Content

	function page:Refresh(fromUser: boolean?)
		if not fromUser then
			local current = engine:GetConfiguration().Weather
			if current then
				state.Type = current.Type or state.Type
				state.Intensity = current.Intensity or state.Intensity
				state.Wind = current.Wind or state.Wind
				state.Fog = current.Fog or state.Fog
				if current.Lightning ~= nil then
					state.Lightning = current.Lightning
				end
			end
		end
		typeDropdown:Set(state.Type)
		intensity:Set(state.Intensity)
		wind:Set(state.Wind)
		fog:Set(state.Fog)
		lightning:Set(state.Lightning)
		local definition = engine.Registry.WeatherTypes[state.Type]
		if definition then
			local composition = require(context.Library.Runtime.Weather).DescribeComposition(definition)
			description.Text = (definition.Description or "") .. "\nComposed of: " .. table.concat(composition, ", ")
		end
	end

	return page
end
