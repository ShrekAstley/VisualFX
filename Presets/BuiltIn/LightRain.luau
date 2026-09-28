--[[
	VisualFX built-in preset: LightRain
	Light steady rain.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Light Rain",
		Category = "Weather",
		Description = "Light steady rain.",
		Tags = { "rain" },
	},
	Weather = {
		Type = "LightRain",
		Intensity = 0.5,
	},
}
