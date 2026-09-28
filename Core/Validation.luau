--[[
	VisualFX.Core.Validation

	Centralized validator. Every configuration (from humans, presets, imports
	or AI agents) passes through here before anything touches the scene.

	  local report = validator:Validate(config)
	  report.Success     -- false when there is at least one error
	  report.Errors      -- { { Path, Code, Message, Expected?, Received? } }
	  report.Warnings    -- same shape; never block execution
	  report.Normalized  -- migrated, alias-resolved, type-coerced configuration

	Pipeline: migration -> schema/type validation -> compatibility validation
	-> section checks (conflicts, references) -> extra checks supplied by the
	caller (performance budgets, preset inheritance, live-scene conflicts).
]]

local Util = require(script.Parent.Util)
local Values = require(script.Parent.Values)
local Config = require(script.Parent.Config)
local Serialization = require(script.Parent.Serialization)

local Validation = {}
Validation.__index = Validation

local Report = {}
Report.__index = Report

function Report.new()
	return setmetatable({ Success = true, Errors = {}, Warnings = {}, Notes = {}, Normalized = nil }, Report)
end

function Report:Error(path: string, code: string, message: string, extra: { [string]: any }?)
	local entry = { Path = path, Code = code, Message = message }
	if extra then
		for key, value in pairs(extra) do
			entry[key] = value
		end
	end
	table.insert(self.Errors, entry)
	self.Success = false
end

function Report:Warn(path: string, code: string, message: string, extra: { [string]: any }?)
	local entry = { Path = path, Code = code, Message = message }
	if extra then
		for key, value in pairs(extra) do
			entry[key] = value
		end
	end
	table.insert(self.Warnings, entry)
end

function Report:Note(message: string)
	table.insert(self.Notes, message)
end

-- The type error format required by the import UI and AI agents.
function Report:TypeError(path: string, expected: string, received: string)
	self:Error(
		path,
		"InvalidType",
		string.format("Invalid property:\n%s\n\nExpected:\n%s\n\nReceived:\n%s", path, expected, received),
		{ Expected = expected, Received = received }
	)
end

-- Plain strings for printing ("Path: message").
function Report:ErrorMessages(): { string }
	local list = {}
	for _, entry in ipairs(self.Errors) do
		table.insert(list, entry.Message)
	end
	return list
end

function Report:WarningMessages(): { string }
	local list = {}
	for _, entry in ipairs(self.Warnings) do
		table.insert(list, entry.Path .. ": " .. entry.Message)
	end
	return list
end

-- Removes the metatable so the report can be serialized or returned to agents.
function Report:ToTable()
	return {
		Success = self.Success,
		Errors = self.Errors,
		Warnings = self.Warnings,
		Notes = self.Notes,
		Normalized = self.Normalized,
	}
end

Validation.Report = Report

function Validation.new(registry, compatibility)
	local self = setmetatable({}, Validation)
	self.Registry = registry
	self.Compatibility = compatibility
	return self
end

local function expectedName(field): string
	if field.Kind == "EnumItem" and field.Enum then
		return "Enum." .. field.Enum
	elseif field.Kind == "string" and field.Values then
		return "string (one of: " .. table.concat(field.Values, ", ") .. ")"
	elseif field.Kind == "integer" then
		return "integer"
	elseif field.Kind == "array" then
		return "array" .. if field.ItemKind then " of " .. field.ItemKind else ""
	end
	return field.Kind
end

local function describeType(value: any): string
	local kind = typeof(value)
	if kind == "EnumItem" then
		return tostring(value.EnumType) .. " enum item"
	end
	return kind
end

local function checkRange(report, field, value: number, path: string)
	if field.Min ~= nil and value < field.Min then
		report:Error(
			path,
			"OutOfRange",
			string.format("%s is %s but must be >= %s", path, Values.describe(value), Values.describe(field.Min)),
			{ Min = field.Min, Max = field.Max, Received = value }
		)
		return false
	elseif field.Max ~= nil and value > field.Max then
		report:Error(
			path,
			"OutOfRange",
			string.format("%s is %s but must be <= %s", path, Values.describe(value), Values.describe(field.Max)),
			{ Min = field.Min, Max = field.Max, Received = value }
		)
		return false
	end
	if field.SoftMax ~= nil and value > field.SoftMax then
		report:Warn(
			path,
			"AboveRecommended",
			string.format("%s is %s; values above %s are rarely useful and may cost performance", path, Values.describe(value), Values.describe(field.SoftMax))
		)
	elseif field.SoftMin ~= nil and value < field.SoftMin then
		report:Warn(
			path,
			"BelowRecommended",
			string.format("%s is %s; values below %s are unusual", path, Values.describe(value), Values.describe(field.SoftMin))
		)
	end
	return true
