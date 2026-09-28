--[[
	VisualFX.Core.Registry

	Central catalogue of everything VisualFX knows how to build:

	  Sections           top-level configuration sections (Lighting, Atmosphere, ...)
	  Effects            custom effect types registered with VisualFX:RegisterEffect
	  ParticleTemplates  named particle presets (Rain, Snow, Dust, ...)
	  WeatherTypes       composable weather definitions (HeavyRain, Thunderstorm, ...)

	New systems are added by registering definitions; the core engine never
	needs to change. Field schemas registered here drive validation, the
	machine-readable schema, the Studio property editors and code generation.
]]

local Util = require(script.Parent.Util)

local Registry = {}
Registry.__index = Registry

Registry.FieldKinds = {
	number = true,
	integer = true,
	boolean = true,
	string = true,
	Color3 = true,
	Vector3 = true,
	Vector2 = true,
	NumberRange = true,
	NumberSequence = true,
	ColorSequence = true,
	EnumItem = true,
	object = true,
	map = true,
	array = true,
	any = true,
}

function Registry.new()
	local self = setmetatable({}, Registry)
	self.Sections = {}
	self.SectionOrder = {}
	self.Effects = {}
	self.ParticleTemplates = {}
	self.WeatherTypes = {}
	return self
end

--[[
	Normalizes a field schema. Accepts either an ordered list of field
	definitions ({ Key = "Density", Kind = "number", ... }) or a dictionary
	keyed by field name ({ Density = { Kind = "number" } }).
]]
function Registry.normalizeFields(fields: any, path: string?): { any }
	local list = {}
	if fields == nil then
		return list
	end
	if Util.isArray(fields) then
		for _, field in ipairs(fields) do
			table.insert(list, field)
		end
	else
		for _, key in ipairs(Util.sortedKeys(fields)) do
			local field = Util.shallowCopy(fields[key])
			field.Key = field.Key or key
			table.insert(list, field)
		end
	end
	for _, field in ipairs(list) do
		assert(typeof(field.Key) == "string", string.format("schema field in %s is missing Key", path or "?"))
		field.Kind = field.Kind or field.Type or "any"
		field.Type = nil
		assert(
			Registry.FieldKinds[field.Kind],
			string.format("schema field %s.%s has unknown Kind '%s'", path or "?", field.Key, tostring(field.Kind))
		)
		if field.Kind == "object" then
			field.Fields = Registry.normalizeFields(field.Fields, (path or "") .. "." .. field.Key)
		elseif field.Kind == "map" then
			field.ItemFields = Registry.normalizeFields(field.ItemFields, (path or "") .. "." .. field.Key)
		end
	end
	return list
end

-- Builds a lookup table { [Key] = field, [Alias] = field } for a field list.
function Registry.indexFields(fields: { any })
	local index, aliases = {}, {}
	for _, field in ipairs(fields) do
		index[field.Key] = field
		if field.Aliases then
			for _, alias in ipairs(field.Aliases) do
				aliases[alias] = field.Key
			end
		end
	end
	return index, aliases
end

function Registry:RegisterSection(definition)
	assert(typeof(definition.Name) == "string", "section definition requires Name")
	assert(self.Sections[definition.Name] == nil, "section already registered: " .. definition.Name)
	definition.Kind = definition.Kind or "object"
	if definition.Kind == "object" then
		definition.Fields = Registry.normalizeFields(definition.Fields, definition.Name)
		definition.FieldIndex, definition.FieldAliases = Registry.indexFields(definition.Fields)
	else
		definition.ItemFields = Registry.normalizeFields(definition.ItemFields, definition.Name)
		definition.FieldIndex, definition.FieldAliases = Registry.indexFields(definition.ItemFields)
	end
	definition.Order = definition.Order or 100
	self.Sections[definition.Name] = definition
	table.insert(self.SectionOrder, definition.Name)
	table.sort(self.SectionOrder, function(a, b)
		local sa, sb = self.Sections[a], self.Sections[b]
		if sa.Order ~= sb.Order then
			return sa.Order < sb.Order
		end
		return a < b
	end)
	return definition
end

function Registry:GetSection(name: string)
	return self.Sections[name]
end

function Registry:GetSectionNames(): { string }
	return table.clone(self.SectionOrder)
end

