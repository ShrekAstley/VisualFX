--[[
	VisualFX.Runtime.EffectAPI

	Uniform per-effect APIs. Every effect exposes the same nine operations:

	  Create(config)      ensure the effect exists and apply config (merge)
	  Get()               live values read from the scene
	  Set(config)         replace the effect's configuration exactly
	  Update(partial)     merge partial values into the configuration
	  Remove()            remove the effect (created instances are destroyed,
	                      adopted/service properties are restored)
	  Reset()             restore original values (same as Remove for effects
	                      VisualFX created; for Lighting/Water it restores the
	                      values that existed before VisualFX touched them)
	  Serialize()         configuration -> JSON-safe data
	  Deserialize(data)   JSON-safe data -> configuration (does not apply)
	  Validate(config)    validation report for a candidate configuration

	  VisualFX.Atmosphere:Update({ Haze = 2 })
	  VisualFX.PostProcessing.Bloom:Set({ Intensity = 0.6, Size = 24 })
	  VisualFX.Particles:Create("Rain", { Template = "Rain", Rate = 400 })
	  VisualFX.Weather:Create("HeavyRain", { Intensity = 0.8 })
]]

local Core = script.Parent.Parent.Core
local Util = require(Core.Util)
local Config = require(Core.Config)
local Serialization = require(Core.Serialization)
local PropertyMap = require(Core.PropertyMap)

local Lighting = require(script.Parent.Lighting)
local Atmosphere = require(script.Parent.Atmosphere)
local Water = require(script.Parent.Water)
local Particles = require(script.Parent.Particles)

local EffectAPI = {}

