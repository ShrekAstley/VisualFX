--[[
	Runtime packaging:

	  Studio plugin -> configure -> export configuration -> install runtime
	  package -> the game requires ReplicatedStorage.VisualFX

	Installs (or updates) a copy of the plugin's bundled VisualFX library into
	ReplicatedStorage. User presets saved in the plugin are written into the
	package's Presets/User folder as ModuleScripts so the game can call
	VisualFX:ApplyPreset("MyPreset") without the plugin.
]]

local ChangeHistory = require(script.Parent.ChangeHistory)

local RuntimePackage = {}

RuntimePackage.PACKAGE_ATTRIBUTE = "VisualFX_Package"

function RuntimePackage.Find(): Instance?
	local storage = game:GetService("ReplicatedStorage")
	local existing = storage:FindFirstChild("VisualFX")
	if existing and existing:IsA("ModuleScript") then
		return existing
	end
	return nil
end

function RuntimePackage.GetInstalledVersion(): string?
	local package = RuntimePackage.Find()
	return package and package:GetAttribute(RuntimePackage.PACKAGE_ATTRIBUTE)
end

--[[
	Installs the library. options:
	  Source       the plugin's bundled VisualFX ModuleScript (required)
	  Version      version string stamped on the package
	  Presets      { [name] = source } user preset modules to include
	Returns { Success, Package, Replaced, Message }.
]]
function RuntimePackage.Install(options: { [string]: any })
	local source = options.Source
	if not source then
		return { Success = false, Message = "the plugin's VisualFX library was not found" }
	end
	return ChangeHistory.Record("VisualFX: Install runtime package", function()
		local storage = game:GetService("ReplicatedStorage")
		local existing = RuntimePackage.Find()
		local replaced = false
		if existing then
			if existing:GetAttribute(RuntimePackage.PACKAGE_ATTRIBUTE) == nil then
				return {
					Success = false,
					Message = "ReplicatedStorage.VisualFX exists but was not installed by VisualFX Studio; rename or remove it first",
				}
			end
			existing:Destroy()
			replaced = true
		end
		local package = source:Clone()
		package.Name = "VisualFX"
		package:SetAttribute(RuntimePackage.PACKAGE_ATTRIBUTE, options.Version or "unknown")
		local presets = package:FindFirstChild("Presets")
		local userFolder = presets and presets:FindFirstChild("User")
		if presets and not userFolder then
			userFolder = Instance.new("Folder")
			userFolder.Name = "User"
			userFolder.Parent = presets
		end
		for name, presetSource in pairs(options.Presets or {}) do
			local module = Instance.new("ModuleScript")
			module.Name = name
			module.Source = presetSource
			module.Parent = userFolder
		end
		package.Parent = storage
		return {
			Success = true,
			Package = package,
			Replaced = replaced,
			Message = if replaced then "Runtime package updated in ReplicatedStorage.VisualFX" else "Runtime package installed in ReplicatedStorage.VisualFX",
		}
	end)
end

return RuntimePackage
