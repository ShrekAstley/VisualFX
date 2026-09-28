return function(t)
	local expect = t.expect

	local function countDescendants(root)
		local counts = {}
		for _, instance in ipairs(root:GetDescendants()) do
			counts[instance.ClassName] = (counts[instance.ClassName] or 0) + 1
		end
		return counts
	end

	local function sceneFingerprint()
		local lighting = countDescendants(t.Services.Lighting)
		local world = countDescendants(t.Services.Workspace)
		return lighting, world
	end

	t.describe("Duplicate prevention", function()
		t.it("repeated ApplyPreset(\"HeavyRain\") never creates additional instances", function()
			local engine = t.newEngine()
			local first = engine:ApplyPreset("HeavyRain")
			expect(first.Success).toBe(true)
			local lightingA, worldA = sceneFingerprint()
			local managedA = #engine.InstanceManager:GetManaged(true)
			for _ = 1, 5 do
				local again = engine:ApplyPreset("HeavyRain")
				expect(again.Success).toBe(true)
				expect(#again.Created).toBe(0)
				expect(#again.Modified).toBe(0)
			end
			local lightingB, worldB = sceneFingerprint()
			expect(t.deepEqual(lightingA, lightingB)).toBe(true)
			expect(t.deepEqual(worldA, worldB)).toBe(true)
			expect(#engine.InstanceManager:GetManaged(true)).toBe(managedA)
		end)

		t.it("a second engine reuses instances created by the first (identity survives)", function()
			local first = t.newEngine()
			first:ApplyPreset("HeavyRain")
			local managed = #first.InstanceManager:GetManaged(true)
			local second = t.newEngine()
			local result = second:ApplyPreset("HeavyRain")
			expect(#result.Created).toBe(0)
			expect(#second.InstanceManager:GetManaged(true)).toBe(managed)
		end)

		t.it("collapses duplicate managed instances", function()
			local engine = t.newEngine()
			engine:SetAtmosphere({ Density = 0.4 })
			local atmosphere = engine.InstanceManager:Find("atmosphere.primary")
			local copy = atmosphere:Clone()
			copy.Parent = t.Services.Lighting
			expect(#engine.InstanceManager:FindAll("atmosphere.primary")).toBe(2)
			local result = engine:SetAtmosphere({ Density = 0.45 })
			expect(result.Success).toBe(true)
			expect(#engine.InstanceManager:FindAll("atmosphere.primary")).toBe(1)
		end)

		t.it("adopts an existing developer Atmosphere instead of duplicating it", function()
			local engine = t.newEngine()
			local developer = Instance.new("Atmosphere")
			developer.Name = "DeveloperAtmosphere"
			developer.Density = 0.2
			developer.Parent = t.Services.Lighting
			local result = engine:SetAtmosphere({ Density = 0.5, Haze = 3 })
			expect(result.Success).toBe(true)
			local atmospheres = 0
			for _, child in ipairs(t.Services.Lighting:GetChildren()) do
				if child.ClassName == "Atmosphere" then
					atmospheres += 1
				end
			end
			expect(atmospheres).toBe(1)
			expect(developer.Density).toBeCloseTo(0.5)
			expect(engine.InstanceManager:IsAdopted(developer)).toBe(true)
			-- Removing the effect restores the developer's values and releases it.
			engine.Atmosphere:Remove()
			expect(developer.Parent).toBe(t.Services.Lighting)
			expect(developer.Density).toBeCloseTo(0.2)
			expect(developer.Haze).toBe(0)
			expect(engine.InstanceManager:IsManaged(developer)).toBe(false)
		end)

		t.it("does not adopt when AdoptExisting is disabled", function()
			local engine = t.newEngine({ AdoptExisting = false })
			local developer = Instance.new("Atmosphere")
			developer.Parent = t.Services.Lighting
			engine:SetAtmosphere({ Density = 0.5 })
			expect(engine.InstanceManager:IsManaged(developer)).toBe(false)
		end)

		t.it("never deletes developer or unknown instances", function()
			local engine = t.newEngine()
			local folder = Instance.new("Folder")
			folder.Name = "DeveloperStuff"
			folder.Parent = t.Services.Lighting
			local emitterHost = Instance.new("Part")
			emitterHost.Parent = t.Services.Workspace
			local emitter = Instance.new("ParticleEmitter")
			emitter.Parent = emitterHost
			local bloom = Instance.new("ColorCorrectionEffect")
			bloom.Parent = t.Services.Lighting
			engine:ApplyPreset("Storm")
			engine:ApplyPreset("Tropical")
			engine:ResetManagedEffects()
			expect(folder.Parent).toBe(t.Services.Lighting)
			expect(emitter.Parent).toBe(emitterHost)
			expect(bloom.Parent).toBe(t.Services.Lighting)
			expect(engine.InstanceManager:Remove(folder)).toBe(false)
		end)

		t.it("switching weather replaces weather-owned particles instead of accumulating them", function()
			local engine = t.newEngine()
			engine:CreateWeather("HeavyRain", { Intensity = 0.8 })
			expect(engine.InstanceManager:Find("weather.rain.primary")).never.toBeNil()
			engine:CreateWeather("Snow", { Intensity = 0.5 })
			expect(engine.InstanceManager:Find("weather.rain.primary")).toBeNil()
			expect(engine.InstanceManager:Find("weather.snow.primary")).never.toBeNil()
			local emitters = 0
			for _, instance in ipairs(t.Services.Workspace:GetDescendants()) do
				if instance.ClassName == "ParticleEmitter" then
					emitters += 1
				end
			end
			expect(emitters).toBe(1)
		end)

		t.it("marks managed instances with identity attributes and tags", function()
			local engine = t.newEngine()
			engine:CreateWeather("HeavyRain")
			local rain = engine.InstanceManager:Find("weather.rain.primary")
			expect(rain:GetAttribute("VisualFX_Managed")).toBe(true)
			expect(rain:GetAttribute("VisualFX_Type")).toBe("Rain")
			expect(rain:GetAttribute("VisualFX_ID")).toBe("weather.rain.primary")
			expect(rain:HasTag("VisualFX")).toBe(true)
		end)
	end)
end
