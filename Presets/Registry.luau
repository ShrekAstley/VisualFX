--[[
	VisualFX.Presets.Registry

	Presets are plain configuration data. Built-in presets live as
	ModuleScripts in Presets/BuiltIn; user presets live in Presets/User
	(ModuleScripts, e.g. exported by the Studio plugin) or are saved at
	runtime with VisualFX:SavePreset.

	Inheritance / composition:

	  AutumnRainForest = { Inherits = { "BaseForest", "Autumn", "LightRain" }, ... }

	Deterministic merge rule: parents are resolved recursively and merged
	left to right with Config.merge, then the preset's own values are merged
	last. Metadata is never inherited. Cycles and missing parents are errors.
]]

local Root = script.Parent.Parent
local Util = require(Root.Core.Util)
local Config = require(Root.Core.Config)
local Serialization = require(Root.Core.Serialization)

local PresetRegistry = {}
PresetRegistry.__index = PresetRegistry

local function loadFolder(folder: Instance?, into: { [string]: any }, source: string, warnings: { string })
	if not folder then
		return
	end
	local children = folder:GetChildren()
	table.sort(children, function(a, b)
		return a.Name < b.Name
	end)
	for _, child in ipairs(children) do
		if child:IsA("ModuleScript") then
			local ok, preset = pcall(require, child)
			if ok and typeof(preset) == "table" then
				into[child.Name] = { Config = Util.deepCopy(preset), Source = source }
			else
				table.insert(warnings, string.format("preset %s could not be loaded: %s", child:GetFullName(), tostring(preset)))
			end
		end
	end
end

function PresetRegistry.new()
	local self = setmetatable({}, PresetRegistry)
	self._presets = {}
	self.LoadWarnings = {}
	self._storage = nil
	loadFolder(script.Parent:FindFirstChild("BuiltIn"), self._presets, "BuiltIn", self.LoadWarnings)
	loadFolder(script.Parent:FindFirstChild("User"), self._presets, "User", self.LoadWarnings)
	return self
end

--[[
	Optional persistence for user presets. The adapter must implement
	  Load() -> { [name] = serializedDocument }   (may yield)
	  Save({ [name] = serializedDocument })       (may yield)
	The Studio plugin uses plugin:SetSetting; games can use a DataStore.
]]
function PresetRegistry:SetStorage(adapter)
	self._storage = adapter
	if adapter and adapter.Load then
		local ok, stored = pcall(adapter.Load)
		if ok and typeof(stored) == "table" then
			for _, name in ipairs(Util.sortedKeys(stored)) do
				local config = Serialization:Deserialize(stored[name])
				if config then
					self._presets[name] = { Config = config, Source = "Saved" }
				end
			end
		end
	end
end

function PresetRegistry:_Persist()
	if not self._storage or not self._storage.Save then
		return
	end
	local data = {}
	for name, entry in pairs(self._presets) do
		if entry.Source == "Saved" then
			data[name] = Serialization:Export(entry.Config, false)
		end
	end
	pcall(self._storage.Save, data)
end

function PresetRegistry:Exists(name: string): boolean
	return self._presets[name] ~= nil
end

-- Case/format-insensitive lookup ("misty_forest" -> "MistyForest").
function PresetRegistry:FindName(name: string): string?
	if typeof(name) ~= "string" then
		return nil
	end
	if self._presets[name] then
		return name
	end
	local normalized = Util.normalizeName(name)
	for _, registered in ipairs(Util.sortedKeys(self._presets)) do
		if Util.normalizeName(registered) == normalized then
			return registered
		end
	end
	return nil
end

function PresetRegistry:GetRaw(name: string)
	local canonical = self:FindName(name)
	local entry = canonical and self._presets[canonical]
	return if entry then Util.deepCopy(entry.Config) else nil
end

function PresetRegistry:GetSource(name: string): string?
	local canonical = self:FindName(name)
	local entry = canonical and self._presets[canonical]
	return entry and entry.Source
end

--[[
	Resolves inheritance. Returns (config, error). The result has no Inherits
	key and keeps the preset's own Metadata.
]]
function PresetRegistry:Resolve(name: string, _visiting: { [string]: boolean }?, _chain: { string }?): ({ [string]: any }?, string?)
	local canonical = self:FindName(name)
	if not canonical then
		return nil, string.format("unknown preset '%s'", tostring(name))
	end
	local visiting = _visiting or {}
	local chain = _chain or {}
	if visiting[canonical] then
		table.insert(chain, canonical)
		return nil, "preset inheritance cycle: " .. table.concat(chain, " -> ")
	end
	visiting[canonical] = true
	table.insert(chain, canonical)
	local raw = self._presets[canonical].Config
	local merged, problem = self:ExpandWith(raw, visiting, chain)
	visiting[canonical] = nil
	table.remove(chain)
	return merged, problem