end

--[[
	Validates and normalizes one value against a field schema.
	Returns (normalizedValue, ok).
]]
function Validation:ValidateField(field, value: any, path: string, report, context): (any, boolean)
	if Config.isRemove(value) then
		if context.AllowRemove then
			return value, true
		end
		report:Error(path, "UnexpectedRemove", path .. ": '$remove' is only allowed in merge overlays")
		return nil, false
	end

	-- Tagged serialized values ({"$type": "Color3", ...}) from JSON input.
	if typeof(value) == "table" and value["$type"] ~= nil then
		local warnings = {}
		local decoded = Serialization:DecodeValue(value, warnings, path)
		for _, warning in ipairs(warnings) do
			report:Warn(path, "DecodeWarning", warning)
		end
		if decoded == nil then
			return nil, false
		end
		value = decoded
	end

	local kind = field.Kind
	if kind == "any" then
		return value, true
	elseif kind == "object" then
		if typeof(value) ~= "table" or Util.isArray(value) then
			report:TypeError(path, "table (object)", describeType(value))
			return nil, false
		end
		return self:ValidateObject(field.Fields, value, path, report, context, field)
	elseif kind == "map" then
		if typeof(value) ~= "table" or Util.isArray(value) then
			report:TypeError(path, "table (dictionary keyed by name)", describeType(value))
			return nil, false
		end
		return self:ValidateMap(field.ItemFields, value, path, report, context, field)
	elseif kind == "array" then
		if typeof(value) ~= "table" or (next(value) ~= nil and not Util.isArray(value)) then
			report:TypeError(path, expectedName(field), describeType(value))
			return nil, false
		end
		local result = {}
		for index, item in ipairs(value) do
			if field.ItemKind and typeof(item) ~= field.ItemKind then
				report:TypeError(path .. "[" .. index .. "]", field.ItemKind, describeType(item))
				return nil, false
			end
			result[index] = item
		end
		return result, true
	elseif kind == "number" or kind == "integer" then
		if typeof(value) ~= "number" then
			report:TypeError(path, expectedName(field), describeType(value))
			return nil, false
		end
		if value ~= value or value == math.huge or value == -math.huge then
			report:Error(path, "NotFinite", path .. " must be a finite number")
			return nil, false
		end
		if kind == "integer" and value % 1 ~= 0 then
			report:TypeError(path, "integer", "non-integer number " .. Values.describe(value))
			return nil, false
		end
		if not checkRange(report, field, value, path) then
			return nil, false
		end
		return value, true
	elseif kind == "boolean" then
		if typeof(value) ~= "boolean" then
			report:TypeError(path, "boolean", describeType(value))
			return nil, false
		end
		return value, true
	elseif kind == "string" then
		if typeof(value) ~= "string" then
			report:TypeError(path, expectedName(field), describeType(value))
			return nil, false
		end
		if field.Values then
			for _, allowed in ipairs(field.Values) do
				if Util.normalizeName(allowed) == Util.normalizeName(value) then
					return allowed, true
				end
			end
			local suggestion = Util.suggest(value, field.Values)
			report:Error(
				path,
				"InvalidValue",
				string.format(
					"%s: '%s' is not a valid value%s. Allowed: %s",
					path,
					value,
					if suggestion then " (did you mean '" .. suggestion .. "'?)" else "",
					table.concat(field.Values, ", ")
				),
				{ Expected = field.Values, Received = value }
			)
			return nil, false
		end
		if field.MaxLength and #value > field.MaxLength then
			report:Error(path, "TooLong", string.format("%s must be at most %d characters", path, field.MaxLength))
			return nil, false
		end
		return value, true
	end

	-- Roblox datatypes.
	local coerced, reason = Values.coerce(value, kind, field.Enum)
	if coerced == nil then
		if kind == "EnumItem" and field.Enum and not Values.getEnum(field.Enum) then
			report:Warn(path, "UnsupportedEnum", string.format("Enum.%s is not available in this engine version; %s skipped", field.Enum, path))
			return nil, false
		end
		if kind == "EnumItem" and reason then
			local suggestion = if typeof(value) == "string"
				then Util.suggest(value, Values.enumItemNames(field.Enum))
				else nil
			report:Error(
				path,
				"InvalidEnum",
				string.format("%s: %s%s", path, reason, if suggestion then " (did you mean '" .. suggestion .. "'?)" else ""),
				{ Expected = expectedName(field), Received = value }
			)
			return nil, false
		end
		report:TypeError(path, expectedName(field), describeType(value))
		return nil, false
	end

	if kind == "NumberRange" then
		if field.Min ~= nil and coerced.Min < field.Min or field.Max ~= nil and coerced.Max > field.Max then
			report:Error(
				path,
				"OutOfRange",
				string.format("%s range %s must stay within [%s, %s]", path, Values.describe(coerced), tostring(field.Min), tostring(field.Max))
			)
			return nil, false
		end
		if field.SoftMax and coerced.Max > field.SoftMax then
			checkRange(report, field, coerced.Max, path)
		end
	elseif kind == "NumberSequence" then
		for _, keypoint in ipairs(coerced.Keypoints) do
			if field.Min ~= nil and keypoint.Value < field.Min or field.Max ~= nil and keypoint.Value > field.Max then
				report:Error(
					path,
					"OutOfRange",
					string.format("%s keypoint value %s must stay within [%s, %s]", path, Values.describe(keypoint.Value), tostring(field.Min), tostring(field.Max))
				)
				return nil, false
			end
		end
	end
	return coerced, true
