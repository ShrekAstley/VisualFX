--[[
	VisualFX built-in preset: Realistic
	Physically plausible midday lighting with sky-driven ambient and reflections.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Realistic",
		Category = "Style",
		Description = "Physically plausible midday lighting with sky-driven ambient and reflections.",
		Tags = { "realistic", "day" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(0, 0, 0),
		Brightness = 3,
		ClockTime = 13.5,
		ColorShiftBottom = Color3.fromRGB(0, 0, 0),
		ColorShiftTop = Color3.fromRGB(255, 245, 230),
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 1,
		ExposureCompensation = -0.1,
		GlobalShadows = true,
		OutdoorAmbient = Color3.fromRGB(100, 100, 100),
		ShadowSoftness = 0.15,
	},
	Atmosphere = {
		Color = Color3.fromRGB(199, 205, 215),
		Decay = Color3.fromRGB(106, 112, 125),
		Density = 0.3,
		Glare = 0.3,
		Haze = 0.6,
		Offset = 0.25,
	},
	Clouds = {
		Color = Color3.fromRGB(255, 255, 255),
		Cover = 0.5,
		Density = 0.6,
	},
	PostProcessing = {
		Bloom = {
			Intensity = 0.4,
			Size = 24,
			Threshold = 2.2,
		},
		ColorCorrection = {
			Contrast = 0.05,
			Saturation = 0.02,
		},
		SunRays = {
			Intensity = 0.06,
			Spread = 0.6,
		},
	},
}
