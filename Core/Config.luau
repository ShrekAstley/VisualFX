--[[
	VisualFX.Core.Config

	The canonical configuration format and the deterministic rules that act on it.

	  {
	      Version = 1,
	      Metadata = { Name, Author, Description, Category, Tags },
	      Inherits = { "BaseForest", "Autumn" },   -- optional preset composition
	      Quality = { Level = "High", ... },
	      Lighting = {...}, Atmosphere = {...}, Sky = {...}, Clouds = {...},
	      PostProcessing = { Bloom = {...}, ColorCorrection = {...}, ... },
	      Water = {...},
	      Particles = { [name] = {...} },
	      Weather = { Type = "HeavyRain", Intensity = 0.8, ... },
	      Environment = { Wind = {...}, DayNight = {...}, Zones = { [name] = {...} } },
	      Effects = { [id] = { Effect = "Fireflies", ... } },
	  }

	Merge rules (used by presets, UpdateScene and transitions):
	  1. Scalars and Roblox values in the overlay replace the base value.
	  2. Dictionaries merge recursively, key by key.
	  3. Arrays are replaced as a whole (never concatenated).
	  4. The string sentinel Config.REMOVE ("$remove") deletes the key.
	  5. Keys are processed in sorted order so results never depend on hash order.
]]

local Util = require(script.Parent.Util)
local Values = require(script.Parent.Values)

local Config = {}

Config.CURRENT_VERSION = 1
Config.REMOVE = "$remove"

-- Top-level keys that are not effect sections.
Config.MetaKeys = {
	Version = true,
	Metadata = true,
	Inherits = true,
	Format = true,
}

function Config.new(sections: { [string]: any }?): { [string]: any }
	local config = Util.deepCopy(sections or {})
	config.Version = config.Version or Config.CURRENT_VERSION
	return config
end

function Config.isRemove(value: any): boolean
	return value == Config.REMOVE
end

--[[
	Deterministically merges `overlay` onto a copy of `base`.
	Neither input is mutated.
]]
function Config.merge(base: { [any]: any }?, overlay: { [any]: any }?): { [any]: any }
	local result = Util.deepCopy(base or {})
	if overlay == nil then
		return result
	end
	for _, key in ipairs(Util.sortedKeys(overlay)) do
		local value = overlay[key]
		if Config.isRemove(value) then
			result[key] = nil
		elseif Util.isPlainTable(value) and not Util.isArray(value) then
			if Util.isPlainTable(result[key]) and not Util.isArray(result[key]) then
				result[key] = Config.merge(result[key], value)
			else
				result[key] = Config.merge({}, value)
			end
		else
			result[key] = Util.deepCopy(value)
		end
	end
	return result
end

-- Merges any number of configurations left to right.
function Config.mergeAll(list: { { [any]: any } }): { [any]: any }
	local result = {}
	for _, item in ipairs(list) do
		result = Config.merge(result, item)
	end
	return result
end

-- Removes every "$remove" sentinel (used after merges that start from nothing).
function Config.stripRemovals(config: any): any
	if typeof(config) ~= "table" then
		return config
	end
	for _, key in ipairs(Util.sortedKeys(config)) do
		if Config.isRemove(config[key]) then
			config[key] = nil
		elseif typeof(config[key]) == "table" then
			Config.stripRemovals(config[key])
		end
	end
	return config
end

---------------------------------------------------------------------------
-- Schema migration
---------------------------------------------------------------------------

