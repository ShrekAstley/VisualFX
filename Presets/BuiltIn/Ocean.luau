--[[
	VisualFX built-in preset: Ocean
	Open ocean with deep blue reflective water and a breeze.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Ocean",
		Category = "Biome",
		Description = "Open ocean with deep blue reflective water and a breeze.",
		Tags = { "ocean", "sea", "water" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(70, 80, 95),
		Brightness = 2.6,
		ClockTime = 15,
		EnvironmentDiffuseScale = 0.7,
		EnvironmentSpecularScale = 1,
		OutdoorAmbient = Color3.fromRGB(140, 150, 165),
	},
	Atmosphere = {
		Color = Color3.fromRGB(190, 215, 235),
		Decay = Color3.fromRGB(100, 130, 165),
		Density = 0.3,
		Glare = 0.6,
		Haze = 1.2,
		Offset = 0.35,
	},
	Clouds = {
		Cover = 0.5,
		Density = 0.55,
	},
	Water = {
		Color = Color3.fromRGB(20, 70, 110),
		Reflectance = 1,
		Transparency = 0.35,
		Underwater = {
			Enabled = true,
			BlurSize = 4,
			TintColor = Color3.fromRGB(90, 160, 210),
		},
		WaveSize = 0.35,
		WaveSpeed = 14,
	},
	Environment = {
		Wind = {
			Direction = Vector3.new(1, 0, 0.5),
			Speed = 18,
		},
	},
}
