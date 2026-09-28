return function(t)
	local expect = t.expect

	-- loadstring is disabled in live Roblox servers unless LoadStringEnabled is set.
	local canLoad = pcall(function()
		return loadstring("return 1")()
	end)

	-- Evaluates generated Module code in a sandbox with only Roblox constructors.
	local function evaluate(source)
		local chunk = loadstring(source)
		expect(chunk ~= nil).toBe(true)
		local env = {
			Color3 = Color3, Vector3 = Vector3, Vector2 = Vector2, NumberRange = NumberRange,
			NumberSequence = NumberSequence, NumberSequenceKeypoint = NumberSequenceKeypoint,
			ColorSequence = ColorSequence, ColorSequenceKeypoint = ColorSequenceKeypoint, Enum = Enum,
		}
		setfenv(chunk, env)
		return chunk()
	end

	t.describe("Code generation", function()
		t.it("generates deterministic, formatted code", function()
			local engine = t.newEngine()
			engine:ApplyPreset("CinematicSunset")
			local a = engine:GenerateCode()
			local b = engine:GenerateCode()
			expect(a).toBe(b)
			expect(a).toContain('local VisualFX = require(game:GetService("ReplicatedStorage").VisualFX)')
			expect(a).toContain("local Configuration = {")
			expect(a).toContain("Color3.fromRGB(")
			expect(a).toContain("-- Lighting service properties")
			expect(a).toContain("VisualFX:CreateScene(Configuration)")
			expect(string.find(a, "\t\t\tIntensity = 0.8,", 1, true) ~= nil).toBe(true)
		end)

		t.it("generated module code evaluates back to the same configuration", function()
			if not canLoad then
				return
			end
			local engine = t.newEngine()
			for _, name in ipairs({ "Horror", "Fantasy", "Ocean", "AutumnRainForest", "SciFi" }) do
				engine:ApplyPreset(name)
				local config = engine:ExportConfiguration()
				local source = engine:GenerateCode(config, { Template = "Module", OmitTemplateDefaults = false })
				local evaluated = evaluate(source)
				local Values = require(game:GetService("ReplicatedStorage").VisualFX.Core.Values)
				expect(Values.equal(evaluated, config)).toBe(true)
				-- And applying it reproduces the scene exactly.
				local diff = engine:DiffScene(evaluated)
				expect(#diff.Modified + #diff.Added + #diff.Removed).toBe(0)
			end
		end)

		t.it("omits particle values equal to template defaults", function()
			local engine = t.newEngine()
			engine:CreateParticleSystem("Rain", { Template = "Rain", Rate = 400 })
			local source = engine:GenerateCode(nil, { Template = "Module" })
			expect(source).toContain("Rate = 400")
			expect(string.find(source, "Squash", 1, true)).toBeNil()
			if not canLoad then
				return
			end
			local config = evaluate(source)
			local diff = engine:DiffScene(config)
			expect(#diff.Modified).toBe(0)
		end)

		t.it("formats Roblox datatypes idiomatically", function()
			local Generator = require(game:GetService("ReplicatedStorage").VisualFX.Codegen.LuauGenerator)
			expect(Generator.FormatValue(Color3.fromRGB(1, 2, 3))).toBe("Color3.fromRGB(1, 2, 3)")
			expect(Generator.FormatValue(NumberRange.new(2))).toBe("NumberRange.new(2)")
			expect(Generator.FormatValue(NumberRange.new(1, 2))).toBe("NumberRange.new(1, 2)")
			expect(Generator.FormatValue(NumberSequence.new(0.5))).toBe("NumberSequence.new(0.5)")
			expect(Generator.FormatValue(NumberSequence.new(0, 1))).toBe("NumberSequence.new(0, 1)")
			expect(Generator.FormatValue(ColorSequence.new(Color3.fromRGB(255, 0, 0)))).toBe("ColorSequence.new(Color3.fromRGB(255, 0, 0))")
			expect(Generator.FormatValue(Vector3.new(0, -40, 1.5))).toBe("Vector3.new(0, -40, 1.5)")
			expect(Generator.FormatValue(Enum.NormalId.Top)).toBe("Enum.NormalId.Top")
			expect(Generator.FormatValue({ ["weird key"] = true, ["end"] = 1 })).toContain('["weird key"] = true')
			expect(Generator.FormatValue({ ["end"] = 1 })).toContain('["end"] = 1')
		end)

		t.it("supports every template", function()
			local engine = t.newEngine()
			engine:ApplyPreset("Night")
			for _, template in ipairs({ "Script", "LocalScript", "Module", "Transition" }) do
				local source = engine:GenerateCode(nil, { Template = template, RequirePath = "game.ReplicatedStorage.VisualFX" })
				if canLoad then
					expect(loadstring(source) ~= nil).toBe(true)
				end
			end
			expect(engine:GenerateCode(nil, { Template = "Transition", Duration = 8 })).toContain("Duration = 8")
			expect(function()
				engine:GenerateCode(nil, { Template = "Nope" })
			end).toThrow("unknown code template")
		end)

		t.it("never emits internal keys", function()
			local engine = t.newEngine()
			engine:CreateWeather("Thunderstorm")
			local source = engine:GenerateCode(engine:ExportConfiguration({ Resolved = true }))
			expect(string.find(source, "_Weather", 1, true)).toBeNil()
		end)
	end)
end
