--[[
	Tiny test framework used by the VisualFX test suite. It runs identically
	under the Luau CLI mock (tools/run_tests.luau) and inside Roblox Studio
	(tools/RunTestsInStudio.server.luau).

	Spec modules return function(t) and use:
	  t.describe(name, fn), t.it(name, fn), t.beforeEach(fn), t.afterEach(fn)
	  t.expect(value).toBe(x) / .toEqual(x) / .toBeCloseTo(x, eps) / .toContain(x)
	                .toBeTruthy() / .toBeFalsy() / .toBeNil() / .toHaveLength(n)
	                .toBeGreaterThan(x) / .toBeLessThan(x) / .toThrow() / .never.<matcher>
	  t.newEngine(options) - isolated VisualFX engine (AutoStart = false)
	  t.VisualFX           - the package module
	  t.Mock               - the engine mock (nil inside Studio)
]]

local TestKit = {}

local function describeValue(value: any): string
	local kind = typeof(value)
	if kind == "string" then
		return string.format("%q", value)
	elseif kind == "table" then
		local parts = {}
		local count = 0
		for key, item in pairs(value) do
			count += 1
			if count > 8 then
				table.insert(parts, "...")
				break
			end
			table.insert(parts, tostring(key) .. "=" .. (if typeof(item) == "table" then "{...}" else tostring(item)))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

local function deepEqual(a: any, b: any): boolean
	if typeof(a) ~= typeof(b) then
		return false
	end
	if typeof(a) == "table" then
		for key, value in pairs(a) do
			if not deepEqual(value, b[key]) then
				return false
			end
		end
		for key in pairs(b) do
			if a[key] == nil then
				return false
			end
		end
		return true
	end
	return a == b
end
TestKit.deepEqual = deepEqual

