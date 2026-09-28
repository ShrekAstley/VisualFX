--[[
	VisualFX.Runtime.CustomEffects

	The `Effects` section instantiates effect types registered at runtime with
	VisualFX:RegisterEffect. The core engine treats them like any other managed
	effect: identity, duplicate prevention, diffing and cleanup all apply.

	  VisualFX:RegisterEffect({ Name = "Fireflies", Category = "Particles", Schema = {...},
	      Create = function(config, context) ... return instance end,
	      Update = function(instance, config, context) ... end,
	      Remove = function(instance, context) ... end })

	  Effects = {
	      GroveFireflies = { Effect = "Fireflies", Rate = 12 },
	  }

	Change detection for custom effects compares a deterministic fingerprint of
	the configuration stored in the VisualFX_ConfigHash attribute, so
	unchanged effects are never re-created or re-updated.
]]

local Core = script.Parent.Parent.Core
local Util = require(Core.Util)
local Serialization = require(Core.Serialization)

local CustomEffects = {}

CustomEffects.HASH_ATTRIBUTE = "VisualFX_ConfigHash"

function CustomEffects.Fingerprint(config: { [string]: any }): string
	local ok, encoded = pcall(function()
		return Serialization:ToJSON(Serialization:EncodeValue(config), false)
	end)
	return if ok then encoded else tostring(os.clock())
end

function CustomEffects.Register(registry)
	registry:RegisterSection({
		Name = "Effects",
		Order = 90,
		Kind = "map",
		ItemAllowUnknown = true,
		Description = "Instances of custom effect types registered with VisualFX:RegisterEffect.",
		ItemFields = {
			{ Key = "Effect", Kind = "string", Description = "Registered effect name (defaults to the entry key)." },
			{ Key = "Enabled", Kind = "boolean", Default = true },
		},
		Validate = function(section, report, context, validator)
			for _, id in ipairs(Util.sortedKeys(section)) do
				local item = section[id]
				if typeof(item) ~= "table" then
					continue
				end
				local effectName = item.Effect or id
				local definition = registry:GetEffect(effectName)
				if not definition then
					local suggestion = Util.suggest(effectName, registry:ListEffects())
					report:Error(
						"Effects." .. id .. ".Effect",
						"UnknownEffect",
						string.format(
							"Effects.%s: no effect named '%s' is registered%s",
							id,
							effectName,
							if suggestion then " (did you mean '" .. suggestion .. "'?)" else ""
						)
					)
					continue
				end
				-- Validate the entry against the effect's own schema.
				local fields = definition.Fields
				local entry = {}
				for key, value in pairs(item) do
					if key ~= "Effect" and key ~= "Enabled" then
						entry[key] = value
					end
				end
				local normalized = validator:ValidateObject(fields, entry, "Effects." .. id, report, context, nil)
				for key, value in pairs(normalized) do
					item[key] = value
				end
				for key in pairs(entry) do
					if normalized[key] == nil then
						item[key] = nil
					end
				end
				if definition.Validate then
					local ok, problem = pcall(definition.Validate, item, report)
					if not ok then
						report:Error("Effects." .. id, "EffectValidator", tostring(problem))
					end
				end
			end
		end,
		Desired = function(section, context)
			local specs = {}
			for _, id in ipairs(Util.sortedKeys(section)) do
				local item = section[id]
				local effectName = item.Effect or id
				local definition = registry:GetEffect(effectName)
				if definition and item.Enabled ~= false then
					local config = Util.deepCopy(item)
					config.Effect = nil
					config.Enabled = nil
					table.insert(specs, {
						ID = "effect." .. id,
						Type = effectName,
						Custom = definition,
						Config = config,
						Fingerprint = CustomEffects.Fingerprint(config),
						ParentID = "root",
						Owner = "Effects",
						Properties = {},
						Depth = 1,
					})
				end
			end
			return specs
		end,
	})
end

return CustomEffects
