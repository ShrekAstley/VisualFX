--[[
	Owns the plugin's VisualFX engine and every stateful interaction the UI
	needs. Pages never call the engine directly for mutations; they go
	through this controller so that:

	  * edits are non-destructive previews (journaled) until Apply,
	  * Apply is a single undoable ChangeHistory step,
	  * Revert restores exactly what was there (keeping developer edits),
	  * the UI is notified through one Changed signal,
	  * settings and user presets persist with plugin:SetSetting.

	All mutations use the same Execute command API that AI agents use.
]]

local Modules = script.Parent.Parent
local ChangeHistory = require(Modules.Commands.ChangeHistory)
local ExportCode = require(Modules.Commands.ExportCode)
local RuntimePackage = require(Modules.Commands.RuntimePackage)

local PluginController = {}
PluginController.__index = PluginController

PluginController.SETTINGS_KEY = "VisualFXStudio.Settings"
PluginController.PRESETS_KEY = "VisualFXStudio.UserPresets"

PluginController.DefaultSettings = {
	LivePreview = true,
	AdoptExisting = true,
	RuntimePreview = false,
	Quality = "High",
	CodeTemplate = "Script",
	RequirePath = 'game:GetService("ReplicatedStorage").VisualFX',
	LastPage = "Overview",
}

function PluginController.new(plugin: Plugin?, engine, library: Instance?)
	local self = setmetatable({}, PluginController)
	self.Plugin = plugin
	self.Engine = engine
	self.Library = library
	self.Signal = engine.Events.Signal or require(library.Core.Events).Signal
	self.Changed = self.Signal.new("ControllerChanged")
	self.LastResult = nil
	self.Pending = nil -- accumulated edits when LivePreview is off
	self._history = nil
	self._connections = {}

	self.Settings = table.clone(PluginController.DefaultSettings)
	local stored = self:_GetSetting(PluginController.SETTINGS_KEY)
	if typeof(stored) == "table" then
		for key, value in pairs(stored) do
			if PluginController.DefaultSettings[key] ~= nil and typeof(value) == typeof(PluginController.DefaultSettings[key]) then
				self.Settings[key] = value
			end
		end
	end
	engine.Settings.AdoptExisting = self.Settings.AdoptExisting
	engine.Settings.RuntimeControllers = self.Settings.RuntimePreview

	engine.Presets:SetStorage({
		Load = function()
			local data = self:_GetSetting(PluginController.PRESETS_KEY)
			return if typeof(data) == "table" then data else {}
		end,
		Save = function(data)
			self:_SetSetting(PluginController.PRESETS_KEY, data)
		end,
	})

	table.insert(self._connections, engine.Events.Changed:Connect(function(result)
		self.LastResult = result
		self.Changed:Fire("Engine")
	end))
	return self
end

function PluginController:_GetSetting(key: string)
	if not self.Plugin then
		return nil
	end
	local ok, value = pcall(function()
		return self.Plugin:GetSetting(key)
	end)
	return if ok then value else nil
end

function PluginController:_SetSetting(key: string, value: any)
	if not self.Plugin then
		return
	end
	pcall(function()
		self.Plugin:SetSetting(key, value)
	end)
end

function PluginController:SetSetting(key: string, value: any)
	self.Settings[key] = value
	self:_SetSetting(PluginController.SETTINGS_KEY, self.Settings)
	if key == "AdoptExisting" then
		self.Engine.Settings.AdoptExisting = value
	elseif key == "RuntimePreview" then
		self.Engine.Settings.RuntimeControllers = value
		self.Engine.Settings.CameraEffects = value
	end
	self.Changed:Fire("Settings")
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

-- Runs an engine command, records the result and notifies the UI.
function PluginController:Execute(command)
	local result = self.Engine:Execute(command)
	self.LastResult = result
	self.Changed:Fire("Command")
	return result
end

function PluginController:IsPreviewing(): boolean
	return self.Engine:IsPreviewing()
end

--[[
	Previews a configuration overlay. With LivePreview the change is visible
	immediately (journaled); without it the overlay accumulates in Pending
	until PreviewPending().
]]
function PluginController:Edit(overlay: { [string]: any }, options: { [string]: any }?)
	local opts = options or {}
	if not self.Settings.LivePreview and not opts.Force then
		local Config = require(self.Library.Core.Config)
		self.Pending = Config.merge(self.Pending or {}, overlay)
		self.Changed:Fire("Pending")
		return { Success = true, Pending = true, Warnings = {}, Errors = {} }
	end
	if not self.Engine:IsPreviewing() then
		self._history = ChangeHistory.Begin("VisualFX: Edit scene")
	end
	local result = self:Execute({ Action = "PreviewScene", Configuration = overlay, Replace = opts.Replace })
	return result
