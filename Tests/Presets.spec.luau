return function(t)
	local expect = t.expect

	local REQUIRED = {
		"CinematicSunset", "DarkStorm", "MistyForest", "MoonlitNight", "TropicalRain", "Realistic", "Stylized",
		"Horror", "Fantasy", "SciFi", "Tropical", "Desert", "Arctic", "Forest", "Ocean", "Storm", "Sunset",
		"Sunrise", "Night", "Dawn", "Overcast",
	}

	t.describe("Presets", function()
		t.it("ships every required built-in preset", function()
			local engine = t.newEngine()
			local names = {}
			for _, preset in ipairs(engine:ListPresets()) do
				names[preset.Name] = preset
			end
			for _, name in ipairs(REQUIRED) do
				expect(names[name] ~= nil).toBe(true)
				expect(names[name].Source).toBe("BuiltIn")
			end
		end)

		t.it("every built-in preset validates and applies cleanly", function()
			local engine = t.newEngine()
			for _, preset in ipairs(engine:ListPresets({ Source = "BuiltIn" })) do
				local result = engine:ApplyPreset(preset.Name)
				if not result.Success then
					error(preset.Name .. ": " .. table.concat(result.Errors, "; "))
				end
			end
		end)

		t.it("resolves inheritance with deterministic left-to-right merges", function()
			local engine = t.newEngine()
			local composed = engine:GetPreset("AutumnRainForest")
			-- From BaseForest:
			expect(composed.Lighting.ClockTime).toBe(9)
			-- Autumn overrides BaseForest's atmosphere color:
			expect(composed.Atmosphere.Color).toBe(Color3.fromRGB(220, 190, 160))
			-- LightRain supplies the weather, the preset's own Intensity wins:
			expect(composed.Weather.Type).toBe("LightRain")
			expect(composed.Weather.Intensity).toBe(0.55)
			-- Particles from Autumn survive:
			expect(composed.Particles.Leaves.Template).toBe("Leaves")
			-- Metadata is never inherited:
			expect(composed.Metadata.Name).toBe("Autumn Rain Forest")
			expect(composed.Inherits).toBeNil()
			-- Same answer every time.
			expect(t.deepEqual(engine:GetPreset("AutumnRainForest"), composed)).toBe(true)
		end)

		t.it("composes presets on demand", function()
			local engine = t.newEngine()
			local config = engine:ComposePresets({ "BaseForest", "Autumn", "LightRain" }, { Weather = { Intensity = 0.3 } })
			expect(config.Weather.Type).toBe("LightRain")
			expect(config.Weather.Intensity).toBe(0.3)
			expect(config.Particles.Leaves ~= nil).toBe(true)
		end)

		t.it("saves, lists, applies and deletes user presets", function()
			local engine = t.newEngine()
			local saved = engine:SavePreset("MyEnvironment", { Lighting = { ClockTime = 20 }, Weather = { Type = "Snow" } })
			expect(saved.Success).toBe(true)
			local listed = engine:ListPresets({ Search = "myenv" })
			expect(#listed).toBe(1)
			expect(listed[1].Source).toBe("Saved")
			expect(engine:ApplyPreset("MyEnvironment").Success).toBe(true)
			expect(t.Services.Lighting.ClockTime).toBe(20)
			expect(engine:SavePreset("MyEnvironment", { Lighting = {} }).Success).toBe(false)
			expect(engine:SavePreset("MyEnvironment", { Lighting = { ClockTime = 3 } }, { Overwrite = true }).Success).toBe(true)
			expect(engine:DeletePreset("MyEnvironment").Success).toBe(true)
			expect(engine:ApplyPreset("MyEnvironment").Success).toBe(false)
		end)

		t.it("saves composed presets that keep their inheritance", function()
			local engine = t.newEngine()
			expect(engine:SavePreset("RainyDusk", { Inherits = { "Sunset", "LightRain" }, Lighting = { ClockTime = 18.4 } }).Success).toBe(true)
			local resolved = engine:GetPreset("RainyDusk")
			expect(resolved.Weather.Type).toBe("LightRain")
			expect(resolved.Lighting.ClockTime).toBe(18.4)
			expect(resolved.Atmosphere.Color).toBe(Color3.fromRGB(245, 170, 130))
		end)

		t.it("detects inheritance cycles", function()
			local engine = t.newEngine()
			engine.Presets:Save("CycleA", { Inherits = { "CycleB" } })
			engine.Presets:Save("CycleB", { Inherits = { "CycleA" } })
			local _, problem = engine:GetPreset("CycleA")
			expect(problem).toContain("cycle")
			local result = engine:ApplyPreset("CycleA")
			expect(result.Success).toBe(false)
		end)

		t.it("protects built-in presets", function()
			local engine = t.newEngine()
			expect(engine:DeletePreset("Night").Success).toBe(false)
			expect(engine:SavePreset("Night", { Lighting = { ClockTime = 1 } }, { Overwrite = true }).Success).toBe(false)
		end)

		t.it("suggests names for unknown presets", function()
			local engine = t.newEngine()
			local result = engine:ApplyPreset("CinematicSunst")
			expect(result.Success).toBe(false)
			expect(result.Errors[1]).toContain("CinematicSunset")
		end)

		t.it("accepts case and format insensitive names", function()
			local engine = t.newEngine()
			expect(engine:ApplyPreset("misty_forest").Success).toBe(true)
		end)

		t.it("persists user presets through a storage adapter", function()
			local engine = t.newEngine()
			local store = {}
			engine.Presets:SetStorage({
				Load = function()
					return store
				end,
				Save = function(data)
					store = data
				end,
			})
			engine:SavePreset("Persisted", { Lighting = { Brightness = 1.5 } })
			expect(typeof(store.Persisted)).toBe("string")
			local other = t.newEngine()
			other.Presets:SetStorage({ Load = function()
				return store
			end })
			expect(other.Presets:Exists("Persisted")).toBe(true)
		end)
	end)
end
