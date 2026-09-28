-- Transitions page: smoothly move the scene to a preset with configurable easing.
local Theme = require(script.Parent.Parent.Theme)

return function(context)
	local ui, controller, engine = context.UI, context.Controller, context.Engine
	local frame = ui:Stack(Theme.Spacing.Medium)
	local page = { Name = "Transitions", Frame = frame }

	local presetNames = {}
	for _, preset in ipairs(engine:ListPresets()) do
		table.insert(presetNames, preset.Name)
	end
	local state = { Preset = presetNames[1], Duration = 5, Easing = "Smooth", Direction = "InOut" }

	local section = ui:Section("Transition to preset", { LayoutOrder = 1 })
	section.Frame.Parent = frame
	ui:Row("Target preset", ui:Dropdown(presetNames, state.Preset, function(choice)
		state.Preset = choice
	end).Instance, { LayoutOrder = 1 }).Parent = section.Content
	ui:Row("Duration (s)", ui:Slider(state.Duration, 0, 30, function(value)
		state.Duration = value
	end).Instance, { LayoutOrder = 2 }).Parent = section.Content
	local easingStyles = require(context.Library.Runtime.Transitions).EasingStyles
	ui:Row("Easing", ui:Dropdown(easingStyles, state.Easing, function(choice)
		state.Easing = choice
	end).Instance, { LayoutOrder = 3 }).Parent = section.Content
	ui:Row("Direction", ui:Dropdown({ "In", "Out", "InOut" }, state.Direction, function(choice)
		state.Direction = choice
	end).Instance, { LayoutOrder = 4 }).Parent = section.Content

	local progress = ui:Label("Idle", { Dim = true, LayoutOrder = 6 })
	ui:ButtonBar({
		ui:Button("Start", function()
			controller:Edit({}, { Force = true }) -- open a preview session so the transition can be reverted
			controller:Execute({
				Action = "TransitionScene",
				Preset = state.Preset,
				Duration = state.Duration,
				Easing = state.Easing,
				EasingDirection = state.Direction,
			})
		end, { Style = "Primary" }),
		ui:Button("Finish now", function()
			engine:CancelTransition(true)
		end),
		ui:Button("Stop", function()
			engine:CancelTransition(false)
		end, { Style = "Danger" }),
	}, 5).Parent = section.Content
	progress.Parent = section.Content

	ui:Label(
		"Transitions run in edit mode and are journaled like any preview: use Apply to keep the result or Revert to go back.",
		{ Dim = true, LayoutOrder = 2, TextSize = Theme.TextSize.Small }
	).Parent = frame

	function page:Refresh()
		local active = engine.Transitions:GetActive()
		progress.Text = if active
			then string.format("Transitioning… %d%%", math.floor(active.Progress * 100 + 0.5))
			else "Idle"
	end

	-- Progress updates while a transition is running.
	page.Tick = function()
		if engine:IsTransitioning() then
			page:Refresh()
		end
	end

	return page
end
