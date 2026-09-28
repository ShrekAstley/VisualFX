return function(t)
	local expect = t.expect

	local function find(list, predicate)
		for _, item in ipairs(list) do
			if predicate(item) then
				return item
			end
		end
		return nil
	end

	t.describe("Scene inspector", function()
		t.it("returns every documented section", function()
			local engine = t.newEngine()
			local scene = engine:InspectScene()
			for _, key in ipairs({ "Lighting", "Atmosphere", "PostProcessing", "Water", "Weather", "Particles", "ManagedEffects", "Conflicts", "Quality", "Configuration", "Summary" }) do
				expect(scene[key] ~= nil).toBe(true)
			end
			expect(scene.Lighting.Properties.ClockTime).toBe(14)
		end)

		t.it("classifies managed, adopted, default, developer and unknown objects", function()
			local engine = t.newEngine()
			local lighting = t.Services.Lighting
			local default = Instance.new("SunRaysEffect")
			default.Name = "DefaultRays"
			default.Parent = lighting
			local developer = Instance.new("ColorCorrectionEffect")
			developer.Name = "DevGrade"
			developer.Saturation = 0.3
			developer.Parent = lighting
			local unknown = Instance.new("StringValue")
			unknown.Parent = lighting
			engine:SetAtmosphere({ Density = 0.3 })
			local sky = Instance.new("Sky")
			sky.Parent = lighting
			engine:SetSky({ StarCount = 100 })

			local scene = engine:InspectScene()
			expect(scene.Atmosphere[1].Classification).toBe("Managed")
			expect(scene.Sky[1].Classification).toBe("Adopted")
			local rays = find(scene.PostProcessing, function(item)
				return item.Name == "DefaultRays"
			end)
			expect(rays.Classification).toBe("RobloxDefault")
			local grade = find(scene.PostProcessing, function(item)
				return item.Name == "DevGrade"
			end)
			expect(grade.Classification).toBe("Developer")
			expect(#scene.Unknown).toBe(1)
			expect(scene.Unknown[1].ClassName).toBe("StringValue")
		end)

		t.it("lists managed effects with identity", function()
			local engine = t.newEngine()
			engine:CreateWeather("Thunderstorm")
			local scene = engine:InspectScene()
			local rain = find(scene.ManagedEffects, function(item)
				return item.ID == "weather.rain.primary"
			end)
			expect(rain.Type).toBe("Rain")
			expect(rain.Owner).toBe("Weather")
			expect(scene.Weather.Active).toBe(true)
			expect(scene.Weather.Type).toBe("Thunderstorm")
			expect(scene.Weather.Components).toContain("Lightning")
			expect(scene.Weather.Components).toContain("AmbientAudioHooks")
		end)

		t.it("detects multiple atmospheres, stacked bloom and duplicate identities", function()
			local engine = t.newEngine()
			local lighting = t.Services.Lighting
			for _ = 1, 2 do
				Instance.new("Atmosphere").Parent = lighting
				Instance.new("BloomEffect").Parent = lighting
			end
			local conflicts = engine:DetectConflicts()
			expect(find(conflicts, function(c)
				return c.Code == "MultipleAtmosphere"
			end) ~= nil).toBe(true)
			expect(find(conflicts, function(c)
				return c.Code == "StackedBloomEffect"
			end) ~= nil).toBe(true)

			engine:SetClouds({ Cover = 0.5 })
			local clouds = engine.InstanceManager:Find("clouds.primary")
			clouds:Clone().Parent = t.Services.Terrain
			conflicts = engine:DetectConflicts()
			local duplicate = find(conflicts, function(c)
				return c.Code == "DuplicateManagedID"
			end)
			expect(duplicate.Severity).toBe("Error")
		end)

		t.it("reports ignored legacy fog", function()
			local engine = t.newEngine()
			t.Services.Lighting.FogEnd = 500
			Instance.new("Atmosphere").Parent = t.Services.Lighting
			local conflicts = engine:DetectConflicts()
			expect(find(conflicts, function(c)
				return c.Code == "FogIgnored"
			end) ~= nil).toBe(true)
		end)

		t.it("summarizes the scene in readable lines", function()
			local engine = t.newEngine()
			engine:ApplyPreset("MoonlitNight")
			local scene = engine:InspectScene()
			expect(scene.Summary[1]).toContain("ClockTime 23.5")
		end)
	end)
end
