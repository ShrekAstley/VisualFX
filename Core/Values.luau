--[[
	VisualFX.Core.Values

	Knowledge about Roblox value types in one place:
	  * kind detection (typeof based, never type())
	  * tolerant equality (engine properties are stored as float32 / seconds)
	  * interpolation, including NumberRange, NumberSequence and ColorSequence
	  * coercion from AI-friendly forms ("#RRGGBB", {x, y, z}, enum names, ...)
]]

local Util = require(script.Parent.Util)

local Values = {}

Values.DEFAULT_EPSILON = 1e-4
Values.MAX_SEQUENCE_KEYPOINTS = 20

Values.InterpolableKinds = {
	number = true,
	Color3 = true,
	Vector3 = true,
	Vector2 = true,
	NumberRange = true,
	NumberSequence = true,
	ColorSequence = true,
}

function Values.kindOf(value: any): string
	return typeof(value)
end

-- Relative tolerance by default; absolute when a field supplies its own epsilon.
local absoluteMode = false

local function numberEqual(a: number, b: number, epsilon: number): boolean
	if a == b then
		return true
	end
	local scale = if absoluteMode then 1 else math.max(1, math.abs(a), math.abs(b))
	return math.abs(a - b) <= epsilon * scale
end

local function colorEqual(a: Color3, b: Color3, epsilon: number): boolean
	return numberEqual(a.R, b.R, epsilon) and numberEqual(a.G, b.G, epsilon) and numberEqual(a.B, b.B, epsilon)
end

local compare