local function makeExpect(value: any, negate: boolean)
	local matchers = {}
	local function check(passed: boolean, message: string)
		if negate then
			passed = not passed
			message = "NOT " .. message
		end
		if not passed then
			error(message, 3)
		end
	end
	function matchers.toBe(expected)
		check(value == expected, string.format("expected %s to be %s", describeValue(value), describeValue(expected)))
	end
	function matchers.toEqual(expected)
		check(deepEqual(value, expected), string.format("expected %s to deep-equal %s", describeValue(value), describeValue(expected)))
	end
	function matchers.toBeCloseTo(expected, epsilon)
		local eps = epsilon or 1e-3
		check(typeof(value) == "number" and math.abs(value - expected) <= eps, string.format("expected %s to be within %s of %s", describeValue(value), tostring(eps), tostring(expected)))
	end
	function matchers.toBeTruthy()
		check(not not value, string.format("expected %s to be truthy", describeValue(value)))
	end
	function matchers.toBeFalsy()
		check(not value, string.format("expected %s to be falsy", describeValue(value)))
	end
	function matchers.toBeNil()
		check(value == nil, string.format("expected %s to be nil", describeValue(value)))
	end
	function matchers.toHaveLength(length)
		check(typeof(value) == "table" and #value == length, string.format("expected length %d, got %s", length, if typeof(value) == "table" then tostring(#value) else typeof(value)))
	end
	function matchers.toBeGreaterThan(other)
		check(typeof(value) == "number" and value > other, string.format("expected %s > %s", describeValue(value), describeValue(other)))
	end
	function matchers.toBeLessThan(other)
		check(typeof(value) == "number" and value < other, string.format("expected %s < %s", describeValue(value), describeValue(other)))
	end
	function matchers.toContain(item)
		local found = false
		if typeof(value) == "string" then
			found = string.find(value, item, 1, true) ~= nil
		elseif typeof(value) == "table" then
			for _, entry in pairs(value) do
				if entry == item or (typeof(entry) == "string" and typeof(item) == "string" and string.find(entry, item, 1, true)) then
					found = true
					break
				end
			end
		end
		check(found, string.format("expected %s to contain %s", describeValue(value), describeValue(item)))
	end
	function matchers.toThrow(pattern)
		local ok, problem = pcall(value)
		local passed = not ok and (pattern == nil or string.find(tostring(problem), pattern, 1, true) ~= nil)
		check(passed, string.format("expected function to throw%s (got %s)", if pattern then " '" .. pattern .. "'" else "", if ok then "no error" else tostring(problem)))
	end
	return matchers
end

function TestKit.expect(value: any)
	local matchers = makeExpect(value, false)
	matchers.never = makeExpect(value, true)
	return matchers
end

--[[
	Runs one spec function. `environment` provides:
	  VisualFX, Mock?, newEngine(options), services = { Lighting, Workspace, Terrain }
	Returns { Passed, Failed, Failures = { { Name, Message } } }.
]]
function TestKit.runSpec(specName: string, spec, environment)
	local results = { Passed = 0, Failed = 0, Failures = {}, Names = {} }
	local tests = {}
	local prefix = {}
	local beforeEach, afterEach = {}, {}

	local t = {}
	t.VisualFX = environment.VisualFX
	t.Mock = environment.Mock
	t.Services = environment.Services
	t.expect = TestKit.expect
	t.deepEqual = deepEqual

	function t.describe(name: string, fn)
		table.insert(prefix, name)
		fn()
		table.remove(prefix)
	end
	function t.it(name: string, fn)
		table.insert(tests, { Name = table.concat(prefix, " > ") .. (if #prefix > 0 then " > " else "") .. name, Fn = fn })
	end
	function t.beforeEach(fn)
		table.insert(beforeEach, fn)
	end
	function t.afterEach(fn)
		table.insert(afterEach, fn)
	end

	local engines = {}
	function t.newEngine(options)
		local opts = options or {}
		if opts.AutoStart == nil then
			opts.AutoStart = false
		end
		local engine = environment.VisualFX.new(opts)
		table.insert(engines, engine)
		return engine
	end

	spec(t)

	for _, test in ipairs(tests) do
		local snapshot = environment.Snapshot and environment.Snapshot()
		local ok, problem = pcall(function()
			for _, hook in ipairs(beforeEach) do
				hook()
			end
			test.Fn()
			for _, hook in ipairs(afterEach) do
				hook()
			end
		end)
		for _, engine in ipairs(engines) do
			pcall(function()
				engine:ResetManagedEffects()
				engine:Destroy()
			end)
		end
		table.clear(engines)
		if environment.Restore and snapshot then
			pcall(environment.Restore, snapshot)
		end
		if ok then
			results.Passed += 1
		else
			results.Failed += 1
			table.insert(results.Failures, { Name = specName .. " > " .. test.Name, Message = tostring(problem) })
		end
		table.insert(results.Names, (if ok then "PASS " else "FAIL ") .. specName .. " > " .. test.Name)
	end
	return results
end

--[[
	Scene snapshot/restore used around each test so tests never leak state
	(and running the suite in Studio leaves the place as it was).
]]
local SNAPSHOT_PROPERTIES = {
	Lighting = { "ClockTime", "Brightness", "ExposureCompensation", "Ambient", "OutdoorAmbient", "ColorShift_Top", "ColorShift_Bottom", "GlobalShadows", "ShadowSoftness", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "FogColor", "FogStart", "FogEnd" },
	Terrain = { "WaterColor", "WaterTransparency", "WaterReflectance", "WaterWaveSize", "WaterWaveSpeed" },
	Workspace = { "GlobalWind" },
}

function TestKit.makeSnapshotter(services)
	local function capture()
		local snapshot = { Properties = {}, Children = {}, Attributes = {} }
		for key, instance in pairs(services) do
			snapshot.Properties[key] = {}
			for _, property in ipairs(SNAPSHOT_PROPERTIES[key] or {}) do
				local ok, value = pcall(function()
					return (instance :: any)[property]
				end)
				if ok then
					snapshot.Properties[key][property] = value
				end
			end
			local children = {}
			for _, child in ipairs(instance:GetChildren()) do
				children[child] = true
			end
			snapshot.Children[key] = children
			snapshot.Attributes[key] = instance:GetAttributes()
		end
		return snapshot
	end
	local function restore(snapshot)
		for key, instance in pairs(services) do
			for _, child in ipairs(instance:GetChildren()) do
				if not snapshot.Children[key][child] and child.ClassName ~= "Terrain" and child.ClassName ~= "Camera" then
					pcall(child.Destroy, child)
				end
			end
			for property, value in pairs(snapshot.Properties[key]) do
				pcall(function()
					(instance :: any)[property] = value
				end)
			end
			for name in pairs(instance:GetAttributes()) do
				if snapshot.Attributes[key][name] == nil then
					instance:SetAttribute(name, nil)
				end
			end
		end
	end
	return capture, restore
end

return TestKit
