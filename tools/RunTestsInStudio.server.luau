--[[
	Runs the VisualFX test suite inside Roblox Studio (Play Solo / Run).
	Build the test place with:  rojo build test.project.json -o VisualFXTests.rbxlx
	Each test snapshots Lighting/Terrain/Workspace and restores them afterwards,
	and every engine created by a test is reset, so the place is left unchanged.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VisualFX = require(ReplicatedStorage:WaitForChild("VisualFX"))
local tests = ReplicatedStorage:WaitForChild("VisualFXTests")
local TestKit = require(tests:WaitForChild("TestKit"))

local services = {
	Lighting = game:GetService("Lighting"),
	Terrain = workspace.Terrain,
	Workspace = workspace,
}
local capture, restore = TestKit.makeSnapshotter(services)

local specs = {}
for _, child in ipairs(tests:GetChildren()) do
	if child:IsA("ModuleScript") and string.sub(child.Name, -5) == ".spec" then
		table.insert(specs, child)
	end
end
table.sort(specs, function(a, b)
	return a.Name < b.Name
end)

local passed, failed = 0, 0
for _, specModule in ipairs(specs) do
	local ok, result = pcall(function()
		return TestKit.runSpec(specModule.Name, require(specModule), {
			VisualFX = VisualFX,
			Services = services,
			Snapshot = capture,
			Restore = restore,
		})
	end)
	if ok then
		passed += result.Passed
		failed += result.Failed
		for _, failure in ipairs(result.Failures) do
			warn("FAIL " .. failure.Name .. "\n" .. failure.Message)
		end
		print(string.format("%s: %d passed, %d failed", specModule.Name, result.Passed, result.Failed))
	else
		failed += 1
		warn("FAIL " .. specModule.Name .. " (load): " .. tostring(result))
	end
end
print(string.format("[VisualFX tests] %d passed, %d failed", passed, failed))
