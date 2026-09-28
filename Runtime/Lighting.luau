--[[
	VisualFX.Runtime.Lighting

	Sections:
	  Lighting        properties of the Lighting service
	  PostProcessing  Bloom, ColorCorrection, DepthOfField, SunRays, Blur
	                  (PostEffect instances parented to Lighting)

	All properties are real Roblox properties. Properties that the running
	engine does not expose (or refuses to set at the current security level,
	such as Lighting.Technology outside Studio) are detected by the
	compatibility layer, reported as warnings and skipped.
]]

local Core = script.Parent.Parent.Core
local PropertyMap = require(Core.PropertyMap)

local Lighting = {}

local TIME_EPSILON = 1.5 / 3600 -- ClockTime is stored with one-second precision

Lighting.Fields = {
	{ Key = "ClockTime", Property = "ClockTime", Kind = "number", Min = 0, Max = 24, Default = 14, Epsilon = TIME_EPSILON, Wrap = 24, Unit = "hours", Description = "Time of day in hours (0-24)." },
	{ Key = "Brightness", Property = "Brightness", Kind = "number", Min = 0, Max = 10, Default = 2, Description = "Intensity of sun/moon light." },
	{ Key = "ExposureCompensation", Property = "ExposureCompensation", Kind = "number", Min = -3, Max = 3, Default = 0, Description = "Camera exposure offset in stops." },
	{ Key = "Ambient", Property = "Ambient", Kind = "Color3", Default = Color3.fromRGB(0, 0, 0), Description = "Ambient light in enclosed/indoor areas." },
	{ Key = "OutdoorAmbient", Property = "OutdoorAmbient", Kind = "Color3", Default = Color3.fromRGB(128, 128, 128), Description = "Ambient light outdoors." },
	{ Key = "ColorShiftTop", Property = "ColorShift_Top", Kind = "Color3", Default = Color3.fromRGB(0, 0, 0), Aliases = { "ColorShift_Top" }, Description = "Tint of surfaces facing the sun." },
	{ Key = "ColorShiftBottom", Property = "ColorShift_Bottom", Kind = "Color3", Default = Color3.fromRGB(0, 0, 0), Aliases = { "ColorShift_Bottom" }, Description = "Tint of surfaces facing away from the sun." },
	{ Key = "GlobalShadows", Property = "GlobalShadows", Kind = "boolean", Default = true, Description = "Enables sun/moon shadows." },
	{ Key = "ShadowSoftness", Property = "ShadowSoftness", Kind = "number", Min = 0, Max = 1, Default = 0.2, Description = "Shadow edge blur (ShadowMap/Future)." },
	{ Key = "EnvironmentDiffuseScale", Property = "EnvironmentDiffuseScale", Kind = "number", Min = 0, Max = 1, Default = 0, Description = "Ambient light derived from the sky." },
	{ Key = "EnvironmentSpecularScale", Property = "EnvironmentSpecularScale", Kind = "number", Min = 0, Max = 1, Default = 0, Description = "Specular reflections derived from the sky (also affects water/metal)." },
	{ Key = "GeographicLatitude", Property = "GeographicLatitude", Kind = "number", Min = -90, Max = 90, Default = 41.733, Description = "Latitude used for sun/moon position." },
	{ Key = "FogColor", Property = "FogColor", Kind = "Color3", Default = Color3.fromRGB(192, 192, 192), Description = "Legacy fog color (ignored while an Atmosphere exists)." },
	{ Key = "FogStart", Property = "FogStart", Kind = "number", Min = 0, Default = 0, Description = "Legacy fog start distance (ignored while an Atmosphere exists)." },
	{ Key = "FogEnd", Property = "FogEnd", Kind = "number", Min = 0, Default = 100000, Description = "Legacy fog end distance (ignored while an Atmosphere exists)." },
	{ Key = "Technology", Property = "Technology", Kind = "EnumItem", Enum = "Technology", Interpolate = false, Description = "Lighting technology. Usually only writable from Studio; skipped with a warning elsewhere." },
}

-- Config keys are the familiar names (Bloom); ClassName is the engine class (BloomEffect).
local function postEffect(key: string, className: string, fields: { any }, description: string)
	return {
		Key = key,
		Kind = "object",
		ClassName = className,
		Description = description,
		Fields = fields,
	}
end

