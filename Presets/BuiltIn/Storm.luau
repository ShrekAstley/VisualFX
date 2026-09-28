--[[
	VisualFX built-in preset: Storm
	Thunderstorm with heavy rain and lightning.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Storm",
		Category = "Weather",
		Description = "Thunderstorm with heavy rain and lightning.",
		Tags = { "storm", "rain", "lightning" },
	},
	Lighting = {
		ClockTime = 15,
		GlobalShadows = true,
		ShadowSoftness = 0.9,
	},
	Weather = {
		Type = "Thunderstorm",
		Intensity = 0.8,
	},
}
