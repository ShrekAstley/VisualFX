--[[
	VisualFX built-in preset: MistyForest
	Cool, damp forest morning wrapped in fog.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Misty Forest",
		Category = "Forest",
		Description = "Cool, damp forest morning wrapped in fog.",
		Tags = { "forest", "fog", "mist" },
	},
	Lighting = {
		Brightness = 1.5,
		ClockTime = 8,
		ExposureCompensation = 0,
	},
	Atmosphere = {
		Color = Color3.fromRGB(170, 190, 175),
		Decay = Color3.fromRGB(90, 110, 100),
		Density = 0.45,
		Glare = 0,
		Haze = 2.5,
	},
	Weather = {
		Type = "Fog",
		Intensity = 0.6,
	},
}