--[[
	Value equality with a tolerance for floating point noise introduced by the
	engine (float32 storage). Tables are compared structurally.
	Without `epsilon` the tolerance is relative (1e-4 of the magnitude);
	an explicit `epsilon` is an absolute tolerance (e.g. ClockTime's one second).
]]
function Values.equal(a: any, b: any, epsilon: number?): boolean
	local previous = absoluteMode
	absoluteMode = epsilon ~= nil
	local result = compare(a, b, epsilon or Values.DEFAULT_EPSILON)
	absoluteMode = previous
	return result
end

function compare(a: any, b: any, eps: number): boolean
	local kindA, kindB = typeof(a), typeof(b)
	if kindA ~= kindB then
		return false
	end
	if kindA == "number" then
		return numberEqual(a, b, eps)
	elseif kindA == "Color3" then
		return colorEqual(a, b, eps)
	elseif kindA == "Vector3" then
		return numberEqual(a.X, b.X, eps) and numberEqual(a.Y, b.Y, eps) and numberEqual(a.Z, b.Z, eps)
	elseif kindA == "Vector2" then
		return numberEqual(a.X, b.X, eps) and numberEqual(a.Y, b.Y, eps)
	elseif kindA == "NumberRange" then
		return numberEqual(a.Min, b.Min, eps) and numberEqual(a.Max, b.Max, eps)
	elseif kindA == "NumberSequence" then
		local ka, kb = a.Keypoints, b.Keypoints
		if #ka ~= #kb then
			return false
		end
		for i = 1, #ka do
			if
				not numberEqual(ka[i].Time, kb[i].Time, eps)
				or not numberEqual(ka[i].Value, kb[i].Value, eps)
				or not numberEqual(ka[i].Envelope, kb[i].Envelope, eps)
			then
				return false
			end
		end
		return true
	elseif kindA == "ColorSequence" then
		local ka, kb = a.Keypoints, b.Keypoints
		if #ka ~= #kb then
			return false
		end
		for i = 1, #ka do
			if not numberEqual(ka[i].Time, kb[i].Time, eps) or not colorEqual(ka[i].Value, kb[i].Value, eps) then
				return false
			end
		end
		return true
	elseif kindA == "table" then
		for key, value in pairs(a) do
			if not compare(value, b[key], eps) then
				return false
			end
		end
		for key in pairs(b) do
			if a[key] == nil then
				return false
			end
		end
		return true
	end
	return a == b
end

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Evaluates a NumberSequence at time t (0..1). Returns value, envelope.
function Values.evaluateNumberSequence(sequence: NumberSequence, t: number): (number, number)
	local keypoints = sequence.Keypoints
	if t <= keypoints[1].Time then
		return keypoints[1].Value, keypoints[1].Envelope
	end
	for i = 1, #keypoints - 1 do
		local current, following = keypoints[i], keypoints[i + 1]
		if t >= current.Time and t <= following.Time then
			local span = following.Time - current.Time
			local alpha = if span > 0 then (t - current.Time) / span else 0
			return lerpNumber(current.Value, following.Value, alpha), lerpNumber(current.Envelope, following.Envelope, alpha)
		end
	end
	local last = keypoints[#keypoints]
	return last.Value, last.Envelope
end

function Values.evaluateColorSequence(sequence: ColorSequence, t: number): Color3
	local keypoints = sequence.Keypoints
	if t <= keypoints[1].Time then
		return keypoints[1].Value
	end
	for i = 1, #keypoints - 1 do
		local current, following = keypoints[i], keypoints[i + 1]
		if t >= current.Time and t <= following.Time then
			local span = following.Time - current.Time
			local alpha = if span > 0 then (t - current.Time) / span else 0
			return current.Value:Lerp(following.Value, alpha)
		end
	end
	return keypoints[#keypoints].Value
end

-- Union of keypoint times of two sequences, capped at the engine limit of 20.
local function mergedTimes(a, b): { number }
	local seen, times = {}, {}
	for _, sequence in ipairs({ a, b }) do
		for _, keypoint in ipairs(sequence.Keypoints) do
			local key = Util.round(keypoint.Time, 6)
			if not seen[key] then
				seen[key] = true
				table.insert(times, key)
			end
		end
	end
	table.sort(times)
	if #times > Values.MAX_SEQUENCE_KEYPOINTS then
		times = {}
		for i = 0, Values.MAX_SEQUENCE_KEYPOINTS - 1 do
			table.insert(times, i / (Values.MAX_SEQUENCE_KEYPOINTS - 1))
		end
	end
	times[1] = 0
	times[#times] = 1
	return times
end

--[[
	Interpolates between two values of the same kind. Non-interpolable kinds
	(booleans, strings, enums) switch at t >= 1.
]]
function Values.lerp(a: any, b: any, t: number): any
	local kind = typeof(b)
	if typeof(a) ~= kind then
		return if t >= 1 then b else a
	end
	if t <= 0 then
		return a
	elseif t >= 1 then
		return b
	end
	if kind == "number" then
		return lerpNumber(a, b, t)
	elseif kind == "Color3" or kind == "Vector3" or kind == "Vector2" then
		return a:Lerp(b, t)
	elseif kind == "NumberRange" then
		local low = lerpNumber(a.Min, b.Min, t)
		local high = lerpNumber(a.Max, b.Max, t)
		return NumberRange.new(math.min(low, high), math.max(low, high))
	elseif kind == "NumberSequence" then
		local keypoints = {}
		for _, time in ipairs(mergedTimes(a, b)) do
			local va, ea = Values.evaluateNumberSequence(a, time)
			local vb, eb = Values.evaluateNumberSequence(b, time)
			table.insert(keypoints, NumberSequenceKeypoint.new(time, lerpNumber(va, vb, t), math.max(0, lerpNumber(ea, eb, t))))
		end
		return NumberSequence.new(keypoints)
	elseif kind == "ColorSequence" then
		local keypoints = {}
		for _, time in ipairs(mergedTimes(a, b)) do
			local ca = Values.evaluateColorSequence(a, time)
			local cb = Values.evaluateColorSequence(b, time)
			table.insert(keypoints, ColorSequenceKeypoint.new(time, ca:Lerp(cb, t)))
		end
		return ColorSequence.new(keypoints)
	end
	return if t >= 1 then b else a
end

-- Multiplies every value of a NumberSequence/NumberRange/number by a factor.
function Values.scale(value: any, factor: number): any
	local kind = typeof(value)
	if kind == "number" then
		return value * factor
	elseif kind == "NumberRange" then
		return NumberRange.new(value.Min * factor, value.Max * factor)
	elseif kind == "NumberSequence" then
		local keypoints = {}
		for _, keypoint in ipairs(value.Keypoints) do
			table.insert(
				keypoints,
				NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value * factor, keypoint.Envelope * math.abs(factor))
			)
		end
		return NumberSequence.new(keypoints)
	end
	return value
end

-- Average value of a NumberRange, NumberSequence or number (used for estimates).
function Values.average(value: any): number
	local kind = typeof(value)
	if kind == "number" then
		return value
	elseif kind == "NumberRange" then
		return (value.Min + value.Max) / 2
	elseif kind == "NumberSequence" then
		local total = 0
		for _, keypoint in ipairs(value.Keypoints) do
			total += keypoint.Value
		end
		return total / #value.Keypoints
	end
	return 0
end

local function parseHex(text: string): Color3?
	local hex = string.match(text, "^#?(%x%x%x%x%x%x)$")
	if not hex then
		return nil
	end
	return Color3.fromRGB(
		tonumber(string.sub(hex, 1, 2), 16) :: number,
		tonumber(string.sub(hex, 3, 4), 16) :: number,
		tonumber(string.sub(hex, 5, 6), 16) :: number
	)
end

local function allNumbers(list: { any }, count: number): boolean
	if #list ~= count then
		return false
	end
	for i = 1, count do
		if typeof(list[i]) ~= "number" then
			return false
		end
	end
	return true
end

-- Resolves an enum type by name, returning nil when the engine does not have it.
function Values.getEnum(enumName: string): any
	local ok, enumType = pcall(function()
		return (Enum :: any)[enumName]
	end)
	if ok then
		return enumType
	end
	return nil
end

function Values.getEnumItem(enumName: string, itemName: string): EnumItem?
	local enumType = Values.getEnum(enumName)
	if not enumType then
		return nil
	end
	local ok, item = pcall(function()
		return enumType[itemName]
	end)
	if ok and typeof(item) == "EnumItem" then
		return item
	end
	-- Case-insensitive fallback ("box" -> Box).
	local okItems, items = pcall(function()
		return enumType:GetEnumItems()
	end)
	if okItems then
		for _, candidate in ipairs(items) do
			if string.lower(candidate.Name) == string.lower(itemName) then
				return candidate
			end
		end
	end
	return nil
end

function Values.enumItemNames(enumName: string): { string }
	local enumType = Values.getEnum(enumName)
	local names = {}
	if enumType then
		local ok, items = pcall(function()
			return enumType:GetEnumItems()
		end)
		if ok then
			for _, item in ipairs(items) do
				table.insert(names, item.Name)
			end
		end
	end
	table.sort(names)
	return names
end

--[[
	Converts friendly input into the Roblox value kind a property expects.
	Returns (value, nil) on success or (nil, reason) when conversion is impossible.
	Accepted conversions are deliberately conservative: a string is never
	silently turned into a number.
]]
function Values.coerce(value: any, kind: string, enumName: string?): (any, string?)
	local actual = typeof(value)
	if kind == "any" or actual == kind then
		if kind == "EnumItem" and enumName and tostring(value.EnumType) ~= enumName then
			return nil, string.format("expected Enum.%s item", enumName)
		end
		return value, nil
	end

	if kind == "number" then
		return nil, nil
	elseif kind == "integer" then
		if actual == "number" and value % 1 == 0 then
			return value, nil
		end
		return nil, nil
	elseif kind == "Color3" then
		if actual == "string" then
			local color = parseHex(value)
			if color then
				return color, nil
			end
		elseif actual == "table" then
			if allNumbers(value, 3) then
				return Color3.fromRGB(value[1], value[2], value[3]), nil
			elseif typeof(value.R) == "number" and typeof(value.G) == "number" and typeof(value.B) == "number" then
				return Color3.fromRGB(value.R, value.G, value.B), nil
			end
		end
	elseif kind == "Vector3" then
		if actual == "table" and allNumbers(value, 3) then
			return Vector3.new(value[1], value[2], value[3]), nil
		elseif actual == "number" then
			return Vector3.new(value, value, value), nil
		end
	elseif kind == "Vector2" then
		if actual == "table" and allNumbers(value, 2) then
			return Vector2.new(value[1], value[2]), nil
		elseif actual == "number" then
			return Vector2.new(value, value), nil
		end
	elseif kind == "NumberRange" then
		if actual == "number" then
			return NumberRange.new(value), nil
		elseif actual == "table" and allNumbers(value, 2) then
			return NumberRange.new(math.min(value[1], value[2]), math.max(value[1], value[2])), nil
		end
	elseif kind == "NumberSequence" then
		if actual == "number" then
			return NumberSequence.new(value), nil
		elseif actual == "NumberRange" then
			return NumberSequence.new(value.Min, value.Max), nil
		elseif actual == "table" and #value >= 2 then
			if allNumbers(value, #value) then
				local keypoints = {}
				for index, item in ipairs(value) do
					table.insert(keypoints, NumberSequenceKeypoint.new((index - 1) / (#value - 1), item))
				end
				return NumberSequence.new(keypoints), nil
			end
		end
	elseif kind == "ColorSequence" then
		if actual == "Color3" then
			return ColorSequence.new(value), nil
		elseif actual == "string" then
			local color = parseHex(value)
			if color then
				return ColorSequence.new(color), nil
			end
		elseif actual == "table" and #value >= 2 then
			local keypoints = {}
			for index, item in ipairs(value) do
				local color = Values.coerce(item, "Color3")
				if not color then
					return nil, nil
				end
				table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (#value - 1), color))
			end
			return ColorSequence.new(keypoints), nil
		end
	elseif kind == "EnumItem" and enumName then
		if actual == "string" then
			local item = Values.getEnumItem(enumName, value)
			if item then
				return item, nil
			end
			return nil, string.format("'%s' is not a member of Enum.%s", value, enumName)
		elseif actual == "number" then
			local enumType = Values.getEnum(enumName)
			if enumType then
				local ok, items = pcall(function()
					return enumType:GetEnumItems()
				end)
				if ok then
					for _, item in ipairs(items) do
						if item.Value == value then
							return item, nil
						end
					end
				end
			end
		end
	elseif kind == "boolean" or kind == "string" then
		return nil, nil
	end
	return nil, nil
end

-- Human readable, deterministic description of a value (used in diffs and errors).
function Values.describe(value: any): string
	local kind = typeof(value)
	if kind == "number" then
		return Util.formatNumber(Util.round(value, 4))
	elseif kind == "string" then
		return string.format("%q", value)
	elseif kind == "Color3" then
		return string.format(
			"rgb(%d, %d, %d)",
			math.floor(value.R * 255 + 0.5),
			math.floor(value.G * 255 + 0.5),
			math.floor(value.B * 255 + 0.5)
		)
	elseif kind == "Vector3" then
		return string.format(
			"(%s, %s, %s)",
			Util.formatNumber(Util.round(value.X, 3)),
			Util.formatNumber(Util.round(value.Y, 3)),
			Util.formatNumber(Util.round(value.Z, 3))
		)
	elseif kind == "Vector2" then
		return string.format("(%s, %s)", Util.formatNumber(Util.round(value.X, 3)), Util.formatNumber(Util.round(value.Y, 3)))
	elseif kind == "NumberRange" then
		return string.format("%s..%s", Util.formatNumber(Util.round(value.Min, 4)), Util.formatNumber(Util.round(value.Max, 4)))
	elseif kind == "NumberSequence" then
		local parts = {}
		for _, keypoint in ipairs(value.Keypoints) do
			table.insert(parts, Util.formatNumber(Util.round(keypoint.Value, 3)))
		end
		return "NumberSequence[" .. table.concat(parts, ", ") .. "]"
	elseif kind == "ColorSequence" then
		local parts = {}
		for _, keypoint in ipairs(value.Keypoints) do
			table.insert(parts, Values.describe(keypoint.Value))
		end
		return "ColorSequence[" .. table.concat(parts, ", ") .. "]"
	elseif kind == "EnumItem" then
		return tostring(value)
	elseif kind == "nil" then
		return "nil"
	elseif kind == "table" then
		return "{...}"
	end
	return tostring(value)
end

return Values
