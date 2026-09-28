return function(t)
	local expect = t.expect

	local function fireflies(log)
		return {
			Name = "Fireflies",
			Category = "Particles",
			Description = "Glowing fireflies around a point.",
			Schema = {
				Rate = { Kind = "number", Min = 0, Default = 10 },
				Position = { Kind = "Vector3", Required = true },
				Color = { Kind = "Color3" },
			},
			Create = function(config)
				table.insert(log, "create")
				local part = Instance.new("Part")
				part.Anchored = true
				part.Transparency = 1
				part.Position = config.Position
				local emitter = Instance.new("ParticleEmitter")
				emitter.Rate = config.Rate or 10
				emitter.Parent = part
				return part
			end,
			Update = function(instance, config)
				table.insert(log, "update")
				instance.Position = config.Position
				instance:FindFirstChildOfClass("ParticleEmitter").Rate = config.Rate or 10
			end,
			Remove = function(instance)
				table.insert(log, "remove")
				instance:Destroy()
			end,
		}
	end

	t.describe("Effect registry", function()
		t.it("registers custom effects without modifying the core", function()
			local engine = t.newEngine()
			local log = {}
			expect(engine:RegisterEffect(fireflies(log)).Success).toBe(true)
			local created = engine:CreateEffect("Grove", { Effect = "Fireflies", Position = Vector3.new(10, 2, 0), Rate = 12 })
			expect(created.Success).toBe(true)
			expect(created.Created).toContain("Fireflies")
			local part = engine.InstanceManager:Find("effect.Grove")
			expect(part.Position).toBe(Vector3.new(10, 2, 0))
			expect(part:GetAttribute("VisualFX_Type")).toBe("Fireflies")

			-- Re-applying the same configuration does not call Create or Update again.
			engine:CreateEffect("Grove", { Effect = "Fireflies", Position = Vector3.new(10, 2, 0), Rate = 12 })
			expect(t.deepEqual(log, { "create" })).toBe(true)

			engine:CreateEffect("Grove", { Effect = "Fireflies", Position = Vector3.new(0, 2, 0), Rate = 20 })
			expect(log[2]).toBe("update")
			expect(part:FindFirstChildOfClass("ParticleEmitter").Rate).toBe(20)

			engine:RemoveEffect("Grove")
			expect(log[3]).toBe("remove")
			expect(engine.InstanceManager:Find("effect.Grove")).toBeNil()
		end)

		t.it("validates custom effect configurations with their schema", function()
			local engine = t.newEngine()
			engine:RegisterEffect(fireflies({}))
			local missing = engine:CreateEffect("A", { Effect = "Fireflies" })
			expect(missing.Success).toBe(false)
			local wrong = engine:CreateEffect("B", { Effect = "Fireflies", Position = Vector3.new(0, 0, 0), Rate = "many" })
			expect(wrong.Success).toBe(false)
			expect(wrong.Errors[1]).toContain("Effects.B.Rate")
			local unknown = engine:CreateEffect("C", { Effect = "Firefles", Position = Vector3.new(0, 0, 0) })
			expect(unknown.Success).toBe(false)
			expect(unknown.Errors[1]).toContain("Fireflies")
		end)

		t.it("rejects invalid effect definitions", function()
			local engine = t.newEngine()
			expect(engine:RegisterEffect({ Name = "NoCreate" }).Success).toBe(false)
			expect(engine:RegisterEffect({ Create = function() end }).Success).toBe(false)
			expect(engine:RegisterEffect({ Name = "BadSchema", Create = function() end, Schema = { X = { Kind = "Banana" } } }).Success).toBe(false)
		end)

		t.it("reports effects whose Create does not return an instance", function()
			local engine = t.newEngine()
			engine:RegisterEffect({ Name = "Broken", Create = function()
				return 42
			end })
			local result = engine:CreateEffect("X", { Effect = "Broken" })
			local reported = false
			for _, warning in ipairs(result.Warnings) do
				if string.find(warning, "did not return an Instance", 1, true) then
					reported = true
				end
			end
			expect(reported).toBe(true)
		end)

		t.it("includes custom effects in the schema", function()
			local engine = t.newEngine()
			engine:RegisterEffect(fireflies({}))
			local schema = engine:GetSchema()
			expect(schema.CustomEffects.Fireflies.Category).toBe("Particles")
		end)

		t.it("registers custom particle templates", function()
			local engine = t.newEngine()
			engine:RegisterParticleTemplate("Bubbles", {
				Description = "Rising bubbles",
				Defaults = { Attach = "World", Rate = 15, Speed = NumberRange.new(2, 4), Acceleration = Vector3.new(0, 3, 0) },
			})
			local result = engine:CreateParticleSystem("Tank", { Template = "Bubbles", Position = Vector3.new(0, 1, 0) })
			expect(result.Success).toBe(true)
			local emitter = engine.InstanceManager:Find("particles.Tank")
			expect(emitter.Acceleration).toBe(Vector3.new(0, 3, 0))
		end)
	end)
end
