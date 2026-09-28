--[[
	VisualFX built-in preset: SciFi
	Cold teal alien light with hard contrast and strong bloom.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Sci-Fi",
		Category = "Style",
		Description = "Cold teal alien light with hard contrast and strong bloom.",
		Tags = { "scifi", "alien", "teal" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(20, 60, 70),
		Brightness = 1.4,
		ClockTime = 16,
		ColorShiftBottom = Color3.fromRGB(60, 0, 90),
		ColorShiftTop = Color3.fromRGB(120, 255, 240),
		EnvironmentDiffuseScale = 0.4,
		EnvironmentSpecularScale = 1,
		ExposureCompensation = -0.1,
		OutdoorAmbient = Color3.fromRGB(60, 130, 140),
		ShadowSoftness = 0.05,
	},
	Atmosphere = {
		Color = Color3.fromRGB(100, 210, 200),
		Decay = Color3.fromRGB(40, 20, 90),
		Density = 0.42,
		Glare = 2,
		Haze = 1.5,
		Offset = 0.05,
	},
	PostProcessing = {
		Bloom = {
			Intensity = 1.6,
			Size = 36,
			Threshold = 0.9,
		},
		ColorCorrection = {
			Contrast = 0.25,
			Saturation = -0.1,
			TintColor = Color3.fromRGB(220, 255, 250),
		},
	},
	Particles = {
		Dust = {
			Template = "Dust",
			Color = Color3.fromRGB(140, 255, 240),
			LightEmission = 0.6,
			Rate = 30,
		},
	},
}
