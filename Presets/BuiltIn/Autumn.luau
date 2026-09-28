--[[
	VisualFX built-in preset: Autumn
	Warm autumn grading with falling leaves. Composes well with forest and rain presets.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Autumn",
		Category = "Seasonal",
		Description = "Warm autumn grading with falling leaves. Composes well with forest and rain presets.",
		Tags = { "autumn", "fall", "leaves" },
	},
	Lighting = {
		ColorShiftTop = Color3.fromRGB(255, 205, 150),
	},
	Atmosphere = {
		Color = Color3.fromRGB(220, 190, 160),
		Decay = Color3.fromRGB(150, 100, 70),
	},
	PostProcessing = {
		ColorCorrection = {
			Saturation = 0.12,
			TintColor = Color3.fromRGB(255, 238, 215),
		},
	},
	Particles = {
		Leaves = {
			Template = "Leaves",
			Rate = 14,
		},
	},
}
