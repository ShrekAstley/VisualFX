--[[
	Creates the dockable VisualFX widget. Uses CreateDockWidgetPluginGuiAsync
	when available and falls back to CreateDockWidgetPluginGui.
]]

local DockWidget = {}

DockWidget.ID = "VisualFXStudioWidget"

function DockWidget.create(plugin: Plugin)
	local info = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Right,
		false, -- initially enabled
		false, -- override previous enabled state
		460, -- floating width
		680, -- floating height
		360, -- minimum width
		420 -- minimum height
	)
	local widget
	local ok = pcall(function()
		widget = (plugin :: any):CreateDockWidgetPluginGuiAsync(DockWidget.ID, info)
	end)
	if not ok or not widget then
		widget = plugin:CreateDockWidgetPluginGui(DockWidget.ID, info)
	end
	widget.Title = "VisualFX Studio"
	widget.Name = "VisualFXStudio"
	pcall(function()
		widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	end)
	return widget
end

return DockWidget
