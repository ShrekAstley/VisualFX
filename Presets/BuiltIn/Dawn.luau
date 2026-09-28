--[[
	VisualFX built-in preset: Dawn
	Blue hour just before the sun rises.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Dawn",
		Category = "Time of Day",
		Description = "Blue hour just before the sun rises.",
		Tags = { "dawn", "blue hour" },
	},
	Lighting = {
		Ambient = Color3.fromRGB(40, 45, 70),
		Brightness = 0.8,
		ClockTime = 5.6,
		ColorShiftBottom = Color3.fromRGB(30, 35, 60),
		ColorShiftTop = Color3.fromRGB(150, 140, 190),
		ExposureCompensation = 0.3,
		OutdoorAmbient = Color3.fromRGB(90, 95, 130),
	},
	Atmosphere = {
		Color = Color3.fromRGB(130, 140, 190),
		Decay = Color3.fromRGB(50, 55, 95),
		Density = 0.4,
		Glare = 0,
		Haze = 1.4,
		Offset = 0.1,
	},
	PostProcessing = {
		ColorCorrection = {
			Saturation = -0.05,
			TintColor = Color3.fromRGB(230, 235, 255),
		},
	},
	Particles = {
		Mist = {
			Template = "Mist",
			Rate = 10,
		},
	},
}
