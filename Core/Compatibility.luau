--[[
	VisualFX.Core.Compatibility

	Detects, at runtime, which classes, properties and enum items the running
	Roblox engine actually exposes. Nothing here is hardcoded: support is
	determined by safely reading properties on real instances inside pcall.

	  Compatibility:IsSupported("Lighting.EnvironmentDiffuseScale") --> boolean
	  Compatibility:GetPropertySupport("Lighting", "EnvironmentDiffuseScale")
	  Compatibility:SetProperty(instance, "Density", 0.4) --> ok, message

	Results are cached per class/property. Unsupported properties are reported
	once and skipped so a single missing property never breaks a configuration.
]]

local Compatibility = {}
Compatibility.__index = Compatibility

-- Services and singletons that cannot be created with Instance.new.
local SERVICE_RESOLVERS = {
	Lighting = function()
		return game:GetService("Lighting")
	end,
	Workspace = function()
		return workspace
	end,
	Terrain = function()
		return workspace.Terrain
	end,
}

function Compatibility.new()
	local self = setmetatable({}, Compatibility)
	self._propertyCache = {}
	self._classCache = {}
	self._samples = {}
	self._reported = {}
	return self
end

-- Returns an instance of `className` suitable for reading properties, or nil.
function Compatibility:GetSample(className: string): Instance?
	local sample = self._samples[className]
	if sample ~= nil then
		return sample or nil
	end
	local resolver = SERVICE_RESOLVERS[className]
	local ok, result
	if resolver then
		ok, result = pcall(resolver)
	else
		ok, result = pcall(Instance.new, className)
	end
	if ok and typeof(result) == "Instance" then
		self._samples[className] = result
		return result
	end
	self._samples[className] = false
	return nil
end

function Compatibility:IsClassSupported(className: string): boolean
	local cached = self._classCache[className]
	if cached == nil then
		cached = self:GetSample(className) ~= nil
		self._classCache[className] = cached
	end
	return cached
end

--[[
	Describes support for ClassName.Property:
	{ ClassName, Property, Supported, Readable, Reason, ValueType, Default }
	`Default` is the value on a freshly created instance (or the live value
	for services) and is used when a property must be reset and no original
	value was recorded.
]]
function Compatibility:GetPropertySupport(className: string, property: string)
	local key = className .. "." .. property
	local cached = self._propertyCache[key]
	if cached then
		return cached
	end
	local info = {
		ClassName = className,
		Property = property,
		Supported = false,
		Readable = false,
		Reason = nil :: string?,
		ValueType = nil :: string?,
		Default = nil :: any,
	}
	local sample = self:GetSample(className)
	if not sample then
		info.Reason = string.format("class '%s' is not available in this engine version", className)
	else
		local ok, value = pcall(function()
			return (sample :: any)[property]
		end)
		if ok and typeof(value) ~= "Instance" and typeof(value) ~= "RBXScriptSignal" and typeof(value) ~= "function" then
			info.Supported = true
			info.Readable = true
			info.ValueType = typeof(value)
			if not SERVICE_RESOLVERS[className] then
				info.Default = value
			end
		elseif ok then
			info.Reason = string.format("%s.%s is not a data property", className, property)
		else
			info.Reason = string.format("%s.%s is not exposed by this engine version", className, property)
		end
	end
	table.freeze(info)
	self._propertyCache[key] = info
	return info
end

-- Accepts "Class.Property" (e.g. "Lighting.EnvironmentDiffuseScale").
function Compatibility:IsSupported(path: string): boolean
	local className, property = string.match(path, "^([%w_]+)%.([%w_]+)$")
	if not className then
		return self:IsClassSupported(path)
	end
	return self:GetPropertySupport(className, property).Supported
end

-- True when the instance itself exposes the property (handles subclasses).
function Compatibility:HasProperty(instance: Instance, property: string): boolean
	local className = instance.ClassName
	local key = className .. "." .. property
	local cached = self._propertyCache[key]
	if cached then
		return cached.Supported
	end
	local ok = pcall(function()
		return (instance :: any)[property]
	end)
	if not ok then
		-- Cache negative results through the class sample path for consistency.
		return self:GetPropertySupport(className, property).Supported
	end
	return true
end

function Compatibility:GetProperty(instance: Instance, property: string): (boolean, any)
	return pcall(function()
		return (instance :: any)[property]
	end)
end

--[[
	Writes a property safely. Returns ok, message. Never throws.
	Failed writes (read-only at this security level, unsupported value, …)
	are reported to the caller as a message.
]]
function Compatibility:SetProperty(instance: Instance, property: string, value: any): (boolean, string?)
	if not self:HasProperty(instance, property) then
		return false, string.format("%s.%s is not supported by this engine version; skipped", instance.ClassName, property)
	end
	local ok, problem = pcall(function()
		(instance :: any)[property] = value
	end)
	if not ok then
		return false, string.format("could not set %s.%s: %s", instance.ClassName, property, tostring(problem))
	end
	return true, nil
end

function Compatibility:HasEnumItem(enumName: string, itemName: string): boolean
	local ok, result = pcall(function()
		return (Enum :: any)[enumName][itemName]
	end)
	return ok and typeof(result) == "EnumItem"
end

-- Returns true only the first time a key is seen; used to avoid log spam.
function Compatibility:ShouldReport(key: string): boolean
	if self._reported[key] then
		return false
	end
	self._reported[key] = true
	return true
end

--[[
	Produces a report of every property referenced by the registered schemas,
	grouped by support. Used by the inspector, the plugin Settings page and
	AI agents that want to know what the current engine can do.
]]
function Compatibility:BuildReport(schemaFields: { { ClassName: string, Property: string, Path: string } })
	local report = { Supported = {}, Unsupported = {} }
	for _, field in ipairs(schemaFields) do
		local info = self:GetPropertySupport(field.ClassName, field.Property)
		if info.Supported then
			table.insert(report.Supported, field.Path)
		else
			table.insert(report.Unsupported, { Path = field.Path, Reason = info.Reason })
		end
	end
	table.sort(report.Supported)
	table.sort(report.Unsupported, function(a, b)
		return a.Path < b.Path
	end)
	return report
end

-- Shared default instance for code that does not need isolation.
Compatibility.Default = Compatibility.new()

return Compatibility
