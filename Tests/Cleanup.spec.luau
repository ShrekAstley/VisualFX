return function(t)
	local expect = t.expect

	t.describe("Cleanup and preview", function()
		t.it("ResetManagedEffects removes managed instances and restores originals", function()
			local engine = t.newEngine()
			local lighting = t.Services.Lighting
			local terrain = t.Services.Terrain
			local brightness, waterColor = lighting.Brightness, terrain.WaterColor
			engine:ApplyPreset("Ocean")
			engine:CreateWeather("Thunderstorm")
			expect(lighting.Brightness ~= brightness).toBe(true)
			local result = engine:ResetManagedEffects()
			expect(result.Success).toBe(true)
			expect(#engine.InstanceManager:GetManaged(true)).toBe(0)
			expect(lighting.Brightness).toBeCloseTo(brightness)
			expect(terrain.WaterColor).toBe(waterColor)
			expect(t.Services.Workspace.GlobalWind).toBe(Vector3.new(0, 0, 0))
			for name in pairs(lighting:GetAttributes()) do
				error("attribute left behind: " .. name)
			end
			expect(t.Services.Workspace:FindFirstChild("VisualFX")).toBeNil()
		end)

		t.it("removing a section restores the service values it managed", function()
			local engine = t.newEngine()
			local lighting = t.Services.Lighting
			engine:SetLighting({ Brightness = 5, ClockTime = 3 })
			engine:UpdateScene({ Lighting = { Brightness = "$remove" } })
			expect(lighting.Brightness).toBeCloseTo(2)
			expect(lighting.ClockTime).toBe(3)
			engine.Lighting:Reset()
			expect(lighting.ClockTime).toBe(14)
		end)

		t.it("original values survive a new engine session (stored in attributes)", function()
			local first = t.newEngine()
			first:SetLighting({ Brightness = 7 })
			local second = t.newEngine()
			second:ResetManagedEffects()
			expect(t.Services.Lighting.Brightness).toBeCloseTo(2)
		end)

		t.it("previews can be reverted exactly", function()
			local engine = t.newEngine()
			engine:ApplyPreset("Night")
			local exported = engine:ExportConfiguration({ Format = "json" })
			local managedBefore = #engine.InstanceManager:GetManaged(true)
			local clock = t.Services.Lighting.ClockTime
			local preview = engine:Preview({ Weather = { Type = "Blizzard" }, Lighting = { ClockTime = 12 } })
			expect(preview.Success).toBe(true)
			expect(engine:IsPreviewing()).toBe(true)
			expect(t.Services.Lighting.ClockTime).toBe(12)
			local reverted = engine:RevertPreview()
			expect(reverted.Success).toBe(true)
			expect(t.Services.Lighting.ClockTime).toBe(clock)
			expect(#engine.InstanceManager:GetManaged(true)).toBe(managedBefore)
			expect(engine:ExportConfiguration({ Format = "json" })).toBe(exported)
		end)

		t.it("reverting keeps edits a developer made during the preview", function()
			local engine = t.newEngine()
			engine:Preview({ Lighting = { Brightness = 4, ExposureCompensation = 0.5 } })
			t.Services.Lighting.ExposureCompensation = -1 -- developer edit
			local reverted = engine:RevertPreview()
			expect(t.Services.Lighting.Brightness).toBeCloseTo(2)
			expect(t.Services.Lighting.ExposureCompensation).toBe(-1)
			expect(#reverted.Warnings).toBe(1)
		end)

		t.it("previews can be committed", function()
			local engine = t.newEngine()
			engine:Preview({ Atmosphere = { Density = 0.5 } })
			local committed = engine:CommitPreview()
			expect(committed.Success).toBe(true)
			expect(engine:IsPreviewing()).toBe(false)
			expect(engine.InstanceManager:Find("atmosphere.primary")).never.toBeNil()
			expect(engine:RevertPreview().Success).toBe(false)
		end)

		t.it("reuses pooled emitter hosts", function()
			local engine = t.newEngine()
			engine:CreateParticleSystem("A", { Template = "Dust" })
			engine:RemoveParticleSystem("A")
			expect(engine.InstanceManager:GetPoolSize()).toBeGreaterThan(0)
			engine:CreateParticleSystem("B", { Template = "Dust" })
			expect(engine.InstanceManager:Find("particles.B")).never.toBeNil()
		end)

		t.it("Destroy disconnects the scheduler", function()
			if not t.Mock then
				return -- inspects mock signal internals
			end
			local engine = t.newEngine({ AutoStart = true })
			local heartbeat = game:GetService("RunService").Heartbeat
			local before = #heartbeat._connections
			engine:Destroy()
			expect(#heartbeat._connections).toBe(before - 1)
		end)
	end)
end
