return function(t)
	local expect = t.expect

	t.describe("Scene diff", function()
		t.it("reports additions without changing the scene", function()
			local engine = t.newEngine()
			local before = t.Services.Lighting.Brightness
			local diff = engine:DiffScene({ Lighting = { GeographicLatitude = 10 }, Weather = { Type = "HeavyRain" } })
			expect(diff.Success).toBe(true)
			expect(t.Services.Lighting.Brightness).toBe(before)
			expect(#engine.InstanceManager:GetManaged(true)).toBe(0)
			local addedTypes = {}
			for _, entry in ipairs(diff.Added) do
				addedTypes[entry.Type] = true
			end
			expect(addedTypes.Rain).toBe(true)
			local brightness = nil
			for _, change in ipairs(diff.Modified) do
				if change.Property == "GeographicLatitude" and change.Type == "Lighting" then
					brightness = change
				end
			end
			expect(brightness.To).toBe(10)
			expect(#diff.Summary).toBeGreaterThan(0)
		end)

		t.it("reports modifications, removals and unchanged effects", function()
			local engine = t.newEngine()
			engine:CreateScene({ Sky = { StarCount = 100 }, Weather = { Type = "HeavyRain" } })
			local diff = engine:DiffScene({ Sky = { StarCount = 100 }, Weather = { Type = "Snow" } })
			local removed = {}
			for _, entry in ipairs(diff.Removed) do
				removed[entry.Type] = true
			end
			expect(removed.Rain).toBe(true)
			local added = {}
			for _, entry in ipairs(diff.Added) do
				added[entry.Type] = true
			end
			expect(added.Snow).toBe(true)
			expect(diff.Unchanged).toContain("sky.primary")
		end)

		t.it("diffs merges against the current scene", function()
			local engine = t.newEngine()
			engine:ApplyPreset("Night")
			local diff = engine:DiffScene({ Lighting = { ClockTime = 1 } }, { Merge = true })
			expect(#diff.Removed).toBe(0)
			expect(#diff.Modified).toBe(1)
			expect(diff.Modified[1].Property).toBe("ClockTime")
		end)

		t.it("an identical configuration produces an empty diff", function()
			local engine = t.newEngine()
			engine:ApplyPreset("CinematicSunset")
			local diff = engine:DiffScene(engine:ExportConfiguration())
			expect(#diff.Added).toBe(0)
			expect(#diff.Modified).toBe(0)
			expect(#diff.Removed).toBe(0)
		end)

		t.it("dry runs report the plan and change nothing", function()
			local engine = t.newEngine()
			local result = engine:UpdateScene({ Atmosphere = { Density = 0.6 } }, { DryRun = true })
			expect(result.DryRun).toBe(true)
			expect(result.Created).toContain("Atmosphere")
			expect(engine.InstanceManager:Find("atmosphere.primary")).toBeNil()
		end)

		t.it("interprets descriptions when diffing", function()
			local engine = t.newEngine()
			local diff = engine:DiffScene({ Mood = "eerie", Time = "night" })
			expect(diff.Success).toBe(true)
			expect(#diff.Added).toBeGreaterThan(0)
		end)
	end)
end