end

function PresetRegistry:ExpandWith(config: { [string]: any }, visiting, chain): ({ [string]: any }?, string?)
	local inherits = config.Inherits
	if typeof(inherits) == "string" then
		inherits = { inherits }
	end
	local result = {}
	if typeof(inherits) == "table" then
		for _, parentName in ipairs(inherits) do
			local parent, problem = self:Resolve(parentName, visiting, chain)
			if not parent then
				return nil, problem
			end
			parent.Metadata = nil
			result = Config.merge(result, parent)
		end
	end
	local own = Util.deepCopy(config)
	own.Inherits = nil
	result = Config.merge(result, own)
	Config.stripRemovals(result)
	result.Version = config.Version or result.Version or Config.CURRENT_VERSION
	return result, nil
end

-- Expands a configuration's Inherits list (used by the scene resolver).
function PresetRegistry:Expand(config: { [string]: any }): { [string]: any }
	local expanded = self:ExpandWith(config, {}, {})
	return expanded or config
end

-- Validation hook: reports missing parents and cycles.
function PresetRegistry:CheckInheritance(config: { [string]: any }, report)
	if not config.Inherits then
		return
	end
	for _, parentName in ipairs(config.Inherits) do
		if not self:FindName(parentName) then
			local suggestion = Util.suggest(parentName, Util.sortedKeys(self._presets))
			report:Error(
				"Inherits",
				"UnknownPreset",
				string.format(
					"Inherits: unknown preset '%s'%s",
					parentName,
					if suggestion then " (did you mean '" .. suggestion .. "'?)" else ""
				)
			)
		else
			local _, problem = self:Resolve(parentName)
			if problem then
				report:Error("Inherits", "InvalidInheritance", "Inherits: " .. problem)
			end
		end
	end
end

-- Merges several presets (and optional overrides) into a new configuration.
function PresetRegistry:Compose(names: { string }, overrides: { [string]: any }?): ({ [string]: any }?, string?)
	local config = { Version = Config.CURRENT_VERSION, Inherits = table.clone(names) }
	if overrides then
		config = Config.merge(config, overrides)
		config.Inherits = table.clone(names)
	end
	return self:ExpandWith(config, {}, {})
end

function PresetRegistry:Save(name: string, config: { [string]: any }, options: { [string]: any }?): (boolean, string?)
	if typeof(name) ~= "string" or not string.match(name, "^[%w_%-]+$") then
		return false, "preset names may only contain letters, digits, '_' and '-'"
	end
	local existing = self._presets[name]
	if existing and existing.Source == "BuiltIn" then
		return false, string.format("'%s' is a built-in preset and cannot be overwritten; choose another name", name)
	end
	if existing and not (options and options.Overwrite) then
		return false, string.format("preset '%s' already exists; pass Overwrite = true to replace it", name)
	end
	local copy = Util.deepCopy(config)
	copy.Metadata = copy.Metadata or {}
	copy.Metadata.Name = copy.Metadata.Name or name
	self._presets[name] = { Config = copy, Source = "Saved" }
	self:_Persist()
	return true, nil
end

function PresetRegistry:Delete(name: string): (boolean, string?)
	local canonical = self:FindName(name)
	if not canonical then
		return false, string.format("unknown preset '%s'", tostring(name))
	end
	local entry = self._presets[canonical]
	if entry.Source == "BuiltIn" then
		return false, string.format("'%s' is a built-in preset and cannot be deleted", canonical)
	end
	self._presets[canonical] = nil
	self:_Persist()
	return true, nil
end

--[[
	Lists presets: { { Name, Category, Description, Source, Inherits } } sorted by name.
	filter: { Category = "Forest", Source = "BuiltIn", Search = "rain" }
]]
function PresetRegistry:List(filter: { [string]: any }?)
	local list = {}
	for _, name in ipairs(Util.sortedKeys(self._presets)) do
		local entry = self._presets[name]
		local metadata = entry.Config.Metadata or {}
		local item = {
			Name = name,
			DisplayName = metadata.Name or name,
			Category = metadata.Category or "General",
			Description = metadata.Description or "",
			Tags = metadata.Tags or {},
			Source = entry.Source,
			Inherits = entry.Config.Inherits,
		}
		local include = true
		if filter then
			if filter.Category and item.Category ~= filter.Category then
				include = false
			end
			if filter.Source and item.Source ~= filter.Source then
				include = false
			end
			if filter.Search and filter.Search ~= "" then
				local haystack = string.lower(name .. " " .. item.DisplayName .. " " .. item.Category .. " " .. item.Description .. " " .. table.concat(item.Tags, " "))
				if not string.find(haystack, string.lower(filter.Search), 1, true) then
					include = false
				end
			end
		end
		if include then
			table.insert(list, item)
		end
	end
	return list
end

return PresetRegistry
