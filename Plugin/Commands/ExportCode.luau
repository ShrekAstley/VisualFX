--[[
	Writes generated Luau into the place as a Script, LocalScript or
	ModuleScript and opens it in the script editor. Plugins may set
	Script.Source; ScriptEditorService is used when the script is already
	open so unsaved editor state is respected.
]]

local ChangeHistory = require(script.Parent.ChangeHistory)

local ExportCode = {}

ExportCode.Targets = {
	Script = { ClassName = "Script", Service = "ServerScriptService", Name = "VisualFXScene" },
	LocalScript = { ClassName = "LocalScript", Service = "StarterPlayer", Child = "StarterPlayerScripts", Name = "VisualFXScene" },
	Module = { ClassName = "ModuleScript", Service = "ReplicatedStorage", Name = "VisualFXSceneConfig" },
	Transition = { ClassName = "LocalScript", Service = "StarterPlayer", Child = "StarterPlayerScripts", Name = "VisualFXTransition" },
}

local function resolveParent(target)
	local parent = game:GetService(target.Service)
	if target.Child then
		local child = parent:FindFirstChild(target.Child)
		if not child then
			-- StarterPlayerScripts exists in every normal place; recreate it if a place lost it.
			local ok, created = pcall(Instance.new, target.Child)
			if not ok then
				error(string.format("%s.%s is missing", target.Service, target.Child), 0)
			end
			created.Name = target.Child
			created.Parent = parent
			child = created
		end
		parent = child
	end
	return parent
end

local function setSource(scriptInstance: Instance, source: string)
	local ok = pcall(function()
		local editor = game:GetService("ScriptEditorService")
		local document = editor:FindScriptDocument(scriptInstance)
		if document then
			editor:UpdateSourceAsync(scriptInstance, function()
				return source
			end)
		else
			(scriptInstance :: any).Source = source
		end
	end)
	if not ok then
		(scriptInstance :: any).Source = source
	end
end

--[[
	Creates or updates the export target for a template. Returns the script.
	An existing script with the same name that VisualFX exported earlier is
	updated in place (identified by the VisualFX_Generated attribute).
]]
function ExportCode.Export(plugin: Plugin?, templateName: string, source: string): Instance
	local target = ExportCode.Targets[templateName] or ExportCode.Targets.Script
	return ChangeHistory.Record("VisualFX: Export " .. templateName, function()
		local parent = resolveParent(target)
		local existing = parent:FindFirstChild(target.Name)
		local scriptInstance
		if existing and existing.ClassName == target.ClassName and existing:GetAttribute("VisualFX_Generated") then
			scriptInstance = existing
		else
			scriptInstance = Instance.new(target.ClassName)
			scriptInstance.Name = target.Name
			scriptInstance:SetAttribute("VisualFX_Generated", true)
			scriptInstance.Parent = parent
		end
		setSource(scriptInstance, source)
		pcall(function()
			game:GetService("Selection"):Set({ scriptInstance })
		end)
		if plugin then
			pcall(function()
				plugin:OpenScript(scriptInstance)
			end)
		end
		return scriptInstance
	end)
end

return ExportCode
