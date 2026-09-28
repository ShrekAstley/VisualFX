--[[
	VisualFX built-in preset: CinematicSunset
	Warm cinematic sunset environment with bloom, sun rays and gentle depth of field.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Cinematic Sunset",
		Category = "Cinematic",
		Description = "Warm cinematic sunset environment with bloom, sun rays and gentle depth of field.",
		Author = "VisualFX",
		Tags = { "sunset", "cinematic", "warm" },
	},
	Inherits = { "Sunset" },
	Lighting = {
		Brightness = 2.2,
		EnvironmentSpecularScale = 0.7,
		ExposureCompensation = 0.15,
		ShadowSoftness = 0.35,
	},
	Atmosphere = {
		Density = 0.35,
		Glare = 0.6,
		Haze = 2,
	},
	PostProcessing = {
		Bloom = {
			Intensity = 0.8,
			Size = 28,
			Threshold = 1.6,
		},
		ColorCorrection = {
			Contrast = 0.12,
			Saturation = 0.12,
			TintColor = Color3.fromRGB(255, 235, 220),
		},
		DepthOfField = {
			FarIntensity = 0.15,
			FocusDistance = 60,
			InFocusRadius = 40,
			NearIntensity = 0,
		},
		SunRays = {
			Intensity = 0.12,
			Spread = 0.8,
		},
	},
	Water = {
		Color = Color3.fromRGB(40, 80, 100),
		Reflectance = 0.9,
		Transparency = 0.4,
		WaveSize = 0.12,
		WaveSpeed = 8,
	},
}
