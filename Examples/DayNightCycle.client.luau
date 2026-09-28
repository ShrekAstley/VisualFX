--[[
	Example (StarterPlayerScripts): a 20-minute day with lighting driven
	through sunrise/sunset keyframes, plus fireflies only at night.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VisualFX = require(ReplicatedStorage:WaitForChild("VisualFX"))

VisualFX:UpdateScene({
	Atmosphere = { Density = 0.34, Haze = 1.2 },
	Environment = {
		DayNight = { Enabled = true, DayLength = 20, StartTime = 6, DriveLighting = true },
	},
})

local lighting = game:GetService("Lighting")
local night = nil
lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
	local isNight = lighting.ClockTime >= 19 or lighting.ClockTime < 5.5
	if isNight ~= night then
		night = isNight
		if isNight then
			VisualFX:UpdateParticleSystem("Fireflies", { Template = "Fireflies", Rate = 8 })
		elseif VisualFX:GetConfiguration().Particles and VisualFX:GetConfiguration().Particles.Fireflies then
			VisualFX:RemoveParticleSystem("Fireflies")
		end
	end
end)
