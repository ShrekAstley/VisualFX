--[[
	VisualFX built-in preset: DarkStorm
	Near-black violent storm with frequent lightning.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Dark Storm",
		Category = "Weather",
		Description = "Near-black violent storm with frequent lightning.",
		Tags = { "storm", "dark", "lightning" },
	},
	Inherits = { "Storm" },
	Lighting = {
		Ambient = Color3.fromRGB(25, 28, 35),
		Brightness = 0.6,
		ClockTime = 17,
		ExposureCompensation = -0.6,
	},
	PostProcessing = {
		ColorCorrection = {
			Contrast = 0.15,
			Saturation = -0.4,
		},
	},
	Weather = {
		Type = "Thunderstorm",
		Intensity = 1,
		LightningFrequency = 10,
		Wind = 40,
	},
}
