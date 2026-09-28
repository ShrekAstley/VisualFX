--[=[
	VisualFX.AI.Schema

	Machine-readable description of everything an agent can configure,
	generated from the live registries (so custom effects, weather types and
	particle templates registered at runtime are included automatically).

	  local schema = VisualFX:GetSchema()                 -- Lua table
	  local jsonSchema = Schema.ToJSONSchema(VisualFX)    -- JSON Schema (draft-07) table

	Roblox value encodings used in JSON (see Core/Serialization.luau):
	  Color3 {"$type":"Color3","rgb":[r,g,b]} | "#RRGGBB" | [r,g,b]
	  Vector3 {"$type":"Vector3","xyz":[x,y,z]} | [x,y,z]
	  NumberRange {"$type":"NumberRange","min":a,"max":b} | number | [a,b]
	  NumberSequence {"$type":"NumberSequence","keypoints":[[t,v,e],...]} | number | [v0,v1,...]
	  ColorSequence {"$type":"ColorSequence","keypoints":[[t,r,g,b],...]} | Color3 forms
	  EnumItem {"$type":"EnumItem","enum":"NormalId","name":"Top"} | "Top"
]=]

local Root = script.Parent.Parent
local Util = require(Root.Core.Util)
local Values = require(Root.Core.Values)
local Serialization = require(Root.Core.Serialization)

local Schema = {}

Schema.ValueEncodings = {
	Color3 = { Tagged = { ["$type"] = "Color3", rgb = { 190, 205, 220 } }, Shorthand = { "#BECDDC", "[190, 205, 220]" } },
	Vector3 = { Tagged = { ["$type"] = "Vector3", xyz = { 0, 30, 0 } }, Shorthand = { "[0, 30, 0]" } },
	Vector2 = { Tagged = { ["$type"] = "Vector2", xy = { 3, 3 } }, Shorthand = { "[3, 3]" } },
	NumberRange = { Tagged = { ["$type"] = "NumberRange", min = 1, max = 2 }, Shorthand = { "1.5", "[1, 2]" } },
	NumberSequence = { Tagged = { ["$type"] = "NumberSequence", keypoints = { { 0, 0.1, 0 }, { 1, 0.3, 0 } } }, Shorthand = { "0.2", "[0.1, 0.3]" } },
	ColorSequence = { Tagged = { ["$type"] = "ColorSequence", keypoints = { { 0, 255, 255, 255 }, { 1, 0, 0, 0 } } }, Shorthand = { "#FFFFFF", "[[255,255,255],[0,0,0]]" } },
	EnumItem = { Tagged = { ["$type"] = "EnumItem", enum = "NormalId", name = "Top" }, Shorthand = { "\"Top\"" } },
}

local function describeField(field)
	local entry = {
		Key = field.Key,
		Kind = field.Kind,
		Description = field.Description,
		Property = field.Property,
		ClassName = field.ClassName,
		Min = field.Min,
		Max = field.Max,
		SoftMax = field.SoftMax,
		SoftMin = field.SoftMin,
		Required = field.Required,
		Aliases = field.Aliases,
		Unit = field.Unit,
		Values = field.Values,
		Enum = field.Enum,
	}
	if field.Default ~= nil then
		local ok, encoded = pcall(function()
			return Serialization:EncodeValue(field.Default)
		end)
		if ok then
			entry.Default = encoded
		end
	end
	if field.Kind == "EnumItem" and field.Enum then
		entry.EnumItems = Values.enumItemNames(field.Enum)
	end
	if field.Kind == "object" then
		entry.Fields = {}
		for _, child in ipairs(field.Fields) do
			table.insert(entry.Fields, describeField(child))
		end
	elseif field.Kind == "map" then
		entry.ItemFields = {}
		for _, child in ipairs(field.ItemFields) do
			table.insert(entry.ItemFields, describeField(child))
		end
	end
	return entry
end

