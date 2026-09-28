--[[
	VisualFX built-in preset: Tropical
	Bright, saturated tropical day with clear turquoise water.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Tropical",
		Category = "Biome",
		Description = "Bright, saturated tropical day with clear turquoise water.",
		Tags = { "tropical", "beach", "island" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(90, 90, 80),
		Brightness = 3,
		ClockTime = 11.5,
		ColorShiftTop = Color3.fromRGB(255, 245, 220),
		EnvironmentDiffuseScale = 0.7,
		EnvironmentSpecularScale = 0.8,
		ExposureCompensation = 0.1,
		OutdoorAmbient = Color3.fromRGB(160, 160, 150),
	},
	Atmosphere = {
		Color = Color3.fromRGB(185, 225, 245),
		Decay = Color3.fromRGB(120, 160, 200),
		Density = 0.26,
		Glare = 0.5,
		Haze = 0.8,
		Offset = 0.3,
	},
	Clouds = {
		Color = Color3.fromRGB(255, 255, 255),
		Cover = 0.4,
		Density = 0.5,
	},
	PostProcessing = {
		Bloom = {
			Intensity = 0.6,
			Size = 24,
			Threshold = 1.8,
		},
		ColorCorrection = {
			Contrast = 0.05,
			Saturation = 0.2,
		},
	},
	Water = {
		Color = Color3.fromRGB(30, 170, 190),
		Reflectance = 0.6,
		Transparency = 0.75,
		WaveSize = 0.1,
		WaveSpeed = 9,
	},
}
