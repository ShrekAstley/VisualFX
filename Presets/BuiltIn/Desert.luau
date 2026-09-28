--[[
	VisualFX built-in preset: Desert
	Scorching, hazy desert noon.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Desert",
		Category = "Biome",
		Description = "Scorching, hazy desert noon.",
		Tags = { "desert", "hot", "dry" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(110, 90, 70),
		Brightness = 3.2,
		ClockTime = 13,
		ColorShiftTop = Color3.fromRGB(255, 225, 180),
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.3,
		ExposureCompensation = 0.1,
		OutdoorAmbient = Color3.fromRGB(190, 160, 130),
	},
	Atmosphere = {
		Color = Color3.fromRGB(230, 200, 160),
		Decay = Color3.fromRGB(170, 120, 80),
		Density = 0.36,
		Glare = 1,
		Haze = 2.5,
		Offset = 0.2,
	},
	Clouds = {
		Cover = 0.1,
		Density = 0.3,
	},
	PostProcessing = {
		ColorCorrection = {
			Contrast = 0.08,
			Saturation = 0.05,
			TintColor = Color3.fromRGB(255, 242, 225),
		},
	},
	Particles = {
		Dust = {
			Template = "Dust",
			Rate = 30,
		},
	},
	Environment = {
		Wind = {
			Direction = Vector3.new(1, 0, 0.2),
			Speed = 12,
		},
	},
}
