return function(t)
	local expect = t.expect

	local DESCRIPTION = {
		Mood = "mysterious",
		Time = "sunset",
		Weather = "light_rain",
		Environment = "dense_forest",
		Fog = "medium",
		LightingStyle = "cinematic",
		WaterStyle = "calm_reflective",
	}

	t.describe("Visual Director", function()
		t.it("interprets descriptions deterministically", function()
			local engine = t.newEngine()
			local a = engine.Director:Interpret(DESCRIPTION)
			local b = engine.Director:Interpret(DESCRIPTION)
			expect(t.deepEqual(a.Configuration, b.Configuration)).toBe(true)
			expect(a.Configuration.Lighting.ClockTime).toBe(17.9)
			expect(a.Configuration.Weather.Type).toBe("LightRain")
			expect(a.Configuration.Weather.Fog).toBe(0.45)
			expect(a.Configuration.Water.WaveSize).toBe(0.05)
			expect(a.Configuration.PostProcessing.DepthOfField.FarIntensity).toBe(0.12)
			expect(#a.Warnings).toBe(0)
		end)

		t.it("creates a scene and returns the documented result shape", function()
			local engine = t.newEngine()
			local result = engine:CreateScene(DESCRIPTION)
			expect(result.Success).toBe(true)
			expect(result.Created).toContain("Rain")
			expect(typeof(result.Modified)).toBe("table")
			expect(typeof(result.Removed)).toBe("table")
			expect(typeof(result.Warnings)).toBe("table")
			expect(result.Configuration.Weather.Type).toBe("LightRain")
			expect(result.Inspection.Summary ~= nil).toBe(true)
		end)

		t.it("reuses and modifies existing effects instead of recreating them", function()
			local engine = t.newEngine()
			engine:CreateScene(DESCRIPTION)
			local atmosphere = engine.InstanceManager:Find("atmosphere.primary")
			local next = table.clone(DESCRIPTION)
			next.Time = "night"
			local result = engine:CreateScene(next)
			expect(result.Success).toBe(true)
			expect(engine.InstanceManager:Find("atmosphere.primary")).toBe(atmosphere)
			expect(result.Modified).toContain("Lighting")
			-- Night swaps daytime dust for fireflies; everything else is reused.
			expect(t.deepEqual(result.Created, { "Fireflies" })).toBe(true)
			expect(result.Removed).toContain("Dust")
		end)

		t.it("removes conflicting effects when the description changes", function()
			local engine = t.newEngine()
			engine:CreateScene({ Time = "noon", Weather = "heavy_rain" })
			local result = engine:CreateScene({ Time = "noon", Weather = "snow" })
			expect(result.Removed).toContain("Rain")
			expect(result.Created).toContain("Snow")
		end)

		t.it("warns about unknown vocabulary with suggestions", function()
			local engine = t.newEngine()
			local result = engine:CreateScene({ Mood = "mysterius", Weather = "rainy", Environment = "atlantis" })
			expect(result.Success).toBe(true)
			local text = table.concat(result.Warnings, "\n")
			expect(text).toContain("Mysterious")
			expect(text).toContain("atlantis")
			expect(result.Configuration.Weather.Type).toBe("LightRain")
		end)

		t.it("accepts numbers for time and fog and explicit overrides", function()
			local engine = t.newEngine()
			local interpreted = engine.Director:Interpret({ Time = 21.5, Fog = 0.8, Lighting = { Brightness = 0.7 } })
			expect(interpreted.Configuration.Lighting.ClockTime).toBe(21.5)
			expect(interpreted.Configuration.Lighting.Brightness).toBe(0.7)
			expect(interpreted.Configuration.Particles.Mist ~= nil).toBe(true)
		end)

		t.it("distinguishes descriptions from configurations", function()
			local engine = t.newEngine()
			expect(engine.Director:IsDescription({ Mood = "calm" })).toBe(true)
			expect(engine.Director:IsDescription({ Environment = "desert" })).toBe(true)
			expect(engine.Director:IsDescription({ Lighting = { ClockTime = 3 } })).toBe(false)
			expect(engine.Director:IsDescription({ Environment = { Wind = { Speed = 3 } } })).toBe(false)
		end)

		t.it("publishes its vocabulary", function()
			local engine = t.newEngine()
			local vocabulary = engine.Director:Vocabulary()
			expect(vocabulary.Mood).toContain("Mysterious")
			expect(vocabulary.Environment).toContain("DenseForest")
			expect(vocabulary.Weather).toContain("Thunderstorm")
		end)
	end)
end