--[[
	Builds the full schema table. options.IncludePresets (default true).
]]
function Schema.Build(engine, options: { [string]: any }?)
	local opts = options or {}
	local registry = engine.Registry
	local sections = {}
	for _, name in ipairs(registry.SectionOrder) do
		local section = registry.Sections[name]
		local entry = {
			Name = name,
			Order = section.Order,
			Kind = section.Kind,
			Description = section.Description,
			ClassName = section.ClassName,
		}
		local fields = if section.Kind == "object" then section.Fields else section.ItemFields
		local list = {}
		for _, field in ipairs(fields) do
			table.insert(list, describeField(field))
		end
		if section.Kind == "object" then
			entry.Fields = list
		else
			entry.ItemFields = list
		end
		table.insert(sections, entry)
	end

	local weather = {}
	for _, name in ipairs(registry:ListWeather()) do
		local definition = registry.WeatherTypes[name]
		weather[name] = {
			Description = definition.Description,
			Category = definition.Category,
			Defaults = Serialization:EncodeValue(definition.Defaults or {}),
			Composition = require(Root.Runtime.Weather).DescribeComposition(definition),
		}
	end

	local templates = {}
	for _, name in ipairs(registry:ListParticleTemplates()) do
		local template = registry.ParticleTemplates[name]
		templates[name] = {
			Description = template.Description,
			Defaults = Serialization:EncodeValue(template.Defaults or {}),
		}
	end

	local effects = {}
	for _, name in ipairs(registry:ListEffects()) do
		local definition = registry.Effects[name]
		local fields = {}
		for _, field in ipairs(definition.Fields) do
			table.insert(fields, describeField(field))
		end
		effects[name] = { Category = definition.Category, Description = definition.Description, Fields = fields }
	end

	local schema = {
		Format = Serialization.FORMAT,
		ConfigVersion = engine.ConfigVersion or 1,
		RuntimeVersion = engine.Version,
		Sections = sections,
		MetaKeys = {
			Version = "integer configuration version (current: 1)",
			Metadata = "{ Name, Author, Description, Category, Tags }",
			Inherits = "list of preset names merged left to right before this configuration",
		},
		MergeRules = {
			"Scalars and Roblox values in an overlay replace the base value.",
			"Dictionaries merge recursively, key by key.",
			"Arrays are replaced as a whole.",
			"The string \"$remove\" deletes a key.",
			"Keys are processed in sorted order.",
		},
		WeatherTypes = weather,
		ParticleTemplates = templates,
		CustomEffects = effects,
		QualityLevels = { "Low", "Medium", "High", "Ultra", "Custom" },
		ValueEncodings = Schema.ValueEncodings,
		Commands = engine.Commands:Catalog(),
		DirectorVocabulary = engine.Director:Vocabulary(),
	}
	if opts.IncludePresets ~= false then
		schema.Presets = engine:ListPresets()
	end
	return schema
end

---------------------------------------------------------------------------
-- JSON Schema export
---------------------------------------------------------------------------

local COLOR3 = {
	oneOf = {
		{ type = "object", required = { "$type", "rgb" }, properties = { ["$type"] = { const = "Color3" }, rgb = { type = "array", items = { type = "number", minimum = 0, maximum = 255 }, minItems = 3, maxItems = 3 } } },
		{ type = "string", pattern = "^#?[0-9A-Fa-f]{6}$" },
		{ type = "array", items = { type = "number", minimum = 0, maximum = 255 }, minItems = 3, maxItems = 3 },
	},
}

local function tagged(tag: string, key: string, count: number?)
	local items = { type = "number" }
	local property = if count
		then { type = "array", items = items, minItems = count, maxItems = count }
		else { type = "array" }
	return {
		type = "object",
		required = { "$type", key },
		properties = { ["$type"] = { const = tag }, [key] = property },
	}
end

