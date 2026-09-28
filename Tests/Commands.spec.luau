return function(t)
	local expect = t.expect

	local function run(engine, seconds)
		local elapsed = 0
		while elapsed < seconds do
			engine:Step(0.1)
			elapsed += 0.1
		end
	end

	t.describe("AI command API", function()
		t.it("runs the complete agent workflow without the UI", function()
			local engine = t.newEngine()

			-- Inspect
			local inspected = engine:Execute({ Action = "InspectScene" })
			expect(inspected.Success).toBe(true)
			expect(#inspected.Data.ManagedEffects).toBe(0)

			-- Create from a description
			local created = engine:Execute({
				Action = "CreateScene",
				Configuration = {
					Mood = "mysterious",
					Time = "sunset",
					Weather = "light_rain",
					Environment = "dense_forest",
					Fog = "medium",
					LightingStyle = "cinematic",
				},
			})
			expect(created.Success).toBe(true)
			expect(created.Created).toContain("Rain")
			expect(created.Created).toContain("Atmosphere")
			expect(#created.Interpretation).toBeGreaterThan(4)

			-- Validate and detect conflicts
			local validation = engine:Execute({ Action = "ValidateConfiguration" })
			expect(validation.Success).toBe(true)
			local conflicts = engine:Execute({ Action = "DetectConflicts" })
			expect(conflicts.Success).toBe(true)

			-- Preview the diff of the next change
			local diff = engine:Execute({ Action = "DiffScene", Merge = true, Configuration = { Weather = { Type = "HeavyRain", Intensity = 0.9 } } })
			expect(diff.Success).toBe(true)
			expect(#diff.Modified).toBeGreaterThan(0)

			-- Transition
			local updated = engine:Execute({
				Action = "TransitionScene",
				Configuration = { Weather = { Type = "HeavyRain", Intensity = 0.9 }, Lighting = { ClockTime = 19.2 } },
				Duration = 5,
			})
			expect(updated.Success).toBe(true)
			expect(updated.TransitionId ~= nil).toBe(true)
			run(engine, 5.2)
			expect(t.Services.Lighting.ClockTime).toBeCloseTo(19.2, 1 / 600)

			-- Inspect the result
			local after = engine:Execute({ Action = "InspectScene" })
			expect(after.Data.Weather.Type).toBe("HeavyRain")

			-- Optimize
			local quality = engine:Execute({ Action = "SetQuality", Level = "Medium" })
			expect(quality.Success).toBe(true)
			local stats = engine:Execute({ Action = "GetPerformanceStats" })
			expect(stats.Data.Quality).toBe("Medium")

			-- Export and generate code
			local exported = engine:Execute({ Action = "ExportConfiguration", Format = "json" })
			expect(exported.Data).toContain('"HeavyRain"')
			local code = engine:Execute({ Action = "GenerateCode" })
			expect(code.Success).toBe(true)
			expect(code.Code).toContain("VisualFX:CreateScene(Configuration)")

			-- The exported configuration reproduces the scene in a fresh engine.
			local other = t.newEngine()
			local imported = other:Execute({ Action = "ImportConfiguration", Data = exported.Data })
			expect(imported.Success).toBe(true)
			expect(#other:DiffScene(engine:ExportConfiguration()).Modified).toBe(0)
		end)

		t.it("creates weather with the documented command shape", function()
			local engine = t.newEngine()
			local result = engine:Execute({
				Action = "CreateWeather",
				Type = "Thunderstorm",
				Configuration = { RainIntensity = 0.9, Fog = 0.4, Wind = 35, Lightning = true },
			})
			expect(result.Success).toBe(true)
			expect(result.Action).toBe("CreateWeather")
			expect(result.Created).toContain("Rain")
			expect(#result.Changed).toBeGreaterThan(0)
		end)

		t.it("returns structured errors for malformed commands", function()
			local engine = t.newEngine()
			local notTable = engine:Execute("InspectScene")
			expect(notTable.Success).toBe(false)
			expect(#notTable.Errors).toBe(1)

			local unknown = engine:Execute({ Action = "ApplyPrest", Name = "Night" })
			expect(unknown.Success).toBe(false)
			expect(unknown.Errors[1]).toContain("ApplyPreset")

			local missing = engine:Execute({ Action = "ApplyPreset" })
			expect(missing.Success).toBe(false)
			expect(missing.Errors[1]).toContain("Name")

			local wrongType = engine:Execute({ Action = "SetLighting", Configuration = "bright" })
			expect(wrongType.Success).toBe(false)
			expect(wrongType.Errors[1]).toContain("Expected:\ntable")

			local badValue = engine:Execute({ Action = "SetLighting", Configuration = { Brightness = "very" } })
			expect(badValue.Success).toBe(false)
			expect(badValue.ValidationErrors[1].Path).toBe("Lighting.Brightness")

			local noAction = engine:Execute({ Configuration = {} })
			expect(noAction.Success).toBe(false)

			local extra = engine:Execute({ Action = "InspectScene", Verbose = true })
			expect(extra.Success).toBe(true)
			expect(extra.Warnings[#extra.Warnings]).toContain("unknown field 'Verbose'")

			-- Nothing was changed by any of the failures.
			expect(#engine.InstanceManager:GetManaged(true)).toBe(0)
		end)

		t.it("never executes code smuggled into configurations", function()
			local engine = t.newEngine()
			local called = false
			local result = engine:Execute({
				Action = "SetLighting",
				Configuration = { Brightness = function()
					called = true
					return 2
				end },
			})
			expect(result.Success).toBe(false)
			expect(called).toBe(false)
			local stringCode = engine:Execute({ Action = "SetLighting", Configuration = { Brightness = "return 5" } })
			expect(stringCode.Success).toBe(false)
		end)

		t.it("supports dry runs for mutating actions", function()
			local engine = t.newEngine()
			local result = engine:Execute({ Action = "SetAtmosphere", Configuration = { Density = 0.5 }, DryRun = true })
			expect(result.Success).toBe(true)
			expect(engine.InstanceManager:Find("atmosphere.primary")).toBeNil()
			local preset = engine:Execute({ Action = "ApplyPreset", Name = "Storm", DryRun = true })
			expect(preset.Success).toBe(true)
			expect(preset.Created).toContain("Rain")
			expect(#engine.InstanceManager:GetManaged(true)).toBe(0)
		end)

		t.it("runs atomic batches and reverts them on failure", function()
			local engine = t.newEngine()
			local ok = engine:Execute({
				Action = "Batch",
				Commands = {
					{ Action = "SetLighting", Configuration = { ClockTime = 6 } },
					{ Action = "CreateParticleSystem", Name = "Motes", Template = "Dust" },
				},
			})
			expect(ok.Success).toBe(true)
			expect(#ok.Results).toBe(2)
			expect(t.Services.Lighting.ClockTime).toBe(6)

			local failed = engine:Execute({
				Action = "Batch",
				Commands = {
					{ Action = "SetLighting", Configuration = { ClockTime = 20 } },
					{ Action = "CreateWeather", Type = "Snow" },
					{ Action = "SetAtmosphere", Configuration = { Density = 5 } },
				},
			})
			expect(failed.Success).toBe(false)
			expect(failed.Reverted).toBe(true)
			expect(t.Services.Lighting.ClockTime).toBe(6)
			expect(engine.InstanceManager:Find("weather.snow.primary")).toBeNil()
			expect(engine.InstanceManager:Find("particles.Motes")).never.toBeNil()
		end)

		t.it("manages presets through commands", function()
			local engine = t.newEngine()
			expect(engine:Execute({ Action = "SavePreset", Name = "AgentPreset", Configuration = { Lighting = { ClockTime = 4 } } }).Success).toBe(true)
			expect(engine:Execute({ Action = "ApplyPreset", Preset = "AgentPreset" }).Success).toBe(true)
			local listed = engine:Execute({ Action = "ListPresets", Filter = { Source = "Saved" } })
			expect(#listed.Data).toBe(1)
			expect(engine:Execute({ Action = "DeletePreset", Name = "AgentPreset" }).Success).toBe(true)
			local got = engine:Execute({ Action = "GetPreset", Name = "Night" })
			expect(got.Data.Lighting.ClockTime).toBe(0)
		end)

		t.it("exposes schema, documentation and the action catalogue", function()
			local engine = t.newEngine()
			local catalog = engine:Execute({ Action = "ListActions" }).Data
			for _, name in ipairs({
				"InspectScene", "SetAtmosphere", "SetLighting", "SetWater", "CreateParticleSystem", "RemoveParticleSystem",
				"CreateWeather", "RemoveWeather", "ApplyPreset", "SavePreset", "DeletePreset", "CreateScene", "UpdateScene",
				"TransitionScene", "ExportConfiguration", "ImportConfiguration", "GenerateCode", "ValidateConfiguration",
				"DetectConflicts", "ResetManagedEffects",
			}) do
				expect(catalog[name] ~= nil).toBe(true)
			end
			local schema = engine:Execute({ Action = "GetSchema" }).Data
			expect(#schema.Sections).toBeGreaterThan(8)
			local jsonSchema = engine:Execute({ Action = "GetSchema", Format = "jsonschema" }).Data
			expect(jsonSchema.properties.Lighting.properties.ClockTime.maximum).toBe(24)
			local docs = engine:Execute({ Action = "GetDocumentation" }).Data
			expect(docs.Markdown).toContain("## Workflow")
		end)

		t.it("resets managed effects through commands", function()
			local engine = t.newEngine()
			engine:Execute({ Action = "ApplyPreset", Name = "DarkStorm" })
			local reset = engine:Execute({ Action = "ResetManagedEffects" })
			expect(reset.Success).toBe(true)
			expect(#engine.InstanceManager:GetManaged(true)).toBe(0)
		end)

		t.it("previews and reverts through commands", function()
			local engine = t.newEngine()
			engine:Execute({ Action = "PreviewScene", Configuration = { Lighting = { ClockTime = 2 } } })
			expect(t.Services.Lighting.ClockTime).toBe(2)
			engine:Execute({ Action = "RevertPreview" })
			expect(t.Services.Lighting.ClockTime).toBe(14)
		end)
	end)
end
