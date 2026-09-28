--[[
	VisualFX.Runtime.Cleanup

	Two responsibilities:
	  * a Maid that owns connections/instances/callbacks created by VisualFX
	    and releases them deterministically (VisualFX:Destroy());
	  * ResetManagedEffects: removes every VisualFX-created instance, releases
	    adopted instances and restores every original property value recorded
	    on Lighting, Terrain and Workspace. Unmanaged instances are never touched.
]]

local Core = script.Parent.Parent.Core
local Util = require(Core.Util)

local Cleanup = {}

local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid:Give(task: any): any
	table.insert(self._tasks, task)
	return task
end

function Maid:Clean()
	local tasks = self._tasks
	self._tasks = {}
	for index = #tasks, 1, -1 do
		local task = tasks[index]
		local kind = typeof(task)
		if kind == "RBXScriptConnection" then
			task:Disconnect()
		elseif kind == "Instance" then
			pcall(task.Destroy, task)
		elseif kind == "function" then
			pcall(task)
		elseif kind == "table" then
			if typeof(task.Disconnect) == "function" then
				pcall(task.Disconnect, task)
			elseif typeof(task.Destroy) == "function" then
				pcall(task.Destroy, task)
			end
		end
	end
end
Maid.Destroy = Maid.Clean

Cleanup.Maid = Maid

--[[
	Removes all managed effects and restores recorded originals.
	Returns { Removed = { types }, Restored = { "Lighting.Brightness", ... }, Warnings }.
]]
function Cleanup.ResetManagedEffects(engine)
	local manager = engine.InstanceManager
	local result = { Removed = {}, Restored = {}, Warnings = {} }
	local managed = manager:GetManaged(true)
	-- Deepest first so children are removed before their parents.
	table.sort(managed, function(a, b)
		local function depth(instance)
			local d, node = 0, instance.Parent
			while node do
				d += 1
				node = node.Parent
			end
			return d
		end
		local da, db = depth(a), depth(b)
		if da ~= db then
			return da > db
		end
		return a:GetFullName() < b:GetFullName()
	end)
	for _, instance in ipairs(managed) do
		local alive = pcall(function()
			return instance.Parent
		end)
		if alive and instance.Parent then
			local identity = manager:GetIdentity(instance)
			local ok, problem = manager:Remove(instance)
			if ok then
				if identity and identity.Type and instance.ClassName ~= "Part" and identity.ID ~= "root" then
					Util.addUnique(result.Removed, identity.Type)
				end
			elseif problem then
				table.insert(result.Warnings, problem)
			end
		end
	end
	for _, target in ipairs({ engine.Context.Lighting, engine.Context.Terrain, engine.Context.Workspace }) do
		for _, property in ipairs(manager:GetManagedProperties(target)) do
			local ok, problem = manager:RestoreOriginal(target, property)
			if ok then
				table.insert(result.Restored, target.Name .. "." .. property)
			elseif problem then
				table.insert(result.Warnings, string.format("%s.%s: %s", target.Name, property, problem))
			end
		end
	end
	table.sort(result.Removed)
	return result
end

return Cleanup
