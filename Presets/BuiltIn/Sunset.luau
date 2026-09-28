--[[
	VisualFX built-in preset: Sunset
	Warm low sun with orange sky and soft purple shadows.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Sunset",
		Category = "Time of Day",
		Description = "Warm low sun with orange sky and soft purple shadows.",
		Tags = { "sunset", "warm", "evening" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(70, 50, 60),
		Brightness = 2,
		ClockTime = 17.8,
		ColorShiftBottom = Color3.fromRGB(80, 50, 70),
		ColorShiftTop = Color3.fromRGB(255, 170, 110),
		EnvironmentDiffuseScale = 0.5,
		EnvironmentSpecularScale = 0.6,
		ExposureCompensation = 0.1,
		GlobalShadows = true,
		OutdoorAmbient = Color3.fromRGB(150, 110, 100),
		ShadowSoftness = 0.3,
	},
	Atmosphere = {
		Color = Color3.fromRGB(245, 170, 130),
		Decay = Color3.fromRGB(120, 70, 90),
		Density = 0.33,
		Glare = 0.5,
		Haze = 1.8,
		Offset = 0.1,
	},
	Clouds = {
		Color = Color3.fromRGB(255, 215, 190),
		Cover = 0.45,
		Density = 0.55,
	},
}
