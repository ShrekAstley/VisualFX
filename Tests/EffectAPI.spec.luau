return function(t)
	local expect = t.expect

	t.describe("Per-effect APIs", function()
		t.it("Atmosphere supports all nine operations", function()
			local engine = t.newEngine()
			local api = engine.Atmosphere
			expect(api:Create({ Density = 0.35, Haze = 2, Glare = 0.15, Color = Color3.fromRGB(190, 205, 220), Decay = Color3.fromRGB(80, 100, 120) }).Success).toBe(true)
			expect(api:Get().Haze).toBeCloseTo(2)
			expect(api:Update({ Haze = 3 }).Success).toBe(true)
			expect(api:GetConfiguration().Density).toBe(0.35)
			expect(api:Set({ Haze = 1 }).Success).toBe(true)
			expect(api:GetConfiguration().Density).toBeNil()
			local data = api:Serialize()
			expect(data.Haze).toBe(1)
			expect(t.deepEqual(api:Deserialize(data), { Haze = 1 })).toBe(true)
			expect(api:Validate({ Density = 3 }).Success).toBe(false)
			expect(api:Remove().Success).toBe(true)
			expect(engine.InstanceManager:Find("atmosphere.primary")).toBeNil()
			expect(api:Reset().Success).toBe(true)
		end)

		t.it("post-processing effects expose the same operations", function()
			local engine = t.newEngine()
			local bloom = engine.PostProcessing.Bloom
			expect(bloom:Create({ Intensity = 0.6 }).Success).toBe(true)
			expect(bloom:Get().Intensity).toBeCloseTo(0.6)
			bloom:Update({ Size = 40 })
			expect(engine.InstanceManager:Find("postprocessing.bloom").Size).toBe(40)
			bloom:Remove()
			expect(engine.InstanceManager:Find("postprocessing.bloom")).toBeNil()
		end)

		t.it("particle systems are addressable by name", function()
			local engine = t.newEngine()
			local particles = engine.Particles
			particles:Create("Rain", {
				Rate = 600,
				Lifetime = NumberRange.new(1, 2),
				Speed = NumberRange.new(80, 120),
				Size = NumberSequence.new(0.08),
				Color = ColorSequence.new(Color3.fromRGB(180, 200, 255)),
				Transparency = NumberSequence.new(0.35),
			})
			expect(particles:List()).toContain("Rain")
			expect(particles:Get("Rain").Rate).toBe(600)
			particles:Update("Rain", { Rate = 300 })
			expect(particles:Get("Rain").Rate).toBe(300)
			expect(particles:Validate("Rain", { Rate = -1 }).Success).toBe(false)
			particles:Remove("Rain")
			expect(#particles:List()).toBe(0)
		end)

		t.it("the documented top-level API works", function()
			local engine = t.newEngine()
			expect(engine:SetAtmosphere({ Density = 0.35, Haze = 2, Glare = 0.15, Color = Color3.fromRGB(190, 205, 220), Decay = Color3.fromRGB(80, 100, 120) }).Success).toBe(true)
			expect(engine:SetWater({ Color = Color3.fromRGB(35, 90, 120), Transparency = 0.25, Reflectance = 0.7, WaveStrength = 0.35, WaveSpeed = 10 }).Success).toBe(true)
			expect(engine:CreateParticleSystem("Rain", { Rate = 600, Lifetime = NumberRange.new(1, 2), Speed = NumberRange.new(80, 120), Size = NumberSequence.new(0.08), Color = ColorSequence.new(Color3.fromRGB(180, 200, 255)), Transparency = NumberSequence.new(0.35) }).Success).toBe(true)
			expect(engine:CreateWeather("HeavyRain", { Intensity = 0.8, Wind = 25, Fog = 0.3, Lightning = true }).Success).toBe(true)
			expect(engine:CreateZone("ForestFog", { Position = Vector3.new(0, 30, 0), Size = Vector3.new(500, 100, 500), Effect = "Fog", Intensity = 0.7 }).Success).toBe(true)
			expect(engine:SetLighting({ ClockTime = 18.5, Brightness = 2, ExposureCompensation = 0.2 }).Success).toBe(true)
			expect(engine:UpdateScene({ Lighting = { Brightness = 2.2 } }).Success).toBe(true)
		end)

		t.it("the module-level default engine accepts colon calls", function()
			local VisualFX = t.VisualFX
			local result = VisualFX:ApplyPreset("Sunrise")
			expect(result.Success).toBe(true)
			expect(VisualFX:GetConfiguration().Lighting.ClockTime).toBe(6.4)
			VisualFX:ResetManagedEffects()
			VisualFX.GetDefault():Stop()
		end)
	end)
end
