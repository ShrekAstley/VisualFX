--[[
	VisualFX built-in preset: BaseForest
	Neutral forest base: soft green ambient light. Designed to be composed with other presets.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Base Forest",
		Category = "Biome",
		Description = "Neutral forest base: soft green ambient light. Designed to be composed with other presets.",
		Tags = { "forest", "base" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(60, 70, 55),
		Brightness = 1.8,
		ClockTime = 9,
		ColorShiftTop = Color3.fromRGB(240, 245, 220),
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.4,
		OutdoorAmbient = Color3.fromRGB(120, 135, 115),
		ShadowSoftness = 0.4,
	},
	Atmosphere = {
		Color = Color3.fromRGB(180, 200, 180),
		Decay = Color3.fromRGB(100, 120, 100),
		Density = 0.4,
		Glare = 0,
		Haze = 1.5,
		Offset = 0.1,
	},
	PostProcessing = {
		ColorCorrection = {
			Saturation = 0.05,
			TintColor = Color3.fromRGB(245, 255, 240),
		},
	},
}
