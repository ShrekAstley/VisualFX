--[[
	VisualFX built-in preset: HeavyRain
	Heavy downpour with low visibility.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Heavy Rain",
		Category = "Weather",
		Description = "Heavy downpour with low visibility.",
		Tags = { "rain", "storm" },
	},
	Lighting = {
		GlobalShadows = true,
		ShadowSoftness = 0.8,
	},
	Weather = {
		Type = "HeavyRain",
		Intensity = 0.85,
	},
}
