--[[
	VisualFX built-in preset: MoonlitNight
	Cool, luminous moonlit night with fireflies and low mist.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Moonlit Night",
		Category = "Time of Day",
		Description = "Cool, luminous moonlit night with fireflies and low mist.",
		Tags = { "night", "moon", "fireflies" },
	},
	Inherits = { "Night" },
	Lighting = {
		Brightness = 0.9,
		ClockTime = 23.5,
		OutdoorAmbient = Color3.fromRGB(60, 70, 105),
	},
	PostProcessing = {
		Bloom = {
			Intensity = 0.9,
			Size = 30,
			Threshold = 1.4,
		},
		ColorCorrection = {
			Contrast = 0.08,
			Saturation = -0.15,
			TintColor = Color3.fromRGB(215, 225, 255),
		},
	},
	Particles = {
		Fireflies = {
			Template = "Fireflies",
			Rate = 8,
		},
		Mist = {
			Template = "Mist",
			Rate = 8,
		},
	},
}