--[[
	Registers a custom effect type:

	  {
	      Name = "Fireflies",
	      Category = "Particles",
	      Description = "...",
	      Schema = { Rate = { Kind = "number", Min = 0, Default = 20 }, ... },
	      Create = function(config, context) return instance end,
	      Update = function(instance, config, context) end,
	      Remove = function(instance, context) end,       -- optional (default: Destroy)
	      Inspect = function(instance) return {...} end,  -- optional
	      Validate = function(config, report) end,        -- optional extra checks
	  }

	Instances of the effect are declared in the configuration under
	`Effects = { [id] = { Effect = "Fireflies", ...fields } }`.
]]
function Registry:RegisterEffect(definition)
	assert(typeof(definition) == "table", "RegisterEffect expects a definition table")
	assert(typeof(definition.Name) == "string" and definition.Name ~= "", "effect definition requires a Name")
	assert(typeof(definition.Create) == "function", "effect definition requires a Create function")
	assert(
		definition.Update == nil or typeof(definition.Update) == "function",
		"effect definition Update must be a function"
	)
	assert(
		definition.Remove == nil or typeof(definition.Remove) == "function",
		"effect definition Remove must be a function"
	)
	local normalized = Util.shallowCopy(definition)
	normalized.Category = normalized.Category or "Custom"
	normalized.Fields = Registry.normalizeFields(definition.Schema, "Effects." .. definition.Name)
	normalized.FieldIndex, normalized.FieldAliases = Registry.indexFields(normalized.Fields)
	self.Effects[definition.Name] = normalized
	return normalized
end

function Registry:UnregisterEffect(name: string): boolean
	if self.Effects[name] then
		self.Effects[name] = nil
		return true
	end
	return false
end

function Registry:GetEffect(name: string)
	return self.Effects[name]
end

function Registry:RegisterParticleTemplate(name: string, template)
	assert(typeof(name) == "string", "particle template requires a name")
	assert(typeof(template) == "table", "particle template must be a table")
	self.ParticleTemplates[name] = template
end

function Registry:GetParticleTemplate(name: string)
	return self.ParticleTemplates[name]
end

function Registry:RegisterWeather(definition)
	assert(typeof(definition.Name) == "string", "weather definition requires a Name")
	self.WeatherTypes[definition.Name] = definition
	return definition
end

-- Resolves "light_rain", "LightRain", "lightrain" to the registered name.
function Registry:FindWeather(name: string)
	if typeof(name) ~= "string" then
		return nil
	end
	if self.WeatherTypes[name] then
		return self.WeatherTypes[name], name
	end
	local normalized = Util.normalizeName(name)
	for registered, definition in pairs(self.WeatherTypes) do
		if Util.normalizeName(registered) == normalized then
			return definition, registered
		end
	end
	return nil
end

function Registry:FindParticleTemplate(name: string)
	if typeof(name) ~= "string" then
		return nil
	end
	if self.ParticleTemplates[name] then
		return self.ParticleTemplates[name], name
	end
	local normalized = Util.normalizeName(name)
	for registered, template in pairs(self.ParticleTemplates) do
		if Util.normalizeName(registered) == normalized then
			return template, registered
		end
	end
	return nil
end

function Registry:ListWeather(): { string }
	return Util.sortedKeys(self.WeatherTypes)
end

function Registry:ListParticleTemplates(): { string }
	return Util.sortedKeys(self.ParticleTemplates)
end

function Registry:ListEffects(): { string }
	return Util.sortedKeys(self.Effects)
end

--[[
	Flattens every schema field that maps to a Roblox property into
	{ Path, ClassName, Property } rows (used by the compatibility report).
]]
function Registry:CollectPropertyFields(): { { Path: string, ClassName: string, Property: string } }
	local rows = {}
	local function visit(fields, prefix: string, className: string?)
		for _, field in ipairs(fields) do
			local path = prefix .. "." .. field.Key
			local owner = field.ClassName or className
			if field.Kind == "object" then
				visit(field.Fields, path, field.ClassName or owner)
			elseif field.Kind == "map" then
				visit(field.ItemFields, path .. ".*", field.ClassName or owner)
			elseif field.Property and owner then
				table.insert(rows, { Path = path, ClassName = owner, Property = field.Property })
			end
		end
	end
	for _, name in ipairs(self.SectionOrder) do
		local section = self.Sections[name]
		visit(if section.Kind == "object" then section.Fields else section.ItemFields, name, section.ClassName)
	end
	return rows
end

return Registry
