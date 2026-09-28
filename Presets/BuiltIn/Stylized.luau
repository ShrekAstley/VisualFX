--[[
	VisualFX built-in preset: Stylized
	Bright, saturated, soft-shadowed stylized look.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Stylized",
		Category = "Style",
		Description = "Bright, saturated, soft-shadowed stylized look.",
		Tags = { "stylized", "cartoon", "bright" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(110, 110, 130),
		Brightness = 2.5,
		ClockTime = 14,
		ColorShiftTop = Color3.fromRGB(255, 240, 210),
		EnvironmentDiffuseScale = 0.2,
		EnvironmentSpecularScale = 0.1,
		ExposureCompensation = 0.2,
		OutdoorAmbient = Color3.fromRGB(170, 170, 185),
		ShadowSoftness = 0.6,
	},
	Atmosphere = {
		Color = Color3.fromRGB(190, 215, 255),
		Decay = Color3.fromRGB(140, 160, 210),
		Density = 0.25,
		Glare = 0.2,
		Haze = 0.5,
		Offset = 0.3,
	},
	Clouds = {
		Color = Color3.fromRGB(255, 255, 255),
		Cover = 0.55,
		Density = 0.45,
	},
	PostProcessing = {
		Bloom = {
			Intensity = 1.1,
			Size = 30,
			Threshold = 1.3,
		},
		ColorCorrection = {
			Contrast = 0.1,
			Saturation = 0.3,
			TintColor = Color3.fromRGB(255, 250, 240),
		},
	},
	Water = {
		Color = Color3.fromRGB(40, 170, 200),
		Reflectance = 0.5,
		Transparency = 0.6,
		WaveSize = 0.1,
		WaveSpeed = 6,
	},
}
