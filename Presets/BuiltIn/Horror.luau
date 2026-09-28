--[[
	VisualFX built-in preset: Horror
	Oppressive, desaturated night with thick sickly fog.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Horror",
		Category = "Mood",
		Description = "Oppressive, desaturated night with thick sickly fog.",
		Tags = { "horror", "dark", "fog" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(15, 18, 15),
		Brightness = 0.3,
		ClockTime = 1,
		ColorShiftTop = Color3.fromRGB(0, 0, 0),
		EnvironmentDiffuseScale = 0.1,
		EnvironmentSpecularScale = 0.2,
		ExposureCompensation = -0.3,
		GlobalShadows = true,
		OutdoorAmbient = Color3.fromRGB(40, 50, 40),
	},
	Atmosphere = {
		Color = Color3.fromRGB(80, 95, 80),
		Decay = Color3.fromRGB(25, 35, 25),
		Density = 0.65,
		Glare = 0,
		Haze = 3,
		Offset = 0,
	},
	Sky = {
		CelestialBodiesShown = false,
		StarCount = 0,
	},
	PostProcessing = {
		Blur = {
			Size = 2,
		},
		ColorCorrection = {
			Brightness = -0.05,
			Contrast = 0.2,
			Saturation = -0.55,
			TintColor = Color3.fromRGB(215, 235, 215),
		},
	},
	Weather = {
		Type = "Fog",
		Intensity = 0.7,
	},
}
