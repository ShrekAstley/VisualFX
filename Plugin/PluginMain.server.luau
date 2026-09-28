--[[
	VisualFX Studio plugin entry point.

	The plugin bundles the VisualFX runtime library (script.Parent.VisualFX)
	and drives it through the same command API AI agents use. The runtime
	library never depends on the plugin; "Install runtime package" copies it
	into ReplicatedStorage for use in published games.

	While the plugin is loaded it publishes a small bridge on _G for code
	that shares the plugin's global table (other plugin scripts, and tooling
	that runs in the same context):
	  _G.VisualFXStudio.Execute({ Action = "InspectScene" })
	If _G is not shared with your context, require the runtime package
	(ReplicatedStorage.VisualFX) instead; it exposes the same Execute API.
]]

if not plugin then
	return
end

local root = script.Parent
local modules = root:WaitForChild("PluginModules")
local library = root:WaitForChild("VisualFX")

local VisualFX = require(library)
local Toolbar = require(modules.Toolbar)
local DockWidget = require(modules.DockWidget)
local PluginController = require(modules.Controllers.PluginController)
local App = require(modules.UI.App)

-- Edit-mode engine: transitions run on Heartbeat; runtime controllers
-- (camera-following weather, day/night) stay off unless enabled in Settings.
local engine = VisualFX.new({ AutoStart = true, RuntimeControllers = false, CameraEffects = false })
local controller = PluginController.new(plugin, engine, library)

local toolbar = Toolbar.create(plugin)
local widget = DockWidget.create(plugin)
local app = nil

local function ensureApp()
	if not app then
		app = App.new(widget, controller, library)
	end
end

toolbar.Button:SetActive(widget.Enabled)
if widget.Enabled then
	ensureApp()
end

toolbar.Button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toolbar.Button:SetActive(widget.Enabled)
	if widget.Enabled then
		ensureApp()
	end
end)

-- Agent bridge for Studio automation (code sharing this plugin's _G).
_G.VisualFXStudio = {
	Version = engine.Version,
	Engine = engine,
	Execute = function(command)
		return controller:Execute(command)
	end,
	Apply = function()
		return controller:Apply()
	end,
	Revert = function()
		return controller:Revert()
	end,
}

plugin.Unloading:Connect(function()
	if app then
		app:Destroy()
	end
	controller:Destroy()
	engine:Destroy()
	if _G.VisualFXStudio and _G.VisualFXStudio.Engine == engine then
		_G.VisualFXStudio = nil
	end
end)