end

local function suggestKey(key: string, fields): string?
	local names = {}
	for _, field in ipairs(fields) do
		table.insert(names, field.Key)
	end
	return Util.suggest(key, names)
end

function Validation:ValidateObject(fields, value, path: string, report, context, owner): (any, boolean)
	local index, aliases = {}, {}
	for _, field in ipairs(fields) do
		index[field.Key] = field
		if field.Aliases then
			for _, alias in ipairs(field.Aliases) do
				aliases[alias] = field.Key
			end
		end
	end
	local result = {}
	local ok = true
	for _, key in ipairs(Util.sortedKeys(value)) do
		local item = value[key]
		local childPath = path .. "." .. tostring(key)
		local canonical = if typeof(key) == "string" then (if index[key] then key else aliases[key]) else nil
		if canonical == nil and owner and owner.AllowUnknown then
			result[key] = item
		elseif canonical == nil then
			local suggestion = if typeof(key) == "string" then suggestKey(key, fields) else nil
			report:Warn(
				childPath,
				"UnknownProperty",
				string.format(
					"Unknown property %s was ignored%s",
					childPath,
					if suggestion then " (did you mean '" .. suggestion .. "'?)" else ""
				),
				{ Suggestion = suggestion }
			)
		else
			if canonical ~= key then
				if value[canonical] ~= nil then
					report:Warn(childPath, "DuplicateAlias", string.format("%s is an alias of %s; both were given, %s wins", childPath, canonical, canonical))
					continue
				end
				report:Note(string.format("%s interpreted as %s.%s", childPath, path, canonical))
			end
			local field = index[canonical]
			local normalized, fieldOk = self:ValidateField(field, item, path .. "." .. canonical, report, context)
			if fieldOk then
				result[canonical] = normalized
				self:CheckFieldCompatibility(field, owner, path .. "." .. canonical, report, context)
			elseif not report.Success then
				ok = false
			end
		end
	end
	for _, field in ipairs(fields) do
		if field.Required and result[field.Key] == nil and not context.Partial then
			report:Error(path .. "." .. field.Key, "Required", string.format("%s.%s is required", path, field.Key))
			ok = false
		end
	end
	return result, ok
end

function Validation:ValidateMap(itemFields, value, path: string, report, context, owner): (any, boolean)
	local result = {}
	local ok = true
	for _, key in ipairs(Util.sortedKeys(value)) do
		local item = value[key]
		local childPath = path .. "." .. tostring(key)
		if typeof(key) ~= "string" or key == "" then
			report:Error(childPath, "InvalidKey", string.format("%s must be keyed by non-empty strings", path))
			ok = false
		elseif string.find(key, "[^%w_%- ]") then
			report:Error(childPath, "InvalidKey", string.format("%s: names may only contain letters, digits, spaces, '_' and '-'", childPath))
			ok = false
		elseif Config.isRemove(item) then
			if context.AllowRemove then
				result[key] = item
			else
				report:Error(childPath, "UnexpectedRemove", childPath .. ": '$remove' is only allowed in merge overlays")
				ok = false
			end
		elseif typeof(item) ~= "table" or Util.isArray(item) then
			report:TypeError(childPath, "table (object)", describeType(item))
			ok = false
		else
			local itemOwner = { ClassName = owner and owner.ClassName, AllowUnknown = owner and owner.ItemAllowUnknown }
			local normalized, itemOk = self:ValidateObject(itemFields, item, childPath, report, context, itemOwner)
			result[key] = normalized
			ok = ok and itemOk
		end
	end
	return result, ok
