--[[
	Example (ServerScriptService): apply a shared scene for every player.
	Lighting, atmosphere, post-processing, water and world particles
	replicate from the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VisualFX = require(ReplicatedStorage:WaitForChild("VisualFX"))

local result = VisualFX:ApplyPreset("CinematicSunset", {
	Overrides = {
		Water = { WaveSize = 0.2 },
	},
})

if not result.Success then
	warn("[VisualFX] could not apply scene:\n" .. table.concat(result.Errors, "\n"))
end
for _, warning in ipairs(result.Warnings) do
	print("[VisualFX] " .. warning)
end

-- A campfire that lives in the world (not camera-attached).
VisualFX:CreateParticleSystem("Campfire", {
	Template = "Embers",
	Attach = "World",
	Position = Vector3.new(12, 1, -8),
	Rate = 25,
})