local function wrap(path: { string }, value: any): { [string]: any }
	local root = {}
	local node = root
	for index = 1, #path - 1 do
		node[path[index]] = {}
		node = node[path[index]]
	end
	node[path[#path]] = value
	return root
end

local function readAt(root: any, path: { string }): any
	local node = root
	for _, key in ipairs(path) do
		if typeof(node) ~= "table" then
			return nil
		end
		node = node[key]
	end
	return node
end

local function liveReader(engine, path: { string })
	local context = engine.Context
	local first, second = path[1], path[2]
	local manager = engine.InstanceManager
	local compatibility = engine.Compatibility
	if first == "Lighting" then
		return PropertyMap.read(context.Lighting, Lighting.Fields, compatibility)
	elseif first == "Water" then
		return PropertyMap.read(context.Terrain, Water.Fields, compatibility)
	elseif first == "Atmosphere" then
		local instance = manager:Find("atmosphere.primary") or context.Lighting:FindFirstChildOfClass("Atmosphere")
		return PropertyMap.read(instance, Atmosphere.Fields, compatibility)
	elseif first == "Sky" then
		local instance = manager:Find("sky.primary") or context.Lighting:FindFirstChildOfClass("Sky")
		return PropertyMap.read(instance, Atmosphere.SkyFields, compatibility)
	elseif first == "Clouds" then
		local instance = manager:Find("clouds.primary") or context.Terrain:FindFirstChildOfClass("Clouds")
		return PropertyMap.read(instance, Atmosphere.CloudFields, compatibility)
	elseif first == "PostProcessing" and second then
		for _, effect in ipairs(Lighting.PostEffects) do
			if effect.Key == second then
				local instance = manager:Find("postprocessing." .. string.lower(second))
				return PropertyMap.read(instance, effect.Fields, compatibility)
			end
		end
	elseif first == "Particles" and second then
		return PropertyMap.read(manager:Find("particles." .. second), Particles.EmitterFields, compatibility)
	elseif first == "Environment" and path[2] == "Zones" and path[3] then
		return PropertyMap.read(manager:Find("zone." .. path[3]), Particles.EmitterFields, compatibility)
	end
	return nil
end

--[[
	API bound to a fixed configuration path, e.g. { "Atmosphere" } or
	{ "PostProcessing", "Bloom" }.
]]
function EffectAPI.Section(engine, path: { string }, label: string?)
	local api = { Path = table.concat(path, "."), Name = label or path[#path] }

	function api:Create(config: { [string]: any }?)
		return engine:_MutateOverlay(wrap(path, config or {}), { Action = "Create" .. api.Name })
	end

	function api:Get()
		return liveReader(engine, path)
	end

	function api:GetConfiguration()
		return Util.deepCopy(readAt(engine:GetConfiguration(), path))
	end

	function api:Set(config: { [string]: any })
		return engine:_ReplacePath(path, config, { Action = "Set" .. api.Name })
	end

	function api:Update(partial: { [string]: any })
		return engine:_MutateOverlay(wrap(path, partial), { Action = "Update" .. api.Name })
	end

	function api:Remove()
		return engine:_MutateOverlay(wrap(path, Config.REMOVE), { Action = "Remove" .. api.Name })
	end

	function api:Reset()
		return engine:_MutateOverlay(wrap(path, Config.REMOVE), { Action = "Reset" .. api.Name })
	end

	function api:Serialize()
		return Serialization:EncodeValue(readAt(engine:GetConfiguration(), path))
	end

	function api:Deserialize(data: any)
		return Serialization:DecodeValue(data)
	end

	function api:Validate(config: { [string]: any })
		return engine:Validate(wrap(path, config), { Partial = true })
	end

	return api
end

--[[
	API for dictionaries of named effects: Particles, Environment.Zones, Effects.
]]
function EffectAPI.Keyed(engine, path: { string }, label: string)
	local api = { Path = table.concat(path, "."), Name = label }

	local function itemPath(name: string): { string }
		local result = table.clone(path)
		table.insert(result, name)
		return result
	end

	function api:Create(name: string, config: { [string]: any }?)
		return engine:_MutateOverlay(wrap(itemPath(name), config or {}), { Action = "Create" .. label })
	end

	function api:Get(name: string)
		return liveReader(engine, itemPath(name))
	end

	function api:GetConfiguration(name: string)
		return Util.deepCopy(readAt(engine:GetConfiguration(), itemPath(name)))
	end

	function api:Set(name: string, config: { [string]: any })
		return engine:_ReplacePath(itemPath(name), config, { Action = "Set" .. label })
	end

	function api:Update(name: string, partial: { [string]: any })
		return engine:_MutateOverlay(wrap(itemPath(name), partial), { Action = "Update" .. label })
	end

	function api:Remove(name: string)
		return engine:_MutateOverlay(wrap(itemPath(name), Config.REMOVE), { Action = "Remove" .. label })
	end

	-- Removes every entry in this collection.
	function api:Reset()
		return engine:_MutateOverlay(wrap(path, Config.REMOVE), { Action = "Reset" .. label })
	end

	function api:List(): { string }
		return Util.sortedKeys(readAt(engine:GetConfiguration(), path) or {})
	end

	function api:Serialize(name: string?)
		local value = readAt(engine:GetConfiguration(), if name then itemPath(name) else path)
		return Serialization:EncodeValue(value)
	end

	function api:Deserialize(data: any)
		return Serialization:DecodeValue(data)
	end

	function api:Validate(name: string, config: { [string]: any })
		return engine:Validate(wrap(itemPath(name), config), { Partial = true })
	end

	return api
end

function EffectAPI.Weather(engine)
	local api = EffectAPI.Section(engine, { "Weather" }, "Weather")

	function api:Create(weatherType: string, config: { [string]: any }?)
		local value = Util.deepCopy(config or {})
		value.Type = weatherType
		return engine:_ReplacePath({ "Weather" }, value, { Action = "CreateWeather" })
	end

	function api:Types(): { string }
		return engine.Registry:ListWeather()
	end

	function api:Get()
		local context = engine.Scene:MakeContext(engine:GetResolvedConfiguration())
		context.Engine = engine
		return engine.Registry:GetSection("Weather").Inspect(context)
	end

	return api
end

-- Installs the APIs on an engine instance.
function EffectAPI.Install(engine)
	engine.Lighting = EffectAPI.Section(engine, { "Lighting" })
	engine.Atmosphere = EffectAPI.Section(engine, { "Atmosphere" })
	engine.Sky = EffectAPI.Section(engine, { "Sky" })
	engine.Clouds = EffectAPI.Section(engine, { "Clouds" })
	engine.Water = EffectAPI.Section(engine, { "Water" })
	engine.PostProcessing = {}
	for _, effect in ipairs(Lighting.PostEffects) do
		engine.PostProcessing[effect.Key] = EffectAPI.Section(engine, { "PostProcessing", effect.Key }, effect.Key)
	end
	engine.Particles = EffectAPI.Keyed(engine, { "Particles" }, "ParticleSystem")
	engine.Zones = EffectAPI.Keyed(engine, { "Environment", "Zones" }, "Zone")
	engine.Effects = EffectAPI.Keyed(engine, { "Effects" }, "Effect")
	engine.Weather = EffectAPI.Weather(engine)
	engine.Wind = EffectAPI.Section(engine, { "Environment", "Wind" }, "Wind")
	engine.DayNight = EffectAPI.Section(engine, { "Environment", "DayNight" }, "DayNight")
end

return EffectAPI