end

-- Warns (once per path) when a property is not exposed by the running engine.
function Validation:CheckFieldCompatibility(field, owner, path: string, report, context)
	if not self.Compatibility or not field.Property then
		return
	end
	local className = field.ClassName or (owner and owner.ClassName)
	if not className then
		return
	end
	local info = self.Compatibility:GetPropertySupport(className, field.Property)
	if not info.Supported then
		report:Warn(path, "UnsupportedProperty", string.format("%s: %s. The value will be skipped.", path, info.Reason or "unsupported"))
	end
end

--[[
	Validates a whole configuration.
	options:
	  Partial      boolean  - allow missing required fields (merge overlays)
	  AllowRemove  boolean  - allow "$remove" sentinels
	  Checks       { (normalized, report) -> () } extra checks (conflicts, performance)
]]
function Validation:Validate(config: any, options: { [string]: any }?)
	local opts = options or {}
	local report = Report.new()
	if typeof(config) ~= "table" then
		report:TypeError("<configuration>", "table", describeType(config))
		return report
	end

	local migrated, notes, problem = Config.migrate(config)
	for _, note in ipairs(notes) do
		report:Note(note)
	end
	if not migrated then
		report:Error("Version", "Migration", problem or "migration failed")
		return report
	end

	local normalized = { Version = migrated.Version }
	local context = { Partial = opts.Partial, AllowRemove = opts.AllowRemove, Report = report }

	-- Metadata
	if migrated.Metadata ~= nil then
		local metadataFields = {
			{ Key = "Name", Kind = "string", MaxLength = 100 },
			{ Key = "Author", Kind = "string", MaxLength = 100 },
			{ Key = "Description", Kind = "string", MaxLength = 2000 },
			{ Key = "Category", Kind = "string", MaxLength = 50 },
			{ Key = "Tags", Kind = "array", ItemKind = "string" },
		}
		normalized.Metadata = self:ValidateField(
			{ Key = "Metadata", Kind = "object", Fields = metadataFields },
			migrated.Metadata,
			"Metadata",
			report,
			context
		)
	end

	-- Inherits (preset composition). Existence and cycles are checked by the
	-- preset registry through opts.Checks.
	if migrated.Inherits ~= nil then
		local inherits = migrated.Inherits
		if typeof(inherits) == "string" then
			inherits = { inherits }
		end
		local value, ok = self:ValidateField({ Key = "Inherits", Kind = "array", ItemKind = "string" }, inherits, "Inherits", report, context)
		if ok then
			normalized.Inherits = value
		end
	end

	-- Sections
	for _, key in ipairs(Util.sortedKeys(migrated)) do
		if Config.MetaKeys[key] then
			continue
		end
		local value = migrated[key]
		local section = self.Registry:GetSection(key)
		if not section then
			local suggestion = if typeof(key) == "string" then Util.suggest(key, self.Registry:GetSectionNames()) else nil
			report:Warn(
				tostring(key),
				"UnknownSection",
				string.format(
					"Unknown section '%s' was ignored%s",
					tostring(key),
					if suggestion then " (did you mean '" .. suggestion .. "'?)" else ""
				),
				{ Suggestion = suggestion }
			)
			continue
		end
		if Config.isRemove(value) then
			if opts.AllowRemove then
				normalized[key] = value
			else
				report:Error(key, "UnexpectedRemove", key .. ": '$remove' is only allowed in merge overlays")
			end
			continue
		end
		if section.Coerce then
			value = section.Coerce(value)
		end
		local field = {
			Key = key,
			Kind = section.Kind,
			Fields = section.Fields,
			ItemFields = section.ItemFields,
			ClassName = section.ClassName,
			ItemAllowUnknown = section.ItemAllowUnknown,
		}
		local sectionValue, ok = self:ValidateField(field, value, key, report, context)
		if ok and sectionValue ~= nil then
			if section.Validate then
				local checkOk, checkProblem = pcall(section.Validate, sectionValue, report, context, self)
				if not checkOk then
					report:Error(key, "ValidatorFailure", string.format("%s validator failed: %s", key, tostring(checkProblem)))
				end
			end
			normalized[key] = sectionValue
		end
	end

	report.Normalized = normalized

	if opts.Checks then
		for _, check in ipairs(opts.Checks) do
			local ok, checkProblem = pcall(check, normalized, report)
			if not ok then
				report:Warn("<configuration>", "CheckFailure", "validation check failed: " .. tostring(checkProblem))
			end
		end
	end

	return report
end

return Validation
