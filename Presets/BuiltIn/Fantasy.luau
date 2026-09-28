--[[
	VisualFX built-in preset: Fantasy
	Dreamy violet twilight with glowing magic motes.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Fantasy",
		Category = "Mood",
		Description = "Dreamy violet twilight with glowing magic motes.",
		Tags = { "fantasy", "magic", "dreamy" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(80, 60, 110),
		Brightness = 1.8,
		ClockTime = 18.3,
		ColorShiftBottom = Color3.fromRGB(90, 60, 160),
		ColorShiftTop = Color3.fromRGB(255, 190, 240),
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.8,
		ExposureCompensation = 0.2,
		OutdoorAmbient = Color3.fromRGB(150, 120, 190),
	},
	Atmosphere = {
		Color = Color3.fromRGB(210, 160, 240),
		Decay = Color3.fromRGB(90, 60, 160),
		Density = 0.38,
		Glare = 1.2,
		Haze = 2.2,
		Offset = 0.2,
	},
	PostProcessing = {
		Bloom = {
			Intensity = 1.3,
			Size = 34,
			Threshold = 1.1,
		},
		ColorCorrection = {
			Saturation = 0.25,
			TintColor = Color3.fromRGB(250, 235, 255),
		},
		SunRays = {
			Intensity = 0.18,
			Spread = 0.9,
		},
	},
	Particles = {
		Fireflies = {
			Template = "Fireflies",
			Rate = 6,
		},
		Motes = {
			Template = "Magic",
			Area = Vector3.new(80, 30, 80),
			Attach = "Camera",
			Offset = Vector3.new(0, 8, 0),
			Rate = 30,
		},
	},
}