Lighting.PostEffects = {
	postEffect("Bloom", "BloomEffect", {
		{ Key = "Enabled", Property = "Enabled", Kind = "boolean", Default = true },
		{ Key = "Intensity", Property = "Intensity", Kind = "number", Min = 0, SoftMax = 3, Default = 1, Neutral = 0 },
		{ Key = "Size", Property = "Size", Kind = "number", Min = 0, Max = 56, Default = 24 },
		{ Key = "Threshold", Property = "Threshold", Kind = "number", Min = 0, SoftMax = 4, Default = 2 },
	}, "Glow around bright areas."),
	postEffect("ColorCorrection", "ColorCorrectionEffect", {
		{ Key = "Enabled", Property = "Enabled", Kind = "boolean", Default = true },
		{ Key = "Brightness", Property = "Brightness", Kind = "number", Min = -1, Max = 1, Default = 0, Neutral = 0 },
		{ Key = "Contrast", Property = "Contrast", Kind = "number", Min = -1, Max = 1, Default = 0, Neutral = 0 },
		{ Key = "Saturation", Property = "Saturation", Kind = "number", Min = -1, Max = 1, Default = 0, Neutral = 0 },
		{ Key = "TintColor", Property = "TintColor", Kind = "Color3", Default = Color3.fromRGB(255, 255, 255), Neutral = Color3.fromRGB(255, 255, 255) },
	}, "Color grading."),
	postEffect("DepthOfField", "DepthOfFieldEffect", {
		{ Key = "Enabled", Property = "Enabled", Kind = "boolean", Default = true },
		{ Key = "FarIntensity", Property = "FarIntensity", Kind = "number", Min = 0, Max = 1, Default = 0.75, Neutral = 0 },
		{ Key = "FocusDistance", Property = "FocusDistance", Kind = "number", Min = 0, Max = 200, Default = 0.05 },
		{ Key = "InFocusRadius", Property = "InFocusRadius", Kind = "number", Min = 0, Max = 50, Default = 10 },
		{ Key = "NearIntensity", Property = "NearIntensity", Kind = "number", Min = 0, Max = 1, Default = 0.75, Neutral = 0 },
	}, "Distance blur."),
	postEffect("SunRays", "SunRaysEffect", {
		{ Key = "Enabled", Property = "Enabled", Kind = "boolean", Default = true },
		{ Key = "Intensity", Property = "Intensity", Kind = "number", Min = 0, Max = 1, Default = 0.25, Neutral = 0 },
		{ Key = "Spread", Property = "Spread", Kind = "number", Min = 0, Max = 1, Default = 1 },
	}, "God rays from the sun."),
	postEffect("Blur", "BlurEffect", {
		{ Key = "Enabled", Property = "Enabled", Kind = "boolean", Default = true },
		{ Key = "Size", Property = "Size", Kind = "number", Min = 0, Max = 56, Default = 24, Neutral = 0 },
	}, "Full-screen blur."),
}

-- Post effects that represent "one per scene" looks and may adopt an
-- existing developer instance. ColorCorrection and Blur are often used by
-- gameplay code, so VisualFX creates its own instead of adopting them.
Lighting.AdoptablePostEffects = { Bloom = true, DepthOfField = true, SunRays = true }

function Lighting.Register(registry)
	registry:RegisterSection({
		Name = "Lighting",
		Order = 10,
		ClassName = "Lighting",
		Description = "Lighting service properties: time of day, brightness, ambient colors, shadows.",
		Fields = Lighting.Fields,
		Targets = function(context)
			return { { ID = "lighting", Instance = context.Lighting } }
		end,
		Desired = function(section, context)
			local properties, byProperty = PropertyMap.toProperties(Lighting.Fields, section)
			return {
				{
					ID = "lighting",
					Type = "Lighting",
					Target = context.Lighting,
					Properties = properties,
					FieldsByProperty = byProperty,
				},
			}
		end,
		Inspect = function(context)
			return PropertyMap.read(context.Lighting, Lighting.Fields, context.Compatibility)
		end,
		Validate = function(section, report, _context, validator)
			if section.Technology ~= nil and validator.Compatibility then
				report:Warn(
					"Lighting.Technology",
					"SecurityRestricted",
					"Lighting.Technology can usually only be changed from Studio; at runtime the write is skipped if the engine rejects it"
				)
			end
		end,
	})

	registry:RegisterSection({
		Name = "PostProcessing",
		Order = 40,
		Description = "Post-processing effects parented to Lighting.",
		Fields = Lighting.PostEffects,
		Desired = function(section, context)
			local specs = {}
			local allowed = context.Quality.PostProcessing or {}
			for _, effect in ipairs(Lighting.PostEffects) do
				local config = section[effect.Key]
				if config ~= nil then
					local properties, byProperty = PropertyMap.toProperties(effect.Fields, config)
					if properties.Enabled == nil then
						properties.Enabled = true
					end
					local qualityDisabled = allowed[effect.Key] == false
					if qualityDisabled then
						properties.Enabled = false
					end
					table.insert(specs, {
						ID = "postprocessing." .. string.lower(effect.Key),
						Type = effect.Key,
						ClassName = effect.ClassName,
						Name = effect.Key,
						Parent = context.Lighting,
						Adopt = context.Settings.AdoptExisting and Lighting.AdoptablePostEffects[effect.Key] == true,
						Properties = properties,
						FieldsByProperty = byProperty,
						QualityDisabled = qualityDisabled,
					})
				end
			end
			return specs
		end,
		Inspect = function(context)
			local result = {}
			for _, child in ipairs(context.Lighting:GetChildren()) do
				for _, effect in ipairs(Lighting.PostEffects) do
					if child.ClassName == effect.ClassName then
						table.insert(result, {
							Name = child.Name,
							ClassName = child.ClassName,
							Effect = effect.Key,
							Properties = PropertyMap.read(child, effect.Fields, context.Compatibility),
							Instance = child,
						})
					end
				end
			end
			local camera = context.Workspace.CurrentCamera
			if camera then
				for _, child in ipairs(camera:GetChildren()) do
					for _, effect in ipairs(Lighting.PostEffects) do
						if child.ClassName == effect.ClassName then
							table.insert(result, {
								Name = child.Name,
								ClassName = child.ClassName,
								Parent = "Camera",
								Properties = PropertyMap.read(child, effect.Fields, context.Compatibility),
								Instance = child,
							})
						end
					end
				end
			end
			return result
		end,
	})
end

return Lighting
