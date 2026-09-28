return function(t)
	local expect = t.expect

	t.describe("Validation", function()
		t.it("accepts a valid configuration and normalizes it", function()
			local engine = t.newEngine()
			local report = engine:Validate({
				Version = 1,
				Lighting = { ClockTime = 18.5, Brightness = 2, ExposureCompensation = 0.2 },
				Atmosphere = { Density = 0.35, Haze = 2, Color = "#BECDDC" },
			})
			expect(report.Success).toBe(true)
			expect(#report.Errors).toBe(0)
			expect(typeof(report.Normalized.Atmosphere.Color)).toBe("Color3")
		end)

		t.it("reports type errors in the documented format", function()
			local engine = t.newEngine()
			local report = engine:Validate({ Lighting = { ExposureCompensation = "bright" } })
			expect(report.Success).toBe(false)
			local entry = report.Errors[1]
			expect(entry.Path).toBe("Lighting.ExposureCompensation")
			expect(entry.Expected).toBe("number")
			expect(entry.Received).toBe("string")
			expect(entry.Message).toBe("Invalid property:\nLighting.ExposureCompensation\n\nExpected:\nnumber\n\nReceived:\nstring")
		end)

		t.it("rejects out-of-range values", function()
			local engine = t.newEngine()
			local report = engine:Validate({ Atmosphere = { Density = 2 } })
			expect(report.Success).toBe(false)
			expect(report.Errors[1].Code).toBe("OutOfRange")
		end)

		t.it("warns about soft limits without failing", function()
			local engine = t.newEngine()
			local report = engine:Validate({ Particles = { Rain = { Rate = 5000 } } })
			expect(report.Success).toBe(true)
			local codes = {}
			for _, warning in ipairs(report.Warnings) do
				codes[warning.Code] = true
			end
			expect(codes.AboveRecommended).toBe(true)
		end)

		t.it("warns about unknown properties with suggestions", function()
			local engine = t.newEngine()
			local report = engine:Validate({ Atmosphere = { Densty = 0.3 } })
			expect(report.Success).toBe(true)
			expect(report.Warnings[1].Code).toBe("UnknownProperty")
			expect(report.Warnings[1].Suggestion).toBe("Density")
		end)

		t.it("warns about unknown sections", function()
			local engine = t.newEngine()
			local report = engine:Validate({ Lightning = { ClockTime = 3 } })
			expect(report.Warnings[1].Code).toBe("UnknownSection")
			expect(report.Warnings[1].Suggestion).toBe("Lighting")
		end)

		t.it("resolves aliases to canonical keys", function()
			local engine = t.newEngine()
			local report = engine:Validate({ Water = { WaveStrength = 0.35, WaterColor = Color3.fromRGB(35, 90, 120) } })
			expect(report.Success).toBe(true)
			expect(report.Normalized.Water.WaveSize).toBe(0.35)
			expect(report.Normalized.Water.WaveStrength).toBeNil()
			expect(typeof(report.Normalized.Water.Color)).toBe("Color3")
		end)

		t.it("coerces friendly values into Roblox datatypes", function()
			local engine = t.newEngine()
			local report = engine:Validate({
				Particles = {
					Rain = {
						Lifetime = { 1, 2 },
						Size = 0.1,
						Color = Color3.fromRGB(180, 200, 255),
						Acceleration = { 0, -40, 0 },
						Shape = "box",
						Transparency = { 0.2, 0.8 },
					},
				},
			})
			expect(report.Success).toBe(true)
			local rain = report.Normalized.Particles.Rain
			expect(typeof(rain.Lifetime)).toBe("NumberRange")
			expect(typeof(rain.Size)).toBe("NumberSequence")
			expect(typeof(rain.Color)).toBe("ColorSequence")
			expect(typeof(rain.Acceleration)).toBe("Vector3")
			expect(rain.Shape).toBe(Enum.ParticleEmitterShape.Box)
			expect(typeof(rain.Transparency)).toBe("NumberSequence")
		end)

		t.it("rejects invalid enum names with suggestions", function()
			local engine = t.newEngine()
			local report = engine:Validate({ Particles = { Rain = { Shape = "Sphre" } } })
			expect(report.Success).toBe(false)
			expect(report.Errors[1].Code).toBe("InvalidEnum")
			expect(report.Errors[1].Message).toContain("Sphere")
		end)

		t.it("requires Weather.Type and knows every weather type", function()
			local engine = t.newEngine()
			local missing = engine:Validate({ Weather = { Intensity = 0.5 } })
			expect(missing.Success).toBe(false)
			expect(missing.Errors[1].Code).toBe("Required")
			local unknown = engine:Validate({ Weather = { Type = "HevyRain" } })
			expect(unknown.Success).toBe(false)
			expect(unknown.Errors[1].Message).toContain("HeavyRain")
			local normalized = engine:Validate({ Weather = "light_rain" })
			expect(normalized.Success).toBe(true)
			expect(normalized.Normalized.Weather.Type).toBe("LightRain")
		end)

		t.it("rejects malformed configurations", function()
			local engine = t.newEngine()
			expect(engine:Validate("nope").Success).toBe(false)
			expect(engine:Validate({ Lighting = "bright" }).Success).toBe(false)
			expect(engine:Validate({ Version = 1, Particles = { { Rate = 1 } } }).Success).toBe(false)
			expect(engine:Validate({ Particles = { ["bad/name"] = {} } }).Success).toBe(false)
			expect(engine:Validate({ Lighting = { Brightness = 0 / 0 } }).Success).toBe(false)
			expect(engine:Validate({ Version = 99 }).Success).toBe(false)
		end)

		t.it("migrates version 0 configurations", function()
			local engine = t.newEngine()
			local report = engine:Validate({
				Lighting = { ClockTime = 12, PostProcessing = { Bloom = { Intensity = 1 } } },
				Particles = { { Name = "Rain", Template = "Rain" } },
				Weather = "Snow",
				Water = { WaterTransparency = 0.5 },
			})
			expect(report.Success).toBe(true)
			expect(report.Normalized.Version).toBe(1)
			expect(report.Normalized.PostProcessing.Bloom.Intensity).toBe(1)
			expect(report.Normalized.Particles.Rain.Template).toBe("Rain")
			expect(report.Normalized.Weather.Type).toBe("Snow")
			expect(report.Normalized.Water.Transparency).toBe(0.5)
			expect(#report.Notes).toBeGreaterThan(0)
		end)

		t.it("validates preset inheritance", function()
			local engine = t.newEngine()
			local missing = engine:Validate({ Inherits = { "BaseForest", "NoSuchPreset" } })
			expect(missing.Success).toBe(false)
			expect(missing.Errors[1].Code).toBe("UnknownPreset")
			local ok = engine:Validate({ Inherits = { "BaseForest", "Autumn" }, Weather = { Type = "LightRain" } })
			expect(ok.Success).toBe(true)
		end)

		t.it("reports unknown particle templates and zone effects", function()
			local engine = t.newEngine()
			expect(engine:Validate({ Particles = { A = { Template = "Rian" } } }).Success).toBe(false)
			local zone = engine:Validate({
				Environment = { Zones = { Z = { Effect = "Fgo", Position = Vector3.new(0, 0, 0), Size = Vector3.new(10, 10, 10) } } },
			})
			expect(zone.Success).toBe(false)
			expect(zone.Errors[1].Message).toContain("Fog")
		end)

		t.it("adds performance warnings for heavy configurations", function()
			local engine = t.newEngine()
			local particles = {}
			for index = 1, 20 do
				particles["System" .. index] = { Template = "Dust", Rate = 500 }
			end
			local report = engine:Validate({ Particles = particles })
			expect(report.Success).toBe(true)
			local found = false
			for _, warning in ipairs(report.Warnings) do
				if warning.Code == "PerformanceBudget" then
					found = true
				end
			end
			expect(found).toBe(true)
		end)
	end)
end
