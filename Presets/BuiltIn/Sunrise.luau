--[[
	VisualFX built-in preset: Sunrise
	Pink-gold early sunrise with cool shadows.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Sunrise",
		Category = "Time of Day",
		Description = "Pink-gold early sunrise with cool shadows.",
		Tags = { "sunrise", "morning" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(60, 50, 70),
		Brightness = 1.6,
		ClockTime = 6.4,
		ColorShiftBottom = Color3.fromRGB(60, 60, 90),
		ColorShiftTop = Color3.fromRGB(255, 190, 150),
		EnvironmentDiffuseScale = 0.5,
		EnvironmentSpecularScale = 0.5,
		ExposureCompensation = 0.1,
		OutdoorAmbient = Color3.fromRGB(140, 120, 130),
	},
	Atmosphere = {
		Color = Color3.fromRGB(235, 180, 170),
		Decay = Color3.fromRGB(110, 100, 140),
		Density = 0.36,
		Glare = 0.4,
		Haze = 1.6,
		Offset = 0.15,
	},
	Clouds = {
		Color = Color3.fromRGB(255, 220, 215),
		Cover = 0.4,
		Density = 0.5,
	},
	PostProcessing = {
		ColorCorrection = {
			Saturation = 0.05,
			TintColor = Color3.fromRGB(255, 240, 235),
		},
	},
}
