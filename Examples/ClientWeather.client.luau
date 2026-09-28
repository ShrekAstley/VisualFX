--[[
	Example (StarterPlayerScripts): client-side weather cycle.

	Weather particles attach to the local camera, lightning flashes, zones
	are culled by distance and the underwater look works only on clients,
	so per-player weather belongs in a LocalScript.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VisualFX = require(ReplicatedStorage:WaitForChild("VisualFX"))

VisualFX:SetQuality("High")
VisualFX:ApplyPreset("Forest")

-- Optional audio: connect weather hooks to sounds you own.
local soundFolder = workspace:FindFirstChild("WeatherSounds")
VisualFX.Events.AudioHook:Connect(function(hook)
	local sound = soundFolder and soundFolder:FindFirstChild(hook.Hook)
	if not sound then
		return
	end
	if hook.Action == "Start" or hook.Action == "Update" then
		sound.Volume = hook.Volume
		if not sound.IsPlaying then
			sound:Play()
		end
	elseif hook.Action == "Stop" then
		sound:Stop()
	elseif hook.Action == "Trigger" then
		task.delay(hook.Delay or 0, function()
			sound:Play()
		end)
	end
end)

local cycle = {
	{ Weather = { Type = "Clear", Intensity = 0.8 }, Hold = 60 },
	{ Weather = { Type = "Cloudy", Intensity = 0.6 }, Hold = 45 },
	{ Weather = { Type = "LightRain", Intensity = 0.5 }, Hold = 45 },
	{ Weather = { Type = "Thunderstorm", Intensity = 0.9 }, Hold = 40 },
	{ Weather = { Type = "LightRain", Intensity = 0.3 }, Hold = 30 },
}

while true do
	for _, stage in ipairs(cycle) do
		VisualFX:TransitionTo({
			Duration = 12,
			Easing = "Smooth",
			Configuration = { Weather = stage.Weather },
		})
		task.wait(stage.Hold)
	end
end
