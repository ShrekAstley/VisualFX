--[[
	VisualFX built-in preset: AutumnRainForest
	BaseForest + Autumn + LightRain composed with deterministic merge rules.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Autumn Rain Forest",
		Category = "Forest",
		Description = "BaseForest + Autumn + LightRain composed with deterministic merge rules.",
		Tags = { "forest", "autumn", "rain", "composed" },
	},
	Inherits = { "BaseForest", "Autumn", "LightRain" },
	Weather = {
		Intensity = 0.55,
	},
}