end

function PluginController:PreviewPending()
	if not self.Pending then
		return nil
	end
	local pending = self.Pending
	self.Pending = nil
	return self:Edit(pending, { Force = true })
end

-- Previews a complete scene (preset, import, director result).
function PluginController:PreviewScene(configuration: { [string]: any })
	return self:Edit(configuration, { Force = true, Replace = true })
end

-- Keeps the preview as one undoable step.
function PluginController:Apply()
	if self.Pending then
		self:PreviewPending()
	end
	if not self.Engine:IsPreviewing() then
		return nil
	end
	local result = self:Execute({ Action = "CommitPreview" })
	ChangeHistory.Finish(self._history)
	self._history = nil
	return result
end

function PluginController:Revert()
	self.Pending = nil
	if not self.Engine:IsPreviewing() then
		self.Changed:Fire("Pending")
		return nil
	end
	local result = self:Execute({ Action = "RevertPreview" })
	ChangeHistory.Finish(self._history)
	self._history = nil
	return result
end

-- Applies immediately as one undo step (used by buttons such as "Apply preset").
function PluginController:ApplyNow(command)
	if self.Engine:IsPreviewing() then
		self:Apply()
	end
	return ChangeHistory.Record("VisualFX: " .. tostring(command.Action), function()
		return self:Execute(command)
	end)
end

function PluginController:ResetManagedEffects()
	if self.Engine:IsPreviewing() then
		self:Revert()
	end
	return self:ApplyNow({ Action = "ResetManagedEffects" })
end

---------------------------------------------------------------------------
-- Code, packaging and presets
---------------------------------------------------------------------------

function PluginController:GenerateCode(templateName: string?)
	local template = templateName or self.Settings.CodeTemplate
	return self:Execute({
		Action = "GenerateCode",
		Options = { Template = template, RequirePath = self.Settings.RequirePath },
	})
end

function PluginController:ExportCode(templateName: string?)
	local template = templateName or self.Settings.CodeTemplate
	local generated = self:GenerateCode(template)
	if not generated.Success then
		return generated
	end
	local ok, scriptOrProblem = pcall(ExportCode.Export, self.Plugin, template, generated.Code)
	if not ok then
		return { Success = false, Errors = { tostring(scriptOrProblem) } }
	end
	return { Success = true, Script = scriptOrProblem, Message = "Exported to " .. scriptOrProblem:GetFullName() }
end

-- User presets as ModuleScript sources (Codegen "Module" template).
function PluginController:BuildUserPresetModules(): { [string]: string }
	local modules = {}
	for _, preset in ipairs(self.Engine:ListPresets({ Source = "Saved" })) do
		local config = self.Engine.Presets:GetRaw(preset.Name)
		if config then
			local ok, source = pcall(self.Engine.GenerateCode, self.Engine, config, { Template = "Module" })
			if ok then
				modules[preset.Name] = source
			end
		end
	end
	return modules
end

function PluginController:InstallRuntimePackage()
	local result = RuntimePackage.Install({
		Source = self.Library,
		Version = self.Engine.Version,
		Presets = self:BuildUserPresetModules(),
	})
	self.LastResult = { Success = result.Success, Action = "InstallRuntimePackage", Warnings = {}, Errors = if result.Success then {} else { result.Message } }
	self.Changed:Fire("Package")
	return result
end

function PluginController:GetInstalledPackageVersion(): string?
	return RuntimePackage.GetInstalledVersion()
end

-- Finds an instance by the dotted path produced by GetFullName().
function PluginController:ResolvePath(path: string): Instance?
	local node: Instance = game
	for part in string.gmatch(path, "[^%.]+") do
		local child = node:FindFirstChild(part)
		if not child then
			local ok, service = pcall(game.GetService, game, part)
			child = if ok and node == game then service else nil
		end
		if not child then
			return nil
		end
		node = child
	end
	return node
end

function PluginController:Select(path: string)
	local instance = self:ResolvePath(path)
	if instance then
		pcall(function()
			game:GetService("Selection"):Set({ instance })
		end)
	end
	return instance
end

function PluginController:Destroy()
	if self.Engine:IsPreviewing() then
		self:Revert()
	end
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self.Changed:DisconnectAll()
end

return PluginController
