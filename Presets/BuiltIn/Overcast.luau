--[[
	VisualFX built-in preset: Overcast
	Flat grey overcast daylight.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Overcast",
		Category = "Weather",
		Description = "Flat grey overcast daylight.",
		Tags = { "overcast", "grey", "cloudy" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(80, 80, 85),
		Brightness = 1.6,
		ClockTime = 13,
		OutdoorAmbient = Color3.fromRGB(140, 140, 145),
		ShadowSoftness = 0.8,
	},
	Weather = {
		Type = "Overcast",
		Intensity = 0.85,
	},
}
