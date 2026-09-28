--[[
	Example: a custom effect type registered without touching the core.

	  local VisualFX = require(game.ReplicatedStorage.VisualFX)
	  VisualFX:RegisterEffect(require(path.To.Beacon))
	  VisualFX:CreateEffect("HarborBeacon", { Effect = "Beacon", Position = Vector3.new(40, 12, -30), Range = 30 })

	VisualFX handles identity, duplicate prevention, diffing, previews and
	cleanup. Update is only called when the configuration changes.
]]

return {
	Name = "Beacon",
	Category = "Lights",
	Description = "A glowing point light with slowly rising sparkles.",
	Schema = {
		Position = { Kind = "Vector3", Required = true, Description = "World position." },
		Color = { Kind = "Color3", Default = Color3.fromRGB(255, 200, 120) },
		Range = { Kind = "number", Min = 0, Max = 60, Default = 20 },
		Brightness = { Kind = "number", Min = 0, SoftMax = 10, Default = 2 },
	},
	Create = function(config)
		local part = Instance.new("Part")
		part.Name = "Beacon"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 1
		part.Size = Vector3.new(1, 1, 1)
		part.Position = config.Position

		local light = Instance.new("PointLight")
		light.Color = config.Color or Color3.fromRGB(255, 200, 120)
		light.Range = config.Range or 20
		light.Brightness = config.Brightness or 2
		light.Parent = part

		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Rate = 6
		sparkles.Lifetime = NumberRange.new(2, 3)
		sparkles.Speed = NumberRange.new(1, 2)
		sparkles.LightEmission = 1
		sparkles.Color = ColorSequence.new(config.Color or Color3.fromRGB(255, 200, 120))
		sparkles.Parent = part
		return part
	end,
	Update = function(part, config)
		part.Position = config.Position
		local light = part:FindFirstChildOfClass("PointLight")
		if light then
			light.Color = config.Color or light.Color
			light.Range = config.Range or light.Range
			light.Brightness = config.Brightness or light.Brightness
		end
		local sparkles = part:FindFirstChildOfClass("ParticleEmitter")
		if sparkles and config.Color then
			sparkles.Color = ColorSequence.new(config.Color)
		end
	end,
}
