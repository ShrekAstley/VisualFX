return function(t)
	local expect = t.expect

	t.describe("Environment, zones and water", function()
		t.it("creates spatial zones at their position", function()
			local engine = t.newEngine()
			local result = engine:CreateZone("ForestFog", {
				Position = Vector3.new(0, 30, 0),
				Size = Vector3.new(500, 100, 500),
				Effect = "Fog",
				Intensity = 0.7,
			})
			expect(result.Success).toBe(true)
			local host = engine.InstanceManager:Find("zone.ForestFog.host")
			expect(host.Position).toBe(Vector3.new(0, 30, 0))
			expect(host.Size).toBe(Vector3.new(500, 100, 500))
			local emitter = engine.InstanceManager:Find("zone.ForestFog")
			expect(emitter.Rate).toBeGreaterThan(0)
			expect(engine:RemoveZone("ForestFog").Success).toBe(true)
			expect(engine.InstanceManager:Find("zone.ForestFog")).toBeNil()
		end)

		t.it("culls distant zones on clients", function()
			local engine = t.newEngine({ RuntimeControllers = true, CameraEffects = true })
			engine:CreateZone("Far", { Position = Vector3.new(5000, 0, 0), Size = Vector3.new(20, 20, 20), Effect = "Mist" })
			engine:CreateZone("Near", { Position = Vector3.new(0, 0, 0), Size = Vector3.new(20, 20, 20), Effect = "Mist" })
			engine:Step(0.2)
			expect(engine.InstanceManager:Find("zone.Far").Enabled).toBe(false)
			expect(engine.InstanceManager:Find("zone.Near").Enabled).toBe(true)
			expect(engine:GetPerformanceStats().CulledParticleSystems).toBe(1)
		end)

		t.it("keeps camera-attached systems above the camera", function()
			local engine = t.newEngine({ RuntimeControllers = true, CameraEffects = true })
			engine:CreateWeather("Snow")
			workspace.CurrentCamera.CFrame = CFrame.new(100, 10, -50)
			engine:Step(0.2)
			local host = engine.InstanceManager:Find("weather.snow.primary.host")
			expect(host.Position).toBe(Vector3.new(100, 55, -50))
			-- Re-applying the scene does not fight the controller.
			local result = engine:UpdateWeather({ Intensity = 0.61 })
			expect(result.Success).toBe(true)
			expect(host.Position).toBe(Vector3.new(100, 55, -50))
		end)

		t.it("blends zone atmosphere while the camera is inside", function()
			local engine = t.newEngine({ RuntimeControllers = true, CameraEffects = true })
			engine:SetAtmosphere({ Density = 0.3 })
			engine:CreateZone("Bank", {
				Position = Vector3.new(0, 0, 0),
				Size = Vector3.new(100, 50, 100),
				Effect = "Fog",
				Intensity = 1,
				Atmosphere = { Density = 0.8 },
			})
			workspace.CurrentCamera.CFrame = CFrame.new(0, 5, 0)
			engine:Step(0.2)
			local atmosphere = engine.InstanceManager:Find("atmosphere.primary")
			expect(atmosphere.Density).toBeCloseTo(0.8)
			workspace.CurrentCamera.CFrame = CFrame.new(1000, 5, 0)
			engine:Step(0.2)
			expect(atmosphere.Density).toBeCloseTo(0.3)
		end)

		t.it("advances the day/night cycle", function()
			local engine = t.newEngine({ RuntimeControllers = true })
			engine:SetDayNightCycle({ Enabled = true, DayLength = 1, StartTime = 6 })
			expect(t.Services.Lighting.ClockTime).toBe(6)
			for _ = 1, 50 do
				engine:Step(0.1) -- 5 seconds = 2 in-game hours at 1 minute per day
			end
			expect(t.Services.Lighting.ClockTime).toBeCloseTo(8, 0.05)
			-- Re-applying does not reset the running clock.
			engine:UpdateScene({ Atmosphere = { Density = 0.3 } })
			expect(t.Services.Lighting.ClockTime).toBeCloseTo(8, 0.05)
		end)

		t.it("drives lighting colors through keyframes", function()
			local engine = t.newEngine({ RuntimeControllers = true })
			engine:SetDayNightCycle({ Enabled = true, DayLength = 1, StartTime = 12, DriveLighting = true })
			local noon = t.Services.Lighting.Brightness
			for _ = 1, 150 do
				engine:Step(0.1) -- +6 hours
			end
			expect(t.Services.Lighting.Brightness < noon).toBe(true)
		end)

		t.it("sets wind", function()
			local engine = t.newEngine()
			engine:SetWind({ Direction = Vector3.new(0, 0, 2), Speed = 10 })
			expect(t.Services.Workspace.GlobalWind).toBe(Vector3.new(0, 0, 10))
		end)

		t.it("configures terrain water with aliases", function()
			local engine = t.newEngine()
			local result = engine:SetWater({
				Color = Color3.fromRGB(35, 90, 120),
				Transparency = 0.25,
				Reflectance = 0.7,
				WaveStrength = 0.35,
				WaveSpeed = 10,
			})
			expect(result.Success).toBe(true)
			local terrain = t.Services.Terrain
			expect(terrain.WaterColor.G).toBeCloseTo(90 / 255)
			expect(terrain.WaterTransparency).toBeCloseTo(0.25)
			expect(terrain.WaterWaveSize).toBeCloseTo(0.35)
			local live = engine.Water:Get()
			expect(live.WaveSize).toBeCloseTo(0.35)
		end)

		t.it("toggles the underwater look when the camera enters water", function()
			if not t.Mock then
				return -- requires simulated terrain water
			end
			local engine = t.newEngine({ RuntimeControllers = true, CameraEffects = true })
			engine:SetWater({ Underwater = { Enabled = true, BlurSize = 6 } })
			local tint = engine.InstanceManager:Find("water.underwater.colorcorrection")
			expect(tint.Enabled).toBe(false)
			table.insert(t.Mock.WaterRegions, { Min = Vector3.new(-50, -50, -50), Max = Vector3.new(50, 0, 50) })
			workspace.CurrentCamera.CFrame = CFrame.new(0, -10, 0)
			engine:Step(0.3)
			expect(tint.Enabled).toBe(true)
			workspace.CurrentCamera.CFrame = CFrame.new(0, 20, 0)
			engine:Step(0.3)
			expect(tint.Enabled).toBe(false)
			table.clear(t.Mock.WaterRegions)
		end)
	end)
end
