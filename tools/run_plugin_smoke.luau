--[[
	Headless smoke test of the VisualFX Studio plugin under the Roblox mock:
	loads the plugin tree from plugin.project.json, opens the widget, visits
	every page and exercises the main flows by firing UI events. Rendering is
	not simulated; this catches runtime errors in UI construction and wiring.

	  python3 tools/bundle.py plugin.project.json build/plugin_bundle.luau
	  luau tools/run_plugin_smoke.luau
]]

local Mock = require("./mock/Roblox")
local bundle = require("../build/plugin_bundle")

local world = Mock.createWorld()
local game = world.game
local root = Mock.mount(bundle, nil)
local pluginObject, settingsStore, opened = Mock.createPlugin()
local globals = { plugin = pluginObject }
local requireFn = Mock.makeRequire(world, globals)

local checks, failures = 0, {}
local function check(condition, message)
	checks += 1
	if not condition then
		table.insert(failures, message)
	end
end

Mock.runScript(world, root.PluginMain, requireFn, globals)

local bridge = world.env._G.VisualFXStudio
check(bridge ~= nil, "plugin exposes _G.VisualFXStudio")

-- Find the widget created by the plugin (it is not parented to the DataModel).
local widget
for instance in pairs(Mock.States) do
	if Mock.States[instance].className == "DockWidgetPluginGui" then
		widget = instance
	end
end
check(widget ~= nil, "dock widget created")
widget.Enabled = true
check(widget:FindFirstChild("VisualFXRoot") ~= nil, "app built when the widget opens")

local heartbeat = world.RunService.Heartbeat
local function tick(times)
	for _ = 1, times or 2 do
		heartbeat:Fire(0.25)
	end
end

local function isShown(instance)
	local node = instance
	while node and node ~= widget do
		if node.Visible == false then
			return false
		end
		node = node.Parent
	end
	return true
end

local function findButton(text, under)
	for _, descendant in ipairs((under or widget):GetDescendants()) do
		if descendant.ClassName == "TextButton" and descendant.Text == text and isShown(descendant) then
			return descendant
		end
	end
	return nil
end

local function click(text, under)
	local button = findButton(text, under)
	check(button ~= nil, "button '" .. text .. "' exists")
	if button then
		button.MouseButton1Click:Fire()
		tick()
	end
	return button
end

local pages = {
	"Overview", "Scene", "Atmosphere", "Lighting", "Water", "Particles", "Weather", "Presets",
	"Transitions", "AI Director", "Inspector", "Code", "Settings",
}
for _, name in ipairs(pages) do
	click("  " .. name)
end

local engine = bridge.Engine

-- Presets: apply a preset through its card.
click("  Presets")
click("Apply")
check(#engine.InstanceManager:GetManaged(true) > 0, "applying a preset card creates managed effects")

-- Preview + revert from a preset card.
local before = engine:ExportConfiguration({ Format = "json" })
click("Preview")
check(engine:IsPreviewing(), "preview button starts a preview")
click("Revert")
check(not engine:IsPreviewing(), "revert ends the preview")
check(engine:ExportConfiguration({ Format = "json" }) == before, "revert restores the configuration")

-- Property editing: toggle GlobalShadows on the Lighting page (live preview) then Apply.
click("  Lighting")
local toggled = false
for _, descendant in ipairs(widget:GetDescendants()) do
	local text = descendant:GetAttribute("SearchText")
	if not toggled and text and string.find(text, "globalshadows", 1, true) and isShown(descendant) then
		for _, inner in ipairs(descendant:GetDescendants()) do
			if not toggled and inner.ClassName == "TextButton" and inner.Text == "" then
				inner.MouseButton1Click:Fire()
				toggled = true
			end
		end
	end
end
tick()
check(toggled, "found the GlobalShadows toggle")
check(engine:IsPreviewing(), "editing a property starts a live preview")
click("Apply")
check(not engine:IsPreviewing(), "apply commits the preview")
check(#world.Waypoints > 0, "apply records a ChangeHistory step")

-- Search filters rows.
local searchBox
for _, descendant in ipairs(widget:GetDescendants()) do
	if descendant.ClassName == "TextBox" and descendant.PlaceholderText == "Search settings…" then
		searchBox = descendant
	end
end
check(searchBox ~= nil, "search box exists")
searchBox.Text = "exposure"
local visibleRows, hiddenRows = 0, 0
for _, descendant in ipairs(widget:GetDescendants()) do
	if descendant:GetAttribute("SearchText") and isShown(descendant.Parent) then
		if descendant.Visible then
			visibleRows += 1
		else
			hiddenRows += 1
		end
	end
end
check(visibleRows >= 1 and hiddenRows > 5, "search hides non-matching rows")
searchBox.Text = ""

-- AI Director: preview and apply the example description.
click("  AI Director")
click("Interpret")
click("Apply")
local weather = engine:GetConfiguration().Weather
check(weather ~= nil and weather.Type == "LightRain", "director applies the interpreted scene")

-- Weather page.
click("  Weather")
click("Remove weather")
click("Apply")
check(engine:GetConfiguration().Weather == nil, "weather removed")

-- Particles page: add a system.
click("  Particles")
click("Add")
check(engine:GetConfiguration().Particles ~= nil, "particle system added")
click("Apply")

-- Transitions page.
click("  Transitions")
click("Start")
tick(40)
click("Apply")

-- Code page: regenerate and export.
click("  Code")
click("Regenerate")
click("Export to place")
local exported = game:GetService("ServerScriptService"):FindFirstChild("VisualFXScene")
check(exported ~= nil and string.find(exported.Source, "VisualFX:CreateScene", 1, true) ~= nil, "code exported as a Script")
check(#opened == 1, "exported script opened in the editor")

-- Settings: install the runtime package.
click("  Settings")
click("Install / update in ReplicatedStorage")
local package = game:GetService("ReplicatedStorage"):FindFirstChild("VisualFX")
check(package ~= nil and package:GetAttribute("VisualFX_Package") == engine.Version, "runtime package installed")
click("Install / update in ReplicatedStorage")
check(#game:GetService("ReplicatedStorage"):GetChildren() == 1, "reinstalling replaces the package")
package = game:GetService("ReplicatedStorage"):FindFirstChild("VisualFX")

-- The installed runtime works without the plugin.
local gameRequire = Mock.makeRequire(world)
local Runtime = gameRequire(package)
local runtimeEngine = Runtime.new({ AutoStart = false })
check(runtimeEngine:ApplyPreset("Night").Success, "installed runtime package applies presets")
runtimeEngine:ResetManagedEffects()

-- Inspector refresh and overview reset.
click("  Inspector")
click("Refresh")
click("  Overview")
click("Reset managed effects")
click("Click again to confirm reset")
check(#engine.InstanceManager:GetManaged(true) == 0, "reset removes managed effects")

-- Settings persisted.
check(typeof(settingsStore["VisualFXStudio.Settings"]) == "table", "settings persisted with plugin:SetSetting")

-- Agent bridge.
local inspected = bridge.Execute({ Action = "InspectScene" })
check(inspected.Success, "agent bridge executes commands")

-- Unload cleanly.
pluginObject.Unloading:Fire()
check(world.env._G.VisualFXStudio == nil, "unloading clears the agent bridge")

for _, warning in ipairs(world.Warnings) do
	table.insert(failures, "warn(): " .. warning)
end

print(string.format("plugin smoke test: %d checks, %d failures", checks, #failures))
for _, failure in ipairs(failures) do
	print("FAIL " .. failure)
end
if #failures > 0 then
	error("plugin smoke test failed", 0)
end