local function kindToJSON(field)
	local kind = field.Kind
	local node
	if kind == "number" or kind == "integer" then
		node = { type = if kind == "integer" then "integer" else "number", minimum = field.Min, maximum = field.Max }
	elseif kind == "boolean" then
		node = { type = "boolean" }
	elseif kind == "string" then
		node = { type = "string" }
		if field.Values then
			node.enum = field.Values
		end
	elseif kind == "Color3" then
		node = Util.deepCopy(COLOR3)
	elseif kind == "Vector3" then
		node = { oneOf = { tagged("Vector3", "xyz", 3), { type = "array", items = { type = "number" }, minItems = 3, maxItems = 3 } } }
	elseif kind == "Vector2" then
		node = { oneOf = { tagged("Vector2", "xy", 2), { type = "array", items = { type = "number" }, minItems = 2, maxItems = 2 } } }
	elseif kind == "NumberRange" then
		node = {
			oneOf = {
				{ type = "object", required = { "$type", "min", "max" }, properties = { ["$type"] = { const = "NumberRange" }, min = { type = "number" }, max = { type = "number" } } },
				{ type = "number" },
				{ type = "array", items = { type = "number" }, minItems = 2, maxItems = 2 },
			},
		}
	elseif kind == "NumberSequence" then
		node = { oneOf = { tagged("NumberSequence", "keypoints"), { type = "number" }, { type = "array", items = { type = "number" }, minItems = 2 } } }
	elseif kind == "ColorSequence" then
		node = { oneOf = { tagged("ColorSequence", "keypoints"), Util.deepCopy(COLOR3) } }
	elseif kind == "EnumItem" then
		node = {
			oneOf = {
				{ type = "string", enum = Values.enumItemNames(field.Enum or "") },
				{ type = "object", required = { "$type", "enum", "name" }, properties = { ["$type"] = { const = "EnumItem" }, enum = { const = field.Enum }, name = { type = "string" } } },
			},
		}
	elseif kind == "array" then
		node = { type = "array", items = if field.ItemKind then { type = field.ItemKind } else {} }
	elseif kind == "object" then
		node = { type = "object", additionalProperties = false, properties = {} }
		for _, child in ipairs(field.Fields) do
			node.properties[child.Key] = kindToJSON(child)
		end
	elseif kind == "map" then
		local item = { type = "object", properties = {} }
		for _, child in ipairs(field.ItemFields) do
			item.properties[child.Key] = kindToJSON(child)
		end
		node = { type = "object", additionalProperties = item }
	else
		node = {}
	end
	if field.Description then
		node.description = field.Description
	end
	return node
end

-- JSON Schema (draft-07) for a VisualFX configuration.
function Schema.ToJSONSchema(engine)
	local registry = engine.Registry
	local properties = {
		Version = { type = "integer", minimum = 0, description = "Configuration schema version." },
		Metadata = {
			type = "object",
			properties = {
				Name = { type = "string" },
				Author = { type = "string" },
				Description = { type = "string" },
				Category = { type = "string" },
				Tags = { type = "array", items = { type = "string" } },
			},
		},
		Inherits = { type = "array", items = { type = "string" }, description = "Preset names merged left to right." },
	}
	for _, name in ipairs(registry.SectionOrder) do
		local section = registry.Sections[name]
		local node = kindToJSON({
			Kind = section.Kind,
			Fields = section.Fields,
			ItemFields = section.ItemFields,
			Description = section.Description,
		})
		if name == "Weather" then
			node.properties.Type = { type = "string", enum = registry:ListWeather(), description = "Weather type." }
		end
		if name == "Effects" then
			node.additionalProperties.additionalProperties = true
		end
		properties[name] = node
	end
	return {
		["$schema"] = "http://json-schema.org/draft-07/schema#",
		["$id"] = "urn:visualfx:config:v1",
		title = "VisualFX configuration",
		description = "Canonical, versioned VisualFX scene configuration. Roblox values use the tagged encodings in Core/Serialization.luau.",
		type = "object",
		additionalProperties = false,
		properties = properties,
	}
end

return Schema
