--[[
	VisualFX built-in preset: Night
	Clear night with moonlight and stars.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Night",
		Category = "Time of Day",
		Description = "Clear night with moonlight and stars.",
		Tags = { "night", "moon", "stars" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(20, 22, 35),
		Brightness = 0.6,
		ClockTime = 0,
		ColorShiftBottom = Color3.fromRGB(0, 0, 0),
		ColorShiftTop = Color3.fromRGB(0, 0, 0),
		EnvironmentDiffuseScale = 0.3,
		EnvironmentSpecularScale = 0.4,
		ExposureCompensation = 0.2,
		OutdoorAmbient = Color3.fromRGB(45, 50, 75),
	},
	Atmosphere = {
		Color = Color3.fromRGB(70, 80, 110),
		Decay = Color3.fromRGB(20, 25, 45),
		Density = 0.4,
		Glare = 0,
		Haze = 0.8,
		Offset = 0,
	},
	Sky = {
		CelestialBodiesShown = true,
		MoonAngularSize = 14,
		StarCount = 4000,
	},
}
