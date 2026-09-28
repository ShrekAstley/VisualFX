--[[
	VisualFX built-in preset: Forest
	Calm forest morning with drifting mist and dust in the light.
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

return {
	Version = 1,
	Metadata = {
		Name = "Forest",
		Category = "Biome",
		Description = "Calm forest morning with drifting mist and dust in the light.",
		Tags = { "forest", "morning" },
	},
	Inherits = { "BaseForest" },
	PostProcessing = {
		SunRays = {
			Intensity = 0.1,
			Spread = 0.7,
		},
	},
	Particles = {
		Dust = {
			Template = "Dust",
			Color = Color3.fromRGB(230, 230, 200),
			Rate = 15,
		},
		Mist = {
			Template = "Mist",
			Rate = 10,
		},
	},
}
