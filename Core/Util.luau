--[[
	VisualFX.Core.Util

	Small, dependency-free helpers shared by every VisualFX module.
	Everything here is deterministic: key ordering, copying and merging never
	depend on hash-table iteration order.
]]

local Util = {}

local function typeRank(value: any): number
	local kind = typeof(value)
	if kind == "number" then
		return 1
	elseif kind == "string" then
		return 2
	elseif kind == "boolean" then
		return 3
	end
	return 4
end

-- Keys that should be listed first when a table is printed, serialized or
-- turned into code. Everything else is sorted alphabetically.
Util.KeyPriority = {
	["$type"] = 0,
	Format = 1,
	Version = 2,
	Metadata = 3,
	Name = 4,
	Inherits = 5,
	Type = 6,
	Template = 6,
	Effect = 6,
	Enabled = 7,
	Level = 7,
	Quality = 10,
	Lighting = 11,
	Atmosphere = 12,
	Sky = 13,
	Clouds = 14,
	PostProcessing = 15,
	Water = 16,
	Particles = 17,
	Weather = 18,
	Environment = 19,
	Effects = 20,
}

--[[
	Returns the keys of `t` in a stable order: numbers ascending, then
	strings (priority keys first, then alphabetical), then everything else.
]]
function Util.sortedKeys(t: { [any]: any }): { any }
	local keys = {}
	for key in pairs(t) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		local ra, rb = typeRank(a), typeRank(b)
		if ra ~= rb then
			return ra < rb
		end
		if ra == 2 then
			local pa, pb = Util.KeyPriority[a] or 1000, Util.KeyPriority[b] or 1000
			if pa ~= pb then
				return pa < pb
			end
			return a < b
		elseif ra == 1 then
			return a < b
		end
		return tostring(a) < tostring(b)
	end)
	return keys
end

-- Iterates a table in `sortedKeys` order.
function Util.spairs(t: { [any]: any })
	local keys = Util.sortedKeys(t)
	local index = 0
	return function()
		index += 1
		local key = keys[index]
		if key ~= nil then
			return key, t[key]
		end
		return nil
	end
end

function Util.isPlainTable(value: any): boolean
	return typeof(value) == "table" and getmetatable(value) == nil
end

