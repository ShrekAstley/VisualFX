--[[
	VisualFX.Core.PropertyMap

	Helpers for sections whose configuration keys map 1:1 onto Roblox
	properties (Lighting, Atmosphere, Sky, Clouds, post-processing, Water).
	A field declares `Property = "WaterColor"` and optional `ClassName`;
	these helpers translate between configuration tables, property tables
	and the live instance.
]]

local Util = require(script.Parent.Util)

local PropertyMap = {}

--[[
	Converts a section configuration into { [PropertyName] = value } using the
	field schema. Returns properties plus a { [PropertyName] = field } index.
	Nested object/map fields are ignored (they are handled by their owner).
]]
function PropertyMap.toProperties(fields: { any }, config: { [string]: any }?)
	local properties, byProperty = {}, {}
	if not config then
		return properties, byProperty
	end
	for _, field in ipairs(fields) do
		if field.Property and field.Kind ~= "object" and field.Kind ~= "map" then
			local value = config[field.Key]
			byProperty[field.Property] = field
			if value ~= nil then
				properties[field.Property] = value
			end
		end
	end
	return properties, byProperty
end

-- Field index keyed by Roblox property name.
function PropertyMap.fieldsByProperty(fields: { any }): { [string]: any }
	local index = {}
	for _, field in ipairs(fields) do
		if field.Property then
			index[field.Property] = field
		end
	end
	return index
end

-- Reads live values from an instance back into configuration keys.
function PropertyMap.read(instance: Instance?, fields: { any }, compatibility): { [string]: any }
	local result = {}
	if not instance then
		return result
	end
	for _, field in ipairs(fields) do
		if field.Property and field.Kind ~= "object" and field.Kind ~= "map" then
			if compatibility:HasProperty(instance, field.Property) then
				local ok, value = compatibility:GetProperty(instance, field.Property)
				if ok then
					result[field.Key] = value
				end
			end
		end
	end
	return result
end

-- Schema default values keyed by configuration key.
function PropertyMap.defaults(fields: { any }): { [string]: any }
	local result = {}
	for _, field in ipairs(fields) do
		if field.Default ~= nil then
			result[field.Key] = field.Default
		end
	end
	return result
end

-- Keeps only the configuration keys that differ from the schema defaults.
function PropertyMap.withoutDefaults(fields: { any }, config: { [string]: any }, equal): { [string]: any }
	local index = {}
	for _, field in ipairs(fields) do
		index[field.Key] = field
	end
	local result = {}
	for _, key in ipairs(Util.sortedKeys(config)) do
		local field = index[key]
		if not field or field.Default == nil or not equal(field.Default, config[key]) then
			result[key] = config[key]
		end
	end
	return result
end

return PropertyMap
