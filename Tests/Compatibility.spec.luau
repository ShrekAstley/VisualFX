return function(t)
	local expect = t.expect

	t.describe("Compatibility", function()
		t.it("detects supported properties by inspecting the engine", function()
			local engine = t.newEngine()
			local compatibility = engine.Compatibility
			expect(compatibility:IsSupported("Lighting.EnvironmentDiffuseScale")).toBe(true)
			expect(compatibility:IsSupported("Lighting.NotARealProperty")).toBe(false)
			local info = compatibility:GetPropertySupport("Atmosphere", "Density")
			expect(info.Supported).toBe(true)
			expect(info.ValueType).toBe("number")
			expect(info.Default).toBeCloseTo(0.395, 1e-4)
			expect(compatibility:IsSupported("NoSuchClass")).toBe(false)
		end)

		t.it("skips unsupported properties but applies the rest", function()
			if not t.Mock then
				return -- engine differences can only be simulated under the mock
			end
			t.Mock.removeProperty("ParticleEmitter", "Squash")
			local ok, problem = pcall(function()
				local engine = t.newEngine()
				local result = engine:CreateParticleSystem("Rain", { Template = "Rain", Rate = 100 })
				expect(result.Success).toBe(true)
				local found = false
				for _, warning in ipairs(result.Warnings) do
					if string.find(warning, "Squash", 1, true) then
						found = true
					end
				end
				expect(found).toBe(true)
				local emitter = engine.InstanceManager:Find("particles.Rain")
				expect(emitter).never.toBeNil()
				expect(emitter.Rate).toBe(100)
			end)
			t.Mock.restoreProperty("ParticleEmitter", "Squash")
			if not ok then
				error(problem, 0)
			end
		end)

		t.it("reports properties the engine refuses to set", function()
			local engine = t.newEngine()
			local result = engine:SetLighting({ Technology = "Future", Brightness = 3 })
			expect(result.Success).toBe(true)
			expect(t.Services.Lighting.Brightness).toBe(3)
			local mentioned = false
			for _, warning in ipairs(result.Warnings) do
				if string.find(warning, "Technology", 1, true) then
					mentioned = true
				end
			end
			expect(mentioned).toBe(true)
		end)

		t.it("warns during validation when a property is unavailable", function()
			if not t.Mock then
				return
			end
			t.Mock.removeProperty("Lighting", "EnvironmentDiffuseScale")
			local ok, problem = pcall(function()
				local engine = t.newEngine()
				local report = engine:Validate({ Lighting = { EnvironmentDiffuseScale = 0.5 } })
				expect(report.Success).toBe(true)
				expect(report.Warnings[1].Code).toBe("UnsupportedProperty")
			end)
			t.Mock.restoreProperty("Lighting", "EnvironmentDiffuseScale")
			if not ok then
				error(problem, 0)
			end
		end)

		t.it("builds a compatibility report from the schema", function()
			local engine = t.newEngine()
			local report = engine:GetCompatibilityReport()
			expect(#report.Supported).toBeGreaterThan(40)
			expect(report.Supported).toContain("Lighting.ClockTime")
			expect(report.Supported).toContain("PostProcessing.Bloom.Intensity")
		end)
	end)
end