-- True for a non-empty table whose keys are exactly 1..n.
function Util.isArray(t: any): boolean
	if typeof(t) ~= "table" then
		return false
	end
	local count = 0
	for key in pairs(t) do
		if typeof(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end
		count += 1
	end
	return count > 0 and count == #t
end

function Util.isEmpty(t: any): boolean
	return typeof(t) == "table" and next(t) == nil
end

-- Deep copies plain tables. Roblox datatypes are immutable values and are shared.
function Util.deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in pairs(value :: any) do
		copy[Util.deepCopy(key)] = Util.deepCopy(item)
	end
	return setmetatable(copy, getmetatable(value :: any)) :: any
end

function Util.deepFreeze<T>(value: T): T
	if typeof(value) == "table" and not table.isfrozen(value :: any) then
		for _, item in pairs(value :: any) do
			Util.deepFreeze(item)
		end
		table.freeze(value :: any)
	end
	return value
end

function Util.count(t: { [any]: any }?): number
	local n = 0
	if t then
		for _ in pairs(t) do
			n += 1
		end
	end
	return n
end

function Util.keys(t: { [any]: any }?): { any }
	if not t then
		return {}
	end
	return Util.sortedKeys(t)
end

function Util.shallowCopy<T>(t: T): T
	local copy = {}
	for key, value in pairs(t :: any) do
		copy[key] = value
	end
	return copy :: any
end

function Util.clamp(value: number, low: number, high: number): number
	if value < low then
		return low
	elseif value > high then
		return high
	end
	return value
end

function Util.round(value: number, decimals: number?): number
	local scale = 10 ^ (decimals or 0)
	local scaled = value * scale
	if scaled >= 0 then
		return math.floor(scaled + 0.5) / scale
	end
	return math.ceil(scaled - 0.5) / scale
end

--[[
	Formats a number with the shortest representation that round-trips,
	so serialized configurations stay readable (0.35 instead of 0.34999999).
]]
function Util.formatNumber(value: number): string
	if value ~= value then
		return "0/0"
	elseif value == math.huge then
		return "math.huge"
	elseif value == -math.huge then
		return "-math.huge"
	end
	if value % 1 == 0 and math.abs(value) < 1e15 then
		return string.format("%d", value)
	end
	for precision = 1, 17 do
		local text = string.format("%." .. precision .. "g", value)
		if tonumber(text) == value then
			return text
		end
	end
	return string.format("%.17g", value)
end

function Util.join(list: { any }, separator: string?): string
	local parts = {}
	for index, item in ipairs(list) do
		parts[index] = tostring(item)
	end
	return table.concat(parts, separator or ", ")
end

function Util.startsWith(text: string, prefix: string): boolean
	return string.sub(text, 1, #prefix) == prefix
end

function Util.split(text: string, separator: string): { string }
	local parts = {}
	local start = 1
	while true do
		local first, last = string.find(text, separator, start, true)
		if not first then
			table.insert(parts, string.sub(text, start))
			break
		end
		table.insert(parts, string.sub(text, start, first - 1))
		start = last + 1
	end
	return parts
end

function Util.trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

-- "light_rain", "light rain", "LightRain", "light-rain" -> "lightrain"
function Util.normalizeName(text: string): string
	return string.lower((string.gsub(text, "[%s_%-%.]", "")))
end

-- "light_rain" -> "LightRain"
function Util.pascalCase(text: string): string
	local result = string.gsub(text, "[%s_%-]+(%w)", function(letter)
		return string.upper(letter)
	end)
	return (string.gsub(result, "^%l", string.upper))
end

-- Levenshtein distance, used to suggest corrections for misspelled keys.
function Util.editDistance(a: string, b: string): number
	a, b = string.lower(a), string.lower(b)
	local lenA, lenB = #a, #b
	if lenA == 0 then
		return lenB
	elseif lenB == 0 then
		return lenA
	end
	local previous = {}
	for j = 0, lenB do
		previous[j] = j
	end
	for i = 1, lenA do
		local current = { [0] = i }
		local charA = string.byte(a, i)
		for j = 1, lenB do
			local cost = if charA == string.byte(b, j) then 0 else 1
			current[j] = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
		end
		previous = current
	end
	return previous[lenB]
end

-- Returns the closest candidate within a reasonable distance, or nil.
function Util.suggest(input: string, candidates: { string }): string?
	local best, bestDistance = nil, math.huge
	local normalized = Util.normalizeName(input)
	for _, candidate in ipairs(candidates) do
		if Util.normalizeName(candidate) == normalized then
			return candidate
		end
		local distance = Util.editDistance(input, candidate)
		if distance < bestDistance then
			best, bestDistance = candidate, distance
		end
	end
	if best and bestDistance <= math.max(2, math.floor(#input / 3)) then
		return best
	end
	return nil
end

-- Appends every item of `source` to `target` and returns `target`.
function Util.append(target: { any }, source: { any }?): { any }
	if source then
		for _, item in ipairs(source) do
			table.insert(target, item)
		end
	end
	return target
end

-- Inserts `value` if it is not already present. Keeps insertion order.
function Util.addUnique(list: { any }, value: any): { any }
	if not table.find(list, value) then
		table.insert(list, value)
	end
	return list
end

-- Walks "A.B.C" into a nested table.
function Util.getPath(root: any, path: string): any
	local node = root
	for _, part in ipairs(Util.split(path, ".")) do
		if typeof(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return node
end

function Util.setPath(root: { [string]: any }, path: string, value: any)
	local parts = Util.split(path, ".")
	local node = root
	for index = 1, #parts - 1 do
		local part = parts[index]
		if typeof(node[part]) ~= "table" then
			node[part] = {}
		end
		node = node[part]
	end
	node[parts[#parts]] = value
end

return Util
