--[[
	Runs the VisualFX test suite with the standalone Luau CLI against the
	Roblox mock. Usage (from the VisualFX directory):

	  python3 tools/bundle.py test.project.json build/test_bundle.luau
	  luau tools/run_tests.luau [-a <filter>]

	or simply: sh tools/test.sh
]]

local Mock = require("./mock/Roblox")
local bundle = require("../build/test_bundle")

local filter = nil
local args = { ... }
if args[1] then
	filter = args[1]
end

local function findNode(node, path)
	for _, name in ipairs(path) do
		local found = nil
		for _, child in ipairs(node.Children) do
			if child.Name == name then
				found = child
			end
		end
		if not found then
			error("bundle is missing " .. table.concat(path, "."))
		end
		node = found
	end
	return node
end

local packageNode = findNode(bundle, { "ReplicatedStorage", "VisualFX" })
local testsNode = findNode(bundle, { "ReplicatedStorage", "VisualFXTests" })
local examplesNode = findNode(bundle, { "ReplicatedStorage", "VisualFXExamples" })

local specNames = {}
for _, child in ipairs(testsNode.Children) do
	if string.sub(child.Name, -5) == ".spec" and (filter == nil or string.find(child.Name, filter, 1, true)) then
		table.insert(specNames, child.Name)
	end
end
table.sort(specNames)

local totals = { Passed = 0, Failed = 0, Failures = {} }
local verbose = os.getenv and os.getenv("VERBOSE") == "1"

for _, specName in ipairs(specNames) do
	local world = Mock.createWorld()
	local replicatedStorage = world.game:GetService("ReplicatedStorage")
	local package = Mock.mount(packageNode, replicatedStorage)
	local tests = Mock.mount(testsNode, replicatedStorage)
	Mock.mount(examplesNode, replicatedStorage)
	local requireFn = Mock.makeRequire(world)
	local ok, problem = pcall(function()
		local TestKit = requireFn(tests.TestKit)
		local VisualFX = requireFn(package)
		local services = {
			Lighting = world.game:GetService("Lighting"),
			Terrain = world.Terrain,
			Workspace = world.workspace,
		}
		local capture, restore = TestKit.makeSnapshotter(services)
		local spec = requireFn(tests[specName])
		local results = TestKit.runSpec(specName, spec, {
			VisualFX = VisualFX,
			Mock = Mock,
			World = world,
			Services = services,
			Snapshot = capture,
			Restore = restore,
		})
		totals.Passed += results.Passed
		totals.Failed += results.Failed
		for _, failure in ipairs(results.Failures) do
			table.insert(totals.Failures, failure)
		end
		if verbose then
			for _, line in ipairs(results.Names) do
				print(line)
			end
		end
		print(string.format("%-34s %3d passed, %d failed", specName, results.Passed, results.Failed))
	end)
	if not ok then
		totals.Failed += 1
		table.insert(totals.Failures, { Name = specName .. " (load)", Message = tostring(problem) })
		print(string.format("%-34s failed to load", specName))
	end
end

print("")
for _, failure in ipairs(totals.Failures) do
	print("FAIL " .. failure.Name)
	print("     " .. string.gsub(failure.Message, "\n", "\n     "))
end
print(string.format("\n%d passed, %d failed", totals.Passed, totals.Failed))
if totals.Failed > 0 then
	error("test failures", 0)
end
