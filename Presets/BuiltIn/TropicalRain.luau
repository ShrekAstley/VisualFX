--[[
	VisualFX built-in preset: TropicalRain
	Warm tropical shower over turquoise water.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Tropical Rain",
		Category = "Weather",
		Description = "Warm tropical shower over turquoise water.",
		Tags = { "tropical", "rain" },
	},
	Inherits = { "Tropical" },
	Lighting = {
		Brightness = 1.8,
		ExposureCompensation = 0,
	},
	Water = {
		Transparency = 0.55,
		WaveSize = 0.2,
		WaveSpeed = 14,
	},
	Weather = {
		Type = "LightRain",
		Intensity = 0.6,
		Wind = 10,
	},
}