--[[
	Ordered migrations. Each migration upgrades from version N-1 to N.
	Version 0 is any configuration written before versioning existed:
	  * Lighting.PostProcessing was nested under Lighting
	  * Particles was an array of { Name = ..., ... }
	  * Weather could be a bare string
	  * Water used WaterColor/WaterTransparency style names
]]
Config.Migrations = {
	[1] = function(config: { [string]: any }, notes: { string })
		if typeof(config.Lighting) == "table" and typeof(config.Lighting.PostProcessing) == "table" then
			config.PostProcessing = Config.merge(config.Lighting.PostProcessing, config.PostProcessing)
			config.Lighting.PostProcessing = nil
			table.insert(notes, "moved Lighting.PostProcessing to PostProcessing")
		end
		if Util.isArray(config.Particles) then
			local map = {}
			for index, item in ipairs(config.Particles) do
				local name = if typeof(item) == "table" and typeof(item.Name) == "string"
					then item.Name
					else "Particle" .. index
				local copy = Util.deepCopy(item)
				if typeof(copy) == "table" then
					copy.Name = nil
				end
				map[name] = copy
			end
			config.Particles = map
			table.insert(notes, "converted Particles array to a dictionary keyed by name")
		end
		if typeof(config.Weather) == "string" and config.Weather ~= Config.REMOVE then
			config.Weather = { Type = config.Weather }
			table.insert(notes, "converted Weather string to { Type = ... }")
		end
		if typeof(config.Water) == "table" then
			for _, name in ipairs({ "Color", "Transparency", "Reflectance", "WaveSize", "WaveSpeed" }) do
				local legacy = "Water" .. name
				if config.Water[legacy] ~= nil and config.Water[name] == nil then
					config.Water[name] = config.Water[legacy]
					config.Water[legacy] = nil
					table.insert(notes, "renamed Water." .. legacy .. " to Water." .. name)
				end
			end
		end
	end,
}

--[[
	Upgrades a configuration to CURRENT_VERSION. Returns (config, notes, error).
	The input is not mutated.
]]
function Config.migrate(config: { [string]: any }): ({ [string]: any }?, { string }, string?)
	local notes = {}
	if typeof(config) ~= "table" then
		return nil, notes, "configuration must be a table, received " .. typeof(config)
	end
	local result = Util.deepCopy(config)
	local version = result.Version
	if version == nil then
		version = 0
	end
	if typeof(version) ~= "number" or version % 1 ~= 0 or version < 0 then
		return nil, notes, "Version must be a non-negative integer"
	end
	if version > Config.CURRENT_VERSION then
		return nil,
			notes,
			string.format(
				"configuration version %d is newer than this VisualFX runtime (supports up to %d)",
				version,
				Config.CURRENT_VERSION
			)
	end
	for target = version + 1, Config.CURRENT_VERSION do
		local migration = Config.Migrations[target]
		if migration then
			migration(result, notes)
		end
		result.Version = target
	end
	if version < Config.CURRENT_VERSION then
		table.insert(notes, 1, string.format("migrated configuration from version %d to %d", version, Config.CURRENT_VERSION))
	end
	result.Version = Config.CURRENT_VERSION
	return result, notes, nil
end

---------------------------------------------------------------------------
-- Structural diff between two configurations
---------------------------------------------------------------------------

--[[
	Compares two configuration tables and returns
	{ Added = { {Path, Value} }, Removed = { {Path, Value} }, Modified = { {Path, From, To} } }
	sorted by path. Roblox values are compared with tolerance.
]]
function Config.diff(before: { [string]: any }?, after: { [string]: any }?)
	local result = { Added = {}, Removed = {}, Modified = {} }
	local function visit(a, b, path: string)
		local keys = {}
		local seen = {}
		for _, source in ipairs({ a or {}, b or {} }) do
			for _, key in ipairs(Util.sortedKeys(source)) do
				if not seen[key] then
					seen[key] = true
					table.insert(keys, key)
				end
			end
		end
		table.sort(keys, function(x, y)
			return tostring(x) < tostring(y)
		end)
		for _, key in ipairs(keys) do
			local childPath = if path == "" then tostring(key) else path .. "." .. tostring(key)
			local va, vb = a and a[key], b and b[key]
			local plainA = Util.isPlainTable(va) and not Util.isArray(va)
			local plainB = Util.isPlainTable(vb) and not Util.isArray(vb)
			if va == nil and vb ~= nil then
				table.insert(result.Added, { Path = childPath, Value = vb })
			elseif va ~= nil and vb == nil then
				table.insert(result.Removed, { Path = childPath, Value = va })
			elseif plainA and plainB then
				visit(va, vb, childPath)
			elseif not Values.equal(va, vb) then
				table.insert(result.Modified, { Path = childPath, From = va, To = vb })
			end
		end
	end
	visit(before, after, "")
	return result
end

-- Returns the section names present in a configuration (excluding meta keys).
function Config.sections(config: { [string]: any }?): { string }
	local names = {}
	if config then
		for _, key in ipairs(Util.sortedKeys(config)) do
			if not Config.MetaKeys[key] and string.sub(tostring(key), 1, 1) ~= "_" then
				table.insert(names, key)
			end
		end
	end
	return names
end

return Config
