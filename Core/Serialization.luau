--[=[
	VisualFX.Core.Serialization

	Converts configurations containing Roblox datatypes into plain JSON-safe
	data and back, plus a deterministic JSON encoder/decoder.

	Roblox values are encoded as tagged objects so they survive any transport:

	  Color3          {"$type":"Color3","rgb":[190,205,220]}
	  Vector3         {"$type":"Vector3","xyz":[0,30,0]}
	  Vector2         {"$type":"Vector2","xy":[0,10]}
	  NumberRange     {"$type":"NumberRange","min":1,"max":2}
	  NumberSequence  {"$type":"NumberSequence","keypoints":[[0,0.1,0],[1,0.3,0]]}
	  ColorSequence   {"$type":"ColorSequence","keypoints":[[0,255,255,255],[1,0,0,0]]}
	  EnumItem        {"$type":"EnumItem","enum":"ParticleEmitterShape","name":"Box"}

	The JSON encoder sorts keys (priority keys first) and formats numbers with
	the shortest round-tripping representation, so the same configuration always
	produces byte-identical text. That makes exported files diffable.
]=]

local Util = require(script.Parent.Util)
local Values = require(script.Parent.Values)

local Serialization = {}

Serialization.FORMAT = "VisualFXConfig"

local function roundChannel(channel: number): number
	return Util.round(channel * 255, 3)
end

-- Encodes a single value. Plain tables are encoded recursively.
function Serialization:EncodeValue(value: any): any
	local kind = typeof(value)
	if kind == "nil" or kind == "boolean" or kind == "string" then
		return value
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error("cannot serialize non-finite number", 2)
		end
		return value
	elseif kind == "Color3" then
		return { ["$type"] = "Color3", rgb = { roundChannel(value.R), roundChannel(value.G), roundChannel(value.B) } }
	elseif kind == "Vector3" then
		return { ["$type"] = "Vector3", xyz = { Util.round(value.X, 4), Util.round(value.Y, 4), Util.round(value.Z, 4) } }
	elseif kind == "Vector2" then
		return { ["$type"] = "Vector2", xy = { Util.round(value.X, 4), Util.round(value.Y, 4) } }
	elseif kind == "NumberRange" then
		return { ["$type"] = "NumberRange", min = Util.round(value.Min, 5), max = Util.round(value.Max, 5) }
	elseif kind == "NumberSequence" then
		local keypoints = {}
		for _, keypoint in ipairs(value.Keypoints) do
			table.insert(keypoints, {
				Util.round(keypoint.Time, 5),
				Util.round(keypoint.Value, 5),
				Util.round(keypoint.Envelope, 5),
			})
		end
		return { ["$type"] = "NumberSequence", keypoints = keypoints }
	elseif kind == "ColorSequence" then
		local keypoints = {}
		for _, keypoint in ipairs(value.Keypoints) do
			local color = keypoint.Value
			table.insert(keypoints, {
				Util.round(keypoint.Time, 5),
				roundChannel(color.R),
				roundChannel(color.G),
				roundChannel(color.B),
			})
		end
		return { ["$type"] = "ColorSequence", keypoints = keypoints }
	elseif kind == "EnumItem" then
		return { ["$type"] = "EnumItem", enum = tostring(value.EnumType), name = value.Name }
	elseif kind == "table" then
		local result = {}
		for key, item in pairs(value) do
			if typeof(key) ~= "string" and typeof(key) ~= "number" then
				error("cannot serialize table key of type " .. typeof(key), 2)
			end
			result[key] = self:EncodeValue(item)
		end
		return result
	end
	error("cannot serialize value of type " .. kind, 2)
end

local function decodeTagged(data: { [string]: any }): (any, string?)
	local tag = data["$type"]
	if tag == "Color3" and typeof(data.rgb) == "table" then
		return Color3.fromRGB(data.rgb[1], data.rgb[2], data.rgb[3])
	elseif tag == "Vector3" and typeof(data.xyz) == "table" then
		return Vector3.new(data.xyz[1], data.xyz[2], data.xyz[3])
	elseif tag == "Vector2" and typeof(data.xy) == "table" then
		return Vector2.new(data.xy[1], data.xy[2])
	elseif tag == "NumberRange" and typeof(data.min) == "number" then
		return NumberRange.new(data.min, data.max or data.min)
	elseif tag == "NumberSequence" and typeof(data.keypoints) == "table" then
		local keypoints = {}
		for _, keypoint in ipairs(data.keypoints) do
			table.insert(keypoints, NumberSequenceKeypoint.new(keypoint[1], keypoint[2], keypoint[3] or 0))
		end
		local ok, result = pcall(NumberSequence.new, keypoints)
		if ok then
			return result
		end
		return nil, "invalid NumberSequence keypoints"
	elseif tag == "ColorSequence" and typeof(data.keypoints) == "table" then
		local keypoints = {}
		for _, keypoint in ipairs(data.keypoints) do
			table.insert(keypoints, ColorSequenceKeypoint.new(keypoint[1], Color3.fromRGB(keypoint[2], keypoint[3], keypoint[4])))
		end
		local ok, result = pcall(ColorSequence.new, keypoints)
		if ok then
			return result
		end
		return nil, "invalid ColorSequence keypoints"
	elseif tag == "EnumItem" and typeof(data.enum) == "string" and typeof(data.name) == "string" then
		local item = Values.getEnumItem(data.enum, data.name)
		if item then
			return item
		end
		return nil, string.format("Enum.%s.%s is not supported by this engine version", data.enum, data.name)
	end
	return nil, "unknown or malformed $type '" .. tostring(tag) .. "'"
