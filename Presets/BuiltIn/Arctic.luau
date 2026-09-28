--[[
	VisualFX built-in preset: Arctic
	Cold, bright polar light with light snowfall.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Arctic",
		Category = "Biome",
		Description = "Cold, bright polar light with light snowfall.",
		Tags = { "arctic", "snow", "cold" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(110, 120, 140),
		Brightness = 2.4,
		ClockTime = 10,
		ColorShiftTop = Color3.fromRGB(230, 240, 255),
		EnvironmentDiffuseScale = 0.8,
		EnvironmentSpecularScale = 0.9,
		ExposureCompensation = 0.2,
		OutdoorAmbient = Color3.fromRGB(175, 185, 205),
	},
	Atmosphere = {
		Color = Color3.fromRGB(215, 228, 240),
		Decay = Color3.fromRGB(150, 170, 200),
		Density = 0.38,
		Glare = 0.3,
		Haze = 1.5,
		Offset = 0.25,
	},
	PostProcessing = {
		ColorCorrection = {
			Saturation = -0.1,
			TintColor = Color3.fromRGB(240, 247, 255),
		},
	},
	Water = {
		Color = Color3.fromRGB(60, 100, 130),
		Reflectance = 1,
		Transparency = 0.3,
		WaveSize = 0.05,
		WaveSpeed = 4,
	},
	Weather = {
		Type = "Snow",
		Intensity = 0.4,
	},
}
