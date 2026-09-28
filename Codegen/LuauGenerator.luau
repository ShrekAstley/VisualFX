--[[
	VisualFX.Codegen.LuauGenerator

	Turns a configuration into readable, deterministic Luau.

	  local code = VisualFX:GenerateCode()                                  -- current scene
	  local code = VisualFX:GenerateCode(config, { Template = "LocalScript" })

	Options:
	  Template      "Script" (default) | "LocalScript" | "Module" | "Transition"
	  RequirePath   expression for the runtime (default game:GetService("ReplicatedStorage").VisualFX)
	  ConfigName    variable name (default "Configuration")
	  Comments      section comments (default true)
	  OmitTemplateDefaults  drop particle values equal to their template defaults (default true)
	  Duration, Easing      for the Transition template
	  Quality       emit VisualFX:SetQuality(<level>) before applying

	Output properties:
	  * keys are emitted in canonical order, so identical configurations
	    always produce identical text;
	  * Roblox values use their idiomatic constructors (Color3.fromRGB,
	    NumberSequence.new, Enum.X.Y, ...);
	  * private/internal keys are never emitted; nothing is timestamped.
]]

local Root = script.Parent.Parent
local Util = require(Root.Core.Util)
local Values = require(Root.Core.Values)
local Config = require(Root.Core.Config)
local Templates = require(script.Parent.Templates)

local LuauGenerator = {}

LuauGenerator.DEFAULT_REQUIRE = 'game:GetService("ReplicatedStorage").VisualFX'