end

--[[
	Decodes plain data back into Roblox values. Unknown tagged values are
	reported as warnings and dropped instead of failing the whole document.
]]
function Serialization:DecodeValue(data: any, warnings: { string }?, path: string?): any
	if typeof(data) ~= "table" then
		return data
	end
	if data["$type"] ~= nil then
		local value, problem = decodeTagged(data)
		if problem and warnings then
			table.insert(warnings, string.format("%s: %s", path or "<root>", problem))
		end
		return value
	end
	local result = {}
	for key, item in pairs(data) do
		local childPath = if path then path .. "." .. tostring(key) else tostring(key)
		result[key] = self:DecodeValue(item, warnings, childPath)
	end
	return result
end

---------------------------------------------------------------------------
-- JSON
---------------------------------------------------------------------------

local escapes = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local function encodeString(text: string): string
	return '"'
		.. string.gsub(text, '[%c"\\]', function(char)
			return escapes[char] or string.format("\\u%04x", string.byte(char))
		end)
		.. '"'
end

local function isScalarArray(list: { any }): boolean
	for _, item in ipairs(list) do
		local kind = typeof(item)
		if kind == "table" then
			if not isScalarArray(item) or #item == 0 then
				return false
			end
		end
	end
	return true
end

local function encodeJSON(value: any, indent: string, depth: number, pretty: boolean): string
	local kind = typeof(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return if value then "true" else "false"
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error("JSON cannot represent non-finite numbers")
		end
		return Util.formatNumber(value)
	elseif kind == "string" then
		return encodeString(value)
	elseif kind == "table" then
		local newline = if pretty then "\n" else ""
		local pad = if pretty then string.rep(indent, depth + 1) else ""
		local closePad = if pretty then string.rep(indent, depth) else ""
		local colon = if pretty then ": " else ":"
		if Util.isArray(value) then
			local parts = {}
			for _, item in ipairs(value) do
				table.insert(parts, encodeJSON(item, indent, depth + 1, pretty))
			end
			if not pretty or isScalarArray(value) then
				return "[" .. table.concat(parts, if pretty then ", " else ",") .. "]"
			end
			return "[" .. newline .. pad .. table.concat(parts, "," .. newline .. pad) .. newline .. closePad .. "]"
		end
		if next(value) == nil then
			return "{}"
		end
		local parts = {}
		for _, key in ipairs(Util.sortedKeys(value)) do
			table.insert(parts, encodeString(tostring(key)) .. colon .. encodeJSON(value[key], indent, depth + 1, pretty))
		end
		return "{" .. newline .. pad .. table.concat(parts, "," .. newline .. pad) .. newline .. closePad .. "}"
	end
	error("JSON cannot represent value of type " .. kind)
end

-- Deterministic JSON. Pass pretty = false for a compact single line.
function Serialization:ToJSON(value: any, pretty: boolean?): string
	return encodeJSON(value, "  ", 0, pretty ~= false)
end

local function decodeError(text: string, position: number, message: string)
	local line = 1
	for _ in string.gmatch(string.sub(text, 1, position), "\n") do
		line += 1
	end
	error(string.format("JSON parse error at line %d (character %d): %s", line, position, message), 0)
end

local function skipWhitespace(text: string, position: number): number
	local _, last = string.find(text, "^[ \n\r\t]*", position)
	return (last :: number) + 1
end

local parseValue

local function parseString(text: string, position: number): (string, number)
	local buffer = {}
	local index = position + 1
	while true do
		local char = string.sub(text, index, index)
		if char == "" then
			decodeError(text, index, "unterminated string")
		elseif char == '"' then
			return table.concat(buffer), index + 1
		elseif char == "\\" then
			local escape = string.sub(text, index + 1, index + 1)
			if escape == "u" then
				local hex = string.sub(text, index + 2, index + 5)
				local code = tonumber(hex, 16)
				if not code then
					decodeError(text, index, "invalid unicode escape")
				end
				table.insert(buffer, utf8.char(code :: number))
				index += 6
			else
				local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
				local replacement = map[escape]
				if not replacement then
					decodeError(text, index, "invalid escape '\\" .. escape .. "'")
				end
				table.insert(buffer, replacement)
				index += 2
			end
		else
			table.insert(buffer, char)
			index += 1
		end
	end
end

function parseValue(text: string, position: number): (any, number)
	position = skipWhitespace(text, position)
	local char = string.sub(text, position, position)
	if char == "{" then
		local result = {}
		position = skipWhitespace(text, position + 1)
		if string.sub(text, position, position) == "}" then
			return result, position + 1
		end
		while true do
			position = skipWhitespace(text, position)
			if string.sub(text, position, position) ~= '"' then
				decodeError(text, position, "expected string key")
			end
			local key
			key, position = parseString(text, position)
			position = skipWhitespace(text, position)
			if string.sub(text, position, position) ~= ":" then
				decodeError(text, position, "expected ':'")
			end
			local item
			item, position = parseValue(text, position + 1)
			result[key] = item
			position = skipWhitespace(text, position)
			local separator = string.sub(text, position, position)
			if separator == "}" then
				return result, position + 1
			elseif separator ~= "," then
				decodeError(text, position, "expected ',' or '}'")
			end
			position += 1
		end
	elseif char == "[" then
		local result = {}
		position = skipWhitespace(text, position + 1)
		if string.sub(text, position, position) == "]" then
			return result, position + 1
		end
		while true do
			local item
			item, position = parseValue(text, position)
			table.insert(result, item)
			position = skipWhitespace(text, position)
			local separator = string.sub(text, position, position)
			if separator == "]" then
				return result, position + 1
			elseif separator ~= "," then
				decodeError(text, position, "expected ',' or ']'")
			end
			position += 1
		end
	elseif char == '"' then
		return parseString(text, position)
	elseif string.sub(text, position, position + 3) == "true" then
		return true, position + 4
	elseif string.sub(text, position, position + 4) == "false" then
		return false, position + 5
	elseif string.sub(text, position, position + 3) == "null" then
		return nil, position + 4
	else
		local numberText = string.match(text, "^-?%d+%.?%d*[eE]?[-+]?%d*", position)
		if numberText and numberText ~= "" then
			local number = tonumber(numberText)
			if number then
				return number, position + #numberText
			end
		end
		decodeError(text, position, "unexpected character '" .. char .. "'")
	end
	return nil, position
end

function Serialization:FromJSON(text: string): any
	if typeof(text) ~= "string" then
		error("expected JSON string, received " .. typeof(text), 0)
	end
	local value, position = parseValue(text, 1)
	position = skipWhitespace(text, position)
	if position <= #text then
		decodeError(text, position, "trailing characters")
	end
	return value
end

---------------------------------------------------------------------------
-- Configuration documents
---------------------------------------------------------------------------

--[[
	Serializes a configuration into a versioned document:
	{ Format = "VisualFXConfig", Version = n, Scene = { ... } }
]]
function Serialization:Serialize(configuration: { [string]: any }): { [string]: any }
	local scene = self:EncodeValue(configuration)
	return {
		Format = Serialization.FORMAT,
		Version = configuration.Version or 1,
		Scene = scene,
	}
end

function Serialization:Deserialize(document: any): ({ [string]: any }?, { string }, string?)
	local warnings = {}
	if typeof(document) == "string" then
		local ok, result = pcall(function()
			return self:FromJSON(document)
		end)
		if not ok then
			return nil, warnings, tostring(result)
		end
		document = result
	end
	if typeof(document) ~= "table" then
		return nil, warnings, "expected a VisualFXConfig document (table or JSON string), received " .. typeof(document)
	end
	local scene = document
	if document.Format ~= nil then
		if document.Format ~= Serialization.FORMAT then
			return nil, warnings, string.format("unknown document format '%s'", tostring(document.Format))
		end
		scene = document.Scene
		if typeof(scene) ~= "table" then
			return nil, warnings, "VisualFXConfig document has no Scene table"
		end
		if scene.Version == nil then
			scene.Version = document.Version
		end
	end
	return self:DecodeValue(scene, warnings), warnings, nil
end

-- Serialize straight to diffable JSON text.
function Serialization:Export(configuration: { [string]: any }, pretty: boolean?): string
	return self:ToJSON(self:Serialize(configuration), pretty)
end

return Serialization
