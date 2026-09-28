return function(t)
	local expect = t.expect

	local ALL_TYPES = {
		"Clear", "Cloudy", "Overcast", "LightRain", "HeavyRain", "Thunderstorm", "Snow", "Blizzard", "Fog",
		"DustStorm", "Sandstorm", "Windy", "Autumn", "MagicalStorm", "Custom",
	}

	t.describe("Weather", function()
		t.it("registers every built-in weather type", function()
			local engine = t.newEngine()
			local registered = engine.Weather:Types()
			for _, name in ipairs(ALL_TYPES) do
				expect(registered).toContain(name)
			end
		end)

		t.it("every weather type applies", function()
			local engine = t.newEngine()
			for _, name in ipairs(ALL_TYPES) do
				local result = engine:CreateWeather(name, { Intensity = 0.7 })
				if not result.Success then
					error(name .. ": " .. table.concat(result.Errors, "; "))
				end
			end
		end)

		t.it("composes a thunderstorm from lower-level systems", function()
			local engine = t.newEngine()
			local result = engine:CreateWeather("Thunderstorm", { RainIntensity = 0.9, Fog = 0.4, Wind = 35, Lightning = true })
			expect(result.Success).toBe(true)
			expect(result.Created).toContain("Rain")
			expect(result.Created).toContain("Lightning")
			expect(result.Created).toContain("Atmosphere")
			local wind = t.Services.Workspace.GlobalWind
			expect(wind.Magnitude).toBeCloseTo(35, 0.01)
			local rain = engine.InstanceManager:Find("weather.rain.primary")
			expect(rain.Rate).toBeCloseTo(1300 * 0.9, 1)
			local weather = engine:GetWeather()
			expect(weather.Components).toContain("Lightning")
			expect(weather.AudioHooks).toContain("Thunder")
		end)

		t.it("scales with intensity and blends toward weather targets", function()
			local engine = t.newEngine()
			engine:SetLighting({ Brightness = 3 })
			engine:CreateWeather("HeavyRain", { Intensity = 0.5, Fog = 0 })
			-- 3 blended halfway toward HeavyRain's target of 1.1
			expect(t.Services.Lighting.Brightness).toBeCloseTo(2.05, 0.01)
			local rain = engine.InstanceManager:Find("weather.rain.primary")
			expect(rain.Rate).toBeCloseTo(1100 * 0.5, 1)
		end)

		t.it("removes everything it created", function()
			local engine = t.newEngine()
			engine:CreateWeather("Blizzard")
			local result = engine:RemoveWeather()
			expect(result.Success).toBe(true)
			expect(result.Removed).toContain("Snow")
			expect(engine.InstanceManager:Find("weather.snow.primary")).toBeNil()
			expect(engine.InstanceManager:Find("atmosphere.primary")).toBeNil()
			expect(t.Services.Workspace.GlobalWind).toBe(Vector3.new(0, 0, 0))
		end)

		t.it("fires audio hooks without playing audio", function()
			local engine = t.newEngine()
			local events = {}
			engine.Events.AudioHook:Connect(function(hook)
				table.insert(events, hook.Action .. ":" .. hook.Hook)
			end)
			engine:CreateWeather("HeavyRain")
			expect(events).toContain("Start:Rain")
			expect(events).toContain("Start:Wind")
			engine:CreateWeather("Clear")
			expect(events).toContain("Stop:Rain")
			expect(events).toContain("Start:Birds")
		end)

		t.it("strikes lightning deterministically from a seed", function()
			local function strikes(seed)
				local engine = t.newEngine({ RuntimeControllers = true })
				engine:CreateWeather("Thunderstorm", { LightningFrequency = 30, Seed = seed })
				local times = {}
				engine.Events.LightningStrike:Connect(function()
					table.insert(times, engine._stats.Steps)
				end)
				for _ = 1, 400 do
					engine:Step(0.1)
				end
				engine:ResetManagedEffects()
				return times
			end
			local a, b = strikes(7), strikes(7)
			expect(#a).toBeGreaterThan(3)
			expect(t.deepEqual(a, b)).toBe(true)
		end)

		t.it("the flash effect returns to neutral between strikes", function()
			local engine = t.newEngine({ RuntimeControllers = true })
			engine:CreateWeather("Thunderstorm")
			local lightning
			for _, controller in ipairs(engine.Controllers) do
				if controller.Name == "Lightning" then
					lightning = controller
				end
			end
			lightning:Strike(1)
			engine:Step(0.05)
			local flash = engine.InstanceManager:Find("weather.lightning.flash")
			expect(flash.Brightness).toBeGreaterThan(0.1)
			for _ = 1, 20 do
				engine:Step(0.05)
			end
			expect(flash.Brightness).toBe(0)
		end)

		t.it("supports custom weather composed from particles", function()
			local engine = t.newEngine()
			local result = engine:CreateWeather("Custom", {
				Wind = 5,
				Particles = { Ash = { Template = "Embers", Attach = "Camera", Rate = 50 } },
			})
			expect(result.Success).toBe(true)
			expect(engine.InstanceManager:Find("weather.ash.primary")).never.toBeNil()
		end)

		t.it("supports registered weather types", function()
			local engine = t.newEngine()
			engine:RegisterWeather({
				Name = "Pollen",
				Description = "Floating pollen",
				Defaults = { Intensity = 1, Wind = 2 },
				Targets = { Atmosphere = { Haze = 1.2 } },
				Particles = { Pollen = { Template = "Dust", Rate = 40, Color = ColorSequence.new(Color3.fromRGB(250, 230, 120)) } },
				Audio = { "Birds" },
			})
			local result = engine:CreateWeather("Pollen")
			expect(result.Success).toBe(true)
			expect(engine.InstanceManager:Find("weather.pollen.primary")).never.toBeNil()
		end)
	end)
end
