--[[
	VisualFX.Runtime.Atmosphere

	Sections:
	  Atmosphere  the Atmosphere instance in Lighting (density, haze, glare, colors)
	  Sky         the Sky instance in Lighting (skybox, sun/moon, stars)
	  Clouds      the Clouds instance under Workspace.Terrain (dynamic clouds)

	Roblox only renders one Atmosphere and one Sky, so these are singletons:
	VisualFX adopts an existing developer instance (recording its original
	values so it can be restored) instead of creating a competing duplicate.
	Fog behaviour: while an Atmosphere exists, Lighting.Fog* is ignored by the
	engine; distance fog is expressed through Density/Offset/Haze instead.
]]

local Core = script.Parent.Parent.Core
local PropertyMap = require(Core.PropertyMap)

local Atmosphere = {}

Atmosphere.Fields = {
	{ Key = "Density", Property = "Density", Kind = "number", Min = 0, Max = 1, Default = 0.395, Neutral = 0, Description = "How much light the air absorbs (distance fog)." },
	{ Key = "Offset", Property = "Offset", Kind = "number", Min = 0, Max = 1, Default = 0, Description = "Light transmission between camera and sky (horizon silhouette)." },
	{ Key = "Color", Property = "Color", Kind = "Color3", Default = Color3.fromRGB(199, 199, 199), Description = "Hue of the atmosphere." },
	{ Key = "Decay", Property = "Decay", Kind = "Color3", Default = Color3.fromRGB(106, 112, 125), Description = "Hue away from the sun." },
	{ Key = "Glare", Property = "Glare", Kind = "number", Min = 0, Max = 10, Default = 0, Neutral = 0, Description = "Glow around the sun." },
	{ Key = "Haze", Property = "Haze", Kind = "number", Min = 0, Max = 10, Default = 0, Neutral = 0, Description = "Haziness above the horizon." },
}

Atmosphere.SkyFields = {
	{ Key = "SkyboxBk", Property = "SkyboxBk", Kind = "string", Interpolate = false, Description = "Skybox back face texture (content id)." },
	{ Key = "SkyboxDn", Property = "SkyboxDn", Kind = "string", Interpolate = false },
	{ Key = "SkyboxFt", Property = "SkyboxFt", Kind = "string", Interpolate = false },
	{ Key = "SkyboxLf", Property = "SkyboxLf", Kind = "string", Interpolate = false },
	{ Key = "SkyboxRt", Property = "SkyboxRt", Kind = "string", Interpolate = false },
	{ Key = "SkyboxUp", Property = "SkyboxUp", Kind = "string", Interpolate = false },
	{ Key = "SunTextureId", Property = "SunTextureId", Kind = "string", Interpolate = false },
	{ Key = "MoonTextureId", Property = "MoonTextureId", Kind = "string", Interpolate = false },
	{ Key = "SunAngularSize", Property = "SunAngularSize", Kind = "number", Min = 0, Max = 60, Default = 21 },
	{ Key = "MoonAngularSize", Property = "MoonAngularSize", Kind = "number", Min = 0, Max = 60, Default = 11 },
	{ Key = "StarCount", Property = "StarCount", Kind = "number", Min = 0, Max = 5000, Default = 3000 },
	{ Key = "CelestialBodiesShown", Property = "CelestialBodiesShown", Kind = "boolean", Default = true },
	{ Key = "SkyboxOrientation", Property = "SkyboxOrientation", Kind = "Vector3", Description = "Skybox rotation in degrees (newer engines only)." },
}

Atmosphere.CloudFields = {
	{ Key = "Enabled", Property = "Enabled", Kind = "boolean", Default = true },
	{ Key = "Cover", Property = "Cover", Kind = "number", Min = 0, Max = 1, Default = 0.5, Neutral = 0, Description = "Fraction of the sky covered by clouds." },
	{ Key = "Density", Property = "Density", Kind = "number", Min = 0, Max = 1, Default = 0.7, Description = "Cloud particle density (opacity)." },
	{ Key = "Color", Property = "Color", Kind = "Color3", Default = Color3.fromRGB(255, 255, 255) },
}

local function singletonSection(registry, options)
	registry:RegisterSection({
		Name = options.Name,
		Order = options.Order,
		ClassName = options.ClassName,
		Description = options.Description,
		Fields = options.Fields,
		Desired = function(section, context)
			local properties, byProperty = PropertyMap.toProperties(options.Fields, section)
			return {
				{
					ID = options.ID,
					Type = options.Name,
					ClassName = options.ClassName,
					Name = options.ClassName,
					Parent = options.Parent(context),
					Adopt = context.Settings.AdoptExisting,
					Singleton = true,
					Properties = properties,
					FieldsByProperty = byProperty,
				},
			}
		end,
		Inspect = function(context)
			local list = {}
			local parent = options.Parent(context)
			if parent then
				for _, child in ipairs(parent:GetChildren()) do
					if child.ClassName == options.ClassName then
						table.insert(list, {
							Name = child.Name,
							Properties = PropertyMap.read(child, options.Fields, context.Compatibility),
							Instance = child,
						})
					end
				end
			end
			return list
		end,
	})
end

function Atmosphere.Register(registry)
	singletonSection(registry, {
		Name = "Atmosphere",
		Order = 20,
		ClassName = "Atmosphere",
		ID = "atmosphere.primary",
		Description = "Atmospheric scattering, distance fog and haze.",
		Fields = Atmosphere.Fields,
		Parent = function(context)
			return context.Lighting
		end,
	})
	singletonSection(registry, {
		Name = "Sky",
		Order = 25,
		ClassName = "Sky",
		ID = "sky.primary",
		Description = "Skybox, sun, moon and stars.",
		Fields = Atmosphere.SkyFields,
		Parent = function(context)
			return context.Lighting
		end,
	})
	singletonSection(registry, {
		Name = "Clouds",
		Order = 30,
		ClassName = "Clouds",
		ID = "clouds.primary",
		Description = "Dynamic terrain clouds (Workspace.Terrain.Clouds).",
		Fields = Atmosphere.CloudFields,
		Parent = function(context)
			return context.Terrain
		end,
	})
end

return Atmosphere