local RESERVED = {
	["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true, ["end"] = true,
	["false"] = true, ["for"] = true, ["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
	["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true, ["return"] = true, ["then"] = true,
	["true"] = true, ["until"] = true, ["while"] = true, ["continue"] = true, ["export"] = true, ["type"] = true,
}

local function formatNumber(value: number): string
	return Util.formatNumber(Util.round(value, 6))
end

local function isByte(channel: number): (boolean, number)
	local scaled = channel * 255
	local rounded = math.floor(scaled + 0.5)
	return math.abs(scaled - rounded) < 1e-3, rounded
end

local function formatColor(color: Color3): string
	local okR, r = isByte(color.R)
	local okG, g = isByte(color.G)
	local okB, b = isByte(color.B)
	if okR and okG and okB then
		return string.format("Color3.fromRGB(%d, %d, %d)", r, g, b)
	end
	return string.format("Color3.new(%s, %s, %s)", formatNumber(color.R), formatNumber(color.G), formatNumber(color.B))
end

local function formatKey(key: any): string
	if typeof(key) == "string" and string.match(key, "^[%a_][%w_]*$") and not RESERVED[key] then
		return key
	end
	if typeof(key) == "number" then
		return "[" .. formatNumber(key) .. "]"
	end
	return "[" .. string.format("%q", tostring(key)) .. "]"
end

-- Luau literal for a single value (Roblox datatypes included).
function LuauGenerator.FormatValue(value: any, indent: number?): string
	local depth = indent or 0
	local kind = typeof(value)
	if kind == "nil" then
		return "nil"
	elseif kind == "boolean" then
		return if value then "true" else "false"
	elseif kind == "number" then
		return formatNumber(value)
	elseif kind == "string" then
		return string.format("%q", value)
	elseif kind == "Color3" then
		return formatColor(value)
	elseif kind == "Vector3" then
		return string.format("Vector3.new(%s, %s, %s)", formatNumber(value.X), formatNumber(value.Y), formatNumber(value.Z))
	elseif kind == "Vector2" then
		return string.format("Vector2.new(%s, %s)", formatNumber(value.X), formatNumber(value.Y))
	elseif kind == "NumberRange" then
		if Values.equal(value.Min, value.Max) then
			return string.format("NumberRange.new(%s)", formatNumber(value.Min))
		end
		return string.format("NumberRange.new(%s, %s)", formatNumber(value.Min), formatNumber(value.Max))
	elseif kind == "NumberSequence" then
		local keypoints = value.Keypoints
		local noEnvelope = true
		for _, keypoint in ipairs(keypoints) do
			if keypoint.Envelope ~= 0 then
				noEnvelope = false
			end
		end
		if noEnvelope and #keypoints == 2 and keypoints[1].Time == 0 and keypoints[2].Time == 1 then
			if Values.equal(keypoints[1].Value, keypoints[2].Value) then
				return string.format("NumberSequence.new(%s)", formatNumber(keypoints[1].Value))
			end
			return string.format("NumberSequence.new(%s, %s)", formatNumber(keypoints[1].Value), formatNumber(keypoints[2].Value))
		end
		local parts = {}
		for _, keypoint in ipairs(keypoints) do
			if keypoint.Envelope ~= 0 then
				table.insert(parts, string.format("NumberSequenceKeypoint.new(%s, %s, %s)", formatNumber(keypoint.Time), formatNumber(keypoint.Value), formatNumber(keypoint.Envelope)))
			else
				table.insert(parts, string.format("NumberSequenceKeypoint.new(%s, %s)", formatNumber(keypoint.Time), formatNumber(keypoint.Value)))
			end
		end
		return "NumberSequence.new({ " .. table.concat(parts, ", ") .. " })"
	elseif kind == "ColorSequence" then
		local keypoints = value.Keypoints
		if #keypoints == 2 and keypoints[1].Time == 0 and keypoints[2].Time == 1 then
			if Values.equal(keypoints[1].Value, keypoints[2].Value) then
				return string.format("ColorSequence.new(%s)", formatColor(keypoints[1].Value))
			end
			return string.format("ColorSequence.new(%s, %s)", formatColor(keypoints[1].Value), formatColor(keypoints[2].Value))
		end
		local parts = {}
		for _, keypoint in ipairs(keypoints) do
			table.insert(parts, string.format("ColorSequenceKeypoint.new(%s, %s)", formatNumber(keypoint.Time), formatColor(keypoint.Value)))
		end
		return "ColorSequence.new({ " .. table.concat(parts, ", ") .. " })"
	elseif kind == "EnumItem" then
		return string.format("Enum.%s.%s", tostring(value.EnumType), value.Name)
	elseif kind == "table" then
		if next(value) == nil then
			return "{}"
		end
		if Util.isArray(value) then
			local simple = true
			for _, item in ipairs(value) do
				if typeof(item) == "table" then
					simple = false
				end
			end
			local parts = {}
			for _, item in ipairs(value) do
				table.insert(parts, LuauGenerator.FormatValue(item, depth + 1))
			end
			if simple then
				return "{ " .. table.concat(parts, ", ") .. " }"
			end
			local pad = string.rep("\t", depth + 1)
			return "{\n" .. pad .. table.concat(parts, ",\n" .. pad) .. ",\n" .. string.rep("\t", depth) .. "}"
		end
		local pad = string.rep("\t", depth + 1)
		local lines = { "{" }
		for _, key in ipairs(Util.sortedKeys(value)) do
			if not (typeof(key) == "string" and string.sub(key, 1, 1) == "_") then
				table.insert(lines, pad .. formatKey(key) .. " = " .. LuauGenerator.FormatValue(value[key], depth + 1) .. ",")
			end
		end
		table.insert(lines, string.rep("\t", depth) .. "}")
		return table.concat(lines, "\n")
	end
	error("cannot generate Luau for value of type " .. kind)
end

-- Removes particle values equal to their template defaults.
local function trimParticles(particles, registry)
	if not registry or typeof(particles) ~= "table" then
		return particles
	end
	local result = {}
	for _, name in ipairs(Util.sortedKeys(particles)) do
		local system = particles[name]
		local templateName = system.Template or name
		local template = registry:FindParticleTemplate(templateName)
		if template and template.Defaults then
			local trimmed = {}
			for key, value in pairs(system) do
				local default = template.Defaults[key]
				if default == nil or not Values.equal(default, value) then
					trimmed[key] = value
				end
			end
			if system.Template then
				trimmed.Template = system.Template
			end
			result[name] = trimmed
		else
			result[name] = system
		end
	end
	return result
end

--[[
	Renders the configuration table with section comments, in canonical order.
]]
function LuauGenerator.FormatConfiguration(config: { [string]: any }, options: { [string]: any }?, registry): string
	local opts = options or {}
	local comments = opts.Comments ~= false
	local lines = { "{" }
	for _, key in ipairs(Util.sortedKeys(config)) do
		if typeof(key) == "string" and string.sub(key, 1, 1) == "_" then
			continue
		end
		local value = config[key]
		if key == "Particles" and opts.OmitTemplateDefaults ~= false then
			value = trimParticles(value, registry)
		elseif key == "Weather" and typeof(value) == "table" and typeof(value.Particles) == "table" and opts.OmitTemplateDefaults ~= false then
			value = Util.shallowCopy(value)
			value.Particles = trimParticles(value.Particles, registry)
		end
		if comments and registry then
			local section = registry:GetSection(key)
			if section and section.Description then
				if #lines > 1 then
					table.insert(lines, "")
				end
				table.insert(lines, "\t-- " .. section.Description)
			end
		end
		table.insert(lines, "\t" .. formatKey(key) .. " = " .. LuauGenerator.FormatValue(value, 1) .. ",")
	end
	table.insert(lines, "}")
	return table.concat(lines, "\n")
end

local function header(config, templateName: string, comments: boolean): string
	local metadata = config.Metadata or {}
	local lines = {
		"--[[",
		"\tGenerated by VisualFX Studio (" .. templateName .. ").",
	}
	if metadata.Name then
		table.insert(lines, "\tScene: " .. metadata.Name)
	end
	if comments and metadata.Description then
		table.insert(lines, "\t" .. metadata.Description)
	end
	table.insert(lines, "\tConfiguration version: " .. tostring(config.Version or Config.CURRENT_VERSION))
	table.insert(lines, "\tRegenerate from the VisualFX Code panel or VisualFX:GenerateCode().")
	table.insert(lines, "]]")
	return table.concat(lines, "\n")
end

--[[
	Generates a complete script. Returns the source text.
]]
function LuauGenerator.Generate(configuration: { [string]: any }, options: { [string]: any }?, registry): string
	local opts = options or {}
	local templateName = opts.Template or "Script"
	local template = Templates[templateName]
	if typeof(template) ~= "string" then
		error(string.format("unknown code template '%s' (available: %s)", tostring(templateName), table.concat(Templates.Names, ", ")), 2)
	end
	local config = Util.deepCopy(configuration or {})
	config.Version = config.Version or Config.CURRENT_VERSION
	local configName = opts.ConfigName or "Configuration"
	assert(string.match(configName, "^[%a_][%w_]*$"), "ConfigName must be a valid identifier")
	local quality = ""
	if opts.Quality then
		quality = string.format("\nVisualFX:SetQuality(%q)\n", opts.Quality)
	end
	local source = Templates.Render(template, {
		HEADER = header(config, templateName, opts.Comments ~= false),
		REQUIRE = opts.RequirePath or LuauGenerator.DEFAULT_REQUIRE,
		CONFIG_NAME = configName,
		CONFIG = LuauGenerator.FormatConfiguration(config, opts, registry),
		QUALITY = quality,
		DURATION = formatNumber(opts.Duration or 5),
		EASING = opts.Easing or "Smooth",
	})
	return source
end

return LuauGenerator
