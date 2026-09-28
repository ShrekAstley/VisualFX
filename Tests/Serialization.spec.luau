return function(t)
	local expect = t.expect
	local Package = t.VisualFX
	local Serialization

	t.beforeEach(function()
		Serialization = require(game:GetService("ReplicatedStorage").VisualFX.Core.Serialization)
	end)

	local function sample()
		return {
			Version = 1,
			Metadata = { Name = "Sample", Tags = { "a", "b" } },
			Lighting = { ClockTime = 18.5, Brightness = 2, Ambient = Color3.fromRGB(70, 50, 60), GlobalShadows = true },
			Particles = {
				Rain = {
					Template = "Rain",
					Lifetime = NumberRange.new(1, 2),
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.3, 0.05), NumberSequenceKeypoint.new(1, 0) }),
					Color = ColorSequence.new(Color3.fromRGB(180, 200, 255), Color3.fromRGB(20, 30, 40)),
					Acceleration = Vector3.new(0, -40, 2.5),
					SpreadAngle = Vector2.new(3, 3),
					Shape = Enum.ParticleEmitterShape.Box,
				},
			},
		}
	end

	t.describe("Serialization", function()
		t.it("round-trips every supported Roblox datatype", function()
			local original = sample()
			local encoded = Serialization:EncodeValue(original)
			local decoded = Serialization:DecodeValue(encoded)
			local Values = require(game:GetService("ReplicatedStorage").VisualFX.Core.Values)
			expect(Values.equal(decoded, original)).toBe(true)
		end)

		t.it("produces deterministic JSON", function()
			local a = Serialization:Export(sample())
			local b = Serialization:Export(sample())
			expect(a).toBe(b)
			expect(a).toContain('"Format": "VisualFXConfig"')
			-- Priority keys come first.
			local versionAt = string.find(a, '"Version"', 1, true)
			local sceneAt = string.find(a, '"Scene"', 1, true)
			expect(versionAt < sceneAt).toBe(true)
		end)

		t.it("parses its own JSON back to equal data", function()
			local json = Serialization:Export(sample())
			local config, warnings, problem = Serialization:Deserialize(json)
			expect(problem).toBeNil()
			expect(#warnings).toBe(0)
			local again = Serialization:Export(config)
			expect(again).toBe(json)
		end)

		t.it("reports malformed JSON with a location", function()
			local config, _, problem = Serialization:Deserialize('{"Format": "VisualFXConfig", "Scene": {')
			expect(config).toBeNil()
			expect(problem).toContain("JSON parse error")
		end)

		t.it("warns about unknown tagged values instead of failing", function()
			local config, warnings = Serialization:Deserialize({ Lighting = { Ambient = { ["$type"] = "Mystery" } } })
			expect(config).never.toBeNil()
			expect(#warnings).toBe(1)
		end)

		t.it("escapes strings safely", function()
			local text = Serialization:ToJSON({ Name = 'quote " backslash \\ newline \n tab \t' }, false)
			local decoded = Serialization:FromJSON(text)
			expect(decoded.Name).toBe('quote " backslash \\ newline \n tab \t')
		end)

		t.it("exports and imports through the engine with validation", function()
			local engine = t.newEngine()
			expect(engine:ApplyPreset("CinematicSunset").Success).toBe(true)
			local json = engine:ExportConfiguration({ Format = "json" })
			local other = t.newEngine()
			local imported = other:ImportConfiguration(json)
			expect(imported.Success).toBe(true)
			expect(other:ExportConfiguration({ Format = "json" })).toBe(json)
		end)

		t.it("rejects invalid imports with useful errors and applies nothing", function()
			local engine = t.newEngine()
			local lighting = t.Services.Lighting
			local before = lighting.Brightness
			local result = engine:ImportConfiguration('{"Format":"VisualFXConfig","Version":1,"Scene":{"Lighting":{"ExposureCompensation":"high","Brightness":5}}}')
			expect(result.Success).toBe(false)
			expect(result.Errors[1]).toContain("Lighting.ExposureCompensation")
			expect(result.Errors[1]).toContain("Expected:\nnumber")
			expect(lighting.Brightness).toBe(before)
		end)

		t.it("serializes per-effect configuration", function()
			local engine = t.newEngine()
			engine.Atmosphere:Set({ Density = 0.4, Color = Color3.fromRGB(10, 20, 30) })
			local data = engine.Atmosphere:Serialize()
			expect(data.Color["$type"]).toBe("Color3")
			local restored = engine.Atmosphere:Deserialize(data)
			expect(restored.Color).toBe(Color3.fromRGB(10, 20, 30))
			expect(Package.REMOVE).toBe("$remove")
		end)
	end)
end
